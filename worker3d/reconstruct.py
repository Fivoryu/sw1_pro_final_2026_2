"""Capture package -> scene v2 draft (F07.7). Standard library only.

``reconstruct`` is a pure function over an unzipped capture package
(``docs/api/f07-capture-package.md``). It ports, to Python, the room-contour
proposal (``contour_proposal.dart``), the wall fit (``Walkthrough.kt``) and the
scene assembly (``scene_builder.dart``) of the capture app, so the phone only
has to record the walkthrough.

Algorithm v1:

1. Validate the manifest; an unusable package raises :class:`InvalidPackage`.
2. Move every plane polygon to the world frame with its pose, fit a floor
   segment to each wall plane and attribute it to the room of the nearest
   trajectory sample.
3. Propose one contour per room; a room that cannot close one is skipped with
   a warning.
4. Room height: ceiling plane minus floor when a ceiling plane overlaps the
   room (measured), otherwise an assumed value flagged as such.
5. Occupancy volumes from back-projected depth keyframes (unlabelled boxes).
6. Assemble the scene v2 document (walls on the centre line, welded shared
   walls). Openings are not detected in v1.
7. Rescale by the optional reference measure.

Every threshold below is a heuristic chosen for v1, not a measured tolerance.
"""

from __future__ import annotations

import json
import math
import shutil
import sys
import tempfile
import zipfile
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import png16

# --- Heuristic thresholds (not measured tolerances) ----------------------------------------

# Contour proposal (same values as contour_proposal.dart).
MIN_WALL_LENGTH_M = 0.3
SNAP_TOLERANCE_RAD = math.radians(12)
SAME_DIRECTION_RAD = math.radians(3)
SAME_LINE_OFFSET_M = 0.15
MIN_CORNER_ANGLE_RAD = math.radians(15)
MAX_CORNER_DISTANCE_M = 20.0
# Contour validation (same values as validation.dart).
MIN_EDGE_LENGTH_M = 0.3
MIN_ROOM_AREA_M2 = 1.0
# Scene assembly (same values as scene_builder.dart).
WALL_THICKNESS_M = 0.15
WELD_TOLERANCE_M = 0.03
OCCUPANCY_COLOR = "#9e9e9e"
DUPLICATE_WALL_ANGLE_DEG = 3.0
DUPLICATE_WALL_DISTANCE_M = 0.3
DUPLICATE_WALL_OVERLAP_M = 0.2

# Heights. Same default as the capture app's editor (RoomHeight.assumedDefault), so a room
# without a ceiling reading gets the same assumed height wherever it is produced.
ASSUMED_ROOM_HEIGHT_M = 2.4
PLAUSIBLE_CEILING_HEIGHT_M = (1.8, 6.0)

# Occupancy volumes from depth.
DEPTH_PIXEL_STRIDE = 2
DEPTH_MAX_M = 8.0
# Depth confidence is 0-255 (8-bit PNG). Pixels below this are ignored when present.
DEPTH_CONFIDENCE_MIN = 128
VOLUME_MIN_ABOVE_FLOOR_M = 0.05
VOLUME_MAX_ABOVE_FLOOR_M = 2.0
WALL_CLEARANCE_M = 0.15
GRID_CELL_M = 0.05
MIN_CELL_POINTS = 1
# 64 cells = 0.16 m2, about a 40 x 40 cm footprint; smaller components are noise.
MIN_COMPONENT_CELLS = 64
# Support at which a component's confidence reaches 1.0 (points per occupied cell).
FULL_SUPPORT_POINTS_PER_CELL = 4
MAX_UNCOMPRESSED_BYTES = 1024 * 1024 * 1024

Point = tuple[float, float]
_PLANE_TYPES = frozenset({"floor", "wall", "ceiling"})


class InvalidPackage(ValueError):
    """The package cannot be reconstructed no matter how often it is retried."""


@dataclass(frozen=True)
class ReconstructionResult:
    scene_draft: dict[str, Any]
    warnings: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class WallSegment:
    start: Point
    end: Point
    min_y: float
    max_y: float

    @property
    def length(self) -> float:
        return _dist(self.start, self.end)


# --- Small 2D vector helpers ---------------------------------------------------------------


def _sub(a: Point, b: Point) -> Point:
    return (a[0] - b[0], a[1] - b[1])


def _add(a: Point, b: Point) -> Point:
    return (a[0] + b[0], a[1] + b[1])


def _scale(a: Point, k: float) -> Point:
    return (a[0] * k, a[1] * k)


def _dot(a: Point, b: Point) -> float:
    return a[0] * b[0] + a[1] * b[1]


def _cross(a: Point, b: Point) -> float:
    return a[0] * b[1] - a[1] * b[0]


def _len(a: Point) -> float:
    return math.hypot(a[0], a[1])


def _dist(a: Point, b: Point) -> float:
    return _len(_sub(a, b))


def _unit(a: Point) -> Point:
    length = _len(a)
    return (0.0, 0.0) if length == 0 else (a[0] / length, a[1] / length)


def _round(value: float, decimals: int) -> float:
    rounded = round(value, decimals)
    return 0.0 if rounded == 0 else rounded


def _sign(value: float) -> float:
    return (value > 0) - (value < 0)


def _signed_area(polygon: list[Point]) -> float:
    return sum(_cross(p, polygon[(i + 1) % len(polygon)]) for i, p in enumerate(polygon)) / 2


def _distance_to_segment(point: Point, a: Point, b: Point) -> float:
    ab = _sub(b, a)
    length_squared = _dot(ab, ab)
    if length_squared == 0:
        return _dist(point, a)
    t = max(0.0, min(1.0, _dot(_sub(point, a), ab) / length_squared))
    return _dist(point, _add(a, _scale(ab, t)))


def _segments_intersect(a: Point, b: Point, c: Point, d: Point) -> bool:
    epsilon = 1e-12

    def orientation(p: Point, q: Point, r: Point) -> int:
        value = _cross(_sub(q, p), _sub(r, p))
        if abs(value) < epsilon:
            return 0
        return 1 if value > 0 else -1

    def on_segment(p: Point, q: Point, r: Point) -> bool:
        return (
            min(p[0], r[0]) - epsilon <= q[0] <= max(p[0], r[0]) + epsilon
            and min(p[1], r[1]) - epsilon <= q[1] <= max(p[1], r[1]) + epsilon
        )

    o1, o2, o3, o4 = orientation(a, b, c), orientation(a, b, d), orientation(c, d, a), orientation(c, d, b)
    if o1 != o2 and o3 != o4:
        return True
    return (
        (o1 == 0 and on_segment(a, c, b))
        or (o2 == 0 and on_segment(a, d, b))
        or (o3 == 0 and on_segment(c, a, d))
        or (o4 == 0 and on_segment(c, b, d))
    )


def _segments_cross_properly(a: Point, b: Point, c: Point, d: Point) -> bool:
    epsilon = 1e-9
    d1 = _cross(_sub(b, a), _sub(c, a))
    d2 = _cross(_sub(b, a), _sub(d, a))
    d3 = _cross(_sub(d, c), _sub(a, c))
    d4 = _cross(_sub(d, c), _sub(b, c))
    return ((d1 > epsilon and d2 < -epsilon) or (d1 < -epsilon and d2 > epsilon)) and (
        (d3 > epsilon and d4 < -epsilon) or (d3 < -epsilon and d4 > epsilon)
    )


def _point_in_polygon(point: Point, polygon: list[Point]) -> bool:
    inside = False
    j = len(polygon) - 1
    for i, pi in enumerate(polygon):
        pj = polygon[j]
        if (pi[1] > point[1]) != (pj[1] > point[1]) and point[0] < (pj[0] - pi[0]) * (
            point[1] - pi[1]
        ) / (pj[1] - pi[1]) + pi[0]:
            inside = not inside
        j = i
    return inside


def _blocking_contour_issue(corners: list[Point]) -> bool:
    """True when the contour has an issue that blocks closing the room (validation.dart)."""
    count = len(corners)
    if count < 3:
        return True
    if any(_dist(corners[i], corners[(i + 1) % count]) < MIN_EDGE_LENGTH_M for i in range(count)):
        return True
    for i in range(count):
        for j in range(i + 2, count):
            if i == 0 and j == count - 1:
                continue
            if _segments_intersect(
                corners[i], corners[(i + 1) % count], corners[j], corners[(j + 1) % count]
            ):
                return True
    return abs(_signed_area(corners)) < MIN_ROOM_AREA_M2


# --- Manifest validation -------------------------------------------------------------------


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise InvalidPackage(message)


def _validate_pose(pose: Any, where: str) -> None:
    _require(
        isinstance(pose, list) and len(pose) == 7 and all(_is_number(v) for v in pose),
        f"{where}: pose must be 7 numbers [tx,ty,tz,qx,qy,qz,qw]",
    )
    _require(math.sqrt(sum(v * v for v in pose[3:])) > 1e-6, f"{where}: pose quaternion is zero")


def _validate_intrinsics(value: Any, where: str) -> None:
    _require(isinstance(value, dict), f"{where}: intrinsics are required")
    for key in ("width", "height", "fx", "fy", "cx", "cy"):
        _require(_is_number(value.get(key)), f"{where}.{key} must be a number")
    _require(
        value["width"] > 0 and value["height"] > 0 and value["fx"] > 0 and value["fy"] > 0,
        f"{where}: size and focal lengths must be positive",
    )


def validate_manifest(manifest: Any) -> dict[str, Any]:
    """Check the manifest against the v1 contract; raise :class:`InvalidPackage` otherwise."""
    _require(isinstance(manifest, dict), "manifest.json must be an object")
    _require(manifest.get("schemaVersion") == 1, "schemaVersion must be 1")
    _require(_is_number(manifest.get("floorY")), "floorY is required: no floor was detected")

    rooms = manifest.get("rooms")
    _require(isinstance(rooms, list) and len(rooms) > 0, "at least one room is required")
    room_ids: set[str] = set()
    for room in rooms:
        _require(
            isinstance(room, dict)
            and isinstance(room.get("id"), str)
            and room["id"]
            and isinstance(room.get("name"), str),
            "every room needs an id and a name",
        )
        _require(room["id"] not in room_ids, f"duplicate room id {room['id']}")
        room_ids.add(room["id"])

    planes = manifest.get("planes")
    _require(isinstance(planes, list), "planes must be a list")
    for plane in planes:
        _require(isinstance(plane, dict), "every plane must be an object")
        where = f"plane {plane.get('id')}"
        _require(plane.get("type") in _PLANE_TYPES, f"{where}: unknown type")
        _validate_pose(plane.get("pose"), where)
        polygon = plane.get("polygon")
        _require(
            isinstance(polygon, list)
            and len(polygon) >= 3
            and all(
                isinstance(p, list) and len(p) == 2 and all(_is_number(v) for v in p)
                for p in polygon
            ),
            f"{where}: polygon must list at least 3 [x, z] points",
        )

    trajectory = manifest.get("trajectory")
    _require(isinstance(trajectory, list) and len(trajectory) > 0, "trajectory is required")
    for sample in trajectory:
        _require(
            isinstance(sample, list)
            and len(sample) == 4
            and all(_is_number(v) for v in sample[:3])
            and sample[3] in room_ids,
            "trajectory samples must be [t_ms, x, z, roomId] with a known room",
        )

    keyframes = manifest.get("keyframes")
    _require(isinstance(keyframes, list), "keyframes must be a list")
    needs_depth = False
    for keyframe in keyframes:
        _require(isinstance(keyframe, dict), "every keyframe must be an object")
        where = f"keyframe {keyframe.get('index')}"
        _require(keyframe.get("roomId") in room_ids, f"{where}: unknown room")
        _require(isinstance(keyframe.get("image"), str), f"{where}: image is required")
        _validate_pose(keyframe.get("pose"), where)
        for key in ("depth", "confidence"):
            _require(
                keyframe.get(key) is None or isinstance(keyframe[key], str),
                f"{where}: {key} must be a path or null",
            )
        needs_depth = needs_depth or keyframe.get("depth") is not None
    if needs_depth:
        _validate_intrinsics(manifest.get("depth"), "depth")

    reference = manifest.get("reference")
    if reference is not None:
        _require(isinstance(reference, dict), "reference must be an object or null")
        for key in ("from", "to"):
            point = reference.get(key)
            _require(
                isinstance(point, list) and len(point) == 3 and all(_is_number(v) for v in point),
                f"reference.{key} must be 3 numbers",
            )
        _require(
            _is_number(reference.get("meters")) and reference["meters"] > 0,
            "reference.meters must be positive",
        )
        _require(
            math.dist(reference["from"], reference["to"]) > 1e-6,
            "reference points must be different",
        )
    return manifest


# --- Plane geometry ------------------------------------------------------------------------


def _rotation(pose: list[float]) -> list[list[float]]:
    qx, qy, qz, qw = pose[3:7]
    norm = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    qx, qy, qz, qw = qx / norm, qy / norm, qz / norm, qw / norm
    return [
        [1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw)],
        [2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw)],
        [2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)],
    ]


def plane_to_world(pose: list[float], polygon: list[list[float]]) -> list[tuple[float, float, float]]:
    """World points of a plane polygon given in local x/z (ARCore plane frame, local y = normal)."""
    r = _rotation(pose)
    tx, ty, tz = pose[0], pose[1], pose[2]
    return [
        (
            r[0][0] * px + r[0][2] * pz + tx,
            r[1][0] * px + r[1][2] * pz + ty,
            r[2][0] * px + r[2][2] * pz + tz,
        )
        for px, pz in polygon
    ]


def fit_wall_segment(points: list[tuple[float, float, float]]) -> WallSegment | None:
    """Floor segment along the principal axis (PCA) of a wall plane (``fitWallSegment`` in Kotlin).

    Returns ``None`` for walls shorter than :data:`MIN_WALL_LENGTH_M`.
    """
    if len(points) < 2:
        return None
    mean_x = sum(p[0] for p in points) / len(points)
    mean_z = sum(p[2] for p in points) / len(points)
    sxx = szz = sxz = 0.0
    for p in points:
        dx, dz = p[0] - mean_x, p[2] - mean_z
        sxx += dx * dx
        szz += dz * dz
        sxz += dx * dz
    angle = 0.5 * math.atan2(2 * sxz, sxx - szz)
    ux, uz = math.cos(angle), math.sin(angle)
    ts = [(p[0] - mean_x) * ux + (p[2] - mean_z) * uz for p in points]
    t_min, t_max = min(ts), max(ts)
    if t_max - t_min < MIN_WALL_LENGTH_M - 1e-9:
        return None
    return WallSegment(
        start=(mean_x + t_min * ux, mean_z + t_min * uz),
        end=(mean_x + t_max * ux, mean_z + t_max * uz),
        min_y=min(p[1] for p in points),
        max_y=max(p[1] for p in points),
    )


# --- Contour proposal (port of contour_proposal.dart) --------------------------------------


@dataclass(frozen=True)
class ProposedContour:
    corners: list[Point]
    observed_walls: int
    inferred_edges: int


@dataclass(frozen=True)
class ProposalFailed:
    message: str


class _Line:
    """One merged wall line: direction angle in [0, pi), signed normal offset, extent."""

    def __init__(self, angle: float, offset: float, t_min: float, t_max: float, weight: float):
        self.angle = angle
        self.offset = offset
        self.t_min = t_min
        self.t_max = t_max
        self.weight = weight

    @property
    def direction(self) -> Point:
        return (math.cos(self.angle), math.sin(self.angle))

    @property
    def normal(self) -> Point:
        return (-math.sin(self.angle), math.cos(self.angle))

    @property
    def length(self) -> float:
        return self.t_max - self.t_min

    def at(self, t: float) -> Point:
        return _add(_scale(self.direction, t), _scale(self.normal, self.offset))

    @property
    def middle(self) -> Point:
        return self.at((self.t_min + self.t_max) / 2)

    def project(self, p: Point) -> Point:
        return self.at(_dot(self.direction, p))


def _normalize_angle(angle: float) -> float:
    return angle % math.pi


def _angle_gap(a: float, b: float) -> float:
    d = abs(a - b) % math.pi
    return min(d, math.pi - d)


def _too_few_walls(count: int) -> ProposalFailed:
    noun = "pared" if count == 1 else "paredes"
    return ProposalFailed(
        f"Se detectaron {count} {noun}; hacen falta al menos 3. Repita el recorrido "
        "apuntando a la base de las paredes que faltan."
    )


def propose_contour(
    walls: list[tuple[Point, Point]], floors: list[list[Point]], trajectory: list[Point]
) -> ProposedContour | ProposalFailed:
    """Room contour from observed wall segments; rooms are assumed to have mostly square corners."""
    walls = [w for w in walls if _dist(w[0], w[1]) >= MIN_WALL_LENGTH_M]
    if len(walls) < 3:
        return _too_few_walls(len(walls))

    # Dominant axis: length-weighted circular mean of 4*theta (period of 90 degrees).
    sum_sin = sum_cos = 0.0
    for start, end in walls:
        d = _sub(end, start)
        theta = math.atan2(d[1], d[0])
        sum_sin += _len(d) * math.sin(4 * theta)
        sum_cos += _len(d) * math.cos(4 * theta)
    axis = math.atan2(sum_sin, sum_cos) / 4

    lines: list[_Line] = []
    quarter = math.pi / 2
    for start, end in walls:
        d = _sub(end, start)
        theta = math.atan2(d[1], d[0])
        diff = (theta - axis) % quarter
        if diff >= quarter / 2:
            diff -= quarter
        if diff < -quarter / 2:
            diff += quarter
        if abs(diff) <= SNAP_TOLERANCE_RAD:
            theta -= diff
        line = _Line(_normalize_angle(theta), 0.0, 0.0, 0.0, _len(d))
        middle = _scale(_add(start, end), 0.5)
        line.offset = _dot(line.normal, middle)
        t1, t2 = _dot(line.direction, start), _dot(line.direction, end)
        line.t_min, line.t_max = min(t1, t2), max(t1, t2)
        lines.append(line)

    merged = _merge_lines(lines)
    centre = _centre(floors, trajectory, merged)
    boundary = _drop_inner_faces(merged, centre)
    if len(boundary) < 3:
        return _too_few_walls(len(boundary))

    def polar(line: _Line) -> float:
        m = _sub(line.middle, centre)
        return math.atan2(m[1], m[0])

    boundary.sort(key=polar)

    corners: list[Point] = []
    inferred = 0
    for i, a in enumerate(boundary):
        b = boundary[(i + 1) % len(boundary)]
        if _angle_gap(a.angle, b.angle) >= MIN_CORNER_ANGLE_RAD:
            corner = _intersect(a, b)
            if _dist(corner, centre) > MAX_CORNER_DISTANCE_M:
                return ProposalFailed(
                    "Dos paredes detectadas se cruzan demasiado lejos del ambiente. "
                    "Repita el recorrido."
                )
            corners.append(corner)
        else:
            # Parallel neighbours: the wall between them was not detected. Close the gap
            # where the observations reach furthest towards it.
            gap = polar(b) - polar(a)
            if gap <= 0:
                gap += 2 * math.pi
            bisector = polar(a) + gap / 2
            towards = (math.cos(bisector), math.sin(bisector))
            candidates = [a.at(a.t_min), a.at(a.t_max), b.at(b.t_min), b.at(b.t_max)]
            candidates.sort(key=lambda p: -_dot(_sub(p, centre), towards))
            reach = candidates[0]
            corners.append(a.project(reach))
            corners.append(b.project(reach))
            inferred += 1

    if _blocking_contour_issue(corners):
        return ProposalFailed(
            "Las paredes detectadas no forman un contorno válido. Repita el recorrido."
        )
    return ProposedContour(corners, len(boundary), inferred)


def _merge_lines(lines: list[_Line]) -> list[_Line]:
    """Join fragments of the same wall (ARCore splits one wall into several planes)."""
    result: list[_Line] = []
    for line in lines:
        target: _Line | None = None
        for candidate in result:
            if _angle_gap(candidate.angle, line.angle) > SAME_DIRECTION_RAD:
                continue
            sign = 1.0 if _dot(candidate.direction, line.direction) >= 0 else -1.0
            if abs(candidate.offset - sign * line.offset) <= SAME_LINE_OFFSET_M:
                target = candidate
                break
        if target is None:
            result.append(line)
            continue
        sign = 1.0 if _dot(target.direction, line.direction) >= 0 else -1.0
        t1, t2 = sign * line.t_min, sign * line.t_max
        total = target.weight + line.weight
        target.offset = (target.offset * target.weight + sign * line.offset * line.weight) / total
        target.t_min = min(target.t_min, t1, t2)
        target.t_max = max(target.t_max, t1, t2)
        target.weight = total
    return result


def _centre(floors: list[list[Point]], trajectory: list[Point], lines: list[_Line]) -> Point:
    points = [p for floor in floors for p in floor] + list(trajectory)
    if not points:
        points = [line.middle for line in lines]
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


def _drop_inner_faces(lines: list[_Line], centre: Point) -> list[_Line]:
    """A surface in front of a parallel wall on the same side (a wardrobe) is not the boundary."""
    dropped: set[int] = set()
    for a in lines:
        for b in lines:
            if a is b or id(a) in dropped or id(b) in dropped:
                continue
            if _angle_gap(a.angle, b.angle) > SAME_DIRECTION_RAD:
                continue
            sign = 1.0 if _dot(a.direction, b.direction) >= 0 else -1.0
            a_side = a.offset - _dot(a.normal, centre)
            b_side = sign * b.offset - _dot(a.normal, centre)
            if _sign(a_side) != _sign(b_side):
                continue
            b_min = min(sign * b.t_min, sign * b.t_max)
            b_max = max(sign * b.t_min, sign * b.t_max)
            overlap = min(a.t_max, b_max) - max(a.t_min, b_min)
            if overlap <= 0.5 * min(a.length, b.length):
                continue
            dropped.add(id(a) if abs(a_side) < abs(b_side) else id(b))
    return [line for line in lines if id(line) not in dropped]


def _intersect(a: _Line, b: _Line) -> Point:
    na, nb = a.normal, b.normal
    det = na[0] * nb[1] - na[1] * nb[0]
    return (
        (a.offset * nb[1] - na[1] * b.offset) / det,
        (na[0] * b.offset - a.offset * nb[0]) / det,
    )


# --- Scene assembly (port of scene_builder.dart) -------------------------------------------


@dataclass
class _Room:
    id: str
    name: str
    corners: list[Point]  # interior face, counter-clockwise on x/z
    height: float
    height_source: str  # contract value: ceiling_plane | assumed
    measured: bool

    def centerline(self) -> list[Point]:
        """Interior contour offset outwards by half the wall thickness (miter joints), in mm."""
        half = WALL_THICKNESS_M / 2
        count = len(self.corners)
        result: list[Point] = []
        for i, corner in enumerate(self.corners):
            previous = self.corners[(i - 1) % count]
            following = self.corners[(i + 1) % count]
            d1, d2 = _unit(_sub(corner, previous)), _unit(_sub(following, corner))
            n1 = _scale((d1[1], -d1[0]), half)
            n2 = _scale((d2[1], -d2[0]), half)
            denominator = _cross(d1, d2)
            if abs(denominator) < 1e-9:
                point = _add(corner, n2)
            else:
                a1, a2 = _add(corner, n1), _add(corner, n2)
                point = _add(a1, _scale(d1, _cross(_sub(a2, a1), d2) / denominator))
            result.append((_round(point[0], 3), _round(point[1], 3)))
        return result


@dataclass
class _WallRecord:
    id: str
    start: int
    end: int
    height: float
    height_source: str


class _SceneBuilder:
    def __init__(self, rooms: list[_Room], boxes: list[dict[str, Any]]) -> None:
        self.rooms = rooms
        self.boxes = boxes
        self.warnings: list[str] = []
        self._vertices: list[Point] = []
        self._walls: list[_WallRecord] = []
        self._by_endpoints: dict[tuple[int, int], int] = {}

    def build(self) -> dict[str, Any]:
        indexes = [[self._weld(v) for v in room.centerline()] for room in self.rooms]
        room_documents: list[dict[str, Any]] = []
        for room, vertex_indexes in zip(self.rooms, indexes, strict=True):
            wall_ids: list[str] = []
            for i, a in enumerate(vertex_indexes):
                chain = self._split_edge(a, vertex_indexes[(i + 1) % len(vertex_indexes)])
                for k in range(len(chain) - 1):
                    wall = self._wall_for(chain[k], chain[k + 1], room)
                    wall_id = self._walls[wall].id
                    if not wall_ids or wall_ids[-1] != wall_id:
                        wall_ids.append(wall_id)
            if len(wall_ids) > 1 and wall_ids[0] == wall_ids[-1]:
                wall_ids.pop()
            room_id = room.id if room.id.startswith("room-") else f"room-{room.id}"
            room_documents.append({"id": room_id, "name": room.name, "wallIds": wall_ids})

        document = {
            "version": "2.0",
            "unit": "meters",
            "walls": [self._wall_json(w) for w in self._walls],
            # Openings are not detected in v1; the agency marks them in the editor.
            "openings": [],
            "rooms": room_documents,
            "objects": self._objects(),
        }
        self._height_warnings()
        self._duplicate_wall_warnings()
        self._overlap_warnings()
        return document

    def _weld(self, point: Point) -> int:
        for i, vertex in enumerate(self._vertices):
            if _dist(vertex, point) <= WELD_TOLERANCE_M + 1e-9:
                return i
        self._vertices.append(point)
        return len(self._vertices) - 1

    def _split_edge(self, a: int, b: int) -> list[int]:
        """Vertex chain a -> b including every vertex within the weld tolerance of the interior."""
        if a == b:
            return [a]
        start = self._vertices[a]
        segment = _sub(self._vertices[b], start)
        length = _len(segment)
        inner: list[tuple[float, int]] = []
        for k, vertex in enumerate(self._vertices):
            if k in (a, b):
                continue
            relative = _sub(vertex, start)
            along = _dot(relative, segment) / length
            if along <= 1e-6 or along >= length - 1e-6:
                continue
            if abs(_cross(relative, segment)) / length <= WELD_TOLERANCE_M + 1e-9:
                inner.append((along, k))
        inner.sort()
        return [a, *(k for _, k in inner), b]

    def _wall_for(self, a: int, b: int, room: _Room) -> int:
        key = (a, b) if a < b else (b, a)
        existing = self._by_endpoints.get(key)
        if existing is not None:
            wall = self._walls[existing]
            if room.height > wall.height:
                wall.height, wall.height_source = room.height, room.height_source
            return existing
        self._walls.append(
            _WallRecord(f"wall-{len(self._walls) + 1}", a, b, room.height, room.height_source)
        )
        self._by_endpoints[key] = len(self._walls) - 1
        return len(self._walls) - 1

    def _wall_json(self, wall: _WallRecord) -> dict[str, Any]:
        start, end = self._vertices[wall.start], self._vertices[wall.end]
        return {
            "id": wall.id,
            "start": {"x": start[0], "z": start[1]},
            "end": {"x": end[0], "z": end[1]},
            "height": _round(wall.height, 3),
            "thickness": WALL_THICKNESS_M,
            "heightSource": wall.height_source,
        }

    def _objects(self) -> list[dict[str, Any]]:
        objects: list[dict[str, Any]] = []
        for box in self.boxes:
            objects.append(
                {
                    "id": f"box-{len(objects) + 1}",
                    "type": "occupancy",
                    "position": {"x": _round(box["x"], 3), "y": 0.0, "z": _round(box["z"], 3)},
                    "dimensions": {
                        "width": _round(box["width"], 3),
                        "height": _round(box["height"], 3),
                        "depth": _round(box["depth"], 3),
                    },
                    "color": OCCUPANCY_COLOR,
                    "source": "depth",
                    "confidence": box["confidence"],
                }
            )
        return objects

    def _height_warnings(self) -> None:
        for room in self.rooms:
            if not room.measured:
                self.warnings.append(
                    f"La altura de «{room.name}» es supuesta ({room.height:.2f} m), no medida. "
                    "Ajústela si conoce el valor real."
                )

    def _duplicate_wall_warnings(self) -> None:
        max_sin = math.sin(math.radians(DUPLICATE_WALL_ANGLE_DEG))
        for i, wall_a in enumerate(self._walls):
            a_start = self._vertices[wall_a.start]
            a_vector = _sub(self._vertices[wall_a.end], a_start)
            a_length = _len(a_vector)
            a_direction = _scale(a_vector, 1 / a_length)
            for wall_b in self._walls[i + 1 :]:
                b_start, b_end = self._vertices[wall_b.start], self._vertices[wall_b.end]
                if abs(_cross(a_direction, _unit(_sub(b_end, b_start)))) > max_sin:
                    continue
                t0 = _dot(_sub(b_start, a_start), a_direction)
                t1 = _dot(_sub(b_end, a_start), a_direction)
                overlap = min(a_length, max(t0, t1)) - max(0.0, min(t0, t1))
                if overlap <= DUPLICATE_WALL_OVERLAP_M:
                    continue
                distance = (
                    abs(_cross(_sub(b_start, a_start), a_direction))
                    + abs(_cross(_sub(b_end, a_start), a_direction))
                ) / 2
                if distance < DUPLICATE_WALL_DISTANCE_M:
                    self.warnings.append(
                        f"Las paredes {wall_a.id} y {wall_b.id} son casi paralelas y están a "
                        "menos de 30 cm: puede ser la misma pared capturada dos veces. "
                        "Revise la conexión de los ambientes."
                    )

    def _overlap_warnings(self) -> None:
        polygons = [room.corners for room in self.rooms]
        for i, first in enumerate(self.rooms):
            for j in range(i + 1, len(self.rooms)):
                if _polygons_overlap(polygons[i], polygons[j]):
                    self.warnings.append(
                        f"«{first.name}» y «{self.rooms[j].name}» se superponen. Revise cómo "
                        "están ubicados."
                    )


def _polygons_overlap(a: list[Point], b: list[Point]) -> bool:
    for i in range(len(a)):
        for j in range(len(b)):
            if _segments_cross_properly(
                a[i], a[(i + 1) % len(a)], b[j], b[(j + 1) % len(b)]
            ):
                return True

    def centroid(polygon: list[Point]) -> Point:
        return (
            sum(p[0] for p in polygon) / len(polygon),
            sum(p[1] for p in polygon) / len(polygon),
        )

    return (
        any(_point_in_polygon(p, b) for p in a)
        or any(_point_in_polygon(p, a) for p in b)
        or _point_in_polygon(centroid(a), b)
        or _point_in_polygon(centroid(b), a)
    )


# --- Occupancy volumes from depth ----------------------------------------------------------


def _extract_volumes(
    package_dir: Path,
    manifest: dict[str, Any],
    rooms: list[_Room],
    floor_y: float,
    stride: int,
    warnings: list[str],
) -> list[dict[str, Any]]:
    keyframes = [k for k in manifest["keyframes"] if k.get("depth") is not None]
    if not keyframes:
        warnings.append(
            "Sin profundidad: no se generaron volúmenes de ocupación. El dispositivo no "
            "entregó datos de profundidad; ubique los muebles manualmente en el editor."
        )
        return []

    intrinsics = manifest["depth"]
    width, height = int(intrinsics["width"]), int(intrinsics["height"])
    fx, fy, cx, cy = (float(intrinsics[k]) for k in ("fx", "fy", "cx", "cy"))
    centerlines = [room.centerline() for room in rooms]
    boxes_of_room = [(min(p[0] for p in r.corners), max(p[0] for p in r.corners),
                      min(p[1] for p in r.corners), max(p[1] for p in r.corners)) for r in rooms]
    y_low = floor_y + VOLUME_MIN_ABOVE_FLOOR_M
    y_high = floor_y + VOLUME_MAX_ABOVE_FLOOR_M
    cells: dict[tuple[int, int, int], list[float]] = {}

    for keyframe in keyframes:
        depth = _load_gray(package_dir, keyframe["depth"], width, height, 16)
        confidence = (
            _load_gray(package_dir, keyframe["confidence"], width, height, 8)
            if keyframe.get("confidence")
            else None
        )
        r = _rotation(keyframe["pose"])
        tx, ty, tz = keyframe["pose"][:3]
        for v in range(0, height, stride):
            y_cam_unit = -(v - cy) / fy
            row = v * width
            for u in range(0, width, stride):
                millimetres = depth[row + u]
                if millimetres == 0:
                    continue
                d = millimetres / 1000.0
                if d > DEPTH_MAX_M:
                    continue
                if confidence is not None and confidence[row + u] < DEPTH_CONFIDENCE_MIN:
                    continue
                # Camera frame: x right, y up, looks towards -z; depth is along the optical axis.
                x_cam, y_cam, z_cam = (u - cx) / fx * d, y_cam_unit * d, -d
                wy = r[1][0] * x_cam + r[1][1] * y_cam + r[1][2] * z_cam + ty
                if wy < y_low or wy > y_high:
                    continue
                wx = r[0][0] * x_cam + r[0][1] * y_cam + r[0][2] * z_cam + tx
                wz = r[2][0] * x_cam + r[2][1] * y_cam + r[2][2] * z_cam + tz
                room_index = _room_containing((wx, wz), rooms, boxes_of_room)
                if room_index is None:
                    continue
                if min(
                    _distance_to_segment((wx, wz), centerlines[room_index][i],
                                         centerlines[room_index][(i + 1) % len(centerlines[room_index])])
                    for i in range(len(centerlines[room_index]))
                ) <= WALL_CLEARANCE_M:
                    continue
                key = (room_index, math.floor(wx / GRID_CELL_M), math.floor(wz / GRID_CELL_M))
                cell = cells.get(key)
                if cell is None:
                    cells[key] = [1.0, wy]
                else:
                    cell[0] += 1
                    cell[1] = max(cell[1], wy)

    boxes = _components_to_boxes(cells, floor_y)
    if not boxes:
        warnings.append(
            "No se detectaron volúmenes de ocupación con la profundidad disponible."
        )
    return boxes


def _load_gray(package_dir: Path, name: str, width: int, height: int, bits: int) -> list[int]:
    path = (package_dir / name).resolve()
    _require(package_dir.resolve() in path.parents, f"{name}: path escapes the package")
    _require(path.is_file(), f"{name}: file is missing from the package")
    try:
        image = png16.decode_gray_png(path.read_bytes())
    except png16.PngError as error:
        raise InvalidPackage(f"{name}: {error}") from error
    _require(
        (image.width, image.height, image.bit_depth) == (width, height, bits),
        f"{name}: expected a {width}x{height} {bits}-bit PNG",
    )
    return image.samples


def _room_containing(
    point: Point, rooms: list[_Room], bounds: list[tuple[float, float, float, float]]
) -> int | None:
    for index, room in enumerate(rooms):
        x0, x1, z0, z1 = bounds[index]
        if x0 <= point[0] <= x1 and z0 <= point[1] <= z1 and _point_in_polygon(point, room.corners):
            return index
    return None


def _components_to_boxes(
    cells: dict[tuple[int, int, int], list[float]], floor_y: float
) -> list[dict[str, Any]]:
    occupied = {key for key, value in cells.items() if value[0] >= MIN_CELL_POINTS}
    seen: set[tuple[int, int, int]] = set()
    boxes: list[dict[str, Any]] = []
    for start in sorted(occupied):
        if start in seen:
            continue
        seen.add(start)
        queue = deque([start])
        members: list[tuple[int, int, int]] = []
        while queue:
            room, ix, iz = queue.popleft()
            members.append((room, ix, iz))
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    neighbour = (room, ix + dx, iz + dz)
                    if neighbour in occupied and neighbour not in seen:
                        seen.add(neighbour)
                        queue.append(neighbour)
        if len(members) < MIN_COMPONENT_CELLS:
            continue
        xs = [m[1] for m in members]
        zs = [m[2] for m in members]
        points = sum(cells[m][0] for m in members)
        top = max(cells[m][1] for m in members)
        x0, x1 = min(xs) * GRID_CELL_M, (max(xs) + 1) * GRID_CELL_M
        z0, z1 = min(zs) * GRID_CELL_M, (max(zs) + 1) * GRID_CELL_M
        support = points / (len(members) * FULL_SUPPORT_POINTS_PER_CELL)
        boxes.append(
            {
                "x": (x0 + x1) / 2,
                "z": (z0 + z1) / 2,
                "width": x1 - x0,
                "depth": z1 - z0,
                "height": top - floor_y,
                "confidence": round(min(1.0, support), 2),
            }
        )
    return boxes


# --- Orchestration -------------------------------------------------------------------------


def _read_manifest(package_dir: Path) -> dict[str, Any]:
    path = package_dir / "manifest.json"
    _require(path.is_file(), "manifest.json is missing")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise InvalidPackage("manifest.json is not valid JSON") from error
    return validate_manifest(data)


def _nearest_room(point: Point, samples: list[tuple[Point, str]]) -> str:
    return min(samples, key=lambda sample: _dist(sample[0], point))[1]


def reconstruct(package_dir: Path, *, depth_stride: int = DEPTH_PIXEL_STRIDE) -> ReconstructionResult:
    """Reconstruct an unzipped capture package into a scene v2 draft plus agency warnings."""
    package_dir = Path(package_dir)
    manifest = _read_manifest(package_dir)
    floor_y = float(manifest["floorY"])
    warnings: list[str] = []

    samples = [((float(s[1]), float(s[2])), s[3]) for s in manifest["trajectory"]]
    walls_by_room: dict[str, list[tuple[Point, Point]]] = {r["id"]: [] for r in manifest["rooms"]}
    floors_by_room: dict[str, list[list[Point]]] = {r["id"]: [] for r in manifest["rooms"]}
    ceilings: list[tuple[list[Point], float, float]] = []  # polygon, mean y, area
    for plane in manifest["planes"]:
        world = plane_to_world(plane["pose"], plane["polygon"])
        footprint = [(p[0], p[2]) for p in world]
        if plane["type"] == "wall":
            segment = fit_wall_segment(world)
            if segment is not None:
                room_id = _nearest_room(_scale(_add(segment.start, segment.end), 0.5), samples)
                walls_by_room[room_id].append((segment.start, segment.end))
        elif plane["type"] == "floor":
            centroid = (
                sum(p[0] for p in footprint) / len(footprint),
                sum(p[1] for p in footprint) / len(footprint),
            )
            floors_by_room[_nearest_room(centroid, samples)].append(footprint)
        else:
            area = abs(_signed_area([(p[0], p[1]) for p in plane["polygon"]]))
            ceilings.append((footprint, sum(p[1] for p in world) / len(world), area))

    rooms: list[_Room] = []
    for room in manifest["rooms"]:
        room_samples = [s[0] for s in samples if s[1] == room["id"]]
        proposal = propose_contour(walls_by_room[room["id"]], floors_by_room[room["id"]], room_samples)
        if isinstance(proposal, ProposalFailed):
            warnings.append(f"«{room['name']}» no se incluyó en la escena. {proposal.message}")
            continue
        corners = proposal.corners
        if _signed_area(corners) < 0:
            corners = corners[::-1]
        if proposal.inferred_edges:
            warnings.append(
                f"«{room['name']}»: {proposal.inferred_edges} lado(s) del contorno no tienen "
                "pared detectada y su posición es una estimación. Verifíquelos en el editor."
            )
        height, measured = _room_height(corners, ceilings, floor_y)
        if height is None:
            height, measured = ASSUMED_ROOM_HEIGHT_M, False
        rooms.append(
            _Room(
                id=room["id"],
                name=room["name"],
                corners=corners,
                height=height,
                height_source="ceiling_plane" if measured else "assumed",
                measured=measured,
            )
        )
    if not rooms:
        raise InvalidPackage(
            "No se pudo cerrar el contorno de ningún ambiente: " + " ".join(warnings)
        )

    boxes = _extract_volumes(package_dir, manifest, rooms, floor_y, max(1, depth_stride), warnings)

    reference = manifest.get("reference")
    if reference is not None:
        factor = float(reference["meters"]) / math.dist(reference["from"], reference["to"])
        for room in rooms:
            room.corners = [_scale(c, factor) for c in room.corners]
            if room.measured:
                room.height *= factor
        for box in boxes:
            for key in ("x", "z", "width", "depth", "height"):
                box[key] *= factor
        warnings.append(
            f"Se aplicó la medida de referencia de {float(reference['meters']):.2f} m: la escena "
            f"se escaló por un factor de {factor:.3f}."
        )

    builder = _SceneBuilder(rooms, boxes)
    scene = builder.build()
    warnings.extend(builder.warnings)
    warnings.append(
        "Las aberturas no se detectan automáticamente: marque las puertas y ventanas en el editor antes de publicar."
    )
    return ReconstructionResult(scene_draft=scene, warnings=warnings)


def _room_height(
    corners: list[Point], ceilings: list[tuple[list[Point], float, float]], floor_y: float
) -> tuple[float | None, bool]:
    """Ceiling height above the floor (measured) from the largest overlapping ceiling plane."""
    overlapping = [
        c
        for c in ceilings
        if _point_in_polygon((sum(p[0] for p in c[0]) / len(c[0]), sum(p[1] for p in c[0]) / len(c[0])), corners)
        or any(_point_in_polygon(p, corners) for p in c[0])
    ]
    if not overlapping:
        return None, False
    height = max(overlapping, key=lambda c: c[2])[1] - floor_y
    low, high = PLAUSIBLE_CEILING_HEIGHT_M
    if not low <= height <= high:
        return None, False
    return height, True


def extract_package(archive: Path, destination: Path) -> Path:
    """Unzip a capture package safely; a bad archive is an :class:`InvalidPackage`."""
    try:
        with zipfile.ZipFile(archive) as handle:
            total = 0
            root = destination.resolve()
            for info in handle.infolist():
                total += info.file_size
                _require(total <= MAX_UNCOMPRESSED_BYTES, "package is too large once extracted")
                target = (destination / info.filename).resolve()
                _require(
                    target == root or root in target.parents, "package entry escapes its folder"
                )
            handle.extractall(destination)
    except (zipfile.BadZipFile, OSError) as error:
        raise InvalidPackage("the package is not a valid ZIP file") from error
    return destination


def reconstruct_path(path: Path) -> ReconstructionResult:
    """Reconstruct from an unzipped directory or a ZIP file (temporary files are removed)."""
    path = Path(path)
    if path.is_dir():
        return reconstruct(path)
    scratch = Path(tempfile.mkdtemp(prefix="roomforge-package-"))
    try:
        return reconstruct(extract_package(path, scratch))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        print("usage: python worker3d/reconstruct.py <unzipped dir | package.zip>", file=sys.stderr)
        return 2
    try:
        result = reconstruct_path(Path(args[0]))
    except InvalidPackage as error:
        print(f"invalid package: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"sceneDraft": result.scene_draft, "warnings": result.warnings},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
