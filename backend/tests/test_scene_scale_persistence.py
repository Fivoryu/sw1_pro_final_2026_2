"""F07 proportional plans: the optional `scale.mode` survives PUT and GET of the scene."""

from __future__ import annotations

import pytest

from test_listing_scene import (  # pyright: ignore[reportMissingImports]
    SceneContext,
    _scene_document,  # pyright: ignore[reportPrivateUsage]
    _scene_url,  # pyright: ignore[reportPrivateUsage]
    _seed_listing,  # pyright: ignore[reportPrivateUsage]
    _staff,  # pyright: ignore[reportPrivateUsage]
    scene_context,  # noqa: F401  # pyright: ignore[reportUnusedImport]
)


@pytest.mark.parametrize("mode", ["metric", "proportional"])
def test_put_round_trips_the_scale_mode(
    scene_context: SceneContext,  # noqa: F811
    mode: str,
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    expected = _scene_document()
    expected["scale"] = {"mode": mode}

    saved = context.client.put(_scene_url(), json=expected)

    assert saved.status_code == 200, saved.text
    assert saved.json() == expected
    assert context.client.get(_scene_url()).json() == expected


def test_put_rejects_an_unknown_scale_mode(
    scene_context: SceneContext,  # noqa: F811
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    scene = _scene_document()
    scene["scale"] = {"mode": "feet"}

    response = context.client.put(_scene_url(), json=scene)

    assert response.status_code == 422, response.text
    body = response.json()
    assert body["code"] == "scene_invalid"
    assert "scale.mode" in str(body)


def test_scene_without_scale_keeps_the_field_absent(
    scene_context: SceneContext,  # noqa: F811
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)

    saved = context.client.put(_scene_url(), json=_scene_document())

    assert saved.status_code == 200, saved.text
    assert "scale" not in saved.json()
    assert "scale" not in context.client.get(_scene_url()).json()
