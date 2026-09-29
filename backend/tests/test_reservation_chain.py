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
        code: str = "0x6000",
        transactions: dict[str, Any] | None = None,
        receipts: dict[str, Any] | None = None,
        blocks: dict[str, Any] | None = None,
    ) -> None:
        self.signer = signer
        self.chain_id = chain_id
        self.nonces = nonces or {}
        self.code = code
        self.transactions = transactions or {}
        self.receipts = receipts or {}
        self.blocks = blocks or {}
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
            return self.code
        if method == "eth_getTransactionByHash":
            return self.transactions.get(params[0].lower(), self.transactions.get(params[0]))
        if method == "eth_getTransactionReceipt":
            return self.receipts.get(params[0].lower(), self.receipts.get(params[0]))
        if method == "eth_getBlockByNumber":
            assert params[1] is False
            return self.blocks.get(params[0])
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


_DEADLINE = datetime(2030, 1, 1, tzinfo=timezone.utc)
_DEADLINE_SECONDS = 1_893_456_000
_TX_HASH = "0x" + "cc" * 32
_BLOCK_HASH = "0x" + "dd" * 32
_TOKEN_ADDRESS = "0x" + "55" * 20
_OUTSIDER_ADDRESS = "0x" + "99" * 20
_RESERVATION_ID = "reservation-one"
_LISTING_ID = "listing-one"
_OTHER_HASH = "0x" + "ab" * 32
_EVENT_BY_ACTION = {
    "deposit": "Deposited",
    "accept": "Accepted",
    "reject": "Rejected",
    "cancel": "Cancelled",
    "expire": "Expired",
}
_PARTICIPANT_BY_ACTION = {
    "deposit": CUSTOMER_ADDRESS,
    "accept": AGENCY_ADDRESS,
    "reject": CUSTOMER_ADDRESS,
    "cancel": CUSTOMER_ADDRESS,
    "expire": CUSTOMER_ADDRESS,
}
_SENDER_BY_ACTION = {
    "deposit": CUSTOMER_ADDRESS,
    "accept": AGENCY_ADDRESS,
    "reject": AGENCY_ADDRESS,
    "cancel": CUSTOMER_ADDRESS,
    "expire": _OUTSIDER_ADDRESS,
}


def _event_topic(event: str) -> str:
    return "0x" + keccak(text=f"{event}(bytes32,bytes32,address,uint256,uint256)").hex()


def _address_topic(address: str) -> str:
    return "0x" + "0" * 24 + address[2:].lower()


def _word(value: int) -> str:
    return hex(value)[2:].rjust(64, "0")


def _escrow_log(
    event: str,
    participant: str,
    amount: int,
    nonce: int,
    *,
    address: str = ESCROW_ADDRESS,
    reservation_hash: str = "0x" + keccak(text=_RESERVATION_ID).hex(),
    listing_hash: str = "0x" + keccak(text=_LISTING_ID).hex(),
    data: str | None = None,
    log_index: int = 0,
) -> dict[str, Any]:
    return {
        "address": address,
        "topics": [
            _event_topic(event),
            reservation_hash,
            listing_hash,
            _address_topic(participant),
        ],
        "data": data if data is not None else "0x" + _word(amount) + _word(nonce),
        "logIndex": hex(log_index),
        "transactionIndex": "0x0",
    }


def _token_transfer_log(amount: int = 3842) -> dict[str, Any]:
    return {
        "address": _TOKEN_ADDRESS,
        "topics": [
            "0x" + keccak(text="Transfer(address,address,uint256)").hex(),
            _address_topic(CUSTOMER_ADDRESS),
            _address_topic(ESCROW_ADDRESS),
        ],
        "data": "0x" + _word(amount),
        "logIndex": "0x1",
        "transactionIndex": "0x0",
    }


def _receipt_case(
    action: str = "deposit",
    *,
    event: str | None = None,
    sender: str | None = None,
    participant: str | None = None,
    actor: str | None = None,
    amount: int = 3842,
    expected_amount: int | None = None,
    nonce: int = 7,
    expected_nonce: int | None = None,
    timestamp: int = _DEADLINE_SECONDS - 1,
    logs: list[Any] | None = None,
    extra_logs: tuple[Any, ...] = (),
    status: Any = "0x1",
    transaction_block_number: Any = 12,
    receipt_block_number: Any = 12,
    tx_hash: str = _TX_HASH,
    receipt_tx_hash: str | None = None,
    tx_to: str = ESCROW_ADDRESS,
    chain_id: int = 31337,
    code: str = "0x6000",
    include_transaction: bool = True,
    include_receipt: bool = True,
    include_block: bool = True,
    block_number_key: int = 12,
    block_number_value: int | None = None,
    submitted_hash: str | None = None,
) -> tuple[dict[str, Any], FakeJsonRpc]:
    resolved_event = event or _EVENT_BY_ACTION[action]
    resolved_participant = participant or _PARTICIPANT_BY_ACTION[action]
    resolved_sender = sender or _SENDER_BY_ACTION[action]
    escrow_logs = (
        list(logs)
        if logs is not None
        else [_escrow_log(resolved_event, resolved_participant, amount, nonce), *extra_logs]
    )
    transaction = {
        "hash": tx_hash,
        "from": resolved_sender,
        "to": tx_to,
        "blockNumber": None if transaction_block_number is None else hex(transaction_block_number),
        "blockHash": _BLOCK_HASH,
        "transactionIndex": "0x0",
    }
    receipt = {
        "transactionHash": receipt_tx_hash or tx_hash,
        "status": status,
        "blockNumber": None if receipt_block_number is None else hex(receipt_block_number),
        "blockHash": _BLOCK_HASH,
        "logs": escrow_logs,
        "transactionIndex": "0x0",
    }
    block = {
        "number": hex(block_number_key if block_number_value is None else block_number_value),
        "hash": _BLOCK_HASH,
        "timestamp": hex(timestamp),
    }
    rpc = FakeJsonRpc(
        chain_id=chain_id,
        code=code,
        transactions={tx_hash.lower(): transaction} if include_transaction else {},
        receipts={tx_hash.lower(): receipt} if include_receipt else {},
        blocks={hex(block_number_key): block} if include_block else {},
    )
    kwargs: dict[str, Any] = {
        "settings": _settings(),
        "transport": rpc,
        "transaction_hash": submitted_hash if submitted_hash is not None else tx_hash,
        "reservation_id": _RESERVATION_ID,
        "listing_id": _LISTING_ID,
        "customer_address": CUSTOMER_ADDRESS,
        "agency_address": AGENCY_ADDRESS,
        "action": action,
        "amount": amount if expected_amount is None else expected_amount,
        "nonce": nonce if expected_nonce is None else expected_nonce,
        "deadline": _DEADLINE,
    }
    if actor is not None:
        kwargs["actor_address"] = actor
    return kwargs, rpc


_PROOF_FIELDS = {
    "chainId",
    "escrowAddress",
    "action",
    "event",
    "eventSignature",
    "topic",
    "transactionHash",
    "blockNumber",
    "blockHash",
    "blockTimestamp",
    "transactionIndex",
    "logIndex",
    "reservationId",
    "listingId",
    "participant",
    "actor",
    "amount",
    "nonce",
    "contractDeadline",
}


@pytest.mark.parametrize(
    ("action", "event", "sender", "participant", "actor", "amount", "timestamp"),
    [
        ("deposit", "Deposited", CUSTOMER_ADDRESS, CUSTOMER_ADDRESS, None, 3842, _DEADLINE_SECONDS - 1),
        ("accept", "Accepted", AGENCY_ADDRESS, AGENCY_ADDRESS, AGENCY_ADDRESS, 3842, _DEADLINE_SECONDS - 1),
        ("accept", "Accepted", AGENCY_ADDRESS, AGENCY_ADDRESS, AGENCY_ADDRESS, 0, _DEADLINE_SECONDS - 1),
        ("reject", "Rejected", AGENCY_ADDRESS, CUSTOMER_ADDRESS, AGENCY_ADDRESS, 3842, _DEADLINE_SECONDS - 1),
        ("reject", "Rejected", AGENCY_ADDRESS, CUSTOMER_ADDRESS, AGENCY_ADDRESS, 0, _DEADLINE_SECONDS - 1),
        ("cancel", "Cancelled", CUSTOMER_ADDRESS, CUSTOMER_ADDRESS, CUSTOMER_ADDRESS, 0, _DEADLINE_SECONDS - 1),
        ("cancel", "Cancelled", AGENCY_ADDRESS, AGENCY_ADDRESS, AGENCY_ADDRESS, 0, _DEADLINE_SECONDS - 1),
        ("expire", "Expired", _OUTSIDER_ADDRESS, CUSTOMER_ADDRESS, None, 0, _DEADLINE_SECONDS),
        ("expire", "Expired", CUSTOMER_ADDRESS, CUSTOMER_ADDRESS, None, 3842, _DEADLINE_SECONDS + 60),
    ],
)
def test_receipt_verifier_accepts_expected_local_escrow_events(
    action: str,
    event: str,
    sender: str,
    participant: str,
    actor: str | None,
    amount: int,
    timestamp: int,
) -> None:
    chain = _chain_module()
    kwargs, rpc = _receipt_case(
        action,
        event=event,
        sender=sender,
        participant=participant,
        actor=actor,
        amount=amount,
        timestamp=timestamp,
    )

    proof = chain.verify_action_receipt(**kwargs)

    assert set(proof) == _PROOF_FIELDS
    assert [method for method, _params in rpc.calls] == [
        "eth_chainId",
        "eth_getCode",
        "eth_getTransactionByHash",
        "eth_getTransactionReceipt",
        "eth_getBlockByNumber",
    ]
    assert proof["chainId"] == 31337
    assert proof["escrowAddress"] == to_checksum_address(ESCROW_ADDRESS)
    assert proof["action"] == action
    assert proof["event"] == event
    assert proof["eventSignature"] == f"{event}(bytes32,bytes32,address,uint256,uint256)"
    assert proof["topic"] == _event_topic(event)
    assert proof["transactionHash"] == _TX_HASH
    assert proof["blockNumber"] == 12
    assert proof["blockHash"] == _BLOCK_HASH
    assert proof["blockTimestamp"] == timestamp
    assert proof["reservationId"] == chain.hash_api_id(_RESERVATION_ID)
    assert proof["listingId"] == chain.hash_api_id(_LISTING_ID)
    assert proof["participant"] == to_checksum_address(participant)
    assert proof["amount"] == amount
    assert proof["nonce"] == 7
    assert proof["contractDeadline"] == _DEADLINE_SECONDS


def test_receipt_verifier_ignores_unrelated_token_transfer_logs() -> None:
    chain = _chain_module()
    kwargs, _rpc = _receipt_case(extra_logs=(_token_transfer_log(),))

    proof = chain.verify_action_receipt(**kwargs)

    assert proof["event"] == "Deposited"


@pytest.mark.parametrize(
    "submitted_hash",
    [
        "0x",
        "",
        "0x" + "cc" * 31,
        "0x" + "cc" * 33,
        "deadline",
        "0x" + "zz" * 32,
        1234,
        None,
    ],
)
def test_receipt_verifier_rejects_malformed_transaction_hash(submitted_hash: Any) -> None:
    chain = _chain_module()
    kwargs, rpc = _receipt_case()

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**{**kwargs, "transaction_hash": submitted_hash})

    assert rpc.calls == []


@pytest.mark.parametrize("action", ["release", "", None, 0, "Deposited"])
def test_receipt_verifier_rejects_unknown_expected_action(action: Any) -> None:
    chain = _chain_module()
    kwargs, rpc = _receipt_case()

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**{**kwargs, "action": action})

    assert rpc.calls == []


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("amount", -1),
        ("amount", 2**256),
        ("amount", "3842"),
        ("amount", True),
        ("nonce", -1),
        ("nonce", 2**256),
        ("nonce", "7"),
        ("nonce", False),
        ("deadline", 1_893_456_000),
        ("deadline", None),
        ("reservation_id", None),
        ("reservation_id", ""),
        ("listing_id", ""),
    ],
)
def test_receipt_verifier_rejects_malformed_expected_context(field: str, value: Any) -> None:
    chain = _chain_module()
    kwargs, rpc = _receipt_case()

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**{**kwargs, field: value})

    assert rpc.calls == []


def test_receipt_verifier_rejects_non_loopback_configuration_before_rpc() -> None:
    chain = _chain_module()
    kwargs, rpc = _receipt_case()

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(
            **{
                **kwargs,
                "settings": _settings(
                    escrow_chain_id="1", escrow_rpc_url="http://example.test:8545"
                ),
            }
        )

    assert rpc.calls == []


def test_receipt_verifier_rejects_wrong_chain_id() -> None:
    chain = _chain_module()
    kwargs, _rpc = _receipt_case(chain_id=1)

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_rejects_absent_contract_code() -> None:
    chain = _chain_module()
    kwargs, _rpc = _receipt_case(code="0x")

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


@pytest.mark.parametrize(
    ("include_transaction", "include_receipt"),
    [(False, True), (True, False), (False, False)],
)
def test_receipt_verifier_rejects_missing_transaction_or_receipt(
    include_transaction: bool, include_receipt: bool
) -> None:
    chain = _chain_module()
    kwargs, _rpc = _receipt_case(
        include_transaction=include_transaction,
        include_receipt=include_receipt,
    )

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_rejects_transaction_hash_mismatch() -> None:
    chain = _chain_module()
    mismatch_kwargs, _rpc = _receipt_case(receipt_tx_hash=_OTHER_HASH)
    submitted_mismatch_kwargs, _submitted_rpc = _receipt_case(
        tx_hash=_OTHER_HASH, submitted_hash=_TX_HASH
    )

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**mismatch_kwargs)
    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**submitted_mismatch_kwargs)


@pytest.mark.parametrize(
    ("status", "receipt_block_number"),
    [("0x0", 12), ("0x1", None), ("1", 12), (None, 12)],
)
def test_receipt_verifier_rejects_unmined_or_failed_receipt(
    status: Any, receipt_block_number: Any
) -> None:
    chain = _chain_module()
    kwargs, _rpc = _receipt_case(status=status, receipt_block_number=receipt_block_number)

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_rejects_block_number_mismatch_or_absent_block() -> None:
    chain = _chain_module()
    mismatch_kwargs, _rpc = _receipt_case(receipt_block_number=13)
    missing_kwargs, _missing_rpc = _receipt_case(include_block=False)
    misreported_kwargs, _misreported_rpc = _receipt_case(block_number_value=13)

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**mismatch_kwargs)
    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**missing_kwargs)
    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**misreported_kwargs)


def test_receipt_verifier_rejects_missing_transaction_block_hash() -> None:
    chain = _chain_module()
    kwargs, rpc = _receipt_case()
    del rpc.transactions[_TX_HASH]["blockHash"]

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_rejects_missing_receipt_block_hash() -> None:
    chain = _chain_module()
    kwargs, rpc = _receipt_case()
    del rpc.receipts[_TX_HASH]["blockHash"]

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_rejects_transaction_receipt_block_hash_mismatch() -> None:
    chain = _chain_module()
    kwargs, rpc = _receipt_case()
    rpc.receipts[_TX_HASH]["blockHash"] = "0x" + "ee" * 32

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_rejects_equal_invalid_transaction_receipt_block_hash() -> None:
    chain = _chain_module()
    kwargs, rpc = _receipt_case()
    invalid_hash = "0x" + "ee" * 31
    rpc.transactions[_TX_HASH]["blockHash"] = invalid_hash
    rpc.receipts[_TX_HASH]["blockHash"] = invalid_hash

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_rejects_queried_block_hash_mismatch_or_missing() -> None:
    chain = _chain_module()
    mismatch_kwargs, mismatch_rpc = _receipt_case()
    mismatch_rpc.blocks["0xc"]["hash"] = "0x" + "ee" * 32
    missing_kwargs, missing_rpc = _receipt_case()
    del missing_rpc.blocks["0xc"]["hash"]

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**mismatch_kwargs)
    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**missing_kwargs)


def test_receipt_verifier_requires_queried_block_header_number() -> None:
    chain = _chain_module()
    kwargs, rpc = _receipt_case()
    del rpc.blocks["0xc"]["number"]

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_rejects_wrong_target_or_sender() -> None:
    chain = _chain_module()
    foreign_target, _rpc = _receipt_case(tx_to=_TOKEN_ADDRESS)
    wrong_deposit_sender, _deposit_rpc = _receipt_case(action="deposit", sender=AGENCY_ADDRESS)
    outsider_cancel, _cancel_rpc = _receipt_case(
        action="cancel",
        sender=_OUTSIDER_ADDRESS,
        participant=_OUTSIDER_ADDRESS,
        actor=CUSTOMER_ADDRESS,
    )

    for kwargs in (foreign_target, wrong_deposit_sender, outsider_cancel):
        with pytest.raises(chain.PermitUnavailableError):
            chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_requires_the_permitted_cancel_actor() -> None:
    chain = _chain_module()
    implicit_actor, _implicit_rpc = _receipt_case(action="cancel")
    foreign_actor, _foreign_rpc = _receipt_case(
        action="cancel",
        actor=_OUTSIDER_ADDRESS,
        sender=_OUTSIDER_ADDRESS,
        participant=_OUTSIDER_ADDRESS,
    )
    agency_actor_customer_sender, _agency_rpc = _receipt_case(
        action="cancel",
        actor=AGENCY_ADDRESS,
        sender=CUSTOMER_ADDRESS,
        participant=AGENCY_ADDRESS,
    )
    accept_with_customer_actor, _accept_rpc = _receipt_case(action="accept", actor=CUSTOMER_ADDRESS)

    for kwargs in (
        implicit_actor,
        foreign_actor,
        agency_actor_customer_sender,
        accept_with_customer_actor,
    ):
        with pytest.raises(chain.PermitUnavailableError):
            chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_rejects_missing_or_foreign_escrow_event() -> None:
    chain = _chain_module()
    empty_logs, _empty_rpc = _receipt_case(logs=[])
    token_only, _token_rpc = _receipt_case(logs=[_token_transfer_log()])
    foreign_event, _foreign_rpc = _receipt_case(event="Cancelled")

    for kwargs in (empty_logs, token_only, foreign_event):
        with pytest.raises(chain.PermitUnavailableError):
            chain.verify_action_receipt(**kwargs)


@pytest.mark.parametrize(
    "mutate",
    [
        lambda log: log.update(
            topics=[log["topics"][0], _OTHER_HASH, log["topics"][2], log["topics"][3]]
        ),
        lambda log: log.update(
            topics=[log["topics"][0], log["topics"][1], _OTHER_HASH, log["topics"][3]]
        ),
        lambda log: log.update(
            topics=[
                log["topics"][0],
                log["topics"][1],
                log["topics"][2],
                _address_topic(AGENCY_ADDRESS),
            ]
        ),
        lambda log: log.update(data="0x" + _word(1) + _word(7)),
        lambda log: log.update(data="0x" + _word(3842) + _word(8)),
        lambda log: log.update(data="0x" + _word(3842)),
        lambda log: log.update(data="0x"),
        lambda log: log.update(
            topics=[log["topics"][0], "0x" + "11" * 31, log["topics"][2], log["topics"][3]]
        ),
        lambda log: log.update(
            topics=[log["topics"][0], log["topics"][1], log["topics"][2], "0x" + "11" * 32]
        ),
        lambda log: log.update(address=_TOKEN_ADDRESS),
    ],
)
def test_receipt_verifier_rejects_mismatched_event_payload(mutate: Any) -> None:
    chain = _chain_module()
    log = _escrow_log("Deposited", CUSTOMER_ADDRESS, 3842, 7)
    mutate(log)
    kwargs, _rpc = _receipt_case(logs=[log])

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_rejects_ambiguous_matching_events() -> None:
    chain = _chain_module()
    first = _escrow_log("Deposited", CUSTOMER_ADDRESS, 3842, 7)
    duplicate = _escrow_log("Deposited", CUSTOMER_ADDRESS, 3842, 7, log_index=1)
    kwargs, _rpc = _receipt_case(logs=[first, duplicate])

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


@pytest.mark.parametrize(
    "logs",
    [
        ["not-a-log"],
        [{"address": "malformed", "topics": [], "data": "0x"}],
        [{"address": ESCROW_ADDRESS, "data": "0x"}],
        [{"address": ESCROW_ADDRESS, "topics": {}, "data": "0x"}],
        [{"address": ESCROW_ADDRESS, "topics": [], "data": "0x"}],
        [
            {
                "address": ESCROW_ADDRESS,
                "topics": [_event_topic("Deposited")],
                "data": "0x",
            }
        ],
    ],
)
def test_receipt_verifier_rejects_malformed_log_entries(logs: list[Any]) -> None:
    chain = _chain_module()
    kwargs, _rpc = _receipt_case(logs=logs)

    with pytest.raises(chain.PermitUnavailableError):
        chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_enforces_the_contract_deadline_per_action() -> None:
    chain = _chain_module()
    late_signed_action, _signed_rpc = _receipt_case(action="deposit", timestamp=_DEADLINE_SECONDS)
    early_expiry, _expiry_rpc = _receipt_case(
        action="expire", timestamp=_DEADLINE_SECONDS - 1, amount=0, sender=_OUTSIDER_ADDRESS
    )

    for kwargs in (late_signed_action, early_expiry):
        with pytest.raises(chain.PermitUnavailableError):
            chain.verify_action_receipt(**kwargs)


def test_receipt_verifier_needs_no_signing_key_while_permit_issuance_still_fails_closed() -> None:
    chain = _chain_module()
    settings = _settings(escrow_signer_private_key=None)
    kwargs, _rpc = _receipt_case()
    kwargs["settings"] = settings

    proof = chain.verify_action_receipt(**kwargs)

    assert proof["event"] == "Deposited"
    with pytest.raises(chain.PermitUnavailableError):
        chain.issue_permit(
            settings=settings,
            transport=FakeJsonRpc(),
            reservation_id=_RESERVATION_ID,
            listing_id=_LISTING_ID,
            customer_address=CUSTOMER_ADDRESS,
            agency_address=AGENCY_ADDRESS,
            actor_address=CUSTOMER_ADDRESS,
            action="deposit",
            amount=1,
            deadline=_DEADLINE_SECONDS,
        )
