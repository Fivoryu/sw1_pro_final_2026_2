"""Pure request-eligibility rules for reservation actions.

Passing these checks only means an actor is eligible to request an action. This
module does not authorize, submit, or confirm any on-chain operation and does
not mutate reservation state.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal, TypeGuard

from app.modules.customer_identity.session import ActiveCustomer
from app.modules.identity.session import ActiveStaff
from app.modules.reservations.errors import ReservationApiError
from app.modules.reservations.models import Reservation

ReservationAction = Literal["cancel", "accept", "reject"]
ReservationActor = ActiveCustomer | ActiveStaff


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _is_staff(actor: ReservationActor) -> TypeGuard[ActiveStaff]:
    return "role" in actor


def _forbidden() -> ReservationApiError:
    return ReservationApiError(
        403,
        "reservation_action_forbidden",
        "The actor is not allowed to request this reservation action.",
    )


def _ensure_pending(reservation: Reservation) -> None:
    if reservation.status != "pending":
        raise ReservationApiError(
            409,
            "reservation_not_pending",
            "Only a pending reservation can receive this action request.",
        )


def _ensure_before_deadline(reservation: Reservation, now: datetime) -> None:
    if _as_utc(now) >= _as_utc(reservation.decision_deadline_at):
        raise ReservationApiError(
            409,
            "reservation_decision_deadline_passed",
            "The reservation decision deadline has passed.",
        )


def ensure_reservation_action_eligible(
    reservation: Reservation,
    actor: ReservationActor,
    *,
    action: ReservationAction,
    now: datetime,
    reservation_agency_id: str | None = None,
    require_before_deadline: bool = True,
) -> None:
    """Raise a stable API error unless this actor may request the action.

    ``reservation_agency_id`` is supplied by the caller from already-resolved
    context: Reservation currently stores its agency wallet ID, not its agency
    ID, so determining that ID belongs to the integrating service/router.

    ``require_before_deadline`` stays true for permit issuance, where a signature
    produced after the exclusive policy deadline would only be rejected on chain.
    Reconciliation passes false because the authoritative instant there is the
    mined block timestamp, which the receipt verifier already checks per action.
    """
    if action not in {"cancel", "accept", "reject"}:
        raise ReservationApiError(
            422,
            "validation_error",
            "The reservation action is invalid.",
        )

    if _is_staff(actor):
        if (
            actor["role"] != "agency_admin"
            or actor["tenant_id"] is None
            or reservation_agency_id is None
            or actor["tenant_id"] != reservation_agency_id
        ):
            raise _forbidden()
    else:
        if action != "cancel":
            raise _forbidden()
        if actor["id"] != reservation.customer_id:
            raise ReservationApiError(
                404,
                "reservation_not_found",
                "The reservation was not found.",
            )

    _ensure_pending(reservation)
    if require_before_deadline:
        _ensure_before_deadline(reservation, now)

    if (
        _is_staff(actor)
        and action in {"accept", "reject"}
        and reservation.deposit_amount is not None
        and reservation.deposit_confirmed_at is None
    ):
        raise ReservationApiError(
            409,
            "reservation_deposit_not_confirmed",
            "The reservation deposit must be confirmed before an agency decision.",
        )
