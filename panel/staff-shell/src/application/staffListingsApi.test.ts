import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  getAgencyListing,
  listAgencyListings,
  listListingTransitions,
  StaffListingsApiError,
  transitionListing,
  type StaffListing,
} from "./staffListingsApi";

const fetchMock = vi.fn<typeof fetch>();

function respondWithJson(body: unknown, status = 200) {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: vi.fn().mockResolvedValue(body),
  } as unknown as Response);
}

const listing: StaffListing = {
  listing_id: "listing-1",
  agency_id: "agency-1",
  operation: "sale",
  base_price: "350000000.00",
  currency: "BOB",
  city: "Medellín",
  zone: "El Poblado",
  bedrooms: 3,
  bathrooms: 2,
  description: "Casa de prueba",
  exact_address: "Calle privada 123",
  approval_status: "pending",
  is_published: false,
  offer_version: 1,
  created_at: "2026-10-01T12:00:00Z",
};

const bearer = { Authorization: "Bearer volatile-access" };

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("staff listings API", () => {
  it("lists an agency's listings filtered by review status with the access token", async () => {
    const page = {
      listings: [listing],
      pagination: { limit: 50, offset: 0, total: 1 },
    };
    respondWithJson(page);

    const result = await listAgencyListings("volatile-access", "agency-1", {
      status: "pending",
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/staff/agencies/agency-1/listings?status=pending&limit=50",
      { method: "GET", headers: bearer },
    );
    expect(result).toEqual(page);
  });

  it("encodes the agency id taken from the session", async () => {
    respondWithJson({ listings: [], pagination: { limit: 50, offset: 0, total: 0 } });

    await listAgencyListings("volatile-access", "agency/../1", { status: "approved" });

    expect(fetchMock.mock.calls[0][0]).toBe(
      "/api/v1/staff/agencies/agency%2F..%2F1/listings?status=approved&limit=50",
    );
  });

  it("reads one listing and its transition history", async () => {
    const history = [
      {
        id: "t-1",
        agency_id: "agency-1",
        listing_id: "listing-1",
        action: "submit",
        from_status: "draft",
        from_published: false,
        to_status: "pending",
        to_published: false,
        observation: null,
        actor_id: "agent-1",
        actor_role: "agent",
        created_at: "2026-10-01T12:05:00Z",
      },
    ];
    respondWithJson(listing);
    respondWithJson(history);

    const detail = await getAgencyListing("volatile-access", "agency-1", "listing-1");
    const transitions = await listListingTransitions(
      "volatile-access",
      "agency-1",
      "listing-1",
    );

    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      "/api/v1/staff/agencies/agency-1/listings/listing-1",
      { method: "GET", headers: bearer },
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      "/api/v1/staff/agencies/agency-1/listings/listing-1/transitions",
      { method: "GET", headers: bearer },
    );
    expect(detail).toEqual(listing);
    expect(transitions).toEqual(history);
  });

  it("posts a review transition with its observation", async () => {
    respondWithJson({ ...listing, approval_status: "rejected" });

    const result = await transitionListing(
      "volatile-access",
      "agency-1",
      "listing-1",
      "reject",
      "Faltan documentos",
    );

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/staff/agencies/agency-1/listings/listing-1/reject",
      {
        method: "POST",
        headers: { ...bearer, "Content-Type": "application/json" },
        body: JSON.stringify({ observation: "Faltan documentos" }),
      },
    );
    expect(result.approval_status).toBe("rejected");
  });

  it("posts an empty body when a transition has no observation", async () => {
    respondWithJson({ ...listing, is_published: true });

    await transitionListing("volatile-access", "agency-1", "listing-1", "publish");

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/staff/agencies/agency-1/listings/listing-1/publish",
      {
        method: "POST",
        headers: { ...bearer, "Content-Type": "application/json" },
        body: JSON.stringify({}),
      },
    );
  });

  it.each([401, 403, 404, 409])(
    "raises a typed error carrying the HTTP status %i",
    async (status) => {
      respondWithJson({ detail: "Listing cannot be changed from its current state" }, status);

      const failure = transitionListing("volatile-access", "agency-1", "listing-1", "approve");

      await expect(failure).rejects.toBeInstanceOf(StaffListingsApiError);
      await expect(failure).rejects.toMatchObject({ status });
    },
  );

  it("keeps a generic message when the error body is not JSON", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 503,
      json: vi.fn().mockRejectedValue(new SyntaxError("Unexpected token")),
    } as unknown as Response);

    await expect(
      getAgencyListing("volatile-access", "agency-1", "listing-1"),
    ).rejects.toMatchObject({ status: 503, message: "Listing request failed." });
  });

  it("lets a network failure surface unchanged", async () => {
    fetchMock.mockRejectedValueOnce(new TypeError("Failed to fetch"));

    await expect(
      listAgencyListings("volatile-access", "agency-1", { status: "pending" }),
    ).rejects.toBeInstanceOf(TypeError);
  });
});
