import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  createExchangeRate,
  ExchangeRatesApiError,
  getCurrentExchangeRates,
  getExchangeRateHistory,
  type ExchangeRateRecord,
} from "./exchangeRatesApi";

const fetchMock = vi.fn<typeof fetch>();

function respondWithJson(body: unknown, status = 200) {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: vi.fn().mockResolvedValue(body),
  } as unknown as Response);
}

const bearer = { Authorization: "Bearer volatile-access" };

const currentRates = {
  rates: [
    { currency: "BOB", units_per_usd: "6.96000000", created_at: "2026-10-03T12:00:00Z" },
    { currency: "USD", units_per_usd: "1.00000000", created_at: null },
    { currency: "USDT", units_per_usd: null, created_at: null },
  ],
};

const rateRecord: ExchangeRateRecord = {
  id: 1,
  currency: "BOB",
  units_per_usd: "6.96000000",
  created_at: "2026-10-03T12:00:00Z",
  created_by: "550e8400-e29b-41d4-a716-446655440000",
};

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("exchange rates API", () => {
  it("reads the public current rates with the staff transport", async () => {
    respondWithJson(currentRates);

    const result = await getCurrentExchangeRates("volatile-access");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/exchange-rates/current", {
      method: "GET",
      headers: bearer,
    });
    expect(result).toEqual(currentRates);
  });

  it("reads the platform rate history with the access token", async () => {
    respondWithJson({ rates: [rateRecord] });

    const result = await getExchangeRateHistory("volatile-access");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/platform/exchange-rates", {
      method: "GET",
      headers: bearer,
    });
    expect(result).toEqual({ rates: [rateRecord] });
  });

  it("creates a rate with the server envelope fields and returns the record", async () => {
    respondWithJson(rateRecord, 201);

    const result = await createExchangeRate("volatile-access", {
      currency: "BOB",
      unitsPerUsd: "6.96",
    });

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/platform/exchange-rates", {
      method: "POST",
      headers: { ...bearer, "Content-Type": "application/json" },
      body: JSON.stringify({ currency: "BOB", units_per_usd: "6.96" }),
    });
    expect(result).toEqual(rateRecord);
  });

  it.each([401, 403, 422])(
    "raises a typed error carrying the HTTP status %i",
    async (status) => {
      respondWithJson({ detail: "Platform-admin role is required", code: "forbidden" }, status);

      const failure = createExchangeRate("volatile-access", {
        currency: "USDT",
        unitsPerUsd: "1.00000000",
      });

      await expect(failure).rejects.toBeInstanceOf(ExchangeRatesApiError);
      await expect(failure).rejects.toMatchObject({ status });
    },
  );

  it("keeps a generic message when the error body is not JSON", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 503,
      json: vi.fn().mockRejectedValue(new SyntaxError("Unexpected token")),
    } as unknown as Response);

    await expect(getExchangeRateHistory("volatile-access")).rejects.toMatchObject({
      status: 503,
      message: "Exchange-rate request failed.",
    });
  });

  it("lets a network failure surface unchanged", async () => {
    fetchMock.mockRejectedValueOnce(new TypeError("Failed to fetch"));

    await expect(getCurrentExchangeRates("volatile-access")).rejects.toBeInstanceOf(
      TypeError,
    );
  });
});
