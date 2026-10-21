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
  resolveMove,
  roomPolygon,
  spawnPoint,
  validateScene,
  wallOpeningsForWall,
} from "../assets/viewer/geometry.mjs";
import * as viewerGeometry from "../assets/viewer/geometry.mjs";

const FIXTURE = JSON.parse(
  readFileSync(new URL("../../../docs/api/f06-scene-fixture.json", import.meta.url), "utf8"),
);
const VIEWER_HTML = readFileSync(new URL("../assets/viewer/index.html", import.meta.url), "utf8");

function collidersFor(document_ = FIXTURE) {
  return buildColliders(document_);
}

/** Floats coming from the contract are never compared bit-exactly. */
function closeTo(actual, expected, message) {
  assert.ok(
    Math.abs(actual - expected) < 1e-9,
    message ? `${message}: expected ${expected}, got ${actual}` : `expected ${expected}, got ${actual}`,
  );
}

test("joystick input normalizes diagonals and clamps at full deflection", () => {
  assert.deepEqual(viewerGeometry.joystickVector?.(30, 40, 50), { x: 0.6, y: 0.8 });
  assert.deepEqual(viewerGeometry.joystickVector?.(0, 0, 50), { x: 0, y: 0 });
  assert.deepEqual(viewerGeometry.joystickVector?.(100, 0, 50), { x: 1, y: 0 });
  assert.deepEqual(viewerGeometry.joystickVector?.(0, -25, 50), { x: 0, y: -0.5 });
});

test("the viewer provides a labeled, touch-sized joystick overlay", () => {
  const buttonStart = VIEWER_HTML.indexOf('<button id="joystick-control"');
  assert.notEqual(buttonStart, -1, "the scene includes a visible joystick button");
  const buttonEnd = VIEWER_HTML.indexOf("</button>", buttonStart);
  assert.notEqual(buttonEnd, -1, "the joystick button is closed");
  const joystickButton = VIEWER_HTML.slice(buttonStart, buttonEnd);
  assert.ok(joystickButton.includes('aria-label="Joystick de movimiento"'));
  assert.ok(joystickButton.includes('id="joystick-knob"'));

  const styleStart = VIEWER_HTML.indexOf("#joystick-control");
  assert.notEqual(styleStart, -1, "the joystick has a dedicated CSS rule");
  const ruleStart = VIEWER_HTML.indexOf("{", styleStart);
  const ruleEnd = VIEWER_HTML.indexOf("}", ruleStart);
  const styles = VIEWER_HTML.slice(ruleStart + 1, ruleEnd);
  assert.ok(styles.includes("width: 144px"));
  assert.ok(styles.includes("height: 144px"));
  assert.ok(styles.includes("touch-action: none"));
});

test("the canonical v2 fixture is a valid scene", () => {
  assert.equal(validateScene(FIXTURE), null);
});

test("v2 validation checks wall geometry, opening references, and duplicate ids", () => {
  assert.match(validateScene(null), /not an object/);
  assert.match(validateScene({ ...FIXTURE, version: "1.0" }), /Unsupported scene version/);
  assert.match(validateScene({ ...FIXTURE, unit: "feet" }), /Unsupported scene unit/);
  assert.match(validateScene({ ...FIXTURE, walls: [] }), /walls/);

  const degenerateWall = structuredClone(FIXTURE);
  degenerateWall.walls[2].end = { ...degenerateWall.walls[2].start };
  assert.equal(validateScene(degenerateWall), "walls[2].start must differ from end.");

  const zeroHeight = structuredClone(FIXTURE);
  zeroHeight.walls[0].height = 0;
  assert.match(validateScene(zeroHeight), /walls\[0\]\.height/);
  const zeroThickness = structuredClone(FIXTURE);
  zeroThickness.walls[0].thickness = 0;
  assert.match(validateScene(zeroThickness), /walls\[0\]\.thickness/);

  const unknownWall = structuredClone(FIXTURE);
  unknownWall.openings[0].wallId = "wall-unknown";
  assert.equal(
    validateScene(unknownWall),
    "openings[0].wallId must refer to an existing wall.",
  );

  const outOfRange = structuredClone(FIXTURE);
  outOfRange.openings[0].position = 1.1;
  assert.match(validateScene(outOfRange), /openings\[0\]\.position/);

  const duplicateWall = structuredClone(FIXTURE);
  duplicateWall.walls[1].id = duplicateWall.walls[0].id;
  assert.match(validateScene(duplicateWall), /duplicate.*wall/i);
});

test("rooms are optional complement metadata and objects remain required", () => {
  assert.equal(validateScene({ ...FIXTURE, rooms: undefined }), null);
  assert.equal(validateScene({ ...FIXTURE, rooms: [{ id: "incomplete" }] }), null);
  assert.match(validateScene({ ...FIXTURE, objects: undefined }), /objects are missing/);
});

test("the middle of the room is walkable", () => {
  assert.equal(isBlocked(2, 1.5, collidersFor()), false);
});

test("wall collision margin includes half the painted wall thickness", () => {
  const colliders = collidersFor();
  const northWall = colliders.segments.find((segment) => segment.az === 0);
  assert.ok(northWall, "the north wall has a blocking segment away from its door");
  closeTo(northWall.thickness, 0.15);
  assert.equal(isBlocked(0.5, CAMERA_RADIUS + northWall.thickness / 2 - 0.001, colliders), true);
  assert.equal(isBlocked(0.5, CAMERA_RADIUS + northWall.thickness / 2 + 0.01, colliders), false);
  assert.equal(isBlocked(4 - CAMERA_RADIUS - 0.001, 1.5, colliders), true);
});

test("the wall-north door is passable and the rest of that wall is not", () => {
  const colliders = collidersFor();
  const north = FIXTURE.walls.find((wall) => wall.id === "wall-north");
  const spans = wallOpeningsForWall(north, FIXTURE.openings);
  assert.equal(spans.length, 1);
  closeTo(spans[0].start, 1.55);
  closeTo(spans[0].end, 2.45);
  closeTo(spans[0].bottom, 0);
  closeTo(spans[0].top, 2.1);

  assert.equal(isBlocked(2, 0, colliders), false);
  assert.equal(isBlocked(2, -0.5, colliders), false, "the customer can step through the door");
  assert.equal(isBlocked(1.4, 0, colliders), true);
  assert.equal(isBlocked(2.6, 0, colliders), true);
});

test("a window above a one-metre sill does not create a floor-level gap", () => {
  const withWindow = structuredClone(FIXTURE);
  withWindow.openings = [{
    id: "window_1",
    wallId: "wall-north",
    position: 0.5,
    width: 0.9,
    height: 1,
    type: "window",
    sillHeight: 1,
  }];
  assert.equal(validateScene(withWindow), null);
  const colliders = collidersFor(withWindow);
  const windowSpan = wallOpeningsForWall(withWindow.walls[0], withWindow.openings)[0];
  closeTo(windowSpan.bottom, 1);
  closeTo(windowSpan.top, 2);
  assert.equal(isBlocked(2, 0, colliders), true);
});

test("openings are owned by wallId and their spans are clamped to the wall", () => {
  const north = FIXTURE.walls[0];
  const opening = { ...FIXTURE.openings[0], wallId: "wall-east" };
  assert.deepEqual(wallOpeningsForWall(north, [opening]), []);

  const nearEnd = { ...opening, wallId: north.id, position: 0.05, width: 1 };
  const [span] = wallOpeningsForWall(north, [nearEnd]);
  closeTo(span.start, 0);
  closeTo(span.end, 0.7);
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
  const slid = resolveMove(3.6, 1.5, 0.5, 0.2, colliders);
  closeTo(slid.x, 3.6, "the blocked axis must not move");
  closeTo(slid.z, 1.7, "the free axis must keep its step");
});

test("a free move is applied as requested", () => {
  const moved = resolveMove(2, 0.7, 0.1, 0.1, collidersFor());
  closeTo(moved.x, 2.1);
  closeTo(moved.z, 0.8);
});

test("a move into a corner keeps the camera where it was", () => {
  const stuck = resolveMove(0.3, 0.3, -0.1, -0.1, collidersFor());
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
    position.x >= CAMERA_RADIUS + FIXTURE.walls[3].thickness / 2 - 1e-9,
    `the camera must stop at the painted edge margin, got x=${position.x}`,
  );
  assert.ok(position.x < 1, "the camera must have walked toward the wall");
});

test("the spawn point uses the wall bounds and looks toward their centre", () => {
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

test("distanceToSegment clamps to the endpoints", () => {
  const segment = { ax: 0, az: 0, bx: 2, bz: 0 };
  closeTo(distanceToSegment(1, 1, segment), 1);
  closeTo(distanceToSegment(-1, 0, segment), 1);
  closeTo(distanceToSegment(3, 0, segment), 1);
});

test("roomPolygon chains room_main from the fixture and rejects a broken chain", () => {
  assert.deepEqual(roomPolygon(FIXTURE, "room_main"), [
    { x: 0, z: 0 },
    { x: 4, z: 0 },
    { x: 4, z: 3 },
    { x: 0, z: 3 },
  ]);

  const brokenChain = structuredClone(FIXTURE);
  brokenChain.walls[1].start = { x: 5, z: 0 };
  assert.equal(roomPolygon(brokenChain, "room_main"), null);
});

// F07: the scene the capture app builds (two rooms joined by one door) walks end to end.
const CAPTURED = JSON.parse(
  readFileSync(new URL("../../../docs/api/f07-captured-scene-fixture.json", import.meta.url), "utf8"),
);

function walkEast(fromX, z, untilX, colliders) {
  let position = { x: fromX, z };
  for (let step = 0; step < 200 && position.x < untilX; step += 1) {
    const next = resolveMove(position.x, position.z, 0.1, 0, colliders);
    if (next.x === position.x && next.z === position.z) break;
    position = next;
  }
  return position;
}

test("captured two-room scene is renderable and every room closes", () => {
  assert.equal(validateScene(CAPTURED), null);
  for (const room of CAPTURED.rooms) {
    assert.ok(roomPolygon(CAPTURED, room.id), `${room.id} must derive a closed polygon`);
  }
});

test("captured scene lets the visitor cross the shared door into the next room", () => {
  const colliders = buildColliders(CAPTURED);

  const throughDoor = walkEast(2, 1.5, 5.5, colliders);
  assert.ok(throughDoor.x >= 5.5, `door must be passable, stopped at x=${throughDoor.x}`);

  const besideDoor = walkEast(2, 0.5, 5.5, colliders);
  assert.ok(besideDoor.x < 4.075, `the shared wall must block away from the door, reached x=${besideDoor.x}`);
});
