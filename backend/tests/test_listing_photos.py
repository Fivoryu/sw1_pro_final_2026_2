from __future__ import annotations

import base64
import importlib.util
import io
import shutil
import tempfile
from collections.abc import Generator, Iterator
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from threading import Event
from typing import Any
from urllib.parse import parse_qs, urlsplit

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import Engine, create_engine, text
from sqlalchemy.orm import Session, sessionmaker

import app.main as main_module
from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.modules.catalog import photo_storage as photo_storage_module
from app.modules.catalog.models import (
    Listing,
    ListingPhoto,
    ListingPhotoDeletion,
    ListingTransition,
)
from app.modules.catalog.photos import UPLOAD_WINDOW, cleanup_photo_deletion_intents
from app.modules.catalog.photo_storage import (
    InMemoryPhotoStorage,
    PhotoStorageUnavailableError,
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


def test_real_storage_refuses_missing_or_remote_endpoint_without_opt_in(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client_calls: list[dict[str, Any]] = []

    def fake_client(service: str, **kwargs: Any) -> object:
        client_calls.append({"service": service, **kwargs})
        return object()

    monkeypatch.setattr(photo_storage_module.boto3, "client", fake_client)

    for endpoint in (None, "https://s3.us-east-1.amazonaws.com"):
        with pytest.raises(ValueError, match="S3_ENDPOINT_URL"):
            create_photo_storage(
                _settings(s3_bucket_name="photo-bucket", s3_endpoint_url=endpoint)
            )
    assert client_calls == []


def test_local_s3_clients_use_placeholders_and_remote_opt_in_is_explicit(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client_calls: list[dict[str, Any]] = []

    def fake_client(service: str, **kwargs: Any) -> object:
        client_calls.append({"service": service, **kwargs})
        return object()

    monkeypatch.setattr(photo_storage_module.boto3, "client", fake_client)

    storage = create_photo_storage(
        _settings(s3_bucket_name="photo-bucket", s3_endpoint_url="http://floci:4566")
    )

    assert isinstance(storage, S3PhotoStorage)
    assert len(client_calls) == 2
    assert all(call["aws_access_key_id"] == "local-test-key" for call in client_calls)
    assert all(call["aws_secret_access_key"] == "local-test-secret" for call in client_calls)

    remote = create_photo_storage(
        _settings(
            s3_bucket_name="photo-bucket",
            s3_endpoint_url="https://s3.us-east-1.amazonaws.com",
            s3_allow_remote_endpoint=True,
            s3_access_key_id="explicit-access-key",
            s3_secret_access_key="explicit-secret-key",
        )
    )
    assert isinstance(remote, S3PhotoStorage)
    assert len(client_calls) == 4
    assert all(
        call["aws_access_key_id"] == "explicit-access-key"
        and call["aws_secret_access_key"] == "explicit-secret-key"
        for call in client_calls[2:]
    )


def test_remote_s3_opt_in_fails_closed_without_explicit_credentials(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client_calls: list[dict[str, Any]] = []

    def fake_client(service: str, **kwargs: Any) -> object:
        client_calls.append({"service": service, **kwargs})
        return object()

    monkeypatch.setattr(photo_storage_module.boto3, "client", fake_client)

    with pytest.raises(ValueError, match="credentials"):
        create_photo_storage(
            _settings(
                s3_bucket_name="photo-bucket",
                s3_endpoint_url="https://s3.us-east-1.amazonaws.com",
                s3_allow_remote_endpoint=True,
            )
        )

    assert client_calls == []


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
_MAX_BYTES = 20 * 1024 * 1024
# Mirrors the policy grace the deletion journal keeps after the upload window closes.
_DELETION_GRACE = timedelta(minutes=15)
_TRUNCATED_HEIF_FIXTURE = base64.b64decode(
    "AAAAHGZ0eXBoZWljAAAAAG1pZjFoZWljbWlhZgAAAXxtZXRhAAAAAAAAACFoZGxyAAAAAAAAAABwaWN0AAAAAAAAAAAAAAAAAAAAACJpbG9jAAAAAERAAAEAAQAAAAABoAABAAAAAAAAADYAAAAjaWluZgAAAAAAAQAAABVpbmZlAgAAAAABAABodmMxAAAAAA5waXRtAAAAAAABAAAA/GlwcnAAAADcaXBjbwAAAHVodmNDAQNwAAAAkAAAAAAAHvAA/P34+AAADwNgAAEAGEABDAH//wNwAAADAJAAAAMAAAMAHroCQGEAAQApQgEBA3AAAAMAkAAAAwAAAwAeoCCBBZbqrprm4CGgwIAAAAyAAAADAIRiAAEABkQBwXPBiQAAABNjb2xybmNseAABAA0ABoAAAAAUaXNwZQAAAAAAAABAAAAAQAAAAChjbGFwAAAABAAAAAEAAAACAAAAAf///wQAAAAC////wgAAAAIAAAAQcGl4aQAAAAADCAgIAAAAGGlwbWEAAAAAAAAAAQABBYECAwWEAAAAPm1kYXRhAAAAyKAGvBPIWhzRxZNLf/Fd///6nY7L9qdcEm1Qjs/RSxGAmv3XroGTEzROpbNAoK6inXqY="
)


def _encode_heif_fixture() -> bytes:
    output = io.BytesIO()
    Image.new("RGB", (4, 2), color=(80, 120, 200)).save(output, format="HEIF", quality=90)
    return output.getvalue()


_HEIF_FIXTURE = _encode_heif_fixture()


@dataclass
class PhotoContext:
    client: TestClient
    app: FastAPI
    session_factory: sessionmaker[Session]
    storage: InMemoryPhotoStorage
    clock: list[datetime]


class _CleanupObservedPhotoStorage(InMemoryPhotoStorage):
    def __init__(self) -> None:
        super().__init__()
        self.expected_deleted_keys: set[str] = set()
        self.deleted_keys: set[str] = set()
        self.expected_deletes_complete = Event()

    def delete(self, key: str) -> None:
        super().delete(key)
        self.deleted_keys.add(key)
        if self.expected_deleted_keys and self.expected_deleted_keys <= self.deleted_keys:
            self.expected_deletes_complete.set()


class _RetryObservedPhotoStorage(InMemoryPhotoStorage):
    def __init__(self) -> None:
        super().__init__()
        self.fail_key: str | None = None
        self.failed = False
        self.failure_observed = Event()
        self.expected_deleted_keys: set[str] = set()
        self.deleted_keys: set[str] = set()
        self.deletions_complete = Event()

    def fail_once_on(self, key: str) -> None:
        self.fail_key = key

    def delete(self, key: str) -> None:
        if key == self.fail_key and not self.failed:
            self.failed = True
            self.failure_observed.set()
            raise PhotoStorageUnavailableError
        super().delete(key)
        self.deleted_keys.add(key)
        if self.expected_deleted_keys and self.expected_deleted_keys <= self.deleted_keys:
            self.deletions_complete.set()


class _LateSigningPhotoStorage(InMemoryPhotoStorage):
    """Signer stamps the URL later than the request instant, as a real signer does."""

    def __init__(self, clock: list[datetime]) -> None:
        super().__init__()
        self.clock = clock

    def presign_upload(self, key: str, *, content_type: str, expires_in: int) -> str:
        self.clock[0] = self.clock[0] + timedelta(seconds=30)
        return super().presign_upload(key, content_type=content_type, expires_in=expires_in)


def _install_offer_version_triggers(engine: Engine) -> None:
    path = Path(__file__).resolve().parents[1] / "alembic" / "versions" / "0007_catalog_offers.py"
    spec = importlib.util.spec_from_file_location("photo_test_catalog_offers", path)
    assert spec is not None and spec.loader is not None
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    from alembic.migration import MigrationContext
    from alembic.operations import Operations

    with engine.begin() as connection:
        # The 0007 bootstrap runs once per database; a second context over the same
        # file database already owns the guard table and its triggers.
        guard_installed = connection.execute(
            text(
                "SELECT 1 FROM sqlite_master "
                "WHERE type = 'table' AND name = 'listing_offer_version_guard'"
            )
        ).first()
        if guard_installed is not None:
            return
        with Operations.context(MigrationContext.configure(connection)):
            migration._install_sqlite_offer_version_triggers()


def _build_context(
    storage: InMemoryPhotoStorage | None,
    *,
    database_url: str = "sqlite+pysqlite:///:memory:",
    clock: list[datetime] | None = None,
) -> Generator[PhotoContext, None, None]:
    # In-memory SQLite under StaticPool is a single connection shared by every
    # session, and the periodic photo workers run on thread-pool threads while
    # the test thread also uses the database: two threads on one pysqlite
    # connection deadlock inside native code, which is the CI stall seen at 48%
    # of the suite. A temporary file-backed database gives each session its own
    # connection, so the sharing that enables the deadlock no longer exists.
    temp_directory: Path | None = None
    if database_url == "sqlite+pysqlite:///:memory:":
        temp_directory = Path(tempfile.mkdtemp(prefix="roomforge-photos-test-"))
        database_url = f"sqlite+pysqlite:///{temp_directory / 'photos.db'}"
    engine = create_engine(
        database_url,
        connect_args={"check_same_thread": False, "timeout": 30},
    )
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    Base.metadata.create_all(engine)
    _install_offer_version_triggers(engine)
    clock_state = clock if clock is not None else [_NOW]
    app = create_app(
        settings=_settings(database_url=database_url),
        session_factory=factory,
        clock=lambda: clock_state[0],
        photo_storage=storage,
    )
    try:
        with TestClient(app) as client:
            yield PhotoContext(
                client, app, factory, storage or InMemoryPhotoStorage(), clock_state
            )
    finally:
        engine.dispose()
        if temp_directory is not None:
            shutil.rmtree(temp_directory, ignore_errors=True)


@pytest.fixture
def photo_context() -> Iterator[PhotoContext]:
    yield from _build_context(InMemoryPhotoStorage())


@pytest.fixture
def storageless_context() -> Iterator[PhotoContext]:
    yield from _build_context(None)


@pytest.fixture
def photo_cleanup_context(monkeypatch: pytest.MonkeyPatch) -> Iterator[PhotoContext]:
    monkeypatch.setattr(
        main_module,
        "PHOTO_UPLOAD_CLEANUP_INTERVAL_SECONDS",
        0.1,
        raising=False,
    )
    yield from _build_context(_CleanupObservedPhotoStorage())


@pytest.fixture
def photo_deletion_manual_context(monkeypatch: pytest.MonkeyPatch) -> Iterator[PhotoContext]:
    """Deletion context whose periodic worker never fires, so sweeps run deterministically by hand."""
    monkeypatch.setattr(
        main_module,
        "PHOTO_DELETION_RETRY_INTERVAL_SECONDS",
        3600.0,
        raising=False,
    )
    yield from _build_context(_CleanupObservedPhotoStorage())


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
    original_object_key: str | None = None,
    upload_object_key: str | None = None,
) -> str:
    key = f"agencies/{agency_id}/listings/{listing_id}/photos/{photo_id}"
    with context.session_factory.begin() as session:
        session.add(
            ListingPhoto(
                id=photo_id,
                agency_id=agency_id,
                listing_id=listing_id,
                object_key=key,
                original_object_key=original_object_key,
                upload_object_key=upload_object_key,
                status=status,
                content_type="image/png",
                size_bytes=10,
                created_at=created_at,
                expires_at=expires_at or created_at + timedelta(minutes=15),
                confirmed_at=created_at if status == "confirmed" else None,
            )
        )
    for asset_key in {key, original_object_key, upload_object_key} - {None}:
        context.storage.write(asset_key, _image_bytes("PNG"), content_type="image/png")
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


def test_signed_upload_url_never_outlives_the_stored_expiry() -> None:
    clock = [_NOW]
    storage = _LateSigningPhotoStorage(clock)
    context_generator = _build_context(storage, clock=clock)
    context = next(context_generator)
    try:
        _seed_listing(context)
        _staff(context)
        upload = _request_upload(context).json()

        photo = _photo(context, upload["photo_id"])
        assert photo is not None
        # The URL was signed 30s after the request instant, so the deadline the deletion
        # journal trusts must cover that URL instead of falling short of it.
        assert photo.expires_at - photo.created_at == UPLOAD_WINDOW + timedelta(seconds=30)
    finally:
        context_generator.close()


def test_staging_assets_live_under_a_prefix_that_cannot_reach_confirmed_photos(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)
    upload = _request_upload(context).json()
    upload_key = _photo_key(context, upload["photo_id"])
    context.storage.write(upload_key, _image_bytes("JPEG"), content_type="image/jpeg")

    confirmed = context.client.post(_photos_url() + f"/{upload['photo_id']}/confirm")

    assert confirmed.status_code == 200, confirmed.text
    photo = _photo(context, upload["photo_id"])
    assert photo is not None
    # A bucket lifecycle rule can only filter by prefix, so the key a presigned PUT can
    # recreate has to sit under its own top-level prefix. The confirmed original and its
    # public derivative never expire, so the staging rule must never reach them.
    assert upload_key.startswith("staging/")
    assert photo.original_object_key is not None
    assert photo.object_key.startswith("agencies/")
    assert photo.original_object_key.startswith("agencies/")


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
    return getattr(photo, "upload_object_key", None) or photo.object_key


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
    expected_prefix = f"agencies/agency-one/listings/listing-one/photos/{body['photo_id']}"
    upload_key = getattr(photo, "upload_object_key", None)
    assert photo.object_key == f"{expected_prefix}/public"
    assert upload_key == f"staging/{expected_prefix}"
    assert photo.object_key != upload_key
    assert (photo.status, photo.content_type, photo.size_bytes) == ("pending", "image/webp", 4096)
    assert body["upload_method"] == "PUT"
    assert body["upload_headers"] == {"Content-Type": "image/webp"}
    assert urlsplit(body["upload_url"]).path.endswith(upload_key)
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
    for index in range(19):
        _seed_photo(context, f"confirmed-{index}")
    expired_key = _seed_photo(
        context,
        "expired",
        status="pending",
        created_at=_NOW - timedelta(minutes=20),
    )

    twentieth = _request_upload(context)
    twenty_first = _request_upload(context)

    assert twentieth.status_code == 201, twentieth.text
    assert twenty_first.status_code == 409
    assert _photo(context, "expired") is None
    assert expired_key not in context.storage.objects


@pytest.mark.parametrize("content_type", ["image/heic", "image/heif"])
def test_upload_request_accepts_heif_formats_at_the_20_mib_limit(
    photo_context: PhotoContext, content_type: str
) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)

    response = _request_upload(context, content_type, _MAX_BYTES)

    assert response.status_code == 201, response.text
    photo = _photo(context, response.json()["photo_id"])
    assert photo is not None
    assert photo.content_type == content_type
    assert photo.size_bytes == _MAX_BYTES


def test_confirm_preserves_the_original_and_sanitizes_a_separate_public_derivative(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)
    upload = _request_upload(context).json()
    upload_key = _photo_key(context, upload["photo_id"])
    original = _image_bytes("JPEG", (4, 2), orientation=6, gps=True)
    assert len(Image.open(io.BytesIO(original)).getexif().get_ifd(0x8825)) > 0
    context.storage.objects[upload_key] = original

    response = context.client.post(_photos_url() + f"/{upload['photo_id']}/confirm")

    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == {"photo_id", "content_type", "size_bytes", "url", "created_at"}
    confirmed = _photo(context, upload["photo_id"])
    assert confirmed is not None
    assert confirmed.status == "confirmed"
    original_key = getattr(confirmed, "original_object_key", None)
    assert original_key is not None
    assert context.storage.read(original_key, max_bytes=_MAX_BYTES) == original
    assert confirmed.object_key != upload_key
    derivative = context.storage.objects[confirmed.object_key]
    cleaned = Image.open(io.BytesIO(derivative))
    assert cleaned.format == "JPEG"
    assert len(cleaned.getexif()) == 0
    assert cleaned.size == (2, 4)
    assert context.storage.content_types[confirmed.object_key] == "image/jpeg"
    assert confirmed.size_bytes == len(original)
    assert confirmed.confirmed_at is not None
    assert body["size_bytes"] == len(original)
    assert urlsplit(body["url"]).path.endswith(confirmed.object_key)
    assert context.storage.objects[upload_key] == original

    context.clock[0] = _NOW + timedelta(minutes=15)
    next_upload = _request_upload(context)
    assert next_upload.status_code == 201, next_upload.text
    assert upload_key not in context.storage.objects
    assert original_key in context.storage.objects
    assert confirmed.object_key in context.storage.objects
    refreshed = _photo(context, upload["photo_id"])
    assert refreshed is not None and refreshed.upload_object_key is None

    again = context.client.post(_photos_url() + f"/{upload['photo_id']}/confirm")
    assert again.status_code == 200
    assert _actions(context) == ["edit"]


def test_legacy_pending_upload_preserves_its_signed_key_and_expires_only_staging(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)
    upload = _request_upload(context).json()
    photo_id = upload["photo_id"]
    legacy_key = f"agencies/agency-one/listings/listing-one/photos/{photo_id}"
    original = _image_bytes("JPEG", (4, 2), orientation=6, gps=True)
    with context.session_factory.begin() as session:
        photo = session.get(ListingPhoto, photo_id)
        assert photo is not None
        photo.object_key = legacy_key
        photo.upload_object_key = None
        photo.original_object_key = None
        photo.public_content_type = None
    context.storage.objects[legacy_key] = original

    response = context.client.post(_photos_url() + f"/{photo_id}/confirm")

    assert response.status_code == 200, response.text
    public_key = f"{legacy_key}/public"
    original_key = f"{legacy_key}/original"
    confirmed = _photo(context, photo_id)
    assert confirmed is not None
    assert confirmed.object_key == public_key
    assert confirmed.upload_object_key == legacy_key
    assert confirmed.original_object_key == original_key
    assert context.storage.objects[legacy_key] == original
    assert context.storage.objects[original_key] == original
    assert context.storage.content_types[public_key] == "image/jpeg"
    assert response.json()["content_type"] == "image/jpeg"
    assert response.json()["size_bytes"] == len(original)

    context.clock[0] = _NOW + timedelta(minutes=15)
    next_upload = _request_upload(context)
    assert next_upload.status_code == 201, next_upload.text
    assert legacy_key not in context.storage.objects
    assert public_key in context.storage.objects
    assert original_key in context.storage.objects
    expired_stage = _photo(context, photo_id)
    assert expired_stage is not None and expired_stage.upload_object_key is None


def test_expired_staging_is_cleaned_without_another_upload_request(
    photo_cleanup_context: PhotoContext,
) -> None:
    context = photo_cleanup_context
    _seed_listing(context)
    storage = context.storage
    assert isinstance(storage, _CleanupObservedPhotoStorage)

    prefix = "agencies/agency-one/listings/listing-one/photos"
    pending_upload_key = f"{prefix}/pending/upload"
    confirmed_upload_key = f"{prefix}/confirmed/upload"
    confirmed_public_key = f"{prefix}/confirmed/public"
    confirmed_original_key = f"{prefix}/confirmed/original"
    storage.expected_deleted_keys = {pending_upload_key, confirmed_upload_key}
    storage.write(pending_upload_key, b"partial", content_type="image/png")
    storage.write(confirmed_upload_key, b"late-put", content_type="image/png")
    storage.write(confirmed_public_key, b"public-photo", content_type="image/png")
    storage.write(confirmed_original_key, b"exact-original", content_type="image/png")

    expired_at = _NOW - timedelta(minutes=1)
    created_at = _NOW - timedelta(minutes=16)
    with context.session_factory.begin() as session:
        session.add(
            ListingPhoto(
                id="expired-pending",
                agency_id="agency-one",
                listing_id="listing-one",
                object_key=f"{prefix}/pending/public",
                upload_object_key=pending_upload_key,
                original_object_key=None,
                public_content_type=None,
                status="pending",
                content_type="image/png",
                size_bytes=7,
                created_at=created_at,
                expires_at=expired_at,
                confirmed_at=None,
            )
        )
        session.add(
            ListingPhoto(
                id="confirmed-photo",
                agency_id="agency-one",
                listing_id="listing-one",
                object_key=confirmed_public_key,
                upload_object_key=confirmed_upload_key,
                original_object_key=confirmed_original_key,
                public_content_type="image/png",
                status="confirmed",
                content_type="image/png",
                size_bytes=13,
                created_at=created_at,
                expires_at=expired_at,
                confirmed_at=created_at,
            )
        )

    assert storage.expected_deletes_complete.wait(timeout=2.0), (
        "Expired staging objects were not cleaned while the listing was idle"
    )
    assert storage.read(pending_upload_key, max_bytes=64) is None
    assert storage.read(confirmed_upload_key, max_bytes=64) is None
    assert storage.read(confirmed_public_key, max_bytes=64) == b"public-photo"
    assert storage.read(confirmed_original_key, max_bytes=64) == b"exact-original"

    _staff(context)
    listed = context.client.get(_photos_url())
    assert listed.status_code == 200, listed.text
    assert [photo["photo_id"] for photo in listed.json()["photos"]] == ["confirmed-photo"]


def test_confirm_preserves_heic_original_and_publishes_a_jpeg_derivative(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context)
    _staff(context)
    upload = _request_upload(context, "image/heic", len(_HEIF_FIXTURE)).json()
    upload_key = _photo_key(context, upload["photo_id"])
    context.storage.write(upload_key, _HEIF_FIXTURE, content_type="image/heic")

    response = context.client.post(_photos_url() + f"/{upload['photo_id']}/confirm")

    assert response.status_code == 200, response.text
    original_key = f"agencies/agency-one/listings/listing-one/photos/{upload['photo_id']}/original"
    public_key = f"agencies/agency-one/listings/listing-one/photos/{upload['photo_id']}/public"
    assert context.storage.read(original_key, max_bytes=_MAX_BYTES) == _HEIF_FIXTURE
    derivative = context.storage.read(public_key, max_bytes=_MAX_BYTES)
    assert derivative is not None
    assert Image.open(io.BytesIO(derivative)).format == "JPEG"
    assert context.storage.content_types[public_key] == "image/jpeg"
    assert response.json()["size_bytes"] == len(_HEIF_FIXTURE)
    assert urlsplit(response.json()["url"]).path.endswith(public_key)


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
        ("image/heic", _TRUNCATED_HEIF_FIXTURE),
    ],
    ids=["format-mismatch", "not-an-image", "too-many-pixels", "too-large", "truncated-heif"],
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


def test_discarded_invalid_upload_is_swept_once_its_signed_put_expires(
    photo_deletion_manual_context: PhotoContext,
) -> None:
    context = photo_deletion_manual_context
    _seed_listing(context)
    _staff(context)
    upload = _request_upload(context, "image/jpeg").json()
    key = _photo_key(context, upload["photo_id"])
    context.storage.objects[key] = b"not an image at all"

    response = context.client.post(_photos_url() + f"/{upload['photo_id']}/confirm")

    assert response.status_code == 422
    assert _photo(context, upload["photo_id"]) is None
    # Discarding deletes the row, so the journal is the only thing that can still
    # remove an object the signed PUT of that key is still allowed to recreate.
    _sweep_deletions(context)
    assert _deletion_intent_count(context) == 1

    context.storage.write(key, b"late-put", content_type="image/jpeg")

    context.clock[0] = _NOW + UPLOAD_WINDOW + _DELETION_GRACE + timedelta(seconds=1)
    _sweep_deletions(context)

    assert context.storage.read(key, max_bytes=_MAX_BYTES) is None


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


def test_agent_cannot_delete_a_confirmed_photo(photo_context: PhotoContext) -> None:
    context = photo_context
    _seed_listing(context, approval_status="approved", is_published=True)
    _staff(context, role="agent")
    key = _seed_photo(context, "photo-a")

    response = context.client.delete(_photos_url() + "/photo-a")

    assert response.status_code == 403
    listed = context.client.get(_photos_url())
    assert listed.status_code == 200, listed.text
    assert [photo["photo_id"] for photo in listed.json()["photos"]] == ["photo-a"]
    assert context.storage.read(key, max_bytes=_MAX_BYTES) is not None
    listing = _listing(context)
    assert (listing.approval_status, listing.is_published) == ("approved", True)
    assert _actions(context) == []


def test_delete_removes_the_object_and_returns_the_listing_to_draft(
    photo_deletion_manual_context: PhotoContext,
) -> None:
    context = photo_deletion_manual_context
    _seed_listing(context, approval_status="approved", is_published=True)
    _staff(context, role="agency_admin")
    original_key = "private/original/photo-a"
    upload_key = "staging/photo-a"
    public_key = _seed_photo(
        context,
        "photo-a",
        original_object_key=original_key,
        upload_object_key=upload_key,
    )
    storage = context.storage
    assert isinstance(storage, _CleanupObservedPhotoStorage)
    storage.expected_deleted_keys = {public_key, original_key, upload_key}

    response = context.client.delete(_photos_url() + "/photo-a")

    assert response.status_code == 204
    # The sweep is driven by hand, like the rest of the deletion tests: it asserts exact
    # retry journal behavior, not the periodic worker's timing.
    _sweep_deletions(context)
    listed = context.client.get(_photos_url())
    assert listed.status_code == 200, listed.text
    assert listed.json()["photos"] == []
    assert all(
        storage.read(key, max_bytes=_MAX_BYTES) is None
        for key in storage.expected_deleted_keys
    )
    listing = _listing(context)
    assert (listing.approval_status, listing.is_published) == ("draft", False)
    assert _actions(context) == ["edit"]


def test_photo_workers_start_even_when_the_rate_refresh_is_disabled(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The photo workers answer to the photo storage, not to the rate refresher.

    A review claimed the deletion worker was created inside the rate-refresh gate. It was
    not, and this pins that: with the refresher disabled the journal would never drain and
    a confirmed photo the admin deleted would keep its objects forever.
    """
    monkeypatch.setenv("ROOMFORGE_RATE_REFRESH_SECONDS", "0")
    context_generator = _build_context(_CleanupObservedPhotoStorage())
    context = next(context_generator)
    try:
        assert getattr(context.app.state, "photo_cleaner_task", None) is not None
        assert getattr(context.app.state, "photo_deleter_task", None) is not None
    finally:
        context_generator.close()


def test_photo_deletion_intent_survives_restart_and_retries_storage_failure(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    database_url = f"sqlite+pysqlite:///{tmp_path / 'photo-deletion.sqlite'}"
    storage = _RetryObservedPhotoStorage()
    clock = [_NOW]
    public_key = "agencies/agency-one/listings/listing-one/photos/photo-retry"
    original_key = "private/original/photo-retry"
    upload_key = "staging/photo-retry"
    expected_keys = {public_key, original_key, upload_key}
    monkeypatch.setattr(
        main_module,
        "PHOTO_DELETION_RETRY_INTERVAL_SECONDS",
        3600.0,
        raising=False,
    )

    first_context_generator = _build_context(
        storage, database_url=database_url, clock=clock
    )
    first_context = next(first_context_generator)
    try:
        _seed_listing(first_context, approval_status="approved", is_published=True)
        _staff(first_context, role="agency_admin")
        _seed_photo(
            first_context,
            "photo-retry",
            original_object_key=original_key,
            upload_object_key=upload_key,
        )

        response = first_context.client.delete(_photos_url() + "/photo-retry")

        assert response.status_code == 204
        listed = first_context.client.get(_photos_url())
        assert listed.status_code == 200, listed.text
        assert listed.json()["photos"] == []
        assert _listing(first_context).approval_status == "draft"
        assert _actions(first_context) == ["edit"]
        assert all(
            storage.read(key, max_bytes=_MAX_BYTES) is not None
            for key in expected_keys
        )
    finally:
        first_context_generator.close()

    storage.fail_once_on(public_key)
    storage.expected_deleted_keys = expected_keys
    monkeypatch.setattr(
        main_module,
        "PHOTO_DELETION_RETRY_INTERVAL_SECONDS",
        0.1,
        raising=False,
    )
    second_context_generator = _build_context(
        storage, database_url=database_url, clock=clock
    )
    second_context = next(second_context_generator)
    try:
        assert storage.failure_observed.wait(timeout=5)
        assert all(
            storage.read(key, max_bytes=_MAX_BYTES) is not None
            for key in expected_keys
        )
        clock[0] = _NOW + timedelta(seconds=1)
        assert storage.deletions_complete.wait(timeout=5)
        assert all(
            storage.read(key, max_bytes=_MAX_BYTES) is None
            for key in expected_keys
        )
        _staff(second_context, role="agency_admin")
        listed = second_context.client.get(_photos_url())
        assert listed.status_code == 200, listed.text
        assert listed.json()["photos"] == []
    finally:
        second_context_generator.close()


def _sweep_deletions(context: PhotoContext) -> None:
    """Run the deletion sweep once, exactly as the periodic worker does."""
    with context.session_factory.begin() as session:
        cleanup_photo_deletion_intents(
            session,
            context.storage,
            now=context.clock[0],
            retry_after=timedelta(seconds=1),
            batch_size=100,
        )


def _deletion_intent_count(context: PhotoContext) -> int:
    with context.session_factory.begin() as session:
        return session.query(ListingPhotoDeletion).count()


def test_late_presigned_upload_is_swept_after_a_confirmed_photo_is_deleted(
    photo_deletion_manual_context: PhotoContext,
) -> None:
    context = photo_deletion_manual_context
    _seed_listing(context, approval_status="approved", is_published=True)
    _staff(context, role="agency_admin")
    storage = context.storage
    upload_key = "staging/photo-late"
    original_key = "private/original/photo-late"
    public_key = _seed_photo(
        context,
        "photo-late",
        original_object_key=original_key,
        upload_object_key=upload_key,
    )

    response = context.client.delete(_photos_url() + "/photo-late")

    assert response.status_code == 204
    _sweep_deletions(context)
    assert all(
        storage.read(key, max_bytes=_MAX_BYTES) is None
        for key in (public_key, original_key, upload_key)
    )
    # That staging key's presigned PUT stays authorized for a whole window, so the
    # deletion record must outlive the successful deletion instead of being dropped.
    assert _deletion_intent_count(context) == 1

    storage.write(upload_key, b"late-put", content_type="image/png")
    assert storage.read(upload_key, max_bytes=_MAX_BYTES) == b"late-put"

    context.clock[0] = _NOW + UPLOAD_WINDOW + _DELETION_GRACE + timedelta(seconds=1)
    _sweep_deletions(context)

    assert storage.read(upload_key, max_bytes=_MAX_BYTES) is None


def test_deletion_journal_survives_the_grace_after_the_upload_window_closes(
    photo_deletion_manual_context: PhotoContext,
) -> None:
    context = photo_deletion_manual_context
    _seed_listing(context, approval_status="approved", is_published=True)
    _staff(context, role="agency_admin")
    upload_key = "staging/photo-grace"
    _seed_photo(context, "photo-grace", upload_object_key=upload_key)

    response = context.client.delete(_photos_url() + "/photo-grace")

    assert response.status_code == 204
    _sweep_deletions(context)
    assert _deletion_intent_count(context) == 1

    context.clock[0] = _NOW + UPLOAD_WINDOW + timedelta(seconds=1)
    _sweep_deletions(context)
    # A PUT authorized before the window closed can still be landing, so the record is
    # kept for one more grace period before it is dropped.
    assert _deletion_intent_count(context) == 1

    context.clock[0] = _NOW + UPLOAD_WINDOW + _DELETION_GRACE + timedelta(seconds=1)
    _sweep_deletions(context)
    assert _deletion_intent_count(context) == 0


def test_late_presigned_upload_is_swept_after_a_pending_photo_is_deleted(
    photo_deletion_manual_context: PhotoContext,
) -> None:
    context = photo_deletion_manual_context
    _seed_listing(context, approval_status="pending")
    _staff(context, role="agent")
    storage = context.storage
    upload_key = "staging/photo-pending-late"
    _seed_photo(context, "pending-late", status="pending", upload_object_key=upload_key)

    response = context.client.delete(_photos_url() + "/pending-late")

    # Discarding a pending photo stays synchronous for agency editors.
    assert response.status_code == 204
    assert storage.read(upload_key, max_bytes=_MAX_BYTES) is None
    assert _listing(context).approval_status == "pending"
    _sweep_deletions(context)
    assert _deletion_intent_count(context) == 1

    storage.write(upload_key, b"late-put", content_type="image/png")

    context.clock[0] = _NOW + UPLOAD_WINDOW + _DELETION_GRACE + timedelta(seconds=1)
    _sweep_deletions(context)

    assert storage.read(upload_key, max_bytes=_MAX_BYTES) is None


def test_deleting_a_pending_photo_does_not_reopen_the_listing(
    photo_context: PhotoContext,
) -> None:
    context = photo_context
    _seed_listing(context, approval_status="pending")
    _staff(context, role="agent")
    key = _seed_photo(context, "pending-a", status="pending")

    response = context.client.delete(_photos_url() + "/pending-a")

    assert response.status_code == 204
    assert context.storage.read(key, max_bytes=_MAX_BYTES) is None
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
