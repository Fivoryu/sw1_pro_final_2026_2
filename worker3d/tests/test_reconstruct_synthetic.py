"""Builders for synthetic capture packages (no tests live here)."""

from __future__ import annotations

import json
import math
import struct
import zlib
from pathlib import Path
from typing import Any


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def encode_gray_png(
    width: int, height: int, samples: list[int], *, bit_depth: int = 16, filter_type: int = 0
) -> bytes:
    """Encode a grayscale PNG, applying ``filter_type`` to every scanline."""
    bpp = bit_depth // 8
    lines: list[bytes] = []
    for y in range(height):
        row = samples[y * width : (y + 1) * width]
        lines.append(bytes(row) if bit_depth == 8 else struct.pack(f">{width}H", *row))
    raw = bytearray()
    previous = bytes(len(lines[0]))
    for line in lines:
        raw.append(filter_type)
        for i, value in enumerate(line):
            left = line[i - bpp] if i >= bpp else 0
            up = previous[i]
            up_left = previous[i - bpp] if i >= bpp else 0
            predictor = {
                0: 0,
                1: left,
                2: up,
                3: (left + up) // 2,
                4: _paeth(left, up, up_left),
            }[filter_type]
            raw.append((value - predictor) & 0xFF)
        previous = line

    def chunk(kind: bytes, body: bytes) -> bytes:
        crc = zlib.crc32(kind + body) & 0xFFFFFFFF
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc)

    header = struct.pack(">IIBBBBB", width, height, bit_depth, 0, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw)))
        + chunk(b"IEND", b"")
    )


def _matrix_to_quaternion(
    x_axis: tuple[float, ...], y_axis: tuple[float, ...], z_axis: tuple[float, ...]
) -> tuple[float, float, float, float]:
    """Quaternion (x, y, z, w) of the rotation whose columns are the given axes."""
    m00, m10, m20 = x_axis
    m01, m11, m21 = y_axis
    m02, m12, m22 = z_axis
    trace = m00 + m11 + m22
    if trace > 0:
        s = math.sqrt(trace + 1.0) * 2
        return ((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s)
    if m00 > m11 and m00 > m22:
        s = math.sqrt(1.0 + m00 - m11 - m22) * 2
        return (0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s)
    if m11 > m22:
        s = math.sqrt(1.0 + m11 - m00 - m22) * 2
        return ((m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s)
    s = math.sqrt(1.0 + m22 - m00 - m11) * 2
    return ((m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s)


def _cross(a: tuple[float, ...], b: tuple[float, ...]) -> tuple[float, float, float]:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def wall_plane(
    plane_id: str,
    start: tuple[float, float],
    end: tuple[float, float],
    *,
    height: float = 2.4,
    floor_y: float = 0.0,
) -> dict[str, Any]:
    """Vertical plane over the segment start->end (x/z), from floor_y up by ``height``.

    Plane frame: local x runs along the wall, local z runs up, local y is the
    horizontal normal (right-handed: y = z cross x).
    """
    dx, dz = end[0] - start[0], end[1] - start[1]
    length = math.hypot(dx, dz)
    x_axis = (dx / length, 0.0, dz / length)
    z_axis = (0.0, 1.0, 0.0)
    y_axis = _cross(z_axis, x_axis)
    qx, qy, qz, qw = _matrix_to_quaternion(x_axis, y_axis, z_axis)
    cx, cy, cz = (start[0] + end[0]) / 2, floor_y + height / 2, (start[1] + end[1]) / 2
    half_l, half_h = length / 2, height / 2
    return {
        "id": plane_id,
        "type": "wall",
        "pose": [cx, cy, cz, qx, qy, qz, qw],
        "polygon": [[-half_l, -half_h], [half_l, -half_h], [half_l, half_h], [-half_l, half_h]],
    }


def floor_plane(
    plane_id: str, x0: float, z0: float, x1: float, z1: float, floor_y: float = 0.0
) -> dict[str, Any]:
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    return {
        "id": plane_id,
        "type": "floor",
        "pose": [cx, floor_y, cz, 0.0, 0.0, 0.0, 1.0],
        "polygon": [[x0 - cx, z0 - cz], [x1 - cx, z0 - cz], [x1 - cx, z1 - cz], [x0 - cx, z1 - cz]],
    }


def ceiling_plane(
    plane_id: str, x0: float, z0: float, x1: float, z1: float, y: float
) -> dict[str, Any]:
    plane = floor_plane(plane_id, x0, z0, x1, z1, y)
    plane["type"] = "ceiling"
    return plane


def rectangle_walls(
    prefix: str,
    x0: float,
    z0: float,
    x1: float,
    z1: float,
    height: float = 2.4,
    floor_y: float = 0.0,
    skip: tuple[str, ...] = (),
) -> list[dict[str, Any]]:
    sides = {
        "n": ((x0, z0), (x1, z0)),
        "e": ((x1, z0), (x1, z1)),
        "s": ((x1, z1), (x0, z1)),
        "w": ((x0, z1), (x0, z0)),
    }
    return [
        wall_plane(f"{prefix}{name}", a, b, height=height, floor_y=floor_y)
        for name, (a, b) in sides.items()
        if name not in skip
    ]


def trajectory_for(
    room_id: str, x0: float, z0: float, x1: float, z1: float, t0: int = 0
) -> list[list[Any]]:
    """A loop of four samples inside the rectangle, 0.5 m away from its sides."""
    path = [(x0 + 0.5, z0 + 0.5), (x1 - 0.5, z0 + 0.5), (x1 - 0.5, z1 - 0.5), (x0 + 0.5, z1 - 0.5)]
    return [[t0 + i * 1000, p[0], p[1], room_id] for i, p in enumerate(path)]


def base_manifest(**overrides: Any) -> dict[str, Any]:
    manifest: dict[str, Any] = {
        "schemaVersion": 1,
        "captureId": "capture-1",
        "listingId": "listing-1",
        "capturedAt": "2026-10-21T22:10:00Z",
        "device": {"model": "test", "arcoreVersion": "1.57.0", "depthSupported": False},
        "image": {"width": 640, "height": 480, "fx": 500.0, "fy": 500.0, "cx": 320.0, "cy": 240.0},
        "depth": None,
        "floorY": 0.0,
        "rooms": [{"id": "room-1", "name": "Estar"}],
        "planes": [],
        "trajectory": [],
        "keyframes": [],
        "reference": None,
    }
    manifest.update(overrides)
    return manifest


def room_package(**overrides: Any) -> dict[str, Any]:
    """A closed 4 x 3 m room (Estar) made from four wall planes plus a floor plane."""
    planes = [*rectangle_walls("w", 0, 0, 4, 3), floor_plane("f1", 0, 0, 4, 3)]
    fields: dict[str, Any] = {
        "planes": planes,
        "trajectory": trajectory_for("room-1", 0, 0, 4, 3),
    }
    fields.update(overrides)
    return base_manifest(**fields)


def write_package(
    directory: Path, manifest: dict[str, Any], files: dict[str, bytes] | None = None
) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    for name, content in (files or {}).items():
        target = directory / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    return directory
