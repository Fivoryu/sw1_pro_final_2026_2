from __future__ import annotations

import hashlib
import json
import sqlite3
import time
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session, sessionmaker

from app.modules.agencies.models import AgencyWallet
from app.modules.catalog.models import Listing, QuoteSnapshot
from app.modules.customer_identity.models import CustomerWallet
from app.modules.reservations.errors import ReservationApiError
from app.modules.reservations.models import Reservation
from app.modules.reservations.schemas import ReservationResponse

_ACTIVE_STATUSES = ("pending", "accepted")
_DECISION_WINDOW = timedelta(hours=24)


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


def _fingerprint(*, listing_id: str, quote_id: str, customer_wallet_id: str) -> str:
    body = {
        "customer_wallet_id": customer_wallet_id,
        "listing_id": listing_id,
        "quote_id": quote_id,
    }
    canonical = json.dumps(body, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _reservation_response(reservation: Reservation) -> ReservationResponse:
    deposit = reservation.deposit_amount_cop
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
                "lines": reservation.quote_lines,
                "one_time_total": {
                    "amount": format(reservation.one_time_total, ".2f"),
                    "currency": "COP",
                },
                "monthly_total": {
                    "amount": format(reservation.monthly_total, ".2f"),
                    "currency": "COP",
                },
            },
            "deposit_amount_cop": format(deposit, ".2f") if deposit is not None else None,
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
                deposit_amount_cop=listing.deposit_amount_cop,
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
