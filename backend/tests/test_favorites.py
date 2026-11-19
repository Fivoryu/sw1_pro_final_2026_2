"""Customer favorites and saved searches (F14.3)."""

from __future__ import annotations

from sqlalchemy import select

from app.modules.catalog.models import Listing
from app.modules.favorites.models import CustomerSavedSearch
from app.modules.favorites import router as favorites_module
from chat_support import AgencyApiContext, register_customer, seed_listing

LISTING = "listing-chat"
FAVORITES = "/api/v1/customer/favorites"
SEARCHES = "/api/v1/customer/saved-searches"
FILTERS = {
    "city": "Santa Cruz",
    "operation": "sale",
    "min_base_price": "50000",
    "max_base_price": "150000.5",
    "min_rooms": 2,
}


# ------------------------------------------------------------------ favorites


def test_a_customer_adds_lists_and_removes_a_favorite(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    seed_listing(context)
    _, headers = register_customer(context)

    assert context.client.get(FAVORITES, headers=headers).json() == {"items": []}
    added = context.client.put(f"{FAVORITES}/{LISTING}", headers=headers)
    listed = context.client.get(FAVORITES, headers=headers).json()["items"]

    assert added.status_code == 204
    assert len(listed) == 1
    assert listed[0]["listing_id"] == LISTING
    assert listed[0]["available"] is True
    assert listed[0]["listing"]["city"] == "Santa Cruz"
    assert listed[0]["listing"]["base_price"] == {"amount": "100000.00", "currency": "BOB"}

    removed = context.client.delete(f"{FAVORITES}/{LISTING}", headers=headers)
    assert removed.status_code == 204
    assert context.client.get(FAVORITES, headers=headers).json() == {"items": []}


def test_adding_and_removing_a_favorite_twice_is_idempotent(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    seed_listing(context)
    _, headers = register_customer(context)

    assert context.client.put(f"{FAVORITES}/{LISTING}", headers=headers).status_code == 204
    assert context.client.put(f"{FAVORITES}/{LISTING}", headers=headers).status_code == 204
    assert len(context.client.get(FAVORITES, headers=headers).json()["items"]) == 1

    assert context.client.delete(f"{FAVORITES}/{LISTING}", headers=headers).status_code == 204
    assert context.client.delete(f"{FAVORITES}/{LISTING}", headers=headers).status_code == 204


def test_only_public_listings_can_be_added(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    seed_listing(context, "draft-listing", approval_status="draft", is_published=False)
    _, headers = register_customer(context)

    assert context.client.put(f"{FAVORITES}/draft-listing", headers=headers).status_code == 404
    assert context.client.put(f"{FAVORITES}/missing", headers=headers).status_code == 404


def test_an_unpublished_favorite_stays_without_revealing_the_listing(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    seed_listing(context)
    _, headers = register_customer(context)
    context.client.put(f"{FAVORITES}/{LISTING}", headers=headers)

    with context.session_factory.begin() as session:
        listing = session.get(Listing, LISTING)
        assert listing is not None
        listing.is_published = False

    items = context.client.get(FAVORITES, headers=headers).json()["items"]
    assert items == [
        {
            "listing_id": LISTING,
            "favorited_at": items[0]["favorited_at"],
            "available": False,
            "listing": None,
        }
    ]


def test_a_customer_never_sees_or_removes_another_customers_favorites(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    seed_listing(context)
    _, first = register_customer(context, "first@example.test")
    _, second = register_customer(context, "second@example.test")
    context.client.put(f"{FAVORITES}/{LISTING}", headers=first)

    assert context.client.get(FAVORITES, headers=second).json() == {"items": []}
    context.client.delete(f"{FAVORITES}/{LISTING}", headers=second)
    assert len(context.client.get(FAVORITES, headers=first).json()["items"]) == 1


def test_the_favorite_limit_is_enforced(
    agency_api_context: AgencyApiContext, monkeypatch
) -> None:
    context = agency_api_context
    seed_listing(context, "listing-1")
    seed_listing(context, "listing-2")
    _, headers = register_customer(context)
    monkeypatch.setattr(favorites_module, "MAX_FAVORITES", 1)

    assert context.client.put(f"{FAVORITES}/listing-1", headers=headers).status_code == 204
    refused = context.client.put(f"{FAVORITES}/listing-2", headers=headers)
    again = context.client.put(f"{FAVORITES}/listing-1", headers=headers)

    assert refused.status_code == 409
    assert refused.json()["detail"] == "favorite_limit"
    assert again.status_code == 204


def test_favorites_and_saved_searches_require_a_customer_session(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    seed_listing(context)

    assert context.client.get(FAVORITES).status_code == 401
    assert context.client.put(f"{FAVORITES}/{LISTING}").status_code == 401
    assert context.client.get(SEARCHES).status_code == 401
    assert context.client.post(SEARCHES, json={"name": "x", "filters": {}}).status_code == 401


def test_the_public_catalog_is_unchanged_for_customers_with_favorites(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    seed_listing(context)
    _, headers = register_customer(context)
    before = context.client.get("/api/v1/listings").json()

    context.client.put(f"{FAVORITES}/{LISTING}", headers=headers)
    context.client.post(SEARCHES, json={"name": "Casas", "filters": FILTERS}, headers=headers)

    assert context.client.get("/api/v1/listings").json() == before
    assert context.client.get("/api/v1/listings", headers=headers).json() == before


# ------------------------------------------------------------------ saved searches


def test_a_customer_saves_lists_and_deletes_a_search(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, headers = register_customer(context)

    created = context.client.post(
        SEARCHES, json={"name": "  Casas en Santa Cruz  ", "filters": FILTERS}, headers=headers
    )
    assert created.status_code == 201
    body = created.json()
    assert body["name"] == "Casas en Santa Cruz"
    assert body["filters"] == {
        "city": "Santa Cruz",
        "zone": None,
        "operation": "sale",
        "min_base_price": "50000",
        "max_base_price": "150000.5",
        "min_rooms": 2,
        "min_bathrooms": None,
    }

    listed = context.client.get(SEARCHES, headers=headers).json()["items"]
    assert [item["id"] for item in listed] == [body["id"]]
    assert listed[0]["filters"] == body["filters"]

    deleted = context.client.delete(f"{SEARCHES}/{body['id']}", headers=headers)
    assert deleted.status_code == 204
    assert context.client.get(SEARCHES, headers=headers).json() == {"items": []}
    assert context.client.delete(f"{SEARCHES}/{body['id']}", headers=headers).status_code == 404


def test_a_saved_search_name_is_unique_per_customer(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, first = register_customer(context, "first@example.test")
    _, second = register_customer(context, "second@example.test")

    assert context.client.post(SEARCHES, json={"name": "Casas", "filters": {}}, headers=first).status_code == 201
    taken = context.client.post(SEARCHES, json={"name": "casas", "filters": {}}, headers=first)
    other = context.client.post(SEARCHES, json={"name": "Casas", "filters": {}}, headers=second)

    assert taken.status_code == 409
    assert taken.json()["detail"] == "saved_search_name_taken"
    assert other.status_code == 201


def test_a_customer_never_sees_or_deletes_another_customers_searches(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, first = register_customer(context, "first@example.test")
    _, second = register_customer(context, "second@example.test")
    search_id = context.client.post(
        SEARCHES, json={"name": "Casas", "filters": FILTERS}, headers=first
    ).json()["id"]

    assert context.client.get(SEARCHES, headers=second).json() == {"items": []}
    assert context.client.delete(f"{SEARCHES}/{search_id}", headers=second).status_code == 404
    assert len(context.client.get(SEARCHES, headers=first).json()["items"]) == 1


def test_the_saved_search_limit_is_enforced(
    agency_api_context: AgencyApiContext, monkeypatch
) -> None:
    context = agency_api_context
    _, headers = register_customer(context)
    monkeypatch.setattr(favorites_module, "MAX_SAVED_SEARCHES", 1)

    assert context.client.post(SEARCHES, json={"name": "A", "filters": {}}, headers=headers).status_code == 201
    refused = context.client.post(SEARCHES, json={"name": "B", "filters": {}}, headers=headers)

    assert refused.status_code == 409
    assert refused.json()["detail"] == "saved_search_limit"


def test_invalid_saved_search_filters_are_rejected(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, headers = register_customer(context)
    invalid = [
        {"name": "", "filters": {}},
        {"name": "x" * 81, "filters": {}},
        {"name": "A", "filters": {"city": "   "}},
        {"name": "A", "filters": {"min_base_price": "10", "max_base_price": "5"}},
        {"name": "A", "filters": {"operation": "lease"}},
        {"name": "A", "filters": {"min_rooms": -1}},
        {"name": "A", "filters": {"unknown": 1}},
    ]

    for body in invalid:
        response = context.client.post(SEARCHES, json=body, headers=headers)
        assert response.status_code == 422, body

    assert context.client.get(SEARCHES, headers=headers).json() == {"items": []}


def test_a_saved_search_never_stores_the_customer_location(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, headers = register_customer(context)

    for point in (
        {"latitude": -17.78, "longitude": -63.18},
        {"latitude": -17.78, "longitude": -63.18, "radius_km": 5},
        {"radius_km": 5},
    ):
        response = context.client.post(
            SEARCHES, json={"name": "Cerca", "filters": point}, headers=headers
        )
        assert response.status_code == 422, point

    with context.session_factory() as session:
        assert session.scalars(select(CustomerSavedSearch)).all() == []
