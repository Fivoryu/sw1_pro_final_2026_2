from __future__ import annotations

import hashlib
import hmac
import json
import time
from collections.abc import Mapping
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


class StripeGatewayError(RuntimeError):
    """A provider operation failed or could not be reached."""


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
        except (HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
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
