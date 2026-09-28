"""Local-only EIP-712 permit signing for ReservationEscrow."""

from __future__ import annotations

import json
import re
from collections.abc import Callable
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

from eth_account import Account
from eth_utils.address import is_address, to_checksum_address
from eth_utils.crypto import keccak

from app.core.config import Settings

CHAIN_ID = 31337
DOMAIN_NAME = "RoomForgeReservationEscrow"
DOMAIN_VERSION = "1"
ACTION_CODES = {"deposit": 0, "accept": 1, "reject": 2, "cancel": 3}
RpcTransport = Callable[[str, str, list[Any]], Any]
_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)


class PermitUnavailableError(Exception):
    """The configured local escrow cannot be safely used for permit issuance."""


class _NoRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, req: Request, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> None:
        del req, fp, code, msg, headers, newurl
        return None


def hash_api_id(identifier: str) -> str:
    if not isinstance(identifier, str) or not identifier:
        raise ValueError("API identifiers must be non-empty strings")
    return "0x" + keccak(text=identifier).hex()


def contract_deadline_seconds(deadline: datetime) -> int:
    """Ceil the exclusive API deadline to the contract's inclusive ``uint64`` second.

    The policy rejects an action once ``now >= decision_deadline_at``, so the signed
    second must be the first whole second that does not end before that instant.
    Integer arithmetic keeps subsecond tails exact instead of relying on floats.
    """
    utc_deadline = (
        deadline.replace(tzinfo=timezone.utc)
        if deadline.tzinfo is None or deadline.utcoffset() is None
        else deadline.astimezone(timezone.utc)
    )
    elapsed = utc_deadline - _EPOCH
    whole_seconds = elapsed.days * 86_400 + elapsed.seconds
    return whole_seconds if elapsed.microseconds == 0 else whole_seconds + 1


def cop_to_token_units(amount: Decimal | None) -> int:
    if amount is None:
        return 0
    if not isinstance(amount, Decimal) or not amount.is_finite() or amount < 0:
        raise ValueError("COP amount must be a finite non-negative Decimal")
    scaled = amount * 100
    if scaled != scaled.to_integral_value():
        raise ValueError("COP amount must have at most two decimal places")
    return int(scaled)


def build_typed_data(*, chain_id: int, escrow_address: str, action: dict[str, Any]) -> dict[str, Any]:
    """Build the exact EIP-712 domain and struct defined by ReservationEscrow."""
    return {
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"},
            ],
            "ReservationAction": [
                {"name": "reservationId", "type": "bytes32"},
                {"name": "listingId", "type": "bytes32"},
                {"name": "customer", "type": "address"},
                {"name": "agency", "type": "address"},
                {"name": "actor", "type": "address"},
                {"name": "action", "type": "uint8"},
                {"name": "amount", "type": "uint256"},
                {"name": "deadline", "type": "uint64"},
                {"name": "nonce", "type": "uint256"},
            ],
        },
        "primaryType": "ReservationAction",
        "domain": {
            "name": DOMAIN_NAME,
            "version": DOMAIN_VERSION,
            "chainId": chain_id,
            "verifyingContract": to_checksum_address(escrow_address),
        },
        "message": action,
    }


def _checksum_address(value: str) -> str:
    if not isinstance(value, str) or not is_address(value):
        raise PermitUnavailableError
    try:
        checksum = to_checksum_address(value)
    except (TypeError, ValueError):
        raise PermitUnavailableError from None
    if int(checksum, 16) == 0:
        raise PermitUnavailableError
    return checksum


def _resolve_configuration(settings: Settings) -> tuple[str, str, str, str]:
    rpc_url = settings.escrow_rpc_url
    escrow_address = settings.escrow_address
    configured_chain_id = settings.escrow_chain_id
    private_key = settings.escrow_signer_private_key
    if (
        not isinstance(rpc_url, str)
        or not rpc_url
        or not isinstance(escrow_address, str)
        or not escrow_address
        or not isinstance(configured_chain_id, str)
        or not configured_chain_id
        or not isinstance(private_key, str)
        or not private_key
    ):
        raise PermitUnavailableError

    try:
        parsed_url = urlsplit(rpc_url)
        hostname = parsed_url.hostname
        port = parsed_url.port
    except ValueError:
        raise PermitUnavailableError from None
    if (
        parsed_url.scheme != "http"
        or hostname not in {"localhost", "127.0.0.1"}
        or parsed_url.username is not None
        or parsed_url.password is not None
        or parsed_url.query
        or parsed_url.fragment
        or parsed_url.path not in {"", "/"}
        or (port is not None and not 1 <= port <= 65535)
    ):
        raise PermitUnavailableError
    if configured_chain_id != str(CHAIN_ID):
        raise PermitUnavailableError

    checksum_escrow = _checksum_address(escrow_address)
    if not re.fullmatch(r"(?:0x)?[0-9a-fA-F]{64}", private_key):
        raise PermitUnavailableError
    normalized_key = private_key if private_key.startswith("0x") else "0x" + private_key
    try:
        signer_address = Account.from_key(normalized_key).address
    except (ValueError, TypeError):
        raise PermitUnavailableError from None
    return rpc_url, checksum_escrow, normalized_key, signer_address


def _http_rpc_transport(url: str, method: str, params: list[Any]) -> Any:
    request_body = json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": method, "params": params},
        separators=(",", ":"),
    ).encode("utf-8")
    request = Request(
        url,
        data=request_body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    # ProxyHandler({}) disables the default environment proxy lookup so loopback
    # JSON-RPC traffic can never be redirected through HTTP(S)_PROXY variables.
    opener = build_opener(ProxyHandler({}), _NoRedirectHandler())
    try:
        with opener.open(request, timeout=3) as response:
            payload = json.loads(response.read(1_048_576))
    except (HTTPError, OSError, ValueError, TimeoutError):
        raise PermitUnavailableError from None
    if (
        not isinstance(payload, dict)
        or payload.get("jsonrpc") != "2.0"
        or payload.get("id") != 1
        or "error" in payload
        or "result" not in payload
    ):
        raise PermitUnavailableError
    return payload["result"]


def _rpc(
    transport: RpcTransport,
    url: str,
    method: str,
    params: list[Any],
) -> Any:
    try:
        return transport(url, method, params)
    except PermitUnavailableError:
        raise
    except Exception:
        raise PermitUnavailableError from None


def _rpc_chain_id(value: Any) -> int:
    if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]+", value):
        raise PermitUnavailableError
    return int(value, 16)


def _contract_code_is_present(value: Any) -> bool:
    if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]*", value):
        return False
    return len(value) > 2 and int(value[2:] or "0", 16) != 0


def _decode_address_result(value: Any) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]{64}", value):
        raise PermitUnavailableError
    word = value[2:]
    if word[:24] != "0" * 24:
        raise PermitUnavailableError
    return _checksum_address("0x" + word[-40:])


def _decode_uint_result(value: Any) -> int:
    if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]{1,64}", value):
        raise PermitUnavailableError
    return int(value, 16)


def _function_selector(signature: str) -> str:
    return "0x" + keccak(text=signature)[:4].hex()


def issue_permit(
    *,
    settings: Settings,
    transport: RpcTransport | None,
    reservation_id: str,
    listing_id: str,
    customer_address: str,
    agency_address: str,
    actor_address: str,
    action: str,
    amount: int,
    deadline: int,
) -> dict[str, Any]:
    """Read local chain identity/nonce and sign one contract-compatible action."""
    try:
        action_code = ACTION_CODES[action]
    except (KeyError, TypeError):
        raise PermitUnavailableError from None
    if (
        not isinstance(amount, int)
        or isinstance(amount, bool)
        or amount < 0
        or amount >= 2**256
        or not isinstance(deadline, int)
        or isinstance(deadline, bool)
        or deadline <= 0
        or deadline >= 2**64
    ):
        raise PermitUnavailableError

    rpc_url, escrow_address, private_key, signer_address = _resolve_configuration(settings)
    customer = _checksum_address(customer_address)
    agency = _checksum_address(agency_address)
    actor = _checksum_address(actor_address)
    if (
        (action == "deposit" and actor != customer)
        or (action in {"accept", "reject"} and actor != agency)
        or (action == "cancel" and actor not in {customer, agency})
    ):
        raise PermitUnavailableError

    rpc = transport or _http_rpc_transport
    if _rpc_chain_id(_rpc(rpc, rpc_url, "eth_chainId", [])) != CHAIN_ID:
        raise PermitUnavailableError
    code = _rpc(rpc, rpc_url, "eth_getCode", [escrow_address, "latest"])
    if not _contract_code_is_present(code):
        raise PermitUnavailableError

    signer_calldata = _function_selector("authorizedSigner()")
    authorized_signer = _decode_address_result(
        _rpc(
            rpc,
            rpc_url,
            "eth_call",
            [{"to": escrow_address, "data": signer_calldata}, "latest"],
        )
    )
    if authorized_signer != signer_address:
        raise PermitUnavailableError

    reservation_hash = hash_api_id(reservation_id)
    listing_hash = hash_api_id(listing_id)
    nonce_calldata = _function_selector("nonces(bytes32)") + reservation_hash[2:]
    nonce = _decode_uint_result(
        _rpc(
            rpc,
            rpc_url,
            "eth_call",
            [{"to": escrow_address, "data": nonce_calldata}, "latest"],
        )
    )
    permit = {
        "reservationId": reservation_hash,
        "listingId": listing_hash,
        "customer": customer,
        "agency": agency,
        "actor": actor,
        "action": action_code,
        "amount": amount,
        "deadline": deadline,
        "nonce": nonce,
    }
    typed_data = build_typed_data(
        chain_id=CHAIN_ID,
        escrow_address=escrow_address,
        action=permit,
    )
    try:
        signed = Account.sign_typed_data(private_key, full_message=typed_data)
    except Exception:
        raise PermitUnavailableError from None
    return {**permit, "signature": "0x" + bytes(signed.signature).hex()}
