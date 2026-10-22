"""HTTP-only consumer for asynchronous capture reconstruction jobs (F07.7).

Same pattern as ``job_worker.py`` (F08.4): the API is the sole writer of job
state. This process receives queue messages, asks the API to claim a job,
downloads the signed capture package URL, runs ``reconstruct.reconstruct`` and
reports the scene draft or the failure. Queue and HTTP abstractions are reused
from ``job_worker``.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

import reconstruct
from job_worker import (
    HttpClient,
    HttpResponse,
    MessageQueue,
    QueueDelivery,
    SqsMessageQueue,
    validate_local_endpoint,
)

LOGGER = logging.getLogger("roomforge.reconstruction.worker")
CLAIM_TOKEN_HEADER = "X-Reconstruction-Claim-Token"

Reconstructor = Callable[[Path], reconstruct.ReconstructionResult]


class ReconstructionJobWorker:
    """Process one queue delivery; all external boundaries are injectable."""

    def __init__(
        self,
        *,
        api_base_url: str,
        service_token: str,
        queue: MessageQueue,
        http_client: HttpClient,
        reconstructor: Reconstructor = reconstruct.reconstruct,
        claim_failure_receive_cap: int = 3,
    ) -> None:
        if not service_token:
            raise ValueError("RECONSTRUCTION_WORKER_TOKEN is required")
        if claim_failure_receive_cap < 1:
            raise ValueError("claim_failure_receive_cap must be positive")
        self._api_base_url = api_base_url.rstrip("/")
        self._service_token = service_token
        self._queue = queue
        self._http_client = http_client
        self._reconstructor = reconstructor
        self._claim_failure_receive_cap = claim_failure_receive_cap

    def run_once(self) -> bool:
        """Receive and process at most one message; return False when the queue is empty."""
        deliveries = self._queue.receive()
        if not deliveries:
            return False
        self._process(deliveries[0])
        return True

    def _process(self, delivery: QueueDelivery) -> None:
        message = json.loads(delivery.body)
        job_id = str(message["job_id"])
        base = f"{self._api_base_url}/api/v1/reconstruction/jobs/{job_id}"
        claim = self._http_client.post(f"{base}/claim", headers=self._headers())
        if claim.status_code == 404:
            # A publication can survive a lost DB commit; there is no job to retry.
            self._queue.delete(delivery)
            return
        if not 200 <= claim.status_code < 300:
            claim_token = claim.headers.get(CLAIM_TOKEN_HEADER)
            if claim_token:
                self._report_failure(
                    base,
                    delivery,
                    claim_token,
                    f"Job claim failed (HTTP {claim.status_code})",
                    retryable=True,
                )
                return
            if delivery.receive_count > self._claim_failure_receive_cap:
                LOGGER.error(
                    "Reconstruction job claim failed without a claim token after %d receives "
                    "(HTTP %d); dropping delivery",
                    delivery.receive_count,
                    claim.status_code,
                )
                self._queue.delete(delivery)
                return
            self._require_success(claim, "Reconstruction API could not claim the job")
        claimed = claim.json()
        if claimed.get("status") != "running" or not claimed.get("download_url"):
            # Completed jobs and jobs leased by another worker need no duplicate work.
            self._queue.delete(delivery)
            return
        if str(claimed.get("job_id")) != job_id:
            raise RuntimeError("Reconstruction API returned a different job")
        claim_token = claimed.get("claim_token")
        if not isinstance(claim_token, str) or not claim_token:
            raise RuntimeError("Reconstruction API returned no active claim token")

        try:
            downloaded = self._http_client.get(str(claimed["download_url"]))
        except Exception as error:  # noqa: BLE001 - any transport failure is retryable
            self._report_failure(
                base,
                delivery,
                claim_token,
                f"Package download failed ({type(error).__name__})",
                retryable=True,
            )
            return
        if not 200 <= downloaded.status_code < 300:
            self._report_failure(
                base,
                delivery,
                claim_token,
                f"Package download failed (HTTP {downloaded.status_code})",
                retryable=True,
            )
            return

        try:
            # The temporary directory is container-local and removed on every outcome.
            with tempfile.TemporaryDirectory(prefix="roomforge-reconstruction-") as scratch:
                archive = Path(scratch) / "package.zip"
                archive.write_bytes(downloaded.content)
                package_dir = reconstruct.extract_package(archive, Path(scratch) / "package")
                result = self._reconstructor(package_dir)
        except reconstruct.InvalidPackage as error:
            # The package itself is unusable: retrying cannot help.
            self._report_failure(
                base, delivery, claim_token, f"Invalid package: {error}", retryable=False
            )
            return
        except Exception as error:  # noqa: BLE001 - unknown failures are retryable
            # Exception text may carry paths or signed values: report the type only.
            self._report_failure(
                base,
                delivery,
                claim_token,
                f"Reconstruction failed ({type(error).__name__})",
                retryable=True,
            )
            return

        completed = self._http_client.post(
            f"{base}/complete",
            headers=self._headers(claim_token),
            json={"sceneDraft": result.scene_draft, "warnings": result.warnings},
        )
        self._require_success(completed, "Reconstruction API could not save the result")
        self._queue.delete(delivery)

    def _report_failure(
        self,
        base: str,
        delivery: QueueDelivery,
        claim_token: str,
        reason: str,
        *,
        retryable: bool,
    ) -> None:
        response = self._http_client.post(
            f"{base}/fail",
            headers=self._headers(claim_token),
            json={"reason": reason[:255], "retryable": retryable},
        )
        self._require_success(response, "Reconstruction API could not record the failure")
        self._queue.delete(delivery)

    def _headers(self, claim_token: str | None = None) -> dict[str, str]:
        headers = {"Authorization": f"Bearer {self._service_token}"}
        if claim_token is not None:
            headers[CLAIM_TOKEN_HEADER] = claim_token
        return headers

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
    service_token = os.environ.get("RECONSTRUCTION_WORKER_TOKEN", "")
    if not service_token:
        raise RuntimeError("RECONSTRUCTION_WORKER_TOKEN is required")

    import httpx

    queue = SqsMessageQueue(
        queue_name=os.environ.get("RECONSTRUCTION_QUEUE_NAME", "roomforge-local-reconstruction"),
        endpoint_url=endpoint_url,
        region=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        # Reconstruction takes longer than a single detection.
        visibility_timeout_seconds=int(
            os.environ.get("RECONSTRUCTION_VISIBILITY_TIMEOUT_SECONDS", "300")
        ),
    )
    api_base_url = os.environ.get("RECONSTRUCTION_API_BASE_URL", "http://api:8000")
    http_client: Any
    with httpx.Client(timeout=60.0) as http_client:
        worker = ReconstructionJobWorker(
            api_base_url=api_base_url,
            service_token=service_token,
            queue=queue,
            http_client=http_client,
            claim_failure_receive_cap=int(os.environ.get("RECONSTRUCTION_MAX_ATTEMPTS", "3")),
        )
        while True:
            try:
                worker.run_once()
            except Exception:  # noqa: BLE001
                # Do not include exception text: signed URLs and service values are sensitive.
                LOGGER.warning(
                    "Reconstruction processing failed; the delivery remains available for retry"
                )
                time.sleep(1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
