"""Persistence models for customer accounts and their independent sessions."""

from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from sqlalchemy import DateTime, ForeignKey, Index, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class CustomerAccount(Base):
    __tablename__ = "customer_account"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    email: Mapped[str] = mapped_column(String(255), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)


Index(
    "uq_customer_account_normalized_email",
    func.lower(func.trim(CustomerAccount.email)),
    unique=True,
)


class CustomerSession(Base):
    __tablename__ = "customer_session"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    customer_id: Mapped[str] = mapped_column(
        ForeignKey("customer_account.id", ondelete="CASCADE"), nullable=False
    )
    refresh_token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_activity_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


Index("ix_customer_session_customer_id", CustomerSession.customer_id)
