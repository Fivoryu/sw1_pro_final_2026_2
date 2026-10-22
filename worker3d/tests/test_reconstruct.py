"""Reconstruction contracts: capture package -> scene v2 draft (stdlib only)."""

from __future__ import annotations

import json
import math
import sys
import zipfile
from pathlib import Path
from typing import Any

import pytest

WORKER3D_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKER3D_DIR))

import reconstruct
from test_reconstruct_synthetic import (
    base_manifest,
    ceiling_plane,
    encode_gray_png,
    floor_plane,
    rectangle_walls,
    room_package,
    trajectory_for,
    wall_plane,
    write_package,
)

REPO_ROOT = WORKER3D_DIR.parent
FIXTURE = REPO_ROOT / "docs" / "api" / "f07-captured-scene-fixture.json"

# Depth rig: camera 3 m above the floor looking straight down (-y), pose is a
# rotation of -90 degrees about x.
_DOWN = [-math.sqrt(0.5), 0.0, 0.0, math.sqrt(0.5)]
_DEPTH = {"width": 160, "height": 120, "fx": 100.0, "fy": 100.0, "cx": 80.0, "cy": 60.0}
_CAMERA_HEIGHT = 3.0


def _scene(package_dir: Path) -> dict[str, Any]:
    return reconstruct.reconstruct(package_dir).scene_draft


def _depth_frame(boxes: list[tuple[float, float, float, float, float]]) -> list[int]:
    """Depth (mm) seen by the camera above (2, 3, 1.5): floor plus boxes.

    Each box is (x0, z0, x1, z1, height). Camera x -> world x, image row v -> world z.
    """
    samples: list[int] = []
    for v in range(_DEPTH["height"]):
        for u in range(_DEPTH["width"]):
            depth = _CAMERA_HEIGHT
            for x0, z0, x1, z1, height in boxes:
                top = _CAMERA_HEIGHT - height
                x = 2.0 + (u - _DEPTH["cx"]) / _DEPTH["fx"] * top
                z = 1.5 + (v - _DEPTH["cy"]) / _DEPTH["fy"] * top
                if x0 <= x <= x1 and z0 <= z <= z1:
                    depth = min(depth, top)
            samples.append(round(depth * 1000))
    return samples


def _depth_package(
    directory: Path, boxes: list[tuple[float, float, float, float, float]], **overrides: Any
) -> Path:
    keyframe = {
        "index": 1,
        "timestampNs": 0,
        "roomId": "room-1",
        "pose": [2.0, _CAMERA_HEIGHT, 1.5, *_DOWN],
        "image": "frames/000001.jpg",
        "depth": "depth/000001.png",
        "confidence": None,
    }
    manifest = room_package(
        depth=_DEPTH,
        device={"model": "test", "arcoreVersion": "1.57.0", "depthSupported": True},
        keyframes=[keyframe],
        **overrides,
    )
    png = encode_gray_png(_DEPTH["width"], _DEPTH["height"], _depth_frame(boxes), filter_type=4)
    return write_package(directory, manifest, {"depth/000001.png": png})


# --- manifest validation -------------------------------------------------------------------


def test_valid_package_reconstructs(tmp_path: Path) -> None:
    result = reconstruct.reconstruct(write_package(tmp_path / "p", room_package()))

    assert result.scene_draft["version"] == "2.0"


def test_missing_manifest_is_invalid(tmp_path: Path) -> None:
    (tmp_path / "p").mkdir()
    with pytest.raises(reconstruct.InvalidPackage):
        reconstruct.reconstruct(tmp_path / "p")


@pytest.mark.parametrize(
    "mutation",
    [
        {"schemaVersion": 2},
        {"floorY": None},
        {"rooms": []},
        {"rooms": [{"id": "a", "name": "A"}, {"id": "a", "name": "B"}]},
        {"planes": [{"id": "x", "type": "roof", "pose": [0] * 6 + [1], "polygon": [[0, 0]]}]},
        {"planes": [{"id": "x", "type": "wall", "pose": [0, 0, 1], "polygon": [[0, 0]]}]},
        {"trajectory": []},
        {"trajectory": [[0, 0.0, 0.0, "ghost-room"]]},
        {
            "keyframes": [
                {"index": 1, "roomId": "ghost", "pose": [0] * 6 + [1], "image": "frames/1.jpg"}
            ]
        },
    ],
    ids=[
        "schema-version",
        "floor-null",
        "no-rooms",
        "duplicate-room-id",
        "unknown-plane-type",
        "short-pose",
        "empty-trajectory",
        "trajectory-unknown-room",
        "keyframe-unknown-room",
    ],
)
def test_invalid_manifest_is_rejected_as_invalid_package(
    tmp_path: Path, mutation: dict[str, Any]
) -> None:
    manifest = room_package()
    manifest.update(mutation)

    with pytest.raises(reconstruct.InvalidPackage):
        reconstruct.reconstruct(write_package(tmp_path / "p", manifest))


def test_depth_keyframe_without_depth_intrinsics_is_invalid(tmp_path: Path) -> None:
    package = _depth_package(tmp_path / "p", [])
    manifest = json.loads((package / "manifest.json").read_text(encoding="utf-8"))
    manifest["depth"] = None
    (package / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(reconstruct.InvalidPackage):
        reconstruct.reconstruct(package)


def test_depth_png_with_unexpected_size_is_invalid(tmp_path: Path) -> None:
    package = _depth_package(tmp_path / "p", [])
    (package / "depth" / "000001.png").write_bytes(encode_gray_png(2, 2, [1, 2, 3, 4]))

    with pytest.raises(reconstruct.InvalidPackage):
        reconstruct.reconstruct(package)


def test_zip_package_is_extracted_and_reconstructed(tmp_path: Path) -> None:
    package = write_package(tmp_path / "p", room_package())
    archive = tmp_path / "package.zip"
    with zipfile.ZipFile(archive, "w") as handle:
        handle.write(package / "manifest.json", "manifest.json")

    result = reconstruct.reconstruct_path(archive)

    assert len(result.scene_draft["walls"]) == 4


def test_corrupt_zip_is_invalid(tmp_path: Path) -> None:
    archive = tmp_path / "broken.zip"
    archive.write_bytes(b"this is not a zip")

    with pytest.raises(reconstruct.InvalidPackage):
        reconstruct.reconstruct_path(archive)


# --- wall fitting --------------------------------------------------------------------------


def test_wall_segment_is_fitted_from_a_rotated_plane_polygon() -> None:
    angle = math.radians(30)
    start = (1.0, 1.0)
    end = (1.0 + 2.0 * math.cos(angle), 1.0 + 2.0 * math.sin(angle))
    plane = wall_plane("w", start, end, height=2.4, floor_y=-1.0)

    points = reconstruct.plane_to_world(plane["pose"], plane["polygon"])
    segment = reconstruct.fit_wall_segment(points)

    assert segment is not None
    ends = sorted([segment.start, segment.end])
    expected = sorted([start, end])
    for got, want in zip(ends, expected, strict=True):
        assert got == pytest.approx(want, abs=1e-6)
    assert segment.min_y == pytest.approx(-1.0, abs=1e-6)
    assert segment.max_y == pytest.approx(1.4, abs=1e-6)


def test_wall_shorter_than_thirty_centimetres_is_ignored() -> None:
    plane = wall_plane("w", (0.0, 0.0), (0.2, 0.0))

    points = reconstruct.plane_to_world(plane["pose"], plane["polygon"])

    assert reconstruct.fit_wall_segment(points) is None


# --- contour and scene -------------------------------------------------------------------


def test_four_wall_planes_close_a_four_by_three_room(tmp_path: Path) -> None:
    scene = _scene(write_package(tmp_path / "p", room_package()))

    walls = scene["walls"]
    assert len(walls) == 4
    xs = sorted({round(p["x"], 3) for w in walls for p in (w["start"], w["end"])})
    zs = sorted({round(p["z"], 3) for w in walls for p in (w["start"], w["end"])})
    # Centre lines sit half a wall thickness outside the observed interior faces.
    assert xs == [-0.075, 4.075]
    assert zs == [-0.075, 3.075]
    assert all(w["thickness"] == 0.15 for w in walls)
    [room] = scene["rooms"]
    assert room["name"] == "Estar"
    assert len(room["wallIds"]) == 4
    assert set(room["wallIds"]) == {w["id"] for w in walls}


def test_room_without_enough_walls_is_skipped_with_a_warning(tmp_path: Path) -> None:
    planes = [
        *rectangle_walls("a", 0, 0, 4, 3),
        floor_plane("f1", 0, 0, 4, 3),
        *rectangle_walls("b", 10, 0, 14, 3, skip=("e", "s")),
    ]
    manifest = base_manifest(
        rooms=[{"id": "room-1", "name": "Estar"}, {"id": "room-2", "name": "Cocina"}],
        planes=planes,
        trajectory=[
            *trajectory_for("room-1", 0, 0, 4, 3),
            *trajectory_for("room-2", 10, 0, 14, 3, t0=10_000),
        ],
    )

    result = reconstruct.reconstruct(write_package(tmp_path / "p", manifest))

    assert [room["name"] for room in result.scene_draft["rooms"]] == ["Estar"]
    assert any("Cocina" in warning for warning in result.warnings)


def test_package_where_no_room_closes_is_invalid(tmp_path: Path) -> None:
    manifest = room_package()
    manifest["planes"] = manifest["planes"][:2]

    with pytest.raises(reconstruct.InvalidPackage):
        reconstruct.reconstruct(write_package(tmp_path / "p", manifest))


def test_two_rooms_sharing_a_wall_produce_one_welded_wall(tmp_path: Path) -> None:
    # The shared 15 cm wall is seen from each side: faces at x=4.0 and x=4.15.
    planes = [
        *rectangle_walls("a", 0, 0, 4, 3),
        *rectangle_walls("b", 4.15, 0, 7.15, 3),
        floor_plane("f1", 0, 0, 4, 3),
        floor_plane("f2", 4.15, 0, 7.15, 3),
    ]
    manifest = base_manifest(
        rooms=[{"id": "room-1", "name": "Estar"}, {"id": "room-2", "name": "Dormitorio"}],
        planes=planes,
        trajectory=[
            *trajectory_for("room-1", 0, 0, 4, 3),
            *trajectory_for("room-2", 4.15, 0, 7.15, 3, t0=10_000),
        ],
    )

    scene = _scene(write_package(tmp_path / "p", manifest))

    assert len(scene["walls"]) == 7
    first, second = (set(room["wallIds"]) for room in scene["rooms"])
    assert len(first & second) == 1
    shared = next(w for w in scene["walls"] if w["id"] in first & second)
    assert shared["start"]["x"] == pytest.approx(4.075, abs=1e-6)
    assert shared["end"]["x"] == pytest.approx(4.075, abs=1e-6)


# --- heights -----------------------------------------------------------------------------


def test_height_is_assumed_and_flagged_without_a_ceiling_plane(tmp_path: Path) -> None:
    result = reconstruct.reconstruct(write_package(tmp_path / "p", room_package()))

    walls = result.scene_draft["walls"]
    assert {w["heightSource"] for w in walls} == {"assumed"}
    assert {w["height"] for w in walls} == {2.4}
    assert any("supuesta" in warning and "Estar" in warning for warning in result.warnings)


def test_ceiling_plane_gives_a_measured_height(tmp_path: Path) -> None:
    manifest = room_package(floorY=-1.4)
    manifest["planes"] = [
        *rectangle_walls("w", 0, 0, 4, 3, floor_y=-1.4),
        floor_plane("f1", 0, 0, 4, 3, floor_y=-1.4),
        ceiling_plane("c1", 0, 0, 4, 3, y=1.15),
    ]

    result = reconstruct.reconstruct(write_package(tmp_path / "p", manifest))

    walls = result.scene_draft["walls"]
    assert {w["heightSource"] for w in walls} == {"ceiling_plane"}
    assert {w["height"] for w in walls} == {2.55}
    assert not any("supuesta" in warning for warning in result.warnings)


# --- volumes -----------------------------------------------------------------------------


def test_depth_frame_produces_one_unlabelled_box_for_the_one_metre_volume(tmp_path: Path) -> None:
    # A 1 x 1 x 0.8 m box and a 10 x 10 cm blob that must be discarded as noise.
    package = _depth_package(
        tmp_path / "p", [(1.5, 1.0, 2.5, 2.0, 0.8), (0.4, 0.4, 0.5, 0.5, 0.5)]
    )

    result = reconstruct.reconstruct(package)

    [box] = result.scene_draft["objects"]
    assert box["type"] == "occupancy"
    assert box["source"] == "depth"
    assert 0 < box["confidence"] <= 1
    assert "class" not in box and "price" not in box and "extra_id" not in box
    assert box["position"]["x"] == pytest.approx(2.0, abs=0.1)
    assert box["position"]["z"] == pytest.approx(1.5, abs=0.1)
    assert box["position"]["y"] == 0.0
    assert box["dimensions"]["width"] == pytest.approx(1.0, abs=0.1)
    assert box["dimensions"]["depth"] == pytest.approx(1.0, abs=0.1)
    assert box["dimensions"]["height"] == pytest.approx(0.8, abs=0.02)


def test_depth_frame_of_an_empty_floor_produces_no_volumes(tmp_path: Path) -> None:
    result = reconstruct.reconstruct(_depth_package(tmp_path / "p", []))

    assert result.scene_draft["objects"] == []


def test_low_confidence_depth_pixels_are_skipped(tmp_path: Path) -> None:
    package = _depth_package(tmp_path / "p", [(1.5, 1.0, 2.5, 2.0, 0.8)])
    manifest = json.loads((package / "manifest.json").read_text(encoding="utf-8"))
    manifest["keyframes"][0]["confidence"] = "confidence/000001.png"
    (package / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    size = _DEPTH["width"] * _DEPTH["height"]
    (package / "confidence").mkdir()
    (package / "confidence" / "000001.png").write_bytes(
        encode_gray_png(_DEPTH["width"], _DEPTH["height"], [0] * size, bit_depth=8)
    )

    result = reconstruct.reconstruct(package)

    assert result.scene_draft["objects"] == []


def test_no_depth_means_no_volumes_and_a_warning(tmp_path: Path) -> None:
    result = reconstruct.reconstruct(write_package(tmp_path / "p", room_package()))

    assert result.scene_draft["objects"] == []
    assert any("profundidad" in warning for warning in result.warnings)


# --- openings, reference, structure -------------------------------------------------------


def test_openings_are_not_detected_and_the_agency_is_told(tmp_path: Path) -> None:
    result = reconstruct.reconstruct(write_package(tmp_path / "p", room_package()))

    assert result.scene_draft["openings"] == []
    assert any("puertas y ventanas" in warning for warning in result.warnings)


def test_reference_rescales_the_scene_and_states_the_factor(tmp_path: Path) -> None:
    manifest = room_package(reference={"meters": 8.0, "from": [0, 0, 0], "to": [4, 0, 0]})

    result = reconstruct.reconstruct(write_package(tmp_path / "p", manifest))

    xs = [p["x"] for w in result.scene_draft["walls"] for p in (w["start"], w["end"])]
    zs = [p["z"] for w in result.scene_draft["walls"] for p in (w["start"], w["end"])]
    assert max(xs) == pytest.approx(8.075, abs=1e-6)
    assert max(zs) == pytest.approx(6.075, abs=1e-6)
    assert any("2.000" in warning for warning in result.warnings)


def test_invalid_reference_is_rejected(tmp_path: Path) -> None:
    manifest = room_package(reference={"meters": 3.0, "from": [1, 0, 1], "to": [1, 0, 1]})

    with pytest.raises(reconstruct.InvalidPackage):
        reconstruct.reconstruct(write_package(tmp_path / "p", manifest))


def test_scene_draft_has_the_structure_of_the_captured_scene_fixture(tmp_path: Path) -> None:
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    package = _depth_package(tmp_path / "p", [(1.5, 1.0, 2.5, 2.0, 0.8)])
    manifest = json.loads((package / "manifest.json").read_text(encoding="utf-8"))
    manifest["planes"].append(ceiling_plane("c1", 0, 0, 4, 3, 2.4))
    (package / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    scene = _scene(package)

    assert set(scene) == set(fixture)
    assert scene["version"] == fixture["version"] and scene["unit"] == fixture["unit"]
    for collection in ("walls", "rooms", "objects"):
        assert scene[collection], collection
        for element in scene[collection]:
            assert set(element) == set(fixture[collection][0]), collection
    # Openings are never detected in v1; the contract shape stays a list.
    assert scene["openings"] == []
    # Every room wall id references an existing wall, as the contract requires.
    wall_ids = {w["id"] for w in scene["walls"]}
    assert all(set(r["wallIds"]) <= wall_ids for r in scene["rooms"])
    # Only provenance values the scene contract allows.
    assert {w["heightSource"] for w in scene["walls"]} <= {
        "ceiling_plane",
        "wall_point",
        "manual",
        "assumed",
    }
    assert {o["source"] for o in scene["objects"]} <= {"depth", "manual"}
    # JSON-serialisable as is.
    json.dumps(scene)
