"""Agency-admin endpoints that assign agents to listings (F14.6)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session, sessionmaker

from app.core.errors import ERROR_RESPONSES
from app.modules.catalog.models import Listing
from app.modules.chat.models import ListingAgent
from app.modules.chat.schemas import ListingAgentsResponse, ListingAgentsUpdate
from app.modules.identity.models import StaffAccount
from app.modules.identity.session import ActiveStaff, get_active_staff

router = APIRouter(
    prefix="/api/v1/staff/agencies",
    tags=["listing-agents"],
    responses=ERROR_RESPONSES,
)


def _require_same_tenant_agency_admin(staff: ActiveStaff, agency_id: str) -> None:
    if staff["role"] != "agency_admin" or staff["tenant_id"] != agency_id:
        raise HTTPException(
            status_code=403, detail="Agency-admin access to this agency is required"
        )


def _assigned_agents(session: Session, listing_id: str) -> list[dict[str, object]]:
    rows = (
        session.query(StaffAccount.id, StaffAccount.email, StaffAccount.active)
        .join(ListingAgent, ListingAgent.agent_id == StaffAccount.id)
        .filter(ListingAgent.listing_id == listing_id)
        .order_by(StaffAccount.email)
        .all()
    )
    return [{"id": agent_id, "email": email, "active": active} for agent_id, email, active in rows]


def _require_listing(session: Session, agency_id: str, listing_id: str) -> None:
    exists = (
        session.query(Listing.id)
        .filter(Listing.id == listing_id, Listing.agency_id == agency_id)
        .first()
    )
    if exists is None:
        raise HTTPException(status_code=404, detail="Listing not found")


@router.get(
    "/{agency_id}/listings/{listing_id}/agents",
    response_model=ListingAgentsResponse,
    operation_id="list_listing_agents",
)
def list_listing_agents(
    agency_id: str,
    listing_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, object]:
    _require_same_tenant_agency_admin(staff, agency_id)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        _require_listing(session, agency_id, listing_id)
        return {"agents": _assigned_agents(session, listing_id)}


@router.put(
    "/{agency_id}/listings/{listing_id}/agents",
    response_model=ListingAgentsResponse,
    operation_id="replace_listing_agents",
)
def replace_listing_agents(
    agency_id: str,
    listing_id: str,
    body: ListingAgentsUpdate,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, object]:
    _require_same_tenant_agency_admin(staff, agency_id)
    wanted = list(dict.fromkeys(body.agent_ids))
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    now = request.app.state.clock()
    with session_factory.begin() as session:
        _require_listing(session, agency_id, listing_id)
        valid = {
            agent_id
            for (agent_id,) in session.query(StaffAccount.id).filter(
                StaffAccount.id.in_(wanted),
                StaffAccount.role == "agent",
                StaffAccount.tenant_id == agency_id,
                StaffAccount.active.is_(True),
            )
        }
        if valid != set(wanted):
            raise HTTPException(
                status_code=422,
                detail="Every agent must be an active agent of this agency",
            )
        current = {
            agent_id
            for (agent_id,) in session.query(ListingAgent.agent_id).filter(
                ListingAgent.listing_id == listing_id
            )
        }
        for agent_id in current - valid:
            session.query(ListingAgent).filter(
                ListingAgent.listing_id == listing_id, ListingAgent.agent_id == agent_id
            ).delete(synchronize_session=False)
        for agent_id in wanted:
            if agent_id not in current:
                session.add(
                    ListingAgent(listing_id=listing_id, agent_id=agent_id, assigned_at=now)
                )
        session.flush()
        return {"agents": _assigned_agents(session, listing_id)}
