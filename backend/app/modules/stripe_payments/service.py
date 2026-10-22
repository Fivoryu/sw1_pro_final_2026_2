from __future__ import annotations

from decimal import Decimal, InvalidOperation


# Stripe accepts BOB and USD for card presentment in supported account regions.
# USDT is a crypto token, not a Stripe card currency.
_CARD_CURRENCY_MINOR_UNITS = {"BOB": 2, "USD": 2}


def stripe_currency(currency: str) -> str:
    normalized = currency.upper()
    if normalized not in _CARD_CURRENCY_MINOR_UNITS:
        raise ValueError(f"Currency {currency!r} is not supported for card payments")
    return normalized.lower()


def payment_amount_minor_units(amount: Decimal, currency: str) -> int:
    """Convert a server-owned decimal deposit to Stripe's integer minor units."""
    currency = currency.upper()
    exponent = _CARD_CURRENCY_MINOR_UNITS.get(currency)
    if exponent is None:
        raise ValueError(f"Currency {currency!r} is not supported for card payments")
    try:
        normalized = Decimal(amount)
    except (InvalidOperation, TypeError, ValueError):
        raise ValueError("Payment amount must be a finite positive decimal") from None
    if not normalized.is_finite() or normalized <= 0:
        raise ValueError("Payment amount must be a finite positive decimal")
    scale = Decimal(10) ** exponent
    minor_units = normalized * scale
    if minor_units != minor_units.to_integral_value():
        raise ValueError("Payment amount must use the currency's exact minor unit")
    return int(minor_units)
