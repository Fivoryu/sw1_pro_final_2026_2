from __future__ import annotations

import socket
from typing import cast
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.main import create_app


def _settings(monkeypatch: pytest.MonkeyPatch, endpoint_url: str) -> Settings:
    monkeypatch.setenv("DATABASE_URL", "sqlite+pysqlite:///:memory:")
    monkeypatch.setenv("JWT_SECRET", "test-jwt-secret-at-least-32-bytes-long")
    monkeypatch.setenv("STAFF_TOTP_ENCRYPTION_KEY", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
    monkeypatch.setenv("STAFF_WEB_ORIGIN", "https://panel.example.test")
    monkeypatch.setenv("S3_ENDPOINT_URL", endpoint_url)
    monkeypatch.setenv("FLOCI_ENDPOINT_URL", "http://127.0.0.1:4566")
    return Settings.from_env()


def _sqlite_session_factory() -> tuple[Engine, sessionmaker[Session]]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    return engine, sessionmaker(bind=engine, expire_on_commit=False)


def _app(settings: Settings, session_factory: sessionmaker[Session]):
    return create_app(settings=settings, session_factory=session_factory)


class _StubSocket:
    def close(self) -> None:
        pass


def test_liveness_does_not_touch_database_or_floci(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = _settings(monkeypatch, "http://floci:4566")
    session_factory = cast(
        sessionmaker[Session], Mock(side_effect=AssertionError("database was touched"))
    )

    def unexpected_connection(*args: object, **kwargs: object) -> None:
        raise AssertionError("Floci was touched")

    monkeypatch.setattr(socket, "create_connection", unexpected_connection)
    # The deliberately hostile factory must stay uninspected so liveness can assert
    # that no database work happens; the guard itself is covered by test_catalog.py.
    monkeypatch.setattr("app.main.protect_session_factory", lambda factory: None)

    with TestClient(_app(settings, session_factory)) as client:
        response = client.get("/health/live")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readiness_uses_injected_session_factory_and_s3_endpoint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = _settings(monkeypatch, "http://floci:4566/s3")
    engine, session_factory = _sqlite_session_factory()
    connections: list[tuple[tuple[str, int], float | None]] = []

    def connect(address: tuple[str, int], timeout: float | None = None) -> _StubSocket:
        connections.append((address, timeout))
        return _StubSocket()

    monkeypatch.setattr(socket, "create_connection", connect)

    try:
        with TestClient(_app(settings, session_factory)) as client:
            response = client.get("/health/ready")
    finally:
        engine.dispose()

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    assert connections == [(('floci', 4566), 2)]


def test_readiness_returns_safe_503_when_database_check_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = _settings(monkeypatch, "http://floci:4566")
    engine, session_factory = _sqlite_session_factory()

    def fail_query(*args: object, **kwargs: object) -> None:
        raise RuntimeError("database-password=do-not-expose")

    event.listen(engine, "before_cursor_execute", fail_query)
    monkeypatch.setattr(socket, "create_connection", lambda *args, **kwargs: _StubSocket())

    try:
        with TestClient(_app(settings, session_factory)) as client:
            response = client.get("/health/ready")
    finally:
        engine.dispose()

    assert response.status_code == 503
    assert response.json() == {
        "detail": "A required dependency is unavailable",
        "code": "dependency_unavailable",
    }
    assert "do-not-expose" not in response.text


def test_readiness_returns_safe_503_when_floci_socket_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = _settings(monkeypatch, "http://floci:4566")
    engine, session_factory = _sqlite_session_factory()

    def fail_connection(*args: object, **kwargs: object) -> None:
        raise OSError("floci-secret=do-not-expose")

    monkeypatch.setattr(socket, "create_connection", fail_connection)

    try:
        with TestClient(_app(settings, session_factory)) as client:
            response = client.get("/health/ready")
    finally:
        engine.dispose()

    assert response.status_code == 503
    assert response.json() == {
        "detail": "A required dependency is unavailable",
        "code": "dependency_unavailable",
    }
    assert "do-not-expose" not in response.text


def test_settings_read_s3_endpoint_and_ignore_host_loopback_floci_endpoint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("DATABASE_URL", "sqlite+pysqlite:///:memory:")
    monkeypatch.setenv("JWT_SECRET", "test-jwt-secret-at-least-32-bytes-long")
    monkeypatch.setenv("STAFF_TOTP_ENCRYPTION_KEY", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
    monkeypatch.setenv("STAFF_WEB_ORIGIN", "https://panel.example.test")
    monkeypatch.setenv("FLOCI_ENDPOINT_URL", "http://127.0.0.1:4566")
    monkeypatch.setenv("S3_ENDPOINT_URL", "http://floci:4566")

    settings = Settings.from_env()

    assert settings.s3_endpoint_url == "http://floci:4566"


def test_readiness_does_not_fall_back_to_host_loopback_floci_endpoint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _settings(monkeypatch, "http://floci:4566")
    monkeypatch.delenv("S3_ENDPOINT_URL")
    settings = Settings.from_env()
    engine, session_factory = _sqlite_session_factory()

    def unexpected_connection(*args: object, **kwargs: object) -> None:
        raise AssertionError("FLOCI_ENDPOINT_URL must not be used by readiness")

    monkeypatch.setattr(socket, "create_connection", unexpected_connection)

    try:
        with TestClient(_app(settings, session_factory)) as client:
            response = client.get("/health/ready")
    finally:
        engine.dispose()

    assert response.status_code == 503
    assert response.json() == {
        "detail": "A required dependency is unavailable",
        "code": "dependency_unavailable",
    }


def test_openapi_documents_readiness_error_with_shared_error_response(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = _settings(monkeypatch, "http://floci:4566")
    engine, session_factory = _sqlite_session_factory()

    try:
        with TestClient(_app(settings, session_factory)) as client:
            openapi = client.get("/openapi.json").json()
    finally:
        engine.dispose()

    responses = openapi["paths"]["/health/ready"]["get"]["responses"]
    error_schema = responses["503"]["content"]["application/json"]["schema"]
    assert error_schema["$ref"] == "#/components/schemas/ErrorResponse"
    assert "dependency_unavailable" in openapi["components"]["schemas"]["ErrorResponse"]["properties"]["code"]["enum"]
