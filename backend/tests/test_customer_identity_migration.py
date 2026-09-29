from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.engine import Connection


_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_MIGRATIONS = _BACKEND_ROOT / "alembic" / "versions"


def _load_migration(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _assert_unique_violation(connection: Connection, statement: str, values: dict[str, str]) -> None:
    with connection.begin_nested():
        with pytest.raises(IntegrityError):
            connection.execute(text(statement), values)


def test_customer_wallet_migration_upgrades_schema_from_0005() -> None:
    wallet_migration_path = _MIGRATIONS / "0006_customer_wallet.py"
    assert wallet_migration_path.is_file(), "CC-03B must add the 0006 customer wallet migration"

    previous = _load_migration(
        _MIGRATIONS / "0005_customer_identity.py", "customer_identity_0005_for_wallet_test"
    )
    migration = _load_migration(wallet_migration_path, "customer_wallet_0006_for_test")
    assert previous.revision == "0005_customer_identity"
    assert migration.revision == "0006_customer_wallet"
    assert migration.down_revision == previous.revision

    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.begin() as connection:
            migration_context = MigrationContext.configure(connection)
            with Operations.context(migration_context):
                previous.upgrade()
                assert {"customer_account", "customer_session"}.issubset(
                    inspect(connection).get_table_names()
                )
                migration.upgrade()

            inspector = inspect(connection)
            assert {"customer_wallet", "customer_wallet_challenge"}.issubset(
                inspector.get_table_names()
            )
            wallet_columns = {column["name"] for column in inspector.get_columns("customer_wallet")}
            assert {"id", "customer_id", "address", "linked_at"}.issubset(wallet_columns)
            challenge_columns = {
                column["name"] for column in inspector.get_columns("customer_wallet_challenge")
            }
            assert {
                "id",
                "customer_id",
                "address",
                "purpose",
                "nonce",
                "message",
                "issued_at",
                "expires_at",
                "consumed_at",
            }.issubset(challenge_columns)

            wallet_uniques = {
                tuple(constraint["column_names"])
                for constraint in inspector.get_unique_constraints("customer_wallet")
            }
            wallet_unique_indexes = {
                tuple(index["column_names"])
                for index in inspector.get_indexes("customer_wallet")
                if index["unique"] and index["column_names"] is not None
            }
            unique_keys = wallet_uniques | wallet_unique_indexes
            assert ("customer_id",) in unique_keys
            assert ("address",) in unique_keys

            connection.execute(
                text(
                    "INSERT INTO customer_account (id, email, password_hash) "
                    "VALUES ('customer-one', 'one@example.test', 'hash'), "
                    "('customer-two', 'two@example.test', 'hash')"
                )
            )
            connection.execute(
                text(
                    "INSERT INTO customer_wallet (id, customer_id, address, linked_at) "
                    "VALUES ('wallet-one', 'customer-one', '0x1111111111111111111111111111111111111111', "
                    "'2026-09-01 12:00:00')"
                )
            )
            _assert_unique_violation(
                connection,
                "INSERT INTO customer_wallet (id, customer_id, address, linked_at) "
                "VALUES ('wallet-two', 'customer-two', '0x1111111111111111111111111111111111111111', "
                "'2026-09-01 12:00:00')",
                {},
            )
            _assert_unique_violation(
                connection,
                "INSERT INTO customer_wallet (id, customer_id, address, linked_at) "
                "VALUES ('wallet-three', 'customer-one', '0x2222222222222222222222222222222222222222', "
                "'2026-09-01 12:00:00')",
                {},
            )
    finally:
        engine.dispose()
