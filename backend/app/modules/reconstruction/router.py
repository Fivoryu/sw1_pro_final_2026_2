"""Staff and worker routes for capture package reconstruction (F07.7).

Contract: docs/api/f07-capture-package.md. The staff routes share the agency
isolation of the catalog staff routes; the worker routes mirror the detection
worker (service token, claim token, lease, bounded retries) with the claim token
carried in the ``X-Reconstruction-Claim-Token`` header.
"""

from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.modules.catalog.photo_storage import PhotoStorage
from app.modules.catalog.photos import lock_staff_listing
from app.modules.catalog.router import (  # pyright: ignore[reportPrivateUsage]
    _require_listing_editor,
    _scene_error_response,
    _scene_validation_detail,
)
from app.modules.catalog.schemas import ListingSceneDocument
from app.modules.catalog.service import InvalidSceneIntegrityError, validate_scene_integrity
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
    return CaptureResponse(
        captureId=capture.id,
        status=capture.status,
        sceneDraft=capture.scene_draft,
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
    storage = _storage(request)
    settings = request.app.state.settings
    now: datetime = request.app.state.clock()
    session_factory = _session_factory(request)

    def read_or_create(session: Session) -> tuple[ListingCapture, bool]:
        if lock_staff_listing(session, agency_id=agency_id, listing_id=listing_id) is None:
            raise HTTPException(status_code=404, detail=_LISTING_NOT_FOUND)
        existing = session.get(ListingCapture, body.capture_id)
        if existing is not None:
            if existing.agency_id != agency_id or existing.listing_id != listing_id:
                raise HTTPException(status_code=409, detail=_CAPTURE_ID_CONFLICT)
            return existing, False
        capture = ListingCapture(
            id=body.capture_id,
            agency_id=agency_id,
            listing_id=listing_id,
            object_key=capture_object_key(agency_id, listing_id, body.capture_id),
            size_bytes=body.size_bytes,
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
        with session_factory() as session:
            capture, created = read_or_create(session)
            capture_id, status, object_key = capture.id, capture.status, capture.object_key

    if not created:
        response.status_code = 200
    upload_url: str | None = None
    expires_at: datetime | None = None
    if status == CAPTURE_AWAITING_UPLOAD:
        try:
            upload_url = storage.presign_upload(
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
    queue = _queue(request)
    settings = request.app.state.settings
    now: datetime = request.app.state.clock()
    session_factory = _session_factory(request)
    with session_factory.begin() as session:
        capture = _require_capture(session, agency_id, listing_id, capture_id, lock=True)
        if capture.status == CAPTURE_AWAITING_UPLOAD:
            capture.status = CAPTURE_QUEUED
            capture.uploaded_at = now
            capture.enqueued_at = None
            # Retention counts from the upload, not from the registration.
            capture.frames_delete_after = now + timedelta(days=settings.capture_retention_days)
        needs_publish = capture.status == CAPTURE_QUEUED and capture.enqueued_at is None
        payload = CaptureStatusOnly(captureId=capture.id, status=capture.status)
        job_id = capture.job_id
    if needs_publish and not publish_queued_capture(
        session_factory, queue, job_id=job_id, clock=request.app.state.clock
    ):
        raise HTTPException(status_code=503, detail=_QUEUE_UNAVAILABLE)
    return payload


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
) -> CaptureResponse:
    """The agency kept the draft: schedule the frames for deletion. Idempotent."""
    _require_listing_editor(staff, agency_id)
    now: datetime = request.app.state.clock()
    with _session_factory(request).begin() as session:
        capture = _require_capture(session, agency_id, listing_id, capture_id, lock=True)
        if capture.status == CAPTURE_COMPLETED:
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
        claimed = (
            session.query(ListingCapture)
            .filter(ListingCapture.job_id == job_id, ListingCapture.status == CAPTURE_QUEUED)
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
        )
    if claim_failure is not None:
        # The claim stays committed so the worker consumes this attempt through /fail.
        raise HTTPException(
            status_code=503,
            detail=claim_failure,
            headers={"X-Reconstruction-Claim-Token": claim_token},
        )
    return result


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

    with _session_factory(request).begin() as session:
        capture = _lock_job(session, job_id)
        if not _claim_token_matches(capture.claim_token, claim_token):
            raise HTTPException(status_code=409, detail=_WORKER_STALE_CLAIM)
        if capture.status in {CAPTURE_COMPLETED, CAPTURE_ACCEPTED}:
            return _capture_response(capture)
        if capture.status != CAPTURE_PROCESSING:
            raise HTTPException(status_code=409, detail=_WORKER_JOB_NOT_CLAIMABLE)
        capture.status = CAPTURE_COMPLETED
        capture.scene_draft = scene.model_dump(mode="json", by_alias=True, exclude_unset=True)
        capture.warnings = list(result.warnings)
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
