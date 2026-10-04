from decimal import Decimal

import pytest

from app.core.money import (
    SUPPORTED_CURRENCIES,
    format_money_amount,
    validate_currency,
)


@pytest.mark.parametrize("currency", ["BOB", "USD", "USDT"])
def test_validate_currency_accepts_exact_supported_codes(currency: str) -> None:
    assert validate_currency(currency) == currency


def test_supported_currencies_contains_exactly_the_currency_domain() -> None:
    assert SUPPORTED_CURRENCIES == ("BOB", "USD", "USDT")


@pytest.mark.parametrize("value", ["bob", "usd", "usdt", "", "COP", "EUR", None])
def test_validate_currency_rejects_values_outside_the_exact_domain(value: object) -> None:
    with pytest.raises(ValueError):
        validate_currency(value)


@pytest.mark.parametrize(
    ("amount", "expected"),
    [
        (Decimal("1.005"), "1.01"),
        (Decimal("1.004"), "1.00"),
        (Decimal("38"), "38.00"),
        (Decimal("-1.005"), "-1.01"),
    ],
)
def test_format_money_amount_uses_two_decimals_and_round_half_up(
    amount: Decimal, expected: str
) -> None:
    assert format_money_amount(amount) == expected


@pytest.mark.parametrize("amount", [Decimal("NaN"), Decimal("Infinity"), Decimal("-Infinity")])
def test_format_money_amount_rejects_non_finite_decimals(amount: Decimal) -> None:
    with pytest.raises(ValueError):
        format_money_amount(amount)


def test_format_money_amount_rejects_non_decimal_input() -> None:
    with pytest.raises(TypeError):
        format_money_amount(1.005)  # type: ignore[arg-type]
