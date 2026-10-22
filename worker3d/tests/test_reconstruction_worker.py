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


# --- class suggestions for depth volumes -------------------------------------------------------

_VIEW = {"objectId": "box-1", "keyframe": 2, "image": "frames/000002.jpg", "box": [100, 100, 200, 200]}


def _reconstructor_with_views(views: list[dict[str, Any]]) -> Any:
    def reconstruct_with_views(package_dir: Path) -> reconstruct.ReconstructionResult:
        result = reconstruct.reconstruct(package_dir)
        return reconstruct.ReconstructionResult(result.scene_draft, result.warnings, views)

    return reconstruct_with_views


def _complete_body(http: FakeHttpClient) -> dict[str, Any]:
    body = http.posts[-1][2]
    assert http.posts[-1][0].endswith("/complete") and body is not None
    return body


def _suggestion_worker(
    http: FakeHttpClient, queue: FakeQueue, labeler: Any
) -> reconstruction_worker.ReconstructionJobWorker:
    return reconstruction_worker.ReconstructionJobWorker(
        api_base_url="http://api:8000",
        service_token="service-token",
        queue=queue,
        http_client=http,
        reconstructor=_reconstructor_with_views([_VIEW]),
        labeler=labeler,
    )


def test_labeler_suggestions_are_posted_with_the_scene_draft() -> None:
    http = FakeHttpClient()
    suggestions = {
        "modelId": "m",
        "items": [
            {"objectId": "box-1", "label": "chair", "score": 0.9, "keyframe": 2, "box": [1, 2, 3, 4]}
        ],
    }
    seen: list[Any] = []

    def labeler(_dir: Path, views: list[dict[str, Any]]) -> dict[str, Any]:
        seen.append(views)
        return suggestions

    _suggestion_worker(http, FakeQueue(), labeler).run_once()

    body = _complete_body(http)
    assert set(body) == {"sceneDraft", "warnings", "volumeSuggestions"}
    assert body["volumeSuggestions"] == suggestions
    assert seen == [[_VIEW]]


def test_no_matches_leaves_the_payload_unchanged() -> None:
    http = FakeHttpClient()

    _suggestion_worker(http, FakeQueue(), lambda _dir, _views: None).run_once()

    assert set(_complete_body(http)) == {"sceneDraft", "warnings"}


def test_detector_unavailable_adds_the_warning_and_sends_no_suggestions() -> None:
    http = FakeHttpClient()

    def unavailable(_dir: Path, _views: list[dict[str, Any]]) -> None:
        raise reconstruction_worker.DetectorUnavailable

    _suggestion_worker(http, FakeQueue(), unavailable).run_once()

    body = _complete_body(http)
    assert "volumeSuggestions" not in body
    assert "Class suggestions skipped: detector unavailable" in body["warnings"]


def test_labeler_failure_does_not_fail_the_job_nor_leak_its_message() -> None:
    http, queue = FakeHttpClient(), FakeQueue()

    def broken(_dir: Path, _views: list[dict[str, Any]]) -> None:
        raise RuntimeError("secret /path")

    _suggestion_worker(http, queue, broken).run_once()

    body = _complete_body(http)
    assert "volumeSuggestions" not in body
    assert "secret" not in json.dumps(body["warnings"])
    assert len(queue.deleted) == 1


def test_default_labeler_without_views_never_loads_the_detector() -> None:
    http = FakeHttpClient()

    _worker(http, FakeQueue()).run_once()

    body = _complete_body(http)
    assert set(body) == {"sceneDraft", "warnings"}
    assert not any("Class suggestions" in warning for warning in body["warnings"])


def _fake_detector(per_image: dict[str, list[dict[str, Any]]], calls: list[str]) -> Any:
    def detector(images: Any, threshold: float) -> tuple[list[dict[str, Any]], list[str]]:
        assert threshold == 0.5
        [path] = list(images)
        calls.append(path.name)
        return [{"image": path.name, "detections": per_image.get(path.name, [])}], []

    return detector


def test_label_volumes_picks_the_highest_iou_detection_and_drops_weak_overlaps(
    tmp_path: Path,
) -> None:
    views = [
        {"objectId": "box-1", "keyframe": 2, "image": "frames/b.jpg", "box": [100, 100, 200, 200]},
        {"objectId": "box-2", "keyframe": 2, "image": "frames/b.jpg", "box": [300, 300, 400, 400]},
        {"objectId": "box-3", "keyframe": 3, "image": "frames/c.jpg", "box": [0, 0, 100, 100]},
    ]
    detections = {
        "b.jpg": [
            {"label": "tv", "score": 0.95, "box": [100, 100, 130, 130]},  # IoU 0.09 with box-1
            {"label": "chair", "score": 0.6, "box": [110, 100, 210, 200]},  # IoU 0.82 with box-1
            {"label": "bed", "score": 0.9, "box": [300, 300, 340, 400]},  # IoU 0.4 with box-2
        ],
        "c.jpg": [{"label": "couch", "score": 0.8, "box": [70, 0, 170, 100]}],  # IoU 0.18
    }
    calls: list[str] = []

    result = reconstruction_worker.label_volumes(
        tmp_path, views, _fake_detector(detections, calls), "model-x", 0.5
    )

    assert result == {
        "modelId": "model-x",
        "items": [
            {
                "objectId": "box-1",
                "label": "chair",
                "score": 0.6,
                "keyframe": 2,
                "box": [110, 100, 210, 200],
            },
            {
                "objectId": "box-2",
                "label": "bed",
                "score": 0.9,
                "keyframe": 2,
                "box": [300, 300, 340, 400],
            },
        ],
    }
    assert calls == ["b.jpg", "c.jpg"]  # once per distinct keyframe


def test_label_volumes_without_any_match_returns_none(tmp_path: Path) -> None:
    view = {"objectId": "box-1", "keyframe": 1, "image": "frames/a.jpg", "box": [0, 0, 10, 10]}

    result = reconstruction_worker.label_volumes(tmp_path, [view], _fake_detector({}, []), "m", 0.5)

    assert result is None


def test_label_volumes_keeps_the_highest_scores_when_truncating(tmp_path: Path) -> None:
    views = [
        {"objectId": f"box-{i}", "keyframe": 1, "image": "a.jpg", "box": [i * 10, 0, i * 10 + 9, 9]}
        for i in range(1, 106)
    ]
    detections = {
        "a.jpg": [
            {"label": "chair", "score": round(0.5 + i / 1000, 4), "box": [i * 10, 0, i * 10 + 9, 9]}
            for i in range(1, 106)
        ]
    }

    result = reconstruction_worker.label_volumes(
        tmp_path, views, _fake_detector(detections, []), "m", 0.5
    )

    assert result is not None and len(result["items"]) == 100
    assert result["items"][0]["objectId"] == "box-105"
    assert "box-1" not in {item["objectId"] for item in result["items"]}
