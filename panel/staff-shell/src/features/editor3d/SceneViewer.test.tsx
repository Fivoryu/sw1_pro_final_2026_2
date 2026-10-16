import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { DEFAULT_SCENE_DOCUMENT, type SceneDocument } from "../../application/sceneContract";
import { SceneViewer } from "./SceneViewer";

const threeMocks = vi.hoisted(() => ({
  BoxGeometry: vi.fn(),
  ShapeGeometry: vi.fn(),
}));

vi.mock("three", () => ({
  Scene: vi.fn(() => ({ background: null, add: vi.fn(), remove: vi.fn() })),
  PerspectiveCamera: vi.fn(() => ({
    position: { set: vi.fn(), addScaledVector: vi.fn() },
    getWorldDirection: vi.fn(),
    up: {},
  })),
  WebGLRenderer: vi.fn(() => ({
    setSize: vi.fn(),
    domElement: document.createElement("canvas"),
    render: vi.fn(),
    dispose: vi.fn(),
  })),
  Color: vi.fn(),
  GridHelper: vi.fn(() => ({ position: { set: vi.fn() } })),
  Group: vi.fn(() => ({ add: vi.fn(), traverse: vi.fn(), clear: vi.fn() })),
  Shape: vi.fn(() => ({ moveTo: vi.fn(), lineTo: vi.fn(), closePath: vi.fn() })),
  ShapeGeometry: threeMocks.ShapeGeometry,
  PlaneGeometry: vi.fn(),
  MeshBasicMaterial: vi.fn(),
  Mesh: vi.fn(() => ({
    rotation: {},
    position: { set: vi.fn() },
    add: vi.fn(),
    userData: {},
  })),
  BoxGeometry: threeMocks.BoxGeometry,
  EdgesGeometry: vi.fn(),
  LineBasicMaterial: vi.fn(),
  LineSegments: vi.fn(),
  Raycaster: vi.fn(() => ({ setFromCamera: vi.fn(), intersectObjects: vi.fn(() => []) })),
  Vector2: vi.fn(),
  Vector3: vi.fn(() => ({
    crossVectors: vi.fn(() => ({ normalize: vi.fn() })),
    normalize: vi.fn(),
  })),
  DoubleSide: 2,
}));

vi.mock("three/examples/jsm/controls/OrbitControls.js", () => ({
  OrbitControls: vi.fn(() => ({
    enableDamping: true,
    target: { set: vi.fn(), addScaledVector: vi.fn() },
    update: vi.fn(),
    dispose: vi.fn(),
  })),
}));

describe("SceneViewer", () => {
  it("uses the extracted synthetic scene when no document is supplied", () => {
    render(<SceneViewer />);

    expect(screen.getByRole("region", { name: "Visor 3D de la escena" })).toBeInTheDocument();
    expect(threeMocks.ShapeGeometry).toHaveBeenCalled();
    expect(threeMocks.BoxGeometry).toHaveBeenCalledWith(
      DEFAULT_SCENE_DOCUMENT.objects[0].dimensions.width,
      DEFAULT_SCENE_DOCUMENT.objects[0].dimensions.height,
      DEFAULT_SCENE_DOCUMENT.objects[0].dimensions.depth,
    );
  });

  it("renders the dimensions and room geometry from the supplied document", () => {
    const sceneDocument: SceneDocument = {
      ...DEFAULT_SCENE_DOCUMENT,
      rooms: [
        {
          ...DEFAULT_SCENE_DOCUMENT.rooms[0],
          contours: [
            { x: -1, z: -2 },
            { x: 6, z: -2 },
            { x: 6, z: 4 },
          ],
          openings: [],
        },
      ],
      objects: [
        {
          ...DEFAULT_SCENE_DOCUMENT.objects[0],
          dimensions: { width: 1.2, height: 0.8, depth: 0.7 },
        },
      ],
    };

    render(<SceneViewer sceneDocument={sceneDocument} />);

    expect(threeMocks.BoxGeometry).toHaveBeenCalledWith(1.2, 0.8, 0.7);
    expect(threeMocks.ShapeGeometry).toHaveBeenCalled();
  });
});
