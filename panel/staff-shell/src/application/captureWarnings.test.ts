import { expect, it } from "vitest";
import { DEFAULT_SCENE_DOCUMENT, type SceneDocument } from "./sceneContract";
import { confirmOpening, confirmWallMeasure, pendingEstimates, pendingOpenings, splitCaptureWarnings } from "./captureWarnings";

it("separates the scale warnings emitted by worker3d from the other warnings", () => {
  const scale = [
    "Sin medida de referencia: el modelo no tiene escala métrica. Las medidas están en unidades arbitrarias y no deben tomarse como metros.",
    "La medida de referencia «Puerta» no pudo ubicarse sobre el piso ajustado; no se aplicó.",
    "La pieza con «Sala» quedó sin medida de referencia: su escala no es métrica ni coincide con la del resto.",
  ];
  const other = ["Pared sin observar entre A y B"];
  expect(splitCaptureWarnings([...scale, ...other])).toEqual({ scale, other });
});

it("lists only walls whose height was assumed as pending estimates", () => {
  const scene: SceneDocument = {
    ...DEFAULT_SCENE_DOCUMENT,
    walls: DEFAULT_SCENE_DOCUMENT.walls.map((wall, index) =>
      ({ ...wall, heightSource: index === 0 ? "assumed" : "manual" })),
  };
  expect(pendingEstimates(scene)).toEqual([{ wallId: DEFAULT_SCENE_DOCUMENT.walls[0]?.id, height: 2.4, source: "assumed" }]);
  expect(pendingEstimates(DEFAULT_SCENE_DOCUMENT)).toEqual([]);
});

it("lists estimated walls too, labelled with their source", () => {
  const scene: SceneDocument = {
    ...DEFAULT_SCENE_DOCUMENT,
    walls: DEFAULT_SCENE_DOCUMENT.walls.map((wall, index) =>
      ({ ...wall, heightSource: index === 0 ? "estimated" : index === 1 ? "assumed" : "wall_point" })),
  };
  expect(pendingEstimates(scene).map(({ wallId, source }) => [wallId, source])).toEqual([
    [DEFAULT_SCENE_DOCUMENT.walls[0]?.id, "estimated"],
    [DEFAULT_SCENE_DOCUMENT.walls[1]?.id, "assumed"],
  ]);
});

it("confirms a measure as manual keeping its height, or corrects it", () => {
  const id = DEFAULT_SCENE_DOCUMENT.walls[0]?.id as string;
  const scene: SceneDocument = {
    ...DEFAULT_SCENE_DOCUMENT,
    walls: DEFAULT_SCENE_DOCUMENT.walls.map((wall) => ({ ...wall, heightSource: "estimated" as const })),
  };
  const confirmed = confirmWallMeasure(scene, id);
  expect(confirmed.walls[0]).toMatchObject({ height: 2.4, heightSource: "manual" });
  expect(confirmed.walls[1]?.heightSource).toBe("estimated");
  expect(confirmWallMeasure(scene, id, 2.65).walls[0]).toMatchObject({ height: 2.65, heightSource: "manual" });
  for (const bad of [0, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
    expect(confirmWallMeasure(scene, id, bad)).toBe(scene);
  }
});

const door = { id: "door-1", wallId: "wall-north", position: 0.5, width: 0.9, height: 2, type: "door" as const };
const sceneWithOpenings: SceneDocument = {
  ...DEFAULT_SCENE_DOCUMENT,
  openings: [
    { ...door, source: "estimated" as const },
    { ...door, id: "window-1", type: "window" as const, sillHeight: 0.9, source: "estimated" as const },
    { ...door, id: "door-2" },
  ],
};

it("lists only the openings the capture recognised with a single signal", () => {
  expect(pendingOpenings(sceneWithOpenings).map(({ openingId, type, wallId }) => [openingId, type, wallId])).toEqual([
    ["door-1", "door", "wall-north"],
    ["window-1", "window", "wall-north"],
  ]);
  expect(pendingOpenings(DEFAULT_SCENE_DOCUMENT)).toEqual([]);
});

it("confirms an opening by clearing its estimated mark and touches nothing else", () => {
  const confirmed = confirmOpening(sceneWithOpenings, "door-1");
  expect(confirmed.openings[0]).toEqual(door);
  expect("source" in (confirmed.openings[0] as object)).toBe(false);
  expect(confirmed.openings[1]).toBe(sceneWithOpenings.openings[1]);
  expect(confirmed.openings[2]).toBe(sceneWithOpenings.openings[2]);
  expect(confirmOpening(sceneWithOpenings, "missing")).toBe(sceneWithOpenings);
});
