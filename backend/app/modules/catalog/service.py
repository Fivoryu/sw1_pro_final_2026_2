"""Read-only public listing queries and opaque cursor handling."""

from __future__ import annotations

import base64
import binascii
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from app.modules.catalog.models import Listing, ListingExtra


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


def list_listing_extras(session: Session, listing_id: str) -> list[ListingExtra]:
    return (
        session.query(ListingExtra)
        .filter(ListingExtra.listing_id == listing_id)
        .order_by(ListingExtra.id.asc())
        .all()
    )
