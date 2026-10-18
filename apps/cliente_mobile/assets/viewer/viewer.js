// RoomForge customer walkthrough viewer (F06.4/F06.5).
// Loads a scene contract v1 document and renders a first-person walkthrough:
// left-half joystick moves, right-half drag looks, taps select objects.
// All content is local (vendored Three.js); the only outbound channel is the
// RoomForgeBridge JavaScript channel posting JSON messages to Flutter.
// Collisions, openings, limits and scene validation live in ./geometry.mjs,
// a dependency-free module covered by node --test (test_js/).
import {
  buildColliders,
  openingSpansForWall,
  resolveMove,
  sortedUnique,
  spawnPoint,
  validateScene,
} from "./geometry.mjs";

const EYE_HEIGHT = 1.6;
const WALK_SPEED = 1.8; // meters per second
const JOYSTICK_RANGE = 60; // pixels of full deflection
const LOOK_RADIANS_PER_PIXEL = 0.005;
const MAX_PITCH = Math.PI / 2 - 0.05;
const TAP_MAX_MS = 300;
const TAP_MAX_PIXELS = 10;

let THREE = null;
let renderer = null;
let scene = null;
let camera = null;
let worldGroup = null;
let objectMeshes = [];
let colliders = { segments: [], boxes: [] };
let yaw = 0;
let pitch = 0;
let moveVector = { x: 0, y: 0 };
let lastTime = 0;

function postMessage(message) {
  if (window.RoomForgeBridge && typeof window.RoomForgeBridge.postMessage === "function") {
    window.RoomForgeBridge.postMessage(JSON.stringify(message));
  }
}

function reportLoadError(detail) {
  postMessage({ type: "load_error", detail: String(detail) });
}

function addWall(group, room, start, end, material, lineMaterial) {
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
          centerX > opening.start && centerX < opening.end &&
          centerY > opening.bottom && centerY < opening.top,
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
      wall.add(new THREE.LineSegments(new THREE.EdgesGeometry(geometry), lineMaterial));
      group.add(wall);
    }
  }
}

function addRoom(group, room) {
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
  const lineMaterial = new THREE.LineBasicMaterial({ color: 0x000000 });
  room.contours.forEach((point, index) => {
    addWall(group, room, point, room.contours[(index + 1) % room.contours.length], wallMaterial, lineMaterial);
  });
}

function addObject(group, object) {
  const geometry = new THREE.BoxGeometry(
    object.dimensions.width,
    object.dimensions.height,
    object.dimensions.depth,
  );
  const mesh = new THREE.Mesh(geometry, new THREE.MeshBasicMaterial({ color: object.color || "#cccccc" }));
  mesh.position.set(
    object.position.x,
    object.position.y + object.dimensions.height / 2,
    object.position.z,
  );
  mesh.userData = { id: object.id, type: object.type };
  mesh.add(new THREE.LineSegments(new THREE.EdgesGeometry(geometry), new THREE.LineBasicMaterial({ color: 0x000000 })));
  group.add(mesh);
  objectMeshes.push(mesh);
}

// --- Scene lifecycle --------------------------------------------------------

function disposeWorld() {
  if (!worldGroup) return;
  scene.remove(worldGroup);
  worldGroup.traverse((child) => {
    if (!child.geometry) return;
    child.geometry.dispose();
    const materials = Array.isArray(child.material) ? child.material : [child.material];
    materials.forEach((material) => material && material.dispose());
  });
  worldGroup = null;
  objectMeshes = [];
}

function spawnCamera(document_) {
  const spawn = spawnPoint(document_, colliders);
  camera.position.set(spawn.x, EYE_HEIGHT, spawn.z);
  yaw = spawn.yaw;
  pitch = spawn.pitch;
}

let loadedDocument = null;

function loadScene(document_) {
  const problem = validateScene(document_);
  if (problem) {
    reportLoadError(problem);
    return;
  }
  try {
    loadedDocument = document_;
    disposeWorld();
    worldGroup = new THREE.Group();
    document_.rooms.forEach((room) => addRoom(worldGroup, room));
    document_.objects.forEach((object) => addObject(worldGroup, object));
    scene.add(worldGroup);
    colliders = buildColliders(document_);
    spawnCamera(document_);
    postMessage({ type: "scene_loaded", objects: document_.objects.map((object) => object.id) });
  } catch (error) {
    reportLoadError(error && error.message ? error.message : "Scene build failed.");
  }
}

function resetView() {
  if (loadedDocument) spawnCamera(loadedDocument);
}

// --- Input ------------------------------------------------------------------

function setupInput(canvas) {
  const pointers = new Map();

  canvas.addEventListener("pointerdown", (event) => {
    const rect = canvas.getBoundingClientRect();
    const mode = event.clientX - rect.left < rect.width / 2 ? "move" : "look";
    pointers.set(event.pointerId, {
      mode,
      startX: event.clientX,
      startY: event.clientY,
      lastX: event.clientX,
      lastY: event.clientY,
      startedAt: performance.now(),
    });
    if (mode === "move") {
      moveVector = { x: 0, y: 0 };
    }
    canvas.setPointerCapture(event.pointerId);
  });

  canvas.addEventListener("pointermove", (event) => {
    const pointer = pointers.get(event.pointerId);
    if (!pointer) return;
    if (pointer.mode === "look") {
      yaw -= (event.clientX - pointer.lastX) * LOOK_RADIANS_PER_PIXEL;
      pitch -= (event.clientY - pointer.lastY) * LOOK_RADIANS_PER_PIXEL;
      pitch = Math.max(-MAX_PITCH, Math.min(MAX_PITCH, pitch));
    }
    pointer.lastX = event.clientX;
    pointer.lastY = event.clientY;
    if (pointer.mode === "move") {
      const deltaX = pointer.lastX - pointer.startX;
      const deltaY = pointer.lastY - pointer.startY;
      const length = Math.hypot(deltaX, deltaY);
      const clamped = Math.min(length, JOYSTICK_RANGE);
      const scale = length === 0 ? 0 : clamped / length / JOYSTICK_RANGE;
      moveVector = { x: deltaX * scale, y: deltaY * scale };
    }
  });

  const releasePointer = (event, canvasEl) => {
    const pointer = pointers.get(event.pointerId);
    if (!pointer) return;
    pointers.delete(event.pointerId);
    if (pointer.mode === "move") moveVector = { x: 0, y: 0 };
    const elapsed = performance.now() - pointer.startedAt;
    const travel = Math.hypot(event.clientX - pointer.startX, event.clientY - pointer.startY);
    if (elapsed <= TAP_MAX_MS && travel <= TAP_MAX_PIXELS) {
      selectAt(canvasEl, event.clientX, event.clientY);
    }
  };

  canvas.addEventListener("pointerup", (event) => releasePointer(event, canvas));
  canvas.addEventListener("pointercancel", (event) => {
    const pointer = pointers.get(event.pointerId);
    if (!pointer) return;
    pointers.delete(event.pointerId);
    if (pointer.mode === "move") moveVector = { x: 0, y: 0 };
  });
}

function selectAt(canvas, clientX, clientY) {
  if (!camera || objectMeshes.length === 0) {
    postMessage({ type: "selection", objectId: null });
    return;
  }
  const rect = canvas.getBoundingClientRect();
  const pointer = new THREE.Vector2(
    ((clientX - rect.left) / rect.width) * 2 - 1,
    -((clientY - rect.top) / rect.height) * 2 + 1,
  );
  const raycaster = new THREE.Raycaster();
  raycaster.setFromCamera(pointer, camera);
  const hits = raycaster.intersectObjects(objectMeshes, false);
  postMessage({ type: "selection", objectId: hits.length > 0 ? hits[0].object.userData.id : null });
}

// --- Main loop and bootstrap ------------------------------------------------

function animate(time) {
  requestAnimationFrame(animate);
  const deltaSeconds = lastTime === 0 ? 0 : Math.min((time - lastTime) / 1000, 0.1);
  lastTime = time;
  if (!camera) return;

  if (moveVector.x !== 0 || moveVector.y !== 0) {
    // Three.js first-person basis: forward = (-sin yaw, -cos yaw), right = (cos yaw, -sin yaw).
    const forwardX = -Math.sin(yaw);
    const forwardZ = -Math.cos(yaw);
    const rightX = Math.cos(yaw);
    const rightZ = -Math.sin(yaw);
    const distance = WALK_SPEED * deltaSeconds;
    const deltaX = (forwardX * -moveVector.y + rightX * moveVector.x) * distance;
    const deltaZ = (forwardZ * -moveVector.y + rightZ * moveVector.x) * distance;
    const next = resolveMove(camera.position.x, camera.position.z, deltaX, deltaZ, colliders);
    camera.position.x = next.x;
    camera.position.z = next.z;
  }

  camera.rotation.order = "YXZ";
  camera.rotation.y = yaw;
  camera.rotation.x = pitch;
  renderer.render(scene, camera);
}

async function bootstrap() {
  const canvas = document.getElementById("scene-canvas");
  try {
    THREE = await import("./three.module.min.js");
  } catch (error) {
    reportLoadError("Viewer runtime failed to load.");
    return;
  }

  scene = new THREE.Scene();
  scene.background = new THREE.Color("#222222");
  camera = new THREE.PerspectiveCamera(75, 1, 0.1, 1000);
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  const resize = () => {
    const width = window.innerWidth;
    const height = window.innerHeight;
    renderer.setSize(width, height, false);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    camera.aspect = width / Math.max(height, 1);
    camera.updateProjectionMatrix();
  };
  window.addEventListener("resize", resize);
  resize();
  setupInput(canvas);
  requestAnimationFrame(animate);
  postMessage({ type: "ready" });
}

window.viewerHost = {
  loadScene: (document_) => loadScene(document_),
  resetView: () => {
    if (loadedDocument) spawnCamera(loadedDocument);
  },
};

bootstrap();
