"""Customer reservation persistence models."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import uuid4

from sqlalchemy import (
    JSON,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Reservation(Base):
    __tablename__ = "reservation"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending', 'accepted', 'rejected', 'cancelled', 'expired')",
            name="ck_reservation_status",
        ),
        CheckConstraint("offer_version >= 1", name="ck_reservation_offer_version_positive"),
        CheckConstraint(
            "decision_deadline_at > api_created_at",
            name="ck_reservation_deadline_after_creation",
        ),
        CheckConstraint(
            "deposit_amount_cop IS NULL OR deposit_amount_cop > 0",
            name="ck_reservation_deposit_amount_cop_positive",
        ),
        CheckConstraint(
            "deposit_amount_cop IS NULL OR deposit_amount_cop = round(deposit_amount_cop, 2)",
            name="ck_reservation_deposit_amount_cop_scale",
        ),
        CheckConstraint("one_time_total >= 0", name="ck_reservation_one_time_total_nonnegative"),
        CheckConstraint("monthly_total >= 0", name="ck_reservation_monthly_total_nonnegative"),
        CheckConstraint(
            "length(trim(idempotency_key)) > 0",
            name="ck_reservation_idempotency_key_nonblank",
        ),
        CheckConstraint(
            "length(request_fingerprint) = 64",
            name="ck_reservation_fingerprint_sha256",
        ),
        UniqueConstraint(
            "customer_id",
            "idempotency_key",
            name="uq_reservation_customer_idempotency_key",
        ),
        Index(
            "uq_reservation_active_listing",
            "listing_id",
            unique=True,
            sqlite_where=text("status IN ('pending', 'accepted')"),
            postgresql_where=text("status IN ('pending', 'accepted')"),
        ),
        Index(
            "ix_reservation_customer_created_at",
            "customer_id",
            "api_created_at",
            "id",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    listing_id: Mapped[str] = mapped_column(
        ForeignKey("listing.id", ondelete="RESTRICT"), nullable=False
    )
    quote_id: Mapped[str] = mapped_column(
        ForeignKey("quote_snapshot.id", ondelete="RESTRICT"), nullable=False
    )
    customer_id: Mapped[str] = mapped_column(
        ForeignKey("customer_account.id", ondelete="RESTRICT"), nullable=False
    )
    customer_wallet_id: Mapped[str] = mapped_column(
        ForeignKey("customer_wallet.id", ondelete="RESTRICT"), nullable=False
    )
    agency_wallet_id: Mapped[str] = mapped_column(
        ForeignKey("agency_wallet.id", ondelete="RESTRICT"), nullable=False
    )
    customer_wallet_address: Mapped[str] = mapped_column(String(42), nullable=False)
    agency_wallet_address: Mapped[str] = mapped_column(String(42), nullable=False)
    offer_version: Mapped[int] = mapped_column(Integer, nullable=False)
    operation: Mapped[str] = mapped_column(String(8), nullable=False)
    quote_lines: Mapped[list[dict[str, str | None]]] = mapped_column(JSON, nullable=False)
    one_time_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    monthly_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    deposit_amount_cop: Mapped[Decimal | None] = mapped_column(Numeric(18, 2), nullable=True)
    api_created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    decision_deadline_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    deposit_confirmed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    idempotency_key: Mapped[str] = mapped_column(String(128), nullable=False)
    request_fingerprint: Mapped[str] = mapped_column(String(64), nullable=False)
