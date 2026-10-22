"""Detection job model (F08.4).

The job state machine has a single writer — the API — and this table's
constraints are the last line of defence against a duplicate job, because the
queue may deliver the same message more than once.

Deliberately **no foreign keys**: the retention policy for results is not
decided yet, and deleting a listing photo must keep working. A job is an
independent record of what was asked, not a child that may block a deletion.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import uuid4

from sqlalchemy import (
    JSON,
    CheckConstraint,
    DateTime,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

DETECTION_JOB_STATES: tuple[str, ...] = ("pending", "running", "completed", "failed")

DETECTION_JOB_STATUS_PENDING = "pending"
DETECTION_JOB_STATUS_RUNNING = "running"
DETECTION_JOB_STATUS_COMPLETED = "completed"
DETECTION_JOB_STATUS_FAILED = "failed"


def dedupe_key_for(photo_id: str, model_id: str) -> str:
    """The key that makes a second job for the same photo and model impossible."""
    return f"{photo_id}:{model_id}"


class FurnitureReview(Base):
    """Append-only human decision, independent of photo/result retention."""

    __tablename__ = "furniture_review"
    __table_args__ = (
        UniqueConstraint("job_id", "detection_index", name="uq_furniture_review_detection"),
        UniqueConstraint("capture_id", "object_id", name="uq_furniture_review_volume"),
        CheckConstraint("action IN ('manual', 'confirmed', 'rejected')", name="ck_furniture_review_action"),
        Index("ix_furniture_review_listing", "listing_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    agency_id: Mapped[str] = mapped_column(String(36), nullable=False)
    listing_id: Mapped[str] = mapped_column(String(36), nullable=False)
    job_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    detection_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # Alternative reference (F08 x F07.7): a class suggestion for a reconstructed volume.
    capture_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    object_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    action: Mapped[str] = mapped_column(String(16), nullable=False)
    extra_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    request_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    snapshot: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    actor_id: Mapped[str] = mapped_column(String(36), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class DetectionJob(Base):
    """One asynchronous detection run over one listing photo."""

    __tablename__ = "detection_job"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending', 'running', 'completed', 'failed')",
            name="ck_detection_job_status",
        ),
        CheckConstraint("attempts >= 0", name="ck_detection_job_attempts"),
        UniqueConstraint("dedupe_key", name="uq_detection_job_dedupe_key"),
        Index("ix_detection_job_status_lease_expires_at", "status", "lease_expires_at"),
        Index("ix_detection_job_listing_id", "listing_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    agency_id: Mapped[str] = mapped_column(String(36), nullable=False)
    listing_id: Mapped[str] = mapped_column(String(36), nullable=False)
    photo_id: Mapped[str] = mapped_column(String(36), nullable=False)
    object_key: Mapped[str] = mapped_column(String(255), nullable=False)
    model_id: Mapped[str] = mapped_column(String(64), nullable=False)
    dedupe_key: Mapped[str] = mapped_column(String(160), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    lease_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    claim_token: Mapped[str | None] = mapped_column(String(64), nullable=True)
    result: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    failure_reason: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    enqueued_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
