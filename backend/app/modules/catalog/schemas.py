"""Public catalog and quote schemas."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StrictInt


class CatalogMoney(BaseModel):
    model_config = ConfigDict(extra="forbid")

    amount: str
    currency: Literal["COP"]


class CatalogListingItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    listing_id: str
    offer_version: int
    operation: Literal["sale", "rent"]
    base_price: CatalogMoney
    city: str
    zone: str


class CatalogExtraItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    extra_id: str
    name: str
    price: CatalogMoney


class CatalogListingDetail(CatalogListingItem):
    bedrooms: int
    bathrooms: int
    extras: list[CatalogExtraItem]


class CatalogListingPage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[CatalogListingItem]
    next_cursor: str | None


class QuoteCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    listing_id: Annotated[str, Field(min_length=1, max_length=36)]
    offer_version: Annotated[StrictInt, Field(ge=1)]
    selected_extra_ids: list[Annotated[str, Field(min_length=1, max_length=36)]] = Field(
        default_factory=list
    )


class QuoteLine(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["base", "extra"]
    extra_id: str | None
    amount: str
    currency: Literal["COP"]
    charge_period: Literal["one_time", "monthly"]


class QuoteSnapshotResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    quote_id: str
    listing_id: str
    offer_version: int
    operation: Literal["sale", "rent"]
    lines: list[QuoteLine]
    one_time_total: CatalogMoney
    monthly_total: CatalogMoney
    created_at: datetime
    expires_at: datetime


class QuoteErrorField(BaseModel):
    model_config = ConfigDict(extra="forbid")

    field: str
    message: str


class QuoteErrorResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: str
    message: str
    request_id: str
    field_errors: list[QuoteErrorField] = Field(default_factory=list)


class ListingDepositUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    deposit_amount_cop: Annotated[
        Decimal,
        Field(gt=Decimal("0"), max_digits=18, decimal_places=2),
    ]


class ListingDepositResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    listing_id: str
    deposit_amount_cop: str
    offer_version: int
