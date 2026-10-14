"""Contract tests for the detection job API (F08.4).

Every acceptance rule is checked through the public interface: the HTTP route
and the job states the API reports back. The queue is a double and the database
is a throwaway SQLite file, so the whole suite runs without AWS or a network.

Where a rule says "nothing was created", the check reads the listing's job list
from the API instead of querying storage: the observable effect is what matters.
"""

from __future__ import annotations

import base64
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.modules.catalog.models import Listing, ListingPhoto
from app.modules.catalog.photo_storage import InMemoryPhotoStorage
from app.modules.detection.job_queue import InMemoryJobQueue, SqsJobQueue
from app.modules.identity.models import Agency
from app.modules.identity.session import get_active_staff

_NOW = datetime(2026, 10, 14, 18, 0, tzinfo=UTC)
MODEL_ID = "ssdlite320-mobilenetv3-coco-v1"


def _settings(**changes: object) -> Settings:
    values: dict[str, object] = {
        "database_url": "sqlite+pysqlite:///:memory:",
        "jwt_secret": "detection-test-secret-that-is-at-least-thirty-two-bytes",
        "totp_encryption_key": base64.urlsafe_b64encode(b"0" * 32).decode(),
        "web_origin": "http://localhost",
    }
    values.update(changes)
    return Settings(**values)  # type: ignore[arg-type]


@dataclass
class DetectionContext:
    client: TestClient
    app: FastAPI
    session_factory: sessionmaker[Session]
    queue: InMemoryJobQueue


def _open_context(queue: InMemoryJobQueue, *, authenticate: bool = True) -> DetectionContext:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    Base.metadata.create_all(engine)
    app = create_app(
        settings=_settings(),
        session_factory=factory,
        clock=lambda: _NOW,
        photo_storage=InMemoryPhotoStorage(),
        job_queue=queue,
    )
    if authenticate:
        app.dependency_overrides[get_active_staff] = lambda: {
            "id": "detection-actor",
            "email": "detection-actor@example.test",
            "role": "agent",
            "tenant_id": "agency-one",
        }
    return DetectionContext(TestClient(app), app, factory, queue)


@pytest.fixture
def context() -> Iterator[DetectionContext]:
    opened = _open_context(InMemoryJobQueue())
    with opened.client:
        yield opened


@pytest.fixture
def anonymous_context() -> Iterator[DetectionContext]:
    opened = _open_context(InMemoryJobQueue(), authenticate=False)
    with opened.client:
        yield opened


def _seed_listing(
    session_factory: sessionmaker[Session],
    *,
    agency_id: str = "agency-one",
    listing_id: str = "listing-one",
) -> None:
    with session_factory.begin() as session:
        session.add(Agency(id=agency_id))
        session.add(
            Listing(
                id=listing_id,
                agency_id=agency_id,
                approval_status="approved",
                is_published=True,
                operation="sale",
                base_price=Decimal("100000.00"),
                offer_version=1,
                city="La Paz",
                zone="Sopocachi",
                bedrooms=2,
                bathrooms=1,
            )
        )


def _seed_photo(
    session_factory: sessionmaker[Session],
    photo_id: str = "photo-one",
    *,
    agency_id: str = "agency-one",
    listing_id: str = "listing-one",
    status: str = "confirmed",
) -> str:
    object_key = f"agencies/{agency_id}/listings/{listing_id}/photos/{photo_id}"
    with session_factory.begin() as session:
        session.add(
            ListingPhoto(
                id=photo_id,
                agency_id=agency_id,
                listing_id=listing_id,
                object_key=object_key,
                status=status,
                content_type="image/jpeg",
                size_bytes=1024,
                created_at=_NOW,
                expires_at=_NOW + timedelta(minutes=15),
                confirmed_at=_NOW if status == "confirmed" else None,
            )
        )
    return object_key


def _detections_url(
    *,
    agency_id: str = "agency-one",
    listing_id: str = "listing-one",
    photo_id: str = "photo-one",
) -> str:
    return f"/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/photos/{photo_id}/detections"


def _jobs_url(*, agency_id: str = "agency-one", listing_id: str = "listing-one") -> str:
    return f"/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/detections"


def _listed_jobs(context: DetectionContext, *, agency_id: str = "agency-one") -> list[dict[str, object]]:
    response = context.client.get(_jobs_url(agency_id=agency_id))
    assert response.status_code == 200, response.text
    return list(response.json()["jobs"])


def test_requesting_detection_creates_a_pending_job_and_publishes_one_message(
    context: DetectionContext,
) -> None:
    _seed_listing(context.session_factory)
    object_key = _seed_photo(context.session_factory)

    response = context.client.post(_detections_url())

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["status"] == "pending"
    assert body["attempts"] == 0
    assert body["result"] is None
    assert body["failure_reason"] is None
    assert body["model_id"] == MODEL_ID

    assert len(context.queue.published) == 1
    message = context.queue.published[0]
    assert message.job_id == body["job_id"]
    assert message.object_key == object_key
    assert message.photo_id == "photo-one"
    assert message.attempt == 1

    assert [job["job_id"] for job in _listed_jobs(context)] == [body["job_id"]]


def test_requesting_the_same_photo_twice_returns_the_same_job(
    context: DetectionContext,
) -> None:
    _seed_listing(context.session_factory)
    _seed_photo(context.session_factory)

    first = context.client.post(_detections_url())
    second = context.client.post(_detections_url())

    assert first.status_code == 201, first.text
    assert second.status_code == 200, second.text
    assert second.json()["job_id"] == first.json()["job_id"]
    assert len(_listed_jobs(context)) == 1
    assert len(context.queue.published) == 1, "a replay must not publish again"


def test_publish_failure_reports_an_error_and_leaves_the_job_unqueued(
    context: DetectionContext,
) -> None:
    """A queue that refuses the message must not hide the job, nor fake a queue."""
    _seed_listing(context.session_factory)
    _seed_photo(context.session_factory)
    context.queue.fail_on_publish = True

    response = context.client.post(_detections_url())

    assert response.status_code == 503, response.text
    listed = _listed_jobs(context)
    assert len(listed) == 1, "the job is persisted so it can be republished"
    assert listed[0]["status"] == "pending"
    assert context.queue.published == []


def test_a_repeated_request_republishes_an_unqueued_job(context: DetectionContext) -> None:
    """The cheap half of the reconciliation for the persist/publish window."""
    _seed_listing(context.session_factory)
    _seed_photo(context.session_factory)
    context.queue.fail_on_publish = True
    failed = context.client.post(_detections_url())
    assert failed.status_code == 503
    # The app sanitizes 5xx bodies, so the job is identified through the API.
    job_id = _listed_jobs(context)[0]["job_id"]

    context.queue.fail_on_publish = False
    retried = context.client.post(_detections_url())

    assert retried.status_code == 200, retried.text
    assert retried.json()["job_id"] == job_id
    assert len(_listed_jobs(context)) == 1
    assert len(context.queue.published) == 1
    assert context.queue.published[0].job_id == job_id


def test_another_agency_cannot_request_detection(context: DetectionContext) -> None:
    _seed_listing(context.session_factory)
    _seed_photo(context.session_factory)

    response = context.client.post(_detections_url(agency_id="agency-two"))

    assert response.status_code == 403, response.text
    assert _listed_jobs(context) == []
    assert context.queue.published == []


def test_unknown_photo_is_not_found_and_creates_nothing(context: DetectionContext) -> None:
    _seed_listing(context.session_factory)

    response = context.client.post(_detections_url(photo_id="photo-missing"))

    assert response.status_code == 404, response.text
    assert _listed_jobs(context) == []
    assert context.queue.published == []


def test_unconfirmed_photo_is_refused(context: DetectionContext) -> None:
    _seed_listing(context.session_factory)
    _seed_photo(context.session_factory, status="pending")

    response = context.client.post(_detections_url())

    assert response.status_code == 409, response.text
    assert _listed_jobs(context) == []
    assert context.queue.published == []


def test_staff_can_list_the_jobs_of_a_listing(context: DetectionContext) -> None:
    _seed_listing(context.session_factory)
    _seed_photo(context.session_factory)
    created = context.client.post(_detections_url()).json()

    listed = _listed_jobs(context)

    assert len(listed) == 1
    assert listed[0]["job_id"] == created["job_id"]
    assert listed[0]["status"] == "pending"
    assert listed[0]["photo_id"] == "photo-one"
    assert listed[0]["created_at"] is not None


def test_without_a_staff_session_the_request_is_unauthorized(
    anonymous_context: DetectionContext,
) -> None:
    _seed_listing(anonymous_context.session_factory)
    _seed_photo(anonymous_context.session_factory)

    response = anonymous_context.client.post(_detections_url())

    assert response.status_code == 401, response.text
    assert anonymous_context.queue.published == []


def test_the_default_job_queue_is_built_when_none_is_injected() -> None:
    """Without this, every app-creating test in the suite would break at once.

    The unit tests always inject the queue, so the default factory needs its own
    coverage: a missing setting once broke `create_app` for the whole project.
    """
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    try:
        app = create_app(
            settings=_settings(), session_factory=factory, photo_storage=InMemoryPhotoStorage()
        )
        assert isinstance(app.state.job_queue, SqsJobQueue)
    finally:
        engine.dispose()


def test_a_lease_shorter_than_the_visibility_timeout_is_rejected() -> None:
    """A job must not look abandoned while a healthy worker may still be working.

    Regression test for a rule shipped in the same unit, so no RED was observed.
    """
    with pytest.raises(ValueError, match="lease"):
        _settings(
            detection_lease_seconds=30, detection_visibility_timeout_seconds=60
        ).validate()
