from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


def _stripped(value: str, what: str) -> str:
    stripped = value.strip()
    if not stripped:
        raise ValueError(f"{what} must not be blank")
    return stripped


class ReviewWrite(BaseModel):
    model_config = ConfigDict(extra="forbid")

    listing_rating: int = Field(ge=1, le=5)
    agency_rating: int = Field(ge=1, le=5)
    comment: str | None = Field(default=None, max_length=1000)

    @field_validator("comment")
    @classmethod
    def blank_comment_is_none(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return value.strip() or None


class TextBody(BaseModel):
    """A reply or a report reason."""

    model_config = ConfigDict(extra="forbid")

    body: str = Field(max_length=1000)

    @field_validator("body")
    @classmethod
    def not_blank(cls, value: str) -> str:
        return _stripped(value, "Text")


class ReportResolution(BaseModel):
    model_config = ConfigDict(extra="forbid")

    decision: Literal["upheld", "dismissed"]


class ReviewView(BaseModel):
    """A review as shown to anyone; it never identifies the customer or the replying staff."""

    id: str
    listing_id: str
    listing_rating: int
    agency_rating: int
    comment: str | None
    verified: bool
    created_at: datetime
    updated_at: datetime
    agency_reply: str | None
    agency_reply_at: datetime | None


class StaffReviewView(ReviewView):
    reported: bool


class RatingSummaryView(BaseModel):
    average: float | None
    count: int
    verified_count: int
    few_ratings: bool


class ListingReviews(BaseModel):
    listing: RatingSummaryView
    agency: RatingSummaryView
    reviews: list[ReviewView]


class AgencyReviews(BaseModel):
    agency_name: str
    summary: RatingSummaryView
    reviews: list[ReviewView]


class StaffReviews(BaseModel):
    summary: RatingSummaryView
    reviews: list[StaffReviewView]


class MyReview(BaseModel):
    can_review: bool
    # "no_conversation" or "awaiting_reply" when the customer cannot rate yet.
    reason: str | None
    review: ReviewView | None


class PlatformReport(BaseModel):
    id: str
    review_id: str
    agency_id: str
    status: str
    reason: str
    created_at: datetime
    review: ReviewView


class PlatformReports(BaseModel):
    reports: list[PlatformReport]
