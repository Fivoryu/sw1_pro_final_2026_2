from __future__ import annotations

import base64
import ipaddress
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from threading import Barrier
from typing import Iterator
from unittest.mock import patch
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory
from fastapi.testclient import TestClient
from sqlalchemy import Engine, create_engine, inspect, text
from sqlalchemy.engine import URL, make_url
from sqlalchemy.orm import sessionmaker

from app.core.config import Settings
from app.core.security import encrypt_totp_secret, hash_password, hash_secret
from app.db.base import Base
from app.main import create_app
from app.modules.identity.models import StaffAccount, StaffLoginChallenge, StaffRecoveryCode, StaffSession

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_R6_DATABASE_PREFIX = "roomforge_r6_"
_R6_ENGINE_INFO_KEY = "roomforge.r6.isolated_engine"


def _validated_r6_url() -> URL:
    raw_url = os.environ.get("ROOMFORGE_R6_DATABASE_URL")
    if not raw_url:
        pytest.skip("ROOMFORGE_R6_DATABASE_URL is unset")
    try:
        url = make_url(raw_url)
    except Exception:
        pytest.fail("ROOMFORGE_R6_DATABASE_URL is not a valid SQLAlchemy URL")

    host = url.host
    try:
        is_loopback = host is not None and ipaddress.ip_address(host).is_loopback
    except ValueError:
        is_loopback = host == "localhost"
    if url.drivername != "postgresql+psycopg" or not is_loopback or url.port is None:
        pytest.fail("R6 tests require postgresql+psycopg on an explicit loopback host and port")
    if not url.database or not url.database.startswith(_R6_DATABASE_PREFIX):
        pytest.fail(f"R6 tests require a fresh database named with prefix {_R6_DATABASE_PREFIX!r}")
    return url


def _prepare_r6_database(url: URL) -> Engine:
    engine = create_engine(url, pool_size=4, max_overflow=0, pool_pre_ping=True)
    try:
        table_names = set(inspect(engine).get_table_names())
        if table_names:
            pytest.fail("PostgreSQL concurrency tests require a fresh, completely blank R6 database")
        config = Config(str(_BACKEND_ROOT / "alembic.ini"))
        config.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
        connection_url = url.render_as_string(hide_password=False)
        config.set_main_option("sqlalchemy.url", connection_url.replace("%", "%%"))
        script = ScriptDirectory.from_config(config)
        expected_head = script.get_current_head()
        with patch.dict(os.environ, {"DATABASE_URL": connection_url}):
            command.upgrade(config, "head")
        with engine.connect() as connection:
            revision = connection.execute(
                text("SELECT version_num FROM alembic_version")
            ).scalar_one_or_none()
        if revision != expected_head:
            pytest.fail("R6 database did not reach the current Alembic head")
        return engine
    except BaseException:
        engine.dispose()
        raise


@pytest.fixture(scope="module")
def r6_postgres_engine() -> Iterator[Engine]:
    url = _validated_r6_url()
    shared_engine = Base.metadata.info.get(_R6_ENGINE_INFO_KEY)
    if shared_engine is not None:
        if not isinstance(shared_engine, Engine) or shared_engine.url != url:
            pytest.fail("R6 migration and concurrency tests must target the same isolated database")
        yield shared_engine
        return

    engine = _prepare_r6_database(url)
    try:
        yield engine
    finally:
        engine.dispose()


def test_postgres_racing_recovery_code_logins_create_one_session(
    r6_postgres_engine: Engine,
) -> None:
    engine = r6_postgres_engine
    user_id = str(uuid4())
    email = f"r6-{user_id}@example.test"
    tenant_id = str(uuid4())
    recovery_code = uuid4().hex
    now = datetime.now(timezone.utc)
    settings = Settings(
        database_url=engine.url.render_as_string(hide_password=False),
        jwt_secret="test-jwt-secret-at-least-32-bytes-long",
        totp_encryption_key=base64.urlsafe_b64encode(b"x" * 32).decode("ascii"),
        web_origin="https://panel.example.test",
    )
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)

    with session_factory.begin() as session:
        session.add(
            StaffAccount(
                id=user_id,
                email=email,
                password_hash=hash_password("Initial-Password-42!"),
                role="agent",
                tenant_id=tenant_id,
                active=True,
                totp_secret_encrypted=encrypt_totp_secret(
                    "JBSWY3DPEHPK3PXP", settings.totp_encryption_key
                ),
                totp_enabled=True,
                created_at=now,
            )
        )
        session.add(
            StaffRecoveryCode(
                user_id=user_id,
                code_hash=hash_secret(recovery_code),
                created_at=now,
            )
        )

    app = create_app(
        settings=settings,
        session_factory=session_factory,
        email_sender=None,
        clock=lambda: now,
    )
    barrier = Barrier(2, timeout=10)
    payload = {"email": email, "password": "Initial-Password-42!"}

    with (
        TestClient(app, raise_server_exceptions=False) as first_client,
        TestClient(app, raise_server_exceptions=False) as second_client,
    ):
        challenge_tokens = []
        for client in (first_client, second_client):
            response = client.post("/api/v1/auth/login", json=payload)
            assert response.status_code == 200
            challenge_tokens.append(response.json()["challenge_token"])

        def consume_recovery_code(
            client: TestClient, challenge_token: str
        ) -> tuple[int, dict[str, object]]:
            barrier.wait()
            response = client.post(
                "/api/v1/auth/login/totp",
                json={"challenge_token": challenge_token, "recovery_code": recovery_code},
                headers={"Origin": settings.web_origin},
            )
            return response.status_code, response.json()

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [
                executor.submit(consume_recovery_code, client, challenge_token)
                for client, challenge_token in zip(
                    (first_client, second_client), challenge_tokens, strict=True
                )
            ]
            results = [future.result(timeout=30) for future in futures]

    assert sorted(status for status, _ in results) == [200, 401], (
        "PostgreSQL must admit one recovery-code login and reject the loser with 401; "
        f"observed statuses: {[status for status, _ in results]}"
    )
    loser_payload = next(body for status, body in results if status == 401)
    assert loser_payload.get("detail") == "Login challenge is invalid or expired"

    with session_factory() as session:
        assert session.query(StaffSession).filter_by(user_id=user_id).count() == 1
        challenges = session.query(StaffLoginChallenge).filter_by(user_id=user_id).all()
        assert len(challenges) == 2
        assert sum(challenge.consumed_at is not None for challenge in challenges) == 1
        persisted_codes = (
            session.query(StaffRecoveryCode)
            .filter_by(user_id=user_id, code_hash=hash_secret(recovery_code))
            .all()
        )
        assert len(persisted_codes) == 1
        assert persisted_codes[0].used_at is not None
