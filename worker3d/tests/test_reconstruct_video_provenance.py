"""Height provenance (F07 T10): video-derived heights are ``estimated`` until the agent confirms them."""

from __future__ import annotations

import sys
from pathlib import Path

WORKER3D_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKER3D_DIR))
sys.path.insert(0, str(WORKER3D_DIR / "tests"))

import reconstruct
import test_reconstruct_video as T
from test_reconstruct_synthetic import (
    ceiling_plane,
    floor_plane,
    rectangle_walls,
    room_package,
    write_package,
)


def test_a_fitted_ceiling_tags_video_heights_as_estimated(tmp_path: Path) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    package, _ = T.single_room(tmp_path, reference=T.floor_reference(model))

    result = T.run(package, [model])

    assert {w["heightSource"] for w in result.scene_draft["walls"]} == {"estimated"}
    assert {w["height"] for w in result.scene_draft["walls"]} == {2.5}


def test_no_ceiling_keeps_the_video_height_assumed(tmp_path: Path) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0), ceiling=False)
    package = T.write_v2(tmp_path / "p", T.v2_manifest(reference=T.floor_reference(model)),
                         sensors=T.gravity_lines([model]))

    result = T.run(package, [model])

    assert {w["heightSource"] for w in result.scene_draft["walls"]} == {"assumed"}


def test_the_schema_1_path_still_emits_ceiling_plane_and_assumed(tmp_path: Path) -> None:
    manifest = room_package(floorY=-1.4)
    manifest["planes"] = [
        *rectangle_walls("w", 0, 0, 4, 3, floor_y=-1.4),
        floor_plane("f1", 0, 0, 4, 3, floor_y=-1.4),
        ceiling_plane("c1", 0, 0, 4, 3, y=1.15),
    ]
    with_ceiling = reconstruct.reconstruct(write_package(tmp_path / "a", manifest))
    without = reconstruct.reconstruct(write_package(tmp_path / "b", room_package()))

    assert {w["heightSource"] for w in with_ceiling.scene_draft["walls"]} == {"ceiling_plane"}
    assert {w["heightSource"] for w in without.scene_draft["walls"]} == {"assumed"}
