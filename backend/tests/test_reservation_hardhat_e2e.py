"""Wallet reservations reconciled against a real local Hardhat escrow (F09.5-F09.6).

The other chain tests swap the JSON-RPC transport for fakes, so nothing proved the
backend and ``ReservationEscrow.sol`` agree on calldata, events and nonces. These
tests send real transactions from the Hardhat test accounts and reconcile the real
receipts through the API, then read token balances to observe where the deposit went.

They skip unless ``ROOMFORGE_HARDHAT_DEPLOYMENT`` points at the JSON printed by
``contracts/scripts/deploy-local.ts`` for a running node. Each test runs inside an
``evm_snapshot``/``evm_revert`` pair, so the node is left as it was deployed.
"""

from __future__ import annotations

import json
import os
import urllib.request
from collections.abc import Iterator
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any, cast
from urllib.parse import urlsplit

import pytest
from eth_abi.abi import encode
from eth_account import Account
from eth_utils.crypto import keccak

from app.modules.agencies.models import AgencyWallet
from app.modules.customer_identity.models import CustomerWallet
from app.modules.reservations.models import Reservation
from test_reservations import (
    ReservationsContext,
    _create_reservation,
    _customer_auth,
    _seed_reservation_inputs,
    _use_staff_principal,
)
from test_reservations import reservations_context as _reservations_context
from testclient_app import client_app

# Default key of Hardhat account #0, which deploy-local.ts uses as the escrow signer.
# It is a public development key with no value outside a local node.
HARDHAT_SIGNER_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
DEPOSIT = Decimal("1000.00")
DEPOSIT_UNITS = 100_000  # BOB uses two token decimals.
ACTION_TUPLE = "(bytes32,bytes32,address,address,address,uint8,uint256,uint64,uint256)"


def _deployment() -> dict[str, Any]:
    path = os.environ.get("ROOMFORGE_HARDHAT_DEPLOYMENT")
    if not path:
        pytest.skip("ROOMFORGE_HARDHAT_DEPLOYMENT is not set; no local Hardhat escrow to test against.")
    deployment = json.loads(Path(path).read_text(encoding="utf-8"))
    rpc = urlsplit(deployment["rpc_url"])
    if rpc.scheme != "http" or rpc.hostname not in {"127.0.0.1", "localhost"}:
        pytest.fail("The Hardhat deployment must point at a loopback node.")
    if Account.from_key(HARDHAT_SIGNER_KEY).address != deployment["accounts"]["backend_signer"]:
        pytest.fail("The escrow signer is not Hardhat account #0; redeploy on a fresh node.")
    return deployment


@dataclass
class HardhatChain:
    rpc_url: str
    contracts: dict[str, str]
    accounts: dict[str, str]

    def rpc(self, method: str, params: list[Any]) -> Any:
        request = urllib.request.Request(
            self.rpc_url,
            data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
            headers={"Content-Type": "application/json"},
        )
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request, timeout=10) as response:
            body = json.loads(response.read())
        if "error" in body:
            raise AssertionError(f"{method} failed: {body['error']}")
        return body["result"]

    def send(self, sender: str, to: str, data: bytes) -> str:
        """Send from an unlocked account; Hardhat mines it at once, so require success."""
        tx_hash = self.rpc("eth_sendTransaction", [{"from": sender, "to": to, "data": "0x" + data.hex()}])
        receipt = self.rpc("eth_getTransactionReceipt", [tx_hash])
        assert receipt is not None and receipt["status"] == "0x1", receipt
        return tx_hash

    def balance(self, owner: str) -> int:
        data = keccak(text="balanceOf(address)")[:4] + encode(["address"], [owner])
        return int(self.rpc("eth_call", [{"to": self.contracts["rft"], "data": "0x" + data.hex()}, "latest"]), 16)

    def escrow_nonce(self, reservation_id: bytes) -> int:
        data = keccak(text="nonces(bytes32)")[:4] + encode(["bytes32"], [reservation_id])
        return int(
            self.rpc("eth_call", [{"to": self.contracts["escrow_bob"], "data": "0x" + data.hex()}, "latest"]),
            16,
        )

    def mine_and_read_time(self) -> datetime:
        # Mining first captures any time offset left by evm_increaseTime.
        self.rpc("evm_mine", [])
        block = self.rpc("eth_getBlockByNumber", ["latest", False])
        return datetime.fromtimestamp(int(block["timestamp"], 16), tz=timezone.utc)


@dataclass
class ChainContext:
    context: ReservationsContext
    chain: HardhatChain

    @property
    def customer(self) -> str:
        return self.chain.accounts["customer_wallet"]

    @property
    def agency(self) -> str:
        return self.chain.accounts["agency_wallet"]

    @property
    def escrow(self) -> str:
        return self.chain.contracts["escrow_bob"]


@pytest.fixture
def chain_context() -> Iterator[ChainContext]:
    deployment = _deployment()
    chain = HardhatChain(deployment["rpc_url"], deployment["contracts"], deployment["accounts"])
    snapshot = chain.rpc("evm_snapshot", [])
    context_generator = cast(Any, _reservations_context).__wrapped__()
    context: ReservationsContext = next(context_generator)
    try:
        app = client_app(context.client)
        app.state.settings = replace(
            app.state.settings,
            escrow_rpc_url=deployment["rpc_url"],
            escrow_address=chain.contracts["escrow_bob"],
            escrow_bob_address=chain.contracts["escrow_bob"],
            escrow_usd_address=chain.contracts["escrow_usd"],
            escrow_usdt_address=chain.contracts["escrow_usdt"],
            escrow_chain_id="31337",
            escrow_signer_private_key=HARDHAT_SIGNER_KEY,
        )
        # The API and the escrow must share one clock: deadlines are signed from it.
        context.clock.now = chain.mine_and_read_time()
        yield ChainContext(context, chain)
    finally:
        try:
            next(context_generator, None)
        finally:
            assert chain.rpc("evm_revert", [snapshot]) is True


def _open_reservation(ctx: ChainContext, *, listing_id: str) -> tuple[dict[str, Any], dict[str, str]]:
    customer_id, auth = _customer_auth(ctx.context, email=f"{listing_id}@example.test")
    quote_id, wallet_id = _seed_reservation_inputs(
        ctx.context, customer_id, listing_id=listing_id, deposit_amount=DEPOSIT
    )
    # The seeded wallets have no keys; bind them to the Hardhat accounts that sign.
    # Stored addresses are canonical lowercase, unlike the checksummed deployment JSON.
    with ctx.context.session_factory.begin() as session:
        session.query(AgencyWallet).filter_by(agency_id="agency-one").update({"address": ctx.agency.lower()})
        session.query(CustomerWallet).filter_by(customer_id=customer_id).update(
            {"address": ctx.customer.lower()}
        )
    response = _create_reservation(
        ctx.context, auth, listing_id=listing_id, quote_id=quote_id, wallet_id=wallet_id
    )
    assert response.status_code == 201, response.text
    return response.json(), auth


def _action_calldata(function: str, permit: dict[str, Any]) -> bytes:
    action = (
        bytes.fromhex(permit["reservationId"][2:]),
        bytes.fromhex(permit["listingId"][2:]),
        permit["customer"],
        permit["agency"],
        permit["actor"],
        permit["action"],
        permit["amount"],
        permit["deadline"],
        permit["nonce"],
    )
    selector = keccak(text=f"{function}({ACTION_TUPLE},bytes)")[:4]
    return selector + encode([ACTION_TUPLE, "bytes"], [action, bytes.fromhex(permit["signature"][2:])])


def _permit(ctx: ChainContext, reservation_id: str, action: str, auth: dict[str, str] | None) -> dict[str, Any]:
    if auth is None:
        _use_staff_principal(ctx.context)
        path = f"/api/v1/staff/reservations/{reservation_id}/permit"
    else:
        path = f"/api/v1/reservations/{reservation_id}/permit"
    response = ctx.context.client.post(path, headers=auth or {}, json={"action": action})
    assert response.status_code == 200, response.text
    return response.json()


def _reconcile(
    ctx: ChainContext,
    reservation_id: str,
    *,
    action: str,
    tx_hash: str,
    nonce: int,
    auth: dict[str, str] | None,
):
    prefix = "/api/v1/staff/reservations" if auth is None else "/api/v1/reservations"
    return ctx.context.client.post(
        f"{prefix}/{reservation_id}/chain-transactions",
        headers=auth or {},
        json={"action": action, "transaction_hash": tx_hash, "nonce": nonce},
    )


def _approve(ctx: ChainContext, amount: int) -> str:
    data = keccak(text="approve(address,uint256)")[:4] + encode(["address", "uint256"], [ctx.escrow, amount])
    return ctx.chain.send(ctx.customer, ctx.chain.contracts["rft"], data)


def _deposit(ctx: ChainContext, reservation: dict[str, Any], auth: dict[str, str]) -> tuple[str, int]:
    reservation_id = reservation["reservation_id"]
    permit = _permit(ctx, reservation_id, "deposit", auth)
    assert permit["amount"] == DEPOSIT_UNITS
    _approve(ctx, permit["amount"])
    tx_hash = ctx.chain.send(ctx.customer, ctx.escrow, _action_calldata("deposit", permit))
    reconciled = _reconcile(ctx, reservation_id, action="deposit", tx_hash=tx_hash, nonce=permit["nonce"], auth=auth)
    assert reconciled.status_code == 200, reconciled.text
    assert reconciled.json()["event_name"] == "Deposited"
    assert reconciled.json()["status"] == "pending"
    assert reconciled.json()["replayed"] is False
    return tx_hash, permit["nonce"]


def _stored(ctx: ChainContext, reservation_id: str) -> Reservation:
    with ctx.context.session_factory() as session:
        reservation = session.get(Reservation, reservation_id)
        assert reservation is not None
        return reservation


def test_deposit_moves_tokens_into_escrow_and_confirms_once(chain_context: ChainContext) -> None:
    ctx = chain_context
    reservation, auth = _open_reservation(ctx, listing_id="hardhat-deposit")
    customer_before = ctx.chain.balance(ctx.customer)
    escrow_before = ctx.chain.balance(ctx.escrow)

    tx_hash, nonce = _deposit(ctx, reservation, auth)

    assert ctx.chain.balance(ctx.customer) == customer_before - DEPOSIT_UNITS
    assert ctx.chain.balance(ctx.escrow) == escrow_before + DEPOSIT_UNITS
    confirmed_at = _stored(ctx, reservation["reservation_id"]).deposit_confirmed_at
    assert confirmed_at is not None

    replay = _reconcile(
        ctx, reservation["reservation_id"], action="deposit", tx_hash=tx_hash, nonce=nonce, auth=auth
    )
    assert replay.status_code == 200, replay.text
    assert replay.json()["replayed"] is True
    assert _stored(ctx, reservation["reservation_id"]).deposit_confirmed_at == confirmed_at
    assert ctx.chain.balance(ctx.escrow) == escrow_before + DEPOSIT_UNITS


def test_a_transaction_without_the_deposit_event_never_confirms_the_reservation(
    chain_context: ChainContext,
) -> None:
    ctx = chain_context
    reservation, auth = _open_reservation(ctx, listing_id="hardhat-wrong-event")
    permit = _permit(ctx, reservation["reservation_id"], "deposit", auth)
    approve_hash = _approve(ctx, permit["amount"])

    rejected = _reconcile(
        ctx,
        reservation["reservation_id"],
        action="deposit",
        tx_hash=approve_hash,
        nonce=permit["nonce"],
        auth=auth,
    )

    assert rejected.status_code in {409, 422}, rejected.text
    stored = _stored(ctx, reservation["reservation_id"])
    assert stored.status == "pending"
    assert stored.deposit_confirmed_at is None


def test_accept_releases_the_deposit_to_the_agency_wallet(chain_context: ChainContext) -> None:
    ctx = chain_context
    reservation, auth = _open_reservation(ctx, listing_id="hardhat-accept")
    _deposit(ctx, reservation, auth)
    customer_before = ctx.chain.balance(ctx.customer)
    agency_before = ctx.chain.balance(ctx.agency)

    permit = _permit(ctx, reservation["reservation_id"], "accept", None)
    tx_hash = ctx.chain.send(ctx.agency, ctx.escrow, _action_calldata("accept", permit))
    reconciled = _reconcile(
        ctx, reservation["reservation_id"], action="accept", tx_hash=tx_hash, nonce=permit["nonce"], auth=None
    )

    assert reconciled.status_code == 200, reconciled.text
    assert reconciled.json()["event_name"] == "Accepted"
    assert reconciled.json()["status"] == "accepted"
    assert _stored(ctx, reservation["reservation_id"]).status == "accepted"
    assert ctx.chain.balance(ctx.agency) == agency_before + DEPOSIT_UNITS
    assert ctx.chain.balance(ctx.customer) == customer_before
    assert ctx.chain.balance(ctx.escrow) == 0


def test_reject_refunds_the_customer(chain_context: ChainContext) -> None:
    ctx = chain_context
    reservation, auth = _open_reservation(ctx, listing_id="hardhat-reject")
    _deposit(ctx, reservation, auth)
    customer_before = ctx.chain.balance(ctx.customer)
    agency_before = ctx.chain.balance(ctx.agency)

    permit = _permit(ctx, reservation["reservation_id"], "reject", None)
    tx_hash = ctx.chain.send(ctx.agency, ctx.escrow, _action_calldata("reject", permit))
    reconciled = _reconcile(
        ctx, reservation["reservation_id"], action="reject", tx_hash=tx_hash, nonce=permit["nonce"], auth=None
    )

    assert reconciled.status_code == 200, reconciled.text
    assert reconciled.json()["event_name"] == "Rejected"
    assert reconciled.json()["status"] == "rejected"
    assert _stored(ctx, reservation["reservation_id"]).status == "rejected"
    assert ctx.chain.balance(ctx.customer) == customer_before + DEPOSIT_UNITS
    assert ctx.chain.balance(ctx.agency) == agency_before
    assert ctx.chain.balance(ctx.escrow) == 0


def test_customer_cancellation_refunds_the_customer(chain_context: ChainContext) -> None:
    ctx = chain_context
    reservation, auth = _open_reservation(ctx, listing_id="hardhat-cancel")
    _deposit(ctx, reservation, auth)
    customer_before = ctx.chain.balance(ctx.customer)

    permit = _permit(ctx, reservation["reservation_id"], "cancel", auth)
    tx_hash = ctx.chain.send(ctx.customer, ctx.escrow, _action_calldata("cancel", permit))
    reconciled = _reconcile(
        ctx, reservation["reservation_id"], action="cancel", tx_hash=tx_hash, nonce=permit["nonce"], auth=auth
    )

    assert reconciled.status_code == 200, reconciled.text
    assert reconciled.json()["event_name"] == "Cancelled"
    assert reconciled.json()["status"] == "cancelled"
    assert _stored(ctx, reservation["reservation_id"]).status == "cancelled"
    assert ctx.chain.balance(ctx.customer) == customer_before + DEPOSIT_UNITS
    assert ctx.chain.balance(ctx.escrow) == 0


def test_expiry_after_the_deadline_refunds_the_customer(chain_context: ChainContext) -> None:
    ctx = chain_context
    reservation, auth = _open_reservation(ctx, listing_id="hardhat-expire")
    _deposit(ctx, reservation, auth)
    customer_before = ctx.chain.balance(ctx.customer)
    chain_reservation_id = keccak(text=reservation["reservation_id"])

    # The 24-hour decision window has to pass on chain; the escrow reads block time.
    ctx.chain.rpc("evm_increaseTime", [24 * 60 * 60 + 1])
    ctx.chain.rpc("evm_mine", [])
    nonce = ctx.chain.escrow_nonce(chain_reservation_id)
    data = keccak(text="expire(bytes32)")[:4] + encode(["bytes32"], [chain_reservation_id])
    tx_hash = ctx.chain.send(ctx.customer, ctx.escrow, data)
    reconciled = _reconcile(
        ctx, reservation["reservation_id"], action="expire", tx_hash=tx_hash, nonce=nonce, auth=auth
    )

    assert reconciled.status_code == 200, reconciled.text
    assert reconciled.json()["event_name"] == "Expired"
    assert reconciled.json()["status"] == "expired"
    assert _stored(ctx, reservation["reservation_id"]).status == "expired"
    assert ctx.chain.balance(ctx.customer) == customer_before + DEPOSIT_UNITS
    assert ctx.chain.balance(ctx.escrow) == 0
