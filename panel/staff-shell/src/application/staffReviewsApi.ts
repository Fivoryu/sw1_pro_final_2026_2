export interface ReviewSummary {
  average: number | null;
  count: number;
  verified_count: number;
  few_ratings: boolean;
}

export interface StaffReview {
  id: string;
  listing_id: string;
  listing_rating: number;
  agency_rating: number;
  comment: string | null;
  verified: boolean;
  created_at: string;
  updated_at: string;
  agency_reply: string | null;
  agency_reply_at: string | null;
  reported: boolean;
}

export interface StaffReviewList {
  summary: ReviewSummary;
  reviews: StaffReview[];
}

export type ReviewReportStatus = "open" | "upheld" | "dismissed";
export type ReviewReportDecision = "upheld" | "dismissed";

export interface ReviewReport {
  id: string;
  review_id: string;
  agency_id: string;
  status: ReviewReportStatus;
  reason: string;
  created_at: string;
  review: StaffReview;
}

export class StaffReviewsApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "StaffReviewsApiError";
  }
}

const BASE = "/api/v1/staff/reviews";
const STATUSES: readonly string[] = ["open", "upheld", "dismissed"];

async function request(url: string, init: RequestInit): Promise<Response> {
  const response = await fetch(url, init);
  if (!response.ok) {
    let message = "Reviews request failed.";
    try {
      const payload: unknown = await response.json();
      if (
        typeof payload === "object" &&
        payload !== null &&
        "detail" in payload &&
        typeof payload.detail === "string"
      ) {
        message = payload.detail;
      }
    } catch {
      // Keep the generic message when the server has no JSON error body.
    }
    throw new StaffReviewsApiError(response.status, message);
  }
  return response;
}

function bearer(accessToken: string): Record<string, string> {
  return { Authorization: `Bearer ${accessToken}` };
}

function jsonInit(accessToken: string, body: unknown): RequestInit {
  return {
    method: "POST",
    headers: { ...bearer(accessToken), "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function isNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isSummary(value: unknown): value is ReviewSummary {
  if (typeof value !== "object" || value === null) return false;
  const item = value as Record<string, unknown>;
  return (
    (item.average === null || isNumber(item.average)) &&
    isNumber(item.count) &&
    isNumber(item.verified_count) &&
    typeof item.few_ratings === "boolean"
  );
}

function isReview(value: unknown): value is StaffReview {
  if (typeof value !== "object" || value === null) return false;
  const item = value as Record<string, unknown>;
  return (
    typeof item.id === "string" &&
    typeof item.listing_id === "string" &&
    isNumber(item.listing_rating) &&
    isNumber(item.agency_rating) &&
    isNullableString(item.comment) &&
    typeof item.verified === "boolean" &&
    typeof item.created_at === "string" &&
    typeof item.updated_at === "string" &&
    isNullableString(item.agency_reply) &&
    isNullableString(item.agency_reply_at) &&
    typeof item.reported === "boolean"
  );
}

function isReport(value: unknown): value is ReviewReport {
  if (typeof value !== "object" || value === null) return false;
  const item = value as Record<string, unknown>;
  return (
    typeof item.id === "string" &&
    typeof item.review_id === "string" &&
    typeof item.agency_id === "string" &&
    typeof item.status === "string" &&
    STATUSES.includes(item.status) &&
    typeof item.reason === "string" &&
    typeof item.created_at === "string" &&
    isReview(item.review)
  );
}

export async function listReviews(accessToken: string): Promise<StaffReviewList> {
  const response = await request(BASE, { method: "GET", headers: bearer(accessToken) });
  const payload: unknown = await response.json();
  const candidate = payload as { summary?: unknown; reviews?: unknown } | null;
  if (
    typeof payload !== "object" ||
    candidate === null ||
    !isSummary(candidate.summary) ||
    !Array.isArray(candidate.reviews) ||
    !candidate.reviews.every(isReview)
  ) {
    throw new StaffReviewsApiError(response.status, "Unexpected reviews response.");
  }
  return payload as StaffReviewList;
}

export async function replyToReview(
  accessToken: string,
  reviewId: string,
  body: string,
): Promise<void> {
  await request(`${BASE}/${encodeURIComponent(reviewId)}/reply`, jsonInit(accessToken, { body }));
}

export async function reportReview(
  accessToken: string,
  reviewId: string,
  body: string,
): Promise<void> {
  await request(`${BASE}/${encodeURIComponent(reviewId)}/report`, jsonInit(accessToken, { body }));
}

export async function listReviewReports(
  accessToken: string,
  status: ReviewReportStatus = "open",
): Promise<ReviewReport[]> {
  const query = new URLSearchParams({ status });
  const response = await request(`${BASE}/reports?${query.toString()}`, {
    method: "GET",
    headers: bearer(accessToken),
  });
  const payload: unknown = await response.json();
  const reports = (payload as { reports?: unknown } | null)?.reports;
  if (!Array.isArray(reports) || !reports.every(isReport)) {
    throw new StaffReviewsApiError(response.status, "Unexpected review reports response.");
  }
  return reports;
}

export async function resolveReviewReport(
  accessToken: string,
  reportId: string,
  decision: ReviewReportDecision,
): Promise<void> {
  await request(
    `${BASE}/reports/${encodeURIComponent(reportId)}/resolve`,
    jsonInit(accessToken, { decision }),
  );
}
