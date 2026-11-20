from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.modules.catalog.schemas import CatalogListingItem, ListingOperation
from app.modules.catalog.service import normalize_geo_key


class FavoriteItem(BaseModel):
    """A favorite; [listing] is null when the listing is no longer public."""

    model_config = ConfigDict(extra="forbid")

    listing_id: str
    favorited_at: datetime
    available: bool
    listing: CatalogListingItem | None


class FavoriteList(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[FavoriteItem]


class SavedSearchFilters(BaseModel):
    """The public catalog filters, with the same rules as `GET /api/v1/listings`.

    The zone search point (`latitude`, `longitude`, `radius_km`) is left out on
    purpose: the customer's location travels only as a query parameter and is
    never stored (F14.5, S4), so a request that includes it is rejected.
    """

    model_config = ConfigDict(extra="forbid")

    city: str | None = Field(default=None, max_length=120)
    zone: str | None = Field(default=None, max_length=120)
    operation: ListingOperation | None = None
    min_base_price: Decimal | None = Field(default=None, ge=0, max_digits=18, decimal_places=2)
    max_base_price: Decimal | None = Field(default=None, ge=0, max_digits=18, decimal_places=2)
    min_rooms: int | None = Field(default=None, ge=0)
    min_bathrooms: int | None = Field(default=None, ge=0)

    @field_validator("city", "zone")
    @classmethod
    def not_blank(cls, value: str | None) -> str | None:
        if value is not None and not normalize_geo_key(value):
            raise ValueError("must not be blank")
        return value.strip() if value is not None else None

    @model_validator(mode="after")
    def consistent(self) -> SavedSearchFilters:
        if (
            self.min_base_price is not None
            and self.max_base_price is not None
            and self.min_base_price > self.max_base_price
        ):
            raise ValueError("min_base_price must not exceed max_base_price")
        return self


class SavedSearchCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(max_length=80)
    filters: SavedSearchFilters

    @field_validator("name")
    @classmethod
    def name_not_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("name must not be blank")
        return stripped


class SavedSearchView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    name: str
    filters: SavedSearchFilters
    created_at: datetime


class SavedSearchList(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[SavedSearchView]
