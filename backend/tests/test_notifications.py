from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from app.modules.chat.models import ChatConversation
from app.modules.reservations.models import Reservation
from chat_support import (
    AgencyApiContext,
    assign,
    register_customer,
    seed_listing,
    seed_staff,
)

LISTING = "listing-chat"
OPEN = f"/api/v1/customer/chat/listings/{LISTING}/conversation"
CUSTOMER_CHAT = "/api/v1/customer/chat"
STAFF_CHAT = "/api/v1/staff/chat"
CUSTOMER_INBOX = "/api/v1/customer/notifications"
STAFF_INBOX = "/api/v1/staff/notifications"


def _setup(context: AgencyApiContext):
    seed_listing(context)
    admin = seed_staff(context, "admin-1", role="agency_admin")
    agent_a = seed_staff(context, "agent-a")
    agent_b = seed_staff(context, "agent-b")
    assign(context, LISTING, "agent-a", "agent-b")
    customer_id, customer = register_customer(context)
    conversation_id = context.client.post(OPEN, headers=customer).json()["id"]
    return admin, agent_a, agent_b, customer_id, customer, conversation_id


def _customer_says(context, customer, conversation_id, body="hola"):
    response = context.client.post(
        f"{CUSTOMER_CHAT}/conversations/{conversation_id}/messages",
        json={"body": body},
        headers=customer,
    )
    assert response.status_code == 201
    return response


def _staff_says(context, headers, conversation_id, body="respuesta"):
    return context.client.post(
        f"{STAFF_CHAT}/conversations/{conversation_id}/messages",
        json={"body": body},
        headers=headers,
    )


def _inbox(context, headers, *, staff: bool):
    response = context.client.get(STAFF_INBOX if staff else CUSTOMER_INBOX, headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def test_customer_message_notifies_every_assigned_agent_until_one_claims_it(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent_a, agent_b, _, customer, conversation_id = _setup(context)

    _customer_says(context, customer, conversation_id)

    for headers in (agent_a, agent_b):
        inbox = _inbox(context, headers, staff=True)
        assert inbox["unread"] == 1
        assert inbox["items"][0]["kind"] == "chat_message"
        assert inbox["items"][0]["conversation_id"] == conversation_id
    assert _inbox(context, admin, staff=True)["items"] == []

    assert _staff_says(context, agent_a, conversation_id).status_code == 201
    _customer_says(context, customer, conversation_id, "otra")

    assert _inbox(context, agent_a, staff=True)["unread"] == 2
    # agent_b lost the conversation, so the new message does not reach them.
    assert _inbox(context, agent_b, staff=True)["unread"] == 1


def test_staff_reply_notifies_the_customer_without_naming_the_agent(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, agent_a, _, _, customer, conversation_id = _setup(context)

    assert _staff_says(context, agent_a, conversation_id).status_code == 201

    inbox = _inbox(context, customer, staff=False)
    assert inbox["unread"] == 1
    item = inbox["items"][0]
    assert item["kind"] == "chat_message"
    assert item["conversation_id"] == conversation_id
    assert set(item) == {
        "id",
        "kind",
        "conversation_id",
        "reservation_id",
        "detail",
        "created_at",
        "read",
    }
    assert "agent-a" not in str(inbox) and "agent_id" not in str(inbox)


def test_a_notice_is_private_to_its_recipient(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    _, agent_a, _, _, customer, conversation_id = _setup(context)
    other_id, other = register_customer(context, "other@example.test")
    assert other_id
    _customer_says(context, customer, conversation_id)
    notice_id = _inbox(context, agent_a, staff=True)["items"][0]["id"]

    forbidden = context.client.post(f"{STAFF_INBOX}/{notice_id}/read", headers=seed_staff(
        context, "agent-x", agency_id="agency-other"
    ))
    assert forbidden.status_code == 404
    assert _inbox(context, other, staff=False)["items"] == []
    assert _inbox(context, agent_a, staff=True)["unread"] == 1


def test_mark_one_and_mark_all_read(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    _, agent_a, _, _, customer, conversation_id = _setup(context)
    _customer_says(context, customer, conversation_id, "uno")
    _customer_says(context, customer, conversation_id, "dos")
    items = _inbox(context, agent_a, staff=True)["items"]
    assert len(items) == 2

    one = context.client.post(f"{STAFF_INBOX}/{items[0]['id']}/read", headers=agent_a)
    assert one.status_code == 204
    assert _inbox(context, agent_a, staff=True)["unread"] == 1

    assert context.client.post(f"{STAFF_INBOX}/read-all", headers=agent_a).status_code == 204
    inbox = _inbox(context, agent_a, staff=True)
    assert inbox["unread"] == 0
    assert all(item["read"] for item in inbox["items"])


def test_inbox_requires_a_session(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    assert context.client.get(CUSTOMER_INBOX).status_code == 401
    assert context.client.get(STAFF_INBOX).status_code == 401


def test_platform_staff_has_no_inbox(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    platform = seed_staff(context, "platform-1", role="platform_admin", agency_id=None)
    assert context.client.get(STAFF_INBOX, headers=platform).status_code == 403


def test_reassignment_notifies_the_new_agent(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    admin, agent_a, agent_b, _, customer, conversation_id = _setup(context)
    _customer_says(context, customer, conversation_id)
    assert _staff_says(context, agent_a, conversation_id).status_code == 201

    deactivated = context.client.post(
        "/api/v1/agencies/agents/agent-a/deactivate", headers=admin
    )
    assert deactivated.status_code in (200, 204), deactivated.text

    kinds = [i["kind"] for i in _inbox(context, agent_b, staff=True)["items"]]
    assert "chat_assigned" in kinds


def test_losing_the_last_agent_notifies_the_admin(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    seed_listing(context)
    admin = seed_staff(context, "admin-1", role="agency_admin")
    seed_staff(context, "agent-a")
    assign(context, LISTING, "agent-a")
    _, customer = register_customer(context)
    conversation_id = context.client.post(OPEN, headers=customer).json()["id"]
    agent_a = seed_staff(context, "agent-a2", agency_id="agency-chat")
    assert agent_a
    with context.session_factory.begin() as session:
        session.get(ChatConversation, conversation_id).agent_id = "agent-a"

    response = context.client.post(
        "/api/v1/agencies/agents/agent-a/deactivate", headers=admin
    )
    assert response.status_code in (200, 204), response.text

    kinds = [i["kind"] for i in _inbox(context, admin, staff=True)["items"]]
    assert kinds == ["chat_needs_admin"]


def test_overdue_conversation_escalates_to_the_admin_once(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, _, _, _, customer, conversation_id = _setup(context)
    _customer_says(context, customer, conversation_id)
    assert _inbox(context, admin, staff=True)["items"] == []

    with context.session_factory.begin() as session:
        conversation = session.get(ChatConversation, conversation_id)
        conversation.awaiting_since = context.now - timedelta(hours=25)

    first = _inbox(context, admin, staff=True)
    second = _inbox(context, admin, staff=True)

    assert [i["kind"] for i in first["items"]] == ["chat_overdue"]
    assert first["items"][0]["conversation_id"] == conversation_id
    assert len(second["items"]) == 1


def test_a_conversation_waiting_less_than_a_day_does_not_escalate(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, _, _, _, customer, conversation_id = _setup(context)
    _customer_says(context, customer, conversation_id)
    with context.session_factory.begin() as session:
        conversation = session.get(ChatConversation, conversation_id)
        conversation.awaiting_since = context.now - timedelta(hours=23)

    assert _inbox(context, admin, staff=True)["items"] == []


def test_expired_reservation_notifies_customer_and_agency_admin_once(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, _, _, customer_id, customer, _ = _setup(context)
    with context.session_factory.begin() as session:
        session.add(
            Reservation(
                id="reservation-1",
                listing_id=LISTING,
                quote_id="quote-1",
                customer_id=customer_id,
                payment_method="card",
                offer_version=1,
                operation="sale",
                quote_lines=[],
                one_time_total=Decimal("1.00"),
                monthly_total=Decimal("0.00"),
                api_created_at=context.now - timedelta(days=2),
                decision_deadline_at=context.now - timedelta(hours=1),
                status="pending",
                idempotency_key="key-1",
                request_fingerprint="a" * 64,
            )
        )

    for _ in range(2):
        assert context.client.get("/api/v1/reservations", headers=customer).status_code == 200

    customer_items = _inbox(context, customer, staff=False)["items"]
    admin_items = _inbox(context, admin, staff=True)["items"]
    for items in (customer_items, admin_items):
        reservation_items = [i for i in items if i["kind"] == "reservation_status"]
        assert len(reservation_items) == 1
        assert reservation_items[0]["reservation_id"] == "reservation-1"
        assert reservation_items[0]["detail"] == "expired"
