from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import IntegrityError


_MIGRATION_PATH = (
    Path(__file__).resolve().parents[1]
    / "alembic"
    / "versions"
    / "0013_listing_currency.py"
)


def _load_migration():
    spec = importlib.util.spec_from_file_location("listing_currency_0013_test", _MIGRATION_PATH)
    assert spec is not None and spec.loader is not None
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    return migration


def test_currency_migration_relabels_existing_money_and_reverses_sqlite_schema() -> None:
    migration = _load_migration()
    assert migration.revision == "0013_listing_currency"
    assert migration.down_revision == "0012_listing_transitions"

    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.begin() as connection:
            connection.execute(text("PRAGMA foreign_keys=ON"))
            connection.execute(
                text(
                    "CREATE TABLE listing ("
                    "id VARCHAR(36) PRIMARY KEY, operation VARCHAR(8) NOT NULL, "
                    "base_price NUMERIC(18, 2) NOT NULL, offer_version INTEGER NOT NULL, "
                    "deposit_amount_cop NUMERIC(18, 2), "
                    "CONSTRAINT ck_listing_deposit_amount_cop_positive "
                    "CHECK (deposit_amount_cop IS NULL OR deposit_amount_cop > 0), "
                    "CONSTRAINT ck_listing_deposit_amount_cop_scale "
                    "CHECK (deposit_amount_cop IS NULL OR "
                    "deposit_amount_cop = round(deposit_amount_cop, 2)))"
                )
            )
            connection.execute(
                text(
                    "CREATE TABLE listing_offer_version_guard "
                    "(listing_id VARCHAR(36) PRIMARY KEY)"
                )
            )
            connection.execute(
                text(
                    "CREATE TABLE listing_extra (id VARCHAR(36) PRIMARY KEY, "
                    "listing_id VARCHAR(36) REFERENCES listing(id), name TEXT)"
                )
            )
            connection.execute(
                text(
                    "CREATE TABLE listing_transition (id VARCHAR(36) PRIMARY KEY, "
                    "listing_id VARCHAR(36) REFERENCES listing(id))"
                )
            )
            connection.execute(
                text("CREATE TABLE quote_snapshot (id VARCHAR(36) PRIMARY KEY, lines JSON NOT NULL)")
            )
            connection.execute(
                text(
                    "CREATE TABLE reservation ("
                    "id VARCHAR(36) PRIMARY KEY, listing_id VARCHAR(36) REFERENCES listing(id), "
                    "deposit_amount_cop NUMERIC(18, 2), quote_lines JSON NOT NULL, "
                    "CONSTRAINT ck_reservation_deposit_amount_cop_positive "
                    "CHECK (deposit_amount_cop IS NULL OR deposit_amount_cop > 0), "
                    "CONSTRAINT ck_reservation_deposit_amount_cop_scale "
                    "CHECK (deposit_amount_cop IS NULL OR "
                    "deposit_amount_cop = round(deposit_amount_cop, 2)))"
                )
            )
            connection.execute(
                text(
                    "INSERT INTO listing (id, operation, base_price, offer_version, "
                    "deposit_amount_cop) VALUES ('listing-one', 'sale', 10.00, 1, 2.50)"
                )
            )
            legacy_lines = json.dumps(
                [{"kind": "base", "amount": "10.00", "currency": "COP"}]
            )
            connection.execute(
                text("INSERT INTO quote_snapshot (id, lines) VALUES ('quote-one', :lines)"),
                {"lines": legacy_lines},
            )
            connection.execute(
                text(
                    "INSERT INTO reservation (id, listing_id, deposit_amount_cop, quote_lines) "
                    "VALUES ('reservation-one', 'listing-one', 2.50, :lines)"
                ),
                {"lines": legacy_lines},
            )
            connection.execute(
                text("INSERT INTO listing_extra (id, listing_id, name) "
                     "VALUES ('extra-one', 'listing-one', 'Furniture')")
            )
            connection.execute(
                text("INSERT INTO listing_transition (id, listing_id) "
                     "VALUES ('transition-one', 'listing-one')")
            )
            connection.execute(
                text(
                    "CREATE TABLE reservation_chain_transaction ("
                    "id VARCHAR(36) PRIMARY KEY, "
                    "reservation_id VARCHAR(36) REFERENCES reservation(id))"
                )
            )
            connection.execute(
                text(
                    "INSERT INTO reservation_chain_transaction (id, reservation_id) "
                    "VALUES ('txn-one', 'reservation-one')"
                )
            )

            with Operations.context(MigrationContext.configure(connection)):
                migration.upgrade()

            inspector = inspect(connection)
            listing_columns = {column["name"] for column in inspector.get_columns("listing")}
            reservation_columns = {
                column["name"] for column in inspector.get_columns("reservation")
            }
            quote_columns = {
                column["name"] for column in inspector.get_columns("quote_snapshot")
            }
            assert {"currency", "deposit_amount"}.issubset(listing_columns)
            assert "deposit_amount_cop" not in listing_columns
            assert "currency" in quote_columns
            assert "deposit_amount" in reservation_columns
            assert "deposit_amount_cop" not in reservation_columns
            assert connection.scalar(
                text("SELECT currency FROM listing WHERE id = 'listing-one'")
            ) == "BOB"
            assert connection.scalar(
                text("SELECT deposit_amount FROM listing WHERE id = 'listing-one'")
            ) == 2.5
            assert connection.scalar(
                text("SELECT currency FROM quote_snapshot WHERE id = 'quote-one'")
            ) == "BOB"
            assert json.loads(
                connection.scalar(text("SELECT lines FROM quote_snapshot WHERE id = 'quote-one'"))
            )[0]["currency"] == "BOB"
            assert json.loads(
                connection.scalar(
                    text("SELECT quote_lines FROM reservation WHERE id = 'reservation-one'")
                )
            )[0]["currency"] == "BOB"
            assert connection.scalar(
                text("SELECT deposit_amount FROM reservation WHERE id = 'reservation-one'")
            ) == 2.5
            assert connection.scalar(
                text(
                    "SELECT reservation_id FROM reservation_chain_transaction "
                    "WHERE id = 'txn-one'"
                )
            ) == "reservation-one"
            assert connection.scalar(
                text("SELECT listing_id FROM listing_extra WHERE id = 'extra-one'")
            ) == "listing-one"
            assert connection.scalar(
                text("SELECT listing_id FROM listing_transition WHERE id = 'transition-one'")
            ) == "listing-one"
            assert connection.exec_driver_sql("PRAGMA foreign_key_check").all() == []

            listing_checks = {
                check["name"] for check in inspector.get_check_constraints("listing")
            }
            reservation_checks = {
                check["name"] for check in inspector.get_check_constraints("reservation")
            }
            assert "ck_listing_currency_supported" in listing_checks
            assert "ck_listing_deposit_amount_positive" in listing_checks
            assert "ck_listing_deposit_amount_scale" in listing_checks
            assert "ck_reservation_deposit_amount_positive" in reservation_checks
            assert "ck_reservation_deposit_amount_scale" in reservation_checks

            with pytest.raises(IntegrityError):
                with connection.begin_nested():
                    connection.execute(
                        text(
                            "INSERT INTO listing (id, operation, base_price, offer_version, currency) "
                            "VALUES ('unsupported', 'sale', 1.00, 1, 'EUR')"
                        )
                    )

            with Operations.context(MigrationContext.configure(connection)):
                migration.downgrade()

            inspector = inspect(connection)
            listing_columns = {column["name"] for column in inspector.get_columns("listing")}
            reservation_columns = {
                column["name"] for column in inspector.get_columns("reservation")
            }
            quote_columns = {
                column["name"] for column in inspector.get_columns("quote_snapshot")
            }
            assert "currency" not in listing_columns | quote_columns
            assert "deposit_amount_cop" in listing_columns
            assert "deposit_amount_cop" in reservation_columns
            assert "deposit_amount" not in listing_columns | reservation_columns
            assert json.loads(
                connection.scalar(text("SELECT lines FROM quote_snapshot WHERE id = 'quote-one'"))
            )[0]["currency"] == "COP"
            assert json.loads(
                connection.scalar(
                    text("SELECT quote_lines FROM reservation WHERE id = 'reservation-one'")
                )
            )[0]["currency"] == "COP"
            assert connection.scalar(
                text(
                    "SELECT reservation_id FROM reservation_chain_transaction "
                    "WHERE id = 'txn-one'"
                )
            ) == "reservation-one"
            assert connection.scalar(
                text("SELECT listing_id FROM listing_extra WHERE id = 'extra-one'")
            ) == "listing-one"
            assert connection.scalar(
                text("SELECT listing_id FROM listing_transition WHERE id = 'transition-one'")
            ) == "listing-one"
            assert connection.exec_driver_sql("PRAGMA foreign_key_check").all() == []
    finally:
        engine.dispose()
