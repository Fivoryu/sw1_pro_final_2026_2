import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  getListingScene,
  listAgencyListings,
  putListingScene,
  StaffListingsApiError,
  type StaffListing,
} from "../../application/staffListingsApi";
import { DEFAULT_SCENE_DOCUMENT, type SceneDocument, type ScenePoint2D } from "../../application/sceneContract";
import { acceptCapture, listCaptures } from "../../application/captureReviewApi";
import { SceneEditor } from "./SceneEditor";

vi.mock("../../application/captureReviewApi", () => ({ listCaptures: vi.fn(), getCapture: vi.fn(), acceptCapture: vi.fn() }));

vi.mock("../../application/staffListingsApi", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("../../application/staffListingsApi")>();
  return {
    ...actual,
    getListingScene: vi.fn(),
    listAgencyListings: vi.fn(),
    putListingScene: vi.fn(),
  };
});

vi.mock("./SceneViewer", () => ({
  SceneViewer: ({ sceneDocument }: { sceneDocument: SceneDocument }) => (
    <output data-testid="scene-viewer-document">{JSON.stringify(sceneDocument)}</output>
  ),
}));

const listing: StaffListing = {
  listing_id: "listing-1",
  agency_id: "agency-1",
  operation: "sale",
  base_price: "350000000.00",
  currency: "BOB",
  city: "La Paz",
  zone: "Sopocachi",
  bedrooms: 3,
  bathrooms: 2,
  description: null,
  exact_address: null,
  approval_status: "approved",
  is_published: true,
  offer_version: 1,
  created_at: "2026-10-01T12:00:00Z",
};

const listingsPage = {
  listings: [listing],
  pagination: { limit: 50, offset: 0, total: 1 },
};

function documentInViewer(): SceneDocument {
  return JSON.parse(screen.getByTestId("scene-viewer-document").textContent ?? "{}") as SceneDocument;
}

function canvasPoint(point: ScenePoint2D) {
  // The fixture fits the 640×420 canvas at 90 px/m, with a 75×345 px origin.
  return { x: 75 + point.x * 90, y: 345 - point.z * 90 };
}

async function chooseListing(user: ReturnType<typeof userEvent.setup>) {
  await screen.findByRole("option", { name: /Venta · La Paz, Sopocachi/ });
  await user.selectOptions(screen.getByLabelText("Inmueble"), listing.listing_id);
  await screen.findByTestId("scene-editor-canvas");
}

function dispatchPointer(
  target: Element,
  type: "pointerdown" | "pointermove" | "pointerup",
  point: ScenePoint2D,
  pointerId: number,
) {
  const { x, y } = canvasPoint(point);
  const event = new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y });
  Object.defineProperty(event, "pointerId", { value: pointerId });
  fireEvent(target, event);
}

async function dragWallEndpoint(user: ReturnType<typeof userEvent.setup>) {
  await chooseListing(user);
  const endpoint = screen.getByTestId("wall-endpoint-wall-north-start");
  const canvas = screen.getByTestId("scene-editor-canvas");
  dispatchPointer(endpoint, "pointerdown", { x: 0, z: 0 }, 1);
  dispatchPointer(canvas, "pointermove", { x: 0.23, z: 0.18 }, 1);
  dispatchPointer(canvas, "pointerup", { x: 0.23, z: 0.18 }, 1);
}

beforeEach(() => {
  vi.mocked(listAgencyListings).mockReset().mockResolvedValue(listingsPage);
  vi.mocked(getListingScene).mockReset().mockResolvedValue(DEFAULT_SCENE_DOCUMENT);
  vi.mocked(putListingScene).mockReset().mockResolvedValue(DEFAULT_SCENE_DOCUMENT);
  vi.mocked(listCaptures).mockReset();
  vi.mocked(acceptCapture).mockReset();
});

describe("SceneEditor", () => {
  it("sends a snapped 2D wall endpoint edit to the 3D viewer through shared scene state", async () => {
    const user = userEvent.setup();
    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await dragWallEndpoint(user);

    await waitFor(() => {
      expect(documentInViewer().walls[0].start).toEqual({ x: 0.2, z: 0.2 });
    });
    // Openings stay parametric on the wall as its endpoints move.
    expect(documentInViewer().openings[0]).toMatchObject({ wallId: "wall-north", position: 0.5 });
    expect(getListingScene).toHaveBeenCalledWith("volatile-access", "agency-1", "listing-1");
  });

  it("snaps a wall endpoint to another endpoint within tolerance", async () => {
    const user = userEvent.setup();
    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await chooseListing(user);

    const endpoint = screen.getByTestId("wall-endpoint-wall-north-start");
    const canvas = screen.getByTestId("scene-editor-canvas");
    dispatchPointer(endpoint, "pointerdown", { x: 0, z: 0 }, 4);
    dispatchPointer(canvas, "pointermove", { x: 3.92, z: 2.92 }, 4);
    dispatchPointer(canvas, "pointerup", { x: 3.92, z: 2.92 }, 4);

    await waitFor(() => {
      expect(documentInViewer().walls[0].start).toEqual({ x: 4, z: 3 });
    });
  });

  it("renders room outlines as derived wall polygons without editable room vertices", async () => {
    const user = userEvent.setup();
    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await chooseListing(user);

    expect(screen.getByTestId("room-outline-room_main")).toBeInTheDocument();
    expect(screen.getByText("Estar")).toBeInTheDocument();
    expect(screen.queryByTestId(/room-vertex-/)).not.toBeInTheDocument();
    expect(Number(screen.getByTestId("scene-wall-wall-north").getAttribute("stroke-width")))
      .toBeCloseTo(13.5);
  });

  it("drags an opening along its wall and clamps its center so its width stays inside", async () => {
    const user = userEvent.setup();
    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await chooseListing(user);

    const opening = screen.getByTestId("scene-opening-door_1");
    const canvas = screen.getByTestId("scene-editor-canvas");
    dispatchPointer(opening, "pointerdown", { x: 2, z: 0 }, 2);
    dispatchPointer(canvas, "pointermove", { x: 4, z: 0 }, 2);
    dispatchPointer(canvas, "pointerup", { x: 4, z: 0 }, 2);

    await waitFor(() => {
      expect(documentInViewer().openings[0].position).toBeCloseTo(0.8875);
    });
    expect(documentInViewer().openings[0].width).toBe(0.9);
  });

  it("updates an object's x/z position while it is dragged on the canvas", async () => {
    const user = userEvent.setup();
    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await chooseListing(user);

    const object = screen.getByTestId("scene-object-ref_cube_1");
    const startingX = Number(object.getAttribute("data-position-x"));
    const canvas = screen.getByTestId("scene-editor-canvas");
    dispatchPointer(object, "pointerdown", { x: 1, z: 1 }, 3);
    dispatchPointer(canvas, "pointermove", { x: 1.9, z: 0.7 }, 3);
    dispatchPointer(canvas, "pointerup", { x: 1.9, z: 0.7 }, 3);

    await waitFor(() => {
      expect(Number(screen.getByTestId("scene-object-ref_cube_1").getAttribute("data-position-x")))
        .toBeGreaterThan(startingX);
    });
    expect(documentInViewer().objects[0].position.x).toBeGreaterThan(startingX);
  });

  it("saves the edited v2 document in a full PUT and reloads the persisted scene", async () => {
    const user = userEvent.setup();
    let storedDocument: SceneDocument = structuredClone(DEFAULT_SCENE_DOCUMENT);
    vi.mocked(getListingScene).mockImplementation(async () => structuredClone(storedDocument));
    vi.mocked(putListingScene).mockImplementation(async (_token, _agency, _listing, document) => {
      storedDocument = structuredClone(document);
      return structuredClone(storedDocument);
    });

    const firstRender = render(
      <SceneEditor accessToken="volatile-access" agencyId="agency-1" />,
    );
    await dragWallEndpoint(user);
    const editedDocument = documentInViewer();
    await user.click(screen.getByRole("button", { name: "Guardar escena" }));

    await waitFor(() => expect(putListingScene).toHaveBeenCalledTimes(1));
    expect(putListingScene).toHaveBeenCalledWith(
      "volatile-access",
      "agency-1",
      "listing-1",
      editedDocument,
    );
    expect(await screen.findByText("Cambios guardados correctamente.")).toBeVisible();
    firstRender.unmount();

    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await chooseListing(user);
    await waitFor(() => expect(documentInViewer()).toEqual(editedDocument));
  });

  it("does not mask other scene 404 responses with the synthetic default", async () => {
    const user = userEvent.setup();
    vi.mocked(getListingScene).mockRejectedValue(
      new StaffListingsApiError(404, "Listing not found", "listing_not_found"),
    );

    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await screen.findByRole("option", { name: /Venta · La Paz, Sopocachi/ });
    await user.selectOptions(screen.getByLabelText("Inmueble"), listing.listing_id);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No se pudo cargar la escena del inmueble.",
    );
    expect(screen.queryByText(/Escena sin guardar/)).not.toBeInTheDocument();
  });

  it("uses the synthetic v2 scene only for scene_not_defined and labels it as unsaved", async () => {
    const user = userEvent.setup();
    vi.mocked(getListingScene).mockRejectedValue(
      new StaffListingsApiError(404, "Scene is not defined", "scene_not_defined"),
    );

    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await chooseListing(user);

    expect(await screen.findByText(/Escena sin guardar/)).toBeVisible();
    expect(documentInViewer()).toEqual(DEFAULT_SCENE_DOCUMENT);
  });
});

describe("SceneEditor capture drafts", () => {
  const draft: SceneDocument = {
    ...DEFAULT_SCENE_DOCUMENT,
    walls: DEFAULT_SCENE_DOCUMENT.walls.map((wall, index) =>
      index === 0 ? { ...wall, start: { x: 0.5, z: 0.5 } } : wall),
  };
  const completed = { captureId: "cap-1", status: "completed" as const, sceneDraft: draft, warnings: [], failureReason: null };

  async function openPanel(user: ReturnType<typeof userEvent.setup>) {
    vi.mocked(listCaptures).mockResolvedValue([completed]);
    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await chooseListing(user);
    await user.click(screen.getByRole("button", { name: "Capturas reconstruidas" }));
    return await screen.findByRole("button", { name: "Cargar borrador en el editor" });
  }

  it("does not render the capture panel nor call the capture API until requested", async () => {
    const user = userEvent.setup();
    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await chooseListing(user);
    expect(screen.queryByRole("region", { name: "Borradores de capturas" })).not.toBeInTheDocument();
    expect(listCaptures).not.toHaveBeenCalled();
    expect(acceptCapture).not.toHaveBeenCalled();
  });

  it("loads the draft into the shared editor state without saving or accepting", async () => {
    const user = userEvent.setup();
    await user.click(await openPanel(user));
    await waitFor(() => expect(documentInViewer().walls[0].start).toEqual({ x: 0.5, z: 0.5 }));
    expect(screen.getByText("Hay cambios sin guardar.")).toBeVisible();
    expect(putListingScene).not.toHaveBeenCalled();
    expect(acceptCapture).not.toHaveBeenCalled();
  });

  it("asks for confirmation before replacing unsaved edits and keeps them when declined", async () => {
    const user = userEvent.setup();
    const button = await openPanel(user);
    const original = documentInViewer().walls[0].start;
    dispatchPointer(screen.getByTestId("wall-endpoint-wall-north-start"), "pointerdown", { x: 0, z: 0 }, 1);
    dispatchPointer(screen.getByTestId("scene-editor-canvas"), "pointermove", { x: 0.23, z: 0.18 }, 1);
    dispatchPointer(screen.getByTestId("scene-editor-canvas"), "pointerup", { x: 0.23, z: 0.18 }, 1);
    await waitFor(() => expect(documentInViewer().walls[0].start).toEqual({ x: 0.2, z: 0.2 }));
    expect(original).toEqual({ x: 0, z: 0 });
    const confirm = vi.spyOn(window, "confirm").mockReturnValue(false);
    await user.click(button);
    expect(confirm).toHaveBeenCalledTimes(1);
    expect(documentInViewer().walls[0].start).toEqual({ x: 0.2, z: 0.2 });
    confirm.mockReturnValue(true);
    await user.click(button);
    await waitFor(() => expect(documentInViewer().walls[0].start).toEqual({ x: 0.5, z: 0.5 }));
    confirm.mockRestore();
  });

  it("accepts the capture only after the scene save succeeds", async () => {
    const user = userEvent.setup();
    vi.mocked(putListingScene).mockResolvedValue(draft);
    vi.mocked(acceptCapture).mockResolvedValue({ ...completed, status: "accepted" as never });
    await user.click(await openPanel(user));
    expect(acceptCapture).not.toHaveBeenCalled();
    await user.click(screen.getByRole("button", { name: "Guardar escena" }));
    await waitFor(() => expect(acceptCapture).toHaveBeenCalledWith(
      "volatile-access", "agency-1", "listing-1", "cap-1"));
    expect(putListingScene).toHaveBeenCalledTimes(1);
  });

  it("does not accept the capture when the scene save fails", async () => {
    const user = userEvent.setup();
    vi.mocked(putListingScene).mockRejectedValue(new StaffListingsApiError(500, "boom"));
    await user.click(await openPanel(user));
    await user.click(screen.getByRole("button", { name: "Guardar escena" }));
    await screen.findByRole("alert");
    expect(acceptCapture).not.toHaveBeenCalled();
  });

  it("reports an accept failure after a saved scene without losing the save", async () => {
    const user = userEvent.setup();
    vi.mocked(putListingScene).mockResolvedValue(draft);
    vi.mocked(acceptCapture).mockRejectedValue(new StaffListingsApiError(409, "x"));
    await user.click(await openPanel(user));
    await user.click(screen.getByRole("button", { name: "Guardar escena" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(/no se pudo aceptar la captura/i);
    expect(screen.getByText("Escena guardada.")).toBeVisible();
  });
});
