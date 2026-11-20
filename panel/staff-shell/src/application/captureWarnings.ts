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
const SCALE_WARNING = /medida de referencia|escala m[eé]trica|unidades arbitrarias|proporcional/i;

export function splitCaptureWarnings(warnings: string[]): CaptureWarningGroups {
  const groups: CaptureWarningGroups = { scale: [], other: [] };
  for (const warning of warnings) {
    (SCALE_WARNING.test(warning) ? groups.scale : groups.other).push(warning);
  }
  return groups;
}

export interface PendingOpening {
  openingId: string;
  wallId: string;
  type: "door" | "window";
}

/** Openings a capture recognised with a single signal that the agent has not confirmed. */
export function pendingOpenings(scene: SceneDocument): PendingOpening[] {
  return scene.openings.flatMap((opening) =>
    opening.source === "estimated"
      ? [{ openingId: opening.id, wallId: opening.wallId, type: opening.type }]
      : []);
}

/** The agent confirms a recognised opening: its estimated mark is removed, nothing else changes. */
export function confirmOpening(scene: SceneDocument, openingId: string): SceneDocument {
  if (!scene.openings.some((opening) => opening.id === openingId && opening.source !== undefined)) return scene;
  return {
    ...scene,
    openings: scene.openings.map((opening) => {
      if (opening.id !== openingId) return opening;
      const { source: _source, ...confirmed } = opening;
      return confirmed;
    }),
  };
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
