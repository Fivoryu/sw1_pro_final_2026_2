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
            contact_email="finance@example.test",
            idempotency_key="roomforge-connect-account-f09-demo-agency",
        )

    request = urlopen.call_args.args[0]
    assert request.full_url == "https://api.stripe.com/v2/core/accounts"
    assert request.get_header("Stripe-version") == "2026-11-18.endive"
    assert request.get_header("Content-type") == "application/json"
    assert request.get_method() == "POST"
    assert request.get_header("Idempotency-key") == (
        "roomforge-connect-account-f09-demo-agency"
    )
    assert json.loads(request.data) == {
        "contact_email": "finance@example.test",
        "dashboard": "express",
        "identity": {"country": "US"},
        "defaults": {"responsibilities": {"fees_collector": "application", "losses_collector": "application"}},
        "configuration": {
            "recipient": {"capabilities": {"stripe_balance": {"stripe_transfers": {"requested": True}}}},
        },
        "metadata": {"agency_id": "f09-demo-agency"},
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
        "https://api.stripe.com/v2/core/accounts",
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
                contact_email="finance@example.test",
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
    assert "req_test_diagnostics" not in caplog.text
    assert "Rejected key" not in caplog.text
    assert "sk_test_supersecret" not in caplog.text
    assert "acct_sensitive_123" not in caplog.text
    assert "whsec_sensitive_456" not in caplog.text


def test_connect_account_link_omits_unsupported_configurations() -> None:
    gateway = StripeGateway("sk_test_gateway")
    with patch("app.modules.stripe_payments.gateway.urlopen") as urlopen:
        urlopen.return_value.__enter__.return_value.read.return_value = b'{"url":"https://stripe.test/link"}'
        gateway.create_account_link(
            account_id="acct_test_only",
            refresh_url="https://roomforge.test/refresh",
            return_url="https://roomforge.test/return",
            idempotency_key="test-link",
        )

    request = urlopen.call_args.args[0]
    assert request.full_url == "https://api.stripe.com/v2/core/account_links"
    assert json.loads(request.data) == {
        "account": "acct_test_only",
        "use_case": {
            "type": "account_onboarding",
            "account_onboarding": {
                "refresh_url": "https://roomforge.test/refresh",
                "return_url": "https://roomforge.test/return",
            },
        },
    }


def test_payment_intent_uses_dashboard_payment_methods() -> None:
    gateway = StripeGateway("sk_test_gateway")
    with patch("app.modules.stripe_payments.gateway.urlopen") as urlopen:
        urlopen.return_value.__enter__.return_value.read.return_value = b'{"id":"pi_test_gateway"}'
        gateway.create_payment_intent(
            amount=1000, currency="bob", reservation_id="demo", idempotency_key="demo-payment"
        )

    request = urlopen.call_args.args[0]
    assert request.full_url == "https://api.stripe.com/v1/payment_intents"
    assert parse_qs(request.data.decode()) == {
        "amount": ["1000"],
        "currency": ["bob"],
        "transfer_group": ["demo"],
        "metadata[reservation_id]": ["demo"],
    }


@pytest.mark.parametrize(
    ("currency", "settlement_amount", "expected_key"),
    [("bob", 85, "demo-transfer-settlement-v1"), ("usd", 1000, "demo-transfer")],
)
def test_transfer_uses_verified_source_settlement(
    currency: str, settlement_amount: int, expected_key: str
) -> None:
    gateway = StripeGateway("sk_test_gateway")
    with patch("app.modules.stripe_payments.gateway.urlopen") as urlopen:
        urlopen.return_value.__enter__.return_value.read.side_effect = [
            json.dumps({
                "id": "ch_demo", "amount": 1000, "currency": currency,
                "paid": True, "amount_refunded": 0,
                "balance_transaction": {"currency": "usd", "amount": settlement_amount, "net": 52},
            }).encode(),
            b'{"id":"tr_demo"}',
        ]
        result = gateway.create_transfer(
            amount=1000, currency=currency, destination="acct_demo",
            source_transaction="ch_demo", reservation_id="demo", idempotency_key="demo-transfer",
        )

    lookup, transfer = (call.args[0] for call in urlopen.call_args_list)
    assert lookup.get_method() == "GET"
    assert lookup.full_url == "https://api.stripe.com/v1/charges/ch_demo?expand%5B%5D=balance_transaction"
    assert lookup.get_header("Idempotency-key") is None
    assert transfer.get_header("Idempotency-key") == expected_key
    assert parse_qs(transfer.data.decode()) == {
        "amount": [str(settlement_amount)], "currency": ["usd"], "destination": ["acct_demo"],
        "source_transaction": ["ch_demo"], "transfer_group": ["demo"],
        "metadata[reservation_id]": ["demo"],
    }
    assert result["id"] == "tr_demo"


@pytest.mark.parametrize(
    "invalid_charge", [{"amount_refunded": 1000}, {"balance_transaction": None}, {"amount": 3000}]
)
def test_transfer_with_unverified_settlement_never_posts(invalid_charge: dict[str, object]) -> None:
    gateway = StripeGateway("sk_test_gateway")
    with patch("app.modules.stripe_payments.gateway.urlopen") as urlopen:
        urlopen.return_value.__enter__.return_value.read.return_value = json.dumps({
            "id": "ch_demo", "amount": 1000, "currency": "bob", "paid": True, "amount_refunded": 0,
            "balance_transaction": {"currency": "usd", "amount": 85}, **invalid_charge,
        }).encode()
        with pytest.raises(StripeGatewayError):
            gateway.create_transfer(
                amount=1000, currency="bob", destination="acct_demo", source_transaction="ch_demo",
                reservation_id="demo", idempotency_key="demo-transfer",
            )
    assert urlopen.call_count == 1
