"""Public scene endpoint: published listings expose their scene to customers."""

from __future__ import annotations

import base64
import json
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any, cast

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.modules.catalog.models import Listing
from app.modules.catalog.service import upsert_listing_scene
from app.modules.identity.models import Agency


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


def _seed_listing(
    context: SceneContext,
    listing_id: str = "scene-listing",
    *,
    agency_id: str = "agency-one",
    approval_status: str = "approved",
    is_published: bool = True,
) -> None:
    with context.session_factory.begin() as session:
        if session.get(Agency, agency_id) is None:
            session.add(Agency(id=agency_id))
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
                city="Córdoba",
                zone="Centro",
                bedrooms=2,
                bathrooms=1,
            )
        )


def _store_scene(
    context: SceneContext,
    listing_id: str = "scene-listing",
    document: dict[str, Any] | None = None,
) -> None:
    with context.session_factory.begin() as session:
        upsert_listing_scene(
            session,
            agency_id="agency-one",
            listing_id=listing_id,
            scene=document if document is not None else _scene_document(),
            updated_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
            updated_by="scene-actor",
        )


def _scene_document() -> dict[str, Any]:
    return {
        "version": "2.0",
        "unit": "meters",
        "walls": [
            {
                "id": "wall-north",
                "start": {"x": 0, "z": 0},
                "end": {"x": 4, "z": 0},
                "height": 2.4,
                "thickness": 0.15,
            },
            {
                "id": "wall-east",
                "start": {"x": 4, "z": 0},
                "end": {"x": 4, "z": 3},
                "height": 2.4,
                "thickness": 0.15,
            },
            {
                "id": "wall-south",
                "start": {"x": 4, "z": 3},
                "end": {"x": 0, "z": 3},
                "height": 2.4,
                "thickness": 0.15,
            },
            {
                "id": "wall-west",
                "start": {"x": 0, "z": 3},
                "end": {"x": 0, "z": 0},
                "height": 2.4,
                "thickness": 0.15,
            },
        ],
        "openings": [
            {
                "id": "door_1",
                "wallId": "wall-north",
                "position": 0.5,
                "width": 0.9,
                "height": 2.1,
                "type": "door",
            }
        ],
        "rooms": [
            {
                "id": "room_main",
                "wallIds": [
                    "wall-north", "wall-east", "wall-south", "wall-west"
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


def test_public_scene_returns_document_for_published_listing(
    scene_context: SceneContext,
) -> None:
    _seed_listing(scene_context)
    _store_scene(scene_context)
    response = scene_context.client.get("/api/v1/listings/scene-listing/scene")
    assert response.status_code == 200
    assert response.json() == _scene_document()


def test_public_scene_treats_stored_v1_scene_as_not_defined(
    scene_context: SceneContext,
) -> None:
    _seed_listing(scene_context)
    _store_scene(
        scene_context,
        document={
            "version": "1.0",
            "unit": "meters",
            "rooms": [],
            "objects": [],
        },
    )

    response = scene_context.client.get("/api/v1/listings/scene-listing/scene")

    assert response.status_code == 404, response.text
    assert response.json()["code"] == "scene_not_defined"


def test_public_scene_without_scene_returns_scene_not_defined(
    scene_context: SceneContext,
) -> None:
    _seed_listing(scene_context)
    response = scene_context.client.get("/api/v1/listings/scene-listing/scene")
    assert response.status_code == 404
    body = response.json()
    assert body["code"] == "scene_not_defined"
    assert body["detail"] == "Scene is not defined for this listing"


def test_public_scene_for_draft_listing_returns_listing_not_found(
    scene_context: SceneContext,
) -> None:
    _seed_listing(scene_context, approval_status="draft", is_published=False)
    _store_scene(scene_context)
    response = scene_context.client.get("/api/v1/listings/scene-listing/scene")
    assert response.status_code == 404
    assert response.json()["detail"] == "listing_not_found"


def test_public_scene_for_unknown_listing_returns_listing_not_found(
    scene_context: SceneContext,
) -> None:
    response = scene_context.client.get("/api/v1/listings/missing-listing/scene")
    assert response.status_code == 404
    assert response.json()["detail"] == "listing_not_found"


# The canonical document every surface must accept verbatim (S7).
_CANONICAL_FIXTURE = (
    Path(__file__).resolve().parents[2] / "docs" / "api" / "f06-scene-fixture.json"
)


def _canonical_scene_document() -> dict[str, Any]:
    return cast(
        "dict[str, Any]",
        json.loads(_CANONICAL_FIXTURE.read_text(encoding="utf-8")),
    )


def test_public_scene_serves_the_canonical_fixture_verbatim(
    scene_context: SceneContext,
) -> None:
    _seed_listing(scene_context)
    document = _canonical_scene_document()
    _store_scene(scene_context, document=document)

    response = scene_context.client.get("/api/v1/listings/scene-listing/scene")

    assert response.status_code == 200, response.text
    assert response.json() == document, (
        "the public scene is the stored document, nothing else"
    )
