from __future__ import annotations

from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, cast

import pytest
from eth_utils.crypto import keccak

from app.modules.reservations import chain
from app.modules.reservations.errors import ReservationApiError
from app.modules.reservations.models import Reservation
from app.modules.reservations.service import (
    expire_unpaid_reservations,
    reconcile_chain_transaction,
)
from app.modules.reservations import models as reservation_models

from test_reservations import (
    ReservationsContext,
    reservations_context as _reservations_context,
    _configure_fake_escrow,
    _create_test_reservation,
    _create_reservation,
    _seed_reservation_inputs,
    _use_staff_principal,
)


@pytest.fixture
def reservations_context() -> Any:
    context_generator = cast(Any, _reservations_context).__wrapped__()
    context = next(context_generator)
    try:
        yield context
    finally:
        next(context_generator, None)


def _proof(
    reservation: dict[str, Any],
    *,
    action: str,
    tx_hash: str,
    amount: int,
    actor: str | None = None,
    block_timestamp: int = 1_788_350_400,
    nonce: int = 0,
) -> dict[str, Any]:
    event = chain.EVENT_BY_ACTION[action]
    signature = chain.EVENT_SIGNATURES[event]
    return {
        "chainId": 31337,
        "escrowAddress": "0x" + "2" * 40,
        "action": action,
        "event": event,
        "eventSignature": signature,
        "topic": "0x" + keccak(text=signature).hex(),
        "transactionHash": tx_hash.lower(),
        "blockNumber": 12,
        "blockHash": "0x" + "3" * 64,
        "blockTimestamp": block_timestamp,
        "transactionIndex": 0,
        "logIndex": 1,
        "reservationId": chain.hash_api_id(reservation["reservation_id"]),
        "listingId": chain.hash_api_id(reservation["listing_id"]),
        "participant": actor or "0x" + "4" * 40,
        "actor": actor,
        "amount": amount,
        "nonce": nonce,
        "contractDeadline": int(
            datetime.fromisoformat(
                reservation["decision_deadline_at"].replace("Z", "+00:00")
            ).timestamp()
        ),
    }


def _submit(
    context: ReservationsContext,
    path: str,
    auth: dict[str, str],
    *,
    action: str,
    tx_hash: str,
    nonce: int = 0,
):
    return context.client.post(
        path,
        headers=auth,
        json={"action": action, "transaction_hash": tx_hash, "nonce": nonce},
    )


def test_customer_reconciles_deposit_atomically_and_replays_without_duplicate_audit(
    reservations_context: ReservationsContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    context = reservations_context
    customer_id, auth, reservation = _create_test_reservation(
        context, listing_id="chain-deposit-listing", deposit_amount_cop=Decimal("1000.00")
    )
    tx_hash = "0x" + "1" * 64
    customer_address = "0x" + __import__("hashlib").sha256(customer_id.encode()).hexdigest()[:40]
    calls: list[dict[str, Any]] = []

    def verify(**kwargs: Any) -> dict[str, Any]:
        calls.append(kwargs)
        return _proof(
            reservation,
            action="deposit",
            tx_hash=tx_hash,
            amount=100000,
            actor=customer_address,
        )

    monkeypatch.setattr(chain, "verify_action_receipt", verify)
    path = f"/api/v1/reservations/{reservation['reservation_id']}/chain-transactions"
    first = _submit(context, path, auth, action="deposit", tx_hash=tx_hash)
    replay = _submit(context, path, auth, action="deposit", tx_hash=tx_hash)

    assert first.status_code == 200, first.text
    assert first.json()["status"] == "pending"
    assert first.json()["replayed"] is False
    assert replay.status_code == 200, replay.text
    assert replay.json()["replayed"] is True
    assert len(calls) == 1
    with context.session_factory() as session:
        stored = session.get(Reservation, reservation["reservation_id"])
        assert stored is not None and stored.status == "pending"
        assert stored.deposit_confirmed_at is not None
        assert session.query(reservation_models.ReservationChainTransaction).count() == 1


def test_reconciliation_requires_expected_actor_and_rejects_failed_proof_without_writes(
    reservations_context: ReservationsContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    context = reservations_context
    _customer_id, auth, reservation = _create_test_reservation(
        context, listing_id="chain-failed-listing"
    )
    tx_hash = "0x" + "2" * 64

    def fail(**_kwargs: Any) -> dict[str, Any]:
        raise chain.PermitUnavailableError

    monkeypatch.setattr(chain, "verify_action_receipt", fail)
    path = f"/api/v1/reservations/{reservation['reservation_id']}/chain-transactions"
    response = _submit(context, path, auth, action="deposit", tx_hash=tx_hash)

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "chain_transaction_unverified"
    with context.session_factory() as session:
        stored = session.get(Reservation, reservation["reservation_id"])
        assert stored is not None and stored.status == "pending"
        assert stored.deposit_confirmed_at is None
        assert session.query(reservation_models.ReservationChainTransaction).count() == 0


def test_staff_accepts_after_confirmed_deposit_and_accepted_stays_listing_locked(
    reservations_context: ReservationsContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    context = reservations_context
    customer_id, customer_auth, reservation = _create_test_reservation(
        context, listing_id="chain-terminal-listing"
    )
    customer_address = "0x" + __import__("hashlib").sha256(customer_id.encode()).hexdigest()[:40]
    agency_address = "0x" + "a" * 40
    deposit_hash = "0x" + "3" * 64
    accept_hash = "0x" + "4" * 64

    def verify(**kwargs: Any) -> dict[str, Any]:
        action = kwargs["action"]
        tx_hash = deposit_hash if action == "deposit" else accept_hash
        return _proof(
            reservation,
            action=action,
            tx_hash=tx_hash,
            amount=100000,
            actor=customer_address if action == "deposit" else agency_address,
            nonce=0 if action == "deposit" else 1,
        )

    monkeypatch.setattr(chain, "verify_action_receipt", verify)
    path = f"/api/v1/reservations/{reservation['reservation_id']}/chain-transactions"
    assert _submit(context, path, customer_auth, action="deposit", tx_hash=deposit_hash).status_code == 200
    _use_staff_principal(context)
    staff_path = f"/api/v1/staff/reservations/{reservation['reservation_id']}/chain-transactions"
    accepted = _submit(
        context, staff_path, {}, action="accept", tx_hash=accept_hash, nonce=1
    )
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["status"] == "accepted"

    with context.session_factory() as session:
        stored = session.get(Reservation, reservation["reservation_id"])
        assert stored is not None and stored.status == "accepted"
    quote_id, wallet_id = _seed_reservation_inputs(
        context, customer_id, listing_id="chain-terminal-listing-2", deposit_amount_cop=Decimal("1000.00")
    )
    blocked = _create_reservation(
        context,
        customer_auth,
        listing_id="chain-terminal-listing",
        quote_id=quote_id,
        wallet_id=wallet_id,
        key="new-after-accepted",
    )
    assert blocked.status_code == 409


def test_zero_deposit_first_actions_and_local_expiry_do_not_need_expired_event(
    reservations_context: ReservationsContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    context = reservations_context
    customer_id, customer_auth, cancel_reservation = _create_test_reservation(
        context,
        listing_id="chain-zero-cancel",
        email="zero-cancel@example.test",
        deposit_amount_cop=None,
    )
    _customer_id2, _customer_auth2, accept_reservation = _create_test_reservation(
        context,
        listing_id="chain-zero-accept",
        email="zero-accept@example.test",
        deposit_amount_cop=None,
    )
    agency_address = "0x" + "a" * 40
    customer_address = "0x" + __import__("hashlib").sha256(customer_id.encode()).hexdigest()[:40]

    def verify(**kwargs: Any) -> dict[str, Any]:
        return _proof(
            accept_reservation if kwargs["reservation_id"] == accept_reservation["reservation_id"] else cancel_reservation,
            action=kwargs["action"],
            tx_hash=kwargs["transaction_hash"],
            amount=0,
            actor=agency_address if kwargs["action"] == "accept" else customer_address,
        )

    monkeypatch.setattr(chain, "verify_action_receipt", verify)
    cancel_path = f"/api/v1/reservations/{cancel_reservation['reservation_id']}/chain-transactions"
    cancelled = _submit(
        context, cancel_path, customer_auth, action="cancel", tx_hash="0x" + "5" * 64
    )
    assert cancelled.status_code == 200, cancelled.text
    _use_staff_principal(context)
    accept_path = f"/api/v1/staff/reservations/{accept_reservation['reservation_id']}/chain-transactions"
    accepted = _submit(
        context, accept_path, {}, action="accept", tx_hash="0x" + "6" * 64
    )
    assert accepted.status_code == 200, accepted.text


def test_local_expiry_has_no_chain_audit_but_deposited_expiry_requires_verified_event(
    reservations_context: ReservationsContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    context = reservations_context
    _customer_id, auth, local_reservation = _create_test_reservation(
        context,
        listing_id="chain-local-expiry",
        email="local-expiry@example.test",
        deposit_amount_cop=None,
    )
    _customer_id2, auth2, chain_reservation = _create_test_reservation(
        context,
        listing_id="chain-onchain-expiry",
        email="onchain-expiry@example.test",
        deposit_amount_cop=Decimal("1000.00"),
    )
    customer_address = "0x" + __import__("hashlib").sha256(_customer_id2.encode()).hexdigest()[:40]
    deposit_hash = "0x" + "9" * 64
    expiry_hash = "0x" + "a" * 64

    def verify(**kwargs: Any) -> dict[str, Any]:
        return _proof(
            chain_reservation,
            action=kwargs["action"],
            tx_hash=kwargs["transaction_hash"],
            amount=100000 if kwargs["action"] == "expire" else 100000,
            actor=customer_address if kwargs["action"] == "deposit" else None,
            nonce=0 if kwargs["action"] == "deposit" else 1,
            block_timestamp=int(context.clock().timestamp()) + 24 * 60 * 60,
        )

    monkeypatch.setattr(chain, "verify_action_receipt", verify)
    deposit_path = f"/api/v1/reservations/{chain_reservation['reservation_id']}/chain-transactions"
    assert _submit(context, deposit_path, auth2, action="deposit", tx_hash=deposit_hash).status_code == 200
    context.clock.advance(__import__("datetime").timedelta(hours=24))
    refreshed = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "onchain-expiry@example.test", "password": "password"},
    )
    assert refreshed.status_code == 200
    auth2 = {"Authorization": f"Bearer {refreshed.json()['access_token']}"}
    expired_path = f"/api/v1/reservations/{chain_reservation['reservation_id']}/chain-transactions"
    expired = _submit(context, expired_path, auth2, action="expire", tx_hash=expiry_hash, nonce=1)
    assert expired.status_code == 200, expired.text
    assert expired.json()["status"] == "expired"

    local_context = context
    local_context.clock.now = datetime.fromisoformat(
        local_reservation["decision_deadline_at"].replace("Z", "+00:00")
    )
    assert expire_unpaid_reservations(
        session_factory=local_context.session_factory,
        now=local_context.clock(),
        listing_id=local_reservation["listing_id"],
    ) == 1
    with context.session_factory() as session:
        local = session.get(Reservation, local_reservation["reservation_id"])
        assert local is not None and local.status == "expired"
        assert session.query(reservation_models.ReservationChainTransaction).count() == 2


def test_same_hash_cannot_be_reused_for_another_reservation(
    reservations_context: ReservationsContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    context = reservations_context
    first_customer, first_auth, first = _create_test_reservation(
        context, listing_id="chain-hash-one", email="hash-one@example.test"
    )
    _second_customer, second_auth, second = _create_test_reservation(
        context, listing_id="chain-hash-two", email="hash-two@example.test"
    )
    tx_hash = "0x" + "7" * 64

    def verify(**kwargs: Any) -> dict[str, Any]:
        return _proof(
            first if kwargs["reservation_id"] == first["reservation_id"] else second,
            action="deposit",
            tx_hash=tx_hash,
            amount=100000,
            actor="0x" + __import__("hashlib").sha256(first_customer.encode()).hexdigest()[:40],
        )

    monkeypatch.setattr(chain, "verify_action_receipt", verify)
    first_path = f"/api/v1/reservations/{first['reservation_id']}/chain-transactions"
    second_path = f"/api/v1/reservations/{second['reservation_id']}/chain-transactions"
    assert _submit(context, first_path, first_auth, action="deposit", tx_hash=tx_hash).status_code == 200
    conflict = _submit(context, second_path, second_auth, action="deposit", tx_hash=tx_hash)
    assert conflict.status_code == 409, conflict.text
    assert conflict.json()["code"] == "chain_transaction_reused"
    with context.session_factory() as session:
        assert session.query(reservation_models.ReservationChainTransaction).count() == 1
        stored = session.get(Reservation, second["reservation_id"])
        assert stored is not None and stored.status == "pending"


def test_positive_decision_without_confirmed_deposit_and_agent_are_rejected(
    reservations_context: ReservationsContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    context = reservations_context
    _customer_id, _auth, reservation = _create_test_reservation(
        context, listing_id="chain-decision-guard"
    )
    called = False

    def verify(**_kwargs: Any) -> dict[str, Any]:
        nonlocal called
        called = True
        raise AssertionError("verification must not run for an ineligible decision")

    monkeypatch.setattr(chain, "verify_action_receipt", verify)
    _use_staff_principal(context, role="agent", tenant_id="agency-one")
    path = f"/api/v1/staff/reservations/{reservation['reservation_id']}/chain-transactions"
    agent = _submit(context, path, {}, action="accept", tx_hash="0x" + "8" * 64)
    assert agent.status_code == 403
    assert called is False


def test_customer_route_rejects_staff_only_actions_before_any_chain_work(
    reservations_context: ReservationsContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    context = reservations_context
    _customer_id, auth, reservation = _create_test_reservation(
        context,
        listing_id="chain-customer-action-scope",
        deposit_amount_cop=None,
    )
    called = False

    def verify(**_kwargs: Any) -> dict[str, Any]:
        nonlocal called
        called = True
        raise AssertionError("verification must not run for a forbidden action")

    monkeypatch.setattr(chain, "verify_action_receipt", verify)
    path = f"/api/v1/reservations/{reservation['reservation_id']}/chain-transactions"
    for action in ("accept", "reject"):
        response = _submit(context, path, auth, action=action, tx_hash="0x" + "b" * 64)
        assert response.status_code == 422, response.text
        assert response.json()["code"] == "validation_error"
    assert called is False
    with context.session_factory() as session:
        stored = session.get(Reservation, reservation["reservation_id"])
        assert stored is not None and stored.status == "pending"
        assert session.query(reservation_models.ReservationChainTransaction).count() == 0


def test_reconciliation_guards_customer_action_scope_before_verifying(
    reservations_context: ReservationsContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    context = reservations_context
    customer_id, _auth, reservation = _create_test_reservation(
        context,
        listing_id="chain-service-action-scope",
        deposit_amount_cop=None,
    )
    customer_address = "0x" + __import__("hashlib").sha256(customer_id.encode()).hexdigest()[:40]
    tx_hash = "0x" + "c" * 64
    called = False

    def verify(**_kwargs: Any) -> dict[str, Any]:
        nonlocal called
        called = True
        return _proof(
            reservation,
            action="accept",
            tx_hash=tx_hash,
            amount=0,
            actor=customer_address,
        )

    monkeypatch.setattr(chain, "verify_action_receipt", verify)
    with pytest.raises(ReservationApiError) as raised:
        reconcile_chain_transaction(
            session_factory=context.session_factory,
            settings=context.client.app.state.settings,
            transport=getattr(context.client.app.state, "reservation_rpc_transport", None),
            reservation_id=reservation["reservation_id"],
            actor={"id": customer_id, "email": "permit-customer@example.test"},
            action="accept",
            transaction_hash=tx_hash,
            nonce=0,
            now=context.clock(),
        )
    assert (raised.value.status_code, raised.value.code) == (403, "reservation_action_forbidden")
    assert called is False
    with context.session_factory() as session:
        stored = session.get(Reservation, reservation["reservation_id"])
        assert stored is not None and stored.status == "pending"
        assert session.query(reservation_models.ReservationChainTransaction).count() == 0


def test_chain_transaction_openapi_limits_actions_per_route(
    reservations_context: ReservationsContext,
) -> None:
    schema = cast(Any, reservations_context.client.app.openapi())
    components = schema["components"]["schemas"]
    customer_operation = schema["paths"][
        "/api/v1/reservations/{reservation_id}/chain-transactions"
    ]["post"]
    staff_operation = schema["paths"][
        "/api/v1/staff/reservations/{reservation_id}/chain-transactions"
    ]["post"]

    def actions(operation: dict[str, Any]) -> set[str]:
        ref = operation["requestBody"]["content"]["application/json"]["schema"]["$ref"]
        return set(components[ref.rsplit("/", 1)[1]]["properties"]["action"]["enum"])

    assert actions(customer_operation) == {"deposit", "cancel", "expire"}
    assert actions(staff_operation) == {"accept", "reject", "cancel", "expire"}


def test_events_confirmed_before_the_deadline_reconcile_after_the_request_deadline(
    reservations_context: ReservationsContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    context = reservations_context
    email = "late-reconcile@example.test"
    customer_id, _auth, reservation = _create_test_reservation(
        context, listing_id="chain-late-reconcile", email=email
    )
    customer_address = "0x" + __import__("hashlib").sha256(customer_id.encode()).hexdigest()[:40]
    agency_address = "0x" + "a" * 40
    policy_deadline = datetime.fromisoformat(
        reservation["decision_deadline_at"].replace("Z", "+00:00")
    )
    signed_deadline = int(policy_deadline.timestamp()) + 1
    pre_deadline = signed_deadline - 1
    deposit_hash = "0x" + "d" * 64
    accept_hash = "0x" + "e" * 64

    def verify(**kwargs: Any) -> dict[str, Any]:
        action = kwargs["action"]
        return _proof(
            reservation,
            action=action,
            tx_hash=deposit_hash if action == "deposit" else accept_hash,
            amount=100000,
            actor=customer_address if action == "deposit" else agency_address,
            nonce=0 if action == "deposit" else 1,
            block_timestamp=pre_deadline,
        )

    monkeypatch.setattr(chain, "verify_action_receipt", verify)
    # Both events were mined before the deadline; only the reconcile request is late.
    context.clock.now = policy_deadline + timedelta(minutes=5)
    refreshed = context.client.post(
        "/api/v1/customer/auth/login", json={"email": email, "password": "password"}
    )
    assert refreshed.status_code == 200
    auth = {"Authorization": f"Bearer {refreshed.json()['access_token']}"}
    path = f"/api/v1/reservations/{reservation['reservation_id']}/chain-transactions"
    deposited = _submit(context, path, auth, action="deposit", tx_hash=deposit_hash)
    assert deposited.status_code == 200, deposited.text
    assert deposited.json()["block_timestamp"] == pre_deadline

    with context.session_factory() as session:
        stored = session.get(Reservation, reservation["reservation_id"])
        assert stored is not None and stored.deposit_confirmed_at is not None

    _use_staff_principal(context)
    staff_path = f"/api/v1/staff/reservations/{reservation['reservation_id']}/chain-transactions"
    accepted = _submit(context, staff_path, {}, action="accept", tx_hash=accept_hash, nonce=1)
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["status"] == "accepted"


def test_customer_cancel_confirmed_before_the_deadline_reconciles_after_it(
    reservations_context: ReservationsContext, monkeypatch: pytest.MonkeyPatch
) -> None:
    context = reservations_context
    email = "late-cancel@example.test"
    customer_id, _auth, reservation = _create_test_reservation(
        context,
        listing_id="chain-late-cancel",
        email=email,
        deposit_amount_cop=None,
    )
    customer_address = "0x" + __import__("hashlib").sha256(customer_id.encode()).hexdigest()[:40]
    policy_deadline = datetime.fromisoformat(
        reservation["decision_deadline_at"].replace("Z", "+00:00")
    )
    pre_deadline = int(policy_deadline.timestamp())
    tx_hash = "0x" + "f" * 64

    def verify(**kwargs: Any) -> dict[str, Any]:
        return _proof(
            reservation,
            action="cancel",
            tx_hash=kwargs["transaction_hash"],
            amount=0,
            actor=customer_address,
            block_timestamp=pre_deadline,
        )

    monkeypatch.setattr(chain, "verify_action_receipt", verify)
    context.clock.now = policy_deadline + timedelta(hours=1)
    refreshed = context.client.post(
        "/api/v1/customer/auth/login", json={"email": email, "password": "password"}
    )
    assert refreshed.status_code == 200
    auth = {"Authorization": f"Bearer {refreshed.json()['access_token']}"}
    path = f"/api/v1/reservations/{reservation['reservation_id']}/chain-transactions"
    cancelled = _submit(context, path, auth, action="cancel", tx_hash=tx_hash)
    assert cancelled.status_code == 200, cancelled.text
    assert cancelled.json()["status"] == "cancelled"


def test_permit_issuance_still_rejects_a_request_after_the_deadline(
    reservations_context: ReservationsContext,
) -> None:
    context = reservations_context
    email = "late-permit@example.test"
    _customer_id, _auth, reservation = _create_test_reservation(
        context, listing_id="chain-late-permit", email=email
    )
    _configure_fake_escrow(context)
    context.clock.now = datetime.fromisoformat(
        reservation["decision_deadline_at"].replace("Z", "+00:00")
    )
    refreshed = context.client.post(
        "/api/v1/customer/auth/login", json={"email": email, "password": "password"}
    )
    assert refreshed.status_code == 200
    auth = {"Authorization": f"Bearer {refreshed.json()['access_token']}"}

    blocked = context.client.post(
        f"/api/v1/reservations/{reservation['reservation_id']}/permit",
        headers=auth,
        json={"action": "deposit"},
    )
    assert (blocked.status_code, blocked.json()["code"]) == (
        409,
        "reservation_decision_deadline_passed",
    )


def test_migration_adds_append_only_audit_identity_and_unique_hash(
    reservations_context: ReservationsContext,
) -> None:
    table = cast(Any, reservation_models.ReservationChainTransaction.__table__)
    assert {column.name for column in table.columns} >= {
        "chain_id",
        "tx_hash",
        "event_name",
        "event_signature",
        "event_topic",
        "log_index",
    }
    assert any(
        constraint.name == "uq_reservation_chain_transaction_chain_tx_hash"
        for constraint in table.constraints
    )
    assert not hasattr(reservation_models.ReservationChainTransaction, "status")
