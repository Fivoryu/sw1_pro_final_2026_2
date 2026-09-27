from __future__ import annotations

import base64
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, replace
from datetime import datetime, timedelta, timezone
from threading import Barrier
from urllib.parse import unquote, urlsplit
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import String, create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import QueuePool, StaticPool

from app.core.config import Settings
from app.core.security import hash_secret
from app.db.base import Base
from app.main import create_app
import app.modules.identity.bootstrap as bootstrap
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
        self.timeouts: list[int] = []

    def send_invitation(
        self, email: str, link: str, expires_at: datetime, *, timeout_seconds: int
    ) -> None:
        self.timeouts.append(timeout_seconds)
        self.messages.append((email, link, expires_at))


@dataclass(frozen=True)
class _PostgresDiagnostic:
    constraint_name: str


class _PostgresUniqueViolation(Exception):
    sqlstate: str
    pgcode: str
    diag: _PostgresDiagnostic

    def __init__(self, constraint_name: str) -> None:
        super().__init__("duplicate key")
        self.sqlstate = "23505"
        self.pgcode = "23505"
        self.diag = _PostgresDiagnostic(constraint_name)


@dataclass
class StaffIdentityContext:
    client: TestClient
    session_factory: sessionmaker[Session]
    email_sender: FakeEmailSender
    clock: FrozenClock
    settings: Settings


def _settings() -> Settings:
    return Settings(
        database_url="sqlite+pysqlite:///:memory:",
        jwt_secret="test-jwt-secret-at-least-32-bytes-long",
        totp_encryption_key=base64.urlsafe_b64encode(b"x" * 32).decode("ascii"),
        web_origin="https://panel.example.test",
    )


@pytest.fixture

def staff_identity_context() -> Any:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    clock = FrozenClock(datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc))
    email_sender = FakeEmailSender()
    settings = _settings()
    app = create_app(
        settings=settings,
        session_factory=session_factory,
        email_sender=email_sender,
        clock=clock,
    )
    with TestClient(app, base_url="https://testserver") as client:
        yield StaffIdentityContext(client, session_factory, email_sender, clock, settings)
    engine.dispose()


def _invitation_token(link: str) -> str:
    path = urlsplit(link).path.rstrip("/")
    return unquote(path.rsplit("/", 1)[-1])


def _seed_invitation(
    context: StaffIdentityContext,
    *,
    invitation_id: str,
    email: str,
    token: str,
    issued_at: datetime,
    expires_at: datetime,
    status: str = "pending",
) -> None:
    with context.session_factory.begin() as session:
        session.add(
            StaffInvitation(
                id=invitation_id,
                email=email,
                role="platform_admin",
                tenant_id=None,
                token_hash=hash_secret(token),
                status=status,
                issued_at=issued_at,
                expires_at=expires_at,
            )
        )


def test_operator_invitation_sends_one_time_token_and_persists_only_its_hash(
    staff_identity_context: StaffIdentityContext,
) -> None:
    context = staff_identity_context

    issue_platform_admin_invitation(
        session_factory=context.session_factory,
        email_sender=context.email_sender,
        email="  OWNER@Example.Test ",
        settings=context.settings,
        clock=context.clock,
    )

    assert len(context.email_sender.messages) == 1, "one invitation email must be sent"
    sent_email, invitation_link, _ = context.email_sender.messages[0]
    token = _invitation_token(invitation_link)

    assert sent_email == "owner@example.test"
    assert token and token in invitation_link, "the invitation link must contain its raw token"
    with context.session_factory() as session:
        invitation = session.query(StaffInvitation).one()
        assert invitation.email == "owner@example.test"
        assert invitation.role == "platform_admin"
        assert invitation.tenant_id is None
        assert invitation.status == "pending"
        assert invitation.token_hash == hash_secret(token)
        assert token not in invitation.token_hash
        assert session.query(StaffAccount).count() == 0
        assert session.query(StaffSession).count() == 0


def test_expired_platform_admin_invitation_is_replaced_and_old_token_is_rejected(
    staff_identity_context: StaffIdentityContext,
) -> None:
    context = staff_identity_context
    old_token = "expired-platform-admin-invitation-token"
    _seed_invitation(
        context,
        invitation_id="expired-platform-admin-invitation",
        email="owner@example.test",
        token=old_token,
        issued_at=(
            context.clock()
            - timedelta(hours=context.settings.invitation_ttl_hours, seconds=1)
        ),
        expires_at=context.clock() - timedelta(seconds=1),
    )

    issue_platform_admin_invitation(
        session_factory=context.session_factory,
        email_sender=context.email_sender,
        email="OWNER@example.test",
        settings=context.settings,
        clock=context.clock,
    )

    assert len(context.email_sender.messages) == 1, "an expired invite must be safely reissued"
    _, invitation_link, _ = context.email_sender.messages[0]
    new_token = _invitation_token(invitation_link)
    assert new_token and new_token != old_token
    with context.session_factory() as session:
        invitations = session.query(StaffInvitation).all()
        prior = next(item for item in invitations if item.id == "expired-platform-admin-invitation")
        replacement = next(item for item in invitations if item.id != prior.id)
        assert prior.status == "expired"
        assert prior.token_hash == hash_secret(old_token)
        assert replacement.email == "owner@example.test"
        assert replacement.role == "platform_admin"
        assert replacement.status == "pending"
        assert replacement.token_hash == hash_secret(new_token)

    old_acceptance = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": old_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    assert old_acceptance.status_code == 401

    new_acceptance = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": new_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    assert new_acceptance.status_code == 200
    replay = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": new_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    assert replay.status_code == 401


def test_accepting_invitation_starts_totp_enrollment_without_authenticating(
    staff_identity_context: StaffIdentityContext,
) -> None:
    context = staff_identity_context
    token = "valid-platform-admin-invitation-token"
    _seed_invitation(
        context,
        invitation_id="valid-platform-admin-invitation",
        email="owner@example.test",
        token=token,
        issued_at=context.clock(),
        expires_at=context.clock() + timedelta(hours=context.settings.invitation_ttl_hours),
    )

    response = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )

    assert response.status_code == 200
    enrollment = response.json()
    assert enrollment.get("enrollment_token")
    assert enrollment.get("totp_secret")
    assert "access_token" not in enrollment
    assert "refresh_token" not in enrollment
    assert response.cookies.get("roomforge_refresh") is None
    with context.session_factory() as session:
        assert session.query(StaffEnrollmentChallenge).count() == 1
        assert session.query(StaffAccount).count() == 0
        assert session.query(StaffSession).count() == 0


def test_bootstrap_is_not_exposed_as_a_public_api_route(
    staff_identity_context: StaffIdentityContext,
) -> None:
    paths = staff_identity_context.client.get("/openapi.json").json()["paths"]
    assert not any(
        "/register" in path or "/bootstrap" in path for path in paths
    )
    response = staff_identity_context.client.post("/api/v1/auth/bootstrap", json={})

    assert response.status_code == 404


_STAFF_SCHEMA_REQUIRED_COLUMNS = {
    "agency": {"id"},
    "staff_account": {
        "id",
        "email",
        "password_hash",
        "role",
        "tenant_id",
        "active",
        "totp_secret_encrypted",
        "totp_enabled",
        "created_at",
    },
    "staff_invitation": {
        "id",
        "email",
        "role",
        "tenant_id",
        "token_hash",
        "status",
        "issued_at",
        "expires_at",
        "accepted_at",
        "delivery_status",
    },
    "staff_session": {
        "id",
        "user_id",
        "refresh_hash",
        "csrf_hash",
        "created_at",
        "last_activity_at",
        "expires_at",
        "revoked_at",
    },
    "staff_enrollment_challenge": {
        "id",
        "invitation_id",
        "token_hash",
        "password_hash",
        "totp_secret_encrypted",
        "created_at",
        "expires_at",
        "attempts",
        "consumed_at",
    },
    "staff_login_challenge": {
        "id",
        "user_id",
        "token_hash",
        "created_at",
        "expires_at",
        "attempts",
        "consumed_at",
    },
    "staff_recovery_code": {"id", "user_id", "code_hash", "created_at", "used_at"},
}


def _staff_schema_table(table_name: str) -> Any:
    table = Base.metadata.tables.get(table_name)
    assert table is not None, f"required schema table {table_name!r} is missing"
    return table


def _staff_schema_unique_keys(table: Any) -> set[tuple[str, ...]]:
    unique_keys = {
        tuple(constraint.columns.keys())
        for constraint in table.constraints
        if constraint.__class__.__name__ == "UniqueConstraint"
    }
    unique_keys.update(
        tuple(expression.name for expression in index.expressions)
        for index in table.indexes
        if index.unique
    )
    return unique_keys


def _staff_schema_checks(table: Any) -> list[str]:
    return [
        " ".join(str(constraint.sqltext).lower().split())
        for constraint in table.constraints
        if constraint.__class__.__name__ == "CheckConstraint"
    ]


def _staff_schema_sql_expression(expression: Any) -> str:
    compiled = expression.compile(compile_kwargs={"literal_binds": True})
    return " ".join(str(compiled).lower().split())


def _staff_schema_foreign_key_targets(table: Any) -> set[tuple[str, str, str | None]]:
    return {
        (foreign_key.parent.name, foreign_key.target_fullname, foreign_key.ondelete)
        for foreign_key in table.foreign_keys
    }


def test_staff_identity_schema_contains_all_required_tables() -> None:
    expected_tables = set(_STAFF_SCHEMA_REQUIRED_COLUMNS)
    actual_tables = set(Base.metadata.tables)
    missing_tables = expected_tables - actual_tables

    assert not missing_tables, f"required staff schema tables are missing: {sorted(missing_tables)}"


def test_staff_identity_schema_tables_contain_required_columns() -> None:
    for table_name, expected_columns in _STAFF_SCHEMA_REQUIRED_COLUMNS.items():
        table = _staff_schema_table(table_name)
        missing_columns = expected_columns - set(table.columns.keys())
        assert not missing_columns, (
            f"schema table {table_name!r} is missing required columns: "
            f"{sorted(missing_columns)}"
        )


def test_agency_schema_persists_only_a_unique_string_identifier() -> None:
    table = _staff_schema_table("agency")

    assert set(table.columns.keys()) == {"id"}
    assert table.primary_key.columns.keys() == ["id"]
    assert isinstance(table.columns["id"].type, String)
    assert table.columns["id"].type.length == 36


def test_staff_account_schema_enforces_identity_and_platform_admin_rules() -> None:
    table = _staff_schema_table("staff_account")
    checks = _staff_schema_checks(table)

    assert ("tenant_id", "agency.id", None) in _staff_schema_foreign_key_targets(table), (
        "staff_account.tenant_id must reference agency.id"
    )
    assert ("email",) in _staff_schema_unique_keys(table), (
        "staff_account.email must be unique"
    )
    assert any(
        "role in ('platform_admin', 'agency_admin', 'agent')" in check
        for check in checks
    ), "staff_account.role must be limited to the supported staff roles"
    assert any(
        all(
            fragment in check
            for fragment in (
                "role = 'platform_admin'",
                "tenant_id is null",
                "role in ('agency_admin', 'agent')",
                "tenant_id is not null",
            )
        )
        for check in checks
    ), "platform admins must have NULL tenant_id and agency roles must have non-NULL tenant_id"

    single_admin_indexes = [
        index
        for index in table.indexes
        if index.unique
        and tuple(expression.name for expression in index.expressions) == ("role",)
        and index.dialect_options["sqlite"].get("where") is not None
    ]
    assert any(
        "role = 'platform_admin'"
        in _staff_schema_sql_expression(index.dialect_options["sqlite"]["where"])
        for index in single_admin_indexes
    ), "staff_account must allow at most one platform_admin account"


def test_staff_invitation_schema_limits_roles_statuses_and_pending_admins() -> None:
    table = _staff_schema_table("staff_invitation")
    checks = _staff_schema_checks(table)

    assert ("tenant_id", "agency.id", None) in _staff_schema_foreign_key_targets(table), (
        "staff_invitation.tenant_id must reference agency.id"
    )
    assert any(
        "role in ('platform_admin', 'agency_admin', 'agent')" in check
        for check in checks
    ), "staff_invitation.role must be limited to the supported staff roles"
    assert any(
        "status in ('pending', 'accepted', 'expired', 'revoked')" in check
        for check in checks
    ), "staff_invitation.status must be limited to the supported statuses"
    assert any(
        all(
            fragment in check
            for fragment in (
                "role = 'platform_admin'",
                "tenant_id is null",
                "role in ('agency_admin', 'agent')",
                "tenant_id is not null",
            )
        )
        for check in checks
    ), "platform-admin invitations must have NULL tenant_id and agency invitations must have non-NULL tenant_id"

    pending_admin_indexes = [
        index
        for index in table.indexes
        if index.unique
        and tuple(expression.name for expression in index.expressions) == ("role", "status")
        and index.dialect_options["sqlite"].get("where") is not None
    ]
    assert any(
        all(
            fragment in _staff_schema_sql_expression(
                index.dialect_options["sqlite"]["where"]
            )
            for fragment in ("role = 'platform_admin'", "status = 'pending'")
        )
        for index in pending_admin_indexes
    ), "staff_invitation must allow at most one pending platform-admin invitation"


def test_staff_enrollment_challenge_is_unique_per_invitation_and_cascades() -> None:
    table = _staff_schema_table("staff_enrollment_challenge")

    assert ("invitation_id",) in _staff_schema_unique_keys(table), (
        "only one staff_enrollment_challenge may exist per invitation"
    )
    assert (
        "invitation_id",
        "staff_invitation.id",
        "CASCADE",
    ) in _staff_schema_foreign_key_targets(table), (
        "staff_enrollment_challenge.invitation_id must cascade on invitation deletion"
    )


def test_staff_session_has_unique_refresh_hash_and_cascading_owner() -> None:
    table = _staff_schema_table("staff_session")

    assert ("refresh_hash",) in _staff_schema_unique_keys(table), (
        "staff_session.refresh_hash must be unique"
    )
    assert ("user_id", "staff_account.id", "CASCADE") in _staff_schema_foreign_key_targets(
        table
    ), "staff_session.user_id must cascade on account deletion"


def test_staff_login_and_recovery_rows_cascade_and_recovery_key_is_unique() -> None:
    login_table = _staff_schema_table("staff_login_challenge")
    recovery_table = _staff_schema_table("staff_recovery_code")

    assert ("user_id", "staff_account.id", "CASCADE") in _staff_schema_foreign_key_targets(
        login_table
    ), "staff_login_challenge.user_id must cascade on account deletion"
    assert ("user_id", "staff_account.id", "CASCADE") in _staff_schema_foreign_key_targets(
        recovery_table
    ), "staff_recovery_code.user_id must cascade on account deletion"
    assert ("user_id", "code_hash") in _staff_schema_unique_keys(recovery_table), (
        "staff_recovery_code must have a unique (user_id, code_hash) key"
    )


def test_operator_cli_issues_platform_admin_invitation(
    staff_identity_context: StaffIdentityContext,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = staff_identity_context
    settings = replace(
        context.settings,
        database_connect_timeout_seconds=6,
        database_pool_timeout_seconds=7,
        database_statement_timeout_seconds=8,
        email_send_timeout_seconds=13,
    )
    session_factory_calls: list[dict[str, object]] = []

    def use_test_session_factory(
        database_url: str, **kwargs: int
    ) -> tuple[None, sessionmaker[Session]]:
        session_factory_calls.append({"database_url": database_url, **kwargs})
        return None, context.session_factory

    monkeypatch.setattr(Settings, "from_env", lambda: settings)
    monkeypatch.setattr(
        bootstrap,
        "configured_email_sender",
        lambda *args, **kwargs: context.email_sender,
        raising=False,
    )
    monkeypatch.setattr(
        bootstrap,
        "create_session_factory",
        use_test_session_factory,
        raising=False,
    )
    monkeypatch.setattr(sys, "argv", ["roomforge-bootstrap", "--email", "owner@example.test"])

    result = bootstrap.main()

    assert result == 0
    assert len(context.email_sender.messages) == 1
    assert context.email_sender.messages[0][0] == "owner@example.test"
    assert context.email_sender.timeouts == [13]
    assert session_factory_calls == [
        {
            "database_url": settings.database_url,
            "connect_timeout_seconds": 6,
            "pool_timeout_seconds": 7,
            "statement_timeout_seconds": 8,
        }
    ]


@pytest.mark.parametrize("password", ["", "   "])
def test_accepting_invitation_rejects_blank_passwords(
    staff_identity_context: StaffIdentityContext,
    password: str,
) -> None:
    context = staff_identity_context
    token = "valid-platform-admin-invitation-token"
    _seed_invitation(
        context,
        invitation_id="valid-platform-admin-invitation",
        email="owner@example.test",
        token=token,
        issued_at=context.clock(),
        expires_at=context.clock() + timedelta(hours=context.settings.invitation_ttl_hours),
    )

    response = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": token,
            "password": password,
            "password_confirmation": password,
        },
    )

    assert response.status_code == 422
    with context.session_factory() as session:
        invitation = session.query(StaffInvitation).one()
        assert invitation.status == "pending"
        assert session.query(StaffEnrollmentChallenge).count() == 0


def test_failed_platform_admin_invitation_delivery_revokes_durable_invitation(
    staff_identity_context: StaffIdentityContext,
) -> None:
    context = staff_identity_context

    class FailingEmailSender:
        def send_invitation(
            self, email: str, link: str, expires_at: datetime, *, timeout_seconds: int
        ) -> None:
            del timeout_seconds
            raise RuntimeError("mail transport unavailable")

    with pytest.raises(RuntimeError, match="delivery failed"):
        issue_platform_admin_invitation(
            session_factory=context.session_factory,
            email_sender=FailingEmailSender(),
            email="owner@example.test",
            settings=context.settings,
            clock=context.clock,
        )

    with context.session_factory() as session:
        invitations = session.query(StaffInvitation).all()
        assert len(invitations) == 1
        assert invitations[0].status == "revoked"
        assert invitations[0].delivery_status == "failed"


def test_concurrent_invitation_acceptance_returns_one_success_and_one_unauthorized(
    tmp_path: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from concurrent.futures import ThreadPoolExecutor
    import threading

    import app.modules.identity.router as identity_router

    database_path = tmp_path / "staff-identity-concurrent.sqlite3"
    engine = create_engine(
        f"sqlite+pysqlite:///{database_path.as_posix()}",
        connect_args={"check_same_thread": False, "timeout": 10.0},
        pool_size=2,
        max_overflow=0,
    )
    try:
        Base.metadata.create_all(engine)
        session_factory = sessionmaker(bind=engine, expire_on_commit=False)
        clock = FrozenClock(datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc))
        settings = _settings()
        token = "concurrent-platform-admin-invitation-token"
        with session_factory.begin() as session:
            session.add(
                StaffInvitation(
                    id="concurrent-platform-admin-invitation",
                    email="owner@example.test",
                    role="platform_admin",
                    tenant_id=None,
                    token_hash=hash_secret(token),
                    status="pending",
                    issued_at=clock(),
                    expires_at=clock() + timedelta(hours=settings.invitation_ttl_hours),
                )
            )
        app = create_app(
            settings=settings,
            session_factory=session_factory,
            email_sender=FakeEmailSender(),
            clock=clock,
        )

        original_hash_password = identity_router.hash_password
        hash_barrier = threading.Barrier(2, timeout=10)

        def synchronized_hash_password(password: str) -> str:
            hash_barrier.wait()
            return original_hash_password(password)

        monkeypatch.setattr(identity_router, "hash_password", synchronized_hash_password)
        payload = {
            "token": token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        }
        with (
            TestClient(app, raise_server_exceptions=False) as first_client,
            TestClient(app, raise_server_exceptions=False) as second_client,
        ):
            with ThreadPoolExecutor(max_workers=2) as executor:
                responses = [
                    executor.submit(
                        client.post,
                        "/api/v1/auth/invitations/accept",
                        json=payload,
                    )
                    for client in (first_client, second_client)
                ]
                results = [future.result(timeout=30) for future in responses]

        assert sorted(response.status_code for response in results) == [200, 401]
        with session_factory() as session:
            assert session.query(StaffEnrollmentChallenge).count() == 1
    finally:
        engine.dispose()


def test_unrelated_enrollment_token_unique_violation_is_not_reported_as_unauthorized(
    staff_identity_context: StaffIdentityContext,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = staff_identity_context
    now = context.clock()
    invitation_ttl = timedelta(hours=context.settings.invitation_ttl_hours)

    _seed_invitation(
        context,
        invitation_id="existing-invitation",
        email="existing-admin@example.test",
        token="existing-invitation-token",
        issued_at=now,
        expires_at=now + invitation_ttl,
        status="accepted",
    )
    with context.session_factory.begin() as session:
        session.add(
            StaffEnrollmentChallenge(
                invitation_id="existing-invitation",
                token_hash=hash_secret("duplicate-enrollment-token"),
                password_hash="placeholder-password-hash",
                totp_secret_encrypted="placeholder-encrypted-secret",
                created_at=now,
                expires_at=now + invitation_ttl,
            )
        )

    target_token = "target-platform-admin-invitation-token"
    _seed_invitation(
        context,
        invitation_id="target-invitation",
        email="target-admin@example.test",
        token=target_token,
        issued_at=now,
        expires_at=now + invitation_ttl,
    )

    import app.modules.identity.router as identity_router

    monkeypatch.setattr(
        identity_router,
        "random_token",
        lambda: "duplicate-enrollment-token",
    )
    app = create_app(
        settings=context.settings,
        session_factory=context.session_factory,
        email_sender=context.email_sender,
        clock=context.clock,
    )

    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.post(
            "/api/v1/auth/invitations/accept",
            json={
                "token": target_token,
                "password": "Initial-Password-42!",
                "password_confirmation": "Initial-Password-42!",
            },
        )

    assert response.status_code == 500
    with context.session_factory() as session:
        challenges = session.query(StaffEnrollmentChallenge).all()
        assert len(challenges) == 1
        assert challenges[0].invitation_id == "existing-invitation"
        target_invitation = session.get(StaffInvitation, "target-invitation")
        assert target_invitation is not None
        assert target_invitation.status == "pending"


@pytest.mark.parametrize(
    ("constraint_name", "expected"),
    [
        ("staff_enrollment_challenge_invitation_id_key", True),
        ("staff_enrollment_challenge_token_hash_key", False),
        ("staff_account_email_key", False),
    ],
)
def test_concurrent_conflict_requires_enrollment_invitation_constraint(
    constraint_name: str,
    expected: bool,
) -> None:
    from sqlalchemy.exc import IntegrityError

    import app.modules.identity.router as identity_router

    original = _PostgresUniqueViolation(constraint_name)
    error = IntegrityError("statement", {}, original)

    assert identity_router._is_concurrent_conflict(error) is expected


def test_totp_enrollment_creates_account_after_valid_code_and_shows_recovery_once(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import decrypt_totp_secret, totp_code, verify_password
    from app.modules.identity.models import StaffRecoveryCode

    context = staff_identity_context
    invitation_token = "valid-platform-admin-invitation-token"
    password = "Initial-Password-42!"
    _seed_invitation(
        context,
        invitation_id="valid-platform-admin-invitation",
        email="owner@example.test",
        token=invitation_token,
        issued_at=context.clock(),
        expires_at=context.clock() + timedelta(hours=context.settings.invitation_ttl_hours),
    )

    acceptance = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": invitation_token,
            "password": password,
            "password_confirmation": password,
        },
    )
    assert acceptance.status_code == 200
    enrollment = acceptance.json()
    enrollment_token = enrollment["enrollment_token"]
    totp_secret = enrollment["totp_secret"]
    code = totp_code(totp_secret, context.clock())

    response = context.client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={"enrollment_token": enrollment_token, "code": code},
    )

    assert response.status_code == 200
    payload = response.json()
    recovery_codes = payload.get("recovery_codes")
    assert isinstance(recovery_codes, list)
    assert len(recovery_codes) == context.settings.recovery_code_count
    assert "access_token" not in payload
    assert "refresh_token" not in payload
    assert response.cookies.get("roomforge_refresh") is None
    with context.session_factory() as session:
        accounts = session.query(StaffAccount).all()
        assert len(accounts) == 1
        account = accounts[0]
        assert account.active is True
        assert account.role == "platform_admin"
        assert account.tenant_id is None
        assert account.totp_enabled is True
        assert verify_password(account.password_hash, password)
        assert account.totp_secret_encrypted is not None
        assert (
            decrypt_totp_secret(
                account.totp_secret_encrypted,
                context.settings.totp_encryption_key,
            )
            == totp_secret
        )

        enrollment_challenge = session.query(StaffEnrollmentChallenge).one()
        assert enrollment_challenge.consumed_at is not None
        assert enrollment_challenge.token_hash == hash_secret(enrollment_token)
        assert enrollment_token not in enrollment_challenge.token_hash

        persisted_recovery_codes = session.query(StaffRecoveryCode).all()
        assert len(persisted_recovery_codes) == len(recovery_codes)
        assert {item.code_hash for item in persisted_recovery_codes} == {
            hash_secret(recovery_code) for recovery_code in recovery_codes
        }
        assert all(
            recovery_code not in item.code_hash
            for recovery_code in recovery_codes
            for item in persisted_recovery_codes
        )
        assert session.query(StaffSession).count() == 0


def test_expired_enrollment_challenge_recovers_with_a_fresh_invitation(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import totp_code

    context = staff_identity_context
    issue_platform_admin_invitation(
        session_factory=context.session_factory,
        email_sender=context.email_sender,
        email="owner@example.test",
        settings=context.settings,
        clock=context.clock,
    )
    first_token = _invitation_token(context.email_sender.messages[-1][1])
    first_acceptance = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": first_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    assert first_acceptance.status_code == 200
    old_enrollment = first_acceptance.json()

    context.clock.advance(timedelta(minutes=context.settings.enrollment_ttl_minutes, seconds=1))
    issue_platform_admin_invitation(
        session_factory=context.session_factory,
        email_sender=context.email_sender,
        email="owner@example.test",
        settings=context.settings,
        clock=context.clock,
    )
    fresh_token = _invitation_token(context.email_sender.messages[-1][1])
    fresh_acceptance = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": fresh_token,
            "password": "Replacement-Password-42!",
            "password_confirmation": "Replacement-Password-42!",
        },
    )
    assert fresh_acceptance.status_code == 200
    new_enrollment = fresh_acceptance.json()

    old_verification = context.client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={
            "enrollment_token": old_enrollment["enrollment_token"],
            "code": totp_code(old_enrollment["totp_secret"], context.clock()),
        },
    )
    new_verification = context.client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={
            "enrollment_token": new_enrollment["enrollment_token"],
            "code": totp_code(new_enrollment["totp_secret"], context.clock()),
        },
    )

    assert old_verification.status_code == 401
    assert new_verification.status_code == 200
    with context.session_factory() as session:
        challenges = session.query(StaffEnrollmentChallenge).all()
        assert len(challenges) == 2
        assert all(challenge.consumed_at is not None for challenge in challenges)
        assert {challenge.invitation_id for challenge in challenges} == {
            invitation.id
            for invitation in session.query(StaffInvitation).all()
            if invitation.token_hash in {hash_secret(first_token), hash_secret(fresh_token)}
        }


def test_totp_lockout_keeps_email_reserved_until_challenge_expiry(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import totp_code

    context = staff_identity_context
    invitation_token = "lockout-platform-admin-invitation-token"
    _seed_invitation(
        context,
        invitation_id="lockout-platform-admin-invitation",
        email="owner@example.test",
        token=invitation_token,
        issued_at=context.clock(),
        expires_at=context.clock() + timedelta(hours=context.settings.invitation_ttl_hours),
    )
    acceptance = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": invitation_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    assert acceptance.status_code == 200
    enrollment = acceptance.json()
    valid_code = totp_code(enrollment["totp_secret"], context.clock())
    invalid_code = f"{(int(valid_code) + 1) % 1_000_000:06d}"

    for _ in range(5):
        rejected = context.client.post(
            "/api/v1/auth/totp/enroll/verify",
            json={
                "enrollment_token": enrollment["enrollment_token"],
                "code": invalid_code,
            },
        )
        assert rejected.status_code == 401

    with context.session_factory() as session:
        challenge = session.query(StaffEnrollmentChallenge).one()
        assert challenge.attempts == 5
        assert challenge.consumed_at is not None

    with pytest.raises(RuntimeError, match="active invitation"):
        issue_platform_admin_invitation(
            session_factory=context.session_factory,
            email_sender=context.email_sender,
            email="owner@example.test",
            settings=context.settings,
            clock=context.clock,
        )

    context.clock.advance(
        timedelta(minutes=context.settings.enrollment_ttl_minutes, seconds=1)
    )
    issue_platform_admin_invitation(
        session_factory=context.session_factory,
        email_sender=context.email_sender,
        email="owner@example.test",
        settings=context.settings,
        clock=context.clock,
    )
    assert len(context.email_sender.messages) == 1
    with context.session_factory() as session:
        pending = session.query(StaffInvitation).filter_by(status="pending").one()
        assert pending.email == "owner@example.test"


def test_legacy_mixed_case_invitation_creates_canonical_login_email(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import totp_code

    context = staff_identity_context
    invitation_token = "legacy-mixed-case-invitation-token"
    password = "Initial-Password-42!"
    _seed_invitation(
        context,
        invitation_id="legacy-mixed-case-invitation",
        email="  LEGACY@Example.Test  ",
        token=invitation_token,
        issued_at=context.clock(),
        expires_at=context.clock() + timedelta(hours=context.settings.invitation_ttl_hours),
    )
    acceptance = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": invitation_token,
            "password": password,
            "password_confirmation": password,
        },
    )
    assert acceptance.status_code == 200
    enrollment = acceptance.json()
    verified = context.client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={
            "enrollment_token": enrollment["enrollment_token"],
            "code": totp_code(enrollment["totp_secret"], context.clock()),
        },
    )
    assert verified.status_code == 200

    with context.session_factory() as session:
        account = session.query(StaffAccount).one()
        assert account.email == "legacy@example.test"

    login = context.client.post(
        "/api/v1/auth/login",
        json={"email": "legacy@example.test", "password": password},
    )
    assert login.status_code == 200
    assert login.json().get("challenge_token")


def test_totp_enrollment_rejects_invalid_code_without_creating_account(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import totp_code

    context = staff_identity_context
    invitation_token = "invalid-code-platform-admin-invitation-token"
    password = "Initial-Password-42!"
    _seed_invitation(
        context,
        invitation_id="invalid-code-platform-admin-invitation",
        email="owner@example.test",
        token=invitation_token,
        issued_at=context.clock(),
        expires_at=context.clock() + timedelta(hours=context.settings.invitation_ttl_hours),
    )

    acceptance = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": invitation_token,
            "password": password,
            "password_confirmation": password,
        },
    )
    assert acceptance.status_code == 200
    enrollment = acceptance.json()
    actual_code = totp_code(enrollment["totp_secret"], context.clock())
    invalid_code = f"{(int(actual_code) + 1) % 1_000_000:06d}"

    response = context.client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={
            "enrollment_token": enrollment["enrollment_token"],
            "code": invalid_code,
        },
    )

    assert response.status_code == 401
    with context.session_factory() as session:
        assert session.query(StaffAccount).count() == 0


def test_first_factor_login_creates_hash_only_challenge_without_session(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import encrypt_totp_secret, hash_password
    from app.modules.identity.models import StaffLoginChallenge

    context = staff_identity_context
    password = "Initial-Password-42!"
    account_id = "platform-admin-login-account"
    totp_secret = "JBSWY3DPEHPK3PXP"
    with context.session_factory.begin() as session:
        session.add(
            StaffAccount(
                id=account_id,
                email="owner@example.test",
                password_hash=hash_password(password),
                role="platform_admin",
                tenant_id=None,
                active=True,
                totp_secret_encrypted=encrypt_totp_secret(
                    totp_secret, context.settings.totp_encryption_key
                ),
                totp_enabled=True,
                created_at=context.clock(),
            )
        )

    response = context.client.post(
        "/api/v1/auth/login",
        json={"email": "  OWNER@Example.Test  ", "password": password},
    )

    assert response.status_code == 200
    payload = response.json()
    challenge_token = payload.get("challenge_token")
    assert isinstance(challenge_token, str) and challenge_token
    assert "access_token" not in payload
    assert "refresh_token" not in payload
    assert response.cookies.get("roomforge_refresh") is None
    with context.session_factory() as session:
        challenge = session.query(StaffLoginChallenge).one()
        assert challenge.user_id == account_id
        assert challenge.token_hash == hash_secret(challenge_token)
        assert challenge_token not in challenge.token_hash
        expires_at = challenge.expires_at
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        else:
            expires_at = expires_at.astimezone(timezone.utc)
        assert expires_at == context.clock() + timedelta(
            minutes=context.settings.login_challenge_minutes
        )
        assert session.query(StaffSession).count() == 0


def test_login_is_denied_until_initial_totp_enrollment_is_complete(
    staff_identity_context: StaffIdentityContext,
) -> None:
    context = staff_identity_context
    token = "initial-enrollment-platform-admin-invitation-token"
    _seed_invitation(
        context,
        invitation_id="initial-enrollment-platform-admin-invitation",
        email="owner@example.test",
        token=token,
        issued_at=context.clock(),
        expires_at=context.clock() + timedelta(hours=context.settings.invitation_ttl_hours),
    )
    acceptance = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    assert acceptance.status_code == 200

    login = context.client.post(
        "/api/v1/auth/login",
        json={"email": "owner@example.test", "password": "Initial-Password-42!"},
    )

    assert login.status_code == 401
    with context.session_factory() as session:
        assert session.query(StaffAccount).count() == 0
        assert session.query(StaffLoginChallenge).count() == 0
        assert session.query(StaffSession).count() == 0


def test_first_factor_login_rejects_wrong_password_without_challenge(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import encrypt_totp_secret, hash_password
    from app.modules.identity.models import StaffLoginChallenge

    context = staff_identity_context
    account_id = "platform-admin-wrong-password-account"
    with context.session_factory.begin() as session:
        session.add(
            StaffAccount(
                id=account_id,
                email="owner@example.test",
                password_hash=hash_password("Initial-Password-42!"),
                role="platform_admin",
                tenant_id=None,
                active=True,
                totp_secret_encrypted=encrypt_totp_secret(
                    "JBSWY3DPEHPK3PXP", context.settings.totp_encryption_key
                ),
                totp_enabled=True,
                created_at=context.clock(),
            )
        )

    response = context.client.post(
        "/api/v1/auth/login",
        json={"email": "owner@example.test", "password": "Wrong-Password-42!"},
    )

    assert response.status_code == 401
    with context.session_factory() as session:
        assert session.query(StaffLoginChallenge).count() == 0


def test_totp_enrollment_consumes_challenge_after_five_invalid_codes(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import totp_code

    context = staff_identity_context
    invitation_token = "totp-lockout-platform-admin-invitation-token"
    password = "Initial-Password-42!"
    _seed_invitation(
        context,
        invitation_id="totp-lockout-platform-admin-invitation",
        email="owner@example.test",
        token=invitation_token,
        issued_at=context.clock(),
        expires_at=context.clock() + timedelta(hours=context.settings.invitation_ttl_hours),
    )

    acceptance = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": invitation_token,
            "password": password,
            "password_confirmation": password,
        },
    )
    assert acceptance.status_code == 200
    enrollment = acceptance.json()
    enrollment_token = enrollment["enrollment_token"]
    totp_secret = enrollment["totp_secret"]
    valid_code = totp_code(totp_secret, context.clock())
    invalid_code = f"{(int(valid_code) + 1) % 1_000_000:06d}"

    for _ in range(5):
        response = context.client.post(
            "/api/v1/auth/totp/enroll/verify",
            json={"enrollment_token": enrollment_token, "code": invalid_code},
        )
        assert response.status_code == 401

    valid_response = context.client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={"enrollment_token": enrollment_token, "code": valid_code},
    )
    assert valid_response.status_code == 401

    with context.session_factory() as session:
        assert session.query(StaffAccount).count() == 0
        challenge = session.query(StaffEnrollmentChallenge).one()
        assert challenge.attempts == 5
        assert challenge.consumed_at is not None


def _seed_login_admin(
    context: StaffIdentityContext,
    *,
    account_id: str,
) -> tuple[str, str]:
    from app.core.security import encrypt_totp_secret, hash_password

    password = "Initial-Password-42!"
    totp_secret = "JBSWY3DPEHPK3PXP"
    with context.session_factory.begin() as session:
        session.add(
            StaffAccount(
                id=account_id,
                email="owner@example.test",
                password_hash=hash_password(password),
                role="platform_admin",
                tenant_id=None,
                active=True,
                totp_secret_encrypted=encrypt_totp_secret(
                    totp_secret, context.settings.totp_encryption_key
                ),
                totp_enabled=True,
                created_at=context.clock(),
            )
        )
    return password, totp_secret


def _start_login_challenge(
    context: StaffIdentityContext,
    *,
    password: str,
) -> str:
    response = context.client.post(
        "/api/v1/auth/login",
        json={"email": "owner@example.test", "password": password},
    )
    assert response.status_code == 200
    challenge_token = response.json().get("challenge_token")
    assert isinstance(challenge_token, str) and challenge_token
    return challenge_token


def test_totp_login_creates_session_and_sets_http_only_refresh_cookie(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import hash_secret, totp_code
    from app.modules.identity.models import StaffLoginChallenge

    context = staff_identity_context
    account_id = "platform-admin-totp-login-account"
    password, totp_secret = _seed_login_admin(context, account_id=account_id)
    challenge_token = _start_login_challenge(context, password=password)

    response = context.client.post(
        "/api/v1/auth/login/totp",
        json={
            "challenge_token": challenge_token,
            "code": totp_code(totp_secret, context.clock()),
        },
        headers={"Origin": "https://panel.example.test"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload.get("access_token")
    assert payload.get("csrf_token")
    assert "refresh_token" not in payload
    user = payload.get("user")
    assert isinstance(user, dict)
    assert user.get("id") == account_id
    assert user.get("email") == "owner@example.test"
    assert user.get("role") == "platform_admin"
    refresh_token = response.cookies.get("roomforge_refresh")
    assert refresh_token
    set_cookie = "; ".join(response.headers.get_list("set-cookie")).lower()
    assert "roomforge_refresh=" in set_cookie
    assert "httponly" in set_cookie
    assert "secure" in set_cookie

    with context.session_factory() as session:
        persisted_session = session.query(StaffSession).one()
        assert persisted_session.user_id == account_id
        assert persisted_session.refresh_hash == hash_secret(refresh_token)
        assert persisted_session.csrf_hash == hash_secret(payload["csrf_token"])
        challenge = session.query(StaffLoginChallenge).one()
        assert challenge.consumed_at is not None

    replay = context.client.post(
        "/api/v1/auth/login/totp",
        json={
            "challenge_token": challenge_token,
            "code": totp_code(totp_secret, context.clock()),
        },
        headers={"Origin": "https://panel.example.test"},
    )
    assert replay.status_code == 401
    with context.session_factory() as session:
        assert session.query(StaffSession).count() == 1


def test_concurrent_recovery_login_allows_at_most_one_success() -> None:
    from app.core.security import encrypt_totp_secret, hash_password

    database_url = (
        "sqlite+pysqlite:///file:staff_identity_recovery"
        "?mode=memory&cache=shared&uri=true"
    )
    engine = create_engine(
        database_url,
        connect_args={"check_same_thread": False, "timeout": 10},
        poolclass=QueuePool,
        pool_size=4,
        max_overflow=0,
    )
    try:
        Base.metadata.create_all(engine)
        session_factory = sessionmaker(bind=engine, expire_on_commit=False)
        now = datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc)
        user_id = "concurrent-recovery-login-account"
        password = "Initial-Password-42!"
        recovery_code = "concurrent-one-time-recovery-code"
        settings = _settings()
        with session_factory.begin() as session:
            session.add(
                StaffAccount(
                    id=user_id,
                    email="owner@example.test",
                    password_hash=hash_password(password),
                    role="platform_admin",
                    tenant_id=None,
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
            email_sender=FakeEmailSender(),
            clock=lambda: now,
        )
        start_barrier = Barrier(2, timeout=10)
        with (
            TestClient(app, raise_server_exceptions=False) as first_client,
            TestClient(app, raise_server_exceptions=False) as second_client,
        ):
            challenge_tokens = []
            for client in (first_client, second_client):
                login = client.post(
                    "/api/v1/auth/login",
                    json={"email": "owner@example.test", "password": password},
                )
                assert login.status_code == 200
                challenge_tokens.append(login.json()["challenge_token"])

            def consume_recovery_code(
                client: TestClient, challenge_token: str
            ) -> int:
                start_barrier.wait()
                response = client.post(
                    "/api/v1/auth/login/totp",
                    json={
                        "challenge_token": challenge_token,
                        "recovery_code": recovery_code,
                    },
                    headers={"Origin": settings.web_origin},
                )
                return response.status_code

            with ThreadPoolExecutor(max_workers=2) as executor:
                attempts = [
                    executor.submit(consume_recovery_code, client, token)
                    for client, token in zip(
                        (first_client, second_client), challenge_tokens, strict=True
                    )
                ]
                status_codes = [attempt.result(timeout=20) for attempt in attempts]

        # Shared-cache SQLite may return 500 for the losing SQLITE_LOCKED write.
        # The asserted contract is one successful authentication and one persisted session.
        assert status_codes.count(200) == 1
        with session_factory() as session:
            assert session.query(StaffSession).count() == 1
            consumed_code = session.query(StaffRecoveryCode).one()
            assert consumed_code.used_at is not None
    finally:
        engine.dispose()


def test_recovery_login_consumes_code_once(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import hash_secret
    from app.modules.identity.models import StaffRecoveryCode

    context = staff_identity_context
    account_id = "platform-admin-recovery-login-account"
    password, _ = _seed_login_admin(context, account_id=account_id)
    raw_code = "single-use-recovery-code"
    with context.session_factory.begin() as session:
        session.add(
            StaffRecoveryCode(
                user_id=account_id,
                code_hash=hash_secret(raw_code),
                created_at=context.clock(),
                used_at=None,
            )
        )

    challenge_token = _start_login_challenge(context, password=password)
    response = context.client.post(
        "/api/v1/auth/login/totp",
        json={"challenge_token": challenge_token, "recovery_code": raw_code},
        headers={"Origin": "https://panel.example.test"},
    )

    assert response.status_code == 200
    with context.session_factory() as session:
        persisted_session = session.query(StaffSession).one()
        assert persisted_session.user_id == account_id
        recovery_code = session.query(StaffRecoveryCode).one()
        assert recovery_code.used_at is not None

    next_challenge_token = _start_login_challenge(context, password=password)
    reused_code = context.client.post(
        "/api/v1/auth/login/totp",
        json={
            "challenge_token": next_challenge_token,
            "recovery_code": raw_code,
        },
        headers={"Origin": "https://panel.example.test"},
    )
    assert reused_code.status_code == 401
    with context.session_factory() as session:
        assert session.query(StaffSession).count() == 1


def test_login_ignores_spoofed_role_and_tenant_in_favor_of_stored_identity(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import totp_code

    context = staff_identity_context
    password, secret = _seed_login_admin(
        context, account_id="platform-admin-spoofed-login-account"
    )
    login = context.client.post(
        "/api/v1/auth/login",
        json={
            "email": "owner@example.test",
            "password": password,
            "role": "agent",
            "tenant_id": "spoofed-tenant",
        },
    )
    assert login.status_code == 200

    authenticated = context.client.post(
        "/api/v1/auth/login/totp",
        json={
            "challenge_token": login.json()["challenge_token"],
            "code": totp_code(secret, context.clock()),
        },
        headers={"Origin": context.settings.web_origin},
    )

    assert authenticated.status_code == 200
    assert authenticated.json()["user"] == {
        "id": "platform-admin-spoofed-login-account",
        "email": "owner@example.test",
        "role": "platform_admin",
        "tenant_id": None,
    }


def test_invalid_login_totp_does_not_create_session(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import totp_code

    context = staff_identity_context
    password, totp_secret = _seed_login_admin(
        context, account_id="platform-admin-invalid-totp-login-account"
    )
    challenge_token = _start_login_challenge(context, password=password)
    accepted_codes = {
        totp_code(
            totp_secret,
            context.clock() + timedelta(seconds=offset * 30),
        )
        for offset in (-1, 0, 1)
    }
    invalid_code = next(
        f"{candidate:06d}"
        for candidate in range(1_000_000)
        if f"{candidate:06d}" not in accepted_codes
    )

    response = context.client.post(
        "/api/v1/auth/login/totp",
        json={"challenge_token": challenge_token, "code": invalid_code},
        headers={"Origin": "https://panel.example.test"},
    )

    assert response.status_code == 401
    with context.session_factory() as session:
        assert session.query(StaffSession).count() == 0


def test_login_mfa_challenge_consumes_after_five_invalid_attempts(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import hash_secret, totp_code
    from app.modules.identity.models import StaffLoginChallenge, StaffRecoveryCode

    context = staff_identity_context
    account_id = "platform-admin-login-mfa-lockout-account"
    password, totp_secret = _seed_login_admin(context, account_id=account_id)
    with context.session_factory.begin() as session:
        session.add(
            StaffRecoveryCode(
                user_id=account_id,
                code_hash=hash_secret("valid-recovery-code"),
                created_at=context.clock(),
                used_at=None,
            )
        )
    challenge_token = _start_login_challenge(context, password=password)
    valid_code = totp_code(totp_secret, context.clock())
    invalid_code = f"{(int(valid_code) + 1) % 1_000_000:06d}"
    headers = {"Origin": "https://panel.example.test"}

    for _ in range(3):
        response = context.client.post(
            "/api/v1/auth/login/totp",
            json={"challenge_token": challenge_token, "code": invalid_code},
            headers=headers,
        )
        assert response.status_code == 401

    for _ in range(2):
        response = context.client.post(
            "/api/v1/auth/login/totp",
            json={
                "challenge_token": challenge_token,
                "recovery_code": "invalid-recovery-code",
            },
            headers=headers,
        )
        assert response.status_code == 401

    final_attempt = context.client.post(
        "/api/v1/auth/login/totp",
        json={
            "challenge_token": challenge_token,
            "code": valid_code,
        },
        headers=headers,
    )
    assert final_attempt.status_code == 401

    with context.session_factory() as session:
        challenge = session.query(StaffLoginChallenge).one()
        assert challenge.attempts == 5
        assert challenge.consumed_at is not None
        assert session.query(StaffSession).count() == 0
        recovery_codes = session.query(StaffRecoveryCode).all()
        assert len(recovery_codes) == 1
        assert all(recovery_code.used_at is None for recovery_code in recovery_codes)


def _authenticate_staff_admin(
    context: StaffIdentityContext,
    *,
    account_id: str,
) -> tuple[dict[str, Any], str]:
    from app.core.security import totp_code

    password, totp_secret = _seed_login_admin(context, account_id=account_id)
    challenge_token = _start_login_challenge(context, password=password)
    response = context.client.post(
        "/api/v1/auth/login/totp",
        json={
            "challenge_token": challenge_token,
            "code": totp_code(totp_secret, context.clock()),
        },
        headers={"Origin": "https://panel.example.test"},
    )

    assert response.status_code == 200
    login_payload = response.json()
    refresh_token = response.cookies.get("roomforge_refresh")
    assert isinstance(refresh_token, str) and refresh_token
    return login_payload, refresh_token


def test_refresh_rotates_cookie_and_rejects_replayed_refresh(
    staff_identity_context: StaffIdentityContext,
) -> None:
    context = staff_identity_context
    login_payload, old_refresh_token = _authenticate_staff_admin(
        context, account_id="platform-admin-refresh-rotation-account"
    )
    old_csrf_token = login_payload["csrf_token"]
    with context.session_factory() as session:
        original_session_id = session.query(StaffSession).one().id

    context.clock.advance(timedelta(minutes=1))
    response = context.client.post(
        "/api/v1/auth/refresh",
        headers={
            "Origin": "https://panel.example.test",
            "X-CSRF-Token": old_csrf_token,
            "Cookie": f"roomforge_refresh={old_refresh_token}",
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload.get("access_token")
    assert payload.get("csrf_token")
    assert "refresh_token" not in payload
    new_refresh_token = response.cookies.get("roomforge_refresh")
    assert new_refresh_token
    assert new_refresh_token != old_refresh_token
    set_cookie = "; ".join(response.headers.get_list("set-cookie")).lower()
    assert "roomforge_refresh=" in set_cookie
    assert "httponly" in set_cookie
    assert "secure" in set_cookie

    with context.session_factory() as session:
        persisted_sessions = session.query(StaffSession).all()
        assert len(persisted_sessions) == 1
        persisted_session = persisted_sessions[0]
        assert persisted_session.id == original_session_id
        assert persisted_session.refresh_hash == hash_secret(new_refresh_token)
        assert persisted_session.csrf_hash == hash_secret(payload["csrf_token"])
        last_activity_at = persisted_session.last_activity_at
        if last_activity_at.tzinfo is None:
            last_activity_at = last_activity_at.replace(tzinfo=timezone.utc)
        else:
            last_activity_at = last_activity_at.astimezone(timezone.utc)
        assert last_activity_at == context.clock()

    replay = context.client.post(
        "/api/v1/auth/refresh",
        headers={
            "Origin": "https://panel.example.test",
            "X-CSRF-Token": payload["csrf_token"],
            "Cookie": f"roomforge_refresh={old_refresh_token}",
        },
    )
    assert replay.status_code == 401
    with context.session_factory() as session:
        assert session.query(StaffSession).count() == 1


def test_refresh_rejects_bad_origin_or_csrf_without_rotation(
    staff_identity_context: StaffIdentityContext,
) -> None:
    context = staff_identity_context
    login_payload, refresh_token = _authenticate_staff_admin(
        context, account_id="platform-admin-refresh-csrf-account"
    )
    csrf_token = login_payload["csrf_token"]
    with context.session_factory() as session:
        persisted_session = session.query(StaffSession).one()
        original_refresh_hash = persisted_session.refresh_hash
        original_csrf_hash = persisted_session.csrf_hash

    invalid_requests = (
        {
            "Origin": "https://attacker.example.test",
            "X-CSRF-Token": csrf_token,
        },
        {
            "Origin": "https://panel.example.test",
            "X-CSRF-Token": "incorrect-csrf-token",
        },
        {"Origin": "https://panel.example.test"},
    )
    for headers in invalid_requests:
        response = context.client.post(
            "/api/v1/auth/refresh",
            headers={
                **headers,
                "Cookie": f"roomforge_refresh={refresh_token}",
            },
        )
        assert response.status_code == 403
        assert context.client.cookies.get("roomforge_refresh") == refresh_token
        with context.session_factory() as session:
            unchanged_session = session.query(StaffSession).one()
            assert unchanged_session.refresh_hash == original_refresh_hash
            assert unchanged_session.csrf_hash == original_csrf_hash


def test_logout_requires_origin_and_csrf_then_revokes_and_clears_cookie(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from email.utils import parsedate_to_datetime

    context = staff_identity_context
    login_payload, refresh_token = _authenticate_staff_admin(
        context, account_id="platform-admin-logout-account"
    )
    access_token = login_payload["access_token"]
    csrf_token = login_payload["csrf_token"]
    with context.session_factory() as session:
        authenticated_session = session.query(StaffSession).one()
        session_id = authenticated_session.id
        assert authenticated_session.revoked_at is None

    invalid_headers = (
        {
            "Origin": "https://attacker.example.test",
            "X-CSRF-Token": csrf_token,
        },
        {
            "Origin": "https://panel.example.test",
            "X-CSRF-Token": "incorrect-csrf-token",
        },
        {"Origin": "https://panel.example.test"},
    )
    for headers in invalid_headers:
        response = context.client.post(
            "/api/v1/auth/logout",
            headers={
                **headers,
                "Cookie": f"roomforge_refresh={refresh_token}",
            },
        )
        assert response.status_code == 403
        assert context.client.cookies.get("roomforge_refresh") == refresh_token
        with context.session_factory() as session:
            unchanged_session = session.get(StaffSession, session_id)
            assert unchanged_session is not None
            assert unchanged_session.revoked_at is None

    response = context.client.post(
        "/api/v1/auth/logout",
        headers={
            "Origin": "https://panel.example.test",
            "X-CSRF-Token": csrf_token,
            "Cookie": f"roomforge_refresh={refresh_token}",
        },
    )

    assert response.status_code == 204
    assert response.content == b""
    refresh_cookie_header = next(
        (
            value.lower()
            for value in response.headers.get_list("set-cookie")
            if value.lower().startswith("roomforge_refresh=")
        ),
        None,
    )
    assert refresh_cookie_header is not None
    assert "path=/api/v1/auth" in refresh_cookie_header
    cookie_is_expired = "max-age=0" in refresh_cookie_header
    if not cookie_is_expired and "expires=" in refresh_cookie_header:
        expires = refresh_cookie_header.split("expires=", 1)[1].split(";", 1)[0]
        cookie_is_expired = parsedate_to_datetime(expires) <= context.clock()
    assert cookie_is_expired, "logout must expire the refresh cookie"

    with context.session_factory() as session:
        revoked_session = session.get(StaffSession, session_id)
        assert revoked_session is not None
        assert revoked_session.revoked_at is not None

    assert context.client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {access_token}"},
    ).status_code == 401

    refresh_response = context.client.post(
        "/api/v1/auth/refresh",
        headers={
            "Origin": "https://panel.example.test",
            "X-CSRF-Token": csrf_token,
            "Cookie": f"roomforge_refresh={refresh_token}",
        },
    )
    assert refresh_response.status_code == 401
    with context.session_factory() as session:
        persisted_sessions = session.query(StaffSession).all()
        assert len(persisted_sessions) == 1
        assert persisted_sessions[0].id == session_id


def test_me_requires_bearer_bound_to_active_session_and_returns_server_identity(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import decode_access_token, create_access_token

    context = staff_identity_context
    context.clock.now = datetime.now(timezone.utc)
    account_id = "platform-admin-me-session-account"
    login_payload, _ = _authenticate_staff_admin(context, account_id=account_id)
    access_token = login_payload["access_token"]

    with context.session_factory() as session:
        persisted_session = session.query(StaffSession).one()
        session_id = persisted_session.id

    claims = decode_access_token(access_token, context.settings.jwt_secret)
    assert claims["sid"] == session_id

    response = context.client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert response.status_code == 200
    assert response.json() == {
        "user": {
            "id": account_id,
            "email": "owner@example.test",
            "role": "platform_admin",
            "tenant_id": None,
        }
    }

    assert context.client.get("/api/v1/auth/me").status_code == 401

    fabricated_session_token = create_access_token(
        user_id=account_id,
        session_id="fabricated-staff-session",
        signing_key=context.settings.jwt_secret,
        now=context.clock(),
        lifetime_minutes=15,
    )
    fabricated_session_response = context.client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {fabricated_session_token}"},
    )
    assert fabricated_session_response.status_code == 401


def test_me_slides_activity_and_expires_after_thirty_minutes_idle(
    staff_identity_context: StaffIdentityContext,
) -> None:
    from app.core.security import create_access_token

    context = staff_identity_context
    context.clock.now = datetime.now(timezone.utc)
    account_id = "platform-admin-me-idle-account"
    _authenticate_staff_admin(context, account_id=account_id)

    with context.session_factory() as session:
        persisted_session = session.query(StaffSession).one()
        session_id = persisted_session.id

    access_token = create_access_token(
        user_id=account_id,
        session_id=session_id,
        signing_key=context.settings.jwt_secret,
        now=context.clock(),
        lifetime_minutes=120,
    )
    headers = {"Authorization": f"Bearer {access_token}"}

    response = context.client.get("/api/v1/auth/me", headers=headers)
    assert response.status_code == 200

    context.clock.advance(timedelta(minutes=29))
    response = context.client.get("/api/v1/auth/me", headers=headers)
    assert response.status_code == 200
    with context.session_factory() as session:
        active_session = session.get(StaffSession, session_id)
        assert active_session is not None
        last_activity_at = active_session.last_activity_at
        if last_activity_at.tzinfo is None:
            last_activity_at = last_activity_at.replace(tzinfo=timezone.utc)
        else:
            last_activity_at = last_activity_at.astimezone(timezone.utc)
        assert last_activity_at == context.clock()

    context.clock.advance(timedelta(minutes=30, seconds=1))
    response = context.client.get("/api/v1/auth/me", headers=headers)
    assert response.status_code == 401
    with context.session_factory() as session:
        expired_session = session.get(StaffSession, session_id)
        assert expired_session is not None
        assert expired_session.revoked_at is not None
