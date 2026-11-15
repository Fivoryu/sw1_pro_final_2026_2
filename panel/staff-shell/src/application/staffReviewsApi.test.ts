import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  listReviewReports,
  listReviews,
  replyToReview,
  reportReview,
  resolveReviewReport,
  StaffReviewsApiError,
} from "./staffReviewsApi";

const fetchMock = vi.fn<typeof fetch>();

function respond(body: unknown, status = 200) {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: vi.fn().mockResolvedValue(body),
  } as unknown as Response);
}

const bearer = { Authorization: "Bearer volatile-access" };
const jsonHeaders = { ...bearer, "Content-Type": "application/json" };

const review = {
  id: "r1",
  listing_id: "l1",
  listing_rating: 4,
  agency_rating: 5,
  comment: null,
  verified: true,
  created_at: "2026-11-01T10:00:00Z",
  updated_at: "2026-11-01T10:00:00Z",
  agency_reply: null,
  agency_reply_at: null,
  reported: false,
};
const summary = { average: null, count: 1, verified_count: 1, few_ratings: true };

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("staff reviews API", () => {
  it("lists reviews with the bearer token", async () => {
    respond({ summary, reviews: [review] });

    const result = await listReviews("volatile-access");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/staff/reviews", {
      method: "GET",
      headers: bearer,
    });
    expect(result.reviews).toEqual([review]);
    expect(result.summary.few_ratings).toBe(true);
  });

  it("rejects a malformed reviews payload", async () => {
    respond({ summary, reviews: [{ id: "r1" }] });
    await expect(listReviews("volatile-access")).rejects.toThrow("Unexpected reviews response.");

    respond({ reviews: [] });
    await expect(listReviews("volatile-access")).rejects.toBeInstanceOf(StaffReviewsApiError);
  });

  it("posts a reply and a report with JSON bodies and encoded ids", async () => {
    respond(null, 204);
    respond({ id: "rep1" }, 201);

    await replyToReview("volatile-access", "r/1", "Gracias");
    await reportReview("volatile-access", "r1", "Ofensiva");

    expect(fetchMock).toHaveBeenNthCalledWith(1, "/api/v1/staff/reviews/r%2F1/reply", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify({ body: "Gracias" }),
    });
    expect(fetchMock).toHaveBeenNthCalledWith(2, "/api/v1/staff/reviews/r1/report", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify({ body: "Ofensiva" }),
    });
  });

  it("lists reports by status and validates them", async () => {
    const report = {
      id: "rep1",
      review_id: "r1",
      agency_id: "a1",
      status: "open",
      reason: "Ofensiva",
      created_at: "2026-11-02T10:00:00Z",
      review,
    };
    respond({ reports: [report] });

    const result = await listReviewReports("volatile-access");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/staff/reviews/reports?status=open", {
      method: "GET",
      headers: bearer,
    });
    expect(result).toEqual([report]);

    respond({ reports: [{ ...report, status: "weird" }] });
    await expect(listReviewReports("volatile-access")).rejects.toThrow(
      "Unexpected review reports response.",
    );
  });

  it("resolves a report with the decision", async () => {
    respond(null, 204);

    await resolveReviewReport("volatile-access", "rep1", "upheld");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/staff/reviews/reports/rep1/resolve", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify({ decision: "upheld" }),
    });
  });

  it("surfaces 403 and 409 errors with the server detail", async () => {
    respond({ detail: "Forbidden" }, 403);
    await expect(listReviews("volatile-access")).rejects.toMatchObject({
      status: 403,
      message: "Forbidden",
    });

    respond({ detail: "Review already replied" }, 409);
    await expect(replyToReview("volatile-access", "r1", "x")).rejects.toMatchObject({
      status: 409,
      message: "Review already replied",
    });

    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: vi.fn().mockRejectedValue(new Error("no json")),
    } as unknown as Response);
    await expect(reportReview("volatile-access", "r1", "x")).rejects.toMatchObject({
      status: 500,
      message: "Reviews request failed.",
    });
  });
});
