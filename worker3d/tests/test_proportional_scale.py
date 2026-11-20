"""F07 proportional plans (S2-S4): ratios survive an arbitrary reconstruction scale.

The reconstructor is never given the expected dimensions: the known 4x3 room only exists in
the synthetic model, and the checks compare ratios obtained from the scene afterwards.
"""

from __future__ import annotations

import math
from pathlib import Path

import pytest
import reconstruct
import reconstruct_video as rv
import test_reconstruct_video as T

WALL_THICKNESS = reconstruct.WALL_THICKNESS_M  # constant applied to wall segments, not scaled


def _centerline_sides(scene: dict) -> tuple[float, float]:
    lengths = sorted(
        math.dist((w["start"]["x"], w["start"]["z"]), (w["end"]["x"], w["end"]["z"])) - WALL_THICKNESS
        for w in scene["walls"]
    )
    return lengths[0], lengths[-1]  # short side, long side


@pytest.mark.parametrize("sfm_scale", [0.4, 1.0, 2.5])
def test_the_width_depth_ratio_does_not_depend_on_the_reconstruction_scale(tmp_path: Path, sfm_scale: float) -> None:
    package, model = T.single_room(tmp_path, scale=sfm_scale)

    result = T.run(package, [model])

    assert result.scene_draft["scale"] == {"mode": "proportional"}
    short, long = _centerline_sides(result.scene_draft)
    assert long / short == pytest.approx(4 / 3, rel=0.06)


def test_the_proportional_scene_is_the_same_whatever_the_reconstruction_scale(tmp_path: Path) -> None:
    small = T.single_room(tmp_path / "a", scale=0.4)
    large = T.single_room(tmp_path / "b", scale=2.0)

    first = T.run(small[0], [small[1]]).scene_draft
    second = T.run(large[0], [large[1]]).scene_draft

    assert T.wall_lengths(first) == pytest.approx(T.wall_lengths(second), abs=0.02)


def test_a_uniform_scale_change_keeps_every_ratio_and_the_scene_stays_proportional(tmp_path: Path) -> None:
    small = T.single_room(tmp_path / "a", scale=0.4)
    large = T.single_room(tmp_path / "b", scale=2.0)

    first = T.run(small[0], [small[1]]).scene_draft
    second = T.run(large[0], [large[1]]).scene_draft

    s1, l1 = _centerline_sides(first)
    s2, l2 = _centerline_sides(second)
    assert l1 / s1 == pytest.approx(l2 / s2, rel=0.03)
    # Both sides grow by the same factor: nothing was normalised per axis.
    assert l2 / l1 == pytest.approx(s2 / s1, rel=0.03)
    assert second["scale"] == first["scale"] == {"mode": "proportional"}


def test_a_reference_turns_the_same_capture_metric_with_one_global_factor(tmp_path: Path) -> None:
    package, model = T.single_room(tmp_path / "ref", scale=0.4)
    plain = T.run(package, [model]).scene_draft
    package2, model2 = T.single_room(tmp_path / "m", reference=T.floor_reference(T.make_model((0.0, 0.0, 4.0, 3.0))), scale=0.4)
    metric = T.run(package2, [model2]).scene_draft

    assert metric["scale"] == {"mode": "metric"}
    ps, pl = _centerline_sides(plain)
    ms, ml = _centerline_sides(metric)
    assert ml / ms == pytest.approx(pl / ps, rel=0.03)


# --- S4: two connected rooms of different size, nothing measured given to the algorithm --------

def _connected_model(sfm_scale: float) -> rv.SparseModel:
    """A 4x3 and a 3x2 room sharing the wall x=4, as ONE connected reconstruction."""
    a = T.make_model((0.0, 0.0, 4.0, 3.0), scale=sfm_scale)
    b = T.make_model((4.0, 0.0, 7.0, 2.0), scale=sfm_scale, first_frame=8)
    return rv.SparseModel(poses=a.poses + b.poses, points=a.points + b.points, intrinsics=a.intrinsics)


def _room_boxes(scene: dict) -> dict[str, tuple[float, float]]:
    walls = {w["id"]: w for w in scene["walls"]}
    boxes: dict[str, tuple[float, float]] = {}
    for room in scene["rooms"]:
        xs = [p for wid in room["wallIds"] for p in (walls[wid]["start"]["x"], walls[wid]["end"]["x"])]
        zs = [p for wid in room["wallIds"] for p in (walls[wid]["start"]["z"], walls[wid]["end"]["z"])]
        boxes[room["name"]] = (max(xs) - min(xs) - WALL_THICKNESS, max(zs) - min(zs) - WALL_THICKNESS)
    return boxes


def _two_room_scene(tmp_path: Path, sfm_scale: float) -> dict:
    model = _connected_model(sfm_scale)
    manifest = T.v2_manifest(rooms=[
        {"id": "room-1", "name": "Estar", "fromNs": T.T0, "toNs": T.T0 + 8 * T.STEP},
        {"id": "room-2", "name": "Cuarto", "fromNs": T.T0 + 8 * T.STEP, "toNs": T.T0 + 20 * T.STEP},
    ])
    package = T.write_v2(tmp_path, manifest, frames=T.frame_lines(16), sensors=T.gravity_lines([model]))
    return T.run(package, [model]).scene_draft


@pytest.mark.parametrize("sfm_scale", [0.4, 1.7])
def test_two_connected_rooms_keep_their_ratios_and_relative_size(tmp_path: Path, sfm_scale: float) -> None:
    scene = _two_room_scene(tmp_path, sfm_scale)

    assert scene["scale"] == {"mode": "proportional"}
    boxes = _room_boxes(scene)
    (aw, ad), (bw, bd) = boxes["Estar"], boxes["Cuarto"]
    assert aw / ad == pytest.approx(4 / 3, rel=0.08)
    assert bw / bd == pytest.approx(3 / 2, rel=0.08)
    # One global factor: the relative size between rooms survives (12 m2 vs 6 m2 in the model).
    assert (aw * ad) / (bw * bd) == pytest.approx(2.0, rel=0.15)


def test_two_connected_rooms_share_the_wall_between_them(tmp_path: Path) -> None:
    scene = _two_room_scene(tmp_path, 0.4)

    shared = set(scene["rooms"][0]["wallIds"]) & set(scene["rooms"][1]["wallIds"])
    assert shared, "the wall between the rooms must be one wall in both 2D and 3D, not two copies"
    # Doors are not detected automatically: they are marked in the editor, so none is expected.
    assert scene["openings"] == []
