import pytest
from test_f04_publications import (
    F04Context,
    _history,
    _payload,
    _seed_listing,
    _staff,
    _url,
    f04_context,  # noqa: F401
)

from app.modules.catalog.models import Listing


def _location_url(agency_id: str, listing_id: str) -> str:
    return _url(agency_id, listing_id) + "/location"


def test_location_patch_reopens_published_listing_and_keeps_other_fields(
    f04_context: F04Context,  # noqa: F811
) -> None:
    context = f04_context
    _seed_listing(context, "published", approval_status="approved", is_published=True)
    _staff(context, role="agent")

    response = context.client.patch(
        _location_url("agency-one", "published"), json={"latitude": -16.5, "longitude": -68.15}
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert (body["latitude"], body["longitude"]) == (-16.5, -68.15)
    assert body["approval_status"] == "draft" and body["is_published"] is False
    assert (body["city"], body["zone"], body["bedrooms"], body["base_price"]) == (
        "Córdoba",
        "Centro",
        2,
        "100000.00",
    )
    assert "published" not in [i["listing_id"] for i in context.client.get("/api/v1/listings").json()["items"]]
    last = _history(context, "published")[-1]
    assert (last.action, last.from_status, last.from_published) == ("edit", "approved", True)
    assert (last.to_status, last.to_published) == ("draft", False)


def test_location_patch_does_not_overwrite_concurrent_field_edits(
    f04_context: F04Context,  # noqa: F811
) -> None:
    context = f04_context
    _seed_listing(context, "l1")
    _staff(context)
    assert context.client.put(_url("agency-one", "l1"), json=_payload(description="fresh")).status_code == 200
    response = context.client.patch(
        _location_url("agency-one", "l1"), json={"latitude": 1.5, "longitude": 2.5}
    )
    assert response.status_code == 200
    assert response.json()["description"] == "fresh"
    assert response.json()["exact_address"] == "Private address"


@pytest.mark.parametrize(
    "body",
    [
        {"latitude": 0},
        {"longitude": 0},
        {},
        {"latitude": None, "longitude": None},
        {"latitude": 91, "longitude": 0},
        {"latitude": 0, "longitude": -181},
        {"latitude": "NaN", "longitude": 0},
        {"latitude": 0, "longitude": 0, "city": "x"},
    ],
)
def test_location_patch_validates_without_mutation(
    f04_context: F04Context,  # noqa: F811
    body: dict[str, object],
) -> None:
    context = f04_context
    _seed_listing(context, "l1", approval_status="approved", is_published=True)
    _staff(context)
    assert context.client.patch(_location_url("agency-one", "l1"), json=body).status_code == 422
    with context.session_factory() as session:
        listing = session.get(Listing, "l1")
        assert listing is not None and listing.is_published and listing.latitude is None
    assert not _history(context, "l1")


def test_location_patch_is_tenant_scoped(f04_context: F04Context) -> None:  # noqa: F811
    context = f04_context
    _seed_listing(context, "other", agency_id="agency-two")
    _seed_listing(context, "mine")
    _staff(context, role="agency_admin", tenant_id="agency-one")
    body = {"latitude": 1, "longitude": 1}

    assert context.client.patch(_location_url("agency-two", "other"), json=body).status_code == 403
    assert context.client.patch(_location_url("agency-one", "other"), json=body).status_code == 404
    assert context.client.patch(_location_url("agency-one", "missing"), json=body).status_code == 404
    with context.session_factory() as session:
        listing = session.get(Listing, "other")
        assert listing is not None and listing.latitude is None
    assert not _history(context, "other")


def test_location_patch_forbids_platform_admin(f04_context: F04Context) -> None:  # noqa: F811
    context = f04_context
    _seed_listing(context, "l1")
    _staff(context, role="platform_admin", tenant_id=None)
    response = context.client.patch(
        _location_url("agency-one", "l1"), json={"latitude": 1, "longitude": 1}
    )
    assert response.status_code == 403
