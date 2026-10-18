import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { DEFAULT_SCENE_DOCUMENT } from "./sceneContract";

/**
 * The canonical scene document lives beside the contract (`docs/api`), not in
 * this package: the panel, the backend and the customer app must all accept the
 * same bytes. This test fails the moment one surface drifts from it (S13).
 */
const CANONICAL_FIXTURE = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../../docs/api/f06-scene-fixture.json",
);

function canonicalFixture(): unknown {
  return JSON.parse(readFileSync(CANONICAL_FIXTURE, "utf8"));
}

describe("scene contract", () => {
  it("keeps the editable starting document identical to the canonical fixture", () => {
    expect(DEFAULT_SCENE_DOCUMENT).toEqual(canonicalFixture());
  });
});
