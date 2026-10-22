// RoomForge customer walkthrough viewer (F06.4/F06.5).
// Loads a scene contract v2 document and renders a first-person walkthrough:
// left-half joystick moves, right-half drag looks, taps select objects.
// All content is local (vendored Three.js); the only outbound channel is the
// RoomForgeBridge JavaScript channel posting JSON messages to Flutter.
// Collisions, openings, limits and scene validation live in ./geometry.mjs,
// a dependency-free module covered by node --test (test_js/).
import {
  buildColliders,
  joystickVector,
  roomPolygon,
  wallOpeningsForWall,
  resolveMove,
  sortedUnique,
  spawnPoint,
  validateScene,
} from "./geometry.mjs";

const EYE_HEIGHT = 1.6;
const WALK_SPEED = 1.8; // meters per second
const JOYSTICK_RANGE = 50; // pixels of full deflection
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

function addWall(group, wallData, openings, material, lineMaterial) {
  const { start, end } = wallData;
  const dx = end.x - start.x;
  const dz = end.z - start.z;
  const length = Math.hypot(dx, dz);
  if (length === 0) return;

  const wallOpenings = wallOpeningsForWall(wallData, openings);
  const horizontalCuts = [0, length];
  const verticalCuts = [0, wallData.height];
  wallOpenings.forEach((opening) => {
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
      const insideOpening = wallOpenings.some(
        (opening) =>
          centerX > opening.start && centerX < opening.end &&
          centerY > opening.bottom && centerY < opening.top,
      );
      if (insideOpening) continue;

      // The box is centered on the wall axis, so its faces sit thickness/2 on
      // either side of that axis, matching the painted-edge collision margin.
      const geometry = new THREE.BoxGeometry(right - left, top - bottom, wallData.thickness);
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

function addRoomFloor(group, document_, room, material) {
  if (!room || typeof room.id !== "string") return;
  const polygon = roomPolygon(document_, room.id);
  if (!polygon) return;
  const shape = new THREE.Shape();
  shape.moveTo(polygon[0].x, polygon[0].z);
  polygon.slice(1).forEach((point) => shape.lineTo(point.x, point.z));
  shape.closePath();

  const floor = new THREE.Mesh(new THREE.ShapeGeometry(shape), material);
  floor.rotation.x = Math.PI / 2;
  group.add(floor);
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
let sceneLoadCount = 0;

function loadScene(document_) {
  const problem = validateScene(document_);
  if (problem) {
    reportLoadError(problem);
    return;
  }
  try {
    sceneLoadCount += 1;
    loadedDocument = document_;
    disposeWorld();
    worldGroup = new THREE.Group();
    const floorMaterial = new THREE.MeshBasicMaterial({
      color: "#3a7bd5",
      transparent: true,
      opacity: 0.5,
      side: THREE.DoubleSide,
    });
    const wallMaterial = new THREE.MeshBasicMaterial({
      color: "#e67e22",
      transparent: true,
      opacity: 0.8,
      side: THREE.DoubleSide,
    });
    const lineMaterial = new THREE.LineBasicMaterial({ color: 0x000000 });
    const rooms = Array.isArray(document_.rooms) ? document_.rooms : [];
    rooms.forEach((room) => addRoomFloor(worldGroup, document_, room, floorMaterial));
    document_.walls.forEach((wall) =>
      addWall(worldGroup, wall, document_.openings, wallMaterial, lineMaterial));
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
  const joystick = document.getElementById("joystick-control");
  const joystickKnob = document.getElementById("joystick-knob");
  let movePointerId = null;

  const resetJoystickVisual = () => {
    if (!joystickKnob) return;
    joystickKnob.style.setProperty("--joystick-x", "0px");
    joystickKnob.style.setProperty("--joystick-y", "0px");
  };
  const resetMoveInput = (pointerId = null) => {
    if (pointerId !== null && movePointerId !== pointerId) return;
    movePointerId = null;
    moveVector = { x: 0, y: 0 };
    resetJoystickVisual();
  };
  const resetAllInput = () => {
    pointers.clear();
    resetMoveInput();
  };
  const updateMoveInput = (pointer, event) => {
    moveVector = joystickVector(
      event.clientX - pointer.startX,
      event.clientY - pointer.startY,
      JOYSTICK_RANGE,
    );
    if (!joystickKnob) return;
    joystickKnob.style.setProperty("--joystick-x", `${moveVector.x * JOYSTICK_RANGE}px`);
    joystickKnob.style.setProperty("--joystick-y", `${moveVector.y * JOYSTICK_RANGE}px`);
  };
  window.addEventListener("blur", resetAllInput);
  document.addEventListener("visibilitychange", resetAllInput);

  canvas.addEventListener("pointerdown", (event) => {
    const rect = canvas.getBoundingClientRect();
    const mode = event.clientX - rect.left < rect.width / 2 ? "move" : "look";
    if (mode === "move" && movePointerId !== null) return;
    const pointer = {
      mode,
      startX: event.clientX,
      startY: event.clientY,
      lastX: event.clientX,
      lastY: event.clientY,
      startedAt: performance.now(),
      selectable: true,
    };
    pointers.set(event.pointerId, pointer);
    if (mode === "move") {
      movePointerId = event.pointerId;
      moveVector = { x: 0, y: 0 };
      resetJoystickVisual();
    }
    canvas.setPointerCapture(event.pointerId);
  });

  const handlePointerMove = (event) => {
    const pointer = pointers.get(event.pointerId);
    if (!pointer) return;
    if (pointer.mode === "look") {
      yaw -= (event.clientX - pointer.lastX) * LOOK_RADIANS_PER_PIXEL;
      pitch -= (event.clientY - pointer.lastY) * LOOK_RADIANS_PER_PIXEL;
      pitch = Math.max(-MAX_PITCH, Math.min(MAX_PITCH, pitch));
    } else if (pointer.mode === "move") {
      updateMoveInput(pointer, event);
    }
    pointer.lastX = event.clientX;
    pointer.lastY = event.clientY;
  };

  const releasePointer = (event, canvasEl) => {
    const pointer = pointers.get(event.pointerId);
    if (!pointer) return;
    pointers.delete(event.pointerId);
    if (pointer.mode === "move") resetMoveInput(event.pointerId);
    const elapsed = performance.now() - pointer.startedAt;
    const travel = Math.hypot(event.clientX - pointer.startX, event.clientY - pointer.startY);
    if (pointer.selectable && elapsed <= TAP_MAX_MS && travel <= TAP_MAX_PIXELS) {
      selectAt(canvasEl, event.clientX, event.clientY);
    }
  };

  const cancelPointer = (event) => {
    const pointer = pointers.get(event.pointerId);
    if (!pointer) return;
    pointers.delete(event.pointerId);
    if (pointer.mode === "move") resetMoveInput(event.pointerId);
  };

  canvas.addEventListener("pointermove", handlePointerMove);
  canvas.addEventListener("pointerup", (event) => releasePointer(event, canvas));
  canvas.addEventListener("pointercancel", cancelPointer);

  if (joystick) {
    joystick.addEventListener("pointerdown", (event) => {
      if (movePointerId !== null) {
        event.preventDefault();
        return;
      }
      const rect = joystick.getBoundingClientRect();
      const pointer = {
        mode: "move",
        startX: rect.left + rect.width / 2,
        startY: rect.top + rect.height / 2,
        lastX: event.clientX,
        lastY: event.clientY,
        startedAt: performance.now(),
        selectable: false,
      };
      pointers.set(event.pointerId, pointer);
      movePointerId = event.pointerId;
      joystick.setPointerCapture(event.pointerId);
      updateMoveInput(pointer, event);
      event.preventDefault();
    });
    joystick.addEventListener("pointermove", handlePointerMove);
    joystick.addEventListener("pointerup", (event) => releasePointer(event, canvas));
    joystick.addEventListener("pointercancel", cancelPointer);
  }
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
  // Read-only probe used by the device run (never by product code): it is what
  // makes "the gestos mueven la cámara" a measured fact instead of a guess.
  debugState: () => ({
    yaw: yaw,
    pitch: pitch,
    x: camera ? camera.position.x : null,
    z: camera ? camera.position.z : null,
    loads: sceneLoadCount,
    objects: objectMeshes.length,
  }),
};

bootstrap();
