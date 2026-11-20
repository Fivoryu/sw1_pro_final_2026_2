import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  createStripeConnectOnboardingLink,
  decideCardReservation,
  getStripeConnectStatus,
  listCardReservations,
} from "../../application/stripeCardPaymentsApi";
import { StripeCardPaymentsAdmin } from "./StripeCardPaymentsAdmin";

vi.mock("../../application/stripeCardPaymentsApi", async (importOriginal) => {
  const actual = await importOriginal<
    typeof import("../../application/stripeCardPaymentsApi")
  >();
  return {
    ...actual,
    createStripeConnectOnboardingLink: vi.fn(),
    decideCardReservation: vi.fn(),
    getStripeConnectStatus: vi.fn(),
    listCardReservations: vi.fn(),
  };
});

beforeEach(() => {
  vi.mocked(getStripeConnectStatus).mockReset().mockResolvedValue({
    agency_id: "agency-1",
    account_exists: true,
    connected: true,
    details_submitted: true,
    charges_enabled: false,
    payouts_enabled: true,
  });
  vi.mocked(listCardReservations).mockReset().mockResolvedValue([
    {
      reservation_id: "reservation-1",
      listing_id: "listing-1",
      status: "pending",
      deposit_amount: "10.00",
      currency: "BOB",
      payment_status: "succeeded",
      created_at: "2026-10-14T12:00:00Z",
      deadline_at: "2026-10-15T12:00:00Z",
    },
  ]);
  vi.mocked(decideCardReservation).mockResolvedValue({
    reservation_id: "reservation-1",
    status: "accepted",
    payment_status: "transferred",
  });
});

describe("StripeCardPaymentsAdmin", () => {
  it("asks for a contact email before opening Stripe for a new account", async () => {
    vi.mocked(getStripeConnectStatus).mockResolvedValue({
      agency_id: "agency-1", account_exists: false, connected: false,
      details_submitted: false, charges_enabled: false, payouts_enabled: false,
    });
    vi.mocked(createStripeConnectOnboardingLink).mockRejectedValueOnce(new Error("Stripe unavailable"));
    render(<StripeCardPaymentsAdmin accessToken="staff-token" agencyId="agency-1" />);

    const email = await screen.findByRole("textbox", { name: "Correo de contacto para Stripe" });
    const submit = screen.getByRole("button", { name: "Configurar Stripe Connect" });
    fireEvent.click(submit);
    expect(createStripeConnectOnboardingLink).not.toHaveBeenCalled();
    fireEvent.change(email, { target: { value: "finance@example.test" } });
    fireEvent.click(submit);
    expect(createStripeConnectOnboardingLink).toHaveBeenCalledWith("staff-token", "agency-1", "finance@example.test");
    expect(await screen.findByRole("alert")).toHaveTextContent("Stripe unavailable");
  });

  it("shows the agency queue and transfers a confirmed test payment on acceptance", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true);
    render(
      <StripeCardPaymentsAdmin accessToken="staff-token" agencyId="agency-1" />,
    );

    expect(await screen.findByText(/Depósito 10.00 BOB/)).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Aceptar y transferir" }));

    await waitFor(() =>
      expect(decideCardReservation).toHaveBeenCalledWith(
        "staff-token",
        "reservation-1",
        "accept",
      ),
    );
    expect(await screen.findByRole("status")).toHaveTextContent(
      "Reserva aceptada; transferencia transferred.",
    );
  });
});
