"""Staff routes for listing photos (F04.2)."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy.orm import Session, sessionmaker

from app.modules.catalog.models import ListingPhoto
from app.modules.catalog.photo_storage import PhotoStorage, PhotoStorageUnavailableError
from app.modules.catalog.photos import (
    DOWNLOAD_LINK_SECONDS,
    ConfirmOutcome,
    PhotoLimitReachedError,
    PhotoNotUploadedError,
    PhotoUploadExpiredError,
    confirm_photo,
    confirmed_photos,
    delete_photo,
    lock_staff_listing,
    request_photo_upload,
)
from app.modules.catalog.router import _require_listing_editor  # pyright: ignore[reportPrivateUsage]
from app.modules.catalog.schemas import (
    ListingPhotoContentType,
    ListingPhotoList,
    ListingPhotoResponse,
    ListingPhotoUploadRequest,
    ListingPhotoUploadResponse,
)
from app.modules.identity.session import ActiveStaff, get_active_staff

router = APIRouter(
    prefix="/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/photos",
    tags=["listing-photos"],
)

_LISTING_NOT_FOUND = "Listing not found"
_PHOTO_NOT_FOUND = "Photo not found"


def _storage(request: Request) -> PhotoStorage:
    storage: PhotoStorage | None = request.app.state.photo_storage
    if storage is None:
        raise HTTPException(status_code=503, detail="Photo storage is not configured")
    return storage


def _session_factory(request: Request) -> sessionmaker[Session]:
    return request.app.state.session_factory


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def photo_response(storage: PhotoStorage, photo: ListingPhoto) -> ListingPhotoResponse:
    content_type: ListingPhotoContentType = photo.content_type  # type: ignore[assignment]
    return ListingPhotoResponse(
        photo_id=photo.id,
        content_type=content_type,
        size_bytes=photo.size_bytes,
        url=storage.presign_download(photo.object_key, expires_in=DOWNLOAD_LINK_SECONDS),
        created_at=_as_utc(photo.created_at),
    )


@router.post("", status_code=201, response_model=ListingPhotoUploadResponse)
def request_listing_photo_upload(
    agency_id: str,
    listing_id: str,
    body: ListingPhotoUploadRequest,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingPhotoUploadResponse:
    _require_listing_editor(staff, agency_id)
    storage = _storage(request)
    try:
        with _session_factory(request).begin() as session:
            listing = lock_staff_listing(session, agency_id=agency_id, listing_id=listing_id)
            if listing is None:
                raise HTTPException(status_code=404, detail=_LISTING_NOT_FOUND)
            grant = request_photo_upload(
                session,
                storage,
                listing=listing,
                content_type=body.content_type,
                size_bytes=body.size_bytes,
                now=request.app.state.clock(),
            )
            return ListingPhotoUploadResponse(
                photo_id=grant.photo.id,
                upload_url=grant.upload_url,
                upload_method="PUT",
                upload_headers={"Content-Type": body.content_type},
                expires_at=grant.expires_at,
            )
    except PhotoLimitReachedError:
        raise HTTPException(status_code=409, detail="Listing photo limit reached") from None
    except PhotoStorageUnavailableError:
        raise HTTPException(status_code=503, detail="Photo storage is unavailable") from None


@router.post("/{photo_id}/confirm", response_model=ListingPhotoResponse)
def confirm_listing_photo(
    agency_id: str,
    listing_id: str,
    photo_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingPhotoResponse:
    _require_listing_editor(staff, agency_id)
    storage = _storage(request)
    try:
        with _session_factory(request).begin() as session:
            listing = lock_staff_listing(session, agency_id=agency_id, listing_id=listing_id)
            if listing is None:
                raise HTTPException(status_code=404, detail=_LISTING_NOT_FOUND)
            result = confirm_photo(
                session,
                storage,
                listing=listing,
                photo_id=photo_id,
                actor_id=staff["id"],
                actor_role=staff["role"],
                now=request.app.state.clock(),
            )
            if result is None:
                raise HTTPException(status_code=404, detail=_PHOTO_NOT_FOUND)
            outcome, photo = result
            response = photo_response(storage, photo) if outcome is ConfirmOutcome.CONFIRMED else None
    except PhotoUploadExpiredError:
        raise HTTPException(status_code=409, detail="Photo upload window expired") from None
    except PhotoNotUploadedError:
        raise HTTPException(status_code=409, detail="Photo has not been uploaded") from None
    except PhotoStorageUnavailableError:
        raise HTTPException(status_code=503, detail="Photo storage is unavailable") from None
    if response is None:
        # The discarded upload is already removed; report it after that commit.
        raise HTTPException(status_code=422, detail="Upload is not a valid photo of its type")
    return response


@router.get("", response_model=ListingPhotoList)
def list_listing_photos(
    agency_id: str,
    listing_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingPhotoList:
    _require_listing_editor(staff, agency_id)
    storage = _storage(request)
    with _session_factory(request)() as session:
        listing = lock_staff_listing(session, agency_id=agency_id, listing_id=listing_id)
        if listing is None:
            raise HTTPException(status_code=404, detail=_LISTING_NOT_FOUND)
        photos = confirmed_photos(session, listing.id)
        return ListingPhotoList(photos=[photo_response(storage, photo) for photo in photos])


@router.delete("/{photo_id}", status_code=204, response_model=None)
def delete_listing_photo(
    agency_id: str,
    listing_id: str,
    photo_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> Response:
    _require_listing_editor(staff, agency_id)
    storage = _storage(request)
    try:
        with _session_factory(request).begin() as session:
            listing = lock_staff_listing(session, agency_id=agency_id, listing_id=listing_id)
            if listing is None:
                raise HTTPException(status_code=404, detail=_LISTING_NOT_FOUND)
            deleted = delete_photo(
                session,
                storage,
                listing=listing,
                photo_id=photo_id,
                actor_id=staff["id"],
                actor_role=staff["role"],
                now=request.app.state.clock(),
            )
            if not deleted:
                raise HTTPException(status_code=404, detail=_PHOTO_NOT_FOUND)
    except PhotoStorageUnavailableError:
        raise HTTPException(status_code=503, detail="Photo storage is unavailable") from None
    return Response(status_code=204)
