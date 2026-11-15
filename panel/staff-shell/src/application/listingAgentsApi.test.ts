import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  getListingAgents,
  ListingAgentsApiError,
  listAgencyAgents,
  putListingAgents,
} from "./listingAgentsApi";

const fetchMock = vi.fn<typeof fetch>();

function respond(body: unknown, status = 200) {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: vi.fn().mockResolvedValue(body),
  } as unknown as Response);
}

const bearer = { Authorization: "Bearer volatile-access" };
const agent = { id: "a1", email: "a1@example.test", active: true };

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("listing agents API", () => {
  it("lists the agency agents", async () => {
    respond({ agents: [agent], pagination: { limit: 100, offset: 0, total: 1 } });

    const result = await listAgencyAgents("volatile-access");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/agencies/agents?limit=100", {
      method: "GET",
      headers: bearer,
    });
    expect(result).toEqual([agent]);
  });

  it("reads the agents assigned to a listing, encoding both ids", async () => {
    respond({ agents: [agent] });

    const result = await getListingAgents("volatile-access", "agency/1", "listing 1");

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/staff/agencies/agency%2F1/listings/listing%201/agents",
      { method: "GET", headers: bearer },
    );
    expect(result).toEqual([agent]);
  });

  it("replaces the assignment with agent_ids", async () => {
    respond({ agents: [agent] });

    const result = await putListingAgents("volatile-access", "agency-1", "listing-1", ["a1"]);

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/staff/agencies/agency-1/listings/listing-1/agents",
      {
        method: "PUT",
        headers: { ...bearer, "Content-Type": "application/json" },
        body: JSON.stringify({ agent_ids: ["a1"] }),
      },
    );
    expect(result).toEqual([agent]);
  });

  it("maps API errors with status, detail and code", async () => {
    respond({ detail: "Agent is inactive", code: "validation_error" }, 422);

    const error = await putListingAgents("volatile-access", "agency-1", "listing-1", ["a1"]).catch(
      (e: unknown) => e,
    );

    expect(error).toBeInstanceOf(ListingAgentsApiError);
    expect((error as ListingAgentsApiError).status).toBe(422);
    expect((error as ListingAgentsApiError).message).toBe("Agent is inactive");
    expect((error as ListingAgentsApiError).code).toBe("validation_error");
  });
});
