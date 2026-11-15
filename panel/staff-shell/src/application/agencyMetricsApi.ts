// panel/staff-shell/src/application/agencyMetricsApi.ts

export interface ListingMetrics {
  draft: number;
  in_review: number;
  published: number;
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

export async function fetchAgencyMetrics(
  accessToken: string,
  agencyId: string
): Promise<AgencyMetricsResponse> {
  const response = await fetch(`/api/v1/staff/agencies/${encodeURIComponent(agencyId)}/metrics`, {
    method: 'GET',
    headers: {
      'Accept': 'application/json',
      'Authorization': `Bearer ${accessToken}`
    }
  });

  if (!response.ok) {
    throw new Error('Error al obtener las métricas de la agencia');
  }

  return response.json() as Promise<AgencyMetricsResponse>;
}