from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import TypedDict

import jwt
from fastapi import HTTPException, Request
from sqlalchemy.orm import Session, sessionmaker

from app.modules.customer_identity.models import CustomerAccount, CustomerSession

_IDLE_WINDOW = timedelta(minutes=30)


class ActiveCustomer(TypedDict):
    id: str
    email: str


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _invalid_session() -> HTTPException:
    return HTTPException(status_code=401, detail="Authentication failed.")


def get_active_customer(request: Request) -> ActiveCustomer:
    authorization = request.headers.get("authorization")
    credentials = authorization.split() if authorization is not None else []
    if len(credentials) != 2 or credentials[0].lower() != "bearer":
        raise _invalid_session()

    settings = request.app.state.settings
    now = _as_utc(request.app.state.clock())
    try:
        claims = jwt.decode(
            credentials[1],
            settings.jwt_secret,
            algorithms=["HS256"],
            audience="roomforge-customer",
            options={
                "require": ["sub", "sid", "type", "aud", "iat", "exp"],
                "verify_exp": False,
                "verify_iat": False,
            },
        )
    except jwt.PyJWTError:
        raise _invalid_session() from None

    customer_id = claims.get("sub")
    session_id = claims.get("sid")
    issued_at = claims.get("iat")
    expires_at = claims.get("exp")
    now_timestamp = int(now.timestamp())
    if (
        claims.get("type") != "access"
        or not isinstance(customer_id, str)
        or not customer_id
        or not isinstance(session_id, str)
        or not session_id
        or not isinstance(issued_at, int)
        or isinstance(issued_at, bool)
        or issued_at > now_timestamp
        or not isinstance(expires_at, int)
        or isinstance(expires_at, bool)
        or expires_at <= now_timestamp
    ):
        raise _invalid_session()

    session_factory: sessionmaker[Session] = request.app.state.session_factory
    unauthorized = False
    customer: ActiveCustomer | None = None
    with session_factory.begin() as session:
        customer_session = (
            session.query(CustomerSession)
            .filter(
                CustomerSession.id == session_id,
                CustomerSession.customer_id == customer_id,
            )
            .with_for_update()
            .one_or_none()
        )
        if customer_session is None or customer_session.revoked_at is not None:
            unauthorized = True
        elif (
            _as_utc(customer_session.expires_at) <= now
            or now > _as_utc(customer_session.last_activity_at) + _IDLE_WINDOW
        ):
            customer_session.revoked_at = now
            unauthorized = True
        else:
            account = (
                session.query(CustomerAccount)
                .filter(CustomerAccount.id == customer_id)
                .with_for_update()
                .one_or_none()
            )
            if account is None:
                customer_session.revoked_at = now
                unauthorized = True
            else:
                customer_session.last_activity_at = now
                customer = {"id": account.id, "email": account.email}

    if unauthorized or customer is None:
        raise _invalid_session()
    return customer
