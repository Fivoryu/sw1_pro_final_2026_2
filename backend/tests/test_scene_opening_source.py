import pytest
from pydantic import ValidationError

from app.modules.catalog.schemas import ListingSceneDocument


def _scene(**opening: object) -> dict[str, object]:
    wall = {
        "id": "w1",
        "start": {"x": 0, "z": 0},
        "end": {"x": 4, "z": 0},
        "height": 2.4,
        "thickness": 0.15,
    }
    base = {"id": "o1", "wallId": "w1", "position": 0.5, "width": 0.9, "height": 2.0, "type": "door"}
    return {
        "version": "2.0",
        "unit": "meters",
        "walls": [wall],
        "openings": [{**base, **opening}],
        "rooms": [],
        "objects": [],
    }


def test_an_opening_without_source_stays_without_it() -> None:
    document = ListingSceneDocument.model_validate(_scene())

    dumped = document.model_dump(mode="json", by_alias=True, exclude_unset=True)
    assert "source" not in dumped["openings"][0]


def test_an_estimated_opening_round_trips() -> None:
    document = ListingSceneDocument.model_validate(_scene(source="estimated"))

    dumped = document.model_dump(mode="json", by_alias=True, exclude_unset=True)
    assert dumped["openings"][0]["source"] == "estimated"


@pytest.mark.parametrize("source", ["guess", "", "manual", 1])
def test_an_opening_source_other_than_estimated_is_rejected(source: object) -> None:
    with pytest.raises(ValidationError):
        ListingSceneDocument.model_validate(_scene(source=source))
