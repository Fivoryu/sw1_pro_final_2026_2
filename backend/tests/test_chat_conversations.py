from __future__ import annotations

import json
from datetime import timedelta

from app.modules.chat.models import ChatConversation
from app.modules.reservations.models import Reservation
from chat_support import (
    AGENCY,
    AgencyApiContext,
    assign,
    register_customer,
    seed_listing,
    seed_staff,
)

LISTING = "listing-chat"
OPEN = f"/api/v1/customer/chat/listings/{LISTING}/conversation"
CUSTOMER = "/api/v1/customer/chat"
STAFF = "/api/v1/staff/chat"


def _setup(context: AgencyApiContext):
    seed_listing(context)
    admin = seed_staff(context, "admin-1", role="agency_admin")
    agent_a = seed_staff(context, "agent-a")
    agent_b = seed_staff(context, "agent-b")
    assign(context, LISTING, "agent-a", "agent-b")
    customer_id, customer = register_customer(context)
    opened = context.client.post(OPEN, headers=customer)
    assert opened.status_code == 201
    return admin, agent_a, agent_b, customer_id, customer, opened.json()["id"]


def _send(context, headers, conversation_id, body="hola", *, staff=False):
    base = STAFF if staff else CUSTOMER
    return context.client.post(
        f"{base}/conversations/{conversation_id}/messages", json={"body": body}, headers=headers
    )


def test_customer_opens_one_conversation_per_listing_and_sees_the_agency_name(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, _, _, _, customer, conversation_id = _setup(context)

    again = context.client.post(OPEN, headers=customer)

    assert again.status_code == 200
    assert again.json()["id"] == conversation_id
    assert again.json()["agency_name"] == "Casa Norte"
    listed = context.client.get(f"{CUSTOMER}/conversations", headers=customer).json()
    assert [c["id"] for c in listed["conversations"]] == [conversation_id]


def test_conversation_requires_a_customer_session_and_a_published_listing(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    seed_listing(context, "listing-draft", approval_status="draft", is_published=False)
    _, customer = register_customer(context)

    assert context.client.post(OPEN).status_code == 401
    seed_listing(context)
    assert context.client.post(OPEN, headers=customer).status_code == 201
    draft = context.client.post(
        f"{CUSTOMER}/listings/listing-draft/conversation", headers=customer
    )
    assert draft.status_code == 404


def test_first_agent_to_reply_takes_the_conversation_and_the_other_loses_sight_of_it(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, agent_a, agent_b, _, customer, conversation_id = _setup(context)
    _send(context, customer, conversation_id, "¿Sigue disponible?")

    for headers in (agent_a, agent_b):
        seen = context.client.get(f"{STAFF}/conversations", headers=headers).json()
        assert [c["status"] for c in seen["conversations"]] == ["unclaimed"]

    assert _send(context, agent_b, conversation_id, "Sí", staff=True).status_code == 201

    a_list = context.client.get(f"{STAFF}/conversations", headers=agent_a).json()
    b_list = context.client.get(f"{STAFF}/conversations", headers=agent_b).json()
    assert a_list["conversations"] == []
    assert [c["mine"] for c in b_list["conversations"]] == [True]
    # A later reply from the loser reports that the conversation is taken.
    late = _send(context, agent_a, conversation_id, "Yo también", staff=True)
    assert late.status_code == 409
    seen_by_a = context.client.get(
        f"{STAFF}/conversations/{conversation_id}/messages", headers=agent_a
    )
    assert seen_by_a.status_code == 404


def test_only_one_of_two_simultaneous_claims_wins(agency_api_context: AgencyApiContext) -> None:
    from app.modules.chat.service import claim_conversation

    context = agency_api_context
    _, _, _, _, _, conversation_id = _setup(context)

    with context.session_factory.begin() as session:
        first = claim_conversation(session, conversation_id=conversation_id, staff_id="agent-a")
        second = claim_conversation(session, conversation_id=conversation_id, staff_id="agent-b")

    assert (first, second) == (True, False)
    with context.session_factory() as session:
        assert session.get(ChatConversation, conversation_id).agent_id == "agent-a"  # type: ignore[union-attr]


def test_customer_never_sees_the_agent_identity_but_the_admin_sees_the_author(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent_a, _, _, customer, conversation_id = _setup(context)
    _send(context, customer, conversation_id, "Hola")
    _send(context, agent_a, conversation_id, "Buenas tardes", staff=True)

    responses = [
        context.client.get(f"{CUSTOMER}/conversations/{conversation_id}/messages", headers=customer),
        context.client.get(f"{CUSTOMER}/conversations", headers=customer),
        context.client.post(OPEN, headers=customer),
    ]
    for response in responses:
        raw = json.dumps(response.json())
        assert "agent-a" not in raw
        assert "example.test" not in raw
    page = responses[0].json()
    assert [m["sender"] for m in page["messages"]] == ["customer", "agency"]

    admin_page = context.client.get(
        f"{STAFF}/conversations/{conversation_id}/messages", headers=admin
    ).json()
    assert [m["author_id"] for m in admin_page["messages"]] == [None, "agent-a"]
    assert admin_page["messages"][1]["author_email"] == "agent-a@example.test"
    agent_page = context.client.get(
        f"{STAFF}/conversations/{conversation_id}/messages", headers=agent_a
    ).json()
    assert all(m["author_id"] is None for m in agent_page["messages"])


def test_messages_are_paged_with_an_after_cursor(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    _, _, _, _, customer, conversation_id = _setup(context)
    ids = [_send(context, customer, conversation_id, f"m{i}").json()["id"] for i in range(3)]

    page = context.client.get(
        f"{CUSTOMER}/conversations/{conversation_id}/messages?after={ids[0]}", headers=customer
    ).json()

    assert [m["body"] for m in page["messages"]] == ["m1", "m2"]


def test_messages_must_not_be_blank_or_oversized(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    _, _, _, _, customer, conversation_id = _setup(context)

    assert _send(context, customer, conversation_id, "   ").status_code == 422
    assert _send(context, customer, conversation_id, "x" * 2001).status_code == 422


def test_other_customers_and_other_agencies_cannot_reach_a_conversation(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, _, _, _, customer, conversation_id = _setup(context)
    _, stranger = register_customer(context, "stranger@example.test")
    foreign_admin = seed_staff(context, "admin-x", role="agency_admin", agency_id="other-agency")
    path = f"/conversations/{conversation_id}/messages"

    assert context.client.get(CUSTOMER + path, headers=stranger).status_code == 404
    assert _send(context, stranger, conversation_id).status_code == 404
    assert context.client.get(STAFF + path, headers=foreign_admin).status_code == 404
    assert context.client.get(f"{STAFF}/conversations", headers=foreign_admin).json() == {
        "conversations": []
    }
    assert context.client.get(STAFF + path, headers=admin).status_code == 200


def test_deactivating_the_owner_moves_conversations_to_the_least_loaded_agent(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent_a, agent_b, _, customer, conversation_id = _setup(context)
    seed_staff(context, "agent-c")
    assign(context, LISTING, "agent-c")
    _send(context, customer, conversation_id, "Hola")
    _send(context, agent_a, conversation_id, "Hola, soy la agencia", staff=True)
    # agent-b already owns another conversation, so agent-c is the least loaded.
    seed_listing(context, "listing-two")
    assign(context, "listing-two", "agent-b")
    with context.session_factory.begin() as session:
        session.add(
            ChatConversation(
                listing_id="listing-two",
                agency_id=AGENCY,
                customer_id=_customer_of(context, conversation_id),
                agent_id="agent-b",
                created_at=context.now,
            )
        )

    response = context.client.post("/api/v1/agencies/agents/agent-a/deactivate", headers=admin)

    assert response.status_code == 200
    with context.session_factory() as session:
        conversation = session.get(ChatConversation, conversation_id)
        assert conversation is not None
        assert conversation.agent_id == "agent-c"
        assert conversation.needs_admin is False
    history = context.client.get(
        f"{STAFF}/conversations/{conversation_id}/messages",
        headers=seed_staff_headers(context, "agent-c"),
    ).json()
    assert [m["body"] for m in history["messages"]] == ["Hola", "Hola, soy la agencia"]
    del agent_b


def seed_staff_headers(context: AgencyApiContext, account_id: str) -> dict[str, str]:
    """Headers for an agent already seeded in the database (new session, same account)."""
    from app.core.security import create_access_token

    token = create_access_token(
        user_id=account_id,
        session_id=f"session-{account_id}",
        signing_key=context.settings.jwt_secret,
        now=context.now,
        lifetime_minutes=context.settings.access_token_minutes,
    )
    return {"Authorization": f"Bearer {token}"}


def _customer_of(context: AgencyApiContext, conversation_id: str) -> str:
    with context.session_factory() as session:
        conversation = session.get(ChatConversation, conversation_id)
        assert conversation is not None
        return conversation.customer_id


def test_conversation_goes_to_the_admin_when_no_agent_is_left(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent_a, _, _, customer, conversation_id = _setup(context)
    _send(context, agent_a, conversation_id, "Hola", staff=True)
    context.client.post("/api/v1/agencies/agents/agent-b/deactivate", headers=admin)

    context.client.post("/api/v1/agencies/agents/agent-a/deactivate", headers=admin)

    listed = context.client.get(f"{STAFF}/conversations", headers=admin).json()
    only = listed["conversations"][0]
    assert only["needs_admin"] is True and only["status"] == "unclaimed"
    # The admin can answer it, which claims it.
    assert _send(context, admin, conversation_id, "Le atiendo yo", staff=True).status_code == 201
    del customer


def test_removing_an_agent_from_the_listing_reassigns_its_conversations(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent_a, _, _, _, conversation_id = _setup(context)
    _send(context, agent_a, conversation_id, "Hola", staff=True)

    url = f"/api/v1/staff/agencies/{AGENCY}/listings/{LISTING}/agents"
    context.client.put(url, json={"agent_ids": ["agent-b"]}, headers=admin)

    with context.session_factory() as session:
        conversation = session.get(ChatConversation, conversation_id)
        assert conversation is not None and conversation.agent_id == "agent-b"


def test_admin_reassigns_manually_only_to_an_assigned_active_agent(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent_a, _, _, _, conversation_id = _setup(context)
    seed_staff(context, "agent-z")
    _send(context, agent_a, conversation_id, "Hola", staff=True)
    path = f"{STAFF}/conversations/{conversation_id}/reassign"

    assert context.client.post(path, json={"agent_id": "agent-z"}, headers=admin).status_code == 422
    ok = context.client.post(path, json={"agent_id": "agent-b"}, headers=admin)
    assert ok.status_code == 200 and ok.json()["agent_id"] == "agent-b"
    assert context.client.post(path, json={}, headers=agent_a).status_code == 403


def test_overdue_is_flagged_after_24_hours_without_an_answer(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, _, _, _, customer, conversation_id = _setup(context)
    _send(context, customer, conversation_id, "¿Alguien?")
    listed = context.client.get(f"{STAFF}/conversations", headers=admin).json()
    assert listed["conversations"][0]["overdue"] is False

    with context.session_factory.begin() as session:
        conversation = session.get(ChatConversation, conversation_id)
        assert conversation is not None
        conversation.awaiting_since = context.now - timedelta(hours=25)

    listed = context.client.get(f"{STAFF}/conversations", headers=admin).json()
    assert listed["conversations"][0]["overdue"] is True


def test_customer_and_staff_reports_reach_the_admins_with_the_agents_involved(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent_a, _, _, customer, conversation_id = _setup(context)
    platform = seed_staff(context, "root", role="platform_admin", agency_id=None)
    _send(context, agent_a, conversation_id, "Hola", staff=True)

    reported = context.client.post(
        f"{CUSTOMER}/conversations/{conversation_id}/report",
        json={"body": "Respuesta ofensiva"},
        headers=customer,
    )
    by_agent = context.client.post(
        f"{STAFF}/conversations/{conversation_id}/report",
        json={"body": "Cliente abusivo"},
        headers=agent_a,
    )

    assert reported.status_code == 201 and by_agent.status_code == 201
    for headers in (admin, platform):
        reports = context.client.get(f"{STAFF}/reports", headers=headers).json()["reports"]
        assert sorted(r["reporter_role"] for r in reports) == ["agent", "customer"]
        assert all(r["agent_ids"] == ["agent-a"] for r in reports)
    assert context.client.get(f"{STAFF}/reports", headers=agent_a).status_code == 403


def test_only_the_admin_learns_the_customer_id_needed_to_block(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent_a, _, customer_id, _, _ = _setup(context)

    as_admin = context.client.get(f"{STAFF}/conversations", headers=admin).json()
    as_agent = context.client.get(f"{STAFF}/conversations", headers=agent_a).json()

    assert as_admin["conversations"][0]["customer_id"] == customer_id
    assert as_agent["conversations"][0]["customer_id"] is None


def test_blocked_customer_cannot_write_to_that_agency_and_can_be_unblocked(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent_a, _, customer_id, customer, conversation_id = _setup(context)

    assert (
        context.client.put(f"{STAFF}/customers/{customer_id}/block", headers=agent_a).status_code
        == 403
    )
    assert (
        context.client.put(f"{STAFF}/customers/{customer_id}/block", headers=admin).status_code
        == 204
    )
    assert _send(context, customer, conversation_id).status_code == 403
    assert context.client.post(OPEN, headers=customer).status_code == 403
    blocked = context.client.get(f"{STAFF}/blocks", headers=admin).json()
    assert [b["customer_id"] for b in blocked["blocked"]] == [customer_id]
    assert blocked["blocked"][0]["customer_email"] == "customer@example.test"

    assert (
        context.client.post(f"{STAFF}/customers/{customer_id}/unblock", headers=admin).status_code
        == 204
    )
    assert _send(context, customer, conversation_id).status_code == 201


def test_conversation_is_read_only_when_unpublished_or_reserved_by_someone_else(
    agency_api_context: AgencyApiContext,
) -> None:
    from app.modules.catalog.models import Listing

    context = agency_api_context
    _, agent_a, _, customer_id, customer, conversation_id = _setup(context)
    _send(context, agent_a, conversation_id, "Hola", staff=True)

    with context.session_factory.begin() as session:
        listing = session.get(Listing, LISTING)
        assert listing is not None
        listing.is_published = False
    assert _send(context, customer, conversation_id).status_code == 409
    assert _send(context, agent_a, conversation_id, staff=True).status_code == 409
    page = context.client.get(
        f"{CUSTOMER}/conversations/{conversation_id}/messages", headers=customer
    ).json()
    assert page["read_only"] is True

    with context.session_factory.begin() as session:
        listing = session.get(Listing, LISTING)
        assert listing is not None
        listing.is_published = True
    assert _send(context, customer, conversation_id).status_code == 201
    del customer_id


def test_reservation_freezes_other_customers_but_not_the_one_who_reserved(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, agent_a, _, customer_id, customer, conversation_id = _setup(context)
    _, other = register_customer(context, "other@example.test")
    other_conversation = context.client.post(OPEN, headers=other).json()["id"]

    _reserve(context, customer_id)

    assert _send(context, customer, conversation_id).status_code == 201
    assert _send(context, agent_a, conversation_id, staff=True).status_code == 201
    assert _send(context, other, other_conversation).status_code == 409


def _reserve(context: AgencyApiContext, customer_id: str) -> None:
    from decimal import Decimal

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
                api_created_at=context.now,
                decision_deadline_at=context.now + timedelta(hours=1),
                status="accepted",
                idempotency_key="key-1",
                request_fingerprint="a" * 64,
            )
        )
