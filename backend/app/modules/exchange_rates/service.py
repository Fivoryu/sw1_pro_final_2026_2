"""Business rules for administered exchange rates and exact conversions."""

from __future__ import annotations

import re
from collections.abc import Mapping
from datetime import datetime
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP, localcontext
from typing import TypedDict

from sqlalchemy.orm import Session, sessionmaker

from app.core.money import SUPPORTED_CURRENCIES, SupportedCurrency, validate_currency
from app.core.rate_source import RateSourceError, fetch_official_rates
from app.modules.exchange_rates.errors import (
    InvalidConversionError,
    InvalidExchangeRateError,
    MissingExchangeRateError,
)
from app.modules.exchange_rates.models import ExchangeRate


_RATE_PATTERN = re.compile(r"^[0-9]+(?:\.[0-9]{1,8})?$")
_RATE_QUANTUM = Decimal("0.00000001")
_AMOUNT_QUANTUM = Decimal("0.01")
_MAX_RATE = Decimal("10000000000")


class ExchangeRateRecord(TypedDict):
    id: int
    currency: str
    units_per_usd: str
    source: str
    created_at: datetime
    created_by: str | None


class CurrentExchangeRateRecord(TypedDict):
    currency: SupportedCurrency
    units_per_usd: str | None
    created_at: datetime | None
    source: str | None


_OFFICIAL_CURRENCIES = ("BOB", "USDT")


def _parse_units_per_usd(value: object) -> Decimal:
    if not isinstance(value, str) or not _RATE_PATTERN.fullmatch(value):
        raise InvalidExchangeRateError(
            "units_per_usd must be a positive decimal string with at most 8 decimals"
        )
    try:
        parsed = Decimal(value)
    except InvalidOperation:
        raise InvalidExchangeRateError("units_per_usd is invalid") from None
    if not parsed.is_finite() or parsed <= 0 or parsed >= _MAX_RATE:
        raise InvalidExchangeRateError(
            "units_per_usd must be positive and fit Numeric(18, 8)"
        )
    return parsed


def _format_rate(value: Decimal) -> str:
    return format(value.quantize(_RATE_QUANTUM), ".8f")


def _precision_for(value: Decimal) -> int:
    parts = value.as_tuple()
    exponent = parts.exponent if isinstance(parts.exponent, int) else 0
    return len(parts.digits) + abs(exponent) + max(value.adjusted(), 0) + 8


def _quantize_amount(value: Decimal) -> Decimal:
    with localcontext() as context:
        context.prec = max(context.prec, _precision_for(value))
        return value.quantize(_AMOUNT_QUANTUM, rounding=ROUND_HALF_UP)


def _rate_record(rate: ExchangeRate) -> ExchangeRateRecord:
    return {
        "id": rate.id,
        "currency": rate.currency,
        "units_per_usd": _format_rate(rate.units_per_usd),
        "source": rate.source,
        "created_at": rate.created_at,
        "created_by": rate.created_by,
    }


def create_rate(
    *,
    session_factory: sessionmaker[Session],
    currency: str,
    units_per_usd: str,
    created_by: str,
) -> ExchangeRateRecord:
    """Append a validated administered rate; USD is fixed and cannot be stored."""
    try:
        supported_currency = validate_currency(currency)
    except ValueError:
        raise InvalidExchangeRateError("currency is not supported") from None
    if supported_currency == "USD":
        raise InvalidExchangeRateError("USD is fixed at 1.00000000 and cannot be administered")
    value = _parse_units_per_usd(units_per_usd)
    if len(created_by) > 36 or not created_by:
        raise InvalidExchangeRateError("created_by must identify a staff account")

    with session_factory.begin() as session:
        rate = ExchangeRate(
            currency=supported_currency,
            units_per_usd=value,
            source="manual",
            created_by=created_by,
        )
        session.add(rate)
        session.flush()
        session.refresh(rate)
        return _rate_record(rate)


def current_rates(
    *, session_factory: sessionmaker[Session]
) -> list[CurrentExchangeRateRecord]:
    """Return the latest administered rate per currency and the fixed USD rate."""
    with session_factory() as session:
        rates = (
            session.query(ExchangeRate)
            .order_by(ExchangeRate.created_at.desc(), ExchangeRate.id.desc())
            .all()
        )
    newest_by_currency: dict[str, ExchangeRate] = {}
    for rate in rates:
        newest_by_currency.setdefault(rate.currency, rate)

    current: list[CurrentExchangeRateRecord] = []
    for currency in SUPPORTED_CURRENCIES:
        if currency == "USD":
            current.append(
                {
                    "currency": currency,
                    "units_per_usd": "1.00000000",
                    "created_at": None,
                    "source": None,
                }
            )
            continue
        rate = newest_by_currency.get(currency)
        current.append(
            {
                "currency": currency,
                "units_per_usd": (
                    _format_rate(rate.units_per_usd) if rate is not None else None
                ),
                "created_at": rate.created_at if rate is not None else None,
                "source": rate.source if rate is not None else None,
            }
        )
    return current


def refresh_official_rates(session: Session) -> dict[str, str]:
    """Ingest official rates into new rows, per currency, in the caller's transaction.

    A new rate row (carrying the official source label) is appended only when the
    fetched value differs from the latest stored value for that currency; otherwise
    the run is a no-op. Manual rows are never overwritten — they are superseded.
    """
    try:
        suggestions = fetch_official_rates()
    except RateSourceError as error:
        reason = str(error)
        return {currency: f"error: {reason}" for currency in _OFFICIAL_CURRENCIES}

    latest: dict[str, ExchangeRate] = {}
    rows = (
        session.query(ExchangeRate)
        .order_by(ExchangeRate.created_at.desc(), ExchangeRate.id.desc())
        .all()
    )
    for row in rows:
        latest.setdefault(row.currency, row)

    outcomes: dict[str, str] = {}
    for currency in _OFFICIAL_CURRENCIES:
        suggestion = suggestions[currency]
        current = latest.get(currency)
        if current is not None and current.units_per_usd == suggestion.units_per_usd:
            outcomes[currency] = "unchanged"
            continue
        session.add(
            ExchangeRate(
                currency=currency,
                units_per_usd=suggestion.units_per_usd,
                source=suggestion.source,
                created_by=None,
            )
        )
        outcomes[currency] = "created"
    session.flush()
    return outcomes


def current_conversion_rates(*, session: Session) -> dict[str, Decimal | None]:
    """Return rates usable by a quote, reading the latest values in its transaction."""
    rows = (
        session.query(ExchangeRate)
        .order_by(ExchangeRate.created_at.desc(), ExchangeRate.id.desc())
        .all()
    )
    current: dict[str, Decimal | None] = {
        "BOB": None,
        "USD": Decimal("1.00000000"),
        "USDT": None,
    }
    for rate in rows:
        if current[rate.currency] is None:
            current[rate.currency] = rate.units_per_usd
    return current


def rate_history(
    *, session_factory: sessionmaker[Session], currency: str
) -> list[ExchangeRateRecord]:
    """Return an administered currency's audit history, newest row first."""
    try:
        supported_currency = validate_currency(currency)
    except ValueError:
        raise InvalidExchangeRateError("currency is not supported") from None
    with session_factory() as session:
        rates = (
            session.query(ExchangeRate)
            .filter(ExchangeRate.currency == supported_currency)
            .order_by(ExchangeRate.created_at.desc(), ExchangeRate.id.desc())
            .all()
        )
        return [_rate_record(rate) for rate in rates]


def all_rate_history(
    *, session_factory: sessionmaker[Session]
) -> list[ExchangeRateRecord]:
    """Return every administered rate, newest row first."""
    with session_factory() as session:
        rates = (
            session.query(ExchangeRate)
            .order_by(ExchangeRate.created_at.desc(), ExchangeRate.id.desc())
            .all()
        )
        return [_rate_record(rate) for rate in rates]


def _conversion_rate(
    currency: str, rates: Mapping[str, Decimal | str | None]
) -> Decimal:
    raw_rate = rates.get(currency)
    if raw_rate is None:
        raise MissingExchangeRateError(f"No current exchange rate is available for {currency}")
    if not isinstance(raw_rate, (Decimal, str)):
        raise InvalidConversionError("Exchange rates must be Decimal values or decimal strings")
    try:
        rate = raw_rate if isinstance(raw_rate, Decimal) else Decimal(raw_rate)
    except InvalidOperation:
        raise InvalidConversionError("An exchange rate is invalid") from None
    if not rate.is_finite() or rate <= 0:
        raise InvalidConversionError("Exchange rates must be finite and positive")
    return rate


def convert(
    amount: Decimal,
    source_currency: str,
    target_currency: str,
    *,
    rates: Mapping[str, Decimal | str | None],
) -> Decimal:
    """Convert through USD and round once to two places using ROUND_HALF_UP."""
    if not isinstance(amount, Decimal) or not amount.is_finite():
        raise InvalidConversionError("Conversion amounts must be finite Decimal values")
    try:
        source = validate_currency(source_currency)
        target = validate_currency(target_currency)
    except ValueError:
        raise InvalidConversionError("Conversion currency is not supported") from None

    if source == target:
        return _quantize_amount(amount)

    source_rate = Decimal("1") if source == "USD" else _conversion_rate(source, rates)
    target_rate = Decimal("1") if target == "USD" else _conversion_rate(target, rates)
    precision = max(
        50,
        _precision_for(amount)
        + _precision_for(source_rate)
        + _precision_for(target_rate),
    )

    with localcontext() as context:
        context.prec = precision
        usd_amount = amount if source == "USD" else amount / source_rate
        converted = usd_amount if target == "USD" else usd_amount * target_rate
        return converted.quantize(_AMOUNT_QUANTUM, rounding=ROUND_HALF_UP)
