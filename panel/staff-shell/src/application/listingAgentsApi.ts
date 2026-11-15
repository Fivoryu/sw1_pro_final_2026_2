export interface AgencyAgent {
  id: string;
  email: string;
  active: boolean;
}

export class ListingAgentsApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code?: string,
  ) {
    super(message);
    this.name = "ListingAgentsApiError";
  }
}

const AGENTS_LIMIT = 100;

async function requestJson<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  if (!response.ok) {
    let message = "Agent request failed.";
    let code: string | undefined;
    try {
      const payload: unknown = await response.json();
      if (typeof payload === "object" && payload !== null) {
        if ("detail" in payload && typeof payload.detail === "string") {
          message = payload.detail;
        }
        if ("code" in payload && typeof payload.code === "string") {
          code = payload.code;
        }
      }
    } catch {
      // Keep the generic message when the server has no JSON error body.
    }
    throw new ListingAgentsApiError(response.status, message, code);
  }
  return (await response.json()) as T;
}

function bearer(accessToken: string): Record<string, string> {
  return { Authorization: `Bearer ${accessToken}` };
}

function assignmentPath(agencyId: string, listingId: string): string {
  return `/api/v1/staff/agencies/${encodeURIComponent(agencyId)}/listings/${encodeURIComponent(listingId)}/agents`;
}

/** Agents of the admin's agency, active and inactive. */
export async function listAgencyAgents(accessToken: string): Promise<AgencyAgent[]> {
  const payload = await requestJson<{ agents: AgencyAgent[] }>(
    `/api/v1/agencies/agents?limit=${AGENTS_LIMIT}`,
    { method: "GET", headers: bearer(accessToken) },
  );
  return payload.agents;
}

export async function getListingAgents(
  accessToken: string,
  agencyId: string,
  listingId: string,
): Promise<AgencyAgent[]> {
  const payload = await requestJson<{ agents: AgencyAgent[] }>(
    assignmentPath(agencyId, listingId),
    { method: "GET", headers: bearer(accessToken) },
  );
  return payload.agents;
}

/** Replaces the whole assignment list of the listing. */
export async function putListingAgents(
  accessToken: string,
  agencyId: string,
  listingId: string,
  agentIds: string[],
): Promise<AgencyAgent[]> {
  const payload = await requestJson<{ agents: AgencyAgent[] }>(
    assignmentPath(agencyId, listingId),
    {
      method: "PUT",
      headers: { ...bearer(accessToken), "Content-Type": "application/json" },
      body: JSON.stringify({ agent_ids: agentIds }),
    },
  );
  return payload.agents;
}
