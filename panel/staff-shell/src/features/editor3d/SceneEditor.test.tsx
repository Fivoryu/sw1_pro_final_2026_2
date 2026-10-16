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
import { DEFAULT_SCENE_DOCUMENT, type SceneDocument } from "../../application/sceneContract";
import { SceneEditor } from "./SceneEditor";

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

async function chooseListing(user: ReturnType<typeof userEvent.setup>) {
  await screen.findByRole("option", { name: /Venta · La Paz, Sopocachi/ });
  await user.selectOptions(screen.getByLabelText("Inmueble"), listing.listing_id);
  await screen.findByTestId("scene-editor-canvas");
}

function dispatchPointer(
  target: Element,
  type: "pointerdown" | "pointermove" | "pointerup",
  clientX: number,
  clientY: number,
  pointerId: number,
) {
  const event = new MouseEvent(type, { bubbles: true, cancelable: true, clientX, clientY });
  Object.defineProperty(event, "pointerId", { value: pointerId });
  fireEvent(target, event);
}

async function dragVertex(user: ReturnType<typeof userEvent.setup>) {
  await chooseListing(user);
  const canvas = screen.getByTestId("scene-editor-canvas");
  dispatchPointer(screen.getByTestId("room-vertex-room_main-0"), "pointerdown", 60, 80, 1);
  dispatchPointer(canvas, "pointermove", 140, 120, 1);
  dispatchPointer(canvas, "pointerup", 140, 120, 1);
}

beforeEach(() => {
  vi.mocked(listAgencyListings).mockReset().mockResolvedValue(listingsPage);
  vi.mocked(getListingScene).mockReset().mockResolvedValue(DEFAULT_SCENE_DOCUMENT);
  vi.mocked(putListingScene).mockReset().mockResolvedValue(DEFAULT_SCENE_DOCUMENT);
});

describe("SceneEditor", () => {
  it("sends an edited 2D wall vertex to the 3D viewer through the shared scene state", async () => {
    const user = userEvent.setup();
    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await dragVertex(user);

    await waitFor(() => {
      expect(documentInViewer().rooms[0].contours[0]).not.toEqual(
        DEFAULT_SCENE_DOCUMENT.rooms[0].contours[0],
      );
    });
    expect(getListingScene).toHaveBeenCalledWith(
      "volatile-access",
      "agency-1",
      "listing-1",
    );
  });

  it("updates an object's x/z position while it is dragged on the canvas", async () => {
    const user = userEvent.setup();
    render(<SceneEditor accessToken="volatile-access" agencyId="agency-1" />);
    await chooseListing(user);

    const object = screen.getByTestId("scene-object-ref_cube_1");
    const startingX = Number(object.getAttribute("data-position-x"));
    const canvas = screen.getByTestId("scene-editor-canvas");
    dispatchPointer(object, "pointerdown", 100, 100, 2);
    dispatchPointer(canvas, "pointermove", 180, 130, 2);
    dispatchPointer(canvas, "pointerup", 180, 130, 2);

    await waitFor(() => {
      expect(Number(screen.getByTestId("scene-object-ref_cube_1").getAttribute("data-position-x")))
        .toBeGreaterThan(startingX);
    });
    expect(documentInViewer().objects[0].position.x).toBeGreaterThan(startingX);
  });

  it("saves the edited document and reloads the persisted scene", async () => {
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
    await dragVertex(user);
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

  it("uses the synthetic scene only for scene_not_defined and labels it as unsaved", async () => {
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
