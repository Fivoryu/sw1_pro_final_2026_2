import { useEffect, useId, useRef, useState, type FormEvent } from "react";
import {
  getFurnitureReview, listDetectionJobs, requestPhotoDetection, reviewFurniture,
  type DetectionJobStatus, type FurnitureCommand, type FurnitureReviewView, type FurnitureSuggestion, type VolumeSuggestion,
} from "../../application/furnitureReviewApi";
import { listListingPhotos, StaffListingsApiError, type ListingPhoto } from "../../application/staffListingsApi";
import "./FurnitureReviewPanel.css";

interface Props {
  accessToken: string;
  agencyId: string;
  listingId: string;
  disabled: boolean;
  onChanged: () => void;
  onBusyChange?: (busy: boolean) => void;
}

const STATUS: Record<string, string> = {
  pending: "Pendiente", running: "En curso", completed: "Completado", failed: "Fallido",
  confirmed: "Confirmado", rejected: "Rechazado", expired: "Expirado", manual: "Alta manual",
};

function message(error: unknown): string {
  if (error instanceof StaffListingsApiError) {
    if (error.status === 401) return "Tu sesión expiró. Vuelve a ingresar.";
    if (error.status === 403) return "No tienes permisos sobre este inmueble.";
    if (error.status === 409) return "No se aplicó el cambio. Recarga la revisión: la oferta cambió, la foto expiró, falta una escena válida o el mueble existente aún no tiene una caja vinculada.";
    if (error.status === 422) return "Revisa los campos: precio exacto, medidas positivas y posición en metros.";
  }
  return "No se pudo completar la operación. Reintenta o actualiza la revisión.";
}

const cm = (metres: number) => String(Math.max(1, Math.round(metres * 100)));

function volumeDefaults(volume: VolumeSuggestion): Record<string, string> {
  return {
    x: String(volume.position.x), y: String(volume.position.y), z: String(volume.position.z),
    width: cm(volume.dimensions.width), height: cm(volume.dimensions.height), depth: cm(volume.dimensions.depth),
  };
}

function Photo({ photo, suggestions }: { photo: ListingPhoto; suggestions: FurnitureSuggestion[] }) {
  const [size, setSize] = useState<{ width: number; height: number } | null>(null);
  return <div className="furniture-review__photo">
    <img src={photo.url} alt={`Foto ${photo.photo_id}`} onLoad={(event) => {
      const image = event.currentTarget;
      if (image.naturalWidth && image.naturalHeight) setSize({ width: image.naturalWidth, height: image.naturalHeight });
    }} />
    {size ? <svg aria-label="Cajas sugeridas en píxeles" viewBox={`0 0 ${size.width} ${size.height}`}>
      {suggestions.map((suggestion) => <rect key={`${suggestion.job_id}:${suggestion.detection_index}`}
        x={suggestion.box[0]} y={suggestion.box[1]}
        width={Math.max(0, suggestion.box[2] - suggestion.box[0])}
        height={Math.max(0, suggestion.box[3] - suggestion.box[1])}
        fill="none" stroke="#f59e0b" strokeWidth={Math.max(2, size.width / 300)} />)}
    </svg> : null}
  </div>;
}

export function FurnitureReviewPanel({ accessToken, agencyId, listingId, disabled, onChanged, onBusyChange }: Props) {
  const formId = useId();
  const [reload, setReload] = useState(0);
  const [view, setView] = useState<FurnitureReviewView | null>(null);
  const [photos, setPhotos] = useState<ListingPhoto[]>([]);
  const [jobs, setJobs] = useState<DetectionJobStatus[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [selected, setSelected] = useState<FurnitureSuggestion | null>(null);
  const [selectedVolume, setSelectedVolume] = useState<VolumeSuggestion | null>(null);
  const [destination, setDestination] = useState("");
  const formRef = useRef<HTMLFormElement>(null);
  const pending = useRef<{ key: string; requestId: string } | null>(null);
  const volumes = view?.volume_suggestions ?? [];
  const blocked = busy || disabled || loading;

  useEffect(() => {
    let current = true;
    setLoading(true);
    setError(null);
    setSelected(null);
    setSelectedVolume(null);
    setDestination("");
    Promise.all([
      getFurnitureReview(accessToken, agencyId, listingId),
      listListingPhotos(accessToken, agencyId, listingId),
      listDetectionJobs(accessToken, agencyId, listingId),
    ]).then(([data, images, states]) => {
      if (!current) return;
      setView(data); setPhotos(images); setJobs(states); setLoading(false);
    }, (failure: unknown) => {
      if (!current) return;
      setView(null); setLoading(false); setError(message(failure));
    });
    return () => { current = false; };
  }, [accessToken, agencyId, listingId, reload]);

  async function decide(content: Omit<FurnitureCommand, "request_id" | "expected_offer_version">) {
    if (!view || blocked) return;
    const body = { ...content, expected_offer_version: view.listing.offer_version };
    const key = JSON.stringify(body);
    if (pending.current?.key !== key) pending.current = { key, requestId: crypto.randomUUID() };
    const command: FurnitureCommand = { ...body, request_id: pending.current.requestId };
    setBusy(true); onBusyChange?.(true); setError(null); setNotice(null);
    try {
      const updated = await reviewFurniture(accessToken, agencyId, listingId, command);
      pending.current = null;
      setView(updated); setSelected(null); setSelectedVolume(null); setDestination(""); formRef.current?.reset();
      setNotice(content.action === "rejected" ? "Sugerencia descartada; inventario sin cambios." : "Mobiliario confirmado. Las altas quedan en borrador para revisión.");
      onChanged();
    } catch (failure) { setError(message(failure)); }
    finally { setBusy(false); onBusyChange?.(false); }
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!view || blocked) return;
    const values = new FormData(event.currentTarget);
    const reference = selectedVolume ? { capture_id: selectedVolume.capture_id, object_id: selectedVolume.object_id }
      : selected ? { job_id: selected.job_id, detection_index: selected.detection_index } : {};
    const reviewing = selected !== null || selectedVolume !== null;
    if (reviewing && destination) {
      void decide({ action: "confirmed", ...reference, existing_extra_id: destination });
      return;
    }
    const number = (name: string) => Number(values.get(name));
    void decide({
      action: reviewing ? "confirmed" : "manual", ...reference,
      item: {
        name: String(values.get("name")), price: String(values.get("price")),
        width_cm: number("width"), height_cm: number("height"), depth_cm: number("depth"),
        quantity: number("quantity"), position: { x: number("x"), y: number("y"), z: number("z") },
        ...(values.get("room") ? { room: String(values.get("room")) } : {}),
        ...(values.get("category") ? { category: String(values.get("category")) } : {}),
      },
    });
  }

  async function detect(photoId: string) {
    if (blocked) return;
    setBusy(true); onBusyChange?.(true); setError(null); setNotice(null);
    try {
      const job = await requestPhotoDetection(accessToken, agencyId, listingId, photoId);
      setJobs((current) => [...current.filter((row) => row.job_id !== job.job_id), job]);
      setNotice("Solicitud registrada. Actualiza para consultar el resultado real del trabajo.");
    } catch (failure) { setError(message(failure)); }
    finally { setBusy(false); onBusyChange?.(false); }
  }

  function input(name: string, label: string, options: { integer?: boolean; min?: number; text?: boolean; required?: boolean } = {}) {
    const prefill = selectedVolume ? volumeDefaults(selectedVolume)[name] : undefined;
    return <label htmlFor={`${formId}-${name}`}>{label}
      <input id={`${formId}-${name}`} name={name} type={options.text ? "text" : "number"}
        required={options.required !== false} min={options.min}
        step={options.text ? undefined : options.integer ? "1" : "any"}
        defaultValue={name === "quantity" ? "1" : prefill}
        maxLength={options.text ? (name === "name" ? 120 : 32) : undefined} />
    </label>;
  }

  return <section className="furniture-review" aria-labelledby={`${formId}-heading`}>
    <header className="scene-editor__panel-heading">
      <h3 id={`${formId}-heading`}>Mobiliario y sugerencias IA</h3>
      <p>Solo tu confirmación crea inventario. La puntuación no es una probabilidad calibrada; la IA no mide dimensiones ni fija precios.</p>
      <button type="button" className="review-button review-button--secondary" disabled={busy}
        onClick={() => { pending.current = null; setNotice(null); setReload((value) => value + 1); }}>Actualizar revisión</button>
    </header>
    {disabled ? <p role="status">Guarda la escena y sus cambios antes de confirmar mobiliario.</p> : null}
    {loading ? <p aria-busy="true">Cargando revisión…</p> : null}
    {error ? <p role="alert">{error}</p> : null}
    {notice ? <p role="status">{notice}</p> : null}
    {view ? <>
      <h4>Inventario confirmado · {view.listing.currency}</h4>
      {view.listing.extras.length ? <ul>{view.listing.extras.map((extra) =>
        <li key={extra.extra_id}>{extra.name} · {extra.price} {view.listing.currency} × {extra.quantity} · {extra.origin ?? "Procedencia no indicada"}</li>)}</ul>
        : <p>No hay mobiliario confirmado. Puedes añadirlo manualmente.</p>}

      <h4>Fotos y trabajos</h4>
      {photos.length ? <div className="furniture-review__photos">{photos.map((photo) => <article key={photo.photo_id}>
        <Photo photo={photo} suggestions={view.suggestions.filter((row) => row.photo_id === photo.photo_id)} />
        <p>Foto {photo.photo_id}</p>
        {jobs.filter((job) => job.photo_id === photo.photo_id).map((job) =>
          <p key={job.job_id}>{STATUS[job.status] ?? job.status}{job.failure_reason ? `: ${job.failure_reason}` : ""}</p>)}
        <button className="review-button review-button--secondary" type="button" disabled={blocked}
          onClick={() => void detect(photo.photo_id)}>Detectar foto {photo.photo_id}</button>
      </article>)}</div> : <p>No hay fotos confirmadas. El alta manual sigue disponible.</p>}

      <h4>Sugerencias por revisar</h4>
      {view.suggestions.length ? <ul className="furniture-review__suggestions">{view.suggestions.map((suggestion) =>
        <li key={`${suggestion.job_id}:${suggestion.detection_index}`}>
          <strong>{suggestion.label} · {STATUS[suggestion.status]}</strong>
          <p>Puntuación: {suggestion.score.toFixed(2)} · Foto {suggestion.photo_id} · Modelo {suggestion.model_id}</p>
          <p>Caja 2D: {suggestion.box.join(", ")} píxeles</p>
          {suggestion.extra_id ? <p>Extra vinculado: {suggestion.extra_id}</p> : null}
          {suggestion.status === "pending" ? <div className="furniture-review__actions">
            <button className="review-button" type="button" disabled={blocked} onClick={() => {
              setSelected(suggestion); setSelectedVolume(null); setDestination(""); formRef.current?.reset(); setNotice(null);
            }}>Revisar {suggestion.label} (foto {suggestion.photo_id})</button>
            <button className="review-button review-button--secondary" type="button" disabled={blocked}
              onClick={() => void decide({ action: "rejected", job_id: suggestion.job_id, detection_index: suggestion.detection_index })}>
              Descartar {suggestion.label} (foto {suggestion.photo_id})</button>
          </div> : null}
        </li>)}</ul> : <p>Sin resultados de detección. No se ha inventado ningún objeto.</p>}

      {volumes.length ? <>
        <h4>Sugerencias por volumen</h4>
        <ul className="furniture-review__suggestions">{volumes.map((volume) =>
          <li key={`${volume.capture_id}:${volume.object_id}`}>
            <strong>{volume.label} · {STATUS[volume.status]}</strong>
            <p>Puntuación: {volume.score.toFixed(2)} · Volumen {volume.object_id} · Modelo {volume.model_id}</p>
            <p>Posición (m): {volume.position.x}, {volume.position.y}, {volume.position.z}</p>
            <p>Dimensiones (m): {volume.dimensions.width} × {volume.dimensions.height} × {volume.dimensions.depth}</p>
            {volume.extra_id ? <p>Extra vinculado: {volume.extra_id}</p> : null}
            {volume.status === "pending" ? <div className="furniture-review__actions">
              <button className="review-button" type="button" disabled={blocked} onClick={() => {
                setSelectedVolume(volume); setSelected(null); setDestination(""); formRef.current?.reset(); setNotice(null);
              }}>Revisar {volume.label} (volumen {volume.object_id})</button>
              <button className="review-button review-button--secondary" type="button" disabled={blocked}
                onClick={() => void decide({ action: "rejected", capture_id: volume.capture_id, object_id: volume.object_id })}>
                Descartar {volume.label} (volumen {volume.object_id})</button>
            </div> : null}
          </li>)}</ul>
      </> : null}

      <form key={selectedVolume ? `${selectedVolume.capture_id}:${selectedVolume.object_id}` : "form"} ref={formRef} onSubmit={submit}>
        <h4>{selected || selectedVolume ? `Confirmar sugerencia: ${(selected ?? selectedVolume)?.label}` : "Añadir mobiliario manualmente"}</h4>
        {selectedVolume ? <p>Posición y medidas precargadas desde el volumen; completa nombre y precio antes de confirmar.</p> : null}
        {selected || selectedVolume ? <button type="button" disabled={blocked} className="review-button review-button--secondary"
          onClick={() => { setSelected(null); setSelectedVolume(null); setDestination(""); formRef.current?.reset(); }}>Volver al alta manual</button> : null}
        <fieldset disabled={blocked}>
          {selected || selectedVolume ? <label htmlFor={`${formId}-destination`}>Destino
            <select id={`${formId}-destination`} value={destination} onChange={(event) => setDestination(event.target.value)}>
              <option value="">Crear un mueble nuevo</option>
              {view.listing.extras.map((extra) => <option key={extra.extra_id} value={extra.extra_id}>Mismo mueble ya inventariado: {extra.name}</option>)}
            </select>
          </label> : null}
          {destination ? <p>Vincular el repetido no cambia precio ni cantidad y no duplica su caja. El mueble debe tener una caja vinculada en la escena.</p>
            : <div className="furniture-review__fields">
              {input("name", "Nombre", { text: true })}
              {input("price", `Precio (${view.listing.currency})`, { min: 0 })}
              {input("width", "Ancho (cm)", { integer: true, min: 1 })}
              {input("height", "Alto (cm)", { integer: true, min: 1 })}
              {input("depth", "Fondo (cm)", { integer: true, min: 1 })}
              {input("quantity", "Cantidad", { integer: true, min: 1 })}
              {input("x", "Posición X (m)")}{input("y", "Posición Y (m)")}{input("z", "Posición Z (m)")}
              {input("room", "Habitación", { text: true, required: false })}
              {input("category", "Categoría", { text: true, required: false })}
            </div>}
          <p>El precio se expresa por unidad. La posición corresponde al centro de la caja, en metros.</p>
          <button className="review-button" type="submit" disabled={blocked}>{busy ? "Procesando…" : "Confirmar mobiliario"}</button>
        </fieldset>
      </form>

      <h4>Historial de revisión</h4>
      {view.history.length ? <ul>{view.history.map((event) => <li key={event.request_id}>
        {STATUS[event.action]} · {event.actor_id} · {new Date(event.created_at).toLocaleString("es")} · {event.extra_id ?? "Sin alta de inventario"}
      </li>)}</ul> : <p>Todavía no hay decisiones humanas registradas.</p>}
    </> : null}
  </section>;
}
