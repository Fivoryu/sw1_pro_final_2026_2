"""Review rules: who may rate, how ratings are weighted and how they are moderated (F14.8)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.modules.catalog.models import Listing
from app.modules.chat.models import ChatConversation, ChatMessage
from app.modules.reservations.models import Reservation
from app.modules.reviews.models import ListingReview, ReviewReport

# A customer may rate once the agency answered, or once this long passed without an answer.
RESPONSE_DEADLINE = timedelta(hours=24)
# A review from a customer with an accepted reservation weighs this much more.
VERIFIED_WEIGHT = 3
# Below this many reviews the average is not shown.
FEW_REVIEWS_BELOW = 3

NOT_ELIGIBLE_NO_CONVERSATION = "no_conversation"
NOT_ELIGIBLE_AWAITING_REPLY = "awaiting_reply"


def _as_utc(value: datetime) -> datetime:
    return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)


def not_eligible_reason(
    session: Session, *, listing_id: str, customer_id: str, now: datetime
) -> str | None:
    """None when the customer may rate this listing, otherwise why not."""
    conversation = (
        session.query(ChatConversation)
        .filter(
            ChatConversation.listing_id == listing_id,
            ChatConversation.customer_id == customer_id,
        )
        .one_or_none()
    )
    if conversation is None:
        return NOT_ELIGIBLE_NO_CONVERSATION
    answered = (
        session.query(ChatMessage.id)
        .filter(
            ChatMessage.conversation_id == conversation.id,
            ChatMessage.sender_role.in_(("agent", "admin")),
        )
        .first()
    )
    if answered is not None:
        return None
    waiting = conversation.awaiting_since
    if waiting is not None and _as_utc(now) - _as_utc(waiting) >= RESPONSE_DEADLINE:
        return None
    return NOT_ELIGIBLE_AWAITING_REPLY


def find_review(session: Session, *, listing_id: str, customer_id: str) -> ListingReview | None:
    return (
        session.query(ListingReview)
        .filter(
            ListingReview.listing_id == listing_id,
            ListingReview.customer_id == customer_id,
        )
        .one_or_none()
    )


def upsert_review(
    session: Session,
    *,
    listing: Listing,
    customer_id: str,
    listing_rating: int,
    agency_rating: int,
    comment: str | None,
    now: datetime,
) -> tuple[ListingReview, bool]:
    """Create or edit the customer's review; the bool is True when it was created."""
    review = find_review(session, listing_id=listing.id, customer_id=customer_id)
    if review is None:
        review = ListingReview(
            listing_id=listing.id,
            agency_id=listing.agency_id,
            customer_id=customer_id,
            listing_rating=listing_rating,
            agency_rating=agency_rating,
            comment=comment,
            created_at=now,
            updated_at=now,
        )
        session.add(review)
        session.flush()
        return review, True
    review.listing_rating = listing_rating
    review.agency_rating = agency_rating
    review.comment = comment
    review.updated_at = now
    session.flush()
    return review, False


def verified_pairs(
    session: Session, reviews: list[ListingReview]
) -> set[tuple[str, str]]:
    """(listing_id, customer_id) pairs among [reviews] that hold an accepted reservation."""
    if not reviews:
        return set()
    listing_ids = {r.listing_id for r in reviews}
    customer_ids = {r.customer_id for r in reviews}
    rows = (
        session.query(Reservation.listing_id, Reservation.customer_id)
        .filter(
            Reservation.status == "accepted",
            Reservation.listing_id.in_(listing_ids),
            Reservation.customer_id.in_(customer_ids),
        )
        .all()
    )
    return {(listing_id, customer_id) for listing_id, customer_id in rows}


def is_verified(review: ListingReview, verified: set[tuple[str, str]]) -> bool:
    return (review.listing_id, review.customer_id) in verified


@dataclass(frozen=True)
class RatingSummary:
    average: float | None
    count: int
    verified_count: int
    few_ratings: bool


def summarize(ratings: list[tuple[int, bool]]) -> RatingSummary:
    """Weighted average of (rating, verified); None when there are too few reviews."""
    count = len(ratings)
    verified_count = sum(1 for _, verified in ratings if verified)
    few = count < FEW_REVIEWS_BELOW
    if count == 0 or few:
        return RatingSummary(None, count, verified_count, few)
    total_weight = sum(VERIFIED_WEIGHT if verified else 1 for _, verified in ratings)
    weighted = sum(rating * (VERIFIED_WEIGHT if verified else 1) for rating, verified in ratings)
    return RatingSummary(round(weighted / total_weight, 2), count, verified_count, False)


def visible_reviews_for_listing(session: Session, listing_id: str) -> list[ListingReview]:
    return (
        session.query(ListingReview)
        .filter(ListingReview.listing_id == listing_id, ListingReview.hidden_at.is_(None))
        .order_by(ListingReview.created_at.desc(), ListingReview.id)
        .all()
    )


def visible_reviews_for_agency(session: Session, agency_id: str) -> list[ListingReview]:
    return (
        session.query(ListingReview)
        .filter(ListingReview.agency_id == agency_id, ListingReview.hidden_at.is_(None))
        .order_by(ListingReview.created_at.desc(), ListingReview.id)
        .all()
    )


def reply_to_review(
    session: Session, *, review: ListingReview, staff_id: str, body: str, now: datetime
) -> bool:
    """Record the agency's single answer; False if the review already has one."""
    if review.agency_reply is not None:
        return False
    review.agency_reply = body
    review.agency_reply_at = now
    review.agency_reply_by = staff_id
    session.flush()
    return True


def open_report_for(session: Session, review_id: str) -> ReviewReport | None:
    return (
        session.query(ReviewReport)
        .filter(ReviewReport.review_id == review_id, ReviewReport.status == "open")
        .first()
    )


def report_review(
    session: Session,
    *,
    review: ListingReview,
    staff_id: str,
    reason: str,
    now: datetime,
) -> ReviewReport | None:
    """File a report; None if the review already has an open one."""
    if open_report_for(session, review.id) is not None:
        return None
    report = ReviewReport(
        review_id=review.id,
        agency_id=review.agency_id,
        reporter_id=staff_id,
        reason=reason,
        status="open",
        created_at=now,
    )
    session.add(report)
    session.flush()
    return report


def resolve_report(
    session: Session, *, report: ReviewReport, decision: str, staff_id: str, now: datetime
) -> bool:
    """Close an open report; upholding it hides the review. False if already resolved."""
    if report.status != "open":
        return False
    report.status = decision
    report.resolved_at = now
    report.resolved_by = staff_id
    if decision == "upheld":
        review = session.get(ListingReview, report.review_id)
        if review is not None and review.hidden_at is None:
            review.hidden_at = now
    session.flush()
    return True

