from __future__ import annotations

import math

import pytest
from sqlalchemy import Table, event

from app.modules.catalog.models import Listing
from test_catalog import CatalogApiContext, _listing_ids, _seed_listing
from test_catalog import catalog_api_context as zone_context  # noqa: F401


@pytest.mark.parametrize(
    "params",
    [
        {"latitude": "0"}, {"longitude": "0"}, {"radius_km": "5"},
        {"latitude": "91", "longitude": "0"},
        {"latitude": "0", "longitude": "181"},
        {"latitude": "nan", "longitude": "0"},
        {"latitude": "0", "longitude": "inf"},
        {"latitude": "0", "longitude": "0", "radius_km": "0.99"},
        {"latitude": "0", "longitude": "0", "radius_km": "50.01"},
        {"latitude": "0", "longitude": "0", "radius_km": "nan"},
        {"latitude": "-91", "longitude": "0"},
        {"latitude": "0", "longitude": "-181"},
        {"latitude": "0", "longitude": "0", "radius_km": "inf"},
    ],
)
def test_invalid_geographic_parameters(zone_context: CatalogApiContext, params: dict[str, str]) -> None:  # noqa: F811
    response = zone_context.client.get("/api/v1/listings", params=params)
    assert response.status_code == 422


def test_radius_order_filters_and_pagination(zone_context: CatalogApiContext) -> None:  # noqa: F811
    ctx = zone_context
    for listing_id, latitude in [("near", 0.001), ("middle", 0.02), ("far", 0.1), ("none", None), ("excluded", 0.0)]:
        _seed_listing(ctx, listing_id=listing_id, city="Other" if listing_id == "excluded" else "Test")
        if latitude is not None:
            with ctx.session_factory.begin() as session:
                listing = session.get(Listing, listing_id)
                assert listing is not None
                listing.latitude = latitude
                listing.longitude = 0
    general = ctx.client.get("/api/v1/listings")
    assert set(_listing_ids(general)) == {"near", "middle", "far", "none", "excluded"}
    params = {"latitude": 0, "longitude": 0, "city": "Test", "limit": 1}
    first = ctx.client.get("/api/v1/listings", params=params)
    assert first.status_code == 200
    assert _listing_ids(first) == ["near"]
    second = ctx.client.get("/api/v1/listings", params={**params, "cursor": first.json()["next_cursor"]})
    assert _listing_ids(second) == ["middle"]
    assert second.json()["next_cursor"] is None
    assert _listing_ids(ctx.client.get("/api/v1/listings", params={**params, "radius_km": 1})) == ["near"]
    assert _listing_ids(ctx.client.get("/api/v1/listings", params={**params, "radius_km": 50, "limit": 10})) == ["near", "middle", "far"]


@pytest.mark.parametrize("radius", [1, 50])
def test_boundary_ties_and_bounded_query(zone_context: CatalogApiContext, radius: int) -> None:  # noqa: F811
    ctx = zone_context
    for listing_id, longitude in [("a", 0.0), ("b", 0.0), ("edge", math.degrees(radius / 6371)), ("outside", math.degrees((radius + 0.0001) / 6371))]:
        _seed_listing(ctx, listing_id=listing_id)
        with ctx.session_factory.begin() as session:
            listing = session.get(Listing, listing_id)
            assert listing is not None
            listing.latitude = 0
            listing.longitude = longitude
    statements: list[str] = []
    query_parameters: list[tuple] = []
    engine = ctx.session_factory.kw["bind"]

    def capture(conn, cursor, statement, parameters, context, executemany):  # type: ignore[no-untyped-def]
        if "FROM listing " in statement or "FROM listing\n" in statement:
            statements.append(statement)
            query_parameters.append(parameters)

    event.listen(engine, "before_cursor_execute", capture)
    try:
        params = {"latitude": 0, "longitude": 0, "radius_km": radius, "limit": 1}
        invalid = ctx.client.get("/api/v1/listings", params={**params, "cursor": "invalid"})
        assert invalid.status_code == 400
        assert not statements
        first = ctx.client.get("/api/v1/listings", params=params)
        second = ctx.client.get("/api/v1/listings", params={**params, "cursor": first.json()["next_cursor"]})
        third = ctx.client.get("/api/v1/listings", params={**params, "cursor": second.json()["next_cursor"]})
        assert _listing_ids(first) == ["b"]
        assert _listing_ids(second) == ["a"]
        assert _listing_ids(third) == ["edge"]
        assert third.json()["next_cursor"] is None
        assert len(statements) == 3
        assert all("LIMIT" in statement.upper() and "ORDER BY" in statement.upper() for statement in statements)
        assert all("sin(" in statement.lower() and "where" in statement.lower() for statement in statements)
        assert all("listing.latitude >=" in statement and "listing.latitude <=" in statement for statement in statements)
        assert all("listing.longitude >=" in statement and "listing.longitude <=" in statement for statement in statements)
        assert isinstance(Listing.__table__, Table)
        assert {"ix_listing_latitude", "ix_listing_longitude"} <= {index.name for index in Listing.__table__.indexes}
        assert all(parameters[-2:] == (2, 0) for parameters in query_parameters)
        assert "listing.created_at <" in statements[1]
    finally:
        event.remove(engine, "before_cursor_execute", capture)


@pytest.mark.parametrize(
    "center,point",
    [
        ((0, 179.999), (0, -179.999)),
        ((0, -179.999), (0, 179.999)),
        ((89.999, 0), (89.999, 180)),
        ((-89.999, 0), (-89.999, -180)),
        ((0, 180), (0, -180)),
    ],
)
def test_geographic_wrap_and_poles(zone_context: CatalogApiContext, center: tuple[float, float], point: tuple[float, float]) -> None:  # noqa: F811
    _seed_listing(zone_context, listing_id="near")
    with zone_context.session_factory.begin() as session:
        listing = session.get(Listing, "near")
        assert listing is not None
        listing.latitude, listing.longitude = point
    response = zone_context.client.get(
        "/api/v1/listings", params={"latitude": center[0], "longitude": center[1], "radius_km": 1}
    )
    assert response.status_code == 200
    assert _listing_ids(response) == ["near"]


@pytest.mark.parametrize("latitude,longitude", [(90, 180), (-90, -180)])
def test_coordinate_extremes_are_valid(zone_context: CatalogApiContext, latitude: int, longitude: int) -> None:  # noqa: F811
    response = zone_context.client.get(
        "/api/v1/listings", params={"latitude": latitude, "longitude": longitude, "radius_km": 1}
    )
    assert response.status_code == 200
    assert _listing_ids(response) == []


def _place(ctx: CatalogApiContext, listing_id: str, latitude: float, **seed: object) -> None:
    _seed_listing(ctx, listing_id=listing_id, **seed)  # type: ignore[arg-type]
    with ctx.session_factory.begin() as session:
        listing = session.get(Listing, listing_id)
        assert listing is not None
        listing.latitude, listing.longitude = latitude, 0


def test_default_radius_is_five_km(zone_context: CatalogApiContext) -> None:  # noqa: F811
    _place(zone_context, "inside", math.degrees(4 / 6371))
    _place(zone_context, "outside", math.degrees(6 / 6371))
    response = zone_context.client.get("/api/v1/listings", params={"latitude": 0, "longitude": 0})
    assert response.status_code == 200
    assert _listing_ids(response) == ["inside"]


def test_unpublished_and_unapproved_are_excluded(zone_context: CatalogApiContext) -> None:  # noqa: F811
    _place(zone_context, "visible", 0.001)
    _place(zone_context, "hidden", 0.001, is_published=False)
    _place(zone_context, "pending", 0.001, approval_status="pending")
    response = zone_context.client.get("/api/v1/listings", params={"latitude": 0, "longitude": 0})
    assert _listing_ids(response) == ["visible"]


def test_cursor_mode_mismatch_is_rejected(zone_context: CatalogApiContext) -> None:  # noqa: F811
    _place(zone_context, "one", 0.001)
    _place(zone_context, "two", 0.002)
    geographic = zone_context.client.get(
        "/api/v1/listings", params={"latitude": 0, "longitude": 0, "limit": 1}
    ).json()["next_cursor"]
    plain = zone_context.client.get("/api/v1/listings", params={"limit": 1}).json()["next_cursor"]
    assert geographic and plain
    without_center = zone_context.client.get("/api/v1/listings", params={"cursor": geographic})
    with_center = zone_context.client.get(
        "/api/v1/listings", params={"latitude": 0, "longitude": 0, "cursor": plain}
    )
    assert without_center.status_code == 400
    assert with_center.status_code == 400
