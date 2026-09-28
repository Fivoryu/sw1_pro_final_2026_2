from __future__ import annotations

import base64
import http.client
import json
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any

import pytest
from eth_account import Account
from eth_account.messages import encode_typed_data
from eth_utils.address import to_checksum_address
from eth_utils.crypto import keccak
from app.core.config import Settings

PRIVATE_KEY = "0x" + "11" * 32
SIGNER_ADDRESS = Account.from_key(PRIVATE_KEY).address
ESCROW_ADDRESS = "0x" + "22" * 20
CUSTOMER_ADDRESS = "0x" + "33" * 20
AGENCY_ADDRESS = "0x" + "44" * 20


def _settings(**overrides: Any) -> Settings:
    values: dict[str, Any] = {
        "database_url": "sqlite+pysqlite:///:memory:",
        "jwt_secret": "reservation-chain-test-secret-at-least-32-bytes",
        "totp_encryption_key": "",
        "web_origin": "https://panel.example.test",
        "escrow_rpc_url": "http://127.0.0.1:8545",
        "escrow_address": ESCROW_ADDRESS,
        "escrow_chain_id": "31337",
        "escrow_signer_private_key": PRIVATE_KEY,
    }
    values.update(overrides)
    return Settings(**values)


class FakeJsonRpc:
    def __init__(
        self,
        *,
        signer: str = SIGNER_ADDRESS,
        chain_id: int = 31337,
        nonces: dict[str, int] | None = None,
    ) -> None:
        self.signer = signer
        self.chain_id = chain_id
        self.nonces = nonces or {}
        self.calls: list[tuple[str, list[Any]]] = []

    def __call__(self, url: str, method: str, params: list[Any]) -> Any:
        assert url == "http://127.0.0.1:8545"
        self.calls.append((method, params))
        if method == "eth_chainId":
            return hex(self.chain_id)
        if method == "eth_getCode":
            assert params == [ESCROW_ADDRESS, "latest"] or params == [
                to_checksum_address(ESCROW_ADDRESS),
                "latest",
            ]
            return "0x6000"
        if method == "eth_call":
            calldata = params[0]["data"]
            selector = calldata[:10]
            if selector == "0x" + keccak(text="authorizedSigner()")[:4].hex():
                return "0x" + self.signer[2:].lower().rjust(64, "0")
            if selector == "0x" + keccak(text="nonces(bytes32)")[:4].hex():
                reservation_hash = "0x" + calldata[10:74]
                return hex(self.nonces.get(reservation_hash, 0))
        raise AssertionError(f"Unexpected JSON-RPC request: {method} {params}")


class SocketlessJsonRpcConnection:
    """``http.client.HTTPConnection`` double that answers JSON-RPC without a socket."""

    debuglevel = 0
    connections: list[SocketlessJsonRpcConnection] = []
    response_body = b'{"jsonrpc":"2.0","id":1,"result":"0x7a69"}'

    def __init__(self, host: str, timeout: float | None = None, **kwargs: Any) -> None:
        del kwargs
        type(self).connections.append(self)
        self.host = host
        self.timeout = timeout
        self.sock: Any = None
        self.method: str | None = None
        self.body = b""

    @staticmethod
    def _get_content_length(body: Any, method: str) -> int | None:
        del method
        return len(body) if isinstance(body, (bytes, bytearray)) else None

    def set_debuglevel(self, level: int) -> None:
        del level

    def request(
        self,
        method: str,
        url: str,
        body: bytes | None = None,
        headers: dict[str, str] | None = None,
        *,
        encode_chunked: bool = False,
    ) -> None:
        del url, headers, encode_chunked
        self.method = method
        self.body = body or b""

    def getresponse(self) -> _SocketlessHttpResponse:
        return _SocketlessHttpResponse(self.response_body)

    def close(self) -> None:
        return None


class _SocketlessHttpResponse:
    """HTTP response double returning one canned body with no transport of its own."""

    code = 200
    reason = "OK"

    def __init__(self, body: bytes) -> None:
        self._body = body

    def info(self) -> Any:
        return None

    def read(self, amount: int | None = None) -> bytes:
        return self._body if amount is None else self._body[:amount]

    def close(self) -> None:
        return None

    def __enter__(self) -> _SocketlessHttpResponse:
        return self

    def __exit__(self, *exc_info: object) -> bool:
        del exc_info
        return False


def _chain_module():
    from app.modules.reservations import chain

    return chain


@pytest.mark.parametrize("proxy_environment", [True, False])
def test_loopback_json_rpc_transport_ignores_ambient_proxy_environment(
    monkeypatch: pytest.MonkeyPatch, proxy_environment: bool
) -> None:
    chain = _chain_module()
    for name in ("HTTP_PROXY", "http_proxy", "HTTPS_PROXY", "https_proxy"):
        if proxy_environment:
            monkeypatch.setenv(name, "http://proxy.invalid:8080")
        else:
            monkeypatch.delenv(name, raising=False)
    for name in ("NO_PROXY", "no_proxy"):
        monkeypatch.delenv(name, raising=False)
    SocketlessJsonRpcConnection.connections = []
    monkeypatch.setattr(http.client, "HTTPConnection", SocketlessJsonRpcConnection)

    result = chain._http_rpc_transport("http://127.0.0.1:8545", "eth_chainId", [])

    connections = SocketlessJsonRpcConnection.connections
    assert result == "0x7a69"
    assert [connection.host for connection in connections] == ["127.0.0.1:8545"]
    assert connections[0].body == json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": "eth_chainId", "params": []},
        separators=(",", ":"),
    ).encode("utf-8")


@pytest.mark.parametrize(
    ("deadline", "expected"),
    [
        (datetime(2030, 1, 1, tzinfo=timezone.utc), 1_893_456_000),
        (datetime(2030, 1, 1, 0, 0, 0, 1, tzinfo=timezone.utc), 1_893_456_001),
        (datetime(2030, 1, 1, 0, 0, 0, 250_000, tzinfo=timezone.utc), 1_893_456_001),
        (datetime(2030, 1, 1, 0, 0, 0, 999_999, tzinfo=timezone.utc), 1_893_456_001),
        (datetime(2030, 1, 1, 5, 0, 0, tzinfo=timezone(timedelta(hours=-5))), 1_893_492_000),
        (datetime(2030, 1, 1, 5, 0, 0, 500_000, tzinfo=timezone(timedelta(hours=-5))), 1_893_492_001),
        (datetime(2030, 1, 1), 1_893_456_000),
        (datetime(2030, 1, 1, 0, 0, 0, 750_000), 1_893_456_001),
    ],
)
def test_contract_deadline_is_ceiled_to_the_next_whole_second(
    deadline: datetime, expected: int
) -> None:
    chain = _chain_module()

    assert chain.contract_deadline_seconds(deadline) == expected


@pytest.mark.parametrize("microseconds", [0, 1, 250_000, 999_999])
def test_contract_deadline_is_the_first_second_not_before_the_policy_instant(
    microseconds: int,
) -> None:
    chain = _chain_module()
    deadline = datetime(2030, 1, 1, 0, 0, 0, microseconds, tzinfo=timezone.utc)

    signed_second = datetime.fromtimestamp(
        chain.contract_deadline_seconds(deadline), tz=timezone.utc
    )

    assert signed_second >= deadline
    assert signed_second - timedelta(seconds=1) < deadline


def test_api_identifiers_use_ethereum_keccak_and_cop_amounts_use_integer_units() -> None:
    chain = _chain_module()

    assert chain.hash_api_id("reserva-ñ") == "0x" + keccak(text="reserva-ñ").hex()
    assert chain.cop_to_token_units(Decimal("38.42")) == 3842
    assert chain.cop_to_token_units(None) == 0
    with pytest.raises(ValueError):
        chain.cop_to_token_units(Decimal("0.001"))


def test_typed_data_exactly_matches_reservation_escrow_domain_and_primary_type() -> None:
    chain = _chain_module()
    action = {
        "reservationId": "0x" + "01" * 32,
        "listingId": "0x" + "02" * 32,
        "customer": CUSTOMER_ADDRESS,
        "agency": AGENCY_ADDRESS,
        "actor": CUSTOMER_ADDRESS,
        "action": 0,
        "amount": 3842,
        "deadline": 1_800_000_000,
        "nonce": 7,
    }

    typed_data = chain.build_typed_data(
        chain_id=31337,
        escrow_address=ESCROW_ADDRESS,
        action=action,
    )

    assert typed_data == {
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
            "name": "RoomForgeReservationEscrow",
            "version": "1",
            "chainId": 31337,
            "verifyingContract": to_checksum_address(ESCROW_ADDRESS),
        },
        "message": action,
    }


def test_permit_uses_contract_action_codes_nonce_per_reservation_and_recovers_signer() -> None:
    chain = _chain_module()
    first_id = "reservation-one"
    second_id = "reservation-two"
    first_hash = chain.hash_api_id(first_id)
    second_hash = chain.hash_api_id(second_id)
    rpc = FakeJsonRpc(nonces={first_hash: 3, second_hash: 9})
    expected_codes = {"deposit": 0, "accept": 1, "reject": 2, "cancel": 3}

    permits = [
        chain.issue_permit(
            settings=_settings(),
            transport=rpc,
            reservation_id=first_id,
            listing_id="listing-one",
            customer_address=CUSTOMER_ADDRESS,
            agency_address=AGENCY_ADDRESS,
            actor_address=(
                CUSTOMER_ADDRESS if action in {"deposit", "cancel"} else AGENCY_ADDRESS
            ),
            action=action,
            amount=3842,
            deadline=1_800_000_000,
        )
        for action in expected_codes
    ]
    second = chain.issue_permit(
        settings=_settings(),
        transport=rpc,
        reservation_id=second_id,
        listing_id="listing-two",
        customer_address=CUSTOMER_ADDRESS,
        agency_address=AGENCY_ADDRESS,
        actor_address=AGENCY_ADDRESS,
        action="accept",
        amount=0,
        deadline=1_800_000_000,
    )

    assert [permit["action"] for permit in permits] == list(expected_codes.values())
    assert [permit["nonce"] for permit in permits] == [3, 3, 3, 3]
    assert second["nonce"] == 9
    for permit in permits + [second]:
        assert Account.recover_message(
            encode_typed_data(full_message=chain.build_typed_data(
                chain_id=31337,
                escrow_address=ESCROW_ADDRESS,
                action={key: value for key, value in permit.items() if key != "signature"},
            )),
            signature=permit["signature"],
        ) == SIGNER_ADDRESS
    nonce_calls = [
        params[0]["data"]
        for method, params in rpc.calls
        if method == "eth_call" and params[0]["data"].startswith(
            "0x" + keccak(text="nonces(bytes32)")[:4].hex()
        )
    ]
    assert ["0x" + calldata[10:74] for calldata in nonce_calls] == [
        first_hash,
        first_hash,
        first_hash,
        first_hash,
        second_hash,
    ]


@pytest.mark.parametrize(
    ("settings_overrides", "rpc_overrides"),
    [
        ({"escrow_chain_id": "1"}, {}),
        ({}, {"chain_id": 1}),
        ({"escrow_signer_private_key": "0x" + "55" * 32}, {}),
        ({"escrow_rpc_url": "http://example.test:8545"}, {}),
        ({"escrow_rpc_url": "https://127.0.0.1:8545"}, {}),
        ({"escrow_address": "not-an-address"}, {}),
        ({"escrow_chain_id": "thirty-one"}, {}),
        ({"escrow_signer_private_key": "not-a-key"}, {}),
    ],
)
def test_invalid_chain_or_signer_configuration_fails_closed(
    settings_overrides: dict[str, Any], rpc_overrides: dict[str, Any]
) -> None:
    chain = _chain_module()
    rpc = FakeJsonRpc(**rpc_overrides)

    with pytest.raises(chain.PermitUnavailableError):
        chain.issue_permit(
            settings=_settings(**settings_overrides),
            transport=rpc,
            reservation_id="reservation-one",
            listing_id="listing-one",
            customer_address=CUSTOMER_ADDRESS,
            agency_address=AGENCY_ADDRESS,
            actor_address=CUSTOMER_ADDRESS,
            action="deposit",
            amount=1,
            deadline=1_800_000_000,
        )


@pytest.mark.parametrize(
    ("action", "actor_address"),
    [
        ("deposit", AGENCY_ADDRESS),
        ("accept", CUSTOMER_ADDRESS),
        ("reject", CUSTOMER_ADDRESS),
        ("cancel", "0x" + "55" * 20),
    ],
)
def test_action_signer_is_bound_to_contract_actor_role(
    action: str, actor_address: str
) -> None:
    chain = _chain_module()
    rpc = FakeJsonRpc()

    with pytest.raises(chain.PermitUnavailableError):
        chain.issue_permit(
            settings=_settings(),
            transport=rpc,
            reservation_id="reservation-one",
            listing_id="listing-one",
            customer_address=CUSTOMER_ADDRESS,
            agency_address=AGENCY_ADDRESS,
            actor_address=actor_address,
            action=action,
            amount=1,
            deadline=1_800_000_000,
        )

    assert rpc.calls == []


def test_absent_or_partial_escrow_environment_is_allowed_until_permit_use(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    chain = _chain_module()
    for name, value in {
        "DATABASE_URL": "sqlite+pysqlite:///:memory:",
        "JWT_SECRET": "reservation-chain-test-secret-at-least-32-bytes",
        "STAFF_TOTP_ENCRYPTION_KEY": base64.urlsafe_b64encode(b"x" * 32).decode(),
        "STAFF_WEB_ORIGIN": "https://panel.example.test",
    }.items():
        monkeypatch.setenv(name, value)
    for name in (
        "ROOMFORGE_ESCROW_RPC_URL",
        "ROOMFORGE_ESCROW_ADDRESS",
        "ROOMFORGE_ESCROW_CHAIN_ID",
        "ROOMFORGE_ESCROW_SIGNER_PRIVATE_KEY",
    ):
        monkeypatch.delenv(name, raising=False)

    settings = Settings.from_env()
    settings.validate()
    assert settings.escrow_rpc_url is None
    missing_rpc = FakeJsonRpc()

    with pytest.raises(chain.PermitUnavailableError):
        chain.issue_permit(
            settings=settings,
            transport=missing_rpc,
            reservation_id="reservation-one",
            listing_id="listing-one",
            customer_address=CUSTOMER_ADDRESS,
            agency_address=AGENCY_ADDRESS,
            actor_address=CUSTOMER_ADDRESS,
            action="deposit",
            amount=1,
            deadline=1_800_000_000,
        )
    assert missing_rpc.calls == []

    monkeypatch.setenv("ROOMFORGE_ESCROW_RPC_URL", "https://rpc.example.test")
    monkeypatch.setenv("ROOMFORGE_ESCROW_ADDRESS", "malformed")
    monkeypatch.setenv("ROOMFORGE_ESCROW_CHAIN_ID", "thirty-one")
    monkeypatch.setenv("ROOMFORGE_ESCROW_SIGNER_PRIVATE_KEY", "not-a-key")
    malformed_settings = Settings.from_env()
    malformed_settings.validate()
    assert malformed_settings.escrow_chain_id == "thirty-one"
    malformed_rpc = FakeJsonRpc()
    with pytest.raises(chain.PermitUnavailableError):
        chain.issue_permit(
            settings=malformed_settings,
            transport=malformed_rpc,
            reservation_id="reservation-one",
            listing_id="listing-one",
            customer_address=CUSTOMER_ADDRESS,
            agency_address=AGENCY_ADDRESS,
            actor_address=CUSTOMER_ADDRESS,
            action="deposit",
            amount=1,
            deadline=1_800_000_000,
        )
    assert malformed_rpc.calls == []


def test_invalid_local_rpc_configuration_is_rejected_before_transport_call() -> None:
    chain = _chain_module()
    rpc = FakeJsonRpc()

    with pytest.raises(chain.PermitUnavailableError):
        chain.issue_permit(
            settings=_settings(escrow_rpc_url="http://localhost.evil.test:8545"),
            transport=rpc,
            reservation_id="reservation-one",
            listing_id="listing-one",
            customer_address=CUSTOMER_ADDRESS,
            agency_address=AGENCY_ADDRESS,
            actor_address=CUSTOMER_ADDRESS,
            action="deposit",
            amount=1,
            deadline=1_800_000_000,
        )

    assert rpc.calls == []
