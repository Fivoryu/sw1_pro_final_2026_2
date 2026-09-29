from __future__ import annotations

from dataclasses import replace

import pytest

from app.core.config import Settings


def _set_required_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://local:test@localhost/roomforge")
    monkeypatch.setenv("JWT_SECRET", "test-jwt-secret-at-least-32-bytes-long")
    monkeypatch.setenv("STAFF_TOTP_ENCRYPTION_KEY", "test-key")
    monkeypatch.setenv("STAFF_WEB_ORIGIN", "https://panel.example.test")


def _settings() -> Settings:
    return Settings(
        database_url="sqlite+pysqlite:///:memory:",
        jwt_secret="test-jwt-secret-at-least-32-bytes-long",
        totp_encryption_key="test-key",
        web_origin="https://panel.example.test",
    )


def test_timeout_settings_use_approved_defaults(monkeypatch: pytest.MonkeyPatch) -> None:
    _set_required_environment(monkeypatch)

    settings = Settings.from_env()

    assert settings.database_connect_timeout_seconds == 5
    assert settings.database_pool_timeout_seconds == 5
    assert settings.database_statement_timeout_seconds == 10
    assert settings.email_send_timeout_seconds == 10


def test_timeout_settings_are_environment_configurable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _set_required_environment(monkeypatch)
    monkeypatch.setenv("DATABASE_CONNECT_TIMEOUT_SECONDS", "7")
    monkeypatch.setenv("DATABASE_POOL_TIMEOUT_SECONDS", "8")
    monkeypatch.setenv("DATABASE_STATEMENT_TIMEOUT_SECONDS", "12")
    monkeypatch.setenv("STAFF_EMAIL_SEND_TIMEOUT_SECONDS", "15")

    settings = Settings.from_env()

    assert settings.database_connect_timeout_seconds == 7
    assert settings.database_pool_timeout_seconds == 8
    assert settings.database_statement_timeout_seconds == 12
    assert settings.email_send_timeout_seconds == 15


@pytest.mark.parametrize(
    "field_name",
    [
        "database_connect_timeout_seconds",
        "database_pool_timeout_seconds",
        "database_statement_timeout_seconds",
        "email_send_timeout_seconds",
    ],
)
def test_timeout_settings_must_be_positive(field_name: str) -> None:
    settings = replace(_settings(), **{field_name: 0})

    with pytest.raises(ValueError, match="positive"):
        settings.validate()


@pytest.mark.parametrize(
    "environment_name",
    [
        "DATABASE_CONNECT_TIMEOUT_SECONDS",
        "DATABASE_POOL_TIMEOUT_SECONDS",
        "DATABASE_STATEMENT_TIMEOUT_SECONDS",
        "STAFF_EMAIL_SEND_TIMEOUT_SECONDS",
    ],
)
@pytest.mark.parametrize("value", ["0", "-1", "invalid"])
def test_timeout_environment_values_must_be_positive_integers(
    monkeypatch: pytest.MonkeyPatch,
    environment_name: str,
    value: str,
) -> None:
    _set_required_environment(monkeypatch)
    monkeypatch.setenv(environment_name, value)

    with pytest.raises(RuntimeError, match=environment_name):
        Settings.from_env()
