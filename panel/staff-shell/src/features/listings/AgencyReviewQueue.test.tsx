import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  getAgencyListing,
  listAgencyListings,
  listListingTransitions,
  StaffListingsApiError,
  transitionListing,
  type ListingTransition,
  type StaffListing,
} from "../../application/staffListingsApi";
import { AgencyReviewQueue, formatCop } from "./AgencyReviewQueue";

vi.mock("../../application/staffListingsApi", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("../../application/staffListingsApi")>();
  return {
    ...actual,
    getAgencyListing: vi.fn(),
    listAgencyListings: vi.fn(),
    listListingTransitions: vi.fn(),
    transitionListing: vi.fn(),
  };
});

function listing(overrides: Partial<StaffListing> = {}): StaffListing {
  return {
    listing_id: "listing-1",
    agency_id: "agency-1",
    operation: "sale",
    base_price: "350000000.00",
    city: "Medellín",
    zone: "El Poblado",
    bedrooms: 3,
    bathrooms: 2,
    description: "Casa luminosa",
    exact_address: "Calle privada 123",
    currency: "BOB",
    approval_status: "pending",
    is_published: false,
    offer_version: 1,
    created_at: "2026-10-01T12:00:00Z",
    ...overrides,
  };
}

function page(listings: StaffListing[]) {
  return { listings, pagination: { limit: 50, offset: 0, total: listings.length } };
}

function transition(overrides: Partial<ListingTransition> = {}): ListingTransition {
  return {
    id: "t-1",
    agency_id: "agency-1",
    listing_id: "listing-1",
    action: "submit",
    from_status: "draft",
    from_published: false,
    to_status: "pending",
    to_published: false,
    observation: null,
    actor_id: "agent-1",
    actor_role: "agent",
    created_at: "2026-10-01T12:05:00Z",
    ...overrides,
  };
}

function renderQueue() {
  return render(<AgencyReviewQueue accessToken="volatile-access" agencyId="agency-1" />);
}

async function openDetail(user: ReturnType<typeof userEvent.setup>, item: StaffListing) {
  vi.mocked(getAgencyListing).mockResolvedValue(item);
  await user.click(await screen.findByRole("button", { name: /Revisar .*Medellín/ }));
  await screen.findByRole("heading", { level: 3, name: /Medellín/ });
}

beforeEach(() => {
  vi.mocked(getAgencyListing).mockReset();
  vi.mocked(listAgencyListings).mockReset();
  vi.mocked(listListingTransitions).mockReset().mockResolvedValue([transition()]);
  vi.mocked(transitionListing).mockReset();
});

describe("formatCop", () => {
  it.each([
    ["350000000.00", "COP 350.000.000,00"],
    ["1234.5", "COP 1.234,50"],
    ["9999999999999999.99", "COP 9.999.999.999.999.999,99"],
    ["0", "COP 0,00"],
  ])("formats %s exactly without floating point", (amount, expected) => {
    expect(formatCop(amount)).toBe(expected);
  });
});

describe("AgencyReviewQueue", () => {
  it("loads the session agency's pending listings with their commercial summary", async () => {
    vi.mocked(listAgencyListings).mockResolvedValue(page([listing()]));

    renderQueue();

    const item = await screen.findByRole("button", { name: /Revisar .*Medellín/ });
    expect(listAgencyListings).toHaveBeenCalledWith("volatile-access", "agency-1", {
      status: "pending",
    });
    expect(screen.getByRole("tab", { name: "En revisión" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    expect(item).toHaveTextContent("Venta");
    expect(item).toHaveTextContent("El Poblado");
    expect(item).toHaveTextContent("BOB 350.000.000,00");
    expect(item).toHaveTextContent("3 dormitorios · 2 baños");
  });

  it("shows rent prices as monthly amounts", async () => {
    vi.mocked(listAgencyListings).mockResolvedValue(
      page([listing({ operation: "rent", base_price: "2500000.00" })]),
    );

    renderQueue();

    const item = await screen.findByRole("button", { name: /Revisar .*Medellín/ });
    expect(item).toHaveTextContent("Alquiler");
    expect(item).toHaveTextContent("BOB 2.500.000,00 por mes");
  });

  it("shows the listing currency alongside the amounts in the row and the detail", async () => {
    const user = userEvent.setup();
    const usdListing = listing({ currency: "USD", base_price: "250000.00" });
    vi.mocked(listAgencyListings).mockResolvedValue(page([usdListing]));

    renderQueue();

    const item = await screen.findByRole("button", { name: /Revisar .*Medellín/ });
    expect(item).toHaveTextContent("USD 250.000,00");

    await openDetail(user, usdListing);
    expect(screen.getByText("Moneda")).toBeVisible();
    expect(screen.getByText("USD")).toBeVisible();
    expect(screen.getByText("USD 250.000,00")).toBeVisible();
  });

  it("explains an empty review queue", async () => {
    vi.mocked(listAgencyListings).mockResolvedValue(page([]));

    renderQueue();

    expect(
      await screen.findByText("No hay inmuebles esperando revisión."),
    ).toBeVisible();
  });

  it("reports a loading failure and retries on demand", async () => {
    const user = userEvent.setup();
    vi.mocked(listAgencyListings)
      .mockRejectedValueOnce(new TypeError("Failed to fetch"))
      .mockResolvedValueOnce(page([listing()]));

    renderQueue();

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No se pudieron cargar los inmuebles.",
    );
    await user.click(screen.getByRole("button", { name: "Reintentar" }));
    expect(await screen.findByRole("button", { name: /Revisar .*Medellín/ })).toBeVisible();
  });

  it("lists approved listings with their catalog visibility", async () => {
    const user = userEvent.setup();
    vi.mocked(listAgencyListings)
      .mockResolvedValueOnce(page([]))
      .mockResolvedValueOnce(
        page([
          listing({ approval_status: "approved", is_published: true }),
          listing({
            listing_id: "listing-2",
            approval_status: "approved",
            city: "Bogotá",
            zone: "Chapinero",
          }),
        ]),
      );

    renderQueue();
    await screen.findByText("No hay inmuebles esperando revisión.");
    await user.click(screen.getByRole("tab", { name: "Aprobados" }));

    expect(listAgencyListings).toHaveBeenLastCalledWith("volatile-access", "agency-1", {
      status: "approved",
    });
    expect(
      await screen.findByRole("button", { name: /Revisar .*Medellín/ }),
    ).toHaveTextContent("Publicado en el catálogo");
    expect(screen.getByRole("button", { name: /Revisar .*Bogotá/ })).toHaveTextContent(
      "Sin publicar",
    );
    expect(screen.getByRole("tab", { name: "Aprobados" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
  });

  it("opens a detail with private fields and the review history", async () => {
    const user = userEvent.setup();
    vi.mocked(listAgencyListings).mockResolvedValue(page([listing()]));
    vi.mocked(listListingTransitions).mockResolvedValue([
      transition({
        id: "t-0",
        action: "reject",
        from_status: "pending",
        to_status: "rejected",
        observation: "Faltan fotos del baño",
        actor_role: "agency_admin",
      }),
      transition(),
    ]);

    renderQueue();
    await openDetail(user, listing());

    expect(getAgencyListing).toHaveBeenCalledWith("volatile-access", "agency-1", "listing-1");
    expect(listListingTransitions).toHaveBeenCalledWith(
      "volatile-access",
      "agency-1",
      "listing-1",
    );
    expect(screen.getByText("Calle privada 123")).toBeVisible();
    expect(screen.getByText("Casa luminosa")).toBeVisible();
    const history = screen.getByRole("list", { name: "Historial" });
    expect(history).toHaveTextContent("Rechazado");
    expect(history).toHaveTextContent("Faltan fotos del baño");
    expect(history).toHaveTextContent("Enviado a revisión");
    expect(history).toHaveTextContent("Agente");

    await user.click(screen.getByRole("button", { name: "Volver a la bandeja" }));
    expect(await screen.findByRole("button", { name: /Revisar .*Medellín/ })).toBeVisible();
  });

  it("approves only after an explicit confirmation", async () => {
    const user = userEvent.setup();
    vi.mocked(listAgencyListings).mockResolvedValue(page([listing()]));
    vi.mocked(transitionListing).mockResolvedValue(
      listing({ approval_status: "approved" }),
    );

    renderQueue();
    await openDetail(user, listing());
    await user.click(screen.getByRole("button", { name: "Aprobar" }));

    const confirmation = screen.getByRole("group", { name: "Confirmar aprobación" });
    expect(confirmation).toHaveTextContent("todavía no aparecerá en el catálogo");
    await user.click(within(confirmation).getByRole("button", { name: "Cancelar" }));
    expect(transitionListing).not.toHaveBeenCalled();

    await user.click(screen.getByRole("button", { name: "Aprobar" }));
    await user.click(
      within(screen.getByRole("group", { name: "Confirmar aprobación" })).getByRole(
        "button",
        { name: "Confirmar" },
      ),
    );

    expect(transitionListing).toHaveBeenCalledWith(
      "volatile-access",
      "agency-1",
      "listing-1",
      "approve",
      undefined,
    );
    expect(await screen.findByRole("status")).toHaveTextContent("Inmueble aprobado.");
    await waitFor(() => expect(listAgencyListings).toHaveBeenCalledTimes(2));
  });

  it("requires a non-blank reason to reject and sends it trimmed", async () => {
    const user = userEvent.setup();
    vi.mocked(listAgencyListings).mockResolvedValue(page([listing()]));
    vi.mocked(transitionListing).mockResolvedValue(
      listing({ approval_status: "rejected" }),
    );

    renderQueue();
    await openDetail(user, listing());
    await user.click(screen.getByRole("button", { name: "Rechazar" }));

    const confirmation = screen.getByRole("group", { name: "Confirmar rechazo" });
    const confirm = within(confirmation).getByRole("button", { name: "Confirmar" });
    expect(confirm).toBeDisabled();
    await user.type(within(confirmation).getByLabelText("Motivo del rechazo"), "   ");
    expect(confirm).toBeDisabled();
    await user.type(
      within(confirmation).getByLabelText("Motivo del rechazo"),
      "Faltan documentos  ",
    );
    await user.click(confirm);

    expect(transitionListing).toHaveBeenCalledWith(
      "volatile-access",
      "agency-1",
      "listing-1",
      "reject",
      "Faltan documentos",
    );
    expect(await screen.findByRole("status")).toHaveTextContent("Inmueble rechazado.");
  });

  it.each([
    [false, "Publicar", "Confirmar publicación", "publish", "Inmueble publicado."],
    [true, "Retirar del catálogo", "Confirmar retiro", "unpublish", "Inmueble retirado del catálogo."],
  ] as const)(
    "offers the catalog action for an approved listing published=%s",
    async (isPublished, actionName, groupName, action, notice) => {
      const user = userEvent.setup();
      const approved = listing({ approval_status: "approved", is_published: isPublished });
      vi.mocked(listAgencyListings)
        .mockResolvedValueOnce(page([]))
        .mockResolvedValue(page([approved]));
      vi.mocked(transitionListing).mockResolvedValue(
        listing({ approval_status: "approved", is_published: !isPublished }),
      );

      renderQueue();
      await screen.findByText("No hay inmuebles esperando revisión.");
      await user.click(screen.getByRole("tab", { name: "Aprobados" }));
      await openDetail(user, approved);

      expect(screen.queryByRole("button", { name: "Aprobar" })).not.toBeInTheDocument();
      expect(screen.queryByRole("button", { name: "Rechazar" })).not.toBeInTheDocument();
      await user.click(screen.getByRole("button", { name: actionName }));
      await user.click(
        within(screen.getByRole("group", { name: groupName })).getByRole("button", {
          name: "Confirmar",
        }),
      );

      expect(transitionListing).toHaveBeenCalledWith(
        "volatile-access",
        "agency-1",
        "listing-1",
        action,
        undefined,
      );
      expect(await screen.findByRole("status")).toHaveTextContent(notice);
    },
  );

  it("explains a state conflict and reloads the detail", async () => {
    const user = userEvent.setup();
    vi.mocked(listAgencyListings).mockResolvedValue(page([listing()]));
    vi.mocked(transitionListing).mockRejectedValue(
      new StaffListingsApiError(409, "Listing cannot be changed from its current state"),
    );

    renderQueue();
    await openDetail(user, listing());
    vi.mocked(getAgencyListing).mockResolvedValue(listing({ approval_status: "approved" }));
    await user.click(screen.getByRole("button", { name: "Aprobar" }));
    await user.click(
      within(screen.getByRole("group", { name: "Confirmar aprobación" })).getByRole(
        "button",
        { name: "Confirmar" },
      ),
    );

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "El inmueble cambió de estado mientras lo revisabas.",
    );
    await waitFor(() => expect(getAgencyListing).toHaveBeenCalledTimes(2));
    expect(await screen.findByRole("button", { name: "Publicar" })).toBeVisible();
  });

  it("asks to sign in again when the session is rejected", async () => {
    vi.mocked(listAgencyListings).mockRejectedValue(
      new StaffListingsApiError(401, "Session is invalid or expired"),
    );

    renderQueue();

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Tu sesión expiró. Cierra sesión y vuelve a ingresar.",
    );
  });
});
