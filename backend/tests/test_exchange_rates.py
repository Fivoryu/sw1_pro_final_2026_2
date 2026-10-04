from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.core.security import create_access_token
from app.db.base import Base
from app.main import create_app
from app.modules.exchange_rates.errors import MissingExchangeRateError
from app.modules.exchange_rates.models import ExchangeRate
from app.modules.exchange_rates.service import convert, rate_history
from app.modules.identity.models import Agency, StaffAccount, StaffSession


@dataclass
class ExchangeRateContext:
    client: TestClient
    session_factory: sessionmaker[Session]
    settings: Settings
    now: datetime


@pytest.fixture

def exchange_rate_context() -> Any:
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
    app = create_app(settings=settings, session_factory=session_factory, clock=lambda: now)
    with TestClient(app, base_url="https://testserver") as client:
        yield ExchangeRateContext(client, session_factory, settings, now)
    engine.dispose()


def _seed_staff(
    context: ExchangeRateContext,
    *,
    role: str = "platform_admin",
    account_id: str | None = None,
) -> str:
    account_id = account_id or str(uuid4())
    session_id = f"session-{account_id}"
    tenant_id = None if role == "platform_admin" else "agency-exchange-rates"
    with context.session_factory.begin() as session:
        if tenant_id is not None and session.get(Agency, tenant_id) is None:
            session.add(Agency(id=tenant_id))
            session.flush()
        session.add(
            StaffAccount(
                id=account_id,
                email=f"{account_id}@example.test",
                password_hash="test-password-hash",
                role=role,
                tenant_id=tenant_id,
                active=True,
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
            )
        )
    token = create_access_token(
        user_id=account_id,
        session_id=session_id,
        signing_key=context.settings.jwt_secret,
        now=context.now,
        lifetime_minutes=context.settings.access_token_minutes,
    )
    return token


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _create_rate(
    context: ExchangeRateContext,
    *,
    token: str,
    currency: str,
    units_per_usd: str,
) -> Any:
    return context.client.post(
        "/api/v1/platform/exchange-rates",
        json={"currency": currency, "units_per_usd": units_per_usd},
        headers=_headers(token),
    )


def test_platform_admin_creates_bob_rate_with_eight_decimal_places(
    exchange_rate_context: ExchangeRateContext,
) -> None:
    context = exchange_rate_context
    token = _seed_staff(context)

    response = _create_rate(
        context, token=token, currency="BOB", units_per_usd="6.96000000"
    )

    assert response.status_code == 201
    body = response.json()
    assert body["id"] > 0
    assert body["currency"] == "BOB"
    assert body["units_per_usd"] == "6.96000000"
    UUID(body["created_by"])
    assert datetime.fromisoformat(body["created_at"].replace("Z", "+00:00"))


@pytest.mark.parametrize(
    ("currency", "units_per_usd"),
    [
        ("USD", "1.00000000"),
        ("BOB", "0"),
        ("BOB", "-1"),
        ("BOB", "1.000000001"),
        ("BOB", "1e2"),
        ("BOB", 1.25),
    ],
)
def test_create_rate_rejects_usd_nonpositive_or_invalid_precision(
    exchange_rate_context: ExchangeRateContext,
    currency: str,
    units_per_usd: str | float,
) -> None:
    context = exchange_rate_context
    token = _seed_staff(context)

    response = context.client.post(
        "/api/v1/platform/exchange-rates",
        json={"currency": currency, "units_per_usd": units_per_usd},
        headers=_headers(token),
    )

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    with context.session_factory() as session:
        assert session.query(ExchangeRate).count() == 0


def test_eight_decimal_rate_is_preserved_without_rounding(
    exchange_rate_context: ExchangeRateContext,
) -> None:
    context = exchange_rate_context
    token = _seed_staff(context)

    response = _create_rate(
        context, token=token, currency="USDT", units_per_usd="1.12345678"
    )

    assert response.status_code == 201
    assert response.json()["units_per_usd"] == "1.12345678"


@pytest.mark.parametrize("role", ["agent", "agency_admin"])
def test_non_platform_staff_cannot_create_exchange_rates(
    exchange_rate_context: ExchangeRateContext, role: str
) -> None:
    context = exchange_rate_context
    token = _seed_staff(context, role=role)

    response = _create_rate(
        context, token=token, currency="BOB", units_per_usd="6.96"
    )

    assert response.status_code == 403
    assert response.json()["code"] == "forbidden"


def test_unauthenticated_staff_route_rejects_rate_creation(
    exchange_rate_context: ExchangeRateContext,
) -> None:
    response = exchange_rate_context.client.post(
        "/api/v1/platform/exchange-rates",
        json={"currency": "BOB", "units_per_usd": "6.96"},
    )

    assert response.status_code == 401
    assert response.json()["code"] == "unauthorized"


def test_customer_cannot_create_platform_exchange_rates(
    exchange_rate_context: ExchangeRateContext,
) -> None:
    context = exchange_rate_context
    registered = context.client.post(
        "/api/v1/customer/auth/register",
        json={"email": "customer@example.test", "password": "safe-password-1"},
    )
    assert registered.status_code == 201
    login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": "safe-password-1"},
    )
    assert login.status_code == 200

    response = _create_rate(
        context,
        token=login.json()["access_token"],
        currency="BOB",
        units_per_usd="6.96",
    )

    assert response.status_code == 403
    assert response.json()["code"] == "forbidden"


def test_public_current_rates_include_fixed_usd_and_unset_rates(
    exchange_rate_context: ExchangeRateContext,
) -> None:
    response = exchange_rate_context.client.get("/api/v1/exchange-rates/current")

    assert response.status_code == 200
    assert response.json() == {
        "rates": [
            {"currency": "BOB", "units_per_usd": None, "created_at": None},
            {"currency": "USD", "units_per_usd": "1.00000000", "created_at": None},
            {"currency": "USDT", "units_per_usd": None, "created_at": None},
        ]
    }


def test_public_current_rates_return_latest_row_per_currency(
    exchange_rate_context: ExchangeRateContext,
) -> None:
    context = exchange_rate_context
    token = _seed_staff(context)
    _create_rate(context, token=token, currency="BOB", units_per_usd="6.90")
    latest = _create_rate(
        context, token=token, currency="BOB", units_per_usd="6.96"
    )
    _create_rate(context, token=token, currency="USDT", units_per_usd="1.01")

    response = context.client.get("/api/v1/exchange-rates/current")

    assert response.status_code == 200
    rates = {rate["currency"]: rate for rate in response.json()["rates"]}
    assert rates["BOB"]["units_per_usd"] == "6.96000000"
    assert rates["BOB"]["created_at"] == latest.json()["created_at"]
    assert rates["USD"]["units_per_usd"] == "1.00000000"
    assert rates["USDT"]["units_per_usd"] == "1.01000000"
    assert rates["USDT"]["created_at"] is not None


def test_customer_and_unauthenticated_users_cannot_read_platform_history(
    exchange_rate_context: ExchangeRateContext,
) -> None:
    context = exchange_rate_context
    unauthenticated = context.client.get("/api/v1/platform/exchange-rates")
    registered = context.client.post(
        "/api/v1/customer/auth/register",
        json={"email": "reader@example.test", "password": "safe-password-1"},
    )
    assert registered.status_code == 201
    login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "reader@example.test", "password": "safe-password-1"},
    )
    assert login.status_code == 200
    customer = context.client.get(
        "/api/v1/platform/exchange-rates",
        headers=_headers(login.json()["access_token"]),
    )

    assert unauthenticated.status_code == 401
    assert customer.status_code == 403


@pytest.mark.parametrize("role", ["agent", "agency_admin"])
def test_non_platform_staff_cannot_read_rate_history(
    exchange_rate_context: ExchangeRateContext, role: str
) -> None:
    token = _seed_staff(exchange_rate_context, role=role)

    response = exchange_rate_context.client.get(
        "/api/v1/platform/exchange-rates", headers=_headers(token)
    )

    assert response.status_code == 403


def test_platform_history_is_newest_first_and_currency_history_is_filtered(
    exchange_rate_context: ExchangeRateContext,
) -> None:
    context = exchange_rate_context
    token = _seed_staff(context)
    first_bob = _create_rate(context, token=token, currency="BOB", units_per_usd="6.90")
    usdt = _create_rate(context, token=token, currency="USDT", units_per_usd="1.01")
    latest_bob = _create_rate(context, token=token, currency="BOB", units_per_usd="6.96")

    response = context.client.get(
        "/api/v1/platform/exchange-rates", headers=_headers(token)
    )

    assert response.status_code == 200
    rates = response.json()["rates"]
    assert [rate["id"] for rate in rates] == [
        latest_bob.json()["id"],
        usdt.json()["id"],
        first_bob.json()["id"],
    ]
    assert len({rate["created_by"] for rate in rates}) == 1
    UUID(rates[0]["created_by"])
    bob_history = rate_history(
        session_factory=context.session_factory, currency="BOB"
    )
    assert [rate["id"] for rate in bob_history] == [
        latest_bob.json()["id"],
        first_bob.json()["id"],
    ]


def test_convert_bob_to_usd_uses_final_two_decimal_half_up_rounding() -> None:
    result = convert(
        Decimal("100"),
        "BOB",
        "USD",
        rates={"BOB": Decimal("6.96")},
    )

    assert result == Decimal("14.37")


def test_convert_bob_to_bob_is_identity_without_a_rate() -> None:
    result = convert(Decimal("12.345"), "BOB", "BOB", rates={})

    assert result == Decimal("12.35")


def test_convert_usdt_to_bob_crosses_usd_exactly() -> None:
    result = convert(
        Decimal("2"),
        "USDT",
        "BOB",
        rates={"USDT": Decimal("1.01"), "BOB": Decimal("6.96")},
    )

    assert result == Decimal("13.78")


def test_convert_fails_closed_when_a_required_rate_is_missing() -> None:
    with pytest.raises(MissingExchangeRateError):
        convert(Decimal("1"), "BOB", "USD", rates={})


def test_exchange_rate_database_checks_reject_unsupported_currency_and_nonpositive_rate(
    exchange_rate_context: ExchangeRateContext,
) -> None:
    context = exchange_rate_context
    _seed_staff(context)

    for currency, value in [("COP", Decimal("1")), ("BOB", Decimal("0"))]:
        with pytest.raises(IntegrityError):
            with context.session_factory.begin() as session:
                session.add(
                    ExchangeRate(
                        currency=currency,
                        units_per_usd=value,
                        created_by="platform_admin-account",
                    )
                )
                session.flush()
