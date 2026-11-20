"""F07 regularization (S1): connected rooms share one dominant axis, without any measure."""

from __future__ import annotations

import math

import reconstruct


def _rotated_box(width: float, depth: float, degrees: float, origin: tuple[float, float] = (0.0, 0.0)):
    """Observed wall segments of a box rotated by ``degrees`` around ``origin`` (x/z plane)."""
    angle = math.radians(degrees)
    cos, sin = math.cos(angle), math.sin(angle)

    def turn(x: float, z: float) -> tuple[float, float]:
        return (origin[0] + x * cos - z * sin, origin[1] + x * sin + z * cos)

    corners = [turn(0, 0), turn(width, 0), turn(width, depth), turn(0, depth)]
    return [(corners[i], corners[(i + 1) % 4]) for i in range(4)]


def _edge_angles(corners: list[tuple[float, float]]) -> list[float]:
    """Direction of every contour edge folded to [0, 90) degrees."""
    angles = []
    for i, a in enumerate(corners):
        b = corners[(i + 1) % len(corners)]
        angles.append(math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])) % 90)
    return angles


def _off_axis(angle: float) -> float:
    return min(angle, 90 - angle)


def test_the_dominant_axis_of_walls_is_exposed() -> None:
    walls = _rotated_box(4, 3, 3.0)

    assert abs(math.degrees(reconstruct.dominant_axis(walls)) - 3.0) < 1e-6


def test_a_room_rotated_a_few_degrees_follows_the_axis_it_is_given() -> None:
    walls = _rotated_box(3, 2, 3.0, origin=(4.0, 0.0))

    proposal = reconstruct.propose_contour(walls, [], [(5.5, 1.0)], axis=0.0)

    assert not isinstance(proposal, reconstruct.ProposalFailed)
    assert all(_off_axis(a) < 1e-6 for a in _edge_angles(proposal.corners))


def test_without_a_given_axis_a_room_keeps_its_own_orientation() -> None:
    walls = _rotated_box(3, 2, 3.0, origin=(4.0, 0.0))

    proposal = reconstruct.propose_contour(walls, [], [(5.5, 1.0)])

    assert not isinstance(proposal, reconstruct.ProposalFailed)
    assert all(abs(_off_axis(a) - 3.0) < 1e-6 for a in _edge_angles(proposal.corners))


def test_a_room_really_off_the_axis_keeps_its_angle() -> None:
    walls = _rotated_box(3, 2, 30.0, origin=(4.0, 0.0))

    proposal = reconstruct.propose_contour(walls, [], [(5.5, 1.0)], axis=0.0)

    assert not isinstance(proposal, reconstruct.ProposalFailed)
    assert all(abs(min(a, 90 - a) - 30.0) < 1e-6 for a in _edge_angles(proposal.corners))


def test_rooms_of_one_reconstruction_receive_the_same_axis(tmp_path, monkeypatch) -> None:
    import test_proportional_scale as P

    seen: list[float | None] = []
    original = reconstruct.propose_contour

    def spy(walls, floors, trajectory, axis=None):
        seen.append(axis)
        return original(walls, floors, trajectory, axis=axis)

    monkeypatch.setattr(reconstruct, "propose_contour", spy)

    P._two_room_scene(tmp_path, 1.0)

    assert len(seen) == 2
    assert seen[0] is not None and seen[0] == seen[1]
