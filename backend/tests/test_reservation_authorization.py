from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import cast

import pytest

from app.modules.customer_identity.session import ActiveCustomer
from app.modules.identity.session import ActiveStaff
from app.modules.reservations.authorization import (
    ReservationAction,
    ensure_reservation_action_eligible,
)
from app.modules.reservations.errors import ReservationApiError
from app.modules.reservations.models import Reservation

NOW = datetime(2026, 9, 1, 12, tzinfo=timezone.utc)
DEADLINE = NOW + timedelta(hours=1)
AGENCY_ID = "agency-one"


def make_reservation(
    *,
    customer_id: str = "customer-one",
    status: str = "pending",
    deadline: datetime = DEADLINE,
    deposit: Decimal | None = None,
    deposit_confirmed_at: datetime | None = None,
) -> Reservation:
    return Reservation(
        id="reservation-one",
        customer_id=customer_id,
        status=status,
        decision_deadline_at=deadline,
        deposit_amount=deposit,
        deposit_confirmed_at=deposit_confirmed_at,
    )


def make_customer(customer_id: str = "customer-one") -> ActiveCustomer:
    return {"id": customer_id, "email": f"{customer_id}@example.test"}


def make_staff(
    *, role: str = "agency_admin", tenant_id: str | None = AGENCY_ID
) -> ActiveStaff:
    return {
        "id": "staff-one",
        "email": "staff@example.test",
        "role": role,
        "tenant_id": tenant_id,
    }


def assert_denied(
    *,
    reservation: Reservation,
    actor: ActiveCustomer | ActiveStaff,
    action: ReservationAction,
    now: datetime = NOW,
    reservation_agency_id: str = AGENCY_ID,
    expected_status: int,
    expected_code: str,
) -> None:
    with pytest.raises(ReservationApiError) as caught:
        ensure_reservation_action_eligible(
            reservation,
            actor,
            action=action,
            now=now,
            reservation_agency_id=reservation_agency_id,
        )

    assert (caught.value.status_code, caught.value.code) == (
        expected_status,
        expected_code,
    )


@pytest.mark.parametrize("action", ["cancel", "accept", "reject"])
def test_customer_can_only_request_own_cancellation(
    action: ReservationAction,
) -> None:
    reservation = make_reservation()
    customer = make_customer()

    if action == "cancel":
        assert ensure_reservation_action_eligible(
            reservation, customer, action=action, now=NOW
        ) is None
        assert reservation.status == "pending"
    else:
        assert_denied(
            reservation=reservation,
            actor=customer,
            action=action,
            expected_status=403,
            expected_code="reservation_action_forbidden",
        )


@pytest.mark.parametrize("action", ["cancel", "accept", "reject"])
def test_customer_cannot_request_action_for_another_customers_reservation(
    action: ReservationAction,
) -> None:
    assert_denied(
        reservation=make_reservation(customer_id="owner"),
        actor=make_customer("another-customer"),
        action=action,
        expected_status=404 if action == "cancel" else 403,
        expected_code=(
            "reservation_not_found" if action == "cancel" else "reservation_action_forbidden"
        ),
    )


@pytest.mark.parametrize("action", ["cancel", "accept", "reject"])
@pytest.mark.parametrize("role", ["agent", "platform_admin"])
def test_non_agency_admin_staff_cannot_request_reservation_actions(
    action: ReservationAction, role: str
) -> None:
    assert_denied(
        reservation=make_reservation(),
        actor=make_staff(
            role=role,
            tenant_id=None if role == "platform_admin" else AGENCY_ID,
        ),
        action=action,
        expected_status=403,
        expected_code="reservation_action_forbidden",
    )


@pytest.mark.parametrize("action", ["cancel", "accept", "reject"])
def test_cross_agency_admin_cannot_request_reservation_actions(
    action: ReservationAction,
) -> None:
    assert_denied(
        reservation=make_reservation(),
        actor=make_staff(tenant_id="agency-two"),
        action=action,
        expected_status=403,
        expected_code="reservation_action_forbidden",
    )


@pytest.mark.parametrize("action", ["cancel", "accept", "reject"])
def test_same_agency_admin_can_request_pending_actions_without_deposit(
    action: ReservationAction,
) -> None:
    reservation = make_reservation()
    assert ensure_reservation_action_eligible(
        reservation,
        make_staff(),
        action=action,
        now=NOW,
        reservation_agency_id=AGENCY_ID,
    ) is None
    assert reservation.status == "pending"


@pytest.mark.parametrize(
    ("actor", "action"),
    [
        (make_customer(), "cancel"),
        (make_staff(), "cancel"),
        (make_staff(), "accept"),
        (make_staff(), "reject"),
    ],
)
def test_only_pending_reservations_are_eligible(
    actor: ActiveCustomer | ActiveStaff, action: ReservationAction
) -> None:
    assert_denied(
        reservation=make_reservation(status="accepted"),
        actor=actor,
        action=action,
        expected_status=409,
        expected_code="reservation_not_pending",
    )


@pytest.mark.parametrize(
    ("actor", "action"),
    [
        (make_customer(), "cancel"),
        (make_staff(), "cancel"),
        (make_staff(), "accept"),
        (make_staff(), "reject"),
    ],
)
@pytest.mark.parametrize("offset", [timedelta(0), timedelta(seconds=1)])
def test_deadline_is_exclusive_for_every_permitted_actor_action(
    actor: ActiveCustomer | ActiveStaff,
    action: ReservationAction,
    offset: timedelta,
) -> None:
    naive_utc_deadline = datetime(2026, 9, 1, 13, tzinfo=None)
    local_now = datetime(2026, 9, 1, 9, tzinfo=timezone(timedelta(hours=-4))) + offset

    assert_denied(
        reservation=make_reservation(deadline=naive_utc_deadline),
        actor=actor,
        action=action,
        now=local_now,
        expected_status=409,
        expected_code="reservation_decision_deadline_passed",
    )


def test_configured_deposit_requires_confirmation_for_acceptance_and_rejection() -> None:
    reservation = make_reservation(deposit=Decimal("25000.00"))

    for action in ("accept", "reject"):
        assert_denied(
            reservation=reservation,
            actor=make_staff(),
            action=action,
            expected_status=409,
            expected_code="reservation_deposit_not_confirmed",
        )


def test_configured_deposit_allows_decision_after_confirmation() -> None:
    reservation = make_reservation(
        deposit=Decimal("25000.00"), deposit_confirmed_at=NOW - timedelta(minutes=1)
    )

    for action in ("accept", "reject"):
        assert ensure_reservation_action_eligible(
            reservation,
            make_staff(),
            action=action,
            now=NOW,
            reservation_agency_id=AGENCY_ID,
        ) is None


def test_cancellation_does_not_require_configured_deposit_confirmation() -> None:
    reservation = make_reservation(deposit=Decimal("25000.00"))

    assert ensure_reservation_action_eligible(
        reservation,
        make_staff(),
        action="cancel",
        now=NOW,
        reservation_agency_id=AGENCY_ID,
    ) is None


def test_nullable_deposit_allows_agency_acceptance_and_rejection() -> None:
    reservation = make_reservation(deposit=None, deposit_confirmed_at=None)

    for action in ("accept", "reject"):
        assert ensure_reservation_action_eligible(
            reservation,
            make_staff(),
            action=action,
            now=NOW,
            reservation_agency_id=AGENCY_ID,
        ) is None


def test_invalid_action_is_rejected_as_validation_error() -> None:
    assert_denied(
        reservation=make_reservation(),
        actor=make_customer(),
        action=cast(ReservationAction, "refund"),
        expected_status=422,
        expected_code="validation_error",
    )
