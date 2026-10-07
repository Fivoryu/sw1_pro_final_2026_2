"""Listing photos (F04.2): upload requests, confirmation, listing and removal.

Uploads go straight to object storage through a signed link. A photo only
counts once the API confirms it: it reads the object back, checks it is a real
image of the declared type and rewrites it without metadata (EXIF, including
GPS), so a published photo cannot reveal the private address.
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from enum import Enum
from uuid import uuid4

from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy.orm import Session

from app.modules.catalog.models import (
    LISTING_PHOTO_MAX_BYTES,
    LISTING_PHOTO_MAX_COUNT,
    Listing,
    ListingPhoto,
    ListingTransition,
)
from app.modules.catalog.photo_storage import PhotoStorage, PhotoTooLargeError

UPLOAD_WINDOW = timedelta(minutes=15)
DOWNLOAD_LINK_SECONDS = 600
MAX_PHOTO_PIXELS = 40_000_000

_PIL_FORMATS = {"image/jpeg": "JPEG", "image/png": "PNG", "image/webp": "WEBP"}


class PhotoLimitReachedError(Exception):
    """The listing already holds the maximum number of photos."""


class PhotoUploadExpiredError(Exception):
    """The upload window of a pending photo is over."""


class PhotoNotUploadedError(Exception):
    """The storage has no object for a pending photo yet."""


class InvalidPhotoError(Exception):
    """The uploaded bytes are not a valid photo of the declared type."""


class ConfirmOutcome(Enum):
    CONFIRMED = "confirmed"
    DISCARDED = "discarded"


@dataclass(frozen=True)
class UploadGrant:
    photo: ListingPhoto
    upload_url: str
    expires_at: datetime


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def photo_key(agency_id: str, listing_id: str, photo_id: str) -> str:
    return f"agencies/{agency_id}/listings/{listing_id}/photos/{photo_id}"


def lock_staff_listing(session: Session, *, agency_id: str, listing_id: str) -> Listing | None:
    return (
        session.query(Listing)
        .filter(Listing.id == listing_id, Listing.agency_id == agency_id)
        .with_for_update()
        .one_or_none()
    )


def _find_photo(session: Session, listing: Listing, photo_id: str) -> ListingPhoto | None:
    return (
        session.query(ListingPhoto)
        .filter(
            ListingPhoto.id == photo_id,
            ListingPhoto.listing_id == listing.id,
            ListingPhoto.agency_id == listing.agency_id,
        )
        .with_for_update()
        .one_or_none()
    )


def confirmed_photos(session: Session, listing_id: str) -> list[ListingPhoto]:
    return (
        session.query(ListingPhoto)
        .filter(ListingPhoto.listing_id == listing_id, ListingPhoto.status == "confirmed")
        .order_by(ListingPhoto.created_at.asc(), ListingPhoto.id.asc())
        .all()
    )


def count_confirmed_photos(session: Session, listing_id: str) -> int:
    return (
        session.query(ListingPhoto)
        .filter(ListingPhoto.listing_id == listing_id, ListingPhoto.status == "confirmed")
        .count()
    )


def request_photo_upload(
    session: Session,
    storage: PhotoStorage,
    *,
    listing: Listing,
    content_type: str,
    size_bytes: int,
    now: datetime,
) -> UploadGrant:
    """Reserve a pending photo and sign its upload link."""
    photos = (
        session.query(ListingPhoto).filter(ListingPhoto.listing_id == listing.id).all()
    )
    live = 0
    for photo in photos:
        if photo.status == "pending" and _as_utc(photo.expires_at) <= now:
            storage.delete(photo.object_key)
            session.delete(photo)
        else:
            live += 1
    if live >= LISTING_PHOTO_MAX_COUNT:
        raise PhotoLimitReachedError

    photo_id = str(uuid4())
    expires_at = now + UPLOAD_WINDOW
    photo = ListingPhoto(
        id=photo_id,
        agency_id=listing.agency_id,
        listing_id=listing.id,
        object_key=photo_key(listing.agency_id, listing.id, photo_id),
        status="pending",
        content_type=content_type,
        size_bytes=size_bytes,
        created_at=now,
        expires_at=expires_at,
        confirmed_at=None,
    )
    session.add(photo)
    session.flush()
    upload_url = storage.presign_upload(
        photo.object_key,
        content_type=content_type,
        expires_in=int(UPLOAD_WINDOW.total_seconds()),
    )
    return UploadGrant(photo=photo, upload_url=upload_url, expires_at=expires_at)


def clean_photo(data: bytes, content_type: str) -> bytes:
    """Return the photo re-encoded without metadata, or raise InvalidPhotoError."""
    expected = _PIL_FORMATS[content_type]
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.format != expected:
                raise InvalidPhotoError
            if image.width * image.height > MAX_PHOTO_PIXELS:
                raise InvalidPhotoError
            image.load()
            icc_profile = image.info.get("icc_profile")
            oriented = ImageOps.exif_transpose(image)
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise InvalidPhotoError from None

    # Drop every metadata block the encoders could carry over (EXIF, XMP, comments).
    oriented.info = {}
    options: dict[str, object] = {}
    if icc_profile:
        options["icc_profile"] = icc_profile
    if expected == "JPEG":
        if oriented.mode not in ("RGB", "L", "CMYK"):
            oriented = oriented.convert("RGB")
        options["quality"] = 90
    elif expected == "WEBP":
        if oriented.mode not in ("RGB", "RGBA"):
            oriented = oriented.convert("RGBA" if "A" in oriented.getbands() else "RGB")
        options["quality"] = 90

    output = io.BytesIO()
    oriented.save(output, format=expected, **options)
    cleaned = output.getvalue()
    if len(cleaned) > LISTING_PHOTO_MAX_BYTES:
        raise InvalidPhotoError
    return cleaned


def _reopen_listing(
    session: Session, listing: Listing, *, actor_id: str, actor_role: str, now: datetime
) -> None:
    """A photo change is a content edit: the listing goes back to draft for review."""
    from_status, from_published = listing.approval_status, listing.is_published
    listing.approval_status, listing.is_published = "draft", False
    session.flush()
    session.add(
        ListingTransition(
            agency_id=listing.agency_id,
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


def confirm_photo(
    session: Session,
    storage: PhotoStorage,
    *,
    listing: Listing,
    photo_id: str,
    actor_id: str,
    actor_role: str,
    now: datetime,
) -> tuple[ConfirmOutcome, ListingPhoto] | None:
    """Validate and clean an uploaded photo; None when the photo does not exist."""
    photo = _find_photo(session, listing, photo_id)
    if photo is None:
        return None
    if photo.status == "confirmed":
        return ConfirmOutcome.CONFIRMED, photo
    if _as_utc(photo.expires_at) <= now:
        raise PhotoUploadExpiredError

    try:
        data = storage.read(photo.object_key, max_bytes=LISTING_PHOTO_MAX_BYTES)
        if data is None:
            raise PhotoNotUploadedError
        cleaned = clean_photo(data, photo.content_type)
    except (PhotoTooLargeError, InvalidPhotoError):
        storage.delete(photo.object_key)
        session.delete(photo)
        session.flush()
        return ConfirmOutcome.DISCARDED, photo

    storage.write(photo.object_key, cleaned, content_type=photo.content_type)
    photo.status = "confirmed"
    photo.size_bytes = len(cleaned)
    photo.confirmed_at = now
    session.flush()
    _reopen_listing(session, listing, actor_id=actor_id, actor_role=actor_role, now=now)
    return ConfirmOutcome.CONFIRMED, photo


def delete_photo(
    session: Session,
    storage: PhotoStorage,
    *,
    listing: Listing,
    photo_id: str,
    actor_id: str,
    actor_role: str,
    now: datetime,
) -> bool:
    """Remove a photo and its object; False when the photo does not exist."""
    photo = _find_photo(session, listing, photo_id)
    if photo is None:
        return False
    was_confirmed = photo.status == "confirmed"
    storage.delete(photo.object_key)
    session.delete(photo)
    session.flush()
    if was_confirmed:
        _reopen_listing(session, listing, actor_id=actor_id, actor_role=actor_role, now=now)
    return True
