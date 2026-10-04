import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  createExchangeRate,
  ExchangeRatesApiError,
  getCurrentExchangeRates,
  getExchangeRateHistory,
  type CurrentExchangeRate,
  type CurrentExchangeRatesResponse,
  type ExchangeRateHistoryResponse,
} from "../../application/exchangeRatesApi";
import { ExchangeRatesAdmin } from "./ExchangeRatesAdmin";

vi.mock("../../application/exchangeRatesApi", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("../../application/exchangeRatesApi")>();
  return {
    ...actual,
    createExchangeRate: vi.fn(),
    getCurrentExchangeRates: vi.fn(),
    getExchangeRateHistory: vi.fn(),
  };
});

function currentRates(
  overrides: CurrentExchangeRate[] = [],
): CurrentExchangeRatesResponse {
  return {
    rates: [
      { currency: "BOB", units_per_usd: "6.96000000", created_at: "2026-10-03T12:00:00Z" },
      { currency: "USD", units_per_usd: "1.00000000", created_at: null },
      { currency: "USDT", units_per_usd: null, created_at: null },
      ...overrides,
    ],
  };
}

function history(): ExchangeRateHistoryResponse {
  return {
    rates: [
      {
        id: 2,
        currency: "USDT",
        units_per_usd: "1.00050000",
        created_at: "2026-10-04T09:30:00Z",
        created_by: "550e8400-e29b-41d4-a716-446655440000",
      },
      {
        id: 1,
        currency: "BOB",
        units_per_usd: "6.90000000",
        created_at: "2026-10-03T12:00:00Z",
        created_by: "550e8400-e29b-41d4-a716-446655440000",
      },
    ],
  };
}

function renderAdmin() {
  return render(<ExchangeRatesAdmin accessToken="volatile-access" />);
}

beforeEach(() => {
  vi.mocked(createExchangeRate).mockReset();
  vi.mocked(getCurrentExchangeRates).mockReset().mockResolvedValue(currentRates());
  vi.mocked(getExchangeRateHistory).mockReset().mockResolvedValue(history());
});

describe("ExchangeRatesAdmin", () => {
  it("shows the current rates with their effective dates and the newest-first history", async () => {
    renderAdmin();

    const currentSection = await screen.findByRole("list", { name: "Tasas vigentes" });
    expect(currentSection).toHaveTextContent("BOB 6.96000000");
    expect(currentSection).toHaveTextContent("USD 1.00000000");
    expect(within(currentSection).getByText("Sin tasa administrada")).toBeVisible();
    expect(getCurrentExchangeRates).toHaveBeenCalledWith("volatile-access");
    expect(getExchangeRateHistory).toHaveBeenCalledWith("volatile-access");

    const historyList = screen.getByRole("list", { name: "Historial de tasas" });
    const entries = within(historyList).getAllByRole("listitem");
    expect(entries).toHaveLength(2);
    expect(entries[0]).toHaveTextContent("USDT 1.00050000");
    expect(entries[1]).toHaveTextContent("BOB 6.90000000");
  });

  it.each([
    ["", "positiva"],
    ["0", "positiva"],
    ["-5", "positiva"],
    ["6.123456789", "ocho decimales"],
    ["seis", "positiva"],
  ] as const)(
    "rejects the units-per-USD value %j before contacting the server",
    async (unitsPerUsd, expectedFragment) => {
      const user = userEvent.setup();
      renderAdmin();
      await screen.findByRole("list", { name: "Tasas vigentes" });

      const field = screen.getByLabelText("Unidades por USD");
      await user.clear(field);
      if (unitsPerUsd) {
        await user.type(field, unitsPerUsd);
      }
      await user.click(screen.getByRole("button", { name: "Registrar tasa" }));

      expect(screen.getByRole("alert")).toHaveTextContent(expectedFragment);
      expect(createExchangeRate).not.toHaveBeenCalled();
    },
  );

  it("registers a rate and refreshes the current rates and the history", async () => {
    const user = userEvent.setup();
    renderAdmin();
    await screen.findByRole("list", { name: "Tasas vigentes" });

    await user.selectOptions(screen.getByLabelText("Moneda"), "USDT");
    await user.type(screen.getByLabelText("Unidades por USD"), "1.0005");
    await user.click(screen.getByRole("button", { name: "Registrar tasa" }));

    expect(createExchangeRate).toHaveBeenCalledWith("volatile-access", {
      currency: "USDT",
      unitsPerUsd: "1.0005",
    });
    expect(await screen.findByRole("status")).toHaveTextContent("Tasa registrada.");
    await waitFor(() => expect(getCurrentExchangeRates).toHaveBeenCalledTimes(2));
    await waitFor(() => expect(getExchangeRateHistory).toHaveBeenCalledTimes(2));
  });

  it("explains a platform permission rejection from the server", async () => {
    const user = userEvent.setup();
    vi.mocked(createExchangeRate).mockRejectedValue(
      new ExchangeRatesApiError(403, "Platform-admin role is required"),
    );
    renderAdmin();
    await screen.findByRole("list", { name: "Tasas vigentes" });

    await user.type(screen.getByLabelText("Unidades por USD"), "6.96");
    await user.click(screen.getByRole("button", { name: "Registrar tasa" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Tu cuenta no tiene permisos para administrar las tasas de cambio.",
    );
  });

  it("surfaces the server validation detail for an invalid rate", async () => {
    const user = userEvent.setup();
    vi.mocked(createExchangeRate).mockRejectedValue(
      new ExchangeRatesApiError(422, "The rate must be positive"),
    );
    renderAdmin();
    await screen.findByRole("list", { name: "Tasas vigentes" });

    await user.type(screen.getByLabelText("Unidades por USD"), "6.96");
    await user.click(screen.getByRole("button", { name: "Registrar tasa" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "The rate must be positive",
    );
  });

  it("asks to sign in again when the session is rejected", async () => {
    const user = userEvent.setup();
    vi.mocked(createExchangeRate).mockRejectedValue(
      new ExchangeRatesApiError(401, "Session is invalid or expired"),
    );
    renderAdmin();
    await screen.findByRole("list", { name: "Tasas vigentes" });

    await user.type(screen.getByLabelText("Unidades por USD"), "6.96");
    await user.click(screen.getByRole("button", { name: "Registrar tasa" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Tu sesión expiró. Cierra sesión y vuelve a ingresar.",
    );
  });
});
