"""Inbox endpoints for customers and agency staff (F14.7)."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from pydantic import BaseModel
from sqlalchemy.orm import Session, sessionmaker

from app.core.errors import ERROR_RESPONSES
from app.modules.customer_identity.session import ActiveCustomer, get_active_customer
from app.modules.identity.session import ActiveStaff, get_active_staff
from app.modules.notifications import service
from app.modules.notifications.models import Notification

customer_router = APIRouter(
    prefix="/api/v1/customer/notifications",
    tags=["customer-notifications"],
    responses=ERROR_RESPONSES,
)
staff_router = APIRouter(
    prefix="/api/v1/staff/notifications",
    tags=["staff-notifications"],
    responses=ERROR_RESPONSES,
)

_Customer = Annotated[ActiveCustomer, Depends(get_active_customer)]
_Staff = Annotated[ActiveStaff, Depends(get_active_staff)]
_Limit = Annotated[int, Query(ge=1, le=100)]


class NotificationView(BaseModel):
    id: str
    kind: str
    conversation_id: str | None
    reservation_id: str | None
    detail: str | None
    created_at: datetime
    read: bool


class NotificationList(BaseModel):
    unread: int
    items: list[NotificationView]


def _factory(request: Request) -> sessionmaker[Session]:
    factory: sessionmaker[Session] = request.app.state.session_factory
    return factory


def _now(request: Request) -> datetime:
    now: datetime = request.app.state.clock()
    return now


def _view(notification: Notification) -> NotificationView:
    return NotificationView(
        id=notification.id,
        kind=notification.kind,
        conversation_id=notification.conversation_id,
        reservation_id=notification.reservation_id,
        detail=notification.detail,
        created_at=notification.created_at,
        read=notification.read_at is not None,
    )


def _inbox(
    request: Request, *, recipient_kind: str, recipient_id: str, limit: int, agency_id: str | None
) -> NotificationList:
    now = _now(request)
    with _factory(request).begin() as session:
        if agency_id is not None:
            service.escalate_overdue(session, agency_id=agency_id, now=now)
        items = service.list_notifications(
            session, recipient_kind=recipient_kind, recipient_id=recipient_id, limit=limit
        )
        unread = service.unread_count(
            session, recipient_kind=recipient_kind, recipient_id=recipient_id
        )
        return NotificationList(unread=unread, items=[_view(item) for item in items])


def _read(
    request: Request, *, recipient_kind: str, recipient_id: str, notification_id: str | None
) -> None:
    with _factory(request).begin() as session:
        changed = service.mark_read(
            session,
            recipient_kind=recipient_kind,
            recipient_id=recipient_id,
            now=_now(request),
            notification_id=notification_id,
        )
        if notification_id is not None and changed == 0:
            exists = (
                session.query(Notification.id)
                .filter(
                    Notification.id == notification_id,
                    Notification.recipient_kind == recipient_kind,
                    Notification.recipient_id == recipient_id,
                )
                .first()
            )
            # Somebody else's notice is indistinguishable from a missing one.
            if exists is None:
                raise HTTPException(status_code=404, detail="Notification not found")


def _agency_staff(staff: ActiveStaff) -> None:
    if staff["role"] not in ("agent", "agency_admin") or staff["tenant_id"] is None:
        raise HTTPException(status_code=403, detail="Agency staff access is required")


@customer_router.get("", response_model=NotificationList)
def customer_inbox(request: Request, customer: _Customer, limit: _Limit = 50) -> NotificationList:
    return _inbox(
        request, recipient_kind="customer", recipient_id=customer["id"], limit=limit, agency_id=None
    )


@customer_router.post("/read-all", status_code=204)
def customer_read_all(request: Request, customer: _Customer) -> Response:
    _read(request, recipient_kind="customer", recipient_id=customer["id"], notification_id=None)
    return Response(status_code=204)


@customer_router.post("/{notification_id}/read", status_code=204)
def customer_read(request: Request, customer: _Customer, notification_id: str) -> Response:
    _read(
        request,
        recipient_kind="customer",
        recipient_id=customer["id"],
        notification_id=notification_id,
    )
    return Response(status_code=204)


@staff_router.get("", response_model=NotificationList)
def staff_inbox(request: Request, staff: _Staff, limit: _Limit = 50) -> NotificationList:
    _agency_staff(staff)
    return _inbox(
        request,
        recipient_kind="staff",
        recipient_id=staff["id"],
        limit=limit,
        agency_id=staff["tenant_id"] if staff["role"] == "agency_admin" else None,
    )


@staff_router.post("/read-all", status_code=204)
def staff_read_all(request: Request, staff: _Staff) -> Response:
    _agency_staff(staff)
    _read(request, recipient_kind="staff", recipient_id=staff["id"], notification_id=None)
    return Response(status_code=204)


@staff_router.post("/{notification_id}/read", status_code=204)
def staff_read(request: Request, staff: _Staff, notification_id: str) -> Response:
    _agency_staff(staff)
    _read(request, recipient_kind="staff", recipient_id=staff["id"], notification_id=notification_id)
    return Response(status_code=204)
