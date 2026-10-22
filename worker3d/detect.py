"""Furniture detection CLI (F08.2).

Runs a COCO-pretrained SSDLite320 + MobileNetV3-Large detector over an
authorized set of photographs and writes one JSON record per image.

PyTorch is imported lazily, inside the detector loader, so the CLI contract
(arguments, exit codes, output schema) stays verifiable without the inference
runtime installed.

Usage:
    python detect.py --images <dir> --out <records.jsonl> [--threshold 0.5]
    python detect.py --list-classes
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from collections.abc import Iterable, Sequence
from pathlib import Path
from typing import Any

MODEL_META: dict[str, str] = {
    "package": "torchvision",
    "version": "0.29.1+cpu",
    "weights_id": "SSDLite320_MobileNet_V3_Large_Weights.COCO_V1",
}

# Classes the plan (§F08.1) expects a COCO detector to offer.
FURNITURE_CLASSES: tuple[str, ...] = ("chair", "couch", "bed", "dining table", "tv", "refrigerator")
# Classes the plan forbids inferring; recorded so the absence is evidence, not a guess.
NOT_IN_COCO_CLASSES: tuple[str, ...] = ("door", "window", "desk")

IMAGE_SUFFIXES = frozenset({".jpg", ".jpeg", ".png"})
DEFAULT_THRESHOLD = 0.5

# COCO_V1 uses 91 slots: index 0 is __background__ and ten slots are N/A for the
# category ids COCO never defined. Neither is an object, so neither may become a
# furniture suggestion.
NON_OBJECT_LABELS = frozenset({"__background__", "N/A"})

EXIT_OK = 0
EXIT_INVALID_USAGE = 2
EXIT_NO_IMAGES = 3
EXIT_RUNTIME_UNAVAILABLE = 4


class UnreadableImageError(Exception):
    """An input file could not be decoded as an image.

    One corrupt file must not discard the records of every other image, so this
    is a per-image condition, not a run-level failure.
    """

    def __init__(self, path: Path) -> None:
        super().__init__(f"no se pudo leer como imagen: {path.name}")
        self.path = path

# Values no available tool exposes in this environment: declared, never estimated.
NOT_MEASURED_CONSTANT: tuple[str, ...] = (
    "gpu_memory_mb",
    "gpu_utilisation_percent",
    "thermal_state",
)


def build_record(
    *,
    image_name: str,
    model_meta: dict[str, str],
    threshold: float,
    detections: Sequence[dict[str, Any]],
    latency_ms: float | None,
    peak_rss_mb: float | None,
    not_measured: Sequence[str],
) -> dict[str, Any]:
    """Build the per-image record. A score is a score, never a probability."""
    return {
        "image": image_name,
        "model": dict(model_meta),
        "score_threshold": threshold,
        "detections": [dict(detection) for detection in detections],
        "latency_ms": latency_ms,
        "peak_rss_mb": peak_rss_mb,
        "not_measured": list(not_measured),
    }


def build_detections(
    *,
    boxes: Iterable[Sequence[float]],
    labels: Iterable[float],
    scores: Iterable[float],
    categories: Sequence[str],
    threshold: float,
) -> list[dict[str, Any]]:
    """Turn raw model output into detections, dropping non-object labels."""
    detections: list[dict[str, Any]] = []
    for box, label, score in zip(boxes, labels, scores, strict=True):
        name = categories[int(label)]
        if name in NON_OBJECT_LABELS:
            continue
        value = float(score)
        if value < threshold:
            continue
        detections.append(
            {
                "label": name,
                "score": round(value, 4),
                "box": [round(float(coordinate), 2) for coordinate in box],
            }
        )
    return detections


def peak_rss_mb() -> float | None:
    """Peak resident set size of this process, or None when not observable.

    `resource` is POSIX-only, so the import stays here: the CLI runs in the Linux
    container, and its contract stays importable on any platform.
    """
    try:
        import resource
    except ModuleNotFoundError:  # pragma: no cover - non-POSIX host
        return None
    usage = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return round(usage / 1024.0, 2)


def collect_images(directory: Path) -> list[Path]:
    return sorted(
        path
        for path in directory.iterdir()
        if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
    )


def load_detector(device: str) -> tuple[Any, Any, Any]:
    """Load the pinned detector. This is the only place the runtime is imported."""
    try:
        import torch
        from torchvision.models.detection import (
            SSDLite320_MobileNet_V3_Large_Weights,
            ssdlite320_mobilenet_v3_large,
        )
    except ModuleNotFoundError as error:  # pragma: no cover - exercised in the container
        raise RuntimeError(
            f"el runtime de inferencia no está disponible en este intérprete ({error.name}); "
            "ejecutá el CLI dentro del servicio de inferencia de infra/docker"
        ) from error

    torch.set_grad_enabled(False)
    weights = SSDLite320_MobileNet_V3_Large_Weights.COCO_V1
    model = ssdlite320_mobilenet_v3_large(weights=weights)
    model.eval()
    model.to(torch.device(device))
    return model, weights, weights.transforms()


def list_classes() -> int:
    _, weights, _ = load_detector("cpu")
    categories = list(weights.meta["categories"])
    payload = {
        "weights_id": MODEL_META["weights_id"],
        "package": MODEL_META["package"],
        "version": MODEL_META["version"],
        "category_count": len(categories),
        "furniture_present": [name for name in FURNITURE_CLASSES if name in categories],
        "furniture_absent": [name for name in FURNITURE_CLASSES if name not in categories],
        "expected_absent": list(NOT_IN_COCO_CLASSES),
        "expected_absent_found": [name for name in NOT_IN_COCO_CLASSES if name in categories],
        "categories": categories,
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return EXIT_OK


def read_image_tensor(image_path: Path, preprocess: Any) -> Any:
    """Decode one image and apply the model preprocessing.

    Defined outside `detect_images` so the per-image failure path stays testable
    without PyTorch or Pillow installed.
    """
    try:
        from PIL import Image
    except ModuleNotFoundError as error:  # pragma: no cover - exercised in the container
        raise RuntimeError(
            f"falta la biblioteca de imágenes en este intérprete ({error.name}); "
            "ejecutá el CLI dentro del servicio de inferencia de infra/docker"
        ) from error

    try:
        with Image.open(image_path) as image:
            return preprocess(image.convert("RGB"))
    except (OSError, ValueError) as error:
        # Pillow raises UnidentifiedImageError (an OSError) for undecodable bytes.
        raise UnreadableImageError(image_path) from error


def detect_images(
    images: Iterable[Path], threshold: float, device: str
) -> tuple[list[dict[str, Any]], list[str]]:
    """Detect over every readable image; unreadable files are skipped and reported."""
    model, weights, preprocess = load_detector(device)
    categories = list(weights.meta["categories"])
    records: list[dict[str, Any]] = []
    skipped: list[str] = []

    for image_path in images:
        try:
            tensor = read_image_tensor(image_path, preprocess)
        except UnreadableImageError as error:
            print(f"  omitida: {error}", file=sys.stderr)
            skipped.append(image_path.name)
            continue

        started = time.perf_counter()
        output = model([tensor])[0]
        latency_ms = round((time.perf_counter() - started) * 1000.0, 2)

        detections = build_detections(
            boxes=output["boxes"],
            labels=output["labels"],
            scores=output["scores"],
            categories=categories,
            threshold=threshold,
        )
        records.append(
            build_record(
                image_name=image_path.name,
                model_meta=MODEL_META,
                threshold=threshold,
                detections=detections,
                latency_ms=latency_ms,
                peak_rss_mb=peak_rss_mb(),
                not_measured=list(NOT_MEASURED_CONSTANT),
            )
        )

    return records, skipped


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="detect.py",
        description=(
            "Detector de mobiliario preentrenado (torchvision SSDLite320 + MobileNetV3-Large, COCO). "
            "Escribe un registro JSON por imagen en --out."
        ),
    )
    parser.add_argument("--images", type=Path, help="directorio con las imágenes autorizadas del piloto")
    parser.add_argument("--out", type=Path, help="archivo JSONL de salida")
    parser.add_argument(
        "--threshold",
        type=float,
        default=DEFAULT_THRESHOLD,
        help=f"umbral de puntuación, se registra en la salida (por defecto {DEFAULT_THRESHOLD})",
    )
    parser.add_argument("--device", default="cpu", help="dispositivo de cómputo (por defecto cpu)")
    parser.add_argument(
        "--list-classes",
        action="store_true",
        help="descarga los pesos una vez y lista las categorías reales del modelo",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.list_classes:
        try:
            return list_classes()
        except RuntimeError as error:
            print(str(error), file=sys.stderr)
            return EXIT_RUNTIME_UNAVAILABLE

    if args.images is None or args.out is None:
        parser.error("--images y --out son obligatorios salvo con --list-classes")

    if not 0.0 <= args.threshold <= 1.0:
        print(
            f"--threshold debe estar entre 0 y 1; se recibió {args.threshold}",
            file=sys.stderr,
        )
        return EXIT_INVALID_USAGE

    if not args.images.is_dir():
        print(f"el directorio de imágenes no existe: {args.images}", file=sys.stderr)
        return EXIT_INVALID_USAGE

    images = collect_images(args.images)
    if not images:
        print(
            f"no se encontró ninguna imagen en {args.images} "
            f"(se aceptan {sorted(IMAGE_SUFFIXES)})",
            file=sys.stderr,
        )
        return EXIT_NO_IMAGES

    try:
        records, skipped = detect_images(images, args.threshold, args.device)
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return EXIT_RUNTIME_UNAVAILABLE

    if skipped:
        print(
            f"{len(skipped)} imágenes omitidas por no poder leerse: {', '.join(skipped)}",
            file=sys.stderr,
        )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")

    print(f"{len(records)} imágenes procesadas; registros en {args.out}")
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
