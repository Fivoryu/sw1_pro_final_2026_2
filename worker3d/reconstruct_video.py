"""Capture package schema 2 (video + sensors) -> scene v2 draft (F07 T5).

Lives next to ``reconstruct.py`` (schema 1, ARCore): ``reconstruct.reconstruct`` dispatches here
when ``manifest.json`` declares ``schemaVersion: 2``. The frozen package is described in
``docs/api/f07-capture-package.md`` (S9); every numeric parameter below is a heuristic, not a
measured tolerance, and nothing here has been run on a real recording.

Pipeline:

1. Validate the package (manifest, ``frames.jsonl``, ``sensors.jsonl``).
2. Extract frames (``FrameExtractor``, ffmpeg) and estimate camera poses plus sparse points
   (``PoseEstimator``, pycolmap). Both are injectable and imported lazily: this module is
   standard library only.
3. Per connected piece of the sparse model: decide "up" from the ``gravity`` samples (synchronised
   to the frames through ``frames.jsonl``), rotate the model so up is +y, assign points to rooms
   by the ``rooms[]`` time intervals, fit floor / ceiling (horizontal clusters) and walls (RANSAC
   lines in plan view) per room.
4. Metric scale: the rays of ``reference.p1`` / ``p2`` at frame ``frameNs`` are intersected with
   the fitted plane named by ``reference.surface``; scale = ``lengthM`` / reconstructed distance.
5. Assemble the scene with the helpers of ``reconstruct.py`` (contour proposal, scene builder).

The output measures are estimates: no accuracy has been measured (S7).
"""

from __future__ import annotations

import bisect
import importlib
import itertools
import json
import math
import random
import shutil
import subprocess
import tempfile
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol

import reconstruct
from reconstruct import ExternalToolMissing, InvalidPackage, ReconstructionResult

# --- Frozen package limits (S9) and heuristics (none of them measured) ----------------------

# Same figure as the API's MAX_PACKAGE_BYTES; well under the 1 GiB extraction guard.
MAX_PACKAGE_BYTES = 150 * 1024 * 1024
# 5 minutes at 30 fps is 9000 frames; 100 Hz x 3 sensors x 300 s is 90000 samples.
MAX_FRAME_LINES = 20_000
MAX_SENSOR_LINES = 400_000
SENSOR_TYPES = frozenset({"gyro", "accel", "gravity", "mag"})
VIDEO_FILE, FRAMES_FILE, SENSORS_FILE = "video.mp4", "frames.jsonl", "sensors.jsonl"

# Frames handed to SfM per second of video.
EXTRACT_FPS = 3.0
# A gravity sample further than this from a frame is not used for it.
GRAVITY_MAX_SKEW_NS = 200_000_000
# Below this length the mean of the per-frame "up" vectors is not a consistent direction.
GRAVITY_MIN_AGREEMENT = 0.5
# Android's TYPE_GRAVITY vector points towards the sky in device axes (a phone lying on a table
# reads +9.81 on z). ASSUMPTION, not verified on a device.
GRAVITY_POINTS_UP = True
SENSOR_ORIENTATIONS = (0, 90, 180, 270)
# Gravity vs fitted-plane check: a floor or ceiling plane fitted without gravity whose normal is
# more than this far from the gravity-derived "up" raises a warning. 10 degrees is a heuristic
# (gravity sensors are low-passed and SfM planes carry noise); it is not a measured tolerance.
GRAVITY_TILT_MAX_DEG = 10.0

# All geometric tolerances are relative to L, the extent of the camera path in plan, because the
# SfM scale is unknown until the reference is applied.
PLANE_TOLERANCE_REL = 0.02
MIN_PLANE_POINTS = 10
MIN_WALL_POINTS = 10
MIN_WALL_SPAN_REL = 0.15
MAX_WALL_LINES = 12
RANSAC_ITERATIONS = 200
RANSAC_SAMPLE = 3000
FLOOR_SEARCH_FRACTION = 0.4  # floor: strongest cluster in the lowest 40 % of the height range
CEILING_SEARCH_FRACTION = 0.6  # ceiling: strongest cluster in the highest 40 %
MIN_CEILING_SEPARATION_TOL = 10  # in tolerances: a "ceiling" must be clearly above the floor
WALL_BAND_MARGIN_TOL = 4  # wall points keep this many tolerances away from floor and ceiling
PIECE_GAP_M = 1.0  # plan gap left between disconnected pieces in the scene
OBSERVED_EDGE_ANGLE = math.sin(math.radians(15))
OBSERVED_EDGE_DISTANCE_M = 0.3
OBSERVED_EDGE_OVERLAP_M = 0.3

Vec3 = tuple[float, float, float]
Mat3 = tuple[Vec3, Vec3, Vec3]  # rows


# --- Data carried between the adapters and the geometry ------------------------------------


@dataclass(frozen=True)
class ExtractedFrame:
    index: int  # frames.jsonl ``i``
    path: Path


@dataclass(frozen=True)
class Intrinsics:
    width: float
    height: float
    fx: float
    fy: float
    cx: float
    cy: float


@dataclass(frozen=True)
class CameraPose:
    """Camera in the SfM world frame; camera axes are x right, y down, z forward."""

    frame_index: int
    rotation: Mat3  # world_from_camera
    center: Vec3


@dataclass(frozen=True)
class SparsePoint:
    xyz: Vec3
    frames: tuple[int, ...]  # frames.jsonl indices that observe the point


@dataclass(frozen=True)
class SparseModel:
    """One connected piece of the sparse reconstruction, in its own arbitrary frame and scale."""

    poses: list[CameraPose]
    points: list[SparsePoint]
    intrinsics: Intrinsics


class FrameExtractor(Protocol):
    def extract(self, video: Path, indices: list[int], out_dir: Path) -> list[ExtractedFrame]: ...


class PoseEstimator(Protocol):
    def estimate(self, frames: list[ExtractedFrame], work_dir: Path) -> list[SparseModel]: ...


@dataclass(frozen=True)
class FrameStamp:
    i: int
    t: int


@dataclass(frozen=True)
class SensorSample:
    t: int
    type: str
    x: float
    y: float
    z: float


@dataclass(frozen=True)
class VideoPackage:
    directory: Path
    manifest: dict[str, Any]
    frames: list[FrameStamp]
    sensors: list[SensorSample]


# --- Validation (S9) -----------------------------------------------------------------------


def _is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _validate_point(point: Any, where: str) -> None:
    reconstruct._require(
        isinstance(point, dict)
        and all(reconstruct._is_number(point.get(k)) and 0 <= point[k] <= 1 for k in ("x", "y")),
        f"{where} must have x and y between 0 and 1",
    )


def validate_manifest(manifest: Any) -> dict[str, Any]:
    """Check a schema 2 manifest; raise :class:`InvalidPackage` otherwise."""
    require = reconstruct._require
    require(isinstance(manifest, dict), "manifest.json must be an object")
    require(manifest.get("schemaVersion") == 2 and _is_int(manifest["schemaVersion"]),
            "schemaVersion must be 2")
    require(_text(manifest.get("captureId")), "captureId is required")
    require(_text(manifest.get("listingId")), "listingId is required")
    device = manifest.get("device")
    require(
        isinstance(device, dict) and all(_text(device.get(k)) for k in ("model", "os", "osVersion")),
        "device needs model, os and osVersion",
    )

    video = manifest.get("video")
    require(isinstance(video, dict), "video is required")
    require(video.get("file") == VIDEO_FILE, f"video.file must be {VIDEO_FILE}")
    require(video.get("framesFile") == FRAMES_FILE, f"video.framesFile must be {FRAMES_FILE}")
    require(
        _is_int(video.get("width")) and _is_int(video.get("height"))
        and video["width"] > 0 and video["height"] > 0,
        "video.width and video.height must be positive integers",
    )
    require(reconstruct._is_number(video.get("fps")) and video["fps"] > 0, "video.fps must be positive")
    require(_is_int(video.get("startedAtNs")) and video["startedAtNs"] >= 0,
            "video.startedAtNs must be a non-negative integer")
    require(_is_int(video.get("sensorOrientation")) and video["sensorOrientation"] in SENSOR_ORIENTATIONS,
            "video.sensorOrientation must be 0, 90, 180 or 270")
    require(video.get("timestampSource") in ("realtime", "unknown"),
            "video.timestampSource must be realtime or unknown")

    sensors = manifest.get("sensors")
    require(isinstance(sensors, dict) and sensors.get("file") == SENSORS_FILE,
            f"sensors.file must be {SENSORS_FILE}")
    require(reconstruct._is_number(sensors.get("rateHz")) and sensors["rateHz"] > 0,
            "sensors.rateHz must be positive")

    rooms = manifest.get("rooms")
    require(isinstance(rooms, list) and len(rooms) > 0, "at least one room is required")
    ids: set[str] = set()
    for room in rooms:
        require(
            isinstance(room, dict) and _text(room.get("id")) and isinstance(room.get("name"), str)
            and _is_int(room.get("fromNs")) and _is_int(room.get("toNs")),
            "every room needs id, name, fromNs and toNs",
        )
        require(room["id"] not in ids, f"duplicate room id {room['id']}")
        ids.add(room["id"])
        require(room["fromNs"] < room["toNs"], f"room {room['id']}: fromNs must be before toNs")
    ordered = sorted(rooms, key=lambda r: r["fromNs"])
    for before, after in itertools.pairwise(ordered):
        require(before["toNs"] <= after["fromNs"], "room intervals must not overlap")

    reference = manifest.get("reference")
    if reference is not None:
        require(isinstance(reference, dict), "reference must be an object or absent")
        require(reference.get("kind") == "object", "reference.kind must be object")
        require(_text(reference.get("label")), "reference.label is required")
        require(
            reconstruct._is_number(reference.get("lengthM")) and reference["lengthM"] > 0,
            "reference.lengthM must be positive",
        )
        require(reference.get("surface") in ("floor", "wall"), "reference.surface must be floor or wall")
        require(_is_int(reference.get("frameNs")), "reference.frameNs must be an integer")
        _validate_point(reference.get("p1"), "reference.p1")
        _validate_point(reference.get("p2"), "reference.p2")
        require(
            (reference["p1"]["x"], reference["p1"]["y"]) != (reference["p2"]["x"], reference["p2"]["y"]),
            "reference points must be different",
        )
        require(
            _room_index_at(ordered, reference["frameNs"]) is not None,
            "reference.frameNs must fall inside a room interval",
        )
    return manifest


def _room_index_at(ordered_rooms: list[dict[str, Any]], t: int) -> int | None:
    """Room whose half-open interval ``[fromNs, toNs)`` holds ``t`` (the app writes the last
    ``toNs`` as the last frame timestamp + 1, so a frame at ``toNs`` belongs to the next room)."""
    for index, room in enumerate(ordered_rooms):
        if room["fromNs"] <= t < room["toNs"]:
            return index
    return None


def _jsonl(path: Path, limit: int) -> list[Any]:
    require = reconstruct._require
    try:
        lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    except (OSError, ValueError) as error:
        raise InvalidPackage(f"{path.name} cannot be read") from error
    require(len(lines) <= limit, f"{path.name} has too many lines")
    try:
        return [json.loads(line) for line in lines]
    except (ValueError, RecursionError) as error:
        raise InvalidPackage(f"{path.name} has a line that is not valid JSON") from error


def _read_frames(path: Path) -> list[FrameStamp]:
    require = reconstruct._require
    rows = _jsonl(path, MAX_FRAME_LINES)
    require(len(rows) > 0, f"{path.name} has no frames")
    frames: list[FrameStamp] = []
    for position, row in enumerate(rows):
        require(
            isinstance(row, dict) and _is_int(row.get("i")) and _is_int(row.get("t")),
            f"{path.name} line {position + 1}: needs integer i and t",
        )
        require(row["i"] == position, f"{path.name} line {position + 1}: i must be {position}")
        require(
            not frames or row["t"] > frames[-1].t,
            f"{path.name} line {position + 1}: t must increase",
        )
        frames.append(FrameStamp(row["i"], row["t"]))
    return frames


def _read_sensors(path: Path) -> list[SensorSample]:
    require = reconstruct._require
    samples: list[SensorSample] = []
    for position, row in enumerate(_jsonl(path, MAX_SENSOR_LINES)):
        require(
            isinstance(row, dict) and _is_int(row.get("t")) and row.get("type") in SENSOR_TYPES
            and all(reconstruct._is_number(row.get(k)) for k in ("x", "y", "z")),
            f"{path.name} line {position + 1}: needs t, a known type and numeric x, y, z",
        )
        require(
            not samples or row["t"] >= samples[-1].t,
            f"{path.name} line {position + 1}: samples must be ordered by t",
        )
        samples.append(SensorSample(row["t"], row["type"], float(row["x"]), float(row["y"]), float(row["z"])))
    return samples


def load_package(package_dir: Path) -> VideoPackage:
    """Read and validate an unzipped schema 2 package."""
    package_dir = Path(package_dir)
    path = package_dir / "manifest.json"
    reconstruct._require(path.is_file(), "manifest.json is missing")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, RecursionError) as error:
        raise InvalidPackage("manifest.json is not valid JSON") from error
    manifest = validate_manifest(document)  # keeps its own InvalidPackage messages
    total = 0
    for name in (VIDEO_FILE, FRAMES_FILE, SENSORS_FILE):
        reconstruct._require((package_dir / name).is_file(), f"{name} is missing from the package")
        total += (package_dir / name).stat().st_size
    reconstruct._require(total <= MAX_PACKAGE_BYTES, "package is too large")
    frames = _read_frames(package_dir / FRAMES_FILE)
    reference = manifest.get("reference")
    if reference is not None:
        reconstruct._require(
            any(f.t == reference["frameNs"] for f in frames),
            "reference.frameNs must be a timestamp listed in frames.jsonl",
        )
    return VideoPackage(package_dir, manifest, frames, _read_sensors(package_dir / SENSORS_FILE))


# --- 3D helpers ----------------------------------------------------------------------------


def _mv(m: Mat3, v: Vec3) -> Vec3:
    return (
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    )


def _mm(a: Mat3, b: Mat3) -> Mat3:
    cols = [tuple(b[r][c] for r in range(3)) for c in range(3)]
    rows = [tuple(sum(a[r][k] * col[k] for k in range(3)) for col in cols) for r in range(3)]
    return (rows[0], rows[1], rows[2])  # type: ignore[return-value]


def _transpose(m: Mat3) -> Mat3:
    return tuple(tuple(m[c][r] for c in range(3)) for r in range(3))  # type: ignore[return-value]


def _cross3(a: Vec3, b: Vec3) -> Vec3:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _norm3(v: Vec3) -> float:
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def _unit3(v: Vec3) -> Vec3:
    n = _norm3(v)
    return (v[0] / n, v[1] / n, v[2] / n)


def device_to_camera_matrix(sensor_orientation: int) -> Mat3:
    """Camera axes (x right, y down, z forward, COLMAP) from raw Android device axes.

    Device axes: x right, y up, z towards the viewer (portrait). Back camera, frames stored
    unrotated: the stored frame is the upright view rotated by ``sensor_orientation``
    (Camera2 SENSOR_ORIENTATION). Upright camera axes are ``(x, -y, -z)`` of the device; the
    in-plane rotation then maps ``(x, y)`` to ``(x, y)``, ``(y, -x)``, ``(-x, -y)`` or ``(-y, x)``
    for 0, 90, 180 and 270 degrees. Rows: camera = D * device.
    """
    rows = {
        0: ((1.0, 0.0, 0.0), (0.0, -1.0, 0.0), (0.0, 0.0, -1.0)),
        90: ((0.0, -1.0, 0.0), (-1.0, 0.0, 0.0), (0.0, 0.0, -1.0)),
        180: ((-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0)),
        270: ((0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, -1.0)),
    }
    if sensor_orientation not in rows:
        raise InvalidPackage("video.sensorOrientation must be 0, 90, 180 or 270")
    return rows[sensor_orientation]


# Kept for callers that want the common portrait-phone case (SENSOR_ORIENTATION 90).
DEVICE_TO_CAMERA = device_to_camera_matrix(90)


def _rotation_to_y(u: Vec3) -> Mat3:
    """Rotation that takes the unit vector ``u`` to +y (Rodrigues)."""
    c = u[1]
    if c < -1 + 1e-9:
        return ((1.0, 0.0, 0.0), (0.0, -1.0, 0.0), (0.0, 0.0, -1.0))
    v = _cross3(u, (0.0, 1.0, 0.0))
    k = 1.0 / (1.0 + c)
    vx = ((0.0, -v[2], v[1]), (v[2], 0.0, -v[0]), (-v[1], v[0], 0.0))
    vx2 = _mm(vx, vx)
    return tuple(  # type: ignore[return-value]
        tuple((1.0 if r == q else 0.0) + vx[r][q] + k * vx2[r][q] for q in range(3)) for r in range(3)
    )


# --- Gravity -------------------------------------------------------------------------------


def estimate_up(
    poses: list[CameraPose],
    frame_times: dict[int, int],
    sensors: list[SensorSample],
    device_to_camera: Mat3,
) -> tuple[Vec3, str]:
    """Direction of "up" in the SfM frame of ``poses`` and where it came from.

    ``"gravity"``: each frame takes the nearest ``gravity`` sample (within
    :data:`GRAVITY_MAX_SKEW_NS`), the device vector is moved to camera axes, then to the SfM
    frame with the pose, and the unit vectors are averaged. ``"cameras"`` is the fallback when
    there is no usable gravity: the mean of the cameras' own "up" (-y), which only holds if the
    phone was kept upright and therefore does not tell floor from ceiling reliably.
    """
    gravity = [s for s in sensors if s.type == "gravity"]
    times = [s.t for s in gravity]
    total = [0.0, 0.0, 0.0]
    used = 0
    for pose in poses:
        t = frame_times.get(pose.frame_index)
        if t is None or not gravity:
            continue
        at = bisect.bisect_left(times, t)
        near = min(
            (gravity[j] for j in (at - 1, at) if 0 <= j < len(gravity)), key=lambda s: abs(s.t - t)
        )
        if abs(near.t - t) > GRAVITY_MAX_SKEW_NS:
            continue
        vector = (near.x, near.y, near.z)
        if _norm3(vector) < 1e-6:
            continue
        up_camera = _mv(device_to_camera, _unit3(vector))
        if not GRAVITY_POINTS_UP:
            up_camera = (-up_camera[0], -up_camera[1], -up_camera[2])
        up_world = _mv(pose.rotation, up_camera)
        total = [a + b for a, b in zip(total, up_world, strict=True)]
        used += 1
    if used and _norm3((total[0], total[1], total[2])) / used >= GRAVITY_MIN_AGREEMENT:
        return _unit3((total[0], total[1], total[2])), "gravity"
    total = [0.0, 0.0, 0.0]
    for pose in poses:
        up_world = _mv(pose.rotation, (0.0, -1.0, 0.0))
        total = [a + b for a, b in zip(total, up_world, strict=True)]
    return _unit3((total[0], total[1], total[2])), "cameras"


# --- Planes --------------------------------------------------------------------------------


@dataclass
class _WallLine:
    """A vertical wall plane seen from above: a 2D line plus its extent."""

    point: tuple[float, float]  # x, z
    direction: tuple[float, float]
    normal: tuple[float, float]
    t_min: float
    t_max: float
    y_min: float
    y_max: float
    points: list[Vec3]


@dataclass
class _RoomFit:
    room_id: str
    name: str
    floor_y: float | None
    ceiling_y: float | None
    floor_xz: list[tuple[float, float]]
    walls: list[_WallLine]
    cameras_xz: list[tuple[float, float]]
    point_count: int


def _percentile(sorted_values: list[float], fraction: float) -> float:
    return sorted_values[min(len(sorted_values) - 1, max(0, int(fraction * (len(sorted_values) - 1))))]


def horizontal_planes(ys: list[float], tol: float) -> tuple[float | None, float | None]:
    """Floor and ceiling heights from dense horizontal clusters of point heights.

    A cluster is a local maximum of the point count in a 3-bin window of width ``tol``; the floor
    is the strongest cluster in the lowest part of the height range and the ceiling the strongest
    in the highest part, at least :data:`MIN_CEILING_SEPARATION_TOL` tolerances above the floor.
    """
    if len(ys) < MIN_PLANE_POINTS or tol <= 0:
        return None, None
    ordered = sorted(ys)
    low, high = _percentile(ordered, 0.02), _percentile(ordered, 0.98)
    bins = Counter(math.floor(y / tol) for y in ordered)

    def score(b: int) -> int:
        return bins[b - 1] + bins[b] + bins[b + 1]

    clusters: list[tuple[float, int]] = []
    for b in sorted(bins):
        s = score(b)
        if s >= MIN_PLANE_POINTS and s >= score(b - 1) and s >= score(b + 1):
            members = [y for y in ordered if b - 1 <= math.floor(y / tol) <= b + 1]
            clusters.append((sum(members) / len(members), s))
    span = high - low
    lower = [c for c in clusters if c[0] <= low + FLOOR_SEARCH_FRACTION * span]
    floor = max(lower, key=lambda c: c[1])[0] if lower else None
    upper = [
        c
        for c in clusters
        if c[0] >= low + CEILING_SEARCH_FRACTION * span
        and (floor is None or c[0] >= floor + MIN_CEILING_SEPARATION_TOL * tol)
    ]
    ceiling = max(upper, key=lambda c: c[1])[0] if upper else None
    return floor, ceiling


def plane_tilt_deg(points: list[Vec3], tol: float) -> float | None:
    """Angle between +y and the normal of the dominant plane of ``points`` (RANSAC, free normal).

    Independent of gravity: it is what the geometry says about "up". None when no plane has
    :data:`MIN_PLANE_POINTS` inliers.
    """
    if len(points) < MIN_PLANE_POINTS:
        return None
    rng = random.Random(1)
    sample = points if len(points) <= 2000 else rng.sample(points, 2000)
    best: tuple[int, Vec3, Vec3] | None = None
    for _ in range(RANSAC_ITERATIONS):
        a, b, c = rng.sample(sample, 3)
        n = _cross3((b[0] - a[0], b[1] - a[1], b[2] - a[2]), (c[0] - a[0], c[1] - a[1], c[2] - a[2]))
        length = _norm3(n)
        if length < 1e-12:
            continue
        n = (n[0] / length, n[1] / length, n[2] / length)
        count = sum(
            1 for p in sample if abs((p[0] - a[0]) * n[0] + (p[1] - a[1]) * n[1] + (p[2] - a[2]) * n[2]) <= tol
        )
        if best is None or count > best[0]:
            best = (count, a, n)
    if best is None or best[0] < MIN_PLANE_POINTS:
        return None
    return math.degrees(math.acos(min(1.0, abs(best[2][1]))))


def _fit_line(points: list[Vec3]) -> tuple[tuple[float, float], tuple[float, float]]:
    mx = sum(p[0] for p in points) / len(points)
    mz = sum(p[2] for p in points) / len(points)
    sxx = szz = sxz = 0.0
    for p in points:
        dx, dz = p[0] - mx, p[2] - mz
        sxx += dx * dx
        szz += dz * dz
        sxz += dx * dz
    angle = 0.5 * math.atan2(2 * sxz, sxx - szz)
    return (mx, mz), (math.cos(angle), math.sin(angle))


def wall_lines(points: list[Vec3], tol: float, min_span: float) -> list[_WallLine]:
    """Vertical wall planes as plan-view lines, by repeated RANSAC (deterministic seed)."""
    rng = random.Random(0)
    remaining = list(points)
    lines: list[_WallLine] = []
    while len(remaining) >= MIN_WALL_POINTS and len(lines) < MAX_WALL_LINES:
        sample = remaining if len(remaining) <= RANSAC_SAMPLE else rng.sample(remaining, RANSAC_SAMPLE)
        best: tuple[int, Vec3, tuple[float, float]] | None = None
        for _ in range(RANSAC_ITERATIONS):
            a, b = rng.sample(sample, 2)
            dx, dz = b[0] - a[0], b[2] - a[2]
            n = math.hypot(dx, dz)
            if n < 1e-12:
                continue
            nx, nz = -dz / n, dx / n
            count = sum(1 for p in sample if abs((p[0] - a[0]) * nx + (p[2] - a[2]) * nz) <= tol)
            if best is None or count > best[0]:
                best = (count, a, (nx, nz))
        if best is None or best[0] * len(remaining) < MIN_WALL_POINTS * len(sample):
            break
        _, a, (nx, nz) = best
        inliers = [p for p in remaining if abs((p[0] - a[0]) * nx + (p[2] - a[2]) * nz) <= tol]
        (px, pz), (ux, uz) = _fit_line(inliers)
        normal = (-uz, ux)
        inliers = [p for p in remaining if abs((p[0] - px) * normal[0] + (p[2] - pz) * normal[1]) <= tol]
        if len(inliers) < MIN_WALL_POINTS:
            break
        ts = [(p[0] - px) * ux + (p[2] - pz) * uz for p in inliers]
        if max(ts) - min(ts) < min_span:
            break
        lines.append(
            _WallLine(
                (px, pz), (ux, uz), normal, min(ts), max(ts),
                min(p[1] for p in inliers), max(p[1] for p in inliers), inliers,
            )
        )
        taken = {id(p) for p in inliers}
        remaining = [p for p in remaining if id(p) not in taken]
    return lines


# --- Metric scale from the reference -------------------------------------------------------


def _pixel_ray(
    point: dict[str, float], pose: CameraPose, intrinsics: Intrinsics
) -> tuple[Vec3, Vec3]:
    u, v = point["x"] * intrinsics.width, point["y"] * intrinsics.height
    direction = _mv(
        pose.rotation, ((u - intrinsics.cx) / intrinsics.fx, (v - intrinsics.cy) / intrinsics.fy, 1.0)
    )
    return pose.center, _unit3(direction)


def _hit_floor(origin: Vec3, direction: Vec3, floor_y: float) -> Vec3 | None:
    if direction[1] >= -1e-9:
        return None
    t = (floor_y - origin[1]) / direction[1]
    return None if t <= 0 else (origin[0] + t * direction[0], floor_y, origin[2] + t * direction[2])


def _hit_wall(origin: Vec3, direction: Vec3, wall: _WallLine) -> tuple[Vec3, float] | None:
    denominator = direction[0] * wall.normal[0] + direction[2] * wall.normal[1]
    if abs(denominator) < 1e-9:
        return None
    t = ((wall.point[0] - origin[0]) * wall.normal[0] + (wall.point[1] - origin[2]) * wall.normal[1]) / denominator
    if t <= 0:
        return None
    hit = (origin[0] + t * direction[0], origin[1] + t * direction[1], origin[2] + t * direction[2])
    along = (hit[0] - wall.point[0]) * wall.direction[0] + (hit[2] - wall.point[1]) * wall.direction[1]
    overflow = max(0.0, wall.t_min - along, along - wall.t_max)
    overflow += max(0.0, wall.y_min - hit[1], hit[1] - wall.y_max)
    return hit, overflow


def reference_scale(
    reference: dict[str, Any], pose: CameraPose, intrinsics: Intrinsics, fit: _RoomFit
) -> float | None:
    """Factor that turns SfM units into metres, or None when the rays do not reach the plane."""
    rays = [_pixel_ray(reference[k], pose, intrinsics) for k in ("p1", "p2")]
    if reference["surface"] == "floor":
        if fit.floor_y is None:
            return None
        hits = [_hit_floor(o, d, fit.floor_y) for o, d in rays]
    else:
        best: tuple[float, list[Vec3]] | None = None
        for wall in fit.walls:
            found = [_hit_wall(o, d, wall) for o, d in rays]
            if any(f is None for f in found):
                continue
            score = sum(f[1] for f in found if f is not None)
            if best is None or score < best[0]:
                best = (score, [f[0] for f in found if f is not None])
        hits = best[1] if best else [None, None]  # type: ignore[list-item]
    if hits[0] is None or hits[1] is None:
        return None
    distance = math.dist(hits[0], hits[1])
    return None if distance < 1e-9 else float(reference["lengthM"]) / distance


# --- Adapters (external tools, imported lazily) --------------------------------------------


class FfmpegFrameExtractor:
    """Frames by index with the ``ffmpeg`` CLI. NOT exercised against a real ffmpeg here."""

    TIMEOUT_S = 900

    def __init__(
        self,
        which: Callable[[str], str | None] = shutil.which,
        runner: Callable[..., Any] = subprocess.run,
    ) -> None:
        self._which = which
        self._runner = runner

    def extract(self, video: Path, indices: list[int], out_dir: Path) -> list[ExtractedFrame]:
        executable = self._which("ffmpeg")
        if executable is None:
            raise ExternalToolMissing(
                "ffmpeg is not installed or not on PATH; it is required to extract frames from video.mp4"
            )
        out_dir.mkdir(parents=True, exist_ok=True)
        ordered = sorted(set(indices))
        script = out_dir.parent / f"{out_dir.name}-select.txt"
        script.write_text("select=" + "+".join(f"eq(n\\,{i})" for i in ordered), encoding="utf-8")
        command = [
            executable, "-hide_banner", "-loglevel", "error",
            "-noautorotate", "-i", str(video), "-an",
            "-filter_script:v", str(script), "-vsync", "0", "-qscale:v", "2",
            str(out_dir / "%06d.jpg"),
        ]
        done = self._runner(command, capture_output=True, check=False, timeout=self.TIMEOUT_S)
        if done.returncode != 0:
            tail = bytes(done.stderr or b"")[-200:].decode("utf-8", "replace")
            raise RuntimeError(f"ffmpeg failed (exit {done.returncode}): {tail}")
        produced = sorted(out_dir.glob("*.jpg"))
        if not produced:
            raise RuntimeError("ffmpeg produced no frames")
        return [ExtractedFrame(i, p) for i, p in zip(ordered, produced, strict=False)]


class PycolmapPoseEstimator:
    """Sparse SfM with ``pycolmap``. NOT exercised against a real pycolmap here: the API calls
    below follow the pycolmap 3.x documentation and need a first real run."""

    def __init__(self, importer: Callable[[str], Any] = importlib.import_module) -> None:
        self._importer = importer

    def estimate(self, frames: list[ExtractedFrame], work_dir: Path) -> list[SparseModel]:
        try:
            pycolmap = self._importer("pycolmap")
        except ImportError as error:
            raise ExternalToolMissing(
                "pycolmap is not installed; it is required to estimate camera poses from the video"
            ) from error
        work_dir.mkdir(parents=True, exist_ok=True)
        images_dir = frames[0].path.parent
        index_by_name = {f.path.name: f.index for f in frames}
        database = work_dir / "database.db"
        pycolmap.extract_features(database, images_dir)
        pycolmap.match_exhaustive(database)
        sparse = work_dir / "sparse"
        sparse.mkdir(exist_ok=True)
        models: list[SparseModel] = []
        for rec in pycolmap.incremental_mapping(database, images_dir, sparse).values():
            frame_of_image: dict[int, int] = {}
            poses: list[CameraPose] = []
            intrinsics: Intrinsics | None = None
            for image_id, image in rec.images.items():
                index = index_by_name.get(image.name)
                if index is None:
                    continue
                frame_of_image[image_id] = index
                pose = image.cam_from_world
                pose = pose() if callable(pose) else pose
                matrix = pose.rotation.matrix()
                r_cw = tuple(tuple(float(matrix[r][c]) for c in range(3)) for r in range(3))
                r_wc = _transpose(r_cw)  # type: ignore[arg-type]
                t = tuple(float(v) for v in pose.translation)
                rt = _mv(r_wc, t)  # type: ignore[arg-type]
                poses.append(CameraPose(index, r_wc, (-rt[0], -rt[1], -rt[2])))
                if intrinsics is None:
                    camera = rec.cameras[image.camera_id]
                    k = camera.calibration_matrix()
                    intrinsics = Intrinsics(
                        float(camera.width), float(camera.height),
                        float(k[0][0]), float(k[1][1]), float(k[0][2]), float(k[1][2]),
                    )
            if intrinsics is None or not poses:
                continue
            points = [
                SparsePoint(
                    tuple(float(v) for v in p.xyz),  # type: ignore[arg-type]
                    tuple(sorted({frame_of_image[e.image_id] for e in p.track.elements
                                  if e.image_id in frame_of_image})),
                )
                for p in rec.points3D.values()
            ]
            models.append(SparseModel(poses, points, intrinsics))
        return models


def default_adapters() -> tuple[FrameExtractor, PoseEstimator]:
    return FfmpegFrameExtractor(), PycolmapPoseEstimator()


# --- Orchestration -------------------------------------------------------------------------


@dataclass
class _Piece:
    poses: list[CameraPose]
    points: list[tuple[Vec3, tuple[int, ...]]]
    intrinsics: Intrinsics
    up_source: str
    rooms: dict[str, _RoomFit] = field(default_factory=dict)
    factor: float | None = None
    tilts: dict[str, float] = field(default_factory=dict)  # room id -> worst floor/ceiling tilt


def _align(model: SparseModel, up: Vec3, up_source: str, frame_times: dict[int, int]) -> _Piece:
    rotation = _rotation_to_y(up)
    poses = [
        CameraPose(p.frame_index, _mm(rotation, p.rotation), _mv(rotation, p.center))
        for p in model.poses
        if p.frame_index in frame_times
    ]
    points = [(_mv(rotation, p.xyz), p.frames) for p in model.points]
    return _Piece(poses, points, model.intrinsics, up_source)


def _plan_extent(piece: _Piece) -> float:
    centres = [p.center for p in piece.poses] or [q[0] for q in piece.points]
    extent = max(
        max(c[0] for c in centres) - min(c[0] for c in centres),
        max(c[2] for c in centres) - min(c[2] for c in centres),
    )
    return extent


def _fit_rooms(piece: _Piece, rooms: list[dict[str, Any]], room_of_frame: dict[int, str]) -> None:
    extent = _plan_extent(piece)
    if extent < 1e-9:
        return
    tol = PLANE_TOLERANCE_REL * extent
    order = {r["id"]: n for n, r in enumerate(rooms)}
    by_room: dict[str, list[Vec3]] = {}
    for xyz, frames in piece.points:
        votes = Counter(room_of_frame[f] for f in frames if f in room_of_frame)
        if votes:
            room_id = max(votes, key=lambda r: (votes[r], -order[r]))
            by_room.setdefault(room_id, []).append(xyz)
    for room in rooms:
        points = by_room.get(room["id"])
        if not points:
            continue
        floor_y, ceiling_y = horizontal_planes([p[1] for p in points], tol)
        low = (
            floor_y + WALL_BAND_MARGIN_TOL * tol
            if floor_y is not None
            else _percentile(sorted(p[1] for p in points), 0.02) + WALL_BAND_MARGIN_TOL * tol
        )
        high = ceiling_y - WALL_BAND_MARGIN_TOL * tol if ceiling_y is not None else math.inf
        if piece.up_source == "gravity":
            span = max(p[1] for p in points) - min(p[1] for p in points)
            ordered = sorted(p[1] for p in points)
            lo_cut = _percentile(ordered, 0.02) + 0.4 * span
            hi_cut = _percentile(ordered, 0.98) - 0.4 * span
            tilts = [
                t
                for region in ([p for p in points if p[1] <= lo_cut], [p for p in points if p[1] >= hi_cut])
                if (t := plane_tilt_deg(region, tol)) is not None
            ]
            if tilts:
                piece.tilts[room["id"]] = max(tilts)
        band = [p for p in points if low <= p[1] <= high]
        cameras = [
            (p.center[0], p.center[2]) for p in piece.poses if room_of_frame.get(p.frame_index) == room["id"]
        ]
        piece.rooms[room["id"]] = _RoomFit(
            room["id"],
            room["name"],
            floor_y,
            ceiling_y,
            [(p[0], p[2]) for p in points if floor_y is not None and abs(p[1] - floor_y) <= 2 * tol],
            wall_lines(band, tol, MIN_WALL_SPAN_REL * extent),
            cameras,
            len(points),
        )


def _edge_observed(a: reconstruct.Point, b: reconstruct.Point, segments: list[reconstruct.WallSegment]) -> bool:
    length = reconstruct._dist(a, b)
    direction = reconstruct._unit(reconstruct._sub(b, a))
    for segment in segments:
        sd = reconstruct._unit(reconstruct._sub(segment.end, segment.start))
        if abs(reconstruct._cross(direction, sd)) > OBSERVED_EDGE_ANGLE:
            continue
        middle = reconstruct._scale(reconstruct._add(segment.start, segment.end), 0.5)
        if abs(reconstruct._cross(reconstruct._sub(middle, a), direction)) > OBSERVED_EDGE_DISTANCE_M:
            continue
        t0 = reconstruct._dot(reconstruct._sub(segment.start, a), direction)
        t1 = reconstruct._dot(reconstruct._sub(segment.end, a), direction)
        overlap = min(length, max(t0, t1)) - max(0.0, min(t0, t1))
        if overlap >= min(OBSERVED_EDGE_OVERLAP_M, 0.5 * length):
            return True
    return False


def _meters(point: reconstruct.Point) -> str:
    return f"({point[0]:.2f} m; {point[1]:.2f} m)"


def reconstruct_video(
    package_dir: Path,
    *,
    extractor: FrameExtractor | None = None,
    estimator: PoseEstimator | None = None,
    device_to_camera: Mat3 | None = None,
) -> ReconstructionResult:
    """Reconstruct an unzipped schema 2 package into a scene v2 draft plus warnings."""
    package = load_package(package_dir)
    manifest = package.manifest
    if device_to_camera is None:
        device_to_camera = device_to_camera_matrix(manifest["video"]["sensorOrientation"])
    if extractor is None or estimator is None:
        default_extractor, default_estimator = default_adapters()
        extractor, estimator = extractor or default_extractor, estimator or default_estimator
    warnings: list[str] = []
    if manifest["video"]["timestampSource"] == "unknown":
        warnings.append(
            "La marca de tiempo de los cuadros no está confirmada como el mismo reloj que los sensores: "
            "la gravedad puede no sincronizarse con el video."
        )

    rooms = sorted(manifest["rooms"], key=lambda r: r["fromNs"])
    frame_times = {f.i: f.t for f in package.frames}
    room_of_frame: dict[int, str] = {}
    for f in package.frames:
        index = _room_index_at(rooms, f.t)
        if index is not None:
            room_of_frame[f.i] = rooms[index]["id"]

    reference = manifest.get("reference")
    reference_index: int | None = None
    if reference is not None:
        reference_index = min(package.frames, key=lambda f: abs(f.t - reference["frameNs"])).i
    stride = max(1, round(float(manifest["video"]["fps"]) / EXTRACT_FPS))
    indices = set(range(0, len(package.frames), stride))
    if reference_index is not None:
        indices.add(reference_index)

    with tempfile.TemporaryDirectory(prefix="roomforge-sfm-") as scratch:
        frames = extractor.extract(package.directory / VIDEO_FILE, sorted(indices), Path(scratch) / "frames")
        models = [m for m in estimator.estimate(frames, Path(scratch) / "sfm") if m.poses and m.points]
    if not models:
        raise InvalidPackage("no camera poses could be estimated from the video")

    pieces: list[_Piece] = []
    for model in models:
        usable = [p for p in model.poses if p.frame_index in frame_times]
        if not usable:
            continue
        up, source = estimate_up(usable, frame_times, package.sensors, device_to_camera)
        piece = _align(model, up, source, frame_times)
        _fit_rooms(piece, rooms, room_of_frame)
        if piece.rooms:
            pieces.append(piece)
    if not pieces:
        raise InvalidPackage("the reconstruction has no points inside any room interval")

    if any(p.up_source == "cameras" for p in pieces):
        warnings.append(
            "Gravedad no disponible: no se distinguió piso de techo. Se supuso que el teléfono se "
            "sostuvo derecho; revise el piso y las alturas."
        )

    for piece in pieces:
        for room_id, tilt in piece.tilts.items():
            if tilt > GRAVITY_TILT_MAX_DEG:
                warnings.append(
                    f"La gravedad medida por el teléfono no coincide con el plano de piso o techo ajustado "
                    f"en «{piece.rooms[room_id].name}» (diferencia de {tilt:.0f}°): revise la orientación "
                    "de la captura; el piso y las alturas pueden no ser fiables."
                )

    scaled = False
    if reference is not None and reference_index is not None:
        room_id = room_of_frame[reference_index]
        for piece in pieces:
            pose = next((p for p in piece.poses if p.frame_index == reference_index), None)
            if pose is None or room_id not in piece.rooms:
                continue
            piece.factor = reference_scale(reference, pose, piece.intrinsics, piece.rooms[room_id])
            scaled = piece.factor is not None
        if not scaled:
            warnings.append(
                f"La medida de referencia «{reference['label']}» no pudo ubicarse sobre "
                f"{'el piso' if reference['surface'] == 'floor' else 'una pared'} ajustado; no se aplicó."
            )
    if not scaled:
        warnings.append(
            "Sin medida de referencia: el modelo no tiene escala métrica. Las medidas están en "
            "unidades arbitrarias y no deben tomarse como metros."
        )
    if len(pieces) > 1:
        warnings.append(
            f"La reconstrucción quedó partida en {len(pieces)} piezas desconectadas: no se conoce la "
            "posición relativa de sus ambientes y se colocaron una junto a otra."
        )
        if scaled:
            for piece in pieces:
                if piece.factor is None:
                    names = ", ".join(f"«{r.name}»" for r in piece.rooms.values())
                    warnings.append(
                        f"La pieza con {names} quedó sin medida de referencia: su escala no es métrica "
                        "ni coincide con la del resto."
                    )

    scene_rooms: list[reconstruct._Room] = []
    seen: set[str] = set()
    cursor = 0.0
    for piece in pieces:
        factor = piece.factor if piece.factor is not None else 1.0
        piece_rooms: list[reconstruct._Room] = []
        for room_id, fit in piece.rooms.items():
            if room_id in seen:
                warnings.append(f"«{fit.name}» aparece en más de una pieza desconectada; se usó la primera.")
                continue
            segments = [
                s
                for line in fit.walls
                if (s := reconstruct.fit_wall_segment([(p[0] * factor, p[1] * factor, p[2] * factor) for p in line.points]))
            ]
            proposal = reconstruct.propose_contour(
                [(s.start, s.end) for s in segments],
                [[(x * factor, z * factor) for x, z in fit.floor_xz]],
                [(x * factor, z * factor) for x, z in fit.cameras_xz],
            )
            if isinstance(proposal, reconstruct.ProposalFailed):
                warnings.append(f"«{fit.name}» no se incluyó en la escena. {proposal.message}")
                continue
            seen.add(room_id)
            corners = proposal.corners
            if reconstruct._signed_area(corners) < 0:
                corners = corners[::-1]
            for i, corner in enumerate(corners):
                following = corners[(i + 1) % len(corners)]
                if not _edge_observed(corner, following, segments):
                    warnings.append(
                        f"Pared sin observar entre {_meters(corner)} y {_meters(following)} en «{fit.name}»: "
                        "su posición es una estimación. Verifíquela en el editor."
                    )
            measured = fit.floor_y is not None and fit.ceiling_y is not None
            height = (fit.ceiling_y - fit.floor_y) * factor if measured else reconstruct.ASSUMED_ROOM_HEIGHT_M  # type: ignore[operator]
            if measured and piece.factor is not None:
                low, high = reconstruct.PLAUSIBLE_CEILING_HEIGHT_M
                if not low <= height <= high:
                    height, measured = reconstruct.ASSUMED_ROOM_HEIGHT_M, False
            piece_rooms.append(
                reconstruct._Room(
                    id=room_id,
                    name=fit.name,
                    corners=corners,
                    height=height,
                    height_source="ceiling_plane" if measured else "assumed",
                    measured=measured,
                )
            )
        if not piece_rooms:
            continue
        min_x = min(c[0] for r in piece_rooms for c in r.corners)
        max_x = max(c[0] for r in piece_rooms for c in r.corners)
        min_z = min(c[1] for r in piece_rooms for c in r.corners)
        for room in piece_rooms:
            room.corners = [(c[0] - min_x + cursor, c[1] - min_z) for c in room.corners]
        cursor += max_x - min_x + PIECE_GAP_M
        scene_rooms.extend(piece_rooms)
    for room in rooms:
        if room["id"] not in seen and not any(room["name"] in w for w in warnings):
            warnings.append(f"«{room['name']}» no se incluyó en la escena: no hay puntos reconstruidos en su intervalo.")
    if not scene_rooms:
        raise InvalidPackage("No se pudo cerrar el contorno de ningún ambiente: " + " ".join(warnings))

    builder = reconstruct._SceneBuilder(scene_rooms, [])
    scene = builder.build()
    warnings.extend(builder.warnings)
    warnings.append(
        "Las medidas son estimadas a partir del video y los sensores; su exactitud no se midió. "
        "Verifíquelas en el editor antes de publicar."
    )
    warnings.append(
        "Las aberturas no se detectan automáticamente: marque las puertas y ventanas en el editor antes de publicar."
    )
    return ReconstructionResult(scene_draft=scene, warnings=[w[:500] for w in warnings], volume_views=[])
