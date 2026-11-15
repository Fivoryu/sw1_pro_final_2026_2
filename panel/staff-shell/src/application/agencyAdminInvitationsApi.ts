export interface AgencySummary {
  id: string;
}

export interface AgenciesResponse {
  agencies: AgencySummary[];
  pagination: { limit: number; offset: number; total: number };
}

export interface AgencyAdminInvitationResponse {
  status: "sent";
}

export class AgencyAdminInvitationsApiError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "AgencyAdminInvitationsApiError";
  }
}

async function requestJson<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  if (!response.ok) {
    let message = "Agency administration request failed.";
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
    throw new AgencyAdminInvitationsApiError(response.status, message);
  }
  return (await response.json()) as T;
}

function authorization(accessToken: string): Record<string, string> {
  return { Authorization: `Bearer ${accessToken}` };
}

export function getAgencies(accessToken: string): Promise<AgenciesResponse> {
  return requestJson<AgenciesResponse>("/api/v1/agencies", {
    method: "GET",
    headers: authorization(accessToken),
  });
}

export function sendAgencyAdminInvitation(
  accessToken: string,
  agencyId: string,
  email: string,
): Promise<AgencyAdminInvitationResponse> {
  return requestJson<AgencyAdminInvitationResponse>(
    `/api/v1/agencies/${encodeURIComponent(agencyId)}/admin-invitations`,
    {
      method: "POST",
      headers: {
        ...authorization(accessToken),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email }),
    },
  );
}
