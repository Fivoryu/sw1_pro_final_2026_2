from __future__ import annotations

import base64
from dataclasses import dataclass, replace
from datetime import datetime, timedelta, timezone
from typing import Any, cast
from urllib.parse import urlsplit

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Table, create_engine, event, insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.core.security import create_access_token, hash_secret, totp_code
from app.db.base import Base
from app.main import create_app
from app.modules.identity.bootstrap import issue_platform_admin_invitation
from app.modules.identity.models import (
    Agency,
    StaffAccount,
    StaffEnrollmentChallenge,
    StaffInvitation,
    StaffSession,
)


@dataclass
class AgencyApiContext:
    client: TestClient
    session_factory: sessionmaker[Session]
    settings: Settings
    now: datetime
    email_sender: "FakeEmailSender"


class FakeEmailSender:
    def __init__(self, *, fail: bool = False) -> None:
        self.messages: list[tuple[str, str, datetime]] = []
        self.timeouts: list[int] = []
        self.fail = fail

    def send_invitation(
        self, email: str, link: str, expires_at: datetime, *, timeout_seconds: int
    ) -> None:
        self.timeouts.append(timeout_seconds)
        if self.fail:
            raise RuntimeError("mail transport unavailable")
        self.messages.append((email, link, expires_at))


@pytest.fixture

def agency_api_context() -> Any:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    now = datetime.now(timezone.utc)
    settings = Settings(
        database_url="sqlite+pysqlite:///:memory:",
        jwt_secret="test-jwt-secret-at-least-32-bytes-long",
        totp_encryption_key=base64.urlsafe_b64encode(b"x" * 32).decode("ascii"),
        web_origin="https://panel.example.test",
    )
    email_sender = FakeEmailSender()
    app = create_app(
        settings=settings,
        session_factory=session_factory,
        email_sender=email_sender,
        clock=lambda: now,
    )
    with TestClient(app, base_url="https://testserver") as client:
        yield AgencyApiContext(client, session_factory, settings, now, email_sender)
    engine.dispose()


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _seed_account(
    context: AgencyApiContext,
    *,
    account_id: str,
    email: str | None = None,
    role: str = "platform_admin",
    tenant_id: str | None = None,
    active: bool = True,
    revoked: bool = False,
    token_role: str | None = None,
) -> str:
    session_id = f"session-{account_id}"
    with context.session_factory.begin() as session:
        if tenant_id is not None and session.get(Agency, tenant_id) is None:
            session.add(Agency(id=tenant_id))
            session.flush()
        session.add(
            StaffAccount(
                id=account_id,
                email=email or f"{account_id}@example.test",
                password_hash="test-password-hash",
                role=role,
                tenant_id=tenant_id,
                active=active,
                totp_secret_encrypted="encrypted-test-secret",
                totp_enabled=True,
                created_at=context.now,
            )
        )
        session.add(
            StaffSession(
                id=session_id,
                user_id=account_id,
                refresh_hash=f"refresh-{account_id}",
                csrf_hash=f"csrf-{account_id}",
                created_at=context.now,
                last_activity_at=context.now,
                expires_at=context.now + timedelta(hours=1),
                revoked_at=context.now if revoked else None,
            )
        )

    if token_role is None:
        token = create_access_token(
            user_id=account_id,
            session_id=session_id,
            signing_key=context.settings.jwt_secret,
            now=context.now,
            lifetime_minutes=context.settings.access_token_minutes,
        )
    else:
        import jwt

        issued_at = int(context.now.timestamp())
        token = jwt.encode(
            {
                "sub": account_id,
                "sid": session_id,
                "iat": issued_at,
                "exp": issued_at + 3600,
                "jti": f"token-{account_id}",
                "role": token_role,
                "tenant_id": None,
            },
            context.settings.jwt_secret,
            algorithm="HS256",
        )
    return token


def _seed_invitation(
    context: AgencyApiContext,
    *,
    email: str,
    role: str,
    tenant_id: str | None,
    token: str,
    expires_at: datetime,
    status: str = "pending",
) -> None:
    with context.session_factory.begin() as session:
        if tenant_id is not None and session.get(Agency, tenant_id) is None:
            session.add(Agency(id=tenant_id))
            session.flush()
        session.add(
            StaffInvitation(
                email=email,
                role=role,
                tenant_id=tenant_id,
                token_hash=hash_secret(token),
                status=status,
                issued_at=context.now,
                expires_at=expires_at,
            )
        )


def _seed_enrollment_claim(
    context: AgencyApiContext,
    *,
    email: str,
    tenant_id: str,
    challenge_expires_at: datetime,
) -> None:
    with context.session_factory.begin() as session:
        if session.get(Agency, tenant_id) is None:
            session.add(Agency(id=tenant_id))
            session.flush()
        invitation = StaffInvitation(
            email=email,
            role="agency_admin",
            tenant_id=tenant_id,
            token_hash=hash_secret(f"invite-{email}"),
            status="accepted",
            issued_at=context.now,
            expires_at=context.now + timedelta(hours=1),
            accepted_at=context.now,
        )
        session.add(invitation)
        session.flush()
        session.add(
            StaffEnrollmentChallenge(
                invitation_id=invitation.id,
                token_hash=hash_secret(f"enrollment-{email}"),
                password_hash="test-password-hash",
                totp_secret_encrypted="encrypted-test-secret",
                created_at=context.now,
                expires_at=challenge_expires_at,
                attempts=0,
            )
        )


def _platform_admin_token(
    context: AgencyApiContext, *, email: str | None = None
) -> str:
    return _seed_account(context, account_id="platform-admin", email=email)


def test_platform_admin_can_create_and_list_id_only_agencies(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    headers = _headers(_platform_admin_token(context))

    created_later = context.client.post(
        "/api/v1/agencies", json={"id": "agency-z"}, headers=headers
    )
    created_first = context.client.post(
        "/api/v1/agencies", json={"id": "agency-a"}, headers=headers
    )
    listed = context.client.get("/api/v1/agencies", headers=headers)

    assert created_later.status_code == 201
    assert created_later.json() == {"id": "agency-z"}
    assert created_first.status_code == 201
    assert created_first.json() == {"id": "agency-a"}
    assert listed.status_code == 200
    assert listed.json() == {
        "agencies": [{"id": "agency-a"}, {"id": "agency-z"}],
        "pagination": {"limit": 20, "offset": 0, "total": 2},
    }


def test_agency_list_paginates_in_stable_order_and_keeps_total_accurate(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    with context.session_factory.begin() as session:
        session.add_all(Agency(id=f"agency-{letter}") for letter in "edcba")
    headers = _headers(_platform_admin_token(context))

    page = context.client.get("/api/v1/agencies?limit=2&offset=1", headers=headers)
    beyond_end = context.client.get("/api/v1/agencies?limit=2&offset=20", headers=headers)

    assert page.status_code == 200
    assert page.json() == {
        "agencies": [{"id": "agency-b"}, {"id": "agency-c"}],
        "pagination": {"limit": 2, "offset": 1, "total": 5},
    }
    assert beyond_end.status_code == 200
    assert beyond_end.json() == {
        "agencies": [],
        "pagination": {"limit": 2, "offset": 20, "total": 5},
    }


def test_agency_list_accepts_maximum_page_size(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    with context.session_factory.begin() as session:
        session.add_all(Agency(id=f"agency-{index:03d}") for index in range(101))

    response = context.client.get(
        "/api/v1/agencies?limit=100",
        headers=_headers(_platform_admin_token(context)),
    )

    assert response.status_code == 200
    assert len(response.json()["agencies"]) == 100
    assert response.json()["pagination"] == {"limit": 100, "offset": 0, "total": 101}


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1", "limit=invalid"])
def test_agency_list_rejects_out_of_range_pagination(
    agency_api_context: AgencyApiContext, query: str
) -> None:
    context = agency_api_context
    response = context.client.get(
        f"/api/v1/agencies?{query}",
        headers=_headers(_platform_admin_token(context)),
    )

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"


def test_duplicate_agency_id_returns_409(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    headers = _headers(_platform_admin_token(context))
    payload = {"id": "agency-duplicate"}

    assert context.client.post("/api/v1/agencies", json=payload, headers=headers).status_code == 201
    duplicate = context.client.post("/api/v1/agencies", json=payload, headers=headers)

    assert duplicate.status_code == 409


@pytest.mark.parametrize("payload", [{}, {"id": ""}, {"id": "a" * 37}])
def test_invalid_agency_payload_returns_422(
    agency_api_context: AgencyApiContext, payload: dict[str, str]
) -> None:
    context = agency_api_context
    response = context.client.post(
        "/api/v1/agencies",
        json=payload,
        headers=_headers(_platform_admin_token(context)),
    )

    assert response.status_code == 422


@pytest.mark.parametrize(
    ("method", "path", "payload"),
    [
        ("get", "/api/v1/agencies", None),
        ("post", "/api/v1/agencies", {"id": "agency-new"}),
        (
            "post",
            "/api/v1/agencies/agency-known/admin-invitations",
            {"email": "staff@example.test"},
        ),
    ],
)
@pytest.mark.parametrize("authorization", [None, "Bearer invalid-token"])
def test_management_routes_require_valid_session(
    agency_api_context: AgencyApiContext,
    method: str,
    path: str,
    payload: dict[str, str] | None,
    authorization: str | None,
) -> None:
    context = agency_api_context
    headers = {} if authorization is None else {"Authorization": authorization}

    response = context.client.request(method, path, json=payload, headers=headers)

    assert response.status_code == 401


def test_revoked_management_session_returns_401(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    token = _seed_account(context, account_id="revoked-admin", revoked=True)

    response = context.client.get("/api/v1/agencies", headers=_headers(token))

    assert response.status_code == 401


def test_inactive_staff_account_cannot_manage_agencies(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    token = _seed_account(context, account_id="inactive-admin", active=False)

    response = context.client.get("/api/v1/agencies", headers=_headers(token))

    assert response.status_code == 401


@pytest.mark.parametrize("role", ["agency_admin", "agent"])
def test_non_platform_admin_cannot_manage_agencies(
    agency_api_context: AgencyApiContext, role: str
) -> None:
    context = agency_api_context
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-known"))
    token = _seed_account(
        context,
        account_id=f"{role}-user",
        role=role,
        tenant_id="agency-known",
    )
    headers = _headers(token)

    responses = [
        context.client.get("/api/v1/agencies", headers=headers),
        context.client.post("/api/v1/agencies", json={"id": "new"}, headers=headers),
        context.client.post(
            "/api/v1/agencies/agency-known/admin-invitations",
            json={"email": "staff@example.test"},
            headers=headers,
        ),
    ]

    assert [response.status_code for response in responses] == [403, 403, 403]


def test_jwt_role_claim_cannot_elevate_server_side_agent(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-known"))
    token = _seed_account(
        context,
        account_id="agent-with-admin-claim",
        role="agent",
        tenant_id="agency-known",
        token_role="platform_admin",
    )

    response = context.client.get("/api/v1/agencies", headers=_headers(token))

    assert response.status_code == 403


@pytest.mark.parametrize(
    ("first_role", "first_tenant", "duplicate_role", "duplicate_tenant"),
    [
        ("platform_admin", None, "agency_admin", "agency-one"),
        ("agency_admin", "agency-one", "agent", "agency-two"),
    ],
)
def test_database_rejects_normalized_pending_invites_across_roles_and_agencies(
    agency_api_context: AgencyApiContext,
    first_role: str,
    first_tenant: str | None,
    duplicate_role: str,
    duplicate_tenant: str,
) -> None:
    context = agency_api_context
    with pytest.raises(IntegrityError):
        with context.session_factory.begin() as session:
            session.add_all([Agency(id="agency-one"), Agency(id="agency-two")])
            session.add(
                StaffInvitation(
                    email="duplicate@example.test",
                    role=first_role,
                    tenant_id=first_tenant,
                    token_hash=hash_secret("first-pending-token"),
                    status="pending",
                    issued_at=context.now,
                    expires_at=context.now + timedelta(hours=1),
                )
            )
            session.flush()
            session.add(
                StaffInvitation(
                    email="  DUPLICATE@Example.Test ",
                    role=duplicate_role,
                    tenant_id=duplicate_tenant,
                    token_hash=hash_secret("second-pending-token"),
                    status="pending",
                    issued_at=context.now,
                    expires_at=context.now + timedelta(hours=1),
                )
            )
            session.flush()


def test_api_maps_simulated_pending_email_unique_race_to_409(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    token = _platform_admin_token(context)
    with context.session_factory.begin() as session:
        session.add_all([Agency(id="agency-one"), Agency(id="agency-two")])

    injected = False

    def insert_competing_invitation(mapper: Any, connection: Any, target: StaffInvitation) -> None:
        nonlocal injected
        if injected or target.role != "agency_admin":
            return
        injected = True
        connection.execute(
            insert(cast(Table, StaffInvitation.__table__)).values(
                id="racing-invitation",
                email="ADMIN@example.test",
                role="agent",
                tenant_id="agency-two",
                token_hash=hash_secret("racing-token"),
                status="pending",
                issued_at=context.now,
                expires_at=context.now + timedelta(hours=1),
            )
        )

    event.listen(StaffInvitation, "before_insert", insert_competing_invitation)
    try:
        response = context.client.post(
            "/api/v1/agencies/agency-one/admin-invitations",
            json={"email": "admin@example.test"},
            headers=_headers(token),
        )
    finally:
        event.remove(StaffInvitation, "before_insert", insert_competing_invitation)

    assert injected
    assert response.status_code == 409
    assert response.json() == {
        "detail": "An account or active invitation already uses this email",
        "code": "conflict",
    }
    assert context.email_sender.messages == []


def test_api_does_not_map_an_unrelated_unique_conflict_to_409(
    agency_api_context: AgencyApiContext,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import app.modules.identity.invitations as invitation_service

    context = agency_api_context
    token = _platform_admin_token(context)
    with context.session_factory.begin() as session:
        session.add_all([Agency(id="agency-one"), Agency(id="agency-two")])
    monkeypatch.setattr(invitation_service, "random_token", lambda: "forced-token")

    injected = False

    def insert_token_collision(mapper: Any, connection: Any, target: StaffInvitation) -> None:
        nonlocal injected
        if injected or target.role != "agency_admin":
            return
        injected = True
        connection.execute(
            insert(cast(Table, StaffInvitation.__table__)).values(
                id="unrelated-unique-race",
                email="another@example.test",
                role="agent",
                tenant_id="agency-two",
                token_hash=hash_secret("forced-token"),
                status="pending",
                issued_at=context.now,
                expires_at=context.now + timedelta(hours=1),
            )
        )

    event.listen(StaffInvitation, "before_insert", insert_token_collision)
    try:
        with pytest.raises(IntegrityError):
            context.client.post(
                "/api/v1/agencies/agency-one/admin-invitations",
                json={"email": "admin@example.test"},
                headers=_headers(token),
            )
    finally:
        event.remove(StaffInvitation, "before_insert", insert_token_collision)

    assert injected
    assert context.email_sender.messages == []


def test_admin_invitation_is_tenant_scoped_and_raw_token_is_only_delivered_by_email(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    token = _platform_admin_token(context)
    context.client.app.state.settings = replace(
        context.settings, email_send_timeout_seconds=13
    )
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-one"))

    response = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": "  ADMIN@Example.Test  "},
        headers=_headers(token),
    )

    assert response.status_code == 201
    assert response.json() == {"status": "sent"}
    assert len(context.email_sender.messages) == 1
    assert context.email_sender.timeouts == [13]
    sent_email, invite_link, _ = context.email_sender.messages[0]
    raw_token = urlsplit(invite_link).path.rsplit("/", 1)[-1]
    assert sent_email == "admin@example.test"
    assert raw_token
    assert raw_token not in response.text
    with context.session_factory() as session:
        invitation = session.query(StaffInvitation).one()
        assert invitation.email == "admin@example.test"
        assert invitation.role == "agency_admin"
        assert invitation.tenant_id == "agency-one"
        assert invitation.status == "pending"
        assert invitation.delivery_status == "sent"
        assert invitation.token_hash == hash_secret(raw_token)
        assert raw_token not in invitation.token_hash


def test_unknown_agency_returns_404_and_invalid_invite_email_returns_422(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    headers = _headers(_platform_admin_token(context))

    unknown = context.client.post(
        "/api/v1/agencies/missing/admin-invitations",
        json={"email": "staff@example.test"},
        headers=headers,
    )
    invalid_email = context.client.post(
        "/api/v1/agencies/missing/admin-invitations",
        json={"email": "not-an-email"},
        headers=headers,
    )

    assert unknown.status_code == 404
    assert invalid_email.status_code == 422


def test_failed_invitation_delivery_revokes_and_never_returns_token(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    context.email_sender.fail = True
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-one"))

    response = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": "admin@example.test"},
        headers=_headers(_platform_admin_token(context)),
    )

    assert response.status_code == 502
    assert response.json() == {
        "detail": "A required dependency is unavailable",
        "code": "dependency_unavailable",
    }
    assert "token" not in response.text.lower()
    with context.session_factory() as session:
        invitation = session.query(StaffInvitation).one()
        assert invitation.status == "revoked"
        assert invitation.delivery_status == "failed"
        assert session.query(StaffAccount).count() == 1


@pytest.mark.parametrize("role", ["platform_admin", "agency_admin", "agent"])
def test_existing_staff_account_email_blocks_agency_admin_invitation_globally(
    agency_api_context: AgencyApiContext, role: str
) -> None:
    context = agency_api_context
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-one"))
        session.add(Agency(id="agency-two"))
    if role == "platform_admin":
        platform_token = _platform_admin_token(context, email="used@example.test")
    else:
        _seed_account(
            context,
            account_id=f"existing-{role}",
            email="used@example.test",
            role=role,
            tenant_id="agency-two",
        )
        platform_token = _platform_admin_token(context)

    response = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": "  USED@Example.Test "},
        headers=_headers(platform_token),
    )

    assert response.status_code == 409
    assert context.email_sender.messages == []
    with context.session_factory() as session:
        assert session.query(StaffInvitation).count() == 0


@pytest.mark.parametrize(
    ("role", "tenant_id"),
    [("platform_admin", None), ("agency_admin", "agency-two"), ("agent", "agency-two")],
)
def test_unexpired_pending_invitation_blocks_agency_admin_invite_across_roles_and_agencies(
    agency_api_context: AgencyApiContext, role: str, tenant_id: str | None
) -> None:
    context = agency_api_context
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-one"))
    _seed_invitation(
        context,
        email="staff@example.test",
        role=role,
        tenant_id=tenant_id,
        token=f"pending-{role}",
        expires_at=context.now + timedelta(minutes=1),
    )

    response = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": " STAFF@Example.Test "},
        headers=_headers(_platform_admin_token(context)),
    )

    assert response.status_code == 409
    assert context.email_sender.messages == []
    with context.session_factory() as session:
        assert session.query(StaffInvitation).count() == 1


def test_platform_admin_bootstrap_rejects_cross_role_pending_email_conflict(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _seed_invitation(
        context,
        email="owner@example.test",
        role="agency_admin",
        tenant_id="agency-one",
        token="agency-admin-invitation-token",
        expires_at=context.now + timedelta(minutes=1),
    )

    with pytest.raises(RuntimeError, match="active invitation"):
        issue_platform_admin_invitation(
            session_factory=context.session_factory,
            email_sender=context.email_sender,
            email="  OWNER@Example.Test ",
            settings=context.settings,
            clock=lambda: context.now,
        )

    assert context.email_sender.messages == []
    with context.session_factory() as session:
        invitation = session.query(StaffInvitation).one()
        assert invitation.status == "pending"
        assert invitation.role == "agency_admin"


def test_platform_admin_bootstrap_rejects_existing_account_and_uses_email_lock(
    agency_api_context: AgencyApiContext,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import app.modules.identity.bootstrap as bootstrap

    context = agency_api_context
    _seed_account(
        context,
        account_id="existing-agency-admin",
        email="owner@example.test",
        role="agency_admin",
        tenant_id="agency-one",
    )
    lock_calls: list[str] = []
    lock_guard = getattr(bootstrap, "lock_normalized_email", None)

    def record_lock(session: Any, email: str) -> Any:
        lock_calls.append(email.strip().lower())
        return lock_guard(session, email) if lock_guard is not None else None

    monkeypatch.setattr(bootstrap, "lock_normalized_email", record_lock, raising=False)

    with pytest.raises(RuntimeError, match="account or active invitation"):
        issue_platform_admin_invitation(
            session_factory=context.session_factory,
            email_sender=context.email_sender,
            email=" OWNER@Example.Test ",
            settings=context.settings,
            clock=lambda: context.now,
        )

    assert lock_calls == ["owner@example.test"]
    assert context.email_sender.messages == []


def test_totp_lockout_keeps_agency_email_reserved_until_challenge_expiry(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-one"))
    platform_token = _platform_admin_token(context)
    issued = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": "lockout@example.test"},
        headers=_headers(platform_token),
    )
    assert issued.status_code == 201
    invite_token = urlsplit(context.email_sender.messages[0][1]).path.rsplit("/", 1)[-1]
    accepted = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": invite_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    assert accepted.status_code == 200
    enrollment = accepted.json()
    valid_code = totp_code(enrollment["totp_secret"], context.now)
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

    still_reserved = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": "LOCKOUT@Example.Test"},
        headers=_headers(platform_token),
    )
    assert still_reserved.status_code == 409

    with context.session_factory.begin() as session:
        challenge = session.query(StaffEnrollmentChallenge).one()
        challenge.expires_at = context.now - timedelta(seconds=1)
    after_expiry = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": "LOCKOUT@Example.Test"},
        headers=_headers(platform_token),
    )

    assert after_expiry.status_code == 201
    assert len(context.email_sender.messages) == 2


def test_active_totp_enrollment_claim_blocks_invite_across_agencies(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-one"))
    _seed_enrollment_claim(
        context,
        email="reserved@example.test",
        tenant_id="agency-two",
        challenge_expires_at=context.now + timedelta(minutes=5),
    )

    response = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": " RESERVED@Example.Test "},
        headers=_headers(_platform_admin_token(context)),
    )

    assert response.status_code == 409
    with pytest.raises(RuntimeError, match="active invitation/enrollment"):
        issue_platform_admin_invitation(
            session_factory=context.session_factory,
            email_sender=context.email_sender,
            email="reserved@example.test",
            settings=context.settings,
            clock=lambda: context.now,
        )
    assert context.email_sender.messages == []


def test_expired_totp_enrollment_claim_allows_new_invite(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-one"))
    _seed_enrollment_claim(
        context,
        email="expired-enrollment@example.test",
        tenant_id="agency-two",
        challenge_expires_at=context.now - timedelta(seconds=1),
    )

    response = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": " EXPIRED-ENROLLMENT@Example.Test "},
        headers=_headers(_platform_admin_token(context)),
    )

    assert response.status_code == 201
    assert len(context.email_sender.messages) == 1
    with context.session_factory() as session:
        assert session.query(StaffInvitation).filter_by(status="pending").one().email == (
            "expired-enrollment@example.test"
        )


def test_email_lock_uses_postgres_transaction_advisory_lock_only() -> None:
    from app.modules.identity.invitations import lock_normalized_email

    class LockSession:
        def __init__(self, dialect_name: str) -> None:
            self.dialect_name = dialect_name
            self.executed: list[tuple[str, dict[str, int]]] = []

        def get_bind(self) -> Any:
            return type(
                "Bind",
                (),
                {"dialect": type("Dialect", (), {"name": self.dialect_name})()},
            )()

        def execute(self, statement: Any, parameters: dict[str, int]) -> None:
            self.executed.append((str(statement), parameters))

    postgres_session = LockSession("postgresql")
    first_lock = lock_normalized_email(
        cast(Session, postgres_session), " Owner@Example.Test "
    )
    second_lock = lock_normalized_email(
        cast(Session, postgres_session), "owner@example.test"
    )

    assert first_lock == second_lock
    assert len(postgres_session.executed) == 2
    assert all(
        "pg_advisory_xact_lock" in statement
        for statement, _ in postgres_session.executed
    )
    assert all(
        parameters["lock_key"] == first_lock
        for _, parameters in postgres_session.executed
    )

    sqlite_session = LockSession("sqlite")
    assert lock_normalized_email(
        cast(Session, sqlite_session), "owner@example.test"
    ) is None
    assert sqlite_session.executed == []


def test_expired_pending_invitation_is_marked_expired_and_reissued(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-one"))
    _seed_invitation(
        context,
        email="staff@example.test",
        role="agency_admin",
        tenant_id="agency-two",
        token="expired-invitation-token",
        expires_at=context.now - timedelta(seconds=1),
    )

    response = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": " STAFF@Example.Test "},
        headers=_headers(_platform_admin_token(context)),
    )

    assert response.status_code == 201
    assert len(context.email_sender.messages) == 1
    with context.session_factory() as session:
        invitations = session.query(StaffInvitation).order_by(StaffInvitation.issued_at).all()
        assert [invitation.status for invitation in invitations] == ["expired", "pending"]
        assert invitations[0].email == invitations[1].email == "staff@example.test"
        assert [invitation.tenant_id for invitation in invitations] == [
            "agency-two",
            "agency-one",
        ]


def test_totp_completion_rechecks_email_claim_after_shared_lock(
    agency_api_context: AgencyApiContext,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import app.modules.identity.router as identity_router

    context = agency_api_context
    token = _platform_admin_token(context)
    with context.session_factory.begin() as session:
        session.add_all([Agency(id="agency-one"), Agency(id="agency-two")])
    issued = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": "racing@example.test"},
        headers=_headers(token),
    )
    assert issued.status_code == 201
    invite_token = urlsplit(context.email_sender.messages[0][1]).path.rsplit("/", 1)[-1]
    accepted = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": invite_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
        },
    )
    assert accepted.status_code == 200
    enrollment = accepted.json()

    lock_guard = identity_router.lock_normalized_email
    injected = False

    def insert_competing_invitation(session: Any, email: str) -> Any:
        nonlocal injected
        if not injected:
            session.add(
                StaffInvitation(
                    email="RACING@example.test",
                    role="agent",
                    tenant_id="agency-two",
                    token_hash=hash_secret("cross-flow-racing-invitation"),
                    status="pending",
                    issued_at=context.now,
                    expires_at=context.now + timedelta(hours=1),
                )
            )
            session.flush()
            injected = True
        return lock_guard(session, email)

    monkeypatch.setattr(
        identity_router, "lock_normalized_email", insert_competing_invitation
    )
    rejected = context.client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={
            "enrollment_token": enrollment["enrollment_token"],
            "code": totp_code(enrollment["totp_secret"], context.now),
        },
    )

    assert injected
    assert rejected.status_code == 401
    with context.session_factory() as session:
        assert (
            session.query(StaffAccount)
            .filter_by(email="racing@example.test")
            .count()
            == 0
        )
        challenge = session.query(StaffEnrollmentChallenge).one()
        assert challenge.consumed_at is not None
        assert challenge.consumed_at.replace(tzinfo=timezone.utc) == context.now
        pending = session.query(StaffInvitation).filter_by(status="pending").one()
        assert pending.role == "agent"


def test_agency_admin_invitation_acceptance_and_totp_use_stored_role_and_tenant(
    agency_api_context: AgencyApiContext,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import app.modules.identity.invitations as invitation_service
    import app.modules.identity.router as identity_router

    context = agency_api_context
    lock_calls: list[str] = []
    invitation_lock = getattr(invitation_service, "lock_normalized_email", None)
    identity_lock = getattr(identity_router, "lock_normalized_email", None)

    def record_invitation_lock(session: Any, email: str) -> Any:
        lock_calls.append(email.strip().lower())
        return invitation_lock(session, email) if invitation_lock is not None else None

    def record_identity_lock(session: Any, email: str) -> Any:
        lock_calls.append(email.strip().lower())
        return identity_lock(session, email) if identity_lock is not None else None

    monkeypatch.setattr(
        invitation_service,
        "lock_normalized_email",
        record_invitation_lock,
        raising=False,
    )
    monkeypatch.setattr(
        identity_router,
        "lock_normalized_email",
        record_identity_lock,
        raising=False,
    )
    token = _platform_admin_token(context)
    with context.session_factory.begin() as session:
        session.add(Agency(id="agency-one"))
    issued = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": "admin@example.test"},
        headers=_headers(token),
    )
    assert issued.status_code == 201
    invite_token = urlsplit(context.email_sender.messages[0][1]).path.rsplit("/", 1)[-1]

    acceptance = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": invite_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
            "role": "platform_admin",
            "tenant_id": "attacker-controlled-agency",
        },
    )
    assert issued.status_code == 201
    assert acceptance.status_code == 200
    enrollment = acceptance.json()
    assert enrollment["enrollment_token"]
    assert "access_token" not in enrollment

    verified = context.client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={
            "enrollment_token": enrollment["enrollment_token"],
            "code": totp_code(enrollment["totp_secret"], context.now),
            "role": "platform_admin",
            "tenant_id": "attacker-controlled-agency",
        },
    )

    assert verified.status_code == 200
    assert verified.json()["account"]["role"] == "agency_admin"
    assert verified.json()["account"]["tenant_id"] == "agency-one"
    assert lock_calls == ["admin@example.test"] * 3
    reinvite = context.client.post(
        "/api/v1/agencies/agency-one/admin-invitations",
        json={"email": " ADMIN@Example.Test "},
        headers=_headers(token),
    )
    assert reinvite.status_code == 409
    with context.session_factory() as session:
        account = session.query(StaffAccount).filter_by(email="admin@example.test").one()
        assert account.role == "agency_admin"
        assert account.tenant_id == "agency-one"


def test_agency_admin_can_invite_agent_with_server_derived_role_and_tenant(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin_token = _seed_account(
        context,
        account_id="agency-admin-one",
        role="agency_admin",
        tenant_id="agency-one",
    )
    headers = _headers(admin_token)

    issued = context.client.post(
        "/api/v1/agencies/agent-invitations",
        json={"email": "  AGENT@Example.Test  "},
        headers=headers,
    )

    assert issued.status_code == 201
    assert issued.json() == {"status": "sent"}
    assert len(context.email_sender.messages) == 1
    email, invitation_link, _ = context.email_sender.messages[0]
    invitation_token = urlsplit(invitation_link).path.rsplit("/", 1)[-1]
    assert email == "agent@example.test"
    assert invitation_token not in issued.text
    with context.session_factory() as session:
        invitation = session.query(StaffInvitation).one()
        assert invitation.email == email
        assert invitation.role == "agent"
        assert invitation.tenant_id == "agency-one"
        assert invitation.status == "pending"
        assert invitation.token_hash == hash_secret(invitation_token)

    accepted = context.client.post(
        "/api/v1/auth/invitations/accept",
        json={
            "token": invitation_token,
            "password": "Initial-Password-42!",
            "password_confirmation": "Initial-Password-42!",
            "role": "platform_admin",
            "tenant_id": "attacker-controlled-agency",
        },
    )
    assert accepted.status_code == 200
    enrollment = accepted.json()
    verified = context.client.post(
        "/api/v1/auth/totp/enroll/verify",
        json={
            "enrollment_token": enrollment["enrollment_token"],
            "code": totp_code(enrollment["totp_secret"], context.now),
            "role": "platform_admin",
            "tenant_id": "attacker-controlled-agency",
        },
    )

    assert verified.status_code == 200
    assert verified.json()["account"]["role"] == "agent"
    assert verified.json()["account"]["tenant_id"] == "agency-one"
    override = context.client.post(
        "/api/v1/agencies/agent-invitations",
        json={
            "email": "override@example.test",
            "role": "agency_admin",
            "tenant_id": "agency-two",
        },
        headers=headers,
    )
    assert override.status_code == 422
    with context.session_factory() as session:
        assert session.query(StaffInvitation).count() == 1
        account = session.query(StaffAccount).filter_by(email=email).one()
        assert account.role == "agent"
        assert account.tenant_id == "agency-one"


def test_agent_invitation_obeys_global_normalized_email_claims(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin_token = _seed_account(
        context,
        account_id="agency-admin-one",
        role="agency_admin",
        tenant_id="agency-one",
    )
    _seed_account(
        context,
        account_id="existing-agent-two",
        email="claimed@example.test",
        role="agent",
        tenant_id="agency-two",
    )

    response = context.client.post(
        "/api/v1/agencies/agent-invitations",
        json={"email": "  CLAIMED@Example.Test "},
        headers=_headers(admin_token),
    )

    assert response.status_code == 409
    assert response.json() == {
        "detail": "An account or active invitation already uses this email",
        "code": "conflict",
    }
    assert context.email_sender.messages == []
    with context.session_factory() as session:
        assert session.query(StaffInvitation).count() == 0


def test_agency_admin_lists_only_agents_in_its_own_agency(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin_token = _seed_account(
        context,
        account_id="agency-admin-one",
        role="agency_admin",
        tenant_id="agency-one",
    )
    _seed_account(
        context,
        account_id="agent-active",
        role="agent",
        tenant_id="agency-one",
    )
    _seed_account(
        context,
        account_id="agent-inactive",
        role="agent",
        tenant_id="agency-one",
        active=False,
    )
    _seed_account(
        context,
        account_id="agency-admin-two",
        role="agency_admin",
        tenant_id="agency-one",
    )
    _seed_account(
        context,
        account_id="agent-other-agency",
        role="agent",
        tenant_id="agency-two",
    )

    response = context.client.get(
        "/api/v1/agencies/agents?limit=1&offset=1",
        headers=_headers(admin_token),
    )

    assert response.status_code == 200
    assert response.json() == {
        "agents": [{
            "id": "agent-inactive",
            "email": "agent-inactive@example.test",
            "active": False,
        }],
        "pagination": {"limit": 1, "offset": 1, "total": 2},
    }


def test_agent_deactivation_revokes_sessions_and_reactivation_requires_fresh_login(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin_token = _seed_account(
        context,
        account_id="agency-admin-one",
        role="agency_admin",
        tenant_id="agency-one",
    )
    agent_token = _seed_account(
        context,
        account_id="agent-to-deactivate",
        role="agent",
        tenant_id="agency-one",
    )
    with context.session_factory.begin() as session:
        session.add(
            StaffSession(
                id="second-agent-session",
                user_id="agent-to-deactivate",
                refresh_hash="second-agent-refresh",
                csrf_hash="second-agent-csrf",
                created_at=context.now,
                last_activity_at=context.now,
                expires_at=context.now + timedelta(hours=1),
            )
        )

    deactivated = context.client.post(
        "/api/v1/agencies/agents/agent-to-deactivate/deactivate",
        headers=_headers(admin_token),
    )

    assert deactivated.status_code == 200
    assert deactivated.json() == {"status": "deactivated"}
    assert context.client.get(
        "/api/v1/auth/me", headers=_headers(agent_token)
    ).status_code == 401
    with context.session_factory() as session:
        agent = session.get(StaffAccount, "agent-to-deactivate")
        sessions = (
            session.query(StaffSession)
            .filter_by(user_id="agent-to-deactivate")
            .order_by(StaffSession.id)
            .all()
        )
        assert agent is not None
        assert agent.active is False
        assert len(sessions) == 2
        assert all(item.revoked_at is not None for item in sessions)

    reactivated = context.client.post(
        "/api/v1/agencies/agents/agent-to-deactivate/activate",
        headers=_headers(admin_token),
    )

    assert reactivated.status_code == 200
    assert reactivated.json() == {"status": "activated"}
    assert context.client.get(
        "/api/v1/auth/me", headers=_headers(agent_token)
    ).status_code == 401
    with context.session_factory() as session:
        agent = session.get(StaffAccount, "agent-to-deactivate")
        sessions = session.query(StaffSession).filter_by(
            user_id="agent-to-deactivate"
        ).all()
        assert agent is not None
        assert agent.active is True
        assert len(sessions) == 2
        assert all(item.revoked_at is not None for item in sessions)


def test_agents_cannot_manage_memberships_and_admins_cannot_change_other_accounts(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin_token = _seed_account(
        context,
        account_id="agency-admin-one",
        role="agency_admin",
        tenant_id="agency-one",
    )
    agent_token = _seed_account(
        context,
        account_id="agent-one",
        role="agent",
        tenant_id="agency-one",
    )
    _seed_account(
        context,
        account_id="agency-admin-target",
        role="agency_admin",
        tenant_id="agency-one",
    )
    _seed_account(
        context,
        account_id="agent-two",
        role="agent",
        tenant_id="agency-two",
    )

    agent_responses = [
        context.client.get("/api/v1/agencies/agents", headers=_headers(agent_token)),
        context.client.post(
            "/api/v1/agencies/agent-invitations",
            json={"email": "new-agent@example.test"},
            headers=_headers(agent_token),
        ),
        context.client.post(
            "/api/v1/agencies/agents/agent-one/deactivate",
            headers=_headers(agent_token),
        ),
    ]
    admin_responses = [
        context.client.post(
            "/api/v1/agencies/agents/agent-two/deactivate",
            headers=_headers(admin_token),
        ),
        context.client.post(
            "/api/v1/agencies/agents/agency-admin-target/deactivate",
            headers=_headers(admin_token),
        ),
    ]

    assert [response.status_code for response in agent_responses] == [403, 403, 403]
    assert [response.status_code for response in admin_responses] == [404, 404]
    with context.session_factory() as session:
        agent_one = session.get(StaffAccount, "agent-one")
        agent_two = session.get(StaffAccount, "agent-two")
        agency_admin_target = session.get(StaffAccount, "agency-admin-target")
        assert agent_one is not None
        assert agent_two is not None
        assert agency_admin_target is not None
        assert agent_one.active is True
        assert agent_two.active is True
        assert agency_admin_target.active is True
    assert context.email_sender.messages == []
