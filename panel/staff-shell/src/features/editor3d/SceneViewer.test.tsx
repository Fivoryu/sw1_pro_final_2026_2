import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { SceneViewer } from "./SceneViewer";

// 1. Simulamos (Mock) la librería Three.js para que las pruebas no colapsen buscando WebGL
vi.mock("three", () => ({
  Scene: vi.fn(() => ({ background: null, add: vi.fn() })),
  PerspectiveCamera: vi.fn(() => ({ position: { set: vi.fn(), addScaledVector: vi.fn() }, getWorldDirection: vi.fn() })),
  WebGLRenderer: vi.fn(() => ({
    setSize: vi.fn(),
    domElement: document.createElement("canvas"),
    render: vi.fn(),
    dispose: vi.fn(),
  })),
  Color: vi.fn(),
  GridHelper: vi.fn(() => ({ position: { set: vi.fn() } })),
  PlaneGeometry: vi.fn(),
  MeshBasicMaterial: vi.fn(),
  Mesh: vi.fn(() => ({ rotation: {}, position: { set: vi.fn() }, add: vi.fn(), userData: {} })),
  BoxGeometry: vi.fn(),
  EdgesGeometry: vi.fn(),
  LineBasicMaterial: vi.fn(),
  LineSegments: vi.fn(),
  Raycaster: vi.fn(() => ({ setFromCamera: vi.fn(), intersectObjects: vi.fn(() => []) })),
  Vector2: vi.fn(),
  Vector3: vi.fn(() => ({ crossVectors: vi.fn(() => ({ normalize: vi.fn() })), normalize: vi.fn() })),
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

vi.mock("three/examples/jsm/controls/DragControls.js", () => ({
  DragControls: vi.fn(() => ({
    addEventListener: vi.fn(),
    dispose: vi.fn(),
  })),
}));

describe("SceneViewer", () => {
  it("renderiza el cascaron del editor 3D y su interfaz integrada", () => {
    render(<SceneViewer />);
    
    // 2. Verificamos que tu componente se inyectó bien en el diseño del compañero
    expect(screen.getByRole("heading", { level: 1, name: "Editor 3D de Inmuebles" })).toBeInTheDocument();
    expect(screen.getByText(/Utiliza el ratón para rotar la cámara/i)).toBeInTheDocument();
  });
});