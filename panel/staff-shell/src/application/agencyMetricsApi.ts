// panel/staff-shell/src/application/agencyMetricsApi.ts

/** Listings of the agency by review state; every listing is in exactly one bucket. */
export interface ListingMetrics {
  draft: number;
  in_review: number;
  published: number;
  approved_unpublished: number;
  rejected: number;
  total: number;
}

export interface ReservationMetrics {
  pending: number;
  accepted: number;
  rejected: number;
  cancelled: number;
  expired: number;
}

export interface AgencyMetricsResponse {
  listings: ListingMetrics;
  active_quotes: number;
  reservations: ReservationMetrics;
}

/** A rejected metrics request; the status tells a forbidden read from a failure. */
export class AgencyMetricsError extends Error {
  constructor(readonly status: number) {
    super("Agency metrics request failed.");
    this.name = "AgencyMetricsError";
  }
}

export async function fetchAgencyMetrics(
  accessToken: string,
  agencyId: string,
): Promise<AgencyMetricsResponse> {
  const response = await fetch(`/api/v1/staff/agencies/${encodeURIComponent(agencyId)}/metrics`, {
    method: "GET",
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    throw new AgencyMetricsError(response.status);
  }

  return response.json() as Promise<AgencyMetricsResponse>;
}
