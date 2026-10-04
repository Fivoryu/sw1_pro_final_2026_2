"""Supported commercial currencies and exact money formatting."""

from decimal import Decimal, ROUND_HALF_UP
from typing import Literal


SupportedCurrency = Literal["BOB", "USD", "USDT"]
SUPPORTED_CURRENCIES: tuple[SupportedCurrency, ...] = ("BOB", "USD", "USDT")
_MONEY_QUANTUM = Decimal("0.01")


def validate_currency(value: object) -> str:
    """Return a supported currency code, rejecting any non-exact match."""
    if not isinstance(value, str) or value not in SUPPORTED_CURRENCIES:
        raise ValueError(f"Unsupported currency: {value!r}")
    return value


def format_money_amount(amount: Decimal) -> str:
    """Format a finite Decimal as a commercial amount rounded to two places."""
    if not isinstance(amount, Decimal):
        raise TypeError("Money amounts must be Decimal instances")
    if not amount.is_finite():
        raise ValueError("Money amounts must be finite")
    return format(amount.quantize(_MONEY_QUANTUM, rounding=ROUND_HALF_UP), ".2f")
