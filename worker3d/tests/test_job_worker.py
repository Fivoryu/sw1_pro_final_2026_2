"""Detection queue consumer contracts; no torch, network, or live queue required."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest

WORKER3D_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKER3D_DIR))

import detect  # noqa: E402
import job_worker  # noqa: E402

_MODEL_ID = "ssdlite320-mobilenetv3-coco-v1"
_JOB_ID = "detection-job-one"
_DETECTION = {"label": "chair", "score": 0.83, "box": [1.0, 2.0, 30.0, 40.0]}


class FakeResponse:
    def __init__(
        self,
        *,
        status_code: int = 200,
        body: dict[str, Any] | None = None,
        content: bytes = b"image bytes",
        headers: dict[str, str] | None = None,
    ) -> None:
        self.status_code = status_code
        self._body = body or {}
        self.content = content
        self.headers = headers or {}

    def json(self) -> dict[str, Any]:
        return self._body


class FakeHttpClient:
    def __init__(self) -> None:
        self.posts: list[tuple[str, dict[str, Any] | None]] = []
        self.downloads: list[str] = []
        self.claims = [
            {"job_id": _JOB_ID, "photo_id": "photo-one", "object_key": "photos/one.jpg",
             "model_id": _MODEL_ID, "status": "running", "claim_token": "claim-token-one",
             "download_url": "http://floci/photo"},
            {"job_id": _JOB_ID, "photo_id": "photo-one", "object_key": "photos/one.jpg",
             "model_id": _MODEL_ID, "status": "completed", "download_url": None},
        ]

    def post(
        self,
        url: str,
        *,
        headers: dict[str, str],
        json: dict[str, Any] | None = None,
    ) -> FakeResponse:
        assert headers == {"Authorization": "Bearer service-token"}
        self.posts.append((url, json))
        if url.endswith("/claim"):
            return FakeResponse(body=self.claims.pop(0))
        if url.endswith("/complete"):
            return FakeResponse(body={"status": "completed"})
        if url.endswith("/fail"):
            return FakeResponse(body={"status": "failed"})
        raise AssertionError(f"unexpected POST {url}")

    def get(self, url: str) -> FakeResponse:
        self.downloads.append(url)
        return FakeResponse(content=b"authorized image bytes")


class FakeQueue:
    def __init__(self, deliveries: list[job_worker.QueueDelivery]) -> None:
        self.deliveries = deliveries
        self.deleted: list[job_worker.QueueDelivery] = []

    def receive(self) -> list[job_worker.QueueDelivery]:
        if not self.deliveries:
            return []
        return [self.deliveries.pop(0)]

    def delete(self, delivery: job_worker.QueueDelivery) -> None:
        self.deleted.append(delivery)


def _delivery(receipt_handle: str) -> job_worker.QueueDelivery:
    return job_worker.QueueDelivery(
        body=json.dumps(
            {
                "version": 1,
                "job_id": _JOB_ID,
                "photo_id": "photo-one",
                "object_key": "photos/one.jpg",
                "model_id": _MODEL_ID,
                "attempt": 1,
            }
        ),
        receipt_handle=receipt_handle,
    )


def test_worker_reuses_existing_detector_and_preserves_detection_schema(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    calls: list[tuple[list[Path], float, str]] = []

    def fake_detect_images(images: list[Path], threshold: float, device: str) -> tuple[list[dict[str, Any]], list[str]]:
        calls.append((images, threshold, device))
        return ([{"detections": [_DETECTION]}], [])

    monkeypatch.setattr(detect, "detect_images", fake_detect_images)
    image = tmp_path / "authorized.jpg"
    image.write_bytes(b"not decoded by the patched detector")

    detections = job_worker.run_inference(image)

    assert detections == [_DETECTION]
    assert calls == [([image], detect.DEFAULT_THRESHOLD, "cpu")]


def test_repeated_delivery_neither_infers_nor_reports_twice() -> None:
    deliveries = [_delivery("receipt-one"), _delivery("receipt-two")]
    queue = FakeQueue(deliveries)
    http = FakeHttpClient()
    inferred: list[bytes] = []

    def detector(image_path: Path) -> list[dict[str, Any]]:
        inferred.append(image_path.read_bytes())
        return [_DETECTION]

    worker = job_worker.DetectionJobWorker(
        api_base_url="http://api:8000",
        service_token="service-token",
        queue=queue,
        http_client=http,
        detector=detector,
    )

    worker.run_once()
    worker.run_once()

    assert inferred == [b"authorized image bytes"]
    assert len([url for url, _ in http.posts if url.endswith("/complete")]) == 1
    assert len([url for url in http.downloads if url == "http://floci/photo"]) == 1
    assert [delivery.receipt_handle for delivery in queue.deleted] == [
        "receipt-one", "receipt-two"
    ]
    complete_body = next(body for url, body in http.posts if url.endswith("/complete"))
    assert complete_body == {
        "claim_token": "claim-token-one",
        "model_id": _MODEL_ID,
        "detections": [_DETECTION],
    }


def test_failed_inference_is_reported_to_api_before_acknowledging() -> None:
    queue = FakeQueue([_delivery("receipt-failed")])
    http = FakeHttpClient()

    def detector(_: Path) -> list[dict[str, Any]]:
        raise RuntimeError("private image path must not leak")

    worker = job_worker.DetectionJobWorker(
        api_base_url="http://api:8000",
        service_token="service-token",
        queue=queue,
        http_client=http,
        detector=detector,
    )

    worker.run_once()

    failures = [(url, body) for url, body in http.posts if url.endswith("/fail")]
    assert len(failures) == 1
    assert failures[0][1] is not None
    assert "private image path" not in failures[0][1]["reason"]
    assert failures[0][1]["claim_token"] == "claim-token-one"
    assert [delivery.receipt_handle for delivery in queue.deleted] == ["receipt-failed"]


def test_claim_404_discards_a_message_for_a_missing_job() -> None:
    delivery = _delivery("receipt-missing")
    queue = FakeQueue([delivery])

    class MissingJobHttpClient:
        posts: list[str] = []

        def post(
            self,
            url: str,
            *,
            headers: dict[str, str],
            json: dict[str, Any] | None = None,
        ) -> FakeResponse:
            assert headers == {"Authorization": "Bearer service-token"}
            assert json is None
            self.posts.append(url)
            return FakeResponse(status_code=404)

        def get(self, url: str) -> FakeResponse:
            raise AssertionError(f"a missing job must not download an image: {url}")

    http = MissingJobHttpClient()
    inferred: list[Path] = []
    worker = job_worker.DetectionJobWorker(
        api_base_url="http://api:8000",
        service_token="service-token",
        queue=queue,
        http_client=http,
        detector=lambda path: inferred.append(path) or [_DETECTION],
    )

    assert worker.run_once() is True
    assert http.posts == [
        f"http://api:8000/api/v1/detection/jobs/{_JOB_ID}/claim"
    ]
    assert inferred == []
    assert queue.deleted == [delivery]


def test_non_404_claim_error_is_reported_and_acknowledged_after_failure_path() -> None:
    delivery = _delivery("receipt-claim-error")
    queue = FakeQueue([delivery])

    class ClaimErrorHttpClient:
        def __init__(self) -> None:
            self.posts: list[tuple[str, dict[str, Any] | None]] = []

        def post(
            self,
            url: str,
            *,
            headers: dict[str, str],
            json: dict[str, Any] | None = None,
        ) -> FakeResponse:
            assert headers == {"Authorization": "Bearer service-token"}
            self.posts.append((url, json))
            if url.endswith("/claim"):
                return FakeResponse(
                    status_code=503,
                    headers={"X-Detection-Claim-Token": "claim-before-signing"},
                )
            if url.endswith("/fail"):
                return FakeResponse(body={"status": "pending"})
            raise AssertionError(f"unexpected POST {url}")

        def get(self, url: str) -> FakeResponse:
            raise AssertionError(f"claim failure must not download an image: {url}")

    http = ClaimErrorHttpClient()
    worker = job_worker.DetectionJobWorker(
        api_base_url="http://api:8000",
        service_token="service-token",
        queue=queue,
        http_client=http,
        detector=lambda _: pytest.fail("claim failure must not run inference"),
    )

    assert worker.run_once() is True
    failure = next((url, body) for url, body in http.posts if url.endswith("/fail"))
    assert failure[1] == {
        "claim_token": "claim-before-signing",
        "reason": "Job claim failed (HTTP 503)",
    }
    assert queue.deleted == [delivery]


def test_completed_job_is_discarded_without_download_or_detection() -> None:
    delivery = _delivery("receipt-completed")
    queue = FakeQueue([delivery])
    http = FakeHttpClient()
    http.claims = [
        {"job_id": _JOB_ID, "status": "completed", "download_url": None}
    ]
    inferred: list[Path] = []
    worker = job_worker.DetectionJobWorker(
        api_base_url="http://api:8000",
        service_token="service-token",
        queue=queue,
        http_client=http,
        detector=lambda path: inferred.append(path) or [_DETECTION],
    )

    worker.run_once()

    assert inferred == []
    assert http.downloads == []
    assert not any(url.endswith(("/complete", "/fail")) for url, _ in http.posts)
    assert queue.deleted == [delivery]


def test_queue_endpoint_must_be_local_and_uses_only_local_placeholder_credentials(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    assert job_worker.validate_local_endpoint("http://floci:4566") == "http://floci:4566"
    with pytest.raises(ValueError, match="local"):
        job_worker.validate_local_endpoint("https://sqs.us-east-1.amazonaws.com")

    observed: dict[str, Any] = {}

    class FakeSqsClient:
        def get_queue_url(self, *, QueueName: str) -> dict[str, str]:
            observed["queue_name"] = QueueName
            return {"QueueUrl": "http://floci:4566/queue/roomforge-local-detection"}

    def fake_boto_client(service: str, **kwargs: Any) -> FakeSqsClient:
        observed["service"] = service
        observed.update(kwargs)
        return FakeSqsClient()

    monkeypatch.setitem(sys.modules, "boto3", SimpleNamespace(client=fake_boto_client))

    job_worker.SqsMessageQueue(
        queue_name="roomforge-local-detection",
        endpoint_url="http://floci:4566",
        region="us-east-1",
    )

    assert observed["service"] == "sqs"
    assert observed["endpoint_url"] == "http://floci:4566"
    assert observed["aws_access_key_id"] == "local-test-key"
    assert observed["aws_secret_access_key"] == "local-test-secret"
    assert observed["queue_name"] == "roomforge-local-detection"
