import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AgencyMetricsError, fetchAgencyMetrics } from "./agencyMetricsApi";

const fetchMock = vi.fn<typeof fetch>();

const metrics = {
  listings: {
    draft: 1,
    in_review: 2,
    published: 2,
    approved_unpublished: 1,
    rejected: 1,
    total: 7,
  },
  active_quotes: 2,
  reservations: { pending: 1, accepted: 1, rejected: 0, cancelled: 1, expired: 1 },
};

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("agency metrics API", () => {
  it("reads the agency metrics with the session access token", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: vi.fn().mockResolvedValue(metrics),
    } as unknown as Response);

    const result = await fetchAgencyMetrics("volatile-access", "agency 1");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/staff/agencies/agency%201/metrics", {
      method: "GET",
      headers: { Accept: "application/json", Authorization: "Bearer volatile-access" },
    });
    expect(result).toEqual(metrics);
  });

  it("keeps the status of a rejected request", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 403,
      json: vi.fn().mockResolvedValue({ detail: "Agency-admin tenant access is required" }),
    } as unknown as Response);

    await expect(fetchAgencyMetrics("volatile-access", "agency-1")).rejects.toEqual(
      new AgencyMetricsError(403),
    );
  });
});
