import { describe, expect, it } from "vitest";

import canonicalFixture from "../../../../docs/api/f06-scene-fixture.json";
import { DEFAULT_SCENE_DOCUMENT } from "./sceneContract";

/**
 * The canonical scene document lives beside the contract (`docs/api`), not in
 * this package: the panel, the backend and the customer app must all accept the
 * same bytes. This test fails the moment one surface drifts from it (S13).
 */
describe("scene contract", () => {
  it("keeps the editable starting document identical to the canonical fixture", () => {
    expect(DEFAULT_SCENE_DOCUMENT).toEqual(canonicalFixture);
  });
});
