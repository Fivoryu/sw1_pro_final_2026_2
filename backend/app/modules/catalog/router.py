"""Public, read-only catalog endpoints."""

from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Path, Query, Request
from sqlalchemy.orm import Session, sessionmaker

from app.modules.catalog.models import Listing
from app.modules.catalog.schemas import (
    CatalogExtraItem,
    CatalogListingDetail,
    CatalogListingItem,
    CatalogListingPage,
    CatalogMoney,
)
from app.modules.catalog.service import (
    InvalidCursorError,
    encode_cursor,
    get_public_listing,
    list_listing_extras,
    normalize_geo_key,
    search_public_listings,
)


router = APIRouter(prefix="/api/v1/listings", tags=["catalog"])
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


@router.get(
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


@router.get(
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
