from __future__ import annotations

import base64
import importlib.util
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.core.security import create_access_token
from app.db.base import Base
from app.main import create_app
from app.modules.catalog.errors import QuoteOfferVersionMismatchError
from app.modules.catalog.models import Listing, ListingPhoto
from app.modules.catalog.service import validate_quote_for_use
from app.modules.identity.models import Agency, StaffAccount, StaffSession
from app.modules.identity.session import get_active_staff


@dataclass
class F04Context:
    client: TestClient
    app: FastAPI
    session_factory: sessionmaker[Session]


@pytest.fixture

def f04_context() -> Iterator[F04Context]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    Base.metadata.create_all(engine)
    migration_path = (
        Path(__file__).resolve().parents[1]
        / "alembic"
        / "versions"
        / "0007_catalog_offers.py"
    )
    spec = importlib.util.spec_from_file_location("f04_catalog_offers", migration_path)
    assert spec is not None and spec.loader is not None
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    from alembic.migration import MigrationContext
    from alembic.operations import Operations

    currency_migration_path = (
        Path(__file__).resolve().parents[1]
        / "alembic"
        / "versions"
        / "0013_listing_currency.py"
    )
    currency_spec = importlib.util.spec_from_file_location(
        "f04_listing_currency", currency_migration_path
    )
    assert currency_spec is not None and currency_spec.loader is not None
    currency_migration = importlib.util.module_from_spec(currency_spec)
    currency_spec.loader.exec_module(currency_migration)
    extra_details_path = (
        Path(__file__).resolve().parents[1]
        / "alembic"
        / "versions"
        / "0016_listing_extra_details.py"
    )
    extra_details_spec = importlib.util.spec_from_file_location(
        "f04_listing_extra_details", extra_details_path
    )
    assert extra_details_spec is not None and extra_details_spec.loader is not None
    extra_details_migration = importlib.util.module_from_spec(extra_details_spec)
    extra_details_spec.loader.exec_module(extra_details_migration)
    with engine.begin() as connection:
        with Operations.context(MigrationContext.configure(connection)):
            migration._install_sqlite_offer_version_triggers()
            currency_migration._install_listing_currency_triggers()
            extra_details_migration._drop_sqlite_extra_triggers()
            extra_details_migration._install_sqlite_extra_triggers(quantity_aware=True)
            currency_migration._install_snapshot_immutability()
    app = create_app(
        settings=Settings(
            database_url="sqlite+pysqlite:///:memory:",
            jwt_secret="f04-test-secret-that-is-at-least-thirty-two-bytes",
            totp_encryption_key=base64.urlsafe_b64encode(b"0" * 32).decode(),
            web_origin="http://localhost",
        ),
        session_factory=factory,
    )
    with TestClient(app) as client:
        yield F04Context(client, app, factory)
    engine.dispose()


def _staff(
    context: F04Context,
    *,
    role: str = "agency_admin",
    tenant_id: str | None = "agency-one",
    actor_id: str = "f04-actor",
) -> None:
    if tenant_id is not None:
        with context.session_factory.begin() as session:
            if session.get(Agency, tenant_id) is None:
                session.add(Agency(id=tenant_id))
    context.app.dependency_overrides[get_active_staff] = lambda: {
        "id": actor_id,
        "email": f"{actor_id}@example.test",
        "role": role,
        "tenant_id": tenant_id,
    }


def _payload(**changes: Any) -> dict[str, Any]:
    result: dict[str, Any] = {
        "operation": "sale",
        "base_price": "125000.00",
        "city": "  Medellín ",
        "zone": " El Poblado ",
        "bedrooms": 3,
        "bathrooms": 2,
        "description": "A bright apartment",
        "exact_address": "Private address",
    }
    result.update(changes)
    return result


def _url(agency_id: str, listing_id: str) -> str:
    return f"/api/v1/staff/agencies/{agency_id}/listings/{listing_id}"


def _collection_url(agency_id: str) -> str:
    return f"/api/v1/staff/agencies/{agency_id}/listings"


def _seed_listing(
    context: F04Context,
    listing_id: str,
    *,
    agency_id: str = "agency-one",
    approval_status: str = "draft",
    is_published: bool = False,
    base_price: str = "100000.00",
    created_at: datetime | None = None,
    currency: str = "BOB",
) -> None:
    with context.session_factory.begin() as session:
        if session.get(Agency, agency_id) is None:
            session.add(Agency(id=agency_id))
            session.flush()
        listing = Listing(
            id=listing_id,
            agency_id=agency_id,
            approval_status=approval_status,
            is_published=is_published,
            operation="sale",
            base_price=Decimal(base_price),
            offer_version=1,
            city="Córdoba",
            zone="Centro",
            bedrooms=2,
            bathrooms=1,
        )
        if created_at is not None:
            listing.created_at = created_at
        listing.currency = currency
        session.add(listing)


def _seed_confirmed_photo(context: F04Context, listing_id: str, agency_id: str = "agency-one") -> None:
    """Submitting for review requires a confirmed photo (F04.2)."""
    now = datetime(2026, 10, 4, 12, 0, tzinfo=timezone.utc)
    with context.session_factory.begin() as session:
        session.add(
            ListingPhoto(
                agency_id=agency_id,
                listing_id=listing_id,
                object_key=f"agencies/{agency_id}/listings/{listing_id}/photos/seeded",
                status="confirmed",
                content_type="image/jpeg",
                size_bytes=10,
                created_at=now,
                expires_at=now + timedelta(minutes=15),
                confirmed_at=now,
            )
        )


def _create_quote(context: F04Context, listing_id: str) -> str:
    response = context.client.post(
        "/api/v1/quotes",
        json={"listing_id": listing_id, "offer_version": 1, "selected_extra_ids": []},
    )
    assert response.status_code == 201, response.text
    return response.json()["quote_id"]


def _history(context: F04Context, listing_id: str) -> list[Any]:
    from app.modules.catalog.models import ListingTransition

    with context.session_factory() as session:
        return (
            session.query(ListingTransition)
            .filter(ListingTransition.listing_id == listing_id)
            .order_by(ListingTransition.created_at, ListingTransition.id)
            .all()
        )


def test_create_listing_starts_as_normalized_unpublished_draft(f04_context: F04Context) -> None:
    context = f04_context
    _staff(context, actor_id="creator")
    response = context.client.post(_collection_url("agency-one"), json=_payload())

    assert response.status_code == 201, response.text
    listing_id = response.json()["listing_id"]
    assert response.json()["approval_status"] == "draft"
    assert response.json()["is_published"] is False
    assert response.json()["offer_version"] == 1
    with context.session_factory() as session:
        listing = session.get(Listing, listing_id)
        assert listing is not None
        assert listing.city_key == "medellín" and listing.zone_key == "el poblado"
        assert listing.deposit_amount is None
    assert [(row.action, row.from_status, row.to_status) for row in _history(context, listing_id)] == [
        ("create", None, "draft")
    ]


def test_invalid_listing_payloads_create_nothing(f04_context: F04Context) -> None:
    context = f04_context
    _staff(context)
    missing = _payload()
    missing.pop("bedrooms")
    cases = [missing, _payload(unknown="value"), _payload(base_price="0"), _payload(operation="buy")]

    for index, body in enumerate(cases):
        response = context.client.post(_collection_url("agency-one"), json=body)
        assert response.status_code == 422, response.text
    with context.session_factory() as session:
        assert session.query(Listing).count() == 0


def test_client_cannot_supply_authority_or_server_derived_fields(f04_context: F04Context) -> None:
    context = f04_context
    _staff(context)
    response = context.client.post(
        _collection_url("agency-one"),
        json=_payload(
            tenant_id="agency-one",
            actor="forged",
            role="agency_admin",
            status="approved",
            is_published=True,
            offer_version=9,
            created_at="2026-09-30T00:00:00Z",
            city_key="forged",
            zone_key="forged",
            photos=["ignored.jpg"],
        ),
    )

    assert response.status_code == 422
    with context.session_factory() as session:
        assert session.query(Listing).count() == 0


def test_edit_keeps_the_stored_currency_regardless_of_the_payload(
    f04_context: F04Context,
) -> None:
    context = f04_context
    _seed_listing(context, "usd-listing", currency="USD")
    _staff(context, role="agent")

    response = context.client.put(
        _url("agency-one", "usd-listing"),
        json=_payload(currency="BOB"),
    )

    assert response.status_code == 200, response.text
    assert response.json()["currency"] == "USD"


def test_editing_published_listing_reopens_it_and_hides_it_immediately(
    f04_context: F04Context,
) -> None:
    context = f04_context
    _seed_listing(context, "published", approval_status="approved", is_published=True)
    _staff(context, role="agent")

    response = context.client.put(
        _url("agency-one", "published"),
        json=_payload(
            base_price="100000.00",
            city="Córdoba",
            zone="Centro",
            bedrooms=2,
            bathrooms=1,
            description="Updated description",
            exact_address=None,
        ),
    )

    assert response.status_code == 200, response.text
    assert response.json()["approval_status"] == "draft"
    assert response.json()["is_published"] is False
    assert response.json()["offer_version"] == 1
    assert "published" not in [item["listing_id"] for item in context.client.get("/api/v1/listings").json()["items"]]
    assert _history(context, "published")[-1].action == "edit"


def test_price_edit_advances_commercial_version_once(f04_context: F04Context) -> None:
    context = f04_context
    _seed_listing(context, "price-change")
    _staff(context, role="agent")

    response = context.client.put(
        _url("agency-one", "price-change"),
        json=_payload(
            base_price="110000.00",
            city="Córdoba",
            zone="Centro",
            bedrooms=2,
            bathrooms=1,
            description=None,
            exact_address=None,
        ),
    )

    assert response.status_code == 200, response.text
    assert response.json()["offer_version"] == 2


def test_quotes_survive_description_edits_but_price_edits_make_them_stale(
    f04_context: F04Context,
) -> None:
    context = f04_context
    _seed_listing(context, "description-quote", approval_status="approved", is_published=True)
    _seed_listing(context, "price-quote", approval_status="approved", is_published=True)
    description_quote = _create_quote(context, "description-quote")
    price_quote = _create_quote(context, "price-quote")
    _staff(context, role="agent")

    description_edit = context.client.put(
        _url("agency-one", "description-quote"),
        json=_payload(
            base_price="100000.00",
            city="Córdoba",
            zone="Centro",
            bedrooms=2,
            bathrooms=1,
            description="Updated description",
            exact_address=None,
        ),
    )
    price_edit = context.client.put(
        _url("agency-one", "price-quote"),
        json=_payload(
            base_price="110000.00",
            city="Córdoba",
            zone="Centro",
            bedrooms=2,
            bathrooms=1,
            description=None,
            exact_address=None,
        ),
    )

    assert description_edit.status_code == price_edit.status_code == 200
    assert description_edit.json()["offer_version"] == 1
    assert price_edit.json()["offer_version"] == 2
    now = datetime.now(timezone.utc)
    with context.session_factory() as session:
        assert validate_quote_for_use(session, description_quote, now=now).offer_version == 1
        with pytest.raises(QuoteOfferVersionMismatchError):
            validate_quote_for_use(session, price_quote, now=now)


def test_submit_is_draft_only_and_invalid_retry_adds_no_history(f04_context: F04Context) -> None:
    context = f04_context
    _seed_listing(context, "submit-me")
    _seed_confirmed_photo(context, "submit-me")
    _staff(context, role="agent")
    url = _url("agency-one", "submit-me")

    first = context.client.post(url + "/submit")
    second = context.client.post(url + "/submit")

    assert first.status_code == 200 and first.json()["approval_status"] == "pending"
    assert second.status_code == 409
    assert [row.action for row in _history(context, "submit-me")] == ["submit"]


def test_agent_cannot_self_approve_or_run_admin_only_transitions(f04_context: F04Context) -> None:
    context = f04_context
    states = {
        "approve-me": ("pending", False, "approve", None),
        "reject-me": ("pending", False, "reject", {"observation": "Reason"}),
        "publish-me": ("approved", False, "publish", None),
        "unpublish-me": ("approved", True, "unpublish", None),
    }
    for listing_id, (status, published, _action, _body) in states.items():
        _seed_listing(context, listing_id, approval_status=status, is_published=published)
    _staff(context, role="agent")

    for listing_id, (_status, _published, action, body) in states.items():
        response = context.client.post(_url("agency-one", listing_id) + f"/{action}", json=body)
        assert response.status_code == 403, response.text
    with context.session_factory() as session:
        for listing_id, (status, published, _action, _body) in states.items():
            listing = session.get(Listing, listing_id)
            assert listing is not None
            assert (listing.approval_status, listing.is_published) == (status, published)
    assert all(not _history(context, listing_id) for listing_id in states)


def test_admin_approves_then_publishes_listing_to_public_catalog(f04_context: F04Context) -> None:
    context = f04_context
    _seed_listing(context, "publish-me", approval_status="pending")
    _staff(context, actor_id="admin")
    url = _url("agency-one", "publish-me")

    approved = context.client.post(url + "/approve")
    published = context.client.post(url + "/publish")

    assert approved.status_code == published.status_code == 200
    assert approved.json()["approval_status"] == "approved"
    assert published.json()["is_published"] is True
    assert "publish-me" in [item["listing_id"] for item in context.client.get("/api/v1/listings").json()["items"]]


def test_reject_requires_nonblank_reason_and_records_it(f04_context: F04Context) -> None:
    context = f04_context
    _seed_listing(context, "reject-me", approval_status="pending")
    _staff(context)
    url = _url("agency-one", "reject-me") + "/reject"

    for observation in ("", "   "):
        assert context.client.post(url, json={"observation": observation}).status_code == 422
    rejected = context.client.post(url, json={"observation": "  Missing documents  "})

    assert rejected.status_code == 200, rejected.text
    assert rejected.json()["approval_status"] == "rejected"
    assert _history(context, "reject-me")[-1].observation == "Missing documents"


def test_unpublish_removes_listing_from_public_catalog(f04_context: F04Context) -> None:
    context = f04_context
    _seed_listing(context, "withdraw-me", approval_status="approved", is_published=True)
    _staff(context)
    assert "withdraw-me" in [item["listing_id"] for item in context.client.get("/api/v1/listings").json()["items"]]

    response = context.client.post(_url("agency-one", "withdraw-me") + "/unpublish")

    assert response.status_code == 200 and response.json()["is_published"] is False
    assert "withdraw-me" not in [item["listing_id"] for item in context.client.get("/api/v1/listings").json()["items"]]


def test_cross_tenant_listing_access_is_forbidden_without_mutation(f04_context: F04Context) -> None:
    context = f04_context
    _seed_listing(context, "other-listing", agency_id="agency-two")
    _staff(context, role="agency_admin", tenant_id="agency-one")

    response = context.client.put(_url("agency-two", "other-listing"), json=_payload())

    assert response.status_code == 403
    with context.session_factory() as session:
        listing = session.get(Listing, "other-listing")
        assert listing is not None and listing.approval_status == "draft"
    assert not _history(context, "other-listing")


def test_missing_listing_is_404_for_authorized_agency_staff(f04_context: F04Context) -> None:
    context = f04_context
    _staff(context, role="agent")

    edited = context.client.put(_url("agency-one", "missing"), json=_payload())
    history = context.client.get(_url("agency-one", "missing") + "/transitions")

    assert edited.status_code == history.status_code == 404


def test_platform_admin_is_forbidden_from_tenant_listing_routes(f04_context: F04Context) -> None:
    context = f04_context
    _staff(context, role="platform_admin", tenant_id=None)

    response = context.client.post(_collection_url("agency-one"), json=_payload())

    assert response.status_code == 403
    with context.session_factory() as session:
        assert session.get(Listing, "platform-listing") is None


def test_listing_authoring_routes_are_documented_only_under_staff_prefix(
    f04_context: F04Context,
) -> None:
    paths = f04_context.client.get("/openapi.json").json()["paths"]
    expected = {
        "/api/v1/staff/agencies/{agency_id}/listings",
        "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}",
        "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/submit",
        "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/approve",
        "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/reject",
        "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/publish",
        "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/unpublish",
        "/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/transitions",
    }
    assert expected <= paths.keys()
    assert all(path.startswith("/api/v1/staff/") for path in expected)


def test_transition_history_is_staff_only_append_ordered_and_absent_from_catalog(
    f04_context: F04Context,
) -> None:
    context = f04_context
    _staff(context, role="agent", actor_id="history-actor")
    created = context.client.post(_collection_url("agency-one"), json=_payload())
    assert created.status_code == 201, created.text
    url = _url("agency-one", created.json()["listing_id"])
    _seed_confirmed_photo(context, created.json()["listing_id"])
    submitted = context.client.post(url + "/submit")
    history = context.client.get(url + "/transitions")

    assert created.status_code == 201 and submitted.status_code == 200
    assert history.status_code == 200, history.text
    assert [item["action"] for item in history.json()] == ["create", "submit"]
    assert history.json()[0]["from_status"] is None
    assert history.json()[0]["to_status"] == "draft"
    assert history.json()[1]["from_status"] == "draft"
    assert all(item["actor_id"] == "history-actor" for item in history.json())
    public = context.client.get("/api/v1/listings")
    assert "transitions" not in public.text and "history-actor" not in public.text


def _at(day: int) -> datetime:
    return datetime(2026, 9, day, 12, 0, tzinfo=timezone.utc)


def _listed_ids(response: Any) -> list[str]:
    return [item["listing_id"] for item in response.json()["listings"]]


def test_staff_list_returns_only_own_agency_listings_newest_first(
    f04_context: F04Context,
) -> None:
    context = f04_context
    _seed_listing(context, "older-draft", created_at=_at(1))
    _seed_listing(context, "newer-pending", approval_status="pending", created_at=_at(3))
    _seed_listing(
        context, "middle-published", approval_status="approved", is_published=True, created_at=_at(2)
    )
    _seed_listing(context, "foreign", agency_id="agency-two", created_at=_at(4))
    _staff(context)

    response = context.client.get(_collection_url("agency-one"))

    assert response.status_code == 200, response.text
    assert _listed_ids(response) == ["newer-pending", "middle-published", "older-draft"]
    assert response.json()["pagination"] == {"limit": 20, "offset": 0, "total": 3}
    item = response.json()["listings"][0]
    assert item["agency_id"] == "agency-one"
    assert item["approval_status"] == "pending" and item["is_published"] is False


def test_staff_list_filters_by_review_status_and_publication(f04_context: F04Context) -> None:
    context = f04_context
    _seed_listing(context, "draft", created_at=_at(1))
    _seed_listing(context, "pending-a", approval_status="pending", created_at=_at(2))
    _seed_listing(context, "pending-b", approval_status="pending", created_at=_at(3))
    _seed_listing(context, "rejected", approval_status="rejected", created_at=_at(4))
    _seed_listing(context, "approved-hidden", approval_status="approved", created_at=_at(5))
    _seed_listing(
        context, "approved-live", approval_status="approved", is_published=True, created_at=_at(6)
    )
    _staff(context)

    pending = context.client.get(_collection_url("agency-one"), params={"status": "pending"})
    approved_hidden = context.client.get(
        _collection_url("agency-one"), params={"status": "approved", "published": "false"}
    )
    live = context.client.get(_collection_url("agency-one"), params={"published": "true"})

    assert _listed_ids(pending) == ["pending-b", "pending-a"]
    assert pending.json()["pagination"]["total"] == 2
    assert _listed_ids(approved_hidden) == ["approved-hidden"]
    assert _listed_ids(live) == ["approved-live"]


def test_staff_list_paginates_with_limit_offset_and_total(f04_context: F04Context) -> None:
    context = f04_context
    for day in range(1, 6):
        _seed_listing(context, f"listing-{day}", created_at=_at(day))
    _staff(context)

    page = context.client.get(_collection_url("agency-one"), params={"limit": 2, "offset": 1})
    past_end = context.client.get(_collection_url("agency-one"), params={"offset": 10})

    assert _listed_ids(page) == ["listing-4", "listing-3"]
    assert page.json()["pagination"] == {"limit": 2, "offset": 1, "total": 5}
    assert past_end.status_code == 200
    assert _listed_ids(past_end) == []
    assert past_end.json()["pagination"]["total"] == 5


@pytest.mark.parametrize(
    "params",
    [
        {"limit": 0},
        {"limit": 101},
        {"offset": -1},
        {"status": "published"},
        {"published": "maybe"},
    ],
)
def test_staff_list_rejects_out_of_contract_query_parameters(
    f04_context: F04Context, params: dict[str, Any]
) -> None:
    context = f04_context
    _staff(context)

    response = context.client.get(_collection_url("agency-one"), params=params)

    assert response.status_code == 422, response.text


def test_agent_lists_every_listing_of_their_agency(f04_context: F04Context) -> None:
    context = f04_context
    _seed_listing(context, "from-admin", created_at=_at(1))
    _seed_listing(context, "from-other-agent", approval_status="pending", created_at=_at(2))
    _staff(context, role="agent", actor_id="some-agent")

    response = context.client.get(_collection_url("agency-one"))

    assert response.status_code == 200, response.text
    assert _listed_ids(response) == ["from-other-agent", "from-admin"]


@pytest.mark.parametrize(
    ("role", "tenant_id"),
    [("agency_admin", "agency-two"), ("agent", "agency-two"), ("platform_admin", None)],
)
def test_staff_list_and_detail_forbid_other_tenants_and_platform_admin(
    f04_context: F04Context, role: str, tenant_id: str | None
) -> None:
    context = f04_context
    _seed_listing(context, "private-listing")
    _staff(context, role=role, tenant_id=tenant_id)

    listed = context.client.get(_collection_url("agency-one"))
    detail = context.client.get(_url("agency-one", "private-listing"))

    assert listed.status_code == detail.status_code == 403
    assert "private-listing" not in listed.text + detail.text


def test_staff_detail_returns_private_listing_fields(f04_context: F04Context) -> None:
    context = f04_context
    _staff(context, role="agent")
    created = context.client.post(_collection_url("agency-one"), json=_payload())
    assert created.status_code == 201, created.text
    listing_id = created.json()["listing_id"]

    response = context.client.get(_url("agency-one", listing_id))

    assert response.status_code == 200, response.text
    assert response.json() == created.json()
    assert response.json()["exact_address"] == "Private address"
    assert response.json()["description"] == "A bright apartment"


def test_staff_detail_of_foreign_or_missing_listing_is_an_identical_404(
    f04_context: F04Context,
) -> None:
    context = f04_context
    _seed_listing(context, "foreign-listing", agency_id="agency-two")
    _staff(context, tenant_id="agency-one")

    foreign = context.client.get(_url("agency-one", "foreign-listing"))
    missing = context.client.get(_url("agency-one", "missing-listing"))

    assert foreign.status_code == missing.status_code == 404
    assert foreign.json() == missing.json()


def test_staff_read_routes_are_documented_and_public_catalog_still_hides_drafts(
    f04_context: F04Context,
) -> None:
    context = f04_context
    _seed_listing(context, "hidden-draft")
    paths = context.client.get("/openapi.json").json()["paths"]

    assert "get" in paths["/api/v1/staff/agencies/{agency_id}/listings"]
    assert "get" in paths["/api/v1/staff/agencies/{agency_id}/listings/{listing_id}"]
    public = context.client.get("/api/v1/listings")
    assert "hidden-draft" not in public.text


# F03.3 isolation matrix: every staff listing route, one actor at a time. Each row
# names the route, its HTTP method and suffix, a valid body and a seed state in
# which the action would succeed for an authorized actor, so a rejection proves
# the guard and not an incidental state conflict.
_LISTING_ROUTES: list[tuple[str, str, str, dict[str, Any] | None, tuple[str, bool]]] = [
    ("detail", "GET", "", None, ("draft", False)),
    ("edit", "PUT", "", _payload(), ("draft", False)),
    ("submit", "POST", "/submit", None, ("draft", False)),
    ("approve", "POST", "/approve", None, ("pending", False)),
    ("reject", "POST", "/reject", {"observation": "Reason"}, ("pending", False)),
    ("publish", "POST", "/publish", None, ("approved", False)),
    ("unpublish", "POST", "/unpublish", None, ("approved", True)),
    ("transitions", "GET", "/transitions", None, ("draft", False)),
    ("deposit", "PATCH", "/deposit", {"deposit_amount": "100.00"}, ("approved", False))
]
_ROUTE_IDS = [route[0] for route in _LISTING_ROUTES]


def _call(
    context: F04Context, method: str, url: str, body: dict[str, Any] | None
) -> Any:
    return context.client.request(method, url, json=body)


def _listing_state(context: F04Context, listing_id: str) -> tuple[Any, ...]:
    with context.session_factory() as session:
        listing = session.get(Listing, listing_id)
        assert listing is not None
        return (
            listing.approval_status,
            listing.is_published,
            listing.base_price,
            listing.city,
            listing.offer_version,
            listing.deposit_amount,
        )


@pytest.mark.parametrize(
    ("name", "method", "suffix", "body", "state"), _LISTING_ROUTES, ids=_ROUTE_IDS
)
def test_foreign_listing_id_under_own_agency_path_is_indistinguishable_from_missing(
    f04_context: F04Context,
    name: str,
    method: str,
    suffix: str,
    body: dict[str, Any] | None,
    state: tuple[str, bool],
) -> None:
    context = f04_context
    status, published = state
    _seed_listing(
        context,
        "foreign-listing",
        agency_id="agency-two",
        approval_status=status,
        is_published=published,
    )
    before = _listing_state(context, "foreign-listing")
    _staff(context, role="agency_admin", tenant_id="agency-one")

    foreign = _call(context, method, _url("agency-one", "foreign-listing") + suffix, body)
    missing = _call(context, method, _url("agency-one", "missing-listing") + suffix, body)

    assert foreign.status_code == missing.status_code == 404, name
    assert foreign.json() == missing.json()
    assert _listing_state(context, "foreign-listing") == before
    assert not _history(context, "foreign-listing")


@pytest.mark.parametrize(
    ("role", "tenant_id"),
    [("agency_admin", "agency-two"), ("agent", "agency-two"), ("platform_admin", None)],
    ids=["other-agency-admin", "other-agency-agent", "platform-admin"],
)
@pytest.mark.parametrize(
    ("name", "method", "suffix", "body", "state"), _LISTING_ROUTES, ids=_ROUTE_IDS
)
def test_actors_outside_the_agency_are_forbidden_on_every_listing_route(
    f04_context: F04Context,
    role: str,
    tenant_id: str | None,
    name: str,
    method: str,
    suffix: str,
    body: dict[str, Any] | None,
    state: tuple[str, bool],
) -> None:
    context = f04_context
    status, published = state
    _seed_listing(
        context, "private-listing", approval_status=status, is_published=published
    )
    before = _listing_state(context, "private-listing")
    _staff(context, role=role, tenant_id=tenant_id)

    response = _call(context, method, _url("agency-one", "private-listing") + suffix, body)

    assert response.status_code == 403, name
    assert "private-listing" not in response.text
    assert _listing_state(context, "private-listing") == before
    assert not _history(context, "private-listing")


@pytest.mark.parametrize(
    ("role", "tenant_id"),
    [("agency_admin", "agency-two"), ("agent", "agency-two"), ("platform_admin", None)],
    ids=["other-agency-admin", "other-agency-agent", "platform-admin"],
)
def test_actors_outside_the_agency_cannot_list_or_create_its_listings(
    f04_context: F04Context, role: str, tenant_id: str | None
) -> None:
    context = f04_context
    _seed_listing(context, "private-listing")
    _staff(context, role=role, tenant_id=tenant_id)

    listed = context.client.get(_collection_url("agency-one"))
    created = context.client.post(_collection_url("agency-one"), json=_payload())

    assert listed.status_code == created.status_code == 403
    assert "private-listing" not in listed.text
    with context.session_factory() as session:
        assert session.query(Listing).count() == 1


def _real_staff_headers(context: F04Context) -> dict[str, str]:
    """Bearer token of a real agency-one admin session, without overrides."""
    now = datetime.now(timezone.utc)
    with context.session_factory.begin() as session:
        if session.get(Agency, "agency-one") is None:
            session.add(Agency(id="agency-one"))
            session.flush()
        session.add(
            StaffAccount(
                id="real-admin",
                email="real-admin@example.test",
                password_hash="test-password-hash",
                role="agency_admin",
                tenant_id="agency-one",
                active=True,
                totp_secret_encrypted="encrypted-test-secret",
                totp_enabled=True,
                created_at=now,
            )
        )
        session.add(
            StaffSession(
                id="real-admin-session",
                user_id="real-admin",
                refresh_hash="refresh-real-admin",
                csrf_hash="csrf-real-admin",
                created_at=now,
                last_activity_at=now,
                expires_at=now + timedelta(hours=1),
            )
        )
    token = create_access_token(
        user_id="real-admin",
        session_id="real-admin-session",
        signing_key=context.app.state.settings.jwt_secret,
        now=now,
        lifetime_minutes=15,
    )
    return {"Authorization": f"Bearer {token}"}


def _customer_headers(context: F04Context) -> dict[str, str]:
    """Bearer token of a real customer session, issued by the customer API."""
    credentials = {"email": "customer@example.test", "password": "password"}
    registered = context.client.post("/api/v1/customer/auth/register", json=credentials)
    assert registered.status_code == 201, registered.text
    login = context.client.post("/api/v1/customer/auth/login", json=credentials)
    assert login.status_code == 200, login.text
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def test_staff_listing_routes_require_a_staff_session_with_real_authentication(
    f04_context: F04Context,
) -> None:
    context = f04_context
    for status, published in {route[4] for route in _LISTING_ROUTES}:
        _seed_listing(
            context,
            f"listing-{status}-{published}".lower(),
            approval_status=status,
            is_published=published,
        )
    staff_headers = _real_staff_headers(context)
    credentials = {
        "no credentials": {},
        "malformed": {"Authorization": "Bearer not-a-token"},
        "customer session": _customer_headers(context),
    }
    requests = [("GET", _collection_url("agency-one"), None), ("POST", _collection_url("agency-one"), _payload())]
    for _name, method, suffix, body, (status, published) in _LISTING_ROUTES:
        listing_id = f"listing-{status}-{published}".lower()
        requests.append((method, _url("agency-one", listing_id) + suffix, body))

    for label, headers in credentials.items():
        for method, url, body in requests:
            response = context.client.request(method, url, json=body, headers=headers)
            assert response.status_code == 401, f"{label}: {method} {url}"

    with context.session_factory() as session:
        assert session.query(Listing).count() == len({route[4] for route in _LISTING_ROUTES})
    control = context.client.get(_collection_url("agency-one"), headers=staff_headers)
    assert control.status_code == 200, control.text


_F05M_EXTRAS_PAYLOAD: list[dict[str, Any]] = [
    {
        "name": "Cama queen",
        "price": "1500.00",
        "category": "bed",
        "room": "dormitorio",
        "width_cm": 160,
        "height_cm": 110,
        "depth_cm": 210,
        "origin": "Importada",
        "visual_reference": "https://cdn.example.test/bed.png",
        "quantity": 2,
    },
    {
        "name": "Sofá tres cuerpos",
        "price": "800.00",
        "quantity": 1,
    },
]

_EXTRA_DETAIL_FIELDS = {
    "extra_id",
    "name",
    "price",
    "category",
    "room",
    "width_cm",
    "height_cm",
    "depth_cm",
    "origin",
    "visual_reference",
    "quantity",
}


def _with_stable_ids(extras: list[dict[str, Any]], response_extras: list[dict[str, Any]]) -> list[dict[str, Any]]:
    assert len(extras) == len(response_extras)
    ids_by_name = {served["name"]: served["extra_id"] for served in response_extras}
    return [
        {"extra_id": ids_by_name[payload["name"]], **payload} for payload in extras
    ]


def _by_name(served: list[dict[str, Any]], name: str) -> dict[str, Any]:
    return next(extra for extra in served if extra["name"] == name)


def _create_listing_with_extras(
    context: F04Context,
    *,
    extras: list[dict[str, Any]] | None = None,
) -> Any:
    _staff(context)
    body = _payload(extras=_F05M_EXTRAS_PAYLOAD if extras is None else extras)
    created = context.client.post(_collection_url("agency-one"), json=body)
    assert created.status_code == 201, created.text
    return created.json()


def _publish_listing(context: F04Context, listing_id: str) -> None:
    _seed_confirmed_photo(context, listing_id)
    for action in ("submit", "approve", "publish"):
        moved = context.client.post(_url("agency-one", listing_id) + f"/{action}")
        assert moved.status_code == 200, moved.text


def test_create_listing_with_extras_inserts_every_payload_extra_with_new_ids(
    f04_context: F04Context,
) -> None:
    context = f04_context
    body = _create_listing_with_extras(context)

    served = body["extras"]
    assert len(served) == 2
    assert all(set(extra) == _EXTRA_DETAIL_FIELDS for extra in served)
    bed = _by_name(served, "Cama queen")
    sofa = _by_name(served, "Sof\u00e1 tres cuerpos")
    assert bed["extra_id"] != sofa["extra_id"]
    assert all(len(extra["extra_id"]) == 36 for extra in served)
    assert bed["price"] == "1500.00"
    assert bed["category"] == "bed"
    assert bed["room"] == "dormitorio"
    assert bed["width_cm"] == 160
    assert bed["height_cm"] == 110
    assert bed["depth_cm"] == 210
    assert bed["origin"] == "Importada"
    assert bed["visual_reference"] == "https://cdn.example.test/bed.png"
    assert bed["quantity"] == 2
    assert sofa["category"] is None
    assert sofa["width_cm"] is None
    assert sofa["quantity"] == 1
    # The existing trigger rule bumps the offer version once per inserted extra.
    assert body["offer_version"] == 3


def test_create_listing_without_extras_echoes_an_empty_set(f04_context: F04Context) -> None:
    context = f04_context
    body = _create_listing_with_extras(context, extras=[])

    assert body["extras"] == []
    assert body["offer_version"] == 1


def test_edit_with_identical_extras_payload_keeps_ids_and_offer_version(
    f04_context: F04Context,
) -> None:
    context = f04_context
    created = _create_listing_with_extras(context)
    payload = _payload(extras=_with_stable_ids(_F05M_EXTRAS_PAYLOAD, created["extras"]))

    edited = context.client.put(_url("agency-one", created["listing_id"]), json=payload)

    assert edited.status_code == 200, edited.text
    assert edited.json()["offer_version"] == created["offer_version"]
    ids_before = {
        extra["name"]: extra["extra_id"] for extra in created["extras"]
    }
    assert {
        extra["name"]: extra["extra_id"] for extra in edited.json()["extras"]
    } == ids_before
    assert all(
        set(extra) == _EXTRA_DETAIL_FIELDS for extra in edited.json()["extras"]
    )


def test_edit_updates_an_extra_in_place_keeping_its_stable_id(
    f04_context: F04Context,
) -> None:
    context = f04_context
    created = _create_listing_with_extras(context)
    payload_extras = _with_stable_ids(_F05M_EXTRAS_PAYLOAD, created["extras"])
    payload_extras[0]["price"] = "1750.00"
    edited = context.client.put(
        _url("agency-one", created["listing_id"]), json=_payload(extras=payload_extras)
    )

    assert edited.status_code == 200, edited.text
    assert edited.json()["offer_version"] == created["offer_version"] + 1
    served = edited.json()["extras"]
    ids_before = {
        extra["name"]: extra["extra_id"] for extra in created["extras"]
    }
    assert {
        extra["name"]: extra["extra_id"] for extra in served
    } == ids_before
    assert _by_name(served, "Cama queen")["price"] == "1750.00"


def test_edit_quantity_change_is_an_offer_change(f04_context: F04Context) -> None:
    context = f04_context
    created = _create_listing_with_extras(context)
    payload_extras = _with_stable_ids(_F05M_EXTRAS_PAYLOAD, created["extras"])
    payload_extras[1]["quantity"] = 4
    edited = context.client.put(
        _url("agency-one", created["listing_id"]), json=_payload(extras=payload_extras)
    )

    assert edited.status_code == 200, edited.text
    assert edited.json()["offer_version"] == created["offer_version"] + 1
    assert _by_name(edited.json()["extras"], "Sof\u00e1 tres cuerpos")["quantity"] == 4


def test_edit_descriptive_extra_fields_do_not_bump_offer_version(
    f04_context: F04Context,
) -> None:
    context = f04_context
    created = _create_listing_with_extras(context)
    payload_extras = _with_stable_ids(_F05M_EXTRAS_PAYLOAD, created["extras"])
    payload_extras[0]["category"] = "sofa"
    payload_extras[0]["room"] = "living"
    payload_extras[0]["origin"] = "Nacional"
    payload_extras[0]["visual_reference"] = "https://cdn.example.test/sofa.png"
    payload_extras[0]["width_cm"] = 200
    edited = context.client.put(
        _url("agency-one", created["listing_id"]), json=_payload(extras=payload_extras)
    )

    assert edited.status_code == 200, edited.text
    assert edited.json()["offer_version"] == created["offer_version"]
    bed = _by_name(edited.json()["extras"], "Cama queen")
    assert bed["category"] == "sofa"
    assert bed["room"] == "living"
    assert bed["origin"] == "Nacional"
    assert bed["width_cm"] == 200


def test_edit_inserts_new_extras_and_deletes_missing_ones(
    f04_context: F04Context,
) -> None:
    context = f04_context
    created = _create_listing_with_extras(context)
    kept = _by_name(created["extras"], "Cama queen")
    new_extra = {
        "name": "Escritorio",
        "price": "450.00",
        "room": "estudio",
        "quantity": 1,
    }
    payload = _payload(extras=[{"extra_id": kept["extra_id"], **{k: v for k, v in _F05M_EXTRAS_PAYLOAD[0].items()}}, new_extra])

    edited = context.client.put(_url("agency-one", created["listing_id"]), json=payload)

    assert edited.status_code == 200, edited.text
    served = edited.json()["extras"]
    desk = _by_name(served, "Escritorio")
    assert _by_name(served, "Cama queen")["extra_id"] == kept["extra_id"]
    assert desk["extra_id"] != kept["extra_id"]
    # One deletion and one insertion each advance the offer version once.
    assert edited.json()["offer_version"] == created["offer_version"] + 2


def test_edit_rejects_unknown_extra_references_without_changes(
    f04_context: F04Context,
) -> None:
    context = f04_context
    created = _create_listing_with_extras(context)
    payload = _payload(
        extras=[{"extra_id": "0" * 36, **_F05M_EXTRAS_PAYLOAD[0]}]
    )

    edited = context.client.put(_url("agency-one", created["listing_id"]), json=payload)

    assert edited.status_code == 422, edited.text
    assert edited.json()["code"] == "validation_error"
    with context.session_factory() as session:
        stored = (
            session.query(Listing)
            .filter(Listing.id == created["listing_id"])
            .one()
        )
        assert stored.offer_version == created["offer_version"]
        assert len(stored.extras) == 2


@pytest.mark.parametrize(
    "extra_change",
    [
        {"quantity": 0},
        {"width_cm": 0},
        {"height_cm": -5},
        {"category": "   "},
        {"name": "   "},
    ],
)
def test_invalid_extra_payloads_are_rejected_without_creating_a_listing(
    f04_context: F04Context, extra_change: dict[str, Any]
) -> None:
    context = f04_context
    _staff(context)
    payload_extra = {**_F05M_EXTRAS_PAYLOAD[0], **extra_change}
    response = context.client.post(
        _collection_url("agency-one"), json=_payload(extras=[payload_extra])
    )

    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"


def test_published_detail_echoes_the_full_extra_set(
    f04_context: F04Context,
) -> None:
    context = f04_context
    created = _create_listing_with_extras(context)
    _publish_listing(context, created["listing_id"])

    detail = context.client.get(f"/api/v1/listings/{created['listing_id']}")

    assert detail.status_code == 200, detail.text
    served = detail.json()["extras"]
    assert len(served) == 2
    assert all(set(extra) == _EXTRA_DETAIL_FIELDS for extra in served)
    assert _by_name(served, "Cama queen")["quantity"] == 2
    assert _by_name(served, "Sof\u00e1 tres cuerpos")["category"] is None


def test_quote_lines_and_totals_multiply_extra_price_by_quantity(
    f04_context: F04Context,
) -> None:
    context = f04_context
    created = _create_listing_with_extras(context)
    _publish_listing(context, created["listing_id"])
    extra_id = _by_name(created["extras"], "Cama queen")["extra_id"]

    quote = context.client.post(
        "/api/v1/quotes",
        json={
            "listing_id": created["listing_id"],
            "offer_version": created["offer_version"],
            "selected_extra_ids": [extra_id],
        },
    )

    assert quote.status_code == 201, quote.text
    lines = quote.json()["lines"]
    extra_line = next(line for line in lines if line["kind"] == "extra")
    assert extra_line["amount"] == "3000.00"
    assert quote.json()["one_time_total"] == {"amount": "128000.00", "currency": "BOB"}
    assert quote.json()["monthly_total"] == {"amount": "0.00", "currency": "BOB"}


def test_quote_snapshot_stays_immutable_after_extras_authoring(
    f04_context: F04Context,
) -> None:
    from sqlalchemy import text
    from sqlalchemy.exc import IntegrityError

    context = f04_context
    created = _create_listing_with_extras(context)
    _publish_listing(context, created["listing_id"])
    quote = context.client.post(
        "/api/v1/quotes",
        json={
            "listing_id": created["listing_id"],
            "offer_version": created["offer_version"],
            "selected_extra_ids": [],
        },
    )
    assert quote.status_code == 201, quote.text
    quote_id = quote.json()["quote_id"]

    with context.session_factory.begin() as session:
        with pytest.raises(IntegrityError):
            session.execute(
                text("UPDATE quote_snapshot SET one_time_total = 0 WHERE id = :id"),
                {"id": quote_id},
            )
        with pytest.raises(IntegrityError):
            session.execute(
                text("DELETE FROM quote_snapshot WHERE id = :id"),
                {"id": quote_id},
            )
