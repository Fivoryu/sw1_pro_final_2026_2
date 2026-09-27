from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import Connection
from sqlalchemy.exc import IntegrityError


_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_MIGRATIONS = _BACKEND_ROOT / "alembic" / "versions"


def _load_migration(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _assert_integrity_error(connection: Connection, statement: str, values: dict[str, object]) -> None:
    with connection.begin_nested():
        with pytest.raises(IntegrityError):
            connection.execute(text(statement), values)


def _insert_listing(
    connection: Connection,
    *,
    listing_id: str = "listing-one",
    agency_id: str = "agency-one",
    approval_status: str = "approved",
    is_published: bool = True,
    operation: str = "sale",
    base_price: str = "1234.50",
    offer_version: int = 1,
    bedrooms: int = 2,
    bathrooms: int = 1,
) -> None:
    connection.execute(
        text(
            "INSERT INTO listing "
            "(id, agency_id, approval_status, is_published, operation, base_price, "
            "offer_version, city, city_key, zone, zone_key, bedrooms, bathrooms, created_at) "
            "VALUES (:id, :agency_id, :approval_status, :is_published, :operation, :base_price, "
            ":offer_version, 'Córdoba', 'córdoba', 'Centro', 'centro', :bedrooms, :bathrooms, "
            "'2026-09-01 12:00:00')"
        ),
        {
            "id": listing_id,
            "agency_id": agency_id,
            "approval_status": approval_status,
            "is_published": is_published,
            "operation": operation,
            "base_price": base_price,
            "offer_version": offer_version,
            "bedrooms": bedrooms,
            "bathrooms": bathrooms,
        },
    )


def test_catalog_migration_creates_constrained_listing_and_offer_tables() -> None:
    migration_path = _MIGRATIONS / "0007_catalog_offers.py"
    assert migration_path.is_file(), "CC-04A must add the 0007 catalog migration"
    previous = _load_migration(
        _MIGRATIONS / "0006_customer_wallet.py", "customer_wallet_0006_for_catalog_test"
    )
    migration = _load_migration(migration_path, "catalog_offers_0007_for_test")
    assert previous.revision == "0006_customer_wallet"
    assert migration.revision == "0007_catalog_offers"
    assert migration.down_revision == previous.revision

    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.begin() as connection:
            connection.execute(text("PRAGMA foreign_keys=ON"))
            connection.execute(text("CREATE TABLE agency (id VARCHAR(36) PRIMARY KEY)"))
            context = MigrationContext.configure(connection)
            with Operations.context(context):
                migration.upgrade()

            inspector = inspect(connection)
            assert {"listing", "listing_extra"}.issubset(set(inspector.get_table_names()))
            assert connection.scalar(text("SELECT COUNT(*) FROM listing")) == 0
            assert connection.scalar(text("SELECT COUNT(*) FROM listing_extra")) == 0

            listing_columns = {
                column["name"]: column for column in inspector.get_columns("listing")
            }
            assert {
                "id",
                "agency_id",
                "approval_status",
                "is_published",
                "operation",
                "base_price",
                "offer_version",
                "city",
                "city_key",
                "zone",
                "zone_key",
                "bedrooms",
                "bathrooms",
                "created_at",
            }.issubset(listing_columns)
            amount_type = listing_columns["base_price"]["type"]
            assert amount_type.precision == 18
            assert amount_type.scale == 2
            extra_columns = {
                column["name"]: column for column in inspector.get_columns("listing_extra")
            }
            assert {"id", "listing_id", "name", "price"}.issubset(extra_columns)
            assert extra_columns["price"]["type"].precision == 18
            assert extra_columns["price"]["type"].scale == 2

            listing_foreign_keys = inspector.get_foreign_keys("listing")
            assert any(
                fk["constrained_columns"] == ["agency_id"]
                and fk["referred_table"] == "agency"
                and fk["referred_columns"] == ["id"]
                for fk in listing_foreign_keys
            )
            extra_foreign_keys = inspector.get_foreign_keys("listing_extra")
            assert any(
                fk["constrained_columns"] == ["listing_id"]
                and fk["referred_table"] == "listing"
                and fk["referred_columns"] == ["id"]
                and fk["options"].get("ondelete") == "CASCADE"
                for fk in extra_foreign_keys
            )

            connection.execute(text("INSERT INTO agency (id) VALUES ('agency-one')"))
            _insert_listing(connection)
            connection.execute(
                text(
                    "INSERT INTO listing_extra (id, listing_id, name, price) "
                    "VALUES ('extra-one', 'listing-one', 'Furnished', '0.10')"
                )
            )
            connection.execute(
                text("UPDATE listing SET base_price = base_price WHERE id = 'listing-one'")
            )
            connection.execute(
                text("UPDATE listing_extra SET price = price WHERE id = 'extra-one'")
            )
            assert connection.scalar(
                text("SELECT offer_version FROM listing WHERE id = 'listing-one'")
            ) == 2
            _assert_integrity_error(
                connection,
                "INSERT OR REPLACE INTO listing_extra (id, listing_id, name, price) "
                "VALUES ('extra-one', 'listing-two', 'Replacement', 99.00)",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT INTO listing_extra (id, listing_id, name, price) "
                "VALUES ('extra-one', 'listing-two', 'Replacement', 99.00) "
                "ON CONFLICT(id) DO UPDATE SET listing_id = excluded.listing_id, "
                "price = excluded.price",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT OR REPLACE INTO listing "
                "(id, agency_id, operation, base_price, offer_version, city, city_key, zone, "
                "zone_key, bedrooms, bathrooms, created_at) "
                "VALUES ('listing-one', 'agency-one', 'rent', 999, 1, 'City', 'city', "
                "'Zone', 'zone', 1, 1, '2026-09-01 12:00:00')",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT INTO listing (id, agency_id, approval_status, is_published, operation, "
                "base_price, offer_version, city, city_key, zone, zone_key, bedrooms, bathrooms, "
                "created_at) VALUES ('forged-version', 'agency-one', 'approved', 1, 'sale', 10, 99, "
                "'City', 'city', 'Zone', 'zone', 1, 1, '2026-09-01 12:00:00')",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT INTO listing (id, agency_id, approval_status, is_published, operation, "
                "base_price, offer_version, city, city_key, zone, zone_key, bedrooms, bathrooms, "
                "created_at) VALUES ('orphan', 'missing-agency', 'approved', 1, 'sale', 10, 1, "
                "'City', 'city', 'Zone', 'zone', 1, 1, '2026-09-01 12:00:00')",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT INTO listing_extra (id, listing_id, name, price) "
                "VALUES ('orphan-extra', 'missing-listing', 'Extra', 1)",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT INTO listing (id, agency_id, approval_status, is_published, operation, "
                "base_price, offer_version, city, city_key, zone, zone_key, bedrooms, bathrooms, "
                "created_at) VALUES ('bad-operation', 'agency-one', 'approved', 1, 'lease', 10, 1, "
                "'City', 'city', 'Zone', 'zone', 1, 1, '2026-09-01 12:00:00')",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT INTO listing (id, agency_id, approval_status, is_published, operation, "
                "base_price, offer_version, city, city_key, zone, zone_key, bedrooms, bathrooms, "
                "created_at) VALUES ('bad-count', 'agency-one', 'approved', 1, 'sale', 10, 1, "
                "'City', 'city', 'Zone', 'zone', -1, 1, '2026-09-01 12:00:00')",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT INTO listing (id, agency_id, approval_status, is_published, operation, "
                "base_price, offer_version, city, city_key, zone, zone_key, bedrooms, bathrooms, "
                "created_at) VALUES ('bad-bathrooms', 'agency-one', 'approved', 1, 'sale', 10, 1, "
                "'City', 'city', 'Zone', 'zone', 1, -1, '2026-09-01 12:00:00')",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT INTO listing (id, agency_id, approval_status, is_published, operation, "
                "base_price, offer_version, city, city_key, zone, zone_key, bedrooms, bathrooms, "
                "created_at) VALUES ('bad-approval', 'agency-one', 'awaiting', 1, 'sale', 10, 1, "
                "'City', 'city', 'Zone', 'zone', 1, 1, '2026-09-01 12:00:00')",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT INTO listing (id, agency_id, approval_status, is_published, operation, "
                "base_price, offer_version, city, city_key, zone, zone_key, bedrooms, bathrooms, "
                "created_at) VALUES ('bad-version', 'agency-one', 'approved', 1, 'sale', 10, 0, "
                "'City', 'city', 'Zone', 'zone', 1, 1, '2026-09-01 12:00:00')",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT INTO listing (id, agency_id, approval_status, is_published, operation, "
                "base_price, offer_version, city, city_key, zone, zone_key, bedrooms, bathrooms, "
                "created_at) VALUES ('bad-price', 'agency-one', 'approved', 1, 'sale', -0.01, 1, "
                "'City', 'city', 'Zone', 'zone', 1, 1, '2026-09-01 12:00:00')",
                {},
            )
            _assert_integrity_error(
                connection,
                "INSERT INTO listing_extra (id, listing_id, name, price) "
                "VALUES ('bad-extra-price', 'listing-one', 'Extra', -0.01)",
                {},
            )

            _insert_listing(connection, listing_id="listing-two")
            connection.execute(
                text("UPDATE listing SET base_price = 1500.00 WHERE id = 'listing-one'")
            )
            connection.execute(
                text("UPDATE listing SET operation = 'rent' WHERE id = 'listing-one'")
            )
            connection.execute(
                text(
                    "INSERT INTO listing_extra (id, listing_id, name, price) "
                    "VALUES ('extra-two', 'listing-one', 'Storage', 50.00)"
                )
            )
            connection.execute(
                text("UPDATE listing_extra SET name = 'Upgraded', price = 25.00 "
                     "WHERE id = 'extra-one'")
            )
            connection.execute(
                text("UPDATE listing_extra SET id = 'extra-renamed' WHERE id = 'extra-one'")
            )
            connection.execute(
                text("UPDATE listing_extra SET listing_id = 'listing-two' "
                     "WHERE id = 'extra-renamed'")
            )
            assert connection.scalar(
                text("SELECT offer_version FROM listing WHERE id = 'listing-one'")
            ) == 8
            assert connection.scalar(
                text("SELECT offer_version FROM listing WHERE id = 'listing-two'")
            ) == 2

            connection.execute(
                text("UPDATE listing_extra SET price = 30.00 WHERE id = 'extra-renamed'")
            )
            connection.execute(text("DELETE FROM listing_extra WHERE id = 'extra-renamed'"))
            assert connection.scalar(
                text("SELECT offer_version FROM listing WHERE id = 'listing-one'")
            ) == 8
            assert connection.scalar(
                text("SELECT offer_version FROM listing WHERE id = 'listing-two'")
            ) == 4

            _assert_integrity_error(
                connection,
                "UPDATE listing SET offer_version = 1 WHERE id = 'listing-one'",
                {},
            )
            _assert_integrity_error(
                connection,
                "UPDATE listing SET id = 'listing-renamed' WHERE id = 'listing-one'",
                {},
            )
            connection.execute(
                text("UPDATE listing SET base_price = 1600.00, offer_version = 99 "
                     "WHERE id = 'listing-one'")
            )
            assert connection.scalar(
                text("SELECT offer_version FROM listing WHERE id = 'listing-one'")
            ) == 9

            connection.execute(text("DELETE FROM listing WHERE id = 'listing-one'"))
            assert connection.scalar(
                text("SELECT COUNT(*) FROM listing_extra WHERE id = 'extra-two'")
            ) == 0

            with Operations.context(context):
                migration.downgrade()
            assert not {
                "listing",
                "listing_extra",
                "listing_offer_version_guard",
            }.intersection(inspect(connection).get_table_names())
            assert connection.scalar(
                text(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' "
                    "AND name LIKE 'trg_listing_%'"
                )
            ) == 0
    finally:
        engine.dispose()
