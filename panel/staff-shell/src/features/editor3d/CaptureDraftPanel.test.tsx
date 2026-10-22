import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, it, vi } from "vitest";
import { listCaptures, type CaptureReview } from "../../application/captureReviewApi";
import { StaffListingsApiError } from "../../application/staffListingsApi";
import { DEFAULT_SCENE_DOCUMENT } from "../../application/sceneContract";
import { CaptureDraftPanel } from "./CaptureDraftPanel";

vi.mock("../../application/captureReviewApi", () => ({
  listCaptures: vi.fn(), getCapture: vi.fn(), acceptCapture: vi.fn(),
}));

const onLoadDraft = vi.fn();
const base: CaptureReview = { captureId: "cap-1", status: "queued", sceneDraft: null, warnings: [], failureReason: null };

function open(props: Partial<React.ComponentProps<typeof CaptureDraftPanel>> = {}) {
  return render(<CaptureDraftPanel accessToken="token" agencyId="agency-1" listingId="listing-1"
    disabled={false} onLoadDraft={onLoadDraft} {...props} />);
}
function listed(...captures: CaptureReview[]) {
  vi.mocked(listCaptures).mockResolvedValue(captures);
}

beforeEach(() => {
  onLoadDraft.mockReset();
  vi.mocked(listCaptures).mockReset();
  listed(base);
});

it("lists the listing captures with the session token, without asking for ids", async () => {
  open();
  await screen.findByText(/En cola/);
  expect(listCaptures).toHaveBeenCalledWith("token", "agency-1", "listing-1");
  expect(screen.queryByLabelText("Identificador de captura")).toBeNull();
});

it("says so when the listing has no captures yet", async () => {
  listed();
  open();
  expect(await screen.findByText(/Todavía no hay capturas/)).toBeInTheDocument();
});

it.each([
  ["awaiting_upload", /Esperando la subida/],
  ["processing", /Procesando/],
  ["accepted", /Aceptada/],
] as const)("renders the %s status honestly without a load action", async (status, text) => {
  listed({ ...base, status });
  open();
  await screen.findByText(text);
  expect(screen.queryByRole("button", { name: "Cargar borrador en el editor" })).toBeNull();
});

it("shows the failure reason of a failed capture", async () => {
  listed({ ...base, status: "failed", failureReason: "frames_insufficient" });
  open();
  expect(await screen.findByText(/frames_insufficient/)).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Cargar borrador en el editor" })).toBeNull();
});

it("shows warnings and loads the draft of a completed capture only on request", async () => {
  listed({ ...base, status: "completed", sceneDraft: DEFAULT_SCENE_DOCUMENT, warnings: ["Altura supuesta"] });
  const user = userEvent.setup(); open();
  expect(await screen.findByText("Altura supuesta")).toBeInTheDocument();
  expect(onLoadDraft).not.toHaveBeenCalled();
  await user.click(screen.getByRole("button", { name: "Cargar borrador en el editor" }));
  expect(onLoadDraft).toHaveBeenCalledWith("cap-1", DEFAULT_SCENE_DOCUMENT);
});

it("explains a listing it cannot read", async () => {
  vi.mocked(listCaptures).mockRejectedValue(new StaffListingsApiError(404, "x"));
  open();
  expect(await screen.findByRole("alert")).toHaveTextContent(/No se encontró el inmueble/);
});

it("refreshes on request and when refreshKey changes", async () => {
  const user = userEvent.setup();
  const view = open();
  await screen.findByText(/En cola/);
  listed({ ...base, status: "processing" });
  await user.click(screen.getByRole("button", { name: "Actualizar" }));
  await screen.findByText(/Procesando/);
  listed({ ...base, status: "accepted" });
  view.rerender(<CaptureDraftPanel accessToken="token" agencyId="agency-1" listingId="listing-1"
    disabled={false} onLoadDraft={onLoadDraft} refreshKey={1} />);
  await waitFor(() => expect(screen.getByText(/Aceptada/)).toBeInTheDocument());
});
