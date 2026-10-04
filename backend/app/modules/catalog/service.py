"""Public catalog queries, quote snapshots, rate limiting, and cursor handling."""

from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import json
import math
import re
import sqlite3
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP

from sqlalchemy import and_, delete, or_, text, update
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.core.money import SupportedCurrency
from app.modules.catalog.errors import (
    InvalidExtraReferenceError,
    InvalidListingTransitionError,
    InvalidQuoteExtrasError,
    QuoteExpiredError,
    QuoteNotFoundError,
    QuoteOfferVersionMismatchError,
    UnsupportedRateLimitDialectError,
)
from app.modules.catalog.models import (
    Listing,
    ListingExtra,
    ListingTransition,
    QuoteRateLimitEvent,
    QuoteSnapshot,
)
from app.modules.catalog.schemas import ExtraPayload, ListingAuthoringRequest
from app.modules.exchange_rates.service import convert, current_conversion_rates


_CURSOR_PATTERN = re.compile(r"[A-Za-z0-9_-]{1,512}\Z")
_MAX_LISTING_ID_LENGTH = 36


class InvalidCursorError(ValueError):
    """Raised when a listing cursor is malformed or unsafe to use."""


@dataclass(frozen=True)
class ListingCursor:
    created_at: datetime
    listing_id: str


def normalize_geo_key(value: str) -> str:
    return value.strip().casefold()


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def encode_cursor(created_at: datetime, listing_id: str) -> str:
    payload = {
        "created_at": _as_utc(created_at).isoformat(timespec="microseconds"),
        "listing_id": listing_id,
    }
    encoded = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return base64.urlsafe_b64encode(encoded).decode("ascii").rstrip("=")


def decode_cursor(value: str) -> ListingCursor:
    if _CURSOR_PATTERN.fullmatch(value) is None:
        raise InvalidCursorError
    try:
        padded = value + "=" * (-len(value) % 4)
        raw = base64.b64decode(padded, altchars=b"-_", validate=True)
        payload = json.loads(raw.decode("utf-8"))
        if not isinstance(payload, dict) or set(payload) != {"created_at", "listing_id"}:
            raise InvalidCursorError
        raw_timestamp = payload["created_at"]
        listing_id = payload["listing_id"]
        if (
            not isinstance(raw_timestamp, str)
            or len(raw_timestamp) > 64
            or not isinstance(listing_id, str)
            or not 1 <= len(listing_id) <= _MAX_LISTING_ID_LENGTH
        ):
            raise InvalidCursorError
        created_at = datetime.fromisoformat(raw_timestamp)
        if created_at.tzinfo is None:
            raise InvalidCursorError
        return ListingCursor(created_at=_as_utc(created_at), listing_id=listing_id)
    except InvalidCursorError:
        raise
    except (ValueError, UnicodeDecodeError, binascii.Error):
        raise InvalidCursorError from None


def search_public_listings(
    session: Session,
    *,
    city: str | None,
    zone: str | None,
    operation: str | None,
    min_base_price: Decimal | None,
    max_base_price: Decimal | None,
    min_rooms: int | None,
    min_bathrooms: int | None,
    limit: int,
    cursor_value: str | None,
) -> tuple[list[Listing], bool]:
    query = session.query(Listing).filter(
        Listing.approval_status == "approved",
        Listing.is_published.is_(True),
    )
    if city is not None:
        query = query.filter(Listing.city_key == normalize_geo_key(city))
    if zone is not None:
        query = query.filter(Listing.zone_key == normalize_geo_key(zone))
    if operation is not None:
        query = query.filter(Listing.operation == operation)
    if min_base_price is not None:
        query = query.filter(Listing.base_price >= min_base_price)
    if max_base_price is not None:
        query = query.filter(Listing.base_price <= max_base_price)
    if min_rooms is not None:
        query = query.filter(Listing.bedrooms >= min_rooms)
    if min_bathrooms is not None:
        query = query.filter(Listing.bathrooms >= min_bathrooms)
    if cursor_value is not None:
        cursor = decode_cursor(cursor_value)
        query = query.filter(
            or_(
                Listing.created_at < cursor.created_at,
                and_(Listing.created_at == cursor.created_at, Listing.id < cursor.listing_id),
            )
        )

    rows = query.order_by(Listing.created_at.desc(), Listing.id.desc()).limit(limit + 1).all()
    has_more = len(rows) > limit
    return rows[:limit], has_more


def get_public_listing(session: Session, listing_id: str) -> Listing | None:
    return (
        session.query(Listing)
        .filter(
            Listing.id == listing_id,
            Listing.approval_status == "approved",
            Listing.is_published.is_(True),
        )
        .one_or_none()
    )


def configure_listing_deposit(
    session: Session,
    *,
    agency_id: str,
    listing_id: str,
    deposit_amount: Decimal,
) -> Listing | None:
    listing = (
        session.query(Listing)
        .filter(Listing.id == listing_id, Listing.agency_id == agency_id)
        .with_for_update()
        .one_or_none()
    )
    if listing is None:
        return None

    listing.deposit_amount = deposit_amount
    session.flush()
    session.refresh(listing, attribute_names=["deposit_amount", "offer_version"])
    return listing


def _extra_values(payload: ExtraPayload) -> dict[str, object]:
    return {
        "name": payload.name,
        "price": payload.price,
        "category": payload.category,
        "room": payload.room,
        "width_cm": payload.width_cm,
        "height_cm": payload.height_cm,
        "depth_cm": payload.depth_cm,
        "origin": payload.origin,
        "visual_reference": payload.visual_reference,
        "quantity": payload.quantity,
    }


def _apply_extras_diff(
    session: Session,
    *,
    listing_id: str,
    payloads: list[ExtraPayload],
) -> None:
    """Diff the payload against stored extras by stable ID.

    Payload rows carrying a known `extra_id` update that row in place; rows
    without one are inserted with a fresh stable ID; stored extras missing from
    the payload are deleted. Rows whose values are identical are left untouched
    so the offer-version triggers do not fire for a semantically equal set.
    """
    existing: dict[str, ListingExtra] = {
        extra.id: extra
        for extra in session.query(ListingExtra)
        .filter(ListingExtra.listing_id == listing_id)
        .all()
    }
    referenced = [payload.extra_id for payload in payloads if payload.extra_id is not None]
    if len(referenced) != len(set(referenced)):
        raise InvalidExtraReferenceError
    for extra_id in referenced:
        if extra_id not in existing:
            raise InvalidExtraReferenceError

    removed_ids = existing.keys() - set(referenced)
    if removed_ids:
        session.query(ListingExtra).filter(
            ListingExtra.listing_id == listing_id,
            ListingExtra.id.in_(removed_ids),
        ).delete(synchronize_session=False)

    for payload in payloads:
        if payload.extra_id is None:
            session.add(ListingExtra(listing_id=listing_id, **_extra_values(payload)))
            continue
        extra = existing[payload.extra_id]
        values = _extra_values(payload)
        if any(getattr(extra, field) != value for field, value in values.items()):
            for field, value in values.items():
                setattr(extra, field, value)

    # Flush so the offer-version triggers run before the caller refreshes the
    # listing; sessions may be built with autoflush disabled.
    session.flush()


def create_staff_listing(
    session: Session,
    *,
    agency_id: str,
    content: ListingAuthoringRequest,
    actor_id: str,
    actor_role: str,
    now: datetime,
) -> Listing:
    listing = Listing(
        agency_id=agency_id,
        approval_status="draft",
        is_published=False,
        operation=content.operation,
        base_price=content.base_price,
        currency=content.currency,
        deposit_amount=None,
        offer_version=1,
        city=content.city,
        city_key=normalize_geo_key(content.city),
        zone=content.zone,
        zone_key=normalize_geo_key(content.zone),
        bedrooms=content.bedrooms,
        bathrooms=content.bathrooms,
        description=content.description,
        exact_address=content.exact_address,
    )
    session.add(listing)
    session.flush()
    if content.extras:
        session.add_all(
            ListingExtra(listing_id=listing.id, **_extra_values(payload))
            for payload in content.extras
        )
        session.flush()
        session.refresh(listing)
    session.add(
        ListingTransition(
            agency_id=agency_id,
            listing_id=listing.id,
            action="create",
            from_status=None,
            from_published=None,
            to_status="draft",
            to_published=False,
            actor_id=actor_id,
            actor_role=actor_role,
            created_at=now,
        )
    )
    session.flush()
    return listing


def edit_staff_listing(
    session: Session,
    *,
    agency_id: str,
    listing_id: str,
    content: ListingAuthoringRequest,
    actor_id: str,
    actor_role: str,
    now: datetime,
) -> Listing | None:
    listing = (
        session.query(Listing)
        .filter(Listing.id == listing_id, Listing.agency_id == agency_id)
        .with_for_update()
        .one_or_none()
    )
    if listing is None:
        return None

    from_status, from_published = listing.approval_status, listing.is_published
    session.execute(
        update(Listing)
        .where(Listing.id == listing_id, Listing.agency_id == agency_id)
        .values(
            operation=content.operation,
            base_price=content.base_price,
            currency=content.currency,
            city=content.city,
            city_key=normalize_geo_key(content.city),
            zone=content.zone,
            zone_key=normalize_geo_key(content.zone),
            bedrooms=content.bedrooms,
            bathrooms=content.bathrooms,
            description=content.description,
            exact_address=content.exact_address,
            approval_status="draft",
            is_published=False,
        )
        .execution_options(synchronize_session=False)
    )
    session.flush()
    session.refresh(listing)
    if content.extras is not None:
        _apply_extras_diff(session, listing_id=listing_id, payloads=content.extras)
        session.refresh(listing)
    session.add(
        ListingTransition(
            agency_id=agency_id,
            listing_id=listing.id,
            action="edit",
            from_status=from_status,
            from_published=from_published,
            to_status="draft",
            to_published=False,
            actor_id=actor_id,
            actor_role=actor_role,
            created_at=now,
        )
    )
    session.flush()
    return listing


_TRANSITION_STATES = {
    "submit": (("draft", False), ("pending", False)),
    "approve": (("pending", False), ("approved", False)),
    "reject": (("pending", False), ("rejected", False)),
    "publish": (("approved", False), ("approved", True)),
    "unpublish": (("approved", True), ("approved", False)),
}


def transition_staff_listing(
    session: Session,
    *,
    agency_id: str,
    listing_id: str,
    action: str,
    observation: str | None,
    actor_id: str,
    actor_role: str,
    now: datetime,
) -> Listing | None:
    listing = (
        session.query(Listing)
        .filter(Listing.id == listing_id, Listing.agency_id == agency_id)
        .with_for_update()
        .one_or_none()
    )
    if listing is None:
        return None

    expected, target = _TRANSITION_STATES[action]
    from_status, from_published = listing.approval_status, listing.is_published
    if (from_status, from_published) != expected:
        raise InvalidListingTransitionError
    listing.approval_status, listing.is_published = target
    session.flush()
    session.add(
        ListingTransition(
            agency_id=agency_id,
            listing_id=listing_id,
            action=action,
            from_status=from_status,
            from_published=from_published,
            to_status=target[0],
            to_published=target[1],
            observation=observation,
            actor_id=actor_id,
            actor_role=actor_role,
            created_at=now,
        )
    )
    session.flush()
    return listing


def get_staff_listing(
    session: Session, *, agency_id: str, listing_id: str
) -> Listing | None:
    return (
        session.query(Listing)
        .filter(Listing.id == listing_id, Listing.agency_id == agency_id)
        .one_or_none()
    )


def list_staff_listings(
    session: Session,
    *,
    agency_id: str,
    approval_status: str | None,
    is_published: bool | None,
    limit: int,
    offset: int,
) -> tuple[list[Listing], int]:
    """Return one page of an agency's listings, newest first, and the filtered total."""
    query = session.query(Listing).filter(Listing.agency_id == agency_id)
    if approval_status is not None:
        query = query.filter(Listing.approval_status == approval_status)
    if is_published is not None:
        query = query.filter(Listing.is_published == is_published)
    total = query.count()
    listings = (
        query.order_by(Listing.created_at.desc(), Listing.id.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return listings, total


def list_listing_transitions(session: Session, listing_id: str) -> list[ListingTransition]:
    return (
        session.query(ListingTransition)
        .filter(ListingTransition.listing_id == listing_id)
        .order_by(ListingTransition.created_at.asc(), ListingTransition.id.asc())
        .all()
    )


def list_listing_extras(session: Session, listing_id: str) -> list[ListingExtra]:
    return (
        session.query(ListingExtra)
        .filter(ListingExtra.listing_id == listing_id)
        .order_by(ListingExtra.id.asc())
        .all()
    )


def _quote_money(amount: Decimal) -> Decimal:
    return amount.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _begin_sqlite_immediate(session: Session) -> None:
    """Acquire SQLite's write reservation before reading or writing quote state."""
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


def create_quote_snapshot(
    session: Session,
    *,
    listing_id: str,
    expected_offer_version: int,
    selected_extra_ids: list[str],
    clock: Callable[[], datetime],
    target_currency: SupportedCurrency | None = None,
) -> QuoteSnapshot:
    """Calculate and persist a new quote from the current public offer."""
    if session.get_bind().dialect.name == "sqlite":
        _begin_sqlite_immediate(session)
    query = session.query(Listing).filter(
        Listing.id == listing_id,
        Listing.approval_status == "approved",
        Listing.is_published.is_(True),
    )
    if session.get_bind().dialect.name == "postgresql":
        query = query.with_for_update()
    listing = query.one_or_none()
    if listing is None:
        raise QuoteNotFoundError
    if listing.offer_version != expected_offer_version:
        raise QuoteOfferVersionMismatchError
    if len(set(selected_extra_ids)) != len(selected_extra_ids):
        raise InvalidQuoteExtrasError

    sorted_extra_ids = sorted(selected_extra_ids)
    extras: list[ListingExtra] = []
    if sorted_extra_ids:
        extras = (
            session.query(ListingExtra)
            .filter(
                ListingExtra.listing_id == listing.id,
                ListingExtra.id.in_(sorted_extra_ids),
            )
            .order_by(ListingExtra.id.asc())
            .all()
        )
        if len(extras) != len(sorted_extra_ids):
            raise InvalidQuoteExtrasError

    period = "one_time" if listing.operation == "sale" else "monthly"
    lines: list[dict[str, str | None]] = [
        {
            "kind": "base",
            "extra_id": None,
            "amount": format(_quote_money(listing.base_price), ".2f"),
            "currency": listing.currency,
            "charge_period": period,
        }
    ]
    lines.extend(
        {
            "kind": "extra",
            "extra_id": extra.id,
            "amount": format(_quote_money(extra.price * extra.quantity), ".2f"),
            "currency": listing.currency,
            "charge_period": period,
        }
        for extra in extras
    )
    total = _quote_money(
        listing.base_price
        + sum(
            (extra.price * extra.quantity for extra in extras),
            start=Decimal("0.00"),
        )
    )
    one_time_total = total if listing.operation == "sale" else Decimal("0.00")
    monthly_total = total if listing.operation == "rent" else Decimal("0.00")

    display_currency: str | None = None
    display_one_time_total: Decimal | None = None
    display_monthly_total: Decimal | None = None
    base_units_per_usd: Decimal | None = None
    display_units_per_usd: Decimal | None = None
    if target_currency is not None and target_currency != listing.currency:
        rates = current_conversion_rates(session=session)
        display_one_time_total = convert(
            one_time_total, listing.currency, target_currency, rates=rates
        )
        display_monthly_total = convert(
            monthly_total, listing.currency, target_currency, rates=rates
        )
        base_units_per_usd = (
            Decimal("1.00000000")
            if listing.currency == "USD"
            else rates[listing.currency]
        )
        display_units_per_usd = (
            Decimal("1.00000000")
            if target_currency == "USD"
            else rates[target_currency]
        )
        assert base_units_per_usd is not None
        assert display_units_per_usd is not None
        display_currency = target_currency

    created_at = _as_utc(clock())
    quote = QuoteSnapshot(
        listing_id=listing.id,
        offer_version=listing.offer_version,
        operation=listing.operation,
        currency=listing.currency,
        lines=lines,
        one_time_total=one_time_total,
        monthly_total=monthly_total,
        display_currency=display_currency,
        display_one_time_total=display_one_time_total,
        display_monthly_total=display_monthly_total,
        base_units_per_usd=base_units_per_usd,
        display_units_per_usd=display_units_per_usd,
        created_at=created_at,
        expires_at=created_at + timedelta(minutes=15),
    )
    session.add(quote)
    session.flush()
    return quote


def _quote_client_key(client_ip: str, hmac_secret: str) -> str:
    message = b"roomforge.quote.rate-limit.v1\0" + client_ip.encode("utf-8")
    return hmac.new(hmac_secret.encode("utf-8"), message, hashlib.sha256).hexdigest()


def consume_quote_rate_limit(
    session: Session,
    *,
    client_ip: str,
    now: datetime,
    hmac_secret: str,
) -> int | None:
    """Persist an allowed attempt or return the integer Retry-After for a denied one."""
    dialect_name = session.get_bind().dialect.name
    client_key = _quote_client_key(client_ip, hmac_secret)
    lock_id = int.from_bytes(bytes.fromhex(client_key[:16]), byteorder="big", signed=True)
    if dialect_name == "postgresql":
        session.execute(text("SELECT pg_advisory_xact_lock(:lock_id)"), {"lock_id": lock_id})
    elif dialect_name == "sqlite":
        _begin_sqlite_immediate(session)
    else:
        raise UnsupportedRateLimitDialectError

    current_time = _as_utc(now)
    cutoff = current_time - timedelta(seconds=60)
    session.execute(
        delete(QuoteRateLimitEvent).where(QuoteRateLimitEvent.occurred_at <= cutoff)
    )
    recent_events = (
        session.query(QuoteRateLimitEvent)
        .filter(
            QuoteRateLimitEvent.client_key == client_key,
            QuoteRateLimitEvent.occurred_at > cutoff,
            QuoteRateLimitEvent.occurred_at <= current_time,
        )
        .order_by(QuoteRateLimitEvent.occurred_at.asc(), QuoteRateLimitEvent.id.asc())
        .all()
    )
    if len(recent_events) >= 10:
        oldest_event = _as_utc(recent_events[0].occurred_at)
        seconds_until_available = (oldest_event + timedelta(seconds=60) - current_time).total_seconds()
        return max(1, math.ceil(seconds_until_available))

    session.add(QuoteRateLimitEvent(client_key=client_key, occurred_at=current_time))
    session.flush()
    return None


def validate_quote_for_use(session: Session, quote_id: str, *, now: datetime) -> QuoteSnapshot:
    """Validate persisted quote TTL and its current catalog offer version for CC-05 use."""
    quote = session.get(QuoteSnapshot, quote_id)
    if quote is None:
        raise QuoteNotFoundError
    if _as_utc(now) >= _as_utc(quote.expires_at):
        raise QuoteExpiredError
    listing = session.get(Listing, quote.listing_id)
    if listing is None or listing.offer_version != quote.offer_version:
        raise QuoteOfferVersionMismatchError
    return quote
