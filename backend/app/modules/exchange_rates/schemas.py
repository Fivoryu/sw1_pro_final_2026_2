"""Request and response schemas for exchange-rate endpoints."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.core.money import SupportedCurrency


class ExchangeRateCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    currency: Literal["BOB", "USD", "USDT"]
    units_per_usd: str = Field(strict=True)


class ExchangeRateResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: int
    currency: SupportedCurrency
    units_per_usd: str
    created_at: datetime
    created_by: str


class ExchangeRateHistoryResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    rates: list[ExchangeRateResponse]


class CurrentExchangeRateResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    currency: SupportedCurrency
    units_per_usd: str | None
    created_at: datetime | None


class CurrentExchangeRatesResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    rates: list[CurrentExchangeRateResponse]
