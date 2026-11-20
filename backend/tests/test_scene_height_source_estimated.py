"""F07 T10: `walls[].heightSource` admits the additive value `estimated`."""

from __future__ import annotations

from test_listing_scene import (  # pyright: ignore[reportMissingImports]
    SceneContext,
    _scene_document,  # pyright: ignore[reportPrivateUsage]
    _scene_url,  # pyright: ignore[reportPrivateUsage]
    _seed_listing,  # pyright: ignore[reportPrivateUsage]
    _staff,  # pyright: ignore[reportPrivateUsage]
    scene_context,  # noqa: F401  # pyright: ignore[reportUnusedImport]
)


def test_put_accepts_and_echoes_estimated_height_source(
    scene_context: SceneContext,  # noqa: F811
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    expected = _scene_document()
    expected["walls"][0]["heightSource"] = "estimated"
    expected["walls"][1]["heightSource"] = "manual"

    saved = context.client.put(_scene_url(), json=expected)

    assert saved.status_code == 200, saved.text
    assert saved.json() == expected
    assert context.client.get(_scene_url()).json() == expected


def test_put_still_rejects_unknown_height_source(
    scene_context: SceneContext,  # noqa: F811
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)
    scene = _scene_document()
    scene["walls"][0]["heightSource"] = "laser"

    response = context.client.put(_scene_url(), json=scene)

    assert response.status_code == 422, response.text
    body = response.json()
    assert body["code"] == "scene_invalid"
    assert "walls[0].heightSource" in str(body)


def test_scene_without_height_source_keeps_the_field_absent(
    scene_context: SceneContext,  # noqa: F811
) -> None:
    context = scene_context
    _seed_listing(context)
    _staff(context)

    saved = context.client.put(_scene_url(), json=_scene_document())

    assert saved.status_code == 200, saved.text
    assert "heightSource" not in saved.json()["walls"][0]
