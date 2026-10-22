"""Capture record and reconstruction job state (F07.7).

One row is both the capture (what the agent uploaded) and its single reconstruction
job: the API is the only writer of this state machine, as in the detection module.

Capture states: ``awaiting_upload`` -> ``queued`` -> ``processing`` -> ``completed``
-> ``accepted``, or ``failed``. ``queued`` and ``processing`` are the job pending
and running states.

Deliberately **no foreign keys**: the ``scene_draft`` and the manifest record outlive
the frames, and deleting a listing must not be blocked by a capture.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import uuid4

from sqlalchemy import (
    JSON,
    BigInteger,
    CheckConstraint,
    DateTime,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

CAPTURE_AWAITING_UPLOAD = "awaiting_upload"
CAPTURE_QUEUED = "queued"
CAPTURE_PROCESSING = "processing"
CAPTURE_COMPLETED = "completed"
CAPTURE_FAILED = "failed"
CAPTURE_ACCEPTED = "accepted"


class ListingCapture(Base):
    """One uploaded capture package and its reconstruction job."""

    __tablename__ = "listing_capture"
    __table_args__ = (
        CheckConstraint(
            "status IN ('awaiting_upload', 'queued', 'processing', 'completed', "
            "'failed', 'accepted')",
            name="ck_listing_capture_status",
        ),
        CheckConstraint("attempts >= 0", name="ck_listing_capture_attempts"),
        CheckConstraint("size_bytes >= 0", name="ck_listing_capture_size"),
        UniqueConstraint("job_id", name="uq_listing_capture_job_id"),
        Index("ix_listing_capture_status_lease_expires_at", "status", "lease_expires_at"),
        Index("ix_listing_capture_listing_id", "listing_id"),
        Index(
            "ix_listing_capture_frames_due", "frames_deleted_at", "frames_delete_after"
        ),
    )

    # Client-generated captureId: the idempotency key of the registration.
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    job_id: Mapped[str] = mapped_column(String(36), nullable=False, default=lambda: str(uuid4()))
    agency_id: Mapped[str] = mapped_column(String(36), nullable=False)
    listing_id: Mapped[str] = mapped_column(String(36), nullable=False)
    object_key: Mapped[str] = mapped_column(String(255), nullable=False)
    size_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    lease_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    claim_token: Mapped[str | None] = mapped_column(String(64), nullable=True)
    scene_draft: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    warnings: Mapped[list[str] | None] = mapped_column(JSON, nullable=True)
    failure_reason: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_by: Mapped[str] = mapped_column(String(36), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    uploaded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    enqueued_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # When the package must be deleted from object storage; moved up on accept.
    frames_delete_after: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    frames_deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
