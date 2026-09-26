from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import TypedDict

import jwt
from fastapi import HTTPException, Request
from sqlalchemy.orm import Session, sessionmaker

from app.core.security import decode_access_token
from app.modules.identity.models import StaffAccount, StaffSession


class ActiveStaff(TypedDict):
    id: str
    email: str
    role: str
    tenant_id: str | None


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def get_active_staff(request: Request) -> ActiveStaff:
    settings = request.app.state.settings
    authorization = request.headers.get("authorization")
    credentials = authorization.split() if authorization is not None else []
    if len(credentials) != 2 or credentials[0].lower() != "bearer":
        raise HTTPException(status_code=401, detail="Session is invalid or expired")

    try:
        claims = decode_access_token(credentials[1], settings.jwt_secret)
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=401, detail="Session is invalid or expired"
        ) from None

    user_id = claims.get("sub")
    session_id = claims.get("sid")
    if (
        not isinstance(user_id, str)
        or not user_id.strip()
        or not isinstance(session_id, str)
        or not session_id.strip()
    ):
        raise HTTPException(status_code=401, detail="Session is invalid or expired")

    session_factory: sessionmaker[Session] = request.app.state.session_factory
    now = _as_utc(request.app.state.clock())
    unauthorized = False
    user: ActiveStaff | None = None

    with session_factory.begin() as session:
        staff_session = (
            session.query(StaffSession)
            .filter(
                StaffSession.id == session_id,
                StaffSession.user_id == user_id,
            )
            .with_for_update()
            .one_or_none()
        )
        if staff_session is None or staff_session.revoked_at is not None:
            unauthorized = True
        elif (
            _as_utc(staff_session.expires_at) <= now
            or now - _as_utc(staff_session.last_activity_at)
            >= timedelta(minutes=settings.admin_idle_minutes)
        ):
            staff_session.revoked_at = now
            unauthorized = True
        else:
            account = (
                session.query(StaffAccount)
                .filter(StaffAccount.id == staff_session.user_id)
                .with_for_update()
                .one_or_none()
            )
            if account is None or not account.active or not account.totp_enabled:
                staff_session.revoked_at = now
                unauthorized = True
            else:
                staff_session.last_activity_at = now
                user = {
                    "id": account.id,
                    "email": account.email,
                    "role": account.role,
                    "tenant_id": account.tenant_id,
                }

    if unauthorized or user is None:
        raise HTTPException(status_code=401, detail="Session is invalid or expired")
    return user
