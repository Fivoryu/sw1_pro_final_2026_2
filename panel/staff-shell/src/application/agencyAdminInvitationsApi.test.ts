import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  getAgencies,
  sendAgencyAdminInvitation,
} from "./agencyAdminInvitationsApi";

beforeEach(() => {
  vi.restoreAllMocks();
});

describe("agency admin invitations API", () => {
  it("lists agencies with the current staff access token", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          agencies: [{ id: "agency-1" }],
          pagination: { limit: 50, offset: 0, total: 1 },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );

    await expect(getAgencies("staff-access")).resolves.toEqual({
      agencies: [{ id: "agency-1" }],
      pagination: { limit: 50, offset: 0, total: 1 },
    });
    expect(fetchMock).toHaveBeenCalledWith("/api/v1/agencies", {
      method: "GET",
      headers: { Authorization: "Bearer staff-access" },
    });
  });

  it("sends only the selected agency and email, never exposing invitation data", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ status: "sent" }), {
        status: 201,
        headers: { "Content-Type": "application/json" },
      }),
    );

    await expect(
      sendAgencyAdminInvitation("staff-access", "agency/1", "admin@example.test"),
    ).resolves.toEqual({ status: "sent" });
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/agencies/agency%2F1/admin-invitations",
      {
        method: "POST",
        headers: {
          Authorization: "Bearer staff-access",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ email: "admin@example.test" }),
      },
    );
  });

  it("converts HTTP failures into an API error without surfacing response secrets", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ detail: "No autorizado", token: "secret" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      }),
    );

    await expect(getAgencies("staff-access")).rejects.toMatchObject({
      name: "AgencyAdminInvitationsApiError",
      status: 403,
      message: "No autorizado",
    });
  });
});
