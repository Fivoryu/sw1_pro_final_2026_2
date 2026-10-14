"""Listing photos (F04.2): upload requests, confirmation, listing and removal.

Uploads go straight to a temporary object-storage key through a signed link. A
photo only counts once the API validates it, preserves its exact bytes under a
separate private key, and writes a sanitized public derivative without EXIF.
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from enum import Enum
from uuid import uuid4

from PIL import Image, ImageOps, UnidentifiedImageError
from pillow_heif import register_heif_opener
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

register_heif_opener()

_PIL_FORMATS = {
    "image/jpeg": "JPEG",
    "image/png": "PNG",
    "image/webp": "WEBP",
    "image/heic": "HEIF",
    "image/heif": "HEIF",
}
_HEIF_CONTENT_TYPES = frozenset({"image/heic", "image/heif"})


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


def photo_upload_key(agency_id: str, listing_id: str, photo_id: str) -> str:
    return f"{photo_key(agency_id, listing_id, photo_id)}/upload"


def photo_public_key(agency_id: str, listing_id: str, photo_id: str) -> str:
    return f"{photo_key(agency_id, listing_id, photo_id)}/public"


def photo_original_key(agency_id: str, listing_id: str, photo_id: str) -> str:
    return f"{photo_key(agency_id, listing_id, photo_id)}/original"


def _pending_object_keys(photo: ListingPhoto) -> tuple[str, ...]:
    upload_key = photo.upload_object_key or photo.object_key
    public_key = (
        photo.object_key
        if photo.upload_object_key is not None
        else photo_public_key(photo.agency_id, photo.listing_id, photo.id)
    )
    original_key = photo.original_object_key or photo_original_key(
        photo.agency_id, photo.listing_id, photo.id
    )
    return tuple(dict.fromkeys((upload_key, public_key, original_key)))


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


def cleanup_expired_photo_uploads(
    session: Session,
    storage: PhotoStorage,
    *,
    now: datetime,
    listing_id: str | None = None,
    batch_size: int | None = None,
    skip_locked: bool = False,
) -> int:
    """Delete expired pending assets and confirmed photos' staging copies only."""
    expires_at = _as_utc(now)
    pending = session.query(ListingPhoto).filter(
        ListingPhoto.status == "pending",
        ListingPhoto.expires_at <= expires_at,
    )
    confirmed_staging = session.query(ListingPhoto).filter(
        ListingPhoto.status == "confirmed",
        ListingPhoto.upload_object_key.isnot(None),
        ListingPhoto.expires_at <= expires_at,
    )
    cleaned = 0
    for status, query in (("pending", pending), ("confirmed", confirmed_staging)):
        if listing_id is not None:
            query = query.filter(ListingPhoto.listing_id == listing_id)
        query = query.order_by(ListingPhoto.expires_at, ListingPhoto.id).with_for_update(
            skip_locked=skip_locked
        )
        if batch_size is not None:
            query = query.limit(batch_size)
        for photo in query.all():
            if status == "pending":
                for key in _pending_object_keys(photo):
                    storage.delete(key)
                session.delete(photo)
            else:
                upload_key = photo.upload_object_key
                if upload_key is None:
                    continue
                storage.delete(upload_key)
                photo.upload_object_key = None
            cleaned += 1
    if cleaned:
        session.flush()
    return cleaned


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
    cleanup_expired_photo_uploads(
        session,
        storage,
        now=now,
        listing_id=listing.id,
    )
    live = session.query(ListingPhoto).filter(ListingPhoto.listing_id == listing.id).count()
    if live >= LISTING_PHOTO_MAX_COUNT:
        raise PhotoLimitReachedError

    photo_id = str(uuid4())
    expires_at = now + UPLOAD_WINDOW
    upload_key = photo_upload_key(listing.agency_id, listing.id, photo_id)
    photo = ListingPhoto(
        id=photo_id,
        agency_id=listing.agency_id,
        listing_id=listing.id,
        object_key=photo_public_key(listing.agency_id, listing.id, photo_id),
        upload_object_key=upload_key,
        original_object_key=None,
        public_content_type=None,
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
        upload_key,
        content_type=content_type,
        expires_in=int(UPLOAD_WINDOW.total_seconds()),
    )
    return UploadGrant(photo=photo, upload_url=upload_url, expires_at=expires_at)


def clean_photo(data: bytes, content_type: str) -> tuple[bytes, str]:
    """Return sanitized derivative bytes and MIME type, or raise InvalidPhotoError."""
    expected = _PIL_FORMATS[content_type]
    try:
        with Image.open(io.BytesIO(data)) as image:
            accepted_formats = {expected, "HEIC"} if expected == "HEIF" else {expected}
            if image.format not in accepted_formats:
                raise InvalidPhotoError
            if image.width * image.height > MAX_PHOTO_PIXELS:
                raise InvalidPhotoError
            image.load()
            icc_profile = image.info.get("icc_profile")
            oriented = ImageOps.exif_transpose(image)
    except (UnidentifiedImageError, OSError, ValueError, EOFError, Image.DecompressionBombError):
        raise InvalidPhotoError from None

    # HEIC/HEIF inputs are decoded but published as JPEG for viewer compatibility.
    output_format = "JPEG" if content_type in _HEIF_CONTENT_TYPES else expected
    output_content_type = "image/jpeg" if output_format == "JPEG" else content_type
    # Drop every metadata block the encoders could carry over (EXIF, XMP, comments).
    oriented.info = {}
    options: dict[str, object] = {}
    if icc_profile:
        options["icc_profile"] = icc_profile
    if output_format == "JPEG":
        if oriented.mode not in ("RGB", "L", "CMYK"):
            oriented = oriented.convert("RGB")
        options["quality"] = 90
    elif output_format == "WEBP":
        if oriented.mode not in ("RGB", "RGBA"):
            oriented = oriented.convert("RGBA" if "A" in oriented.getbands() else "RGB")
        options["quality"] = 90

    output = io.BytesIO()
    oriented.save(output, format=output_format, **options)
    cleaned = output.getvalue()
    if len(cleaned) > LISTING_PHOTO_MAX_BYTES:
        raise InvalidPhotoError
    return cleaned, output_content_type


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
    """Validate, preserve, and publish an upload; None when it does not exist."""
    photo = _find_photo(session, listing, photo_id)
    if photo is None:
        return None
    if photo.status == "confirmed":
        return ConfirmOutcome.CONFIRMED, photo
    if _as_utc(photo.expires_at) <= now:
        raise PhotoUploadExpiredError

    upload_key = photo.upload_object_key or photo.object_key
    legacy_pending = photo.upload_object_key is None
    public_key = (
        photo_public_key(photo.agency_id, photo.listing_id, photo.id)
        if legacy_pending
        else photo.object_key
    )
    original_key = photo.original_object_key or photo_original_key(
        photo.agency_id, photo.listing_id, photo.id
    )

    try:
        # A previously written original may survive a failed DB commit. Reuse it
        # rather than ever replacing immutable source bytes on a retry.
        data = storage.read(original_key, max_bytes=LISTING_PHOTO_MAX_BYTES)
        original_exists = data is not None
        if data is None:
            data = storage.read(upload_key, max_bytes=LISTING_PHOTO_MAX_BYTES)
            if data is None:
                raise PhotoNotUploadedError
        cleaned, public_content_type = clean_photo(data, photo.content_type)
        if not original_exists:
            storage.write(original_key, data, content_type=photo.content_type)
        storage.write(public_key, cleaned, content_type=public_content_type)
    except (PhotoTooLargeError, InvalidPhotoError):
        for key in _pending_object_keys(photo):
            storage.delete(key)
        session.delete(photo)
        session.flush()
        return ConfirmOutcome.DISCARDED, photo

    photo.object_key = public_key
    photo.upload_object_key = upload_key
    photo.original_object_key = original_key
    photo.public_content_type = public_content_type
    # Keep the staging key until its signed PUT expires; a later sweep removes
    # only that temporary object and leaves the confirmed original/derivative.
    photo.status = "confirmed"
    photo.size_bytes = len(data)
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
