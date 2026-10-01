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
from fastapi.testclient import TestClient
from sqlalchemy import Engine, create_engine, inspect, text
from sqlalchemy.engine import URL, make_url
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings
from app.main import create_app
from app.modules.catalog.models import Listing, ListingTransition
from app.modules.identity.models import Agency
from app.modules.identity.session import get_active_staff

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_DATABASE_PREFIX = "roomforge_f04_"
_TRANSITION_REVISION = "0012_listing_transitions"
_AGENCY_ONE = "f04-agency-one"
_AGENCY_TWO = "f04-agency-two"


def _validated_postgres_url() -> URL:
    raw_url = os.environ.get("ROOMFORGE_POSTGRES_DATABASE_URL")
    if not raw_url:
        pytest.skip("ROOMFORGE_POSTGRES_DATABASE_URL is unset")
    try:
        url = make_url(raw_url)
    except Exception:
        pytest.fail("ROOMFORGE_POSTGRES_DATABASE_URL is not a valid SQLAlchemy URL")

    host = url.host
    try:
        is_loopback = host is not None and ipaddress.ip_address(host).is_loopback
    except ValueError:
        is_loopback = host == "localhost"
    if url.drivername != "postgresql+psycopg" or not is_loopback or url.port is None:
        pytest.fail("F04 PostgreSQL tests require postgresql+psycopg on an explicit loopback host and port")
    if not url.database or not url.database.startswith(_DATABASE_PREFIX):
        pytest.fail(f"F04 tests require a fresh database named with prefix {_DATABASE_PREFIX!r}")
    return url


@pytest.fixture(scope="module")
def f04_postgres_engine() -> Iterator[Engine]:
    url = _validated_postgres_url()
    engine = create_engine(url, pool_pre_ping=True)
    try:
        if inspect(engine).get_table_names():
            pytest.fail("F04 PostgreSQL tests require a fresh, completely blank database")

        config = Config(str(_BACKEND_ROOT / "alembic.ini"))
        config.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
        connection_url = url.render_as_string(hide_password=False)
        config.set_main_option("sqlalchemy.url", connection_url.replace("%", "%%"))
        script = ScriptDirectory.from_config(config)
        revisions = {
            revision.revision for revision in script.iterate_revisions("head", "base")
        }
        if _TRANSITION_REVISION not in revisions:
            pytest.fail(f"Alembic chain does not include {_TRANSITION_REVISION}")

        with patch.dict(os.environ, {"DATABASE_URL": connection_url}):
            command.upgrade(config, "head")

        with engine.connect() as connection:
            current_revision = connection.execute(
                text("SELECT version_num FROM alembic_version")
            ).scalar_one()
        if current_revision != script.get_current_head():
            pytest.fail("F04 PostgreSQL database did not reach the current Alembic head")
        yield engine
    finally:
        engine.dispose()


def _payload(**changes: object) -> dict[str, object]:
    result: dict[str, object] = {
        "operation": "sale",
        "base_price": "125000.00",
        "city": "Medellín",
        "zone": "El Poblado",
        "bedrooms": 3,
        "bathrooms": 2,
        "description": "A bright apartment",
        "exact_address": "Private address",
    }
    result.update(changes)
    return result


def _listing_url(agency_id: str, listing_id: str) -> str:
    return f"/api/v1/staff/agencies/{agency_id}/listings/{listing_id}"


def _collection_url(agency_id: str) -> str:
    return f"/api/v1/staff/agencies/{agency_id}/listings"


def _listing_state(
    factory: sessionmaker[Session], listing_id: str
) -> tuple[str, bool, int]:
    with factory() as session:
        listing = session.get(Listing, listing_id)
        assert listing is not None
        return listing.approval_status, listing.is_published, listing.offer_version


def _history_actions(factory: sessionmaker[Session], listing_id: str) -> list[str]:
    with factory() as session:
        rows = (
            session.query(ListingTransition)
            .filter(ListingTransition.listing_id == listing_id)
            .order_by(ListingTransition.created_at, ListingTransition.id)
            .all()
        )
        return [row.action for row in rows]


def _public_listing_ids(client: TestClient) -> set[str]:
    response = client.get("/api/v1/listings")
    assert response.status_code == 200, response.text
    return {item["listing_id"] for item in response.json()["items"]}


def test_f04_publications_against_real_postgres(f04_postgres_engine: Engine) -> None:
    engine = f04_postgres_engine
    inspector = inspect(engine)
    assert "listing_transition" in inspector.get_table_names()
    assert {column["name"] for column in inspector.get_columns("listing_transition")} == {
        "id",
        "agency_id",
        "listing_id",
        "action",
        "from_status",
        "from_published",
        "to_status",
        "to_published",
        "observation",
        "actor_id",
        "actor_role",
        "created_at",
    }
    indexes = {
        index["name"]: tuple(index["column_names"])
        for index in inspector.get_indexes("listing_transition")
    }
    assert indexes == {
        "ix_listing_transition_listing_id": ("listing_id",),
        "ix_listing_transition_listing_id_created_at": ("listing_id", "created_at"),
    }

    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    with factory.begin() as session:
        session.add_all([Agency(id=_AGENCY_ONE), Agency(id=_AGENCY_TWO)])

    clock_start = datetime.now(timezone.utc)
    clock_ticks = count()
    app = create_app(
        settings=Settings(
            database_url=engine.url.render_as_string(hide_password=False),
            jwt_secret="f04-postgres-test-secret-at-least-32-bytes",
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
    act_as("agency_admin", _AGENCY_ONE, "f04-admin-one")

    with TestClient(app) as client:
        # Create and edit through the API; PostgreSQL's offer-version trigger owns versioning.
        created = client.post(_collection_url(_AGENCY_ONE), json=_payload())
        assert created.status_code == 201, created.text
        listing_id = created.json()["listing_id"]
        url = _listing_url(_AGENCY_ONE, listing_id)
        assert created.json()["approval_status"] == "draft"
        assert created.json()["is_published"] is False
        assert created.json()["offer_version"] == 1
        assert _history_actions(factory, listing_id) == ["create"]

        description_edit = client.put(
            url,
            json=_payload(description="A newly described bright apartment"),
        )
        assert description_edit.status_code == 200, description_edit.text
        assert description_edit.json()["offer_version"] == 1
        assert _listing_state(factory, listing_id)[2] == 1
        assert _history_actions(factory, listing_id) == ["create", "edit"]

        price_edit = client.put(url, json=_payload(base_price="130000.00"))
        assert price_edit.status_code == 200, price_edit.text
        assert price_edit.json()["offer_version"] == 2
        assert _listing_state(factory, listing_id)[2] == 2
        assert _history_actions(factory, listing_id) == ["create", "edit", "edit"]

        submitted = client.post(url + "/submit")
        assert submitted.status_code == 200, submitted.text
        assert submitted.json()["approval_status"] == "pending"
        assert _history_actions(factory, listing_id) == ["create", "edit", "edit", "submit"]

        approved = client.post(url + "/approve")
        assert approved.status_code == 200, approved.text
        assert approved.json()["approval_status"] == "approved"
        assert _history_actions(factory, listing_id) == [
            "create",
            "edit",
            "edit",
            "submit",
            "approve",
        ]

        published = client.post(url + "/publish")
        assert published.status_code == 200, published.text
        assert published.json()["is_published"] is True
        assert listing_id in _public_listing_ids(client)
        assert _history_actions(factory, listing_id) == [
            "create",
            "edit",
            "edit",
            "submit",
            "approve",
            "publish",
        ]

        transitions = client.get(url + "/transitions")
        assert transitions.status_code == 200, transitions.text
        assert [row["action"] for row in transitions.json()] == _history_actions(
            factory, listing_id
        )
        assert transitions.json()[0]["from_status"] is None
        assert transitions.json()[0]["to_status"] == "draft"
        assert all(row["actor_id"] == "f04-admin-one" for row in transitions.json())

        unpublished = client.post(url + "/unpublish")
        assert unpublished.status_code == 200, unpublished.text
        assert unpublished.json()["is_published"] is False
        assert listing_id not in _public_listing_ids(client)
        assert _listing_state(factory, listing_id)[:2] == ("approved", False)
        expected_history = [
            "create",
            "edit",
            "edit",
            "submit",
            "approve",
            "publish",
            "unpublish",
        ]
        assert _history_actions(factory, listing_id) == expected_history
        transitions = client.get(url + "/transitions")
        assert transitions.status_code == 200, transitions.text
        assert [row["action"] for row in transitions.json()] == expected_history

        # Rejection requires a meaningful reason; a rejected listing cannot be published.
        rejected_create = client.post(_collection_url(_AGENCY_ONE), json=_payload())
        assert rejected_create.status_code == 201, rejected_create.text
        rejected_id = rejected_create.json()["listing_id"]
        rejected_url = _listing_url(_AGENCY_ONE, rejected_id)
        rejected_submit = client.post(rejected_url + "/submit")
        assert rejected_submit.status_code == 200, rejected_submit.text
        pending_state = _listing_state(factory, rejected_id)
        pending_history = _history_actions(factory, rejected_id)
        for reason in ("", "   "):
            invalid_rejection = client.post(
                rejected_url + "/reject", json={"observation": reason}
            )
            assert invalid_rejection.status_code == 422
            assert _listing_state(factory, rejected_id) == pending_state
            assert _history_actions(factory, rejected_id) == pending_history

        rejected = client.post(
            rejected_url + "/reject", json={"observation": "  Missing documents  "}
        )
        assert rejected.status_code == 200, rejected.text
        assert rejected.json()["approval_status"] == "rejected"
        rejected_history = _history_actions(factory, rejected_id)
        assert rejected_history == ["create", "submit", "reject"]
        assert rejected.json()["offer_version"] == pending_state[2]

        state_before_failed_publish = _listing_state(factory, rejected_id)
        history_before_failed_publish = _history_actions(factory, rejected_id)
        failed_publish = client.post(rejected_url + "/publish")
        assert failed_publish.status_code == 409, failed_publish.text
        assert _listing_state(factory, rejected_id) == state_before_failed_publish
        assert _history_actions(factory, rejected_id) == history_before_failed_publish

        # An agent is denied an otherwise-valid administrative publish without mutation.
        act_as("agent", _AGENCY_ONE, "f04-agent-one")
        state_before_agent = _listing_state(factory, listing_id)
        history_before_agent = _history_actions(factory, listing_id)
        agent_publish = client.post(url + "/publish")
        assert agent_publish.status_code == 403, agent_publish.text
        assert _listing_state(factory, listing_id) == state_before_agent
        assert _history_actions(factory, listing_id) == history_before_agent

        # Tenant mismatch is forbidden and cannot alter the listing or its history.
        act_as("agency_admin", _AGENCY_TWO, "f04-admin-two")
        state_before_mismatch = _listing_state(factory, listing_id)
        history_before_mismatch = _history_actions(factory, listing_id)
        mismatch = client.put(
            url,
            json=_payload(base_price="140000.00", description="Must not be applied"),
        )
        assert mismatch.status_code == 403, mismatch.text
        assert _listing_state(factory, listing_id) == state_before_mismatch
        assert _history_actions(factory, listing_id) == history_before_mismatch

        # A listing owned by another agency is 404, indistinguishable from an absent listing.
        foreign_create = client.post(_collection_url(_AGENCY_TWO), json=_payload())
        assert foreign_create.status_code == 201, foreign_create.text
        foreign_id = foreign_create.json()["listing_id"]
        foreign_state = _listing_state(factory, foreign_id)
        foreign_history = _history_actions(factory, foreign_id)

        act_as("agency_admin", _AGENCY_ONE, "f04-admin-one")
        foreign = client.get(_listing_url(_AGENCY_ONE, foreign_id) + "/transitions")
        absent = client.get(_listing_url(_AGENCY_ONE, "absent-listing") + "/transitions")
        assert foreign.status_code == absent.status_code == 404
        assert (foreign.json().get("code"), foreign.json().get("detail")) == (
            absent.json().get("code"),
            absent.json().get("detail"),
        )
        assert _listing_state(factory, foreign_id) == foreign_state
        assert _history_actions(factory, foreign_id) == foreign_history
