from __future__ import annotations

from datetime import datetime, timezone
from typing import Annotated, Any, Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.modules.catalog.models import Listing
from app.modules.customer_identity.session import ActiveCustomer, get_active_customer
from app.modules.identity.session import ActiveStaff, get_active_staff
from app.modules.reservations.models import Reservation
from app.modules.stripe_payments.gateway import (
    StripeGateway,
    StripeGatewayError,
    decode_webhook_event,
    verify_webhook_signature,
)
from app.modules.stripe_payments.models import (
    ReservationCardPayment,
    StripeConnectAccount,
    StripeWebhookEvent,
)
from app.modules.stripe_payments.service import payment_amount_minor_units, stripe_currency

router = APIRouter(tags=["stripe-card-payments"])


class CardPaymentResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reservation_id: str
    payment_intent_id: str
    client_secret: str
    publishable_key: str
    amount_minor: int
    currency: str
    status: str


class StripeConnectStatusResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    agency_id: str
    connected: bool
    details_submitted: bool
    charges_enabled: bool
    payouts_enabled: bool
    onboarding_url: str | None = None


class CardReservationItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reservation_id: str
    listing_id: str
    status: str
    deposit_amount: str | None
    currency: str
    payment_status: str
    created_at: datetime
    deadline_at: datetime


class CardReservationDecisionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    action: Literal["accept", "reject"]


def _session_factory(request: Request) -> sessionmaker[Session]:
    return request.app.state.session_factory


def _gateway(request: Request) -> Any:
    gateway = getattr(request.app.state, "stripe_gateway", None)
    if gateway is not None:
        return gateway
    settings: Settings = request.app.state.settings
    if not settings.stripe_secret_key:
        raise HTTPException(status_code=503, detail="Stripe test mode is not configured")
    try:
        gateway = StripeGateway(settings.stripe_secret_key)
    except ValueError:
        raise HTTPException(status_code=503, detail="Stripe test mode is not configured") from None
    request.app.state.stripe_gateway = gateway
    return gateway


def _as_utc(value: datetime) -> datetime:
    return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)


def _now(request: Request) -> datetime:
    return _as_utc(request.app.state.clock())


def _require_agency_admin(staff: ActiveStaff, agency_id: str) -> None:
    if staff.get("role") != "agency_admin" or staff.get("tenant_id") != agency_id:
        raise HTTPException(status_code=403, detail="Agency administrator access is required")


def _staff_agency_for_reservation(session: Session, *, reservation: Reservation, staff: ActiveStaff) -> str:
    listing = session.get(Listing, reservation.listing_id)
    if listing is None:
        raise HTTPException(status_code=404, detail="Reservation not found")
    _require_agency_admin(staff, listing.agency_id)
    return listing.agency_id


def _deposit_currency(reservation: Reservation) -> str:
    return next(
        (
            str(line.get("currency", "BOB")).upper()
            for line in reservation.quote_lines
            if line.get("kind") == "base"
        ),
        "BOB",
    )


@router.post(
    "/api/v1/reservations/{reservation_id}/card-payment-intent",
    response_model=CardPaymentResponse,
)
def create_card_payment_intent(
    reservation_id: str,
    request: Request,
    customer: ActiveCustomer = Depends(get_active_customer),
) -> CardPaymentResponse:
    settings: Settings = request.app.state.settings
    if (
        not settings.stripe_publishable_key
        or not settings.stripe_publishable_key.startswith("pk_test_")
        or not settings.stripe_webhook_secret
    ):
        raise HTTPException(status_code=503, detail="Stripe test mode and webhook are not fully configured")
    with _session_factory(request)() as session:
        reservation = (
            session.query(Reservation)
            .filter(
                Reservation.id == reservation_id,
                Reservation.customer_id == customer["id"],
                Reservation.payment_method == "card",
            )
            .one_or_none()
        )
        if reservation is None:
            raise HTTPException(status_code=404, detail="Card reservation not found")
        if reservation.status != "pending" or reservation.deposit_confirmed_at is not None:
            raise HTTPException(status_code=409, detail="Reservation is not eligible for card payment")
        if reservation.deposit_amount is None:
            raise HTTPException(status_code=409, detail="Reservation has no deposit")
        if _now(request) >= _as_utc(reservation.decision_deadline_at):
            raise HTTPException(status_code=409, detail="Reservation payment deadline has expired")
        currency = _deposit_currency(reservation)
        try:
            stripe_ccy = stripe_currency(currency)
            amount_minor = payment_amount_minor_units(reservation.deposit_amount, currency)
        except ValueError as error:
            raise HTTPException(status_code=422, detail=str(error)) from None
        connected_account = (
            session.query(StripeConnectAccount)
            .join(Listing, Listing.agency_id == StripeConnectAccount.agency_id)
            .filter(Listing.id == reservation.listing_id)
            .one_or_none()
        )
        if connected_account is None or not connected_account.payouts_enabled:
            raise HTTPException(status_code=409, detail="Agency Stripe Connect account is not ready")
        reservation_id_value = reservation.id

    try:
        payment_intent = _gateway(request).create_payment_intent(
            amount=amount_minor,
            currency=stripe_ccy,
            reservation_id=reservation_id_value,
            idempotency_key=f"roomforge-card-payment-{reservation_id_value}",
        )
    except (StripeGatewayError, ValueError):
        raise HTTPException(status_code=503, detail="Stripe could not initialize the card payment") from None
    intent_id = payment_intent.get("id")
    client_secret = payment_intent.get("client_secret")
    if not isinstance(intent_id, str) or not isinstance(client_secret, str):
        raise HTTPException(status_code=502, detail="Stripe returned an incomplete payment session")

    now = _now(request)
    with _session_factory(request).begin() as session:
        payment = (
            session.query(ReservationCardPayment)
            .filter(ReservationCardPayment.reservation_id == reservation_id_value)
            .one_or_none()
        )
        if payment is None:
            payment = ReservationCardPayment(
                id=str(uuid4()),
                reservation_id=reservation_id_value,
                stripe_payment_intent_id=intent_id,
                amount_minor=amount_minor,
                currency=stripe_ccy,
                status=str(payment_intent.get("status", "requires_payment_method")),
                created_at=now,
                updated_at=now,
            )
            session.add(payment)
        elif payment.stripe_payment_intent_id != intent_id or payment.amount_minor != amount_minor:
            raise HTTPException(status_code=409, detail="Card payment session conflicts with reservation")
    return CardPaymentResponse(
        reservation_id=reservation_id_value,
        payment_intent_id=intent_id,
        client_secret=client_secret,
        publishable_key=settings.stripe_publishable_key,
        amount_minor=amount_minor,
        currency=stripe_ccy,
        status=str(payment_intent.get("status", "requires_payment_method")),
    )


@router.post("/api/v1/stripe/webhook", status_code=status.HTTP_200_OK)
async def stripe_webhook(
    request: Request,
    stripe_signature: Annotated[str | None, Header(alias="Stripe-Signature")] = None,
) -> dict[str, bool]:
    settings: Settings = request.app.state.settings
    secret = settings.stripe_webhook_secret
    if not secret:
        raise HTTPException(status_code=503, detail="Stripe webhook is not configured")
    payload = await request.body()
    if stripe_signature is None or not verify_webhook_signature(payload, stripe_signature, secret):
        raise HTTPException(status_code=400, detail="Invalid Stripe signature")
    try:
        event = decode_webhook_event(payload)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid Stripe event") from None
    event_id = event.get("id")
    event_type = event.get("type")
    event_data = event.get("data")
    event_object = event_data.get("object") if isinstance(event_data, dict) else None
    if not isinstance(event_id, str) or not isinstance(event_type, str) or not isinstance(event_object, dict):
        raise HTTPException(status_code=400, detail="Invalid Stripe event")

    with _session_factory(request).begin() as session:
        if session.query(StripeWebhookEvent).filter_by(stripe_event_id=event_id).one_or_none():
            return {"received": True}
        intent_id = event_object.get("id") if event_type.startswith("payment_intent.") else None
        if event_type == "account.updated":
            account_id = event_object.get("id")
            if isinstance(account_id, str):
                connected = (
                    session.query(StripeConnectAccount).filter_by(stripe_account_id=account_id).one_or_none()
                )
                if connected is not None:
                    connected.details_submitted = bool(event_object.get("details_submitted", False))
                    connected.charges_enabled = bool(event_object.get("charges_enabled", False))
                    connected.payouts_enabled = bool(event_object.get("payouts_enabled", False))
                    connected.updated_at = _now(request)
        if event_type in {"charge.refunded", "refund.updated"}:
            payment_intent = event_object.get("payment_intent")
            if isinstance(payment_intent, dict):
                payment_intent = payment_intent.get("id")
            if isinstance(payment_intent, str):
                payment = (
                    session.query(ReservationCardPayment)
                    .filter_by(stripe_payment_intent_id=payment_intent)
                    .with_for_update()
                    .one_or_none()
                )
                if payment is not None:
                    refund_status = event_object.get("status")
                    if event_type == "charge.refunded":
                        amount_refunded = event_object.get("amount_refunded")
                        refund_status = (
                            "succeeded"
                            if isinstance(amount_refunded, int) and amount_refunded >= payment.amount_minor
                            else "pending"
                        )
                    payment.status = "refunded" if refund_status == "succeeded" else "refund_pending"
                    refund_id = event_object.get("id")
                    if isinstance(refund_id, str):
                        payment.refund_id = refund_id
                    payment.updated_at = _now(request)
        if event_type in {"payment_intent.succeeded", "payment_intent.payment_failed"} and isinstance(
            intent_id, str
        ):
            payment = (
                session.query(ReservationCardPayment)
                .filter_by(stripe_payment_intent_id=intent_id)
                .with_for_update()
                .one_or_none()
            )
            if payment is not None:
                reservation = session.get(Reservation, payment.reservation_id)
                if reservation is not None:
                    received_amount = event_object.get("amount_received", event_object.get("amount"))
                    received_currency = event_object.get("currency")
                    if received_amount != payment.amount_minor or received_currency != payment.currency:
                        raise HTTPException(
                            status_code=400, detail="Stripe payment does not match reservation"
                        )
                    if event_type == "payment_intent.succeeded":
                        latest_charge = event_object.get("latest_charge")
                        payment.latest_charge_id = latest_charge if isinstance(latest_charge, str) else None
                        payment.status = "succeeded"
                        if reservation.status == "pending" and _now(request) < _as_utc(
                            reservation.decision_deadline_at
                        ):
                            reservation.deposit_confirmed_at = _now(request)
                        else:
                            try:
                                refund = _gateway(request).create_refund(
                                    payment_intent_id=payment.stripe_payment_intent_id,
                                    idempotency_key=f"roomforge-card-refund-{reservation.id}",
                                )
                            except StripeGatewayError:
                                raise HTTPException(
                                    status_code=503, detail="Stripe refund is pending retry"
                                ) from None
                            refund_id = refund.get("id")
                            if not isinstance(refund_id, str):
                                raise HTTPException(status_code=503, detail="Stripe refund is pending retry")
                            payment.refund_id = refund_id
                            payment.status = "refunded"
                            if reservation.status == "pending":
                                reservation.status = "expired"
                    else:
                        payment.status = "failed"
                    payment.updated_at = _now(request)
        session.add(
            StripeWebhookEvent(
                id=str(uuid4()),
                stripe_event_id=event_id,
                event_type=event_type,
                processed_at=_now(request),
            )
        )
    return {"received": True}


@router.post("/api/v1/staff/agencies/{agency_id}/stripe/connect/onboarding-link")
def create_connect_onboarding_link(
    agency_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, str]:
    _require_agency_admin(staff, agency_id)
    settings: Settings = request.app.state.settings
    if not settings.stripe_connect_account_country:
        raise HTTPException(status_code=503, detail="Stripe Connect test country is not configured")
    with _session_factory(request)() as session:
        account = session.query(StripeConnectAccount).filter_by(agency_id=agency_id).one_or_none()
    try:
        gateway = _gateway(request)
        if account is None:
            remote = gateway.create_connect_account(
                country=settings.stripe_connect_account_country.upper(),
                agency_id=agency_id,
                idempotency_key=f"roomforge-connect-account-{agency_id}",
            )
            account_id = remote.get("id")
            if not isinstance(account_id, str):
                raise StripeGatewayError("Stripe returned an invalid connected account")
            now = _now(request)
            with _session_factory(request).begin() as session:
                account = StripeConnectAccount(
                    id=str(uuid4()),
                    agency_id=agency_id,
                    stripe_account_id=account_id,
                    details_submitted=bool(remote.get("details_submitted", False)),
                    charges_enabled=bool(remote.get("charges_enabled", False)),
                    payouts_enabled=bool(remote.get("payouts_enabled", False)),
                    created_at=now,
                    updated_at=now,
                )
                session.add(account)
        else:
            account_id = account.stripe_account_id
        origin = settings.web_origin.rstrip("/")
        link = gateway.create_account_link(
            account_id=account_id,
            refresh_url=f"{origin}/?stripe-connect=refresh",
            return_url=f"{origin}/?stripe-connect=return",
            idempotency_key=f"roomforge-connect-link-{agency_id}-{int(_now(request).timestamp()) // 60}",
        )
    except (StripeGatewayError, ValueError):
        raise HTTPException(status_code=503, detail="Stripe Connect onboarding is unavailable") from None
    url = link.get("url")
    if not isinstance(url, str):
        raise HTTPException(status_code=502, detail="Stripe returned an invalid onboarding link")
    return {"url": url}


@router.get(
    "/api/v1/staff/agencies/{agency_id}/stripe/connect",
    response_model=StripeConnectStatusResponse,
)
def get_connect_status(
    agency_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> StripeConnectStatusResponse:
    _require_agency_admin(staff, agency_id)
    with _session_factory(request)() as session:
        account = session.query(StripeConnectAccount).filter_by(agency_id=agency_id).one_or_none()
    if account is None:
        return StripeConnectStatusResponse(
            agency_id=agency_id,
            connected=False,
            details_submitted=False,
            charges_enabled=False,
            payouts_enabled=False,
        )
    try:
        remote = _gateway(request).retrieve_account(account.stripe_account_id)
    except StripeGatewayError:
        raise HTTPException(status_code=503, detail="Stripe Connect status is unavailable") from None
    values = {
        "details_submitted": bool(remote.get("details_submitted", False)),
        "charges_enabled": bool(remote.get("charges_enabled", False)),
        "payouts_enabled": bool(remote.get("payouts_enabled", False)),
    }
    with _session_factory(request).begin() as session:
        stored = session.query(StripeConnectAccount).filter_by(agency_id=agency_id).one()
        for field, value in values.items():
            setattr(stored, field, value)
        stored.updated_at = _now(request)
    return StripeConnectStatusResponse(
        agency_id=agency_id,
        connected=values["details_submitted"] and values["payouts_enabled"],
        details_submitted=values["details_submitted"],
        charges_enabled=values["charges_enabled"],
        payouts_enabled=values["payouts_enabled"],
    )


@router.get("/api/v1/staff/agencies/{agency_id}/reservations/card", response_model=list[CardReservationItem])
def list_card_reservations(
    agency_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> list[CardReservationItem]:
    _require_agency_admin(staff, agency_id)
    with _session_factory(request)() as session:
        rows = (
            session.query(Reservation, ReservationCardPayment)
            .join(ReservationCardPayment, ReservationCardPayment.reservation_id == Reservation.id)
            .join(Listing, Listing.id == Reservation.listing_id)
            .filter(
                Listing.agency_id == agency_id,
                Reservation.payment_method == "card",
                Reservation.status == "pending",
                ReservationCardPayment.status == "succeeded",
                Reservation.deposit_confirmed_at.is_not(None),
            )
            .order_by(Reservation.api_created_at.asc())
            .all()
        )
        return [
            CardReservationItem(
                reservation_id=reservation.id,
                listing_id=reservation.listing_id,
                status=reservation.status,
                deposit_amount=str(reservation.deposit_amount)
                if reservation.deposit_amount is not None
                else None,
                currency=_deposit_currency(reservation),
                payment_status=payment.status,
                created_at=reservation.api_created_at,
                deadline_at=reservation.decision_deadline_at,
            )
            for reservation, payment in rows
        ]


@router.post("/api/v1/staff/reservations/{reservation_id}/card-decision")
def decide_card_reservation(
    reservation_id: str,
    body: CardReservationDecisionRequest,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, str]:
    now = _now(request)
    with _session_factory(request).begin() as session:
        reservation = session.get(Reservation, reservation_id)
        if reservation is None or reservation.payment_method != "card":
            raise HTTPException(status_code=404, detail="Card reservation not found")
        agency_id = _staff_agency_for_reservation(session, reservation=reservation, staff=staff)
        payment = session.query(ReservationCardPayment).filter_by(reservation_id=reservation_id).one_or_none()
        account = session.query(StripeConnectAccount).filter_by(agency_id=agency_id).one_or_none()
        if reservation.status != "pending":
            raise HTTPException(status_code=409, detail="Card reservation is no longer pending")
        if now >= _as_utc(reservation.decision_deadline_at):
            raise HTTPException(status_code=409, detail="Card reservation decision deadline has expired")
        operation_pending_status = "transfer_pending" if body.action == "accept" else "refund_pending"
        if (
            payment is None
            or payment.status not in {"succeeded", operation_pending_status}
            or not reservation.deposit_confirmed_at
        ):
            raise HTTPException(status_code=409, detail="A verified card payment is required")
        payment.status = operation_pending_status
        payment.updated_at = now
        payment_id = payment.id
        intent_id = payment.stripe_payment_intent_id
        charge_id = payment.latest_charge_id
        amount = payment.amount_minor
        currency = payment.currency
        destination = account.stripe_account_id if account else None
        if body.action == "accept" and (account is None or not account.payouts_enabled):
            raise HTTPException(status_code=409, detail="Agency Stripe Connect account is not payout-enabled")

    try:
        if body.action == "accept":
            if not charge_id or not destination:
                raise HTTPException(status_code=409, detail="The card charge is not ready for transfer")
            result = _gateway(request).create_transfer(
                amount=amount,
                currency=currency,
                destination=destination,
                source_transaction=charge_id,
                reservation_id=reservation_id,
                idempotency_key=f"roomforge-card-transfer-{reservation_id}",
            )
            operation_id = result.get("id")
            payment_status = "transferred"
        else:
            result = _gateway(request).create_refund(
                payment_intent_id=intent_id,
                idempotency_key=f"roomforge-card-refund-{reservation_id}",
            )
            operation_id = result.get("id")
            payment_status = "refunded" if result.get("status") == "succeeded" else "refund_pending"
    except StripeGatewayError:
        with _session_factory(request).begin() as session:
            payment = session.query(ReservationCardPayment).filter_by(id=payment_id).with_for_update().one()
            if payment.status == operation_pending_status:
                payment.status = "succeeded"
                payment.updated_at = now
        raise HTTPException(
            status_code=503, detail="Stripe could not complete the reservation decision"
        ) from None
    if not isinstance(operation_id, str):
        raise HTTPException(status_code=502, detail="Stripe returned an invalid financial operation")

    with _session_factory(request).begin() as session:
        reservation = session.query(Reservation).filter_by(id=reservation_id).with_for_update().one()
        payment = session.query(ReservationCardPayment).filter_by(id=payment_id).with_for_update().one()
        if reservation.status != "pending" or payment.status != operation_pending_status:
            raise HTTPException(
                status_code=409, detail="Card reservation decision is already being processed"
            )
        reservation.status = "accepted" if body.action == "accept" else "rejected"
        payment.status = payment_status
        if body.action == "accept":
            payment.transfer_id = operation_id
        else:
            payment.refund_id = operation_id
        payment.updated_at = now
    return {
        "reservation_id": reservation_id,
        "status": "accepted" if body.action == "accept" else "rejected",
        "payment_status": payment_status,
    }


def _close_customer_card_reservation(
    *, reservation_id: str, request: Request, customer: ActiveCustomer, expired: bool
) -> dict[str, str]:
    now = _now(request)
    target_status = "expired" if expired else "cancelled"
    with _session_factory(request)() as session:
        reservation = (
            session.query(Reservation)
            .filter_by(id=reservation_id, customer_id=customer["id"], payment_method="card")
            .one_or_none()
        )
        if reservation is None:
            raise HTTPException(status_code=404, detail="Card reservation not found")
        if reservation.status == target_status:
            payment = (
                session.query(ReservationCardPayment).filter_by(reservation_id=reservation_id).one_or_none()
            )
            return {
                "reservation_id": reservation_id,
                "status": target_status,
                "payment_status": payment.status if payment else "cancelled",
            }
        if reservation.status != "pending":
            raise HTTPException(status_code=409, detail="Card reservation is no longer pending")
        deadline = _as_utc(reservation.decision_deadline_at)
        if expired and now < deadline:
            raise HTTPException(status_code=409, detail="Reservation deadline has not expired")
        if not expired and now >= deadline:
            raise HTTPException(status_code=409, detail="Reservation deadline has expired")
        payment = session.query(ReservationCardPayment).filter_by(reservation_id=reservation_id).one_or_none()
        payment_id = payment.id if payment else None
        intent_id = payment.stripe_payment_intent_id if payment else None
        paid = payment is not None and payment.status == "succeeded"
    payment_status = "cancelled"
    operation_id: str | None = None
    if intent_id is not None:
        try:
            gateway = _gateway(request)
            result = (
                gateway.create_refund(
                    payment_intent_id=intent_id,
                    idempotency_key=f"roomforge-card-refund-{reservation_id}",
                )
                if paid
                else gateway.cancel_payment_intent(
                    payment_intent_id=intent_id,
                    idempotency_key=f"roomforge-card-cancel-{reservation_id}",
                )
            )
        except StripeGatewayError:
            raise HTTPException(
                status_code=503, detail="Stripe could not close this card reservation"
            ) from None
        operation_id = result.get("id") if isinstance(result.get("id"), str) else None
        if operation_id is None:
            raise HTTPException(status_code=502, detail="Stripe returned an invalid financial operation")
        payment_status = (
            ("refunded" if result.get("status") == "succeeded" else "refund_pending") if paid else "cancelled"
        )
    with _session_factory(request).begin() as session:
        reservation = session.query(Reservation).filter_by(id=reservation_id).with_for_update().one()
        if reservation.status == target_status:
            return {
                "reservation_id": reservation_id,
                "status": target_status,
                "payment_status": payment_status,
            }
        if reservation.status != "pending":
            raise HTTPException(status_code=409, detail="Card reservation is no longer pending")
        reservation.status = target_status
        if payment_id is not None:
            payment = session.query(ReservationCardPayment).filter_by(id=payment_id).with_for_update().one()
            payment.status = payment_status
            if paid:
                payment.refund_id = operation_id
            payment.updated_at = now
    return {"reservation_id": reservation_id, "status": target_status, "payment_status": payment_status}


@router.post("/api/v1/reservations/{reservation_id}/card-cancel")
def cancel_card_reservation(
    reservation_id: str,
    request: Request,
    customer: ActiveCustomer = Depends(get_active_customer),
) -> dict[str, str]:
    return _close_customer_card_reservation(
        reservation_id=reservation_id, request=request, customer=customer, expired=False
    )


@router.post("/api/v1/reservations/{reservation_id}/card-expire")
def expire_card_reservation(
    reservation_id: str,
    request: Request,
    customer: ActiveCustomer = Depends(get_active_customer),
) -> dict[str, str]:
    return _close_customer_card_reservation(
        reservation_id=reservation_id, request=request, customer=customer, expired=True
    )
