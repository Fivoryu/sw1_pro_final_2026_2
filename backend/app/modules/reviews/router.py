"""Review endpoints: customers rate, anyone reads, agencies answer and report (F14.8)."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlalchemy.orm import Session, sessionmaker

from app.core.errors import ERROR_RESPONSES
from app.modules.catalog.models import Listing
from app.modules.customer_identity.session import ActiveCustomer, get_active_customer
from app.modules.identity.models import Agency
from app.modules.identity.session import ActiveStaff, get_active_staff
from app.modules.reviews import service
from app.modules.reviews.models import ListingReview, ReviewReport
from app.modules.reviews.schemas import (
    AgencyReviews,
    ListingReviews,
    MyReview,
    PlatformReport,
    PlatformReports,
    RatingSummaryView,
    ReportResolution,
    ReviewView,
    ReviewWrite,
    StaffReviews,
    StaffReviewView,
    TextBody,
)

customer_router = APIRouter(
    prefix="/api/v1/customer/reviews", tags=["customer-reviews"], responses=ERROR_RESPONSES
)
public_router = APIRouter(tags=["reviews"], responses=ERROR_RESPONSES)
staff_router = APIRouter(
    prefix="/api/v1/staff/reviews", tags=["staff-reviews"], responses=ERROR_RESPONSES
)

_Customer = Annotated[ActiveCustomer, Depends(get_active_customer)]
_Staff = Annotated[ActiveStaff, Depends(get_active_staff)]


def _factory(request: Request) -> sessionmaker[Session]:
    factory: sessionmaker[Session] = request.app.state.session_factory
    return factory


def _now(request: Request) -> datetime:
    now: datetime = request.app.state.clock()
    return now


def _not_found() -> HTTPException:
    return HTTPException(status_code=404, detail="Not found")


def _published_listing(session: Session, listing_id: str) -> Listing:
    listing = session.get(Listing, listing_id)
    if listing is None or listing.approval_status != "approved" or not listing.is_published:
        raise _not_found()
    return listing


def _view(review: ListingReview, verified: set[tuple[str, str]]) -> ReviewView:
    return ReviewView(
        id=review.id,
        listing_id=review.listing_id,
        listing_rating=review.listing_rating,
        agency_rating=review.agency_rating,
        comment=review.comment,
        verified=service.is_verified(review, verified),
        created_at=review.created_at,
        updated_at=review.updated_at,
        agency_reply=review.agency_reply,
        agency_reply_at=review.agency_reply_at,
    )


def _summary(
    reviews: list[ListingReview], verified: set[tuple[str, str]], field: Literal["listing", "agency"]
) -> RatingSummaryView:
    ratings = [
        (
            review.listing_rating if field == "listing" else review.agency_rating,
            service.is_verified(review, verified),
        )
        for review in reviews
    ]
    summary = service.summarize(ratings)
    return RatingSummaryView(
        average=summary.average,
        count=summary.count,
        verified_count=summary.verified_count,
        few_ratings=summary.few_ratings,
    )


# --------------------------------------------------------------------------- customer


@customer_router.get("/listings/{listing_id}", response_model=MyReview)
def my_review(listing_id: str, request: Request, customer: _Customer) -> MyReview:
    with _factory(request)() as session:
        _published_listing(session, listing_id)
        review = service.find_review(session, listing_id=listing_id, customer_id=customer["id"])
        reason = service.not_eligible_reason(
            session, listing_id=listing_id, customer_id=customer["id"], now=_now(request)
        )
        verified = service.verified_pairs(session, [review] if review else [])
        return MyReview(
            can_review=reason is None or review is not None,
            reason=None if review is not None else reason,
            review=_view(review, verified) if review else None,
        )


@customer_router.put("/listings/{listing_id}", response_model=ReviewView)
def write_review(
    listing_id: str,
    body: ReviewWrite,
    request: Request,
    response: Response,
    customer: _Customer,
) -> ReviewView:
    now = _now(request)
    with _factory(request).begin() as session:
        listing = _published_listing(session, listing_id)
        existing = service.find_review(session, listing_id=listing_id, customer_id=customer["id"])
        if existing is None:
            reason = service.not_eligible_reason(
                session, listing_id=listing_id, customer_id=customer["id"], now=now
            )
            if reason is not None:
                raise HTTPException(status_code=403, detail=f"Not eligible to review: {reason}")
        review, created = service.upsert_review(
            session,
            listing=listing,
            customer_id=customer["id"],
            listing_rating=body.listing_rating,
            agency_rating=body.agency_rating,
            comment=body.comment,
            now=now,
        )
        response.status_code = 201 if created else 200
        return _view(review, service.verified_pairs(session, [review]))


# --------------------------------------------------------------------------- public


@public_router.get("/api/v1/listings/{listing_id}/reviews", response_model=ListingReviews)
def listing_reviews(listing_id: str, request: Request) -> ListingReviews:
    with _factory(request)() as session:
        listing = _published_listing(session, listing_id)
        own = service.visible_reviews_for_listing(session, listing_id)
        agency_reviews = service.visible_reviews_for_agency(session, listing.agency_id)
        verified = service.verified_pairs(session, agency_reviews)
        return ListingReviews(
            listing=_summary(own, verified, "listing"),
            agency=_summary(agency_reviews, verified, "agency"),
            reviews=[_view(review, verified) for review in own],
        )


@public_router.get("/api/v1/public/agencies/{agency_id}/reviews", response_model=AgencyReviews)
def agency_reviews(agency_id: str, request: Request) -> AgencyReviews:
    with _factory(request)() as session:
        agency = session.get(Agency, agency_id)
        if agency is None:
            raise _not_found()
        reviews = service.visible_reviews_for_agency(session, agency_id)
        verified = service.verified_pairs(session, reviews)
        return AgencyReviews(
            agency_name=agency.name,
            summary=_summary(reviews, verified, "agency"),
            reviews=[_view(review, verified) for review in reviews],
        )


# --------------------------------------------------------------------------- staff


def _agency_staff(staff: ActiveStaff) -> str:
    if staff["role"] not in ("agent", "agency_admin") or staff["tenant_id"] is None:
        raise HTTPException(status_code=403, detail="Agency staff access is required")
    return staff["tenant_id"]


def _agency_admin(staff: ActiveStaff) -> str:
    if staff["role"] != "agency_admin" or staff["tenant_id"] is None:
        raise HTTPException(status_code=403, detail="Agency-admin role is required")
    return staff["tenant_id"]


def _own_review(session: Session, review_id: str, agency_id: str) -> ListingReview:
    review = session.get(ListingReview, review_id)
    # Another agency's review is indistinguishable from a missing one.
    if review is None or review.agency_id != agency_id or review.hidden_at is not None:
        raise _not_found()
    return review


@staff_router.get("", response_model=StaffReviews)
def staff_reviews(request: Request, staff: _Staff) -> StaffReviews:
    agency_id = _agency_staff(staff)
    with _factory(request)() as session:
        reviews = service.visible_reviews_for_agency(session, agency_id)
        verified = service.verified_pairs(session, reviews)
        reported = {
            review_id
            for (review_id,) in session.query(ReviewReport.review_id).filter(
                ReviewReport.agency_id == agency_id, ReviewReport.status == "open"
            )
        }
        return StaffReviews(
            summary=_summary(reviews, verified, "agency"),
            reviews=[
                StaffReviewView(**_view(r, verified).model_dump(), reported=r.id in reported)
                for r in reviews
            ],
        )


@staff_router.post("/{review_id}/reply", status_code=204)
def reply(review_id: str, body: TextBody, request: Request, staff: _Staff) -> Response:
    agency_id = _agency_admin(staff)
    with _factory(request).begin() as session:
        review = _own_review(session, review_id, agency_id)
        if not service.reply_to_review(
            session, review=review, staff_id=staff["id"], body=body.body, now=_now(request)
        ):
            raise HTTPException(status_code=409, detail="The review already has a reply")
    return Response(status_code=204)


@staff_router.post("/{review_id}/report", status_code=201)
def report(review_id: str, body: TextBody, request: Request, staff: _Staff) -> dict[str, str]:
    agency_id = _agency_admin(staff)
    with _factory(request).begin() as session:
        review = _own_review(session, review_id, agency_id)
        created = service.report_review(
            session, review=review, staff_id=staff["id"], reason=body.body, now=_now(request)
        )
        if created is None:
            raise HTTPException(status_code=409, detail="The review already has an open report")
        return {"id": created.id}


def _platform_admin(staff: ActiveStaff) -> None:
    if staff["role"] != "platform_admin":
        raise HTTPException(status_code=403, detail="Platform-admin role is required")


@staff_router.get("/reports", response_model=PlatformReports)
def list_reports(
    request: Request,
    staff: _Staff,
    status: Annotated[Literal["open", "upheld", "dismissed"], Query()] = "open",
) -> PlatformReports:
    _platform_admin(staff)
    with _factory(request)() as session:
        rows = (
            session.query(ReviewReport, ListingReview)
            .join(ListingReview, ListingReview.id == ReviewReport.review_id)
            .filter(ReviewReport.status == status)
            .order_by(ReviewReport.created_at, ReviewReport.id)
            .all()
        )
        verified = service.verified_pairs(session, [review for _, review in rows])
        return PlatformReports(
            reports=[
                PlatformReport(
                    id=report_row.id,
                    review_id=report_row.review_id,
                    agency_id=report_row.agency_id,
                    status=report_row.status,
                    reason=report_row.reason,
                    created_at=report_row.created_at,
                    review=_view(review, verified),
                )
                for report_row, review in rows
            ]
        )


@staff_router.post("/reports/{report_id}/resolve", status_code=204)
def resolve(
    report_id: str, body: ReportResolution, request: Request, staff: _Staff
) -> Response:
    _platform_admin(staff)
    with _factory(request).begin() as session:
        report_row = session.get(ReviewReport, report_id)
        if report_row is None:
            raise _not_found()
        if not service.resolve_report(
            session,
            report=report_row,
            decision=body.decision,
            staff_id=staff["id"],
            now=_now(request),
        ):
            raise HTTPException(status_code=409, detail="The report is already resolved")
    return Response(status_code=204)
