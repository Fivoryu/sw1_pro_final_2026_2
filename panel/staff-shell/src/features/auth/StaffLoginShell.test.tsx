import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  completeStaffLogin,
  startStaffLogin,
} from "../../application/staffAuthApi";
import { StaffLoginShell } from "./StaffLoginShell";

vi.mock("../../application/staffAuthApi", () => ({
  completeStaffLogin: vi.fn(),
  startStaffLogin: vi.fn(),
}));

beforeEach(() => {
  vi.mocked(completeStaffLogin).mockReset();
  vi.mocked(startStaffLogin).mockReset();
});

describe("StaffLoginShell credentials view", () => {
  it("provides an accessible, labeled staff sign-in form", () => {
    render(<StaffLoginShell />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Acceso de personal" }),
    ).toBeVisible();
    expect(
      screen.getByRole("textbox", { name: "Correo electrónico" }),
    ).toHaveAttribute("type", "email");
    expect(screen.getByLabelText("Contraseña")).toHaveAttribute(
      "type",
      "password",
    );
    expect(
      screen.getByRole("button", { name: "Continuar" }),
    ).toBeEnabled();
  });

  it("submits credentials and advances to the MFA challenge", async () => {
    const user = userEvent.setup();
    vi.mocked(startStaffLogin).mockResolvedValue({
      challenge_token: "one-time-login-challenge",
    });
    render(<StaffLoginShell />);

    await user.type(
      screen.getByLabelText("Correo electrónico"),
      "owner@example.test",
    );
    await user.type(screen.getByLabelText("Contraseña"), "correct-password");
    await user.click(screen.getByRole("button", { name: "Continuar" }));

    await waitFor(() =>
      expect(startStaffLogin).toHaveBeenCalledWith({
        email: "owner@example.test",
        password: "correct-password",
      }),
    );
    expect(
      screen.getByRole("textbox", { name: "Código de autenticación" }),
    ).toBeVisible();
    expect(
      screen.getByRole("button", { name: "Verificar acceso" }),
    ).toBeEnabled();
  });

  it("submits a TOTP code and returns the server-issued session", async () => {
    const user = userEvent.setup();
    const completedSession = {
      access_token: "short-lived-access-token",
      csrf_token: "csrf-token",
      user: {
        id: "staff-1",
        email: "owner@example.test",
        role: "platform_admin",
        tenant_id: null,
      },
    };
    const onAuthenticated = vi.fn();
    vi.mocked(startStaffLogin).mockResolvedValue({
      challenge_token: "one-time-login-challenge",
    });
    vi.mocked(completeStaffLogin).mockResolvedValue(completedSession);
    render(<StaffLoginShell onAuthenticated={onAuthenticated} />);

    await user.type(screen.getByLabelText("Correo electrónico"), "owner@example.test");
    await user.type(screen.getByLabelText("Contraseña"), "correct-password");
    await user.click(screen.getByRole("button", { name: "Continuar" }));
    await screen.findByLabelText("Código de autenticación");
    await user.type(screen.getByLabelText("Código de autenticación"), "123456");
    await user.click(screen.getByRole("button", { name: "Verificar acceso" }));

    await waitFor(() =>
      expect(completeStaffLogin).toHaveBeenCalledWith({
        challenge_token: "one-time-login-challenge",
        code: "123456",
      }),
    );
    expect(onAuthenticated).toHaveBeenCalledWith(completedSession);
  });

  it("allows a one-time recovery code as the alternative MFA proof", async () => {
    const user = userEvent.setup();
    vi.mocked(startStaffLogin).mockResolvedValue({
      challenge_token: "one-time-login-challenge",
    });
    render(<StaffLoginShell />);

    await user.type(screen.getByLabelText("Correo electrónico"), "owner@example.test");
    await user.type(screen.getByLabelText("Contraseña"), "correct-password");
    await user.click(screen.getByRole("button", { name: "Continuar" }));
    await screen.findByLabelText("Código de autenticación");
    await user.click(
      screen.getByRole("button", { name: "Usar un código de recuperación" }),
    );
    await user.type(screen.getByLabelText("Código de recuperación"), "RF-AAAA-BBBB");
    await user.click(screen.getByRole("button", { name: "Verificar acceso" }));

    await waitFor(() =>
      expect(completeStaffLogin).toHaveBeenCalledWith({
        challenge_token: "one-time-login-challenge",
        recovery_code: "RF-AAAA-BBBB",
      }),
    );
  });

  it("keeps the MFA step available and reports rejected proofs", async () => {
    const user = userEvent.setup();
    const onAuthenticated = vi.fn();
    vi.mocked(startStaffLogin).mockResolvedValue({
      challenge_token: "one-time-login-challenge",
    });
    vi.mocked(completeStaffLogin).mockRejectedValue(
      new Error("Login challenge is invalid or expired"),
    );
    render(<StaffLoginShell onAuthenticated={onAuthenticated} />);

    await user.type(screen.getByLabelText("Correo electrónico"), "owner@example.test");
    await user.type(screen.getByLabelText("Contraseña"), "correct-password");
    await user.click(screen.getByRole("button", { name: "Continuar" }));
    await screen.findByLabelText("Código de autenticación");
    await user.type(screen.getByLabelText("Código de autenticación"), "000000");
    await user.click(screen.getByRole("button", { name: "Verificar acceso" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No pudimos verificar tu identidad. Inténtalo nuevamente.",
    );
    expect(screen.getByLabelText("Código de autenticación")).toBeVisible();
    expect(onAuthenticated).not.toHaveBeenCalled();
  });
});
