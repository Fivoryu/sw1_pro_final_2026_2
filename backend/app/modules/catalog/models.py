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
    event,
    func,
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
    approval_status: Mapped[str] = mapped_column(String(16), nullable=False, default="draft")
    is_published: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    operation: Mapped[str] = mapped_column(String(8), nullable=False)
    base_price: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    offer_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
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
