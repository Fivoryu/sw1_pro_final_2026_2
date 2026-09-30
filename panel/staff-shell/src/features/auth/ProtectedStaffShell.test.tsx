import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  getStaffMe,
  logoutStaffSession,
  refreshStaffSession,
  type StaffUser,
} from "../../application/staffAuthApi";
import { ProtectedStaffShell } from "./ProtectedStaffShell";

vi.mock("../../application/staffAuthApi", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("../../application/staffAuthApi")>();
  return {
    ...actual,
    acceptStaffInvitation: vi.fn(),
    completeStaffLogin: vi.fn(),
    getStaffMe: vi.fn(),
    logoutStaffSession: vi.fn(),
    refreshStaffSession: vi.fn(),
    startStaffLogin: vi.fn(),
    verifyStaffEnrollment: vi.fn(),
  };
});

function expiredAccessToken(): string {
  const exp = Math.floor(Date.now() / 1000) - 60;
  return `header.${btoa(JSON.stringify({ exp }))}.signature`;
}

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
  vi.mocked(getStaffMe).mockReset();
  vi.mocked(logoutStaffSession).mockReset();
  vi.mocked(refreshStaffSession).mockReset();
});

describe("ProtectedStaffShell", () => {
  it("shows staff login without refreshing when no CSRF token is stored", async () => {
    render(<ProtectedStaffShell />);

    expect(
      await screen.findByRole("heading", { level: 1, name: "Acceso de personal" }),
    ).toBeVisible();
    expect(refreshStaffSession).not.toHaveBeenCalled();
  });

  it.each([
    ["platform_admin", "Administración de plataforma", "Inicio de plataforma"],
    ["agent", "Área de agente", "Inicio del agente"],
  ])("shows a minimal role-aware shell for %s", async (role, heading, navigation) => {
    sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "volatile-access",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser(role) });

    render(<ProtectedStaffShell />);

    expect(await screen.findByRole("heading", { name: heading })).toBeVisible();
    expect(screen.getByRole("navigation")).toHaveTextContent(navigation);
    expect(screen.getByText("El espacio protegido está listo.")).toBeVisible();
    expect(screen.queryByText(/crear|editar|eliminar|publicar/i)).not.toBeInTheDocument();
  });

  it("shows an honest prototype review queue for agency admins", async () => {
    sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "volatile-access",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("agency_admin") });

    render(<ProtectedStaffShell />);

    expect(
      await screen.findByRole("heading", { level: 2, name: "Cola de revisión" }),
    ).toBeVisible();
    expect(screen.getByRole("navigation")).toHaveTextContent("Inicio de inmobiliaria");
    expect(screen.getByText("No se muestran solicitudes en este prototipo.")).toBeVisible();
    expect(
      screen.getByText("Esta vista no está conectada a solicitudes reales."),
    ).toBeVisible();
    expect(screen.queryByText("El espacio protegido está listo.")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /aprobar|rechazar/i })).not.toBeInTheDocument();
    expect(screen.queryByText(/precio|disponibilidad/i)).not.toBeInTheDocument();
  });

  it("returns to login after a successful API logout", async () => {
    const user = userEvent.setup();
    sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "volatile-access",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("platform_admin") });
    vi.mocked(logoutStaffSession).mockResolvedValue(undefined);

    render(<ProtectedStaffShell />);
    await screen.findByRole("heading", { name: "Administración de plataforma" });
    await user.click(screen.getByRole("button", { name: "Cerrar sesión" }));

    expect(logoutStaffSession).toHaveBeenCalledWith("rotated-csrf");
    expect(
      await screen.findByRole("heading", { level: 1, name: "Acceso de personal" }),
    ).toBeVisible();
    expect(sessionStorage.getItem("roomforge.staff.csrf")).toBeNull();
  });

  it("explains an unusable role instead of returning to the login form", async () => {
    sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "volatile-access",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("superuser") });

    render(<ProtectedStaffShell />);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Tu cuenta no tiene permisos para este panel.",
    );
    expect(
      screen.queryByRole("heading", { level: 1, name: "Acceso de personal" }),
    ).not.toBeInTheDocument();
    expect(sessionStorage.getItem("roomforge.staff.csrf")).toBeNull();
  });

  it("offers a retry when the API is unreachable and restores on demand", async () => {
    const user = userEvent.setup();
    sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
    vi.mocked(refreshStaffSession).mockRejectedValueOnce(
      new TypeError("Failed to fetch"),
    );

    render(<ProtectedStaffShell />);

    const retry = await screen.findByRole("button", { name: "Reintentar" });
    expect(screen.getByRole("alert")).toHaveTextContent(
      "No se pudo contactar el servicio.",
    );
    expect(sessionStorage.getItem("roomforge.staff.csrf")).toBe("stored-csrf");

    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "volatile-access",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("agent") });
    await user.click(retry);

    expect(
      await screen.findByRole("heading", { name: "Área de agente" }),
    ).toBeVisible();
  });

  it("signs out with an explanation when the access token is already expired", async () => {
    sessionStorage.setItem("roomforge.staff.csrf", "stored-csrf");
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: expiredAccessToken(),
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("agent") });

    render(<ProtectedStaffShell />);

    expect(
      await screen.findByRole("heading", { level: 1, name: "Acceso de personal" }),
    ).toBeVisible();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Tu sesión expiró. Inicia sesión nuevamente.",
    );
  });
});
