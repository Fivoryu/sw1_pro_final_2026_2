"""Persistence models for listing and agency reviews (F14.8)."""

from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ListingReview(Base):
    """One customer's rating of a listing and of the agency's attention.

    Whether the review counts as verified is never stored: it is derived from
    the customer's reservation each time, so a customer who reserves after
    rating is verified from then on.
    """

    __tablename__ = "listing_review"
    __table_args__ = (
        UniqueConstraint("listing_id", "customer_id", name="uq_listing_review_listing_customer"),
        CheckConstraint("listing_rating BETWEEN 1 AND 5", name="ck_listing_review_listing_rating"),
        CheckConstraint("agency_rating BETWEEN 1 AND 5", name="ck_listing_review_agency_rating"),
        Index("ix_listing_review_agency_id", "agency_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    listing_id: Mapped[str] = mapped_column(
        ForeignKey("listing.id", ondelete="CASCADE"), nullable=False
    )
    agency_id: Mapped[str] = mapped_column(
        ForeignKey("agency.id", ondelete="CASCADE"), nullable=False
    )
    customer_id: Mapped[str] = mapped_column(
        ForeignKey("customer_account.id", ondelete="CASCADE"), nullable=False
    )
    listing_rating: Mapped[int] = mapped_column(Integer, nullable=False)
    agency_rating: Mapped[int] = mapped_column(Integer, nullable=False)
    comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    # The agency answers once per review; the customer never learns who wrote it.
    agency_reply: Mapped[str | None] = mapped_column(Text, nullable=True)
    agency_reply_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    agency_reply_by: Mapped[str | None] = mapped_column(
        ForeignKey("staff_account.id", ondelete="SET NULL"), nullable=True
    )
    # Set when the platform administrator upholds a report; hidden reviews do not count.
    hidden_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ReviewReport(Base):
    """An agency's report of a review; the platform administrator decides."""

    __tablename__ = "review_report"
    __table_args__ = (
        CheckConstraint(
            "status IN ('open', 'upheld', 'dismissed')", name="ck_review_report_status"
        ),
        Index("ix_review_report_review_id", "review_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    review_id: Mapped[str] = mapped_column(
        ForeignKey("listing_review.id", ondelete="CASCADE"), nullable=False
    )
    agency_id: Mapped[str] = mapped_column(
        ForeignKey("agency.id", ondelete="CASCADE"), nullable=False
    )
    reporter_id: Mapped[str | None] = mapped_column(
        ForeignKey("staff_account.id", ondelete="SET NULL"), nullable=True
    )
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="open")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    resolved_by: Mapped[str | None] = mapped_column(
        ForeignKey("staff_account.id", ondelete="SET NULL"), nullable=True
    )
