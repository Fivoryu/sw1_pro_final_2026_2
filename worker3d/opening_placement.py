"""Place a recognised door or window on a room wall, in the units of the plan (F07, openings).

A recognised box is a rectangle in an image. With the camera pose, the box's lower corners and
top centre are rays; where they cross the vertical plane of a wall they give the opening's
position along that wall, its width and its height, in whatever units the reconstruction uses.
No measure is involved: only the geometry the camera already saw.

A door must stand on the floor of the wall it lies on; a box that floats is a window at best.
Thresholds are fractions of the room height, so they hold in metric and proportional plans.
"""

from __future__ import annotations

import dataclasses
import math
from dataclasses import dataclass

Vec3 = tuple[float, float, float]
Mat3 = tuple[Vec3, Vec3, Vec3]  # rows, world_from_camera (COLMAP axes: x right, y down, z forward)
Point = tuple[float, float]

# Fractions of the room height; assumed, not measured on real recordings.
FLOOR_CONTACT_REL = 0.06
WALL_SPAN_MARGIN_REL = 0.05
MIN_DOOR_HEIGHT_REL = 0.3
MAX_OPENING_HEIGHT_REL = 1.05
MERGE_CENTRE_REL = 0.5  # views closer than this share of the wider opening are the same one


@dataclass(frozen=True)
class Camera:
    frame: int
    center: Vec3
    rotation: Mat3
    width: float
    height: float
    fx: float
    fy: float
    cx: float
    cy: float


@dataclass(frozen=True)
class Placement:
    edge: int  # index of the contour edge (corner i to corner i+1)
    position: float  # centre along the edge, 0..1 from its start
    length: float  # of the edge, in plan units
    width: float
    height: float
    sill: float  # height of the lower side above the floor (0 for a door)
    kind: str
    score: float
    views: int = 1


def _ray(camera: Camera, u: float, v: float) -> Vec3:
    d = ((u - camera.cx) / camera.fx, (v - camera.cy) / camera.fy, 1.0)
    r = camera.rotation
    return tuple(sum(r[row][col] * d[col] for col in range(3)) for row in range(3))  # type: ignore[return-value]


def _hit(origin: Vec3, direction: Vec3, a: Point, n: Point) -> tuple[float, Vec3] | None:
    """Where a ray meets the vertical plane through ``a`` with plan normal ``n``."""
    denominator = n[0] * direction[0] + n[1] * direction[2]
    if abs(denominator) < 1e-9:
        return None
    t = (n[0] * (a[0] - origin[0]) + n[1] * (a[1] - origin[2])) / denominator
    if t <= 0:
        return None
    return t, (origin[0] + t * direction[0], origin[1] + t * direction[1], origin[2] + t * direction[2])


def place_detection(
    corners: list[Point],
    floor_y: float,
    room_height: float,
    camera: Camera,
    box: tuple[float, float, float, float],
    kind: str,
    score: float,
) -> Placement | None:
    """The opening a box describes on the wall it lies on, or ``None`` if it fits none."""
    x0, y0, x1, y1 = box
    rays = {
        "left": _ray(camera, x0 * camera.width, y1 * camera.height),
        "right": _ray(camera, x1 * camera.width, y1 * camera.height),
        "top": _ray(camera, (x0 + x1) / 2 * camera.width, y0 * camera.height),
    }
    margin = WALL_SPAN_MARGIN_REL * room_height
    best: tuple[float, Placement] | None = None
    for index, a in enumerate(corners):
        b = corners[(index + 1) % len(corners)]
        length = math.dist(a, b)
        if length < 1e-9:
            continue
        u = ((b[0] - a[0]) / length, (b[1] - a[1]) / length)
        n = (-u[1], u[0])
        hits = {name: _hit(camera.center, ray, a, n) for name, ray in rays.items()}
        if any(h is None for h in hits.values()):
            continue
        left, right, top = hits["left"], hits["right"], hits["top"]
        along_left = u[0] * (left[1][0] - a[0]) + u[1] * (left[1][2] - a[1])
        along_right = u[0] * (right[1][0] - a[0]) + u[1] * (right[1][2] - a[1])
        low, high = min(along_left, along_right), max(along_left, along_right)
        if low < -margin or high > length + margin:
            continue
        bottom_y = (left[1][1] + right[1][1]) / 2
        sill = bottom_y - floor_y
        height = top[1][1] - bottom_y
        if sill < -margin or height <= 0 or sill + height > room_height * MAX_OPENING_HEIGHT_REL + margin:
            continue
        if kind == "door" and (sill > FLOOR_CONTACT_REL * room_height or height < MIN_DOOR_HEIGHT_REL * room_height):
            continue
        centre = min(max((low + high) / 2, 0.0), length)
        placement = Placement(index, centre / length, length, high - low, height, max(0.0, sill), kind, score)
        distance = (left[0] + right[0] + top[0]) / 3
        if best is None or distance < best[0]:
            best = (distance, placement)
    return best[1] if best else None


def _weighted(group: list[Placement], field: str) -> float:
    total = sum(p.score for p in group) or 1.0
    return sum(getattr(p, field) * p.score for p in group) / total


def merge_views(placements: list[Placement]) -> list[Placement]:
    """One opening per physical door or window: views of it from several frames are averaged."""
    groups: list[list[Placement]] = []
    for placement in sorted(placements, key=lambda p: (p.edge, p.kind, p.position)):
        for group in groups:
            head = group[0]
            if head.edge != placement.edge or head.kind != placement.kind:
                continue
            gap = abs(head.position - placement.position) * placement.length
            if gap <= MERGE_CENTRE_REL * max(head.width, placement.width):
                group.append(placement)
                break
        else:
            groups.append([placement])
    merged: list[Placement] = []
    for group in groups:
        merged.append(
            dataclasses.replace(
                group[0],
                position=_weighted(group, "position"),
                width=_weighted(group, "width"),
                height=_weighted(group, "height"),
                sill=_weighted(group, "sill"),
                score=max(p.score for p in group),
                views=len(group),
            )
        )
    return merged
