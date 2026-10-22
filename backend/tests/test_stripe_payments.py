from decimal import Decimal
import hashlib
import hmac
import importlib.util
from pathlib import Path

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, inspect, text

from app.modules.stripe_payments.gateway import StripeGateway, verify_webhook_signature
from app.modules.stripe_payments.service import payment_amount_minor_units, stripe_currency


@pytest.mark.parametrize(
    ("amount", "currency", "expected_minor"),
    [
        (Decimal("10.00"), "BOB", 1000),
        (Decimal("1.25"), "USD", 125),
    ],
)
def test_payment_amount_uses_exact_minor_units(amount: Decimal, currency: str, expected_minor: int) -> None:
    assert payment_amount_minor_units(amount, currency) == expected_minor


def test_gateway_rejects_live_secret_keys() -> None:
    with pytest.raises(ValueError, match="test-mode"):
        StripeGateway("sk_" + "live_do_not_use")


def test_stripe_currency_is_lowercase_for_supported_card_currency() -> None:
    assert stripe_currency("BOB") == "bob"


def test_usdt_is_not_available_as_a_card_currency() -> None:
    with pytest.raises(ValueError, match="not supported"):
        stripe_currency("USDT")


def test_payment_amount_rejects_fractional_minor_units() -> None:
    with pytest.raises(ValueError, match="minor unit"):
        payment_amount_minor_units(Decimal("10.001"), "BOB")


def test_webhook_signature_matches_raw_payload_and_timestamp() -> None:
    payload = b'{"id":"evt_test"}'
    secret = "whsec_test"
    timestamp = 1_800_000_000
    signed = str(timestamp).encode() + b"." + payload
    signature = hmac.new(secret.encode(), signed, hashlib.sha256).hexdigest()

    assert verify_webhook_signature(payload, f"t={timestamp},v1={signature}", secret, now=timestamp)
    assert not verify_webhook_signature(
        payload + b" ", f"t={timestamp},v1={signature}", secret, now=timestamp
    )


def test_webhook_signature_rejects_stale_timestamp() -> None:
    assert not verify_webhook_signature(b"{}", "t=100,v1=abc", "whsec_test", now=1_000)


def test_stripe_migration_preserves_wallet_rows_and_allows_card_rows() -> None:
    engine = create_engine("sqlite+pysqlite:///:memory:")
    try:
        with engine.begin() as connection:
            connection.execute(text("CREATE TABLE agency (id VARCHAR(36) PRIMARY KEY)"))
            connection.execute(
                text("""
                    CREATE TABLE reservation (
                        id VARCHAR(36) PRIMARY KEY,
                        customer_wallet_id VARCHAR(36) NOT NULL,
                        agency_wallet_id VARCHAR(36) NOT NULL,
                        customer_wallet_address VARCHAR(42) NOT NULL,
                        agency_wallet_address VARCHAR(42) NOT NULL
                    )
                """)
            )
            connection.execute(
                text("""
                    INSERT INTO reservation VALUES (
                        'wallet-reservation', 'cw-1', 'aw-1', '0x111', '0xaaa'
                    )
                """)
            )
            path = (
                Path(__file__).resolve().parents[1] / "alembic" / "versions" / "0019_stripe_card_payments.py"
            )
            spec = importlib.util.spec_from_file_location("stripe_0019_test", path)
            assert spec is not None and spec.loader is not None
            migration = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(migration)
            setattr(migration, "op", Operations(MigrationContext.configure(connection)))
            migration.upgrade()

            columns = {column["name"]: column for column in inspect(connection).get_columns("reservation")}
            assert columns["customer_wallet_id"]["nullable"]
            assert columns["agency_wallet_id"]["nullable"]
            assert columns["payment_method"]["nullable"] is False
            assert columns["payment_method"]["default"] is None
            assert (
                connection.execute(
                    text("SELECT payment_method FROM reservation WHERE id = 'wallet-reservation'")
                ).scalar_one()
                == "wallet"
            )
            connection.execute(
                text("""
                    INSERT INTO reservation (
                        id, customer_wallet_id, agency_wallet_id,
                        customer_wallet_address, agency_wallet_address, payment_method
                    ) VALUES ('card-reservation', NULL, NULL, NULL, NULL, 'card')
                """)
            )
            assert (
                connection.execute(
                    text("SELECT count(*) FROM reservation WHERE payment_method = 'card'")
                ).scalar_one()
                == 1
            )
            assert {
                "stripe_connect_account",
                "reservation_card_payment",
                "stripe_webhook_event",
            }.issubset(set(inspect(connection).get_table_names()))
    finally:
        engine.dispose()
