from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ListingAgentsUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    agent_ids: list[str] = Field(max_length=50)


class AssignedAgent(BaseModel):
    id: str
    email: str
    active: bool


class ListingAgentsResponse(BaseModel):
    agents: list[AssignedAgent]


class MessageCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(max_length=2000)

    @field_validator("body")
    @classmethod
    def not_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Message must not be blank")
        return stripped


class ReportCreate(MessageCreate):
    """A report reason; same shape and limits as a message."""


# --- Customer view: the agent behind a reply is never exposed. ---


class CustomerConversation(BaseModel):
    id: str
    listing_id: str
    agency_name: str
    read_only: bool
    created_at: datetime
    last_message_at: datetime | None


class CustomerConversationList(BaseModel):
    conversations: list[CustomerConversation]


class CustomerMessage(BaseModel):
    id: int
    sender: Literal["customer", "agency"]
    body: str
    created_at: datetime


class CustomerMessagePage(BaseModel):
    messages: list[CustomerMessage]
    read_only: bool


# --- Staff view. ---


class StaffConversation(BaseModel):
    id: str
    listing_id: str
    customer_email: str
    status: Literal["unclaimed", "claimed"]
    mine: bool
    read_only: bool
    needs_admin: bool
    overdue: bool
    created_at: datetime
    last_message_at: datetime | None
    # Only the agency admin sees who owns a conversation.
    agent_id: str | None = None
    agent_email: str | None = None


class StaffConversationList(BaseModel):
    conversations: list[StaffConversation]


class StaffMessage(BaseModel):
    id: int
    sender: Literal["customer", "agent", "admin"]
    mine: bool
    body: str
    created_at: datetime
    # Only the agency admin sees the real author of each message.
    author_id: str | None = None
    author_email: str | None = None


class StaffMessagePage(BaseModel):
    messages: list[StaffMessage]
    read_only: bool


class ReassignRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    agent_id: str | None = None


class ReportItem(BaseModel):
    id: str
    conversation_id: str
    listing_id: str
    agency_id: str
    reporter_role: Literal["customer", "agent", "admin"]
    reason: str
    created_at: datetime
    # The agency admin and the platform admin see which agent wrote the messages.
    agent_ids: list[str]


class ReportList(BaseModel):
    reports: list[ReportItem]


class BlockedCustomer(BaseModel):
    customer_id: str
    created_at: datetime


class BlockedCustomerList(BaseModel):
    blocked: list[BlockedCustomer]
