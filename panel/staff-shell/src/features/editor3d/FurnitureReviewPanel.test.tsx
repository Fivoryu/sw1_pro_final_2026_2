import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, it, vi } from "vitest";
import { listListingPhotos, StaffListingsApiError } from "../../application/staffListingsApi";
import { getFurnitureReview, reviewFurniture, listDetectionJobs, requestPhotoDetection } from "../../application/furnitureReviewApi";
import { FurnitureReviewPanel } from "./FurnitureReviewPanel";

vi.mock("../../application/furnitureReviewApi", () => ({
  getFurnitureReview: vi.fn(), reviewFurniture: vi.fn(),
  listDetectionJobs: vi.fn(), requestPhotoDetection: vi.fn(),
}));
vi.mock("../../application/staffListingsApi", async (original) => ({
  ...await original<typeof import("../../application/staffListingsApi")>(),
  listListingPhotos: vi.fn(),
}));

const extra = { extra_id: "extra-1", name: "Silla existente", price: "20.50", quantity: 1,
  width_cm: 50, height_cm: 90, depth_cm: 60, origin: "manual", category: null, room: null, visual_reference: null };
const data = {
  listing: { listing_id: "listing-1", agency_id: "agency-1", operation: "sale" as const,
    base_price: "100000.00", currency: "BOB" as const, city: "La Paz", zone: "Centro",
    bedrooms: 2, bathrooms: 1, description: null, exact_address: null,
    approval_status: "draft" as const, is_published: false, offer_version: 4,
    created_at: "2026-10-21T10:00:00Z", extras: [extra] },
  suggestions: [{ job_id: "job-1", detection_index: 0, photo_id: "photo-1", model_id: "model-1",
    label: "chair", score: 0.91, box: [1, 2, 50, 90], status: "pending" as const, extra_id: null }],
  history: [],
};
const onChanged = vi.fn();

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(getFurnitureReview).mockResolvedValue(data);
  vi.mocked(reviewFurniture).mockResolvedValue(data);
  vi.mocked(listDetectionJobs).mockResolvedValue([{ job_id: "job-1", photo_id: "photo-1", status: "completed", failure_reason: null }]);
  vi.mocked(requestPhotoDetection).mockResolvedValue({ job_id: "job-2", photo_id: "photo-1", status: "pending", failure_reason: null });
  vi.mocked(listListingPhotos).mockResolvedValue([{ photo_id: "photo-1", url: "https://example.test/photo.jpg", content_type: "image/jpeg", size_bytes: 100, created_at: "2026-10-21T10:00:00Z" }]);
});

function open(disabled = false) {
  render(<FurnitureReviewPanel accessToken="token" agencyId="agency-1" listingId="listing-1" disabled={disabled} onChanged={onChanged} />);
}

function fill() {
  const fields = { "Nombre": "Silla revisada", "Precio (BOB)": "20.50", "Ancho (cm)": "50",
    "Alto (cm)": "90", "Fondo (cm)": "60", "Posición X (m)": "1", "Posición Y (m)": "0.45", "Posición Z (m)": "1" };
  for (const [label, value] of Object.entries(fields)) {
    const field = screen.getByLabelText(label);
    fireEvent.change(field, { target: { value } });
  }
}

it("shows honest detections and provenance without auto-confirmation", async () => {
  open();
  expect(await screen.findByText(/Puntuación: 0.91/)).toBeInTheDocument();
  expect(screen.getByText(/no es una probabilidad calibrada/)).toBeInTheDocument();
  expect(screen.getByText(/Caja 2D: 1, 2, 50, 90/)).toBeInTheDocument();
  expect(screen.getByText("Completado")).toBeInTheDocument();
  expect(screen.getByAltText("Foto photo-1")).toHaveAttribute("src", "https://example.test/photo.jpg");
  expect(reviewFurniture).not.toHaveBeenCalled();
});

it("requires human dimensions and price for a new confirmed suggestion", async () => {
  const user = userEvent.setup(); open();
  await user.click(await screen.findByRole("button", { name: /Revisar chair/ }));
  expect(screen.getByLabelText("Precio (BOB)")).toHaveValue(null);
  expect(screen.getByLabelText("Ancho (cm)")).toHaveValue(null);
  fill();
  await user.click(screen.getByRole("button", { name: "Confirmar mobiliario" }));
  await waitFor(() => expect(reviewFurniture).toHaveBeenCalledWith("token", "agency-1", "listing-1", expect.objectContaining({
    action: "confirmed", job_id: "job-1", detection_index: 0, expected_offer_version: 4,
    request_id: expect.any(String), item: expect.objectContaining({ name: "Silla revisada", price: "20.50", width_cm: 50, position: { x: 1, y: 0.45, z: 1 } }),
  })));
  expect(onChanged).toHaveBeenCalledOnce();
});

it("supports manual inventory and explicit duplicate linking", async () => {
  const user = userEvent.setup(); open();
  await screen.findByText(/Puntuación/);
  fill();
  await user.click(screen.getByRole("button", { name: "Confirmar mobiliario" }));
  await waitFor(() => expect(reviewFurniture).toHaveBeenCalledWith("token", "agency-1", "listing-1", expect.objectContaining({ action: "manual" })));
  await user.click(screen.getByRole("button", { name: /Revisar chair/ }));
  await user.selectOptions(screen.getByLabelText("Destino"), "extra-1");
  await user.click(screen.getByRole("button", { name: "Confirmar mobiliario" }));
  await waitFor(() => expect(reviewFurniture).toHaveBeenLastCalledWith("token", "agency-1", "listing-1", expect.objectContaining({
    action: "confirmed", existing_extra_id: "extra-1", job_id: "job-1", detection_index: 0,
  })));
  expect(vi.mocked(reviewFurniture).mock.lastCall?.[3]).not.toHaveProperty("item");
});

it("discards a false positive without commercial input", async () => {
  const user = userEvent.setup(); open();
  await user.click(await screen.findByRole("button", { name: /Descartar chair/ }));
  await waitFor(() => expect(reviewFurniture).toHaveBeenCalledWith("token", "agency-1", "listing-1", expect.objectContaining({ action: "rejected", job_id: "job-1", detection_index: 0 })));
  expect(vi.mocked(reviewFurniture).mock.lastCall?.[3]).not.toHaveProperty("item");
});

it("keeps conflicts visible and reloads rather than pretending confirmation", async () => {
  vi.mocked(reviewFurniture).mockRejectedValue(new StaffListingsApiError(409, "Offer changed"));
  const user = userEvent.setup(); open();
  await user.click(await screen.findByRole("button", { name: /Descartar chair/ }));
  expect(await screen.findByRole("alert")).toHaveTextContent(/Recarga/);
  expect(onChanged).not.toHaveBeenCalled();
  await user.click(screen.getByRole("button", { name: "Actualizar revisión" }));
  await waitFor(() => expect(getFurnitureReview).toHaveBeenCalledTimes(2));
});

it("blocks mutations until local scene edits are saved", async () => {
  open(true);
  expect(await screen.findByRole("button", { name: /Revisar chair/ })).toBeDisabled();
  expect(screen.getByRole("button", { name: /Descartar chair/ })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Confirmar mobiliario" })).toBeDisabled();
  expect(screen.getByText(/Guarda la escena/)).toBeInTheDocument();
});

it("requests inference and shows actual pending or failed jobs", async () => {
  vi.mocked(listDetectionJobs).mockResolvedValue([{ job_id: "job-1", photo_id: "photo-1", status: "failed", failure_reason: "Image unavailable" }]);
  const user = userEvent.setup(); open();
  expect(await screen.findByText("Fallido: Image unavailable")).toBeInTheDocument();
  await user.click(screen.getByRole("button", { name: "Detectar foto photo-1" }));
  await waitFor(() => expect(requestPhotoDetection).toHaveBeenCalledWith("token", "agency-1", "listing-1", "photo-1"));
});
