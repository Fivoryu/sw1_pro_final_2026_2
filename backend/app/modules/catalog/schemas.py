"""Public catalog and quote schemas."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StrictInt

from app.core.money import SupportedCurrency

# Single source of truth for the listing operation domain; the ORM stores it as a plain
# string guarded by a CHECK constraint, so routers cast database values to this alias.
ListingOperation = Literal["sale", "rent"]
ListingApprovalStatus = Literal["draft", "pending", "approved", "rejected"]


class CatalogMoney(BaseModel):
    model_config = ConfigDict(extra="forbid")

    amount: str
    currency: SupportedCurrency


class CatalogListingItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    listing_id: str
    offer_version: int
    operation: ListingOperation
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
    currency: SupportedCurrency
    charge_period: Literal["one_time", "monthly"]


class QuoteSnapshotResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    quote_id: str
    listing_id: str
    offer_version: int
    operation: ListingOperation
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

    deposit_amount: Annotated[
        Decimal,
        Field(gt=Decimal("0"), max_digits=18, decimal_places=2),
    ]


class ListingDepositResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    listing_id: str
    deposit_amount: str
    offer_version: int


class ListingAuthoringRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    operation: ListingOperation
    base_price: Annotated[
        Decimal,
        Field(gt=Decimal("0"), max_digits=18, decimal_places=2),
    ]
    currency: SupportedCurrency = "BOB"
    city: Annotated[str, Field(min_length=1, max_length=120)]
    zone: Annotated[str, Field(min_length=1, max_length=120)]
    bedrooms: Annotated[StrictInt, Field(ge=0)]
    bathrooms: Annotated[StrictInt, Field(ge=0)]
    description: str | None = None
    exact_address: str | None = None


class ListingTransitionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    observation: str | None = None


class ListingAuthoringResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    listing_id: str
    agency_id: str
    operation: ListingOperation
    base_price: Decimal
    currency: SupportedCurrency
    city: str
    zone: str
    bedrooms: int
    bathrooms: int
    description: str | None
    exact_address: str | None
    approval_status: ListingApprovalStatus
    is_published: bool
    offer_version: int
    created_at: datetime


class StaffListingPagination(BaseModel):
    model_config = ConfigDict(extra="forbid")

    limit: int = Field(ge=1, le=100)
    offset: int = Field(ge=0)
    total: int = Field(ge=0)


class StaffListingPage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    listings: list[ListingAuthoringResponse]
    pagination: StaffListingPagination


class ListingTransitionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", from_attributes=True)

    id: str
    agency_id: str
    listing_id: str
    action: Literal["create", "edit", "submit", "approve", "reject", "publish", "unpublish"]
    from_status: str | None
    from_published: bool | None
    to_status: str
    to_published: bool
    observation: str | None
    actor_id: str
    actor_role: str
    created_at: datetime
