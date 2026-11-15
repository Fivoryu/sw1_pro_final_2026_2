"""Shared fixtures and seeding helpers for the agency chat tests (F14.6)."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal

from app.modules.catalog.models import Listing
from app.modules.chat.models import ListingAgent
from app.modules.identity.models import Agency

from test_agencies import (  # noqa: F401  (re-exported fixture and helpers)
    AgencyApiContext,
    _headers,
    _seed_account,
    agency_api_context,
)

AGENCY = "agency-chat"


def seed_listing(
    context: AgencyApiContext,
    listing_id: str = "listing-chat",
    *,
    agency_id: str = AGENCY,
    approval_status: str = "approved",
    is_published: bool = True,
) -> None:
    with context.session_factory.begin() as session:
        if session.get(Agency, agency_id) is None:
            session.add(Agency(id=agency_id, name="Casa Norte"))
            session.flush()
        session.add(
            Listing(
                id=listing_id,
                agency_id=agency_id,
                approval_status=approval_status,
                is_published=is_published,
                operation="sale",
                base_price=Decimal("100000.00"),
                offer_version=1,
                city="Santa Cruz",
                zone="Equipetrol",
                bedrooms=2,
                bathrooms=1,
                created_at=datetime(2026, 9, 1, tzinfo=timezone.utc),
                description=None,
                exact_address=None,
                photos=[],
            )
        )


def seed_staff(
    context: AgencyApiContext,
    account_id: str,
    *,
    role: str = "agent",
    agency_id: str | None = AGENCY,
    active: bool = True,
) -> dict[str, str]:
    token = _seed_account(
        context,
        account_id=account_id,
        role=role,
        tenant_id=agency_id,
        active=active,
    )
    return _headers(token)


def assign(context: AgencyApiContext, listing_id: str, *agent_ids: str) -> None:
    with context.session_factory.begin() as session:
        for agent_id in agent_ids:
            session.add(
                ListingAgent(listing_id=listing_id, agent_id=agent_id, assigned_at=context.now)
            )


def register_customer(
    context: AgencyApiContext, email: str = "customer@example.test"
) -> tuple[str, dict[str, str]]:
    registered = context.client.post(
        "/api/v1/customer/auth/register", json={"email": email, "password": "password"}
    )
    assert registered.status_code == 201
    login = context.client.post(
        "/api/v1/customer/auth/login", json={"email": email, "password": "password"}
    )
    assert login.status_code == 200
    return registered.json()["id"], {"Authorization": f"Bearer {login.json()['access_token']}"}
