"""Expired detection leases are recovered by the API's single-writer path."""

from __future__ import annotations

import asyncio
import base64
import importlib.util
import sys
from collections.abc import Iterator
from contextlib import suppress
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.modules.catalog.photo_storage import InMemoryPhotoStorage
from app.main import _detection_recovery_loop
from app.main import create_app
from app.modules.detection.job_queue import InMemoryJobQueue, JobMessage
from app.modules.detection.models import DetectionJob, dedupe_key_for
from app.modules.detection.service import run_detection_recovery_sweep
from app.modules.identity.session import get_active_staff

_NOW = datetime(2026, 10, 14, 21, 0, tzinfo=UTC)
_MODEL_ID = "ssdlite320-mobilenetv3-coco-v1"
_JOB_ID = "expired-detection-job"
_MAX_ATTEMPTS = 3
_LEASE_SECONDS = 300


def _settings(**changes: object) -> Settings:
    values: dict[str, object] = {
        "database_url": "sqlite+pysqlite:///:memory:",
        "jwt_secret": "detection-recovery-test-secret-long-enough",
        "totp_encryption_key": base64.urlsafe_b64encode(b"r" * 32).decode(),
        "web_origin": "http://localhost",
        "detection_worker_token": "test-worker-token",
        "detection_max_attempts": _MAX_ATTEMPTS,
    }
    values.update(changes)
    return Settings(**values)  # type: ignore[arg-type]


@dataclass
class RecoveryContext:
    app: FastAPI
    client: TestClient
    session_factory: sessionmaker[Session]
    queue: InMemoryJobQueue
    engine: object

    def close(self) -> None:
        self.client.close()
        self.engine.dispose()  # type: ignore[attr-defined]


@pytest.fixture

def context() -> Iterator[RecoveryContext]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    Base.metadata.create_all(engine)
    queue = InMemoryJobQueue()
    app = create_app(
        settings=_settings(),
        session_factory=factory,
        clock=lambda: _NOW,
        photo_storage=InMemoryPhotoStorage(),
        job_queue=queue,
    )
    app.dependency_overrides[get_active_staff] = lambda: {
        "id": "recovery-actor",
        "email": "recovery-actor@example.test",
        "role": "agent",
        "tenant_id": "agency-one",
    }
    client = TestClient(app)
    with client:
        yield RecoveryContext(app, client, factory, queue, engine)
    engine.dispose()


def _seed_expired_job(context: RecoveryContext, *, attempts: int) -> None:
    with context.session_factory.begin() as session:
        session.add(
            DetectionJob(
                id=_JOB_ID,
                agency_id="agency-one",
                listing_id="listing-one",
                photo_id="photo-one",
                object_key="agencies/agency-one/listings/listing-one/photos/photo-one",
                model_id=_MODEL_ID,
                dedupe_key=dedupe_key_for("photo-one", _MODEL_ID),
                status="running",
                attempts=attempts,
                lease_expires_at=_NOW - timedelta(seconds=1),
                created_at=_NOW - timedelta(minutes=10),
                enqueued_at=_NOW - timedelta(minutes=5),
                started_at=_NOW - timedelta(minutes=5),
            )
        )


def _listed_jobs(context: RecoveryContext) -> list[dict[str, object]]:
    response = context.client.get(
        "/api/v1/staff/agencies/agency-one/listings/listing-one/detections"
    )
    assert response.status_code == 200, response.text
    return list(response.json()["jobs"])


@pytest.mark.parametrize(
    ("attempts", "expected_status", "expected_attempts", "expected_messages"),
    [
        (0, "pending", 1, 1),
        (_MAX_ATTEMPTS - 1, "failed", _MAX_ATTEMPTS, 0),
        (_MAX_ATTEMPTS, "failed", _MAX_ATTEMPTS, 0),
    ],
)
def test_expired_lease_consumes_an_attempt_and_fails_at_the_cap(
    context: RecoveryContext,
    attempts: int,
    expected_status: str,
    expected_attempts: int,
    expected_messages: int,
) -> None:
    _seed_expired_job(context, attempts=attempts)
    before = _listed_jobs(context)
    assert before[0]["status"] == "running"

    recovered = run_detection_recovery_sweep(
        context.session_factory,
        context.queue,
        now=_NOW,
        max_attempts=_MAX_ATTEMPTS,
    )

    after = _listed_jobs(context)
    assert recovered == 1
    assert after[0]["status"] == expected_status
    assert after[0]["attempts"] == expected_attempts
    assert len(context.queue.published) == expected_messages
    if expected_status == "pending":
        assert after[0]["failure_reason"] is None
        assert context.queue.published[0].job_id == _JOB_ID
        assert context.queue.published[0].attempt == expected_attempts + 1
    else:
        reason = after[0]["failure_reason"]
        assert isinstance(reason, str) and "lease" in reason.lower()
        assert context.queue.published == []



def test_claim_failures_beyond_receive_cap_drop_delivery_and_recover_job(
    context: RecoveryContext,
) -> None:
    worker_path = Path(__file__).resolve().parents[2] / "worker3d" / "job_worker.py"
    spec = importlib.util.spec_from_file_location(
        "roomforge_detection_worker_recovery_test", worker_path
    )
    assert spec is not None and spec.loader is not None
    worker_module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = worker_module
    spec.loader.exec_module(worker_module)

    with context.session_factory.begin() as session:
        session.add(
            DetectionJob(
                id=_JOB_ID,
                agency_id="agency-one",
                listing_id="listing-one",
                photo_id="photo-one",
                object_key="agencies/agency-one/listings/listing-one/photos/photo-one",
                model_id=_MODEL_ID,
                dedupe_key=dedupe_key_for("photo-one", _MODEL_ID),
                status="pending",
                attempts=0,
                created_at=_NOW - timedelta(minutes=10),
                enqueued_at=_NOW - timedelta(minutes=10),
            )
        )

    message = JobMessage(
        version=1,
        job_id=_JOB_ID,
        photo_id="photo-one",
        object_key="agencies/agency-one/listings/listing-one/photos/photo-one",
        model_id=_MODEL_ID,
        attempt=1,
    )

    class RedeliveringQueue:
        def __init__(self) -> None:
            self.receive_count = 0
            self.deleted: list[object] = []

        def receive(self) -> list[object]:
            if self.deleted:
                return []
            self.receive_count += 1
            return [
                worker_module.QueueDelivery(
                    body=message.as_body(),
                    receipt_handle="receipt-claim-failure",
                    receive_count=self.receive_count,
                )
            ]

        def delete(self, delivery: object) -> None:
            self.deleted.append(delivery)

    class ApiHttpClient:
        def post(
            self,
            url: str,
            *,
            headers: dict[str, str],
            json: dict[str, object] | None = None,
        ) -> object:
            return context.client.post(
                url.replace("http://api:8000", ""), headers=headers, json=json
            )

        def get(self, url: str) -> object:
            return context.client.get(url.replace("http://api:8000", ""))

    delivery_queue = RedeliveringQueue()
    worker = worker_module.DetectionJobWorker(
        api_base_url="http://api:8000",
        service_token="wrong-worker-token",
        queue=delivery_queue,
        http_client=ApiHttpClient(),
        claim_failure_receive_cap=2,
    )

    with pytest.raises(RuntimeError):
        worker.run_once()
    with pytest.raises(RuntimeError):
        worker.run_once()
    assert worker.run_once() is True
    assert worker.run_once() is False
    assert delivery_queue.receive_count == 3
    assert len(delivery_queue.deleted) == 1

    with context.session_factory() as session:
        after_claim_errors = session.get(DetectionJob, _JOB_ID)
        assert after_claim_errors is not None
        assert after_claim_errors.status == "pending"
        assert after_claim_errors.attempts == 0
        assert after_claim_errors.claim_token is None
        assert after_claim_errors.enqueued_at is not None
        assert after_claim_errors.enqueued_at.replace(tzinfo=UTC) == _NOW - timedelta(minutes=10)

    recovered = run_detection_recovery_sweep(
        context.session_factory,
        context.queue,
        now=_NOW,
        max_attempts=_MAX_ATTEMPTS,
    )
    with context.session_factory() as session:
        after_sweep = session.get(DetectionJob, _JOB_ID)
        assert after_sweep is not None
        assert after_sweep.status == "pending"
        assert after_sweep.enqueued_at is not None
    assert recovered == 1
    assert [queued.attempt for queued in context.queue.published] == [1]


def test_pending_job_that_was_never_enqueued_is_republished(context: RecoveryContext) -> None:
    with context.session_factory.begin() as session:
        session.add(
            DetectionJob(
                id=_JOB_ID,
                agency_id="agency-one",
                listing_id="listing-one",
                photo_id="photo-one",
                object_key="agencies/agency-one/listings/listing-one/photos/photo-one",
                model_id=_MODEL_ID,
                dedupe_key=dedupe_key_for("photo-one", _MODEL_ID),
                status="pending",
                attempts=0,
                created_at=_NOW - timedelta(minutes=10),
                enqueued_at=None,
            )
        )

    before = _listed_jobs(context)
    recovered = run_detection_recovery_sweep(
        context.session_factory,
        context.queue,
        now=_NOW,
        max_attempts=_MAX_ATTEMPTS,
    )
    after = _listed_jobs(context)

    assert before[0]["status"] == "pending"
    assert recovered == 1
    assert after[0]["status"] == "pending"
    assert after[0]["attempts"] == 0
    assert [message.job_id for message in context.queue.published] == [_JOB_ID]
    assert [message.attempt for message in context.queue.published] == [1]


def test_pending_job_with_stale_enqueue_marker_is_republished(context: RecoveryContext) -> None:
    """A lost/deleted delivery must recover even after it was marked enqueued."""
    with context.session_factory.begin() as session:
        session.add(
            DetectionJob(
                id=_JOB_ID,
                agency_id="agency-one",
                listing_id="listing-one",
                photo_id="photo-one",
                object_key="agencies/agency-one/listings/listing-one/photos/photo-one",
                model_id=_MODEL_ID,
                dedupe_key=dedupe_key_for("photo-one", _MODEL_ID),
                status="pending",
                attempts=0,
                created_at=_NOW - timedelta(minutes=10),
                enqueued_at=_NOW - timedelta(seconds=_LEASE_SECONDS),
            )
        )

    recovered = run_detection_recovery_sweep(
        context.session_factory,
        context.queue,
        now=_NOW,
        max_attempts=_MAX_ATTEMPTS,
    )

    assert recovered == 1
    assert [message.job_id for message in context.queue.published] == [_JOB_ID]
    assert [message.attempt for message in context.queue.published] == [1]
    with context.session_factory() as session:
        job = session.get(DetectionJob, _JOB_ID)
        assert job is not None
        assert job.status == "pending"
        assert job.enqueued_at is not None
        assert job.enqueued_at.replace(tzinfo=UTC) != _NOW - timedelta(seconds=_LEASE_SECONDS)


def test_recent_enqueue_marker_is_not_republished_on_each_sweep(
    context: RecoveryContext,
) -> None:
    """A healthy queue/worker gets one lease interval before safety-net replay."""
    with context.session_factory.begin() as session:
        session.add(
            DetectionJob(
                id=_JOB_ID,
                agency_id="agency-one",
                listing_id="listing-one",
                photo_id="photo-one",
                object_key="agencies/agency-one/listings/listing-one/photos/photo-one",
                model_id=_MODEL_ID,
                dedupe_key=dedupe_key_for("photo-one", _MODEL_ID),
                status="pending",
                attempts=0,
                created_at=_NOW,
                enqueued_at=_NOW,
            )
        )

    for elapsed in (0, 60, 120):
        recovered = run_detection_recovery_sweep(
            context.session_factory,
            context.queue,
            now=_NOW + timedelta(seconds=elapsed),
            max_attempts=_MAX_ATTEMPTS,
        )
        assert recovered == 0
        assert context.queue.published == []


def test_running_job_with_active_lease_is_not_republished_by_repeated_sweeps(
    context: RecoveryContext,
) -> None:
    _seed_expired_job(context, attempts=0)
    with context.session_factory.begin() as session:
        job = session.get(DetectionJob, _JOB_ID)
        assert job is not None
        job.lease_expires_at = _NOW + timedelta(minutes=10)

    for elapsed in (0, 60, 120):
        recovered = run_detection_recovery_sweep(
            context.session_factory,
            context.queue,
            now=_NOW + timedelta(seconds=elapsed),
            max_attempts=_MAX_ATTEMPTS,
        )
        assert recovered == 0
        assert context.queue.published == []

    assert _listed_jobs(context)[0]["status"] == "running"


def test_repeated_worker_crashes_consume_the_retry_budget(context: RecoveryContext) -> None:
    _seed_expired_job(context, attempts=0)

    for crash_number in range(1, _MAX_ATTEMPTS + 1):
        recovered = run_detection_recovery_sweep(
            context.session_factory,
            context.queue,
            now=_NOW + timedelta(hours=crash_number),
            max_attempts=_MAX_ATTEMPTS,
        )
        job = _listed_jobs(context)[0]

        assert recovered == 1
        assert job["attempts"] == crash_number
        expected_status = "failed" if crash_number == _MAX_ATTEMPTS else "pending"
        assert job["status"] == expected_status
        assert [message.attempt for message in context.queue.published] == list(
            range(2, min(crash_number, _MAX_ATTEMPTS - 1) + 2)
        )

        if crash_number < _MAX_ATTEMPTS:
            claimed = context.client.post(
                f"/api/v1/detection/jobs/{_JOB_ID}/claim",
                headers={"Authorization": "Bearer test-worker-token"},
            )
            assert claimed.status_code == 200, claimed.text
            assert claimed.json()["status"] == "running"

    final_job = _listed_jobs(context)[0]
    assert final_job["status"] == "failed"
    assert final_job["attempts"] == _MAX_ATTEMPTS
    assert len(context.queue.published) == _MAX_ATTEMPTS - 1

    later = run_detection_recovery_sweep(
        context.session_factory,
        context.queue,
        now=_NOW + timedelta(days=1),
        max_attempts=_MAX_ATTEMPTS,
    )
    assert later == 0
    assert _listed_jobs(context)[0] == final_job
    assert len(context.queue.published) == _MAX_ATTEMPTS - 1


def test_sweep_publish_failure_is_logged_and_remains_recoverable(
    context: RecoveryContext, caplog: pytest.LogCaptureFixture
) -> None:
    _seed_expired_job(context, attempts=0)
    context.queue.fail_on_publish = True

    run_detection_recovery_sweep(
        context.session_factory,
        context.queue,
        now=_NOW,
        max_attempts=_MAX_ATTEMPTS,
    )

    job = _listed_jobs(context)[0]
    assert job["status"] == "pending"
    assert context.queue.published == []
    assert "Detection recovery sweep could not publish a job message" in caplog.text
    assert _JOB_ID not in caplog.text


def test_recovery_loop_repeats_after_an_error_and_can_be_cancelled(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app import main as main_module

    runs: list[int] = []

    def _run(*args: object, **kwargs: object) -> None:
        runs.append(1)
        if len(runs) == 1:
            raise RuntimeError("temporary database outage")

    monkeypatch.setattr(main_module, "_run_detection_recovery_sweep", _run)

    async def _drive() -> None:
        task = asyncio.create_task(
            _detection_recovery_loop(
                session_factory=None,  # type: ignore[arg-type]
                job_queue=None,  # type: ignore[arg-type]
                clock=lambda: _NOW,
                max_attempts=_MAX_ATTEMPTS,
                interval_seconds=0.01,
            )
        )
        # Bounded wait instead of a fixed window: each sweep runs in a thread, so
        # counting iterations inside a fixed sleep is a race against the clock.
        for _ in range(400):
            if len(runs) >= 3:
                break
            await asyncio.sleep(0.01)
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task

    asyncio.run(_drive())

    assert len(runs) >= 3, "the loop must keep sweeping after a failed sweep"
