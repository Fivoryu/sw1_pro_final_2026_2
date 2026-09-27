from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.core.errors import ERROR_RESPONSES

from app.modules.agencies.schemas import (
    AgencyAdminInvitationCreate,
    AgencyCreate,
    AgencyListResponse,
    AgencyWalletChallengeCreate,
    AgencyWalletChallengeResponse,
    AgencyWalletLinkRequest,
    AgencyWalletResponse,
    AgentInvitationCreate,
    AgentListResponse,
)
from app.modules.agencies.service import (
    AgencyWalletAddressConflictError,
    AgencyWalletAlreadyLinkedError,
    InvalidAgencyWalletChallengeError,
    create_agency_wallet_challenge,
    verify_and_link_agency_wallet,
)
from app.modules.identity.invitations import (
    InvitationConflictError,
    InvitationDeliveryError,
    issue_agency_admin_invitation,
    issue_agent_invitation,
)
from app.modules.identity.models import Agency, StaffAccount, StaffSession
from app.modules.identity.session import ActiveStaff, get_active_staff


router = APIRouter(
    prefix="/api/v1/agencies", tags=["agencies"], responses=ERROR_RESPONSES
)
agency_wallet_router = APIRouter(
    prefix="/api/v1/staff/agencies", tags=["agency-wallets"]
)


def _require_platform_admin(staff: ActiveStaff) -> None:
    if staff["role"] != "platform_admin":
        raise HTTPException(status_code=403, detail="Platform-admin role is required")


def _require_same_tenant_agency_admin(staff: ActiveStaff, agency_id: str) -> None:
    if staff["role"] != "agency_admin" or staff["tenant_id"] != agency_id:
        raise HTTPException(status_code=403, detail="Agency-admin tenant access is required")


def _require_agency_admin(staff: ActiveStaff) -> str:
    tenant_id = staff["tenant_id"]
    if staff["role"] != "agency_admin" or tenant_id is None:
        raise HTTPException(status_code=403, detail="Agency-admin role is required")
    return tenant_id


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


@router.get("", response_model=AgencyListResponse)
def list_agencies(
    request: Request,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, object]:
    _require_platform_admin(staff)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        total = session.query(func.count(Agency.id)).scalar() or 0
        agency_ids = (
            session.query(Agency.id)
            .order_by(Agency.id)
            .offset(offset)
            .limit(limit)
            .all()
        )
    return {
        "agencies": [{"id": agency_id} for (agency_id,) in agency_ids],
        "pagination": {"limit": limit, "offset": offset, "total": total},
    }


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


@agency_wallet_router.post(
    "/{agency_id}/wallet-challenges",
    status_code=status.HTTP_201_CREATED,
    response_model=AgencyWalletChallengeResponse,
)
def create_wallet_challenge(
    agency_id: str,
    body: AgencyWalletChallengeCreate,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> AgencyWalletChallengeResponse:
    _require_same_tenant_agency_admin(staff, agency_id)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        if session.get(Agency, agency_id) is None:
            raise HTTPException(status_code=404, detail="Agency not found")

    try:
        challenge = create_agency_wallet_challenge(
            session_factory=session_factory,
            agency_id=agency_id,
            address=body.address,
            now=request.app.state.clock(),
        )
    except AgencyWalletAlreadyLinkedError:
        raise HTTPException(status_code=409, detail="Agency wallet is already linked") from None
    return AgencyWalletChallengeResponse.model_validate(challenge)


@agency_wallet_router.put(
    "/{agency_id}/wallet",
    status_code=status.HTTP_201_CREATED,
    response_model=AgencyWalletResponse,
)
def link_wallet(
    agency_id: str,
    body: AgencyWalletLinkRequest,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> AgencyWalletResponse:
    _require_same_tenant_agency_admin(staff, agency_id)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    try:
        wallet = verify_and_link_agency_wallet(
            session_factory=session_factory,
            agency_id=agency_id,
            challenge_id=body.challenge_id,
            signature=body.signature,
            now=request.app.state.clock(),
        )
    except InvalidAgencyWalletChallengeError:
        raise HTTPException(status_code=401, detail="Wallet challenge is invalid") from None
    except AgencyWalletAlreadyLinkedError:
        raise HTTPException(status_code=409, detail="Agency wallet is already linked") from None
    except AgencyWalletAddressConflictError:
        raise HTTPException(status_code=409, detail="Wallet conflict") from None
    return AgencyWalletResponse.model_validate(wallet)


@router.post("/agent-invitations", status_code=201, response_model=None)
def create_agent_invitation(
    invitation: AgentInvitationCreate,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, str]:
    tenant_id = _require_agency_admin(staff)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    try:
        issue_agent_invitation(
            session_factory=session_factory,
            email_sender=request.app.state.email_sender,
            email=invitation.email,
            tenant_id=tenant_id,
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


@router.get("/agents", response_model=AgentListResponse)
def list_agents(
    request: Request,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, object]:
    tenant_id = _require_agency_admin(staff)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        agents_query = session.query(StaffAccount).filter(
            StaffAccount.role == "agent",
            StaffAccount.tenant_id == tenant_id,
        )
        total = agents_query.count()
        agents = (
            agents_query.order_by(StaffAccount.id)
            .offset(offset)
            .limit(limit)
            .all()
        )
    return {
        "agents": [
            {"id": agent.id, "email": agent.email, "active": agent.active}
            for agent in agents
        ],
        "pagination": {"limit": limit, "offset": offset, "total": total},
    }


def _set_agent_active(
    *,
    agent_id: str,
    active: bool,
    request: Request,
    staff: ActiveStaff,
) -> dict[str, str]:
    tenant_id = _require_agency_admin(staff)
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    now = request.app.state.clock()
    with session_factory.begin() as session:
        agent = (
            session.query(StaffAccount)
            .filter(
                StaffAccount.id == agent_id,
                StaffAccount.role == "agent",
                StaffAccount.tenant_id == tenant_id,
            )
            .with_for_update()
            .one_or_none()
        )
        if agent is None:
            raise HTTPException(status_code=404, detail="Agent not found")

        agent.active = active
        if not active:
            (
                session.query(StaffSession)
                .filter(
                    StaffSession.user_id == agent.id,
                    StaffSession.revoked_at.is_(None),
                )
                .update(
                    {StaffSession.revoked_at: now},
                    synchronize_session=False,
                )
            )
    return {"status": "activated" if active else "deactivated"}


@router.post("/agents/{agent_id}/deactivate", response_model=None)
def deactivate_agent(
    agent_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, str]:
    return _set_agent_active(
        agent_id=agent_id,
        active=False,
        request=request,
        staff=staff,
    )


@router.post("/agents/{agent_id}/activate", response_model=None)
def activate_agent(
    agent_id: str,
    request: Request,
    staff: ActiveStaff = Depends(get_active_staff),
) -> dict[str, str]:
    return _set_agent_active(
        agent_id=agent_id,
        active=True,
        request=request,
        staff=staff,
    )
