import {
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type PointerEvent,
} from "react";
import {
  getListingScene,
  listAgencyListings,
  putListingScene,
  StaffListingsApiError,
  type ListingApprovalStatus,
  type StaffListing,
} from "../../application/staffListingsApi";
import {
  DEFAULT_SCENE_DOCUMENT,
  roomPolygon,
  type SceneDocument,
  type SceneOpeningV2,
  type ScenePoint2D,
  type SceneWall,
} from "../../application/sceneContract";
import { SceneViewer } from "./SceneViewer";

interface SceneEditorProps {
  accessToken: string;
  agencyId: string;
}

type ListState<T> =
  | { kind: "loading" }
  | { kind: "ready"; value: T }
  | { kind: "error"; message: string };

type SceneLoadState = "idle" | "loading" | "ready" | "error";
type DragTarget =
  | { kind: "wall-endpoint"; wallId: string; endpoint: "start" | "end" }
  | { kind: "opening"; openingId: string }
  | { kind: "object"; objectId: string };

interface CanvasTransform {
  minX: number;
  minZ: number;
  scale: number;
}

interface ActiveDrag {
  target: DragTarget;
  transform: CanvasTransform;
  startPoint: ScenePoint2D;
  originalPosition?: ScenePoint2D;
  wall?: SceneWall;
}

const LISTING_STATUSES: ListingApprovalStatus[] = [
  "draft",
  "pending",
  "approved",
  "rejected",
];
const CANVAS_WIDTH = 640;
const CANVAS_HEIGHT = 420;
const CANVAS_PADDING = 48;
const SNAP_GRID_METERS = 0.1;
const ENDPOINT_SNAP_TOLERANCE = 0.15;
const SESSION_EXPIRED = "Tu sesión expiró. Cierra sesión y vuelve a ingresar.";
const FORBIDDEN = "Tu cuenta no tiene permisos sobre los inmuebles de esta inmobiliaria.";

function errorMessage(error: unknown, fallback: string): string {
  if (error instanceof StaffListingsApiError && error.status === 401) {
    return SESSION_EXPIRED;
  }
  if (error instanceof StaffListingsApiError && error.status === 403) {
    return FORBIDDEN;
  }
  if (error instanceof StaffListingsApiError && error.status !== 404) {
    return error.message;
  }
  return fallback;
}

function listingLabel(listing: StaffListing): string {
  const operation = listing.operation === "rent" ? "Alquiler" : "Venta";
  const rooms = `${listing.bedrooms} ${listing.bedrooms === 1 ? "dormitorio" : "dormitorios"}`;
  return `${operation} · ${listing.city}, ${listing.zone} · ${rooms}`;
}

function canvasTransform(document: SceneDocument): CanvasTransform {
  const points: ScenePoint2D[] = document.walls.flatMap((wall) => [wall.start, wall.end]);
  document.objects.forEach((object) => {
    points.push(
      { x: object.position.x - object.dimensions.width / 2, z: object.position.z - object.dimensions.depth / 2 },
      { x: object.position.x + object.dimensions.width / 2, z: object.position.z + object.dimensions.depth / 2 },
    );
  });

  if (points.length === 0) {
    points.push({ x: 0, z: 0 }, { x: 4, z: 3 });
  }
  const minX = Math.min(...points.map((point) => point.x)) - 0.3;
  const maxX = Math.max(...points.map((point) => point.x)) + 0.3;
  const minZ = Math.min(...points.map((point) => point.z)) - 0.3;
  const maxZ = Math.max(...points.map((point) => point.z)) + 0.3;
  const scale = Math.max(
    1,
    Math.min(
      (CANVAS_WIDTH - CANVAS_PADDING * 2) / (maxX - minX),
      (CANVAS_HEIGHT - CANVAS_PADDING * 2) / (maxZ - minZ),
    ),
  );
  return { minX, minZ, scale };
}

function toCanvas(point: ScenePoint2D, transform: CanvasTransform) {
  return {
    x: CANVAS_PADDING + (point.x - transform.minX) * transform.scale,
    y: CANVAS_HEIGHT - CANVAS_PADDING - (point.z - transform.minZ) * transform.scale,
  };
}

function toWorld(
  event: PointerEvent<SVGSVGElement>,
  svg: SVGSVGElement,
  transform: CanvasTransform,
): ScenePoint2D {
  const rect = svg.getBoundingClientRect();
  const width = rect.width || CANVAS_WIDTH;
  const height = rect.height || CANVAS_HEIGHT;
  const canvasX = ((event.clientX - rect.left) / width) * CANVAS_WIDTH;
  const canvasY = ((event.clientY - rect.top) / height) * CANVAS_HEIGHT;
  return {
    x: transform.minX + (canvasX - CANVAS_PADDING) / transform.scale,
    z: transform.minZ + (CANVAS_HEIGHT - CANVAS_PADDING - canvasY) / transform.scale,
  };
}

function snapEndpoint(
  document: SceneDocument,
  wallId: string,
  point: ScenePoint2D,
): ScenePoint2D {
  const snapped = {
    x: Number((Math.round(point.x / SNAP_GRID_METERS) * SNAP_GRID_METERS).toFixed(1)),
    z: Number((Math.round(point.z / SNAP_GRID_METERS) * SNAP_GRID_METERS).toFixed(1)),
  };

  let nearest: ScenePoint2D | null = null;
  let nearestDistance = ENDPOINT_SNAP_TOLERANCE;
  for (const wall of document.walls) {
    if (wall.id === wallId) continue;
    for (const endpoint of [wall.start, wall.end]) {
      const distance = Math.hypot(endpoint.x - snapped.x, endpoint.z - snapped.z);
      if (distance <= nearestDistance) {
        nearest = endpoint;
        nearestDistance = distance;
      }
    }
  }
  return nearest ? { ...nearest } : snapped;
}

function updateWallEndpoint(
  document: SceneDocument,
  wallId: string,
  endpoint: "start" | "end",
  point: ScenePoint2D,
): SceneDocument {
  return {
    ...document,
    walls: document.walls.map((wall) =>
      wall.id !== wallId ? wall : { ...wall, [endpoint]: { ...point } },
    ),
  };
}

function updateOpeningPosition(
  document: SceneDocument,
  openingId: string,
  position: number,
): SceneDocument {
  return {
    ...document,
    openings: document.openings.map((opening) =>
      opening.id !== openingId ? opening : { ...opening, position },
    ),
  };
}

function updateObjectPosition(
  document: SceneDocument,
  objectId: string,
  position: ScenePoint2D,
): SceneDocument {
  return {
    ...document,
    objects: document.objects.map((object) =>
      object.id !== objectId
        ? object
        : { ...object, position: { ...object.position, ...position } },
    ),
  };
}

function openingPositionOnWall(
  opening: SceneOpeningV2,
  wall: SceneWall,
  point: ScenePoint2D,
): number {
  const dx = wall.end.x - wall.start.x;
  const dz = wall.end.z - wall.start.z;
  const length = Math.hypot(dx, dz);
  if (length === 0) return opening.position;

  const projected = ((point.x - wall.start.x) * dx + (point.z - wall.start.z) * dz) / (length * length);
  const halfWidthRatio = opening.width / (2 * length);
  const minimum = Math.min(0.5, halfWidthRatio);
  const maximum = Math.max(0.5, 1 - halfWidthRatio);
  return Math.max(minimum, Math.min(maximum, projected));
}

interface SceneCanvasProps {
  sceneDocument: SceneDocument;
  selectedObjectId: string | null;
  disabled: boolean;
  onObjectSelect: (objectId: string | null) => void;
  onEdit: (edit: (document: SceneDocument) => SceneDocument) => void;
}

function SceneCanvas({
  sceneDocument,
  selectedObjectId,
  disabled,
  onObjectSelect,
  onEdit,
}: SceneCanvasProps) {
  const svgRef = useRef<SVGSVGElement>(null);
  const dragRef = useRef<ActiveDrag | null>(null);
  const [selection, setSelection] = useState<DragTarget | null>(null);
  const transform = useMemo(() => canvasTransform(sceneDocument), [sceneDocument]);

  function beginDrag(event: PointerEvent<SVGElement>, target: DragTarget) {
    event.stopPropagation();
    event.preventDefault();
    if (disabled || !svgRef.current) return;

    const frozenTransform = canvasTransform(sceneDocument);
    const startPoint = toWorld(
      event as PointerEvent<SVGSVGElement>,
      svgRef.current,
      frozenTransform,
    );
    const targetWall = target.kind === "opening"
      ? sceneDocument.walls.find((wall) =>
          wall.id === sceneDocument.openings.find((opening) => opening.id === target.openingId)?.wallId,
        )
      : undefined;
    dragRef.current = {
      target,
      transform: frozenTransform,
      startPoint,
      originalPosition:
        target.kind === "object"
          ? sceneDocument.objects.find((object) => object.id === target.objectId)?.position
          : undefined,
      wall: targetWall,
    };
    setSelection(target);
    if (target.kind === "object") onObjectSelect(target.objectId);

    try {
      if (typeof event.pointerId === "number") {
        svgRef.current.setPointerCapture(event.pointerId);
      }
    } catch {
      // Pointer capture is optional; the canvas handlers still track the drag.
    }
  }

  function handlePointerMove(event: PointerEvent<SVGSVGElement>) {
    const drag = dragRef.current;
    const svg = svgRef.current;
    if (!drag || !svg || disabled) return;
    const point = toWorld(event, svg, drag.transform);

    if (drag.target.kind === "wall-endpoint") {
      const { wallId, endpoint } = drag.target;
      const snapped = snapEndpoint(sceneDocument, wallId, point);
      onEdit((document) => updateWallEndpoint(document, wallId, endpoint, snapped));
      return;
    }

    if (drag.target.kind === "opening") {
      const openingId = drag.target.openingId;
      const opening = sceneDocument.openings.find((candidate) => candidate.id === openingId);
      if (!opening || !drag.wall) return;
      const position = openingPositionOnWall(opening, drag.wall, point);
      onEdit((document) => updateOpeningPosition(document, openingId, position));
      return;
    }

    const objectId = drag.target.objectId;
    const originalPosition = drag.originalPosition;
    if (!originalPosition) return;
    onEdit((document) =>
      updateObjectPosition(document, objectId, {
        x: originalPosition.x + (point.x - drag.startPoint.x),
        z: originalPosition.z + (point.z - drag.startPoint.z),
      }),
    );
  }

  function endDrag(event: PointerEvent<SVGSVGElement>) {
    dragRef.current = null;
    try {
      if (typeof event.pointerId === "number" && svgRef.current?.hasPointerCapture(event.pointerId)) {
        svgRef.current.releasePointerCapture(event.pointerId);
      }
    } catch {
      // Some browsers can lose pointer capture before the pointer-up event.
    }
  }

  return (
    <svg
      aria-label="Plano 2D del inmueble"
      className="scene-editor__canvas"
      data-testid="scene-editor-canvas"
      onPointerCancel={endDrag}
      onPointerMove={handlePointerMove}
      onPointerUp={endDrag}
      ref={svgRef}
      role="group"
      viewBox={`0 0 ${CANVAS_WIDTH} ${CANVAS_HEIGHT}`}
    >
      <rect fill="#f4f2eb" height={CANVAS_HEIGHT} width={CANVAS_WIDTH} x="0" y="0" />
      {sceneDocument.rooms.map((room) => {
        const polygon = roomPolygon(sceneDocument, room.id);
        if (!polygon) return null;
        const points = polygon.map((point) => toCanvas(point, transform));
        const labelPoint = points.reduce(
          (center, point) => ({ x: center.x + point.x / points.length, y: center.y + point.y / points.length }),
          { x: 0, y: 0 },
        );
        return (
          <g key={room.id}>
            <polygon
              className="scene-editor__room"
              data-testid={`room-outline-${room.id}`}
              fill={room.color ?? "#3a7bd5"}
              fillOpacity="0.2"
              points={points.map((point) => `${point.x},${point.y}`).join(" ")}
            />
            <text
              className="scene-editor__room-label"
              data-testid={`room-label-${room.id}`}
              pointerEvents="none"
              textAnchor="middle"
              x={labelPoint.x}
              y={labelPoint.y}
            >
              {room.name ?? room.id}
            </text>
          </g>
        );
      })}
      {sceneDocument.walls.map((wall) => {
        const start = toCanvas(wall.start, transform);
        const end = toCanvas(wall.end, transform);
        const strokeWidth = Math.max(4, wall.thickness * transform.scale);
        return (
          <g key={wall.id}>
            <line
              aria-label={`Pared ${wall.id}`}
              className="scene-editor__wall"
              data-testid={`scene-wall-${wall.id}`}
              stroke={wall.color ?? "#555a60"}
              strokeLinecap="square"
              strokeWidth={strokeWidth}
              x1={start.x}
              x2={end.x}
              y1={start.y}
              y2={end.y}
            />
            {(["start", "end"] as const).map((endpoint) => {
              const point = endpoint === "start" ? start : end;
              const position = wall[endpoint];
              const selected =
                selection?.kind === "wall-endpoint" &&
                selection.wallId === wall.id &&
                selection.endpoint === endpoint;
              return (
                <circle
                  aria-label={`Mover extremo ${endpoint === "start" ? "inicial" : "final"} de ${wall.id}`}
                  aria-pressed={selected}
                  className={`scene-editor__wall-endpoint${selected ? " is-selected" : ""}`}
                  cx={point.x}
                  cy={point.y}
                  data-position-x={position.x}
                  data-position-z={position.z}
                  data-testid={`wall-endpoint-${wall.id}-${endpoint}`}
                  key={`${wall.id}-${endpoint}`}
                  onPointerDown={(event) =>
                    beginDrag(event, { kind: "wall-endpoint", wallId: wall.id, endpoint })
                  }
                  r="7"
                  role="button"
                  tabIndex={0}
                />
              );
            })}
          </g>
        );
      })}
      {sceneDocument.openings.map((opening) => {
        const wall = sceneDocument.walls.find((candidate) => candidate.id === opening.wallId);
        if (!wall) return null;
        const dx = wall.end.x - wall.start.x;
        const dz = wall.end.z - wall.start.z;
        const length = Math.hypot(dx, dz);
        if (length === 0) return null;
        const halfWidthRatio = opening.width / (2 * length);
        const from = Math.max(0, opening.position - halfWidthRatio);
        const to = Math.min(1, opening.position + halfWidthRatio);
        const start = toCanvas(
          { x: wall.start.x + dx * from, z: wall.start.z + dz * from },
          transform,
        );
        const end = toCanvas(
          { x: wall.start.x + dx * to, z: wall.start.z + dz * to },
          transform,
        );
        const wallStrokeWidth = Math.max(4, wall.thickness * transform.scale);
        return (
          <g key={opening.id}>
            <line
              pointerEvents="none"
              stroke="#f4f2eb"
              strokeWidth={wallStrokeWidth + 2}
              x1={start.x}
              x2={end.x}
              y1={start.y}
              y2={end.y}
            />
            <line
              pointerEvents="none"
              stroke={opening.type === "window" ? "#248c8c" : "#bd6b42"}
              strokeWidth="2"
              x1={start.x}
              x2={end.x}
              y1={start.y}
              y2={end.y}
            />
            <line
              aria-label={`Mover abertura ${opening.id}`}
              aria-pressed={selection?.kind === "opening" && selection.openingId === opening.id}
              className="scene-editor__opening-hit-area"
              data-position={opening.position}
              data-testid={`scene-opening-${opening.id}`}
              onPointerDown={(event) => beginDrag(event, { kind: "opening", openingId: opening.id })}
              role="button"
              pointerEvents="stroke"
              stroke="transparent"
              strokeWidth={Math.max(12, wallStrokeWidth + 8)}
              tabIndex={0}
              x1={start.x}
              x2={end.x}
              y1={start.y}
              y2={end.y}
            />
          </g>
        );
      })}
      {sceneDocument.objects.map((object) => {
        const center = toCanvas(object.position, transform);
        const width = object.dimensions.width * transform.scale;
        const height = object.dimensions.depth * transform.scale;
        const selected = selectedObjectId === object.id;
        return (
          <g key={object.id}>
            <rect
              aria-label={`Mover objeto ${object.id}`}
              aria-pressed={selected}
              className={`scene-editor__object${selected ? " is-selected" : ""}`}
              data-object-id={object.id}
              data-position-x={object.position.x}
              data-position-z={object.position.z}
              data-testid={`scene-object-${object.id}`}
              height={height}
              onClick={() => {
                setSelection({ kind: "object", objectId: object.id });
                onObjectSelect(object.id);
              }}
              onPointerDown={(event) =>
                beginDrag(event, { kind: "object", objectId: object.id })
              }
              role="button"
              tabIndex={0}
              width={width}
              x={center.x - width / 2}
              y={center.y - height / 2}
            />
            <text
              className="scene-editor__object-label"
              pointerEvents="none"
              textAnchor="middle"
              x={center.x}
              y={center.y + 4}
            >
              {object.type}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

export function SceneEditor({ accessToken, agencyId }: SceneEditorProps) {
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;

  const listingSelectId = useId();
  const [listReload, setListReload] = useState(0);
  const [listings, setListings] = useState<ListState<StaffListing[]>>({ kind: "loading" });
  const [selectedListingId, setSelectedListingId] = useState("");
  const [sceneReload, setSceneReload] = useState(0);
  const [scene, setScene] = useState<SceneDocument>(DEFAULT_SCENE_DOCUMENT);
  const [sceneLoad, setSceneLoad] = useState<SceneLoadState>("idle");
  const [hasSavedScene, setHasSavedScene] = useState(false);
  const [isDirty, setIsDirty] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [selectedObjectId, setSelectedObjectId] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let isCurrent = true;
    setListings({ kind: "loading" });
    Promise.all(
      LISTING_STATUSES.map((status) =>
        listAgencyListings(tokenRef.current, agencyId, { status }),
      ),
    ).then(
      (pages) => {
        if (!isCurrent) return;
        const uniqueListings = new Map<string, StaffListing>();
        pages.forEach((page) =>
          page.listings.forEach((listing) => uniqueListings.set(listing.listing_id, listing)),
        );
        setListings({
          kind: "ready",
          value: [...uniqueListings.values()].sort((left, right) =>
            listingLabel(left).localeCompare(listingLabel(right), "es"),
          ),
        });
      },
      (failure: unknown) => {
        if (isCurrent) {
          setListings({
            kind: "error",
            message: errorMessage(failure, "No se pudieron cargar los inmuebles."),
          });
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [agencyId, listReload]);

  useEffect(() => {
    let isCurrent = true;
    setNotice(null);
    setError(null);
    setSelectedObjectId(null);
    setIsDirty(false);
    setHasSavedScene(false);

    if (!selectedListingId) {
      setSceneLoad("idle");
      setScene(DEFAULT_SCENE_DOCUMENT);
      return () => {
        isCurrent = false;
      };
    }

    setSceneLoad("loading");
    setScene(DEFAULT_SCENE_DOCUMENT);
    getListingScene(tokenRef.current, agencyId, selectedListingId).then(
      (document) => {
        if (!isCurrent) return;
        setScene(document);
        setHasSavedScene(true);
        setSceneLoad("ready");
      },
      (failure: unknown) => {
        if (!isCurrent) return;
        if (
          failure instanceof StaffListingsApiError &&
          failure.status === 404 &&
          failure.code === "scene_not_defined"
        ) {
          setScene(DEFAULT_SCENE_DOCUMENT);
          setHasSavedScene(false);
          setSceneLoad("ready");
          return;
        }
        setError(errorMessage(failure, "No se pudo cargar la escena del inmueble."));
        setSceneLoad("error");
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [agencyId, selectedListingId, sceneReload]);

  function handleEdit(edit: (document: SceneDocument) => SceneDocument) {
    if (isSaving) return;
    setScene(edit);
    setIsDirty(true);
    setNotice(null);
    setError(null);
  }

  async function handleSave() {
    if (!selectedListingId || sceneLoad !== "ready" || isSaving) return;
    setIsSaving(true);
    setNotice(null);
    setError(null);
    try {
      const savedDocument = await putListingScene(
        tokenRef.current,
        agencyId,
        selectedListingId,
        scene,
      );
      setScene(savedDocument);
      setHasSavedScene(true);
      setIsDirty(false);
      setNotice("Cambios guardados correctamente.");
    } catch (failure) {
      setError(errorMessage(failure, "No se pudo guardar la escena. Inténtalo nuevamente."));
    } finally {
      setIsSaving(false);
    }
  }

  const sceneReady = sceneLoad === "ready";

  return (
    <section aria-labelledby="scene-editor-heading" className="scene-editor">
      <div className="protected-staff-review-queue__heading">
        <span className="protected-staff-review-queue__eyebrow">
          EDICIÓN DE INMUEBLES
        </span>
        <h2 id="scene-editor-heading">Editor de escenas</h2>
        <p className="scene-editor__intro">
          Ajusta el plano en metros; los cambios se reflejan en el visor 3D y solo se guardan cuando
          confirmas la acción.
        </p>
      </div>

      <div className="scene-editor__toolbar">
        <div className="scene-editor__listing-field">
          <label htmlFor={listingSelectId}>Inmueble</label>
          <select
            disabled={listings.kind !== "ready" || listings.value.length === 0}
            id={listingSelectId}
            onChange={(event) => setSelectedListingId(event.target.value)}
            value={selectedListingId}
          >
            <option value="">Selecciona un inmueble</option>
            {listings.kind === "ready"
              ? listings.value.map((listing) => (
                  <option key={listing.listing_id} value={listing.listing_id}>
                    {listingLabel(listing)}
                  </option>
                ))
              : null}
          </select>
        </div>
        <button
          className="review-button"
          disabled={!sceneReady || isSaving || (hasSavedScene && !isDirty)}
          onClick={() => void handleSave()}
          type="button"
        >
          {isSaving ? "Guardando…" : "Guardar escena"}
        </button>
      </div>

      {listings.kind === "loading" ? (
        <p aria-busy="true" className="review-queue__message">
          Cargando inmuebles…
        </p>
      ) : null}
      {listings.kind === "error" ? (
        <div className="review-queue__message review-queue__message--error" role="alert">
          <p>{listings.message}</p>
          <button
            className="review-button review-button--secondary"
            onClick={() => setListReload((value) => value + 1)}
            type="button"
          >
            Reintentar
          </button>
        </div>
      ) : null}
      {listings.kind === "ready" && listings.value.length === 0 ? (
        <p className="protected-staff-review-queue__empty">
          No hay inmuebles disponibles para editar.
        </p>
      ) : null}
      {sceneLoad === "idle" && listings.kind === "ready" && listings.value.length > 0 ? (
        <p className="review-queue__message">Selecciona un inmueble para cargar su escena.</p>
      ) : null}
      {sceneLoad === "loading" ? (
        <p aria-busy="true" className="review-queue__message">
          Cargando escena…
        </p>
      ) : null}
      {sceneLoad === "error" ? (
        <div className="review-queue__message review-queue__message--error" role="alert">
          <p>{error}</p>
          <button
            className="review-button review-button--secondary"
            onClick={() => setSceneReload((value) => value + 1)}
            type="button"
          >
            Reintentar
          </button>
        </div>
      ) : null}
      {sceneReady ? (
        <>
          <div className="scene-editor__notices">
            {!hasSavedScene ? (
              <p className="scene-editor__unsaved" role="status">
                Escena sin guardar · se usa la escena sintética de inicio.
              </p>
            ) : isDirty ? (
              <p className="scene-editor__unsaved" role="status">
                Hay cambios sin guardar.
              </p>
            ) : (
              <p className="scene-editor__saved" role="status">
                Escena guardada.
              </p>
            )}
            {notice && !isDirty ? <p className="review-notice">{notice}</p> : null}
            {error ? <p className="review-queue__message review-queue__message--error" role="alert">{error}</p> : null}
          </div>
          <div className="scene-editor__workspace">
            <section aria-label="Edición del plano 2D" className="scene-editor__panel">
              <div className="scene-editor__panel-heading">
                <h3>Plano 2D</h3>
                <p>Arrastra los extremos de las paredes, las aberturas sobre su pared o los objetos.</p>
              </div>
              <SceneCanvas
                disabled={isSaving}
                onEdit={handleEdit}
                onObjectSelect={setSelectedObjectId}
                sceneDocument={scene}
                selectedObjectId={selectedObjectId}
              />
            </section>
            <section aria-label="Vista tridimensional" className="scene-editor__panel">
              <div className="scene-editor__panel-heading">
                <h3>Visor 3D</h3>
              </div>
              <SceneViewer
                onObjectSelect={setSelectedObjectId}
                sceneDocument={scene}
                selectedObjectId={selectedObjectId}
              />
            </section>
          </div>
        </>
      ) : null}
    </section>
  );
}
