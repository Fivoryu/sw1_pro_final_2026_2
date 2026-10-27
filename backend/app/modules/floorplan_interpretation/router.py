from __future__ import annotations

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile

from app.modules.catalog.router import _require_listing_editor
from app.modules.catalog.photos import lock_staff_listing
from app.modules.floorplan_interpretation.schemas import FloorplanInterpretation
from app.modules.floorplan_interpretation.service import InvalidProviderResponse, ProviderUnavailable
from app.modules.identity.session import ActiveStaff, get_active_staff

router = APIRouter(
    prefix="/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/floorplan-interpretations",
    tags=["floorplan-interpretation"],
)


@router.post("", response_model=FloorplanInterpretation, response_model_by_alias=True)
async def interpret_floorplan(
    agency_id: str,
    listing_id: str,
    request: Request,
    image: UploadFile = File(...),
    staff: ActiveStaff = Depends(get_active_staff),
) -> FloorplanInterpretation:
    _require_listing_editor(staff, agency_id)
    with request.app.state.session_factory() as session:
        if lock_staff_listing(session, agency_id=agency_id, listing_id=listing_id) is None:
            raise HTTPException(status_code=404, detail="Listing not found")
    content_type = image.content_type or ""
    if content_type not in {"image/jpeg", "image/png", "image/webp"}:
        raise HTTPException(status_code=422, detail="Unsupported floor-plan image")
    data = await image.read(10 * 1024 * 1024 + 1)
    if not data or len(data) > 10 * 1024 * 1024:
        raise HTTPException(status_code=413 if data else 422, detail="Invalid floor-plan image")
    interpreter = request.app.state.floorplan_interpreter
    try:
        return await interpreter.interpret(image=data, content_type=content_type)
    except ProviderUnavailable as exc:
        return FloorplanInterpretation(
            status="provider_unavailable",
            warnings=["La interpretación automática no está disponible."],
            informationStillNeeded=["Corregir o trazar el ambiente manualmente."],
            retryable=exc.retryable,
        )
    except InvalidProviderResponse:
        return FloorplanInterpretation(
            status="needs_review",
            warnings=["La interpretación automática no produjo geometría válida."],
            informationStillNeeded=["Corregir o trazar el ambiente manualmente."],
        )
