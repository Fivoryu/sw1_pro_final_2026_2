"""Customer favorites and saved searches (F14.3).

Everything here is scoped to the customer of the session: a customer never
reads, adds or deletes another customer's favorites or searches, and the
public catalog behaves the same for customers who never use them.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.core.errors import ERROR_RESPONSES
from app.modules.catalog.models import Listing
from app.modules.catalog.router import _listing_item, _public_photos
from app.modules.customer_identity.session import ActiveCustomer, get_active_customer
from app.modules.favorites.models import CustomerFavorite, CustomerSavedSearch
from app.modules.favorites.schemas import (
    FavoriteItem,
    FavoriteList,
    SavedSearchCreate,
    SavedSearchFilters,
    SavedSearchList,
    SavedSearchView,
)

MAX_FAVORITES = 100
MAX_SAVED_SEARCHES = 20

favorites_router = APIRouter(
    prefix="/api/v1/customer/favorites", tags=["customer-favorites"], responses=ERROR_RESPONSES
)
saved_searches_router = APIRouter(
    prefix="/api/v1/customer/saved-searches",
    tags=["customer-saved-searches"],
    responses=ERROR_RESPONSES,
)

_Customer = Annotated[ActiveCustomer, Depends(get_active_customer)]


def _factory(request: Request) -> sessionmaker[Session]:
    factory: sessionmaker[Session] = request.app.state.session_factory
    return factory


def _now(request: Request) -> datetime:
    now: datetime = request.app.state.clock()
    return now


def _is_public(listing: Listing | None) -> bool:
    return listing is not None and listing.approval_status == "approved" and listing.is_published


# --------------------------------------------------------------------------- favorites


@favorites_router.get("", response_model=FavoriteList)
def list_favorites(request: Request, customer: _Customer) -> FavoriteList:
    with _factory(request)() as session:
        favorites = session.scalars(
            select(CustomerFavorite)
            .where(CustomerFavorite.customer_id == customer["id"])
            .order_by(CustomerFavorite.created_at.desc(), CustomerFavorite.id)
        ).all()
        items: list[FavoriteItem] = []
        for favorite in favorites:
            listing = session.get(Listing, favorite.listing_id)
            if listing is not None and _is_public(listing):
                photos = _public_photos(request, session, listing.id)
                summary = _listing_item(listing, photos[0].url if photos else None)
                items.append(
                    FavoriteItem(
                        listing_id=favorite.listing_id,
                        favorited_at=favorite.created_at,
                        available=True,
                        listing=summary,
                    )
                )
            else:
                # An unpublished listing keeps the favorite but reveals nothing about it.
                items.append(
                    FavoriteItem(
                        listing_id=favorite.listing_id,
                        favorited_at=favorite.created_at,
                        available=False,
                        listing=None,
                    )
                )
        return FavoriteList(items=items)


@favorites_router.put("/{listing_id}", status_code=204)
def add_favorite(listing_id: str, request: Request, customer: _Customer) -> Response:
    with _factory(request).begin() as session:
        if not _is_public(session.get(Listing, listing_id)):
            raise HTTPException(status_code=404, detail="Not found")
        existing = session.scalar(
            select(CustomerFavorite.id).where(
                CustomerFavorite.customer_id == customer["id"],
                CustomerFavorite.listing_id == listing_id,
            )
        )
        if existing is not None:
            return Response(status_code=204)
        count = session.scalar(
            select(func.count())
            .select_from(CustomerFavorite)
            .where(CustomerFavorite.customer_id == customer["id"])
        )
        if (count or 0) >= MAX_FAVORITES:
            raise HTTPException(status_code=409, detail="favorite_limit")
        try:
            with session.begin_nested():
                session.add(
                    CustomerFavorite(
                        customer_id=customer["id"], listing_id=listing_id, created_at=_now(request)
                    )
                )
        except IntegrityError:
            pass  # A concurrent request already added it: the result is the same.
    return Response(status_code=204)


@favorites_router.delete("/{listing_id}", status_code=204)
def remove_favorite(listing_id: str, request: Request, customer: _Customer) -> Response:
    with _factory(request).begin() as session:
        favorite = session.scalar(
            select(CustomerFavorite).where(
                CustomerFavorite.customer_id == customer["id"],
                CustomerFavorite.listing_id == listing_id,
            )
        )
        if favorite is not None:
            session.delete(favorite)
    return Response(status_code=204)


# --------------------------------------------------------------------------- saved searches


def _search_view(search: CustomerSavedSearch) -> SavedSearchView:
    return SavedSearchView(
        id=search.id,
        name=search.name,
        filters=SavedSearchFilters.model_validate(search.filters),
        created_at=search.created_at,
    )


@saved_searches_router.get("", response_model=SavedSearchList)
def list_saved_searches(request: Request, customer: _Customer) -> SavedSearchList:
    with _factory(request)() as session:
        searches = session.scalars(
            select(CustomerSavedSearch)
            .where(CustomerSavedSearch.customer_id == customer["id"])
            .order_by(CustomerSavedSearch.created_at.desc(), CustomerSavedSearch.id)
        ).all()
        return SavedSearchList(items=[_search_view(search) for search in searches])


@saved_searches_router.post("", response_model=SavedSearchView, status_code=201)
def create_saved_search(
    body: SavedSearchCreate, request: Request, customer: _Customer
) -> SavedSearchView:
    with _factory(request).begin() as session:
        names = session.scalars(
            select(CustomerSavedSearch.name).where(
                CustomerSavedSearch.customer_id == customer["id"]
            )
        ).all()
        if body.name.casefold() in {name.casefold() for name in names}:
            raise HTTPException(status_code=409, detail="saved_search_name_taken")
        if len(names) >= MAX_SAVED_SEARCHES:
            raise HTTPException(status_code=409, detail="saved_search_limit")
        search = CustomerSavedSearch(
            customer_id=customer["id"],
            name=body.name,
            filters=body.filters.model_dump(mode="json", exclude_none=True),
            created_at=_now(request),
        )
        try:
            with session.begin_nested():
                session.add(search)
        except IntegrityError:
            raise HTTPException(status_code=409, detail="saved_search_name_taken") from None
        return _search_view(search)


@saved_searches_router.delete("/{search_id}", status_code=204)
def delete_saved_search(search_id: str, request: Request, customer: _Customer) -> Response:
    with _factory(request).begin() as session:
        search = session.get(CustomerSavedSearch, search_id)
        # Another customer's search answers like a missing one.
        if search is None or search.customer_id != customer["id"]:
            raise HTTPException(status_code=404, detail="Not found")
        session.delete(search)
    return Response(status_code=204)
