export interface ScenePoint2D {
  x: number;
  z: number;
}

export interface ScenePoint3D extends ScenePoint2D {
  y: number;
}

export interface SceneDimensions {
  width: number;
  height: number;
  depth: number;
}

export interface SceneWall {
  id: string;
  start: ScenePoint2D;
  end: ScenePoint2D;
  height: number;
  thickness: number;
  color?: string;
}

export interface SceneOpeningV2 {
  id: string;
  wallId: string;
  /** Center along the referenced wall, measured from its start as a fraction. */
  position: number;
  width: number;
  height: number;
  type: "door" | "window";
  sillHeight?: number;
}

export interface SceneRoomV2 {
  id: string;
  name?: string;
  wallIds: string[];
  color?: string;
}

export interface SceneObject {
  id: string;
  type: string;
  position: ScenePoint3D;
  dimensions: SceneDimensions;
  color: string;
}

export interface SceneDocument {
  version: "2.0";
  unit: "meters";
  walls: SceneWall[];
  openings: SceneOpeningV2[];
  rooms: SceneRoomV2[];
  objects: SceneObject[];
}

function samePoint(left: ScenePoint2D, right: ScenePoint2D): boolean {
  return left.x === right.x && left.z === right.z;
}

/**
 * Derive a room's polygon by walking the referenced wall endpoints in order.
 * A malformed, missing, or non-closing wall chain has no renderable polygon.
 */
export function roomPolygon(document: SceneDocument, roomId: string): ScenePoint2D[] | null {
  const room = document.rooms.find((candidate) => candidate.id === roomId);
  if (!room || room.wallIds.length < 3 || new Set(room.wallIds).size !== room.wallIds.length) {
    return null;
  }

  const wallsById = new Map(document.walls.map((wall) => [wall.id, wall]));
  const walls = room.wallIds.map((wallId) => wallsById.get(wallId));
  if (walls.some((wall) => !wall)) return null;

  const firstWall = walls[0];
  if (!firstWall || samePoint(firstWall.start, firstWall.end)) return null;

  for (const reverseFirst of [false, true]) {
    const start = reverseFirst ? firstWall.end : firstWall.start;
    let current = reverseFirst ? firstWall.start : firstWall.end;
    const polygon: ScenePoint2D[] = [{ ...start }, { ...current }];
    let valid = true;

    for (let index = 1; index < walls.length; index += 1) {
      const wall = walls[index];
      if (!wall || samePoint(wall.start, wall.end)) {
        valid = false;
        break;
      }
      if (samePoint(wall.start, current)) {
        current = wall.end;
      } else if (samePoint(wall.end, current)) {
        current = wall.start;
      } else {
        valid = false;
        break;
      }
      polygon.push({ ...current });
    }

    if (valid && samePoint(current, start)) {
      polygon.pop();
      return polygon;
    }
  }

  return null;
}

/**
 * A contract-valid editable starting point used before a listing has a saved scene.
 *
 * It must stay equal to the canonical fixture shared by every surface,
 * `docs/api/f06-scene-fixture.json`; `sceneContract.test.ts` fails the moment
 * the two drift apart.
 */
export const DEFAULT_SCENE_DOCUMENT: SceneDocument = {
  version: "2.0",
  unit: "meters",
  walls: [
    {
      id: "wall-north",
      start: { x: 0, z: 0 },
      end: { x: 4, z: 0 },
      height: 2.4,
      thickness: 0.15,
    },
    {
      id: "wall-east",
      start: { x: 4, z: 0 },
      end: { x: 4, z: 3 },
      height: 2.4,
      thickness: 0.15,
    },
    {
      id: "wall-south",
      start: { x: 4, z: 3 },
      end: { x: 0, z: 3 },
      height: 2.4,
      thickness: 0.15,
    },
    {
      id: "wall-west",
      start: { x: 0, z: 3 },
      end: { x: 0, z: 0 },
      height: 2.4,
      thickness: 0.15,
    },
  ],
  openings: [
    {
      id: "door_1",
      wallId: "wall-north",
      position: 0.5,
      width: 0.9,
      height: 2.1,
      type: "door",
    },
  ],
  rooms: [
    {
      id: "room_main",
      name: "Estar",
      wallIds: ["wall-north", "wall-east", "wall-south", "wall-west"],
    },
  ],
  objects: [
    {
      id: "ref_cube_1",
      type: "placeholder",
      position: { x: 1, y: 0, z: 1 },
      dimensions: { width: 0.5, height: 0.5, depth: 0.5 },
      color: "red",
    },
    {
      id: "ref_cube_2",
      type: "placeholder",
      position: { x: 3, y: 0, z: 1 },
      dimensions: { width: 0.5, height: 0.5, depth: 0.5 },
      color: "green",
    },
    {
      id: "ref_cube_3",
      type: "placeholder",
      position: { x: 2, y: 0, z: 2 },
      dimensions: { width: 0.5, height: 0.5, depth: 0.5 },
      color: "blue",
    },
  ],
};
