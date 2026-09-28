import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  completeStaffLogin,
  getStaffMe,
  logoutStaffSession,
  refreshStaffSession,
  startStaffLogin,
  type StaffUser,
} from "./application/staffAuthApi";
import { App } from "./App";
import * as staffSession from "./application/staffSession";

vi.mock("./application/staffAuthApi", () => ({
  acceptStaffInvitation: vi.fn(),
  completeStaffLogin: vi.fn(),
  getStaffMe: vi.fn(),
  logoutStaffSession: vi.fn(),
  refreshStaffSession: vi.fn(),
  startStaffLogin: vi.fn(),
  verifyStaffEnrollment: vi.fn(),
}));

function staffUser(role: string): StaffUser {
  return {
    id: "staff-1",
    email: "owner@example.test",
    role,
    tenant_id: role === "platform_admin" ? null : "agency-1",
  };
}

beforeEach(() => {
  sessionStorage.clear();
  localStorage.clear();
  window.history.replaceState({}, "", "/staff");
  vi.mocked(completeStaffLogin).mockReset();
  vi.mocked(getStaffMe).mockReset();
  vi.mocked(logoutStaffSession).mockReset();
  vi.mocked(refreshStaffSession).mockReset();
  vi.mocked(startStaffLogin).mockReset();
});

describe("staff invitation routing", () => {
  it("opens invitation acceptance from the invitation token query", () => {
    window.history.replaceState({}, "", "/accept-invitation?token=single-use-invitation");

    render(<App />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Acepta tu invitación" }),
    ).toBeVisible();
    expect(screen.getByLabelText("Nueva contraseña")).toBeVisible();
  });

  it("opens invitation acceptance from the backend invitation path", () => {
    window.history.replaceState({}, "", "/invitations/accept/raw-token_01");

    render(<App />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Acepta tu invitación" }),
    ).toBeVisible();
    expect(screen.getByLabelText("Nueva contraseña")).toBeVisible();
  });

  it.each([
    "/invitations/accept",
    "/invitations/accept/",
    "/invitations/accept/%20%20",
    "/invitations/accept/not%2Fone",
    "/invitations/accept/too/many/segments",
  ])("shows an invalid invitation state for malformed backend links: %s", (url) => {
    window.history.replaceState({}, "", url);

    render(<App />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Invitación no válida" }),
    ).toBeVisible();
    expect(screen.queryByLabelText("Nueva contraseña")).not.toBeInTheDocument();
  });

  it("falls back to staff login outside invitation routes without public registration", async () => {
    render(<App />);

    expect(
      await screen.findByRole("heading", { level: 1, name: "Acceso de personal" }),
    ).toBeVisible();
    expect(screen.getByLabelText("Correo electrónico")).toBeVisible();
    expect(screen.queryByText("Crear una cuenta")).not.toBeInTheDocument();
    expect(refreshStaffSession).not.toHaveBeenCalled();
  });

  it.each(["/accept-invitation", "/accept-invitation?token=%20%20"])(
    "does not expose password entry for an invalid invitation URL: %s",
    (url) => {
      window.history.replaceState({}, "", url);

      render(<App />);

      expect(
        screen.getByRole("heading", { level: 1, name: "Invitación no válida" }),
      ).toBeVisible();
      expect(screen.queryByLabelText("Nueva contraseña")).not.toBeInTheDocument();
    },
  );

  it("does not restore a session while a backend invitation route is open", () => {
    sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
    window.history.replaceState({}, "", "/invitations/accept/invitation-token");
    const restoreStaffSession = vi.spyOn(staffSession, "restoreStaffSession");

    render(<App />);

    expect(screen.getByRole("heading", { name: "Acepta tu invitación" })).toBeVisible();
    expect(restoreStaffSession).not.toHaveBeenCalled();
    expect(refreshStaffSession).not.toHaveBeenCalled();
    restoreStaffSession.mockRestore();
  });
});

describe("protected staff session lifecycle", () => {
  it("restores by rotating the tab CSRF token before resolving the server user", async () => {
    sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "volatile-access-token",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("agent") });

    render(<App />);

    expect(await screen.findByRole("heading", { name: "Área de agente" })).toBeVisible();
    expect(refreshStaffSession).toHaveBeenCalledWith("stored-csrf");
    expect(getStaffMe).toHaveBeenCalledWith("volatile-access-token");
    expect(vi.mocked(refreshStaffSession).mock.invocationCallOrder[0]).toBeLessThan(
      vi.mocked(getStaffMe).mock.invocationCallOrder[0],
    );
    expect(sessionStorage.getItem("roomforge.staff.csrf")).toBe("rotated-csrf");
    expect(localStorage.length).toBe(0);
    expect(sessionStorage.getItem("roomforge.staff.csrf")).not.toContain(
      "volatile-access-token",
    );
  });

  it.each(["refresh", "me"] as const)(
    "clears stored CSRF and returns to login when %s fails during restore",
    async (failedRequest) => {
      sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
      if (failedRequest === "refresh") {
        vi.mocked(refreshStaffSession).mockRejectedValue(new Error("refresh rejected"));
      } else {
        vi.mocked(refreshStaffSession).mockResolvedValue({
          access_token: "volatile-access-token",
          csrf_token: "rotated-csrf",
        });
        vi.mocked(getStaffMe).mockRejectedValue(new Error("identity rejected"));
      }

      render(<App />);

      expect(
        await screen.findByRole("heading", { level: 1, name: "Acceso de personal" }),
      ).toBeVisible();
      expect(sessionStorage.getItem("roomforge.staff.csrf")).toBeNull();
      expect(screen.queryByRole("heading", { name: "Área de agente" })).not.toBeInTheDocument();
    },
  );

  it("waits for /me after MFA login and keeps the access token in memory only", async () => {
    const user = userEvent.setup();
    vi.mocked(startStaffLogin).mockResolvedValue({ challenge_token: "login-challenge" });
    vi.mocked(completeStaffLogin).mockResolvedValue({
      access_token: "volatile-login-access",
      csrf_token: "login-csrf",
      user: staffUser("platform_admin"),
    });
    let resolveIdentity!: (response: { user: StaffUser }) => void;
    vi.mocked(getStaffMe).mockReturnValue(
      new Promise((resolve) => {
        resolveIdentity = resolve;
      }),
    );

    render(<App />);
    await user.type(await screen.findByLabelText("Correo electrónico"), "owner@example.test");
    await user.type(screen.getByLabelText("Contraseña"), "correct-password");
    await user.click(screen.getByRole("button", { name: "Continuar" }));
    await user.type(await screen.findByLabelText("Código de autenticación"), "123456");
    await user.click(screen.getByRole("button", { name: "Verificar acceso" }));

    await waitFor(() => expect(getStaffMe).toHaveBeenCalledWith("volatile-login-access"));
    expect(sessionStorage.getItem("roomforge.staff.csrf")).toBe("login-csrf");
    expect(screen.queryByRole("heading", { name: "Administración de plataforma" })).not.toBeInTheDocument();
    expect(localStorage.length).toBe(0);
    expect(sessionStorage.getItem("roomforge.staff.csrf")).not.toContain(
      "volatile-login-access",
    );

    resolveIdentity({ user: staffUser("platform_admin") });
    expect(
      await screen.findByRole("heading", { name: "Administración de plataforma" }),
    ).toBeVisible();
  });

  it("revokes on logout, clears tab storage, and returns to login", async () => {
    const user = userEvent.setup();
    sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "volatile-access-token",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("platform_admin") });
    vi.mocked(logoutStaffSession).mockResolvedValue(undefined);

    render(<App />);
    await screen.findByRole("heading", { name: "Administración de plataforma" });
    await user.click(screen.getByRole("button", { name: "Cerrar sesión" }));

    expect(logoutStaffSession).toHaveBeenCalledWith("rotated-csrf");
    expect(
      await screen.findByRole("heading", { level: 1, name: "Acceso de personal" }),
    ).toBeVisible();
    expect(sessionStorage.getItem("roomforge.staff.csrf")).toBeNull();
  });

  it.each([
    ["platform_admin", "Administración de plataforma", "Inicio de plataforma", "El espacio protegido está listo."],
    ["agency_admin", "Administración de inmobiliaria", "Inicio de inmobiliaria", "Cola de revisión"],
    ["agent", "Área de agente", "Inicio del agente", "El espacio protegido está listo."],
  ])("renders only the supported %s role in its placeholder shell", async (role, heading, navigation, viewText) => {
    sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "volatile-access-token",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser(role) });

    render(<App />);

    expect(await screen.findByRole("heading", { name: heading })).toBeVisible();
    expect(screen.getByRole("navigation")).toHaveTextContent(navigation);
    expect(screen.getByText(viewText)).toBeVisible();
  });

  it("rejects an unknown server role and falls back to login", async () => {
    sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "volatile-access-token",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("superuser") });

    render(<App />);

    expect(
      await screen.findByRole("heading", { level: 1, name: "Acceso de personal" }),
    ).toBeVisible();
    expect(sessionStorage.getItem("roomforge.staff.csrf")).toBeNull();
    expect(screen.queryByRole("navigation")).not.toBeInTheDocument();
  });
});
