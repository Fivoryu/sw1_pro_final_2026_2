"""HTTP-only consumer for asynchronous capture reconstruction jobs (F07.7).

Same pattern as ``job_worker.py`` (F08.4): the API is the sole writer of job
state. This process receives queue messages, asks the API to claim a job,
downloads the signed capture package URL, runs ``reconstruct.reconstruct`` and
reports the scene draft or the failure. Queue and HTTP abstractions are reused
from ``job_worker``.
"""

from __future__ import annotations

import hashlib
import json
import logging
import math
import os
import re
import tempfile
import threading
import time
from collections.abc import Callable, Iterable, Mapping
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import reconstruct
from job_worker import (
    LOCAL_AWS_ACCESS_KEY_ID,
    LOCAL_AWS_SECRET_ACCESS_KEY,
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

# Class suggestions are optional and never come from the geometry: the labeler gets the package
# directory and the volume views and returns the ``volumeSuggestions`` payload (or None).
Labeler = Callable[[Path, list[dict[str, Any]]], dict[str, Any] | None]

MIN_SUGGESTION_IOU = 0.3
MAX_SUGGESTIONS = 100
# Mirrors MAX_WARNINGS in backend/app/modules/reconstruction/schemas.py; more is a 422.
MAX_WARNINGS = 200
WARNING_DETECTOR_UNAVAILABLE = "Class suggestions skipped: detector unavailable"
WARNING_LABELING_FAILED = "Class suggestions skipped: labeling failed"


# Pilot switches, both off unless set. Door recognition needs torch, transformers and Pillow on the
# worker machine; the stage cache keeps the sparse reconstruction and the door model's raw output on
# disk so a threshold can be tried again without paying for them twice. Neither is for production.
OPENING_DETECTION_ENV = "ROOMFORGE_OPENING_DETECTION"
STAGE_CACHE_ENV = "ROOMFORGE_STAGE_CACHE_DIR"
OPENING_DETECTION_MODELS = ("owlv2",)  # the only one with a backend; Grounding DINO is pinned but not built
_OFF = {"", "off", "0", "false", "no"}


def pilot_options(environ: Mapping[str, str] | None = None) -> dict[str, Any]:
    """Keyword arguments for ``reconstruct_video`` that the environment switches on."""
    import openings
    import reconstruct_video

    environ = os.environ if environ is None else environ
    options: dict[str, Any] = {}
    cache = None
    directory = environ.get(STAGE_CACHE_ENV, "").strip()
    if directory:
        cache = reconstruct_video.make_stage_cache(Path(directory))
        options["stage_cache"] = cache
    model = environ.get(OPENING_DETECTION_ENV, "").strip().lower()
    if model not in _OFF:
        if model not in OPENING_DETECTION_MODELS:
            raise ValueError(
                f"{OPENING_DETECTION_ENV}={model!r} is not supported; use one of {', '.join(OPENING_DETECTION_MODELS)} or off"
            )
        # Built when the pipeline asks, so a missing runtime becomes a warning, not a failed job.
        options["opening_detector"] = lambda: openings.build_detector(model, cache=cache)
    return options


def reconstruct_package(package_dir: Path) -> reconstruct.ReconstructionResult:
    """Default reconstructor: schema 2 (video) also detects furniture; schema 1 is unchanged."""
    if reconstruct._declared_schema_version(package_dir) == 2:
        import reconstruct_video

        return reconstruct_video.reconstruct_video(
            package_dir, detector_factory=lambda: reconstruct_video.default_detector(), **pilot_options()
        )
    return reconstruct.reconstruct(package_dir)


class DetectorUnavailable(Exception):
    """The inference runtime (torch/torchvision) is not installed in this interpreter."""


def box_iou(a: list[float], b: list[float]) -> float:
    width = min(a[2], b[2]) - max(a[0], b[0])
    height = min(a[3], b[3]) - max(a[1], b[1])
    if width <= 0 or height <= 0:
        return 0.0
    inter = width * height
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0.0


def label_volumes(
    package_dir: Path,
    views: list[dict[str, Any]],
    detector: Callable[[Iterable[Path], float], tuple[list[dict[str, Any]], list[str]]],
    model_id: str,
    threshold: float,
) -> dict[str, Any] | None:
    """Match each volume to the detection of its chosen keyframe with the highest IoU."""
    root = package_dir.resolve()
    detections: dict[int, list[dict[str, Any]]] = {}
    items: list[dict[str, Any]] = []
    for view in views:
        frame = view["keyframe"]
        if frame not in detections:
            path = (package_dir / view["image"]).resolve()
            # One detector call per distinct keyframe; a path outside the package is ignored.
            records = detector([path], threshold)[0] if root in path.parents else []
            detections[frame] = records[0]["detections"] if records else []
        best = max(
            detections[frame],
            key=lambda d: box_iou(view["box"], d["box"]),
            default=None,
        )
        if best is None or box_iou(view["box"], best["box"]) < MIN_SUGGESTION_IOU:
            continue
        items.append(
            {
                "objectId": view["objectId"],
                "label": best["label"],
                "score": best["score"],
                "keyframe": frame,
                "box": best["box"],
            }
        )
    if not items:
        return None
    if len(items) > MAX_SUGGESTIONS:
        items = sorted(items, key=lambda item: item["score"], reverse=True)[:MAX_SUGGESTIONS]
    return {"modelId": model_id, "items": items}


def label_with_detector(
    package_dir: Path, views: list[dict[str, Any]]
) -> dict[str, Any] | None:
    """Default labeler: the F08 detector, loaded once and imported lazily."""
    if not views:
        return None
    try:
        import detect

        detector = detect.build_detector("cpu")
    except (ImportError, RuntimeError) as error:
        raise DetectorUnavailable from error
    return label_volumes(
        package_dir,
        views,
        detector,
        detect.MODEL_META["weights_id"],
        detect.DEFAULT_THRESHOLD,
    )


class ReconstructionJobWorker:
    """Process one queue delivery; all external boundaries are injectable."""

    def __init__(
        self,
        *,
        api_base_url: str,
        service_token: str,
        queue: MessageQueue,
        http_client: HttpClient,
        reconstructor: Reconstructor = reconstruct_package,
        labeler: Labeler = label_with_detector,
        claim_failure_receive_cap: int = 3,
        result_cache: Path | None = None,
        cache_retention_seconds: int = 30 * 24 * 3600,
        cache_max_bytes: int = 128 * 1024 * 1024,
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
        self._labeler = labeler
        self._claim_failure_receive_cap = claim_failure_receive_cap
        self._result_cache = result_cache
        if not 1 <= cache_retention_seconds <= 30 * 24 * 3600 or cache_max_bytes < 1:
            raise ValueError("Cache retention must be within 30 days and capacity positive")
        self._cache_retention_seconds = cache_retention_seconds
        self._cache_max_bytes = cache_max_bytes

    def run_once(self) -> bool:
        """Receive and process at most one message; return False when the queue is empty."""
        if self._sweep_cache() >= self._cache_max_bytes:
            # Backpressure preserves unacknowledged results instead of evicting them
            # and silently repeating expensive reconstruction on a later delivery.
            LOGGER.warning("Reconstruction cache full; waiting for retention cleanup")
            return False
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
            if claimed.get("status") in {"completed", "failed"} and self._result_cache is not None:
                self._cache_path(claimed, job_id=job_id).unlink(missing_ok=True)
            # Completed jobs and jobs leased by another worker need no duplicate work.
            self._queue.delete(delivery)
            return
        if str(claimed.get("job_id")) != job_id:
            raise RuntimeError("Reconstruction API returned a different job")
        claim_token = claimed.get("claim_token")
        if not isinstance(claim_token, str) or not claim_token:
            raise RuntimeError("Reconstruction API returned no active claim token")

        stop, lost = threading.Event(), threading.Event()
        lease = claimed.get("lease_seconds")
        def renew() -> None:
            while not stop.wait(max(0.05, min(30.0, float(lease) / 3))):
                try:
                    reply = self._http_client.post(f"{base}/renew", headers=self._headers(claim_token))
                    if not 200 <= reply.status_code < 300:
                        lost.set()
                        return
                except Exception:  # noqa: BLE001 - transport loss fences this worker
                    lost.set()
                    return
        heartbeat = threading.Thread(target=renew, daemon=True) if lease else None
        if heartbeat is not None:
            heartbeat.start()
        try:
            self._execute_claimed(base, delivery, claimed, claim_token, lost)
        finally:
            stop.set()
            if heartbeat is not None:
                heartbeat.join(timeout=65)

    def _execute_claimed(self, base: str, delivery: QueueDelivery, claimed: dict[str, Any],
                         claim_token: str, lost: threading.Event) -> None:
        cached_path: Path | None = None
        if self._result_cache is not None and claimed.get("package_sha256"):
            self._result_cache.mkdir(parents=True, exist_ok=True)
            cached_path = self._cache_path(claimed)
            try:
                cached_payload = self._load_cached_result(cached_path)
            except OSError:
                self._report_failure(base, delivery, claim_token,
                                     "Reconstruction cache unavailable", retryable=True)
                return
            if cached_payload is not None:
                response = self._post_result(f"{base}/complete", headers=self._headers(claim_token), json=cached_payload)
                if response.status_code == 422:
                    # The API owns deep scene validation; an incompatible derived
                    # result can be rebuilt. Ambiguous/ownership failures keep it.
                    try:
                        cached_path.unlink(missing_ok=True)
                    except OSError:
                        self._report_failure(base, delivery, claim_token,
                                             "Reconstruction cache unavailable", retryable=True)
                        return
                else:
                    self._require_success(response, "Cached reconstruction result could not be saved")
                    self._queue.delete(delivery)
                    cached_path.unlink(missing_ok=True)
                    return
        try:
            # The temporary directory is container-local and removed on every outcome.
            with tempfile.TemporaryDirectory(prefix="roomforge-reconstruction-") as scratch:
                archive = Path(scratch) / "package.zip"
                self._download(str(claimed["download_url"]), archive, claimed)
                if lost.is_set():
                    raise RuntimeError("Reconstruction lease ownership was lost")
                package_dir = reconstruct.extract_package(archive, Path(scratch) / "package")
                manifest = json.loads((package_dir / "manifest.json").read_text(encoding="utf-8"))
                for name, expected in (("captureId", claimed.get("capture_id")), ("listingId", claimed.get("listing_id"))):
                    if expected is not None and manifest.get(name) != expected:
                        raise reconstruct.InvalidPackage(f"manifest {name} differs from claimed capture")
                result = self._reconstructor(package_dir)
                suggestions, extra_warnings = self._suggest(package_dir, result)
        except reconstruct.InvalidPackage as error:
            # The package itself is unusable: retrying cannot help.
            self._report_failure(
                base, delivery, claim_token, f"Invalid package: {error}", retryable=False
            )
            return
        except Exception as error:  # noqa: BLE001 - unknown failures are retryable
            # Exception text may carry paths or signed values: report the type only.
            from reconstruct_video import VideoRuntimeError

            self._report_failure(
                base,
                delivery,
                claim_token,
                error.public_reason if isinstance(error, VideoRuntimeError)
                else f"Reconstruction failed ({type(error).__name__})",
                retryable=True,
            )
            return

        payload: dict[str, Any] = {
            "sceneDraft": result.scene_draft,
            # Keep the worker's own warnings when the reconstruction already fills the cap.
            "warnings": [*result.warnings[: MAX_WARNINGS - len(extra_warnings)], *extra_warnings],
        }
        if suggestions is not None:
            payload["volumeSuggestions"] = suggestions
        if cached_path is not None:
            temporary = cached_path.with_suffix("." + claim_token[:12] + ".tmp")
            expires_at = time.time() + self._cache_retention_seconds
            if claimed.get("cache_delete_after"):
                deadline = datetime.fromisoformat(claimed["cache_delete_after"])
                if deadline.tzinfo is None:
                    deadline = deadline.replace(tzinfo=UTC)
                expires_at = min(expires_at, deadline.timestamp())
            encoded = json.dumps({"expires_at": expires_at, "payload": payload}).encode("utf-8")
            if self._sweep_cache() + len(encoded) > self._cache_max_bytes:
                raise RuntimeError("Reconstruction cache capacity exceeded; result not acknowledged")
            with temporary.open("wb") as output:
                output.write(encoded)
                output.flush()
                os.fsync(output.fileno())
            temporary.replace(cached_path)
        if lost.is_set():
            raise RuntimeError("Reconstruction lease ownership was lost; result not submitted")
        completed = self._post_result(
            f"{base}/complete",
            headers=self._headers(claim_token),
            json=payload,
        )
        self._require_success(completed, "Reconstruction API could not save the result")
        self._queue.delete(delivery)
        if cached_path is not None:
            cached_path.unlink(missing_ok=True)

    def _cache_path(self, claimed: dict[str, Any], *, job_id: str | None = None) -> Path:
        assert self._result_cache is not None
        identity = hashlib.sha256((str(job_id or claimed["job_id"]) +
                                   str(claimed.get("package_sha256", "")) + "f07-hardening-1").encode()).hexdigest()
        return self._result_cache / (identity + ".json")

    def _load_cached_result(self, path: Path) -> dict[str, Any] | None:
        """Read only derived results; invalid bytes never poison subsequent claims."""
        try:
            deadline = path.stat().st_mtime + self._cache_retention_seconds
            saved = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(saved, dict):
                raise TypeError("Invalid cache root")
            if "payload" in saved:
                expires_at = saved["expires_at"]
                if (type(expires_at) not in (int, float) or not math.isfinite(expires_at)):
                    raise ValueError("Invalid cache expiration")
                deadline = min(deadline, expires_at)
            payload = saved.get("payload", saved)  # Legacy direct payloads retain their mtime TTL.
            if not isinstance(payload, dict) or not isinstance(payload.get("sceneDraft"), dict):
                raise TypeError("Invalid cached result")
            warnings = payload.get("warnings", [])
            if (payload["sceneDraft"].get("version") != "2.0"
                    or set(payload) - {"sceneDraft", "warnings", "volumeSuggestions"}
                    or not isinstance(warnings, list) or len(warnings) > MAX_WARNINGS
                    or any(not isinstance(item, str) or len(item) > 500 for item in warnings)
                    or (payload.get("volumeSuggestions") is not None
                        and not isinstance(payload["volumeSuggestions"], dict))):
                raise ValueError("Incompatible cached result")
        except FileNotFoundError:
            return None  # Another worker may have acknowledged the result.
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, OverflowError, RecursionError):
            LOGGER.warning("Discarding unreadable or incompatible derived reconstruction cache")
            path.unlink(missing_ok=True)
            return None
        if time.time() >= deadline:
            path.unlink(missing_ok=True)
            return None
        return payload

    def _sweep_cache(self) -> int:
        if self._result_cache is None or not self._result_cache.exists():
            return 0
        total = 0
        now = time.time()
        for path in self._result_cache.iterdir():
            if not re.fullmatch(r"[a-f0-9]{64}(?:\.[A-Za-z0-9_-]{1,12})?\.(?:json|tmp)", path.name) or path.is_symlink():
                continue
            size = 0
            try:
                stat = path.stat()
                size = stat.st_size
                deadline = stat.st_mtime + (min(3600, self._cache_retention_seconds) if path.suffix == ".tmp"
                                           else self._cache_retention_seconds)
                if path.suffix == ".json":
                    if self._load_cached_result(path) is not None:
                        total += stat.st_size
                    continue
                if now >= deadline:
                    path.unlink(missing_ok=True)
                else:
                    total += stat.st_size
            except FileNotFoundError:
                pass # Another process acknowledged this result.
            except OSError:
                # Keep capacity accounting if the filesystem refuses cache cleanup.
                # A claimed job reports this as recoverable, without exposing paths.
                LOGGER.warning("Derived reconstruction cache cleanup unavailable")
                total += size
        return total

    def _post_result(self, url: str, *, headers: dict[str, str], json: dict[str, Any]) -> HttpResponse:
        # Retry the same result/token before releasing its memory; /complete is idempotent.
        for attempt in range(3):
            try:
                response = self._http_client.post(url, headers=headers, json=json)
                if response.status_code < 500 or attempt == 2:
                    return response
            except Exception:
                if attempt == 2:
                    raise
        raise RuntimeError("Result delivery exhausted")

    def _download(self, url: str, archive: Path, claimed: dict[str, Any]) -> None:
        maximum = 150 * 1024 * 1024
        digest = hashlib.sha256()
        total = 0
        def consume(response: Any, chunks: Iterable[bytes]) -> None:
            nonlocal total
            if not 200 <= response.status_code < 300:
                raise RuntimeError(f"Package download failed (HTTP {response.status_code})")
            length = response.headers.get("content-length")
            if length is not None and int(length) > maximum:
                raise reconstruct.InvalidPackage("capture exceeds download limit")
            with archive.open("wb") as output:
                for chunk in chunks:
                    total += len(chunk)
                    if total > maximum:
                        raise reconstruct.InvalidPackage("capture exceeds download limit")
                    digest.update(chunk)
                    output.write(chunk)
            if length is not None and total != int(length):
                raise RuntimeError("Package download truncated")
        stream = getattr(self._http_client, "stream", None)
        if stream is not None:
            with stream("GET", url) as response:
                consume(response, response.iter_bytes(chunk_size=1024 * 1024))
        else:  # Injectable legacy HTTP doubles; production httpx always streams.
            response = self._http_client.get(url)
            consume(response, [response.content])
        if claimed.get("size_bytes") is not None and total != claimed["size_bytes"]:
            raise reconstruct.InvalidPackage("capture size differs from claim")
        if claimed.get("package_sha256") and digest.hexdigest() != claimed["package_sha256"]:
            raise reconstruct.InvalidPackage("capture checksum differs from claim")

    def _suggest(
        self, package_dir: Path, result: reconstruct.ReconstructionResult
    ) -> tuple[dict[str, Any] | None, list[str]]:
        """Class suggestions for the depth volumes; they never fail the job."""
        # Schema 2 results carry their suggestions already (their frames were temporary).
        if hasattr(result, "volume_suggestions"):
            suggestions: dict[str, Any] | None = getattr(result, "volume_suggestions")  # noqa: B009
            return suggestions, []
        try:
            return self._labeler(package_dir, result.volume_views), []
        except DetectorUnavailable:
            return None, [WARNING_DETECTOR_UNAVAILABLE]
        except Exception:  # noqa: BLE001 - suggestions are optional; do not leak exception text
            return None, [WARNING_LABELING_FAILED]

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
    logging.basicConfig(level=logging.WARNING)
    # Enable only bounded pipeline telemetry, not HTTP-client INFO logs (signed URLs).
    logging.getLogger("reconstruct_video").setLevel(logging.INFO)
    LOGGER.setLevel(logging.INFO)
    endpoint_url = os.environ.get("SQS_ENDPOINT_URL", "")
    if not endpoint_url:
        raise RuntimeError("SQS_ENDPOINT_URL is required; this worker does not use AWS")
    validate_local_endpoint(endpoint_url)
    service_token = os.environ.get("RECONSTRUCTION_WORKER_TOKEN", "")
    if not service_token:
        raise RuntimeError("RECONSTRUCTION_WORKER_TOKEN is required")

    # Floci is the only allowed endpoint. A clean deployment must not wait for a
    # first API publication to create the queue before the consumer can start.
    import boto3
    import httpx

    queue_name = os.environ.get("RECONSTRUCTION_QUEUE_NAME", "roomforge-local-reconstruction")
    boto3.client("sqs", endpoint_url=endpoint_url,
                 region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
                 aws_access_key_id=LOCAL_AWS_ACCESS_KEY_ID,
                 aws_secret_access_key=LOCAL_AWS_SECRET_ACCESS_KEY).create_queue(QueueName=queue_name)
    queue = SqsMessageQueue(
        queue_name=queue_name,
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
            result_cache=Path(os.environ.get("RECONSTRUCTION_RESULT_CACHE", "/cache/reconstruction")),
            cache_retention_seconds=int(os.environ.get("RECONSTRUCTION_CACHE_RETENTION_SECONDS", "2592000")),
            cache_max_bytes=int(os.environ.get("RECONSTRUCTION_CACHE_MAX_BYTES", "134217728")),
        )
        # Import before accepting work so this record identifies the code loaded
        # by the consumer, even when the read-only source bind later changes.
        from reconstruct_video import SOURCE_SHA256

        LOGGER.info("F07 worker ready: %s", json.dumps({
            "video_source_sha256": SOURCE_SHA256,
            "consumer_source_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "job_diagnostic": "F07 reconstruction diagnostic",
        }, sort_keys=True))
        while True:
            try:
                if not worker.run_once():
                    time.sleep(1)
            except Exception:  # noqa: BLE001
                # Do not include exception text: signed URLs and service values are sensitive.
                LOGGER.warning(
                    "Reconstruction processing failed; the delivery remains available for retry"
                )
                time.sleep(1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
