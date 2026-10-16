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
  type SceneDocument,
  type ScenePoint2D,
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
type SceneSelection =
  | { kind: "room"; roomId: string }
  | { kind: "vertex"; roomId: string; index: number }
  | { kind: "object"; objectId: string }
  | null;
type DragTarget = Exclude<SceneSelection, { kind: "room" } | null>;

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
  const points: ScenePoint2D[] = document.rooms.flatMap((room) => room.contours);
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

function updateVertex(
  document: SceneDocument,
  roomId: string,
  index: number,
  point: ScenePoint2D,
): SceneDocument {
  return {
    ...document,
    rooms: document.rooms.map((room) =>
      room.id !== roomId
        ? room
        : {
            ...room,
            contours: room.contours.map((vertex, vertexIndex) =>
              vertexIndex === index ? { ...vertex, ...point } : vertex,
            ),
          },
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
  const [selection, setSelection] = useState<SceneSelection>(null);
  const transform = useMemo(() => canvasTransform(sceneDocument), [sceneDocument]);

  function beginDrag(
    event: PointerEvent<SVGElement>,
    target: DragTarget,
    originalPosition?: ScenePoint2D,
  ) {
    event.stopPropagation();
    event.preventDefault();
    if (disabled || !svgRef.current) return;

    const frozenTransform = canvasTransform(sceneDocument);
    dragRef.current = {
      target,
      transform: frozenTransform,
      startPoint: toWorld(event as PointerEvent<SVGSVGElement>, svgRef.current, frozenTransform),
      originalPosition,
    };
    if (target.kind === "object") {
      setSelection({ kind: "object", objectId: target.objectId });
      onObjectSelect(target.objectId);
    } else {
      setSelection({ kind: "vertex", roomId: target.roomId, index: target.index });
    }

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
    if (drag.target.kind === "vertex") {
      const { roomId, index } = drag.target;
      onEdit((document) => updateVertex(document, roomId, index, point));
      return;
    }

    const originalPosition = drag.originalPosition;
    if (!originalPosition) return;
    const { objectId } = drag.target;
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
        const points = room.contours.map((point) => toCanvas(point, transform));
        const selected = selection?.kind === "room" && selection.roomId === room.id;
        return (
          <g key={room.id}>
            <polygon
              aria-label={`Seleccionar habitación ${room.id}`}
              className={`scene-editor__room${selected ? " is-selected" : ""}`}
              data-testid={`room-outline-${room.id}`}
              onClick={() => setSelection({ kind: "room", roomId: room.id })}
              points={points.map((point) => `${point.x},${point.y}`).join(" ")}
              role="button"
              tabIndex={0}
            />
            {room.contours.map((point, index) => {
              const canvasPoint = toCanvas(point, transform);
              const vertexSelected =
                selection?.kind === "vertex" &&
                selection.roomId === room.id &&
                selection.index === index;
              return (
                <circle
                  aria-label={`Mover esquina ${index + 1} de ${room.id}`}
                  aria-pressed={vertexSelected}
                  className={`scene-editor__vertex${vertexSelected ? " is-selected" : ""}`}
                  cx={canvasPoint.x}
                  cy={canvasPoint.y}
                  data-testid={`room-vertex-${room.id}-${index}`}
                  key={`${room.id}-vertex-${index}`}
                  onClick={() => setSelection({ kind: "vertex", roomId: room.id, index })}
                  onPointerDown={(event) =>
                    beginDrag(event, { kind: "vertex", roomId: room.id, index })
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
                beginDrag(event, { kind: "object", objectId: object.id }, object.position)
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
                <p>Arrastra los puntos de las paredes o los objetos para modificar su posición.</p>
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
