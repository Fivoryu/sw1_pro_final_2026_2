from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.modules.agencies.schemas import AgencyAdminInvitationCreate, AgencyCreate
from app.modules.identity.invitations import (
    InvitationConflictError,
    InvitationDeliveryError,
    issue_agency_admin_invitation,
)
from app.modules.identity.models import Agency
from app.modules.identity.session import ActiveStaff, get_active_staff


router = APIRouter(prefix="/api/v1/agencies", tags=["agencies"])


def _require_platform_admin(staff: ActiveStaff) -> None:
    if staff["role"] != "platform_admin":
        raise HTTPException(status_code=403, detail="Platform-admin role is required")


@router.post("", status_code=201, response_model=None)
def create_agency(
    agency: AgencyCreate,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, str]:
    _require_platform_admin(staff)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    try:
        with session_factory.begin() as session:
            session.add(Agency(id=agency.id))
            session.flush()
    except IntegrityError:
        raise HTTPException(status_code=409, detail="Agency ID already exists") from None
    return {"id": agency.id}


@router.get("", response_model=None)
def list_agencies(
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, list[dict[str, str]]]:
    _require_platform_admin(staff)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        agency_ids = session.query(Agency.id).order_by(Agency.id).all()
    return {"agencies": [{"id": agency_id} for (agency_id,) in agency_ids]}


@router.post("/{agency_id}/admin-invitations", status_code=201, response_model=None)
def create_agency_admin_invitation(
    agency_id: str,
    invitation: AgencyAdminInvitationCreate,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, str]:
    _require_platform_admin(staff)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        if session.get(Agency, agency_id) is None:
            raise HTTPException(status_code=404, detail="Agency not found")

    try:
        issue_agency_admin_invitation(
            session_factory=session_factory,
            email_sender=request.app.state.email_sender,
            email=invitation.email,
            tenant_id=agency_id,
            settings=request.app.state.settings,
            clock=request.app.state.clock,
        )
    except InvitationConflictError:
        raise HTTPException(
            status_code=409,
            detail="An account or active invitation already uses this email",
        ) from None
    except InvitationDeliveryError:
        raise HTTPException(
            status_code=502, detail="Invitation email delivery failed"
        ) from None
    return {"status": "sent"}
