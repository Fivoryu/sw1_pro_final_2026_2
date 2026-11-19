"""F07 synthetic worker -> upload -> review -> persistence; no physical acceptance."""
from __future__ import annotations

import io
import sys
import zipfile
from pathlib import Path

import pytest
from test_reconstruction import Ctx, _CAPTURE  # pyright: ignore[reportMissingImports]

_WORKER = Path(__file__).resolve().parents[2] / "worker3d"
sys.path.insert(0, str(_WORKER))
sys.path.insert(0, str(_WORKER / "tests"))
import test_reconstruct_video as video  # noqa: E402  # pyright: ignore[reportMissingImports]

from app.modules.catalog.models import Listing, ListingScene  # noqa: E402


@pytest.mark.parametrize("case", ["proportional", "metric", "unknown_clock", "unconfirmed"])
def test_video_draft_survives_review_without_promoting_unverified_units(tmp_path: Path, case: str) -> None:
    model = video.make_model((0.0, 0.0, 4.0, 3.0))
    manifest = video.v2_manifest()
    manifest.update(captureId=_CAPTURE, listingId="listing-one")
    if case != "proportional":
        manifest["reference"] = {**video.floor_reference(model), "dimensionsSource": "user_confirmed"}
    if case == "unknown_clock":
        manifest["video"]["timestampSource"] = "unknown"
    if case == "unconfirmed":
        manifest["reference"].pop("dimensionsSource")
    package = video.write_v2(tmp_path, manifest, sensors=video.gravity_lines([model]))
    result = video.run(package, [model])
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as archive:
        for name in ("manifest.json", "video.mp4", "frames.jsonl", "sensors.jsonl"):
            archive.writestr(name, (package / name).read_bytes())
    context = Ctx()
    try:
        data = stream.getvalue()
        assert context.register(size=len(data)).status_code == 201
        context.storage.objects[context.row().object_key] = data
        assert context.client.post(f"{context.base()}/{_CAPTURE}/complete").status_code == 202
        job = context.row().job_id
        claim = context.claim(job).json()
        completed = context.worker(job, "complete", claim["claim_token"], {
            "sceneDraft": result.scene_draft, "warnings": result.warnings,
        })
        assert completed.status_code == 200, completed.text
        draft = context.status()["sceneDraft"]
        assert draft == result.scene_draft
        assert context.row().scene_draft == draft
        assert draft["scale"]["mode"] == ("proportional" if draft["unit"] == "arbitrary" else "metric")
        scene_url = context.base().removesuffix("/captures") + "/scene"
        saved = context.client.put(scene_url, json={**draft, "captureId": _CAPTURE})
        if case == "metric":
            assert saved.status_code == 200, saved.text
            accepted = context.client.post(f"{context.base()}/{_CAPTURE}/accept", headers={"If-Match": saved.headers["ETag"]})
            assert accepted.status_code == 200, accepted.text
            assert context.client.get(scene_url).json()["scale"] == {"mode": "metric"}
        else:
            assert saved.status_code == 422, saved.text
            assert context.client.post(f"{context.base()}/{_CAPTURE}/accept").status_code == 409
            assert context.row().accepted_at is None
            with context.session_factory() as session:
                assert session.get(ListingScene, "listing-one") is None
    finally:
        context.close()


@pytest.mark.parametrize("unit", ["meters", "arbitrary"])
def test_historical_proportional_scene_never_becomes_public(unit: str) -> None:
    from test_reconstruction import _scene  # pyright: ignore[reportMissingImports]

    context = Ctx()
    try:
        scene = {**_scene(), "unit": unit, "scale": {"mode": "proportional"}}
        with context.session_factory.begin() as session:
            listing = session.get(Listing, "listing-one")
            assert listing is not None
            listing.approval_status = "approved"
            session.add(ListingScene(listing_id=listing.id, scene=scene, updated_at=context.now))
        context.set_staff(tenant="agency-one", role="agency_admin")
        assert context.client.post(context.base().removesuffix("/captures") + "/publish").status_code == 409
        with context.session_factory.begin() as session:
            listing = session.get(Listing, "listing-one")
            assert listing is not None
            listing.is_published = True  # Historical invalid state is also fenced on public reads.
        assert context.client.get("/api/v1/listings/listing-one/scene").status_code == 404
    finally:
        context.close()
