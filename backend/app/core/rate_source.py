"""Official exchange-rate sources for automatic ingestion.

Two currencies are ingested automatically; USD stays the fixed 1.0 reference and is
never fetched:

- ``USDT``: Coinbase public spot price (``USDT-USD``, keyless). This is an exchange
  midpoint of a stablecoin pair, **not** an official FX rate; it is labeled
  ``coinbase`` so consumers can present it honestly.
- ``BOB``: Bolivia's official rate is administratively fixed by the Banco Central de
  Bolivia, so it is modeled as a static official source read from
  ``ROOMFORGE_OFFICIAL_BOB_RATE`` (default ``6.96``), labeled ``bcb-static``.

Every failure fails closed with :class:`RateSourceError`; a rate is never guessed.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from urllib.request import Request, urlopen

RATE_REFRESH_SECONDS_ENV = "ROOMFORGE_RATE_REFRESH_SECONDS"
OFFICIAL_BOB_RATE_ENV = "ROOMFORGE_OFFICIAL_BOB_RATE"

_DEFAULT_RATE_REFRESH_SECONDS = 21600
_DEFAULT_OFFICIAL_BOB_RATE = "6.96"

_COINBASE_SPOT_URL = "https://api.coinbase.com/v2/prices/USDT-USD/spot"
_COINBASE_TIMEOUT_SECONDS = 10
_RATE_QUANTUM = Decimal("0.00000001")
_MAX_RATE = Decimal("10000000000")

_SOURCES = {
    "USDT": "coinbase",
    "BOB": "bcb-static",
}


class RateSourceError(RuntimeError):
    """Raised when an official rate cannot be fetched from its source."""


@dataclass(frozen=True)
class RateSuggestion:
    """An ingested official rate for one currency, expressed per 1 USD."""

    currency: str
    units_per_usd: Decimal
    source: str


def _parse_positive_rate(raw: object, *, source: str, invert: bool = False) -> Decimal:
    if not isinstance(raw, str):
        raise RateSourceError(f"{source} returned a non-string rate value")
    try:
        value = Decimal(raw)
    except InvalidOperation:
        raise RateSourceError(f"{source} returned a malformed rate value") from None
    if not value.is_finite() or value <= 0:
        raise RateSourceError(f"{source} returned a non-positive rate value")
    if value >= _MAX_RATE:
        raise RateSourceError(f"{source} returned a rate beyond the supported precision")
    if invert:
        # Price sources quote 1 currency unit in USD; our convention is units
        # of the currency per 1 USD, so the price must be inverted.
        value = Decimal(1) / value
        if value >= _MAX_RATE:
            raise RateSourceError(f"{source} returned a price too small to invert")
    return value.quantize(_RATE_QUANTUM, rounding=ROUND_HALF_UP)


def _fetch_usdt_suggestion() -> RateSuggestion:
    request = Request(  # noqa: S310 - fixed HTTPS endpoint, no user input
        _COINBASE_SPOT_URL,
        headers={"Accept": "application/json", "User-Agent": "roomforge-backend"},
    )
    try:
        with urlopen(request, timeout=_COINBASE_TIMEOUT_SECONDS) as response:  # noqa: S310
            if response.status != 200:
                raise RateSourceError(
                    f"coinbase spot price request failed: HTTP {response.status}"
                )
            payload = json.loads(response.read().decode("utf-8"))
    except RateSourceError:
        raise
    except (OSError, ValueError) as error:
        raise RateSourceError(
            f"coinbase spot price request failed: {error}"
        ) from None
    if not isinstance(payload, dict) or not isinstance(payload.get("data"), dict):
        raise RateSourceError("coinbase spot price response is malformed")
    return RateSuggestion(
        currency="USDT",
        units_per_usd=_parse_positive_rate(
            payload["data"].get("amount"), source="coinbase", invert=True
        ),
        source=_SOURCES["USDT"],
    )


def _fetch_bob_suggestion() -> RateSuggestion:
    raw = os.environ.get(OFFICIAL_BOB_RATE_ENV, _DEFAULT_OFFICIAL_BOB_RATE)
    return RateSuggestion(
        currency="BOB",
        units_per_usd=_parse_positive_rate(raw, source="bcb-static"),
        source=_SOURCES["BOB"],
    )


def fetch_official_rates() -> dict[str, RateSuggestion]:
    """Fetch the official rates for the ingested currencies; failures fail closed."""
    return {
        "USDT": _fetch_usdt_suggestion(),
        "BOB": _fetch_bob_suggestion(),
    }


def official_rate_refresh_interval_seconds() -> int:
    """Read the background refresh interval; a value <= 0 disables the refresher."""
    raw = os.environ.get(RATE_REFRESH_SECONDS_ENV)
    if raw is None:
        return _DEFAULT_RATE_REFRESH_SECONDS
    try:
        return int(raw)
    except ValueError:
        raise RuntimeError(f"{RATE_REFRESH_SECONDS_ENV} must be an integer") from None
