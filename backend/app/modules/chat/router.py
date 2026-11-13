"""HTTP endpoints for the agency chat: customer side and staff side (F14.6)."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlalchemy import or_
from sqlalchemy.orm import Session, sessionmaker

from app.core.errors import ERROR_RESPONSES
from app.modules.chat import service
from app.modules.chat.models import (
    ChatConversation,
    ChatCustomerBlock,
    ChatMessage,
    ChatReport,
    ListingAgent,
)
from app.modules.chat.schemas import (
    BlockedCustomerList,
    CustomerConversation,
    CustomerConversationList,
    CustomerMessage,
    CustomerMessagePage,
    MessageCreate,
    ReassignRequest,
    ReportCreate,
    ReportList,
    StaffConversation,
    StaffConversationList,
    StaffMessage,
    StaffMessagePage,
)
from app.modules.customer_identity.models import CustomerAccount
from app.modules.customer_identity.session import ActiveCustomer, get_active_customer
from app.modules.identity.models import StaffAccount
from app.modules.identity.session import ActiveStaff, get_active_staff

customer_router = APIRouter(
    prefix="/api/v1/customer/chat", tags=["customer-chat"], responses=ERROR_RESPONSES
)
staff_router = APIRouter(
    prefix="/api/v1/staff/chat", tags=["staff-chat"], responses=ERROR_RESPONSES
)

_Customer = Annotated[ActiveCustomer, Depends(get_active_customer)]
_Staff = Annotated[ActiveStaff, Depends(get_active_staff)]
_After = Annotated[int, Query(ge=0)]
_Limit = Annotated[int, Query(ge=1, le=100)]


def _factory(request: Request) -> sessionmaker[Session]:
    factory: sessionmaker[Session] = request.app.state.session_factory
    return factory


def _now(request: Request) -> datetime:
    now: datetime = request.app.state.clock()
    return now


def _require_agency_staff(staff: ActiveStaff) -> None:
    if staff["role"] not in ("agent", "agency_admin") or staff["tenant_id"] is None:
        raise HTTPException(status_code=403, detail="Agency staff access is required")


def _require_agency_admin(staff: ActiveStaff) -> str:
    if staff["role"] != "agency_admin" or staff["tenant_id"] is None:
        raise HTTPException(status_code=403, detail="Agency-admin role is required")
    return staff["tenant_id"]


# --------------------------------------------------------------------------- customer


def _customer_view(session: Session, conversation: ChatConversation) -> CustomerConversation:
    return CustomerConversation(
        id=conversation.id,
        listing_id=conversation.listing_id,
        agency_name=service.agency_name(session, conversation.agency_id),
        read_only=service.is_read_only(session, conversation),
        created_at=conversation.created_at,
        last_message_at=conversation.last_message_at,
    )


@customer_router.post(
    "/listings/{listing_id}/conversation",
    response_model=CustomerConversation,
    operation_id="open_customer_conversation",
)
def open_conversation(
    listing_id: str, request: Request, response: Response, customer: _Customer
) -> CustomerConversation:
    with _factory(request).begin() as session:
        conversation, created = service.get_or_create_conversation(
            session, customer_id=customer["id"], listing_id=listing_id, now=_now(request)
        )
        if service.is_blocked(
            session, agency_id=conversation.agency_id, customer_id=customer["id"]
        ):
            raise HTTPException(status_code=403, detail="This agency is not accepting messages")
        response.status_code = 201 if created else 200
        return _customer_view(session, conversation)


@customer_router.get(
    "/conversations",
    response_model=CustomerConversationList,
    operation_id="list_customer_conversations",
)
def list_customer_conversations(request: Request, customer: _Customer) -> CustomerConversationList:
    with _factory(request)() as session:
        rows = (
            session.query(ChatConversation)
            .filter(ChatConversation.customer_id == customer["id"])
            .order_by(ChatConversation.last_message_at.desc(), ChatConversation.id)
            .all()
        )
        return CustomerConversationList(
            conversations=[_customer_view(session, row) for row in rows]
        )


@customer_router.get(
    "/conversations/{conversation_id}/messages",
    response_model=CustomerMessagePage,
    operation_id="list_customer_messages",
)
def list_customer_messages(
    conversation_id: str,
    request: Request,
    customer: _Customer,
    after: _After = 0,
    limit: _Limit = 50,
) -> CustomerMessagePage:
    with _factory(request)() as session:
        conversation = service.customer_conversation(
            session, customer_id=customer["id"], conversation_id=conversation_id
        )
        rows = (
            session.query(ChatMessage)
            .filter(ChatMessage.conversation_id == conversation.id, ChatMessage.id > after)
            .order_by(ChatMessage.id)
            .limit(limit)
            .all()
        )
        return CustomerMessagePage(
            messages=[
                CustomerMessage(
                    id=row.id,
                    sender="customer" if row.sender_role == "customer" else "agency",
                    body=row.body,
                    created_at=row.created_at,
                )
                for row in rows
            ],
            read_only=service.is_read_only(session, conversation),
        )


@customer_router.post(
    "/conversations/{conversation_id}/messages",
    status_code=201,
    response_model=CustomerMessage,
    operation_id="send_customer_message",
)
def send_customer_message(
    conversation_id: str, body: MessageCreate, request: Request, customer: _Customer
) -> CustomerMessage:
    with _factory(request).begin() as session:
        conversation = service.customer_conversation(
            session, customer_id=customer["id"], conversation_id=conversation_id
        )
        if service.is_blocked(
            session, agency_id=conversation.agency_id, customer_id=customer["id"]
        ):
            raise HTTPException(status_code=403, detail="This agency is not accepting messages")
        if service.is_read_only(session, conversation):
            raise HTTPException(status_code=409, detail="Conversation is read-only")
        message = service.append_message(
            session,
            conversation,
            role="customer",
            staff_id=None,
            body=body.body,
            now=_now(request),
        )
        return CustomerMessage(
            id=message.id, sender="customer", body=message.body, created_at=message.created_at
        )


@customer_router.post(
    "/conversations/{conversation_id}/report",
    status_code=201,
    response_model=None,
    operation_id="report_customer_conversation",
)
def report_conversation_as_customer(
    conversation_id: str, body: ReportCreate, request: Request, customer: _Customer
) -> dict[str, str]:
    with _factory(request).begin() as session:
        conversation = service.customer_conversation(
            session, customer_id=customer["id"], conversation_id=conversation_id
        )
        report = ChatReport(
            conversation_id=conversation.id,
            reporter_role="customer",
            reporter_id=customer["id"],
            reason=body.body,
            created_at=_now(request),
        )
        session.add(report)
        session.flush()
        return {"id": report.id}


# --------------------------------------------------------------------------- staff


def _staff_conversation_view(
    session: Session,
    staff: ActiveStaff,
    conversation: ChatConversation,
    *,
    customer_email: str,
    now: datetime,
) -> StaffConversation:
    is_admin = staff["role"] == "agency_admin"
    return StaffConversation(
        id=conversation.id,
        listing_id=conversation.listing_id,
        customer_email=customer_email,
        status="unclaimed" if conversation.agent_id is None else "claimed",
        mine=conversation.agent_id == staff["id"],
        read_only=service.is_read_only(session, conversation),
        needs_admin=conversation.needs_admin,
        overdue=service.is_overdue(conversation, now),
        created_at=conversation.created_at,
        last_message_at=conversation.last_message_at,
        customer_id=conversation.customer_id if is_admin else None,
        agent_id=conversation.agent_id if is_admin else None,
        agent_email=service.staff_email(session, conversation.agent_id) if is_admin else None,
    )


@staff_router.get(
    "/conversations",
    response_model=StaffConversationList,
    operation_id="list_staff_conversations",
)
def list_staff_conversations(request: Request, staff: _Staff) -> StaffConversationList:
    _require_agency_staff(staff)
    now = _now(request)
    with _factory(request)() as session:
        query = (
            session.query(ChatConversation, CustomerAccount.email)
            .join(CustomerAccount, CustomerAccount.id == ChatConversation.customer_id)
            .filter(ChatConversation.agency_id == staff["tenant_id"])
        )
        if staff["role"] == "agent":
            assigned = session.query(ListingAgent.listing_id).filter(
                ListingAgent.agent_id == staff["id"]
            )
            query = query.filter(
                or_(
                    ChatConversation.agent_id == staff["id"],
                    (ChatConversation.agent_id.is_(None))
                    & ChatConversation.listing_id.in_(assigned),
                )
            )
        rows = query.order_by(
            ChatConversation.last_message_at.desc(), ChatConversation.id
        ).all()
        return StaffConversationList(
            conversations=[
                _staff_conversation_view(session, staff, conversation, customer_email=email, now=now)
                for conversation, email in rows
            ]
        )


@staff_router.get(
    "/conversations/{conversation_id}/messages",
    response_model=StaffMessagePage,
    operation_id="list_staff_messages",
)
def list_staff_messages(
    conversation_id: str,
    request: Request,
    staff: _Staff,
    after: _After = 0,
    limit: _Limit = 50,
) -> StaffMessagePage:
    _require_agency_staff(staff)
    with _factory(request)() as session:
        conversation = service.staff_conversation(
            session, staff=staff, conversation_id=conversation_id
        )
        rows = (
            session.query(ChatMessage, StaffAccount.email)
            .outerjoin(StaffAccount, StaffAccount.id == ChatMessage.sender_staff_id)
            .filter(ChatMessage.conversation_id == conversation.id, ChatMessage.id > after)
            .order_by(ChatMessage.id)
            .limit(limit)
            .all()
        )
        is_admin = staff["role"] == "agency_admin"
        return StaffMessagePage(
            messages=[
                StaffMessage(
                    id=message.id,
                    sender=message.sender_role,  # type: ignore[arg-type]
                    mine=message.sender_staff_id == staff["id"],
                    body=message.body,
                    created_at=message.created_at,
                    author_id=message.sender_staff_id if is_admin else None,
                    author_email=email if is_admin else None,
                )
                for message, email in rows
            ],
            read_only=service.is_read_only(session, conversation),
        )


@staff_router.post(
    "/conversations/{conversation_id}/messages",
    status_code=201,
    response_model=StaffMessage,
    operation_id="send_staff_message",
)
def send_staff_message(
    conversation_id: str, body: MessageCreate, request: Request, staff: _Staff
) -> StaffMessage:
    _require_agency_staff(staff)
    with _factory(request).begin() as session:
        message = service.post_staff_message(
            session,
            staff=staff,
            conversation_id=conversation_id,
            body=body.body,
            now=_now(request),
        )
        is_admin = staff["role"] == "agency_admin"
        return StaffMessage(
            id=message.id,
            sender="admin" if is_admin else "agent",
            mine=True,
            body=message.body,
            created_at=message.created_at,
            author_id=staff["id"] if is_admin else None,
            author_email=staff["email"] if is_admin else None,
        )


@staff_router.post(
    "/conversations/{conversation_id}/reassign",
    response_model=StaffConversation,
    operation_id="reassign_conversation",
)
def reassign(
    conversation_id: str, body: ReassignRequest, request: Request, staff: _Staff
) -> StaffConversation:
    tenant_id = _require_agency_admin(staff)
    with _factory(request).begin() as session:
        conversation = service.staff_conversation(
            session, staff=staff, conversation_id=conversation_id
        )
        if body.agent_id is not None:
            valid = (
                session.query(StaffAccount.id)
                .join(ListingAgent, ListingAgent.agent_id == StaffAccount.id)
                .filter(
                    StaffAccount.id == body.agent_id,
                    StaffAccount.role == "agent",
                    StaffAccount.tenant_id == tenant_id,
                    StaffAccount.active.is_(True),
                    ListingAgent.listing_id == conversation.listing_id,
                )
                .first()
            )
            if valid is None:
                raise HTTPException(
                    status_code=422,
                    detail="The agent must be active and assigned to this listing",
                )
        exclude = {conversation.agent_id} if conversation.agent_id else set()
        service.reassign_conversation(
            session,
            conversation,
            exclude=exclude,
            now=_now(request),
            new_agent_id=body.agent_id,
        )
        session.flush()
        email = session.query(CustomerAccount.email).filter(
            CustomerAccount.id == conversation.customer_id
        ).scalar()
        return _staff_conversation_view(
            session, staff, conversation, customer_email=email, now=_now(request)
        )


@staff_router.post(
    "/conversations/{conversation_id}/report",
    status_code=201,
    response_model=None,
    operation_id="report_conversation_as_staff",
)
def report_conversation_as_staff(
    conversation_id: str, body: ReportCreate, request: Request, staff: _Staff
) -> dict[str, str]:
    _require_agency_staff(staff)
    with _factory(request).begin() as session:
        conversation = service.staff_conversation(
            session, staff=staff, conversation_id=conversation_id
        )
        report = ChatReport(
            conversation_id=conversation.id,
            reporter_role="admin" if staff["role"] == "agency_admin" else "agent",
            reporter_id=staff["id"],
            reason=body.body,
            created_at=_now(request),
        )
        session.add(report)
        session.flush()
        return {"id": report.id}


@staff_router.get("/reports", response_model=ReportList, operation_id="list_chat_reports")
def list_reports(request: Request, staff: _Staff) -> ReportList:
    if staff["role"] == "agency_admin" and staff["tenant_id"] is not None:
        tenant: str | None = staff["tenant_id"]
    elif staff["role"] == "platform_admin":
        tenant = None
    else:
        raise HTTPException(status_code=403, detail="Admin role is required")
    with _factory(request)() as session:
        query = session.query(ChatReport, ChatConversation).join(
            ChatConversation, ChatConversation.id == ChatReport.conversation_id
        )
        if tenant is not None:
            query = query.filter(ChatConversation.agency_id == tenant)
        items = []
        for report, conversation in query.order_by(ChatReport.created_at.desc(), ChatReport.id):
            agent_ids = sorted(
                {
                    staff_id
                    for (staff_id,) in session.query(ChatMessage.sender_staff_id).filter(
                        ChatMessage.conversation_id == conversation.id,
                        ChatMessage.sender_staff_id.is_not(None),
                    )
                    if staff_id is not None
                }
            )
            items.append(
                {
                    "id": report.id,
                    "conversation_id": conversation.id,
                    "listing_id": conversation.listing_id,
                    "agency_id": conversation.agency_id,
                    "reporter_role": report.reporter_role,
                    "reason": report.reason,
                    "created_at": report.created_at,
                    "agent_ids": agent_ids,
                }
            )
        return ReportList.model_validate({"reports": items})


@staff_router.get("/blocks", response_model=BlockedCustomerList, operation_id="list_chat_blocks")
def list_blocks(request: Request, staff: _Staff) -> BlockedCustomerList:
    tenant_id = _require_agency_admin(staff)
    with _factory(request)() as session:
        rows = (
            session.query(ChatCustomerBlock, CustomerAccount.email)
            .join(CustomerAccount, CustomerAccount.id == ChatCustomerBlock.customer_id)
            .filter(ChatCustomerBlock.agency_id == tenant_id)
            .order_by(ChatCustomerBlock.created_at, ChatCustomerBlock.customer_id)
            .all()
        )
        return BlockedCustomerList.model_validate(
            {
                "blocked": [
                    {
                        "customer_id": row.customer_id,
                        "customer_email": email,
                        "created_at": row.created_at,
                    }
                    for row, email in rows
                ]
            }
        )


@staff_router.put(
    "/customers/{customer_id}/block",
    status_code=204,
    operation_id="block_chat_customer",
)
def block_customer(customer_id: str, request: Request, staff: _Staff) -> Response:
    tenant_id = _require_agency_admin(staff)
    with _factory(request).begin() as session:
        talked = (
            session.query(ChatConversation.id)
            .filter(
                ChatConversation.agency_id == tenant_id,
                ChatConversation.customer_id == customer_id,
            )
            .first()
        )
        if talked is None:
            raise service.not_found("Customer not found")
        if not service.is_blocked(session, agency_id=tenant_id, customer_id=customer_id):
            session.add(
                ChatCustomerBlock(
                    agency_id=tenant_id,
                    customer_id=customer_id,
                    blocked_by=staff["id"],
                    created_at=_now(request),
                )
            )
    return Response(status_code=204)


# POST rather than DELETE: the API's CORS policy allows GET, POST, PUT and PATCH only.
@staff_router.post(
    "/customers/{customer_id}/unblock",
    status_code=204,
    operation_id="unblock_chat_customer",
)
def unblock_customer(customer_id: str, request: Request, staff: _Staff) -> Response:
    tenant_id = _require_agency_admin(staff)
    with _factory(request).begin() as session:
        session.query(ChatCustomerBlock).filter(
            ChatCustomerBlock.agency_id == tenant_id,
            ChatCustomerBlock.customer_id == customer_id,
        ).delete(synchronize_session=False)
    return Response(status_code=204)
