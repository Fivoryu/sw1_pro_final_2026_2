"""Place a recognised door or window on a room wall, in the units of the plan (F07, openings).

A recognised box is the axis-aligned bounding box of an opening, which seen obliquely is a
quadrilateral: its box corners are not the opening's corners. So the opening is fitted instead:
it is a rectangle on the vertical plane of a wall, and its position along that wall, bottom and
top are the four numbers whose projection has exactly that bounding box. The fit uses the camera
pose and no measure, and gives the opening's width and height in whatever units the reconstruction
uses.

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


FIT_ITERATIONS = 8
FIT_TOLERANCE_REL = 1e-6  # of the opening's width, between two refinements


def _to_camera(camera: Camera, point: Vec3) -> Vec3:
    rel = (point[0] - camera.center[0], point[1] - camera.center[1], point[2] - camera.center[2])
    r = camera.rotation
    return tuple(sum(r[row][col] * rel[row] for row in range(3)) for col in range(3))  # type: ignore[return-value]


def _project(camera: Camera, point: Vec3) -> tuple[float, float] | None:
    x, y, z = _to_camera(camera, point)
    if z <= 1e-9:
        return None
    return camera.fx * x / z + camera.cx, camera.fy * y / z + camera.cy


def _height_at(camera: Camera, ground: Point, target_v: float) -> float | None:
    """World height of the point above ``ground`` (plan x, z) that projects to image row ``target_v``."""
    r = camera.rotation
    c = camera.center
    base = (ground[0] - c[0], -c[1], ground[1] - c[2])
    a = [sum(r[row][i] * base[row] for row in range(3)) for i in range(3)]  # camera coordinates at y = 0
    b = [r[1][i] for i in range(3)]  # change per unit of world height
    shifted = target_v - camera.cy
    denominator = camera.fy * b[1] - shifted * b[2]
    if abs(denominator) < 1e-12:
        return None
    return (shifted * a[2] - camera.fy * a[1]) / denominator


def _fit_opening(
    camera: Camera, a: Point, u: Point, n: Point, px: tuple[float, float, float, float]
) -> tuple[float, float, float, float] | None:
    """(left, right, bottom, top) of the rectangle on the wall whose projection has the box ``px``.

    ``left``/``right`` are distances along the wall from ``a``; ``bottom``/``top`` are world heights.
    ``px`` is (u0, v0, u1, v1) in pixels. Starts from the rays through the middle of the box and
    refines: the extreme column belongs to whichever corner is leftmost, the extreme row to whichever
    is highest or lowest, and each is re-solved from the others a few times.
    """
    u0, v0, u1, v1 = px
    middle = (v0 + v1) / 2
    along: list[float] = []
    for column in (u0, u1):
        hit = _hit(camera.center, _ray(camera, column, middle), a, n)
        if hit is None:
            return None
        along.append(u[0] * (hit[1][0] - a[0]) + u[1] * (hit[1][2] - a[1]))
    s_left, s_right = along
    bottom, top = 0.0, 0.0
    for _ in range(FIT_ITERATIONS):
        # Rows: the nearer corner decides the extreme, so the true height is the smaller solution for
        # the top and the larger one for the bottom.
        ground = [(a[0] + u[0] * s, a[1] + u[1] * s) for s in (s_left, s_right)]
        tops = [_height_at(camera, g, v0) for g in ground]
        bottoms = [_height_at(camera, g, v1) for g in ground]
        if any(h is None for h in tops + bottoms):
            return None
        top, bottom = min(tops), max(bottoms)  # type: ignore[type-var]
        # Columns: the leftmost / rightmost corner, then the ray through its own row.
        moved: list[float] = []
        for column, side, pick in ((u0, s_left, min), (u1, s_right, max)):
            corners = []
            for height in (bottom, top):
                point = (a[0] + u[0] * side, height, a[1] + u[1] * side)
                projected = _project(camera, point)
                if projected is None:
                    return None
                corners.append(projected)
            row = pick(corners, key=lambda c: c[0])[1]
            hit = _hit(camera.center, _ray(camera, column, row), a, n)
            if hit is None:
                return None
            moved.append(u[0] * (hit[1][0] - a[0]) + u[1] * (hit[1][2] - a[1]))
        change = max(abs(moved[0] - s_left), abs(moved[1] - s_right))
        s_left, s_right = moved
        if change < FIT_TOLERANCE_REL * max(abs(s_right - s_left), 1e-9):
            break
    return s_left, s_right, bottom, top


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
    pixels = (x0 * camera.width, y0 * camera.height, x1 * camera.width, y1 * camera.height)
    middle_ray = _ray(camera, (pixels[0] + pixels[2]) / 2, (pixels[1] + pixels[3]) / 2)
    margin = WALL_SPAN_MARGIN_REL * room_height
    best: tuple[float, Placement] | None = None
    for index, a in enumerate(corners):
        b = corners[(index + 1) % len(corners)]
        length = math.dist(a, b)
        if length < 1e-9:
            continue
        u = ((b[0] - a[0]) / length, (b[1] - a[1]) / length)
        n = (-u[1], u[0])
        centre_hit = _hit(camera.center, middle_ray, a, n)
        fitted = _fit_opening(camera, a, u, n, pixels)
        if centre_hit is None or fitted is None:
            continue
        along_left, along_right, bottom_y, top_y = fitted
        low, high = min(along_left, along_right), max(along_left, along_right)
        if low < -margin or high > length + margin:
            continue
        sill = bottom_y - floor_y
        height = top_y - bottom_y
        if sill < -margin or height <= 0 or sill + height > room_height * MAX_OPENING_HEIGHT_REL + margin:
            continue
        if kind == "door" and (sill > FLOOR_CONTACT_REL * room_height or height < MIN_DOOR_HEIGHT_REL * room_height):
            continue
        centre = min(max((low + high) / 2, 0.0), length)
        placement = Placement(index, centre / length, length, high - low, height, max(0.0, sill), kind, score)
        distance = centre_hit[0]
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
