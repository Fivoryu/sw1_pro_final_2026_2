"""Request, response, and error schemas for customer reservations."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field

from app.modules.catalog.schemas import CatalogMoney, QuoteLine


class ReservationCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    listing_id: Annotated[str, Field(min_length=1, max_length=36)]
    quote_id: Annotated[str, Field(min_length=1, max_length=36)]
    customer_wallet_id: Annotated[str, Field(min_length=1, max_length=36)]


class ReservationQuoteSnapshotResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    quote_id: str
    offer_version: int
    operation: Literal["sale", "rent"]
    lines: list[QuoteLine]
    one_time_total: CatalogMoney
    monthly_total: CatalogMoney


class ReservationResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reservation_id: str
    listing_id: str
    status: Literal["pending", "accepted", "rejected", "cancelled", "expired"]
    api_created_at: datetime
    decision_deadline_at: datetime
    quote_snapshot: ReservationQuoteSnapshotResponse
    deposit_amount_cop: str | None


class ReservationErrorField(BaseModel):
    model_config = ConfigDict(extra="forbid")

    field: str
    message: str


class ReservationErrorResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: str
    message: str
    request_id: str
    field_errors: list[ReservationErrorField] = Field(default_factory=list)
