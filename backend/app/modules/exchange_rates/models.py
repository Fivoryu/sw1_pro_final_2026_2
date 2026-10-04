"""Persistence model for the administered USD-relative exchange-rate history."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, Numeric, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ExchangeRate(Base):
    __tablename__ = "exchange_rate"
    __table_args__ = (
        CheckConstraint(
            "currency IN ('BOB', 'USD', 'USDT')",
            name="ck_exchange_rate_currency_supported",
        ),
        CheckConstraint(
            "units_per_usd > 0",
            name="ck_exchange_rate_units_per_usd_positive",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    currency: Mapped[str] = mapped_column(String(4), nullable=False)
    units_per_usd: Mapped[Decimal] = mapped_column(Numeric(18, 8), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    created_by: Mapped[str] = mapped_column(
        String(36), ForeignKey("staff_account.id"), nullable=False
    )
