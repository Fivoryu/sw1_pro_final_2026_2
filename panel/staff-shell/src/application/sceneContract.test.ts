import { describe, expect, it } from "vitest";

import canonicalFixture from "../../../../docs/api/f06-scene-fixture.json";
import { DEFAULT_SCENE_DOCUMENT, roomPolygon } from "./sceneContract";

/**
 * The canonical scene document lives beside the contract (`docs/api`), not in
 * this package: the panel, the backend and the customer app must all accept the
 * same document value. This test fails the moment one surface drifts from it (S6).
 */
describe("scene contract", () => {
  it("keeps the editable starting document identical to the canonical fixture", () => {
    expect(DEFAULT_SCENE_DOCUMENT).toEqual(canonicalFixture);
  });

  it("derives a room polygon by chaining wall endpoints in its wallIds order", () => {
    expect(roomPolygon(DEFAULT_SCENE_DOCUMENT, "room_main")).toEqual([
      { x: 0, z: 0 },
      { x: 4, z: 0 },
      { x: 4, z: 3 },
      { x: 0, z: 3 },
    ]);
  });

  it("returns null for a room whose wall chain is missing or does not close", () => {
    const document = structuredClone(DEFAULT_SCENE_DOCUMENT);
    document.rooms[0].wallIds = ["wall-north", "wall-south", "wall-east", "wall-west"];

    expect(roomPolygon(document, "room_main")).toBeNull();
    expect(roomPolygon(document, "missing-room")).toBeNull();
  });
});
