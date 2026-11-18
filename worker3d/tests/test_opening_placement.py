"""F07 door placement (S2, S3, S7): a recognised box becomes a position on a wall, in plan units.

The placement is checked against a door whose geometry is known only to the test; the code
under test gets the pixel boxes and the camera poses, never the expected numbers.
"""

from __future__ import annotations

import pytest
import opening_placement as op

WIDTH, HEIGHT, FOCAL = 640.0, 480.0, 500.0
# Camera looks along +z with world y up: camera x is world -x, camera y (down) is world -y.
FACING_Z = ((-1.0, 0.0, 0.0), (0.0, -1.0, 0.0), (0.0, 0.0, 1.0))
# Room 4 x 3 (x/z), height 2.4; the wall z=3 is edge 2 of this counter-clockwise contour.
ROOM = [(0.0, 0.0), (4.0, 0.0), (4.0, 3.0), (0.0, 3.0)]
FLOOR_Y, ROOM_HEIGHT = 0.0, 2.4


def camera(x: float, y: float = 1.4, z: float = 0.2) -> op.Camera:
    return op.Camera(frame=0, center=(x, y, z), rotation=FACING_Z, width=WIDTH, height=HEIGHT, fx=FOCAL, fy=FOCAL, cx=WIDTH / 2, cy=HEIGHT / 2)


def pixel(cam: op.Camera, point: tuple[float, float, float]) -> tuple[float, float]:
    rel = tuple(p - c for p, c in zip(point, cam.center, strict=True))
    # world_from_camera is its own inverse for this diagonal rotation
    x, y, z = (-rel[0], -rel[1], rel[2])
    return cam.fx * x / z + cam.cx, cam.fy * y / z + cam.cy


def box_of(cam: op.Camera, x_left: float, x_right: float, bottom: float, top: float, z: float = 3.0):
    """Normalised box of a rectangle on the wall z=3 spanning x_left..x_right, bottom..top (y)."""
    corners = [pixel(cam, (x, y, z)) for x in (x_left, x_right) for y in (bottom, top)]
    us, vs = [c[0] for c in corners], [c[1] for c in corners]
    return (min(us) / cam.width, min(vs) / cam.height, max(us) / cam.width, max(vs) / cam.height)


def place(cam, box, kind="door", score=0.8):
    return op.place_detection(ROOM, FLOOR_Y, ROOM_HEIGHT, cam, box, kind, score)


def test_a_door_on_the_far_wall_gets_its_edge_position_width_and_height() -> None:
    cam = camera(x=2.0)
    box = box_of(cam, 1.5, 2.4, 0.0, 2.0)  # a 0.9 wide, 2.0 high door whose left edge is x=1.5

    found = place(cam, box)

    assert found is not None
    assert found.edge == 2
    # edge 2 runs from (4,3) to (0,3): the door centre x=1.95 is 2.05 along its 4.0 length
    assert found.position == pytest.approx(2.05 / 4.0, abs=0.01)
    assert found.width == pytest.approx(0.9, abs=0.02)
    assert found.height == pytest.approx(2.0, abs=0.03)
    assert found.sill == pytest.approx(0.0, abs=0.03)


def test_the_result_does_not_depend_on_the_camera_distance() -> None:
    near, far = camera(x=2.0, z=1.6), camera(x=2.0, z=0.1)

    a = place(near, box_of(near, 1.5, 2.4, 0.0, 2.0))
    b = place(far, box_of(far, 1.5, 2.4, 0.0, 2.0))

    assert a is not None and b is not None
    assert (a.position, a.width, a.height) == pytest.approx((b.position, b.width, b.height), abs=0.02)


def test_a_box_that_floats_above_the_floor_is_not_a_door() -> None:
    cam = camera(x=2.0)

    assert place(cam, box_of(cam, 1.5, 2.4, 0.9, 2.1)) is None


def test_a_window_may_float_and_reports_its_sill() -> None:
    cam = camera(x=2.0)

    found = place(cam, box_of(cam, 1.0, 2.0, 0.9, 1.9), kind="window")

    assert found is not None
    assert found.sill == pytest.approx(0.9, abs=0.03)
    assert found.height == pytest.approx(1.0, abs=0.03)


def test_a_box_that_does_not_land_on_any_wall_is_discarded() -> None:
    cam = camera(x=2.0)
    box = box_of(cam, 1.5, 2.4, 0.0, 2.0, z=3.0)
    sideways = (box[0] + 2.0, box[1], box[2] + 2.0, box[3])  # far off the image, beyond the room

    assert place(cam, sideways) is None


def test_views_of_the_same_door_become_one_opening() -> None:
    views = []
    for x in (1.2, 2.0, 2.8):
        cam = camera(x=x)
        views.append(place(cam, box_of(cam, 1.5, 2.4, 0.0, 2.0)))

    merged = op.merge_views([v for v in views if v is not None])

    assert len(merged) == 1
    assert merged[0].views == 3
    assert merged[0].width == pytest.approx(0.9, abs=0.03)


def test_two_different_doors_on_one_wall_stay_apart() -> None:
    cam = camera(x=2.0)
    first = place(cam, box_of(cam, 0.3, 1.2, 0.0, 2.0))
    second = place(cam, box_of(cam, 2.8, 3.7, 0.0, 2.0))

    merged = op.merge_views([first, second])

    assert len(merged) == 2
