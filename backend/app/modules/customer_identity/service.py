from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.core.security import hash_password, hash_secret, random_token, verify_password
from app.modules.customer_identity.models import CustomerAccount, CustomerSession

ACCESS_TOKEN_MINUTES = 15
ACCESS_TOKEN_SECONDS = ACCESS_TOKEN_MINUTES * 60
REFRESH_TOKEN_DAYS = 7
IDLE_WINDOW = timedelta(minutes=30)


class DuplicateCustomerEmailError(Exception):
    pass


class InvalidCustomerCredentialsError(Exception):
    pass


class InvalidCustomerSessionError(Exception):
    pass


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _access_token(
    *,
    customer_id: str,
    session_id: str,
    signing_key: str,
    now: datetime,
) -> str:
    issued_at = int(_as_utc(now).timestamp())
    return jwt.encode(
        {
            "sub": customer_id,
            "sid": session_id,
            "type": "access",
            "aud": "roomforge-customer",
            "iat": issued_at,
            "exp": issued_at + ACCESS_TOKEN_SECONDS,
        },
        signing_key,
        algorithm="HS256",
    )


def _token_pair(
    *,
    customer_id: str,
    session_id: str,
    refresh_token: str,
    settings: Settings,
    now: datetime,
) -> dict[str, str | int]:
    return {
        "access_token": _access_token(
            customer_id=customer_id,
            session_id=session_id,
            signing_key=settings.jwt_secret,
            now=now,
        ),
        "refresh_token": refresh_token,
        "token_type": "Bearer",
        "access_expires_in": ACCESS_TOKEN_SECONDS,
    }


def register_customer(
    *,
    session_factory: sessionmaker[Session],
    email: str,
    password: str,
) -> dict[str, str]:
    normalized_email = email.strip().lower()
    try:
        with session_factory.begin() as session:
            account = (
                session.query(CustomerAccount)
                .filter(func.lower(func.trim(CustomerAccount.email)) == normalized_email)
                .one_or_none()
            )
            if account is not None:
                raise DuplicateCustomerEmailError

            account = CustomerAccount(
                id=str(uuid4()),
                email=normalized_email,
                password_hash=hash_password(password),
            )
            session.add(account)
            session.flush()
            return {"id": account.id, "email": account.email}
    except IntegrityError:
        raise DuplicateCustomerEmailError from None


def login_customer(
    *,
    session_factory: sessionmaker[Session],
    settings: Settings,
    email: str,
    password: str,
    now: datetime,
) -> dict[str, str | int]:
    normalized_email = email.strip().lower()
    now_utc = _as_utc(now)
    refresh_token = random_token()
    session_id = str(uuid4())
    refresh_expires_at = now_utc + timedelta(days=REFRESH_TOKEN_DAYS)
    unauthorized = False
    token_pair: dict[str, str | int] | None = None

    with session_factory.begin() as session:
        account = (
            session.query(CustomerAccount)
            .filter(func.lower(func.trim(CustomerAccount.email)) == normalized_email)
            .with_for_update()
            .one_or_none()
        )
        password_hash = account.password_hash if account is not None else _DUMMY_PASSWORD_HASH
        valid_password = verify_password(password_hash, password)
        if account is None or not valid_password:
            unauthorized = True
        else:
            customer_session = CustomerSession(
                id=session_id,
                customer_id=account.id,
                refresh_token_hash=hash_secret(refresh_token),
                created_at=now_utc,
                last_activity_at=now_utc,
                expires_at=refresh_expires_at,
            )
            session.add(customer_session)
            session.flush()
            token_pair = _token_pair(
                customer_id=account.id,
                session_id=session_id,
                refresh_token=refresh_token,
                settings=settings,
                now=now_utc,
            )

    if unauthorized or token_pair is None:
        raise InvalidCustomerCredentialsError
    return token_pair


def refresh_customer_session(
    *,
    session_factory: sessionmaker[Session],
    settings: Settings,
    refresh_token: str,
    now: datetime,
) -> dict[str, str | int]:
    now_utc = _as_utc(now)
    previous_hash = hash_secret(refresh_token)
    next_refresh_token = random_token()
    next_session_id = str(uuid4())
    next_expiration = now_utc + timedelta(days=REFRESH_TOKEN_DAYS)
    unauthorized = False
    token_pair: dict[str, str | int] | None = None

    with session_factory.begin() as session:
        previous_session = (
            session.query(CustomerSession)
            .filter(CustomerSession.refresh_token_hash == previous_hash)
            .with_for_update()
            .one_or_none()
        )
        if previous_session is None or previous_session.revoked_at is not None:
            unauthorized = True
        elif (
            _as_utc(previous_session.expires_at) <= now_utc
            or now_utc > _as_utc(previous_session.last_activity_at) + IDLE_WINDOW
        ):
            previous_session.revoked_at = now_utc
            unauthorized = True
        else:
            account = (
                session.query(CustomerAccount)
                .filter(CustomerAccount.id == previous_session.customer_id)
                .with_for_update()
                .one_or_none()
            )
            if account is None:
                previous_session.revoked_at = now_utc
                unauthorized = True
            else:
                claimed = (
                    session.query(CustomerSession)
                    .filter(
                        CustomerSession.id == previous_session.id,
                        CustomerSession.revoked_at.is_(None),
                    )
                    .update(
                        {CustomerSession.revoked_at: now_utc},
                        synchronize_session=False,
                    )
                )
                if claimed != 1:
                    unauthorized = True
                else:
                    next_session = CustomerSession(
                        id=next_session_id,
                        customer_id=account.id,
                        refresh_token_hash=hash_secret(next_refresh_token),
                        created_at=now_utc,
                        last_activity_at=now_utc,
                        expires_at=next_expiration,
                    )
                    session.add(next_session)
                    session.flush()
                    token_pair = _token_pair(
                        customer_id=account.id,
                        session_id=next_session_id,
                        refresh_token=next_refresh_token,
                        settings=settings,
                        now=now_utc,
                    )

    if unauthorized or token_pair is None:
        raise InvalidCustomerSessionError
    return token_pair


def logout_customer_session(
    *,
    session_factory: sessionmaker[Session],
    refresh_token: str,
    now: datetime,
) -> None:
    with session_factory.begin() as session:
        customer_session = (
            session.query(CustomerSession)
            .filter(CustomerSession.refresh_token_hash == hash_secret(refresh_token))
            .with_for_update()
            .one_or_none()
        )
        if customer_session is not None and customer_session.revoked_at is None:
            customer_session.revoked_at = _as_utc(now)


_DUMMY_PASSWORD_HASH = hash_password("customer-login-dummy-password")
