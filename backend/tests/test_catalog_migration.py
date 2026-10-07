from __future__ import annotations

import importlib.util
from collections.abc import Mapping
from pathlib import Path
from types import ModuleType
from typing import Any, cast

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import Numeric, create_engine, inspect, text
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
            amount_type = cast(Numeric, listing_columns["base_price"]["type"])
            assert amount_type.precision == 18
            assert amount_type.scale == 2
            extra_columns = {
                column["name"]: column for column in inspector.get_columns("listing_extra")
            }
            assert {"id", "listing_id", "name", "price"}.issubset(extra_columns)
            assert cast(Numeric, extra_columns["price"]["type"]).precision == 18
            assert cast(Numeric, extra_columns["price"]["type"]).scale == 2

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
                and cast(Mapping[str, Any], fk)["options"].get("ondelete") == "CASCADE"
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


def test_agency_wallet_and_listing_deposit_migration_upgrades_and_downgrades_sqlite() -> None:
    migration_path = _MIGRATIONS / "0009_agency_wallets_deposit.py"
    assert migration_path.is_file(), "CC-05A must add the 0009 agency wallet/deposit migration"
    offers = _load_migration(
        _MIGRATIONS / "0007_catalog_offers.py", "catalog_offers_0007_for_agency_wallet_test"
    )
    quotes = _load_migration(
        _MIGRATIONS / "0008_quote_snapshots.py", "quote_snapshots_0008_for_agency_wallet_test"
    )
    migration = _load_migration(migration_path, "agency_wallets_0009_for_test")
    assert migration.revision == "0009_agency_wallets_deposit"
    assert migration.down_revision == quotes.revision

    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.begin() as connection:
            connection.execute(text("PRAGMA foreign_keys=ON"))
            connection.execute(text("CREATE TABLE agency (id VARCHAR(36) PRIMARY KEY)"))
            connection.execute(text("INSERT INTO agency (id) VALUES ('agency-one')"))
            context = MigrationContext.configure(connection)
            with Operations.context(context):
                offers.upgrade()
                quotes.upgrade()
            _insert_listing(connection)
            connection.execute(
                text(
                    "INSERT INTO quote_snapshot "
                    "(id, listing_id, offer_version, operation, lines, one_time_total, "
                    "monthly_total, created_at, expires_at) VALUES "
                    "('old-quote', 'listing-one', 1, 'sale', '[]', 1234.50, 0.00, "
                    "'2026-09-01 12:00:00', '2026-09-01 12:15:00')"
                )
            )
            with Operations.context(context):
                migration.upgrade()

            inspector = inspect(connection)
            assert {"agency_wallet", "agency_wallet_challenge"}.issubset(
                set(inspector.get_table_names())
            )
            deposit_column = {
                column["name"]: column for column in inspector.get_columns("listing")
            }["deposit_amount_cop"]
            assert deposit_column["nullable"] is True
            deposit_type = deposit_column["type"]
            assert isinstance(deposit_type, Numeric)
            assert deposit_type.precision == 18
            assert deposit_type.scale == 2
            assert connection.scalar(
                text("SELECT deposit_amount_cop FROM listing WHERE id = 'listing-one'")
            ) is None
            wallet_unique_columns = {
                tuple(constraint["column_names"])
                for constraint in inspector.get_unique_constraints("agency_wallet")
            }
            assert {("agency_id",), ("address",)}.issubset(wallet_unique_columns)

            connection.execute(
                text(
                    "UPDATE listing SET deposit_amount_cop = 5000.00 "
                    "WHERE id = 'listing-one'"
                )
            )
            _assert_integrity_error(
                connection,
                "UPDATE listing SET deposit_amount_cop = 5000.001 "
                "WHERE id = 'listing-one'",
                {},
            )
            assert connection.scalar(
                text("SELECT offer_version FROM listing WHERE id = 'listing-one'")
            ) == 2
            assert connection.scalar(
                text("SELECT offer_version FROM quote_snapshot WHERE id = 'old-quote'")
            ) == 1

            with Operations.context(context):
                migration.downgrade()
            inspector = inspect(connection)
            assert not {"agency_wallet", "agency_wallet_challenge"}.intersection(
                inspector.get_table_names()
            )
            assert "deposit_amount_cop" not in {
                column["name"] for column in inspector.get_columns("listing")
            }
            connection.execute(
                text("UPDATE listing SET base_price = 1500.00 WHERE id = 'listing-one'")
            )
            assert connection.scalar(
                text("SELECT offer_version FROM listing WHERE id = 'listing-one'")
            ) == 3
            assert "quote_snapshot" in inspect(connection).get_table_names()
    finally:
        engine.dispose()


def test_quote_snapshot_migration_upgrades_and_downgrades_sqlite() -> None:
    previous = _load_migration(
        _MIGRATIONS / "0007_catalog_offers.py", "catalog_offers_0007_for_quote_test"
    )
    migration_path = _MIGRATIONS / "0008_quote_snapshots.py"
    assert migration_path.is_file(), "CC-04B must add the 0008 quote snapshot migration"
    migration = _load_migration(migration_path, "quote_snapshots_0008_for_test")
    assert migration.revision == "0008_quote_snapshots"
    assert migration.down_revision == previous.revision

    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.begin() as connection:
            connection.execute(text("PRAGMA foreign_keys=ON"))
            connection.execute(text("CREATE TABLE agency (id VARCHAR(36) PRIMARY KEY)"))
            context = MigrationContext.configure(connection)
            with Operations.context(context):
                previous.upgrade()
                migration.upgrade()

            inspector = inspect(connection)
            assert {"quote_snapshot", "quote_rate_limit_event"}.issubset(
                set(inspector.get_table_names())
            )
            snapshot_columns = {
                column["name"]: column for column in inspector.get_columns("quote_snapshot")
            }
            assert {
                "id",
                "listing_id",
                "offer_version",
                "operation",
                "lines",
                "one_time_total",
                "monthly_total",
                "created_at",
                "expires_at",
            }.issubset(snapshot_columns)
            assert cast(Numeric, snapshot_columns["one_time_total"]["type"]).precision == 18
            assert cast(Numeric, snapshot_columns["one_time_total"]["type"]).scale == 2
            rate_columns = {
                column["name"]: column
                for column in inspector.get_columns("quote_rate_limit_event")
            }
            assert {"id", "client_key", "occurred_at"}.issubset(rate_columns)
            assert {"client_key", "occurred_at"}.issubset(
                set(inspector.get_indexes("quote_rate_limit_event")[0]["column_names"])
            )

            connection.execute(
                text(
                    "INSERT INTO quote_snapshot "
                    "(id, listing_id, offer_version, operation, lines, one_time_total, "
                    "monthly_total, created_at, expires_at) VALUES "
                    "('quote-one', 'listing-one', 1, 'sale', '[]', 10.00, 0.00, "
                    "'2026-09-01 12:00:00', '2026-09-01 12:15:00')"
                )
            )
            with pytest.raises(IntegrityError):
                with connection.begin_nested():
                    connection.execute(
                        text("UPDATE quote_snapshot SET one_time_total = 99.00 WHERE id = 'quote-one'")
                    )
            with pytest.raises(IntegrityError):
                with connection.begin_nested():
                    connection.execute(text("DELETE FROM quote_snapshot WHERE id = 'quote-one'"))

            with Operations.context(context):
                migration.downgrade()
            assert not {"quote_snapshot", "quote_rate_limit_event"}.intersection(
                inspect(connection).get_table_names()
            )
            assert connection.scalar(
                text(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' "
                    "AND name LIKE 'trg_quote_snapshot_%'"
                )
            ) == 0
            assert "listing" in inspect(connection).get_table_names()
    finally:
        engine.dispose()


def test_listing_photo_migration_upgrades_and_downgrades_sqlite() -> None:
    catalog = _load_migration(
        _MIGRATIONS / "0007_catalog_offers.py", "catalog_offers_0007_for_photo_test"
    )
    migration_path = _MIGRATIONS / "0013_listing_photos.py"
    assert migration_path.is_file(), "F04.2 must add the 0013 listing photo migration"
    migration = _load_migration(migration_path, "listing_photos_0013_for_test")
    assert migration.revision == "0013_listing_photos"
    assert migration.down_revision == "0012_listing_transitions"

    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.begin() as connection:
            connection.execute(text("PRAGMA foreign_keys=ON"))
            connection.execute(text("CREATE TABLE agency (id VARCHAR(36) PRIMARY KEY)"))
            connection.execute(text("INSERT INTO agency (id) VALUES ('agency-one')"))
            context = MigrationContext.configure(connection)
            with Operations.context(context):
                catalog.upgrade()
                migration.upgrade()
            _insert_listing(connection)

            inspector = inspect(connection)
            assert {column["name"] for column in inspector.get_columns("listing_photo")} == {
                "id",
                "agency_id",
                "listing_id",
                "object_key",
                "status",
                "content_type",
                "size_bytes",
                "created_at",
                "expires_at",
                "confirmed_at",
            }
            assert {index["name"] for index in inspector.get_indexes("listing_photo")} >= {
                "ix_listing_photo_listing_id_created_at",
            }

            insert = (
                "INSERT INTO listing_photo "
                "(id, agency_id, listing_id, object_key, status, content_type, size_bytes, "
                "created_at, expires_at, confirmed_at) VALUES "
                "(:id, 'agency-one', 'listing-one', :object_key, :status, :content_type, "
                ":size_bytes, '2026-10-04 12:00:00', '2026-10-04 12:15:00', :confirmed_at)"
            )
            valid = {
                "id": "photo-one",
                "object_key": "agencies/agency-one/listings/listing-one/photos/photo-one",
                "status": "pending",
                "content_type": "image/jpeg",
                "size_bytes": 1024,
                "confirmed_at": None,
            }
            connection.execute(text(insert), valid)
            connection.execute(
                text(insert),
                {
                    **valid,
                    "id": "photo-two",
                    "object_key": "agencies/agency-one/listings/listing-one/photos/photo-two",
                    "status": "confirmed",
                    "content_type": "image/webp",
                    "size_bytes": 5 * 1024 * 1024,
                    "confirmed_at": "2026-10-04 12:01:00",
                },
            )

            for invalid in (
                {"status": "uploaded"},
                {"content_type": "image/gif"},
                {"size_bytes": 0},
                {"size_bytes": 5 * 1024 * 1024 + 1},
                {"status": "confirmed", "confirmed_at": None},
                {"status": "pending", "confirmed_at": "2026-10-04 12:01:00"},
                {"object_key": valid["object_key"]},
            ):
                _assert_integrity_error(
                    connection,
                    insert,
                    {
                        **valid,
                        "id": "photo-invalid",
                        "object_key": "agencies/agency-one/listings/listing-one/photos/other",
                        **invalid,
                    },
                )
            _assert_integrity_error(
                connection,
                insert.replace("'listing-one'", "'missing-listing'"),
                {**valid, "id": "photo-orphan", "object_key": "orphan"},
            )

            with Operations.context(context):
                migration.downgrade()
            assert "listing_photo" not in inspect(connection).get_table_names()
            assert "listing" in inspect(connection).get_table_names()
    finally:
        engine.dispose()

