"""Persistence models for the agency chat (F14.6)."""

from __future__ import annotations

from datetime import datetime
from uuid import uuid4

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    false,
)
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


class ChatConversation(Base):
    """One conversation per customer and listing; ``agent_id`` is the staff owner."""

    __tablename__ = "chat_conversation"
    __table_args__ = (
        UniqueConstraint("listing_id", "customer_id", name="uq_chat_conversation_listing_customer"),
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
    # NULL while nobody has answered; the first staff reply claims it atomically.
    agent_id: Mapped[str | None] = mapped_column(
        ForeignKey("staff_account.id", ondelete="SET NULL"), nullable=True
    )
    # Set when no active agent was left to take over; the agency admin must act.
    needs_admin: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=false()
    )
    # Since when the customer waits for an answer; NULL when nothing is pending.
    awaiting_since: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    last_message_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


Index("ix_chat_conversation_agency_id", ChatConversation.agency_id)
Index("ix_chat_conversation_agent_id", ChatConversation.agent_id)
Index("ix_chat_conversation_customer_id", ChatConversation.customer_id)


class ChatMessage(Base):
    """An immutable message; messages are never edited or deleted (report evidence)."""

    __tablename__ = "chat_message"
    __table_args__ = (
        CheckConstraint(
            "sender_role IN ('customer', 'agent', 'admin')", name="ck_chat_message_sender_role"
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("chat_conversation.id", ondelete="CASCADE"), nullable=False
    )
    sender_role: Mapped[str] = mapped_column(String(16), nullable=False)
    sender_staff_id: Mapped[str | None] = mapped_column(
        ForeignKey("staff_account.id", ondelete="SET NULL"), nullable=True
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


Index("ix_chat_message_conversation_id_id", ChatMessage.conversation_id, ChatMessage.id)


class ChatReport(Base):
    """A report of a conversation raised by the customer or by agency staff."""

    __tablename__ = "chat_report"
    __table_args__ = (
        CheckConstraint(
            "reporter_role IN ('customer', 'agent', 'admin')", name="ck_chat_report_reporter_role"
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("chat_conversation.id", ondelete="CASCADE"), nullable=False
    )
    reporter_role: Mapped[str] = mapped_column(String(16), nullable=False)
    reporter_id: Mapped[str] = mapped_column(String(36), nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


Index("ix_chat_report_conversation_id", ChatReport.conversation_id)


class ChatCustomerBlock(Base):
    """A customer an agency stopped receiving messages from."""

    __tablename__ = "chat_customer_block"

    agency_id: Mapped[str] = mapped_column(
        ForeignKey("agency.id", ondelete="CASCADE"), primary_key=True
    )
    customer_id: Mapped[str] = mapped_column(
        ForeignKey("customer_account.id", ondelete="CASCADE"), primary_key=True
    )
    blocked_by: Mapped[str | None] = mapped_column(
        ForeignKey("staff_account.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
