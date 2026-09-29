"""Persistence models for agency wallet ownership proofs."""

from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class AgencyWallet(Base):
    __tablename__ = "agency_wallet"
    __table_args__ = (
        UniqueConstraint("agency_id", name="uq_agency_wallet_agency_id"),
        UniqueConstraint("address", name="uq_agency_wallet_address"),
        CheckConstraint("address = lower(address)", name="ck_agency_wallet_address_canonical"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    agency_id: Mapped[str] = mapped_column(
        ForeignKey("agency.id", ondelete="CASCADE"), nullable=False
    )
    address: Mapped[str] = mapped_column(String(42), nullable=False)
    linked_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class AgencyWalletChallenge(Base):
    __tablename__ = "agency_wallet_challenge"
    __table_args__ = (
        UniqueConstraint("nonce", name="uq_agency_wallet_challenge_nonce"),
        CheckConstraint(
            "purpose = 'link-agency-wallet'", name="ck_agency_wallet_challenge_purpose"
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    agency_id: Mapped[str] = mapped_column(
        ForeignKey("agency.id", ondelete="CASCADE"), nullable=False
    )
    address: Mapped[str] = mapped_column(String(42), nullable=False)
    purpose: Mapped[str] = mapped_column(String(64), nullable=False)
    nonce: Mapped[str] = mapped_column(String(64), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


Index("ix_agency_wallet_challenge_agency_id", AgencyWalletChallenge.agency_id)
