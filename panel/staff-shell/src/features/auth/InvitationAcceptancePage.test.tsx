import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  acceptStaffInvitation,
  verifyStaffEnrollment,
} from "../../application/staffAuthApi";
import { InvitationAcceptancePage } from "./InvitationAcceptancePage";

vi.mock("../../application/staffAuthApi", () => ({
  acceptStaffInvitation: vi.fn(),
  verifyStaffEnrollment: vi.fn(),
}));

beforeEach(() => {
  vi.mocked(acceptStaffInvitation).mockReset();
  vi.mocked(verifyStaffEnrollment).mockReset();
  localStorage.clear();
  sessionStorage.clear();
});

describe("invitation-only staff enrollment", () => {
  it("presents an acceptance form only for a supplied invitation token", () => {
    const { rerender } = render(
      <InvitationAcceptancePage invitationToken="single-use-invitation" />,
    );

    expect(
      screen.getByRole("heading", { level: 1, name: "Acepta tu invitación" }),
    ).toBeVisible();
    expect(screen.getByLabelText("Nueva contraseña")).toBeVisible();
    expect(screen.getByLabelText("Confirmar contraseña")).toBeVisible();
    expect(screen.queryByText("Crear una cuenta" )).not.toBeInTheDocument();

    rerender(<InvitationAcceptancePage invitationToken={null} />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Invitación no válida" }),
    ).toBeVisible();
    expect(screen.queryByLabelText("Nueva contraseña")).not.toBeInTheDocument();

    rerender(<InvitationAcceptancePage invitationToken="   " />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Invitación no válida" }),
    ).toBeVisible();
    expect(screen.queryByLabelText("Nueva contraseña")).not.toBeInTheDocument();
  });

  it("checks password confirmation before sending the one-time token", async () => {
    const user = userEvent.setup();
    render(
      <InvitationAcceptancePage invitationToken="single-use-invitation" />,
    );

    await user.type(screen.getByLabelText("Nueva contraseña"), "first-secret");
    await user.type(screen.getByLabelText("Confirmar contraseña"), "different-secret");
    await user.click(screen.getByRole("button", { name: "Continuar" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Las contraseñas no coinciden.",
    );
    expect(acceptStaffInvitation).not.toHaveBeenCalled();
  });

  it("sends the invitation token and confirmed password before TOTP setup", async () => {
    const user = userEvent.setup();
    vi.mocked(acceptStaffInvitation).mockResolvedValue({
      enrollment_token: "enrollment-challenge",
      totp_secret: "BASE32SECRET",
      provisioning_uri: "otpauth://totp/RoomForge:owner%40example.test",
    });
    render(
      <InvitationAcceptancePage invitationToken="single-use-invitation" />,
    );

    await user.type(screen.getByLabelText("Nueva contraseña"), "correct-secret");
    await user.type(screen.getByLabelText("Confirmar contraseña"), "correct-secret");
    await user.click(screen.getByRole("button", { name: "Continuar" }));

    await waitFor(() =>
      expect(acceptStaffInvitation).toHaveBeenCalledWith({
        token: "single-use-invitation",
        password: "correct-secret",
        password_confirmation: "correct-secret",
      }),
    );
    expect(screen.getByText("BASE32SECRET")).toBeVisible();
    expect(screen.getByLabelText("Código de autenticación")).toBeVisible();
    expect(screen.getByRole("link", { name: "Abrir en aplicación autenticadora" })).toHaveAttribute(
      "href",
      "otpauth://totp/RoomForge:owner%40example.test",
    );
  });

  it("verifies TOTP and displays recovery codes once without persisting them", async () => {
    const user = userEvent.setup();
    const recoveryCodes = ["RF-AAAA-BBBB", "RF-CCCC-DDDD"];
    const onComplete = vi.fn();
    vi.mocked(acceptStaffInvitation).mockResolvedValue({
      enrollment_token: "enrollment-challenge",
      totp_secret: "BASE32SECRET",
      provisioning_uri: "otpauth://totp/RoomForge:owner%40example.test",
    });
    vi.mocked(verifyStaffEnrollment).mockResolvedValue({
      account: {
        id: "staff-1",
        email: "owner@example.test",
        role: "platform_admin",
        tenant_id: null,
      },
      recovery_codes: recoveryCodes,
    });
    render(
      <InvitationAcceptancePage
        invitationToken="single-use-invitation"
        onComplete={onComplete}
      />,
    );

    await user.type(screen.getByLabelText("Nueva contraseña"), "correct-secret");
    await user.type(screen.getByLabelText("Confirmar contraseña"), "correct-secret");
    await user.click(screen.getByRole("button", { name: "Continuar" }));
    await screen.findByLabelText("Código de autenticación");
    await user.type(screen.getByLabelText("Código de autenticación"), "123456");
    await user.click(screen.getByRole("button", { name: "Verificar TOTP" }));

    await waitFor(() =>
      expect(verifyStaffEnrollment).toHaveBeenCalledWith({
        enrollment_token: "enrollment-challenge",
        code: "123456",
      }),
    );
    expect(
      screen.getByRole("heading", { name: "Guarda tus códigos de recuperación" }),
    ).toBeVisible();
    for (const code of recoveryCodes) {
      expect(screen.getByText(code)).toBeVisible();
    }
    expect(localStorage.length).toBe(0);
    expect(sessionStorage.length).toBe(0);

    await user.click(screen.getByRole("button", { name: "Ya guardé mis códigos" }));

    for (const code of recoveryCodes) {
      expect(screen.queryByText(code)).not.toBeInTheDocument();
    }
    expect(onComplete).toHaveBeenCalledOnce();
  });
});
