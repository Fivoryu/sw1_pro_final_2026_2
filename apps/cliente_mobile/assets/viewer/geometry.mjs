// RoomForge walkthrough geometry (F06.4) — pure functions, no Three.js.
//
// The viewer renders; everything the walkthrough promises about collisions,
// passable doorways and staying inside the flat lives here, so it can be
// exercised by `node --test` (test_js/viewer_geometry.test.mjs) instead of only
// by hand on a phone. Keep this file dependency-free: it is loaded as an ES
// module both by the WebView and by Node.

export const CAMERA_RADIUS = 0.25; // collision margin around the camera

/** Convert a touch offset into a unit joystick vector with a circular clamp. */
export function joystickVector(deltaX, deltaY, range) {
  const distance = Math.hypot(deltaX, deltaY);
  if (!Number.isFinite(distance) || !Number.isFinite(range) || distance === 0 || range <= 0) {
    return { x: 0, y: 0 };
  }
  const scale = Math.min(distance, range) / (distance * range);
  return { x: deltaX * scale, y: deltaY * scale };
}

/** Return an opening's vertical and parametric span along its owning wall. */
export function wallOpeningsForWall(wall, openings) {
  if (!wall || !wall.start || !wall.end) return [];
  const dx = wall.end.x - wall.start.x;
  const dz = wall.end.z - wall.start.z;
  const length = Math.hypot(dx, dz);
  if (length === 0) return [];

  const spans = [];
  (openings || []).forEach((opening) => {
    if (opening.wallId !== wall.id) return;
    const center = opening.position * length;
    const start = Math.max(0, center - opening.width / 2);
    const end = Math.min(length, center + opening.width / 2);
    const bottom = opening.type === "window"
      ? Math.max(0, opening.sillHeight === undefined ? 0.9 : opening.sillHeight)
      : 0;
    const top = Math.min(wall.height, bottom + opening.height);
    if (start < end && bottom < top) spans.push({ start, end, bottom, top });
  });
  return spans;
}

export function sortedUnique(values) {
  return [...new Set(values.map((value) => Number(value.toFixed(6))))].sort((a, b) => a - b);
}

/**
 * Colliders of one scene: wall segments (with floor-level doorway gaps
 * removed) and the boxes of the objects. Furniture keeps its collision even
 * when it is hidden from the commercial selection (F06.4 acceptance).
 */
export function buildColliders(document_) {
  const segments = [];
  const boxes = [];
  const openings = document_.openings || [];
  (document_.walls || []).forEach((wall) => {
    const start = wall.start;
    const end = wall.end;
    const dx = end.x - start.x;
    const dz = end.z - start.z;
    const length = Math.hypot(dx, dz);
    if (length === 0) return;

    const spans = wallOpeningsForWall(wall, openings);
    // Only floor-level openings (doors) are passable; windows remain blockers.
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
      segments.push({
        ax: start.x + (dx / length) * from,
        az: start.z + (dz / length) * from,
        bx: start.x + (dx / length) * to,
        bz: start.z + (dz / length) * to,
        thickness: wall.thickness,
      });
    });
  });
  (document_.objects || []).forEach((object) => {
    boxes.push({
      minX: object.position.x - object.dimensions.width / 2 - CAMERA_RADIUS,
      maxX: object.position.x + object.dimensions.width / 2 + CAMERA_RADIUS,
      minZ: object.position.z - object.dimensions.depth / 2 - CAMERA_RADIUS,
      maxZ: object.position.z + object.dimensions.depth / 2 + CAMERA_RADIUS,
    });
  });
  return { segments, boxes };
}

export function distanceToSegment(px, pz, segment) {
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

export function isBlocked(x, z, colliders) {
  const segments = colliders.segments;
  for (let index = 0; index < segments.length; index += 1) {
    const segment = segments[index];
    const margin = CAMERA_RADIUS + (segment.thickness || 0) / 2;
    if (distanceToSegment(x, z, segment) <= margin) return true;
  }
  const boxes = colliders.boxes;
  for (let index = 0; index < boxes.length; index += 1) {
    const box = boxes[index];
    if (x > box.minX && x < box.maxX && z > box.minZ && z < box.maxZ) return true;
  }
  return false;
}

/** Slide along walls: try the full move, then each axis alone. */
export function resolveMove(fromX, fromZ, deltaX, deltaZ, colliders) {
  if (!isBlocked(fromX + deltaX, fromZ + deltaZ, colliders)) {
    return { x: fromX + deltaX, z: fromZ + deltaZ };
  }
  if (deltaX !== 0 && !isBlocked(fromX + deltaX, fromZ, colliders)) {
    return { x: fromX + deltaX, z: fromZ };
  }
  if (deltaZ !== 0 && !isBlocked(fromX, fromZ + deltaZ, colliders)) {
    return { x: fromX, z: fromZ + deltaZ };
  }
  return { x: fromX, z: fromZ };
}

function isFiniteNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

function hasPointCoordinates(point, dimensions) {
  return Boolean(point) && dimensions.every((dimension) => isFiniteNumber(point[dimension]));
}

function samePoint(left, right) {
  return Math.abs(left.x - right.x) <= 1e-9 && Math.abs(left.z - right.z) <= 1e-9;
}

/** Why this v2 document cannot be rendered, or null when it can. */
export function validateScene(document_) {
  if (!document_ || typeof document_ !== "object") return "Scene document is not an object.";
  if (document_.version !== "2.0") return "Unsupported scene version.";
  if (document_.unit !== "meters") return "Unsupported scene unit.";
  if (!Array.isArray(document_.walls) || document_.walls.length === 0) return "Scene has no walls.";

  const wallIds = new Set();
  for (let index = 0; index < document_.walls.length; index += 1) {
    const wall = document_.walls[index];
    if (!wall || typeof wall !== "object") return `walls[${index}] must be an object.`;
    if (typeof wall.id !== "string" || wall.id.length === 0) return `walls[${index}].id is required.`;
    if (wallIds.has(wall.id)) return "Duplicate id in walls.";
    wallIds.add(wall.id);
    if (!hasPointCoordinates(wall.start, ["x", "z"])) return `walls[${index}].start must have numeric x and z.`;
    if (!hasPointCoordinates(wall.end, ["x", "z"])) return `walls[${index}].end must have numeric x and z.`;
    if (samePoint(wall.start, wall.end)) return `walls[${index}].start must differ from end.`;
    if (!(isFiniteNumber(wall.height) && wall.height > 0)) {
      return `walls[${index}].height must be greater than 0.`;
    }
    if (!(isFiniteNumber(wall.thickness) && wall.thickness > 0)) {
      return `walls[${index}].thickness must be greater than 0.`;
    }
  }

  if (!Array.isArray(document_.openings)) return "Scene openings are missing.";
  const openingIds = new Set();
  for (let index = 0; index < document_.openings.length; index += 1) {
    const opening = document_.openings[index];
    if (!opening || typeof opening !== "object") return `openings[${index}] must be an object.`;
    if (typeof opening.id !== "string" || opening.id.length === 0) {
      return `openings[${index}].id is required.`;
    }
    if (openingIds.has(opening.id)) return "Duplicate id in openings.";
    openingIds.add(opening.id);
    if (!wallIds.has(opening.wallId)) {
      return `openings[${index}].wallId must refer to an existing wall.`;
    }
    if (!(isFiniteNumber(opening.position) && opening.position >= 0 && opening.position <= 1)) {
      return `openings[${index}].position must be between 0 and 1.`;
    }
    if (!(isFiniteNumber(opening.width) && opening.width > 0)) {
      return `openings[${index}].width must be greater than 0.`;
    }
    if (!(isFiniteNumber(opening.height) && opening.height > 0)) {
      return `openings[${index}].height must be greater than 0.`;
    }
    if (opening.type !== "door" && opening.type !== "window") {
      return `openings[${index}].type must be door or window.`;
    }
    if (opening.sillHeight !== undefined &&
      !(isFiniteNumber(opening.sillHeight) && opening.sillHeight >= 0)) {
      return `openings[${index}].sillHeight must be at least 0.`;
    }
  }

  if (!Array.isArray(document_.objects)) return "Scene objects are missing.";
  const objectIds = new Set();
  for (let index = 0; index < document_.objects.length; index += 1) {
    const object = document_.objects[index];
    if (!object || typeof object !== "object") return `objects[${index}] must be an object.`;
    if (typeof object.id !== "string" || object.id.length === 0) return `objects[${index}].id is required.`;
    if (objectIds.has(object.id)) return "Duplicate id in objects.";
    objectIds.add(object.id);
    if (!object.position || !["x", "y", "z"].every((axis) => isFiniteNumber(object.position[axis]))) {
      return `objects[${index}].position must have numeric x, y, and z.`;
    }
    if (!object.dimensions || !["width", "height", "depth"].every((dimension) =>
      isFiniteNumber(object.dimensions[dimension]) && object.dimensions[dimension] > 0)) {
      return `objects[${index}].dimensions must be greater than 0.`;
    }
  }
  return null;
}

/** Build a room floor polygon by following its ordered wall cycle. */
export function roomPolygon(document_, roomId) {
  if (!document_ || !Array.isArray(document_.rooms) || !Array.isArray(document_.walls)) return null;
  const room = document_.rooms.find((candidate) => candidate && candidate.id === roomId);
  if (!room || !Array.isArray(room.wallIds) || room.wallIds.length < 3) return null;
  if (new Set(room.wallIds).size !== room.wallIds.length) return null;

  const wallsById = new Map(document_.walls.map((wall) => [wall.id, wall]));
  const walls = room.wallIds.map((wallId) => wallsById.get(wallId));
  if (walls.some((wall) => !wall ||
    !hasPointCoordinates(wall.start, ["x", "z"]) ||
    !hasPointCoordinates(wall.end, ["x", "z"]))) return null;

  // A wall shared by two rooms runs backwards in one of them, so each wall may
  // be walked in either direction (same rule as the panel's roomPolygon).
  for (const reverseFirst of [false, true]) {
    const first = walls[0];
    const start = reverseFirst ? first.end : first.start;
    let current = reverseFirst ? first.start : first.end;
    const points = [{ x: start.x, z: start.z }];
    let closed = true;
    for (let index = 1; index < walls.length; index += 1) {
      const wall = walls[index];
      points.push({ x: current.x, z: current.z });
      if (samePoint(wall.start, current)) {
        current = wall.end;
      } else if (samePoint(wall.end, current)) {
        current = wall.start;
      } else {
        closed = false;
        break;
      }
    }
    if (closed && samePoint(current, start)) return points;
  }
  return null;
}

/**
 * Where the walkthrough starts and which way it looks: the bounding-box centre
 * of all wall endpoints when free, otherwise the first free midpoint between
 * that centre and a wall endpoint.
 */
export function spawnPoint(document_, colliders) {
  const points = (document_.walls || []).flatMap((wall) => [wall.start, wall.end]);
  if (points.length === 0) return { x: 0, z: 0, yaw: 0, pitch: 0 };
  const xs = points.map((point) => point.x);
  const zs = points.map((point) => point.z);
  const centerX = (Math.min(...xs) + Math.max(...xs)) / 2;
  const centerZ = (Math.min(...zs) + Math.max(...zs)) / 2;
  const candidates = [
    { x: centerX, z: centerZ },
    ...points.map((point) => ({
      x: (point.x + centerX) / 2,
      z: (point.z + centerZ) / 2,
    })),
  ];
  let spawn = candidates.find((candidate) => !isBlocked(candidate.x, candidate.z, colliders));
  if (!spawn) spawn = { x: centerX, z: centerZ };
  const dx = centerX - spawn.x;
  const dz = centerZ - spawn.z;
  return {
    x: spawn.x,
    z: spawn.z,
    yaw: Math.atan2(-dx, -dz),
    pitch: 0,
  };
}
