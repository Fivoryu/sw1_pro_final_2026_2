"""Public catalog read endpoints and quote creation."""

from __future__ import annotations

from decimal import Decimal
from typing import Annotated, cast

from fastapi import APIRouter, Depends, HTTPException, Path, Query, Request
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from app.core.money import SupportedCurrency, format_money_amount
from app.modules.catalog.errors import (
    InvalidQuoteExtrasError,
    QuoteApiError,
    QuoteNotFoundError,
    QuoteOfferVersionMismatchError,
    UnsupportedRateLimitDialectError,
)
from app.modules.catalog.models import Listing, QuoteSnapshot
from app.modules.exchange_rates.errors import MissingExchangeRateError
from app.modules.catalog.schemas import (
    CatalogExtraItem,
    CatalogListingDetail,
    CatalogListingItem,
    CatalogListingPage,
    CatalogMoney,
    ListingApprovalStatus,
    ListingOperation,
    QuoteCreateRequest,
    QuoteDisplayRate,
    QuoteDisplayTotals,
    QuoteErrorResponse,
    QuoteLine,
    QuoteSnapshotResponse,
    ListingDepositResponse,
    ListingDepositUpdateRequest,
    ListingAuthoringRequest,
    ListingAuthoringResponse,
    ListingTransitionRequest,
    ListingTransitionResponse,
    StaffListingPage,
    StaffListingPagination,
)
from app.modules.catalog.errors import InvalidListingTransitionError
from app.modules.catalog.service import (
    configure_listing_deposit,
    create_staff_listing,
    edit_staff_listing,
    get_staff_listing,
    list_listing_transitions,
    list_staff_listings,
    InvalidCursorError,
    consume_quote_rate_limit,
    create_quote_snapshot,
    encode_cursor,
    get_public_listing,
    list_listing_extras,
    normalize_geo_key,
    search_public_listings,
    transition_staff_listing,
)
from app.modules.identity.session import ActiveStaff, get_active_staff


router = APIRouter()
listings_router = APIRouter(prefix="/api/v1/listings", tags=["catalog"])
quotes_router = APIRouter(prefix="/api/v1/quotes", tags=["quotes"])


def _money(amount: Decimal, currency: str) -> CatalogMoney:
    return CatalogMoney(
        amount=format_money_amount(amount), currency=cast(SupportedCurrency, currency)
    )


def _listing_item(listing: Listing) -> CatalogListingItem:
    return CatalogListingItem(
        listing_id=listing.id,
        offer_version=listing.offer_version,
        operation=cast(ListingOperation, listing.operation),
        base_price=_money(listing.base_price, listing.currency),
        city=listing.city,
        zone=listing.zone,
    )


@listings_router.get(
    "",
    response_model=CatalogListingPage,
    responses={400: {"description": "Invalid cursor"}},
)
def list_public_listings(
    request: Request,
    city: Annotated[str | None, Query(max_length=120)] = None,
    zone: Annotated[str | None, Query(max_length=120)] = None,
    operation: Annotated[ListingOperation | None, Query()] = None,
    min_base_price: Annotated[
        Decimal | None,
        Query(ge=0, max_digits=18, decimal_places=2),
    ] = None,
    max_base_price: Annotated[
        Decimal | None,
        Query(ge=0, max_digits=18, decimal_places=2),
    ] = None,
    min_rooms: Annotated[int | None, Query(ge=0)] = None,
    min_bathrooms: Annotated[int | None, Query(ge=0)] = None,
    cursor: Annotated[str | None, Query(max_length=512)] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> CatalogListingPage:
    if city is not None and not normalize_geo_key(city):
        raise HTTPException(status_code=422, detail="invalid_filter")
    if zone is not None and not normalize_geo_key(zone):
        raise HTTPException(status_code=422, detail="invalid_filter")
    if (
        min_base_price is not None
        and max_base_price is not None
        and min_base_price > max_base_price
    ):
        raise HTTPException(status_code=422, detail="invalid_filter")

    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        try:
            listings, has_more = search_public_listings(
                session,
                city=city,
                zone=zone,
                operation=operation,
                min_base_price=min_base_price,
                max_base_price=max_base_price,
                min_rooms=min_rooms,
                min_bathrooms=min_bathrooms,
                limit=limit,
                cursor_value=cursor,
            )
        except InvalidCursorError:
            raise HTTPException(status_code=400, detail="invalid_cursor") from None

    next_cursor = encode_cursor(listings[-1].created_at, listings[-1].id) if has_more else None
    return CatalogListingPage(
        items=[_listing_item(listing) for listing in listings],
        next_cursor=next_cursor,
    )


@listings_router.get(
    "/{listing_id}",
    response_model=CatalogListingDetail,
    responses={404: {"description": "Listing not found"}},
)
def get_public_listing_detail(
    listing_id: Annotated[str, Path(min_length=1, max_length=36)], request: Request
) -> CatalogListingDetail:
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        listing = get_public_listing(session, listing_id)
        if listing is None:
            raise HTTPException(status_code=404, detail="listing_not_found")
        extras = list_listing_extras(session, listing.id)
        return CatalogListingDetail(
            **_listing_item(listing).model_dump(),
            bedrooms=listing.bedrooms,
            bathrooms=listing.bathrooms,
            extras=[
                CatalogExtraItem(
                    extra_id=extra.id,
                    name=extra.name,
                    price=_money(extra.price, listing.currency),
                )
                for extra in extras
            ],
        )


def _quote_response(quote: QuoteSnapshot) -> QuoteSnapshotResponse:
    response = QuoteSnapshotResponse(
        quote_id=quote.id,
        listing_id=quote.listing_id,
        offer_version=quote.offer_version,
        operation=cast(ListingOperation, quote.operation),
        lines=[
            QuoteLine.model_validate({**line, "currency": quote.currency})
            for line in quote.lines
        ],
        one_time_total=_money(quote.one_time_total, quote.currency),
        monthly_total=_money(quote.monthly_total, quote.currency),
        created_at=quote.created_at,
        expires_at=quote.expires_at,
    )
    if quote.display_currency is None:
        return response

    assert quote.display_one_time_total is not None
    assert quote.display_monthly_total is not None
    assert quote.base_units_per_usd is not None
    assert quote.display_units_per_usd is not None
    return response.model_copy(
        update={
            "display_totals": QuoteDisplayTotals(
                one_time_total=_money(quote.display_one_time_total, quote.display_currency),
                monthly_total=_money(quote.display_monthly_total, quote.display_currency),
            ),
            "display_rate": QuoteDisplayRate(
                base_currency=cast(SupportedCurrency, quote.currency),
                display_currency=cast(SupportedCurrency, quote.display_currency),
                base_units_per_usd=format(quote.base_units_per_usd, ".8f"),
                display_units_per_usd=format(quote.display_units_per_usd, ".8f"),
            ),
        }
    )


@quotes_router.post(
    "",
    status_code=201,
    response_model=QuoteSnapshotResponse,
    response_model_exclude_unset=True,
    responses={
        404: {"model": QuoteErrorResponse, "description": "Listing not found"},
        409: {"model": QuoteErrorResponse, "description": "Offer version mismatch"},
        422: {"model": QuoteErrorResponse, "description": "Invalid quote request"},
        429: {
            "model": QuoteErrorResponse,
            "description": "Rate limit exceeded",
            "headers": {
                "Retry-After": {
                    "description": "Seconds until another quote request can be made.",
                    "schema": {"type": "integer", "minimum": 1},
                }
            },
        },
        503: {
            "model": QuoteErrorResponse,
            "description": "Quote service or required exchange rate unavailable",
        },
    },
)
def create_public_quote(body: QuoteCreateRequest, request: Request) -> QuoteSnapshotResponse:
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    client = request.client
    if client is None or not client.host:
        raise QuoteApiError(
            503,
            "quote_service_unavailable",
            "The quote service is temporarily unavailable.",
        )

    rate_limit_now = request.app.state.clock()
    try:
        with session_factory.begin() as session:
            retry_after = consume_quote_rate_limit(
                session,
                client_ip=client.host,
                now=rate_limit_now,
                hmac_secret=request.app.state.settings.jwt_secret,
            )
    except UnsupportedRateLimitDialectError:
        raise QuoteApiError(
            503,
            "quote_service_unavailable",
            "The quote service is temporarily unavailable.",
        ) from None
    except SQLAlchemyError:
        raise QuoteApiError(
            503,
            "quote_service_unavailable",
            "The quote service is temporarily unavailable.",
        ) from None

    if retry_after is not None:
        raise QuoteApiError(
            429,
            "rate_limit_exceeded",
            "Too many quote requests from this IP address.",
            headers={"Retry-After": str(retry_after)},
        )

    try:
        with session_factory.begin() as session:
            quote = create_quote_snapshot(
                session,
                listing_id=body.listing_id,
                expected_offer_version=body.offer_version,
                selected_extra_ids=body.selected_extra_ids,
                clock=request.app.state.clock,
                target_currency=body.target_currency,
            )
            return _quote_response(quote)
    except QuoteNotFoundError:
        raise QuoteApiError(
            404,
            "listing_not_found",
            "The listing was not found.",
        ) from None
    except QuoteOfferVersionMismatchError:
        raise QuoteApiError(
            409,
            "offer_version_mismatch",
            "The listing offer has changed.",
        ) from None
    except InvalidQuoteExtrasError:
        raise QuoteApiError(
            422,
            "invalid_extra_selection",
            "Selected extras must be unique and belong to the listing.",
            field_errors=[
                {"field": "selected_extra_ids", "message": "Invalid extra selection."}
            ],
        ) from None
    except MissingExchangeRateError:
        raise QuoteApiError(
            503,
            "exchange_rate_unavailable",
            "A required exchange rate is not available for this quote.",
        ) from None
    except SQLAlchemyError:
        raise QuoteApiError(
            503,
            "quote_service_unavailable",
            "The quote service is temporarily unavailable.",
        ) from None


@router.patch(
    "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/deposit",
    response_model=ListingDepositResponse,
)
def set_listing_deposit(
    agency_id: str,
    listing_id: str,
    body: ListingDepositUpdateRequest,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingDepositResponse:
    if staff["role"] != "agency_admin" or staff["tenant_id"] != agency_id:
        raise HTTPException(status_code=403, detail="Agency-admin tenant access is required")

    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory.begin() as session:
        listing = configure_listing_deposit(
            session,
            agency_id=agency_id,
            listing_id=listing_id,
            deposit_amount=body.deposit_amount,
        )
        if listing is None:
            raise HTTPException(status_code=404, detail="Listing not found")
        assert listing.deposit_amount is not None
        return ListingDepositResponse(
            listing_id=listing.id,
            deposit_amount=format_money_amount(listing.deposit_amount),
            offer_version=listing.offer_version,
        )


def _require_listing_editor(staff: ActiveStaff, agency_id: str) -> None:
    if staff["role"] not in {"agency_admin", "agent"} or staff["tenant_id"] != agency_id:
        raise HTTPException(status_code=403, detail="Agency tenant access is required")


def _require_listing_admin(staff: ActiveStaff, agency_id: str) -> None:
    if staff["role"] != "agency_admin" or staff["tenant_id"] != agency_id:
        raise HTTPException(status_code=403, detail="Agency-admin tenant access is required")


def _authoring_response(listing: Listing) -> ListingAuthoringResponse:
    return ListingAuthoringResponse(
        listing_id=listing.id,
        agency_id=listing.agency_id,
        operation=cast(ListingOperation, listing.operation),
        base_price=listing.base_price,
        currency=cast(SupportedCurrency, listing.currency),
        city=listing.city,
        zone=listing.zone,
        bedrooms=listing.bedrooms,
        bathrooms=listing.bathrooms,
        description=listing.description,
        exact_address=listing.exact_address,
        approval_status=cast(ListingApprovalStatus, listing.approval_status),
        is_published=listing.is_published,
        offer_version=listing.offer_version,
        created_at=listing.created_at,
    )


@router.post(
    "/api/v1/staff/agencies/{agency_id}/listings",
    status_code=201,
    response_model=ListingAuthoringResponse,
)
def create_agency_listing(
    agency_id: str,
    body: ListingAuthoringRequest,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingAuthoringResponse:
    _require_listing_editor(staff, agency_id)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory.begin() as session:
        listing = create_staff_listing(
            session,
            agency_id=agency_id,
            content=body,
            actor_id=staff["id"],
            actor_role=staff["role"],
            now=request.app.state.clock(),
        )
        return _authoring_response(listing)


@router.get(
    "/api/v1/staff/agencies/{agency_id}/listings",
    response_model=StaffListingPage,
)
def list_agency_listings(
    agency_id: str,
    request: Request,
    status: Annotated[ListingApprovalStatus | None, Query()] = None,
    published: Annotated[bool | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
    staff: ActiveStaff = Depends(get_active_staff),
) -> StaffListingPage:
    _require_listing_editor(staff, agency_id)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        listings, total = list_staff_listings(
            session,
            agency_id=agency_id,
            approval_status=status,
            is_published=published,
            limit=limit,
            offset=offset,
        )
        return StaffListingPage(
            listings=[_authoring_response(listing) for listing in listings],
            pagination=StaffListingPagination(limit=limit, offset=offset, total=total),
        )


@router.get(
    "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}",
    response_model=ListingAuthoringResponse,
)
def get_agency_listing(
    agency_id: str,
    listing_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingAuthoringResponse:
    _require_listing_editor(staff, agency_id)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        listing = get_staff_listing(session, agency_id=agency_id, listing_id=listing_id)
        if listing is None:
            raise HTTPException(status_code=404, detail="Listing not found")
        return _authoring_response(listing)


@router.put(
    "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}",
    response_model=ListingAuthoringResponse,
)
def replace_agency_listing(
    agency_id: str,
    listing_id: str,
    body: ListingAuthoringRequest,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingAuthoringResponse:
    _require_listing_editor(staff, agency_id)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory.begin() as session:
        listing = edit_staff_listing(
            session,
            agency_id=agency_id,
            listing_id=listing_id,
            content=body,
            actor_id=staff["id"],
            actor_role=staff["role"],
            now=request.app.state.clock(),
        )
        if listing is None:
            raise HTTPException(status_code=404, detail="Listing not found")
        return _authoring_response(listing)


def _apply_listing_transition(
    *,
    agency_id: str,
    listing_id: str,
    action: str,
    request: Request,
    staff: ActiveStaff,
    body: ListingTransitionRequest | None,
    admin_only: bool = False,
) -> ListingAuthoringResponse:
    if admin_only:
        _require_listing_admin(staff, agency_id)
    else:
        _require_listing_editor(staff, agency_id)
    observation = body.observation if body is not None else None
    if action == "reject" and (observation is None or not observation.strip()):
        raise HTTPException(status_code=422, detail="A rejection reason is required")

    session_factory: sessionmaker[Session] = request.app.state.session_factory
    try:
        with session_factory.begin() as session:
            listing = transition_staff_listing(
                session,
                agency_id=agency_id,
                listing_id=listing_id,
                action=action,
                observation=observation,
                actor_id=staff["id"],
                actor_role=staff["role"],
                now=request.app.state.clock(),
            )
            if listing is None:
                raise HTTPException(status_code=404, detail="Listing not found")
            return _authoring_response(listing)
    except InvalidListingTransitionError:
        raise HTTPException(
            status_code=409, detail="Listing cannot be changed from its current state"
        ) from None


@router.post(
    "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/submit",
    response_model=ListingAuthoringResponse,
)
def submit_agency_listing(
    agency_id: str,
    listing_id: str,
    request: Request,
    body: ListingTransitionRequest | None = None,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingAuthoringResponse:
    return _apply_listing_transition(
        agency_id=agency_id, listing_id=listing_id, action="submit",
        request=request, staff=staff, body=body,
    )


@router.post(
    "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/approve",
    response_model=ListingAuthoringResponse,
)
def approve_agency_listing(
    agency_id: str,
    listing_id: str,
    request: Request,
    body: ListingTransitionRequest | None = None,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingAuthoringResponse:
    return _apply_listing_transition(
        agency_id=agency_id, listing_id=listing_id, action="approve",
        request=request, staff=staff, body=body, admin_only=True,
    )


@router.post(
    "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/reject",
    response_model=ListingAuthoringResponse,
)
def reject_agency_listing(
    agency_id: str,
    listing_id: str,
    request: Request,
    body: ListingTransitionRequest | None = None,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingAuthoringResponse:
    return _apply_listing_transition(
        agency_id=agency_id, listing_id=listing_id, action="reject",
        request=request, staff=staff, body=body, admin_only=True,
    )


@router.post(
    "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/publish",
    response_model=ListingAuthoringResponse,
)
def publish_agency_listing(
    agency_id: str,
    listing_id: str,
    request: Request,
    body: ListingTransitionRequest | None = None,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingAuthoringResponse:
    return _apply_listing_transition(
        agency_id=agency_id, listing_id=listing_id, action="publish",
        request=request, staff=staff, body=body, admin_only=True,
    )


@router.post(
    "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/unpublish",
    response_model=ListingAuthoringResponse,
)
def unpublish_agency_listing(
    agency_id: str,
    listing_id: str,
    request: Request,
    body: ListingTransitionRequest | None = None,
    staff: ActiveStaff = Depends(get_active_staff),
) -> ListingAuthoringResponse:
    return _apply_listing_transition(
        agency_id=agency_id, listing_id=listing_id, action="unpublish",
        request=request, staff=staff, body=body, admin_only=True,
    )


@router.get(
    "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/transitions",
    response_model=list[ListingTransitionResponse],
)
def get_agency_listing_transitions(
    agency_id: str,
    listing_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> list[ListingTransitionResponse]:
    _require_listing_editor(staff, agency_id)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        listing = get_staff_listing(session, agency_id=agency_id, listing_id=listing_id)
        if listing is None:
            raise HTTPException(status_code=404, detail="Listing not found")
        return [
            ListingTransitionResponse.model_validate(row)
            for row in list_listing_transitions(session, listing_id)
        ]


router.include_router(listings_router)
router.include_router(quotes_router)
