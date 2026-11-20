"""Device registrations used to deliver push notifications (FCM)."""

from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from sqlalchemy import CheckConstraint, DateTime, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

PLATFORMS = ("android", "ios")


class DeviceToken(Base):
    """One FCM registration token owned by one customer or one staff member."""

    __tablename__ = "device_token"
    __table_args__ = (
        CheckConstraint(
            "recipient_kind IN ('customer', 'staff')", name="ck_device_token_recipient_kind"
        ),
        CheckConstraint("platform IN ('android', 'ios')", name="ck_device_token_platform"),
        UniqueConstraint("token", name="uq_device_token_token"),
        Index("ix_device_token_recipient", "recipient_kind", "recipient_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    recipient_kind: Mapped[str] = mapped_column(String(16), nullable=False)
    recipient_id: Mapped[str] = mapped_column(String(36), nullable=False)
    token: Mapped[str] = mapped_column(String(512), nullable=False)
    platform: Mapped[str] = mapped_column(String(16), nullable=False, default="android")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
