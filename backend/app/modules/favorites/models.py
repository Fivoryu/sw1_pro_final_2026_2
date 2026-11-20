"""Persistence models for customer favorites and saved searches (F14.3)."""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import uuid4

from sqlalchemy import JSON, DateTime, ForeignKey, Index, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class CustomerFavorite(Base):
    """A listing one customer marked as favorite; only that customer sees it."""

    __tablename__ = "customer_favorite"
    __table_args__ = (
        UniqueConstraint("customer_id", "listing_id", name="uq_customer_favorite_customer_listing"),
        Index("ix_customer_favorite_listing_id", "listing_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    customer_id: Mapped[str] = mapped_column(
        ForeignKey("customer_account.id", ondelete="CASCADE"), nullable=False
    )
    listing_id: Mapped[str] = mapped_column(
        ForeignKey("listing.id", ondelete="CASCADE"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class CustomerSavedSearch(Base):
    """A named set of public catalog filters one customer can apply again."""

    __tablename__ = "customer_saved_search"
    __table_args__ = (
        UniqueConstraint("customer_id", "name", name="uq_customer_saved_search_customer_name"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    customer_id: Mapped[str] = mapped_column(
        ForeignKey("customer_account.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    # Only the keys of SavedSearchFilters, validated on write; prices as decimal strings.
    filters: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
