from __future__ import annotations

import importlib.util
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from threading import Event
from typing import Any

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, insert, text, update
from sqlalchemy.exc import DatabaseError, IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import QueuePool, StaticPool

from app.core.config import Settings
from app.core.security import create_access_token
from app.db.base import Base
from app.db.session import (
    _authorize_sqlite_offer_version_guard,
    create_session_factory,
    protect_session_factory,
)
from app.main import create_app
from app.modules.identity.models import Agency, StaffAccount, StaffSession


_CATALOG_TEST_JWT_SECRET = "catalog-test-secret-that-is-at-least-thirty-two-bytes"


@dataclass
class CatalogApiContext:
    client: TestClient
    session_factory: sessionmaker[Session]


@pytest.fixture

def catalog_api_context() -> Iterator[CatalogApiContext]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    session_factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    Base.metadata.create_all(engine)
    migration_path = (
        Path(__file__).resolve().parents[1]
        / "alembic"
        / "versions"
        / "0007_catalog_offers.py"
    )
    migration_spec = importlib.util.spec_from_file_location(
        "catalog_offer_triggers_for_api_tests", migration_path
    )
    assert migration_spec is not None and migration_spec.loader is not None
    migration = importlib.util.module_from_spec(migration_spec)
    migration_spec.loader.exec_module(migration)
    quote_migration_path = (
        Path(__file__).resolve().parents[1]
        / "alembic"
        / "versions"
        / "0008_quote_snapshots.py"
    )
    quote_migration_spec = importlib.util.spec_from_file_location(
        "quote_snapshot_triggers_for_api_tests", quote_migration_path
    )
    assert quote_migration_spec is not None and quote_migration_spec.loader is not None
    quote_migration = importlib.util.module_from_spec(quote_migration_spec)
    quote_migration_spec.loader.exec_module(quote_migration)
    deposit_migration_path = (
        Path(__file__).resolve().parents[1]
        / "alembic"
        / "versions"
        / "0009_agency_wallets_listing_deposit.py"
    )
    deposit_migration_spec = importlib.util.spec_from_file_location(
        "listing_deposit_triggers_for_api_tests", deposit_migration_path
    )
    assert deposit_migration_spec is not None and deposit_migration_spec.loader is not None
    deposit_migration = importlib.util.module_from_spec(deposit_migration_spec)
    deposit_migration_spec.loader.exec_module(deposit_migration)
    with engine.begin() as connection:
        migration_context = MigrationContext.configure(connection)
        with Operations.context(migration_context):
            migration._install_offer_version_triggers()
            quote_migration._install_snapshot_immutability()
            deposit_migration._install_listing_deposit_offer_version_triggers()
    app = create_app(
        settings=Settings(
            database_url="sqlite+pysqlite:///:memory:",
            jwt_secret=_CATALOG_TEST_JWT_SECRET,
            totp_encryption_key="MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=",
            web_origin="http://localhost",
        ),
        session_factory=session_factory,
    )
    with TestClient(app) as client:
        yield CatalogApiContext(client=client, session_factory=session_factory)
    engine.dispose()


def _seed_listing(
    context: CatalogApiContext,
    *,
    listing_id: str,
    agency_id: str = "agency-one",
    approval_status: str = "approved",
    is_published: bool = True,
    operation: str = "sale",
    base_price: str = "100000.00",
    city: str = "Córdoba",
    zone: str = "Centro",
    bedrooms: int = 2,
    bathrooms: int = 1,
    created_at: datetime | None = None,
    extras: tuple[tuple[str, str, str], ...] = (),
    description: str = "private description",
    exact_address: str = "private exact address",
    photos: tuple[str, ...] = ("private-photo.jpg",),
) -> None:
    from app.modules.catalog.models import Listing, ListingExtra

    with context.session_factory.begin() as session:
        if session.get(Agency, agency_id) is None:
            session.add(Agency(id=agency_id))
            session.flush()
        listing = Listing(
            id=listing_id,
            agency_id=agency_id,
            approval_status=approval_status,
            is_published=is_published,
            operation=operation,
            base_price=Decimal(base_price),
            offer_version=1,
            city=city,
            zone=zone,
            bedrooms=bedrooms,
            bathrooms=bathrooms,
            created_at=created_at or datetime(2026, 9, 1, tzinfo=timezone.utc),
            description=description,
            exact_address=exact_address,
            photos=list(photos),
        )
        session.add(listing)
        session.add_all(
            ListingExtra(
                id=extra_id,
                listing_id=listing_id,
                name=name,
                price=Decimal(price),
            )
            for extra_id, name, price in extras
        )


def _listing_ids(response: Any) -> list[str]:
    return [item["listing_id"] for item in response.json()["items"]]


def _staff_headers(
    context: CatalogApiContext,
    *,
    account_id: str = "agency-admin",
    role: str = "agency_admin",
    tenant_id: str | None = "agency-one",
) -> dict[str, str]:
    now = datetime.now(timezone.utc)
    session_id = f"session-{account_id}"
    with context.session_factory.begin() as session:
        if tenant_id is not None and session.get(Agency, tenant_id) is None:
            session.add(Agency(id=tenant_id))
            session.flush()
        session.add(
            StaffAccount(
                id=account_id,
                email=f"{account_id}@example.test",
                password_hash="test-password-hash",
                role=role,
                tenant_id=tenant_id,
                active=True,
                totp_secret_encrypted="encrypted-test-secret",
                totp_enabled=True,
                created_at=now,
            )
        )
        session.add(
            StaffSession(
                id=session_id,
                user_id=account_id,
                refresh_hash=f"refresh-{account_id}",
                csrf_hash=f"csrf-{account_id}",
                created_at=now,
                last_activity_at=now,
                expires_at=now + timedelta(hours=1),
            )
        )
    token = create_access_token(
        user_id=account_id,
        session_id=session_id,
        signing_key=_CATALOG_TEST_JWT_SECRET,
        now=now,
        lifetime_minutes=15,
    )
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.parametrize("amount", ["0.00", "-0.01", "1.001"])
def test_deposit_configuration_rejects_nonpositive_or_excess_precision(
    catalog_api_context: CatalogApiContext, amount: str
) -> None:
    context = catalog_api_context
    _seed_listing(context, listing_id="invalid-deposit")

    response = context.client.patch(
        "/api/v1/staff/agencies/agency-one/listings/invalid-deposit/deposit",
        json={"deposit_amount_cop": amount},
        headers=_staff_headers(context),
    )

    assert response.status_code == 422


def test_only_owning_agency_admin_can_configure_listing_deposit(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(context, listing_id="owned-deposit")
    _seed_listing(context, listing_id="other-agency-deposit", agency_id="agency-two")
    own_headers = _staff_headers(context)

    configured = context.client.patch(
        "/api/v1/staff/agencies/agency-one/listings/owned-deposit/deposit",
        json={"deposit_amount_cop": "1250.50"},
        headers=own_headers,
    )
    cross_tenant = context.client.patch(
        "/api/v1/staff/agencies/agency-two/listings/other-agency-deposit/deposit",
        json={"deposit_amount_cop": "1250.50"},
        headers=own_headers,
    )
    agent = context.client.patch(
        "/api/v1/staff/agencies/agency-one/listings/owned-deposit/deposit",
        json={"deposit_amount_cop": "1500.00"},
        headers=_staff_headers(context, account_id="listing-agent", role="agent"),
    )
    platform_admin = context.client.patch(
        "/api/v1/staff/agencies/agency-one/listings/owned-deposit/deposit",
        json={"deposit_amount_cop": "1500.00"},
        headers=_staff_headers(
            context,
            account_id="listing-platform-admin",
            role="platform_admin",
            tenant_id=None,
        ),
    )

    assert configured.status_code == 200, configured.text
    assert configured.json() == {
        "listing_id": "owned-deposit",
        "deposit_amount_cop": "1250.50",
        "offer_version": 2,
    }
    assert [cross_tenant.status_code, agent.status_code, platform_admin.status_code] == [
        403,
        403,
        403,
    ]
    from app.modules.catalog.models import Listing

    with context.session_factory() as session:
        owned = session.get(Listing, "owned-deposit")
        other = session.get(Listing, "other-agency-deposit")
        assert owned is not None and owned.deposit_amount_cop == Decimal("1250.50")
        assert other is not None and other.deposit_amount_cop is None


def test_deposit_change_invalidates_existing_quote_by_offer_version(
    catalog_api_context: CatalogApiContext,
) -> None:
    from app.modules.catalog.errors import QuoteOfferVersionMismatchError
    from app.modules.catalog.models import Listing
    from app.modules.catalog.service import validate_quote_for_use

    context = catalog_api_context
    _seed_listing(context, listing_id="deposit-quote")
    quote_response = context.client.post(
        "/api/v1/quotes",
        json={
            "listing_id": "deposit-quote",
            "offer_version": 1,
            "selected_extra_ids": [],
        },
    )
    assert quote_response.status_code == 201, quote_response.text
    changed = context.client.patch(
        "/api/v1/staff/agencies/agency-one/listings/deposit-quote/deposit",
        json={"deposit_amount_cop": "5000.00"},
        headers=_staff_headers(context),
    )
    assert changed.status_code == 200, changed.text
    assert changed.json()["offer_version"] == 2

    with context.session_factory() as session:
        listing = session.get(Listing, "deposit-quote")
        assert listing is not None and listing.offer_version == 2
        with pytest.raises(QuoteOfferVersionMismatchError):
            validate_quote_for_use(
                session,
                quote_response.json()["quote_id"],
                now=datetime.now(timezone.utc),
            )


def test_public_list_is_approved_published_and_cross_agency(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(context, listing_id="visible-a", agency_id="agency-a")
    _seed_listing(context, listing_id="visible-b", agency_id="agency-b")
    _seed_listing(context, listing_id="draft", approval_status="pending")
    _seed_listing(context, listing_id="unpublished", is_published=False)
    _seed_listing(context, listing_id="rejected", approval_status="rejected")

    response = context.client.get("/api/v1/listings")

    assert response.status_code == 200
    assert set(_listing_ids(response)) == {"visible-a", "visible-b"}
    assert set(response.json()["items"][0]) == {
        "listing_id",
        "offer_version",
        "operation",
        "base_price",
        "city",
        "zone",
    }


def test_detail_has_minimal_public_schema_and_hides_private_fields(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(
        context,
        listing_id="detail-listing",
        extras=(("extra-stable-id", "Amoblamiento", "1234.50"),),
    )

    response = context.client.get("/api/v1/listings/detail-listing")

    assert response.status_code == 200
    assert response.json() == {
        "listing_id": "detail-listing",
        "offer_version": 2,
        "operation": "sale",
        "base_price": {"amount": "100000.00", "currency": "COP"},
        "city": "Córdoba",
        "zone": "Centro",
        "bedrooms": 2,
        "bathrooms": 1,
        "extras": [
            {
                "extra_id": "extra-stable-id",
                "name": "Amoblamiento",
                "price": {"amount": "1234.50", "currency": "COP"},
            }
        ],
    }
    serialized = response.text
    assert "private description" not in serialized
    assert "private exact address" not in serialized
    assert "private-photo.jpg" not in serialized
    assert set(response.json()["extras"][0]) == {"extra_id", "name", "price"}


def test_missing_and_non_visible_listing_detail_return_same_404(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(context, listing_id="hidden", is_published=False)

    missing = context.client.get("/api/v1/listings/not-found")
    hidden = context.client.get("/api/v1/listings/hidden")

    assert missing.status_code == hidden.status_code == 404
    assert missing.json() == hidden.json()


def test_city_zone_operation_price_and_room_filters_are_applied(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(
        context,
        listing_id="cordoba-centro-sale",
        base_price="100000.00",
        bedrooms=2,
        bathrooms=1,
    )
    _seed_listing(
        context,
        listing_id="cordoba-centro-rent",
        agency_id="agency-two",
        operation="rent",
        base_price="150000.00",
        city="CÓRDOBA",
        bedrooms=3,
        bathrooms=2,
    )
    _seed_listing(
        context,
        listing_id="rosario-norte-sale",
        agency_id="agency-three",
        city="Rosario",
        zone="Norte",
        base_price="250000.00",
        bedrooms=4,
        bathrooms=3,
    )
    _seed_listing(
        context,
        listing_id="cordoba-sur-sale",
        agency_id="agency-four",
        zone="Sur",
        base_price="175000.00",
        bedrooms=1,
        bathrooms=1,
    )

    cases = [
        (
            {"city": "  CÓRDOBA  "},
            {"cordoba-centro-sale", "cordoba-centro-rent", "cordoba-sur-sale"},
        ),
        (
            {"zone": " centro "},
            {"cordoba-centro-sale", "cordoba-centro-rent"},
        ),
        ({"operation": "rent"}, {"cordoba-centro-rent"}),
        (
            {"min_base_price": "150000.00"},
            {"cordoba-centro-rent", "rosario-norte-sale", "cordoba-sur-sale"},
        ),
        (
            {"max_base_price": "150000.00"},
            {"cordoba-centro-sale", "cordoba-centro-rent"},
        ),
        (
            {"min_rooms": "3"},
            {"cordoba-centro-rent", "rosario-norte-sale"},
        ),
        (
            {"min_bathrooms": "2"},
            {"cordoba-centro-rent", "rosario-norte-sale"},
        ),
        (
            {
                "min_base_price": "150000.00",
                "max_base_price": "175000.00",
                "min_rooms": "1",
                "min_bathrooms": "1",
            },
            {"cordoba-centro-rent", "cordoba-sur-sale"},
        ),
    ]
    for filters, expected_ids in cases:
        response = context.client.get("/api/v1/listings", params=filters)
        assert response.status_code == 200, filters
        assert set(_listing_ids(response)) == expected_ids, filters


def test_offer_version_advances_when_base_price_or_extras_change(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(context, listing_id="versioned-offer")

    from app.modules.catalog.models import Listing, ListingExtra

    with context.session_factory.begin() as session:
        listing = session.get(Listing, "versioned-offer")
        assert listing is not None
        listing.base_price = Decimal("125000.00")
    with context.session_factory() as session:
        listing = session.get(Listing, "versioned-offer")
        assert listing is not None and listing.offer_version == 2

    with context.session_factory.begin() as session:
        listing = session.get(Listing, "versioned-offer")
        assert listing is not None
        listing.operation = "rent"
    with context.session_factory() as session:
        listing = session.get(Listing, "versioned-offer")
        assert listing is not None and listing.offer_version == 3

    with context.session_factory.begin() as session:
        session.add(
            ListingExtra(
                id="versioned-extra",
                listing_id="versioned-offer",
                name="Furniture",
                price=Decimal("100.00"),
            )
        )
    with context.session_factory() as session:
        listing = session.get(Listing, "versioned-offer")
        assert listing is not None and listing.offer_version == 4

    with context.session_factory.begin() as session:
        extra = session.get(ListingExtra, "versioned-extra")
        assert extra is not None
        extra.name = "Upgraded furniture"
        extra.price = Decimal("150.00")
    with context.session_factory() as session:
        listing = session.get(Listing, "versioned-offer")
        assert listing is not None and listing.offer_version == 5

    with context.session_factory.begin() as session:
        extra = session.get(ListingExtra, "versioned-extra")
        assert extra is not None
        session.delete(extra)
    with context.session_factory() as session:
        listing = session.get(Listing, "versioned-offer")
        assert listing is not None and listing.offer_version == 6


@pytest.mark.parametrize("reassign_by_relationship", [True, False])
def test_reassigning_extra_advances_both_offer_versions(
    catalog_api_context: CatalogApiContext, reassign_by_relationship: bool
) -> None:
    context = catalog_api_context
    _seed_listing(
        context,
        listing_id="source-offer",
        extras=(("movable-extra", "Furniture", "100.00"),),
    )
    _seed_listing(context, listing_id="destination-offer")

    from app.modules.catalog.models import Listing, ListingExtra

    with context.session_factory.begin() as session:
        extra = session.get(ListingExtra, "movable-extra")
        destination = session.get(Listing, "destination-offer")
        assert extra is not None and destination is not None
        if reassign_by_relationship:
            extra.listing = destination
        else:
            extra.listing_id = destination.id
        extra.price = Decimal("150.00")
        destination.base_price = Decimal("125000.00")

    with context.session_factory() as session:
        source = session.get(Listing, "source-offer")
        destination = session.get(Listing, "destination-offer")
        assert source is not None and destination is not None
        assert source.offer_version == 3
        assert destination.offer_version == 3


@pytest.mark.parametrize(
    "bulk_path",
    ["query_update", "execute_listing_update", "execute_extra_update", "query_delete", "execute_insert"],
)
def test_bulk_catalog_writes_advance_offer_versions(
    catalog_api_context: CatalogApiContext, bulk_path: str
) -> None:
    context = catalog_api_context
    _seed_listing(
        context,
        listing_id="bulk-offer",
        extras=(("bulk-extra", "Furniture", "100.00"),),
    )

    from app.modules.catalog.models import Listing, ListingExtra

    with context.session_factory.begin() as session:
        if bulk_path == "query_update":
            session.query(Listing).filter(Listing.id == "bulk-offer").update(
                {Listing.base_price: Decimal("125000.00")}, synchronize_session=False
            )
        elif bulk_path == "execute_listing_update":
            session.execute(
                update(Listing)
                .where(Listing.id == "bulk-offer")
                .values(operation="rent")
            )
        elif bulk_path == "execute_extra_update":
            session.execute(
                update(ListingExtra)
                .where(ListingExtra.id == "bulk-extra")
                .values(price=Decimal("150.00"))
            )
        elif bulk_path == "query_delete":
            session.query(ListingExtra).filter(
                ListingExtra.id == "bulk-extra"
            ).delete(synchronize_session=False)
        else:
            session.execute(
                insert(ListingExtra).values(
                    id="bulk-extra-added",
                    listing_id="bulk-offer",
                    name="Storage",
                    price=Decimal("50.00"),
                )
            )

    with context.session_factory() as session:
        listing = session.get(Listing, "bulk-offer")
        assert listing is not None and listing.offer_version == 3


def test_session_bulk_apis_advance_versions_for_listings_and_extras(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(
        context,
        listing_id="bulk-api-offer",
        extras=(("bulk-api-extra", "Furniture", "100.00"),),
    )

    from app.modules.catalog.models import Listing, ListingExtra

    with context.session_factory() as session:
        session.bulk_save_objects(
            [
                ListingExtra(
                    id="bulk-save-extra",
                    listing_id="bulk-api-offer",
                    name="Storage",
                    price=Decimal("50.00"),
                )
            ]
        )
        session.commit()
    with context.session_factory() as session:
        saved_extra = session.get(ListingExtra, "bulk-save-extra")
        assert saved_extra is not None
        session.expunge(saved_extra)
        saved_extra.price = Decimal("60.00")
        session.bulk_save_objects([saved_extra])
        session.commit()
    with context.session_factory() as session:
        session.bulk_insert_mappings(
            ListingExtra,
            [
                {
                    "id": "bulk-mapped-extra",
                    "listing_id": "bulk-api-offer",
                    "name": "Parking",
                    "price": Decimal("75.00"),
                }
            ],
        )
        session.commit()
    with context.session_factory() as session:
        session.bulk_update_mappings(
            Listing, [{"id": "bulk-api-offer", "base_price": Decimal("125000.00")}]
        )
        session.commit()
    with context.session_factory() as session:
        session.bulk_update_mappings(
            ListingExtra, [{"id": "bulk-api-extra", "price": Decimal("150.00")}]
        )
        session.commit()

    with context.session_factory() as session:
        listing = session.get(Listing, "bulk-api-offer")
        assert listing is not None and listing.offer_version == 7


def test_bulk_update_mapping_cannot_forge_offer_version(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(context, listing_id="bulk-tamper-offer")

    from app.modules.catalog.models import Listing

    with pytest.raises(IntegrityError):
        with context.session_factory.begin() as session:
            session.bulk_update_mappings(
                Listing, [{"id": "bulk-tamper-offer", "offer_version": 99}]
            )

    with context.session_factory() as session:
        listing = session.get(Listing, "bulk-tamper-offer")
        assert listing is not None and listing.offer_version == 1


def test_raw_sql_business_updates_and_extra_lifecycle_advance_versions(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(
        context,
        listing_id="raw-source",
        extras=(("raw-extra", "Furniture", "100.00"),),
    )
    _seed_listing(context, listing_id="raw-destination")

    with context.session_factory.begin() as session:
        session.execute(
            text("UPDATE listing SET base_price = :price WHERE id = :listing_id"),
            {"price": "125000.00", "listing_id": "raw-source"},
        )
    with context.session_factory.begin() as session:
        session.execute(
            text("UPDATE listing SET operation = 'rent' WHERE id = 'raw-source'")
        )
    with context.session_factory.begin() as session:
        session.execute(
            text(
                "UPDATE listing_extra SET name = 'Updated', price = 150.00 "
                "WHERE id = 'raw-extra'"
            )
        )
    with context.session_factory.begin() as session:
        session.execute(
            text("UPDATE listing_extra SET id = 'raw-extra-renamed' WHERE id = 'raw-extra'")
        )
    with context.session_factory.begin() as session:
        session.execute(
            text(
                "UPDATE listing_extra SET listing_id = 'raw-destination' "
                "WHERE id = 'raw-extra-renamed'"
            )
        )
    with context.session_factory.begin() as session:
        session.execute(
            text(
                "INSERT INTO listing_extra (id, listing_id, name, price) "
                "VALUES ('raw-extra-inserted', 'raw-destination', 'Storage', 50.00)"
            )
        )
    with context.session_factory.begin() as session:
        session.execute(text("DELETE FROM listing_extra WHERE id = 'raw-extra-renamed'"))

    from app.modules.catalog.models import Listing

    with context.session_factory() as session:
        source = session.get(Listing, "raw-source")
        destination = session.get(Listing, "raw-destination")
        assert source is not None and source.offer_version == 7
        assert destination is not None and destination.offer_version == 4


def test_orm_extra_reassignment_and_primary_key_change_advance_affected_offers(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(
        context,
        listing_id="orm-source",
        extras=(("orm-extra", "Furniture", "100.00"),),
    )
    _seed_listing(context, listing_id="orm-destination")

    from app.modules.catalog.models import Listing, ListingExtra

    with context.session_factory.begin() as session:
        extra = session.get(ListingExtra, "orm-extra")
        destination = session.get(Listing, "orm-destination")
        assert extra is not None and destination is not None
        extra.id = "orm-extra-renamed"
        extra.listing_id = destination.id

    with context.session_factory() as session:
        source = session.get(Listing, "orm-source")
        destination = session.get(Listing, "orm-destination")
        assert source is not None and source.offer_version == 3
        assert destination is not None and destination.offer_version == 2


def test_offer_version_cannot_be_directly_forged_but_business_change_advances_once(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(context, listing_id="tamper-offer")

    from app.modules.catalog.models import Listing

    with context.session_factory.begin() as session:
        session.execute(
            text("UPDATE listing SET base_price = 125000.00, offer_version = 99 WHERE id = :id"),
            {"id": "tamper-offer"},
        )
    with context.session_factory() as session:
        listing = session.get(Listing, "tamper-offer")
        assert listing is not None and listing.offer_version == 2

    with pytest.raises(IntegrityError):
        with context.session_factory.begin() as session:
            session.execute(
                text("UPDATE listing SET offer_version = 1 WHERE id = 'tamper-offer'")
            )

    with pytest.raises(IntegrityError):
        with context.session_factory.begin() as session:
            listing = session.get(Listing, "tamper-offer")
            assert listing is not None
            listing.offer_version = 100

    with context.session_factory() as session:
        listing = session.get(Listing, "tamper-offer")
        assert listing is not None and listing.offer_version == 2


def test_sqlite_guard_marker_cannot_be_spoofed_on_application_connection(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(context, listing_id="marker-spoof-offer")

    with pytest.raises(DatabaseError, match="not authorized"):
        with context.session_factory.begin() as session:
            connection = session.connection()
            connection.exec_driver_sql(
                "INSERT INTO listing_offer_version_guard (listing_id) VALUES (?)",
                ("marker-spoof-offer",),
            )
            connection.exec_driver_sql(
                "UPDATE listing SET offer_version = 99 WHERE id = ?",
                ("marker-spoof-offer",),
            )

    from app.modules.catalog.models import Listing

    with context.session_factory() as session:
        listing = session.get(Listing, "marker-spoof-offer")
        assert listing is not None and listing.offer_version == 1


def test_untrusted_sqlite_trigger_cannot_spoof_offer_version_guard_marker(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(context, listing_id="untrusted-trigger-offer")

    raw_connection = context.session_factory.kw["bind"].raw_connection()
    try:
        dbapi_connection = raw_connection.driver_connection
        # Model a trigger installed before application connections are protected.
        dbapi_connection.set_authorizer(None)
        dbapi_connection.execute(
            "CREATE TRIGGER trg_attacker_offer_version_forge "
            "AFTER UPDATE OF base_price ON listing BEGIN "
            "INSERT INTO listing_offer_version_guard (listing_id) VALUES (NEW.id); "
            "UPDATE listing SET offer_version = NEW.offer_version + 99 "
            "WHERE id = NEW.id; END"
        )
    finally:
        dbapi_connection.set_authorizer(_authorize_sqlite_offer_version_guard)
        raw_connection.close()

    with pytest.raises(DatabaseError, match="not authorized"):
        with context.session_factory.begin() as session:
            session.execute(
                text("UPDATE listing SET base_price = 125000.00 WHERE id = :id"),
                {"id": "untrusted-trigger-offer"},
            )

    from app.modules.catalog.models import Listing

    with context.session_factory() as session:
        listing = session.get(Listing, "untrusted-trigger-offer")
        assert listing is not None
        assert listing.base_price == Decimal("100000.00")
        assert listing.offer_version == 1


@pytest.mark.parametrize(
    ("statement", "error_message"),
    [
        ("DROP TRIGGER trg_listing_offer_version_advance", "not authorized"),
        (
            "CREATE TRIGGER trg_listing_offer_version_advance AFTER UPDATE ON listing "
            "BEGIN SELECT 1; END",
            "already exists",
        ),
        ("DROP TABLE listing_offer_version_guard", "not authorized"),
        (
            "ALTER TABLE listing_offer_version_guard RENAME TO replaced_offer_version_guard",
            "not authorized",
        ),
        ("DROP TABLE listing", "not authorized"),
        ("ALTER TABLE listing RENAME TO replaced_listing", "not authorized"),
        ("PRAGMA writable_schema=ON", "not authorized"),
    ],
)
def test_sqlite_application_connections_cannot_replace_or_drop_guard_internals(
    catalog_api_context: CatalogApiContext, statement: str, error_message: str
) -> None:
    with pytest.raises(DatabaseError, match=error_message):
        with catalog_api_context.session_factory.begin() as session:
            session.execute(text(statement))


def test_create_app_protects_injected_sqlite_factory_despite_spoofed_engine_marker() -> None:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    try:
        with engine.begin() as connection:
            connection.execute(
                text(
                    "CREATE TABLE listing_offer_version_guard "
                    "(listing_id VARCHAR(36) PRIMARY KEY)"
                )
            )
        # A pooled DBAPI connection exists before the application installs protection.
        with engine.connect() as connection:
            connection.exec_driver_sql("SELECT 1")
        setattr(engine, "_roomforge_sqlite_offer_version_protection", True)
        unsafe_factory = sessionmaker(bind=engine, expire_on_commit=False)
        app = create_app(
            settings=Settings(
                database_url="sqlite+pysqlite:///:memory:",
                jwt_secret="catalog-test-secret-that-is-at-least-thirty-two-bytes",
                totp_encryption_key="MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=",
                web_origin="http://localhost",
            ),
            session_factory=unsafe_factory,
        )

        with TestClient(app):
            with pytest.raises(DatabaseError, match="not authorized"):
                with app.state.session_factory.begin() as session:
                    session.execute(
                        text(
                            "INSERT INTO listing_offer_version_guard (listing_id) "
                            "VALUES ('injected-factory-offer')"
                        )
                    )
    finally:
        engine.dispose()


def test_create_app_protects_all_mapped_sqlite_binds_with_non_sqlite_default() -> None:
    from app.modules.catalog.models import Listing, ListingExtra

    default_engine = create_engine(
        "postgresql+psycopg://roomforge:unused@localhost/unused"
    )
    first_sqlite_engine = create_engine(
        "sqlite+pysqlite:///:memory:", poolclass=StaticPool
    )
    second_sqlite_engine = create_engine(
        "sqlite+pysqlite:///:memory:", poolclass=StaticPool
    )
    sqlite_binds = {
        Listing: first_sqlite_engine,
        ListingExtra: second_sqlite_engine,
    }
    try:
        for sqlite_engine in sqlite_binds.values():
            with sqlite_engine.begin() as connection:
                connection.execute(
                    text(
                        "CREATE TABLE listing_offer_version_guard "
                        "(listing_id VARCHAR(36) PRIMARY KEY)"
                    )
                )

        injected_factory = sessionmaker(
            bind=default_engine,
            binds=sqlite_binds,
            expire_on_commit=False,
        )
        app = create_app(
            settings=Settings(
                database_url="postgresql+psycopg://roomforge:unused@localhost/unused",
                jwt_secret="catalog-test-secret-that-is-at-least-thirty-two-bytes",
                totp_encryption_key="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                web_origin="http://localhost",
            ),
            session_factory=injected_factory,
        )

        with TestClient(app):
            for mapper, sqlite_engine in sqlite_binds.items():
                with pytest.raises(DatabaseError, match="not authorized"):
                    with app.state.session_factory() as session:
                        connection = session.connection(
                            bind_arguments={"mapper": mapper}
                        )
                        connection.exec_driver_sql(
                            "INSERT INTO listing_offer_version_guard (listing_id) "
                            "VALUES ('mapped-bind-offer')"
                        )
    finally:
        first_sqlite_engine.dispose()
        second_sqlite_engine.dispose()
        default_engine.dispose()


def test_protect_session_factory_authorizes_open_sqlite_connection_bind() -> None:
    from app.modules.catalog.models import Listing

    default_engine = create_engine(
        "postgresql+psycopg://roomforge:unused@localhost/unused"
    )
    sqlite_engine = create_engine("sqlite+pysqlite:///:memory:")
    sqlite_connection = sqlite_engine.connect()
    try:
        sqlite_connection.exec_driver_sql(
            "CREATE TABLE listing_offer_version_guard "
            "(listing_id VARCHAR(36) PRIMARY KEY)"
        )
        injected_factory = sessionmaker(
            bind=default_engine,
            binds={Listing: sqlite_connection},
        )

        protect_session_factory(injected_factory)

        with pytest.raises(DatabaseError, match="not authorized"):
            sqlite_connection.exec_driver_sql(
                "INSERT INTO listing_offer_version_guard (listing_id) "
                "VALUES ('connection-bind-offer')"
            )
    finally:
        sqlite_connection.close()
        sqlite_engine.dispose()
        default_engine.dispose()


def test_protect_session_factory_rejects_uninspectable_bind_value() -> None:
    from app.modules.catalog.models import Listing

    default_engine = create_engine(
        "postgresql+psycopg://roomforge:unused@localhost/unused"
    )
    try:
        injected_factory = sessionmaker(
            bind=default_engine,
            binds={Listing: object()},
        )

        with pytest.raises(RuntimeError, match="unsupported session factory bind"):
            protect_session_factory(injected_factory)
    finally:
        default_engine.dispose()


def test_create_session_factory_protects_sqlite_guard_writes(tmp_path: Path) -> None:
    database_url = f"sqlite+pysqlite:///{tmp_path / 'protected-catalog.db'}"
    setup_engine = create_engine(database_url)
    with setup_engine.begin() as connection:
        connection.execute(
            text(
                "CREATE TABLE listing_offer_version_guard "
                "(listing_id VARCHAR(36) PRIMARY KEY)"
            )
        )
    setup_engine.dispose()

    engine, protected_factory = create_session_factory(database_url)
    try:
        with pytest.raises(DatabaseError, match="not authorized"):
            with protected_factory.begin() as session:
                session.execute(
                    text(
                        "INSERT INTO listing_offer_version_guard (listing_id) "
                        "VALUES ('protected-factory-offer')"
                    )
                )
    finally:
        engine.dispose()


def test_price_serialization_is_exact_cop_with_two_decimals(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(
        context,
        listing_id="exact-price",
        base_price="1234.50",
        extras=(("extra-price", "Extra", "0.10"),),
    )

    list_response = context.client.get("/api/v1/listings")
    detail_response = context.client.get("/api/v1/listings/exact-price")

    assert list_response.status_code == detail_response.status_code == 200
    assert list_response.json()["items"][0]["base_price"] == {
        "amount": "1234.50",
        "currency": "COP",
    }
    assert detail_response.json()["base_price"]["amount"] == "1234.50"
    assert detail_response.json()["extras"][0]["price"]["amount"] == "0.10"


def test_keyset_pagination_is_stable_for_equal_timestamps(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    same_time = datetime(2026, 9, 1, 12, tzinfo=timezone.utc)
    for listing_id in ("listing-a", "listing-b", "listing-c", "listing-d", "listing-e"):
        _seed_listing(context, listing_id=listing_id, created_at=same_time)

    first = context.client.get("/api/v1/listings", params={"limit": 2})
    assert first.status_code == 200
    assert _listing_ids(first) == ["listing-e", "listing-d"]
    cursor = first.json()["next_cursor"]
    assert isinstance(cursor, str) and cursor

    second = context.client.get("/api/v1/listings", params={"limit": 2, "cursor": cursor})
    third = context.client.get(
        "/api/v1/listings", params={"limit": 2, "cursor": second.json()["next_cursor"]}
    )

    assert second.status_code == third.status_code == 200
    assert _listing_ids(second) == ["listing-c", "listing-b"]
    assert _listing_ids(third) == ["listing-a"]
    assert third.json()["next_cursor"] is None
    assert first.json()["next_cursor"] != second.json()["next_cursor"]


def test_default_page_size_is_twenty_and_limit_is_capped_at_one_hundred(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    for index in range(101):
        _seed_listing(context, listing_id=f"listing-{index:03d}")

    default_page = context.client.get("/api/v1/listings")
    maximum_page = context.client.get("/api/v1/listings", params={"limit": 100})
    too_large = context.client.get("/api/v1/listings", params={"limit": 101})

    assert default_page.status_code == maximum_page.status_code == 200
    assert len(default_page.json()["items"]) == 20
    assert default_page.json()["next_cursor"] is not None
    assert len(maximum_page.json()["items"]) == 100
    assert maximum_page.json()["next_cursor"] is not None
    assert too_large.status_code == 422


def test_invalid_cursor_and_reversed_price_range_fail_safely(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context

    invalid_cursor = context.client.get(
        "/api/v1/listings", params={"cursor": "not-a-valid-cursor!"}
    )
    reversed_range = context.client.get(
        "/api/v1/listings",
        params={"min_base_price": "200.00", "max_base_price": "100.00"},
    )

    assert invalid_cursor.status_code == 400
    assert invalid_cursor.json()["detail"] == "invalid_cursor"
    assert reversed_range.status_code == 422


def test_openapi_and_validation_preserve_staff_customer_namespaces(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    openapi = context.client.get("/openapi.json").json()
    paths = openapi["paths"]

    assert set(paths["/api/v1/listings"]) == {"get"}
    assert set(paths["/api/v1/listings/{listing_id}"]) == {"get"}
    assert set(paths["/api/v1/quotes"]) == {"post"}
    assert "/api/v1/auth/login" in paths
    assert "/api/v1/customer/auth/register" in paths
    assert not any(path.startswith("/api/v1/staff/listings") for path in paths)
    assert "422" in paths["/api/v1/listings"]["get"]["responses"]
    schemas = openapi["components"]["schemas"]
    assert set(schemas["CatalogListingItem"]["properties"]) == {
        "listing_id",
        "offer_version",
        "operation",
        "base_price",
        "city",
        "zone",
    }
    assert set(schemas["CatalogListingDetail"]["properties"]) == {
        "listing_id",
        "offer_version",
        "operation",
        "base_price",
        "city",
        "zone",
        "bedrooms",
        "bathrooms",
        "extras",
    }
    assert set(schemas["CatalogExtraItem"]["properties"]) == {
        "extra_id",
        "name",
        "price",
    }

    catalog_invalid = context.client.get("/api/v1/listings", params={"limit": 0})
    staff_invalid = context.client.post("/api/v1/auth/login", json={})
    customer_invalid = context.client.post("/api/v1/customer/auth/register", json={})

    assert catalog_invalid.status_code == staff_invalid.status_code == 422
    assert catalog_invalid.json() == {
        "detail": "Request validation failed",
        "code": "validation_error",
    }
    assert staff_invalid.json() == {
        "detail": "Request validation failed",
        "code": "validation_error",
    }
    assert customer_invalid.status_code == 422
    assert customer_invalid.json() == {
        "detail": "Request validation failed",
        "code": "validation_error",
    }


def _quote_payload(
    *,
    listing_id: str = "quote-listing",
    offer_version: int = 2,
    selected_extra_ids: list[str] | None = None,
) -> dict[str, Any]:
    return {
        "listing_id": listing_id,
        "offer_version": offer_version,
        "selected_extra_ids": selected_extra_ids or [],
    }


def _assert_quote_error(response: Any, *, status_code: int, code: str) -> None:
    assert response.status_code == status_code
    body = response.json()
    assert body["code"] == code
    assert isinstance(body["message"], str)
    assert isinstance(body["request_id"], str) and body["request_id"]
    assert isinstance(body["field_errors"], list)


def test_quote_openapi_and_public_creation_make_a_new_snapshot_per_post(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    context.client.app.state.clock = lambda: datetime(2026, 9, 1, 12, tzinfo=timezone.utc)
    _seed_listing(
        context,
        listing_id="quote-listing",
        extras=(
            ("extra-z", "Storage", "0.20"),
            ("extra-a", "Parking", "0.10"),
        ),
    )

    openapi = context.client.get("/openapi.json").json()
    operation = openapi["paths"]["/api/v1/quotes"]["post"]
    assert "security" not in operation
    assert "201" in operation["responses"]
    assert "422" in operation["responses"]
    assert "429" in operation["responses"]
    retry_after_header = operation["responses"]["429"]["headers"]["Retry-After"]
    assert retry_after_header["schema"]["type"] == "integer"
    assert retry_after_header["description"]
    request_schema = openapi["components"]["schemas"]["QuoteCreateRequest"]
    assert set(request_schema["properties"]) == {
        "listing_id",
        "offer_version",
        "selected_extra_ids",
    }
    assert request_schema["properties"]["offer_version"]["type"] == "integer"
    assert operation["responses"]["201"]["content"]["application/json"]["schema"][
        "$ref"
    ].endswith("/QuoteSnapshotResponse")
    assert "Idempotency-Key" not in str(operation)

    first = context.client.post(
        "/api/v1/quotes",
        json=_quote_payload(offer_version=3, selected_extra_ids=["extra-z", "extra-a"]),
    )
    second = context.client.post(
        "/api/v1/quotes",
        json=_quote_payload(offer_version=3, selected_extra_ids=["extra-z", "extra-a"]),
    )

    assert first.status_code == second.status_code == 201
    first_quote, second_quote = first.json(), second.json()
    assert first_quote["quote_id"] != second_quote["quote_id"]
    assert first_quote["offer_version"] == 3
    assert first_quote["operation"] == "sale"
    assert [line["extra_id"] for line in first_quote["lines"]] == [None, "extra-a", "extra-z"]
    assert first_quote["one_time_total"] == {"amount": "100000.30", "currency": "COP"}
    assert first_quote["monthly_total"] == {"amount": "0.00", "currency": "COP"}
    assert first_quote["expires_at"] == "2026-09-01T12:15:00Z"


def test_quote_ttl_starts_after_rate_limiter_wait(
    catalog_api_context: CatalogApiContext,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = catalog_api_context
    initial_time = datetime(2026, 9, 1, 12, tzinfo=timezone.utc)
    snapshot_time = initial_time + timedelta(minutes=7)
    clock_time = [initial_time]
    context.client.app.state.clock = lambda: clock_time[0]
    _seed_listing(context, listing_id="quote-listing")

    from app.modules.catalog import router as catalog_router

    original_consume_rate_limit = catalog_router.consume_quote_rate_limit
    limiter_entered = Event()
    release_limiter = Event()

    def blocking_consume_rate_limit(*args: Any, **kwargs: Any) -> int | None:
        assert kwargs["now"] == initial_time
        limiter_entered.set()
        assert release_limiter.wait(timeout=5)
        return original_consume_rate_limit(*args, **kwargs)

    monkeypatch.setattr(
        catalog_router, "consume_quote_rate_limit", blocking_consume_rate_limit
    )
    with ThreadPoolExecutor(max_workers=1) as executor:
        response_future = executor.submit(
            context.client.post,
            "/api/v1/quotes",
            json=_quote_payload(offer_version=1),
        )
        entered = limiter_entered.wait(timeout=5)
        clock_time[0] = snapshot_time
        release_limiter.set()
        response = response_future.result(timeout=10)

    assert entered
    assert response.status_code == 201
    quote = response.json()
    created_at = datetime.fromisoformat(quote["created_at"].replace("Z", "+00:00"))
    expires_at = datetime.fromisoformat(quote["expires_at"].replace("Z", "+00:00"))
    assert created_at == snapshot_time
    assert expires_at - created_at == timedelta(minutes=15)

    from app.modules.catalog.models import QuoteRateLimitEvent

    with context.session_factory() as session:
        event = session.query(QuoteRateLimitEvent).one()
        assert event.occurred_at == initial_time.replace(tzinfo=None)


def test_quote_sale_and_rent_charge_periods_and_round_half_up_totals(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    now = datetime(2026, 9, 1, 12, tzinfo=timezone.utc)
    context.client.app.state.clock = lambda: now
    _seed_listing(
        context,
        listing_id="sale-rounding",
        base_price="1.00",
        extras=(("sale-extra", "Furniture", "0.10"),),
    )
    _seed_listing(
        context,
        listing_id="rent-listing",
        agency_id="agency-rent",
        operation="rent",
        base_price="2000.15",
        extras=(("rent-extra", "Parking", "50.25"),),
    )

    sale = context.client.post(
        "/api/v1/quotes",
        json=_quote_payload(
            listing_id="sale-rounding", offer_version=2, selected_extra_ids=["sale-extra"]
        ),
    )
    rent = context.client.post(
        "/api/v1/quotes",
        json=_quote_payload(
            listing_id="rent-listing", offer_version=2, selected_extra_ids=["rent-extra"]
        ),
    )

    assert sale.status_code == rent.status_code == 201
    assert sale.json()["lines"] == [
        {
            "kind": "base",
            "extra_id": None,
            "amount": "1.00",
            "currency": "COP",
            "charge_period": "one_time",
        },
        {
            "kind": "extra",
            "extra_id": "sale-extra",
            "amount": "0.10",
            "currency": "COP",
            "charge_period": "one_time",
        },
    ]
    assert sale.json()["one_time_total"]["amount"] == "1.10"
    assert sale.json()["monthly_total"]["amount"] == "0.00"
    assert rent.json()["operation"] == "rent"
    assert [line["charge_period"] for line in rent.json()["lines"]] == ["monthly", "monthly"]
    assert rent.json()["one_time_total"]["amount"] == "0.00"
    assert rent.json()["monthly_total"]["amount"] == "2050.40"

    from app.modules.catalog.service import _quote_money

    assert _quote_money(Decimal("1.005")) == Decimal("1.01")
    assert _quote_money(Decimal("1.004")) == Decimal("1.00")


def test_quote_rejects_duplicate_or_foreign_extras_and_maps_stale_version(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(
        context,
        listing_id="quote-listing",
        extras=(("owned-extra", "Furniture", "50.00"),),
    )
    _seed_listing(
        context,
        listing_id="other-listing",
        agency_id="agency-other",
        extras=(("foreign-extra", "Storage", "75.00"),),
    )

    duplicate = context.client.post(
        "/api/v1/quotes",
        json=_quote_payload(selected_extra_ids=["owned-extra", "owned-extra"]),
    )
    foreign = context.client.post(
        "/api/v1/quotes",
        json=_quote_payload(selected_extra_ids=["foreign-extra"]),
    )
    stale = context.client.post(
        "/api/v1/quotes",
        json=_quote_payload(offer_version=1),
    )

    _assert_quote_error(duplicate, status_code=422, code="invalid_extra_selection")
    _assert_quote_error(foreign, status_code=422, code="invalid_extra_selection")
    _assert_quote_error(stale, status_code=409, code="offer_version_mismatch")


def test_quote_snapshot_stays_immutable_and_later_use_checks_expiry_and_version(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    now = datetime(2026, 9, 1, 12, tzinfo=timezone.utc)
    context.client.app.state.clock = lambda: now
    _seed_listing(
        context,
        listing_id="quote-listing",
        extras=(("quote-extra", "Furniture", "50.00"),),
    )

    response = context.client.post(
        "/api/v1/quotes",
        json=_quote_payload(selected_extra_ids=["quote-extra"]),
    )
    assert response.status_code == 201
    original = response.json()

    from app.modules.catalog.models import Listing, QuoteSnapshot
    from app.modules.catalog.service import (
        QuoteExpiredError,
        QuoteOfferVersionMismatchError,
        validate_quote_for_use,
    )

    with context.session_factory() as session:
        snapshot = session.get(QuoteSnapshot, original["quote_id"])
        assert snapshot is not None
        stored_lines = snapshot.lines
        stored_total = snapshot.one_time_total
        with pytest.raises(IntegrityError):
            with session.begin_nested():
                snapshot.one_time_total = Decimal("1.00")
                session.flush()

    with context.session_factory.begin() as session:
        listing = session.get(Listing, "quote-listing")
        assert listing is not None
        listing.base_price = Decimal("125000.00")

    with context.session_factory() as session:
        snapshot = session.get(QuoteSnapshot, original["quote_id"])
        assert snapshot is not None
        assert snapshot.lines == stored_lines
        assert snapshot.one_time_total == stored_total
        with pytest.raises(QuoteOfferVersionMismatchError):
            validate_quote_for_use(session, original["quote_id"], now=now)
        with pytest.raises(QuoteExpiredError):
            validate_quote_for_use(
                session,
                original["quote_id"],
                now=now + timedelta(minutes=15),
            )

    repeated = context.client.post(
        "/api/v1/quotes",
        json=_quote_payload(
            offer_version=3,
            selected_extra_ids=["quote-extra"],
        ),
    )
    assert repeated.status_code == 201
    assert repeated.json()["quote_id"] != original["quote_id"]
    assert repeated.json()["one_time_total"]["amount"] == "125050.00"


def test_quote_rate_limit_counts_semantic_failures_and_sets_retry_after_at_boundary(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    now = datetime(2026, 9, 1, 12, tzinfo=timezone.utc)
    context.client.app.state.clock = lambda: now
    invalid_payload = _quote_payload(listing_id="missing-listing", offer_version=1)

    for _ in range(10):
        assert context.client.post("/api/v1/quotes", json=invalid_payload).status_code == 404
    limited = context.client.post("/api/v1/quotes", json=invalid_payload)
    _assert_quote_error(limited, status_code=429, code="rate_limit_exceeded")
    assert limited.headers["Retry-After"] == "60"

    context.client.app.state.clock = lambda: now + timedelta(seconds=59, milliseconds=100)
    almost_ready = context.client.post("/api/v1/quotes", json=invalid_payload)
    _assert_quote_error(almost_ready, status_code=429, code="rate_limit_exceeded")
    assert almost_ready.headers["Retry-After"] == "1"

    context.client.app.state.clock = lambda: now + timedelta(minutes=1)
    _assert_quote_error(
        context.client.post("/api/v1/quotes", json=invalid_payload),
        status_code=404,
        code="listing_not_found",
    )

    from app.modules.catalog.models import QuoteRateLimitEvent

    with context.session_factory() as session:
        assert session.query(QuoteRateLimitEvent).count() == 1


def test_quote_rate_limit_is_per_direct_peer_ip_and_stores_only_hmac_key(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    _seed_listing(context, listing_id="quote-listing")
    other_ip_client = TestClient(
        context.client.app,
        client=("192.0.2.44", 12345),
    )
    try:
        for _ in range(10):
            assert context.client.post(
                "/api/v1/quotes", json=_quote_payload(offer_version=1)
            ).status_code == 201
        isolated = other_ip_client.post(
            "/api/v1/quotes", json=_quote_payload(offer_version=1)
        )
        assert isolated.status_code == 201
        limited = context.client.post(
            "/api/v1/quotes",
            json=_quote_payload(offer_version=1),
            headers={"X-Forwarded-For": "203.0.113.100"},
        )
        _assert_quote_error(limited, status_code=429, code="rate_limit_exceeded")
    finally:
        other_ip_client.close()

    from app.modules.catalog.models import QuoteRateLimitEvent

    with context.session_factory() as session:
        events = session.query(QuoteRateLimitEvent).all()
        assert len(events) == 11
        assert {len(event.client_key) for event in events} == {64}
        assert all("127.0.0.1" not in event.client_key for event in events)
        assert all("192.0.2.44" not in event.client_key for event in events)


def test_quote_validation_envelope_is_quote_specific(
    catalog_api_context: CatalogApiContext,
) -> None:
    context = catalog_api_context
    malformed = context.client.post("/api/v1/quotes", json={})
    string_version = context.client.post(
        "/api/v1/quotes",
        json={"listing_id": "listing", "offer_version": "1", "selected_extra_ids": []},
    )
    unknown_field = context.client.post(
        "/api/v1/quotes",
        json={"listing_id": "listing", "offer_version": 1, "unexpected": True},
    )
    staff_invalid = context.client.post("/api/v1/auth/login", json={})
    customer_invalid = context.client.post("/api/v1/customer/auth/register", json={})

    _assert_quote_error(malformed, status_code=422, code="validation_error")
    _assert_quote_error(string_version, status_code=422, code="validation_error")
    _assert_quote_error(unknown_field, status_code=422, code="validation_error")
    assert staff_invalid.json() == {
        "detail": "Request validation failed",
        "code": "validation_error",
    }
    assert customer_invalid.json() == {
        "detail": "Request validation failed",
        "code": "validation_error",
    }

    from app.modules.catalog.models import QuoteRateLimitEvent

    with context.session_factory() as session:
        assert session.query(QuoteRateLimitEvent).count() == 0


def test_quote_rate_limiter_fails_closed_for_unsupported_dialect() -> None:
    from unittest.mock import Mock

    from app.modules.catalog.errors import UnsupportedRateLimitDialectError
    from app.modules.catalog.service import consume_quote_rate_limit

    session = Mock()
    session.get_bind.return_value.dialect.name = "mysql"

    with pytest.raises(UnsupportedRateLimitDialectError):
        consume_quote_rate_limit(
            session,
            client_ip="192.0.2.15",
            now=datetime(2026, 9, 1, 12, tzinfo=timezone.utc),
            hmac_secret="test-secret",
        )


def test_quote_rate_limit_is_atomic_under_sqlite_concurrency() -> None:
    database_url = "sqlite+pysqlite:///file:quote-rate-limit?mode=memory&cache=shared&uri=true"
    engine = create_engine(
        database_url,
        connect_args={"timeout": 30, "check_same_thread": False},
        poolclass=QueuePool,
        pool_size=12,
        max_overflow=0,
    )
    session_factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    Base.metadata.create_all(engine)
    with session_factory.begin() as session:
        session.add(Agency(id="agency-concurrent"))
        from app.modules.catalog.models import Listing

        session.add(
            Listing(
                id="quote-listing",
                agency_id="agency-concurrent",
                approval_status="approved",
                is_published=True,
                operation="sale",
                base_price=Decimal("100.00"),
                offer_version=1,
                city="Córdoba",
                zone="Centro",
                bedrooms=1,
                bathrooms=1,
            )
        )
    settings = Settings(
        database_url=database_url,
        jwt_secret="catalog-test-secret-that-is-at-least-thirty-two-bytes",
        totp_encryption_key="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        web_origin="http://localhost",
    )
    app = create_app(settings=settings, session_factory=session_factory)
    now = datetime(2026, 9, 1, 12, tzinfo=timezone.utc)
    app.state.clock = lambda: now
    try:
        with TestClient(app) as client:
            with ThreadPoolExecutor(max_workers=12) as executor:
                responses = list(
                    executor.map(
                        lambda _: client.post(
                            "/api/v1/quotes", json=_quote_payload(offer_version=1)
                        ),
                        range(12),
                    )
                )
        assert sum(response.status_code == 201 for response in responses) == 10
        assert sum(response.status_code == 429 for response in responses) == 2
    finally:
        engine.dispose()
