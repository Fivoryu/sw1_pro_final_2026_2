"""F08.5: a human transaction, never a side effect of inference."""
from __future__ import annotations

import hashlib
import json
from decimal import Decimal
from typing import Annotated, Any, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, StrictInt, ValidationError, model_validator
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.modules.catalog.models import Listing, ListingExtra, ListingPhoto
from app.modules.catalog.router import (
    _authoring_response,  # pyright: ignore[reportPrivateUsage]
    _require_listing_editor,  # pyright: ignore[reportPrivateUsage]
)
from app.modules.catalog.schemas import ExtraPayload, ListingAuthoringRequest, ListingSceneDocument, ScenePosition
from app.modules.catalog.service import (
    InvalidSceneIntegrityError,
    _begin_sqlite_immediate,  # pyright: ignore[reportPrivateUsage]
    edit_staff_listing,
    get_listing_scene,
    list_listing_extras,
    upsert_listing_scene,
    validate_scene_integrity,
)
from app.modules.detection.models import DetectionJob, FurnitureReview
from app.modules.detection.schemas import DetectionSuggestion
from app.modules.identity.session import ActiveStaff, get_active_staff

router = APIRouter(
    prefix="/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/furniture-review",
    tags=["furniture-review"],
)


class FurniturePosition(ScenePosition):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class FurnitureItem(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: Annotated[str, Field(min_length=1, max_length=120)]
    price: Annotated[Decimal, Field(ge=0, max_digits=18, decimal_places=2)]
    width_cm: Annotated[StrictInt, Field(ge=1, le=1000000)]
    height_cm: Annotated[StrictInt, Field(ge=1, le=1000000)]
    depth_cm: Annotated[StrictInt, Field(ge=1, le=1000000)]
    position: FurniturePosition
    category: Annotated[str, Field(min_length=1, max_length=32)] | None = None
    room: Annotated[str, Field(min_length=1, max_length=32)] | None = None
    quantity: Annotated[StrictInt, Field(ge=1)] = 1


class ReviewCommand(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: UUID
    expected_offer_version: Annotated[StrictInt, Field(ge=1)]
    action: Literal["manual", "confirmed", "rejected"]
    job_id: UUID | None = None
    detection_index: Annotated[StrictInt, Field(ge=0, le=99)] | None = None
    item: FurnitureItem | None = None
    existing_extra_id: Annotated[str, Field(min_length=1, max_length=36)] | None = None

    @model_validator(mode="after")
    def valid_mode(self) -> ReviewCommand:
        if self.action == "manual":
            if self.item is None or any(v is not None for v in (self.job_id, self.detection_index, self.existing_extra_id)):
                raise ValueError("Manual inventory requires only an item")
        elif self.job_id is None or self.detection_index is None:
            raise ValueError("A detection reference is required")
        elif self.action == "rejected":
            if self.item is not None or self.existing_extra_id is not None:
                raise ValueError("Rejection cannot change inventory")
        elif (self.item is None) == (self.existing_extra_id is None):
            raise ValueError("Confirm a new item or link an existing extra, not both")
        return self


def _listing(session: Session, agency_id: str, listing_id: str, *, lock: bool = False) -> Listing:
    query = session.query(Listing).filter(Listing.id == listing_id, Listing.agency_id == agency_id)
    listing = (query.with_for_update() if lock else query).one_or_none()
    if listing is None:
        raise HTTPException(404, "Listing not found")
    return listing


def _detections(job: DetectionJob) -> list[DetectionSuggestion]:
    if job.status != "completed" or job.result is None:
        return []
    try:
        return [DetectionSuggestion.model_validate(value) for value in job.result.get("detections", [])]
    except (ValidationError, TypeError):
        return []


def _source_current(session: Session, job: DetectionJob) -> bool:
    photo = session.get(ListingPhoto, job.photo_id)
    return bool(photo and photo.agency_id == job.agency_id and photo.listing_id == job.listing_id
                and photo.status == "confirmed" and photo.object_key == job.object_key)


def _view(session: Session, listing: Listing) -> dict[str, Any]:
    history = session.query(FurnitureReview).filter(
        FurnitureReview.listing_id == listing.id, FurnitureReview.agency_id == listing.agency_id,
    ).order_by(FurnitureReview.created_at, FurnitureReview.id).all()
    decisions = {(row.job_id, row.detection_index): row for row in history if row.job_id}
    suggestions: list[dict[str, Any]] = []
    jobs = session.query(DetectionJob).filter(
        DetectionJob.listing_id == listing.id, DetectionJob.agency_id == listing.agency_id,
        DetectionJob.status == "completed",
    ).order_by(DetectionJob.created_at, DetectionJob.id).all()
    for job in jobs:
        current = _source_current(session, job)
        for index, detection in enumerate(_detections(job)):
            decision = decisions.get((job.id, index))
            suggestions.append({
                "job_id": job.id, "detection_index": index, "photo_id": job.photo_id,
                "model_id": job.model_id, **detection.model_dump(mode="json"),
                "status": decision.action if decision else ("pending" if current else "expired"),
                "extra_id": decision.extra_id if decision else None,
            })
    return {
        "listing": _authoring_response(listing, list_listing_extras(session, listing.id)).model_dump(mode="json"),
        "suggestions": suggestions,
        "history": [{
            "request_id": row.id, "job_id": row.job_id, "detection_index": row.detection_index,
            "action": row.action, "extra_id": row.extra_id, "snapshot": row.snapshot,
            "actor_id": row.actor_id, "created_at": row.created_at.isoformat(),
        } for row in history],
    }


def _scene(session: Session, listing: Listing) -> ListingSceneDocument:
    stored = get_listing_scene(session, listing.id)
    try:
        if stored is not None:
            scene = ListingSceneDocument.model_validate(stored.scene)
            validate_scene_integrity(scene)
            return scene
    except (ValidationError, InvalidSceneIntegrityError):
        pass
    raise HTTPException(409, "Save a valid scene before placing furniture")


def _add_item(
    session: Session, listing: Listing, item: FurnitureItem, staff: ActiveStaff,
    request: Request, job: DetectionJob | None,
) -> str:
    scene = _scene(session, listing)
    extras = list_listing_extras(session, listing.id)
    existing = [ExtraPayload(
        extra_id=extra.id, name=extra.name, price=extra.price, category=extra.category,
        room=extra.room, width_cm=extra.width_cm, height_cm=extra.height_cm,
        depth_cm=extra.depth_cm, origin=extra.origin, visual_reference=extra.visual_reference,
        quantity=extra.quantity,
    ) for extra in extras]
    new = ExtraPayload.model_validate({
        **item.model_dump(exclude={"position"}), "origin": "human-confirmed-ai" if job else "manual",
        "visual_reference": f"photo:{job.photo_id}" if job else None,
    })
    content = ListingAuthoringRequest.model_validate({
        **{key: getattr(listing, key) for key in (
            "operation", "base_price", "currency", "city", "zone", "bedrooms", "bathrooms",
            "description", "exact_address",
        )},
        "extras": [*existing, new],
    })
    edited = edit_staff_listing(
        session, agency_id=listing.agency_id, listing_id=listing.id, content=content,
        actor_id=staff["id"], actor_role=staff["role"], now=request.app.state.clock(),
    )
    assert edited is not None
    old_ids = {extra.id for extra in extras}
    extra_id = next(extra.id for extra in list_listing_extras(session, listing.id) if extra.id not in old_ids)
    document = scene.model_dump(mode="json", by_alias=True, exclude_unset=True)
    document["objects"].append({
        "id": extra_id, "type": "box", "color": "#8b9aab",
        "position": item.position.model_dump(),
        "dimensions": {"width": item.width_cm / 100, "height": item.height_cm / 100, "depth": item.depth_cm / 100},
    })
    validated = ListingSceneDocument.model_validate(document)
    validate_scene_integrity(validated)
    upsert_listing_scene(
        session, agency_id=listing.agency_id, listing_id=listing.id, scene=document,
        updated_at=request.app.state.clock(), updated_by=staff["id"],
    )
    return extra_id


@router.get("")
def get_furniture_review(
    agency_id: str, listing_id: str, request: Request, staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, Any]:
    _require_listing_editor(staff, agency_id)
    with request.app.state.session_factory() as session:
        return _view(session, _listing(session, agency_id, listing_id))


@router.post("")
def review_furniture(
    agency_id: str, listing_id: str, body: ReviewCommand, request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, Any]:
    _require_listing_editor(staff, agency_id)
    content = body.model_dump(mode="json", exclude={"request_id", "expected_offer_version"})
    fingerprint = hashlib.sha256(json.dumps(content, sort_keys=True).encode()).hexdigest()
    try:
        with request.app.state.session_factory.begin() as session:
            if session.get_bind().dialect.name == "sqlite":
                _begin_sqlite_immediate(session)
            listing = _listing(session, agency_id, listing_id, lock=True)
            previous = session.get(FurnitureReview, str(body.request_id))
            if previous is None and body.job_id is not None:
                previous = session.query(FurnitureReview).filter(
                    FurnitureReview.job_id == str(body.job_id),
                    FurnitureReview.detection_index == body.detection_index,
                    FurnitureReview.agency_id == agency_id,
                    FurnitureReview.listing_id == listing_id,
                ).one_or_none()
            if previous is not None:
                if previous.listing_id != listing.id or previous.agency_id != agency_id or previous.request_hash != fingerprint:
                    raise HTTPException(409, "Review already exists with different content")
                return _view(session, listing)
            if listing.offer_version != body.expected_offer_version:
                raise HTTPException(409, "The listing offer changed; reload before reviewing")
            job: DetectionJob | None = None
            snapshot: dict[str, Any] = {"item": content.get("item")}
            if body.job_id is not None:
                job = session.query(DetectionJob).filter(
                    DetectionJob.id == str(body.job_id), DetectionJob.agency_id == agency_id,
                    DetectionJob.listing_id == listing_id,
                ).one_or_none()
                if job is None:
                    raise HTTPException(404, "Detection not found")
                detections = _detections(job)
                assert body.detection_index is not None
                if body.detection_index >= len(detections):
                    raise HTTPException(404, "Detection not found")
                if not _source_current(session, job):
                    raise HTTPException(409, "The source photo is no longer available")
                snapshot.update({
                    **detections[body.detection_index].model_dump(mode="json"),
                    "model_id": job.model_id, "photo_id": job.photo_id,
                })
            extra_id = body.existing_extra_id
            if extra_id is not None:
                extra = session.query(ListingExtra).filter(
                    ListingExtra.id == extra_id, ListingExtra.listing_id == listing_id,
                ).one_or_none()
                if extra is None:
                    raise HTTPException(404, "Furniture not found")
                if not any(item.id == extra_id for item in _scene(session, listing).objects):
                    raise HTTPException(409, "The existing furniture has no linked scene object")
            elif body.item is not None:
                extra_id = _add_item(session, listing, body.item, staff, request, job)
            session.add(FurnitureReview(
                id=str(body.request_id), agency_id=agency_id, listing_id=listing_id,
                job_id=str(body.job_id) if body.job_id else None, detection_index=body.detection_index,
                action=body.action, extra_id=extra_id, request_hash=fingerprint, snapshot=snapshot,
                actor_id=staff["id"], created_at=request.app.state.clock(),
            ))
            session.flush()
            session.refresh(listing)
            return _view(session, listing)
    except IntegrityError:
        raise HTTPException(409, "A concurrent review changed this request; reload") from None
