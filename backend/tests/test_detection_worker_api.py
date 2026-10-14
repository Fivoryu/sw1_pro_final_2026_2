"""HTTP contract tests for the service-authenticated detection worker routes."""

from __future__ import annotations

import base64
from collections.abc import Iterator
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import main as main_module
from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.modules.catalog.models import Listing, ListingExtra
from app.modules.catalog.photo_storage import InMemoryPhotoStorage
from app.modules.detection.job_queue import InMemoryJobQueue
from app.modules.detection.models import DetectionJob, dedupe_key_for
from app.modules.identity.models import Agency

_NOW = datetime(2026, 10, 14, 20, 0, tzinfo=UTC)
_JOB_ID = "detection-job-one"
_TOKEN = "test-worker-service-token"
_KEY = "agencies/agency-one/listings/listing-one/photos/photo-one"
_MODEL_ID = "ssdlite320-mobilenetv3-coco-v1"


def _settings(**changes: object) -> Settings:
    values: dict[str, object] = {
        "database_url": "sqlite+pysqlite:///:memory:",
        "jwt_secret": "detection-worker-test-secret-that-is-long-enough",
        "totp_encryption_key": base64.urlsafe_b64encode(b"0" * 32).decode(),
        "web_origin": "http://localhost",
        "detection_worker_token": _TOKEN,
    }
    values.update(changes)
    return Settings(**values)  # type: ignore[arg-type]


class WorkerContext:
    def __init__(self, *, token: str | None = _TOKEN) -> None:
        self.engine = create_engine(
            "sqlite+pysqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        self.session_factory = sessionmaker(
            bind=self.engine, autoflush=False, expire_on_commit=False
        )
        Base.metadata.create_all(self.engine)
        self.storage = InMemoryPhotoStorage("https://storage.example.test")
        self.queue = InMemoryJobQueue()
        self.app = create_app(
            settings=_settings(detection_worker_token=token),
            session_factory=self.session_factory,
            clock=lambda: _NOW,
            photo_storage=self.storage,
            job_queue=self.queue,
        )
        self.client = TestClient(self.app)
        with self.session_factory.begin() as session:
            session.add(
                DetectionJob(
                    id=_JOB_ID,
                    agency_id="agency-one",
                    listing_id="listing-one",
                    photo_id="photo-one",
                    object_key=_KEY,
                    model_id=_MODEL_ID,
                    dedupe_key=dedupe_key_for("photo-one", _MODEL_ID),
                    status="pending",
                    attempts=0,
                    created_at=_NOW,
                )
            )

    def close(self) -> None:
        self.client.close()
        self.engine.dispose()


@pytest.fixture
def context() -> Iterator[WorkerContext]:
    opened = WorkerContext()
    yield opened
    opened.close()


def _url(action: str) -> str:
    return f"/api/v1/detection/jobs/{_JOB_ID}/{action}"


def _headers(token: str = _TOKEN) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_worker_token_is_required_and_missing_configuration_fails_closed() -> None:
    unopened = WorkerContext(token=None)
    try:
        response = unopened.client.post(_url("claim"))
    finally:
        unopened.close()

    assert response.status_code == 503, response.text


def test_invalid_worker_token_is_rejected_without_claiming(context: WorkerContext) -> None:
    response = context.client.post(_url("claim"), headers=_headers("wrong-token"))

    assert response.status_code == 401, response.text
    with context.session_factory() as session:
        job = session.get(DetectionJob, _JOB_ID)
        assert job is not None and job.status == "pending"


def test_claim_sets_running_lease_and_returns_the_authorized_download_url(
    context: WorkerContext,
) -> None:
    response = context.client.post(_url("claim"), headers=_headers())

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["job_id"] == _JOB_ID
    assert body["photo_id"] == "photo-one"
    assert body["object_key"] == _KEY
    assert body["model_id"] == _MODEL_ID
    assert body["status"] == "running"
    assert body["download_url"] == context.storage.presign_download(_KEY, expires_in=300)
    with context.session_factory() as session:
        job = session.get(DetectionJob, _JOB_ID)
        assert job is not None
        assert job.status == "running"
        assert job.lease_expires_at is not None
        assert job.attempts == 0


def test_reclaiming_a_completed_job_does_not_issue_an_image_url(context: WorkerContext) -> None:
    claimed = context.client.post(_url("claim"), headers=_headers())
    assert claimed.status_code == 200, claimed.text
    result = {"model_id": _MODEL_ID, "detections": []}
    completed = context.client.post(_url("complete"), headers=_headers(), json=result)
    assert completed.status_code == 200, completed.text

    repeated = context.client.post(_url("claim"), headers=_headers())

    assert repeated.status_code == 200, repeated.text
    assert repeated.json()["status"] == "completed"
    assert repeated.json()["download_url"] is None


def test_complete_persists_detections_and_is_idempotent(context: WorkerContext) -> None:
    claimed = context.client.post(_url("claim"), headers=_headers())
    assert claimed.status_code == 200, claimed.text
    first_result = {
        "model_id": _MODEL_ID,
        "detections": [
            {"label": "chair", "score": 0.83, "box": [1.0, 2.0, 30.0, 40.0]}
        ],
    }
    completed = context.client.post(_url("complete"), headers=_headers(), json=first_result)
    replay = context.client.post(
        _url("complete"),
        headers=_headers(),
        json={"model_id": _MODEL_ID, "detections": []},
    )

    assert completed.status_code == 200, completed.text
    assert replay.status_code == 200, replay.text
    assert completed.json()["status"] == "completed"
    assert replay.json()["result"] == first_result
    with context.session_factory() as session:
        job = session.get(DetectionJob, _JOB_ID)
        assert job is not None
        assert job.result == first_result
        assert job.finished_at is not None
        assert job.finished_at.replace(tzinfo=UTC) == _NOW


def test_fail_counts_attempts_republishes_then_stops_at_the_limit() -> None:
    limited = WorkerContext()
    limited.app.state.settings = _settings(
        detection_worker_token=_TOKEN, detection_max_attempts=2
    )
    try:
        first_claim = limited.client.post(_url("claim"), headers=_headers())
        assert first_claim.status_code == 200, first_claim.text
        first_fail = limited.client.post(
            _url("fail"), headers=_headers(), json={"reason": "temporary detector error"}
        )
        assert first_fail.status_code == 200, first_fail.text
        assert first_fail.json()["status"] == "pending"
        assert first_fail.json()["attempts"] == 1
        assert len(limited.queue.published) == 1

        second_claim = limited.client.post(_url("claim"), headers=_headers())
        assert second_claim.status_code == 200, second_claim.text
        second_fail = limited.client.post(
            _url("fail"), headers=_headers(), json={"reason": "image is unreadable"}
        )

        assert second_fail.status_code == 200, second_fail.text
        assert second_fail.json()["status"] == "failed"
        assert second_fail.json()["attempts"] == 2
        assert second_fail.json()["failure_reason"] == "image is unreadable"
        assert len(limited.queue.published) == 1
    finally:
        limited.close()


def test_permanent_failure_stops_at_the_exact_attempt_cap_and_stays_failed() -> None:
    limited = WorkerContext()
    limited.app.state.settings = _settings(
        detection_worker_token=_TOKEN, detection_max_attempts=3
    )
    try:
        failure_reason = "The referenced image is permanently unavailable"
        for attempt in range(1, 4):
            claimed = limited.client.post(_url("claim"), headers=_headers())
            assert claimed.status_code == 200, claimed.text
            assert claimed.json()["status"] == "running"

            failed = limited.client.post(
                _url("fail"), headers=_headers(), json={"reason": failure_reason}
            )
            assert failed.status_code == 200, failed.text
            expected_status = "failed" if attempt == 3 else "pending"
            assert failed.json()["status"] == expected_status
            assert failed.json()["attempts"] == attempt

        assert failed.json()["failure_reason"] == failure_reason
        assert [message.attempt for message in limited.queue.published] == [2, 3]

        later_claim = limited.client.post(_url("claim"), headers=_headers())
        later_failure = limited.client.post(
            _url("fail"), headers=_headers(), json={"reason": "must not replace the reason"}
        )

        assert later_claim.status_code == 200, later_claim.text
        assert later_claim.json()["status"] == "failed"
        assert later_claim.json()["attempts"] == 3
        assert later_failure.status_code == 200, later_failure.text
        assert later_failure.json()["status"] == "failed"
        assert later_failure.json()["attempts"] == 3
        assert later_failure.json()["failure_reason"] == failure_reason
        assert [message.attempt for message in limited.queue.published] == [2, 3]
    finally:
        limited.close()


def test_worker_routes_never_echo_or_log_the_service_token(
    context: WorkerContext, caplog: pytest.LogCaptureFixture
) -> None:
    response = context.client.post(_url("claim"), headers=_headers("never-log-this-token"))

    assert response.status_code == 401
    assert "never-log-this-token" not in caplog.text


def test_worker_download_signatures_use_the_local_service_endpoint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    observed: list[Settings] = []
    sentinel = object()

    def fake_create_photo_storage(settings: Settings) -> object:
        observed.append(settings)
        return sentinel

    monkeypatch.setattr(main_module, "create_photo_storage", fake_create_photo_storage)
    settings = _settings(
        s3_bucket_name="roomforge-local-assets",
        s3_endpoint_url="http://floci:4566",
        s3_public_endpoint_url="http://127.0.0.1:4566",
    )

    storage = main_module._create_worker_photo_storage(settings, injected_storage=None)

    assert storage is sentinel
    assert observed[0].s3_public_endpoint_url == "http://floci:4566"

    remote = _settings(
        s3_bucket_name="assets",
        s3_endpoint_url="https://s3.us-east-1.amazonaws.com",
    )
    assert main_module._create_worker_photo_storage(remote, injected_storage=None) is None


def test_worker_result_does_not_write_commercial_inventory(context: WorkerContext) -> None:
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-one"))
        session.add(
            Listing(
                id="listing-one",
                agency_id="agency-one",
                approval_status="approved",
                is_published=True,
                operation="sale",
                base_price=Decimal("100000.00"),
                city="La Paz",
                city_key="la paz",
                zone="Sopocachi",
                zone_key="sopocachi",
                bedrooms=2,
                bathrooms=1,
            )
        )
        session.add(
            ListingExtra(
                id="extra-one",
                listing_id="listing-one",
                name="Chair",
                price=Decimal("100.00"),
                quantity=2,
            )
        )
    with context.session_factory() as session:
        before = [
            (extra.id, extra.name, extra.price, extra.quantity)
            for extra in session.query(ListingExtra).filter_by(listing_id="listing-one")
        ]

    claimed = context.client.post(_url("claim"), headers=_headers())
    assert claimed.status_code == 200, claimed.text
    completed = context.client.post(
        _url("complete"),
        headers=_headers(),
        json={
            "model_id": _MODEL_ID,
            "detections": [
                {"label": "chair", "score": 0.83, "box": [1.0, 2.0, 30.0, 40.0]}
            ],
        },
    )
    assert completed.status_code == 200, completed.text

    with context.session_factory() as session:
        after = [
            (extra.id, extra.name, extra.price, extra.quantity)
            for extra in session.query(ListingExtra).filter_by(listing_id="listing-one")
        ]
    assert after == before


def test_worker_complete_rejects_a_result_for_another_model(context: WorkerContext) -> None:
    claimed = context.client.post(_url("claim"), headers=_headers())
    assert claimed.status_code == 200, claimed.text

    response = context.client.post(
        _url("complete"),
        headers=_headers(),
        json={"model_id": "different-model", "detections": []},
    )

    assert response.status_code == 409, response.text
    with context.session_factory() as session:
        job = session.get(DetectionJob, _JOB_ID)
        assert job is not None and job.status == "running" and job.result is None


def test_failure_body_is_bounded_by_the_published_schema(context: WorkerContext) -> None:
    claimed = context.client.post(_url("claim"), headers=_headers())
    assert claimed.status_code == 200, claimed.text
    bad_body: dict[str, Any] = {"reason": "x" * 256}

    response = context.client.post(_url("fail"), headers=_headers(), json=bad_body)

    assert response.status_code == 422
