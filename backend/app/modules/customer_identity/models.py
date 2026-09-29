"""Persistence models for customer accounts and their independent sessions."""

from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, String, Text, UniqueConstraint, func
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


class CustomerWallet(Base):
    __tablename__ = "customer_wallet"
    __table_args__ = (
        UniqueConstraint("customer_id", name="uq_customer_wallet_customer_id"),
        UniqueConstraint("address", name="uq_customer_wallet_address"),
        CheckConstraint("address = lower(address)", name="ck_customer_wallet_address_canonical"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    customer_id: Mapped[str] = mapped_column(
        ForeignKey("customer_account.id", ondelete="CASCADE"), nullable=False
    )
    address: Mapped[str] = mapped_column(String(42), nullable=False)
    linked_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class CustomerWalletChallenge(Base):
    __tablename__ = "customer_wallet_challenge"
    __table_args__ = (
        UniqueConstraint("nonce", name="uq_customer_wallet_challenge_nonce"),
        CheckConstraint(
            "purpose = 'link-customer-wallet'", name="ck_customer_wallet_challenge_purpose"
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    customer_id: Mapped[str] = mapped_column(
        ForeignKey("customer_account.id", ondelete="CASCADE"), nullable=False
    )
    address: Mapped[str] = mapped_column(String(42), nullable=False)
    purpose: Mapped[str] = mapped_column(String(64), nullable=False)
    nonce: Mapped[str] = mapped_column(String(64), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


Index("ix_customer_wallet_challenge_customer_id", CustomerWalletChallenge.customer_id)
