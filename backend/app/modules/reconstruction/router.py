"""Staff and worker routes for capture package reconstruction (F07.7).

Contract: docs/api/f07-capture-package.md. The staff routes share the agency
isolation of the catalog staff routes; the worker routes mirror the detection
worker (service token, claim token, lease, bounded retries) with the claim token
carried in the ``X-Reconstruction-Claim-Token`` header.
"""

from __future__ import annotations

import secrets
import hashlib
from datetime import datetime, timedelta, timezone
from typing import Annotated, Any
from uuid import uuid4

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.modules.catalog.photo_storage import PhotoStorage, PhotoTooLargeError
from app.modules.catalog.photos import lock_staff_listing
from app.modules.catalog.router import (  # pyright: ignore[reportPrivateUsage]
    _require_listing_editor,
    _scene_error_response,
    _scene_validation_detail,
)
from app.modules.catalog.schemas import ListingSceneDocument
from app.modules.catalog.models import ListingScene
from app.modules.catalog.service import (
    InvalidSceneIntegrityError, validate_scene_integrity, require_metric_scene, scene_etag,
)
from app.modules.reconstruction.package import inspect_package
from app.modules.identity.session import ActiveStaff, get_active_staff
from app.modules.reconstruction.job_queue import ReconstructionQueue
from app.modules.reconstruction.models import (
    CAPTURE_ACCEPTED,
    CAPTURE_AWAITING_UPLOAD,
    CAPTURE_COMPLETED,
    CAPTURE_FAILED,
    CAPTURE_PROCESSING,
    CAPTURE_QUEUED,
    ListingCapture,
)
from app.modules.reconstruction.schemas import (
    CaptureList,
    CaptureRegistered,
    CaptureRegistration,
    CaptureResponse,
    CaptureStatusOnly,
    ReconstructionClaimResponse,
    ReconstructionFailure,
    ReconstructionResult,
)
from app.modules.reconstruction.service import (
    capture_object_key,
    find_capture,
    publish_queued_capture,
)

UPLOAD_URL_SECONDS = 900
UPLOAD_CONTENT_TYPE = "application/zip"

_LISTING_NOT_FOUND = "Listing not found"
_CAPTURE_NOT_FOUND = "Capture not found"
_CAPTURE_ID_CONFLICT = "Capture id is already used by another listing"
_NOT_COMPLETED = "Only a completed capture can be accepted"
_STORAGE_UNAVAILABLE = "Capture storage is unavailable"
_QUEUE_UNAVAILABLE = "Reconstruction queue is unavailable"
_WORKER_AUTH_UNAVAILABLE = "Reconstruction worker authentication is not configured"
_WORKER_UNAUTHORIZED = "Reconstruction worker authentication failed"
_WORKER_JOB_NOT_FOUND = "Reconstruction job not found"
_WORKER_JOB_NOT_CLAIMABLE = "Reconstruction job is not running"
_WORKER_STALE_CLAIM = "Reconstruction job claim is no longer current"

router = APIRouter(
    prefix="/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/captures",
    tags=["captures"],
)

ClaimTokenHeader = Annotated[str, Header(alias="X-Reconstruction-Claim-Token")]


def _session_factory(request: Request) -> sessionmaker[Session]:
    return request.app.state.session_factory


def _queue(request: Request) -> ReconstructionQueue:
    queue: ReconstructionQueue | None = request.app.state.reconstruction_queue
    if queue is None:
        raise HTTPException(status_code=503, detail=_QUEUE_UNAVAILABLE)
    return queue


def _storage(request: Request) -> PhotoStorage:
    storage: PhotoStorage | None = request.app.state.photo_storage
    if storage is None:
        raise HTTPException(status_code=503, detail=_STORAGE_UNAVAILABLE)
    return storage


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def _claim_token_matches(stored: str | None, supplied: str) -> bool:
    if stored is None:
        return False
    try:
        return secrets.compare_digest(stored.encode("utf-8"), supplied.encode("utf-8"))
    except UnicodeEncodeError:
        return False


def _capture_response(capture: ListingCapture) -> CaptureResponse:
    draft = capture.scene_draft
    if draft is not None and isinstance(draft.get("scale"), dict) and draft["scale"].get("mode") == "proportional":
        # Normalize historical previews without mutating their persisted evidence on a read.
        draft = {**draft, "unit": "arbitrary"}
    return CaptureResponse(
        captureId=capture.id,
        status=capture.status,
        sceneDraft=draft,
        warnings=list(capture.warnings or []),
        failureReason=capture.failure_reason,
    )


def _require_capture(
    session: Session, agency_id: str, listing_id: str, capture_id: str, *, lock: bool = False
) -> ListingCapture:
    capture = find_capture(
        session, agency_id=agency_id, listing_id=listing_id, capture_id=capture_id, lock=lock
    )
    if capture is None:
        raise HTTPException(status_code=404, detail=_CAPTURE_NOT_FOUND)
    return capture


# --- staff ---------------------------------------------------------------------------


@router.post("", status_code=201, response_model=CaptureRegistered, response_model_by_alias=True)
def register_capture(
    agency_id: str,
    listing_id: str,
    body: CaptureRegistration,
    request: Request,
    response: Response,
    staff: ActiveStaff = Depends(get_active_staff),
) -> CaptureRegistered:
    """Register a capture (idempotent by ``captureId``) and sign its upload URL."""
    _require_listing_editor(staff, agency_id)
    settings = request.app.state.settings
    now: datetime = request.app.state.clock()
    session_factory = _session_factory(request)

    # A nullable legacy checksum can be adopted only after reconciling any
    # existing remote bytes. Storage I/O is deliberately outside row locks.
    if body.sha256 is not None:
        with session_factory() as session:
            legacy = find_capture(session, agency_id=agency_id, listing_id=listing_id,
                                  capture_id=body.capture_id)
            legacy_key = legacy.object_key if legacy is not None and legacy.package_sha256 is None else None
            legacy_size = legacy.size_bytes if legacy is not None else body.size_bytes
            legacy_status = legacy.status if legacy is not None else CAPTURE_AWAITING_UPLOAD
            if legacy is not None and (legacy_key is not None or legacy_status == CAPTURE_AWAITING_UPLOAD):
                _require_retained(legacy, now)
        if legacy_key is not None:
            try:
                existing_bytes = _storage(request).read(legacy_key, max_bytes=legacy_size)
            except PhotoTooLargeError:
                raise HTTPException(status_code=409, detail="Historical capture size differs") from None
            except Exception:
                raise HTTPException(status_code=503, detail=_STORAGE_UNAVAILABLE) from None
            if existing_bytes is not None and (len(existing_bytes) != body.size_bytes or
                                               hashlib.sha256(existing_bytes).hexdigest() != body.sha256):
                raise HTTPException(status_code=409, detail="Historical capture checksum differs")
            if existing_bytes is None and legacy_status != CAPTURE_AWAITING_UPLOAD:
                raise HTTPException(status_code=409, detail="Historical package unavailable; local copy must be retained")

    def read_or_create(session: Session) -> tuple[ListingCapture, bool]:
        if lock_staff_listing(session, agency_id=agency_id, listing_id=listing_id) is None:
            raise HTTPException(status_code=404, detail=_LISTING_NOT_FOUND)
        existing = session.get(ListingCapture, body.capture_id)
        if existing is not None:
            if existing.agency_id != agency_id or existing.listing_id != listing_id:
                raise HTTPException(status_code=409, detail=_CAPTURE_ID_CONFLICT)
            if existing.status == CAPTURE_AWAITING_UPLOAD or existing.package_manifest is None:
                _require_retained(existing, now)
            if existing.size_bytes != body.size_bytes or (
                body.sha256 is not None and existing.package_sha256 is not None
                and existing.package_sha256 != body.sha256
            ):
                raise HTTPException(status_code=409, detail="Capture metadata differs from registration")
            if body.sha256 is not None and existing.package_sha256 is None:
                # Pin an expectation, not proof of delivery. /complete still verifies
                # the remote bytes, size, manifest and checksum before acknowledgement.
                existing.package_sha256 = body.sha256
            return existing, False
        capture = ListingCapture(
            id=body.capture_id,
            agency_id=agency_id,
            listing_id=listing_id,
            object_key=capture_object_key(agency_id, listing_id, body.capture_id),
            size_bytes=body.size_bytes,
            package_sha256=body.sha256,
            status=CAPTURE_AWAITING_UPLOAD,
            attempts=0,
            created_by=staff["id"],
            created_at=now,
            frames_delete_after=now + timedelta(days=settings.capture_retention_days),
        )
        session.add(capture)
        return capture, True

    try:
        with session_factory.begin() as session:
            capture, created = read_or_create(session)
            capture_id, status, object_key = capture.id, capture.status, capture.object_key
    except IntegrityError:
        # Another request registered the same captureId between the read and the commit.
        with session_factory.begin() as session:
            capture, created = read_or_create(session)
            capture_id, status, object_key = capture.id, capture.status, capture.object_key

    if not created:
        response.status_code = 200
    upload_url: str | None = None
    expires_at: datetime | None = None
    if status == CAPTURE_AWAITING_UPLOAD:
        try:
            upload_url = _storage(request).presign_upload(
                object_key, content_type=UPLOAD_CONTENT_TYPE, expires_in=UPLOAD_URL_SECONDS
            )
        except Exception:
            raise HTTPException(status_code=503, detail=_STORAGE_UNAVAILABLE) from None
        expires_at = now + timedelta(seconds=UPLOAD_URL_SECONDS)
    return CaptureRegistered(
        captureId=capture_id, status=status, uploadUrl=upload_url, expiresAt=expires_at
    )


@router.post(
    "/{capture_id}/complete",
    status_code=202,
    response_model=CaptureStatusOnly,
    response_model_by_alias=True,
)
def complete_capture_upload(
    agency_id: str,
    listing_id: str,
    capture_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> CaptureStatusOnly:
    """Confirm the upload and enqueue the reconstruction; repeating it is a no-op."""
    _require_listing_editor(staff, agency_id)
    settings = request.app.state.settings
    now: datetime = request.app.state.clock()
    session_factory = _session_factory(request)
    # Snapshot only scalar expectations, close the read transaction before CPU/I/O.
    with session_factory() as session:
        capture = _require_capture(session, agency_id, listing_id, capture_id)
        needs_verification = (capture.status == CAPTURE_AWAITING_UPLOAD or
                              capture.package_manifest is None or capture.package_sha256 is None)
        if needs_verification:
            _require_retained(capture, now)
        expected = (capture.object_key, capture.size_bytes, capture.package_sha256)
    verified_key: str | None = None
    manifest: dict[str, Any] | None = None
    digest = expected[2]
    storage = _storage(request) if needs_verification else None
    try:
        if needs_verification:
            assert storage is not None
            try:
                data = storage.read(expected[0], max_bytes=expected[1])
            except PhotoTooLargeError:
                raise HTTPException(status_code=409, detail="Uploaded capture size differs") from None
            except Exception:
                raise HTTPException(status_code=503, detail=_STORAGE_UNAVAILABLE) from None
            if data is None or len(data) != expected[1]:
                raise HTTPException(status_code=409, detail="Uploaded capture is missing or truncated")
            digest = hashlib.sha256(data).hexdigest()
            if expected[2] is not None and expected[2] != digest:
                raise HTTPException(status_code=409, detail="Uploaded capture checksum differs")
            try:
                manifest = inspect_package(data, capture_id, listing_id)
            except ValueError as error:
                raise HTTPException(status_code=422, detail=str(error)) from None
            # Signatures for the upload key may still be valid. Workers only read a separate
            # verified snapshot for which no PUT URL is ever issued.
            # Request-private candidate: a losing CAS can delete it without deleting
            # another request's committed snapshot, even for identical bytes.
            verified_key = (expected[0] if "/verified-" in expected[0] else
                            expected[0].rsplit("/", 1)[0] + f"/verified-{digest}-{uuid4().hex}.zip")
            try:
                if verified_key != expected[0]:
                    storage.write(verified_key, data, content_type=UPLOAD_CONTENT_TYPE)
                confirmed = storage.read(verified_key, max_bytes=expected[1])
                if confirmed is None or hashlib.sha256(confirmed).hexdigest() != digest:
                    raise ValueError("Verified snapshot readback differs")
            except Exception:
                raise HTTPException(status_code=503, detail=_STORAGE_UNAVAILABLE) from None
        with session_factory.begin() as session:
            capture = _require_capture(session, agency_id, listing_id, capture_id, lock=True)
            if needs_verification:
                _require_retained(capture, request.app.state.clock())
            if verified_key is not None and (capture.package_manifest is None or capture.package_sha256 is None):
                if (capture.object_key, capture.size_bytes, capture.package_sha256) != expected:
                    raise HTTPException(status_code=409, detail="Capture changed during verification; retry")
                capture.object_key = verified_key
                capture.package_sha256 = digest
                capture.package_manifest = manifest
                if capture.status == CAPTURE_AWAITING_UPLOAD:
                    capture.status = CAPTURE_QUEUED
                    capture.uploaded_at = now
                    capture.enqueued_at = None
                    capture.frames_delete_after = now + timedelta(days=settings.capture_retention_days)
                elif capture.status == CAPTURE_QUEUED:
                    capture.enqueued_at = None # Republish verified legacy job, not a new execution.
                # Historical advanced captures retain their original deadline and state.
                committed_key = verified_key
            else:
                committed_key = capture.object_key
            needs_publish = (capture.status == CAPTURE_QUEUED and capture.enqueued_at is None
                             and capture.frames_deleted_at is None and _as_utc(capture.frames_delete_after) > now)
            payload = CaptureStatusOnly(captureId=capture.id, status=capture.status,
                                        uploadVerified=capture.package_manifest is not None)
            job_id = capture.job_id
    except Exception:
        if storage is not None and verified_key is not None and verified_key != expected[0]:
            storage.delete(verified_key)
        raise
    if storage is not None and verified_key is not None and verified_key != expected[0] and committed_key != verified_key:
        storage.delete(verified_key)
    if needs_publish and not publish_queued_capture(
        session_factory, _queue(request), job_id=job_id, clock=request.app.state.clock
    ):
        raise HTTPException(status_code=503, detail=_QUEUE_UNAVAILABLE)
    return payload


def _require_retained(capture: ListingCapture, now: datetime) -> None:
    if capture.frames_deleted_at is not None or _as_utc(capture.frames_delete_after) <= _as_utc(now):
        raise HTTPException(status_code=410, detail="Capture retention expired; retain local file and register a new capture")


@router.get("", response_model=CaptureList, response_model_by_alias=True)
def list_captures(
    agency_id: str,
    listing_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> CaptureList:
    """The listing's captures, newest first, so the panel can offer their drafts."""
    _require_listing_editor(staff, agency_id)
    with _session_factory(request).begin() as session:
        if lock_staff_listing(session, agency_id=agency_id, listing_id=listing_id) is None:
            raise HTTPException(status_code=404, detail=_LISTING_NOT_FOUND)
        captures = (
            session.query(ListingCapture)
            .filter(ListingCapture.agency_id == agency_id, ListingCapture.listing_id == listing_id)
            .order_by(ListingCapture.created_at.desc(), ListingCapture.id)
            .all()
        )
        return CaptureList(captures=[_capture_response(capture) for capture in captures])


@router.get("/{capture_id}", response_model=CaptureResponse, response_model_by_alias=True)
def get_capture(
    agency_id: str,
    listing_id: str,
    capture_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> CaptureResponse:
    _require_listing_editor(staff, agency_id)
    with _session_factory(request)() as session:
        return _capture_response(_require_capture(session, agency_id, listing_id, capture_id))


@router.post(
    "/{capture_id}/accept", response_model=CaptureResponse, response_model_by_alias=True
)
def accept_capture(
    agency_id: str,
    listing_id: str,
    capture_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
    if_match: Annotated[str | None, Header()] = None,
) -> CaptureResponse:
    """The agency kept the draft: schedule the frames for deletion. Idempotent."""
    _require_listing_editor(staff, agency_id)
    now: datetime = request.app.state.clock()
    with _session_factory(request).begin() as session:
        # Same lock order as scene replacement; a concurrent editor cannot change
        # the scene between checking evidence and shortening capture retention.
        if lock_staff_listing(session, agency_id=agency_id, listing_id=listing_id) is None:
            raise HTTPException(status_code=404, detail=_LISTING_NOT_FOUND)
        capture = _require_capture(session, agency_id, listing_id, capture_id, lock=True)
        if capture.status == CAPTURE_COMPLETED:
            if capture.package_manifest is None or capture.package_sha256 is None:
                raise HTTPException(status_code=409, detail="Verify historical package before acceptance")
            if capture.scene_draft is None:
                raise HTTPException(status_code=409, detail="Capture has no scene")
            try:
                draft = ListingSceneDocument.model_validate(capture.scene_draft)
                require_metric_scene(draft)
                if capture.package_manifest.get("schemaVersion") == 2 and draft.measurement is None:
                    raise InvalidSceneIntegrityError("Historical video lacks measurement evidence")
                # Historical video drafts have warnings but no structured scale evidence.
                if any("unidades arbitrarias" in w or "sin medida de referencia" in w.lower()
                       for w in capture.warnings or []):
                    raise InvalidSceneIntegrityError("Historical capture has no verified scale")
            except (ValidationError, InvalidSceneIntegrityError) as error:
                raise HTTPException(status_code=409, detail=str(error)) from None
            stored = session.get(ListingScene, listing_id)
            if stored is None or stored.scene.get("captureId") != capture_id:
                raise HTTPException(status_code=409, detail="Save a scene associated with this capture before acceptance")
            if if_match is not None and if_match != scene_etag(stored.revision):
                raise HTTPException(status_code=412, detail="Scene revision changed; reload before acceptance")
            try:
                persisted = ListingSceneDocument.model_validate(stored.scene)
                require_metric_scene(persisted)
                if stored.scene.get("measurement") != capture.scene_draft.get("measurement"):
                    raise InvalidSceneIntegrityError("Saved measurement evidence differs from capture")
            except (ValidationError, InvalidSceneIntegrityError) as error:
                raise HTTPException(status_code=409, detail=str(error)) from None
            capture.status = CAPTURE_ACCEPTED
            capture.accepted_at = now
            capture.frames_delete_after = min(_as_utc(capture.frames_delete_after), now)
        elif capture.status != CAPTURE_ACCEPTED:
            raise HTTPException(status_code=409, detail=_NOT_COMPLETED)
        return _capture_response(capture)


# --- worker --------------------------------------------------------------------------


def _require_reconstruction_worker(
    request: Request,
    authorization: str | None = Header(default=None),
) -> None:
    """Authenticate the API-only worker without ever logging its service token."""
    settings = request.app.state.settings
    expected = settings.reconstruction_worker_token or settings.detection_worker_token
    if not expected:
        raise HTTPException(status_code=503, detail=_WORKER_AUTH_UNAVAILABLE)
    scheme, separator, candidate = (authorization or "").partition(" ")
    if (
        not separator
        or scheme.lower() != "bearer"
        or not candidate
        or not secrets.compare_digest(candidate.encode("utf-8"), expected.encode("utf-8"))
    ):
        raise HTTPException(status_code=401, detail=_WORKER_UNAUTHORIZED)


worker_router = APIRouter(
    prefix="/api/v1/reconstruction/jobs",
    tags=["reconstruction-worker"],
    dependencies=[Depends(_require_reconstruction_worker)],
)


def _worker_status(status: str) -> str:
    return {
        CAPTURE_QUEUED: "pending",
        CAPTURE_PROCESSING: "running",
        CAPTURE_COMPLETED: "completed",
        CAPTURE_ACCEPTED: "completed",
        CAPTURE_FAILED: "failed",
    }.get(status, status)


def _lock_job(session: Session, job_id: str) -> ListingCapture:
    capture = (
        session.query(ListingCapture)
        .filter(ListingCapture.job_id == job_id)
        .with_for_update()
        .one_or_none()
    )
    if capture is None:
        raise HTTPException(status_code=404, detail=_WORKER_JOB_NOT_FOUND)
    return capture


@worker_router.post("/{job_id}/claim", response_model=ReconstructionClaimResponse)
def claim_reconstruction_job(job_id: str, request: Request) -> ReconstructionClaimResponse:
    """Atomically lease a queued job and sign the download of its package."""
    settings = request.app.state.settings
    now: datetime = request.app.state.clock()
    claim_token = secrets.token_urlsafe(32)
    claim_failure: str | None = None
    with _session_factory(request).begin() as session:
        candidate = _lock_job(session, job_id)
        if candidate.status == CAPTURE_QUEUED and (candidate.package_manifest is None or candidate.package_sha256 is None):
            raise HTTPException(status_code=409, detail="Verify historical package through /complete before claiming")
        claimed = (
            session.query(ListingCapture)
            .filter(ListingCapture.job_id == job_id, ListingCapture.status == CAPTURE_QUEUED,
                    ListingCapture.frames_deleted_at.is_(None), ListingCapture.frames_delete_after > now)
            .update(
                {
                    ListingCapture.status: CAPTURE_PROCESSING,
                    ListingCapture.lease_expires_at: now
                    + timedelta(seconds=settings.reconstruction_lease_seconds),
                    ListingCapture.started_at: now,
                    ListingCapture.failure_reason: None,
                    ListingCapture.claim_token: claim_token,
                },
                synchronize_session=False,
            )
        )
        # The proof guard loaded this row before the bulk UPDATE. Refresh its
        # identity-map state before serializing the atomic claim result.
        session.expire(candidate)
        capture = (
            session.query(ListingCapture).filter(ListingCapture.job_id == job_id).one_or_none()
        )
        if capture is None:
            raise HTTPException(status_code=404, detail=_WORKER_JOB_NOT_FOUND)
        if capture.status == CAPTURE_AWAITING_UPLOAD:
            raise HTTPException(status_code=409, detail=_WORKER_JOB_NOT_CLAIMABLE)
        download_url: str | None = None
        if claimed:
            storage: PhotoStorage | None = getattr(
                request.app.state, "worker_photo_storage", request.app.state.photo_storage
            )
            if storage is None:
                claim_failure = _STORAGE_UNAVAILABLE
            else:
                try:
                    download_url = storage.presign_download(
                        capture.object_key, expires_in=settings.reconstruction_lease_seconds
                    )
                except Exception:
                    claim_failure = _STORAGE_UNAVAILABLE
        result = ReconstructionClaimResponse(
            job_id=job_id,
            status=_worker_status(capture.status),
            claim_token=claim_token if claimed else None,
            download_url=download_url,
            capture_id=capture.id,
            listing_id=capture.listing_id,
            package_sha256=capture.package_sha256,
            size_bytes=capture.size_bytes,
            lease_seconds=settings.reconstruction_lease_seconds,
            cache_delete_after=capture.frames_delete_after,
        )
    if claim_failure is not None:
        # The claim stays committed so the worker consumes this attempt through /fail.
        raise HTTPException(
            status_code=503,
            detail=claim_failure,
            headers={"X-Reconstruction-Claim-Token": claim_token},
        )
    return result


@worker_router.post("/{job_id}/renew")
def renew_reconstruction_job(job_id: str, request: Request, claim_token: ClaimTokenHeader) -> dict[str, str]:
    now = request.app.state.clock()
    with _session_factory(request).begin() as session:
        capture = _lock_job(session, job_id)
        if (capture.status != CAPTURE_PROCESSING or
            not _claim_token_matches(capture.claim_token, claim_token) or
            capture.lease_expires_at is None or _as_utc(capture.lease_expires_at) <= now):
            raise HTTPException(status_code=409, detail=_WORKER_STALE_CLAIM)
        capture.lease_expires_at = now + timedelta(seconds=request.app.state.settings.reconstruction_lease_seconds)
    return {"status": "running"}


@worker_router.post(
    "/{job_id}/complete", response_model=CaptureResponse, response_model_by_alias=True
)
def complete_reconstruction_job(
    job_id: str,
    result: ReconstructionResult,
    request: Request,
    claim_token: ClaimTokenHeader,
) -> CaptureResponse | JSONResponse:
    """Store the validated draft; a repeated completion returns the first result."""
    # Same strict scene v2 validation and 422 shape as the staff scene PUT.
    try:
        scene = ListingSceneDocument.model_validate(result.scene_draft)
        validate_scene_integrity(scene)
    except ValidationError as error:
        return _scene_error_response(422, _scene_validation_detail(error), "scene_invalid")
    except InvalidSceneIntegrityError as error:
        return _scene_error_response(422, error.detail, "scene_invalid")

    suggestions: dict[str, Any] | None = None
    if result.volume_suggestions is not None:
        volumes = {obj.id for obj in scene.objects if obj.type == "occupancy"}
        seen: set[str] = set()
        for item in result.volume_suggestions.items:
            if item.object_id not in volumes:
                return _scene_error_response(
                    422,
                    f"volumeSuggestions objectId {item.object_id} is not an occupancy object",
                    "volume_suggestions_invalid",
                )
            if item.object_id in seen:
                return _scene_error_response(
                    422,
                    f"volumeSuggestions repeats objectId {item.object_id}",
                    "volume_suggestions_invalid",
                )
            seen.add(item.object_id)
        suggestions = result.volume_suggestions.model_dump(mode="json", by_alias=True)

    with _session_factory(request).begin() as session:
        capture = _lock_job(session, job_id)
        if not _claim_token_matches(capture.claim_token, claim_token):
            raise HTTPException(status_code=409, detail=_WORKER_STALE_CLAIM)
        if capture.status in {CAPTURE_COMPLETED, CAPTURE_ACCEPTED}:
            return _capture_response(capture)
        if capture.status != CAPTURE_PROCESSING:
            raise HTTPException(status_code=409, detail=_WORKER_JOB_NOT_CLAIMABLE)
        if capture.package_manifest and capture.package_manifest.get("schemaVersion") == 2 and scene.measurement is None:
            return _scene_error_response(422, "Video reconstruction must declare measurement provenance", "scene_invalid")
        if capture.lease_expires_at is None or _as_utc(capture.lease_expires_at) <= request.app.state.clock():
            raise HTTPException(status_code=409, detail=_WORKER_STALE_CLAIM)
        capture.status = CAPTURE_COMPLETED
        capture.scene_draft = scene.model_dump(mode="json", by_alias=True, exclude_unset=True)
        capture.warnings = list(result.warnings)
        capture.volume_suggestions = suggestions
        capture.failure_reason = None
        capture.lease_expires_at = None
        capture.finished_at = request.app.state.clock()
        return _capture_response(capture)


@worker_router.post("/{job_id}/fail", response_model=CaptureResponse, response_model_by_alias=True)
def fail_reconstruction_job(
    job_id: str,
    failure: ReconstructionFailure,
    request: Request,
    claim_token: ClaimTokenHeader,
) -> CaptureResponse:
    """Consume one failed attempt; republish while bounded retries remain."""
    settings = request.app.state.settings
    now: datetime = request.app.state.clock()
    should_publish = False
    with _session_factory(request).begin() as session:
        capture = _lock_job(session, job_id)
        if not _claim_token_matches(capture.claim_token, claim_token):
            raise HTTPException(status_code=409, detail=_WORKER_STALE_CLAIM)
        if capture.status == CAPTURE_PROCESSING:
            capture.attempts += 1
            capture.failure_reason = failure.reason
            capture.lease_expires_at = None
            if not failure.retryable or capture.attempts >= settings.reconstruction_max_attempts:
                capture.status = CAPTURE_FAILED
                capture.finished_at = now
            else:
                capture.status = CAPTURE_QUEUED
                capture.enqueued_at = None
                capture.claim_token = None
                should_publish = True
        elif capture.status not in {CAPTURE_COMPLETED, CAPTURE_ACCEPTED, CAPTURE_FAILED}:
            raise HTTPException(status_code=409, detail=_WORKER_JOB_NOT_CLAIMABLE)
        payload = _capture_response(capture)

    if should_publish:
        queue: ReconstructionQueue | None = request.app.state.reconstruction_queue
        if queue is None or not publish_queued_capture(
            _session_factory(request), queue, job_id=job_id, clock=request.app.state.clock
        ):
            raise HTTPException(status_code=503, detail=_QUEUE_UNAVAILABLE)
    return payload
