"""Public catalog response schemas."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict


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
