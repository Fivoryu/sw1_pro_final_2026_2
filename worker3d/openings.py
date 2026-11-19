"""Door and window recognition in video frames (F07, openings).

An open-vocabulary detector scores every box against several descriptions at once: a door,
a window, but also the things that get mistaken for them (a wardrobe, a mirror). A box only
counts as an opening when its description beats those competitors by a margin.

Everything that decides lives in pure functions so it can be tested without the model. The
model itself needs ``torch`` and ``transformers`` plus the downloaded weights; none of them is a
dependency of the worker unless door recognition is switched on, and a missing one is reported
as :class:`reconstruct.ExternalToolMissing` (retryable), never as a bad package.

The recognised boxes carry no measure: they are fractions of the image. Their position and
width on the wall come later from the camera poses, in the units of the plan.
"""

from __future__ import annotations

import importlib
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from reconstruct import ExternalToolMissing
from stage_cache import StageCache, fingerprint

# One prompt per thing a doorway can be confused with. "an archway" is a passage without a leaf.
DOOR, WINDOW = "a door", "a window"
ARCHWAY, WARDROBE, MIRROR = "an archway", "a wardrobe", "a mirror"
PROMPTS = (DOOR, WINDOW, ARCHWAY, WARDROBE, MIRROR)
_KIND_OF = {DOOR: "door", ARCHWAY: "door", WINDOW: "window"}
_LOOKALIKES = (WARDROBE, MIRROR)

# Assumed thresholds, not measured: nobody has run the model on real doors yet.
MIN_SCORE = 0.25
MIN_MARGIN = 0.1
DUPLICATE_IOU = 0.5
# The raw model output keeps every box whose best prompt reaches this probability, so a stored
# result can still answer to any minimum score at or above it.
RAW_FLOOR = 0.05

# Weights must come with a permissive license. The check reads the license declared by the
# model card; it does not audit the data the model was trained on.
PERMISSIVE_LICENSES = frozenset({"apache-2.0", "mit", "bsd-2-clause", "bsd-3-clause", "cc0-1.0", "cc-by-4.0"})

Box = tuple[float, float, float, float]  # x0, y0, x1, y1 as fractions of the image, y down


class LicenseNotPermitted(RuntimeError):
    """The model's declared license is not one the project accepts."""


@dataclass(frozen=True)
class Model:
    repo: str
    license: str


MODELS = {
    "owlv2": Model("google/owlv2-base-patch16-ensemble", "apache-2.0"),
    "grounding-dino": Model("onnx-community/grounding-dino-tiny-ONNX", "apache-2.0"),
}


@dataclass(frozen=True)
class Detection:
    frame: int
    box: Box
    kind: str  # "door" | "window"
    score: float


def require_permissive(license_id: str) -> None:
    if license_id.strip().lower() not in PERMISSIVE_LICENSES:
        raise LicenseNotPermitted(f"license {license_id!r} is not permissive; the model is not loaded")


def classify(
    scores: dict[str, float], min_score: float = MIN_SCORE, min_margin: float = MIN_MARGIN
) -> tuple[str, float] | None:
    """The kind of opening a box is, or ``None`` when it is not clearly one."""
    winner = max(scores, key=lambda prompt: scores[prompt])
    kind = _KIND_OF.get(winner)
    if kind is None or scores[winner] < min_score:
        return None
    rival = max((scores.get(prompt, 0.0) for prompt in _LOOKALIKES), default=0.0)
    if scores[winner] - rival < min_margin:
        return None
    return kind, scores[winner]


def _iou(a: Box, b: Box) -> float:
    width = min(a[2], b[2]) - max(a[0], b[0])
    height = min(a[3], b[3]) - max(a[1], b[1])
    if width <= 0 or height <= 0:
        return 0.0
    inter = width * height
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union


def suppress_duplicates(detections: list[Detection]) -> list[Detection]:
    """Keep the best box among overlapping ones of the same kind (highest score first)."""
    kept: list[Detection] = []
    for candidate in sorted(detections, key=lambda d: -d.score):
        if any(k.kind == candidate.kind and _iou(k.box, candidate.box) >= DUPLICATE_IOU for k in kept):
            continue
        kept.append(candidate)
    return kept


def unpad_box(box: tuple[float, float, float, float], width: int, height: int) -> Box:
    """OWLv2 box (cx, cy, w, h), relative to the image padded to a square, as image fractions."""
    cx, cy, w, h = box
    side = max(width, height)
    x0, x1 = (cx - w / 2) * side / width, (cx + w / 2) * side / width
    y0, y1 = (cy - h / 2) * side / height, (cy + h / 2) * side / height
    return (max(0.0, x0), max(0.0, y0), min(1.0, x1), min(1.0, y1))


# Detects the openings of one image: file -> detections without a frame number.
OpeningDetector = Callable[[Path], list[tuple[Box, str, float]]]
# What the model says about one image, before any decision: every box with its probability per prompt.
RawBoxes = list[tuple[Box, dict[str, float]]]
Scorer = Callable[[Path], RawBoxes]


def decide(raw: RawBoxes, min_score: float = MIN_SCORE, min_margin: float = MIN_MARGIN) -> list[tuple[Box, str, float]]:
    """The openings among raw boxes. Pure: changing a threshold never needs the model again."""
    found: list[tuple[Box, str, float]] = []
    for box, scores in raw:
        verdict = classify(scores, min_score, min_margin)
        if verdict is not None:
            found.append((box, verdict[0], verdict[1]))
    return found


def detector_from(
    scorer: Scorer,
    model_key: str,
    min_score: float = MIN_SCORE,
    min_margin: float = MIN_MARGIN,
    cache: StageCache | None = None,
) -> OpeningDetector:
    """A per-image detector over a raw scorer, optionally remembering what the model said.

    The stored value is the raw output keyed by the image bytes, the model and the prompts, so
    the thresholds are applied on every call and can change without running the model again.
    """
    if min_score < RAW_FLOOR:
        raise ValueError(f"minimum score {min_score} is below the {RAW_FLOOR} that raw results keep")
    repo = MODELS[model_key].repo

    def detect(image_path: Path) -> list[tuple[Box, str, float]]:
        if cache is None:
            raw = scorer(image_path)
        else:
            key = f"{repo}|{'|'.join(PROMPTS)}|{fingerprint([image_path])}"
            raw = cache.fetch("raw-openings", key, lambda: scorer(image_path))
        return decide(raw, min_score, min_margin)

    return detect


def _import_torch() -> tuple[Any, Any]:
    return importlib.import_module("torch"), importlib.import_module("transformers")


def build_detector(
    model_key: str = "owlv2",
    min_score: float = MIN_SCORE,
    min_margin: float = MIN_MARGIN,
    cache: StageCache | None = None,
) -> OpeningDetector:
    """Load the open-vocabulary model once and return a per-image detector.

    Not exercised against the real weights in this repository: the interface is pinned by tests
    with simulated models, and its accuracy on real doors is unmeasured.
    """
    if model_key != "owlv2":
        raise ValueError(f"{model_key!r} is pinned in MODELS but has no backend yet; use 'owlv2'")
    model = MODELS[model_key]
    require_permissive(model.license)
    try:
        torch, transformers = _import_torch()
        from PIL import Image  # optional, only needed with the model
    except ImportError as error:
        raise ExternalToolMissing(
            f"El reconocimiento de puertas necesita torch, transformers y Pillow ({error}). "
            "Instálelos en la máquina del worker."
        ) from error

    processor = transformers.Owlv2Processor.from_pretrained(model.repo)
    network = transformers.Owlv2ForObjectDetection.from_pretrained(model.repo).eval()

    def score(image_path: Path) -> RawBoxes:
        image = Image.open(image_path).convert("RGB")
        inputs = processor(text=[list(PROMPTS)], images=image, return_tensors="pt")
        with torch.no_grad():
            output = network(**inputs)
        probabilities = torch.sigmoid(output.logits[0]).tolist()  # boxes x prompts
        boxes = output.pred_boxes[0].tolist()
        raw: RawBoxes = []
        for raw_box, row in zip(boxes, probabilities, strict=True):
            if max(row) >= RAW_FLOOR:
                raw.append((unpad_box(tuple(raw_box), image.width, image.height), dict(zip(PROMPTS, row, strict=True))))
        return raw

    return detector_from(score, model_key, min_score, min_margin, cache)
