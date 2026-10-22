"""Manual review sheets for the F08.2 pilot (R4).

The separation between hits, false positives and misses requires a human look at
each photograph next to what the detector claimed. This tool draws the detected
boxes over the images and composes contact sheets, so the review can be done on
a handful of images instead of opening every file.

Pillow is imported lazily: the CLI contract (exit codes, pagination) stays
verifiable without the image library installed.

Usage:
    python review_sheet.py --records pilot/out/detections.jsonl \
        --images pilot/input --out-dir pilot/out/sheets
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any

EXIT_OK = 0
EXIT_INVALID_USAGE = 2
EXIT_NO_RECORDS = 3
# Same code as detect.py for the same condition: the runtime is unavailable.
EXIT_RUNTIME_UNAVAILABLE = 4

DEFAULT_PER_SHEET = 6
DEFAULT_COLUMNS = 3
DEFAULT_TILE_WIDTH = 640
CAPTION_HEIGHT = 24
BACKGROUND = (18, 18, 18)
CAPTION_BACKGROUND = (0, 0, 0)
CAPTION_COLOR = (255, 255, 255)
BOX_COLOR = (0, 255, 0)


def plan_sheets(record_count: int, per_sheet: int) -> list[int]:
    """Split the record count into page sizes, preserving order."""
    if per_sheet <= 0:
        raise ValueError("per_sheet must be positive")
    sizes: list[int] = []
    remaining = record_count
    while remaining > 0:
        take = min(per_sheet, remaining)
        sizes.append(take)
        remaining -= take
    return sizes


def fit_box(width: int, height: int, box: int) -> tuple[int, int]:
    """Fit an image inside a square cell, preserving aspect ratio.

    Every tile must live inside a fixed cell. Without this, a portrait photo is
    pasted taller than the cell and covers the caption of its own row, which
    makes the review sheet ambiguous — exactly the failure this function exists
    to prevent.
    """
    scale = box / float(max(width, height))
    return max(1, round(width * scale)), max(1, round(height * scale))


def cell_origin(slot: int, columns: int, tile_width: int, caption_height: int) -> tuple[int, int]:
    """Top-left corner of the cell that owns this tile.

    Cells are disjoint and ordered. Detections are drawn in tile space, so this
    origin is only ever used for pasting and for the caption band.
    """
    column = slot % columns
    row = slot // columns
    return column * tile_width, row * (tile_width + caption_height)


class MalformedRecordsError(Exception):
    """The records file is not valid JSONL."""

    def __init__(self, path: Path, line_number: int, detail: str) -> None:
        super().__init__(
            f"el archivo de registros no es JSON válido: {path} "
            f"(línea {line_number}: {detail})"
        )
        self.path = path


def load_records(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as error:
                raise MalformedRecordsError(path, line_number, error.msg) from error
    return records


def render_sheets(
    records: Sequence[dict[str, Any]],
    images_dir: Path,
    out_dir: Path,
    per_sheet: int,
    columns: int,
    tile_width: int,
) -> list[Path]:
    try:
        from PIL import Image, ImageDraw
    except ModuleNotFoundError as error:  # pragma: no cover - exercised in the container
        raise RuntimeError(
            f"falta la biblioteca de imágenes en este intérprete ({error.name}); "
            "ejecutá esta herramienta dentro del servicio de inferencia de infra/docker"
        ) from error

    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    page_sizes = plan_sheets(len(records), per_sheet)
    cursor = 0

    for page_number, page_size in enumerate(page_sizes, start=1):
        rows = math.ceil(page_size / columns)
        page = Image.new("RGB", (tile_width * columns, (tile_width + CAPTION_HEIGHT) * rows), BACKGROUND)
        draw = ImageDraw.Draw(page)

        for slot in range(page_size):
            record = records[cursor + slot]
            origin_x, origin_y = cell_origin(slot, columns, tile_width, CAPTION_HEIGHT)
            image_path = images_dir / str(record.get("image", ""))
            detections = record.get("detections") or []

            if image_path.is_file():
                with Image.open(image_path) as source:
                    tile = source.convert("RGB")
                    fitted_width, fitted_height = fit_box(tile.width, tile.height, tile_width)
                    scale = fitted_width / float(tile.width)
                    tile = tile.resize((fitted_width, fitted_height), Image.LANCZOS)
                # Draw in TILE space. Drawing in page space with tile-local
                # coordinates piles every detection of the page onto the first
                # tile, which is precisely the defect this shape avoids.
                tile_draw = ImageDraw.Draw(tile)
                for detection in detections:
                    box = detection.get("box") or []
                    if len(box) != 4:
                        continue
                    x1, y1, x2, y2 = (float(value) * scale for value in box)
                    tile_draw.rectangle([x1, y1, x2, y2], outline=BOX_COLOR, width=3)
                    label = f"{detection.get('label')} {float(detection.get('score', 0.0)):.2f}"
                    tile_draw.text((x1 + 4, max(0.0, y1 + 4)), label, fill=BOX_COLOR)
                del tile_draw
                # Center inside the fixed cell so no tile can reach its caption.
                page.paste(
                    tile,
                    (
                        origin_x + (tile_width - fitted_width) // 2,
                        origin_y + (tile_width - fitted_height) // 2,
                    ),
                )
            else:
                draw.text((origin_x + 8, origin_y + 8), f"IMAGEN AUSENTE: {image_path.name}", fill=(255, 80, 80))

            names = ", ".join(
                f"{detection.get('label')}({float(detection.get('score', 0.0)):.2f})"
                for detection in detections
            )
            caption = f"{record.get('image')} | {len(detections)} det | {names}"[:110]
            draw.rectangle(
                [origin_x, origin_y + tile_width, origin_x + tile_width, origin_y + tile_width + CAPTION_HEIGHT],
                fill=CAPTION_BACKGROUND,
            )
            draw.text((origin_x + 6, origin_y + tile_width + 6), caption, fill=CAPTION_COLOR)

        sheet_path = out_dir / f"sheet-{page_number:02d}.jpg"
        page.save(sheet_path, quality=85)
        written.append(sheet_path)
        cursor += page_size

    return written


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="review_sheet.py",
        description="Compone planchas de contacto con las cajas detectadas para la revisión manual.",
    )
    parser.add_argument("--records", type=Path, required=True, help="JSONL producido por detect.py")
    parser.add_argument("--images", type=Path, required=True, help="directorio de las imágenes")
    parser.add_argument("--out-dir", type=Path, required=True, help="directorio de las planchas")
    parser.add_argument(
        "--per-sheet", type=int, default=DEFAULT_PER_SHEET, help="imágenes por plancha"
    )
    parser.add_argument("--columns", type=int, default=DEFAULT_COLUMNS, help="columnas por plancha")
    parser.add_argument(
        "--tile-width", type=int, default=DEFAULT_TILE_WIDTH, help="ancho de cada mosaico en píxeles"
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.per_sheet <= 0:
        print(f"--per-sheet debe ser mayor que 0; se recibió {args.per_sheet}", file=sys.stderr)
        return EXIT_INVALID_USAGE
    if args.columns <= 0 or args.tile_width <= 0:
        print("--columns y --tile-width deben ser mayores que 0", file=sys.stderr)
        return EXIT_INVALID_USAGE

    if not args.records.is_file():
        print(f"el archivo de registros no existe: {args.records}", file=sys.stderr)
        return EXIT_INVALID_USAGE

    try:
        records = load_records(args.records)
    except MalformedRecordsError as error:
        print(str(error), file=sys.stderr)
        return EXIT_INVALID_USAGE

    if not records:
        print(f"el archivo de registros está vacío: {args.records}", file=sys.stderr)
        return EXIT_NO_RECORDS

    try:
        written = render_sheets(
            records, args.images, args.out_dir, args.per_sheet, args.columns, args.tile_width
        )
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return EXIT_RUNTIME_UNAVAILABLE

    for sheet in written:
        print(f"plancha: {sheet}")
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
