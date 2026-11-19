# ruff: noqa: E402  -- tests import the standalone worker after configuring sys.path.
"""``reference.rect`` (F07 T16): validation, two scale estimates and optional corner refinement.

The refinement itself needs OpenCV, which is not installed here: its seam is tested with fakes and
a simulated import failure. Its real accuracy on a real image is NOT measured by these tests.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

import pytest

WORKER3D_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKER3D_DIR))
sys.path.insert(0, str(WORKER3D_DIR / "tests"))

import reconstruct
import reconstruct_video as rv
import test_reconstruct_video as T

SHIFT = (3.0, -2.0, 5.0)
# Mirror of panel/staff-shell/src/application/captureWarnings.ts (SCALE_WARNING).
PANEL_SCALE_WARNING = re.compile(r"medida de referencia|escala m[eé]trica|unidades arbitrarias", re.IGNORECASE)
# Floor rectangle in metres: long side along x (0.5 m), short side along z (0.3 m).
FLOOR_CORNERS = [(1.9, 0.0, 1.3), (2.4, 0.0, 1.3), (2.4, 0.0, 1.6), (1.9, 0.0, 1.6)]


def rect_reference(
    model: rv.SparseModel, *, height_m: float = 0.3, **rect_overrides: Any
) -> dict[str, Any]:
    corners = [T.project(model, 0, c, 0.4, SHIFT) for c in FLOOR_CORNERS]
    rect: dict[str, Any] = {"widthM": 0.5, "heightM": height_m, "corners": corners, "source": "auto"}
    rect.update(rect_overrides)
    return {
        "kind": "object", "label": "Hoja A4", "lengthM": 0.5, "surface": "floor", "frameNs": T.T0,
        "p1": dict(corners[0]), "p2": dict(corners[1]), "rect": rect,
    }


def without_rect(reference: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in reference.items() if k != "rect"}


def run_rect(tmp_path: Path, reference: dict[str, Any], **kwargs: Any) -> reconstruct.ReconstructionResult:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    package = T.write_v2(
        tmp_path / "p", T.v2_manifest(reference=reference), sensors=T.gravity_lines([model])
    )
    return rv.reconstruct_video(
        package, extractor=T.FakeExtractor(), estimator=T.FakeEstimator([model]), **kwargs
    )


def room_size(result: reconstruct.ReconstructionResult) -> list[float]:
    return [round(v - 0.15, 3) for v in T.wall_lengths(result.scene_draft)]


# --- validation -----------------------------------------------------------------------------


def _bad(mutate: Any) -> dict[str, Any]:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    reference = rect_reference(model)
    mutate(reference)
    return reference


def _set(key: str, value: Any) -> Any:
    return lambda ref: ref["rect"].__setitem__(key, value)


def _corner(index: int, point: dict[str, float]) -> Any:
    return lambda ref: ref["rect"]["corners"].__setitem__(index, point)


def _swap_tail(ref: dict[str, Any]) -> None:
    corners = ref["rect"]["corners"]
    corners[2], corners[3] = corners[3], corners[2]


def _collapse(ref: dict[str, Any]) -> None:
    corners = ref["rect"]["corners"]
    corners[2], corners[3] = dict(corners[1]), dict(corners[0])


INCOHERENT = {
    "rect-not-object": lambda ref: ref.__setitem__("rect", [1, 2]),
    "width-differs-from-length": _set("widthM", 0.6),
    "height-zero": _set("heightM", 0),
    "height-negative": _set("heightM", -0.1),
    "height-above-width": _set("heightM", 0.7),
    "width-not-number": _set("widthM", "0.5"),
    "source-unknown": _set("source", "magic"),
    "three-corners": lambda ref: ref["rect"]["corners"].pop(),
    "corners-not-list": _set("corners", "abcd"),
    "corner0-not-p1": _corner(0, {"x": 0.5, "y": 0.5}),
    "corner1-not-p2": _corner(1, {"x": 0.6, "y": 0.6}),
    "corner-outside": _corner(2, {"x": 1.4, "y": 0.5}),
    "corner-not-finite": _corner(3, {"x": float("nan"), "y": 0.5}),
    "degenerate": _collapse,
    "bow-tie": _swap_tail,
}


@pytest.mark.parametrize("name", sorted(INCOHERENT))
def test_an_incoherent_rect_is_rejected_as_an_invalid_package(name: str) -> None:
    reference = _bad(INCOHERENT[name])

    with pytest.raises(reconstruct.InvalidPackage, match=r"reference\.rect"):
        rv.validate_manifest(T.v2_manifest(reference=reference))


def test_a_coherent_rect_passes_validation() -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))

    manifest = rv.validate_manifest(T.v2_manifest(reference=rect_reference(model)))

    assert manifest["reference"]["rect"]["source"] == "auto"


# --- two scale estimates --------------------------------------------------------------------


def test_consistent_width_and_height_use_the_length_weighted_mean_without_warning(tmp_path: Path) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    baseline = room_size(run_rect(tmp_path / "base", without_rect(rect_reference(model))))
    # Height 3 % off: s_h = 1.03 s_w, mean = s_w * (0.5 + 0.3 * 1.03) / 0.8.
    result = run_rect(tmp_path / "rect", rect_reference(model, height_m=0.309))

    factor = (0.5 + 0.3 * 1.03) / 0.8
    assert room_size(result) == pytest.approx([round(v * factor, 3) for v in baseline], abs=0.02)
    assert not any(PANEL_SCALE_WARNING.search(w) for w in result.warnings)


def test_inconsistent_estimates_leave_an_unscaled_draft(tmp_path: Path) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    baseline = room_size(run_rect(tmp_path / "base", without_rect(rect_reference(model))))

    result = run_rect(tmp_path / "rect", rect_reference(model, height_m=0.36))  # 20 % apart

    assert room_size(result) != baseline
    assert result.scene_draft["unit"] == "arbitrary"
    warnings = [w for w in result.warnings if PANEL_SCALE_WARNING.search(w)]
    assert any("8 %" in warning for warning in warnings)


def test_the_threshold_is_a_named_assumption() -> None:
    assert rv.RECT_SCALE_DISAGREEMENT_MAX == 0.08


def test_a_package_without_rect_keeps_the_previous_scale_and_warnings(tmp_path: Path) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    package, _ = T.single_room(tmp_path, reference=T.floor_reference(model))

    result = T.run(package, [model])

    assert T.wall_lengths(result.scene_draft) == [3.15, 3.15, 4.15, 4.15]
    assert not any(PANEL_SCALE_WARNING.search(w) for w in result.warnings)


def test_a_rect_that_misses_the_plane_leaves_an_unscaled_draft(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    baseline = room_size(run_rect(tmp_path / "base", without_rect(rect_reference(model))))
    monkeypatch.setattr(rv, "rect_scale", lambda *args, **kwargs: None)

    result = run_rect(tmp_path / "rect", rect_reference(model, height_m=0.36))

    assert room_size(result) != baseline
    assert result.scene_draft["unit"] == "arbitrary"
    assert any(PANEL_SCALE_WARNING.search(w) for w in result.warnings)


# --- optional corner refinement -------------------------------------------------------------

CORNERS = [{"x": 0.30, "y": 0.50}, {"x": 0.60, "y": 0.50}, {"x": 0.60, "y": 0.70}, {"x": 0.30, "y": 0.70}]
FRAME = Path("frame.jpg")


def _shifted(dx: float) -> Any:
    return lambda path, corners: [{"x": c["x"] + dx, "y": c["y"]} for c in corners]


def test_a_refinement_within_the_bound_is_used() -> None:
    out = rv.refine_rect_corners(FRAME, CORNERS, _shifted(0.005))

    assert out[0]["x"] == pytest.approx(0.305)


def test_a_refinement_beyond_the_bound_is_ignored() -> None:
    assert rv.CORNER_REFINE_MAX_SHIFT == 0.01

    assert rv.refine_rect_corners(FRAME, CORNERS, _shifted(0.05)) == CORNERS


def test_a_failing_or_malformed_refiner_leaves_the_corners_unchanged() -> None:
    def boom(path: Path, corners: Any) -> Any:
        raise RuntimeError("cv2 blew up")

    assert rv.refine_rect_corners(FRAME, CORNERS, boom) == CORNERS
    assert rv.refine_rect_corners(FRAME, CORNERS, lambda p, c: c[:3]) == CORNERS
    assert rv.refine_rect_corners(FRAME, CORNERS, lambda p, c: None) == CORNERS  # type: ignore[arg-type,return-value]


def test_the_default_refiner_returns_the_corners_when_cv2_is_missing(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setitem(sys.modules, "cv2", None)  # makes ``import cv2`` raise ImportError

    assert rv.default_corner_refiner(FRAME, CORNERS) == CORNERS


def test_the_reconstruction_calls_the_refiner_with_the_reference_frame_and_uses_its_corners(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    seen: dict[str, Any] = {}

    def refiner(path: Path, corners: list[dict[str, float]]) -> list[dict[str, float]]:
        seen["path"] = path
        return [{"x": c["x"] + 0.004, "y": c["y"]} for c in corners]

    original = rv.rect_scale

    def spy(rect: Any, corners: Any, *args: Any, **kwargs: Any) -> Any:
        seen["corners"] = corners
        return original(rect, corners, *args, **kwargs)

    monkeypatch.setattr(rv, "rect_scale", spy)
    reference = rect_reference(model)
    unrefined = reference["rect"]["corners"]

    run_rect(tmp_path, reference, corner_refiner=refiner)

    assert seen["path"].name == "000000.jpg"
    assert seen["corners"][0]["x"] == pytest.approx(unrefined[0]["x"] + 0.004)


def test_a_missing_refiner_library_does_not_change_the_result(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    model = T.make_model((0.0, 0.0, 4.0, 3.0))
    monkeypatch.setitem(sys.modules, "cv2", None)
    with_default = room_size(run_rect(tmp_path / "a", rect_reference(model, height_m=0.309)))
    identity = room_size(
        run_rect(tmp_path / "b", rect_reference(model, height_m=0.309), corner_refiner=lambda p, c: c)
    )

    assert with_default == identity
