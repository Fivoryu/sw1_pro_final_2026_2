import { expect, it } from "vitest";
import { DEFAULT_SCENE_DOCUMENT, type SceneDocument } from "./sceneContract";
import { pendingEstimates, splitCaptureWarnings } from "./captureWarnings";

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
  expect(pendingEstimates(scene)).toEqual([{ wallId: DEFAULT_SCENE_DOCUMENT.walls[0]?.id, height: 2.4 }]);
  expect(pendingEstimates(DEFAULT_SCENE_DOCUMENT)).toEqual([]);
});
