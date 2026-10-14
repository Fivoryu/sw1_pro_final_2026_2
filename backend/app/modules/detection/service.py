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

1. the job is inserted and the database transaction commits with ``enqueued_at`` unset;
2. only after that commit, the message is published;
3. ``enqueued_at`` is recorded in a second transaction only when publish succeeds.

If the publish fails, the job remains ``pending`` with ``enqueued_at`` unset,
the caller receives an error, and a repeated request or recovery sweep
republishes it. A message that outlives a failed database commit refers to a
job that does not exist, and the worker drops it instead of retrying forever.
"""

from __future__ import annotations

import logging
from datetime import datetime
from uuid import uuid4

from sqlalchemy.orm import Session, sessionmaker

from app.modules.catalog.models import ListingPhoto
from app.modules.catalog.photos import lock_staff_listing
from app.modules.detection.job_queue import MESSAGE_VERSION, JobMessage, JobQueue
from app.modules.detection.models import DetectionJob, dedupe_key_for

PHOTO_STATUS_CONFIRMED = "confirmed"
STATUS_PENDING = "pending"
LOGGER = logging.getLogger("roomforge.detection.recovery")


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


def publish_pending_detection_job(
    session_factory: sessionmaker[Session],
    job_queue: JobQueue,
    *,
    job_id: str,
    now: datetime,
) -> bool:
    """Publish a committed pending job, then record the successful enqueue."""
    with session_factory() as session:
        job = (
            session.query(DetectionJob)
            .filter(DetectionJob.id == job_id)
            .one_or_none()
        )
        if job is None:
            return False
        if job.status != STATUS_PENDING or job.enqueued_at is not None:
            return True
        message = JobMessage(
            version=MESSAGE_VERSION,
            job_id=job.id,
            photo_id=job.photo_id,
            object_key=job.object_key,
            model_id=job.model_id,
            attempt=job.attempts + 1,
        )

    try:
        job_queue.publish(message)
    except Exception:  # any queue failure leaves the committed job recoverable
        return False

    with session_factory.begin() as session:
        job = (
            session.query(DetectionJob)
            .filter(
                DetectionJob.id == job_id,
                DetectionJob.status == STATUS_PENDING,
                DetectionJob.enqueued_at.is_(None),
            )
            .with_for_update()
            .one_or_none()
        )
        if job is not None:
            job.enqueued_at = now
    return True


def run_detection_recovery_sweep(
    session_factory: sessionmaker[Session],
    job_queue: JobQueue | None,
    *,
    now: datetime,
    max_attempts: int,
) -> int:
    """Recover expired leases and republish pending jobs that were never queued.

    The state transition is committed before publishing so a worker that receives
    the message can claim the now-pending job. If publication fails, the job stays
    pending with no ``enqueued_at`` and a later sweep retries it.
    """
    if max_attempts < 1:
        raise ValueError("max_attempts must be positive")

    messages: dict[str, JobMessage] = {}
    expired_count = 0
    with session_factory.begin() as session:
        expired_jobs = (
            session.query(DetectionJob)
            .filter(
                DetectionJob.status == "running",
                DetectionJob.lease_expires_at.is_not(None),
                DetectionJob.lease_expires_at <= now,
            )
            .with_for_update()
            .all()
        )
        unqueued_jobs = (
            session.query(DetectionJob)
            .filter(
                DetectionJob.status == STATUS_PENDING,
                DetectionJob.enqueued_at.is_(None),
            )
            .with_for_update()
            .all()
        )
        expired_count = len(expired_jobs)

        for job in expired_jobs:
            if job.attempts >= max_attempts:
                job.status = "failed"
                job.failure_reason = (
                    f"Worker lease expired after {max_attempts} attempts without completion"
                )
                job.lease_expires_at = None
                job.claim_token = None
                job.finished_at = now
                continue

            job.attempts += 1
            job.lease_expires_at = None
            job.claim_token = None
            job.enqueued_at = None
            job.failure_reason = None
            if job.attempts >= max_attempts:
                job.status = "failed"
                job.failure_reason = (
                    f"Worker lease expired after {job.attempts} attempts without completion"
                )
                job.finished_at = now
                continue

            job.status = STATUS_PENDING
            messages[job.id] = JobMessage(
                version=MESSAGE_VERSION,
                job_id=job.id,
                photo_id=job.photo_id,
                object_key=job.object_key,
                model_id=job.model_id,
                attempt=job.attempts + 1,
            )

        for job in unqueued_jobs:
            if job.attempts >= max_attempts:
                job.status = "failed"
                job.failure_reason = (
                    f"Detection attempts exhausted at {max_attempts} without queue delivery"
                )
                job.claim_token = None
                job.finished_at = now
                continue
            messages.setdefault(
                job.id,
                JobMessage(
                    version=MESSAGE_VERSION,
                    job_id=job.id,
                    photo_id=job.photo_id,
                    object_key=job.object_key,
                    model_id=job.model_id,
                    attempt=job.attempts + 1,
                ),
            )

    for message in messages.values():
        if job_queue is None:
            LOGGER.warning("Detection recovery sweep could not publish a job message")
            continue
        try:
            job_queue.publish(message)
        except Exception:
            # The unqueued marker remains unset so the next sweep can retry.
            LOGGER.warning("Detection recovery sweep could not publish a job message")
            continue
        with session_factory.begin() as session:
            job = (
                session.query(DetectionJob)
                .filter(
                    DetectionJob.id == message.job_id,
                    DetectionJob.status == STATUS_PENDING,
                    DetectionJob.enqueued_at.is_(None),
                )
                .with_for_update()
                .one_or_none()
            )
            if job is not None:
                job.enqueued_at = now

    return expired_count + len(unqueued_jobs)


def request_detection_job(
    session: Session,
    *,
    agency_id: str,
    listing_id: str,
    photo_id: str,
    model_id: str,
    now: datetime,
) -> tuple[DetectionJob, bool, bool]:
    """Create the job for a photo, or replay the existing one.

    Returns ``(job, created, needs_publish)``. The caller commits the transaction
    before publishing; ``needs_publish`` is true only for a pending job whose
    ``enqueued_at`` marker is still empty.
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
        needs_publish = existing.enqueued_at is None and existing.status == STATUS_PENDING
        return existing, False, needs_publish

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
    return job, True, True
