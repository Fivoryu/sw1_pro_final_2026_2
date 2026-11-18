"""F07 robustness (S8): stray points and shaky poses must not change what the geometry finds.

The cases are the ones a phone produces and a tidy synthetic cloud never does: a few points that
belong to no surface, sitting right next to a real plane.
"""

from __future__ import annotations

import random

import pytest
import reconstruct_video as rv

TOL = 0.1


def cloud(floor: float = 0.0, ceiling: float = 2.5, per_plane: int = 300, walls: int = 350, seed: int = 1) -> list[float]:
    """Heights of a room: a dense floor, a dense ceiling and wall points between them."""
    rng = random.Random(seed)
    return (
        [floor + rng.uniform(-0.01, 0.01) for _ in range(per_plane)]
        + [ceiling + rng.uniform(-0.01, 0.01) for _ in range(per_plane)]
        + [rng.uniform(0.5, 2.0) for _ in range(walls)]
    )


def test_a_clean_room_gives_its_floor_and_ceiling() -> None:
    floor, ceiling = rv.horizontal_planes(cloud(), TOL)

    assert floor == pytest.approx(0.0, abs=0.05)
    assert ceiling == pytest.approx(2.5, abs=0.05)


def test_a_few_stray_points_beside_the_ceiling_do_not_hide_it() -> None:
    # Two tolerances above the ceiling: the dense bin stops being a local maximum of the 3-bin
    # window, and the real maximum falls on an empty bin.
    heights = cloud() + [2.5 + 2.0 * TOL + 0.01] * 3 + [2.5 - 2.0 * TOL - 0.01] * 3

    floor, ceiling = rv.horizontal_planes(heights, TOL)

    assert ceiling is not None and abs(ceiling - 2.5) < 0.06
    assert floor is not None and abs(floor) < 0.06


def test_stray_points_next_to_the_floor_do_not_hide_it_either() -> None:
    heights = cloud() + [-2.0 * TOL - 0.01] * 3 + [2.0 * TOL + 0.01] * 3

    floor, _ = rv.horizontal_planes(heights, TOL)

    assert floor is not None and abs(floor) < 0.06


def test_the_result_does_not_depend_on_where_the_bins_happen_to_fall() -> None:
    results = []
    for shift in [i * 0.011 for i in range(10)]:
        heights = [y + shift for y in cloud() + [2.5 + 2.0 * TOL + 0.01] * 3]
        floor, ceiling = rv.horizontal_planes(heights, TOL)
        assert floor is not None and ceiling is not None
        results.append(ceiling - floor)

    assert max(results) - min(results) < 0.05


# --- a measured height is kept in proportional plans ------------------------------------------


def test_in_a_proportional_plan_the_measured_height_keeps_its_ratio_to_the_room(tmp_path) -> None:
    import test_reconstruct_video as T

    # A 9 x 3 room, 2.5 high: normalised to a nominal 5.0 side it measures 1.4 high. That is not a
    # "metric ceiling below 1.8 m": the plan has no metres, so the measured height must stay.
    model = T.make_model((0.0, 0.0, 9.0, 3.0), height=2.5, scale=1.0)
    package = T.write_v2(tmp_path / "p", T.v2_manifest(), sensors=T.gravity_lines([model]))

    scene = T.run(package, [model]).scene_draft

    walls = scene["walls"]
    long_side = max(
        abs(w["end"]["x"] - w["start"]["x"]) + abs(w["end"]["z"] - w["start"]["z"]) for w in walls
    ) - 0.15
    assert scene["scale"] == {"mode": "proportional"}
    assert walls[0]["height"] / long_side == pytest.approx(2.5 / 9.0, rel=0.08)


# --- stray points do not become walls ----------------------------------------------------------


def _room_wall_points(width: float = 4.0, depth: float = 3.0) -> list[tuple[float, float, float]]:
    points = []
    for level in range(6):
        y = 0.5 + 0.3 * level
        for i in range(int(width / 0.1) + 1):
            points += [(i * 0.1, y, 0.0), (i * 0.1, y, depth)]
        for i in range(int(depth / 0.1) + 1):
            points += [(0.0, y, i * 0.1), (width, y, i * 0.1)]
    return points


def test_four_dense_walls_give_four_lines() -> None:
    lines = rv.wall_lines(_room_wall_points(), 0.08, 0.6)

    assert len(lines) == 4


def test_scattered_stray_points_do_not_add_phantom_walls() -> None:
    rng = random.Random(3)
    strays = [(rng.uniform(-0.5, 4.5), rng.uniform(0.5, 2.0), rng.uniform(-0.5, 3.5)) for _ in range(160)]

    lines = rv.wall_lines(_room_wall_points() + strays, 0.08, 0.6)

    assert len(lines) == 4


def test_a_real_short_wall_survives_the_support_rule() -> None:
    # An L-shaped room has a 1.2 long jog next to 4.0 long walls: a third of the points of the longest.
    points = _room_wall_points()
    for level in range(6):
        points += [(2.0, 0.5 + 0.3 * level, 1.0 + i * 0.1) for i in range(13)]  # a stub wall

    lines = rv.wall_lines(points, 0.08, 0.6)

    assert len(lines) == 5


# --- isolated points are dropped before anything is fitted -------------------------------------


def _room_surface_points(step: float = 0.25) -> list[tuple[float, float, float]]:
    """Floor, ceiling and four walls of a 4 x 3 x 2.5 room sampled on a regular grid."""
    points = []
    for i in range(int(4 / step) + 1):
        for j in range(int(3 / step) + 1):
            points += [(i * step, 0.0, j * step), (i * step, 2.5, j * step)]
    for k in range(int(2.5 / step) + 1):
        for i in range(int(4 / step) + 1):
            points += [(i * step, k * step, 0.0), (i * step, k * step, 3.0)]
        for j in range(int(3 / step) + 1):
            points += [(0.0, k * step, j * step), (4.0, k * step, j * step)]
    return points


def _strays(count: int, seed: int = 5) -> list[tuple[float, float, float]]:
    rng = random.Random(seed)
    return [(rng.uniform(-0.8, 4.8), rng.uniform(-0.5, 3.0), rng.uniform(-0.8, 3.8)) for _ in range(count)]


def test_points_far_from_everything_are_dropped_and_the_surfaces_stay() -> None:
    surfaces = _room_surface_points()
    strays = _strays(200)
    kept = set(rv.remove_stray_points(surfaces + strays))

    assert sum(1 for p in surfaces if p in kept) >= 0.97 * len(surfaces)
    # Deep inside the room (0.7 from every surface) a stray is alone: it must not survive. Closer to
    # a surface it is indistinguishable from the surface's own scatter and is left to the fitting.
    deep = [p for p in strays if 0.7 < p[0] < 3.3 and 0.7 < p[1] < 1.8 and 0.7 < p[2] < 2.3]
    assert deep and sum(1 for p in deep if p in kept) <= 0.4 * len(deep)


def test_a_clean_cloud_loses_almost_nothing() -> None:
    surfaces = _room_surface_points()

    assert len(rv.remove_stray_points(surfaces)) >= 0.97 * len(surfaces)


def test_a_small_cloud_is_left_alone() -> None:
    points = _strays(15)

    assert rv.remove_stray_points(points) == points


def test_dropping_strays_does_not_depend_on_the_unit_of_the_cloud() -> None:
    scaled = [(x * 7.0, y * 7.0, z * 7.0) for x, y, z in _room_surface_points() + _strays(150)]

    kept = rv.remove_stray_points(scaled)

    assert len(kept) >= 0.97 * len(_room_surface_points())
    assert len(kept) < len(scaled) - 20  # some strays went, and the same ones as without the scaling


def test_wall_fitting_after_dropping_strays_finds_the_four_walls_of_a_noisy_room() -> None:
    cloud_ = [p for p in _room_wall_points() if True] + _strays(250, seed=9)

    lines = rv.wall_lines(rv.remove_stray_points(cloud_), 0.08, 0.6)

    assert len(lines) == 4
