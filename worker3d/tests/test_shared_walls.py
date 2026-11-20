"""F07 shared walls: two rooms that touch end up with one wall between them, and a door is one door.

Interior faces come from each room's own observations, so two adjacent rooms rarely agree to the
centimetre: a wall with no thickness (both faces on one plane) or a thicker or thinner one than
the builder assumes leaves two almost-coincident walls. Those are welded when the builder is asked
to (reconstruct_video asks; the schema 1 path does not, and keeps its output).
"""

from __future__ import annotations

import math
from typing import Any

import pytest
import reconstruct

THICKNESS = reconstruct.WALL_THICKNESS_M


def room(name: str, corners: list[tuple[float, float]], group: int = 0, openings: list[dict[str, Any]] | None = None):
    return reconstruct._Room(
        id=name.lower(), name=name, corners=corners, height=2.4, height_source="assumed", measured=False,
        openings=openings or [], group=group,
    )


def rect(x0: float, z0: float, x1: float, z1: float) -> list[tuple[float, float]]:
    return [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]  # counter-clockwise on x/z


def build(rooms, snap: bool = True) -> tuple[dict[str, Any], list[str]]:
    builder = reconstruct._SceneBuilder(rooms, [], snap_shared_walls=snap)
    return builder.build(), builder.warnings


def shared(scene: dict[str, Any]) -> set[str]:
    """Vertical walls (constant x) listed by both rooms: the north walls of rooms on one line touch anyway."""
    walls = {w["id"]: w for w in scene["walls"]}
    both = set(scene["rooms"][0]["wallIds"]) & set(scene["rooms"][1]["wallIds"])
    return {i for i in both if walls[i]["start"]["x"] == walls[i]["end"]["x"]}


def walls_on_x(scene: dict[str, Any], x: float, tolerance: float = 0.01) -> list[dict[str, Any]]:
    return [
        w for w in scene["walls"]
        if abs(w["start"]["x"] - x) < tolerance and abs(w["end"]["x"] - x) < tolerance
    ]


@pytest.mark.parametrize("gap", [0.0, THICKNESS, 0.25])
def test_adjacent_rooms_whatever_the_gap_between_their_faces_share_one_wall(gap: float) -> None:
    scene, _ = build([room("A", rect(0, 0, 4, 3)), room("B", rect(4 + gap, 0, 7 + gap, 2))])

    assert shared(scene)
    # one line of wall between them, not two parallel copies
    xs = {round(w["start"]["x"], 2) for w in scene["walls"] if w["start"]["x"] == w["end"]["x"]}
    assert len([x for x in xs if 3.5 < x < 5]) == 1


def test_without_the_option_two_coincident_faces_stay_as_two_walls() -> None:
    scene, _ = build([room("A", rect(0, 0, 4, 3)), room("B", rect(4, 0, 7, 2))], snap=False)

    assert not shared(scene)


def test_faces_that_are_exactly_one_thickness_apart_are_not_moved() -> None:
    scene, _ = build([room("A", rect(0, 0, 4, 3)), room("B", rect(4 + THICKNESS, 0, 7, 2))])

    assert walls_on_x(scene, 4 + THICKNESS / 2)  # the shared centre line, where physics puts it


def test_each_room_gives_up_at_most_half_the_gap() -> None:
    gap = 0.25
    scene, _ = build([room("A", rect(0, 0, 4, 3)), room("B", rect(4 + gap, 0, 7 + gap, 2))])

    centre = (4 + THICKNESS / 2 + 4 + gap - THICKNESS / 2) / 2  # midway between the two centre lines
    assert walls_on_x(scene, centre)


def test_rooms_further_apart_than_the_tolerance_stay_separate() -> None:
    scene, _ = build([room("A", rect(0, 0, 4, 3)), room("B", rect(4.9, 0, 8, 2))])

    assert not shared(scene)


def test_rooms_of_different_pieces_are_never_welded() -> None:
    scene, _ = build([room("A", rect(0, 0, 4, 3), group=0), room("B", rect(4, 0, 7, 2), group=1)])

    assert not shared(scene)


def test_edges_that_are_not_parallel_are_left_alone() -> None:
    angle = math.radians(20)
    tilted = [(4 + 3 * math.sin(angle) * f, 3 * f) for f in (0.0, 1.0)]  # a slanted west side
    slanted = [tilted[0], (7.0, 0.0), (7.0, 3.0), tilted[1]]  # counter-clockwise, west edge slanted

    scene, _ = build([room("A", rect(0, 0, 4, 3)), room("B", slanted)])

    assert not shared(scene)
    assert walls_on_x(scene, 4 + THICKNESS / 2)  # A's east wall did not move towards the slanted one


def test_a_door_seen_from_both_rooms_is_one_door() -> None:
    door_a = {"edge": 1, "position": 0.5, "width": 0.9, "height": 2.0, "sill": 0.0, "kind": "door"}
    # B's west edge runs (4, 2) -> (4, 0): the same spot, 1.5 along A's wall, is 0.25 along B's
    door_b = {"edge": 3, "position": 0.25, "width": 0.9, "height": 2.0, "sill": 0.0, "kind": "door"}

    scene, _ = build([room("A", rect(0, 0, 4, 3), openings=[door_a]), room("B", rect(4, 0, 7, 2), openings=[door_b])])

    assert [o["type"] for o in scene["openings"]] == ["door"]


def test_welding_removes_the_same_wall_captured_twice_warning() -> None:
    _, with_snap = build([room("A", rect(0, 0, 4, 3)), room("B", rect(4, 0, 7, 2))])
    _, without = build([room("A", rect(0, 0, 4, 3)), room("B", rect(4, 0, 7, 2))], snap=False)

    assert any("misma pared capturada dos veces" in w for w in without)
    assert not any("misma pared capturada dos veces" in w for w in with_snap)


def test_a_single_room_is_not_affected() -> None:
    plain, _ = build([room("A", rect(0, 0, 4, 3))], snap=False)
    snapped, _ = build([room("A", rect(0, 0, 4, 3))], snap=True)

    assert plain == snapped


def test_disconnected_pieces_of_a_reconstruction_are_never_welded_even_when_placed_close(
    tmp_path, monkeypatch: pytest.MonkeyPatch
) -> None:
    import reconstruct_video as rv
    import test_reconstruct_video as T

    first = T.make_model((0.0, 0.0, 4.0, 3.0))
    second = T.make_model((0.0, 0.0, 3.0, 3.0), first_frame=8, scale=0.7, shift=(-4.0, 1.0, 2.0))
    manifest = T.v2_manifest(rooms=[
        {"id": "room-1", "name": "Estar", "fromNs": T.T0, "toNs": T.T0 + 8 * T.STEP},
        {"id": "room-2", "name": "Cuarto", "fromNs": T.T0 + 8 * T.STEP, "toNs": T.T0 + 20 * T.STEP},
    ])
    package = T.write_v2(tmp_path / "p", manifest, frames=T.frame_lines(16), sensors=T.gravity_lines([first, second]))
    # With the pieces drawn side by side almost touching, only the piece boundary keeps them apart.
    monkeypatch.setattr(rv, "PIECE_GAP_M", 0.05)

    scene = T.run(package, [first, second]).scene_draft

    assert not shared(scene)
