"""Standard-library decoder for grayscale PNG images (8 or 16 bits per sample).

The capture package stores depth as 16-bit grayscale PNG (millimetres) and depth
confidence as 8-bit grayscale PNG. The worker environment has neither numpy nor
Pillow, so this module reads exactly that subset: colour type 0, non-interlaced,
all five scanline filters. Anything else raises :class:`PngError`.
"""

from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass

_SIGNATURE = b"\x89PNG\r\n\x1a\n"
# Guards against decompression bombs: a 16-bit 4096x4096 image is 32 MiB.
MAX_PIXELS = 4096 * 4096


class PngError(ValueError):
    """The bytes are not a PNG this decoder supports."""


@dataclass(frozen=True)
class GrayImage:
    width: int
    height: int
    bit_depth: int
    #: Row-major samples, ``len == width * height``.
    samples: list[int]


def decode_gray_png(data: bytes) -> GrayImage:
    """Decode a non-interlaced grayscale PNG with 8 or 16 bits per sample."""
    if not data.startswith(_SIGNATURE):
        raise PngError("not a PNG file")
    position = len(_SIGNATURE)
    header: tuple[int, int, int, int, int, int, int] | None = None
    compressed = bytearray()
    while position + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[position : position + 8])
        body = data[position + 8 : position + 8 + length]
        if len(body) != length:
            raise PngError("truncated chunk")
        position += 12 + length  # length + type + body + CRC
        if kind == b"IHDR":
            if length != 13:
                raise PngError("invalid IHDR")
            header = struct.unpack(">IIBBBBB", body)  # type: ignore[assignment]
        elif kind == b"IDAT":
            compressed.extend(body)
        elif kind == b"IEND":
            break
    if header is None:
        raise PngError("missing IHDR")
    width, height, bit_depth, color_type, _compression, _filter, interlace = header
    if color_type != 0 or bit_depth not in (8, 16):
        raise PngError("only 8/16-bit grayscale PNG is supported")
    if interlace != 0:
        raise PngError("interlaced PNG is not supported")
    if width <= 0 or height <= 0 or width * height > MAX_PIXELS:
        raise PngError("invalid image size")

    bytes_per_pixel = bit_depth // 8
    stride = width * bytes_per_pixel
    try:
        raw = zlib.decompress(bytes(compressed))
    except zlib.error as error:
        raise PngError("corrupt image data") from error
    if len(raw) != height * (stride + 1):
        raise PngError("image data size does not match the header")

    previous = bytearray(stride)
    samples: list[int] = []
    for row in range(height):
        start = row * (stride + 1)
        filter_type = raw[start]
        line = bytearray(raw[start + 1 : start + 1 + stride])
        _unfilter(line, previous, filter_type, bytes_per_pixel)
        if bit_depth == 8:
            samples.extend(line)
        else:
            samples.extend(struct.unpack(f">{width}H", bytes(line)))
        previous = line
    return GrayImage(width, height, bit_depth, samples)


def _unfilter(line: bytearray, previous: bytearray, filter_type: int, bpp: int) -> None:
    if filter_type == 0:
        return
    if filter_type not in (1, 2, 3, 4):
        raise PngError("unknown scanline filter")
    for i in range(len(line)):
        left = line[i - bpp] if i >= bpp else 0
        up = previous[i]
        up_left = previous[i - bpp] if i >= bpp else 0
        if filter_type == 1:
            predictor = left
        elif filter_type == 2:
            predictor = up
        elif filter_type == 3:
            predictor = (left + up) // 2
        else:
            predictor = _paeth(left, up, up_left)
        line[i] = (line[i] + predictor) & 0xFF


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c
