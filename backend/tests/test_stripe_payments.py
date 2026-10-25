from decimal import Decimal
from email.message import Message
import hashlib
import hmac
import importlib.util
import json
from io import BytesIO
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import parse_qs
from unittest.mock import patch

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, inspect, text

from app.modules.stripe_payments.gateway import (
    StripeGateway,
    StripeGatewayError,
    verify_webhook_signature,
)
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


def test_connect_account_request_uses_marketplace_express_transfer_payload() -> None:
    gateway = StripeGateway("sk_test_gateway")
    with patch("app.modules.stripe_payments.gateway.urlopen") as urlopen:
        urlopen.return_value.__enter__.return_value.read.return_value = json.dumps(
            {"id": "acct_test_only", "object": "account"}
        ).encode()

        result = gateway.create_connect_account(
            country="US",
            agency_id="f09-demo-agency",
            idempotency_key="roomforge-connect-account-f09-demo-agency",
        )

    request = urlopen.call_args.args[0]
    assert request.full_url == "https://api.stripe.com/v1/accounts"
    assert request.get_method() == "POST"
    assert request.get_header("Idempotency-key") == (
        "roomforge-connect-account-f09-demo-agency"
    )
    assert parse_qs(request.data.decode("utf-8")) == {
        "type": ["express"],
        "country": ["US"],
        "capabilities[transfers][requested]": ["true"],
        "metadata[agency_id]": ["f09-demo-agency"],
    }
    assert result["object"] == "account"


def test_connect_account_provider_error_is_logged_safely(caplog: pytest.LogCaptureFixture) -> None:
    headers = Message()
    headers["Request-Id"] = "req_test_diagnostics"
    body = json.dumps(
        {
            "error": {
                "type": "invalid_request_error",
                "code": "parameter_invalid",
                "param": "capabilities[transfers][requested]",
                "message": (
                    "Rejected key sk_test_supersecret and account acct_sensitive_123; "
                    "webhook whsec_sensitive_456"
                ),
            }
        }
    ).encode("utf-8")
    provider_error = HTTPError(
        "https://api.stripe.com/v1/accounts",
        400,
        "Bad Request",
        headers,
        BytesIO(body),
    )
    gateway = StripeGateway("sk_test_gateway")

    with patch("app.modules.stripe_payments.gateway.urlopen", side_effect=provider_error):
        with caplog.at_level(
            "WARNING", logger="app.modules.stripe_payments.gateway"
        ), pytest.raises(StripeGatewayError) as captured:
            gateway.create_connect_account(
                country="US",
                agency_id="f09-demo-agency",
                idempotency_key="roomforge-connect-account-f09-demo-agency",
            )

    error = captured.value
    assert error.http_status == 400
    assert error.provider_error_type == "invalid_request_error"
    assert error.provider_error_code == "parameter_invalid"
    assert error.provider_error_param == "capabilities[transfers][requested]"
    assert error.provider_request_id == "req_test_diagnostics"
    assert error.provider_error_message == (
        "Rejected key [redacted] and account [redacted]; webhook [redacted]"
    )
    assert error.__cause__ is None
    assert str(error) == "Stripe is unavailable or rejected the request"
    assert "invalid_request_error" in caplog.text
    assert "parameter_invalid" in caplog.text
    assert "capabilities[transfers][requested]" in caplog.text
    assert "req_test_diagnostics" in caplog.text
    assert "Rejected key" in caplog.text
    assert "sk_test_supersecret" not in caplog.text
    assert "acct_sensitive_123" not in caplog.text
    assert "whsec_sensitive_456" not in caplog.text
