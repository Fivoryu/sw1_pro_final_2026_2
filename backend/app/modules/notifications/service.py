"""Notification generation and inbox queries (F14.7).

Generation functions run inside the caller's transaction, so a notice commits
or rolls back together with the event that caused it. Recipients are resolved
here and nowhere else: a customer notice never names the agent (F14.6, S6).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import func, update
from sqlalchemy.orm import Session

from app.modules.catalog.models import Listing
from app.modules.chat.models import ChatConversation, ListingAgent
from app.modules.identity.models import StaffAccount
from app.modules.notifications.models import Notification
from app.modules.reservations.models import Reservation

OVERDUE_AFTER = timedelta(hours=24)


def _as_utc(value: datetime) -> datetime:
    return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)


def notify(
    session: Session,
    *,
    recipient_kind: str,
    recipient_id: str,
    kind: str,
    now: datetime,
    conversation_id: str | None = None,
    reservation_id: str | None = None,
    detail: str | None = None,
    dedupe_key: str | None = None,
) -> Notification | None:
    """Add one notice; return None when an identical one already exists."""
    if dedupe_key is not None:
        exists = session.query(Notification.id).filter(Notification.dedupe_key == dedupe_key).first()
        if exists is not None:
            return None
    notification = Notification(
        recipient_kind=recipient_kind,
        recipient_id=recipient_id,
        kind=kind,
        conversation_id=conversation_id,
        reservation_id=reservation_id,
        detail=detail,
        dedupe_key=dedupe_key,
        created_at=now,
    )
    session.add(notification)
    session.flush()
    return notification


def agency_admin_ids(session: Session, agency_id: str) -> list[str]:
    return [
        staff_id
        for (staff_id,) in session.query(StaffAccount.id).filter(
            StaffAccount.role == "agency_admin",
            StaffAccount.tenant_id == agency_id,
            StaffAccount.active.is_(True),
        )
    ]


def _assigned_agent_ids(session: Session, listing_id: str) -> list[str]:
    return [
        staff_id
        for (staff_id,) in session.query(StaffAccount.id)
        .join(ListingAgent, ListingAgent.agent_id == StaffAccount.id)
        .filter(
            ListingAgent.listing_id == listing_id,
            StaffAccount.role == "agent",
            StaffAccount.active.is_(True),
        )
    ]


def on_customer_message(session: Session, conversation: ChatConversation, now: datetime) -> None:
    """Tell the owning agent, or every assigned agent while it is unclaimed."""
    if conversation.agent_id is not None:
        recipients = [conversation.agent_id]
    else:
        recipients = _assigned_agent_ids(session, conversation.listing_id)
    if not recipients:
        recipients = agency_admin_ids(session, conversation.agency_id)
    for staff_id in recipients:
        notify(
            session,
            recipient_kind="staff",
            recipient_id=staff_id,
            kind="chat_message",
            now=now,
            conversation_id=conversation.id,
        )


def on_staff_message(session: Session, conversation: ChatConversation, now: datetime) -> None:
    """Tell the customer; the notice carries no sender identity."""
    notify(
        session,
        recipient_kind="customer",
        recipient_id=conversation.customer_id,
        kind="chat_message",
        now=now,
        conversation_id=conversation.id,
    )


def on_assignment(session: Session, conversation: ChatConversation, now: datetime) -> None:
    """Tell the agent who received a conversation, or the admins if nobody is left."""
    if conversation.agent_id is not None:
        notify(
            session,
            recipient_kind="staff",
            recipient_id=conversation.agent_id,
            kind="chat_assigned",
            now=now,
            conversation_id=conversation.id,
        )
        return
    for admin_id in agency_admin_ids(session, conversation.agency_id):
        notify(
            session,
            recipient_kind="staff",
            recipient_id=admin_id,
            kind="chat_needs_admin",
            now=now,
            conversation_id=conversation.id,
        )


def on_reservation_status(session: Session, reservation: Reservation, now: datetime) -> None:
    """Tell the customer and the agency admins that a reservation changed status."""
    listing = session.get(Listing, reservation.listing_id)
    recipients: list[tuple[str, str]] = [("customer", reservation.customer_id)]
    if listing is not None:
        recipients += [("staff", a) for a in agency_admin_ids(session, listing.agency_id)]
    for recipient_kind, recipient_id in recipients:
        notify(
            session,
            recipient_kind=recipient_kind,
            recipient_id=recipient_id,
            kind="reservation_status",
            now=now,
            reservation_id=reservation.id,
            detail=reservation.status,
            dedupe_key=f"reservation:{reservation.id}:{reservation.status}:{recipient_id}",
        )


def escalate_overdue(session: Session, *, agency_id: str, now: datetime) -> None:
    """Raise one notice per admin for each conversation waiting past the limit.

    There is no background job, so the escalation happens when an admin of the
    agency reads the inbox; the dedupe key keeps it to one notice per window.
    """
    cutoff = _as_utc(now) - OVERDUE_AFTER
    waiting = (
        session.query(ChatConversation)
        .filter(
            ChatConversation.agency_id == agency_id,
            ChatConversation.awaiting_since.is_not(None),
        )
        .all()
    )
    overdue = [
        (c, _as_utc(c.awaiting_since))
        for c in waiting
        if c.awaiting_since is not None and _as_utc(c.awaiting_since) <= cutoff
    ]
    if not overdue:
        return
    admins = agency_admin_ids(session, agency_id)
    for conversation, since in overdue:
        for admin_id in admins:
            notify(
                session,
                recipient_kind="staff",
                recipient_id=admin_id,
                kind="chat_overdue",
                now=now,
                conversation_id=conversation.id,
                dedupe_key=f"overdue:{conversation.id}:{since.isoformat()}:{admin_id}",
            )


def list_notifications(
    session: Session, *, recipient_kind: str, recipient_id: str, limit: int
) -> list[Notification]:
    return (
        session.query(Notification)
        .filter(
            Notification.recipient_kind == recipient_kind,
            Notification.recipient_id == recipient_id,
        )
        .order_by(Notification.created_at.desc(), Notification.id.desc())
        .limit(limit)
        .all()
    )


def unread_count(session: Session, *, recipient_kind: str, recipient_id: str) -> int:
    return (
        session.query(func.count(Notification.id))
        .filter(
            Notification.recipient_kind == recipient_kind,
            Notification.recipient_id == recipient_id,
            Notification.read_at.is_(None),
        )
        .scalar()
        or 0
    )


def mark_read(
    session: Session,
    *,
    recipient_kind: str,
    recipient_id: str,
    now: datetime,
    notification_id: str | None = None,
) -> int:
    """Mark one notice (or all) read; only the recipient's own rows can match."""
    statement = (
        update(Notification)
        .where(
            Notification.recipient_kind == recipient_kind,
            Notification.recipient_id == recipient_id,
            Notification.read_at.is_(None),
        )
        .values(read_at=now)
        .execution_options(synchronize_session=False)
    )
    if notification_id is not None:
        statement = statement.where(Notification.id == notification_id)
    result = session.execute(statement)
    return getattr(result, "rowcount", 0) or 0
