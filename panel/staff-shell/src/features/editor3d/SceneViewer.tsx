import React, { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import type {
  SceneDocument,
  SceneObject,
  SceneOpening,
  ScenePoint2D,
  SceneRoom,
} from "../../application/sceneContract";
import { DEFAULT_SCENE_DOCUMENT } from "../../application/sceneContract";

interface SceneViewerProps {
  sceneDocument?: SceneDocument;
  selectedObjectId?: string | null;
  onObjectSelect?: (objectId: string | null) => void;
}

interface SelectedObject {
  id: string;
  type: string;
}

interface WallOpeningSpan {
  start: number;
  end: number;
  bottom: number;
  top: number;
}

function openingSpansForWall(
  room: SceneRoom,
  start: ScenePoint2D,
  end: ScenePoint2D,
  wallLength: number,
): WallOpeningSpan[] {
  const dx = end.x - start.x;
  const dz = end.z - start.z;

  return room.openings.flatMap((opening: SceneOpening) => {
    const offsetX = opening.position.x - start.x;
    const offsetZ = opening.position.z - start.z;
    const center = (offsetX * dx + offsetZ * dz) / wallLength;
    const distance = Math.abs(offsetX * dz - offsetZ * dx) / wallLength;
    if (distance > 0.05 || center < -opening.width / 2 || center > wallLength + opening.width / 2) {
      return [];
    }

    const span = {
      start: Math.max(0, center - opening.width / 2),
      end: Math.min(wallLength, center + opening.width / 2),
      bottom: Math.max(0, opening.position.y),
      top: Math.min(room.height, opening.position.y + opening.height),
    };
    return span.start < span.end && span.bottom < span.top ? [span] : [];
  });
}

function addWall(
  group: THREE.Group,
  room: SceneRoom,
  start: ScenePoint2D,
  end: ScenePoint2D,
  material: THREE.MeshBasicMaterial,
  lineMaterial: THREE.LineBasicMaterial,
) {
  const dx = end.x - start.x;
  const dz = end.z - start.z;
  const length = Math.hypot(dx, dz);
  if (length === 0) return;

  const openings = openingSpansForWall(room, start, end, length);
  const horizontalCuts = [0, length];
  const verticalCuts = [0, room.height];
  openings.forEach((opening) => {
    horizontalCuts.push(opening.start, opening.end);
    verticalCuts.push(opening.bottom, opening.top);
  });
  const sortedUnique = (values: number[]) =>
    [...new Set(values.map((value) => Number(value.toFixed(6))))].sort((a, b) => a - b);
  const xs = sortedUnique(horizontalCuts);
  const ys = sortedUnique(verticalCuts);
  const rotation = Math.atan2(-dz, dx);

  for (let xIndex = 0; xIndex < xs.length - 1; xIndex += 1) {
    const left = xs[xIndex];
    const right = xs[xIndex + 1];
    if (right <= left) continue;

    for (let yIndex = 0; yIndex < ys.length - 1; yIndex += 1) {
      const bottom = ys[yIndex];
      const top = ys[yIndex + 1];
      if (top <= bottom) continue;
      const centerX = (left + right) / 2;
      const centerY = (bottom + top) / 2;
      const insideOpening = openings.some(
        (opening) =>
          centerX > opening.start &&
          centerX < opening.end &&
          centerY > opening.bottom &&
          centerY < opening.top,
      );
      if (insideOpening) continue;

      const geometry = new THREE.PlaneGeometry(right - left, top - bottom);
      const wall = new THREE.Mesh(geometry, material);
      const distanceFromStart = (left + right) / 2;
      wall.position.set(
        start.x + (dx / length) * distanceFromStart,
        centerY,
        start.z + (dz / length) * distanceFromStart,
      );
      wall.rotation.y = rotation;
      const edges = new THREE.EdgesGeometry(geometry);
      wall.add(new THREE.LineSegments(edges, lineMaterial));
      group.add(wall);
    }
  }
}

function addRoom(group: THREE.Group, room: SceneRoom) {
  if (room.contours.length < 3) return;

  const shape = new THREE.Shape();
  shape.moveTo(room.contours[0].x, room.contours[0].z);
  room.contours.slice(1).forEach((point) => shape.lineTo(point.x, point.z));
  shape.closePath();

  const floor = new THREE.Mesh(
    new THREE.ShapeGeometry(shape),
    new THREE.MeshBasicMaterial({
      color: "#3a7bd5",
      transparent: true,
      opacity: 0.5,
      side: THREE.DoubleSide,
    }),
  );
  floor.rotation.x = Math.PI / 2;
  group.add(floor);

  const wallMaterial = new THREE.MeshBasicMaterial({
    color: "#e67e22",
    transparent: true,
    opacity: 0.8,
    side: THREE.DoubleSide,
  });
  const lineMaterial = new THREE.LineBasicMaterial({ color: 0x000000, linewidth: 2 });
  room.contours.forEach((point, index) => {
    addWall(
      group,
      room,
      point,
      room.contours[(index + 1) % room.contours.length],
      wallMaterial,
      lineMaterial,
    );
  });
}

function addObject(group: THREE.Group, object: SceneObject, isSelected: boolean): THREE.Mesh {
  const geometry = new THREE.BoxGeometry(
    object.dimensions.width,
    object.dimensions.height,
    object.dimensions.depth,
  );
  const mesh = new THREE.Mesh(
    geometry,
    new THREE.MeshBasicMaterial({ color: isSelected ? "#f4c95d" : object.color }),
  );
  mesh.position.set(
    object.position.x,
    object.position.y + object.dimensions.height / 2,
    object.position.z,
  );
  mesh.userData = { id: object.id, type: object.type };
  mesh.add(
    new THREE.LineSegments(
      new THREE.EdgesGeometry(geometry),
      new THREE.LineBasicMaterial({ color: 0x000000 }),
    ),
  );
  group.add(mesh);
  return mesh;
}

function disposeGroup(group: THREE.Group) {
  group.traverse((child: THREE.Object3D) => {
    if (!("geometry" in child)) return;
    const renderable = child as THREE.Mesh;
    renderable.geometry.dispose();
    const materials: THREE.Material[] = Array.isArray(renderable.material)
      ? renderable.material
      : [renderable.material];
    materials.forEach((material: THREE.Material) => material.dispose());
  });
  group.clear();
}

function focusPoint(document: SceneDocument) {
  const points = document.rooms.flatMap((room) => room.contours);
  if (points.length === 0) return { x: 2, z: 1.5, height: 2.4 };
  const minX = Math.min(...points.map((point) => point.x));
  const maxX = Math.max(...points.map((point) => point.x));
  const minZ = Math.min(...points.map((point) => point.z));
  const maxZ = Math.max(...points.map((point) => point.z));
  return {
    x: (minX + maxX) / 2,
    z: (minZ + maxZ) / 2,
    height: Math.max(...document.rooms.map((room) => room.height)),
  };
}

export const SceneViewer: React.FC<SceneViewerProps> = ({
  sceneDocument = DEFAULT_SCENE_DOCUMENT,
  selectedObjectId,
  onObjectSelect,
}) => {
  const mountRef = useRef<HTMLDivElement>(null);
  const sceneRef = useRef<THREE.Scene | null>(null);
  const groupRef = useRef<THREE.Group | null>(null);
  const cameraRef = useRef<THREE.PerspectiveCamera | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const controlsRef = useRef<OrbitControls | null>(null);
  const gridRef = useRef<THREE.GridHelper | null>(null);
  const objectMeshesRef = useRef<THREE.Mesh[]>([]);
  const hasFocusedSceneRef = useRef(false);
  const [clickedObject, setClickedObject] = useState<SelectedObject | null>(null);

  useEffect(() => {
    const mount = mountRef.current;
    if (!mount) return;
    mount.innerHTML = "";

    const scene = new THREE.Scene();
    scene.background = new THREE.Color("#222222");
    sceneRef.current = scene;

    const grid = new THREE.GridHelper(10, 10, "#888888", "#444444");
    grid.position.set(2, 0, 1.5);
    gridRef.current = grid;
    scene.add(grid);

    const camera = new THREE.PerspectiveCamera(75, 800 / 600, 0.1, 1000);
    camera.position.set(5, 6, 7);
    cameraRef.current = camera;

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(800, 500);
    rendererRef.current = renderer;
    mount.appendChild(renderer.domElement);

    const orbitControls = new OrbitControls(camera, renderer.domElement);
    orbitControls.enableDamping = true;
    orbitControls.target.set(2, 1.6, 1.5);
    orbitControls.maxPolarAngle = Math.PI / 2;
    controlsRef.current = orbitControls;

    const raycaster = new THREE.Raycaster();
    const mouse = new THREE.Vector2();
    const onClick = (event: MouseEvent) => {
      const rect = renderer.domElement.getBoundingClientRect();
      mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
      raycaster.setFromCamera(mouse, camera);
      const intersects = raycaster.intersectObjects(objectMeshesRef.current);
      const object = intersects[0]?.object;
      if (object) {
        const selected = { id: object.userData.id as string, type: object.userData.type as string };
        setClickedObject(selected);
        onObjectSelect?.(selected.id);
      } else {
        setClickedObject(null);
        onObjectSelect?.(null);
      }
    };
    renderer.domElement.addEventListener("click", onClick);

    const keys = { w: false, a: false, s: false, d: false };
    const handleKeyDown = (event: KeyboardEvent) => {
      const key = event.key.toLowerCase();
      if (key in keys) keys[key as keyof typeof keys] = true;
    };
    const handleKeyUp = (event: KeyboardEvent) => {
      const key = event.key.toLowerCase();
      if (key in keys) keys[key as keyof typeof keys] = false;
    };
    window.addEventListener("keydown", handleKeyDown);
    window.addEventListener("keyup", handleKeyUp);

    let animationId: number;
    const animate = () => {
      animationId = requestAnimationFrame(animate);
      const speed = 0.05;
      const direction = new THREE.Vector3();
      camera.getWorldDirection(direction);
      direction.y = 0;
      direction.normalize();
      const right = new THREE.Vector3();
      right.crossVectors(camera.up, direction).normalize();

      if (keys.w) {
        camera.position.addScaledVector(direction, speed);
        orbitControls.target.addScaledVector(direction, speed);
      }
      if (keys.s) {
        camera.position.addScaledVector(direction, -speed);
        orbitControls.target.addScaledVector(direction, -speed);
      }
      if (keys.a) {
        camera.position.addScaledVector(right, speed);
        orbitControls.target.addScaledVector(right, speed);
      }
      if (keys.d) {
        camera.position.addScaledVector(right, -speed);
        orbitControls.target.addScaledVector(right, -speed);
      }

      orbitControls.update();
      renderer.render(scene, camera);
    };
    animate();

    return () => {
      cancelAnimationFrame(animationId);
      window.removeEventListener("keydown", handleKeyDown);
      window.removeEventListener("keyup", handleKeyUp);
      renderer.domElement.removeEventListener("click", onClick);
      orbitControls.dispose();
      if (groupRef.current) {
        scene.remove(groupRef.current);
        disposeGroup(groupRef.current);
      }
      renderer.dispose();
      mount.innerHTML = "";
      sceneRef.current = null;
      groupRef.current = null;
      cameraRef.current = null;
      rendererRef.current = null;
      controlsRef.current = null;
      gridRef.current = null;
      objectMeshesRef.current = [];
      hasFocusedSceneRef.current = false;
    };
  }, []);

  useEffect(() => {
    const scene = sceneRef.current;
    if (!scene) return;

    if (groupRef.current) {
      scene.remove(groupRef.current);
      disposeGroup(groupRef.current);
    }
    const group = new THREE.Group();
    sceneDocument.rooms.forEach((room) => addRoom(group, room));
    objectMeshesRef.current = sceneDocument.objects.map((object) =>
      addObject(group, object, object.id === selectedObjectId),
    );
    scene.add(group);
    groupRef.current = group;

    const focus = focusPoint(sceneDocument);
    gridRef.current?.position.set(focus.x, 0, focus.z);
    if (!hasFocusedSceneRef.current) {
      cameraRef.current?.position.set(focus.x + 3, focus.height + 3.6, focus.z + 4.5);
      controlsRef.current?.target.set(focus.x, focus.height * 0.65, focus.z);
      hasFocusedSceneRef.current = true;
    }
  }, [sceneDocument, selectedObjectId]);

  const activeObjectId = selectedObjectId === undefined ? clickedObject?.id ?? null : selectedObjectId;
  const activeObject = sceneDocument.objects.find((object) => object.id === activeObjectId);

  return (
    <section aria-label="Visor 3D de la escena" className="scene-viewer">
      <p className="scene-viewer__hint">
        Arrastra para rotar la cámara. Usa <strong>W, A, S, D</strong> para desplazarte y haz clic
        en un objeto para seleccionarlo.
      </p>
      <div className="scene-viewer__canvas-wrap">
        <div
          aria-label="Renderizado interactivo de la escena"
          className="scene-viewer__canvas"
          ref={mountRef}
        />
        {activeObject ? (
          <div className="scene-viewer__selection" role="status">
            <strong>{activeObject.id}</strong>
            <span>{activeObject.type}</span>
          </div>
        ) : null}
      </div>
    </section>
  );
};
