"""One-use EIP-191 challenges for agency wallet ownership."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import secrets
from uuid import uuid4

from eth_account import Account
from eth_account.messages import encode_defunct
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.modules.agencies.models import AgencyWallet, AgencyWalletChallenge


AGENCY_WALLET_CHALLENGE_TTL = timedelta(minutes=5)
AGENCY_WALLET_CHALLENGE_PURPOSE = "link-agency-wallet"


class AgencyWalletAlreadyLinkedError(Exception):
    pass


class AgencyWalletAddressConflictError(Exception):
    pass


class InvalidAgencyWalletChallengeError(Exception):
    pass


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _message_timestamp(value: datetime) -> str:
    return _as_utc(value).isoformat().replace("+00:00", "Z")


def _agency_wallet_unique_violation(error: IntegrityError) -> str | None:
    constraint_name = getattr(getattr(error.orig, "diag", None), "constraint_name", None)
    if constraint_name == "uq_agency_wallet_agency_id":
        return "agency"
    if constraint_name == "uq_agency_wallet_address":
        return "address"

    sqlite_message = str(error.orig)
    if sqlite_message == "UNIQUE constraint failed: agency_wallet.agency_id":
        return "agency"
    if sqlite_message == "UNIQUE constraint failed: agency_wallet.address":
        return "address"
    return None


def create_agency_wallet_challenge(
    *,
    session_factory: sessionmaker[Session],
    agency_id: str,
    address: str,
    now: datetime,
) -> dict[str, str | datetime]:
    now_utc = _as_utc(now)
    expires_at = now_utc + AGENCY_WALLET_CHALLENGE_TTL
    challenge_id = str(uuid4())
    nonce = secrets.token_hex(32)
    message = (
        "RoomForge agency wallet link\n"
        f"Agency ID: {agency_id}\n"
        f"Wallet address: {address}\n"
        f"Purpose: {AGENCY_WALLET_CHALLENGE_PURPOSE}\n"
        f"Nonce: {nonce}\n"
        f"Issued at: {_message_timestamp(now_utc)}\n"
        f"Expires at: {_message_timestamp(expires_at)}"
    )

    with session_factory.begin() as session:
        if (
            session.query(AgencyWallet.id)
            .filter(AgencyWallet.agency_id == agency_id)
            .one_or_none()
            is not None
        ):
            raise AgencyWalletAlreadyLinkedError
        session.add(
            AgencyWalletChallenge(
                id=challenge_id,
                agency_id=agency_id,
                address=address,
                purpose=AGENCY_WALLET_CHALLENGE_PURPOSE,
                nonce=nonce,
                message=message,
                issued_at=now_utc,
                expires_at=expires_at,
            )
        )
        session.flush()

    return {"challenge_id": challenge_id, "message": message, "expires_at": expires_at}


def verify_and_link_agency_wallet(
    *,
    session_factory: sessionmaker[Session],
    agency_id: str,
    challenge_id: str,
    signature: str,
    now: datetime,
) -> dict[str, str | datetime]:
    now_utc = _as_utc(now)
    claimed_challenge: tuple[str, str] | None = None

    # Commit one-time consumption before parsing or recovering an untrusted signature.
    with session_factory.begin() as session:
        challenge = (
            session.query(AgencyWalletChallenge)
            .filter(
                AgencyWalletChallenge.id == challenge_id,
                AgencyWalletChallenge.agency_id == agency_id,
                AgencyWalletChallenge.purpose == AGENCY_WALLET_CHALLENGE_PURPOSE,
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
                session.query(AgencyWalletChallenge)
                .filter(
                    AgencyWalletChallenge.id == challenge_id,
                    AgencyWalletChallenge.agency_id == agency_id,
                    AgencyWalletChallenge.consumed_at.is_(None),
                    AgencyWalletChallenge.expires_at > now_utc,
                )
                .update(
                    {AgencyWalletChallenge.consumed_at: now_utc},
                    synchronize_session=False,
                )
            )
            if consumed == 1:
                claimed_challenge = (challenge.message, challenge.address)

    if claimed_challenge is None:
        raise InvalidAgencyWalletChallengeError

    message, expected_address = claimed_challenge
    try:
        recovered_address = Account.recover_message(
            encode_defunct(text=message), signature=signature
        )
    except Exception:
        raise InvalidAgencyWalletChallengeError from None
    if recovered_address.lower() != expected_address:
        raise InvalidAgencyWalletChallengeError

    wallet_id = str(uuid4())
    try:
        with session_factory.begin() as session:
            existing_wallet = (
                session.query(AgencyWallet)
                .filter(AgencyWallet.agency_id == agency_id)
                .one_or_none()
            )
            if existing_wallet is not None:
                raise AgencyWalletAlreadyLinkedError

            session.add(
                AgencyWallet(
                    id=wallet_id,
                    agency_id=agency_id,
                    address=expected_address,
                    linked_at=now_utc,
                )
            )
            session.flush()
    except IntegrityError as error:
        conflict = _agency_wallet_unique_violation(error)
        if conflict == "agency":
            with session_factory() as session:
                linked_wallet = (
                    session.query(AgencyWallet.id)
                    .filter(AgencyWallet.agency_id == agency_id)
                    .one_or_none()
                )
            if linked_wallet is not None:
                raise AgencyWalletAlreadyLinkedError from None
        elif conflict == "address":
            raise AgencyWalletAddressConflictError from None
        raise

    return {"agency_id": agency_id, "address": expected_address, "linked_at": now_utc}
