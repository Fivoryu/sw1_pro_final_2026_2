"""Agency dashboard metrics (F14.4): consistent with the stored states and isolated per agency."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.modules.agencies.service import get_agency_metrics
from app.modules.catalog.models import Listing, QuoteSnapshot
from app.modules.identity.models import Agency
from app.modules.reservations.models import Reservation
from chat_support import AgencyApiContext, register_customer, seed_listing, seed_staff

NOW = datetime(2026, 11, 14, 12, 0, tzinfo=timezone.utc)


@pytest.fixture
def session_factory():
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, expire_on_commit=False)
    yield factory
    engine.dispose()


def _listing(listing_id: str, agency_id: str, status: str, published: bool = False) -> Listing:
    return Listing(
        id=listing_id,
        agency_id=agency_id,
        approval_status=status,
        is_published=published,
        operation="sale",
        base_price=Decimal("100000.00"),
        currency="BOB",
        offer_version=1,
        city="La Paz",
        city_key="la paz",
        zone="Centro",
        zone_key="centro",
        bedrooms=2,
        bathrooms=1,
        description="Inmueble de prueba",
    )


def _seed(factory: sessionmaker[Session], listings: list[Listing]) -> None:
    with factory() as session:
        session.add_all([Agency(id="agency-a"), Agency(id="agency-b")])
        session.flush()
        session.add_all(listings)
        session.commit()


def test_listing_metrics_use_real_states_and_the_published_flag(
    session_factory: sessionmaker[Session],
) -> None:
    _seed(
        session_factory,
        [
            _listing("d1", "agency-a", "draft"),
            _listing("d2", "agency-a", "draft"),
            _listing("p1", "agency-a", "pending"),
            _listing("pub1", "agency-a", "approved", published=True),
            _listing("pub2", "agency-a", "approved", published=True),
            _listing("pub3", "agency-a", "approved", published=True),
            # Approved but not published and rejected ones have their own cards (F14.4 D2).
            _listing("a-off", "agency-a", "approved", published=False),
            _listing("r1", "agency-a", "rejected"),
        ],
    )

    metrics = get_agency_metrics(
        session_factory=session_factory, agency_id="agency-a", now=NOW
    )

    assert metrics.listings.draft == 2
    assert metrics.listings.in_review == 1
    assert metrics.listings.published == 3
    assert metrics.listings.approved_unpublished == 1
    assert metrics.listings.rejected == 1
    assert metrics.listings.total == 8
    assert metrics.active_quotes == 0
    assert metrics.reservations.pending == 0


def test_listing_metrics_never_include_another_agency(
    session_factory: sessionmaker[Session],
) -> None:
    _seed(
        session_factory,
        [
            _listing("a1", "agency-a", "pending"),
            _listing("b1", "agency-b", "pending"),
            _listing("b2", "agency-b", "approved", published=True),
            _listing("b3", "agency-b", "draft"),
        ],
    )

    metrics = get_agency_metrics(
        session_factory=session_factory, agency_id="agency-a", now=NOW
    )

    assert metrics.listings.draft == 0
    assert metrics.listings.in_review == 1
    assert metrics.listings.published == 0


def test_listing_metrics_are_zero_for_an_agency_without_listings(
    session_factory: sessionmaker[Session],
) -> None:
    _seed(session_factory, [])

    metrics = get_agency_metrics(
        session_factory=session_factory, agency_id="agency-a", now=NOW
    )

    assert (metrics.listings.draft, metrics.listings.in_review, metrics.listings.published) == (0, 0, 0)


# --- Route: GET /api/v1/staff/agencies/{agency_id}/metrics -------------------

AGENCY = "agency-chat"
OTHER = "agency-other"
METRICS = f"/api/v1/staff/agencies/{AGENCY}/metrics"


def _seed_quote(context: AgencyApiContext, quote_id: str, listing_id: str, expires_at: datetime) -> None:
    with context.session_factory.begin() as session:
        session.add(
            QuoteSnapshot(
                id=quote_id,
                listing_id=listing_id,
                offer_version=1,
                operation="sale",
                lines=[],
                one_time_total=Decimal("1.00"),
                monthly_total=Decimal("0.00"),
                created_at=context.now - timedelta(minutes=30),
                expires_at=expires_at,
            )
        )


def _seed_reservation(
    context: AgencyApiContext, reservation_id: str, listing_id: str, status: str
) -> None:
    with context.session_factory.begin() as session:
        session.add(
            Reservation(
                id=reservation_id,
                listing_id=listing_id,
                quote_id=f"quote-{reservation_id}",
                customer_id=f"customer-{reservation_id}",
                payment_method="card",
                offer_version=1,
                operation="sale",
                quote_lines=[],
                one_time_total=Decimal("1.00"),
                monthly_total=Decimal("0.00"),
                api_created_at=context.now,
                decision_deadline_at=context.now + timedelta(hours=1),
                status=status,
                idempotency_key=f"key-{reservation_id}",
                request_fingerprint="a" * 64,
            )
        )


def _seed_dashboard(context: AgencyApiContext) -> None:
    for listing_id, status, published in (
        ("draft-1", "draft", False),
        ("pending-1", "pending", False),
        ("pending-2", "pending", False),
        ("live-1", "approved", True),
        ("live-2", "approved", True),
        ("off-1", "approved", False),
        ("rejected-1", "rejected", False),
    ):
        seed_listing(context, listing_id, approval_status=status, is_published=published)
    seed_listing(context, "other-live", agency_id=OTHER, approval_status="approved", is_published=True)
    seed_listing(context, "other-draft", agency_id=OTHER, approval_status="draft", is_published=False)

    _seed_quote(context, "quote-live", "live-1", context.now + timedelta(minutes=5))
    _seed_quote(context, "quote-live-2", "live-2", context.now + timedelta(minutes=10))
    _seed_quote(context, "quote-expired", "live-1", context.now - timedelta(seconds=1))
    _seed_quote(context, "quote-other", "other-live", context.now + timedelta(minutes=5))

    _seed_reservation(context, "res-pending", "live-1", "pending")
    _seed_reservation(context, "res-accepted", "live-2", "accepted")
    _seed_reservation(context, "res-cancelled", "live-1", "cancelled")
    _seed_reservation(context, "res-expired", "live-1", "expired")
    _seed_reservation(context, "res-other", "other-live", "accepted")


def test_the_agency_admin_sees_metrics_consistent_with_the_database(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _seed_dashboard(context)
    admin = seed_staff(context, "admin-1", role="agency_admin")

    response = context.client.get(METRICS, headers=admin)

    assert response.status_code == 200, response.text
    assert response.json() == {
        "listings": {
            "draft": 1,
            "in_review": 2,
            "published": 2,
            "approved_unpublished": 1,
            "rejected": 1,
            "total": 7,
        },
        "active_quotes": 2,
        "reservations": {
            "pending": 1,
            "accepted": 1,
            "rejected": 0,
            "cancelled": 1,
            "expired": 1,
        },
    }
    listings = response.json()["listings"]
    assert sum(value for key, value in listings.items() if key != "total") == listings["total"]


@pytest.mark.parametrize(
    ("account_id", "role", "agency_id"),
    [
        ("agent-1", "agent", AGENCY),
        ("other-admin", "agency_admin", OTHER),
        ("other-agent", "agent", OTHER),
        ("platform-1", "platform_admin", None),
    ],
    ids=["own-agency-agent", "other-agency-admin", "other-agency-agent", "platform-admin"],
)
def test_only_the_agency_admin_of_that_agency_can_read_its_metrics(
    agency_api_context: AgencyApiContext, account_id: str, role: str, agency_id: str | None
) -> None:
    context = agency_api_context
    _seed_dashboard(context)
    headers = seed_staff(context, account_id, role=role, agency_id=agency_id)

    response = context.client.get(METRICS, headers=headers)

    assert response.status_code == 403
    assert "listings" not in response.json()


def test_metrics_of_an_unknown_agency_are_forbidden_like_another_agency(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _seed_dashboard(context)
    admin = seed_staff(context, "admin-1", role="agency_admin")

    unknown = context.client.get("/api/v1/staff/agencies/missing-agency/metrics", headers=admin)
    other = context.client.get(f"/api/v1/staff/agencies/{OTHER}/metrics", headers=admin)

    assert unknown.status_code == other.status_code == 403
    assert unknown.json() == other.json()


def test_metrics_require_a_staff_session(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    _seed_dashboard(context)
    _, customer = register_customer(context)

    anonymous = context.client.get(METRICS)
    malformed = context.client.get(METRICS, headers={"Authorization": "Bearer not-a-token"})
    as_customer = context.client.get(METRICS, headers=customer)

    assert anonymous.status_code == malformed.status_code == as_customer.status_code == 401

