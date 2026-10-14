"""Contract tests for the detection job API (F08.4).

Every acceptance rule is checked through the public interface: the HTTP route
and the job states the API reports back. The queue is a double and the database
is a throwaway SQLite file, so the whole suite runs without AWS or a network.

Where a rule says "nothing was created", the check reads the listing's job list
from the API instead of querying storage: the observable effect is what matters.
"""

from __future__ import annotations

import base64
import sys
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from threading import Event
from types import SimpleNamespace

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
from app.modules.detection.job_queue import InMemoryJobQueue, JobMessage, SqsJobQueue
from app.modules.detection.models import DetectionJob
from app.modules.identity.models import Agency
from app.modules.detection.service import run_detection_recovery_sweep
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


def test_concurrent_same_generation_enqueue_marker_is_successful(
    context: DetectionContext,
) -> None:
    _seed_listing(context.session_factory)
    _seed_photo(context.session_factory)

    class ConcurrentMarkerQueue:
        def __init__(self) -> None:
            self.published: list[JobMessage] = []

        def publish(self, message: JobMessage) -> None:
            self.published.append(message)
            with context.session_factory.begin() as session:
                job = session.get(DetectionJob, message.job_id)
                assert job is not None
                assert job.status == "pending" and job.attempts == 0
                job.enqueued_at = _NOW

    queue = ConcurrentMarkerQueue()
    context.app.state.job_queue = queue

    response = context.client.post(_detections_url())

    assert response.status_code == 201, response.text
    assert len(queue.published) == 1
    assert queue.published[0].job_id == response.json()["job_id"]
    with context.session_factory() as session:
        job = session.get(DetectionJob, response.json()["job_id"])
        assert job is not None
        assert job.status == "pending" and job.attempts == 0
        assert job.enqueued_at is not None
        assert job.enqueued_at.replace(tzinfo=UTC) == _NOW


def test_publisher_accepts_a_same_generation_job_claimed_during_publish(
    context: DetectionContext,
) -> None:
    _seed_listing(context.session_factory)
    _seed_photo(context.session_factory)
    context.app.state.settings = _settings(detection_worker_token="test-worker-token")

    class ClaimingQueue:
        def __init__(self) -> None:
            self.published: list[JobMessage] = []
            self.claimed: dict[str, object] | None = None

        def publish(self, message: JobMessage) -> None:
            self.published.append(message)
            response = context.client.post(
                f"/api/v1/detection/jobs/{message.job_id}/claim",
                headers={"Authorization": "Bearer test-worker-token"},
            )
            assert response.status_code == 200, response.text
            self.claimed = response.json()

    queue = ClaimingQueue()
    context.app.state.job_queue = queue

    response = context.client.post(_detections_url())

    assert response.status_code == 201, response.text
    assert len(queue.published) == 1
    assert queue.claimed is not None
    assert queue.claimed["status"] == "running"
    with context.session_factory() as session:
        job = session.get(DetectionJob, response.json()["job_id"])
        assert job is not None
        assert job.status == "running"
        assert job.attempts == 0
        assert job.enqueued_at is None


def test_stale_publisher_cannot_mark_a_later_attempt_enqueued(
    context: DetectionContext,
) -> None:
    _seed_listing(context.session_factory)
    _seed_photo(context.session_factory)
    started = Event()
    release = Event()

    class DelayedQueue:
        def __init__(self) -> None:
            self.publish_calls = 0
            self.published: list[JobMessage] = []
            self.received: list[JobMessage] = []

        def publish(self, message: JobMessage) -> None:
            self.publish_calls += 1
            if self.publish_calls == 1:
                self.published.append(message)
                started.set()
                if not release.wait(timeout=5):
                    raise TimeoutError("delayed publish was not released")
                return
            if self.publish_calls == 2:
                raise RuntimeError("retry publication failed")
            self.published.append(message)

        def receive(self) -> JobMessage | None:
            if not self.published:
                return None
            message = self.published.pop(0)
            self.received.append(message)
            return message

    queue = DelayedQueue()
    context.app.state.job_queue = queue
    context.app.state.settings = _settings(detection_worker_token="test-worker-token")
    with ThreadPoolExecutor(max_workers=1) as executor:
        first_request = executor.submit(context.client.post, _detections_url())
        try:
            assert started.wait(timeout=5), "the first publish must reach the delayed queue"
            first_message = queue.receive()
            assert first_message is not None and first_message.attempt == 1

            claim = context.client.post(
                f"/api/v1/detection/jobs/{first_message.job_id}/claim",
                headers={"Authorization": "Bearer test-worker-token"},
            )
            assert claim.status_code == 200, claim.text
            failed = context.client.post(
                f"/api/v1/detection/jobs/{first_message.job_id}/fail",
                headers={"Authorization": "Bearer test-worker-token"},
                json={"claim_token": claim.json()["claim_token"], "reason": "transient"},
            )
            assert failed.status_code == 503, failed.text
            before_sweep = _listed_jobs(context)[0]
            assert before_sweep["status"] == "pending"
            assert before_sweep["attempts"] == 1
        finally:
            release.set()
        stale_response = first_request.result(timeout=5)

    run_detection_recovery_sweep(
        context.session_factory, queue, now=_NOW + timedelta(seconds=1), max_attempts=3
    )
    recovered = _listed_jobs(context)[0]
    retry_message = queue.receive()

    assert recovered["status"] == "pending"
    assert recovered["attempts"] == 1
    assert retry_message is not None and retry_message.attempt == 2
    assert stale_response.status_code == 503, stale_response.text
    assert [message.attempt for message in queue.received] == [1, 2]


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


def test_job_is_committed_before_the_queue_receives_it(tmp_path: Path) -> None:
    """A queue consumer must never race ahead of the job transaction."""
    database = tmp_path / "detection-commit-order.db"
    engine = create_engine(
        f"sqlite+pysqlite:///{database}", connect_args={"check_same_thread": False}
    )
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    Base.metadata.create_all(engine)

    class CommitObservingQueue(InMemoryJobQueue):
        job_visible_at_publish = False

        def publish(self, message: JobMessage) -> None:
            with factory() as independent_session:
                self.job_visible_at_publish = (
                    independent_session.get(DetectionJob, message.job_id) is not None
                )
            super().publish(message)

    queue = CommitObservingQueue()
    app = create_app(
        settings=_settings(),
        session_factory=factory,
        clock=lambda: _NOW,
        photo_storage=InMemoryPhotoStorage(),
        job_queue=queue,
    )
    app.dependency_overrides[get_active_staff] = lambda: {
        "id": "detection-actor",
        "email": "detection-actor@example.test",
        "role": "agent",
        "tenant_id": "agency-one",
    }
    try:
        with TestClient(app) as client:
            _seed_listing(factory)
            _seed_photo(factory)

            response = client.post(_detections_url())
            listed = client.get(_jobs_url())

            assert response.status_code == 201, response.text
            assert listed.status_code == 200, listed.text
            assert [job["job_id"] for job in listed.json()["jobs"]] == [
                response.json()["job_id"]
            ]
            assert queue.job_visible_at_publish is True
            assert [message.job_id for message in queue.published] == [
                response.json()["job_id"]
            ]
    finally:
        engine.dispose()


@pytest.mark.parametrize("endpoint_url", [None, "https://sqs.us-east-1.amazonaws.com"])
def test_producer_refuses_missing_or_remote_sqs_endpoints(
    context: DetectionContext,
    monkeypatch: pytest.MonkeyPatch,
    endpoint_url: str | None,
) -> None:
    _seed_listing(context.session_factory)
    _seed_photo(context.session_factory)
    boto_calls: list[object] = []

    def forbidden_resource(*args: object, **kwargs: object) -> object:
        boto_calls.append((args, kwargs))
        raise AssertionError("boto3 must not be called for a non-local endpoint")

    monkeypatch.setitem(sys.modules, "boto3", SimpleNamespace(resource=forbidden_resource))
    context.app.state.job_queue = SqsJobQueue(
        queue_name="roomforge-local-detection",
        endpoint_url=endpoint_url,
        region="us-east-1",
    )

    response = context.client.post(_detections_url())
    listed = _listed_jobs(context)

    assert response.status_code == 503, response.text
    assert len(listed) == 1 and listed[0]["status"] == "pending"
    assert context.queue.published == []
    assert boto_calls == []
