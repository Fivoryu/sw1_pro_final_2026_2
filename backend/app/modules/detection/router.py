"""Staff routes for detection jobs (F08.4).

These routes let agency staff ask for the detection of a confirmed listing photo
and read the resulting job states. They never write commercial inventory.
"""

from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.modules.catalog.router import _require_listing_editor  # pyright: ignore[reportPrivateUsage]
from app.modules.detection.job_queue import JobQueue
from app.modules.detection.models import (
    DETECTION_JOB_STATUS_COMPLETED,
    DETECTION_JOB_STATUS_FAILED,
    DETECTION_JOB_STATUS_PENDING,
    DETECTION_JOB_STATUS_RUNNING,
    DetectionJob,
)
from app.modules.detection.schemas import (
    DetectionJobFailure,
    DetectionJobList,
    DetectionJobResponse,
    DetectionResultPayload,
    DetectionWorkerClaimResponse,
)
from app.modules.detection.service import (
    DetectionListingNotFoundError,
    DetectionPhotoNotConfirmedError,
    DetectionPhotoNotFoundError,
    find_job,
    list_jobs,
    publish_pending_detection_job,
    request_detection_job,
)
from app.modules.identity.session import ActiveStaff, get_active_staff

router = APIRouter(
    prefix="/api/v1/staff/agencies/{agency_id}/listings/{listing_id}",
    tags=["detection-jobs"],
)

_LISTING_NOT_FOUND = "Listing not found"
_PHOTO_NOT_FOUND = "Photo not found"
_PHOTO_NOT_CONFIRMED = "Only a confirmed photo can be detected"
_ALREADY_EXISTS = "A detection job already exists for this photo and model"
_QUEUE_UNAVAILABLE = "Detection queue is unavailable"
_WORKER_AUTH_UNAVAILABLE = "Detection worker authentication is not configured"
_WORKER_UNAUTHORIZED = "Detection worker authentication failed"
_WORKER_JOB_NOT_FOUND = "Detection job not found"
_WORKER_JOB_NOT_CLAIMABLE = "Detection job is not running"
_WORKER_STALE_CLAIM = "Detection job claim is no longer current"
_WORKER_RESULT_MODEL_MISMATCH = "Detection result model does not match the job"


def _require_detection_worker(
    request: Request,
    authorization: str | None = Header(default=None),
) -> None:
    """Authenticate the API-only worker without ever logging its service token."""
    expected = request.app.state.settings.detection_worker_token
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


def _session_factory(request: Request) -> sessionmaker[Session]:
    return request.app.state.session_factory


def _job_queue(request: Request) -> JobQueue:
    queue: JobQueue | None = request.app.state.job_queue
    if queue is None:
        raise HTTPException(status_code=503, detail=_QUEUE_UNAVAILABLE)
    return queue


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def job_response(job: DetectionJob) -> DetectionJobResponse:
    return DetectionJobResponse(
        job_id=job.id,
        photo_id=job.photo_id,
        model_id=job.model_id,
        status=job.status,
        attempts=job.attempts,
        created_at=_as_utc(job.created_at),
        started_at=_as_utc(job.started_at) if job.started_at else None,
        finished_at=_as_utc(job.finished_at) if job.finished_at else None,
        result=job.result,
        failure_reason=job.failure_reason,
    )


@router.post(
    "/photos/{photo_id}/detections",
    status_code=201,
    response_model=DetectionJobResponse,
)
def request_detection(
    agency_id: str,
    listing_id: str,
    photo_id: str,
    request: Request,
    response: Response,
    staff: ActiveStaff = Depends(get_active_staff),
) -> DetectionJobResponse:
    """Create the detection job for a photo, or replay the existing one.

    The job transaction commits before publication. If the queue refuses the
    message, the committed pending job remains available to a later request or
    recovery sweep. Losing the race for the dedupe key is replayed, not failed.
    """
    _require_listing_editor(staff, agency_id)
    queue = _job_queue(request)
    settings = request.app.state.settings
    session_factory = _session_factory(request)
    try:
        with session_factory.begin() as session:
            job, created, needs_publish = request_detection_job(
                session,
                agency_id=agency_id,
                listing_id=listing_id,
                photo_id=photo_id,
                model_id=settings.detection_model_id,
                now=request.app.state.clock(),
            )
            payload = job_response(job)
    except IntegrityError:
        # Another request created the same job between the read and the commit.
        with session_factory() as session:
            winner = find_job(
                session, agency_id=agency_id, listing_id=listing_id, photo_id=photo_id
            )
            if winner is None:
                raise HTTPException(status_code=409, detail=_ALREADY_EXISTS) from None
            payload = job_response(winner)
            needs_publish = (
                winner.status == DETECTION_JOB_STATUS_PENDING and winner.enqueued_at is None
            )
        created = False
    except DetectionListingNotFoundError as error:
        raise HTTPException(status_code=404, detail=_LISTING_NOT_FOUND) from error
    except DetectionPhotoNotFoundError as error:
        raise HTTPException(status_code=404, detail=_PHOTO_NOT_FOUND) from error
    except DetectionPhotoNotConfirmedError as error:
        raise HTTPException(status_code=409, detail=_PHOTO_NOT_CONFIRMED) from error

    if not created:
        response.status_code = 200
    if needs_publish and not publish_pending_detection_job(
        session_factory,
        queue,
        job_id=payload.job_id,
        now=request.app.state.clock(),
    ):
        raise HTTPException(status_code=503, detail=_QUEUE_UNAVAILABLE)
    return payload


@router.get("/detections", response_model=DetectionJobList)
def list_detection_jobs(
    agency_id: str,
    listing_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> DetectionJobList:
    """Every detection job of one listing, with its state and result."""
    _require_listing_editor(staff, agency_id)
    with _session_factory(request)() as session:
        jobs = list_jobs(session, agency_id=agency_id, listing_id=listing_id)
        return DetectionJobList(jobs=[job_response(job) for job in jobs])


worker_router = APIRouter(
    prefix="/api/v1/detection/jobs",
    tags=["detection-worker"],
    dependencies=[Depends(_require_detection_worker)],
)


@worker_router.post("/{job_id}/claim", response_model=DetectionWorkerClaimResponse)
def claim_detection_job(job_id: str, request: Request) -> DetectionWorkerClaimResponse:
    """Atomically lease a pending job and sign only its referenced image."""
    settings = request.app.state.settings
    now = request.app.state.clock()
    claim_token = secrets.token_urlsafe(32)
    download_url: str | None = None
    with _session_factory(request).begin() as session:
        claimed = (
            session.query(DetectionJob)
            .filter(
                DetectionJob.id == job_id,
                DetectionJob.status == DETECTION_JOB_STATUS_PENDING,
            )
            .update(
                {
                    DetectionJob.status: DETECTION_JOB_STATUS_RUNNING,
                    DetectionJob.lease_expires_at: now
                    + timedelta(seconds=settings.detection_lease_seconds),
                    DetectionJob.started_at: now,
                    DetectionJob.failure_reason: None,
                    DetectionJob.claim_token: claim_token,
                },
                synchronize_session=False,
            )
        )
        job = session.get(DetectionJob, job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=_WORKER_JOB_NOT_FOUND)
        if claimed:
            storage = getattr(
                request.app.state,
                "worker_photo_storage",
                request.app.state.photo_storage,
            )
            if storage is None:
                raise HTTPException(status_code=503, detail="Photo storage is not configured")
            try:
                download_url = storage.presign_download(
                    job.object_key, expires_in=settings.detection_lease_seconds
                )
            except Exception:
                raise HTTPException(status_code=503, detail="Photo storage is unavailable") from None
        return DetectionWorkerClaimResponse(
            job_id=job.id,
            photo_id=job.photo_id,
            object_key=job.object_key,
            model_id=job.model_id,
            status=job.status,
            attempts=job.attempts,
            claim_token=claim_token if claimed else None,
            download_url=download_url,
        )


@worker_router.post("/{job_id}/complete", response_model=DetectionJobResponse)
def complete_detection_job(
    job_id: str,
    result: DetectionResultPayload,
    request: Request,
) -> DetectionJobResponse:
    """Persist one inference result; a repeated completion returns the first."""
    with _session_factory(request).begin() as session:
        job = (
            session.query(DetectionJob)
            .filter(DetectionJob.id == job_id)
            .with_for_update()
            .one_or_none()
        )
        if job is None:
            raise HTTPException(status_code=404, detail=_WORKER_JOB_NOT_FOUND)
        if job.claim_token is None or not secrets.compare_digest(
            job.claim_token, result.claim_token
        ):
            raise HTTPException(status_code=409, detail=_WORKER_STALE_CLAIM)
        if job.status == DETECTION_JOB_STATUS_COMPLETED:
            return job_response(job)
        if job.status != DETECTION_JOB_STATUS_RUNNING:
            raise HTTPException(status_code=409, detail=_WORKER_JOB_NOT_CLAIMABLE)
        if result.model_id != job.model_id:
            raise HTTPException(status_code=409, detail=_WORKER_RESULT_MODEL_MISMATCH)
        job.status = DETECTION_JOB_STATUS_COMPLETED
        job.result = result.model_dump(mode="json", exclude={"claim_token"})
        job.failure_reason = None
        job.lease_expires_at = None
        job.finished_at = request.app.state.clock()
        return job_response(job)


@worker_router.post("/{job_id}/fail", response_model=DetectionJobResponse)
def fail_detection_job(
    job_id: str,
    failure: DetectionJobFailure,
    request: Request,
) -> DetectionJobResponse:
    """Consume one failed attempt, republish while bounded retries remain."""
    settings = request.app.state.settings
    now = request.app.state.clock()
    queue: JobQueue | None = request.app.state.job_queue
    should_publish = False
    with _session_factory(request).begin() as session:
        job = (
            session.query(DetectionJob)
            .filter(DetectionJob.id == job_id)
            .with_for_update()
            .one_or_none()
        )
        if job is None:
            raise HTTPException(status_code=404, detail=_WORKER_JOB_NOT_FOUND)
        if job.claim_token is None or not secrets.compare_digest(
            job.claim_token, failure.claim_token
        ):
            raise HTTPException(status_code=409, detail=_WORKER_STALE_CLAIM)
        if job.status == DETECTION_JOB_STATUS_RUNNING:
            job.attempts += 1
            job.failure_reason = failure.reason
            job.lease_expires_at = None
            if job.attempts >= settings.detection_max_attempts:
                job.status = DETECTION_JOB_STATUS_FAILED
                job.finished_at = now
            else:
                job.status = DETECTION_JOB_STATUS_PENDING
                job.enqueued_at = None
                job.claim_token = None
                should_publish = True
        elif job.status not in {
            DETECTION_JOB_STATUS_COMPLETED,
            DETECTION_JOB_STATUS_FAILED,
        }:
            raise HTTPException(status_code=409, detail=_WORKER_JOB_NOT_CLAIMABLE)
        payload = job_response(job)

    if should_publish:
        if queue is None or not publish_pending_detection_job(
            _session_factory(request), queue, job_id=job_id, now=now
        ):
            raise HTTPException(status_code=503, detail=_QUEUE_UNAVAILABLE)
    return payload
