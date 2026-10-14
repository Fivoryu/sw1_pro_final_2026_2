"""HTTP-only consumer for asynchronous furniture detection jobs (F08.4).

The API is the sole writer of job state. This process receives queue messages,
asks the API to claim a job, downloads only the signed image URL, runs the
existing ``detect.py`` inference module, and reports completion or failure.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import urlparse

LOGGER = logging.getLogger("roomforge.detection.worker")
LOCAL_AWS_ACCESS_KEY_ID = "local-test-key"
LOCAL_AWS_SECRET_ACCESS_KEY = "local-test-secret"
LOCAL_QUEUE_HOSTS = frozenset({"floci", "localhost", "127.0.0.1", "::1"})
_SUPPORTED_IMAGE_SUFFIXES = frozenset({".jpg", ".jpeg", ".png"})


@dataclass(frozen=True)
class QueueDelivery:
    """One queue message and the receipt handle needed to acknowledge it."""

    body: str
    receipt_handle: str


class MessageQueue(Protocol):
    def receive(self) -> list[QueueDelivery]: ...

    def delete(self, delivery: QueueDelivery) -> None: ...


class HttpResponse(Protocol):
    status_code: int
    content: bytes

    def json(self) -> Any: ...


class HttpClient(Protocol):
    def post(
        self,
        url: str,
        *,
        headers: dict[str, str],
        json: dict[str, Any] | None = None,
    ) -> HttpResponse: ...

    def get(self, url: str) -> HttpResponse: ...


DetectionFunction = Callable[[Path], list[dict[str, Any]]]


def validate_local_endpoint(endpoint_url: str) -> str:
    """Reject AWS/public endpoints: this pilot's consumer is local-only."""
    try:
        parsed = urlparse(endpoint_url)
        host = parsed.hostname
    except ValueError:
        host = None
        parsed = urlparse("")
    if (
        parsed.scheme not in {"http", "https"}
        or host not in LOCAL_QUEUE_HOSTS
        or parsed.username is not None
        or parsed.password is not None
    ):
        raise ValueError("SQS_ENDPOINT_URL must point to a local Floci endpoint")
    return endpoint_url.rstrip("/")


class SqsMessageQueue:
    """Long-poll a queue at the required local endpoint using placeholder creds."""

    def __init__(
        self,
        *,
        queue_name: str,
        endpoint_url: str,
        region: str,
        visibility_timeout_seconds: int = 60,
        wait_time_seconds: int = 20,
    ) -> None:
        self._endpoint_url = validate_local_endpoint(endpoint_url)
        self._visibility_timeout_seconds = visibility_timeout_seconds
        self._wait_time_seconds = wait_time_seconds
        import boto3

        # Explicit local-only values avoid the AWS credential chain and metadata service.
        self._client: Any = boto3.client(
            "sqs",
            endpoint_url=self._endpoint_url,
            region_name=region,
            aws_access_key_id=LOCAL_AWS_ACCESS_KEY_ID,
            aws_secret_access_key=LOCAL_AWS_SECRET_ACCESS_KEY,
        )
        self._queue_url = str(self._client.get_queue_url(QueueName=queue_name)["QueueUrl"])

    def receive(self) -> list[QueueDelivery]:
        response = self._client.receive_message(
            QueueUrl=self._queue_url,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=self._wait_time_seconds,
            VisibilityTimeout=self._visibility_timeout_seconds,
        )
        messages = response.get("Messages", [])
        return [
            QueueDelivery(body=str(message["Body"]), receipt_handle=str(message["ReceiptHandle"]))
            for message in messages
        ]

    def delete(self, delivery: QueueDelivery) -> None:
        self._client.delete_message(
            QueueUrl=self._queue_url,
            ReceiptHandle=delivery.receipt_handle,
        )


def run_inference(image_path: Path) -> list[dict[str, Any]]:
    """Adapt the pilot CLI's detector without duplicating any inference logic."""
    import detect

    records, skipped = detect.detect_images(
        [image_path], detect.DEFAULT_THRESHOLD, "cpu"
    )
    if skipped or len(records) != 1:
        raise RuntimeError("The detector did not produce a readable image record")
    detections = records[0].get("detections")
    if not isinstance(detections, list):
        raise RuntimeError("The detector returned an invalid detection record")
    return [dict(detection) for detection in detections]


class DetectionJobWorker:
    """Process one queue delivery; all external boundaries are injectable."""

    def __init__(
        self,
        *,
        api_base_url: str,
        service_token: str,
        queue: MessageQueue,
        http_client: HttpClient,
        detector: DetectionFunction = run_inference,
    ) -> None:
        if not service_token:
            raise ValueError("DETECTION_WORKER_TOKEN is required")
        self._api_base_url = api_base_url.rstrip("/")
        self._service_token = service_token
        self._queue = queue
        self._http_client = http_client
        self._detector = detector

    def run_once(self) -> bool:
        """Receive and process at most one message; return False when the queue is empty."""
        deliveries = self._queue.receive()
        if not deliveries:
            return False
        delivery = deliveries[0]
        self._process(delivery)
        return True

    def _process(self, delivery: QueueDelivery) -> None:
        message = json.loads(delivery.body)
        job_id = str(message["job_id"])
        base = f"{self._api_base_url}/api/v1/detection/jobs/{job_id}"
        claim = self._http_client.post(
            f"{base}/claim", headers=self._headers()
        )
        if claim.status_code == 404:
            # A publication can survive a lost DB commit; there is no job to retry.
            self._queue.delete(delivery)
            return
        self._require_success(claim, "Detection API could not claim the job")
        claimed = claim.json()
        if claimed.get("status") != "running" or not claimed.get("download_url"):
            # Completed jobs and jobs leased by another worker need no duplicate work.
            self._queue.delete(delivery)
            return
        if str(claimed.get("job_id")) != job_id:
            raise RuntimeError("Detection API returned a different job")
        claim_token = claimed.get("claim_token")
        if not isinstance(claim_token, str) or not claim_token:
            raise RuntimeError("Detection API returned no active claim token")

        download_url = str(claimed["download_url"])
        try:
            downloaded = self._http_client.get(download_url)
        except Exception as error:
            self._report_failure(
                base,
                delivery,
                claim_token,
                f"Image download failed ({type(error).__name__})",
            )
            return
        if not 200 <= downloaded.status_code < 300:
            self._report_failure(
                base,
                delivery,
                claim_token,
                f"Image download failed (HTTP {downloaded.status_code})",
            )
            return

        suffix = Path(urlparse(str(claimed.get("object_key", ""))).path).suffix.lower()
        if suffix not in _SUPPORTED_IMAGE_SUFFIXES:
            suffix = ".jpg"
        try:
            # The temporary directory is container-local and removed on every outcome.
            with tempfile.TemporaryDirectory(prefix="roomforge-detection-") as temporary_dir:
                image_path = Path(temporary_dir) / f"image{suffix}"
                image_path.write_bytes(downloaded.content)
                detections = self._detector(image_path)
        except Exception as error:
            self._report_failure(
                base,
                delivery,
                claim_token,
                f"Image processing failed ({type(error).__name__})",
            )
            return

        result = {
            "claim_token": claim_token,
            "model_id": str(claimed["model_id"]),
            "detections": detections,
        }
        completed = self._http_client.post(
            f"{base}/complete",
            headers=self._headers(),
            json=result,
        )
        self._require_success(completed, "Detection API could not save the result")
        self._queue.delete(delivery)

    def _report_failure(
        self, base: str, delivery: QueueDelivery, claim_token: str, reason: str
    ) -> None:
        response = self._http_client.post(
            f"{base}/fail",
            headers=self._headers(),
            json={"claim_token": claim_token, "reason": reason[:255]},
        )
        self._require_success(response, "Detection API could not record the failure")
        self._queue.delete(delivery)

    def _headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self._service_token}"}

    @staticmethod
    def _require_success(response: HttpResponse, message: str) -> None:
        if not 200 <= response.status_code < 300:
            raise RuntimeError(message)


def main() -> int:
    """Run the local SQS consumer until interrupted."""
    endpoint_url = os.environ.get("SQS_ENDPOINT_URL", "")
    if not endpoint_url:
        raise RuntimeError("SQS_ENDPOINT_URL is required; this worker does not use AWS")
    validate_local_endpoint(endpoint_url)
    service_token = os.environ.get("DETECTION_WORKER_TOKEN", "")
    if not service_token:
        raise RuntimeError("DETECTION_WORKER_TOKEN is required")

    import httpx

    queue = SqsMessageQueue(
        queue_name=os.environ.get("DETECTION_QUEUE_NAME", "roomforge-local-detection"),
        endpoint_url=endpoint_url,
        region=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        visibility_timeout_seconds=int(
            os.environ.get("DETECTION_VISIBILITY_TIMEOUT_SECONDS", "60")
        ),
    )
    api_base_url = os.environ.get("DETECTION_API_BASE_URL", "http://api:8000")
    with httpx.Client(timeout=30.0) as http_client:
        worker = DetectionJobWorker(
            api_base_url=api_base_url,
            service_token=service_token,
            queue=queue,
            http_client=http_client,
        )
        while True:
            try:
                worker.run_once()
            except Exception:
                # Do not include exception text: signed URLs and service values are sensitive.
                LOGGER.warning("Detection processing failed; the delivery remains available for retry")
                time.sleep(1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
