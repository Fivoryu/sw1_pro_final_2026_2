"""F07 door recognition cache (S4): the model runs once per image; thresholds are decided afterwards."""

from __future__ import annotations

from pathlib import Path

import openings
import pytest
import stage_cache

BOX = (0.1, 0.2, 0.4, 0.9)


def raw(door: float, wardrobe: float = 0.0, window: float = 0.0):
    scores = {prompt: 0.0 for prompt in openings.PROMPTS}
    scores.update({"a door": door, "a wardrobe": wardrobe, "a window": window})
    return [(BOX, scores)]


class FakeScorer:
    def __init__(self, result) -> None:
        self.result = result
        self.calls = 0

    def __call__(self, path: Path):
        self.calls += 1
        return self.result


def image(tmp_path: Path, content: bytes = b"frame") -> Path:
    path = tmp_path / "frame.jpg"
    path.write_bytes(content)
    return path


def test_decide_applies_the_thresholds_it_is_given() -> None:
    boxes = raw(door=0.4, wardrobe=0.2)

    assert openings.decide(boxes) == [(BOX, "door", 0.4)]
    assert openings.decide(boxes, min_score=0.5) == []
    assert openings.decide(boxes, min_margin=0.3) == []


def test_the_default_decision_is_the_one_classify_makes() -> None:
    scores = raw(door=0.45, wardrobe=0.42)[0][1]

    assert openings.classify(scores) is None
    assert openings.decide([(BOX, scores)]) == []


def test_the_model_runs_once_per_image_and_other_thresholds_reuse_it(tmp_path: Path) -> None:
    cache = stage_cache.StageCache(tmp_path / "cache")
    first = FakeScorer(raw(door=0.4, wardrobe=0.2))
    path = image(tmp_path)

    loose = openings.detector_from(first, "owlv2", cache=cache)
    assert loose(path) == [(BOX, "door", 0.4)]

    never = FakeScorer([])
    strict = openings.detector_from(never, "owlv2", min_score=0.5, cache=cache)
    assert strict(path) == []  # same stored scores, stricter decision
    assert first.calls == 1 and never.calls == 0


def test_a_different_image_content_runs_the_model_again(tmp_path: Path) -> None:
    cache = stage_cache.StageCache(tmp_path / "cache")
    scorer = FakeScorer(raw(door=0.6))
    detect = openings.detector_from(scorer, "owlv2", cache=cache)

    detect(image(tmp_path, b"one"))
    detect(image(tmp_path, b"two"))

    assert scorer.calls == 2


def test_without_a_cache_the_model_runs_for_every_call(tmp_path: Path) -> None:
    scorer = FakeScorer(raw(door=0.6))
    detect = openings.detector_from(scorer, "owlv2")
    path = image(tmp_path)

    detect(path)
    detect(path)

    assert scorer.calls == 2


def test_a_minimum_score_below_what_is_stored_is_refused() -> None:
    with pytest.raises(ValueError, match="minimum score"):
        openings.detector_from(FakeScorer([]), "owlv2", min_score=openings.RAW_FLOOR / 2)


def test_the_raw_floor_does_not_exceed_the_default_minimum_score() -> None:
    assert openings.RAW_FLOOR <= openings.MIN_SCORE
