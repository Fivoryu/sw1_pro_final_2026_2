from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.core.security import hash_secret
from app.db.base import Base
from app.main import create_app
from app.modules.identity.bootstrap import issue_platform_admin_invitation
from app.modules.identity.models import (
    StaffAccount,
    StaffEnrollmentChallenge,
    StaffInvitation,
    StaffLoginChallenge,
    StaffRecoveryCode,
    StaffSession,
)


@dataclass
class FrozenClock:
    now: datetime

    def __call__(self) -> datetime:
        return self.now

    def advance(self, delta: timedelta) -> None:
        self.now += delta


class FakeEmailSender:
    def __init__(self) -> None:
        self.messages: list[tuple[str, str, datetime]] = []

    def send_invitation(self, email: str, link: str, expires_at: datetime) -> None:
        self.messages.append((email, link, expires_at))


def _settings() -> Settings:
    return Settings(
        database_url="sqlite+pysqlite:///:memory:",
        jwt_secret="test-jwt-secret-at-least-32-bytes-long",
        totp_encryption_key="MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=",
        web_origin="https://panel.example.test",
        secure_cookies=True,
        access_token_minutes=60,
    )


@pytest.fixture
def def_context() -> Any:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    clock = FrozenClock(datetime.now(timezone.utc))
    email_sender = FakeEmailSender()
    app = create_app(
        settings=_settings(),
        session_factory=session_factory,
        email_sender=email_sender,
        clock=clock,
    )
    with TestClient(app, base_url="https://testserver") as client:
        yield client, session_factory, email_sender, clock
    engine.dispose()


def _totp(secret: str, now: datetime) -> str:
    from app.core.security import totp_code

    return totp_code(secret, now)


def _create_initial_admin(context: Any) -> tuple[str, str, str, list[str]]:
    client, session_factory, email_sender, clock = context
    issued = issue_platform_admin_invitation(
        session_factory=session_factory,
        email_sender=email_sender,
        email="  OWNER@Example.Test ",
        settings=_settings(),
        clock=clock,
    )
    assert issued is None
    assert len(email_sender.messages) == 1
    email, link, _ = email_sender.messages[0]
    assert email == "owner@example.test"
    invite_token = link.rsplit("/", 1)[-1]

    accepted = client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": invite_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    assert accepted.status_code == 200
    enrollment = accepted.json()
    assert "totp_secret" in enrollment
    assert "enrollment_token" in enrollment
    assert "access_token" not in enrollment
    assert "refresh_token" not in enrollment

    verified = client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={
            "enrollment_token": enrollment["enrollment_token"],
            "code": _totp(enrollment["totp_secret"], clock()),
        },
    )
    assert verified.status_code == 200
    recovery_codes = verified.json()["recovery_codes"]
    assert recovery_codes
    assert "totp_secret" not in verified.json()
    assert "refresh_token" not in verified.json()
    return email, "Initial-Password-42!", enrollment["totp_secret"], recovery_codes


def _begin_admin_login(client: TestClient, email: str, password: str) -> str:
    response = client.post("/api/v1/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200
    assert set(response.json()) == {"challenge_token"}
    assert isinstance(response.json()["challenge_token"], str)
    assert response.json()["challenge_token"]
    assert response.cookies.get("roomforge_refresh") is None
    assert "access_token" not in response.json()
    return response.json()["challenge_token"]


def test_operator_invitation_is_one_time_and_not_exposed_by_public_route(def_context: Any) -> None:
    client, session_factory, email_sender, clock = def_context
    paths = client.get("/openapi.json").json()["paths"]
    assert "/api/v1/auth/register" not in paths
    assert "/api/v1/auth/bootstrap" not in paths
    assert "/api/v1/customer/auth/register" in paths

    issue_platform_admin_invitation(
        session_factory=session_factory,
        email_sender=email_sender,
        email="owner@example.test",
        settings=_settings(),
        clock=clock,
    )
    assert len(email_sender.messages) == 1
    token = email_sender.messages[0][1].rsplit("/", 1)[-1]
    with session_factory() as session:
        invitation = session.query(StaffInvitation).one()
        assert invitation.token_hash == hash_secret(token)

    with pytest.raises(RuntimeError):
        issue_platform_admin_invitation(
            session_factory=session_factory,
            email_sender=email_sender,
            email="owner@example.test",
            settings=_settings(),
            clock=clock,
        )
    assert len(email_sender.messages) == 1


def test_malformed_staff_login_preserves_baseline_validation_response(
    def_context: Any,
) -> None:
    client, _, _, _ = def_context

    response = client.post("/api/v1/auth/login", json={})

    assert response.status_code == 422
    assert response.json() == {"detail": "Request validation failed"}


def test_operator_can_reissue_an_expired_platform_invitation(def_context: Any) -> None:
    client, session_factory, email_sender, clock = def_context
    issue_platform_admin_invitation(
        session_factory=session_factory,
        email_sender=email_sender,
        email="owner@example.test",
        settings=_settings(),
        clock=clock,
    )
    old_token = email_sender.messages[0][1].rsplit("/", 1)[-1]
    clock.advance(timedelta(hours=_settings().invitation_ttl_hours, seconds=1))

    issue_platform_admin_invitation(
        session_factory=session_factory,
        email_sender=email_sender,
        email="owner@example.test",
        settings=_settings(),
        clock=clock,
    )

    assert len(email_sender.messages) == 2, "expired invitations must not block safe reissue"
    new_token = email_sender.messages[1][1].rsplit("/", 1)[-1]
    assert new_token != old_token
    with session_factory() as session:
        invitations = session.query(StaffInvitation).order_by(StaffInvitation.issued_at).all()
        assert [invitation.status for invitation in invitations] == ["expired", "pending"]
        assert invitations[0].token_hash == hash_secret(old_token)
        assert invitations[1].token_hash == hash_secret(new_token)

    old_acceptance = client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": old_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    new_acceptance = client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": new_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    assert old_acceptance.status_code == 401
    assert new_acceptance.status_code == 200


def test_expired_enrollment_challenge_can_be_reissued_safely(def_context: Any) -> None:
    client, session_factory, email_sender, clock = def_context
    issue_platform_admin_invitation(
        session_factory=session_factory,
        email_sender=email_sender,
        email="owner@example.test",
        settings=_settings(),
        clock=clock,
    )
    invite_token = email_sender.messages[0][1].rsplit("/", 1)[-1]
    original = client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": invite_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    assert original.status_code == 200
    old_enrollment = original.json()
    clock.advance(timedelta(minutes=_settings().enrollment_ttl_minutes, seconds=1))

    issue_platform_admin_invitation(
        session_factory=session_factory,
        email_sender=email_sender,
        email="owner@example.test",
        settings=_settings(),
        clock=clock,
    )
    fresh_invite_token = email_sender.messages[-1][1].rsplit("/", 1)[-1]
    reissued = client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": fresh_invite_token,
            "password": "Replacement-Password-42!",
            "password_confirmation": "Replacement-Password-42!",
        },
    )
    assert reissued.status_code == 200, "a fresh invitation must recover expired enrollment"
    new_enrollment = reissued.json()
    assert new_enrollment["enrollment_token"] != old_enrollment["enrollment_token"]

    old_verification = client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={
            "enrollment_token": old_enrollment["enrollment_token"],
            "code": _totp(old_enrollment["totp_secret"], clock()),
        },
    )
    new_verification = client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={
            "enrollment_token": new_enrollment["enrollment_token"],
            "code": _totp(new_enrollment["totp_secret"], clock()),
        },
    )
    assert old_verification.status_code == 401
    assert new_verification.status_code == 200
    with session_factory() as session:
        challenges = session.query(StaffEnrollmentChallenge).all()
        assert len(challenges) == 2
        assert any(
            challenge.token_hash == hash_secret(old_enrollment["enrollment_token"])
            and challenge.consumed_at is not None
            for challenge in challenges
        )
        assert any(
            challenge.token_hash == hash_secret(new_enrollment["enrollment_token"])
            and challenge.consumed_at is not None
            for challenge in challenges
        )


def test_initial_admin_must_enroll_totp_before_any_session(def_context: Any) -> None:
    client, session_factory, email_sender, clock = def_context
    issue_platform_admin_invitation(
        session_factory=def_context[1],
        email_sender=email_sender,
        email="owner@example.test",
        settings=_settings(),
        clock=clock,
    )
    token = email_sender.messages[0][1].rsplit("/", 1)[-1]
    response = client.post(
        "/api/v1/auth/invitations/accept",
        json={"token": token, "password": "Initial-Password-42!", "password_confirmation": "Initial-Password-42!"},
    )
    assert response.status_code == 200
    assert "refresh_token" not in response.json()
    assert "access_token" not in response.json()
    with session_factory() as session:
        invitation = session.query(StaffInvitation).one()
        challenge = session.query(StaffEnrollmentChallenge).one()
        assert invitation.token_hash == hash_secret(token)
        assert challenge.token_hash == hash_secret(response.json()["enrollment_token"])
        assert challenge.password_hash != "Initial-Password-42!"

    no_mfa = client.post(
        "/api/v1/auth/login",
        json={"email": "owner@example.test", "password": "Initial-Password-42!"},
    )
    assert no_mfa.status_code == 401
    assert no_mfa.cookies.get("roomforge_refresh") is None


def test_admin_totp_or_one_time_recovery_code_is_required_before_session(def_context: Any) -> None:
    client, session_factory, _, clock = def_context
    email, password, secret, recovery_codes = _create_initial_admin(def_context)
    with session_factory() as session:
        account = session.query(StaffAccount).one()
        persisted_recovery_hashes = {
            recovery.code_hash
            for recovery in session.query(StaffRecoveryCode).filter_by(user_id=account.id).all()
        }
        assert account.password_hash != password
        assert persisted_recovery_hashes == {hash_secret(code) for code in recovery_codes}

    challenge = _begin_admin_login(client, email, password)
    with session_factory() as session:
        login_challenge = session.query(StaffLoginChallenge).one()
        assert login_challenge.token_hash == hash_secret(challenge)
    valid_totp = _totp(secret, clock())
    invalid_totp = f"{(int(valid_totp) + 1) % 1_000_000:06d}"
    bad_totp = client.post(
        "/api/v1/auth/login/totp",
        json={"challenge_token": challenge, "code": invalid_totp},
        headers={"Origin": "https://panel.example.test"},
    )
    assert bad_totp.status_code == 401
    assert bad_totp.cookies.get("roomforge_refresh") is None

    challenge = _begin_admin_login(client, email, password)
    authenticated = client.post(
        "/api/v1/auth/login/totp",
        json={"challenge_token": challenge, "code": _totp(secret, clock())},
        headers={"Origin": "https://panel.example.test"},
    )
    assert authenticated.status_code == 200
    assert authenticated.json()["user"] == {
        "id": authenticated.json()["user"]["id"],
        "email": email,
        "role": "platform_admin",
        "tenant_id": None,
    }
    assert "refresh_token" not in authenticated.json()
    refresh_token = authenticated.cookies.get("roomforge_refresh")
    assert refresh_token
    assert authenticated.headers["set-cookie"].lower().find("httponly") >= 0
    assert authenticated.headers["set-cookie"].lower().find("secure") >= 0
    with session_factory() as session:
        auth_session = session.query(StaffSession).one()
        assert auth_session.refresh_hash == hash_secret(refresh_token)
        assert auth_session.csrf_hash == hash_secret(authenticated.json()["csrf_token"])

    first_challenge = _begin_admin_login(client, email, password)
    recovered = client.post(
        "/api/v1/auth/login/totp",
        json={"challenge_token": first_challenge, "recovery_code": recovery_codes[0]},
        headers={"Origin": "https://panel.example.test"},
    )
    assert recovered.status_code == 200

    second_challenge = _begin_admin_login(client, email, password)
    reused = client.post(
        "/api/v1/auth/login/totp",
        json={"challenge_token": second_challenge, "recovery_code": recovery_codes[0]},
        headers={"Origin": "https://panel.example.test"},
    )
    assert reused.status_code == 401
    with session_factory() as session:
        account = session.query(StaffAccount).one()
        assert account.password_hash != password
        assert account.totp_secret_encrypted != secret


def test_refresh_rotation_requires_origin_and_csrf_and_logout_revokes_session(def_context: Any) -> None:
    client, _, _, clock = def_context
    email, password, secret, _ = _create_initial_admin(def_context)
    challenge = _begin_admin_login(client, email, password)
    authenticated = client.post(
        "/api/v1/auth/login/totp",
        json={"challenge_token": challenge, "code": _totp(secret, clock())},
        headers={"Origin": "https://panel.example.test"},
    )
    access_token = authenticated.json()["access_token"]
    csrf_token = authenticated.json()["csrf_token"]
    old_refresh = client.cookies.get("roomforge_refresh")
    assert old_refresh

    invalid_origin = client.post(
        "/api/v1/auth/refresh",
        headers={"Origin": "https://evil.example", "X-CSRF-Token": csrf_token},
    )
    assert invalid_origin.status_code == 403
    assert client.cookies.get("roomforge_refresh") == old_refresh

    rotated = client.post(
        "/api/v1/auth/refresh",
        headers={"Origin": "https://panel.example.test", "X-CSRF-Token": csrf_token},
    )
    assert rotated.status_code == 200
    assert "refresh_token" not in rotated.json()
    new_refresh = client.cookies.get("roomforge_refresh")
    assert new_refresh and new_refresh != old_refresh

    old_replay = client.post(
        "/api/v1/auth/refresh",
        cookies={"roomforge_refresh": old_refresh},
        headers={"Origin": "https://panel.example.test", "X-CSRF-Token": rotated.json()["csrf_token"]},
    )
    assert old_replay.status_code == 401

    logout = client.post(
        "/api/v1/auth/logout",
        headers={"Origin": "https://panel.example.test", "X-CSRF-Token": rotated.json()["csrf_token"]},
    )
    assert logout.status_code == 204
    me = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {access_token}"})
    assert me.status_code == 401


def test_admin_session_expires_after_thirty_minutes_of_inactivity(def_context: Any) -> None:
    client, _, _, clock = def_context
    email, password, secret, _ = _create_initial_admin(def_context)
    challenge = _begin_admin_login(client, email, password)
    authenticated = client.post(
        "/api/v1/auth/login/totp",
        json={"challenge_token": challenge, "code": _totp(secret, clock())},
        headers={"Origin": "https://panel.example.test"},
    )
    token = authenticated.json()["access_token"]
    assert client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"}).status_code == 200
    clock.advance(timedelta(minutes=30, seconds=1))
    expired = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert expired.status_code == 401


def test_login_ignores_client_role_and_tenant_in_favor_of_server_identity(
    def_context: Any,
) -> None:
    client, _, _, clock = def_context
    email, password, secret, _ = _create_initial_admin(def_context)
    response = client.post(
        "/api/v1/auth/login",
        json={
            "email": email,
            "password": password,
            "role": "agent",
            "tenant_id": "client-controlled-tenant",
        },
    )

    assert response.status_code == 200
    challenge_token = response.json()["challenge_token"]
    authenticated = client.post(
        "/api/v1/auth/login/totp",
        json={
            "challenge_token": challenge_token,
            "code": _totp(secret, clock()),
        },
        headers={"Origin": "https://panel.example.test"},
    )

    assert authenticated.status_code == 200
    assert authenticated.json()["user"]["email"] == email
    assert authenticated.json()["user"]["role"] == "platform_admin"
    assert authenticated.json()["user"]["tenant_id"] is None
