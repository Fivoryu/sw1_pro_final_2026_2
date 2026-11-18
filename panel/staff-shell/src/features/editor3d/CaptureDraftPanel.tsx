import { useCallback, useEffect, useRef, useState } from "react";
import { listCaptures, type CaptureReview, type CaptureStatus } from "../../application/captureReviewApi";
import { StaffListingsApiError } from "../../application/staffListingsApi";
import { pendingEstimates, splitCaptureWarnings, type PendingEstimate } from "../../application/captureWarnings";
import { isProportional, type SceneDocument } from "../../application/sceneContract";
import "./CaptureDraftPanel.css";

interface Props {
  accessToken: string;
  agencyId: string;
  listingId: string;
  disabled: boolean;
  /** Changes whenever a capture was accepted so the statuses are fetched again. */
  refreshKey?: number;
  loadedCaptureId?: string | null;
  onLoadDraft: (captureId: string, draft: SceneDocument) => void;
  /** The scene the editor holds; once the draft is loaded, pending measures are read from it. */
  scene?: SceneDocument;
  /** Confirms a pending wall height as manual, optionally correcting it (meters). */
  onConfirmMeasure?: (wallId: string, height?: number) => void;
}

const STATUS: Record<CaptureStatus, string> = {
  awaiting_upload: "Esperando la subida desde el teléfono.",
  queued: "En cola: esperando para reconstruirse.",
  processing: "Procesando: la reconstrucción sigue en curso.",
  completed: "Completada: el borrador está listo para revisar.",
  failed: "Fallida.",
  accepted: "Aceptada: el borrador ya fue conservado y los fotogramas se eliminarán.",
};

function message(error: unknown): string {
  if (error instanceof StaffListingsApiError) {
    if (error.status === 401) return "Tu sesión expiró. Vuelve a ingresar.";
    if (error.status === 403) return "No tienes permisos sobre este inmueble.";
    if (error.status === 404) return "No se encontró el inmueble en esta inmobiliaria.";
  }
  return "No se pudieron consultar las capturas. Reintenta.";
}

export function CaptureDraftPanel({
  accessToken, agencyId, listingId, disabled, refreshKey = 0, loadedCaptureId = null, onLoadDraft,
  scene, onConfirmMeasure,
}: Props) {
  const [captures, setCaptures] = useState<CaptureReview[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;
  const requestRef = useRef(0);

  const refresh = useCallback(async () => {
    const request = ++requestRef.current;
    setBusy(true);
    setError(null);
    try {
      const fresh = await listCaptures(tokenRef.current, agencyId, listingId);
      if (request === requestRef.current) setCaptures(fresh);
    } catch (failure) {
      if (request === requestRef.current) setError(message(failure));
    } finally {
      if (request === requestRef.current) setBusy(false);
    }
  }, [agencyId, listingId]);

  useEffect(() => {
    void refresh();
    // A newer request (or unmount) makes any pending answer stale.
    return () => { requestRef.current++; };
  }, [refresh, refreshKey]);

  return <section className="capture-draft" aria-label="Borradores de capturas">
    <h4>Borradores de capturas</h4>
    <p>La reconstrucción es un borrador: no se guarda ni se acepta hasta que lo cargues, lo edites y guardes la escena.</p>
    <button className="review-button review-button--secondary" type="button" disabled={busy}
      onClick={() => void refresh()}>Actualizar</button>
    {error ? <p role="alert">{error}</p> : null}
    {captures !== null && captures.length === 0 && !error
      ? <p>Todavía no hay capturas subidas para este inmueble.</p> : null}
    <ul className="capture-draft__list">
      {(captures ?? []).map((capture) => <li key={capture.captureId}>
        <strong>{capture.captureId}</strong>
        <p>{STATUS[capture.status] ?? capture.status}</p>
        {capture.status === "failed"
          ? <p>Motivo: {capture.failureReason ?? "No se informó un motivo."}</p> : null}
        {capture.status === "completed" ? <CaptureNotes capture={capture}
          editable={loadedCaptureId === capture.captureId && scene !== undefined && onConfirmMeasure !== undefined}
          scene={scene} onConfirmMeasure={onConfirmMeasure} /> : null}
        {capture.status === "completed" && capture.sceneDraft
          ? loadedCaptureId === capture.captureId
            ? <p>Borrador cargado en el editor: guarda la escena para aceptarlo.</p>
            : <button className="review-button" type="button" disabled={disabled}
              onClick={() => onLoadDraft(capture.captureId, capture.sceneDraft as SceneDocument)}>
              Cargar borrador en el editor</button>
          : null}
      </li>)}
    </ul>
  </section>;
}

interface NotesProps {
  capture: CaptureReview;
  editable: boolean;
  scene?: SceneDocument;
  onConfirmMeasure?: (wallId: string, height?: number) => void;
}

function CaptureNotes({ capture, editable, scene, onConfirmMeasure }: NotesProps) {
  const { scale, other } = splitCaptureWarnings(capture.warnings);
  // Once loaded, the editor scene is the source: confirmed measures leave the list.
  const source = editable && scene ? scene : capture.sceneDraft;
  const pending = source ? pendingEstimates(source) : [];
  const proportional = source ? isProportional(source) : false;
  return <>
    {scale.length > 0
      ? <ul aria-label={`Advertencias de escala de ${capture.captureId}`} className="capture-draft__scale">
        {scale.map((warning, index) => <li key={index}>{warning}</li>)}</ul> : null}
    {other.length > 0
      ? <ul aria-label={`Advertencias de ${capture.captureId}`}>
        {other.map((warning, index) => <li key={index}>{warning}</li>)}</ul> : null}
    {pending.length > 0 ? <>
      <p>Medidas estimadas pendientes de confirmar (no fueron medidas; no las tomes como exactas):</p>
      <ul aria-label={`Medidas estimadas pendientes de ${capture.captureId}`}>
        {pending.map((estimate) => <li key={estimate.wallId}>
          {proportional
            ? `Altura relativa del muro ${estimate.wallId}: ${estimate.height.toFixed(2).replace(".", ",")} (unidades del plano, no metros)`
            : `Altura del muro ${estimate.wallId}: ${estimate.height.toFixed(2).replace(".", ",")} m`}
          {estimate.source === "estimated" ? " (estimada desde el video)" : " (no medida)"}
          {editable && onConfirmMeasure
            ? <PendingMeasureActions estimate={estimate} onConfirm={onConfirmMeasure} /> : null}</li>)}
      </ul></> : null}
  </>;
}

function PendingMeasureActions({ estimate, onConfirm }: {
  estimate: PendingEstimate;
  onConfirm: (wallId: string, height?: number) => void;
}) {
  const [value, setValue] = useState("");
  const [invalid, setInvalid] = useState(false);
  function correct() {
    const height = Number(value.trim().replace(",", "."));
    if (value.trim() === "" || !Number.isFinite(height) || height <= 0) {
      setInvalid(true);
      return;
    }
    setInvalid(false);
    onConfirm(estimate.wallId, height);
  }
  return <span className="capture-draft__measure-actions">
    {" "}
    <button className="review-button review-button--secondary" type="button"
      onClick={() => onConfirm(estimate.wallId, undefined)}>Confirmar</button>
    <input type="text" inputMode="decimal" value={value}
      aria-label={`Altura corregida del muro ${estimate.wallId} (m)`}
      onChange={(event) => { setValue(event.target.value); setInvalid(false); }} />
    <button className="review-button review-button--secondary" type="button"
      onClick={correct}>Corregir y confirmar</button>
    {invalid ? <span role="alert">La altura debe ser un número mayor que cero (en metros).</span> : null}
  </span>;
}
