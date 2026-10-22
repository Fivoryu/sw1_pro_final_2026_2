"""Real migration and concurrent HTTP decisions on a guarded disposable database."""
from __future__ import annotations

import os
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

import pytest
from alembic import command as alembic_command
from alembic.config import Config
from alembic.script import ScriptDirectory
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, inspect
from sqlalchemy.engine import make_url
from sqlalchemy.orm import sessionmaker

from app.main import create_app
from test_f04_publications import F04Context
from test_furniture_review import command, seed_review, view
from test_detection_jobs_api import _settings  # pyright: ignore[reportPrivateUsage]


@pytest.fixture(scope="module")
def postgres_context() -> Iterator[F04Context]:
    value = os.environ.get("ROOMFORGE_F08_DATABASE_URL")
    if not value:
        pytest.skip("ROOMFORGE_F08_DATABASE_URL is unset")
    url = make_url(value)
    if (url.drivername != "postgresql+psycopg" or url.host not in {"127.0.0.1", "localhost"}
            or not url.port or not url.database or not url.database.startswith("roomforge_f08_")):
        pytest.fail("F08 requires a new loopback PostgreSQL database prefixed roomforge_f08_")
    engine = create_engine(url, pool_pre_ping=True)
    try:
        assert inspect(engine).get_table_names() == [], "F08 never migrates a nonempty database"
        backend = Path(__file__).parents[1]
        config = Config(str(backend / "alembic.ini"))
        config.set_main_option("script_location", str(backend / "alembic"))
        scripts = ScriptDirectory.from_config(config)
        heads = scripts.get_heads()
        assert len(heads) == 1, f"the migration chain must have one head, got {heads}"
        # Later phases chain onto F08; the furniture review revision must stay in the history.
        assert "0023_furniture_review" in {rev.revision for rev in scripts.walk_revisions()}
        with patch.dict(os.environ, {"DATABASE_URL": value}):
            alembic_command.upgrade(config, "head")
        assert "furniture_review" in inspect(engine).get_table_names()
        factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
        app = create_app(settings=_settings(), session_factory=factory)
        with TestClient(app) as client:
            yield F04Context(client, app, factory)
    finally:
        engine.dispose()


def test_concurrent_identical_confirmation_creates_one_inventory_object(postgres_context: F04Context) -> None:
    context, path, jobs = seed_review(postgres_context)
    initial = view(context, path)
    original_scene = context.client.get(path + "/scene").json()
    original_jobs = context.client.get(path + "/detections").json()
    body = command(context, path, action="confirmed", job_id=jobs[0], detection_index=0)
    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(
            lambda _: context.client.post(path + "/furniture-review", json={**body, "request_id": str(uuid4())}),
            range(8),
        ))
    assert [response.status_code for response in responses] == [200] * 8
    after = view(context, path)
    assert len(after["history"]) == 1 and len(after["listing"]["extras"]) == 1
    assert after["listing"]["offer_version"] == initial["listing"]["offer_version"] + 1
    extra_id = after["listing"]["extras"][0]["extra_id"]
    objects = context.client.get(path + "/scene").json()["objects"]
    assert len(objects) == len(original_scene["objects"]) + 1
    assert sum(obj["id"] == extra_id for obj in objects) == 1
    assert context.client.get(path + "/detections").json() == original_jobs


def test_racing_confirm_and_reject_never_publish_or_leave_partial_data(postgres_context: F04Context) -> None:
    context, path, jobs = seed_review(postgres_context)
    initial = view(context, path)
    original_scene = context.client.get(path + "/scene").json()
    confirm = command(context, path, action="confirmed", job_id=jobs[0], detection_index=0)
    reject = command(context, path, action="rejected", job_id=jobs[0], detection_index=0, item=None)
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(
            lambda body: context.client.post(path + "/furniture-review", json=body),
            [confirm, reject],
        ))
    assert sorted(response.status_code for response in responses) == [200, 409]
    after = view(context, path)
    assert len(after["history"]) == 1 and after["listing"]["is_published"] is False
    confirmed = int(after["history"][0]["action"] == "confirmed")
    assert len(after["listing"]["extras"]) == confirmed
    assert after["listing"]["offer_version"] == initial["listing"]["offer_version"] + confirmed
    assert len(context.client.get(path + "/scene").json()["objects"]) == len(original_scene["objects"]) + confirmed
