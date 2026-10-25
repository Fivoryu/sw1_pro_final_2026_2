import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  getAgencies,
  sendAgencyAdminInvitation,
} from "../../application/agencyAdminInvitationsApi";
import { AgencyAdminInvitations } from "./AgencyAdminInvitations";

vi.mock("../../application/agencyAdminInvitationsApi", async (importOriginal) => {
  const actual = await importOriginal<
    typeof import("../../application/agencyAdminInvitationsApi")
  >();
  return {
    ...actual,
    getAgencies: vi.fn(),
    sendAgencyAdminInvitation: vi.fn(),
  };
});

beforeEach(() => {
  vi.mocked(getAgencies).mockReset();
  vi.mocked(sendAgencyAdminInvitation).mockReset();
});

describe("AgencyAdminInvitations", () => {
  it("loads agencies, accepts an email, and confirms delivery to the local outbox", async () => {
    const user = userEvent.setup();
    vi.mocked(getAgencies).mockResolvedValue({
      agencies: [{ id: "f09-demo-agency" }],
      pagination: { limit: 50, offset: 0, total: 1 },
    });
    vi.mocked(sendAgencyAdminInvitation).mockResolvedValue({ status: "sent" });

    render(<AgencyAdminInvitations accessToken="staff-access" />);

    expect(await screen.findByRole("option", { name: "f09-demo-agency" })).toBeVisible();
    await user.type(screen.getByLabelText("Correo del administrador"), "admin@example.test");
    await user.click(screen.getByRole("button", { name: "Enviar invitación" }));

    await waitFor(() => {
      expect(sendAgencyAdminInvitation).toHaveBeenCalledWith(
        "staff-access",
        "f09-demo-agency",
        "admin@example.test",
      );
    });
    expect(await screen.findByRole("status")).toHaveTextContent(
      "La invitación se envió al outbox local de desarrollo.",
    );
    expect(screen.queryByText(/token|link|vínculo/i)).not.toBeInTheDocument();
  });

  it("shows loading and API errors", async () => {
    let rejectLoad!: (error: Error) => void;
    vi.mocked(getAgencies).mockReturnValue(
      new Promise((_resolve, reject) => {
        rejectLoad = reject;
      }),
    );
    render(<AgencyAdminInvitations accessToken="staff-access" />);
    expect(screen.getByRole("status")).toHaveTextContent("Cargando inmobiliarias…");

    rejectLoad(new Error("No se pudieron cargar las inmobiliarias."));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No se pudieron cargar las inmobiliarias.",
    );
  });

  it("shows a submission error without exposing invitation details", async () => {
    const user = userEvent.setup();
    vi.mocked(getAgencies).mockResolvedValue({
      agencies: [{ id: "agency-1" }],
      pagination: { limit: 50, offset: 0, total: 1 },
    });
    vi.mocked(sendAgencyAdminInvitation).mockRejectedValue(
      new Error("No se pudo enviar la invitación."),
    );

    render(<AgencyAdminInvitations accessToken="staff-access" />);
    await screen.findByRole("option", { name: "agency-1" });
    await user.type(screen.getByLabelText("Correo del administrador"), "admin@example.test");
    await user.click(screen.getByRole("button", { name: "Enviar invitación" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No se pudo enviar la invitación.",
    );
    expect(screen.queryByText(/secret|token|link|vínculo/i)).not.toBeInTheDocument();
  });
});
