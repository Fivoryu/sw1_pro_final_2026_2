"""Expired detection leases are recovered by the API's single-writer path."""

from __future__ import annotations

import asyncio
import base64
from collections.abc import Iterator
from contextlib import suppress
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

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
from app.modules.detection.job_queue import InMemoryJobQueue
from app.modules.detection.models import DetectionJob, dedupe_key_for
from app.modules.detection.service import run_detection_recovery_sweep
from app.modules.identity.session import get_active_staff

_NOW = datetime(2026, 10, 14, 21, 0, tzinfo=UTC)
_MODEL_ID = "ssdlite320-mobilenetv3-coco-v1"
_JOB_ID = "expired-detection-job"
_MAX_ATTEMPTS = 3


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
