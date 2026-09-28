from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Header, Request, status
from sqlalchemy.orm import Session, sessionmaker

from app.modules.customer_identity.schemas import CustomerErrorResponse
from app.modules.customer_identity.session import ActiveCustomer, get_active_customer
from app.modules.identity.session import ActiveStaff, get_active_staff
from app.modules.reservations.schemas import (
    CustomerReservationPermitRequest,
    ReservationCreateRequest,
    ReservationErrorResponse,
    ReservationPermitResponse,
    ReservationResponse,
    StaffReservationPermitRequest,
)
from app.modules.reservations.service import (
    create_reservation,
    get_customer_reservation,
    issue_reservation_permit,
    list_customer_reservations,
)


router = APIRouter(prefix="/api/v1/reservations", tags=["reservations"])
staff_router = APIRouter(prefix="/api/v1/staff/reservations", tags=["staff-reservations"])
_RESERVATION_ERRORS = {
    403: ReservationErrorResponse,
    404: ReservationErrorResponse,
    409: ReservationErrorResponse,
}
_PERMIT_ERRORS = {**_RESERVATION_ERRORS, 503: ReservationErrorResponse}


def _session_factory(request: Request) -> sessionmaker[Session]:
    return request.app.state.session_factory


def _authenticated_customer(request: Request) -> ActiveCustomer:
    return get_active_customer(request)


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    response_model=ReservationResponse,
    responses={
        401: {"model": CustomerErrorResponse, "description": "Invalid customer session"},
        **{
            code: {"model": schema, "description": "Reservation request conflict or validation error"}
            for code, schema in _RESERVATION_ERRORS.items()
        },
        422: {"model": ReservationErrorResponse, "description": "Invalid reservation request"},
    },
)
def create(
    body: ReservationCreateRequest,
    request: Request,
    idempotency_key: Annotated[
        str, Header(alias="Idempotency-Key", min_length=1, max_length=128, pattern=r"\S")
    ],
    customer: ActiveCustomer = Depends(_authenticated_customer),
) -> ReservationResponse:
    return create_reservation(
        session_factory=_session_factory(request),
        customer_id=customer["id"],
        listing_id=body.listing_id,
        quote_id=body.quote_id,
        customer_wallet_id=body.customer_wallet_id,
        idempotency_key=idempotency_key,
        now=request.app.state.clock(),
    )


@router.get(
    "",
    response_model=list[ReservationResponse],
    responses={401: {"model": CustomerErrorResponse, "description": "Invalid customer session"}},
)
def list_own(
    request: Request,
    customer: ActiveCustomer = Depends(_authenticated_customer),
) -> list[ReservationResponse]:
    return list_customer_reservations(
        session_factory=_session_factory(request),
        customer_id=customer["id"],
        now=request.app.state.clock(),
    )


@router.get(
    "/{reservation_id}",
    response_model=ReservationResponse,
    responses={
        401: {"model": CustomerErrorResponse, "description": "Invalid customer session"},
        404: {"model": ReservationErrorResponse, "description": "Reservation not found"},
    },
)
def get_own(
    reservation_id: str,
    request: Request,
    customer: ActiveCustomer = Depends(_authenticated_customer),
) -> ReservationResponse:
    return get_customer_reservation(
        session_factory=_session_factory(request),
        customer_id=customer["id"],
        reservation_id=reservation_id,
        now=request.app.state.clock(),
    )


@router.post(
    "/{reservation_id}/permit",
    response_model=ReservationPermitResponse,
    responses={
        401: {"model": CustomerErrorResponse, "description": "Invalid customer session"},
        **{
            code: {"model": schema, "description": "Permit action is not eligible or unavailable"}
            for code, schema in _PERMIT_ERRORS.items()
        },
        422: {"model": ReservationErrorResponse, "description": "Invalid permit request"},
    },
)
def customer_permit(
    reservation_id: str,
    body: CustomerReservationPermitRequest,
    request: Request,
    customer: ActiveCustomer = Depends(_authenticated_customer),
) -> ReservationPermitResponse:
    permit = issue_reservation_permit(
        session_factory=_session_factory(request),
        settings=request.app.state.settings,
        transport=getattr(request.app.state, "reservation_rpc_transport", None),
        reservation_id=reservation_id,
        actor=customer,
        action=body.action,
        now=request.app.state.clock(),
    )
    return ReservationPermitResponse.model_validate(permit)


@staff_router.post(
    "/{reservation_id}/permit",
    response_model=ReservationPermitResponse,
    responses={
        401: {"description": "Invalid staff session"},
        **{
            code: {"model": schema, "description": "Permit action is not eligible or unavailable"}
            for code, schema in _PERMIT_ERRORS.items()
        },
        422: {"model": ReservationErrorResponse, "description": "Invalid permit request"},
    },
)
def staff_permit(
    reservation_id: str,
    body: StaffReservationPermitRequest,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ReservationPermitResponse:
    permit = issue_reservation_permit(
        session_factory=_session_factory(request),
        settings=request.app.state.settings,
        transport=getattr(request.app.state, "reservation_rpc_transport", None),
        reservation_id=reservation_id,
        actor=staff,
        action=body.action,
        now=request.app.state.clock(),
    )
    return ReservationPermitResponse.model_validate(permit)
