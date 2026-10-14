"""Detection job orchestration (F08.4).

One job per listing photo and model version.

**Why there is no savepoint here.** A first implementation wrapped the insert in
``session.begin_nested()`` to survive a lost race on the unique key. That is
wrong with the pysqlite driver: releasing the outermost SAVEPOINT commits the
SQLite transaction, so the row survived the rollback that the caller's
transaction performed and a job could outlive a failed publish. Worse, it made
the persist/publish window look closed when it was not.

**What replaces it.** A database and a queue cannot be committed together, so
this code does not pretend otherwise:

1. the job is inserted with ``enqueued_at`` unset;
2. the message is published;
3. ``enqueued_at`` is set only when the publish succeeded.

If the publish fails, the job is still committed as ``pending`` with
``enqueued_at`` unset, the caller is told it was not queued, and the next
repeated request — or the recovery sweep — republishes it. A message that
outlives a lost commit race refers to a job that does not exist, and the worker
drops it instead of retrying forever.
"""

from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from sqlalchemy.orm import Session

from app.modules.catalog.models import ListingPhoto
from app.modules.catalog.photos import lock_staff_listing
from app.modules.detection.job_queue import MESSAGE_VERSION, JobMessage, JobQueue
from app.modules.detection.models import DetectionJob, dedupe_key_for

PHOTO_STATUS_CONFIRMED = "confirmed"
STATUS_PENDING = "pending"


class DetectionListingNotFoundError(LookupError):
    """The listing does not exist for that agency."""


class DetectionPhotoNotFoundError(LookupError):
    """The photo does not belong to that listing."""


class DetectionPhotoNotConfirmedError(RuntimeError):
    """Only a confirmed photo can be detected: an upload grant may have expired."""


def find_job(
    session: Session, *, agency_id: str, listing_id: str, photo_id: str
) -> DetectionJob | None:
    return (
        session.query(DetectionJob)
        .filter(
            DetectionJob.agency_id == agency_id,
            DetectionJob.listing_id == listing_id,
            DetectionJob.photo_id == photo_id,
        )
        .one_or_none()
    )


def list_jobs(session: Session, *, agency_id: str, listing_id: str) -> list[DetectionJob]:
    return (
        session.query(DetectionJob)
        .filter(DetectionJob.agency_id == agency_id, DetectionJob.listing_id == listing_id)
        .order_by(DetectionJob.created_at, DetectionJob.id)
        .all()
    )


def _find_by_dedupe_key(session: Session, dedupe_key: str) -> DetectionJob | None:
    return (
        session.query(DetectionJob).filter(DetectionJob.dedupe_key == dedupe_key).one_or_none()
    )


def _find_photo(
    session: Session, *, agency_id: str, listing_id: str, photo_id: str
) -> ListingPhoto | None:
    return (
        session.query(ListingPhoto)
        .filter(
            ListingPhoto.id == photo_id,
            ListingPhoto.listing_id == listing_id,
            ListingPhoto.agency_id == agency_id,
        )
        .one_or_none()
    )


def _publish(job: DetectionJob, job_queue: JobQueue, now: datetime) -> bool:
    """Publish the job. Returns whether the queue accepted the message."""
    try:
        job_queue.publish(
            JobMessage(
                version=MESSAGE_VERSION,
                job_id=job.id,
                photo_id=job.photo_id,
                object_key=job.object_key,
                model_id=job.model_id,
                attempt=job.attempts + 1,
            )
        )
    except Exception:  # any queue failure means "not queued", never a lost job
        return False
    job.enqueued_at = now
    return True


def request_detection_job(
    session: Session,
    *,
    job_queue: JobQueue,
    agency_id: str,
    listing_id: str,
    photo_id: str,
    model_id: str,
    now: datetime,
) -> tuple[DetectionJob, bool, bool]:
    """Create the job for a photo, or replay the existing one.

    Returns ``(job, created, queued)``. ``created`` is False when the job already
    existed, and ``queued`` is False when the queue refused the message — in
    which case the job is still persisted and awaits republication.
    """
    listing = lock_staff_listing(session, agency_id=agency_id, listing_id=listing_id)
    if listing is None:
        raise DetectionListingNotFoundError(listing_id)

    photo = _find_photo(session, agency_id=agency_id, listing_id=listing_id, photo_id=photo_id)
    if photo is None:
        raise DetectionPhotoNotFoundError(photo_id)
    if photo.status != PHOTO_STATUS_CONFIRMED:
        raise DetectionPhotoNotConfirmedError(photo_id)

    dedupe_key = dedupe_key_for(photo_id, model_id)
    existing = _find_by_dedupe_key(session, dedupe_key)
    if existing is not None:
        # A job that was never enqueued is republished on the next request: this
        # is the cheap half of the reconciliation for the persist/publish window.
        if existing.enqueued_at is None and existing.status == STATUS_PENDING:
            return existing, False, _publish(existing, job_queue, now)
        return existing, False, True

    job = DetectionJob(
        id=str(uuid4()),
        agency_id=agency_id,
        listing_id=listing_id,
        photo_id=photo_id,
        object_key=photo.object_key,
        model_id=model_id,
        dedupe_key=dedupe_key,
        status=STATUS_PENDING,
        attempts=0,
        created_at=now,
    )
    session.add(job)
    queued = _publish(job, job_queue, now)
    return job, True, queued
