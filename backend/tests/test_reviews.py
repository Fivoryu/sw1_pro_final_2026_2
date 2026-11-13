from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from app.modules.chat.models import ChatConversation
from app.modules.reservations.models import Reservation
from app.modules.reviews.models import ListingReview
from chat_support import (
    AgencyApiContext,
    assign,
    register_customer,
    seed_listing,
    seed_staff,
)

LISTING = "listing-chat"
OPEN = f"/api/v1/customer/chat/listings/{LISTING}/conversation"
MINE = f"/api/v1/customer/reviews/listings/{LISTING}"
PUBLIC = f"/api/v1/listings/{LISTING}/reviews"
STAFF = "/api/v1/staff/reviews"
RATING = {"listing_rating": 4, "agency_rating": 5, "comment": "Muy buena atención"}


def _setup(context: AgencyApiContext):
    seed_listing(context)
    admin = seed_staff(context, "admin-1", role="agency_admin")
    agent = seed_staff(context, "agent-a")
    platform = seed_staff(context, "platform-1", role="platform_admin", agency_id=None)
    assign(context, LISTING, "agent-a")
    return admin, agent, platform


def _customer(context: AgencyApiContext, email: str, *, agent=None, replied: bool = True):
    """A customer who opened a conversation; the agent answers it when [replied]."""
    customer_id, headers = register_customer(context, email)
    conversation_id = context.client.post(OPEN, headers=headers).json()["id"]
    sent = context.client.post(
        f"/api/v1/customer/chat/conversations/{conversation_id}/messages",
        json={"body": "hola"},
        headers=headers,
    )
    assert sent.status_code == 201
    if replied:
        answered = context.client.post(
            f"/api/v1/staff/chat/conversations/{conversation_id}/messages",
            json={"body": "respuesta"},
            headers=agent,
        )
        assert answered.status_code == 201
    return customer_id, headers, conversation_id


def _rate(context, headers, listing_rating=4, agency_rating=5, comment=None):
    return context.client.put(
        MINE,
        json={"listing_rating": listing_rating, "agency_rating": agency_rating, "comment": comment},
        headers=headers,
    )


def _accept_reservation(context: AgencyApiContext, customer_id: str) -> None:
    with context.session_factory.begin() as session:
        session.add(
            Reservation(
                id=f"reservation-{customer_id}",
                listing_id=LISTING,
                quote_id=f"quote-{customer_id}",
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
                idempotency_key=f"key-{customer_id}",
                request_fingerprint="a" * 64,
            )
        )


# ------------------------------------------------------------------ eligibility


def test_a_customer_without_a_conversation_cannot_rate(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _setup(context)
    _, headers = register_customer(context)

    state = context.client.get(MINE, headers=headers).json()
    refused = _rate(context, headers)

    assert state == {"can_review": False, "reason": "no_conversation", "review": None}
    assert refused.status_code == 403
    assert "no_conversation" in refused.json()["detail"]


def test_a_conversation_the_agency_answered_allows_rating(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, agent, _ = _setup(context)
    _, headers, _ = _customer(context, "c1@example.test", agent=agent)

    state = context.client.get(MINE, headers=headers).json()
    created = _rate(context, headers, 4, 5, "  Muy buena atención  ")

    assert state["can_review"] is True and state["reason"] is None
    assert created.status_code == 201
    body = created.json()
    assert (body["listing_rating"], body["agency_rating"]) == (4, 5)
    assert body["comment"] == "Muy buena atención"
    assert body["verified"] is False


def test_an_unanswered_conversation_waits_for_the_response_deadline(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _setup(context)
    _, headers, conversation_id = _customer(context, "c1@example.test", replied=False)

    too_soon = _rate(context, headers)
    assert too_soon.status_code == 403
    assert "awaiting_reply" in too_soon.json()["detail"]

    with context.session_factory.begin() as session:
        conversation = session.get(ChatConversation, conversation_id)
        assert conversation is not None
        conversation.awaiting_since = context.now - timedelta(hours=25)

    assert _rate(context, headers).status_code == 201


def test_rating_the_same_listing_again_edits_the_one_review(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, agent, _ = _setup(context)
    _, headers, _ = _customer(context, "c1@example.test", agent=agent)

    first = _rate(context, headers, 2, 2)
    second = _rate(context, headers, 5, 3, "Cambié de opinión")

    assert (first.status_code, second.status_code) == (201, 200)
    assert second.json()["id"] == first.json()["id"]
    with context.session_factory() as session:
        assert session.query(ListingReview).count() == 1
    mine = context.client.get(MINE, headers=headers).json()
    assert mine["review"]["listing_rating"] == 5


def test_ratings_outside_one_to_five_are_rejected(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, agent, _ = _setup(context)
    _, headers, _ = _customer(context, "c1@example.test", agent=agent)

    assert _rate(context, headers, 0, 3).status_code == 422
    assert _rate(context, headers, 3, 6).status_code == 422


def test_rating_requires_a_session_and_a_published_listing(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _setup(context)
    _, headers = register_customer(context)

    assert context.client.put(MINE, json=RATING).status_code == 401
    missing = context.client.get("/api/v1/customer/reviews/listings/nope", headers=headers)
    assert missing.status_code == 404


# ------------------------------------------------------------------ averages


def test_few_reviews_show_no_average_but_the_counts(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, agent, _ = _setup(context)
    for index in range(2):
        _, headers, _ = _customer(context, f"c{index}@example.test", agent=agent)
        assert _rate(context, headers, 5, 5).status_code == 201

    page = context.client.get(PUBLIC).json()

    assert page["listing"] == {
        "average": None,
        "count": 2,
        "verified_count": 0,
        "few_ratings": True,
    }
    assert len(page["reviews"]) == 2


def test_verified_reviews_weigh_more_in_the_average(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, agent, _ = _setup(context)
    ids = []
    for index, rating in enumerate((5, 1, 1)):
        customer_id, headers, _ = _customer(context, f"c{index}@example.test", agent=agent)
        assert _rate(context, headers, rating, rating).status_code == 201
        ids.append(customer_id)
    _accept_reservation(context, ids[0])

    page = context.client.get(PUBLIC).json()

    # (5*3 + 1 + 1) / (3 + 1 + 1)
    assert page["listing"]["average"] == 3.4
    assert page["agency"]["average"] == 3.4
    assert page["listing"]["count"] == 3 and page["listing"]["verified_count"] == 1
    assert [r["verified"] for r in page["reviews"]].count(True) == 1


def test_a_review_becomes_verified_when_the_customer_reserves_afterwards(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, agent, _ = _setup(context)
    customer_id, headers, _ = _customer(context, "c1@example.test", agent=agent)
    assert _rate(context, headers).json()["verified"] is False

    _accept_reservation(context, customer_id)

    assert context.client.get(MINE, headers=headers).json()["review"]["verified"] is True


def test_public_reviews_never_identify_the_customer_or_the_replying_staff(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent, _ = _setup(context)
    _, headers, _ = _customer(context, "secreto@example.test", agent=agent)
    review_id = _rate(context, headers, comment="ok").json()["id"]
    assert (
        context.client.post(f"{STAFF}/{review_id}/reply", json={"body": "Gracias"}, headers=admin)
    ).status_code == 204

    text = context.client.get(PUBLIC).text + context.client.get(
        "/api/v1/public/agencies/agency-chat/reviews"
    ).text

    assert "secreto@example.test" not in text
    assert "admin-1" not in text and "agent-a" not in text and "customer_id" not in text
    assert "Gracias" in text


def test_the_agency_page_aggregates_all_its_listings(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, agent, _ = _setup(context)
    for index in range(3):
        _, headers, _ = _customer(context, f"c{index}@example.test", agent=agent)
        _rate(context, headers, 3, 4)

    page = context.client.get("/api/v1/public/agencies/agency-chat/reviews").json()

    assert page["agency_name"] == "Casa Norte"
    assert page["summary"]["average"] == 4.0 and page["summary"]["count"] == 3
    assert context.client.get("/api/v1/public/agencies/missing/reviews").status_code == 404


# ------------------------------------------------------------------ reply and moderation


def _one_review(context, agent):
    _, headers, _ = _customer(context, "c1@example.test", agent=agent)
    return _rate(context, headers, 1, 1, "Pésimo").json()["id"]


def test_the_agency_answers_once_and_only_the_admin_can(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent, _ = _setup(context)
    review_id = _one_review(context, agent)

    by_agent = context.client.post(f"{STAFF}/{review_id}/reply", json={"body": "x"}, headers=agent)
    first = context.client.post(f"{STAFF}/{review_id}/reply", json={"body": "Lo sentimos"}, headers=admin)
    second = context.client.post(f"{STAFF}/{review_id}/reply", json={"body": "Otra"}, headers=admin)
    blank = context.client.post(f"{STAFF}/{review_id}/reply", json={"body": "  "}, headers=admin)

    assert by_agent.status_code == 403
    assert (first.status_code, second.status_code, blank.status_code) == (204, 409, 422)
    shown = context.client.get(PUBLIC).json()["reviews"][0]
    assert shown["agency_reply"] == "Lo sentimos" and shown["comment"] == "Pésimo"


def test_another_agency_cannot_answer_or_report_the_review(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    _, agent, _ = _setup(context)
    review_id = _one_review(context, agent)
    other = seed_staff(context, "admin-2", role="agency_admin", agency_id="agency-other")

    reply = context.client.post(f"{STAFF}/{review_id}/reply", json={"body": "x"}, headers=other)
    report = context.client.post(f"{STAFF}/{review_id}/report", json={"body": "x"}, headers=other)

    assert (reply.status_code, report.status_code) == (404, 404)


def test_staff_list_shows_the_agency_reviews_and_open_reports(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent, _ = _setup(context)
    review_id = _one_review(context, agent)
    context.client.post(f"{STAFF}/{review_id}/report", json={"body": "Falso"}, headers=admin)

    for headers in (admin, agent):
        page = context.client.get(STAFF, headers=headers).json()
        assert page["reviews"][0]["id"] == review_id
        assert page["reviews"][0]["reported"] is True
    assert context.client.get(STAFF).status_code == 401


def test_upholding_a_report_hides_the_review_from_averages_and_lists(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent, platform = _setup(context)
    review_id = _one_review(context, agent)
    reported = context.client.post(f"{STAFF}/{review_id}/report", json={"body": "Falso"}, headers=admin)
    assert reported.status_code == 201
    duplicate = context.client.post(f"{STAFF}/{review_id}/report", json={"body": "Otra"}, headers=admin)
    assert duplicate.status_code == 409

    queue = context.client.get(f"{STAFF}/reports", headers=platform).json()["reports"]
    assert [r["review_id"] for r in queue] == [review_id] and queue[0]["reason"] == "Falso"
    report_id = queue[0]["id"]

    resolved = context.client.post(
        f"{STAFF}/reports/{report_id}/resolve", json={"decision": "upheld"}, headers=platform
    )
    again = context.client.post(
        f"{STAFF}/reports/{report_id}/resolve", json={"decision": "dismissed"}, headers=platform
    )

    assert (resolved.status_code, again.status_code) == (204, 409)
    assert context.client.get(PUBLIC).json()["reviews"] == []
    assert context.client.get(STAFF, headers=admin).json()["reviews"] == []
    assert context.client.get(f"{STAFF}/reports", headers=platform).json()["reports"] == []


def test_dismissing_a_report_keeps_the_review(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    admin, agent, platform = _setup(context)
    review_id = _one_review(context, agent)
    context.client.post(f"{STAFF}/{review_id}/report", json={"body": "Falso"}, headers=admin)
    report_id = context.client.get(f"{STAFF}/reports", headers=platform).json()["reports"][0]["id"]

    resolved = context.client.post(
        f"{STAFF}/reports/{report_id}/resolve", json={"decision": "dismissed"}, headers=platform
    )

    assert resolved.status_code == 204
    assert len(context.client.get(PUBLIC).json()["reviews"]) == 1
    closed = context.client.get(f"{STAFF}/reports?status=dismissed", headers=platform).json()
    assert len(closed["reports"]) == 1


def test_only_the_platform_admin_resolves_and_lists_reports(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    admin, agent, platform = _setup(context)
    review_id = _one_review(context, agent)
    context.client.post(f"{STAFF}/{review_id}/report", json={"body": "Falso"}, headers=admin)

    assert context.client.get(f"{STAFF}/reports", headers=admin).status_code == 403
    assert (
        context.client.post(
            f"{STAFF}/reports/any/resolve", json={"decision": "upheld"}, headers=admin
        ).status_code
        == 403
    )
    missing = context.client.post(
        f"{STAFF}/reports/missing/resolve", json={"decision": "upheld"}, headers=platform
    )
    assert missing.status_code == 404
