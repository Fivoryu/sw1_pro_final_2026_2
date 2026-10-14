"""Contract tests for detection jobs (F08.4).

The job state machine has a single writer — the API — and these constraints are
the last line of defence: only four states exist, and one photo can have only
one job per model version no matter what the queue delivers twice.
"""

from __future__ import annotations

import importlib.util
from collections.abc import Iterator
from datetime import UTC, datetime
from pathlib import Path

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, inspect
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.modules.detection.models import (
    DETECTION_JOB_STATES,
    DetectionJob,
    dedupe_key_for,
)

BACKEND_DIR = Path(__file__).resolve().parents[1]
MIGRATION_PATH = BACKEND_DIR / "alembic" / "versions" / "0019_detection_jobs.py"
CLAIM_TOKEN_MIGRATION_PATH = (
    BACKEND_DIR / "alembic" / "versions" / "0020_detection_job_claim_token.py"
)
_NOW = datetime(2026, 10, 14, 15, 0, tzinfo=UTC)


@pytest.fixture
def session() -> Iterator[Session]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    with factory() as active:
        yield active
    engine.dispose()


def _job(*, photo_id: str = "photo-one", model_id: str = "model-v1", status: str = "pending") -> DetectionJob:
    return DetectionJob(
        agency_id="agency-one",
        listing_id="listing-one",
        photo_id=photo_id,
        object_key=f"agencies/agency-one/listings/listing-one/photos/{photo_id}",
        model_id=model_id,
        dedupe_key=dedupe_key_for(photo_id, model_id),
        status=status,
        created_at=_NOW,
    )


def test_dedupe_key_is_built_from_photo_and_model() -> None:
    assert dedupe_key_for("photo-one", "model-v1") == "photo-one:model-v1"
    assert dedupe_key_for("photo-one", "model-v1") != dedupe_key_for("photo-one", "model-v2")


def test_states_are_exactly_the_four_declared() -> None:
    assert DETECTION_JOB_STATES == ("pending", "running", "completed", "failed")


def test_only_the_four_states_are_accepted(session: Session) -> None:
    for state in DETECTION_JOB_STATES:
        session.add(_job(photo_id=f"photo-{state}", status=state))
    session.commit()

    session.add(_job(photo_id="photo-invalid", status="unknown"))
    with pytest.raises(IntegrityError):
        session.commit()


def test_a_second_job_for_the_same_photo_and_model_is_rejected(session: Session) -> None:
    session.add(_job())
    session.commit()

    session.add(_job())
    with pytest.raises(IntegrityError):
        session.commit()


def test_a_second_job_for_another_model_version_is_allowed(session: Session) -> None:
    session.add(_job(model_id="model-v1"))
    session.add(_job(model_id="model-v2"))
    session.commit()

    assert session.query(DetectionJob).count() == 2


def test_new_job_defaults_to_pending_with_no_attempts(session: Session) -> None:
    job = _job()
    session.add(job)
    session.commit()

    stored = session.get(DetectionJob, job.id)
    assert stored is not None
    assert stored.status == "pending"
    assert stored.attempts == 0
    assert stored.result is None
    assert stored.started_at is None
    assert stored.finished_at is None
    assert stored.lease_expires_at is None


def test_claim_token_migration_adds_and_drops_the_fencing_column() -> None:
    spec = importlib.util.spec_from_file_location(
        "detection_job_claim_token_migration", CLAIM_TOKEN_MIGRATION_PATH
    )
    assert spec is not None and spec.loader is not None
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)

    base_spec = importlib.util.spec_from_file_location(
        "detection_jobs_migration_for_claim_token", MIGRATION_PATH
    )
    assert base_spec is not None and base_spec.loader is not None
    base_migration = importlib.util.module_from_spec(base_spec)
    base_spec.loader.exec_module(base_migration)

    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    try:
        with engine.begin() as connection:
            with Operations.context(MigrationContext.configure(connection)):
                base_migration.upgrade()
                migration.upgrade()
            columns = {
                column["name"]
                for column in inspect(connection).get_columns("detection_job")
            }
            assert "claim_token" in columns

        with engine.begin() as connection:
            with Operations.context(MigrationContext.configure(connection)):
                migration.downgrade()
            columns = {
                column["name"]
                for column in inspect(connection).get_columns("detection_job")
            }
            assert "claim_token" not in columns
    finally:
        engine.dispose()


def test_migration_creates_and_drops_the_detection_job_table() -> None:
    spec = importlib.util.spec_from_file_location("detection_jobs_migration", MIGRATION_PATH)
    assert spec is not None and spec.loader is not None
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)

    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    try:
        with engine.begin() as connection:
            with Operations.context(MigrationContext.configure(connection)):
                migration.upgrade()
            columns = {column["name"] for column in inspect(connection).get_columns("detection_job")}
            assert {
                "id",
                "agency_id",
                "listing_id",
                "photo_id",
                "object_key",
                "model_id",
                "dedupe_key",
                "status",
                "attempts",
                "lease_expires_at",
                "result",
                "failure_reason",
                "created_at",
                "enqueued_at",
                "started_at",
                "finished_at",
            } <= columns

        with engine.begin() as connection:
            with Operations.context(MigrationContext.configure(connection)):
                migration.downgrade()
            assert "detection_job" not in inspect(connection).get_table_names()
    finally:
        engine.dispose()
