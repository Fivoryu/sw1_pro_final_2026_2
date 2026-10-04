"""Tests for official exchange-rate ingestion (Coinbase USDT + static BCB BOB)."""

from __future__ import annotations

import asyncio
import base64
import json
from contextlib import suppress
from decimal import Decimal
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.core.rate_source import (
    RateSourceError,
    RateSuggestion,
    fetch_official_rates,
    official_rate_refresh_interval_seconds,
)
from app.db.base import Base
from app.main import create_app
from app.modules.exchange_rates import service as exchange_rates_service
from app.modules.exchange_rates.models import ExchangeRate
from app.modules.exchange_rates.service import refresh_official_rates


class _FakeResponse:
    def __init__(self, *, status: int, payload: Any) -> None:
        self.status = status
        self._payload = payload

    def __enter__(self) -> _FakeResponse:
        return self

    def __exit__(self, *args: object) -> bool:
        return False

    def read(self) -> bytes:
        if isinstance(self._payload, (bytes, bytearray)):
            return bytes(self._payload)
        return json.dumps(self._payload).encode("utf-8")


@pytest.fixture
def rate_session_factory() -> Any:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, expire_on_commit=False)
    yield factory
    engine.dispose()


def _insert_rate(
    factory: sessionmaker[Session],
    *,
    currency: str,
    units_per_usd: str,
    source: str = "manual",
) -> None:
    with factory.begin() as session:
        session.add(
            ExchangeRate(
                currency=currency,
                units_per_usd=Decimal(units_per_usd),
                created_by=None,
                source=source,
            )
        )


def _stored_rows(factory: sessionmaker[Session]) -> list[tuple[str, str, str]]:
    with factory() as session:
        rows = session.query(ExchangeRate).order_by(ExchangeRate.id).all()
        return [
            (row.currency, format(row.units_per_usd, ".8f"), row.source) for row in rows
        ]


def _stub_suggestions(
    monkeypatch: pytest.MonkeyPatch,
    *,
    usdt: str = "0.99980000",
    bob: str = "6.96000000",
) -> None:
    monkeypatch.setattr(
        exchange_rates_service,
        "fetch_official_rates",
        lambda: {
            "USDT": RateSuggestion("USDT", Decimal(usdt), "coinbase"),
            "BOB": RateSuggestion("BOB", Decimal(bob), "bcb-static"),
        },
    )


# ---------------------------------------------------------------------------
# Official source fetch (Coinbase USDT spot + static BCB BOB)
# ---------------------------------------------------------------------------


def test_coinbase_spot_price_is_inverted_into_units_per_usd(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        "app.core.rate_source.urlopen",
        lambda request, timeout: _FakeResponse(
            status=200,
            payload={"data": {"base": "USDT", "currency": "USD", "amount": "0.9998"}},
        ),
    )

    rates = fetch_official_rates()

    assert rates["USDT"].currency == "USDT"
    # Coinbase quotes 1 USDT in USD; our convention is units of USDT per 1 USD.
    assert rates["USDT"].units_per_usd == Decimal("1.00020004")
    assert rates["USDT"].source == "coinbase"


def test_coinbase_amount_is_inverted_and_quantized_to_eight_decimals_with_half_up(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        "app.core.rate_source.urlopen",
        lambda request, timeout: _FakeResponse(
            status=200, payload={"data": {"amount": "1.234567855"}}
        ),
    )

    rates = fetch_official_rates()

    assert rates["USDT"].units_per_usd == Decimal("0.81000003")


@pytest.mark.parametrize(
    "response_kwargs",
    [
        {"status": 500, "payload": {"error": "boom"}},
        {"status": 200, "payload": {"data": {}}},
        {"status": 200, "payload": {"unexpected": "shape"}},
        {"status": 200, "payload": b"not-json"},
    ],
)
def test_coinbase_failures_fail_closed(
    monkeypatch: pytest.MonkeyPatch, response_kwargs: dict[str, Any]
) -> None:
    monkeypatch.setattr(
        "app.core.rate_source.urlopen",
        lambda request, timeout: _FakeResponse(**response_kwargs),
    )

    with pytest.raises(RateSourceError):
        fetch_official_rates()


@pytest.mark.parametrize("error", [TimeoutError("timed out"), OSError("unreachable")])
def test_coinbase_transport_failures_fail_closed(
    monkeypatch: pytest.MonkeyPatch, error: Exception
) -> None:
    def _raise(request: object, timeout: object) -> _FakeResponse:
        raise error

    monkeypatch.setattr("app.core.rate_source.urlopen", _raise)

    with pytest.raises(RateSourceError):
        fetch_official_rates()


def test_coinbase_non_positive_amounts_fail_closed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    for amount in ("0", "-1.00"):
        monkeypatch.setattr(
            "app.core.rate_source.urlopen",
            lambda request, timeout, amount=amount: _FakeResponse(
                status=200, payload={"data": {"amount": amount}}
            ),
        )
        with pytest.raises(RateSourceError):
            fetch_official_rates()


def test_bob_official_rate_defaults_to_the_static_bcb_value() -> None:
    monkeypatch = pytest.MonkeyPatch()
    monkeypatch.delenv("ROOMFORGE_OFFICIAL_BOB_RATE", raising=False)
    try:
        rates = fetch_official_rates()
    finally:
        monkeypatch.undo()

    assert rates["BOB"].currency == "BOB"
    assert rates["BOB"].units_per_usd == Decimal("6.96000000")
    assert rates["BOB"].source == "bcb-static"


def test_bob_official_rate_honors_the_environment_override(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ROOMFORGE_OFFICIAL_BOB_RATE", "6.97")

    rates = fetch_official_rates()

    assert rates["BOB"].units_per_usd == Decimal("6.97000000")
    assert rates["BOB"].source == "bcb-static"


def test_bob_official_rate_fails_closed_on_a_malformed_override(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ROOMFORGE_OFFICIAL_BOB_RATE", "six-ninety-six")

    with pytest.raises(RateSourceError):
        fetch_official_rates()


def test_suggestions_carry_the_currency_and_source_labels() -> None:
    suggestion = RateSuggestion("BOB", Decimal("6.96"), "bcb-static")

    assert suggestion.currency == "BOB"
    assert suggestion.source == "bcb-static"


# ---------------------------------------------------------------------------
# Refresh interval configuration
# ---------------------------------------------------------------------------


def test_refresh_interval_defaults_to_six_hours(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("ROOMFORGE_RATE_REFRESH_SECONDS", raising=False)

    assert official_rate_refresh_interval_seconds() == 21600


def test_refresh_interval_reads_the_environment_override(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ROOMFORGE_RATE_REFRESH_SECONDS", "60")

    assert official_rate_refresh_interval_seconds() == 60


def test_refresh_interval_zero_or_negative_disables_the_refresher(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    for raw in ("0", "-1"):
        monkeypatch.setenv("ROOMFORGE_RATE_REFRESH_SECONDS", raw)
        assert official_rate_refresh_interval_seconds() <= 0


def test_refresh_interval_rejects_a_malformed_value(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ROOMFORGE_RATE_REFRESH_SECONDS", "hourly")

    with pytest.raises(RuntimeError):
        official_rate_refresh_interval_seconds()


# ---------------------------------------------------------------------------
# refresh_official_rates service
# ---------------------------------------------------------------------------


def test_refresh_creates_official_rows_with_their_source_labels(
    rate_session_factory: sessionmaker[Session],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_suggestions(monkeypatch)

    with rate_session_factory.begin() as session:
        outcomes = refresh_official_rates(session)

    assert outcomes == {"BOB": "created", "USDT": "created"}
    assert _stored_rows(rate_session_factory) == [
        ("BOB", "6.96000000", "bcb-static"),
        ("USDT", "0.99980000", "coinbase"),
    ]


def test_refresh_is_a_noop_when_the_fetched_value_is_unchanged(
    rate_session_factory: sessionmaker[Session],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_suggestions(monkeypatch)
    with rate_session_factory.begin() as session:
        refresh_official_rates(session)

    with rate_session_factory.begin() as session:
        outcomes = refresh_official_rates(session)

    assert outcomes == {"BOB": "unchanged", "USDT": "unchanged"}
    assert len(_stored_rows(rate_session_factory)) == 2


def test_refresh_creates_a_new_row_when_the_official_value_changes(
    rate_session_factory: sessionmaker[Session],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_suggestions(monkeypatch, usdt="0.99980000")
    with rate_session_factory.begin() as session:
        refresh_official_rates(session)
    _stub_suggestions(monkeypatch, usdt="1.00050000")

    with rate_session_factory.begin() as session:
        outcomes = refresh_official_rates(session)

    assert outcomes == {"BOB": "unchanged", "USDT": "created"}
    rows = _stored_rows(rate_session_factory)
    assert len(rows) == 3
    assert rows[-1] == ("USDT", "1.00050000", "coinbase")


def test_refresh_supersedes_but_never_overwrites_manual_rows(
    rate_session_factory: sessionmaker[Session],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _insert_rate(rate_session_factory, currency="BOB", units_per_usd="6.90000000")
    _stub_suggestions(monkeypatch, bob="6.96000000")

    with rate_session_factory.begin() as session:
        outcomes = refresh_official_rates(session)

    assert outcomes == {"BOB": "created", "USDT": "created"}
    rows = _stored_rows(rate_session_factory)
    assert ("BOB", "6.90000000", "manual") in rows
    assert ("BOB", "6.96000000", "bcb-static") in rows


def test_refresh_is_a_noop_when_the_official_value_matches_a_manual_row(
    rate_session_factory: sessionmaker[Session],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _insert_rate(rate_session_factory, currency="BOB", units_per_usd="6.96000000")
    _stub_suggestions(monkeypatch, bob="6.96")

    with rate_session_factory.begin() as session:
        outcomes = refresh_official_rates(session)

    assert outcomes["BOB"] == "unchanged"
    rows = _stored_rows(rate_session_factory)
    assert [row for row in rows if row[0] == "BOB"] == [
        ("BOB", "6.96000000", "manual")
    ]


def test_refresh_reports_a_per_currency_error_and_writes_nothing_on_fetch_failure(
    rate_session_factory: sessionmaker[Session],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def _fail() -> dict[str, RateSuggestion]:
        raise RateSourceError("coinbase spot price request failed: timed out")

    monkeypatch.setattr(exchange_rates_service, "fetch_official_rates", _fail)

    with rate_session_factory.begin() as session:
        outcomes = refresh_official_rates(session)

    assert outcomes == {
        "BOB": "error: coinbase spot price request failed: timed out",
        "USDT": "error: coinbase spot price request failed: timed out",
    }
    assert _stored_rows(rate_session_factory) == []


# ---------------------------------------------------------------------------
# Background lifespan refresher
# ---------------------------------------------------------------------------


def _app_settings() -> Settings:
    return Settings(
        database_url="sqlite+pysqlite:///:memory:",
        jwt_secret="test-jwt-secret-at-least-32-bytes-long",
        totp_encryption_key=base64.urlsafe_b64encode(b"x" * 32).decode("ascii"),
        web_origin="https://panel.example.test",
    )


def test_app_startup_never_touches_the_official_sources(
    rate_session_factory: sessionmaker[Session],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("ROOMFORGE_RATE_REFRESH_SECONDS", raising=False)
    calls: list[object] = []

    def _record(request: object, timeout: object) -> _FakeResponse:
        calls.append(request)
        return _FakeResponse(status=200, payload={"data": {"amount": "1.00"}})

    monkeypatch.setattr("app.core.rate_source.urlopen", _record)

    app = create_app(settings=_app_settings(), session_factory=rate_session_factory)
    with TestClient(app, base_url="https://testserver") as client:
        response = client.get("/api/v1/exchange-rates/current")

    assert response.status_code == 200
    assert calls == []


def test_disabled_refresh_interval_starts_no_background_work(
    rate_session_factory: sessionmaker[Session],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ROOMFORGE_RATE_REFRESH_SECONDS", "0")
    calls: list[object] = []

    def _record(request: object, timeout: object) -> _FakeResponse:
        calls.append(request)
        return _FakeResponse(status=200, payload={"data": {"amount": "1.00"}})

    monkeypatch.setattr("app.core.rate_source.urlopen", _record)

    app = create_app(settings=_app_settings(), session_factory=rate_session_factory)
    with TestClient(app, base_url="https://testserver") as client:
        response = client.get("/api/v1/exchange-rates/current")

    assert response.status_code == 200
    assert calls == []


def test_refresh_loop_runs_after_each_interval_and_survives_failures(
    rate_session_factory: sessionmaker[Session],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.main import _official_rate_refresh_loop

    outcomes: list[str] = []

    def _flaky_refresh(session: Session) -> dict[str, str]:
        outcomes.append("run")
        if len(outcomes) < 3:
            raise RuntimeError("transient outage")
        return {"BOB": "created", "USDT": "created"}

    monkeypatch.setattr(
        "app.main.refresh_official_rates", _flaky_refresh, raising=False
    )

    async def _drive() -> None:
        task = asyncio.create_task(
            _official_rate_refresh_loop(
                rate_session_factory, interval_seconds=0.02
            )
        )
        await asyncio.sleep(0.15)
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task

    asyncio.run(_drive())

    assert len(outcomes) >= 3


def test_background_session_factory_is_usable_from_the_loop_thread(
    rate_session_factory: sessionmaker[Session],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _stub_suggestions(monkeypatch)
    from app.main import _run_official_rate_refresh

    _run_official_rate_refresh(rate_session_factory)

    assert _stored_rows(rate_session_factory) == [
        ("BOB", "6.96000000", "bcb-static"),
        ("USDT", "0.99980000", "coinbase"),
    ]
