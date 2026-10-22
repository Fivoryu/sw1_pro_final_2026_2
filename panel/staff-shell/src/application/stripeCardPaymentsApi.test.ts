import { afterEach, describe, expect, it, vi } from "vitest";
import {
  createStripeConnectOnboardingLink,
  decideCardReservation,
  getStripeConnectStatus,
  listCardReservations,
} from "./stripeCardPaymentsApi";

afterEach(() => vi.unstubAllGlobals());

describe("Stripe card-payment staff API", () => {
  it("scopes Connect onboarding and status to the selected agency", async () => {
    const fetchMock = vi.fn().mockImplementation(() =>
      Promise.resolve(
        new Response(JSON.stringify({ url: "https://connect.stripe.com/test-link" }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      ),
    );
    vi.stubGlobal("fetch", fetchMock);

    const url = await createStripeConnectOnboardingLink("staff-token", "agency/one");
    await getStripeConnectStatus("staff-token", "agency/one");

    expect(url).toBe("https://connect.stripe.com/test-link");
    expect(fetchMock.mock.calls[0][0]).toBe(
      "/api/v1/staff/agencies/agency%2Fone/stripe/connect/onboarding-link",
    );
    expect(fetchMock.mock.calls[0][1]).toMatchObject({
      method: "POST",
      headers: { Authorization: "Bearer staff-token" },
    });
    expect(fetchMock.mock.calls[1][0]).toBe(
      "/api/v1/staff/agencies/agency%2Fone/stripe/connect",
    );
  });

  it("lists and decides a card reservation with authenticated staff requests", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(JSON.stringify([]), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            reservation_id: "reservation-1",
            status: "accepted",
            payment_status: "transferred",
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      );
    vi.stubGlobal("fetch", fetchMock);

    await listCardReservations("staff-token", "agency-1");
    const decision = await decideCardReservation(
      "staff-token",
      "reservation-1",
      "accept",
    );

    expect(decision.payment_status).toBe("transferred");
    expect(fetchMock.mock.calls[0][0]).toBe(
      "/api/v1/staff/agencies/agency-1/reservations/card",
    );
    expect(fetchMock.mock.calls[1][1]).toMatchObject({
      method: "POST",
      headers: {
        Authorization: "Bearer staff-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ action: "accept" }),
    });
  });
});
