"""F07 door recognition (S2, S4, S5): pure decisions around an open-vocabulary detector.

The model itself is not run here (torch and the weights are optional and heavy); these tests
pin what decides between a door and the other things in a room.
"""

from __future__ import annotations

import openings
import pytest
import reconstruct


def scores(door=0.0, window=0.0, wardrobe=0.0, mirror=0.0, archway=0.0) -> dict[str, float]:
    return {
        "a door": door,
        "a window": window,
        "a wardrobe": wardrobe,
        "a mirror": mirror,
        "an archway": archway,
    }


def test_a_clear_door_is_a_door() -> None:
    assert openings.classify(scores(door=0.6, wardrobe=0.2)) == ("door", 0.6)


def test_a_window_is_a_window() -> None:
    assert openings.classify(scores(window=0.55, mirror=0.1)) == ("window", 0.55)


def test_an_archway_is_a_passage_so_it_is_a_door() -> None:
    assert openings.classify(scores(archway=0.5, door=0.1)) == ("door", 0.5)


def test_a_wardrobe_that_looks_like_a_door_is_not_a_door() -> None:
    assert openings.classify(scores(door=0.45, wardrobe=0.42)) is None


def test_a_mirror_that_looks_like_a_window_is_not_a_window() -> None:
    assert openings.classify(scores(window=0.40, mirror=0.38)) is None


def test_a_wardrobe_that_wins_is_not_an_opening() -> None:
    assert openings.classify(scores(door=0.3, wardrobe=0.7)) is None


def test_a_weak_door_is_discarded() -> None:
    assert openings.classify(scores(door=openings.MIN_SCORE - 0.01)) is None


def test_duplicate_boxes_of_the_same_kind_keep_only_the_best() -> None:
    a = openings.Detection(0, (0.40, 0.20, 0.60, 0.90), "door", 0.9)
    b = openings.Detection(0, (0.41, 0.21, 0.61, 0.91), "door", 0.6)
    c = openings.Detection(0, (0.05, 0.20, 0.20, 0.90), "door", 0.5)

    kept = openings.suppress_duplicates([b, c, a])

    assert kept == [a, c]


def test_boxes_of_different_kinds_never_suppress_each_other() -> None:
    door = openings.Detection(0, (0.4, 0.2, 0.6, 0.9), "door", 0.9)
    window = openings.Detection(0, (0.4, 0.2, 0.6, 0.9), "window", 0.8)

    assert openings.suppress_duplicates([door, window]) == [door, window]


def test_owlv2_boxes_are_relative_to_the_padded_square_and_come_back_to_the_image() -> None:
    # A 200x100 image is padded below to 200x200: a box that spans the whole padded height
    # (cy=0.5, h=1.0) covers image rows 0..100 once clipped.
    box = openings.unpad_box((0.5, 0.5, 0.5, 1.0), width=200, height=100)

    assert box == pytest.approx((0.25, 0.0, 0.75, 1.0))


def test_only_permissive_licenses_are_accepted() -> None:
    openings.require_permissive("apache-2.0")
    for forbidden in ("gpl-3.0", "agpl-3.0", "other", "cc-by-nc-4.0", ""):
        with pytest.raises(openings.LicenseNotPermitted):
            openings.require_permissive(forbidden)


def test_the_pinned_models_declare_a_permissive_license() -> None:
    for model in openings.MODELS.values():
        openings.require_permissive(model.license)


def test_without_torch_the_detector_reports_a_missing_tool_not_a_bad_package(monkeypatch) -> None:
    monkeypatch.setattr(openings, "_import_torch", lambda: (_ for _ in ()).throw(ImportError("torch")))

    with pytest.raises(reconstruct.ExternalToolMissing):
        openings.build_detector()
