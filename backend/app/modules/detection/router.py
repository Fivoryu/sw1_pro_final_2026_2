"""Staff routes for detection jobs (F08.4).

These routes let agency staff ask for the detection of a confirmed listing photo
and read the resulting job states. They never write commercial inventory.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.modules.catalog.router import _require_listing_editor  # pyright: ignore[reportPrivateUsage]
from app.modules.detection.job_queue import JobQueue
from app.modules.detection.models import DetectionJob
from app.modules.detection.schemas import DetectionJobList, DetectionJobResponse
from app.modules.detection.service import (
    DetectionListingNotFoundError,
    DetectionPhotoNotConfirmedError,
    DetectionPhotoNotFoundError,
    find_job,
    list_jobs,
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

    A job is created and committed even when the queue refuses the message: it is
    then reported as not queued, and the next request or the recovery sweep
    publishes it. Losing the race for the dedupe key is replayed, not failed.
    """
    _require_listing_editor(staff, agency_id)
    queue = _job_queue(request)
    settings = request.app.state.settings
    session_factory = _session_factory(request)
    try:
        with session_factory.begin() as session:
            job, created, queued = request_detection_job(
                session,
                job_queue=queue,
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
        created, queued = False, True
    except DetectionListingNotFoundError as error:
        raise HTTPException(status_code=404, detail=_LISTING_NOT_FOUND) from error
    except DetectionPhotoNotFoundError as error:
        raise HTTPException(status_code=404, detail=_PHOTO_NOT_FOUND) from error
    except DetectionPhotoNotConfirmedError as error:
        raise HTTPException(status_code=409, detail=_PHOTO_NOT_CONFIRMED) from error

    if not created:
        response.status_code = 200
    if not queued:
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
