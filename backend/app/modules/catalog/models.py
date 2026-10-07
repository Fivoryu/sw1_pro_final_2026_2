"""Catalog listing and commercial-offer persistence models."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import uuid4

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    event,
    false,
    func,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class Listing(Base):
    __tablename__ = "listing"
    __table_args__ = (
        CheckConstraint(
            "approval_status IN ('draft', 'pending', 'approved', 'rejected')",
            name="ck_listing_approval_status",
        ),
        CheckConstraint("operation IN ('sale', 'rent')", name="ck_listing_operation"),
        CheckConstraint("base_price >= 0", name="ck_listing_base_price_nonnegative"),
        CheckConstraint(
            "deposit_amount_cop IS NULL OR deposit_amount_cop > 0",
            name="ck_listing_deposit_amount_cop_positive",
        ),
        CheckConstraint(
            "deposit_amount_cop IS NULL OR deposit_amount_cop = round(deposit_amount_cop, 2)",
            name="ck_listing_deposit_amount_cop_scale",
        ),
        CheckConstraint("offer_version >= 1", name="ck_listing_offer_version_positive"),
        CheckConstraint("bedrooms >= 0", name="ck_listing_bedrooms_nonnegative"),
        CheckConstraint("bathrooms >= 0", name="ck_listing_bathrooms_nonnegative"),
        Index(
            "ix_listing_public_created_at_id",
            "approval_status",
            "is_published",
            "created_at",
            "id",
        ),
        Index("ix_listing_city_key", "city_key"),
        Index("ix_listing_zone_key", "zone_key"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    agency_id: Mapped[str] = mapped_column(ForeignKey("agency.id"), nullable=False)
    approval_status: Mapped[str] = mapped_column(
        String(16), nullable=False, default="draft", server_default=text("'draft'")
    )
    is_published: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=false()
    )
    operation: Mapped[str] = mapped_column(String(8), nullable=False)
    base_price: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    deposit_amount_cop: Mapped[Decimal | None] = mapped_column(Numeric(18, 2), nullable=True)
    offer_version: Mapped[int] = mapped_column(
        Integer, nullable=False, default=1, server_default=text("1")
    )
    city: Mapped[str] = mapped_column(String(120), nullable=False)
    city_key: Mapped[str] = mapped_column(String(360), nullable=False)
    zone: Mapped[str] = mapped_column(String(120), nullable=False)
    zone_key: Mapped[str] = mapped_column(String(360), nullable=False)
    bedrooms: Mapped[int] = mapped_column(Integer, nullable=False)
    bathrooms: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    exact_address: Mapped[str | None] = mapped_column(Text, nullable=True)
    photos: Mapped[list[str] | None] = mapped_column(JSON, nullable=True)
    extras: Mapped[list[ListingExtra]] = relationship(
        back_populates="listing",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


# Photo limits shared by the model constraints and the photo service.
LISTING_PHOTO_CONTENT_TYPES = ("image/jpeg", "image/png", "image/webp")
LISTING_PHOTO_MAX_BYTES = 5 * 1024 * 1024
LISTING_PHOTO_MAX_COUNT = 10


class ListingPhoto(Base):
    """A listing photo kept in object storage; the database holds only its metadata."""

    __tablename__ = "listing_photo"
    __table_args__ = (
        CheckConstraint("status IN ('pending', 'confirmed')", name="ck_listing_photo_status"),
        CheckConstraint(
            "content_type IN ('image/jpeg', 'image/png', 'image/webp')",
            name="ck_listing_photo_content_type",
        ),
        CheckConstraint(
            "size_bytes > 0 AND size_bytes <= 5242880", name="ck_listing_photo_size_bytes"
        ),
        CheckConstraint(
            "(status = 'confirmed') = (confirmed_at IS NOT NULL)",
            name="ck_listing_photo_confirmed_at",
        ),
        UniqueConstraint("object_key", name="uq_listing_photo_object_key"),
        Index("ix_listing_photo_listing_id_created_at", "listing_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    agency_id: Mapped[str] = mapped_column(ForeignKey("agency.id"), nullable=False)
    listing_id: Mapped[str] = mapped_column(ForeignKey("listing.id"), nullable=False)
    object_key: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    content_type: Mapped[str] = mapped_column(String(32), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ListingTransition(Base):
    __tablename__ = "listing_transition"
    __table_args__ = (
        CheckConstraint(
            "action IN ('create', 'edit', 'submit', 'approve', 'reject', 'publish', 'unpublish')",
            name="ck_listing_transition_action",
        ),
        Index("ix_listing_transition_listing_id", "listing_id"),
        Index("ix_listing_transition_listing_id_created_at", "listing_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    agency_id: Mapped[str] = mapped_column(ForeignKey("agency.id"), nullable=False)
    listing_id: Mapped[str] = mapped_column(ForeignKey("listing.id"), nullable=False)
    action: Mapped[str] = mapped_column(String(16), nullable=False)
    from_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    from_published: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    to_status: Mapped[str] = mapped_column(String(16), nullable=False)
    to_published: Mapped[bool] = mapped_column(Boolean, nullable=False)
    observation: Mapped[str | None] = mapped_column(Text, nullable=True)
    actor_id: Mapped[str] = mapped_column(String(36), nullable=False)
    actor_role: Mapped[str] = mapped_column(String(32), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class ListingExtra(Base):
    __tablename__ = "listing_extra"
    __table_args__ = (
        CheckConstraint("price >= 0", name="ck_listing_extra_price_nonnegative"),
        CheckConstraint("length(trim(name)) > 0", name="ck_listing_extra_name_nonblank"),
        Index("ix_listing_extra_listing_id", "listing_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    listing_id: Mapped[str] = mapped_column(
        ForeignKey("listing.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    price: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    listing: Mapped[Listing] = relationship(back_populates="extras")


class QuoteSnapshot(Base):
    """Immutable offer and price lines returned by public quote creation."""

    __tablename__ = "quote_snapshot"
    __table_args__ = (
        CheckConstraint("offer_version >= 1", name="ck_quote_snapshot_offer_version_positive"),
        CheckConstraint("operation IN ('sale', 'rent')", name="ck_quote_snapshot_operation"),
        CheckConstraint("one_time_total >= 0", name="ck_quote_snapshot_one_time_nonnegative"),
        CheckConstraint("monthly_total >= 0", name="ck_quote_snapshot_monthly_nonnegative"),
        CheckConstraint("expires_at > created_at", name="ck_quote_snapshot_expiry_after_creation"),
        Index("ix_quote_snapshot_listing_version", "listing_id", "offer_version"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    listing_id: Mapped[str] = mapped_column(String(36), nullable=False)
    offer_version: Mapped[int] = mapped_column(Integer, nullable=False)
    operation: Mapped[str] = mapped_column(String(8), nullable=False)
    lines: Mapped[list[dict[str, str | None]]] = mapped_column(JSON, nullable=False)
    one_time_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    monthly_total: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class QuoteRateLimitEvent(Base):
    """A single accepted well-formed quote attempt, keyed by an HMAC IP digest."""

    __tablename__ = "quote_rate_limit_event"
    __table_args__ = (
        Index("ix_quote_rate_limit_client_time", "client_key", "occurred_at"),
        Index("ix_quote_rate_limit_occurred_at", "occurred_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    client_key: Mapped[str] = mapped_column(String(64), nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


# Offer versions are authoritative in the database triggers installed by migration
# 0007_catalog_offers. Keeping versioning out of ORM events avoids double increments
# and covers raw SQL plus every SQLAlchemy write path consistently.


@event.listens_for(Listing, "before_insert")
@event.listens_for(Listing, "before_update")
def _set_normalized_geography_keys(
    _mapper: object, _connection: object, listing: Listing
) -> None:
    listing.city_key = listing.city.strip().casefold()
    listing.zone_key = listing.zone.strip().casefold()
