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


class CustomerReservationPermitRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    action: Literal["deposit", "cancel"]


class StaffReservationPermitRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    action: Literal["accept", "reject", "cancel"]


class CustomerReservationChainTransactionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    action: Literal["deposit", "cancel", "expire"]
    transaction_hash: str = Field(pattern=r"^0x[0-9a-fA-F]{64}$")
    nonce: int = Field(ge=0)


class StaffReservationChainTransactionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    action: Literal["accept", "reject", "cancel", "expire"]
    transaction_hash: str = Field(pattern=r"^0x[0-9a-fA-F]{64}$")
    nonce: int = Field(ge=0)


class ReservationChainTransactionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reservation_id: str
    status: Literal["pending", "accepted", "rejected", "cancelled", "expired"]
    replayed: bool
    chain_id: int
    tx_hash: str
    action: Literal["deposit", "accept", "reject", "cancel", "expire"]
    event_name: str
    event_signature: str
    event_topic: str
    log_index: int
    block_number: int
    block_hash: str
    block_timestamp: int
    transaction_index: int | None
    amount: int
    nonce: int
    escrow_address: str
    participant: str
    actor: str | None


class ReservationPermitResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reservationId: str
    listingId: str
    customer: str
    agency: str
    actor: str
    action: Literal[0, 1, 2, 3]
    amount: int
    deadline: int
    nonce: int
    signature: str


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
