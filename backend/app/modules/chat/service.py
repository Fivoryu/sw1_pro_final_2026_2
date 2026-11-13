"""Conversation rules for the agency chat (F14.6).

The customer only ever sees the agency: the agent behind a reply is exposed to the
agency admin and never to the customer.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy import func, update
from sqlalchemy.orm import Session

from app.modules.catalog.models import Listing
from app.modules.chat.models import (
    ChatConversation,
    ChatCustomerBlock,
    ChatMessage,
    ListingAgent,
)
from app.modules.identity.models import Agency, StaffAccount
from app.modules.identity.session import ActiveStaff
from app.modules.reservations.models import Reservation


def not_found(detail: str = "Conversation not found") -> HTTPException:
    return HTTPException(status_code=404, detail=detail)


def get_or_create_conversation(
    session: Session, *, customer_id: str, listing_id: str, now: datetime
) -> tuple[ChatConversation, bool]:
    listing = (
        session.query(Listing)
        .filter(
            Listing.id == listing_id,
            Listing.approval_status == "approved",
            Listing.is_published.is_(True),
        )
        .one_or_none()
    )
    if listing is None:
        raise not_found("Listing not found")
    conversation = (
        session.query(ChatConversation)
        .filter(
            ChatConversation.listing_id == listing_id,
            ChatConversation.customer_id == customer_id,
        )
        .one_or_none()
    )
    if conversation is not None:
        return conversation, False
    conversation = ChatConversation(
        listing_id=listing_id,
        agency_id=listing.agency_id,
        customer_id=customer_id,
        created_at=now,
    )
    session.add(conversation)
    session.flush()
    return conversation, True


def customer_conversation(
    session: Session, *, customer_id: str, conversation_id: str
) -> ChatConversation:
    conversation = (
        session.query(ChatConversation)
        .filter(
            ChatConversation.id == conversation_id,
            ChatConversation.customer_id == customer_id,
        )
        .one_or_none()
    )
    if conversation is None:
        raise not_found()
    return conversation


def agency_name(session: Session, agency_id: str) -> str:
    name =session.query(Agency.name).filter(Agency.id == agency_id).scalar()
    return name if name is not None else agency_id


def staff_can_see(session: Session, staff: ActiveStaff, conversation: ChatConversation) -> bool:
    if staff["tenant_id"] != conversation.agency_id:
        return False
    if staff["role"] == "agency_admin":
        return True
    if staff["role"] != "agent":
        return False
    if conversation.agent_id is not None:
        return conversation.agent_id == staff["id"]
    return is_assigned(session, conversation.listing_id, staff["id"])


def is_assigned(session: Session, listing_id: str, agent_id: str) -> bool:
    return (
        session.query(ListingAgent)
        .filter(ListingAgent.listing_id == listing_id, ListingAgent.agent_id == agent_id)
        .first()
        is not None
    )


def staff_conversation(
    session: Session, *, staff: ActiveStaff, conversation_id: str
) -> ChatConversation:
    conversation = session.get(ChatConversation, conversation_id)
    if conversation is None or not staff_can_see(session, staff, conversation):
        # Another agent's conversation is indistinguishable from a missing one.
        raise not_found()
    return conversation


def append_message(
    session: Session,
    conversation: ChatConversation,
    *,
    role: str,
    staff_id: str | None,
    body: str,
    now: datetime,
) -> ChatMessage:
    message = ChatMessage(
        conversation_id=conversation.id,
        sender_role=role,
        sender_staff_id=staff_id,
        body=body,
        created_at=now,
    )
    session.add(message)
    conversation.last_message_at = now
    if role == "customer":
        if conversation.awaiting_since is None:
            conversation.awaiting_since = now
    else:
        conversation.awaiting_since = None
    session.flush()
    return message


def claim_conversation(session: Session, *, conversation_id: str, staff_id: str) -> bool:
    """Atomically take an unclaimed conversation; False if somebody else won."""
    result = session.execute(
        update(ChatConversation)
        .where(ChatConversation.id == conversation_id, ChatConversation.agent_id.is_(None))
        .values(agent_id=staff_id, needs_admin=False)
        .execution_options(synchronize_session=False)
    )
    return (getattr(result, "rowcount", 0) or 0) == 1


def post_staff_message(
    session: Session,
    *,
    staff: ActiveStaff,
    conversation_id: str,
    body: str,
    now: datetime,
) -> ChatMessage:
    raw = session.get(ChatConversation, conversation_id)
    if (
        raw is not None
        and staff["role"] == "agent"
        and raw.agent_id not in (None, staff["id"])
        and raw.agency_id == staff["tenant_id"]
        and is_assigned(session, raw.listing_id, staff["id"])
    ):
        # The agent could see it until someone else answered first.
        raise HTTPException(status_code=409, detail="Conversation already taken")
    conversation = staff_conversation(session, staff=staff, conversation_id=conversation_id)
    if is_read_only(session, conversation):
        raise HTTPException(status_code=409, detail="Conversation is read-only")
    if staff["role"] == "agent" and conversation.agent_id is None:
        if not claim_conversation(session, conversation_id=conversation.id, staff_id=staff["id"]):
            raise HTTPException(status_code=409, detail="Conversation already taken")
        session.refresh(conversation)
    elif staff["role"] == "agency_admin" and conversation.agent_id is None:
        claim_conversation(session, conversation_id=conversation.id, staff_id=staff["id"])
        session.refresh(conversation)
    role = "admin" if staff["role"] == "agency_admin" else "agent"
    return append_message(
        session, conversation, role=role, staff_id=staff["id"], body=body, now=now
    )


OVERDUE_AFTER = timedelta(hours=24)


def is_overdue(conversation: ChatConversation, now: datetime) -> bool:
    waiting = conversation.awaiting_since
    if waiting is None:
        return False
    if waiting.tzinfo is None:
        waiting = waiting.replace(tzinfo=timezone.utc)
    return now - waiting >= OVERDUE_AFTER


def is_read_only(session: Session, conversation: ChatConversation) -> bool:
    """A conversation freezes when its listing is withdrawn or reserved by someone else."""
    listing = session.get(Listing, conversation.listing_id)
    if listing is None or listing.approval_status != "approved" or not listing.is_published:
        return True
    holder = (
        session.query(Reservation.customer_id)
        .filter(
            Reservation.listing_id == conversation.listing_id,
            Reservation.status.in_(("pending", "accepted")),
        )
        .scalar()
    )
    return holder is not None and holder != conversation.customer_id


def is_blocked(session: Session, *, agency_id: str, customer_id: str) -> bool:
    return (
        session.query(ChatCustomerBlock)
        .filter(
            ChatCustomerBlock.agency_id == agency_id,
            ChatCustomerBlock.customer_id == customer_id,
        )
        .first()
        is not None
    )


def _open_load(session: Session, agent_id: str) -> int:
    return (
        session.query(func.count(ChatConversation.id))
        .filter(ChatConversation.agent_id == agent_id)
        .scalar()
        or 0
    )


def pick_agent(session: Session, *, listing_id: str, exclude: set[str]) -> str | None:
    """The active assigned agent with the fewest conversations, ties broken by id."""
    candidates = [
        agent_id
        for (agent_id,) in session.query(StaffAccount.id)
        .join(ListingAgent, ListingAgent.agent_id == StaffAccount.id)
        .filter(
            ListingAgent.listing_id == listing_id,
            StaffAccount.role == "agent",
            StaffAccount.active.is_(True),
        )
        if agent_id not in exclude
    ]
    if not candidates:
        return None
    return min(candidates, key=lambda agent_id: (_open_load(session, agent_id), agent_id))


def reassign_conversation(
    session: Session,
    conversation: ChatConversation,
    *,
    exclude: set[str],
    new_agent_id: str | None = None,
) -> None:
    """Hand a conversation to another agent, or flag it for the admin if none is left."""
    target = new_agent_id or pick_agent(
        session, listing_id=conversation.listing_id, exclude=exclude
    )
    conversation.agent_id = target
    conversation.needs_admin = target is None


def reassign_for_agent(
    session: Session, *, agent_id: str, listing_id: str | None = None
) -> int:
    """Move an agent's conversations away (deactivation or removal from a listing)."""
    query = session.query(ChatConversation).filter(ChatConversation.agent_id == agent_id)
    if listing_id is not None:
        query = query.filter(ChatConversation.listing_id == listing_id)
    conversations = query.all()
    for conversation in conversations:
        reassign_conversation(session, conversation, exclude={agent_id})
    session.flush()
    return len(conversations)


def staff_email(session: Session, staff_id: str | None) -> str | None:
    if staff_id is None:
        return None
    return session.query(StaffAccount.email).filter(StaffAccount.id == staff_id).scalar()
