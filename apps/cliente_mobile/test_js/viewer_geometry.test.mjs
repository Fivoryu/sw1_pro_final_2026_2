// RoomForge walkthrough geometry (F06.4) — pure functions, no Three.js.
// Run with: node --test test_js/viewer_geometry.test.mjs

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import {
  CAMERA_RADIUS,
  buildColliders,
  distanceToSegment,
  isBlocked,
  openingSpansForWall,
  resolveMove,
  spawnPoint,
  validateScene,
} from "../assets/viewer/geometry.mjs";

const FIXTURE = JSON.parse(
  readFileSync(new URL("../../../docs/api/f06-scene-fixture.json", import.meta.url), "utf8"),
);

function collidersFor(document = FIXTURE) {
  return buildColliders(document);
}

/** Floats coming from the contract are never compared bit-exactly. */
function closeTo(actual, expected, message) {
  assert.ok(
    Math.abs(actual - expected) < 1e-9,
    message ? `${message}: expected ${expected}, got ${actual}` : `expected ${expected}, got ${actual}`,
  );
}

test("the canonical fixture is a valid scene", () => {
  assert.equal(validateScene(FIXTURE), null);
});

test("validateScene rejects what the viewer cannot render", () => {
  assert.match(validateScene(null), /not an object/);
  assert.match(validateScene({ ...FIXTURE, version: "2.0" }), /Unsupported scene version/);
  assert.match(validateScene({ ...FIXTURE, unit: "feet" }), /Unsupported scene unit/);
  assert.match(validateScene({ ...FIXTURE, rooms: [] }), /no rooms/);
  assert.match(validateScene({ ...FIXTURE, objects: undefined }), /objects are missing/);
  const flat = { ...FIXTURE, rooms: [{ ...FIXTURE.rooms[0], height: 0 }] };
  assert.match(validateScene(flat), /has no height/);
  const triangle = {
    ...FIXTURE,
    rooms: [
      {
        ...FIXTURE.rooms[0],
        contours: [
          { x: 0, z: 0 },
          { x: 1, z: 0 },
        ],
      },
    ],
  };
  assert.match(validateScene(triangle), /fewer than three contours/);
});

test("the middle of the room is walkable", () => {
  assert.equal(isBlocked(2, 1.5, collidersFor()), false);
});

test("walls block the camera before it walks through them", () => {
  const colliders = collidersFor();
  // The z=0 wall away from the doorway, and the x=4 wall.
  assert.equal(isBlocked(0.5, 0, colliders), true);
  assert.equal(isBlocked(4, 1.5, colliders), true);
  // The camera radius is the margin, not a point.
  assert.equal(isBlocked(0.5, CAMERA_RADIUS / 2, colliders), true);
  assert.equal(isBlocked(0.5, CAMERA_RADIUS + 0.05, colliders), false);
});

test("the door opening is passable and the rest of its wall is not", () => {
  const colliders = collidersFor();
  // door_1 sits at x=2 on the z=0 wall, 0.9 m wide: x in [1.55, 2.45].
  assert.equal(isBlocked(2, 0, colliders), false);
  assert.equal(isBlocked(2, -0.5, colliders), false, "the customer can step through the door");
  assert.equal(isBlocked(1.4, 0, colliders), true);
  assert.equal(isBlocked(2.6, 0, colliders), true);
});

test("furniture blocks the camera even though it is selectable", () => {
  const colliders = collidersFor();
  for (const object of FIXTURE.objects) {
    assert.equal(
      isBlocked(object.position.x, object.position.z, colliders),
      true,
      `${object.id} must keep its collision`,
    );
  }
});

test("a blocked move slides along the wall instead of stopping dead", () => {
  const colliders = collidersFor();
  // Walking diagonally into the x=4 wall keeps the z component.
  const slid = resolveMove(3.7, 1.5, 0.5, 0.2, colliders);
  closeTo(slid.x, 3.7, "the blocked axis must not move");
  closeTo(slid.z, 1.7, "the free axis must keep its step");
});

test("a free move is applied as requested", () => {
  const colliders = collidersFor();
  const moved = resolveMove(2, 0.7, 0.1, 0.1, colliders);
  closeTo(moved.x, 2.1);
  closeTo(moved.z, 0.8);
});

test("a move into a corner keeps the camera where it was", () => {
  const colliders = collidersFor();
  // A real frame never steps further than WALK_SPEED * 0.1 = 0.18 m.
  const stuck = resolveMove(0.3, 0.3, -0.1, -0.1, colliders);
  closeTo(stuck.x, 0.3);
  closeTo(stuck.z, 0.3);
});

test("walking into a wall never leaves the room", () => {
  const colliders = collidersFor();
  let position = { x: 2, z: 1.5 };
  for (let step = 0; step < 40; step += 1) {
    position = resolveMove(position.x, position.z, -0.1, 0, colliders);
  }
  assert.equal(isBlocked(position.x, position.z, colliders), false);
  assert.ok(
    position.x >= CAMERA_RADIUS - 1e-9,
    `the camera must stop at the radius, got x=${position.x}`,
  );
  assert.ok(position.x < 1, "the camera must have walked toward the wall");
});

test("the spawn point is inside the room and looks at its centre", () => {
  const colliders = collidersFor();
  const spawn = spawnPoint(FIXTURE, colliders);
  assert.equal(isBlocked(spawn.x, spawn.z, colliders), false);
  assert.ok(Number.isFinite(spawn.yaw));
  closeTo(spawn.pitch, 0);
});

test("a spawn candidate blocked by furniture is skipped", () => {
  const sofa = {
    ...FIXTURE.objects[0],
    id: "sofa_at_the_centre",
    position: { x: 2, y: 0, z: 1.5 },
    dimensions: { width: 1, height: 0.5, depth: 1 },
  };
  const crowded = { ...FIXTURE, objects: [sofa] };
  const colliders = collidersFor(crowded);

  const spawn = spawnPoint(crowded, colliders);

  assert.equal(isBlocked(spawn.x, spawn.z, colliders), false);
  assert.ok(
    Math.hypot(spawn.x - 2, spawn.z - 1.5) > 0.5,
    "the camera must not spawn on top of the furniture",
  );
});

test("opening spans are computed only for the wall that owns the opening", () => {
  const room = FIXTURE.rooms[0];
  const doorWall = openingSpansForWall(room, { x: 0, z: 0 }, { x: 4, z: 0 }, 4);
  assert.equal(doorWall.length, 1);
  closeTo(doorWall[0].start, 1.55);
  closeTo(doorWall[0].end, 2.45);
  closeTo(doorWall[0].bottom, 0);
  closeTo(doorWall[0].top, 2.1);

  const oppositeWall = openingSpansForWall(room, { x: 4, z: 3 }, { x: 0, z: 3 }, 4);
  assert.deepEqual(oppositeWall, []);
});

test("distanceToSegment clamps to the endpoints", () => {
  const segment = { ax: 0, az: 0, bx: 2, bz: 0 };
  closeTo(distanceToSegment(1, 1, segment), 1);
  closeTo(distanceToSegment(-1, 0, segment), 1);
  closeTo(distanceToSegment(3, 0, segment), 1);
});
