from __future__ import annotations

from datetime import datetime, timedelta, timezone
import secrets
from uuid import uuid4

import jwt
from eth_account import Account
from eth_account.messages import encode_defunct
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.core.security import hash_password, hash_secret, random_token, verify_password
from app.modules.customer_identity.models import (
    CustomerAccount,
    CustomerSession,
    CustomerWallet,
    CustomerWalletChallenge,
)

ACCESS_TOKEN_MINUTES = 15
ACCESS_TOKEN_SECONDS = ACCESS_TOKEN_MINUTES * 60
REFRESH_TOKEN_DAYS = 7
IDLE_WINDOW = timedelta(minutes=30)
WALLET_CHALLENGE_TTL = timedelta(minutes=5)
WALLET_CHALLENGE_PURPOSE = "link-customer-wallet"


class DuplicateCustomerEmailError(Exception):
    pass


class InvalidCustomerCredentialsError(Exception):
    pass


class InvalidCustomerSessionError(Exception):
    pass


class CustomerWalletAlreadyLinkedError(Exception):
    pass


class CustomerWalletAddressConflictError(Exception):
    pass


class InvalidCustomerWalletChallengeError(Exception):
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


def _wallet_message_timestamp(value: datetime) -> str:
    return _as_utc(value).isoformat().replace("+00:00", "Z")


def _customer_wallet_unique_violation(error: IntegrityError) -> str | None:
    constraint_name = getattr(getattr(error.orig, "diag", None), "constraint_name", None)
    if constraint_name == "uq_customer_wallet_customer_id":
        return "customer"
    if constraint_name == "uq_customer_wallet_address":
        return "address"

    # SQLite reports unique columns rather than the declared constraint name.
    sqlite_message = str(error.orig)
    if sqlite_message == "UNIQUE constraint failed: customer_wallet.customer_id":
        return "customer"
    if sqlite_message == "UNIQUE constraint failed: customer_wallet.address":
        return "address"
    return None


def create_customer_wallet_challenge(
    *,
    session_factory: sessionmaker[Session],
    customer_id: str,
    address: str,
    now: datetime,
) -> dict[str, str | datetime]:
    now_utc = _as_utc(now)
    expires_at = now_utc + WALLET_CHALLENGE_TTL
    challenge_id = str(uuid4())
    nonce = secrets.token_hex(32)
    message = (
        "RoomForge customer wallet link\n"
        f"Customer ID: {customer_id}\n"
        f"Wallet address: {address}\n"
        f"Purpose: {WALLET_CHALLENGE_PURPOSE}\n"
        f"Nonce: {nonce}\n"
        f"Issued at: {_wallet_message_timestamp(now_utc)}\n"
        f"Expires at: {_wallet_message_timestamp(expires_at)}"
    )

    with session_factory.begin() as session:
        existing_wallet = (
            session.query(CustomerWallet)
            .filter(CustomerWallet.customer_id == customer_id)
            .one_or_none()
        )
        if existing_wallet is not None:
            raise CustomerWalletAlreadyLinkedError
        challenge = CustomerWalletChallenge(
            id=challenge_id,
            customer_id=customer_id,
            address=address,
            purpose=WALLET_CHALLENGE_PURPOSE,
            nonce=nonce,
            message=message,
            issued_at=now_utc,
            expires_at=expires_at,
        )
        session.add(challenge)
        session.flush()

    return {"challenge_id": challenge_id, "message": message, "expires_at": expires_at}


def verify_and_link_customer_wallet(
    *,
    session_factory: sessionmaker[Session],
    customer_id: str,
    challenge_id: str,
    signature: str,
    now: datetime,
) -> dict[str, str | datetime]:
    now_utc = _as_utc(now)
    claimed_challenge: tuple[str, str] | None = None

    # Commit one-time consumption before parsing or recovering an untrusted signature.
    with session_factory.begin() as session:
        challenge = (
            session.query(CustomerWalletChallenge)
            .filter(
                CustomerWalletChallenge.id == challenge_id,
                CustomerWalletChallenge.customer_id == customer_id,
                CustomerWalletChallenge.purpose == WALLET_CHALLENGE_PURPOSE,
            )
            .with_for_update()
            .one_or_none()
        )
        if (
            challenge is not None
            and challenge.consumed_at is None
            and _as_utc(challenge.expires_at) > now_utc
        ):
            consumed = (
                session.query(CustomerWalletChallenge)
                .filter(
                    CustomerWalletChallenge.id == challenge_id,
                    CustomerWalletChallenge.customer_id == customer_id,
                    CustomerWalletChallenge.consumed_at.is_(None),
                    CustomerWalletChallenge.expires_at > now_utc,
                )
                .update(
                    {CustomerWalletChallenge.consumed_at: now_utc},
                    synchronize_session=False,
                )
            )
            if consumed == 1:
                claimed_challenge = (challenge.message, challenge.address)

    if claimed_challenge is None:
        raise InvalidCustomerWalletChallengeError

    message, expected_address = claimed_challenge
    try:
        recovered_address = Account.recover_message(
            encode_defunct(text=message), signature=signature
        )
    except Exception:
        raise InvalidCustomerWalletChallengeError from None
    if recovered_address.lower() != expected_address:
        raise InvalidCustomerWalletChallengeError

    wallet_id = str(uuid4())
    try:
        with session_factory.begin() as session:
            existing_wallet = (
                session.query(CustomerWallet)
                .filter(CustomerWallet.customer_id == customer_id)
                .one_or_none()
            )
            if existing_wallet is not None:
                raise CustomerWalletAlreadyLinkedError

            wallet = CustomerWallet(
                id=wallet_id,
                customer_id=customer_id,
                address=expected_address,
                linked_at=now_utc,
            )
            session.add(wallet)
            session.flush()
    except IntegrityError as error:
        conflict = _customer_wallet_unique_violation(error)
        if conflict == "customer":
            # Re-read only after the failed transaction has rolled back. A competing
            # transaction may have linked this account after the preflight query.
            with session_factory() as session:
                linked_wallet_id = (
                    session.query(CustomerWallet.id)
                    .filter(CustomerWallet.customer_id == customer_id)
                    .scalar()
                )
            if linked_wallet_id is not None:
                raise CustomerWalletAlreadyLinkedError from None
        elif conflict == "address":
            raise CustomerWalletAddressConflictError from None
        raise

    return {"id": wallet_id, "address": expected_address, "linked_at": now_utc}


def list_customer_wallets(
    *, session_factory: sessionmaker[Session], customer_id: str
) -> list[dict[str, str | datetime]]:
    with session_factory() as session:
        wallets = (
            session.query(CustomerWallet)
            .filter(CustomerWallet.customer_id == customer_id)
            .order_by(CustomerWallet.linked_at, CustomerWallet.id)
            .all()
        )
        return [
            {
                "id": wallet.id,
                "address": wallet.address,
                "linked_at": _as_utc(wallet.linked_at),
            }
            for wallet in wallets
        ]
