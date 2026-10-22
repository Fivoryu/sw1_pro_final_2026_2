"""Reconstruction queue consumer contracts; no network, queue or heavy dependency required."""

from __future__ import annotations

import io
import json
import sys
import zipfile
from pathlib import Path
from typing import Any

import pytest

WORKER3D_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKER3D_DIR))

import job_worker
import reconstruct
import reconstruction_worker
from test_reconstruct_synthetic import room_package

_JOB_ID = "reconstruction-job-one"
_CLAIM_HEADER = "X-Reconstruction-Claim-Token"


class FakeResponse:
    def __init__(
        self,
        *,
        status_code: int = 200,
        body: dict[str, Any] | None = None,
        content: bytes = b"",
        headers: dict[str, str] | None = None,
    ) -> None:
        self.status_code = status_code
        self._body = body or {}
        self.content = content
        self.headers = headers or {}

    def json(self) -> dict[str, Any]:
        return self._body


def _zip_bytes(manifest: dict[str, Any] | None = None) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as handle:
        handle.writestr("manifest.json", json.dumps(manifest or room_package()))
    return buffer.getvalue()


class FakeHttpClient:
    def __init__(
        self,
        *,
        claim: FakeResponse | None = None,
        package: bytes | None = None,
        download_status: int = 200,
        download_error: Exception | None = None,
    ) -> None:
        self.claim = claim or FakeResponse(
            body={
                "job_id": _JOB_ID,
                "status": "running",
                "download_url": "http://floci/package.zip",
                "claim_token": "claim-token-one",
            }
        )
        self.package = _zip_bytes() if package is None else package
        self.download_status = download_status
        self.download_error = download_error
        self.posts: list[tuple[str, dict[str, str], dict[str, Any] | None]] = []
        self.downloads: list[str] = []

    def post(
        self, url: str, *, headers: dict[str, str], json: dict[str, Any] | None = None
    ) -> FakeResponse:
        assert headers["Authorization"] == "Bearer service-token"
        self.posts.append((url, headers, json))
        if url.endswith("/claim"):
            return self.claim
        if url.endswith(("/complete", "/fail")):
            assert headers[_CLAIM_HEADER] == "claim-token-one"
            return FakeResponse(body={"status": "ok"})
        raise AssertionError(f"unexpected POST {url}")

    def get(self, url: str) -> FakeResponse:
        self.downloads.append(url)
        if self.download_error is not None:
            raise self.download_error
        return FakeResponse(status_code=self.download_status, content=self.package)


class FakeQueue:
    def __init__(self, count: int = 1) -> None:
        self.deliveries = [
            job_worker.QueueDelivery(body=json.dumps({"job_id": _JOB_ID}), receipt_handle=f"r{i}")
            for i in range(count)
        ]
        self.deleted: list[job_worker.QueueDelivery] = []

    def receive(self) -> list[job_worker.QueueDelivery]:
        return [self.deliveries.pop(0)] if self.deliveries else []

    def delete(self, delivery: job_worker.QueueDelivery) -> None:
        self.deleted.append(delivery)


def _worker(
    http: FakeHttpClient, queue: FakeQueue, reconstructor: Any = reconstruct.reconstruct
) -> reconstruction_worker.ReconstructionJobWorker:
    return reconstruction_worker.ReconstructionJobWorker(
        api_base_url="http://api:8000",
        service_token="service-token",
        queue=queue,
        http_client=http,
        reconstructor=reconstructor,
    )


def test_successful_job_posts_scene_draft_and_warnings_then_acknowledges() -> None:
    http, queue = FakeHttpClient(), FakeQueue()

    assert _worker(http, queue).run_once() is True

    base = f"http://api:8000/api/v1/reconstruction/jobs/{_JOB_ID}"
    assert [url for url, _, _ in http.posts] == [f"{base}/claim", f"{base}/complete"]
    _, _, body = http.posts[1]
    assert body is not None
    assert set(body) == {"sceneDraft", "warnings"}
    assert body["sceneDraft"]["version"] == "2.0"
    assert isinstance(body["warnings"], list)
    assert http.downloads == ["http://floci/package.zip"]
    assert len(queue.deleted) == 1


def test_empty_queue_does_nothing() -> None:
    http = FakeHttpClient()

    assert _worker(http, FakeQueue(0)).run_once() is False
    assert http.posts == []


def test_temporary_directory_is_removed_after_success_and_after_failure() -> None:
    seen: list[Path] = []

    def reconstructor(package_dir: Path) -> reconstruct.ReconstructionResult:
        seen.append(package_dir)
        assert (package_dir / "manifest.json").is_file()
        if len(seen) == 2:
            raise RuntimeError("boom")
        return reconstruct.ReconstructionResult({"version": "2.0"}, [])

    for _ in range(2):
        _worker(FakeHttpClient(), FakeQueue(), reconstructor).run_once()

    assert len(seen) == 2
    assert all(not path.exists() and not path.parent.exists() for path in seen)


def test_invalid_package_is_reported_as_not_retryable() -> None:
    manifest = room_package(schemaVersion=2)
    http, queue = FakeHttpClient(package=_zip_bytes(manifest)), FakeQueue()

    _worker(http, queue).run_once()

    url, _, body = http.posts[1]
    assert url.endswith("/fail")
    assert body is not None
    assert body["retryable"] is False
    assert "schemaVersion" in body["reason"]
    assert len(queue.deleted) == 1


def test_corrupt_zip_is_not_retryable() -> None:
    http = FakeHttpClient(package=b"definitely not a zip")

    _worker(http, FakeQueue()).run_once()

    _, _, body = http.posts[1]
    assert body is not None
    assert body["retryable"] is False


def test_unexpected_error_is_retryable_and_hides_exception_text() -> None:
    def reconstructor(package_dir: Path) -> reconstruct.ReconstructionResult:
        raise RuntimeError("secret internal detail")

    http, queue = FakeHttpClient(), FakeQueue()

    _worker(http, queue, reconstructor).run_once()

    url, _, body = http.posts[1]
    assert url.endswith("/fail")
    assert body is not None
    assert body["retryable"] is True
    assert "secret" not in body["reason"]
    assert len(queue.deleted) == 1


@pytest.mark.parametrize(
    "http",
    [
        FakeHttpClient(download_status=403),
        FakeHttpClient(download_error=ConnectionError("down")),
    ],
    ids=["http-error", "network-error"],
)
def test_download_failure_is_retryable(http: FakeHttpClient) -> None:
    queue = FakeQueue()

    _worker(http, queue).run_once()

    url, _, body = http.posts[1]
    assert url.endswith("/fail")
    assert body is not None
    assert body["retryable"] is True


def test_unknown_job_is_dropped_without_work() -> None:
    http = FakeHttpClient(claim=FakeResponse(status_code=404))
    queue = FakeQueue()

    _worker(http, queue).run_once()

    assert len(http.posts) == 1
    assert http.downloads == []
    assert len(queue.deleted) == 1


def test_terminal_job_is_acknowledged_without_reprocessing() -> None:
    http = FakeHttpClient(
        claim=FakeResponse(body={"job_id": _JOB_ID, "status": "completed", "download_url": None})
    )
    queue = FakeQueue()

    _worker(http, queue).run_once()

    assert len(http.posts) == 1
    assert http.downloads == []
    assert len(queue.deleted) == 1


def test_failed_claim_with_token_is_reported_as_retryable_failure() -> None:
    http = FakeHttpClient(
        claim=FakeResponse(status_code=500, headers={_CLAIM_HEADER: "claim-token-one"})
    )

    _worker(http, FakeQueue()).run_once()

    url, _, body = http.posts[1]
    assert url.endswith("/fail")
    assert body is not None
    assert body["retryable"] is True


def test_failed_claim_without_token_leaves_the_delivery_for_retry() -> None:
    http = FakeHttpClient(claim=FakeResponse(status_code=503))
    queue = FakeQueue()

    with pytest.raises(RuntimeError):
        _worker(http, queue).run_once()

    assert queue.deleted == []


def test_worker_requires_a_service_token() -> None:
    with pytest.raises(ValueError):
        reconstruction_worker.ReconstructionJobWorker(
            api_base_url="http://api",
            service_token="",
            queue=FakeQueue(),
            http_client=FakeHttpClient(),
        )
