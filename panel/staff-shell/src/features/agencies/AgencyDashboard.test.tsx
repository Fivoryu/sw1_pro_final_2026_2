import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  AgencyMetricsError,
  fetchAgencyMetrics,
  type AgencyMetricsResponse,
} from "../../application/agencyMetricsApi";
import { AgencyDashboard } from "./AgencyDashboard";

vi.mock("../../application/agencyMetricsApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../application/agencyMetricsApi")>();
  return { ...actual, fetchAgencyMetrics: vi.fn() };
});

const metrics: AgencyMetricsResponse = {
  listings: {
    draft: 1,
    in_review: 2,
    published: 3,
    approved_unpublished: 4,
    rejected: 5,
    total: 15,
  },
  active_quotes: 6,
  reservations: { pending: 7, accepted: 8, rejected: 9, cancelled: 10, expired: 11 },
};

function value(card: HTMLElement, label: string): string | null | undefined {
  return within(card).getByText(label).nextElementSibling?.textContent;
}

beforeEach(() => {
  vi.mocked(fetchAgencyMetrics).mockReset();
});

describe("AgencyDashboard", () => {
  it("shows every listing state, quotes and reservations of the agency", async () => {
    vi.mocked(fetchAgencyMetrics).mockResolvedValue(metrics);

    render(<AgencyDashboard accessToken="volatile-access" agencyId="agency-1" />);

    const listings = await screen.findByRole("region", { name: "Publicaciones" });
    expect(value(listings, "Borradores")).toBe("1");
    expect(value(listings, "En revisión")).toBe("2");
    expect(value(listings, "Publicados")).toBe("3");
    expect(value(listings, "Aprobados sin publicar")).toBe("4");
    expect(value(listings, "Rechazados")).toBe("5");
    expect(value(listings, "Total de inmuebles")).toBe("15");
    expect(
      within(screen.getByRole("region", { name: "Cotizaciones" })).getByText("6"),
    ).toBeInTheDocument();
    const reservations = screen.getByRole("region", { name: "Estado de Reservas" });
    expect(value(reservations, "Pendientes")).toBe("7");
    expect(value(reservations, "Vencidas")).toBe("11");
    expect(fetchAgencyMetrics).toHaveBeenCalledWith("volatile-access", "agency-1");
  });

  it("shows a loading state while the metrics arrive", () => {
    vi.mocked(fetchAgencyMetrics).mockReturnValue(new Promise(() => {}));

    render(<AgencyDashboard accessToken="volatile-access" agencyId="agency-1" />);

    expect(screen.getByText("Cargando métricas del panel...")).toBeInTheDocument();
  });

  it("explains a forbidden request without showing numbers", async () => {
    vi.mocked(fetchAgencyMetrics).mockRejectedValue(new AgencyMetricsError(403));

    render(<AgencyDashboard accessToken="volatile-access" agencyId="agency-1" />);

    expect(
      await screen.findByText("Solo el administrador de la agencia puede ver estas métricas."),
    ).toBeInTheDocument();
    expect(screen.queryByRole("region", { name: "Publicaciones" })).not.toBeInTheDocument();
  });

  it("retries after a failure", async () => {
    const user = userEvent.setup();
    vi.mocked(fetchAgencyMetrics)
      .mockRejectedValueOnce(new AgencyMetricsError(503))
      .mockResolvedValueOnce(metrics);

    render(<AgencyDashboard accessToken="volatile-access" agencyId="agency-1" />);

    expect(
      await screen.findByText("No se pudieron cargar las métricas. Intentá de nuevo."),
    ).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Reintentar" }));

    expect(await screen.findByRole("region", { name: "Publicaciones" })).toBeInTheDocument();
    expect(fetchAgencyMetrics).toHaveBeenCalledTimes(2);
  });
});
