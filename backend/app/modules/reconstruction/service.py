"""Capture package orchestration (F07.7).

The persist/publish window is handled exactly like the detection jobs: the capture
is committed as ``queued`` with ``enqueued_at`` unset, the message is published only
after that commit, and ``enqueued_at`` is recorded in a second transaction when the
publish succeeded. A failed publish leaves a committed ``queued`` capture that a
repeated ``complete`` or the recovery sweep republishes.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from datetime import datetime, timedelta

from sqlalchemy import or_, update
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import DETECTION_LEASE_SECONDS_DEFAULT
from app.modules.catalog.photo_storage import PhotoStorage
from app.modules.reconstruction.job_queue import (
    MESSAGE_VERSION,
    ReconstructionMessage,
    ReconstructionQueue,
)
from app.modules.reconstruction.models import (
    CAPTURE_FAILED,
    CAPTURE_PROCESSING,
    CAPTURE_QUEUED,
    ListingCapture,
)

LOGGER = logging.getLogger("roomforge.reconstruction")
RETENTION_BATCH_SIZE = 100


def capture_object_key(agency_id: str, listing_id: str, capture_id: str) -> str:
    return f"agencies/{agency_id}/listings/{listing_id}/captures/{capture_id}.zip"


def find_capture(
    session: Session, *, agency_id: str, listing_id: str, capture_id: str, lock: bool = False
) -> ListingCapture | None:
    query = session.query(ListingCapture).filter(
        ListingCapture.id == capture_id,
        ListingCapture.agency_id == agency_id,
        ListingCapture.listing_id == listing_id,
    )
    return (query.with_for_update() if lock else query).one_or_none()


def _message_for(capture: ListingCapture, *, generation: int) -> ReconstructionMessage:
    return ReconstructionMessage(
        version=MESSAGE_VERSION, job_id=capture.job_id, attempt=generation + 1
    )


def _mark_enqueued(
    session_factory: sessionmaker[Session], *, job_id: str, generation: int, enqueued_at: datetime
) -> bool:
    with session_factory.begin() as session:
        result = session.connection().execute(
            update(ListingCapture)
            .where(
                ListingCapture.job_id == job_id,
                ListingCapture.attempts == generation,
                ListingCapture.status == CAPTURE_QUEUED,
                ListingCapture.enqueued_at.is_(None),
            )
            .values(enqueued_at=enqueued_at)
        )
    if result.rowcount == 1:
        return True
    # Someone else moved the capture on (claimed it, or republished a newer attempt).
    with session_factory() as session:
        capture = session.query(ListingCapture).filter(ListingCapture.job_id == job_id).one_or_none()
        if capture is None or capture.attempts < generation:
            return False
        if capture.status == CAPTURE_QUEUED:
            return capture.attempts > generation or capture.enqueued_at is not None
        return True


def publish_queued_capture(
    session_factory: sessionmaker[Session],
    queue: ReconstructionQueue,
    *,
    job_id: str,
    clock: Callable[[], datetime],
) -> bool:
    """Publish a committed queued capture, then record the successful enqueue."""
    with session_factory() as session:
        capture = (
            session.query(ListingCapture).filter(ListingCapture.job_id == job_id).one_or_none()
        )
        if capture is None:
            return False
        if capture.status != CAPTURE_QUEUED or capture.enqueued_at is not None:
            return True
        generation = capture.attempts
        message = _message_for(capture, generation=generation)
    try:
        queue.publish(message)
    except Exception:  # any queue failure leaves the committed capture recoverable
        return False
    return _mark_enqueued(session_factory, job_id=job_id, generation=generation, enqueued_at=clock())


def run_reconstruction_recovery_sweep(
    session_factory: sessionmaker[Session],
    queue: ReconstructionQueue | None,
    *,
    now: datetime,
    max_attempts: int,
    pending_republish_after_seconds: int = DETECTION_LEASE_SECONDS_DEFAULT,
) -> int:
    """Recover expired leases and stale queued deliveries; bounded by ``max_attempts``.

    A queued capture is eligible when it was never marked enqueued or its marker is at
    least one lease interval old. Before publishing, the marker is cleared so a failed
    publish stays recoverable by the next sweep.
    """
    if max_attempts < 1:
        raise ValueError("max_attempts must be positive")
    if pending_republish_after_seconds < 1:
        raise ValueError("pending_republish_after_seconds must be positive")

    messages: dict[str, tuple[ReconstructionMessage, int]] = {}
    with session_factory.begin() as session:
        expired = (
            session.query(ListingCapture)
            .filter(
                ListingCapture.status == CAPTURE_PROCESSING,
                ListingCapture.lease_expires_at.is_not(None),
                ListingCapture.lease_expires_at <= now,
            )
            .with_for_update()
            .all()
        )
        cutoff = now - timedelta(seconds=pending_republish_after_seconds)
        stale_queued = (
            session.query(ListingCapture)
            .filter(
                ListingCapture.status == CAPTURE_QUEUED,
                or_(
                    ListingCapture.enqueued_at.is_(None),
                    ListingCapture.enqueued_at <= cutoff,
                ),
            )
            .with_for_update()
            .all()
        )
        for capture, reason in (
            *((c, "Worker lease expired after {n} attempts without completion") for c in expired),
            *((c, "Reconstruction delivery was not claimed after {n} attempts") for c in stale_queued),
        ):
            capture.attempts += 1
            capture.lease_expires_at = None
            capture.claim_token = None
            capture.enqueued_at = None
            if capture.attempts >= max_attempts:
                capture.status = CAPTURE_FAILED
                capture.failure_reason = reason.format(n=capture.attempts)
                capture.finished_at = now
                continue
            capture.status = CAPTURE_QUEUED
            capture.failure_reason = None
            messages.setdefault(
                capture.job_id,
                (_message_for(capture, generation=capture.attempts), capture.attempts),
            )
        recovered = len(expired) + len(stale_queued)

    for message, generation in messages.values():
        if queue is None:
            LOGGER.warning("Reconstruction recovery sweep could not publish a job message")
            continue
        try:
            queue.publish(message)
        except Exception:
            LOGGER.warning("Reconstruction recovery sweep could not publish a job message")
            continue
        if not _mark_enqueued(
            session_factory, job_id=message.job_id, generation=generation, enqueued_at=now
        ):
            LOGGER.warning("Reconstruction recovery sweep could not mark a job as enqueued")
    return recovered


def run_capture_retention_sweep(
    session_factory: sessionmaker[Session],
    storage: PhotoStorage,
    *,
    now: datetime,
    batch_size: int = RETENTION_BATCH_SIZE,
) -> int:
    """Delete the stored package of every capture whose frames are due.

    Frames are due when the capture was accepted, or 30 days after upload. The
    ``scene_draft`` and the capture record are kept. A capture being processed is
    skipped, and a failed deletion is retried by the next sweep.
    """
    with session_factory() as session:
        due_ids = [
            row[0]
            for row in session.query(ListingCapture.id)
            .filter(
                ListingCapture.frames_deleted_at.is_(None),
                ListingCapture.status != CAPTURE_PROCESSING,
                ListingCapture.frames_delete_after <= now,
            )
            .order_by(ListingCapture.frames_delete_after)
            .limit(batch_size)
            .all()
        ]
    deleted = 0
    for capture_id in due_ids:
        with session_factory.begin() as session:
            capture = (
                session.query(ListingCapture)
                .filter(ListingCapture.id == capture_id)
                .with_for_update()
                .one_or_none()
            )
            if capture is None or capture.frames_deleted_at is not None:
                continue
            try:
                storage.delete(capture.object_key)
            except Exception:  # keep the record; the next sweep retries
                LOGGER.warning("Capture package deletion failed; the next sweep will retry")
                continue
            capture.frames_deleted_at = now
            deleted += 1
    return deleted
