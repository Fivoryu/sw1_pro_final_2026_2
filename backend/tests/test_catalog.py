from __future__ import annotations

import importlib.util
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, insert, text, update
from sqlalchemy.exc import DatabaseError, IntegrityError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.db.session import (
    _authorize_sqlite_offer_version_guard,
    create_session_factory,
    protect_session_factory,
)
from app.main import create_app
from app.modules.identity.models import Agency


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
    with engine.begin() as connection:
        migration_context = MigrationContext.configure(connection)
        with Operations.context(migration_context):
            migration._install_offer_version_triggers()
    app = create_app(
        settings=Settings(
            database_url="sqlite+pysqlite:///:memory:",
            jwt_secret="catalog-test-secret-that-is-at-least-thirty-two-bytes",
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
    assert "/api/v1/quotes" not in paths
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
    assert catalog_invalid.json() == {"detail": "Request validation failed"}
    assert staff_invalid.json() == {"detail": "Request validation failed"}
    assert customer_invalid.status_code == 422
    assert customer_invalid.json() == {"error": {"code": "validation_error"}}
