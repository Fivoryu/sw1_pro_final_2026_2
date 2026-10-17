// RoomForge customer walkthrough viewer (F06.4/F06.5).
// Loads a scene contract v1 document and renders a first-person walkthrough:
// left-half joystick moves, right-half drag looks, taps select objects.
// All content is local (vendored Three.js); the only outbound channel is the
// RoomForgeBridge JavaScript channel posting JSON messages to Flutter.

const EYE_HEIGHT = 1.6;
const WALK_SPEED = 1.8; // meters per second
const CAMERA_RADIUS = 0.25; // collision margin around the camera
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
let colliderSegments = [];
let colliderBoxes = [];
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

// --- Geometry (ported from the panel SceneViewer) ---------------------------

function openingSpansForWall(room, start, end, wallLength) {
  const dx = end.x - start.x;
  const dz = end.z - start.z;
  const spans = [];
  (room.openings || []).forEach((opening) => {
    const offsetX = opening.position.x - start.x;
    const offsetZ = opening.position.z - start.z;
    const center = (offsetX * dx + offsetZ * dz) / wallLength;
    const distance = Math.abs(offsetX * dz - offsetZ * dx) / wallLength;
    if (distance > 0.05 || center < -opening.width / 2 || center > wallLength + opening.width / 2) {
      return;
    }
    const span = {
      start: Math.max(0, center - opening.width / 2),
      end: Math.min(wallLength, center + opening.width / 2),
      bottom: Math.max(0, opening.position.y),
      top: Math.min(room.height, opening.position.y + opening.height),
    };
    if (span.start < span.end && span.bottom < span.top) spans.push(span);
  });
  return spans;
}

function sortedUnique(values) {
  return [...new Set(values.map((value) => Number(value.toFixed(6))))].sort((a, b) => a - b);
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

// --- Collisions -------------------------------------------------------------

function buildColliders(document_) {
  colliderSegments = [];
  colliderBoxes = [];
  document_.rooms.forEach((room) => {
    const contours = room.contours;
    for (let index = 0; index < contours.length; index += 1) {
      const start = contours[index];
      const end = contours[(index + 1) % contours.length];
      const dx = end.x - start.x;
      const dz = end.z - start.z;
      const length = Math.hypot(dx, dz);
      if (length === 0) continue;
      const spans = openingSpansForWall(room, start, end, length);
      // Doorways (floor-level openings) are passable; everything else blocks.
      const passable = spans
        .filter((span) => span.bottom <= 0.01)
        .sort((a, b) => a.start - b.start);
      let cursor = 0;
      const blockers = [];
      passable.forEach((span) => {
        if (span.start > cursor) blockers.push([cursor, span.start]);
        cursor = Math.max(cursor, span.end);
      });
      if (cursor < length) blockers.push([cursor, length]);
      blockers.forEach(([from, to]) => {
        if (to - from < 0.05) return;
        colliderSegments.push({
          ax: start.x + (dx / length) * from,
          az: start.z + (dz / length) * from,
          bx: start.x + (dx / length) * to,
          bz: start.z + (dz / length) * to,
        });
      });
    }
  });
  document_.objects.forEach((object) => {
    colliderBoxes.push({
      minX: object.position.x - object.dimensions.width / 2 - CAMERA_RADIUS,
      maxX: object.position.x + object.dimensions.width / 2 + CAMERA_RADIUS,
      minZ: object.position.z - object.dimensions.depth / 2 - CAMERA_RADIUS,
      maxZ: object.position.z + object.dimensions.depth / 2 + CAMERA_RADIUS,
    });
  });
}

function distanceToSegment(px, pz, segment) {
  const dx = segment.bx - segment.ax;
  const dz = segment.bz - segment.az;
  const squaredLength = dx * dx + dz * dz;
  let t = squaredLength === 0
    ? 0
    : ((px - segment.ax) * dx + (pz - segment.az) * dz) / squaredLength;
  t = Math.max(0, Math.min(1, t));
  const nearestX = segment.ax + t * dx;
  const nearestZ = segment.az + t * dz;
  return Math.hypot(px - nearestX, pz - nearestZ);
}

function isBlocked(x, z) {
  for (let index = 0; index < colliderSegments.length; index += 1) {
    if (distanceToSegment(x, z, colliderSegments[index]) < CAMERA_RADIUS) return true;
  }
  for (let index = 0; index < colliderBoxes.length; index += 1) {
    const box = colliderBoxes[index];
    if (x > box.minX && x < box.maxX && z > box.minZ && z < box.maxZ) return true;
  }
  return false;
}

/// Slide along walls: try the full move, then each axis alone.
function resolveMove(fromX, fromZ, deltaX, deltaZ) {
  if (!isBlocked(fromX + deltaX, fromZ + deltaZ)) return { x: fromX + deltaX, z: fromZ + deltaZ };
  if (deltaX !== 0 && !isBlocked(fromX + deltaX, fromZ)) return { x: fromX + deltaX, z: fromZ };
  if (deltaZ !== 0 && !isBlocked(fromX, fromZ + deltaZ)) return { x: fromX, z: fromZ + deltaZ };
  return { x: fromX, z: fromZ };
}

// --- Scene lifecycle --------------------------------------------------------

function validateScene(document_) {
  if (!document_ || typeof document_ !== "object") return "Scene document is not an object.";
  if (document_.version !== "1.0") return "Unsupported scene version.";
  if (document_.unit !== "meters") return "Unsupported scene unit.";
  if (!Array.isArray(document_.rooms) || document_.rooms.length === 0) return "Scene has no rooms.";
  for (let index = 0; index < document_.rooms.length; index += 1) {
    const room = document_.rooms[index];
    if (!Array.isArray(room.contours) || room.contours.length < 3) return `Room ${index} has fewer than three contours.`;
    if (!(room.height > 0)) return `Room ${index} has no height.`;
  }
  if (!Array.isArray(document_.objects)) return "Scene objects are missing.";
  return null;
}

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
  const room = document_.rooms[0];
  const points = room.contours;
  const xs = points.map((point) => point.x);
  const zs = points.map((point) => point.z);
  const centerX = (Math.min(...xs) + Math.max(...xs)) / 2;
  const centerZ = (Math.min(...zs) + Math.max(...zs)) / 2;
  // Candidates inside the room, best first: bounding-box center then vertices.
  const candidates = [
    { x: centerX, z: centerZ },
    ...points.map((point) => ({
      x: (point.x + centerX) / 2,
      z: (point.z + centerZ) / 2,
    })),
  ];
  let spawn = candidates.find((candidate) => !isBlocked(candidate.x, candidate.z));
  if (!spawn) spawn = { x: centerX, z: centerZ };
  camera.position.set(spawn.x, EYE_HEIGHT, spawn.z);
  const dx = centerX - spawn.x;
  const dz = centerZ - spawn.z;
  yaw = Math.atan2(-dx, -dz);
  pitch = 0;
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
    buildColliders(document_);
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
    const next = resolveMove(camera.position.x, camera.position.z, deltaX, deltaZ);
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
