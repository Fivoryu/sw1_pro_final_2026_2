from __future__ import annotations

import base64
import importlib.util
import io
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlsplit

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.modules.catalog.models import Listing, ListingPhoto, ListingTransition
from app.modules.catalog.photo_storage import (
    InMemoryPhotoStorage,
    PhotoTooLargeError,
    S3PhotoStorage,
    create_photo_storage,
)
from app.modules.identity.models import Agency
from app.modules.identity.session import get_active_staff


def _settings(**changes: object) -> Settings:
    values: dict[str, object] = {
        "database_url": "sqlite+pysqlite:///:memory:",
        "jwt_secret": "photo-test-secret-that-is-at-least-thirty-two-bytes",
        "totp_encryption_key": base64.urlsafe_b64encode(b"0" * 32).decode(),
        "web_origin": "http://localhost",
    }
    values.update(changes)
    return Settings(**values)  # type: ignore[arg-type]


def _s3_storage() -> S3PhotoStorage:
    return S3PhotoStorage(
        bucket="photo-bucket",
        endpoint_url="http://floci:4566",
        public_endpoint_url="http://127.0.0.1:4566",
        region="us-east-1",
        access_key_id="local-test-key",
        secret_access_key="local-test-secret",
    )


def test_upload_link_is_signed_for_the_public_endpoint_and_content_type() -> None:
    url = _s3_storage().presign_upload(
        "agencies/a/listings/l/photos/p", content_type="image/jpeg", expires_in=300
    )

    parts = urlsplit(url)
    query = parse_qs(parts.query)
    assert f"{parts.scheme}://{parts.netloc}" == "http://127.0.0.1:4566"
    assert parts.path == "/photo-bucket/agencies/a/listings/l/photos/p"
    assert query["X-Amz-Algorithm"] == ["AWS4-HMAC-SHA256"]
    assert query["X-Amz-Expires"] == ["300"]
    assert "content-type" in query["X-Amz-SignedHeaders"][0].split(";")
    assert query["X-Amz-Signature"][0]


def test_download_link_is_signed_for_the_public_endpoint() -> None:
    url = _s3_storage().presign_download("agencies/a/listings/l/photos/p", expires_in=600)

    parts = urlsplit(url)
    query = parse_qs(parts.query)
    assert f"{parts.scheme}://{parts.netloc}" == "http://127.0.0.1:4566"
    assert parts.path == "/photo-bucket/agencies/a/listings/l/photos/p"
    assert query["X-Amz-Expires"] == ["600"]
    assert query["X-Amz-Signature"][0]


def test_storage_is_disabled_without_a_bucket() -> None:
    assert create_photo_storage(_settings(s3_endpoint_url="http://floci:4566")) is None


@pytest.fixture
def aws_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """The runtime reads credentials from the environment, as in the local stack."""
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "local-test-key")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "local-test-secret")


@pytest.mark.usefixtures("aws_env")
def test_storage_signs_with_the_internal_endpoint_when_no_public_one_is_set() -> None:
    storage = create_photo_storage(
        _settings(s3_bucket_name="photo-bucket", s3_endpoint_url="http://floci:4566")
    )

    assert isinstance(storage, S3PhotoStorage)
    url = storage.presign_download("key", expires_in=60)
    assert url.startswith("http://floci:4566/photo-bucket/key?")


@pytest.mark.usefixtures("aws_env")
def test_storage_uses_the_public_endpoint_for_links() -> None:
    storage = create_photo_storage(
        _settings(
            s3_bucket_name="photo-bucket",
            s3_endpoint_url="http://floci:4566",
            s3_public_endpoint_url="http://127.0.0.1:4566/",
        )
    )

    assert isinstance(storage, S3PhotoStorage)
    assert storage.presign_download("key", expires_in=60).startswith(
        "http://127.0.0.1:4566/photo-bucket/key?"
    )


def test_in_memory_storage_round_trip_and_size_cap() -> None:
    storage = InMemoryPhotoStorage()
    assert storage.read("missing", max_bytes=10) is None

    storage.objects["key"] = b"0123456789"
    assert storage.read("key", max_bytes=10) == b"0123456789"
    with pytest.raises(PhotoTooLargeError):
        storage.read("key", max_bytes=9)

    storage.write("key", b"clean", content_type="image/png")
    assert storage.objects["key"] == b"clean"
    assert storage.content_types["key"] == "image/png"
    storage.delete("key")
    storage.delete("key")
    assert "key" not in storage.objects

    upload = urlsplit(storage.presign_upload("a b", content_type="image/png", expires_in=60))
    download = urlsplit(storage.presign_download("a b", expires_in=60))
    assert upload.path.endswith("/a%20b") and download.path.endswith("/a%20b")


# --- Staff photo routes ------------------------------------------------------

_NOW = datetime(2026, 10, 4, 12, 0, tzinfo=timezone.utc)
_MAX_BYTES = 5 * 1024 * 1024


@dataclass
class PhotoContext:
    client: TestClient
    app: FastAPI
    session_factory: sessionmaker[Session]
    storage: InMemoryPhotoStorage
    clock: list[datetime]


def _install_offer_version_triggers(engine: Engine) -> None:
    path = Path(__file__).resolve().parents[1] / "alembic" / "versions" / "0007_catalog_offers.py"
    spec = importlib.util.spec_from_file_location("photo_test_catalog_offers", path)
    assert spec is not None and spec.loader is not None
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    from alembic.migration import MigrationContext
    from alembic.operations import Operations

    with engine.begin() as connection:
        with Operations.context(MigrationContext.configure(connection)):
            migration._install_sqlite_offer_version_triggers()


def _build_context(storage: InMemoryPhotoStorage | None) -> Iterator[PhotoContext]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    Base.metadata.create_all(engine)
    _install_offer_version_triggers(engine)
    clock = [_NOW]
    app = create_app(
        settings=_settings(),
        session_factory=factory,
        clock=lambda: clock[0],
        photo_storage=storage,
    )
    with TestClient(app) as client:
        yield PhotoContext(client, app, factory, storage or InMemoryPhotoStorage(), clock)
    engine.dispose()


@pytest.fixture
def photo_context() -> Iterator[PhotoContext]:
    yield from _build_context(InMemoryPhotoStorage())


@pytest.fixture
def storageless_context() -> Iterator[PhotoContext]:
    yield from _build_context(None)


def _staff(
    context: PhotoContext,
    *,
    role: str = "agent",
    tenant_id: str | None = "agency-one",
) -> None:
    context.app.dependency_overrides[get_active_staff] = lambda: {
        "id": "photo-actor",
        "email": "photo-actor@example.test",
        "role": role,
        "tenant_id": tenant_id,
    }


def _seed_listing(
    context: PhotoContext,
    listing_id: str = "listing-one",
    *,
    agency_id: str = "agency-one",
    approval_status: str = "draft",
    is_published: bool = False,
) -> None:
    with context.session_factory.begin() as session:
        if session.get(Agency, agency_id) is None:
            session.add(Agency(id=agency_id))
            session.flush()
        session.add(
            Listing(
                id=listing_id,
                agency_id=agency_id,
                approval_status=approval_status,
                is_published=is_published,
                operation="sale",
                base_price=Decimal("100000.00"),
                offer_version=1,
                city="Medellín",
                zone="Laureles",
                bedrooms=2,
                bathrooms=1,
            )
        )


def _seed_photo(
    context: PhotoContext,
    photo_id: str,
    *,
    listing_id: str = "listing-one",
    agency_id: str = "agency-one",
    status: str = "confirmed",
    created_at: datetime = _NOW,
    expires_at: datetime | None = None,
) -> str:
    key = f"agencies/{agency_id}/listings/{listing_id}/photos/{photo_id}"
    with context.session_factory.begin() as session:
        session.add(
            ListingPhoto(
                id=photo_id,
                agency_id=agency_id,
                listing_id=listing_id,
                object_key=key,
                status=status,
                content_type="image/png",
                size_bytes=10,
                created_at=created_at,
                expires_at=expires_at or created_at + timedelta(minutes=15),
                confirmed_at=created_at if status == "confirmed" else None,
            )
        )
    context.storage.objects[key] = _image_bytes("PNG")
    return key


def _image_bytes(
    image_format: str,
    size: tuple[int, int] = (4, 2),
    *,
    orientation: int | None = None,
    gps: bool = False,
    mode: str = "RGB",
) -> bytes:
    image = Image.new(mode, size, color=0 if mode == "1" else (200, 30, 30))
    exif = Image.Exif()
    if orientation is not None:
        exif[0x0112] = orientation
    if gps:
        gps_ifd = exif.get_ifd(0x8825)
        gps_ifd[1] = "N"
        gps_ifd[2] = (6.0, 15.0, 0.0)
        gps_ifd[3] = "W"
        gps_ifd[4] = (75.0, 34.0, 0.0)
    buffer = io.BytesIO()
    if len(exif):
        image.save(buffer, format=image_format, exif=exif)
    else:
        image.save(buffer, format=image_format)
    return buffer.getvalue()


def _photos_url(listing_id: str = "listing-one", agency_id: str = "agency-one") -> str:
    return f"/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/photos"


def _request_upload(
    context: PhotoContext, content_type: str = "image/jpeg", size_bytes: int = 2048
) -> Any:
    return context.client.post(
        _photos_url(), json={"content_type": content_type, "size_bytes": size_bytes}
    )


def _listing(context: PhotoContext, listing_id: str = "listing-one") -> Listing:
    with context.session_factory() as session:
        listing = session.get(Listing, listing_id)
        assert listing is not None
        return listing


def _photo(context: PhotoContext, photo_id: str) -> ListingPhoto | None:
    with context.session_factory() as session:
        return session.get(ListingPhoto, photo_id)


def _photo_key(context: PhotoContext, photo_id: str) -> str:
    photo = _photo(context, photo_id)
    assert photo is not None
    return photo.object_key


def _actions(context: PhotoContext, listing_id: str = "listing-one") -> list[str]:
    with context.session_factory() as session:
        rows = (
            session.query(ListingTransition)
            .filter(ListingTransition.listing_id == listing_id)
            .order_by(ListingTransition.created_at, ListingTransition.id)
            .all()
        )
        return [row.action for row in rows]


def test_upload_request_signs_a_server_chosen_key_and_keeps_the_photo_pending(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)

    response = _request_upload(context, "image/webp", 4096)

    assert response.status_code == 201, response.text
    body = response.json()
    assert set(body) == {"photo_id", "upload_url", "upload_method", "upload_headers", "expires_at"}
    photo = _photo(context, body["photo_id"])
    assert photo is not None
    expected_key = f"agencies/agency-one/listings/listing-one/photos/{body['photo_id']}"
    assert photo.object_key == expected_key
    assert (photo.status, photo.content_type, photo.size_bytes) == ("pending", "image/webp", 4096)
    assert body["upload_method"] == "PUT"
    assert body["upload_headers"] == {"Content-Type": "image/webp"}
    assert urlsplit(body["upload_url"]).path.endswith(expected_key)
    assert datetime.fromisoformat(body["expires_at"]) == _NOW + timedelta(minutes=15)
    assert _actions(context) == []


@pytest.mark.parametrize(
    "body",
    [
        {"content_type": "image/gif", "size_bytes": 10},
        {"content_type": "image/jpeg", "size_bytes": 0},
        {"content_type": "image/jpeg", "size_bytes": _MAX_BYTES + 1},
        {"content_type": "image/jpeg", "size_bytes": "10"},
        {"content_type": "image/jpeg", "size_bytes": 10, "object_key": "chosen"},
    ],
)
def test_upload_request_rejects_types_sizes_and_client_keys(
    photo_context: PhotoContext, body: dict[str, Any]
) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)

    response = context.client.post(_photos_url(), json=body)

    assert response.status_code == 422
    with context.session_factory() as session:
        assert session.query(ListingPhoto).count() == 0


def test_upload_limit_counts_confirmed_and_live_pending_photos_only(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)
    for index in range(9):
        _seed_photo(context, f"confirmed-{index}")
    expired_key = _seed_photo(
        context,
        "expired",
        status="pending",
        created_at=_NOW - timedelta(minutes=20),
    )

    tenth = _request_upload(context)
    eleventh = _request_upload(context)

    assert tenth.status_code == 201, tenth.text
    assert eleventh.status_code == 409
    assert _photo(context, "expired") is None
    assert expired_key not in context.storage.objects


def test_confirm_validates_and_rewrites_the_photo_without_metadata(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)
    upload = _request_upload(context).json()
    key = _photo_key(context, upload["photo_id"])
    original = _image_bytes("JPEG", (4, 2), orientation=6, gps=True)
    assert len(Image.open(io.BytesIO(original)).getexif().get_ifd(0x8825)) > 0
    context.storage.objects[key] = original

    response = context.client.post(_photos_url() + f"/{upload['photo_id']}/confirm")

    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == {"photo_id", "content_type", "size_bytes", "url", "created_at"}
    stored = context.storage.objects[key]
    cleaned = Image.open(io.BytesIO(stored))
    assert cleaned.format == "JPEG"
    assert len(cleaned.getexif()) == 0
    assert cleaned.size == (2, 4)
    assert context.storage.content_types[key] == "image/jpeg"
    confirmed = _photo(context, upload["photo_id"])
    assert confirmed is not None
    assert (confirmed.status, confirmed.size_bytes) == ("confirmed", len(stored))
    assert confirmed.confirmed_at is not None
    assert body["size_bytes"] == len(stored)
    assert urlsplit(body["url"]).path.endswith(key)

    again = context.client.post(_photos_url() + f"/{upload['photo_id']}/confirm")
    assert again.status_code == 200
    assert _actions(context) == ["edit"]


def test_confirm_before_upload_keeps_the_photo_pending(photo_context: PhotoContext) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)
    upload = _request_upload(context).json()

    response = context.client.post(_photos_url() + f"/{upload['photo_id']}/confirm")

    assert response.status_code == 409
    photo = _photo(context, upload["photo_id"])
    assert photo is not None and photo.status == "pending"


@pytest.mark.parametrize(
    ("declared", "data"),
    [
        ("image/png", _image_bytes("JPEG")),
        ("image/jpeg", b"not an image at all"),
        ("image/png", _image_bytes("PNG", (9000, 5000), mode="1")),
        ("image/jpeg", b"x" * (_MAX_BYTES + 1)),
    ],
    ids=["format-mismatch", "not-an-image", "too-many-pixels", "too-large"],
)
def test_confirm_discards_uploads_that_are_not_valid_photos(
    photo_context: PhotoContext, declared: str, data: bytes
) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)
    upload = _request_upload(context, declared).json()
    key = _photo_key(context, upload["photo_id"])
    context.storage.objects[key] = data

    response = context.client.post(_photos_url() + f"/{upload['photo_id']}/confirm")

    assert response.status_code == 422
    assert _photo(context, upload["photo_id"]) is None
    assert key not in context.storage.objects
    assert _actions(context) == []


def test_confirm_after_the_upload_window_is_rejected(photo_context: PhotoContext) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)
    upload = _request_upload(context).json()
    context.storage.objects[_photo_key(context, upload["photo_id"])] = _image_bytes("JPEG")
    context.clock[0] = _NOW + timedelta(minutes=15, seconds=1)

    response = context.client.post(_photos_url() + f"/{upload['photo_id']}/confirm")

    assert response.status_code == 409
    photo = _photo(context, upload["photo_id"])
    assert photo is not None and photo.status == "pending"


def test_list_returns_confirmed_photos_oldest_first_with_download_links(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)
    later_key = _seed_photo(context, "photo-c", created_at=_NOW + timedelta(seconds=5))
    first_key = _seed_photo(context, "photo-a")
    _seed_photo(context, "pending-b", status="pending")

    response = context.client.get(_photos_url())

    assert response.status_code == 200, response.text
    photos = response.json()["photos"]
    assert [photo["photo_id"] for photo in photos] == ["photo-a", "photo-c"]
    assert urlsplit(photos[0]["url"]).path.endswith(first_key)
    assert urlsplit(photos[1]["url"]).path.endswith(later_key)


@pytest.mark.parametrize(
    ("status", "published"),
    [
        ("draft", False),
        ("pending", False),
        ("approved", False),
        ("approved", True),
        ("rejected", False),
    ],
)
def test_photo_changes_return_the_listing_to_draft(
    photo_context: PhotoContext, status: str, published: bool
) -> None:
    context = photo_context
    _seed_listing(context, approval_status=status, is_published=published)
    _staff(context)
    upload = _request_upload(context).json()
    context.storage.objects[_photo_key(context, upload["photo_id"])] = _image_bytes("JPEG")

    confirmed = context.client.post(_photos_url() + f"/{upload['photo_id']}/confirm")

    assert confirmed.status_code == 200, confirmed.text
    listing = _listing(context)
    assert (listing.approval_status, listing.is_published) == ("draft", False)
    assert listing.offer_version == 1
    assert _actions(context) == ["edit"]


def test_delete_removes_the_object_and_returns_the_listing_to_draft(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context, approval_status="approved", is_published=True)
    _staff(context)
    key = _seed_photo(context, "photo-a")

    response = context.client.delete(_photos_url() + "/photo-a")

    assert response.status_code == 204
    assert _photo(context, "photo-a") is None
    assert key not in context.storage.objects
    listing = _listing(context)
    assert (listing.approval_status, listing.is_published) == ("draft", False)
    assert _actions(context) == ["edit"]


def test_deleting_a_pending_photo_does_not_reopen_the_listing(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context, approval_status="pending")
    _staff(context)
    _seed_photo(context, "pending-a", status="pending")

    response = context.client.delete(_photos_url() + "/pending-a")

    assert response.status_code == 204
    assert _listing(context).approval_status == "pending"
    assert _actions(context) == []


def test_submit_requires_one_confirmed_photo(photo_context: PhotoContext) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)
    _seed_photo(context, "pending-a", status="pending")
    submit_url = "/api/v1/staff/agencies/agency-one/listings/listing-one/submit"

    without = context.client.post(submit_url)
    assert without.status_code == 409
    assert _listing(context).approval_status == "draft"
    assert _actions(context) == []

    _seed_photo(context, "photo-b")
    with_photo = context.client.post(submit_url)
    assert with_photo.status_code == 200, with_photo.text
    assert _listing(context).approval_status == "pending"


_PHOTO_ROUTES = [
    ("request", "POST", "", {"content_type": "image/jpeg", "size_bytes": 10}),
    ("confirm", "POST", "/photo-a/confirm", None),
    ("list", "GET", "", None),
    ("delete", "DELETE", "/photo-a", None),
]
_PHOTO_ROUTE_IDS = [route[0] for route in _PHOTO_ROUTES]


@pytest.mark.parametrize(
    ("role", "tenant_id"),
    [("agency_admin", "agency-two"), ("agent", "agency-two"), ("platform_admin", None)],
    ids=["other-agency-admin", "other-agency-agent", "platform-admin"],
)
@pytest.mark.parametrize(("name", "method", "suffix", "body"), _PHOTO_ROUTES, ids=_PHOTO_ROUTE_IDS)
def test_actors_outside_the_agency_are_forbidden_on_photo_routes(
    photo_context: PhotoContext,
    role: str,
    tenant_id: str | None,
    name: str,
    method: str,
    suffix: str,
    body: dict[str, Any] | None,
) -> None:
    context = photo_context
    _seed_listing(context)
    key = _seed_photo(context, "photo-a", status="pending")
    _staff(context, role=role, tenant_id=tenant_id)

    response = context.client.request(method, _photos_url() + suffix, json=body)

    assert response.status_code == 403, name
    assert "photo-a" not in response.text and "storage.example.test" not in response.text
    assert _photo(context, "photo-a") is not None and key in context.storage.objects


@pytest.mark.parametrize(("name", "method", "suffix", "body"), _PHOTO_ROUTES, ids=_PHOTO_ROUTE_IDS)
def test_foreign_listing_or_photo_under_own_agency_is_indistinguishable_from_missing(
    photo_context: PhotoContext,
    name: str,
    method: str,
    suffix: str,
    body: dict[str, Any] | None,
) -> None:
    context = photo_context
    _seed_listing(context)
    _seed_listing(context, "foreign-listing", agency_id="agency-two")
    key = _seed_photo(
        context, "photo-a", listing_id="foreign-listing", agency_id="agency-two", status="pending"
    )
    _staff(context, role="agency_admin")

    foreign = context.client.request(method, _photos_url("foreign-listing") + suffix, json=body)
    missing = context.client.request(method, _photos_url("missing-listing") + suffix, json=body)

    assert foreign.status_code == missing.status_code == 404, name
    assert foreign.json() == missing.json()
    assert _photo(context, "photo-a") is not None and key in context.storage.objects
    if suffix:
        # A photo of another listing is also missing under this agency's own listing.
        own = context.client.request(method, _photos_url() + suffix, json=body)
        assert own.status_code == 404, name


def test_photo_routes_fail_closed_without_storage(storageless_context: PhotoContext) -> None:
    context = storageless_context
    _seed_listing(context)
    _staff(context)

    response = _request_upload(context)

    assert response.status_code == 503
    with context.session_factory() as session:
        assert session.query(ListingPhoto).count() == 0


# --- Public catalog exposure --------------------------------------------------


def test_public_catalog_shows_only_confirmed_photos_of_published_listings(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context, approval_status="approved", is_published=True)
    _seed_listing(context, "bare-listing", approval_status="approved", is_published=True)
    _seed_listing(context, "draft-listing")
    later_key = _seed_photo(context, "photo-c", created_at=_NOW + timedelta(seconds=5))
    first_key = _seed_photo(context, "photo-a")
    _seed_photo(context, "pending-b", status="pending")
    _seed_photo(context, "draft-photo", listing_id="draft-listing")

    listed = context.client.get("/api/v1/listings")
    detail = context.client.get("/api/v1/listings/listing-one")
    bare = context.client.get("/api/v1/listings/bare-listing")
    hidden = context.client.get("/api/v1/listings/draft-listing")

    assert listed.status_code == detail.status_code == bare.status_code == 200
    covers = {item["listing_id"]: item["cover_photo_url"] for item in listed.json()["items"]}
    assert set(covers) == {"listing-one", "bare-listing"}
    assert covers["bare-listing"] is None
    assert urlsplit(covers["listing-one"]).path.endswith(first_key)
    photos = detail.json()["photos"]
    assert [photo["photo_id"] for photo in photos] == ["photo-a", "photo-c"]
    assert all(set(photo) == {"photo_id", "url"} for photo in photos)
    assert urlsplit(photos[1]["url"]).path.endswith(later_key)
    assert bare.json()["photos"] == []
    assert hidden.status_code == 404
    assert "draft-photo" not in listed.text and "pending-b" not in detail.text


def test_public_catalog_omits_photos_when_storage_is_not_configured(
    storageless_context: PhotoContext,
) -> None:
    context = storageless_context
    _seed_listing(context, approval_status="approved", is_published=True)
    with context.session_factory.begin() as session:
        session.add(
            ListingPhoto(
                id="photo-a",
                agency_id="agency-one",
                listing_id="listing-one",
                object_key="agencies/agency-one/listings/listing-one/photos/photo-a",
                status="confirmed",
                content_type="image/png",
                size_bytes=10,
                created_at=_NOW,
                expires_at=_NOW + timedelta(minutes=15),
                confirmed_at=_NOW,
            )
        )

    listed = context.client.get("/api/v1/listings")
    detail = context.client.get("/api/v1/listings/listing-one")

    assert listed.json()["items"][0]["cover_photo_url"] is None
    assert detail.json()["photos"] == []
