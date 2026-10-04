"""HTTP routes for platform-managed and public exchange rates."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session, sessionmaker

from app.core.errors import ERROR_RESPONSES, ErrorResponse
from app.modules.customer_identity.session import get_active_customer
from app.modules.exchange_rates.errors import InvalidExchangeRateError
from app.modules.exchange_rates.schemas import (
    CurrentExchangeRateResponse,
    CurrentExchangeRatesResponse,
    ExchangeRateCreateRequest,
    ExchangeRateHistoryResponse,
    ExchangeRateResponse,
)
from app.modules.exchange_rates.service import (
    all_rate_history,
    create_rate,
    current_rates,
)
from app.modules.identity.session import ActiveStaff, get_active_staff


platform_router = APIRouter(
    prefix="/api/v1/platform/exchange-rates",
    tags=["platform-exchange-rates"],
    responses=ERROR_RESPONSES,
)
public_router = APIRouter(
    prefix="/api/v1/exchange-rates",
    tags=["exchange-rates"],
    responses=ERROR_RESPONSES,
)


def _session_factory(request: Request) -> sessionmaker[Session]:
    return request.app.state.session_factory


def _authenticated_staff(request: Request) -> ActiveStaff:
    try:
        return get_active_staff(request)
    except HTTPException as staff_error:
        if staff_error.status_code != status.HTTP_401_UNAUTHORIZED:
            raise
        try:
            get_active_customer(request)
        except HTTPException:
            raise staff_error from None
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Customer accounts cannot access platform exchange rates",
        ) from None


def _platform_admin(request: Request) -> ActiveStaff:
    staff = _authenticated_staff(request)
    if staff["role"] != "platform_admin":
        raise HTTPException(status_code=403, detail="Platform-admin role is required")
    return staff


@platform_router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    response_model=ExchangeRateResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Authentication required"},
        403: {"model": ErrorResponse, "description": "Forbidden"},
    },
)
def create(
    body: ExchangeRateCreateRequest,
    request: Request,
    staff: ActiveStaff = Depends(_platform_admin),
) -> ExchangeRateResponse:
    try:
        rate = create_rate(
            session_factory=_session_factory(request),
            currency=body.currency,
            units_per_usd=body.units_per_usd,
            created_by=staff["id"],
        )
    except InvalidExchangeRateError as error:
        raise HTTPException(status_code=422, detail=str(error)) from None
    return ExchangeRateResponse.model_validate(rate)


@platform_router.get(
    "",
    response_model=ExchangeRateHistoryResponse,
    responses={
        401: {"model": ErrorResponse, "description": "Authentication required"},
        403: {"model": ErrorResponse, "description": "Forbidden"},
    },
)
def list_history(
    request: Request,
    _staff: ActiveStaff = Depends(_platform_admin),
) -> ExchangeRateHistoryResponse:
    return ExchangeRateHistoryResponse(
        rates=[
            ExchangeRateResponse.model_validate(rate)
            for rate in all_rate_history(session_factory=_session_factory(request))
        ]
    )


@public_router.get("/current", response_model=CurrentExchangeRatesResponse)
def read_current(request: Request) -> CurrentExchangeRatesResponse:
    return CurrentExchangeRatesResponse(
        rates=[
            CurrentExchangeRateResponse.model_validate(rate)
            for rate in current_rates(session_factory=_session_factory(request))
        ]
    )
