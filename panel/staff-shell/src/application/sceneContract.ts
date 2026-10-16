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

export interface SceneOpening {
  id: string;
  type: string;
  position: ScenePoint3D;
  width: number;
  height: number;
}

export interface SceneRoom {
  id: string;
  height: number;
  contours: ScenePoint2D[];
  openings: SceneOpening[];
}

export interface SceneObject {
  id: string;
  type: string;
  position: ScenePoint3D;
  dimensions: SceneDimensions;
  color: string;
}

export interface SceneDocument {
  version: "1.0";
  unit: "meters";
  rooms: SceneRoom[];
  objects: SceneObject[];
}

/** A contract-valid editable starting point used before a listing has a saved scene. */
export const DEFAULT_SCENE_DOCUMENT: SceneDocument = {
  version: "1.0",
  unit: "meters",
  rooms: [
    {
      id: "room_main",
      height: 2.4,
      contours: [
        { x: 0, z: 0 },
        { x: 4, z: 0 },
        { x: 4, z: 3 },
        { x: 0, z: 3 },
      ],
      openings: [
        {
          id: "door_1",
          type: "door",
          position: { x: 2, y: 0, z: 0 },
          width: 0.9,
          height: 2.1,
        },
      ],
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
  ],
};
