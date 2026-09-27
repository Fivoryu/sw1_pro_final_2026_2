from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

import jwt
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.core.security import create_access_token, hash_secret, verify_password
from app.db.base import Base
from app.main import create_app


@dataclass
class FrozenClock:
    now: datetime

    def __call__(self) -> datetime:
        return self.now

    def advance(self, delta: timedelta) -> None:
        self.now += delta


@dataclass
class CustomerIdentityContext:
    client: TestClient
    session_factory: sessionmaker[Session]
    clock: FrozenClock
    settings: Settings


@pytest.fixture

def customer_identity_context() -> Any:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    clock = FrozenClock(datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc))
    settings = Settings(
        database_url="sqlite+pysqlite:///:memory:",
        jwt_secret="test-jwt-secret-at-least-32-bytes-long",
        totp_encryption_key=base64.urlsafe_b64encode(b"x" * 32).decode("ascii"),
        web_origin="https://panel.example.test",
    )
    app = create_app(settings=settings, session_factory=session_factory, clock=clock)
    with TestClient(app, base_url="https://testserver") as client:
        yield CustomerIdentityContext(client, session_factory, clock, settings)
    engine.dispose()


def _register(
    context: CustomerIdentityContext,
    *,
    email: str = "customer@example.test",
    password: str = "password",
):
    return context.client.post(
        "/api/v1/customer/auth/register",
        json={"email": email, "password": password},
    )


def _error_code(response: Any) -> str:
    return response.json()["error"]["code"]


def test_customer_registration_returns_minimal_account_and_allows_immediate_login(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    password = "password"

    response = _register(
        context,
        email="  Customer@Example.Test ",
        password=password,
    )

    assert response.status_code == 201
    account = response.json()
    assert set(account) == {"id", "email"}
    UUID(account["id"])
    assert account["email"] == "customer@example.test"
    assert password not in response.text
    assert "correo_verificado" not in account
    assert "estado" not in account

    with context.session_factory() as session:
        saved = session.execute(
            text("SELECT email, password_hash FROM customer_account")
        ).mappings().one()
        assert saved["email"] == "customer@example.test"
        assert saved["password_hash"] != password
        assert verify_password(saved["password_hash"], password)
        assert session.execute(text("SELECT count(*) FROM staff_account")).scalar_one() == 0
        assert session.execute(text("SELECT count(*) FROM customer_session")).scalar_one() == 0

    login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": password},
    )
    assert login.status_code == 200
    assert set(login.json()) == {
        "access_token",
        "refresh_token",
        "token_type",
        "access_expires_in",
    }


def test_customer_registration_validates_and_enforces_case_insensitive_uniqueness(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context

    invalid_email = _register(context, email="not-an-email")
    assert invalid_email.status_code == 422
    assert _error_code(invalid_email) == "validation_error"
    short_password = _register(context, password="short")
    assert short_password.status_code == 422
    assert _error_code(short_password) == "validation_error"
    assert _register(context, email="customer@example.test").status_code == 201

    duplicate = _register(context, email="  CUSTOMER@EXAMPLE.TEST ")

    assert duplicate.status_code == 409
    assert _error_code(duplicate) == "account_conflict"
    assert "detail" not in duplicate.json()
    with context.session_factory() as session:
        assert session.execute(text("SELECT count(*) FROM customer_account")).scalar_one() == 1


def test_customer_login_refresh_logout_and_me_obey_the_approved_wire_contract(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    password = "password"
    registered = _register(context, password=password)
    customer_id = registered.json()["id"]

    login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": " CUSTOMER@EXAMPLE.TEST ", "password": password},
    )

    assert login.status_code == 200
    original = login.json()
    assert set(original) == {
        "access_token",
        "refresh_token",
        "token_type",
        "access_expires_in",
    }
    assert original["token_type"] == "Bearer"
    assert original["access_expires_in"] == 900
    claims = jwt.decode(
        original["access_token"],
        context.settings.jwt_secret,
        algorithms=["HS256"],
        audience="roomforge-customer",
        options={"verify_exp": False, "verify_iat": False},
    )
    assert claims["sub"] == customer_id
    assert claims["aud"] == "roomforge-customer"
    assert claims["type"] == "access"
    assert claims["exp"] - claims["iat"] == 15 * 60

    with context.session_factory() as session:
        saved_session = session.execute(
            text(
                "SELECT id, refresh_token_hash, expires_at, last_activity_at, revoked_at "
                "FROM customer_session"
            )
        ).mappings().one()
        assert saved_session["refresh_token_hash"] == hash_secret(original["refresh_token"])
        assert original["refresh_token"] not in saved_session["refresh_token_hash"]
        assert saved_session["revoked_at"] is None
        assert datetime.fromisoformat(saved_session["last_activity_at"]) == (
            context.clock().replace(tzinfo=None)
        )
        assert datetime.fromisoformat(saved_session["expires_at"]) == (
            context.clock() + timedelta(days=7)
        ).replace(tzinfo=None)

    me = context.client.get(
        "/api/v1/customer/auth/me",
        headers={"Authorization": f"Bearer {original['access_token']}"},
    )
    assert me.status_code == 200
    assert me.json() == {"id": customer_id, "email": "customer@example.test"}

    staff_me = context.client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {original['access_token']}"},
    )
    assert staff_me.status_code == 401

    context.clock.advance(timedelta(seconds=1))
    refresh = context.client.post(
        "/api/v1/customer/auth/refresh",
        json={"refresh_token": original["refresh_token"]},
    )
    assert refresh.status_code == 200
    rotated = refresh.json()
    assert set(rotated) == set(original)
    assert rotated["token_type"] == "Bearer"
    assert rotated["access_expires_in"] == 900
    assert rotated["refresh_token"] != original["refresh_token"]

    with context.session_factory() as session:
        saved_sessions = session.execute(
            text(
                "SELECT refresh_token_hash, expires_at, revoked_at "
                "FROM customer_session ORDER BY created_at, id"
            )
        ).mappings().all()
        old_session = next(
            item
            for item in saved_sessions
            if item["refresh_token_hash"] == hash_secret(original["refresh_token"])
        )
        new_session = next(
            item
            for item in saved_sessions
            if item["refresh_token_hash"] == hash_secret(rotated["refresh_token"])
        )
        assert old_session["revoked_at"] is not None
        assert new_session["revoked_at"] is None
        assert datetime.fromisoformat(new_session["expires_at"]) == (
            context.clock() + timedelta(days=7)
        ).replace(tzinfo=None)

    reused = context.client.post(
        "/api/v1/customer/auth/refresh",
        json={"refresh_token": original["refresh_token"]},
    )
    assert reused.status_code == 401
    assert _error_code(reused) == "invalid_session"
    assert context.client.get(
        "/api/v1/customer/auth/me",
        headers={"Authorization": f"Bearer {original['access_token']}"},
    ).status_code == 401
    assert context.client.get(
        "/api/v1/customer/auth/me",
        headers={"Authorization": f"Bearer {rotated['access_token']}"},
    ).status_code == 200

    logout = context.client.post(
        "/api/v1/customer/auth/logout",
        json={"refresh_token": rotated["refresh_token"]},
    )
    assert logout.status_code == 204
    assert logout.content == b""
    assert context.client.get(
        "/api/v1/customer/auth/me",
        headers={"Authorization": f"Bearer {rotated['access_token']}"},
    ).status_code == 401
    assert context.client.post(
        "/api/v1/customer/auth/logout",
        json={"refresh_token": "unknown-but-valid-format"},
    ).status_code == 204


def test_customer_rejects_invalid_credentials_with_one_generic_error(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    assert _register(context).status_code == 201

    unknown = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "unknown@example.test", "password": "password"},
    )
    wrong_password = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": "incorrect"},
    )

    assert unknown.status_code == wrong_password.status_code == 401
    assert unknown.json() == wrong_password.json() == {
        "error": {"code": "invalid_credentials"}
    }
    with context.session_factory() as session:
        assert session.execute(text("SELECT count(*) FROM customer_session")).scalar_one() == 0


def test_customer_refresh_allows_exact_idle_boundary_and_rejects_after_it(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    assert _register(context).status_code == 201
    login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": "password"},
    )
    assert login.status_code == 200

    context.clock.advance(timedelta(minutes=30))
    at_boundary = context.client.post(
        "/api/v1/customer/auth/refresh",
        json={"refresh_token": login.json()["refresh_token"]},
    )
    assert at_boundary.status_code == 200

    context.clock.advance(timedelta(minutes=30, seconds=1))
    after_boundary = context.client.post(
        "/api/v1/customer/auth/refresh",
        json={"refresh_token": at_boundary.json()["refresh_token"]},
    )
    assert after_boundary.status_code == 401
    assert after_boundary.json() == {"error": {"code": "invalid_session"}}


def test_customer_me_slides_idle_window_for_refresh(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    assert _register(context).status_code == 201
    login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": "password"},
    )
    assert login.status_code == 200
    original_tokens = login.json()

    context.clock.advance(timedelta(minutes=14))
    me = context.client.get(
        "/api/v1/customer/auth/me",
        headers={"Authorization": f"Bearer {original_tokens['access_token']}"},
    )
    assert me.status_code == 200

    with context.session_factory() as session:
        last_activity_at = session.execute(
            text(
                "SELECT last_activity_at FROM customer_session "
                "WHERE refresh_token_hash = :refresh_hash"
            ),
            {"refresh_hash": hash_secret(original_tokens["refresh_token"])},
        ).scalar_one()
    assert datetime.fromisoformat(last_activity_at) == context.clock().replace(tzinfo=None)

    context.clock.advance(timedelta(minutes=17))
    refresh = context.client.post(
        "/api/v1/customer/auth/refresh",
        json={"refresh_token": original_tokens["refresh_token"]},
    )

    assert refresh.status_code == 200
    assert refresh.json()["refresh_token"] != original_tokens["refresh_token"]


def test_customer_and_staff_route_namespaces_and_dependencies_remain_separate(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    paths = context.client.get("/openapi.json").json()["paths"]

    assert "/api/v1/auth/login" in paths
    assert "/api/v1/auth/me" in paths
    assert "/api/v1/auth/register" not in paths
    assert "/api/v1/customer/auth/register" in paths
    assert "/api/v1/customer/auth/login" in paths
    assert "/api/v1/customer/auth/refresh" in paths
    assert "/api/v1/customer/auth/logout" in paths
    assert "/api/v1/customer/auth/me" in paths
    assert "/api/v1/customer/auth/session" not in paths

    customer_token = create_access_token(
        user_id="customer-id",
        session_id="customer-session-id",
        signing_key=context.settings.jwt_secret,
        now=context.clock(),
        lifetime_minutes=15,
    )
    customer_me = context.client.get(
        "/api/v1/customer/auth/me",
        headers={"Authorization": f"Bearer {customer_token}"},
    )
    assert customer_me.status_code == 401
    assert customer_me.json() == {"error": {"code": "invalid_session"}}


def test_customer_me_requires_customer_bearer_session(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    response = customer_identity_context.client.get("/api/v1/customer/auth/me")

    assert response.status_code == 401
    assert response.json() == {"error": {"code": "invalid_session"}}


def test_customer_openapi_documents_error_envelopes_and_email_format(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    openapi = customer_identity_context.client.get("/openapi.json").json()
    paths = openapi["paths"]
    schemas = openapi["components"]["schemas"]

    expected_errors = {
        "/api/v1/customer/auth/register": {"409", "422"},
        "/api/v1/customer/auth/login": {"401", "422"},
        "/api/v1/customer/auth/refresh": {"401", "422"},
        "/api/v1/customer/auth/logout": {"422"},
        "/api/v1/customer/auth/me": {"401"},
    }
    for path, statuses in expected_errors.items():
        method = "get" if path.endswith("/me") else "post"
        responses = paths[path][method]["responses"]
        for status_code in statuses:
            assert status_code in responses
            response_schema = responses[status_code]["content"]["application/json"]["schema"]
            assert response_schema["$ref"].endswith("/CustomerErrorResponse")

    error_response = schemas["CustomerErrorResponse"]
    assert error_response["required"] == ["error"]
    error_detail_ref = error_response["properties"]["error"]["$ref"].rsplit("/", 1)[-1]
    error_detail = schemas[error_detail_ref]
    assert "code" in error_detail["required"]
    assert "fields" in error_detail["properties"]
    assert "fields" not in error_detail["required"]

    for path in ("/api/v1/customer/auth/register", "/api/v1/customer/auth/login"):
        request_schema = paths[path]["post"]["requestBody"]["content"]["application/json"]["schema"]
        request_model_ref = request_schema["$ref"].rsplit("/", 1)[-1]
        assert schemas[request_model_ref]["properties"]["email"]["format"] == "email"
