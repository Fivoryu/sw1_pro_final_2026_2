from __future__ import annotations

import base64
import json
from collections.abc import Iterator
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any, cast

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.modules.catalog.models import Listing
from app.modules.identity.models import Agency
from app.modules.identity.session import get_active_staff


@dataclass
class SceneContext:
    client: TestClient
    app: FastAPI
    session_factory: sessionmaker[Session]


@pytest.fixture
def scene_context() -> Iterator[SceneContext]:
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    Base.metadata.create_all(engine)
    app = create_app(
        settings=Settings(
            database_url="sqlite+pysqlite:///:memory:",
            jwt_secret="scene-test-secret-that-is-at-least-thirty-two-bytes",
            totp_encryption_key=base64.urlsafe_b64encode(b"0" * 32).decode(),
            web_origin="http://localhost",
        ),
        session_factory=factory,
    )
    with TestClient(app) as client:
        yield SceneContext(client, app, factory)
    engine.dispose()


def _staff(
    context: SceneContext,
    *,
    role: str = "agency_admin",
    tenant_id: str | None = "agency-one",
    actor_id: str = "scene-actor",
) -> None:
    if tenant_id is not None:
        with context.session_factory.begin() as session:
            if session.get(Agency, tenant_id) is None:
                session.add(Agency(id=tenant_id))
    context.app.dependency_overrides[get_active_staff] = lambda: {
        "id": actor_id,
        "email": f"{actor_id}@example.test",
        "role": role,
        "tenant_id": tenant_id,
    }


def _seed_listing(
    context: SceneContext,
    listing_id: str = "scene-listing",
    *,
    agency_id: str = "agency-one",
) -> None:
    with context.session_factory.begin() as session:
        if session.get(Agency, agency_id) is None:
            session.add(Agency(id=agency_id))
            session.flush()
        session.add(
            Listing(
                id=listing_id,
                agency_id=agency_id,
                approval_status="draft",
                is_published=False,
                operation="sale",
                base_price=Decimal("100000.00"),
                offer_version=1,
                city="Córdoba",
                zone="Centro",
                bedrooms=2,
                bathrooms=1,
            )
        )


def _scene_url(
    agency_id: str = "agency-one", listing_id: str = "scene-listing"
) -> str:
    return f"/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/scene"


def _scene_document() -> dict[str, Any]:
    return {
        "version": "1.0",
        "unit": "meters",
        "rooms": [
            {
                "id": "room_main",
                "height": 2.4,
                "contours": [
                    {"x": 0, "z": 0},
                    {"x": 4, "z": 0},
                    {"x": 4, "z": 3},
                    {"x": 0, "z": 3},
                ],
                "openings": [
                    {
                        "id": "door_1",
                        "type": "door",
                        "position": {"x": 2, "y": 0, "z": 0},
                        "width": 0.9,
                        "height": 2.1,
                    }
                ],
            }
        ],
        "objects": [
            {
                "id": "ref_cube_1",
                "type": "placeholder",
                "position": {"x": 1, "y": 0, "z": 1},
                "dimensions": {"width": 0.5, "height": 0.5, "depth": 0.5},
                "color": "red",
            }
        ],
    }


def test_get_scene_before_first_save_returns_scene_not_defined(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context, role="agent")

    response = context.client.get(_scene_url())

    assert response.status_code == 404, response.text
    assert response.json()["code"] == "scene_not_defined"
    assert response.json()["detail"]


def test_put_scene_round_trips_full_document_and_records_actor(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context, role="agent", actor_id="scene-editor")
    expected = _scene_document()

    saved = context.client.put(_scene_url(), json=expected)
    loaded = context.client.get(_scene_url())

    assert saved.status_code == 200, saved.text
    assert saved.json() == expected
    assert loaded.status_code == 200, loaded.text
    assert loaded.json() == expected
    with context.session_factory() as session:
        stored = session.execute(
            text(
                "SELECT updated_by, updated_at FROM listing_scene "
                "WHERE listing_id = :listing_id"
            ),
            {"listing_id": "scene-listing"},
        ).one()
    assert stored.updated_by == "scene-editor"
    assert stored.updated_at is not None


@pytest.mark.parametrize(
    "change",
    [
        lambda scene: scene.update(version="2.0"),
        lambda scene: scene.update(extra="not allowed"),
        lambda scene: scene.update(unit="feet"),
        lambda scene: scene["rooms"][0].update(height="2.4"),
    ],
    ids=["unknown-version", "extra-key", "unknown-unit", "non-numeric-height"],
)
def test_put_rejects_scene_outside_contract(
    scene_context: SceneContext,
    change: Any,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    change(body)

    response = context.client.put(_scene_url(), json=body)

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "scene_invalid"
    assert response.json()["detail"]


def test_put_scene_for_another_agency_is_forbidden(scene_context: SceneContext) -> None:
    context = scene_context
    _seed_listing(context, agency_id="agency-two")
    _staff(context, role="agency_admin", tenant_id="agency-one")

    response = context.client.put(
        _scene_url("agency-two"), json=_scene_document()
    )

    assert response.status_code == 403, response.text
    assert response.json()["code"] == "forbidden"


@pytest.mark.parametrize("method", ["GET", "PUT"])
def test_scene_routes_return_404_for_unknown_listing(
    scene_context: SceneContext,
    method: str,
) -> None:
    context = scene_context
    _staff(context, role="agent")

    response = context.client.request(
        method,
        _scene_url(listing_id="missing-listing"),
        json=_scene_document() if method == "PUT" else None,
    )

    assert response.status_code == 404, response.text
    if method == "GET":
        assert response.json() == {"detail": "Listing not found", "code": "not_found"}
    else:
        assert response.json()["code"] == "listing_not_found"


# The canonical document every surface must accept verbatim (S13). The backend
# validates and stores it without adding, dropping or retyping a single field.
_CANONICAL_FIXTURE = (
    Path(__file__).resolve().parents[2] / "docs" / "api" / "f06-scene-fixture.json"
)


def _canonical_scene_document() -> dict[str, Any]:
    return cast(
        "dict[str, Any]",
        json.loads(_CANONICAL_FIXTURE.read_text(encoding="utf-8")),
    )


def test_scene_round_trip_stores_the_canonical_fixture_verbatim(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)

    document = _canonical_scene_document()
    saved = context.client.put(_scene_url(), json=document)

    assert saved.status_code == 200, saved.text
    assert saved.json() == document, "a valid scene must be stored exactly as received"

    stored = context.client.get(_scene_url())

    assert stored.status_code == 200, stored.text
    assert stored.json() == document
