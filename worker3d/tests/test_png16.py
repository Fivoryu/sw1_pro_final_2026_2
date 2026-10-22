"""PNG decoder contracts; test PNGs are generated with zlib, no Pillow needed."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

WORKER3D_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKER3D_DIR))

import png16
from test_reconstruct_synthetic import encode_gray_png

_SAMPLES = [0, 1, 255, 256, 1000, 65535, 40000, 12345, 7, 4242, 30000, 9]


@pytest.mark.parametrize("filter_type", [0, 1, 2, 3, 4])
def test_decodes_16_bit_values_under_every_scanline_filter(filter_type: int) -> None:
    data = encode_gray_png(4, 3, _SAMPLES, bit_depth=16, filter_type=filter_type)

    image = png16.decode_gray_png(data)

    assert (image.width, image.height, image.bit_depth) == (4, 3, 16)
    assert image.samples == _SAMPLES


@pytest.mark.parametrize("filter_type", [0, 2, 4])
def test_decodes_8_bit_confidence_maps(filter_type: int) -> None:
    samples = [0, 128, 255, 17, 99, 200]
    data = encode_gray_png(3, 2, samples, bit_depth=8, filter_type=filter_type)

    image = png16.decode_gray_png(data)

    assert image.bit_depth == 8
    assert image.samples == samples


def test_rejects_non_png_bytes() -> None:
    with pytest.raises(png16.PngError):
        png16.decode_gray_png(b"not a png at all")


def test_rejects_truncated_image_data() -> None:
    data = encode_gray_png(4, 3, _SAMPLES)
    with pytest.raises(png16.PngError):
        png16.decode_gray_png(data[:-20])
