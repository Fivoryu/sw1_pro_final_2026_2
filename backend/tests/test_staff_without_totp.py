"""Staff access with STAFF_REQUIRE_TOTP=false: password only, no TOTP step."""

from __future__ import annotations

import base64
from dataclasses import replace
from datetime import datetime, timezone
from typing import Any, Iterator
from urllib.parse import urlsplit

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.modules.identity.bootstrap import issue_platform_admin_invitation
from app.modules.identity.models import StaffAccount, StaffEnrollmentChallenge

PASSWORD = "Initial-Password-42!"


class _Outbox:
    def __init__(self) -> None:
        self.links: list[str] = []

    def send_invitation(
        self, email: str, link: str, expires_at: datetime, *, timeout_seconds: int
    ) -> None:
        del email, expires_at, timeout_seconds
        self.links.append(link)


def _context(require_totp: bool) -> Iterator[dict[str, Any]]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    now = datetime.now(timezone.utc)
    settings = replace(
        Settings(
            database_url="sqlite+pysqlite:///:memory:",
            jwt_secret="test-jwt-secret-at-least-32-bytes-long",
            totp_encryption_key=base64.urlsafe_b64encode(b"x" * 32).decode("ascii"),
            web_origin="https://panel.example.test",
        ),
        require_totp=require_totp,
    )
    outbox = _Outbox()
    app = create_app(
        settings=settings,
        session_factory=session_factory,
        email_sender=outbox,
        clock=lambda: now,
    )
    with TestClient(app, base_url="https://testserver") as client:
        issue_platform_admin_invitation(
            session_factory=session_factory,
            email_sender=outbox,
            email="admin@example.test",
            settings=settings,
            clock=lambda: now,
        )
        token = urlsplit(outbox.links[0]).path.rsplit("/", 1)[-1]
        yield {"client": client, "session_factory": session_factory, "token": token}
    engine.dispose()


@pytest.fixture
def without_totp() -> Iterator[dict[str, Any]]:
    yield from _context(require_totp=False)


@pytest.fixture
def with_totp() -> Iterator[dict[str, Any]]:
    yield from _context(require_totp=True)


def _accept(context: dict[str, Any]) -> Any:
    return context["client"].post(
        "/api/v1/auth/invitations/accept",
        json={"token": context["token"], "password": PASSWORD, "password_confirmation": PASSWORD},
    )


def test_settings_read_the_flag_from_the_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "sqlite+pysqlite:///:memory:")
    monkeypatch.setenv("JWT_SECRET", "test-jwt-secret-at-least-32-bytes-long")
    monkeypatch.setenv("STAFF_TOTP_ENCRYPTION_KEY", base64.urlsafe_b64encode(b"x" * 32).decode())
    monkeypatch.setenv("STAFF_WEB_ORIGIN", "https://panel.example.test")

    monkeypatch.delenv("STAFF_REQUIRE_TOTP", raising=False)
    assert Settings.from_env().require_totp is True
    monkeypatch.setenv("STAFF_REQUIRE_TOTP", "false")
    assert Settings.from_env().require_totp is False


def test_accepting_an_invitation_creates_the_account_without_enrollment(
    without_totp: dict[str, Any],
) -> None:
    accepted = _accept(without_totp)

    assert accepted.status_code == 200
    body = accepted.json()
    assert body["totp_required"] is False
    assert body["account"]["email"] == "admin@example.test"
    assert body["account"]["role"] == "platform_admin"
    assert "totp_secret" not in body
    with without_totp["session_factory"]() as session:
        account = session.query(StaffAccount).one()
        assert account.active is True
        assert account.totp_enabled is False
        assert account.totp_secret_encrypted is None
        assert session.query(StaffEnrollmentChallenge).count() == 0
    # The invitation is single use.
    assert _accept(without_totp).status_code == 401


def test_login_completes_with_the_password_only(without_totp: dict[str, Any]) -> None:
    _accept(without_totp)
    client = without_totp["client"]

    started = client.post(
        "/api/v1/auth/login", json={"email": "admin@example.test", "password": PASSWORD}
    )
    assert started.status_code == 200
    assert started.json()["totp_required"] is False

    completed = client.post(
        "/api/v1/auth/login/totp", json={"challenge_token": started.json()["challenge_token"]}
    )
    assert completed.status_code == 200
    session_body = completed.json()
    me = client.get(
        "/api/v1/auth/me", headers={"Authorization": f"Bearer {session_body['access_token']}"}
    )
    assert me.status_code == 200
    assert me.json()["user"]["email"] == "admin@example.test"


def test_a_wrong_password_or_a_reused_challenge_is_still_refused(
    without_totp: dict[str, Any],
) -> None:
    _accept(without_totp)
    client = without_totp["client"]

    wrong = client.post(
        "/api/v1/auth/login", json={"email": "admin@example.test", "password": "nope"}
    )
    assert wrong.status_code == 401

    challenge = client.post(
        "/api/v1/auth/login", json={"email": "admin@example.test", "password": PASSWORD}
    ).json()["challenge_token"]
    assert client.post("/api/v1/auth/login/totp", json={"challenge_token": challenge}).status_code == 200
    assert client.post("/api/v1/auth/login/totp", json={"challenge_token": challenge}).status_code == 401
    assert client.post("/api/v1/auth/login/totp", json={"challenge_token": "unknown"}).status_code == 401


def test_a_code_is_rejected_when_totp_is_off(without_totp: dict[str, Any]) -> None:
    _accept(without_totp)
    client = without_totp["client"]
    challenge = client.post(
        "/api/v1/auth/login", json={"email": "admin@example.test", "password": PASSWORD}
    ).json()["challenge_token"]

    response = client.post(
        "/api/v1/auth/login/totp", json={"challenge_token": challenge, "code": "123456"}
    )
    assert response.status_code == 422


def test_with_totp_on_the_flow_is_unchanged(with_totp: dict[str, Any]) -> None:
    accepted = _accept(with_totp)
    assert accepted.status_code == 200
    assert "totp_secret" in accepted.json()
    assert "account" not in accepted.json()

    client = with_totp["client"]
    # Not enrolled yet: no account, so the password alone does not start a login.
    started = client.post(
        "/api/v1/auth/login", json={"email": "admin@example.test", "password": PASSWORD}
    )
    assert started.status_code == 401
