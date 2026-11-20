"""Turns unsent inbox notices into push messages (at most once per notice)."""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.orm import Session, sessionmaker

from app.modules.notifications.models import Notification
from app.modules.push.fcm import PushSender
from app.modules.push.models import DeviceToken

LOGGER = logging.getLogger("roomforge.push.dispatcher")

DISPATCH_INTERVAL_SECONDS = 5.0
BATCH_SIZE = 50
STALE_AFTER = timedelta(days=1)

_CUSTOMER_RESERVATION = {
    "accepted": "Tu reserva fue aceptada.",
    "rejected": "Tu reserva fue rechazada.",
    "cancelled": "Tu reserva fue cancelada.",
    "expired": "Tu reserva venció sin respuesta.",
    "pending": "Tu reserva espera la decisión de la agencia.",
}
_STAFF_RESERVATION = {
    "accepted": "Una reserva fue aceptada.",
    "rejected": "Una reserva fue rechazada.",
    "cancelled": "Una reserva fue cancelada.",
    "expired": "Una reserva venció sin respuesta.",
    "pending": "Hay una reserva esperando decisión.",
}


@dataclass(frozen=True)
class _Outgoing:
    title: str
    body: str
    data: dict[str, str]
    tokens: list[tuple[str, str]]


def compose(notification: Notification) -> tuple[str, str]:
    """Generic copy: notices carry ids and a kind, never message text."""
    kind = notification.kind
    if kind == "chat_message":
        return "Nuevo mensaje", "Tienes un mensaje nuevo en una conversación."
    if kind == "chat_assigned":
        return "Conversación asignada", "Se te asignó una conversación."
    if kind == "chat_needs_admin":
        return "Conversación sin agente", "Una conversación necesita un administrador."
    if kind == "chat_overdue":
        return "Conversación pendiente", "Un cliente espera respuesta desde hace más de 24 horas."
    bodies = _STAFF_RESERVATION if notification.recipient_kind == "staff" else _CUSTOMER_RESERVATION
    return "Reserva actualizada", bodies.get(
        notification.detail or "", "El estado de una reserva cambió."
    )


def dispatch_pending(
    session_factory: sessionmaker[Session],
    sender: PushSender,
    *,
    now: datetime,
    batch_size: int = BATCH_SIZE,
) -> int:
    """Claim unsent notices, push them, and drop tokens FCM says are gone.

    The claim commits before any network call, so a slow FCM never holds row
    locks and a crash loses at most one batch instead of repeating it.
    """
    outgoing: list[_Outgoing] = []
    with session_factory.begin() as session:
        pending = session.scalars(
            select(Notification)
            .where(Notification.pushed_at.is_(None), Notification.read_at.is_(None))
            .order_by(Notification.created_at)
            .limit(batch_size)
            .with_for_update(skip_locked=True)
        ).all()
        for notification in pending:
            notification.pushed_at = now
            created = notification.created_at
            if created.tzinfo is None:
                created = created.replace(tzinfo=now.tzinfo)
            if now - created > STALE_AFTER:
                continue
            tokens = session.execute(
                select(DeviceToken.id, DeviceToken.token).where(
                    DeviceToken.recipient_kind == notification.recipient_kind,
                    DeviceToken.recipient_id == notification.recipient_id,
                )
            ).all()
            if not tokens:
                continue
            title, body = compose(notification)
            data = {"kind": notification.kind, "notification_id": notification.id}
            if notification.conversation_id:
                data["conversation_id"] = notification.conversation_id
            if notification.reservation_id:
                data["reservation_id"] = notification.reservation_id
            outgoing.append(_Outgoing(title, body, data, [(row.id, row.token) for row in tokens]))
        claimed = len(pending)
    gone: list[str] = []
    for item in outgoing:
        for token_id, token in item.tokens:
            result = sender.send(token, title=item.title, body=item.body, data=item.data)
            if result == "unregistered":
                gone.append(token_id)
    if gone:
        with session_factory.begin() as session:
            session.execute(delete(DeviceToken).where(DeviceToken.id.in_(gone)))
    return claimed


async def dispatch_loop(
    session_factory: sessionmaker[Session],
    sender: PushSender,
    *,
    clock: Callable[[], datetime],
    interval_seconds: float = DISPATCH_INTERVAL_SECONDS,
) -> None:
    """Poll for unsent notices while the API process runs; failures retry next interval."""
    while True:
        await asyncio.sleep(interval_seconds)
        try:
            await asyncio.to_thread(dispatch_pending, session_factory, sender, now=clock())
        except Exception:  # noqa: BLE001 - the loop must survive any single failure
            LOGGER.exception("Push dispatch failed; retrying next interval")
