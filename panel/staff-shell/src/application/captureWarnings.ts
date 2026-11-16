import type { SceneDocument } from "./sceneContract";

export interface CaptureWarningGroups {
  /** Warnings about the metric scale of the reconstruction. */
  scale: string[];
  other: string[];
}

export interface PendingEstimate {
  wallId: string;
  /** Wall height in meters as recorded by the capture; it was assumed, not measured. */
  height: number;
  /** `estimated`: derived from the video; `assumed`: not measured at all. */
  source: "estimated" | "assumed";
}

// Texts emitted by worker3d/reconstruct_video.py when the scale could not be anchored.
const SCALE_WARNING = /medida de referencia|escala m[eé]trica|unidades arbitrarias/i;

export function splitCaptureWarnings(warnings: string[]): CaptureWarningGroups {
  const groups: CaptureWarningGroups = { scale: [], other: [] };
  for (const warning of warnings) {
    (SCALE_WARNING.test(warning) ? groups.scale : groups.other).push(warning);
  }
  return groups;
}

/** Measures recorded as estimated or assumed (not measured) that the agent has not confirmed. */
export function pendingEstimates(scene: SceneDocument): PendingEstimate[] {
  return scene.walls.flatMap((wall) =>
    wall.heightSource === "estimated" || wall.heightSource === "assumed"
      ? [{ wallId: wall.id, height: wall.height, source: wall.heightSource }]
      : []);
}

/**
 * The agent confirms a wall height (it becomes `manual`), optionally correcting it.
 * An invalid correction (not a finite positive number) leaves the scene untouched.
 */
export function confirmWallMeasure(scene: SceneDocument, wallId: string, height?: number): SceneDocument {
  if (height !== undefined && !(Number.isFinite(height) && height > 0)) return scene;
  return {
    ...scene,
    walls: scene.walls.map((wall) =>
      wall.id === wallId ? { ...wall, height: height ?? wall.height, heightSource: "manual" as const } : wall),
  };
}
