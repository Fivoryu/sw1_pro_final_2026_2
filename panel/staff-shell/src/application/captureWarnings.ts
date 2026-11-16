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

/** Measures recorded as assumed (not measured) that the agent has not confirmed. */
export function pendingEstimates(scene: SceneDocument): PendingEstimate[] {
  return scene.walls
    .filter((wall) => wall.heightSource === "assumed")
    .map((wall) => ({ wallId: wall.id, height: wall.height }));
}
