"""Agency dashboard metrics must count listings by the states the database really stores."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.modules.agencies.service import get_agency_metrics
from app.modules.catalog.models import Listing
from app.modules.identity.models import Agency

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
            # Approved but withdrawn from the catalog and rejected ones are not shown.
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
