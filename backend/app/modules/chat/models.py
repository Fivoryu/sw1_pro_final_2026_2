"""Persistence models for the agency chat (F14.6)."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ListingAgent(Base):
    """An agent the agency assigned to answer conversations about a listing."""

    __tablename__ = "listing_agent"

    listing_id: Mapped[str] = mapped_column(
        ForeignKey("listing.id", ondelete="CASCADE"), primary_key=True
    )
    agent_id: Mapped[str] = mapped_column(
        ForeignKey("staff_account.id", ondelete="CASCADE"), primary_key=True
    )
    assigned_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


Index("ix_listing_agent_agent_id", ListingAgent.agent_id)
