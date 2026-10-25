from __future__ import annotations

import hashlib
import hmac
import json
import logging
import re
import time
from collections.abc import Mapping
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


_logger = logging.getLogger(__name__)
_MAX_DIAGNOSTIC_LENGTH = 300
_SENSITIVE_PROVIDER_VALUE = re.compile(
    r"\b(?:sk|pk|rk)_(?:test|live)_[A-Za-z0-9_-]+\b"
    r"|\bwhsec_[A-Za-z0-9_-]+\b"
    r"|\b(?:acct|cus|pi|pm|tok|cs|seti|btok|ba|ca|src|ch|tr|re|rf|dp|in|sub)_"
    r"[A-Za-z0-9_-]+\b"
    r"|https?://\S+"
    r"|\b[A-Za-z0-9.+_-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"
)


def _safe_provider_text(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    compact = " ".join(value.split())
    redacted = _SENSITIVE_PROVIDER_VALUE.sub("[redacted]", compact)
    return redacted[:_MAX_DIAGNOSTIC_LENGTH]


def _provider_error_details(error: HTTPError) -> dict[str, object]:
    try:
        payload = json.loads(error.read())
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        payload = None
    provider_error = payload.get("error") if isinstance(payload, dict) else None
    if not isinstance(provider_error, dict):
        provider_error = {}
    headers = error.headers
    request_id = headers.get("Request-Id") if headers is not None else None
    return {
        "http_status": error.code,
        "provider_error_type": _safe_provider_text(provider_error.get("type")),
        "provider_error_code": _safe_provider_text(provider_error.get("code")),
        "provider_error_param": _safe_provider_text(provider_error.get("param")),
        "provider_request_id": _safe_provider_text(request_id),
        "provider_error_message": _safe_provider_text(provider_error.get("message")),
    }


class StripeGatewayError(RuntimeError):
    """A provider operation failed or could not be reached."""

    def __init__(self, message: str, **diagnostics: object) -> None:
        super().__init__(message)
        self.http_status = diagnostics.get("http_status")
        self.provider_error_type = diagnostics.get("provider_error_type")
        self.provider_error_code = diagnostics.get("provider_error_code")
        self.provider_error_param = diagnostics.get("provider_error_param")
        self.provider_request_id = diagnostics.get("provider_request_id")
        self.provider_error_message = diagnostics.get("provider_error_message")


class StripeGateway:
    """Small synchronous Stripe REST adapter, injectable in API tests."""

    def __init__(self, secret_key: str, *, timeout_seconds: float = 10.0) -> None:
        if not secret_key.startswith("sk_test_"):
            raise ValueError("Only Stripe test-mode secret keys are permitted")
        self._secret_key = secret_key
        self._timeout_seconds = timeout_seconds

    def _request(
        self,
        method: str,
        path: str,
        fields: Mapping[str, str],
        *,
        idempotency_key: str,
    ) -> dict[str, object]:
        body = urlencode(fields).encode("utf-8")
        request = Request(
            f"https://api.stripe.com/v1/{path.lstrip('/')}",
            data=body,
            method=method,
            headers={
                "Authorization": f"Bearer {self._secret_key}",
                "Content-Type": "application/x-www-form-urlencoded",
                "Idempotency-Key": idempotency_key,
            },
        )
        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:
                decoded = json.loads(response.read())
        except HTTPError as error:
            diagnostics = _provider_error_details(error)
            _logger.warning(
                "Stripe API rejected request: status=%s type=%s code=%s param=%s "
                "request_id=%s message=%s",
                diagnostics["http_status"],
                diagnostics["provider_error_type"] or "-",
                diagnostics["provider_error_code"] or "-",
                diagnostics["provider_error_param"] or "-",
                diagnostics["provider_request_id"] or "-",
                diagnostics["provider_error_message"] or "-",
            )
            raise StripeGatewayError(
                "Stripe is unavailable or rejected the request", **diagnostics
            ) from None
        except (URLError, TimeoutError, OSError, ValueError) as error:
            raise StripeGatewayError("Stripe is unavailable or rejected the request") from error
        if not isinstance(decoded, dict):
            raise StripeGatewayError("Stripe returned an invalid response")
        if "error" in decoded:
            raise StripeGatewayError("Stripe rejected the request")
        return decoded

    def create_payment_intent(
        self,
        *,
        amount: int,
        currency: str,
        reservation_id: str,
        idempotency_key: str,
    ) -> dict[str, object]:
        return self._request(
            "POST",
            "payment_intents",
            {
                "amount": str(amount),
                "currency": currency,
                "payment_method_types[0]": "card",
                "transfer_group": reservation_id,
                "metadata[reservation_id]": reservation_id,
            },
            idempotency_key=idempotency_key,
        )

    def create_connect_account(
        self, *, country: str, agency_id: str, idempotency_key: str
    ) -> dict[str, object]:
        return self._request(
            "POST",
            "accounts",
            {
                "type": "express",
                "country": country.upper(),
                "capabilities[transfers][requested]": "true",
                "metadata[agency_id]": agency_id,
            },
            idempotency_key=idempotency_key,
        )

    def create_account_link(
        self,
        *,
        account_id: str,
        refresh_url: str,
        return_url: str,
        idempotency_key: str,
    ) -> dict[str, object]:
        return self._request(
            "POST",
            "account_links",
            {
                "account": account_id,
                "type": "account_onboarding",
                "refresh_url": refresh_url,
                "return_url": return_url,
            },
            idempotency_key=idempotency_key,
        )

    def retrieve_account(self, account_id: str) -> dict[str, object]:
        request = Request(
            f"https://api.stripe.com/v1/accounts/{account_id}",
            method="GET",
            headers={"Authorization": f"Bearer {self._secret_key}"},
        )
        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:
                decoded = json.loads(response.read())
        except (HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
            raise StripeGatewayError("Stripe is unavailable or rejected the request") from error
        if not isinstance(decoded, dict):
            raise StripeGatewayError("Stripe returned an invalid response")
        return decoded

    def create_transfer(
        self,
        *,
        amount: int,
        currency: str,
        destination: str,
        source_transaction: str,
        reservation_id: str,
        idempotency_key: str,
    ) -> dict[str, object]:
        return self._request(
            "POST",
            "transfers",
            {
                "amount": str(amount),
                "currency": currency,
                "destination": destination,
                "source_transaction": source_transaction,
                "transfer_group": reservation_id,
                "metadata[reservation_id]": reservation_id,
            },
            idempotency_key=idempotency_key,
        )

    def cancel_payment_intent(self, *, payment_intent_id: str, idempotency_key: str) -> dict[str, object]:
        return self._request(
            "POST",
            f"payment_intents/{payment_intent_id}/cancel",
            {},
            idempotency_key=idempotency_key,
        )

    def create_refund(self, *, payment_intent_id: str, idempotency_key: str) -> dict[str, object]:
        return self._request(
            "POST",
            "refunds",
            {"payment_intent": payment_intent_id},
            idempotency_key=idempotency_key,
        )


def verify_webhook_signature(
    payload: bytes,
    signature_header: str,
    secret: str,
    *,
    now: int | None = None,
    tolerance_seconds: int = 300,
) -> bool:
    """Verify Stripe's signed raw request body and reject stale/replayed signatures."""
    timestamp: int | None = None
    signatures: list[str] = []
    for part in signature_header.split(","):
        key, separator, value = part.partition("=")
        if not separator:
            continue
        if key == "t":
            try:
                timestamp = int(value)
            except ValueError:
                return False
        elif key == "v1":
            signatures.append(value)
    if timestamp is None or not signatures:
        return False
    current_time = int(time.time()) if now is None else now
    if abs(current_time - timestamp) > tolerance_seconds:
        return False
    signed_payload = str(timestamp).encode("ascii") + b"." + payload
    expected = hmac.new(secret.encode("utf-8"), signed_payload, hashlib.sha256).hexdigest()
    return any(hmac.compare_digest(expected, signature) for signature in signatures)


def decode_webhook_event(payload: bytes) -> dict[str, object]:
    try:
        decoded = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise ValueError("Invalid Stripe event payload") from None
    if not isinstance(decoded, dict):
        raise ValueError("Invalid Stripe event payload")
    return decoded
