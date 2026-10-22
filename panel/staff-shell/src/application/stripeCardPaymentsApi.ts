export interface StripeConnectStatus {
  agency_id: string;
  connected: boolean;
  details_submitted: boolean;
  charges_enabled: boolean;
  payouts_enabled: boolean;
}

export interface CardReservation {
  reservation_id: string;
  listing_id: string;
  status: string;
  deposit_amount: string | null;
  currency: string;
  payment_status: string;
  created_at: string;
  deadline_at: string;
}

export class StripeCardPaymentsApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "StripeCardPaymentsApiError";
  }
}

async function requestJson<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  if (!response.ok) {
    let message = "Stripe card-payment request failed.";
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
      // Keep the generic message when no JSON error is available.
    }
    throw new StripeCardPaymentsApiError(response.status, message);
  }
  return (await response.json()) as T;
}

function headers(accessToken: string, json = false): HeadersInit {
  return {
    Authorization: `Bearer ${accessToken}`,
    ...(json ? { "Content-Type": "application/json" } : {}),
  };
}

export function getStripeConnectStatus(
  accessToken: string,
  agencyId: string,
): Promise<StripeConnectStatus> {
  return requestJson(
    `/api/v1/staff/agencies/${encodeURIComponent(agencyId)}/stripe/connect`,
    { method: "GET", headers: headers(accessToken) },
  );
}

export async function createStripeConnectOnboardingLink(
  accessToken: string,
  agencyId: string,
): Promise<string> {
  const response = await requestJson<{ url: string }>(
    `/api/v1/staff/agencies/${encodeURIComponent(agencyId)}/stripe/connect/onboarding-link`,
    { method: "POST", headers: headers(accessToken) },
  );
  return response.url;
}

export function listCardReservations(
  accessToken: string,
  agencyId: string,
): Promise<CardReservation[]> {
  return requestJson(
    `/api/v1/staff/agencies/${encodeURIComponent(agencyId)}/reservations/card`,
    { method: "GET", headers: headers(accessToken) },
  );
}

export function decideCardReservation(
  accessToken: string,
  reservationId: string,
  action: "accept" | "reject",
): Promise<{ reservation_id: string; status: string; payment_status: string }> {
  return requestJson(
    `/api/v1/staff/reservations/${encodeURIComponent(reservationId)}/card-decision`,
    {
      method: "POST",
      headers: headers(accessToken, true),
      body: JSON.stringify({ action }),
    },
  );
}
