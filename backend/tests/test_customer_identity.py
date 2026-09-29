from __future__ import annotations

import base64
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

import jwt
import pytest
from eth_account import Account
from eth_account.messages import encode_defunct
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.core.security import create_access_token, hash_secret, verify_password
from app.db.base import Base
from app.modules.customer_identity import service as customer_identity_service
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
    body = response.json()
    assert set(body) == {"detail", "code"}
    assert "error" not in body
    assert isinstance(body["detail"], str)
    return body["code"]


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
    assert _error_code(duplicate) == "conflict"
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
    absolute_deadline = context.clock() + timedelta(days=7)
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
            absolute_deadline.replace(tzinfo=None)
        )

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
            absolute_deadline.replace(tzinfo=None)
        )

    reused = context.client.post(
        "/api/v1/customer/auth/refresh",
        json={"refresh_token": original["refresh_token"]},
    )
    assert reused.status_code == 401
    assert _error_code(reused) == "unauthorized"
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


def test_customer_refresh_cannot_extend_absolute_lifetime_beyond_login(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    assert _register(context).status_code == 201
    login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": "password"},
    )
    assert login.status_code == 200
    refresh_token = login.json()["refresh_token"]
    absolute_deadline = context.clock() + timedelta(days=7)
    refresh_interval = timedelta(minutes=29)

    while context.clock() + refresh_interval < absolute_deadline:
        context.clock.advance(refresh_interval)
        refresh = context.client.post(
            "/api/v1/customer/auth/refresh",
            json={"refresh_token": refresh_token},
        )
        assert refresh.status_code == 200
        rotated = refresh.json()
        assert rotated["refresh_token"] != refresh_token
        refresh_token = rotated["refresh_token"]

    context.clock.advance(refresh_interval)
    after_deadline = context.client.post(
        "/api/v1/customer/auth/refresh",
        json={"refresh_token": refresh_token},
    )

    assert after_deadline.status_code == 401


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
        "detail": "Authentication failed.",
        "code": "unauthorized",
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
    assert after_boundary.json() == {
        "detail": "Authentication failed.",
        "code": "unauthorized",
    }


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
    assert customer_me.json() == {
        "detail": "Authentication failed.",
        "code": "unauthorized",
    }


def test_customer_me_requires_customer_bearer_session(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    response = customer_identity_context.client.get("/api/v1/customer/auth/me")

    assert response.status_code == 401
    assert response.json() == {
        "detail": "Authentication failed.",
        "code": "unauthorized",
    }


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
            assert response_schema["$ref"] == "#/components/schemas/ErrorResponse"

    error_response = schemas["ErrorResponse"]
    assert set(error_response["properties"]) == {"detail", "code"}
    assert set(error_response["required"]) == {"detail", "code"}
    assert "CustomerErrorResponse" not in schemas

    for path in ("/api/v1/customer/auth/register", "/api/v1/customer/auth/login"):
        request_schema = paths[path]["post"]["requestBody"]["content"]["application/json"]["schema"]
        request_model_ref = request_schema["$ref"].rsplit("/", 1)[-1]
        assert schemas[request_model_ref]["properties"]["email"]["format"] == "email"


_WALLET_PRIVATE_KEY = bytes.fromhex("01" * 32)
_OTHER_WALLET_PRIVATE_KEY = bytes.fromhex("02" * 32)


def _wallet_address(private_key: bytes = _WALLET_PRIVATE_KEY) -> str:
    return Account.from_key(private_key).address


def _wallet_signature(message: str, private_key: bytes = _WALLET_PRIVATE_KEY) -> str:
    signed = Account.sign_message(encode_defunct(text=message), private_key=private_key)
    return signed.signature.hex()


def _customer_auth(
    context: CustomerIdentityContext,
    *,
    email: str = "customer@example.test",
) -> tuple[str, dict[str, str]]:
    registered = _register(context, email=email)
    assert registered.status_code == 201
    login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": email, "password": "password"},
    )
    assert login.status_code == 200
    return registered.json()["id"], {
        "Authorization": f"Bearer {login.json()['access_token']}"
    }


def _create_wallet_challenge(
    context: CustomerIdentityContext,
    auth: dict[str, str],
    address: str,
):
    return context.client.post(
        "/api/v1/customer/wallet-challenges",
        headers=auth,
        json={"address": address},
    )


def test_customer_wallet_link_race_for_same_account_maps_account_conflict(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    customer_id, auth = _customer_auth(context)
    requested_address = _wallet_address()
    challenge = _create_wallet_challenge(context, auth, requested_address).json()
    competing_address = _wallet_address(_OTHER_WALLET_PRIVATE_KEY).lower()

    # Model the competing transaction committing after the initial read but before insert.
    with context.session_factory.begin() as session:
        session.add(
            customer_identity_service.CustomerWallet(
                id="concurrent-wallet",
                customer_id=customer_id,
                address=competing_address,
                linked_at=context.clock(),
            )
        )

    class HiddenPreflightQuery:
        def filter(self, *args: object, **kwargs: object) -> HiddenPreflightQuery:
            return self

        def one_or_none(self) -> None:
            return None

    class RacingSession:
        def __init__(self, session: Session) -> None:
            self._session = session

        def query(self, entity: object, *args: object, **kwargs: object) -> object:
            if entity is customer_identity_service.CustomerWallet:
                return HiddenPreflightQuery()
            return self._session.query(entity, *args, **kwargs)

        def __getattr__(self, name: str) -> object:
            return getattr(self._session, name)

    class RacingSessionFactory:
        def __init__(self) -> None:
            self._begin_count = 0

        def __call__(self, *args: object, **kwargs: object) -> Session:
            return context.session_factory(*args, **kwargs)

        @contextmanager
        def begin(self):
            self._begin_count += 1
            with context.session_factory.begin() as session:
                yield RacingSession(session) if self._begin_count == 2 else session

    with pytest.raises(customer_identity_service.CustomerWalletAlreadyLinkedError):
        customer_identity_service.verify_and_link_customer_wallet(
            session_factory=RacingSessionFactory(),
            customer_id=customer_id,
            challenge_id=challenge["challenge_id"],
            signature=_wallet_signature(challenge["message"]),
            now=context.clock(),
        )


def test_unrelated_wallet_integrity_error_is_not_mapped_to_address_conflict(
    customer_identity_context: CustomerIdentityContext,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = customer_identity_context
    customer_id, auth = _customer_auth(context)
    challenge = _create_wallet_challenge(context, auth, _wallet_address()).json()
    unrelated_error = IntegrityError(
        "INSERT INTO customer_wallet (...) VALUES (...)",
        {},
        RuntimeError("NOT NULL constraint failed: customer_wallet.linked_at"),
    )

    flush_calls: list[bool] = []
    original_flush = Session.flush

    def fail_wallet_flush(self: Session, *args: object, **kwargs: object) -> None:
        if any(
            isinstance(instance, customer_identity_service.CustomerWallet)
            for instance in self.new
        ):
            flush_calls.append(True)
            raise unrelated_error
        original_flush(self, *args, **kwargs)

    monkeypatch.setattr(Session, "flush", fail_wallet_flush)

    with pytest.raises(IntegrityError) as raised:
        customer_identity_service.verify_and_link_customer_wallet(
            session_factory=context.session_factory,
            customer_id=customer_id,
            challenge_id=challenge["challenge_id"],
            signature=_wallet_signature(challenge["message"]),
            now=context.clock(),
        )

    assert raised.value is unrelated_error
    assert flush_calls == [True]


def test_wallet_challenge_requires_customer_session_and_persists_exact_canonical_message(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    address = _wallet_address()

    unauthorized = context.client.post(
        "/api/v1/customer/wallet-challenges", json={"address": address}
    )
    assert unauthorized.status_code == 401
    assert unauthorized.json() == {
        "detail": "Authentication failed.",
        "code": "unauthorized",
    }

    customer_id, auth = _customer_auth(context)
    response = _create_wallet_challenge(context, auth, address)

    assert response.status_code == 201
    body = response.json()
    assert set(body) == {"challenge_id", "message", "expires_at"}
    expires_at = datetime.fromisoformat(body["expires_at"].replace("Z", "+00:00"))
    assert expires_at == context.clock() + timedelta(minutes=5)
    assert customer_id in body["message"]
    assert address.lower() in body["message"]
    assert "link-customer-wallet" in body["message"]
    assert "Nonce:" in body["message"]
    assert "Issued at:" in body["message"]
    assert "Expires at:" in body["message"]

    with context.session_factory() as session:
        stored = session.execute(
            text(
                "SELECT customer_id, address, purpose, nonce, message, issued_at, expires_at, consumed_at "
                "FROM customer_wallet_challenge WHERE id = :id"
            ),
            {"id": body["challenge_id"]},
        ).mappings().one()
    assert stored["customer_id"] == customer_id
    assert stored["address"] == address.lower()
    assert stored["purpose"] == "link-customer-wallet"
    assert len(stored["nonce"]) >= 32
    assert stored["message"] == body["message"]
    assert datetime.fromisoformat(stored["issued_at"]) == context.clock().replace(tzinfo=None)
    assert datetime.fromisoformat(stored["expires_at"]) == expires_at.replace(tzinfo=None)
    assert stored["consumed_at"] is None

    empty_wallets = context.client.get("/api/v1/customer/wallets", headers=auth)
    assert empty_wallets.status_code == 200
    assert empty_wallets.json() == []


@pytest.mark.parametrize("address", ["not-an-address", "0x1234", "0x" + "gg" * 20])
def test_wallet_challenge_rejects_malformed_addresses_with_customer_validation_error(
    customer_identity_context: CustomerIdentityContext,
    address: str,
) -> None:
    _, auth = _customer_auth(customer_identity_context)

    response = _create_wallet_challenge(customer_identity_context, auth, address)

    assert response.status_code == 422
    assert response.json() == {
        "detail": "Request validation failed",
        "code": "validation_error",
    }


def test_valid_wallet_signature_links_wallet_and_replay_fails_generically(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    _, auth = _customer_auth(context)
    address = _wallet_address()
    challenge = _create_wallet_challenge(context, auth, address)
    assert challenge.status_code == 201
    challenge_body = challenge.json()

    linked = context.client.post(
        "/api/v1/customer/wallets",
        headers=auth,
        json={
            "challenge_id": challenge_body["challenge_id"],
            "signature": _wallet_signature(challenge_body["message"]),
            "message": "Client-controlled alternate text must be ignored",
        },
    )

    assert linked.status_code == 201
    assert linked.json()["address"] == address.lower()
    assert set(linked.json()) == {"id", "address", "linked_at"}
    listed = context.client.get("/api/v1/customer/wallets", headers=auth)
    assert listed.status_code == 200
    assert listed.json() == [linked.json()]

    replay = context.client.post(
        "/api/v1/customer/wallets",
        headers=auth,
        json={
            "challenge_id": challenge_body["challenge_id"],
            "signature": _wallet_signature(challenge_body["message"]),
        },
    )
    assert replay.status_code == 401
    assert _error_code(replay) == "unauthorized"


@pytest.mark.parametrize("invalid_signature", ["not-a-signature", "0x" + "00" * 65])
def test_invalid_wallet_signature_durably_consumes_challenge_before_retry(
    customer_identity_context: CustomerIdentityContext,
    invalid_signature: str,
) -> None:
    context = customer_identity_context
    _, auth = _customer_auth(context)
    challenge = _create_wallet_challenge(context, auth, _wallet_address())
    challenge_body = challenge.json()

    failed = context.client.post(
        "/api/v1/customer/wallets",
        headers=auth,
        json={"challenge_id": challenge_body["challenge_id"], "signature": invalid_signature},
    )

    assert failed.status_code == 401
    assert _error_code(failed) == "unauthorized"
    with context.session_factory() as session:
        consumed_at = session.execute(
            text("SELECT consumed_at FROM customer_wallet_challenge WHERE id = :id"),
            {"id": challenge_body["challenge_id"]},
        ).scalar_one()
    assert consumed_at is not None

    valid_retry = context.client.post(
        "/api/v1/customer/wallets",
        headers=auth,
        json={
            "challenge_id": challenge_body["challenge_id"],
            "signature": _wallet_signature(challenge_body["message"]),
        },
    )
    assert valid_retry.status_code == 401
    assert _error_code(valid_retry) == "unauthorized"
    assert context.client.get("/api/v1/customer/wallets", headers=auth).json() == []


def test_signature_from_a_different_wallet_is_rejected_and_consumed(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    _, auth = _customer_auth(context)
    challenge = _create_wallet_challenge(context, auth, _wallet_address()).json()

    response = context.client.post(
        "/api/v1/customer/wallets",
        headers=auth,
        json={
            "challenge_id": challenge["challenge_id"],
            "signature": _wallet_signature(
                challenge["message"], _OTHER_WALLET_PRIVATE_KEY
            ),
        },
    )

    assert response.status_code == 401
    assert _error_code(response) == "unauthorized"
    with context.session_factory() as session:
        consumed_at = session.execute(
            text("SELECT consumed_at FROM customer_wallet_challenge WHERE id = :id"),
            {"id": challenge["challenge_id"]},
        ).scalar_one()
    assert consumed_at is not None
    assert context.client.get("/api/v1/customer/wallets", headers=auth).json() == []


def test_wallet_challenge_consumption_commits_before_signature_recovery(
    customer_identity_context: CustomerIdentityContext,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = customer_identity_context
    _, auth = _customer_auth(context)
    challenge = _create_wallet_challenge(context, auth, _wallet_address()).json()
    consumed_before_recovery: list[bool] = []

    def inspect_consumption(message: object, signature: str) -> str:
        assert message is not None
        assert signature == "malformed"
        with context.session_factory() as session:
            consumed_at = session.execute(
                text("SELECT consumed_at FROM customer_wallet_challenge WHERE id = :id"),
                {"id": challenge["challenge_id"]},
            ).scalar_one()
        consumed_before_recovery.append(consumed_at is not None)
        raise ValueError("Malformed test signature")

    monkeypatch.setattr(
        customer_identity_service.Account,
        "recover_message",
        staticmethod(inspect_consumption),
    )
    response = context.client.post(
        "/api/v1/customer/wallets",
        headers=auth,
        json={"challenge_id": challenge["challenge_id"], "signature": "malformed"},
    )

    assert response.status_code == 401
    assert _error_code(response) == "unauthorized"
    assert consumed_before_recovery == [True]


def test_expired_wallet_challenge_fails_closed(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    _, auth = _customer_auth(context)
    challenge = _create_wallet_challenge(context, auth, _wallet_address())
    challenge_body = challenge.json()
    context.clock.advance(timedelta(minutes=5, microseconds=1))

    response = context.client.post(
        "/api/v1/customer/wallets",
        headers=auth,
        json={
            "challenge_id": challenge_body["challenge_id"],
            "signature": _wallet_signature(challenge_body["message"]),
        },
    )

    assert response.status_code == 401
    assert _error_code(response) == "unauthorized"
    assert context.client.get("/api/v1/customer/wallets", headers=auth).json() == []


def test_wallet_challenge_is_bound_to_customer_without_consuming_other_customers_challenge(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    alice_id, alice_auth = _customer_auth(context)
    bob_id, bob_auth = _customer_auth(context, email="bob@example.test")
    assert alice_id != bob_id
    challenge = _create_wallet_challenge(context, alice_auth, _wallet_address())
    challenge_body = challenge.json()
    signature = _wallet_signature(challenge_body["message"])

    cross_customer_attempt = context.client.post(
        "/api/v1/customer/wallets",
        headers=bob_auth,
        json={"challenge_id": challenge_body["challenge_id"], "signature": signature},
    )

    assert cross_customer_attempt.status_code == 401
    assert _error_code(cross_customer_attempt) == "unauthorized"
    with context.session_factory() as session:
        assert session.execute(
            text("SELECT consumed_at FROM customer_wallet_challenge WHERE id = :id"),
            {"id": challenge_body["challenge_id"]},
        ).scalar_one() is None

    linked = context.client.post(
        "/api/v1/customer/wallets",
        headers=alice_auth,
        json={"challenge_id": challenge_body["challenge_id"], "signature": signature},
    )
    assert linked.status_code == 201
    assert context.client.get("/api/v1/customer/wallets", headers=bob_auth).json() == []


def test_wallet_is_globally_unique_and_owner_is_never_disclosed(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    _, alice_auth = _customer_auth(context)
    _, bob_auth = _customer_auth(context, email="bob@example.test")
    address = _wallet_address()
    first_challenge = _create_wallet_challenge(context, alice_auth, address).json()
    first_link = context.client.post(
        "/api/v1/customer/wallets",
        headers=alice_auth,
        json={
            "challenge_id": first_challenge["challenge_id"],
            "signature": _wallet_signature(first_challenge["message"]),
        },
    )
    assert first_link.status_code == 201

    second_challenge = _create_wallet_challenge(context, bob_auth, address)
    assert second_challenge.status_code == 201
    second_body = second_challenge.json()
    conflict = context.client.post(
        "/api/v1/customer/wallets",
        headers=bob_auth,
        json={
            "challenge_id": second_body["challenge_id"],
            "signature": _wallet_signature(second_body["message"]),
        },
    )

    assert conflict.status_code == 409
    assert _error_code(conflict) == "conflict"
    assert alice_auth["Authorization"] not in conflict.text
    assert "alice@example.test" not in conflict.text
    assert "customer_id" not in conflict.text
    assert context.client.get("/api/v1/customer/wallets", headers=bob_auth).json() == []
    assert len(context.client.get("/api/v1/customer/wallets", headers=alice_auth).json()) == 1


def test_customer_wallet_has_cardinality_one_and_cannot_be_replaced(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    _, auth = _customer_auth(context)
    first_address = _wallet_address()
    replacement_address = _wallet_address(_OTHER_WALLET_PRIVATE_KEY)
    first_challenge = _create_wallet_challenge(context, auth, first_address).json()
    replacement_challenge = _create_wallet_challenge(context, auth, replacement_address).json()

    first_link = context.client.post(
        "/api/v1/customer/wallets",
        headers=auth,
        json={
            "challenge_id": first_challenge["challenge_id"],
            "signature": _wallet_signature(first_challenge["message"]),
        },
    )
    assert first_link.status_code == 201

    replacement = context.client.post(
        "/api/v1/customer/wallets",
        headers=auth,
        json={
            "challenge_id": replacement_challenge["challenge_id"],
            "signature": _wallet_signature(
                replacement_challenge["message"], _OTHER_WALLET_PRIVATE_KEY
            ),
        },
    )
    assert replacement.status_code == 409
    assert _error_code(replacement) == "conflict"
    challenge_conflict = _create_wallet_challenge(context, auth, replacement_address)
    assert challenge_conflict.status_code == 409
    assert _error_code(challenge_conflict) == "conflict"
    listed = context.client.get("/api/v1/customer/wallets", headers=auth)
    assert listed.status_code == 200
    assert len(listed.json()) == 1
    assert listed.json()[0]["address"] == first_address.lower()


def test_customer_wallet_openapi_and_validation_scope_preserve_staff_errors(
    customer_identity_context: CustomerIdentityContext,
) -> None:
    context = customer_identity_context
    paths = context.client.get("/openapi.json").json()["paths"]

    assert "/api/v1/customer/wallet-challenges" in paths
    assert "/api/v1/customer/wallets" in paths
    assert "/api/v1/customer/auth/wallets" not in paths
    address_schema = paths["/api/v1/customer/wallet-challenges"]["post"]["requestBody"][
        "content"
    ]["application/json"]["schema"]
    address_schema_name = address_schema["$ref"].rsplit("/", 1)[-1]
    address_pattern = context.client.get("/openapi.json").json()["components"]["schemas"][
        address_schema_name
    ]["properties"]["address"]["pattern"]
    assert address_pattern == "^0x[a-fA-F0-9]{40}$"
    expected_responses = {
        ("/api/v1/customer/wallet-challenges", "post"): {"401", "409", "422"},
        ("/api/v1/customer/wallets", "post"): {"401", "409", "422"},
        ("/api/v1/customer/wallets", "get"): {"401"},
    }
    for (path, method), status_codes in expected_responses.items():
        responses = paths[path][method]["responses"]
        for status_code in status_codes:
            assert status_code in responses
            assert responses[status_code]["content"]["application/json"]["schema"][
                "$ref"
            ] == "#/components/schemas/ErrorResponse"

    reservation_unauthorized_responses = (
        ("/api/v1/reservations", "post"),
        ("/api/v1/reservations", "get"),
        ("/api/v1/reservations/{reservation_id}/chain-transactions", "post"),
        ("/api/v1/reservations/{reservation_id}", "get"),
        ("/api/v1/reservations/{reservation_id}/permit", "post"),
    )
    for path, method in reservation_unauthorized_responses:
        schema = paths[path][method]["responses"]["401"]["content"][
            "application/json"
        ]["schema"]
        assert schema["$ref"] == "#/components/schemas/ErrorResponse"

    _, auth = _customer_auth(context)
    malformed = _create_wallet_challenge(context, auth, "invalid")
    assert malformed.status_code == 422
    assert malformed.json() == {
        "detail": "Request validation failed",
        "code": "validation_error",
    }
    staff_validation = context.client.post("/api/v1/auth/login", json={})
    assert staff_validation.status_code == 422
    assert staff_validation.json() == {
        "detail": "Request validation failed",
        "code": "validation_error",
    }

    unauthenticated_list = context.client.get("/api/v1/customer/wallets")
    assert unauthenticated_list.status_code == 401
    assert unauthenticated_list.json() == {
        "detail": "Authentication failed.",
        "code": "unauthorized",
    }
    unauthenticated_reservations = context.client.get("/api/v1/reservations")
    assert unauthenticated_reservations.status_code == 401
    assert unauthenticated_reservations.json() == {
        "detail": "Authentication failed.",
        "code": "unauthorized",
    }
