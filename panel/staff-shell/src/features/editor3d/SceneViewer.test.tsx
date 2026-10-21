import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
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

beforeEach(() => {
  threeMocks.BoxGeometry.mockClear();
  threeMocks.ShapeGeometry.mockClear();
});

describe("SceneViewer", () => {
  it("renders the default v2 walls, derived room floor, and reference objects", () => {
    render(<SceneViewer />);

    expect(screen.getByRole("region", { name: "Visor 3D de la escena" })).toBeInTheDocument();
    expect(threeMocks.ShapeGeometry).toHaveBeenCalledTimes(1);
    // The centered 0.9 m door splits the 4 m north wall into two solid spans.
    expect(threeMocks.BoxGeometry.mock.calls.some(([width, height, thickness]) =>
      Math.abs(Number(width) - 1.55) < 1e-6 && Number(height) === 2.1 && Number(thickness) === 0.15,
    )).toBe(true);
    expect(threeMocks.BoxGeometry.mock.calls.some(([width, height, thickness]) =>
      Math.abs(Number(width) - 1.55) < 1e-6 && Math.abs(Number(height) - 0.3) < 1e-6 && Number(thickness) === 0.15,
    )).toBe(true);
    expect(threeMocks.BoxGeometry).toHaveBeenCalledWith(0.5, 0.5, 0.5);
  });

  it("uses window sill and top heights to leave the opening clear through the wall", () => {
    const sceneDocument: SceneDocument = {
      ...structuredClone(DEFAULT_SCENE_DOCUMENT),
      walls: DEFAULT_SCENE_DOCUMENT.walls.map((wall) =>
        wall.id === "wall-north" ? { ...wall, height: 3, thickness: 0.2 } : wall,
      ),
      openings: [
        {
          id: "window-1",
          wallId: "wall-north",
          position: 0.5,
          width: 1,
          height: 1,
          type: "window",
          sillHeight: 1,
        },
      ],
    };

    render(<SceneViewer sceneDocument={sceneDocument} />);

    // The window interval has no box; the lower sill and the wall above it remain.
    expect(threeMocks.BoxGeometry).toHaveBeenCalledTimes(14);
    expect(threeMocks.BoxGeometry.mock.calls.filter(([length, height, thickness]) =>
      length === 1 && height === 1 && thickness === 0.2,
    )).toHaveLength(2);
    expect(threeMocks.ShapeGeometry).toHaveBeenCalledTimes(1);
  });

  it("skips a room floor when its wall chain does not close", () => {
    const sceneDocument: SceneDocument = {
      ...structuredClone(DEFAULT_SCENE_DOCUMENT),
      rooms: [
        {
          ...DEFAULT_SCENE_DOCUMENT.rooms[0],
          wallIds: ["wall-north", "wall-south", "wall-east", "wall-west"],
        },
      ],
    };

    render(<SceneViewer sceneDocument={sceneDocument} />);

    expect(threeMocks.ShapeGeometry).not.toHaveBeenCalled();
  });

  it("renders object dimensions from the supplied scene document", () => {
    const sceneDocument: SceneDocument = {
      ...structuredClone(DEFAULT_SCENE_DOCUMENT),
      objects: [
        {
          ...DEFAULT_SCENE_DOCUMENT.objects[0],
          dimensions: { width: 1.2, height: 0.8, depth: 0.7 },
        },
      ],
    };

    render(<SceneViewer sceneDocument={sceneDocument} />);

    expect(threeMocks.BoxGeometry).toHaveBeenCalledWith(1.2, 0.8, 0.7);
  });
});
