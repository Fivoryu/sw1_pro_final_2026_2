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
_MIGRATION_PATH = _BACKEND_ROOT / "alembic" / "versions" / "0010_reservations.py"


def _load_migration(connection: Connection) -> ModuleType:
    assert _MIGRATION_PATH.is_file(), "CC-05B must add migration 0010_reservations"
    spec = importlib.util.spec_from_file_location("reservations_0010_test", _MIGRATION_PATH)
    assert spec is not None and spec.loader is not None
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    setattr(migration, "op", Operations(MigrationContext.configure(connection)))
    return migration


def _insert_reservation(
    connection: Connection,
    *,
    reservation_id: str,
    listing_id: str = "listing-one",
    quote_id: str = "quote-one",
    customer_id: str = "customer-one",
    customer_wallet_id: str = "customer-wallet-one",
    agency_wallet_id: str = "agency-wallet-one",
    status: str = "pending",
    key: str | None = None,
    deposit: str | None = None,
    api_created_at: str = "2026-09-01 12:00:00",
    deadline: str = "2026-09-02 12:00:00",
) -> None:
    connection.execute(
        text(
            "INSERT INTO reservation ("
            "id, listing_id, quote_id, customer_id, customer_wallet_id, agency_wallet_id, "
            "customer_wallet_address, agency_wallet_address, offer_version, operation, "
            "quote_lines, one_time_total, monthly_total, deposit_amount_cop, api_created_at, "
            "decision_deadline_at, status, deposit_confirmed_at, idempotency_key, "
            "request_fingerprint"
            ") VALUES ("
            ":id, :listing_id, :quote_id, :customer_id, :customer_wallet_id, :agency_wallet_id, "
            "'0x1111111111111111111111111111111111111111', "
            "'0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 1, 'sale', '[]', 100.00, 0.00, "
            ":deposit, :api_created_at, :deadline, :status, NULL, :idempotency_key, :fingerprint"
            ")"
        ),
        {
            "id": reservation_id,
            "listing_id": listing_id,
            "quote_id": quote_id,
            "customer_id": customer_id,
            "customer_wallet_id": customer_wallet_id,
            "agency_wallet_id": agency_wallet_id,
            "deposit": deposit,
            "api_created_at": api_created_at,
            "deadline": deadline,
            "status": status,
            "idempotency_key": key or reservation_id,
            "fingerprint": "a" * 64,
        },
    )


def test_reservation_migration_enforces_active_partial_index_checks_and_downgrades() -> None:
    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.begin() as connection:
            connection.execute(text("PRAGMA foreign_keys=ON"))
            connection.execute(text("CREATE TABLE agency (id VARCHAR(36) PRIMARY KEY)"))
            connection.execute(
                text("CREATE TABLE listing (id VARCHAR(36) PRIMARY KEY, agency_id VARCHAR(36))")
            )
            connection.execute(
                text("CREATE TABLE customer_account (id VARCHAR(36) PRIMARY KEY)")
            )
            connection.execute(
                text(
                    "CREATE TABLE customer_wallet ("
                    "id VARCHAR(36) PRIMARY KEY, customer_id VARCHAR(36), address VARCHAR(42))"
                )
            )
            connection.execute(
                text(
                    "CREATE TABLE agency_wallet ("
                    "id VARCHAR(36) PRIMARY KEY, agency_id VARCHAR(36), address VARCHAR(42))"
                )
            )
            connection.execute(
                text(
                    "CREATE TABLE quote_snapshot ("
                    "id VARCHAR(36) PRIMARY KEY, listing_id VARCHAR(36))"
                )
            )
            migration = _load_migration(connection)
            assert migration.revision == "0010_reservations"
            assert migration.down_revision == "0009_agency_wallets_listing_deposit"
            migration.upgrade()

            inspector = inspect(connection)
            assert "reservation" in inspector.get_table_names()
            columns = {column["name"]: column for column in inspector.get_columns("reservation")}
            assert {
                "id",
                "listing_id",
                "quote_id",
                "customer_id",
                "customer_wallet_id",
                "agency_wallet_id",
                "customer_wallet_address",
                "agency_wallet_address",
                "offer_version",
                "operation",
                "quote_lines",
                "one_time_total",
                "monthly_total",
                "deposit_amount_cop",
                "api_created_at",
                "decision_deadline_at",
                "status",
                "deposit_confirmed_at",
                "idempotency_key",
                "request_fingerprint",
            }.issubset(columns)
            indexes = {index["name"]: index for index in inspector.get_indexes("reservation")}
            active_index = indexes["uq_reservation_active_listing"]
            assert bool(active_index["unique"])
            assert active_index["column_names"] == ["listing_id"]
            active_predicate = str(
                (active_index.get("dialect_options") or {}).get("sqlite_where", "")
            )
            assert "pending" in active_predicate
            assert "accepted" in active_predicate
            unique_constraints = {
                constraint["name"]: constraint
                for constraint in inspector.get_unique_constraints("reservation")
            }
            idempotency_constraint = unique_constraints[
                "uq_reservation_customer_idempotency_key"
            ]
            assert idempotency_constraint["column_names"] == [
                "customer_id",
                "idempotency_key",
            ]

            checks = {check["name"] for check in inspector.get_check_constraints("reservation")}
            assert {
                "ck_reservation_status",
                "ck_reservation_offer_version_positive",
                "ck_reservation_deadline_after_creation",
                "ck_reservation_deposit_amount_cop_positive",
                "ck_reservation_deposit_amount_cop_scale",
            }.issubset(checks)

            for statement, values in (
                ("INSERT INTO agency (id) VALUES ('agency-one')", {}),
                ("INSERT INTO listing (id, agency_id) VALUES ('listing-one', 'agency-one')", {}),
                ("INSERT INTO listing (id, agency_id) VALUES ('listing-two', 'agency-one')", {}),
                ("INSERT INTO customer_account (id) VALUES ('customer-one')", {}),
                (
                    "INSERT INTO customer_wallet (id, customer_id, address) "
                    "VALUES ('customer-wallet-one', 'customer-one', '0x1111111111111111111111111111111111111111')",
                    {},
                ),
                (
                    "INSERT INTO agency_wallet (id, agency_id, address) "
                    "VALUES ('agency-wallet-one', 'agency-one', '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')",
                    {},
                ),
                (
                    "INSERT INTO quote_snapshot (id, listing_id) VALUES ('quote-one', 'listing-one')",
                    {},
                ),
                (
                    "INSERT INTO quote_snapshot (id, listing_id) VALUES ('quote-two', 'listing-two')",
                    {},
                ),
            ):
                connection.execute(text(statement), values)

            _insert_reservation(connection, reservation_id="active-one")
            with pytest.raises(IntegrityError):
                with connection.begin_nested():
                    _insert_reservation(
                        connection,
                        reservation_id="active-two",
                        status="accepted",
                        key="active-two-key",
                    )
            connection.execute(
                text("UPDATE reservation SET status = 'expired' WHERE id = 'active-one'")
            )
            _insert_reservation(
                connection,
                reservation_id="active-two",
                status="pending",
                key="active-two-key",
            )
            _insert_reservation(
                connection,
                reservation_id="no-deposit",
                listing_id="listing-two",
                quote_id="quote-two",
                customer_id="customer-one",
                customer_wallet_id="customer-wallet-one",
                agency_wallet_id="agency-wallet-one",
                deposit=None,
                key="no-deposit-key",
            )

            with pytest.raises(IntegrityError):
                with connection.begin_nested():
                    _insert_reservation(
                        connection,
                        reservation_id="duplicate-key",
                        listing_id="listing-two",
                        quote_id="quote-two",
                        customer_id="customer-one",
                        customer_wallet_id="customer-wallet-one",
                        agency_wallet_id="agency-wallet-one",
                        key="active-two-key",
                    )
            with pytest.raises(IntegrityError):
                with connection.begin_nested():
                    _insert_reservation(
                        connection,
                        reservation_id="bad-status",
                        listing_id="listing-two",
                        quote_id="quote-two",
                        customer_id="customer-one",
                        customer_wallet_id="customer-wallet-one",
                        agency_wallet_id="agency-wallet-one",
                        key="bad-status-key",
                        status="processing",
                    )
            with pytest.raises(IntegrityError):
                with connection.begin_nested():
                    _insert_reservation(
                        connection,
                        reservation_id="bad-deadline",
                        listing_id="listing-two",
                        quote_id="quote-two",
                        customer_id="customer-one",
                        customer_wallet_id="customer-wallet-one",
                        agency_wallet_id="agency-wallet-one",
                        key="bad-deadline-key",
                        deadline="2026-09-01 11:00:00",
                    )
            with pytest.raises(IntegrityError):
                with connection.begin_nested():
                    _insert_reservation(
                        connection,
                        reservation_id="bad-deposit",
                        listing_id="listing-two",
                        quote_id="quote-two",
                        customer_id="customer-one",
                        customer_wallet_id="customer-wallet-one",
                        agency_wallet_id="agency-wallet-one",
                        key="bad-deposit-key",
                        deposit="0.00",
                    )

            migration.downgrade()
            assert "reservation" not in inspect(connection).get_table_names()
    finally:
        engine.dispose()
