"""Geometric safeguards use real projections; no claim of measured phone accuracy."""
from __future__ import annotations

import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import reconstruct_video as rv
import test_reconstruct_video as T


def test_unscaled_geometry_has_no_metric_unit(tmp_path: Path) -> None:
    model = T.make_model((0, 0, 4, 3))
    package, _ = T.single_room(tmp_path)
    # Interrupted marking is retained as evidence, never as a confirmed reference.
    (package / "reference-draft.json").write_text('{"confirmed":false,"lengthM":100}')
    result = T.run(package, [model])
    assert result.scene_draft["unit"] == "arbitrary"
    assert result.scene_draft["measurement"]["scale"] == "unscaled"


def test_floor_reference_outside_observed_support_is_rejected() -> None:
    fit = rv._RoomFit("r", "r", 0.0, 2.5, [(0, 0), (1, 0), (1, 1), (0, 1)], [], [], 50)
    pose = rv.CameraPose(0, ((1., 0., 0.), (0., -1., 0.), (0., 0., -1.)), (3., 1., 0.))
    k = rv.Intrinsics(100, 100, 100, 100, 50, 50)
    assert rv._plane_hits([{"x": .5, "y": .8}], pose, k, fit, "floor") is None


def test_wall_reference_cannot_extrapolate_beyond_the_observed_segment() -> None:
    wall = rv._WallLine((0., 0.), (1., 0.), (0., 1.), 0., 1., 0., 2., [])
    fit = rv._RoomFit("r", "r", 0., 2.5, [], [wall], [], 50)
    pose = rv.CameraPose(0, ((1., 0., 0.), (0., 1., 0.), (0., 0., 1.)), (3., 1., -1.))
    k = rv.Intrinsics(100, 100, 100, 100, 50, 50)
    assert rv._plane_hits([{"x": .5, "y": .5}], pose, k, fit, "wall") is None


@pytest.mark.parametrize("radial", [-.0187772819, .1, 0.])
def test_radial_projection_and_reference_unprojection_agree(radial: float) -> None:
    k = rv.Intrinsics(1024, 768, 850, 850, 512, 384, radial)
    pose = rv.CameraPose(0, ((1., 0., 0.), (0., 1., 0.), (0., 0., 1.)), (0., 0., 0.))
    x, y = .48, .32
    factor = 1 + radial * (x*x + y*y)
    pixel = {"x": (k.fx*x*factor+k.cx)/k.width, "y": (k.fy*y*factor+k.cy)/k.height}
    _, ray = rv._pixel_ray(pixel, pose, k)
    assert ray[0]/ray[2] == pytest.approx(x, abs=1e-7)
    assert ray[1]/ray[2] == pytest.approx(y, abs=1e-7)
    assert math.isfinite(sum(ray))
