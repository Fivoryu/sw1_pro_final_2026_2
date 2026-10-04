from __future__ import annotations

import hashlib
import json
import sqlite3
import time
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.core.money import format_money_amount, validate_currency, TOKEN_UNIT_SCALES
from app.modules.agencies.models import AgencyWallet
from app.modules.catalog.models import Listing, QuoteSnapshot
from app.modules.customer_identity.models import CustomerWallet
from app.modules.identity.models import Agency
from app.modules.customer_identity.session import ActiveCustomer
from app.modules.identity.session import ActiveStaff
from app.modules.reservations import chain
from app.modules.reservations.authorization import (
    ReservationAction,
    ensure_reservation_action_eligible,
)
from app.modules.reservations.chain import (
    PermitUnavailableError,
    RpcTransport,
    contract_deadline_seconds,
    money_to_token_units,
    issue_permit,
)
from app.modules.reservations.errors import ReservationApiError
from app.modules.reservations.models import Reservation, ReservationChainTransaction
from app.modules.reservations.schemas import (
    ReservationChainTransactionResponse,
    ReservationResponse,
)

_ACTIVE_STATUSES = ("pending", "accepted")
_DECISION_WINDOW = timedelta(hours=24)
_STAFF_ACTIONS: tuple[ReservationAction, ...] = ("accept", "reject", "cancel")
_CUSTOMER_ACTIONS = ("deposit", "cancel", "expire")
_CHAIN_ACTIONS = ("deposit", "accept", "reject", "cancel", "expire")


def _authorized_staff_action(action: str) -> ReservationAction:
    """Authorize one staff action and narrow it to the contract-level literal."""
    for allowed in _STAFF_ACTIONS:
        if action == allowed:
            return allowed
    raise ReservationApiError(
        403,
        "reservation_action_forbidden",
        "The actor is not allowed to request this action.",
    )


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _begin_sqlite_immediate(session: Session) -> None:
    """Acquire SQLite's write reservation before inspecting listing availability."""
    connection = session.connection()
    deadline = time.monotonic() + 30
    while True:
        try:
            connection.exec_driver_sql("BEGIN IMMEDIATE")
            return
        except OperationalError as error:
            error_code = getattr(error.orig, "sqlite_errorcode", None)
            is_lock_error = error_code is not None and error_code & 0xFF in {
                sqlite3.SQLITE_BUSY,
                sqlite3.SQLITE_LOCKED,
            }
            if not is_lock_error and "locked" not in str(error.orig).casefold():
                raise
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.01)


def _reservation_currency(reservation: Reservation) -> str:
    """Derive the reservation currency from its persisted quote snapshot lines."""
    return validate_currency(
        next(
            (line.get("currency") for line in reservation.quote_lines if line.get("kind") == "base"),
            "BOB",
        )
    )


def _deposit_token_units(reservation: Reservation) -> int:
    """Scale the deposit to on-chain token units using its currency precision."""
    return money_to_token_units(
        reservation.deposit_amount,
        token_scale=TOKEN_UNIT_SCALES[_reservation_currency(reservation)],
    )


def _fingerprint(*, listing_id: str, quote_id: str, customer_wallet_id: str) -> str:
    body = {
        "customer_wallet_id": customer_wallet_id,
        "listing_id": listing_id,
        "quote_id": quote_id,
    }
    canonical = json.dumps(body, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _reservation_response(reservation: Reservation) -> ReservationResponse:
    deposit = reservation.deposit_amount
    currency = _reservation_currency(reservation)
    quote_lines = [{**line, "currency": currency} for line in reservation.quote_lines]
    return ReservationResponse.model_validate(
        {
            "reservation_id": reservation.id,
            "listing_id": reservation.listing_id,
            "status": reservation.status,
            "api_created_at": _as_utc(reservation.api_created_at),
            "decision_deadline_at": _as_utc(reservation.decision_deadline_at),
            "quote_snapshot": {
                "quote_id": reservation.quote_id,
                "offer_version": reservation.offer_version,
                "operation": reservation.operation,
                "lines": quote_lines,
                "one_time_total": {
                    "amount": format_money_amount(reservation.one_time_total),
                    "currency": currency,
                },
                "monthly_total": {
                    "amount": format_money_amount(reservation.monthly_total),
                    "currency": currency,
                },
            },
            "deposit_amount": format_money_amount(deposit) if deposit is not None else None,
        }
    )


def _expire_due_reservations(
    session: Session,
    *,
    now: datetime,
    listing_id: str | None = None,
    customer_id: str | None = None,
) -> int:
    query = session.query(Reservation).filter(
        Reservation.status == "pending",
        Reservation.decision_deadline_at <= _as_utc(now),
        Reservation.deposit_confirmed_at.is_(None),
    )
    if listing_id is not None:
        query = query.filter(Reservation.listing_id == listing_id)
    if customer_id is not None:
        query = query.filter(Reservation.customer_id == customer_id)
    if session.get_bind().dialect.name == "postgresql":
        query = query.with_for_update()
    expired = query.all()
    for reservation in expired:
        reservation.status = "expired"
    return len(expired)


def expire_unpaid_reservations(
    *,
    session_factory: sessionmaker[Session],
    now: datetime,
    listing_id: str | None = None,
    customer_id: str | None = None,
) -> int:
    """Expire only overdue pending reservations without a confirmed deposit."""
    with session_factory.begin() as session:
        if session.get_bind().dialect.name == "sqlite":
            _begin_sqlite_immediate(session)
        return _expire_due_reservations(
            session,
            now=now,
            listing_id=listing_id,
            customer_id=customer_id,
        )


def _existing_idempotent_reservation(
    session: Session,
    *,
    customer_id: str,
    idempotency_key: str,
    fingerprint: str,
) -> ReservationResponse | None:
    reservation = (
        session.query(Reservation)
        .filter(
            Reservation.customer_id == customer_id,
            Reservation.idempotency_key == idempotency_key,
        )
        .one_or_none()
    )
    if reservation is None:
        return None
    if reservation.request_fingerprint != fingerprint:
        raise ReservationApiError(
            409,
            "idempotency_key_reused",
            "The Idempotency-Key was already used with a different request body.",
        )
    return _reservation_response(reservation)


def create_reservation(
    *,
    session_factory: sessionmaker[Session],
    customer_id: str,
    listing_id: str,
    quote_id: str,
    customer_wallet_id: str,
    idempotency_key: str,
    now: datetime,
) -> ReservationResponse:
    """Atomically validate and persist one customer reservation."""
    if not idempotency_key.strip():
        raise ReservationApiError(
            422,
            "validation_error",
            "The Idempotency-Key must contain a non-whitespace character.",
        )

    api_created_at = _as_utc(now)
    request_fingerprint = _fingerprint(
        listing_id=listing_id,
        quote_id=quote_id,
        customer_wallet_id=customer_wallet_id,
    )
    try:
        with session_factory.begin() as session:
            if session.get_bind().dialect.name == "sqlite":
                _begin_sqlite_immediate(session)

            replay = _existing_idempotent_reservation(
                session,
                customer_id=customer_id,
                idempotency_key=idempotency_key,
                fingerprint=request_fingerprint,
            )
            if replay is not None:
                return replay

            listing_query = session.query(Listing).filter(
                Listing.id == listing_id,
                Listing.approval_status == "approved",
                Listing.is_published.is_(True),
            )
            if session.get_bind().dialect.name == "postgresql":
                listing_query = listing_query.with_for_update()
            listing = listing_query.one_or_none()
            if listing is None:
                raise ReservationApiError(404, "listing_not_found", "The public listing was not found.")

            _expire_due_reservations(session, now=api_created_at, listing_id=listing.id)

            active = (
                session.query(Reservation)
                .filter(
                    Reservation.listing_id == listing.id,
                    Reservation.status.in_(_ACTIVE_STATUSES),
                )
                .one_or_none()
            )
            if active is not None:
                raise ReservationApiError(
                    409,
                    "listing_has_active_reservation",
                    "The listing already has an active reservation.",
                )

            customer_wallet = (
                session.query(CustomerWallet)
                .filter(
                    CustomerWallet.id == customer_wallet_id,
                    CustomerWallet.customer_id == customer_id,
                )
                .one_or_none()
            )
            if customer_wallet is None:
                raise ReservationApiError(
                    403,
                    "customer_wallet_not_linked",
                    "A linked customer wallet is required to reserve a listing.",
                )

            agency_wallet = (
                session.query(AgencyWallet)
                .filter(AgencyWallet.agency_id == listing.agency_id)
                .one_or_none()
            )
            if agency_wallet is None:
                raise ReservationApiError(
                    409,
                    "agency_wallet_not_linked",
                    "The listing agency must link a wallet before reservations can be created.",
                )

            quote = (
                session.query(QuoteSnapshot)
                .filter(
                    QuoteSnapshot.id == quote_id,
                    QuoteSnapshot.listing_id == listing.id,
                )
                .one_or_none()
            )
            if quote is None:
                raise ReservationApiError(
                    404,
                    "quote_not_found",
                    "A quote for this listing was not found.",
                )
            if api_created_at >= _as_utc(quote.expires_at):
                raise ReservationApiError(409, "quote_expired", "The quote has expired.")
            if quote.offer_version != listing.offer_version:
                raise ReservationApiError(
                    409,
                    "offer_version_mismatch",
                    "The quote no longer matches the listing offer.",
                )

            reservation = Reservation(
                id=str(uuid4()),
                listing_id=listing.id,
                quote_id=quote.id,
                customer_id=customer_id,
                customer_wallet_id=customer_wallet.id,
                agency_wallet_id=agency_wallet.id,
                customer_wallet_address=customer_wallet.address,
                agency_wallet_address=agency_wallet.address,
                offer_version=quote.offer_version,
                operation=quote.operation,
                quote_lines=[dict(line) for line in quote.lines],
                one_time_total=quote.one_time_total,
                monthly_total=quote.monthly_total,
                deposit_amount=listing.deposit_amount,
                api_created_at=api_created_at,
                decision_deadline_at=api_created_at + _DECISION_WINDOW,
                status="pending",
                idempotency_key=idempotency_key,
                request_fingerprint=request_fingerprint,
            )
            session.add(reservation)
            session.flush()
            return _reservation_response(reservation)
    except IntegrityError as integrity_error:
        with session_factory() as session:
            replay = _existing_idempotent_reservation(
                session,
                customer_id=customer_id,
                idempotency_key=idempotency_key,
                fingerprint=request_fingerprint,
            )
            if replay is not None:
                return replay
            active = (
                session.query(Reservation)
                .filter(
                    Reservation.listing_id == listing_id,
                    Reservation.status.in_(_ACTIVE_STATUSES),
                )
                .one_or_none()
            )
            if active is not None:
                raise ReservationApiError(
                    409,
                    "listing_has_active_reservation",
                    "The listing already has an active reservation.",
                ) from None
        raise integrity_error


def list_customer_reservations(
    *, session_factory: sessionmaker[Session], customer_id: str, now: datetime
) -> list[ReservationResponse]:
    with session_factory.begin() as session:
        if session.get_bind().dialect.name == "sqlite":
            _begin_sqlite_immediate(session)
        _expire_due_reservations(session, now=now, customer_id=customer_id)
        reservations = (
            session.query(Reservation)
            .filter(Reservation.customer_id == customer_id)
            .order_by(Reservation.api_created_at.desc(), Reservation.id.desc())
            .all()
        )
        return [_reservation_response(reservation) for reservation in reservations]


def get_customer_reservation(
    *,
    session_factory: sessionmaker[Session],
    customer_id: str,
    reservation_id: str,
    now: datetime,
) -> ReservationResponse:
    with session_factory.begin() as session:
        if session.get_bind().dialect.name == "sqlite":
            _begin_sqlite_immediate(session)
        _expire_due_reservations(session, now=now, customer_id=customer_id)
        reservation = (
            session.query(Reservation)
            .filter(
                Reservation.id == reservation_id,
                Reservation.customer_id == customer_id,
            )
            .one_or_none()
        )
        if reservation is None:
            raise ReservationApiError(
                404,
                "reservation_not_found",
                "The reservation was not found.",
            )
        return _reservation_response(reservation)


def _ensure_deposit_request_eligible(
    reservation: Reservation, *, now: datetime, require_before_deadline: bool = True
) -> None:
    if reservation.status != "pending":
        raise ReservationApiError(
            409,
            "reservation_not_pending",
            "Only a pending reservation can receive this action request.",
        )
    if require_before_deadline and _as_utc(now) >= _as_utc(reservation.decision_deadline_at):
        raise ReservationApiError(
            409,
            "reservation_decision_deadline_passed",
            "The reservation decision deadline has passed.",
        )
    if reservation.deposit_amount is None:
        raise ReservationApiError(
            409,
            "reservation_deposit_not_configured",
            "A configured deposit is required for a deposit permit.",
        )
    if reservation.deposit_confirmed_at is not None:
        raise ReservationApiError(
            409,
            "reservation_deposit_already_confirmed",
            "The reservation deposit is already confirmed.",
        )


def _wallet_snapshot_matches(wallet_address: str, reservation_address: str) -> bool:
    return wallet_address.lower() == reservation_address.lower()


def issue_reservation_permit(
    *,
    session_factory: sessionmaker[Session],
    settings: Settings,
    transport: RpcTransport | None,
    reservation_id: str,
    actor: ActiveCustomer | ActiveStaff,
    action: str,
    now: datetime,
) -> dict[str, object]:
    """Authorize and sign an action using only the persisted reservation snapshot."""
    is_staff = "role" in actor
    staff_action = _authorized_staff_action(action) if is_staff else None
    if not is_staff and action not in _CUSTOMER_ACTIONS:
        raise ReservationApiError(
            403,
            "reservation_action_forbidden",
            "The actor is not allowed to request this action.",
        )

    with session_factory() as session:
        reservation = session.get(Reservation, reservation_id)
        if reservation is None:
            raise ReservationApiError(
                404,
                "reservation_not_found",
                "The reservation was not found.",
            )
        if not is_staff and actor["id"] != reservation.customer_id:
            raise ReservationApiError(
                404,
                "reservation_not_found",
                "The reservation was not found.",
            )

        agency_wallet = session.get(AgencyWallet, reservation.agency_wallet_id)
        if agency_wallet is None:
            raise ReservationApiError(
                409,
                "agency_wallet_mismatch",
                "The reservation agency wallet snapshot is unavailable.",
            )
        agency = session.get(Agency, agency_wallet.agency_id)
        if agency is None:
            raise ReservationApiError(
                409,
                "agency_wallet_mismatch",
                "The reservation agency wallet snapshot is unavailable.",
            )

        if staff_action is not None:
            ensure_reservation_action_eligible(
                reservation,
                actor,
                action=staff_action,
                now=now,
                reservation_agency_id=agency_wallet.agency_id,
            )
            if not _wallet_snapshot_matches(agency_wallet.address, reservation.agency_wallet_address):
                raise ReservationApiError(
                    409,
                    "agency_wallet_mismatch",
                    "The reservation agency wallet does not match its persisted snapshot.",
                )
        elif action == "cancel":
            ensure_reservation_action_eligible(
                reservation,
                actor,
                action="cancel",
                now=now,
            )
        else:
            _ensure_deposit_request_eligible(reservation, now=now)

        customer_wallet = session.get(CustomerWallet, reservation.customer_wallet_id)
        if (
            customer_wallet is None
            or customer_wallet.customer_id != reservation.customer_id
            or not _wallet_snapshot_matches(
                customer_wallet.address,
                reservation.customer_wallet_address,
            )
        ):
            raise ReservationApiError(
                409,
                "customer_wallet_mismatch",
                "The reservation customer wallet does not match its persisted snapshot.",
            )

        try:
            amount = _deposit_token_units(reservation)
        except ValueError:
            raise ReservationApiError(
                409,
                "reservation_deposit_invalid",
                "The persisted reservation deposit is invalid.",
            ) from None
        deadline = contract_deadline_seconds(reservation.decision_deadline_at)
        action_actor = (
            reservation.agency_wallet_address if is_staff else reservation.customer_wallet_address
        )
        permit_terms = {
            "reservation_id": reservation.id,
            "listing_id": reservation.listing_id,
            "customer_address": reservation.customer_wallet_address,
            "agency_address": reservation.agency_wallet_address,
            "actor_address": action_actor,
            "amount": amount,
            "deadline": deadline,
        }

    try:
        return issue_permit(
            settings=settings,
            transport=transport,
            action=action,
            **permit_terms,
        )
    except PermitUnavailableError:
        raise ReservationApiError(
            503,
            "permit_unavailable",
            "A local reservation escrow permit is unavailable.",
        ) from None


def _chain_transaction_response(
    audit: ReservationChainTransaction,
    *,
    status: str,
    replayed: bool,
) -> ReservationChainTransactionResponse:
    return ReservationChainTransactionResponse.model_validate(
        {
            "reservation_id": audit.reservation_id,
            "status": status,
            "replayed": replayed,
            "chain_id": audit.chain_id,
            "tx_hash": audit.tx_hash,
            "action": audit.action,
            "event_name": audit.event_name,
            "event_signature": audit.event_signature,
            "event_topic": audit.event_topic,
            "log_index": audit.log_index,
            "block_number": audit.block_number,
            "block_hash": audit.block_hash,
            "block_timestamp": audit.block_timestamp,
            "transaction_index": audit.transaction_index,
            "amount": audit.amount,
            "nonce": audit.nonce,
            "escrow_address": audit.escrow_address,
            "participant": audit.participant,
            "actor": audit.actor,
        }
    )


def _chain_proof_matches(
    proof: dict[str, object],
    *,
    reservation: Reservation,
    transaction_hash: str,
    action: str,
    amount: int,
    actor_address: str | None,
    nonce: int,
) -> None:
    expected_event = chain.EVENT_BY_ACTION[action]
    event_signature = chain.EVENT_SIGNATURES[expected_event]
    expected = {
        "chainId": chain.CHAIN_ID,
        "action": action,
        "event": expected_event,
        "eventSignature": event_signature,
        "topic": "0x" + chain.keccak(text=event_signature).hex(),
        "transactionHash": transaction_hash.lower(),
        "reservationId": chain.hash_api_id(reservation.id),
        "listingId": chain.hash_api_id(reservation.listing_id),
        "amount": amount,
        "nonce": nonce,
        "actor": actor_address,
    }
    for field, expected_value in expected.items():
        actual = proof.get(field)
        if field == "transactionHash" and isinstance(actual, str):
            actual = actual.lower()
        if field == "actor" and isinstance(actual, str) and isinstance(expected_value, str):
            actual = actual.lower()
            expected_value = expected_value.lower()
        if actual != expected_value:
            raise ReservationApiError(
                422,
                "chain_transaction_unverified",
                "The submitted transaction proof does not match the reservation action.",
            )
    for field in (
        "blockNumber",
        "blockTimestamp",
        "logIndex",
        "amount",
        "nonce",
    ):
        value = proof.get(field)
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise ReservationApiError(
                422,
                "chain_transaction_unverified",
                "The submitted transaction proof is incomplete.",
            )


def _audit_context_matches(
    audit: ReservationChainTransaction,
    *,
    reservation_id: str,
    action: str,
    nonce: int,
    amount: int,
    actor_address: str | None,
) -> bool:
    return (
        audit.reservation_id == reservation_id
        and audit.action == action
        and audit.nonce == nonce
        and audit.amount == amount
        and (audit.actor or "").lower() == (actor_address or "").lower()
    )


def _load_chain_context(
    session: Session,
    *,
    reservation_id: str,
    actor: ActiveCustomer | ActiveStaff,
    action: str,
    now: datetime,
    allow_replay: bool = False,
) -> tuple[Reservation, str | None, int]:
    reservation = session.get(Reservation, reservation_id)
    if reservation is None:
        raise ReservationApiError(404, "reservation_not_found", "The reservation was not found.")
    if action not in _CHAIN_ACTIONS:
        raise ReservationApiError(422, "validation_error", "The reservation action is invalid.")

    agency_wallet = session.get(AgencyWallet, reservation.agency_wallet_id)
    if agency_wallet is None or not _wallet_snapshot_matches(
        agency_wallet.address, reservation.agency_wallet_address
    ):
        raise ReservationApiError(
            409,
            "agency_wallet_mismatch",
            "The reservation agency wallet does not match its persisted snapshot.",
        )

    is_staff = "role" in actor
    if is_staff:
        if action == "expire":
            if (
                actor["role"] != "agency_admin"
                or actor["tenant_id"] is None
                or actor["tenant_id"] != agency_wallet.agency_id
            ):
                raise ReservationApiError(
                    403,
                    "reservation_action_forbidden",
                    "The actor is not allowed to request this action.",
                )
            if not allow_replay and (
                reservation.status != "pending" or reservation.deposit_confirmed_at is None
            ):
                raise ReservationApiError(
                    409,
                    "reservation_not_expirable",
                    "Only a deposited pending reservation can be expired on chain.",
                )
        else:
            if action == "deposit":
                raise ReservationApiError(
                    403,
                    "reservation_action_forbidden",
                    "The actor is not allowed to request this action.",
                )
            if allow_replay:
                if (
                    actor["role"] != "agency_admin"
                    or actor["tenant_id"] is None
                    or actor["tenant_id"] != agency_wallet.agency_id
                ):
                    raise ReservationApiError(
                        403,
                        "reservation_action_forbidden",
                        "The actor is not allowed to request this action.",
                    )
            else:
                ensure_reservation_action_eligible(
                    reservation,
                    actor,
                    action=action,  # type: ignore[arg-type]
                    now=now,
                    reservation_agency_id=agency_wallet.agency_id,
                    # Reconcile authorizes an already-mined event; the receipt verifier
                    # enforces the contract deadline against its block timestamp.
                    require_before_deadline=False,
                )
        actor_address = reservation.agency_wallet_address
    else:
        customer_wallet = session.get(CustomerWallet, reservation.customer_wallet_id)
        if customer_wallet is None or customer_wallet.customer_id != reservation.customer_id:
            raise ReservationApiError(
                409,
                "customer_wallet_mismatch",
                "The reservation customer wallet is unavailable.",
            )
        if not _wallet_snapshot_matches(
            customer_wallet.address, reservation.customer_wallet_address
        ):
            raise ReservationApiError(
                409,
                "customer_wallet_mismatch",
                "The reservation customer wallet does not match its persisted snapshot.",
            )
        if actor["id"] != reservation.customer_id:
            raise ReservationApiError(404, "reservation_not_found", "The reservation was not found.")
        if action == "deposit":
            if not allow_replay:
                _ensure_deposit_request_eligible(
                    reservation, now=now, require_before_deadline=False
                )
        elif action == "expire":
            if not allow_replay and (
                reservation.status != "pending" or reservation.deposit_confirmed_at is None
            ):
                raise ReservationApiError(
                    409,
                    "reservation_not_expirable",
                    "Only a deposited pending reservation can be expired on chain.",
                )
        elif not allow_replay:
            ensure_reservation_action_eligible(
                reservation,
                actor,
                action="cancel",
                now=now,
                # Reconcile authorizes an already-mined event; the receipt verifier
                # enforces the contract deadline against its block timestamp.
                require_before_deadline=False,
            )
        actor_address = reservation.customer_wallet_address

    if action in {"accept", "reject", "deposit"}:
        amount = _deposit_token_units(reservation)
        if action in {"accept", "reject"} and amount and reservation.deposit_confirmed_at is None:
            raise ReservationApiError(
                409,
                "reservation_deposit_not_confirmed",
                "The reservation deposit must be confirmed before this decision.",
            )
    elif action == "expire":
        amount = _deposit_token_units(reservation)
    else:
        amount = _deposit_token_units(reservation)
        if reservation.deposit_confirmed_at is None:
            amount = 0
    return reservation, actor_address if action != "expire" else None, amount


def reconcile_chain_transaction(
    *,
    session_factory: sessionmaker[Session],
    settings: Settings,
    transport: RpcTransport | None,
    reservation_id: str,
    actor: ActiveCustomer | ActiveStaff,
    action: str,
    transaction_hash: str,
    nonce: int,
    now: datetime,
) -> ReservationChainTransactionResponse:
    """Verify one local receipt, then atomically append proof and transition state."""
    is_staff = "role" in actor
    if not is_staff and action not in _CUSTOMER_ACTIONS:
        raise ReservationApiError(
            403,
            "reservation_action_forbidden",
            "The actor is not allowed to request this action.",
        )
    normalized_hash = transaction_hash.lower()
    with session_factory() as session:
        reservation = session.get(Reservation, reservation_id)
        if reservation is None:
            raise ReservationApiError(404, "reservation_not_found", "The reservation was not found.")
        existing = (
            session.query(ReservationChainTransaction)
            .filter(
                ReservationChainTransaction.chain_id == chain.CHAIN_ID,
                ReservationChainTransaction.tx_hash == normalized_hash,
            )
            .one_or_none()
        )
        if existing is not None:
            _, replay_actor_address, replay_amount = _load_chain_context(
                session,
                reservation_id=reservation_id,
                actor=actor,
                action=action,
                now=now,
                allow_replay=True,
            )
            if not _audit_context_matches(
                existing,
                reservation_id=reservation.id,
                action=action,
                nonce=nonce,
                amount=replay_amount,
                actor_address=replay_actor_address,
            ):
                raise ReservationApiError(
                    409,
                    "chain_transaction_reused",
                    "The transaction hash is already bound to another reservation action.",
                )
            return _chain_transaction_response(existing, status=reservation.status, replayed=True)
        _, actor_address, expected_amount = _load_chain_context(
            session, reservation_id=reservation_id, actor=actor, action=action, now=now
        )

    try:
        proof = chain.verify_action_receipt(
            settings=settings,
            transport=transport,
            transaction_hash=transaction_hash,
            reservation_id=reservation.id,
            listing_id=reservation.listing_id,
            customer_address=reservation.customer_wallet_address,
            agency_address=reservation.agency_wallet_address,
            action=action,
            amount=expected_amount,
            nonce=nonce,
            deadline=reservation.decision_deadline_at,
            actor_address=actor_address,
        )
    except PermitUnavailableError:
        raise ReservationApiError(
            422,
            "chain_transaction_unverified",
            "The submitted transaction could not be verified against the local escrow.",
        ) from None

    _chain_proof_matches(
        proof,
        reservation=reservation,
        transaction_hash=transaction_hash,
        action=action,
        amount=expected_amount,
        actor_address=actor_address,
        nonce=nonce,
    )

    try:
        with session_factory.begin() as session:
            if session.get_bind().dialect.name == "sqlite":
                _begin_sqlite_immediate(session)
            reservation_query = session.query(Reservation).filter(Reservation.id == reservation_id)
            if session.get_bind().dialect.name == "postgresql":
                reservation_query = reservation_query.with_for_update()
            locked_reservation = reservation_query.one_or_none()
            if locked_reservation is None:
                raise ReservationApiError(
                    404, "reservation_not_found", "The reservation was not found."
                )
            _, locked_actor_address, locked_amount = _load_chain_context(
                session,
                reservation_id=reservation_id,
                actor=actor,
                action=action,
                now=now,
                allow_replay=True,
            )
            existing = (
                session.query(ReservationChainTransaction)
                .filter(
                    ReservationChainTransaction.chain_id == chain.CHAIN_ID,
                    ReservationChainTransaction.tx_hash == normalized_hash,
                )
                .one_or_none()
            )
            if existing is not None:
                if not _audit_context_matches(
                    existing,
                    reservation_id=reservation_id,
                    action=action,
                    nonce=nonce,
                    amount=locked_amount,
                    actor_address=locked_actor_address,
                ):
                    raise ReservationApiError(
                        409,
                        "chain_transaction_reused",
                        "The transaction hash is already bound to another reservation action.",
                    )
                return _chain_transaction_response(
                    existing, status=locked_reservation.status, replayed=True
                )
            _, locked_actor_address, locked_amount = _load_chain_context(
                session,
                reservation_id=reservation_id,
                actor=actor,
                action=action,
                now=now,
            )
            audit = ReservationChainTransaction(
                reservation_id=reservation_id,
                chain_id=chain.CHAIN_ID,
                tx_hash=normalized_hash,
                action=action,
                event_name=str(proof["event"]),
                event_signature=str(proof["eventSignature"]),
                event_topic=str(proof["topic"]),
                log_index=int(proof["logIndex"]),
                block_number=int(proof["blockNumber"]),
                block_hash=str(proof["blockHash"]),
                block_timestamp=int(proof["blockTimestamp"]),
                transaction_index=(
                    int(proof["transactionIndex"])
                    if proof.get("transactionIndex") is not None
                    else None
                ),
                amount=int(proof["amount"]),
                nonce=int(proof["nonce"]),
                escrow_address=str(proof["escrowAddress"]),
                participant=str(proof["participant"]),
                actor=str(proof["actor"]) if proof.get("actor") is not None else None,
            )
            session.add(audit)
            if action == "deposit":
                locked_reservation.deposit_confirmed_at = datetime.fromtimestamp(
                    int(proof["blockTimestamp"]), tz=timezone.utc
                )
            else:
                locked_reservation.status = {
                    "accept": "accepted",
                    "reject": "rejected",
                    "cancel": "cancelled",
                    "expire": "expired",
                }[action]
            session.flush()
            return _chain_transaction_response(
                audit, status=locked_reservation.status, replayed=False
            )
    except IntegrityError:
        with session_factory() as session:
            existing = (
                session.query(ReservationChainTransaction)
                .filter(
                    ReservationChainTransaction.chain_id == chain.CHAIN_ID,
                    ReservationChainTransaction.tx_hash == normalized_hash,
                )
                .one_or_none()
            )
            if existing is not None:
                reservation = session.get(Reservation, reservation_id)
                if reservation is not None:
                    _, replay_actor_address, replay_amount = _load_chain_context(
                        session,
                        reservation_id=reservation_id,
                        actor=actor,
                        action=action,
                        now=now,
                        allow_replay=True,
                    )
                    if _audit_context_matches(
                        existing,
                        reservation_id=reservation_id,
                        action=action,
                        nonce=nonce,
                        amount=replay_amount,
                        actor_address=replay_actor_address,
                    ):
                        return _chain_transaction_response(
                            existing, status=reservation.status, replayed=True
                        )
        raise ReservationApiError(
            409,
            "chain_transaction_reused",
            "The transaction hash is already bound to another reservation action.",
        ) from None
