from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timezone
from email.message import Message
from types import SimpleNamespace
from typing import cast
from urllib.error import HTTPError

import pytest
from fastapi import HTTPException, Request

from app.modules.identity.session import ActiveStaff

from app.modules.stripe_payments import router as stripe_router
from app.modules.stripe_payments.gateway import StripeGatewayError


class FakeQuery:
    def __init__(self, account: object | None) -> None:
        self.account = account

    def filter_by(self, **_: object) -> FakeQuery:
        return self

    def one_or_none(self) -> object | None:
        return self.account


class FakeSession:
    def __init__(self, account: object | None) -> None:
        self.account = account

    def query(self, _: object) -> FakeQuery:
        return FakeQuery(self.account)


class FakeSessionFactory:
    def __init__(self, account: object | None) -> None:
        self.account = account

    @contextmanager
    def __call__(self):
        yield FakeSession(self.account)


class FailingGateway:
    def __init__(self, error: Exception, *, operation: str) -> None:
        self.error = error
        self.operation = operation

    def create_connect_account(self, **_: object) -> dict[str, object]:
        assert self.operation == "create_connect_account"
        raise self.error

    def create_account_link(self, **_: object) -> dict[str, object]:
        assert self.operation == "create_account_link"
        raise self.error


def make_request(gateway: FailingGateway, account: object | None) -> SimpleNamespace:
    return SimpleNamespace(
        app=SimpleNamespace(
            state=SimpleNamespace(
                session_factory=FakeSessionFactory(account),
                settings=SimpleNamespace(stripe_connect_account_country="BO", web_origin="https://roomforge.test"),
                stripe_gateway=gateway,
                clock=lambda: datetime.fromtimestamp(1_700_000_000, tz=timezone.utc),
            )
        )
    )


@pytest.mark.parametrize(
    ("account", "operation", "error"),
    [
        (
            None,
            "create_connect_account",
            StripeGatewayError(
                "provider message sk_test_secret acct_123 https://stripe.test/raw",
                http_status=403,
                provider_error_type="account_error",
                provider_error_code="country_unsupported",
                provider_error_param="country",
                provider_error_message="raw provider message",
                provider_request_id="req_secret",
            ),
        ),
        (
            SimpleNamespace(stripe_account_id="acct_existing"),
            "create_account_link",
            StripeGatewayError(
                "provider message sk_test_secret acct_123 https://stripe.test/raw",
                http_status=400,
                provider_error_type="invalid_request_error",
                provider_error_code="link_invalid",
                provider_error_param="refresh_url",
                provider_error_message="raw provider message",
                provider_request_id="req_secret",
            ),
        ),
    ],
)
def test_onboarding_logs_safe_static_diagnostics_and_preserves_http_503(
    account: object | None,
    operation: str,
    error: StripeGatewayError,
    caplog: pytest.LogCaptureFixture,
) -> None:
    request = make_request(FailingGateway(error, operation=operation), account)
    staff = {"id": "staff-1", "email": "staff@example.test", "role": "agency_admin", "tenant_id": "agency-secret"}

    with caplog.at_level("WARNING", logger=stripe_router.__name__), pytest.raises(HTTPException) as raised:
        stripe_router.create_connect_onboarding_link(
            "agency-secret", cast(Request, request), cast(ActiveStaff, staff),
            stripe_router.ConnectOnboardingRequest(contact_email="finance@example.test"),
        )

    assert raised.value.status_code == 503
    assert raised.value.detail == "Stripe Connect onboarding is unavailable"
    assert len(caplog.records) == 1
    record = caplog.records[0]
    assert getattr(record, "operation_stage") == operation
    assert getattr(record, "exception_class") == "StripeGatewayError"
    assert getattr(record, "http_status") == error.http_status
    assert getattr(record, "provider_error_type") == error.provider_error_type
    assert getattr(record, "provider_error_code") == error.provider_error_code
    assert getattr(record, "provider_error_param") == error.provider_error_param
    rendered = caplog.text
    for forbidden in (
        str(error),
        "raw provider message",
        "req_secret",
        "sk_test_secret",
        "acct_existing",
        "agency-secret",
        "https://stripe.test/raw",
    ):
        assert forbidden not in rendered


def test_onboarding_logs_only_exception_and_cause_class_for_value_error(
    caplog: pytest.LogCaptureFixture,
) -> None:
    error = ValueError("raw value message sk_test_secret acct_123 https://stripe.test/raw")
    error.__cause__ = ConnectionError("transport secret")
    request = make_request(FailingGateway(error, operation="create_account_link"), SimpleNamespace(stripe_account_id="acct_existing"))

    with caplog.at_level("WARNING", logger=stripe_router.__name__), pytest.raises(HTTPException) as raised:
        stripe_router.create_connect_onboarding_link(
            "agency-secret",
            cast(Request, request),
            cast(
                ActiveStaff,
                {"id": "staff-1", "email": "staff@example.test", "role": "agency_admin", "tenant_id": "agency-secret"},
            ),
        )

    assert raised.value.status_code == 503
    assert raised.value.detail == "Stripe Connect onboarding is unavailable"
    record = caplog.records[0]
    assert getattr(record, "operation_stage") == "create_account_link"
    assert getattr(record, "exception_class") == "ValueError"
    assert getattr(record, "cause_class") == "ConnectionError"
    assert not hasattr(record, "http_status")
    assert not hasattr(record, "provider_error_type")
    assert "raw value message" not in caplog.text
    assert "transport secret" not in caplog.text
    assert "sk_test_secret" not in caplog.text
    assert "acct_existing" not in caplog.text
    assert "agency-secret" not in caplog.text
    assert "https://stripe.test/raw" not in caplog.text


def test_onboarding_handles_legacy_gateway_error_without_diagnostic_fields(
    caplog: pytest.LogCaptureFixture,
) -> None:
    error = StripeGatewayError.__new__(StripeGatewayError)
    RuntimeError.__init__(error, "legacy error")
    error.__cause__ = HTTPError("https://stripe.test/private", 400, "provider text", Message(), None)
    request = make_request(FailingGateway(error, operation="create_connect_account"), None)
    staff = {"id": "staff-1", "email": "staff@example.test", "role": "agency_admin", "tenant_id": "agency-secret"}

    with caplog.at_level("WARNING", logger=stripe_router.__name__), pytest.raises(HTTPException) as raised:
        stripe_router.create_connect_onboarding_link(
            "agency-secret", cast(Request, request), cast(ActiveStaff, staff),
            stripe_router.ConnectOnboardingRequest(contact_email="finance@example.test"),
        )

    assert raised.value.status_code == 503
    assert "stage=create_connect_account" in caplog.text
    assert "http_status=400" in caplog.text
    assert "provider text" not in caplog.text
    assert "https://stripe.test/private" not in caplog.text
