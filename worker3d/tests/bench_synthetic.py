"""Synthetic bench for the F07 reconstruction: known rooms in, error figures out.

Each case is two connected rooms filmed by simulated cameras, with a door or a window on the wall
they share (and, optionally, a wardrobe that scores almost like a door). The case's true geometry
lives only here: the pipeline gets the cloud, the camera poses and the detector's boxes, exactly
as in production, and the scene it returns is compared with the truth afterwards.

What it tells: how well the geometry and the fusion recover a known room, with the noise level you
choose. What it does not tell: how the door model or the phone behave on a real recording. Errors
are ratios or fractions of the host wall, never metres.

    python worker3d/tests/bench_synthetic.py --cases 30 --seed 1 --point-noise 0.02 --pixel-noise 3
    python worker3d/tests/bench_synthetic.py --decoys --set openings.MIN_MARGIN=0.05 --out run.json

``--set module.CONSTANT=value`` (repeatable) replaces a threshold of the worker for the run, so two
configurations can be compared on the very same cases.
"""

from __future__ import annotations

import argparse
import ast
import contextlib
import importlib
import json
import math
import random
import sys
import tempfile
from collections.abc import Iterator
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

TESTS_DIR = Path(__file__).resolve().parent
sys.path[:0] = [str(TESTS_DIR.parent), str(TESTS_DIR)]

import opening_placement  # noqa: F401 - imported so ``--set`` can reach it
import openings
import reconstruct
import reconstruct_video as rv
import test_reconstruct_video as T

OVERRIDABLE_MODULES = frozenset({"openings", "opening_placement", "reconstruct", "reconstruct_video"})
TRUE_DOOR_SCORES = {"a door": 0.75, "a wardrobe": 0.2}
TRUE_WINDOW_SCORES = {"a window": 0.75, "a wardrobe": 0.2}
DECOY_SCORES = {"a door": 0.45, "a wardrobe": 0.42}  # a wardrobe the model almost takes for a door
DUPLICATE_RADIUS = 0.15  # same kind this close to the match along the wall: the same opening, seen twice
SHIFT = (3.0, -2.0, 5.0)
LEVEL_PITCH_DEG = 5.0


@dataclass(frozen=True)
class BenchConfig:
    cases: int = 20
    seed: int = 1
    point_noise: float = 0.0  # metres of the true room, Gaussian, on every cloud point
    pixel_noise: float = 0.0  # pixels, Gaussian, on every coordinate of a detector box
    outliers: float = 0.0  # share of cloud points replaced by stray points anywhere near the room
    pose_rotation_noise: float = 0.0  # degrees, Gaussian angle about a random axis, on every camera
    pose_position_noise: float = 0.0  # metres of the true room, Gaussian, on every camera centre
    score_noise: float = 0.0  # Gaussian, on the model's probabilities
    decoys: bool = False
    window_share: float = 0.25
    wall: float | None = None  # thickness of the shared wall in metres; None: drawn per case (0.08 to 0.3)
    overrides: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class Case:
    index: int
    seed: int
    wa: float
    da: float
    wb: float
    db: float
    height: float
    sfm_scale: float
    kind: str  # "door" | "window"
    center: float  # along the shared wall, from its start
    width: float
    opening_height: float
    sill: float
    decoy_center: float | None
    wall: float  # thickness of the wall the two rooms share: their faces are this far apart

    # kept for the readability of the generator and the tests
    @property
    def door_center(self) -> float:
        return self.center

    @property
    def door_width(self) -> float:
        return self.width


def make_cases(
    count: int, seed: int, window_share: float = 0.25, decoys: bool = False, wall: float | None = None
) -> list[Case]:
    rng = random.Random(seed)
    cases: list[Case] = []
    for index in range(count):
        wa, da = rng.uniform(3.5, 6.0), rng.uniform(3.0, 5.0)
        wb, db = rng.uniform(2.8, 4.0), rng.uniform(2.5, min(da, 4.0))
        window = rng.random() < window_share
        width = rng.uniform(0.8, 1.0) if not window else rng.uniform(0.9, 1.2)
        opening_height = rng.uniform(1.9, 2.1) if not window else rng.uniform(1.0, 1.2)
        sill = rng.uniform(0.8, 1.0) if window else 0.0
        margin = width / 2 + 0.4
        center = rng.uniform(margin, db - margin)
        decoy = None
        if decoys:
            gap = width / 2 + 0.3 + 0.4
            if center + gap <= db - 0.4:
                decoy = rng.uniform(center + gap, db - 0.4)
            elif center - gap >= 0.4:
                decoy = rng.uniform(0.4, center - gap)
        cases.append(
            Case(
                index, rng.randrange(1 << 30), wa, da, wb, db, rng.uniform(2.4, 2.8), rng.choice((0.4, 1.0, 2.5)),
                "window" if window else "door", center, width, opening_height, sill, decoy,
                wall if wall is not None else rng.uniform(0.08, 0.3),
            )
        )
    return cases


# --- overrides ------------------------------------------------------------------------------


@contextlib.contextmanager
def overrides(assignments: list[str]) -> Iterator[None]:
    """Replace ``module.CONSTANT`` of the worker for the duration of the block."""
    saved: list[tuple[Any, str, Any]] = []
    try:
        for assignment in assignments:
            target, separator, value = assignment.partition("=")
            module_name, dot, attribute = target.partition(".")
            if not separator or not dot or module_name not in OVERRIDABLE_MODULES:
                raise ValueError(f"cannot override {assignment!r}: expected module.CONSTANT=value on a worker module")
            module = importlib.import_module(module_name)
            if not hasattr(module, attribute):
                raise ValueError(f"{module_name} has no {attribute}")
            saved.append((module, attribute, getattr(module, attribute)))
            setattr(module, attribute, ast.literal_eval(value))
        yield
    finally:
        for module, attribute, original in reversed(saved):
            setattr(module, attribute, original)


# --- one case -------------------------------------------------------------------------------


def _noisy(model: rv.SparseModel, sigma: float, scale: float, rng: random.Random) -> rv.SparseModel:
    if sigma <= 0:
        return model
    points = [
        rv.SparsePoint(tuple(c + rng.gauss(0.0, sigma * scale) for c in p.xyz), p.frames)  # type: ignore[arg-type]
        for p in model.points
    ]
    return rv.SparseModel(poses=model.poses, points=points, intrinsics=model.intrinsics)


def _outliers(model: rv.SparseModel, share: float, rng: random.Random) -> rv.SparseModel:
    """Replace a share of the points by stray ones inside the cloud's bounding box, plus 20 %."""
    if share <= 0:
        return model
    lows = [min(p.xyz[i] for p in model.points) for i in range(3)]
    highs = [max(p.xyz[i] for p in model.points) for i in range(3)]
    pads = [0.2 * (h - lo) for lo, h in zip(lows, highs, strict=True)]
    points = [
        rv.SparsePoint(tuple(rng.uniform(lo - pad, h + pad) for lo, h, pad in zip(lows, highs, pads, strict=True)), p.frames)  # type: ignore[arg-type]
        if rng.random() < share
        else p
        for p in model.points
    ]
    return rv.SparseModel(poses=model.poses, points=points, intrinsics=model.intrinsics)


def _turn(rotation: rv.Mat3, axis: tuple[float, float, float], angle: float) -> rv.Mat3:
    """``rotation`` followed by a turn of ``angle`` radians about ``axis`` (Rodrigues), in the camera frame."""
    norm = math.sqrt(sum(a * a for a in axis)) or 1.0
    x, y, z = (a / norm for a in axis)
    c, s_, t = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
    delta = (
        (t * x * x + c, t * x * y - s_ * z, t * x * z + s_ * y),
        (t * x * y + s_ * z, t * y * y + c, t * y * z - s_ * x),
        (t * x * z - s_ * y, t * y * z + s_ * x, t * z * z + c),
    )
    return tuple(  # type: ignore[return-value]
        tuple(sum(rotation[r][k] * delta[k][col] for k in range(3)) for col in range(3)) for r in range(3)
    )


def _jittered(
    model: rv.SparseModel, rotation_deg: float, position: float, scale: float, rng: random.Random
) -> rv.SparseModel:
    """Camera poses that are slightly off, as a phone's are; the cloud stays where it is."""
    if rotation_deg <= 0 and position <= 0:
        return model
    poses = []
    for pose in model.poses:
        axis = (rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))
        rotation = _turn(pose.rotation, axis, math.radians(rng.gauss(0, rotation_deg))) if rotation_deg > 0 else pose.rotation
        centre = tuple(c + rng.gauss(0, position * scale) for c in pose.center) if position > 0 else pose.center
        poses.append(rv.CameraPose(pose.frame_index, rotation, centre))  # type: ignore[arg-type]
    return rv.SparseModel(poses=poses, points=model.points, intrinsics=model.intrinsics)


def _boxes(model: rv.SparseModel, case: Case, z0: float, z1: float, y0: float, y1: float, frames: set[int]):
    """Per extracted frame, the normalised box of the opening on the shared wall, when fully visible.

    The wall has two faces: frames of the first room see the opening on its face, frames of the
    second one on the other face, one wall thickness further.
    """
    found: dict[int, tuple[float, float, float, float]] = {}
    for pose in model.poses:
        if pose.frame_index not in frames:
            continue
        try:
            corners = [
                T.project(model, pose.frame_index, (case.wa + (case.wall if pose.frame_index >= 8 else 0.0), y, z), case.sfm_scale, SHIFT)
                for z in (z0, z1)
                for y in (y0, y1)
            ]
        except AssertionError:
            continue
        xs, ys = [c["x"] for c in corners], [c["y"] for c in corners]
        found[pose.frame_index] = (min(xs), min(ys), max(xs), max(ys))
    return found


def _stats(values: list[float]) -> dict[str, float]:
    if not values:
        return {"n": 0, "mean": 0.0, "p90": 0.0, "max": 0.0}
    ordered = sorted(values)
    return {
        "n": len(values),
        "mean": round(sum(values) / len(values), 4),
        "p90": round(ordered[min(len(ordered) - 1, math.ceil(0.9 * len(ordered)) - 1)], 4),
        "max": round(ordered[-1], 4),
    }


def _room_sides(scene: dict[str, Any]) -> dict[str, tuple[float, float]]:
    walls = {w["id"]: w for w in scene["walls"]}
    sides: dict[str, tuple[float, float]] = {}
    for room in scene["rooms"]:
        xs = [p for wid in room["wallIds"] for p in (walls[wid]["start"]["x"], walls[wid]["end"]["x"])]
        zs = [p for wid in room["wallIds"] for p in (walls[wid]["start"]["z"], walls[wid]["end"]["z"])]
        a, b = max(xs) - min(xs) - reconstruct.WALL_THICKNESS_M, max(zs) - min(zs) - reconstruct.WALL_THICKNESS_M
        sides[room["name"]] = (min(a, b), max(a, b))
    return sides


def _wall_of(scene: dict[str, Any], wall_id: str) -> tuple[float, float, str] | None:
    """Length, height and room of a wall (the room that lists it first)."""
    wall = next((w for w in scene["walls"] if w["id"] == wall_id), None)
    if wall is None:
        return None
    room = next((r["name"] for r in scene["rooms"] if wall_id in r["wallIds"]), None)
    if room is None:
        return None
    length = math.dist((wall["start"]["x"], wall["start"]["z"]), (wall["end"]["x"], wall["end"]["z"]))
    return length, wall["height"], room


def run_case(case: Case, config: BenchConfig) -> dict[str, Any]:
    rng = random.Random(case.seed)
    a = T.make_model((0.0, 0.0, case.wa, case.da), height=case.height, scale=case.sfm_scale, pitch_deg=LEVEL_PITCH_DEG)
    b = T.make_model(
        (case.wa + case.wall, 0.0, case.wa + case.wall + case.wb, case.db), height=case.height, scale=case.sfm_scale, first_frame=8,
        pitch_deg=LEVEL_PITCH_DEG,
    )
    clean = rv.SparseModel(poses=a.poses + b.poses, points=a.points + b.points, intrinsics=a.intrinsics)
    model = _noisy(clean, config.point_noise, case.sfm_scale, rng)
    model = _outliers(model, config.outliers, rng)
    model = _jittered(model, config.pose_rotation_noise, config.pose_position_noise, case.sfm_scale, rng)

    stride = max(1, round(10 / rv.EXTRACT_FPS))
    extracted = set(range(0, 16, stride))
    half = case.width / 2
    truth = _boxes(clean, case, case.center - half, case.center + half, case.sill, case.sill + case.opening_height, extracted)
    decoys = {}
    if case.decoy_center is not None:
        decoys = _boxes(clean, case, case.decoy_center - 0.4, case.decoy_center + 0.4, 0.0, 2.0, extracted)

    def jitter(box: tuple[float, float, float, float], frame_rng: random.Random):
        s = config.pixel_noise
        return (
            box[0] + frame_rng.gauss(0, s) / T.WIDTH, box[1] + frame_rng.gauss(0, s) / T.HEIGHT,
            box[2] + frame_rng.gauss(0, s) / T.WIDTH, box[3] + frame_rng.gauss(0, s) / T.HEIGHT,
        )

    def noisy_scores(scores: dict[str, float], frame_rng: random.Random) -> dict[str, float]:
        full = {prompt: 0.0 for prompt in openings.PROMPTS}
        full.update(scores)
        if config.score_noise > 0:
            full = {p: min(1.0, max(0.0, v + frame_rng.gauss(0, config.score_noise))) for p, v in full.items()}
        return full

    def scorer(path: Path):
        frame = int(path.stem)
        frame_rng = random.Random(case.seed * 1009 + frame)
        raw = []
        if frame in truth:
            scores = TRUE_WINDOW_SCORES if case.kind == "window" else TRUE_DOOR_SCORES
            raw.append((jitter(truth[frame], frame_rng), noisy_scores(scores, frame_rng)))
        if frame in decoys:
            raw.append((jitter(decoys[frame], frame_rng), noisy_scores(DECOY_SCORES, frame_rng)))
        return raw

    def detector_factory():
        # Thresholds are read now, so an ``--set`` override is honoured.
        return openings.detector_from(
            scorer, "owlv2", min_score=max(openings.MIN_SCORE, openings.RAW_FLOOR), min_margin=openings.MIN_MARGIN
        )

    with tempfile.TemporaryDirectory(prefix="roomforge-bench-") as scratch:
        manifest = T.v2_manifest(rooms=[
            {"id": "room-1", "name": "Estar", "fromNs": T.T0, "toNs": T.T0 + 8 * T.STEP},
            {"id": "room-2", "name": "Cuarto", "fromNs": T.T0 + 8 * T.STEP, "toNs": T.T0 + 20 * T.STEP},
        ])
        package = T.write_v2(Path(scratch) / "package", manifest, frames=T.frame_lines(16), sensors=T.gravity_lines([clean]))
        try:
            scene = T.run(package, [model], opening_detector=detector_factory).scene_draft
        except Exception as error:  # noqa: BLE001 - a case that cannot be reconstructed is a result, not a crash
            return {"index": case.index, "failed": str(error)[:200], "case": asdict(case)}

    return {"index": case.index, "case": asdict(case), **_measure(case, scene, visible=bool(truth), decoyed=bool(decoys))}


def _measure(case: Case, scene: dict[str, Any], visible: bool, decoyed: bool) -> dict[str, Any]:
    sides = _room_sides(scene)
    true_ratio = {"Estar": max(case.wa, case.da) / min(case.wa, case.da), "Cuarto": max(case.wb, case.db) / min(case.wb, case.db)}
    ratio_err = {
        name: abs(sides[name][1] / sides[name][0] / true_ratio[name] - 1) for name in true_ratio if name in sides
    }
    area_err = None
    if len(sides) == 2:
        measured = (sides["Estar"][0] * sides["Estar"][1]) / (sides["Cuarto"][0] * sides["Cuarto"][1])
        area_err = abs(measured / ((case.wa * case.da) / (case.wb * case.db)) - 1)

    thickness = reconstruct.WALL_THICKNESS_M
    scale = math.sqrt(sides["Cuarto"][0] * sides["Cuarto"][1] / (case.wb * case.db)) if "Cuarto" in sides else 1.0
    candidates = []
    for opening in scene["openings"]:
        wall = _wall_of(scene, opening["wallId"])
        if wall is None or opening["type"] != case.kind:
            continue
        length, wall_height, _ = wall
        # The wall that holds the opening starts at the north end of the shared line, whether it is the
        # whole side of one room or only the part both rooms share. Plan units are not metres: the
        # scene's own scale (from the second room's area) converts the truth, the wall thickness aside.
        true_position = (scale * case.center + thickness / 2) / length
        position = opening["position"]
        candidates.append(
            {
                "position_err": min(abs(position - true_position), abs(1 - position - true_position)),
                "width_err": abs(opening["width"] / length - scale * case.width / length),
                "height_err": abs(opening["height"] / wall_height - case.opening_height / case.height),
                "sill_err": abs(opening.get("sillHeight", 0.0) / wall_height - case.sill / case.height),
            }
        )
    best = min(candidates, key=lambda c: c["position_err"], default=None)
    emitted = len(scene["openings"])
    matched = 1 if best else 0
    duplicates = sum(1 for c in candidates if c is not best and c["position_err"] <= DUPLICATE_RADIUS)
    return {
        "ratio_err": ratio_err,
        "area_ratio_err": area_err,
        "visible": visible,
        "decoyed": decoyed,
        "emitted": emitted,
        "matched": matched,
        "missed": 1 if visible and not best else 0,
        "duplicates": duplicates,
        "spurious": max(0, emitted - matched - duplicates),
        **({"opening": best} if best else {}),
    }


# --- the whole bench ------------------------------------------------------------------------


def run_bench(config: BenchConfig) -> dict[str, Any]:
    cases = make_cases(config.cases, config.seed, config.window_share, config.decoys, config.wall)
    with overrides(config.overrides):
        results = [run_case(case, config) for case in cases]
    done = [r for r in results if "failed" not in r]
    ratios = [v for r in done for v in r["ratio_err"].values()]
    opening = [r["opening"] for r in done if "opening" in r]
    windows = [r["opening"] for r in done if "opening" in r and r["case"]["kind"] == "window"]
    summary = {
        "cases": len(results),
        "failed": len(results) - len(done),
        "visible": sum(1 for r in done if r["visible"]),
        "missed": sum(r["missed"] for r in done),
        "spurious": sum(r["spurious"] for r in done),
        "duplicates": sum(r["duplicates"] for r in done),
        "decoys": sum(1 for r in done if r["decoyed"]),
        "ratio_err": _stats(ratios),
        "area_ratio_err": _stats([r["area_ratio_err"] for r in done if r["area_ratio_err"] is not None]),
        "opening_position_err": _stats([o["position_err"] for o in opening]),
        "opening_width_err": _stats([o["width_err"] for o in opening]),
        "opening_height_err": _stats([o["height_err"] for o in opening]),
        "opening_sill_err": _stats([o["sill_err"] for o in windows]),
    }
    return {"config": asdict(config), "summary": summary, "cases": results}


def format_summary(report: dict[str, Any]) -> str:
    summary = report["summary"]
    lines = [
        (
            f"cases={summary['cases']} failed={summary['failed']} visible={summary['visible']} "
            f"missed={summary['missed']} spurious={summary['spurious']} duplicates={summary['duplicates']} "
            f"decoys={summary['decoys']}"
        ),
        f"{'metric':24}{'n':>5}{'mean':>9}{'p90':>9}{'max':>9}",
    ]
    for name in ("ratio_err", "area_ratio_err", "opening_position_err", "opening_width_err", "opening_height_err", "opening_sill_err"):
        s = summary[name]
        lines.append(f"{name:24}{s['n']:>5}{s['mean']:>9.4f}{s['p90']:>9.4f}{s['max']:>9.4f}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> dict[str, Any]:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cases", type=int, default=20)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--point-noise", type=float, default=0.0, help="metres, Gaussian, per cloud point")
    parser.add_argument("--pixel-noise", type=float, default=0.0, help="pixels, Gaussian, per box coordinate")
    parser.add_argument("--score-noise", type=float, default=0.0, help="Gaussian on the model probabilities")
    parser.add_argument("--outliers", type=float, default=0.0, help="share of cloud points replaced by stray ones")
    parser.add_argument("--pose-rot-noise", type=float, default=0.0, help="degrees, Gaussian, per camera")
    parser.add_argument("--pose-pos-noise", type=float, default=0.0, help="metres, Gaussian, per camera centre")
    parser.add_argument("--decoys", action="store_true", help="add a wardrobe that scores almost like a door")
    parser.add_argument("--window-share", type=float, default=0.25)
    parser.add_argument("--wall", type=float, default=None, help="shared wall thickness in metres (default: drawn per case)")
    parser.add_argument("--set", dest="overrides", action="append", default=[], metavar="MODULE.CONSTANT=VALUE")
    parser.add_argument("--out", type=Path, help="write the full report as JSON")
    args = parser.parse_args(argv)
    config = BenchConfig(
        cases=args.cases, seed=args.seed, point_noise=args.point_noise, pixel_noise=args.pixel_noise,
        outliers=args.outliers, pose_rotation_noise=args.pose_rot_noise, pose_position_noise=args.pose_pos_noise,
        score_noise=args.score_noise, decoys=args.decoys, window_share=args.window_share, wall=args.wall, overrides=args.overrides,
    )
    report = run_bench(config)
    print(format_summary(report))
    if args.out:
        args.out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


if __name__ == "__main__":
    main()
