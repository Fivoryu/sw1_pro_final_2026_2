"""Persistence model for in-app notifications (F14.7)."""

from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

RECIPIENT_KINDS = ("customer", "staff")
NOTIFICATION_KINDS = (
    "chat_message",
    "chat_assigned",
    "chat_needs_admin",
    "chat_overdue",
    "reservation_status",
)


class Notification(Base):
    """One notice for one recipient; it carries ids and a kind, never message text."""

    __tablename__ = "notification"
    __table_args__ = (
        CheckConstraint("recipient_kind IN ('customer', 'staff')", name="ck_notification_recipient_kind"),
        Index("ix_notification_recipient", "recipient_kind", "recipient_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    recipient_kind: Mapped[str] = mapped_column(String(16), nullable=False)
    recipient_id: Mapped[str] = mapped_column(String(36), nullable=False)
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    conversation_id: Mapped[str | None] = mapped_column(
        ForeignKey("chat_conversation.id", ondelete="CASCADE"), nullable=True
    )
    reservation_id: Mapped[str | None] = mapped_column(
        ForeignKey("reservation.id", ondelete="CASCADE"), nullable=True
    )
    # Reservation status or similar short qualifier; never free text.
    detail: Mapped[str | None] = mapped_column(String(32), nullable=True)
    # Makes a notice idempotent, for example one overdue notice per waiting window.
    dedupe_key: Mapped[str | None] = mapped_column(String(160), nullable=True, unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
