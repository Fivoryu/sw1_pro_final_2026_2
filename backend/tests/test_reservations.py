from __future__ import annotations

import base64
import hashlib
import importlib.util
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.modules.agencies.models import AgencyWallet
from app.modules.catalog.models import Listing, QuoteSnapshot
from app.modules.customer_identity.models import CustomerWallet
from app.modules.identity.models import Agency


@dataclass
class FrozenClock:
    now: datetime

    def __call__(self) -> datetime:
        return self.now

    def advance(self, delta: timedelta) -> None:
        self.now += delta


@dataclass
class ReservationsContext:
    client: TestClient
    session_factory: sessionmaker[Session]
    clock: FrozenClock


@pytest.fixture

def reservations_context() -> Iterator[ReservationsContext]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    migrations = Path(__file__).resolve().parents[1] / "alembic" / "versions"
    for filename, module_name, installer in (
        ("0007_catalog_offers.py", "reservation_catalog_0007", "_install_offer_version_triggers"),
        ("0008_quote_snapshots.py", "reservation_quotes_0008", "_install_snapshot_immutability"),
        (
            "0009_agency_wallets_listing_deposit.py",
            "reservation_deposits_0009",
            "_install_listing_deposit_offer_version_triggers",
        ),
    ):
        spec = importlib.util.spec_from_file_location(module_name, migrations / filename)
        assert spec is not None and spec.loader is not None
        migration = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(migration)
        with engine.begin() as connection:
            with Operations.context(MigrationContext.configure(connection)):
                getattr(migration, installer)()

    clock = FrozenClock(datetime(2026, 9, 1, 12, tzinfo=timezone.utc))
    app = create_app(
        settings=Settings(
            database_url="sqlite+pysqlite:///:memory:",
            jwt_secret="reservations-test-secret-at-least-32-bytes",
            totp_encryption_key=base64.urlsafe_b64encode(b"x" * 32).decode("ascii"),
            web_origin="https://panel.example.test",
        ),
        session_factory=session_factory,
        clock=clock,
    )
    with TestClient(app, base_url="https://api.example.test") as client:
        yield ReservationsContext(client, session_factory, clock)
    engine.dispose()


def _customer_auth(
    context: ReservationsContext,
    *,
    email: str = "customer@example.test",
) -> tuple[str, dict[str, str]]:
    registered = context.client.post(
        "/api/v1/customer/auth/register",
        json={"email": email, "password": "password"},
    )
    assert registered.status_code == 201
    login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": email, "password": "password"},
    )
    assert login.status_code == 200
    return registered.json()["id"], {
        "Authorization": f"Bearer {login.json()['access_token']}"
    }


def _seed_reservation_inputs(
    context: ReservationsContext,
    customer_id: str,
    *,
    listing_id: str,
    agency_id: str = "agency-one",
    deposit_amount_cop: Decimal | None = None,
    with_agency_wallet: bool = True,
    with_customer_wallet: bool = True,
    quote_id: str | None = None,
) -> tuple[str, str | None]:
    wallet_id = customer_id if with_customer_wallet else None
    quote_id = quote_id or f"quote-{listing_id}"
    with context.session_factory.begin() as session:
        if session.get(Agency, agency_id) is None:
            session.add(Agency(id=agency_id))
            session.flush()
        if with_agency_wallet and session.query(AgencyWallet).filter_by(agency_id=agency_id).first() is None:
            session.add(
                AgencyWallet(
                    id=f"agency-wallet-{agency_id}",
                    agency_id=agency_id,
                    address=f"0x{'a' * 40}",
                    linked_at=context.clock(),
                )
            )
        session.add(
            Listing(
                id=listing_id,
                agency_id=agency_id,
                approval_status="approved",
                is_published=True,
                operation="sale",
                base_price=Decimal("100000.00"),
                deposit_amount_cop=deposit_amount_cop,
                offer_version=1,
                city="Córdoba",
                city_key="córdoba",
                zone="Centro",
                zone_key="centro",
                bedrooms=2,
                bathrooms=1,
                created_at=context.clock(),
            )
        )
        if wallet_id is not None and session.query(CustomerWallet).filter_by(
            customer_id=customer_id
        ).first() is None:
            session.add(
                CustomerWallet(
                    id=wallet_id,
                    customer_id=customer_id,
                    address=f"0x{hashlib.sha256(customer_id.encode()).hexdigest()[:40]}",
                    linked_at=context.clock(),
                )
            )
        session.add(
            QuoteSnapshot(
                id=quote_id,
                listing_id=listing_id,
                offer_version=1,
                operation="sale",
                lines=[
                    {
                        "kind": "base",
                        "extra_id": None,
                        "amount": "100000.00",
                        "currency": "COP",
                        "charge_period": "one_time",
                    }
                ],
                one_time_total=Decimal("100000.00"),
                monthly_total=Decimal("0.00"),
                created_at=context.clock(),
                expires_at=context.clock() + timedelta(minutes=15),
            )
        )
    return quote_id, wallet_id


def _create_reservation(
    context: ReservationsContext,
    auth: dict[str, str],
    *,
    listing_id: str,
    quote_id: str,
    wallet_id: str | None,
    key: str = "request-one",
):
    return context.client.post(
        "/api/v1/reservations",
        headers={**auth, "Idempotency-Key": key},
        json={
            "listing_id": listing_id,
            "quote_id": quote_id,
            "customer_wallet_id": wallet_id or "missing-wallet",
        },
    )


def test_create_snapshots_quote_deposit_and_both_linked_wallet_addresses(
    reservations_context: ReservationsContext,
) -> None:
    context = reservations_context
    customer_id, auth = _customer_auth(context)
    quote_id, wallet_id = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="listing-with-deposit",
        deposit_amount_cop=Decimal("25000.00"),
    )
    response = _create_reservation(
        context,
        auth,
        listing_id="listing-with-deposit",
        quote_id=quote_id,
        wallet_id=wallet_id,
    )

    assert response.status_code == 201, response.text
    created = response.json()
    assert created["listing_id"] == "listing-with-deposit"
    assert created["status"] == "pending"
    assert datetime.fromisoformat(created["api_created_at"].replace("Z", "+00:00")) == context.clock()
    assert datetime.fromisoformat(
        created["decision_deadline_at"].replace("Z", "+00:00")
    ) == context.clock() + timedelta(hours=24)
    assert created["quote_snapshot"]["quote_id"] == quote_id
    assert created["deposit_amount_cop"] == "25000.00"

    nullable_quote, nullable_wallet = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="listing-without-deposit",
        deposit_amount_cop=None,
    )
    nullable = _create_reservation(
        context,
        auth,
        listing_id="listing-without-deposit",
        quote_id=nullable_quote,
        wallet_id=nullable_wallet,
        key="request-null-deposit",
    )
    assert nullable.status_code == 201, nullable.text
    assert nullable.json()["deposit_amount_cop"] is None

    from app.modules.reservations.models import Reservation

    with context.session_factory() as session:
        stored = session.get(Reservation, created["reservation_id"])
        assert stored is not None
        assert stored.customer_wallet_address == (
            f"0x{hashlib.sha256(customer_id.encode()).hexdigest()[:40]}"
        )
        assert stored.agency_wallet_address == f"0x{'a' * 40}"
        assert stored.deposit_amount_cop == Decimal("25000.00")


def test_rejects_missing_or_foreign_stale_and_expired_quotes_and_unlinked_wallets(
    reservations_context: ReservationsContext,
) -> None:
    context = reservations_context
    customer_id, auth = _customer_auth(context)
    quote_id, wallet_id = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="quote-owner-listing",
        deposit_amount_cop=None,
    )
    _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="different-listing",
        deposit_amount_cop=None,
    )
    expiry_quote, _ = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="expiry-listing",
        deposit_amount_cop=None,
    )

    missing = _create_reservation(
        context,
        auth,
        listing_id="quote-owner-listing",
        quote_id="missing-quote",
        wallet_id=wallet_id,
        key="missing",
    )
    foreign = _create_reservation(
        context,
        auth,
        listing_id="different-listing",
        quote_id=quote_id,
        wallet_id=wallet_id,
        key="foreign",
    )
    assert (missing.status_code, missing.json()["code"]) == (404, "quote_not_found")
    assert (foreign.status_code, foreign.json()["code"]) == (404, "quote_not_found")

    with context.session_factory.begin() as session:
        listing = session.get(Listing, "quote-owner-listing")
        assert listing is not None
        listing.base_price = Decimal("110000.00")
    stale = _create_reservation(
        context,
        auth,
        listing_id="quote-owner-listing",
        quote_id=quote_id,
        wallet_id=wallet_id,
        key="stale",
    )
    assert (stale.status_code, stale.json()["code"]) == (409, "offer_version_mismatch")

    context.clock.advance(timedelta(minutes=15))
    refreshed_login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": "password"},
    )
    assert refreshed_login.status_code == 200
    expired_auth = {"Authorization": f"Bearer {refreshed_login.json()['access_token']}"}
    expired = _create_reservation(
        context,
        expired_auth,
        listing_id="expiry-listing",
        quote_id=expiry_quote,
        wallet_id=wallet_id,
        key="expired",
    )
    assert (expired.status_code, expired.json().get("code")) == (409, "quote_expired"), expired.text

    unlinked_customer_id, unlinked_auth = _customer_auth(
        context, email="no-wallet@example.test"
    )
    _seed_reservation_inputs(
        context,
        unlinked_customer_id,
        listing_id="customer-wallet-required",
        deposit_amount_cop=None,
        with_customer_wallet=False,
    )
    no_customer_wallet = _create_reservation(
        context,
        unlinked_auth,
        listing_id="customer-wallet-required",
        quote_id="quote-customer-wallet-required",
        wallet_id=None,
        key="no-customer-wallet",
    )
    assert (no_customer_wallet.status_code, no_customer_wallet.json()["code"]) == (
        403,
        "customer_wallet_not_linked",
    )

    foreign_customer_id, foreign_auth = _customer_auth(
        context, email="foreign-wallet@example.test"
    )
    foreign_quote, _ = _seed_reservation_inputs(
        context,
        foreign_customer_id,
        listing_id="foreign-wallet-listing",
        deposit_amount_cop=None,
    )
    foreign_wallet = _create_reservation(
        context,
        foreign_auth,
        listing_id="foreign-wallet-listing",
        quote_id=foreign_quote,
        wallet_id=wallet_id,
        key="foreign-customer-wallet",
    )
    assert (foreign_wallet.status_code, foreign_wallet.json().get("code")) == (
        403,
        "customer_wallet_not_linked",
    ), foreign_wallet.text

    no_agency_wallet_quote, linked_wallet = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="agency-wallet-required",
        agency_id="agency-without-wallet",
        deposit_amount_cop=None,
        with_agency_wallet=False,
    )
    no_agency_wallet = _create_reservation(
        context,
        expired_auth,
        listing_id="agency-wallet-required",
        quote_id=no_agency_wallet_quote,
        wallet_id=linked_wallet,
        key="no-agency-wallet",
    )
    assert (no_agency_wallet.status_code, no_agency_wallet.json()["code"]) == (
        409,
        "agency_wallet_not_linked",
    )


def test_idempotency_replays_same_body_and_rejects_key_reuse_with_different_body(
    reservations_context: ReservationsContext,
) -> None:
    context = reservations_context
    customer_id, auth = _customer_auth(context)
    first_quote, wallet_id = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="idempotent-listing-one",
        deposit_amount_cop=None,
    )
    second_quote, _ = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="idempotent-listing-two",
        deposit_amount_cop=None,
    )
    first = _create_reservation(
        context,
        auth,
        listing_id="idempotent-listing-one",
        quote_id=first_quote,
        wallet_id=wallet_id,
        key="same-key",
    )
    context.clock.advance(timedelta(minutes=15))
    refreshed_login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": "password"},
    )
    assert refreshed_login.status_code == 200
    auth = {"Authorization": f"Bearer {refreshed_login.json()['access_token']}"}
    replay = _create_reservation(
        context,
        auth,
        listing_id="idempotent-listing-one",
        quote_id=first_quote,
        wallet_id=wallet_id,
        key="same-key",
    )
    assert first.status_code == replay.status_code == 201
    assert replay.json() == first.json()

    changed = _create_reservation(
        context,
        auth,
        listing_id="idempotent-listing-two",
        quote_id=second_quote,
        wallet_id=wallet_id,
        key="same-key",
    )
    assert (changed.status_code, changed.json()["code"]) == (409, "idempotency_key_reused")


def test_active_listing_lock_reusable_quote_and_unpaid_deadline_expiry(
    reservations_context: ReservationsContext,
) -> None:
    context = reservations_context
    customer_id, auth = _customer_auth(context)
    quote_id, wallet_id = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="locked-listing",
        deposit_amount_cop=None,
    )
    first = _create_reservation(
        context,
        auth,
        listing_id="locked-listing",
        quote_id=quote_id,
        wallet_id=wallet_id,
        key="lock-one",
    )
    assert first.status_code == 201, first.text
    conflict = _create_reservation(
        context,
        auth,
        listing_id="locked-listing",
        quote_id=quote_id,
        wallet_id=wallet_id,
        key="lock-two",
    )
    assert (conflict.status_code, conflict.json()["code"]) == (
        409,
        "listing_has_active_reservation",
    )

    from app.modules.reservations.models import Reservation
    from app.modules.reservations.service import expire_unpaid_reservations

    with context.session_factory.begin() as session:
        reservation = session.get(Reservation, first.json()["reservation_id"])
        assert reservation is not None
        reservation.status = "accepted"
    accepted_conflict = _create_reservation(
        context,
        auth,
        listing_id="locked-listing",
        quote_id=quote_id,
        wallet_id=wallet_id,
        key="accepted-lock",
    )
    assert (accepted_conflict.status_code, accepted_conflict.json()["code"]) == (
        409,
        "listing_has_active_reservation",
    )

    with context.session_factory.begin() as session:
        reservation = session.get(Reservation, first.json()["reservation_id"])
        assert reservation is not None
        reservation.status = "expired"
    reusable = _create_reservation(
        context,
        auth,
        listing_id="locked-listing",
        quote_id=quote_id,
        wallet_id=wallet_id,
        key="reusable-quote",
    )
    assert reusable.status_code == 201, reusable.text

    context.clock.advance(timedelta(hours=24))
    expired_count = expire_unpaid_reservations(
        session_factory=context.session_factory,
        now=context.clock(),
        listing_id="locked-listing",
    )
    assert expired_count == 1
    with context.session_factory() as session:
        expired = session.get(Reservation, reusable.json()["reservation_id"])
        assert expired is not None and expired.status == "expired"

    refreshed_login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": "password"},
    )
    assert refreshed_login.status_code == 200
    refreshed_auth = {"Authorization": f"Bearer {refreshed_login.json()['access_token']}"}
    paid_quote, paid_wallet = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="deposit-confirmed-listing",
        deposit_amount_cop=Decimal("1000.00"),
    )
    paid = _create_reservation(
        context,
        refreshed_auth,
        listing_id="deposit-confirmed-listing",
        quote_id=paid_quote,
        wallet_id=paid_wallet,
        key="paid-lock",
    )
    assert paid.status_code == 201, paid.text
    with context.session_factory.begin() as session:
        reservation = session.get(Reservation, paid.json()["reservation_id"])
        assert reservation is not None
        reservation.deposit_confirmed_at = context.clock()
    context.clock.advance(timedelta(hours=24))
    assert expire_unpaid_reservations(
        session_factory=context.session_factory,
        now=context.clock(),
        listing_id="deposit-confirmed-listing",
    ) == 0
    deadline_login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": "password"},
    )
    assert deadline_login.status_code == 200
    deadline_auth = {"Authorization": f"Bearer {deadline_login.json()['access_token']}"}
    still_locked = _create_reservation(
        context,
        deadline_auth,
        listing_id="deposit-confirmed-listing",
        quote_id=paid_quote,
        wallet_id=paid_wallet,
        key="paid-lock-again",
    )
    assert (still_locked.status_code, still_locked.json()["code"]) == (
        409,
        "listing_has_active_reservation",
    )


def test_customer_can_only_read_and_list_own_reservations(
    reservations_context: ReservationsContext,
) -> None:
    context = reservations_context
    owner_id, owner_auth = _customer_auth(context)
    other_id, other_auth = _customer_auth(context, email="other@example.test")
    own_quote, own_wallet = _seed_reservation_inputs(
        context,
        owner_id,
        listing_id="owner-listing",
        deposit_amount_cop=None,
    )
    other_quote, other_wallet = _seed_reservation_inputs(
        context,
        other_id,
        listing_id="other-listing",
        deposit_amount_cop=None,
    )
    own = _create_reservation(
        context,
        owner_auth,
        listing_id="owner-listing",
        quote_id=own_quote,
        wallet_id=own_wallet,
        key="owner-key",
    )
    other = _create_reservation(
        context,
        other_auth,
        listing_id="other-listing",
        quote_id=other_quote,
        wallet_id=other_wallet,
        key="other-key",
    )
    assert own.status_code == other.status_code == 201

    forbidden_read = context.client.get(
        f"/api/v1/reservations/{other.json()['reservation_id']}", headers=owner_auth
    )
    assert (forbidden_read.status_code, forbidden_read.json()["code"]) == (
        404,
        "reservation_not_found",
    )
    listed = context.client.get("/api/v1/reservations", headers=owner_auth)
    assert listed.status_code == 200
    assert [item["reservation_id"] for item in listed.json()] == [
        own.json()["reservation_id"]
    ]


def test_reservation_openapi_and_cors_advertise_idempotency_header(
    reservations_context: ReservationsContext,
) -> None:
    context = reservations_context
    operation = context.client.get("/openapi.json").json()["paths"][
        "/api/v1/reservations"
    ]["post"]
    assert any(
        parameter["name"] == "Idempotency-Key" and parameter["in"] == "header"
        for parameter in operation["parameters"]
    )
    assert "201" in operation["responses"] and "409" in operation["responses"]
    preflight = context.client.options(
        "/api/v1/reservations",
        headers={
            "Origin": "https://panel.example.test",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type,idempotency-key",
        },
    )
    assert preflight.status_code == 200
    assert "idempotency-key" in preflight.headers["access-control-allow-headers"].lower()


def test_required_idempotency_key_is_validated_as_a_header(
    reservations_context: ReservationsContext,
) -> None:
    context = reservations_context
    customer_id, auth = _customer_auth(context)
    quote_id, wallet_id = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="header-required-listing",
        deposit_amount_cop=None,
    )
    response = context.client.post(
        "/api/v1/reservations",
        headers=auth,
        json={
            "listing_id": "header-required-listing",
            "quote_id": quote_id,
            "customer_wallet_id": wallet_id,
        },
    )
    assert response.status_code == 422
    assert response.json()["code"] == "validation_error"
    assert response.json()["field_errors"]


def test_whitespace_only_idempotency_key_is_rejected_before_persistence(
    reservations_context: ReservationsContext,
) -> None:
    context = reservations_context
    customer_id, auth = _customer_auth(context)
    quote_id, wallet_id = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="blank-key-listing",
        deposit_amount_cop=None,
    )

    response = _create_reservation(
        context,
        auth,
        listing_id="blank-key-listing",
        quote_id=quote_id,
        wallet_id=wallet_id,
        key="   ",
    )

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "validation_error"
    from app.modules.reservations.models import Reservation

    with context.session_factory() as session:
        assert session.query(Reservation).count() == 0


def test_create_expires_due_reservations_only_for_requested_listing(
    reservations_context: ReservationsContext,
) -> None:
    context = reservations_context
    customer_id, auth = _customer_auth(context)
    target_quote, wallet_id = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="due-target-listing",
        deposit_amount_cop=None,
    )
    unrelated_quote, _ = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="due-unrelated-listing",
        deposit_amount_cop=None,
    )
    target_original = _create_reservation(
        context,
        auth,
        listing_id="due-target-listing",
        quote_id=target_quote,
        wallet_id=wallet_id,
        key="target-original",
    )
    unrelated_original = _create_reservation(
        context,
        auth,
        listing_id="due-unrelated-listing",
        quote_id=unrelated_quote,
        wallet_id=wallet_id,
        key="unrelated-original",
    )
    assert target_original.status_code == unrelated_original.status_code == 201

    context.clock.advance(timedelta(hours=24))
    fresh_quote = "due-target-fresh-quote"
    with context.session_factory.begin() as session:
        session.add(
            QuoteSnapshot(
                id=fresh_quote,
                listing_id="due-target-listing",
                offer_version=1,
                operation="sale",
                lines=[
                    {
                        "kind": "base",
                        "extra_id": None,
                        "amount": "100000.00",
                        "currency": "COP",
                        "charge_period": "one_time",
                    }
                ],
                one_time_total=Decimal("100000.00"),
                monthly_total=Decimal("0.00"),
                created_at=context.clock(),
                expires_at=context.clock() + timedelta(minutes=15),
            )
        )

    refreshed_login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": "password"},
    )
    assert refreshed_login.status_code == 200
    refreshed_auth = {"Authorization": f"Bearer {refreshed_login.json()['access_token']}"}
    retried = _create_reservation(
        context,
        refreshed_auth,
        listing_id="due-target-listing",
        quote_id=fresh_quote,
        wallet_id=wallet_id,
        key="target-after-deadline",
    )
    assert retried.status_code == 201, retried.text

    from app.modules.reservations.models import Reservation

    with context.session_factory() as session:
        target = session.get(Reservation, target_original.json()["reservation_id"])
        unrelated = session.get(Reservation, unrelated_original.json()["reservation_id"])
        assert target is not None and target.status == "expired"
        assert unrelated is not None and unrelated.status == "pending"


def test_list_route_expires_overdue_pending_reservation_and_allows_new_creation(
    reservations_context: ReservationsContext,
) -> None:
    context = reservations_context
    customer_id, auth = _customer_auth(context)
    quote_id, wallet_id = _seed_reservation_inputs(
        context,
        customer_id,
        listing_id="list-expiry-listing",
        deposit_amount_cop=None,
    )
    original = _create_reservation(
        context,
        auth,
        listing_id="list-expiry-listing",
        quote_id=quote_id,
        wallet_id=wallet_id,
        key="list-expiry-original",
    )
    assert original.status_code == 201, original.text

    context.clock.advance(timedelta(hours=24))
    refreshed_login = context.client.post(
        "/api/v1/customer/auth/login",
        json={"email": "customer@example.test", "password": "password"},
    )
    assert refreshed_login.status_code == 200
    refreshed_auth = {"Authorization": f"Bearer {refreshed_login.json()['access_token']}"}

    listed = context.client.get("/api/v1/reservations", headers=refreshed_auth)
    assert listed.status_code == 200, listed.text
    expired = next(
        item
        for item in listed.json()
        if item["reservation_id"] == original.json()["reservation_id"]
    )
    assert expired["status"] == "expired"

    fresh_quote = "list-expiry-fresh-quote"
    with context.session_factory.begin() as session:
        session.add(
            QuoteSnapshot(
                id=fresh_quote,
                listing_id="list-expiry-listing",
                offer_version=1,
                operation="sale",
                lines=[
                    {
                        "kind": "base",
                        "extra_id": None,
                        "amount": "100000.00",
                        "currency": "COP",
                        "charge_period": "one_time",
                    }
                ],
                one_time_total=Decimal("100000.00"),
                monthly_total=Decimal("0.00"),
                created_at=context.clock(),
                expires_at=context.clock() + timedelta(minutes=15),
            )
        )
    created_after_expiry = _create_reservation(
        context,
        refreshed_auth,
        listing_id="list-expiry-listing",
        quote_id=fresh_quote,
        wallet_id=wallet_id,
        key="list-expiry-retry",
    )
    assert created_after_expiry.status_code == 201, created_after_expiry.text
