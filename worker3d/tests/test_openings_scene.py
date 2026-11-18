"""F07 openings in the scene (S2, S3, S7): a recognised door shows up on the right wall, proportionally.

The detector is simulated: it answers with the pixel box a camera would see for a door whose
geometry only this test knows (0.9 wide, 2.0 high, on the wall between the two rooms). The
reconstructor never receives those numbers.
"""

from __future__ import annotations

import math
from pathlib import Path

import pytest
import reconstruct_video as rv
import test_proportional_scale as P
import test_reconstruct_video as T

SHIFT = (3.0, -2.0, 5.0)
LEVEL_PITCH_DEG = 5.0  # a near-level camera: a full door fits in the frame


def _model(sfm_scale: float) -> rv.SparseModel:
    """The 4x3 and 3x2 rooms of the proportional tests, filmed with a near-level camera."""
    a = T.make_model((0.0, 0.0, 4.0, 3.0), scale=sfm_scale, pitch_deg=LEVEL_PITCH_DEG)
    b = T.make_model((4.0, 0.0, 7.0, 2.0), scale=sfm_scale, first_frame=8, pitch_deg=LEVEL_PITCH_DEG)
    return rv.SparseModel(poses=a.poses + b.poses, points=a.points + b.points, intrinsics=a.intrinsics)


def _door_boxes(
    model: rv.SparseModel, scale: float, z0: float, z1: float, x: float = 4.0, y0: float = 0.0, y1: float = 2.0
):
    """Per frame, the normalised box of an opening on the plane ``x`` (z0..z1, y0..y1) when visible."""
    boxes = {}
    for pose in model.poses:
        try:
            corners = [
                T.project(model, pose.frame_index, (x, y, z), scale, SHIFT)
                for z in (z0, z1)
                for y in (y0, y1)
            ]
        except AssertionError:
            continue  # the door is not fully visible from this frame
        us, vs = [c["x"] for c in corners], [c["y"] for c in corners]
        boxes[pose.frame_index] = (min(us), min(vs), max(us), max(vs))
    return boxes


def _detector(boxes: dict[int, tuple[float, float, float, float]], kind: str = "door", score: float = 0.8):
    def detect(path: Path):
        frame = int(path.stem)
        return [(boxes[frame], kind, score)] if frame in boxes else []

    return detect


def _scene(tmp_path: Path, sfm_scale: float, detector, **extra) -> tuple[dict, list[str]]:
    model = _model(sfm_scale)
    manifest = T.v2_manifest(rooms=[
        {"id": "room-1", "name": "Estar", "fromNs": T.T0, "toNs": T.T0 + 8 * T.STEP},
        {"id": "room-2", "name": "Cuarto", "fromNs": T.T0 + 8 * T.STEP, "toNs": T.T0 + 20 * T.STEP},
    ])
    package = T.write_v2(tmp_path, manifest, frames=T.frame_lines(16), sensors=T.gravity_lines([model]))
    result = T.run(package, [model], opening_detector=lambda: detector(model, sfm_scale), **extra)
    return result.scene_draft, result.warnings


def _on_shared_door(model: rv.SparseModel, scale: float):
    return _detector(_door_boxes(model, scale, 1.0, 1.9))


@pytest.mark.parametrize("sfm_scale", [0.4, 1.7])
def test_a_recognised_door_lands_on_its_wall_with_proportional_size(
    tmp_path: Path, sfm_scale: float
) -> None:
    scene, _ = _scene(tmp_path, sfm_scale, lambda model, scale: _on_shared_door(model, scale))

    doors = [o for o in scene["openings"] if o["type"] == "door"]
    assert len(doors) == 1
    # The door is on the east wall of "Estar": the vertical wall with the greatest x of that room.
    walls = {w["id"]: w for w in scene["walls"]}
    east = max(
        (walls[i] for i in scene["rooms"][0]["wallIds"] if walls[i]["start"]["x"] == walls[i]["end"]["x"]),
        key=lambda w: w["start"]["x"],
    )
    assert doors[0]["wallId"] == east["id"]
    wall = east
    length = math.dist((wall["start"]["x"], wall["start"]["z"]), (wall["end"]["x"], wall["end"]["z"]))
    # 0.9 wide door on a 3.0 wall; 2.0 high door in a room 4.0 wide: ratios, never metres.
    assert doors[0]["width"] / length == pytest.approx(0.3, abs=0.07)
    estar_width = P._room_boxes(scene)["Estar"][0]
    assert doors[0]["height"] / estar_width == pytest.approx(0.5, abs=0.1)
    assert 0.0 < doors[0]["position"] < 1.0


def test_without_an_opening_detector_nothing_changes(tmp_path: Path) -> None:
    scene = P._two_room_scene(tmp_path, 1.0)

    assert scene["openings"] == []


def test_a_box_that_floats_is_not_emitted_as_a_door(tmp_path: Path) -> None:
    def floating(model, scale):
        boxes = {}
        for frame, box in _door_boxes(model, scale, 1.0, 1.9).items():
            boxes[frame] = (box[0], box[1] - 0.12, box[2], box[3] - 0.12)  # lifted off the floor
        return _detector(boxes)

    scene, _ = _scene(tmp_path, 1.0, floating)

    assert [o for o in scene["openings"] if o["type"] == "door"] == []


def test_a_door_seen_at_the_crossing_between_rooms_is_not_marked_estimated(tmp_path: Path) -> None:
    scene, _ = _scene(tmp_path, 1.0, lambda model, scale: _on_shared_door(model, scale))

    assert "source" not in scene["openings"][0]


def test_a_window_has_no_crossing_so_it_is_marked_estimated_and_keeps_its_sill(tmp_path: Path) -> None:
    def window(model, scale):
        return _detector(_door_boxes(model, scale, 0.9, 1.9, y0=0.9, y1=1.9), kind="window")

    scene, _ = _scene(tmp_path, 1.0, window)

    windows = [o for o in scene["openings"] if o["type"] == "window"]
    # Both rooms see the opening through their own wall: in this synthetic model the two walls sit
    # side by side instead of being welded, so each room reports it.
    assert windows
    assert all(w["source"] == "estimated" for w in windows)
    # sill 0.9 under a 1.0 high window: the ratio survives the plan scale, never metres
    assert windows[0]["sillHeight"] / windows[0]["height"] == pytest.approx(0.9, abs=0.2)


def test_a_failing_opening_detector_does_not_break_the_scene(tmp_path: Path) -> None:
    def broken(model, scale):
        def detect(path):
            raise RuntimeError("model crashed")

        return detect

    scene, warnings = _scene(tmp_path, 1.0, broken)

    assert scene["openings"] == []
    assert any("puertas" in w.lower() for w in warnings)


def _scored_detector(boxes, scores):
    """A detector that goes through the real door-versus-lookalike decision of ``openings``."""
    import openings

    def detect(path: Path):
        frame = int(path.stem)
        if frame not in boxes:
            return []
        verdict = openings.classify(scores)
        return [(boxes[frame], *verdict)] if verdict else []

    return detect


def _scores(door: float, wardrobe: float) -> dict[str, float]:
    return {"a door": door, "a window": 0.0, "an archway": 0.0, "a wardrobe": wardrobe, "a mirror": 0.0}


def test_a_wardrobe_that_looks_like_a_door_never_reaches_the_scene(tmp_path: Path) -> None:
    scene, _ = _scene(
        tmp_path, 1.0, lambda model, scale: _scored_detector(_door_boxes(model, scale, 1.0, 1.9), _scores(0.45, 0.42))
    )

    assert scene["openings"] == []


def test_the_same_box_with_a_clear_door_score_does_reach_the_scene(tmp_path: Path) -> None:
    scene, _ = _scene(
        tmp_path, 1.0, lambda model, scale: _scored_detector(_door_boxes(model, scale, 1.0, 1.9), _scores(0.8, 0.2))
    )

    assert [o["type"] for o in scene["openings"]] == ["door"]
