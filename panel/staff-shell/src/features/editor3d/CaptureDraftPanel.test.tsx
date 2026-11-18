import { render, screen, waitFor, within } from "@testing-library/react";
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

it("separates scale warnings and lists the assumed measures still pending confirmation, read-only", async () => {
  const draft = { ...DEFAULT_SCENE_DOCUMENT,
    walls: DEFAULT_SCENE_DOCUMENT.walls.map((wall, i) => ({ ...wall, heightSource: i === 0 ? "assumed" as const : "manual" as const })) };
  listed({ ...base, status: "completed", sceneDraft: draft, warnings: [
    "Sin medida de referencia: el modelo no tiene escala métrica. Las medidas están en unidades arbitrarias y no deben tomarse como metros.",
    "Pared sin observar entre A y B"] });
  open();
  const scale = await screen.findByRole("list", { name: "Advertencias de escala de cap-1" });
  expect(scale).toHaveTextContent(/Sin medida de referencia/);
  expect(screen.getByRole("list", { name: "Advertencias de cap-1" })).toHaveTextContent("Pared sin observar");
  const pending = screen.getByRole("list", { name: "Medidas estimadas pendientes de cap-1" });
  expect(pending).toHaveTextContent(/wall-north/);
  expect(pending).toHaveTextContent(/2,40 m/);
  expect(pending.querySelectorAll("li")).toHaveLength(1);
  expect(within(pending).queryByRole("button")).toBeNull();
});

function withAssumedHeight(scale?: { mode: "metric" | "proportional" }) {
  return { ...DEFAULT_SCENE_DOCUMENT, ...(scale ? { scale } : {}),
    walls: DEFAULT_SCENE_DOCUMENT.walls.map((wall, i) => ({ ...wall,
      heightSource: i === 0 ? "assumed" as const : "manual" as const })) };
}

it("does not label heights as meters in a proportional plan", async () => {
  listed({ ...base, status: "completed", sceneDraft: withAssumedHeight({ mode: "proportional" }) });
  open();
  const pending = await screen.findByRole("list", { name: "Medidas estimadas pendientes de cap-1" });
  expect(pending).toHaveTextContent(/Altura relativa del muro wall-north: 2,40 \(unidades del plano, no metros\)/);
  expect(pending).not.toHaveTextContent(/2,40 m/);
});

it("keeps the metric height label for calibrated and older scenes", async () => {
  for (const scale of [{ mode: "metric" as const }, undefined]) {
    listed({ ...base, status: "completed", sceneDraft: withAssumedHeight(scale) });
    const { unmount } = open();
    const pending = await screen.findByRole("list", { name: "Medidas estimadas pendientes de cap-1" });
    expect(pending).toHaveTextContent(/Altura del muro wall-north: 2,40 m/);
    unmount();
  }
});

it("shows no estimate section when nothing is pending", async () => {
  listed({ ...base, status: "completed", sceneDraft: DEFAULT_SCENE_DOCUMENT });
  open();
  await screen.findByText(/Completada/);
  expect(screen.queryByText(/Medidas estimadas/)).toBeNull();
  expect(screen.queryByRole("list", { name: /Advertencias/ })).toBeNull();
});

const estimatedScene = {
  ...DEFAULT_SCENE_DOCUMENT,
  walls: DEFAULT_SCENE_DOCUMENT.walls.map((wall, i) => ({ ...wall,
    heightSource: i === 0 ? "estimated" as const : i === 1 ? "assumed" as const : "manual" as const })),
};

it("once loaded, lists estimated and assumed walls from the editor scene and confirms one as manual", async () => {
  const onConfirmMeasure = vi.fn();
  listed({ ...base, status: "completed", sceneDraft: estimatedScene });
  const user = userEvent.setup();
  open({ loadedCaptureId: "cap-1", scene: estimatedScene, onConfirmMeasure });
  const pending = await screen.findByRole("list", { name: "Medidas estimadas pendientes de cap-1" });
  expect(pending.querySelectorAll("li")).toHaveLength(2);
  expect(pending).toHaveTextContent(/estimada desde el video/);
  expect(pending).toHaveTextContent(/no medida/);
  await user.click(within(pending).getAllByRole("button", { name: "Confirmar" })[0] as HTMLElement);
  expect(onConfirmMeasure).toHaveBeenCalledWith("wall-north", undefined);
});

it("corrects a pending height with a valid positive number and rejects invalid ones", async () => {
  const onConfirmMeasure = vi.fn();
  listed({ ...base, status: "completed", sceneDraft: estimatedScene });
  const user = userEvent.setup();
  open({ loadedCaptureId: "cap-1", scene: estimatedScene, onConfirmMeasure });
  const input = await screen.findByLabelText("Altura corregida del muro wall-north (m)");
  await user.type(input, "0");
  await user.click(screen.getAllByRole("button", { name: "Corregir y confirmar" })[0] as HTMLElement);
  expect(onConfirmMeasure).not.toHaveBeenCalled();
  expect(screen.getByRole("alert")).toHaveTextContent(/mayor que cero/);
  await user.clear(input);
  await user.type(input, "2,65");
  await user.click(screen.getAllByRole("button", { name: "Corregir y confirmar" })[0] as HTMLElement);
  expect(onConfirmMeasure).toHaveBeenCalledWith("wall-north", 2.65);
});

it("does not offer confirmation while the draft is not loaded (T8 behavior)", async () => {
  listed({ ...base, status: "completed", sceneDraft: estimatedScene });
  open({ scene: DEFAULT_SCENE_DOCUMENT, onConfirmMeasure: vi.fn() });
  const pending = await screen.findByRole("list", { name: "Medidas estimadas pendientes de cap-1" });
  expect(within(pending).queryByRole("button")).toBeNull();
});
