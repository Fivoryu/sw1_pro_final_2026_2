// RoomForge walkthrough geometry (F06.4) — pure functions, no Three.js.
//
// The viewer renders; everything the walkthrough promises about collisions,
// passable doorways and staying inside the flat lives here, so it can be
// exercised by `node --test` (test_js/viewer_geometry.test.mjs) instead of only
// by hand on a phone. Keep this file dependency-free: it is loaded as an ES
// module both by the WebView and by Node.

export const CAMERA_RADIUS = 0.25; // collision margin around the camera

/** The door/window spans a wall must leave open, in metres from its start. */
export function openingSpansForWall(room, start, end, wallLength) {
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

export function sortedUnique(values) {
  return [...new Set(values.map((value) => Number(value.toFixed(6))))].sort((a, b) => a - b);
}

/**
 * Colliders of one scene: wall segments (with their doorway gaps already
 * removed) and the boxes of the objects. Furniture keeps its collision even
 * when it is hidden from the commercial selection (F06.4 acceptance).
 */
export function buildColliders(document_) {
  const segments = [];
  const boxes = [];
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
        segments.push({
          ax: start.x + (dx / length) * from,
          az: start.z + (dz / length) * from,
          bx: start.x + (dx / length) * to,
          bz: start.z + (dz / length) * to,
        });
      });
    }
  });
  document_.objects.forEach((object) => {
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
    if (distanceToSegment(x, z, segments[index]) < CAMERA_RADIUS) return true;
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

/** Why this document cannot be rendered, or null when it can. */
export function validateScene(document_) {
  if (!document_ || typeof document_ !== "object") return "Scene document is not an object.";
  if (document_.version !== "1.0") return "Unsupported scene version.";
  if (document_.unit !== "meters") return "Unsupported scene unit.";
  if (!Array.isArray(document_.rooms) || document_.rooms.length === 0) return "Scene has no rooms.";
  for (let index = 0; index < document_.rooms.length; index += 1) {
    const room = document_.rooms[index];
    if (!Array.isArray(room.contours) || room.contours.length < 3) {
      return `Room ${index} has fewer than three contours.`;
    }
    if (!(room.height > 0)) return `Room ${index} has no height.`;
  }
  if (!Array.isArray(document_.objects)) return "Scene objects are missing.";
  return null;
}

/**
 * Where the walkthrough starts and which way it looks: the bounding-box centre
 * of the first room when it is free, otherwise the first free midpoint between
 * that centre and a contour vertex.
 */
export function spawnPoint(document_, colliders) {
  const room = document_.rooms[0];
  const points = room.contours;
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
