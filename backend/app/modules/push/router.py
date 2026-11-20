"""Device token registration for customers and agency staff."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.core.errors import ERROR_RESPONSES
from app.modules.customer_identity.session import ActiveCustomer, get_active_customer
from app.modules.identity.session import ActiveStaff, get_active_staff
from app.modules.push.models import DeviceToken

MAX_TOKENS_PER_RECIPIENT = 10

customer_router = APIRouter(
    prefix="/api/v1/customer/devices", tags=["customer-devices"], responses=ERROR_RESPONSES
)
staff_router = APIRouter(
    prefix="/api/v1/staff/devices", tags=["staff-devices"], responses=ERROR_RESPONSES
)

_Customer = Annotated[ActiveCustomer, Depends(get_active_customer)]
_Staff = Annotated[ActiveStaff, Depends(get_active_staff)]


class DeviceRegistration(BaseModel):
    token: str = Field(min_length=20, max_length=512)
    platform: Literal["android", "ios"] = "android"


class DeviceRemoval(BaseModel):
    token: str = Field(min_length=20, max_length=512)


def _factory(request: Request) -> sessionmaker[Session]:
    factory: sessionmaker[Session] = request.app.state.session_factory
    return factory


def _now(request: Request) -> datetime:
    now: datetime = request.app.state.clock()
    return now


def _agency_staff(staff: ActiveStaff) -> None:
    if staff["role"] not in ("agent", "agency_admin") or staff["tenant_id"] is None:
        raise HTTPException(status_code=403, detail="Agency staff access is required")


def _register(
    request: Request, *, kind: str, recipient_id: str, body: DeviceRegistration
) -> None:
    now = _now(request)
    for attempt in range(2):
        try:
            with _factory(request).begin() as session:
                existing = session.scalars(
                    select(DeviceToken).where(DeviceToken.token == body.token)
                ).one_or_none()
                if existing is not None:
                    # A token belongs to the device, so a new login on it takes the token over.
                    existing.recipient_kind = kind
                    existing.recipient_id = recipient_id
                    existing.platform = body.platform
                    existing.updated_at = now
                else:
                    session.add(
                        DeviceToken(
                            recipient_kind=kind,
                            recipient_id=recipient_id,
                            token=body.token,
                            platform=body.platform,
                            created_at=now,
                            updated_at=now,
                        )
                    )
                session.flush()
                owned = session.scalars(
                    select(DeviceToken)
                    .where(
                        DeviceToken.recipient_kind == kind,
                        DeviceToken.recipient_id == recipient_id,
                    )
                    .order_by(DeviceToken.updated_at.desc(), DeviceToken.id)
                ).all()
                for stale in owned[MAX_TOKENS_PER_RECIPIENT:]:
                    session.delete(stale)
            return
        except IntegrityError:
            # Two registrations of the same new token raced; the second attempt updates it.
            if attempt == 1:
                raise


def _remove(request: Request, *, kind: str, recipient_id: str, token: str) -> None:
    with _factory(request).begin() as session:
        session.execute(
            delete(DeviceToken).where(
                DeviceToken.token == token,
                DeviceToken.recipient_kind == kind,
                DeviceToken.recipient_id == recipient_id,
            )
        )


@customer_router.post("", status_code=204)
def register_customer_device(
    request: Request, customer: _Customer, body: DeviceRegistration
) -> Response:
    _register(request, kind="customer", recipient_id=customer["id"], body=body)
    return Response(status_code=204)


@customer_router.post("/remove", status_code=204)
def remove_customer_device(request: Request, customer: _Customer, body: DeviceRemoval) -> Response:
    _remove(request, kind="customer", recipient_id=customer["id"], token=body.token)
    return Response(status_code=204)


@staff_router.post("", status_code=204)
def register_staff_device(request: Request, staff: _Staff, body: DeviceRegistration) -> Response:
    _agency_staff(staff)
    _register(request, kind="staff", recipient_id=staff["id"], body=body)
    return Response(status_code=204)


@staff_router.post("/remove", status_code=204)
def remove_staff_device(request: Request, staff: _Staff, body: DeviceRemoval) -> Response:
    _agency_staff(staff)
    _remove(request, kind="staff", recipient_id=staff["id"], token=body.token)
    return Response(status_code=204)
