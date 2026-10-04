export type RateCurrency = "BOB" | "USDT";

export type CurrentRateCurrency = RateCurrency | "USD";

export interface CurrentExchangeRate {
  currency: CurrentRateCurrency;
  /** Server decimal string; never recomputed here. Null when no rate is administered yet. */
  units_per_usd: string | null;
  created_at: string | null;
}

export interface CurrentExchangeRatesResponse {
  rates: CurrentExchangeRate[];
}

export interface ExchangeRateRecord {
  id: number;
  currency: CurrentRateCurrency;
  units_per_usd: string;
  created_at: string;
  created_by: string;
}

export interface ExchangeRateHistoryResponse {
  rates: ExchangeRateRecord[];
}

export interface ExchangeRateCreation {
  currency: RateCurrency;
  unitsPerUsd: string;
}

export class ExchangeRatesApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "ExchangeRatesApiError";
  }
}

const CURRENT_RATES_PATH = "/api/v1/exchange-rates/current";
const PLATFORM_RATES_PATH = "/api/v1/platform/exchange-rates";

async function requestJson<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, init);

  if (!response.ok) {
    let message = "Exchange-rate request failed.";

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
      // Retain the generic message when the server has no JSON error body.
    }

    throw new ExchangeRatesApiError(response.status, message);
  }

  return (await response.json()) as T;
}

function authorizedGet(accessToken: string): RequestInit {
  return { method: "GET", headers: { Authorization: `Bearer ${accessToken}` } };
}

export function getCurrentExchangeRates(
  accessToken: string,
): Promise<CurrentExchangeRatesResponse> {
  return requestJson<CurrentExchangeRatesResponse>(
    CURRENT_RATES_PATH,
    authorizedGet(accessToken),
  );
}

export function getExchangeRateHistory(
  accessToken: string,
): Promise<ExchangeRateHistoryResponse> {
  return requestJson<ExchangeRateHistoryResponse>(
    PLATFORM_RATES_PATH,
    authorizedGet(accessToken),
  );
}

export function createExchangeRate(
  accessToken: string,
  creation: ExchangeRateCreation,
): Promise<ExchangeRateRecord> {
  return requestJson<ExchangeRateRecord>(PLATFORM_RATES_PATH, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      currency: creation.currency,
      units_per_usd: creation.unitsPerUsd,
    }),
  });
}
