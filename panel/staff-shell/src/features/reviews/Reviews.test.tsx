import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  listReviewReports,
  listReviews,
  replyToReview,
  reportReview,
  resolveReviewReport,
  StaffReviewsApiError,
  type ReviewReport,
  type StaffReview,
} from "../../application/staffReviewsApi";
import { AgencyReviews } from "./AgencyReviews";
import { ReviewReportsQueue } from "./ReviewReportsQueue";

vi.mock("../../application/staffReviewsApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../application/staffReviewsApi")>();
  return {
    ...actual,
    listReviews: vi.fn(),
    replyToReview: vi.fn(),
    reportReview: vi.fn(),
    listReviewReports: vi.fn(),
    resolveReviewReport: vi.fn(),
  };
});

function review(overrides: Partial<StaffReview> = {}): StaffReview {
  return {
    id: "r1",
    listing_id: "listing-1",
    listing_rating: 4,
    agency_rating: 5,
    comment: "Muy buena atención",
    verified: false,
    created_at: "2026-11-01T10:00:00Z",
    updated_at: "2026-11-01T10:00:00Z",
    agency_reply: null,
    agency_reply_at: null,
    reported: false,
    ...overrides,
  };
}

const manySummary = { average: 4.25, count: 5, verified_count: 2, few_ratings: false };

beforeEach(() => {
  vi.mocked(listReviews)
    .mockReset()
    .mockResolvedValue({ summary: manySummary, reviews: [review()] });
  vi.mocked(replyToReview).mockReset().mockResolvedValue(undefined);
  vi.mocked(reportReview).mockReset().mockResolvedValue(undefined);
  vi.mocked(listReviewReports).mockReset().mockResolvedValue([]);
  vi.mocked(resolveReviewReport).mockReset().mockResolvedValue(undefined);
});

describe("AgencyReviews", () => {
  it("renders the summary with the average, counts and review details", async () => {
    vi.mocked(listReviews).mockResolvedValue({
      summary: manySummary,
      reviews: [
        review({ verified: true, reported: true, agency_reply: "Gracias", agency_reply_at: "2026-11-02T10:00:00Z" }),
      ],
    });

    render(<AgencyReviews accessToken="tok" isAgencyAdmin={false} />);

    expect(await screen.findByText("Promedio 4.3 de 5")).toBeVisible();
    expect(screen.getByText(/5 reseñas · 2 verificadas/)).toBeVisible();
    expect(screen.getByText("Verificada")).toBeVisible();
    expect(screen.getByText(/Reportada/)).toBeVisible();
    expect(screen.getByText("Inmueble: 4 de 5")).toBeVisible();
    expect(screen.getByText("Atención de la agencia: 5 de 5")).toBeVisible();
    expect(screen.getByText("Muy buena atención")).toBeVisible();
    expect(screen.getByText("Gracias")).toBeVisible();
    expect(listReviews).toHaveBeenCalledWith("tok");
  });

  it("shows 'pocas calificaciones' with counts instead of a number", async () => {
    vi.mocked(listReviews).mockResolvedValue({
      summary: { average: null, count: 2, verified_count: 1, few_ratings: true },
      reviews: [review()],
    });

    render(<AgencyReviews accessToken="tok" isAgencyAdmin={false} />);

    expect(await screen.findByText("Pocas calificaciones")).toBeVisible();
    expect(screen.getByText(/2 reseñas · 1 verificada/)).toBeVisible();
    expect(screen.queryByText(/Promedio/)).not.toBeInTheDocument();
    expect(screen.queryByText("Verificada")).not.toBeInTheDocument();
  });

  it("lets the agency admin reply once and hides the form once replied", async () => {
    const user = userEvent.setup();
    vi.mocked(listReviews)
      .mockResolvedValueOnce({ summary: manySummary, reviews: [review()] })
      .mockResolvedValueOnce({
        summary: manySummary,
        reviews: [review({ agency_reply: "Gracias por escribir", agency_reply_at: "2026-11-02T10:00:00Z" })],
      });

    render(<AgencyReviews accessToken="tok" isAgencyAdmin />);
    await user.type(await screen.findByLabelText("Tu respuesta"), "Gracias por escribir");
    await user.click(screen.getByRole("button", { name: "Responder" }));

    expect(replyToReview).toHaveBeenCalledWith("tok", "r1", "Gracias por escribir");
    expect(await screen.findByText("Respuesta de la agencia")).toBeVisible();
    expect(screen.queryByLabelText("Tu respuesta")).not.toBeInTheDocument();
  });

  it("shows the server error when a reply conflicts", async () => {
    const user = userEvent.setup();
    vi.mocked(replyToReview).mockRejectedValue(new StaffReviewsApiError(409, "Review already replied"));

    render(<AgencyReviews accessToken="tok" isAgencyAdmin />);
    await user.type(await screen.findByLabelText("Tu respuesta"), "Hola");
    await user.click(screen.getByRole("button", { name: "Responder" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Review already replied");
  });

  it("lets the agency admin report a review with a reason", async () => {
    const user = userEvent.setup();
    vi.mocked(listReviews)
      .mockResolvedValueOnce({ summary: manySummary, reviews: [review()] })
      .mockResolvedValueOnce({ summary: manySummary, reviews: [review({ reported: true })] });

    render(<AgencyReviews accessToken="tok" isAgencyAdmin />);
    await user.click(await screen.findByRole("button", { name: "Reportar reseña" }));
    await user.type(screen.getByLabelText("Motivo del reporte"), "Lenguaje ofensivo");
    await user.click(screen.getByRole("button", { name: "Enviar reporte" }));

    expect(reportReview).toHaveBeenCalledWith("tok", "r1", "Lenguaje ofensivo");
    expect(await screen.findByText(/Reportada/)).toBeVisible();
    expect(screen.queryByRole("button", { name: "Reportar reseña" })).not.toBeInTheDocument();
  });

  it("offers no reply or report controls to an agent", async () => {
    render(<AgencyReviews accessToken="tok" isAgencyAdmin={false} />);

    expect(await screen.findByText("Muy buena atención")).toBeVisible();
    expect(screen.queryByLabelText("Tu respuesta")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Responder" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Reportar reseña" })).not.toBeInTheDocument();
  });

  it("shows an error when loading fails", async () => {
    vi.mocked(listReviews).mockRejectedValue(new StaffReviewsApiError(403, "Forbidden"));

    render(<AgencyReviews accessToken="tok" isAgencyAdmin={false} />);

    expect(await screen.findByRole("alert")).toHaveTextContent("Forbidden");
  });
});

describe("ReviewReportsQueue", () => {
  function report(overrides: Partial<ReviewReport> = {}): ReviewReport {
    return {
      id: "rep1",
      review_id: "r1",
      agency_id: "agency-1",
      status: "open",
      reason: "Lenguaje ofensivo",
      created_at: "2026-11-02T10:00:00Z",
      review: review({ reported: true, comment: "Texto reportado" }),
      ...overrides,
    };
  }

  it("lists open reports with the review and the reason", async () => {
    vi.mocked(listReviewReports).mockResolvedValue([report()]);

    render(<ReviewReportsQueue accessToken="tok" />);

    expect(await screen.findByText("Texto reportado")).toBeVisible();
    expect(screen.getByText(/Lenguaje ofensivo/)).toBeVisible();
    expect(listReviewReports).toHaveBeenCalledWith("tok", "open");
  });

  it("shows an empty state", async () => {
    render(<ReviewReportsQueue accessToken="tok" />);

    expect(await screen.findByText("No hay reportes de reseñas pendientes.")).toBeVisible();
  });

  it("upholds a report and reloads the queue", async () => {
    const user = userEvent.setup();
    vi.mocked(listReviewReports).mockResolvedValueOnce([report()]).mockResolvedValueOnce([]);

    render(<ReviewReportsQueue accessToken="tok" />);
    await user.click(await screen.findByRole("button", { name: "Confirmar y ocultar reseña" }));

    expect(resolveReviewReport).toHaveBeenCalledWith("tok", "rep1", "upheld");
    expect(await screen.findByText("No hay reportes de reseñas pendientes.")).toBeVisible();
  });

  it("dismisses a report", async () => {
    const user = userEvent.setup();
    vi.mocked(listReviewReports).mockResolvedValueOnce([report()]).mockResolvedValueOnce([]);

    render(<ReviewReportsQueue accessToken="tok" />);
    const item = within(await screen.findByRole("list", { name: "Reportes de reseñas" }));
    await user.click(item.getByRole("button", { name: "Descartar reporte" }));

    expect(resolveReviewReport).toHaveBeenCalledWith("tok", "rep1", "dismissed");
  });

  it("shows the error when resolving fails", async () => {
    const user = userEvent.setup();
    vi.mocked(listReviewReports).mockResolvedValue([report()]);
    vi.mocked(resolveReviewReport).mockRejectedValue(new StaffReviewsApiError(409, "Already resolved"));

    render(<ReviewReportsQueue accessToken="tok" />);
    await user.click(await screen.findByRole("button", { name: "Descartar reporte" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Already resolved");
  });
});
