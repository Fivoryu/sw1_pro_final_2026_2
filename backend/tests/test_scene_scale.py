import pytest
from pydantic import ValidationError

from app.modules.catalog.schemas import ListingSceneDocument


def _scene(**extra: object) -> dict[str, object]:
    return {"version": "2.0", "unit": "meters", "walls": [], "openings": [], "rooms": [], "objects": [], **extra}


def test_scene_without_scale_still_validates_and_stays_without_it() -> None:
    document = ListingSceneDocument.model_validate(_scene())

    assert document.scale is None
    assert "scale" not in document.model_dump(mode="json", by_alias=True, exclude_unset=True)


@pytest.mark.parametrize("mode", ["metric", "proportional"])
def test_scene_scale_mode_round_trips(mode: str) -> None:
    document = ListingSceneDocument.model_validate(_scene(scale={"mode": mode}))

    assert document.model_dump(mode="json", by_alias=True, exclude_unset=True)["scale"] == {"mode": mode}


def test_scene_scale_rejects_unknown_modes() -> None:
    with pytest.raises(ValidationError):
        ListingSceneDocument.model_validate(_scene(scale={"mode": "feet"}))
