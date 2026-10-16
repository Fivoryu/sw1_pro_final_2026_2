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


def test_listing_extra_details_migration_upgrades_and_downgrades_sqlite() -> None:
    offers = _load_migration(
        _MIGRATIONS / "0007_catalog_offers.py", "catalog_offers_0007_for_extra_details"
    )
    migration_path = _MIGRATIONS / "0016_listing_extra_details.py"
    assert migration_path.is_file(), "F05.1 must add the 0016 extra details migration"
    migration = _load_migration(migration_path, "listing_extra_details_0016_for_test")
    assert migration.revision == "0016_listing_extra_details"
    assert migration.down_revision == "0015_quote_display_currency"

    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.begin() as connection:
            connection.execute(text("PRAGMA foreign_keys=ON"))
            connection.execute(text("CREATE TABLE agency (id VARCHAR(36) PRIMARY KEY)"))
            context = MigrationContext.configure(connection)
            with Operations.context(context):
                offers.upgrade()
                migration.upgrade()

            extra_columns = {
                column["name"]: column for column in inspect(connection).get_columns("listing_extra")
            }
            assert {
                "category",
                "room",
                "width_cm",
                "height_cm",
                "depth_cm",
                "origin",
                "visual_reference",
                "quantity",
            }.issubset(extra_columns)

            connection.execute(text("INSERT INTO agency (id) VALUES ('agency-one')"))
            _insert_listing(connection)
            connection.execute(
                text(
                    "INSERT INTO listing_extra (id, listing_id, name, price) "
                    "VALUES ('extra-one', 'listing-one', 'Cama', '10.00')"
                )
            )
            assert connection.scalar(
                text("SELECT quantity FROM listing_extra WHERE id = 'extra-one'")
            ) == 1
            for statement in (
                "UPDATE listing_extra SET quantity = 0 WHERE id = 'extra-one'",
                "UPDATE listing_extra SET width_cm = 0 WHERE id = 'extra-one'",
                "UPDATE listing_extra SET height_cm = -5 WHERE id = 'extra-one'",
                "UPDATE listing_extra SET category = '   ' WHERE id = 'extra-one'",
                "UPDATE listing_extra SET visual_reference = ' ' WHERE id = 'extra-one'",
            ):
                _assert_integrity_error(connection, statement, {})

            # Quantity is an offer field: changing it advances the offer version.
            # The insert itself already advanced it once (1 -> 2 -> 3).
            connection.execute(
                text("UPDATE listing_extra SET quantity = 3 WHERE id = 'extra-one'")
            )
            assert connection.scalar(
                text("SELECT offer_version FROM listing WHERE id = 'listing-one'")
            ) == 3
            connection.execute(
                text("UPDATE listing_extra SET category = 'bed' WHERE id = 'extra-one'")
            )
            assert connection.scalar(
                text("SELECT offer_version FROM listing WHERE id = 'listing-one'")
            ) == 3

            with Operations.context(MigrationContext.configure(connection)):
                migration.downgrade()
            downgraded = {
                column["name"] for column in inspect(connection).get_columns("listing_extra")
            }
            assert not downgraded & {
                "category",
                "room",
                "width_cm",
                "height_cm",
                "depth_cm",
                "origin",
                "visual_reference",
                "quantity",
            }
            connection.execute(
                text(
                    "UPDATE listing_extra SET price = '12.00' WHERE id = 'extra-one'"
                )
            )
            assert connection.scalar(
                text("SELECT offer_version FROM listing WHERE id = 'listing-one'")
            ) == 4
    finally:
        engine.dispose()


def test_listing_photo_migration_upgrades_and_downgrades_sqlite() -> None:
    catalog = _load_migration(
        _MIGRATIONS / "0007_catalog_offers.py", "catalog_offers_0007_for_photo_test"
    )
    migration_path = _MIGRATIONS / "0018_listing_photos.py"
    assert migration_path.is_file(), "F04.2 must add the 0018 listing photo migration"
    migration = _load_migration(migration_path, "listing_photos_0018_for_test")
    assert migration.revision == "0018_listing_photos"
    assert migration.down_revision == "0017_exchange_rate_source"

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


def test_listing_photo_policy_migration_preserves_legacy_rows_and_guards_downgrade() -> None:
    catalog = _load_migration(
        _MIGRATIONS / "0007_catalog_offers.py", "catalog_offers_0007_for_photo_policy_test"
    )
    photos_0018 = _load_migration(
        _MIGRATIONS / "0018_listing_photos.py", "listing_photos_0018_for_policy_test"
    )
    migration_path = _MIGRATIONS / "0019_listing_photo_assets.py"
    assert migration_path.is_file(), "F04.2 policy must add the 0019 photo assets migration"
    migration = _load_migration(migration_path, "listing_photo_assets_0019_for_test")
    assert migration.revision == "0019_listing_photo_assets"
    assert migration.down_revision == "0018_listing_photos"

    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.begin() as connection:
            connection.execute(text("PRAGMA foreign_keys=ON"))
            connection.execute(text("CREATE TABLE agency (id VARCHAR(36) PRIMARY KEY)"))
            connection.execute(text("INSERT INTO agency (id) VALUES ('agency-one')"))
            context = MigrationContext.configure(connection)
            with Operations.context(context):
                catalog.upgrade()
                photos_0018.upgrade()
            _insert_listing(connection)

            insert = (
                "INSERT INTO listing_photo "
                "(id, agency_id, listing_id, object_key, status, content_type, size_bytes, "
                "created_at, expires_at, confirmed_at) VALUES "
                "(:id, 'agency-one', 'listing-one', :object_key, :status, :content_type, "
                ":size_bytes, '2026-10-04 12:00:00', '2026-10-04 12:15:00', :confirmed_at)"
            )
            legacy_pending = {
                "id": "legacy-pending",
                "object_key": "agencies/agency-one/listings/listing-one/photos/legacy-pending",
                "status": "pending",
                "content_type": "image/jpeg",
                "size_bytes": 1024,
                "confirmed_at": None,
            }
            legacy_confirmed = {
                **legacy_pending,
                "id": "legacy-confirmed",
                "object_key": "agencies/agency-one/listings/listing-one/photos/legacy-confirmed",
                "status": "confirmed",
                "content_type": "image/webp",
                "size_bytes": 8192,
                "confirmed_at": "2026-10-04 12:01:00",
            }
            connection.execute(text(insert), legacy_pending)
            connection.execute(text(insert), legacy_confirmed)

            with Operations.context(context):
                migration.upgrade()

            inspector = inspect(connection)
            columns = {column["name"] for column in inspector.get_columns("listing_photo")}
            assert {
                "upload_object_key",
                "original_object_key",
                "public_content_type",
            } <= columns
            photo_indexes = {index["name"] for index in inspector.get_indexes("listing_photo")}
            assert "ix_listing_photo_status_expires_at" in photo_indexes
            legacy_rows = {
                row["id"]: row
                for row in connection.execute(
                    text(
                        "SELECT id, object_key, status, content_type, size_bytes, confirmed_at, "
                        "upload_object_key, original_object_key, public_content_type "
                        "FROM listing_photo"
                    )
                ).mappings()
            }
            for expected in (legacy_pending, legacy_confirmed):
                actual = legacy_rows[expected["id"]]
                assert actual["object_key"] == expected["object_key"]
                assert actual["status"] == expected["status"]
                assert actual["content_type"] == expected["content_type"]
                assert actual["size_bytes"] == expected["size_bytes"]
                assert actual["upload_object_key"] is None
                assert actual["original_object_key"] is None
                assert actual["public_content_type"] is None

            for photo_id, content_type in (
                ("new-heic", "image/heic"),
                ("new-heif", "image/heif"),
            ):
                connection.execute(
                    text(insert),
                    {
                        **legacy_pending,
                        "id": photo_id,
                        "object_key": f"agencies/agency-one/listings/listing-one/photos/{photo_id}",
                        "content_type": content_type,
                        "size_bytes": 20 * 1024 * 1024,
                    },
                )
            modern = {
                **legacy_pending,
                "id": "new-photo-with-staging-key",
                "object_key": "agencies/agency-one/listings/listing-one/photos/new-photo/public",
            }
            connection.execute(text(insert), modern)
            connection.execute(
                text(
                    "UPDATE listing_photo SET upload_object_key = :upload_key "
                    "WHERE id = 'new-photo-with-staging-key'"
                ),
                {"upload_key": "agencies/agency-one/listings/listing-one/photos/new-photo/upload"},
            )

            _assert_integrity_error(
                connection,
                insert,
                {
                    **legacy_pending,
                    "id": "unsupported-photo-type",
                    "object_key": "unsupported-photo-type",
                    "content_type": "image/gif",
                },
            )
            _assert_integrity_error(
                connection,
                insert,
                {
                    **legacy_pending,
                    "id": "photo-over-20-mib",
                    "object_key": "photo-over-20-mib",
                    "content_type": "image/heic",
                    "size_bytes": 20 * 1024 * 1024 + 1,
                },
            )

            with pytest.raises(RuntimeError, match="new photo assets"):
                with Operations.context(context):
                    migration.downgrade()
            assert "original_object_key" in {
                column["name"] for column in inspect(connection).get_columns("listing_photo")
            }
            assert "ix_listing_photo_status_expires_at" in {
                index["name"] for index in inspect(connection).get_indexes("listing_photo")
            }
            assert connection.scalar(
                text("SELECT count(*) FROM listing_photo WHERE id LIKE 'new-%'")
            ) == 3

            connection.execute(text("DELETE FROM listing_photo WHERE id LIKE 'new-%'"))
            with Operations.context(context):
                migration.downgrade()
            assert "original_object_key" not in {
                column["name"] for column in inspect(connection).get_columns("listing_photo")
            }
            assert "ix_listing_photo_status_expires_at" not in {
                index["name"] for index in inspect(connection).get_indexes("listing_photo")
            }
            with Operations.context(context):
                photos_0018.downgrade()
                catalog.downgrade()
            assert "listing_photo" not in inspect(connection).get_table_names()
    finally:
        engine.dispose()


def test_listing_photo_deletion_migration_preserves_legacy_rows_and_guards_downgrade() -> None:
    catalog = _load_migration(
        _MIGRATIONS / "0007_catalog_offers.py",
        "catalog_offers_0007_for_photo_deletion_test",
    )
    photos_0018 = _load_migration(
        _MIGRATIONS / "0018_listing_photos.py",
        "listing_photos_0018_for_photo_deletion_test",
    )
    assets_0019 = _load_migration(
        _MIGRATIONS / "0019_listing_photo_assets.py",
        "listing_photo_assets_0019_for_deletion_test",
    )
    migration_path = _MIGRATIONS / "0020_listing_photo_deletion.py"
    assert migration_path.is_file(), "F04.2 durable deletion must add the 0020 migration"
    migration = _load_migration(migration_path, "listing_photo_deletion_0020_for_test")
    assert migration.revision == "0020_listing_photo_deletion"
    assert migration.down_revision == assets_0019.revision

    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.begin() as connection:
            connection.execute(text("PRAGMA foreign_keys=ON"))
            connection.execute(text("CREATE TABLE agency (id VARCHAR(36) PRIMARY KEY)"))
            connection.execute(text("INSERT INTO agency (id) VALUES ('agency-one')"))
            context = MigrationContext.configure(connection)
            with Operations.context(context):
                catalog.upgrade()
                photos_0018.upgrade()
            _insert_listing(connection)

            insert_photo = text(
                "INSERT INTO listing_photo "
                "(id, agency_id, listing_id, object_key, status, content_type, size_bytes, "
                "created_at, expires_at, confirmed_at) VALUES "
                "(:id, 'agency-one', 'listing-one', :object_key, :status, :content_type, "
                ":size_bytes, '2026-10-04 12:00:00', '2026-10-04 12:15:00', :confirmed_at)"
            )
            legacy_pending = {
                "id": "legacy-pending",
                "object_key": "agencies/agency-one/listings/listing-one/photos/legacy-pending",
                "status": "pending",
                "content_type": "image/jpeg",
                "size_bytes": 1024,
                "confirmed_at": None,
            }
            legacy_confirmed = {
                **legacy_pending,
                "id": "legacy-confirmed",
                "object_key": "agencies/agency-one/listings/listing-one/photos/legacy-confirmed",
                "status": "confirmed",
                "content_type": "image/webp",
                "size_bytes": 8192,
                "confirmed_at": "2026-10-04 12:01:00",
            }
            connection.execute(insert_photo, legacy_pending)
            connection.execute(insert_photo, legacy_confirmed)
            with Operations.context(context):
                assets_0019.upgrade()

            select_legacy = text(
                "SELECT id, object_key, status, content_type, size_bytes, confirmed_at, "
                "upload_object_key, original_object_key, public_content_type "
                "FROM listing_photo ORDER BY id"
            )
            legacy_before = [dict(row) for row in connection.execute(select_legacy).mappings()]
            with Operations.context(context):
                migration.upgrade()

            inspector = inspect(connection)
            assert "listing_photo_deletion" in inspector.get_table_names()
            deletion_columns = {
                column["name"]
                for column in inspector.get_columns("listing_photo_deletion")
            }
            assert {
                "id",
                "agency_id",
                "listing_id",
                "photo_id",
                "actor_id",
                "object_key",
                "original_object_key",
                "upload_object_key",
                "requested_at",
                "upload_expires_at",
                "attempts",
                "next_attempt_at",
                "last_error",
            } <= deletion_columns
            assert "ix_listing_photo_deletion_due" in {
                index["name"] for index in inspector.get_indexes("listing_photo_deletion")
            }
            assert "uq_listing_photo_deletion_photo_id" in {
                constraint["name"]
                for constraint in inspector.get_unique_constraints("listing_photo_deletion")
            }
            assert [dict(row) for row in connection.execute(select_legacy).mappings()] == legacy_before

            connection.execute(
                text(
                    "INSERT INTO listing_photo_deletion "
                    "(id, agency_id, listing_id, photo_id, actor_id, object_key, "
                    "original_object_key, upload_object_key, requested_at, attempts, "
                    "next_attempt_at, last_error) VALUES "
                    "(:id, :agency_id, :listing_id, :photo_id, :actor_id, :object_key, "
                    ":original_object_key, :upload_object_key, :requested_at, :attempts, "
                    ":next_attempt_at, :last_error)"
                ),
                {
                    "id": "delete-job-one",
                    "agency_id": "agency-one",
                    "listing_id": "listing-one",
                    "photo_id": "legacy-confirmed",
                    "actor_id": "staff-one",
                    "object_key": legacy_confirmed["object_key"],
                    "original_object_key": None,
                    "upload_object_key": None,
                    "requested_at": "2026-10-04 12:02:00",
                    "attempts": 1,
                    "next_attempt_at": "2026-10-04 12:03:00",
                    "last_error": "storage_unavailable",
                },
            )
            with pytest.raises(RuntimeError, match="pending photo deletion intents"):
                with Operations.context(context):
                    migration.downgrade()
            assert "listing_photo_deletion" in inspect(connection).get_table_names()
            assert connection.scalar(
                text("SELECT count(*) FROM listing_photo_deletion")
            ) == 1
            assert [dict(row) for row in connection.execute(select_legacy).mappings()] == legacy_before

            connection.execute(
                text("DELETE FROM listing_photo_deletion WHERE id = 'delete-job-one'")
            )
            with Operations.context(context):
                migration.downgrade()
            assert "listing_photo_deletion" not in inspect(connection).get_table_names()
            assert [dict(row) for row in connection.execute(select_legacy).mappings()] == legacy_before
    finally:
        engine.dispose()
