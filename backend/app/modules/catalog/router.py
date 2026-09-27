"""Public catalog read endpoints and quote creation."""

from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Path, Query, Request
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from app.modules.catalog.errors import (
    InvalidQuoteExtrasError,
    QuoteApiError,
    QuoteNotFoundError,
    QuoteOfferVersionMismatchError,
    UnsupportedRateLimitDialectError,
)
from app.modules.catalog.models import Listing, QuoteSnapshot
from app.modules.catalog.schemas import (
    CatalogExtraItem,
    CatalogListingDetail,
    CatalogListingItem,
    CatalogListingPage,
    CatalogMoney,
    QuoteCreateRequest,
    QuoteErrorResponse,
    QuoteLine,
    QuoteSnapshotResponse,
)
from app.modules.catalog.service import (
    InvalidCursorError,
    consume_quote_rate_limit,
    create_quote_snapshot,
    encode_cursor,
    get_public_listing,
    list_listing_extras,
    normalize_geo_key,
    search_public_listings,
)


router = APIRouter()
listings_router = APIRouter(prefix="/api/v1/listings", tags=["catalog"])
quotes_router = APIRouter(prefix="/api/v1/quotes", tags=["quotes"])
_MONEY_QUANTUM = Decimal("0.01")


def _money(amount: Decimal) -> CatalogMoney:
    exact_amount = amount.quantize(_MONEY_QUANTUM, rounding=ROUND_HALF_UP)
    return CatalogMoney(amount=format(exact_amount, ".2f"), currency="COP")


def _listing_item(listing: Listing) -> CatalogListingItem:
    return CatalogListingItem(
        listing_id=listing.id,
        offer_version=listing.offer_version,
        operation=listing.operation,
        base_price=_money(listing.base_price),
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
    operation: Annotated[Literal["sale", "rent"] | None, Query()] = None,
    min_base_price: Annotated[
        Decimal | None,
        Query(ge=Decimal("0"), max_digits=18, decimal_places=2),
    ] = None,
    max_base_price: Annotated[
        Decimal | None,
        Query(ge=Decimal("0"), max_digits=18, decimal_places=2),
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
                    price=_money(extra.price),
                )
                for extra in extras
            ],
        )


def _quote_response(quote: QuoteSnapshot) -> QuoteSnapshotResponse:
    return QuoteSnapshotResponse(
        quote_id=quote.id,
        listing_id=quote.listing_id,
        offer_version=quote.offer_version,
        operation=quote.operation,
        lines=[QuoteLine.model_validate(line) for line in quote.lines],
        one_time_total=_money(quote.one_time_total),
        monthly_total=_money(quote.monthly_total),
        created_at=quote.created_at,
        expires_at=quote.expires_at,
    )


@quotes_router.post(
    "",
    status_code=201,
    response_model=QuoteSnapshotResponse,
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
        503: {"model": QuoteErrorResponse, "description": "Quote service unavailable"},
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
    except SQLAlchemyError:
        raise QuoteApiError(
            503,
            "quote_service_unavailable",
            "The quote service is temporarily unavailable.",
        ) from None


router.include_router(listings_router)
router.include_router(quotes_router)
