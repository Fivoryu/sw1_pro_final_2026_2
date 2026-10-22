from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class StripeConnectAccount(Base):
    __tablename__ = "stripe_connect_account"
    __table_args__ = (
        UniqueConstraint("agency_id", name="uq_stripe_connect_account_agency"),
        UniqueConstraint("stripe_account_id", name="uq_stripe_connect_account_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    agency_id: Mapped[str] = mapped_column(ForeignKey("agency.id", ondelete="CASCADE"), nullable=False)
    stripe_account_id: Mapped[str] = mapped_column(String(128), nullable=False)
    details_submitted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    charges_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    payouts_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class ReservationCardPayment(Base):
    __tablename__ = "reservation_card_payment"
    __table_args__ = (
        UniqueConstraint("reservation_id", name="uq_reservation_card_payment_reservation"),
        UniqueConstraint("stripe_payment_intent_id", name="uq_reservation_card_payment_intent"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    reservation_id: Mapped[str] = mapped_column(
        ForeignKey("reservation.id", ondelete="RESTRICT"), nullable=False
    )
    stripe_payment_intent_id: Mapped[str] = mapped_column(String(128), nullable=False)
    latest_charge_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    amount_minor: Mapped[int] = mapped_column(Integer, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False)
    transfer_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    refund_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class StripeWebhookEvent(Base):
    __tablename__ = "stripe_webhook_event"
    __table_args__ = (UniqueConstraint("stripe_event_id", name="uq_stripe_webhook_event_id"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    stripe_event_id: Mapped[str] = mapped_column(String(128), nullable=False)
    event_type: Mapped[str] = mapped_column(String(128), nullable=False)
    processed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
