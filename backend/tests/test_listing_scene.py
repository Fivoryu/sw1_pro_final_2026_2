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
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.main import create_app
from app.modules.catalog.models import Listing
from app.modules.catalog.service import upsert_listing_scene
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
        lambda scene: scene.update(version="1.0"),
        lambda scene: scene.update(extra="not allowed"),
        lambda scene: scene.update(unit="feet"),
        lambda scene: scene["walls"][0].update(height="2.4"),
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


def _assert_scene_invalid(response: Any, path: str) -> None:
    assert response.status_code == 422, response.text
    body = response.json()
    assert body["code"] == "scene_invalid"
    assert path in body["detail"]


def test_put_rejects_unknown_opening_wall_id(scene_context: SceneContext) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    body["openings"][0]["wallId"] = "wall-missing"

    response = context.client.put(_scene_url(), json=body)

    _assert_scene_invalid(response, "openings[0].wallId")


def test_put_rejects_room_wall_ids_referencing_unknown_walls(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    body["rooms"][0]["wallIds"][2] = "wall-missing"

    response = context.client.put(_scene_url(), json=body)

    _assert_scene_invalid(response, "rooms[0].wallIds[2]")


def test_put_rejects_duplicate_wall_ids(scene_context: SceneContext) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    body["walls"][1]["id"] = body["walls"][0]["id"]

    response = context.client.put(_scene_url(), json=body)

    _assert_scene_invalid(response, "walls[1].id")


def test_put_rejects_duplicate_opening_ids(scene_context: SceneContext) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    body["openings"].append(dict(body["openings"][0]))

    response = context.client.put(_scene_url(), json=body)

    _assert_scene_invalid(response, "openings[1].id")


def test_put_rejects_duplicate_room_ids(scene_context: SceneContext) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    body["rooms"].append(dict(body["rooms"][0]))

    response = context.client.put(_scene_url(), json=body)

    _assert_scene_invalid(response, "rooms[1].id")


def test_put_rejects_duplicate_object_ids(scene_context: SceneContext) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    body["objects"].append(dict(body["objects"][0]))

    response = context.client.put(_scene_url(), json=body)

    _assert_scene_invalid(response, "objects[1].id")


@pytest.mark.parametrize("position", [-0.01, 1.01])
def test_put_rejects_opening_position_outside_unit_interval(
    scene_context: SceneContext,
    position: float,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    body["openings"][0]["position"] = position

    response = context.client.put(_scene_url(), json=body)

    _assert_scene_invalid(response, "openings[0].position")


def test_put_rejects_wall_with_identical_start_and_end(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    body["walls"][0]["end"] = dict(body["walls"][0]["start"])

    response = context.client.put(_scene_url(), json=body)

    _assert_scene_invalid(response, "walls[0]")


def test_put_accepts_empty_rooms(scene_context: SceneContext) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    body["rooms"] = []

    response = context.client.put(_scene_url(), json=body)

    assert response.status_code == 200, response.text
    assert response.json()["rooms"] == []


def test_put_applies_default_window_sill_height(scene_context: SceneContext) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    body["openings"][0].update(type="window", height=1.2)

    response = context.client.put(_scene_url(), json=body)

    assert response.status_code == 200, response.text
    assert response.json()["openings"][0]["sillHeight"] == 0.9


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


def test_get_treats_stored_v1_scene_as_not_defined(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    legacy_document = {
        "version": "1.0",
        "unit": "meters",
        "rooms": [],
        "objects": [],
    }
    with context.session_factory.begin() as session:
        upsert_listing_scene(
            session,
            agency_id="agency-one",
            listing_id="scene-listing",
            scene=legacy_document,
            updated_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
            updated_by="scene-actor",
        )

    response = context.client.get(_scene_url())

    assert response.status_code == 404, response.text
    assert response.json()["code"] == "scene_not_defined"


# The canonical document every surface must accept verbatim (S7). The backend
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


_CAPTURED_FIXTURE = (
    Path(__file__).resolve().parents[2] / "docs" / "api" / "f07-captured-scene-fixture.json"
)


def test_scene_built_by_the_capture_app_is_accepted_verbatim(
    scene_context: SceneContext,
) -> None:
    """The capture app's scene builder output (two rooms sharing a wall) is valid v2."""
    context = scene_context
    _seed_listing(context)
    _staff(context)
    document = cast(
        "dict[str, Any]",
        json.loads(_CAPTURED_FIXTURE.read_text(encoding="utf-8")),
    )

    saved = context.client.put(
        _scene_url(), json=document, headers={"If-None-Match": "*"}
    )

    assert saved.status_code == 200, saved.text
    assert saved.json() == document
    assert saved.headers["ETag"] == '"1"'


# --- F07.5: optimistic versioning of the staff scene (ETag + preconditions) ---


def test_put_creates_revision_one_and_get_exposes_the_same_etag(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)

    saved = context.client.put(_scene_url(), json=_scene_document())
    loaded = context.client.get(_scene_url())

    assert saved.status_code == 200, saved.text
    assert saved.headers["ETag"] == '"1"'
    assert saved.json() == _scene_document(), "the body stays the bare scene document"
    assert loaded.status_code == 200, loaded.text
    assert loaded.headers["ETag"] == '"1"'
    with context.session_factory() as session:
        revision = session.execute(
            text("SELECT revision FROM listing_scene WHERE listing_id = :listing_id"),
            {"listing_id": "scene-listing"},
        ).scalar_one()
    assert revision == 1


def test_each_successful_put_increments_the_revision(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)

    etags = [
        context.client.put(_scene_url(), json=_scene_document()).headers.get("ETag")
        for _ in range(3)
    ]

    assert etags == ['"1"', '"2"', '"3"']
    assert context.client.get(_scene_url()).headers.get("ETag") == '"3"'


def test_put_without_preconditions_still_replaces_unconditionally(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    context.client.put(_scene_url(), json=_scene_document())
    changed = _scene_document()
    changed["objects"] = []

    response = context.client.put(_scene_url(), json=changed)

    assert response.status_code == 200, response.text
    assert response.json() == changed
    assert response.headers.get("ETag") == '"2"'


def test_put_with_matching_if_match_replaces_the_scene(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    context.client.put(_scene_url(), json=_scene_document())
    changed = _scene_document()
    changed["objects"] = []

    response = context.client.put(
        _scene_url(), json=changed, headers={"If-Match": '"1"'}
    )

    assert response.status_code == 200, response.text
    assert response.headers.get("ETag") == '"2"'
    assert context.client.get(_scene_url()).json() == changed


def _assert_scene_conflict(response: Any, etag: str | None) -> None:
    assert response.status_code == 412, response.text
    body = response.json()
    assert body["code"] == "scene_conflict"
    assert body["detail"]
    assert response.headers.get("ETag") == etag


def test_put_with_stale_if_match_returns_conflict_and_keeps_the_scene(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    context.client.put(_scene_url(), json=_scene_document())
    context.client.put(_scene_url(), json=_scene_document())
    changed = _scene_document()
    changed["objects"] = []

    response = context.client.put(
        _scene_url(), json=changed, headers={"If-Match": '"1"'}
    )

    _assert_scene_conflict(response, '"2"')
    loaded = context.client.get(_scene_url())
    assert loaded.json() == _scene_document()
    assert loaded.headers.get("ETag") == '"2"'


def test_put_with_if_match_and_no_scene_returns_conflict_without_etag(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)

    response = context.client.put(
        _scene_url(), json=_scene_document(), headers={"If-Match": '"1"'}
    )

    _assert_scene_conflict(response, None)
    assert context.client.get(_scene_url()).status_code == 404


def test_put_with_if_match_star_requires_an_existing_scene(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)

    missing = context.client.put(
        _scene_url(), json=_scene_document(), headers={"If-Match": "*"}
    )
    context.client.put(_scene_url(), json=_scene_document())
    present = context.client.put(
        _scene_url(), json=_scene_document(), headers={"If-Match": "*"}
    )

    _assert_scene_conflict(missing, None)
    assert present.status_code == 200, present.text
    assert present.headers.get("ETag") == '"2"'


def test_put_with_if_none_match_star_creates_only_the_first_scene(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)

    created = context.client.put(
        _scene_url(), json=_scene_document(), headers={"If-None-Match": "*"}
    )
    duplicated = context.client.put(
        _scene_url(), json=_scene_document(), headers={"If-None-Match": "*"}
    )

    assert created.status_code == 200, created.text
    assert created.headers.get("ETag") == '"1"'
    _assert_scene_conflict(duplicated, '"1"')


def test_put_with_weak_if_match_never_matches(scene_context: SceneContext) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    context.client.put(_scene_url(), json=_scene_document())

    response = context.client.put(
        _scene_url(), json=_scene_document(), headers={"If-Match": 'W/"1"'}
    )

    _assert_scene_conflict(response, '"1"')


def test_invalid_scene_takes_precedence_over_precondition(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    body["unit"] = "feet"

    response = context.client.put(_scene_url(), json=body, headers={"If-Match": '"9"'})

    assert response.status_code == 422, response.text
    assert response.json()["code"] == "scene_invalid"


def test_unknown_listing_takes_precedence_over_precondition(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _staff(context)

    response = context.client.put(
        _scene_url(listing_id="missing-listing"),
        json=_scene_document(),
        headers={"If-Match": '"1"'},
    )

    assert response.status_code == 404, response.text
    assert response.json()["code"] == "listing_not_found"


def test_cors_exposes_etag_to_the_panel_origin(scene_context: SceneContext) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)

    response = context.client.put(
        _scene_url(), json=_scene_document(), headers={"Origin": "http://localhost"}
    )

    exposed = response.headers.get("access-control-expose-headers", "")
    assert "etag" in exposed.lower()


# --- F07: additive optional provenance fields (contract v2) ---


def _scene_with_provenance() -> dict[str, Any]:
    scene = _scene_document()
    scene["walls"][0]["heightSource"] = "ceiling_plane"
    scene["walls"][1]["heightSource"] = "wall_point"
    scene["walls"][2]["heightSource"] = "manual"
    scene["walls"][3]["heightSource"] = "assumed"
    scene["objects"][0]["source"] = "depth"
    scene["objects"][0]["confidence"] = 0.82
    scene["objects"].append(
        {
            "id": "manual_box",
            "type": "placeholder",
            "position": {"x": 2, "y": 0, "z": 2},
            "dimensions": {"width": 1, "height": 1, "depth": 1},
            "color": "gray",
            "source": "manual",
        }
    )
    return scene


def test_put_accepts_and_round_trips_provenance_fields(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    expected = _scene_with_provenance()

    saved = context.client.put(_scene_url(), json=expected)

    assert saved.status_code == 200, saved.text
    assert saved.json() == expected
    assert context.client.get(_scene_url()).json() == expected


def test_scene_without_provenance_keeps_the_fields_absent(
    scene_context: SceneContext,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)

    saved = context.client.put(_scene_url(), json=_scene_document())

    assert saved.status_code == 200, saved.text
    assert "heightSource" not in saved.json()["walls"][0]
    assert "source" not in saved.json()["objects"][0]
    assert "confidence" not in saved.json()["objects"][0]


@pytest.mark.parametrize(
    ("change", "path"),
    [
        (
            lambda scene: scene["walls"][0].update(heightSource="laser"),
            "walls[0].heightSource",
        ),
        (
            lambda scene: scene["objects"][0].update(source="lidar"),
            "objects[0].source",
        ),
        (
            lambda scene: scene["objects"][0].update(confidence=1.5),
            "objects[0].confidence",
        ),
        (
            lambda scene: scene["objects"][0].update(confidence=-0.1),
            "objects[0].confidence",
        ),
        (
            lambda scene: scene["objects"][0].update(confidence="0.5"),
            "objects[0].confidence",
        ),
    ],
    ids=[
        "unknown-height-source",
        "unknown-object-source",
        "confidence-above-one",
        "confidence-below-zero",
        "confidence-string",
    ],
)
def test_put_rejects_invalid_provenance_fields(
    scene_context: SceneContext,
    change: Any,
    path: str,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    body = _scene_document()
    change(body)

    response = context.client.put(_scene_url(), json=body)

    _assert_scene_invalid(response, path)
