"""F10 — End-to-end journey across surfaces: agency → panel → customer.

One automated walk over real PostgreSQL and the full Alembic chain, the same
E2E level as the F04 disposable-database test. The listing is authored and
driven through the staff API, published from the panel-side transitions, and
consumed by a real customer account through the public catalog, quotes, and
reservations APIs. Wallets are linked through the challenge/signature API
flow with real Ethereum signatures.

Documented limits (see odd/tasks/f10-e2e-agency-customer-journey.md):
- Staff actors are injected through the ``get_active_staff`` override; the
  panel's real TOTP login is covered by its own Node E2E.
- The confirmed photo required by F04.2 is seeded as a row, like the F04
  E2E does; the photo pipeline has its own extensive coverage.
- The quote runs in the listing currency; target-currency conversion needs
  exchange rates (F05 coverage) and is left out of this journey.
"""

from __future__ import annotations

import base64
import ipaddress
import os
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from itertools import count
from pathlib import Path
from unittest.mock import patch

import pytest
from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory
from eth_account import Account
from eth_account.messages import encode_defunct
from fastapi.testclient import TestClient
from sqlalchemy import Engine, create_engine, inspect, text
from sqlalchemy.engine import URL, make_url
from sqlalchemy.orm import sessionmaker

from app.core.config import Settings
from app.main import create_app
from app.modules.catalog.models import ListingPhoto
from app.modules.identity.models import Agency
from app.modules.identity.session import get_active_staff

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_DATABASE_PREFIX = "roomforge_f10_"
_AGENCY_ONE = "f10-agency-one"
_AGENCY_TWO = "f10-agency-two"
_AGENCY_WALLET_KEY = "0x" + "11" * 32
_CUSTOMER_WALLET_KEY = "0x" + "22" * 32


def _validated_journey_url() -> URL:
    raw_url = os.environ.get("ROOMFORGE_F10_DATABASE_URL")
    if not raw_url:
        pytest.skip("ROOMFORGE_F10_DATABASE_URL is unset")
    try:
        url = make_url(raw_url)
    except Exception:
        pytest.fail("ROOMFORGE_F10_DATABASE_URL is not a valid SQLAlchemy URL")

    host = url.host
    try:
        is_loopback = host is not None and ipaddress.ip_address(host).is_loopback
    except ValueError:
        is_loopback = host == "localhost"
    if url.drivername != "postgresql+psycopg" or not is_loopback or url.port is None:
        pytest.fail("F10 journey tests require postgresql+psycopg on an explicit loopback host and port")
    if not url.database or not url.database.startswith(_DATABASE_PREFIX):
        pytest.fail(f"F10 journey tests require a fresh database named with prefix {_DATABASE_PREFIX!r}")
    return url


def _wallet_address(private_key: str) -> str:
    return Account.from_key(private_key).address.lower()


def _signature(message: str, private_key: str) -> str:
    return Account.sign_message(
        encode_defunct(text=message), private_key=private_key
    ).signature.hex()


def _payload() -> dict[str, object]:
    return {
        "operation": "sale",
        "base_price": "125000.00",
        "currency": "BOB",
        "city": "Medellín",
        "zone": "El Poblado",
        "bedrooms": 3,
        "bathrooms": 2,
        "description": "A bright apartment ready for its first customer",
        "exact_address": "Private address",
        "extras": [
            {
                "name": "Cama queen con colchón nuevo",
                "price": "5000.00",
                "quantity": 1,
            }
        ],
    }


@pytest.fixture(scope="module")
def journey_postgres_engine() -> Iterator[Engine]:
    url = _validated_journey_url()
    engine = create_engine(url, pool_pre_ping=True)
    try:
        if inspect(engine).get_table_names():
            pytest.fail("F10 journey tests require a fresh, completely blank database")

        config = Config(str(_BACKEND_ROOT / "alembic.ini"))
        config.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
        connection_url = url.render_as_string(hide_password=False)
        config.set_main_option("sqlalchemy.url", connection_url.replace("%", "%%"))
        with patch.dict(os.environ, {"DATABASE_URL": connection_url}):
            command.upgrade(config, "head")

        with engine.connect() as connection:
            current_revision = connection.execute(
                text("SELECT version_num FROM alembic_version")
            ).scalar_one()
        script = ScriptDirectory.from_config(config)
        if current_revision != script.get_current_head():
            pytest.fail("F10 journey database did not reach the current Alembic head")
        yield engine
    finally:
        engine.dispose()


def test_agency_to_customer_journey_e2e(journey_postgres_engine: Engine) -> None:
    engine = journey_postgres_engine
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    with factory.begin() as session:
        session.add_all([Agency(id=_AGENCY_ONE), Agency(id=_AGENCY_TWO)])

    clock_start = datetime.now(timezone.utc)
    clock_ticks = count()
    app = create_app(
        settings=Settings(
            database_url=engine.url.render_as_string(hide_password=False),
            jwt_secret="f10-journey-test-secret-at-least-32-bytes",
            totp_encryption_key=base64.urlsafe_b64encode(b"f" * 32).decode("ascii"),
            web_origin="http://localhost",
        ),
        session_factory=factory,
        clock=lambda: clock_start + timedelta(seconds=next(clock_ticks)),
    )
    actor: dict[str, str | None] = {}

    def act_as(role: str, tenant_id: str, actor_id: str) -> None:
        actor.clear()
        actor.update(
            {
                "id": actor_id,
                "email": f"{actor_id}@example.test",
                "role": role,
                "tenant_id": tenant_id,
            }
        )

    app.dependency_overrides[get_active_staff] = lambda: actor

    with TestClient(app) as client:
        # --- Agency surface: the agent authors the listing (F04.1) ------------
        act_as("agency_admin", _AGENCY_ONE, "f10-admin-one")
        collection_url = f"/api/v1/staff/agencies/{_AGENCY_ONE}/listings"
        created = client.post(collection_url, json=_payload())
        assert created.status_code == 201, created.text
        listing = created.json()
        listing_id = listing["listing_id"]
        listing_url = f"{collection_url}/{listing_id}"
        assert listing["approval_status"] == "draft"
        assert listing["is_published"] is False
        assert listing["offer_version"] == 1
        assert len(listing["extras"]) == 1
        extra_id = listing["extras"][0]["extra_id"]

        # --- Cross-surface isolation before publication ------------------------
        public_before = client.get("/api/v1/listings")
        assert public_before.status_code == 200
        assert all(
            item["listing_id"] != listing_id for item in public_before.json()["items"]
        ), "a draft listing must never reach the customer catalog"

        # --- The confirmed photo F04.2 requires before review (seeded row) -----
        with factory.begin() as session:
            session.add(
                ListingPhoto(
                    agency_id=_AGENCY_ONE,
                    listing_id=listing_id,
                    object_key=f"agencies/{_AGENCY_ONE}/listings/{listing_id}/photos/seeded",
                    status="confirmed",
                    content_type="image/jpeg",
                    size_bytes=10,
                    created_at=clock_start,
                    expires_at=clock_start + timedelta(minutes=15),
                    confirmed_at=clock_start,
                )
            )

        # --- Panel surface: review and publication (F04.3, admin transitions) --
        submitted = client.post(f"{listing_url}/submit")
        assert submitted.status_code == 200, submitted.text
        assert submitted.json()["approval_status"] == "pending_review"
        approved = client.post(f"{listing_url}/approve")
        assert approved.status_code == 200, approved.text
        assert approved.json()["approval_status"] == "approved"
        published = client.post(f"{listing_url}/publish")
        assert published.status_code == 200, published.text
        assert published.json()["is_published"] is True

        history = client.get(f"{listing_url}/transitions")
        assert history.status_code == 200
        assert [entry["action"] for entry in history.json()] == [
            "create",
            "submit",
            "approve",
            "publish",
        ]

        # --- Cross-surface isolation after publication: the other agency ------
        act_as("agency_admin", _AGENCY_TWO, "f10-admin-two")
        other_agency_list = client.get(f"/api/v1/staff/agencies/{_AGENCY_TWO}/listings")
        assert other_agency_list.status_code == 200
        assert all(
            item["listing_id"] != listing_id for item in other_agency_list.json()
        )
        foreign_edit = client.put(listing_url, json=_payload())
        assert foreign_edit.status_code == 403, foreign_edit.text
        foreign_publish = client.post(f"{listing_url}/publish")
        assert foreign_publish.status_code == 403, foreign_publish.text

        # --- Customer surface: catalog and detail (F04.4) -----------------------
        registered = client.post(
            "/api/v1/customer/auth/register",
            json={"email": "f10-customer@example.test", "password": "password"},
        )
        assert registered.status_code == 201, registered.text
        registered.json()["id"]
        login = client.post(
            "/api/v1/customer/auth/login",
            json={"email": "f10-customer@example.test", "password": "password"},
        )
        assert login.status_code == 200, login.text
        customer_headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

        catalog = client.get("/api/v1/listings", params={"city": "Medellín"})
        assert catalog.status_code == 200, catalog.text
        matched = [
            item
            for item in catalog.json()["items"]
            if item["listing_id"] == listing_id
        ]
        assert len(matched) == 1, "the published listing must be reachable through the catalog"

        detail = client.get(f"/api/v1/listings/{listing_id}")
        assert detail.status_code == 200, detail.text
        detail_extras = detail.json()["extras"]
        assert [extra["extra_id"] for extra in detail_extras] == [extra_id]

        # --- Quote (F05): base plus the selected extra, snapshot returned ------
        quote = client.post(
            "/api/v1/quotes",
            json={
                "listing_id": listing_id,
                "offer_version": 1,
                "selected_extra_ids": [extra_id],
            },
        )
        assert quote.status_code == 201, quote.text
        quote_snapshot = quote.json()
        quote_id = quote_snapshot["quote_id"]
        assert [line["kind"] for line in quote_snapshot["lines"]] == ["base", "extra"]

        # --- Wallets linked through the real challenge/signature flow ----------
        agency_challenge = client.post(
            f"/api/v1/staff/agencies/{_AGENCY_ONE}/wallet-challenges",
            json={"address": _wallet_address(_AGENCY_WALLET_KEY)},
        )
        assert agency_challenge.status_code == 201, agency_challenge.text
        agency_wallet = client.put(
            f"/api/v1/staff/agencies/{_AGENCY_ONE}/wallet",
            json={
                "challenge_id": agency_challenge.json()["challenge_id"],
                "signature": _signature(
                    agency_challenge.json()["message"], _AGENCY_WALLET_KEY
                ),
            },
        )
        assert agency_wallet.status_code == 200, agency_wallet.text

        customer_challenge = client.post(
            "/api/v1/customer/wallet-challenges",
            json={"address": _wallet_address(_CUSTOMER_WALLET_KEY)},
            headers=customer_headers,
        )
        assert customer_challenge.status_code == 201, customer_challenge.text
        customer_wallet = client.post(
            "/api/v1/customer/wallets",
            json={
                "challenge_id": customer_challenge.json()["challenge_id"],
                "signature": _signature(
                    customer_challenge.json()["message"], _CUSTOMER_WALLET_KEY
                ),
            },
            headers=customer_headers,
        )
        assert customer_wallet.status_code == 201, customer_wallet.text
        customer_wallet_id = customer_wallet.json()["id"]

        # --- Reservation (F09 as integrated): escrow-backed, idempotent --------
        reservation = client.post(
            "/api/v1/reservations",
            json={
                "listing_id": listing_id,
                "quote_id": quote_id,
                "customer_wallet_id": customer_wallet_id,
            },
            headers={**customer_headers, "Idempotency-Key": "f10-journey-reservation-1"},
        )
        assert reservation.status_code == 201, reservation.text
        reservation_body = reservation.json()
        reservation_id = reservation_body["reservation_id"]
        assert reservation_body["status"] == "pending"
        assert reservation_body["listing_id"] == listing_id
        assert reservation_body["quote_snapshot"]["quote_id"] == quote_id

        replay = client.post(
            "/api/v1/reservations",
            json={
                "listing_id": listing_id,
                "quote_id": quote_id,
                "customer_wallet_id": customer_wallet_id,
            },
            headers={**customer_headers, "Idempotency-Key": "f10-journey-reservation-1"},
        )
        assert replay.status_code == 201, replay.text
        assert replay.json()["reservation_id"] == reservation_id, (
            "the same idempotency key must return the same reservation"
        )

        own_reservations = client.get("/api/v1/reservations", headers=customer_headers)
        assert own_reservations.status_code == 200
        assert [
            item["reservation_id"] for item in own_reservations.json()
        ] == [reservation_id]

        # --- Closing the loop: quote changes must not touch the reservation ----
        act_as("agency_admin", _AGENCY_ONE, "f10-admin-one")
        repriced = client.put(
            listing_url,
            json={**_payload(), "base_price": "140000.00"},
        )
        assert repriced.status_code == 200, repriced.text
        assert repriced.json()["offer_version"] == 2

        own_after_reprice = client.get("/api/v1/reservations", headers=customer_headers)
        assert own_after_reprice.status_code == 200
        still_reserved = own_after_reprice.json()[0]
        assert still_reserved["reservation_id"] == reservation_id
        assert still_reserved["quote_snapshot"]["offer_version"] == 1, (
            "the reservation snapshot must stay immutable after a repricing"
        )
