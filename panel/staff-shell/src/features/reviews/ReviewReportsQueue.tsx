import { useEffect, useRef, useState } from "react";
import {
  listReviewReports,
  resolveReviewReport,
  type ReviewReport,
  type ReviewReportDecision,
} from "../../application/staffReviewsApi";
import { formatReviewDate, ReviewBody, reviewsErrorMessage } from "./ReviewCard";

type LoadState =
  | { kind: "loading" }
  | { kind: "ready"; value: ReviewReport[] }
  | { kind: "error"; message: string };

interface ReviewReportsQueueProps {
  accessToken: string;
}

export function ReviewReportsQueue({ accessToken }: ReviewReportsQueueProps) {
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;
  const [state, setState] = useState<LoadState>({ kind: "loading" });
  const [reload, setReload] = useState(0);
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => {
    let isCurrent = true;
    listReviewReports(tokenRef.current, "open").then(
      (value) => {
        if (isCurrent) setState({ kind: "ready", value });
      },
      (error: unknown) => {
        if (isCurrent) {
          setState({
            kind: "error",
            message: reviewsErrorMessage(error, "No se pudieron cargar los reportes de reseñas."),
          });
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [reload]);

  async function handleResolve(reportId: string, decision: ReviewReportDecision) {
    setActionError(null);
    try {
      await resolveReviewReport(tokenRef.current, reportId, decision);
      setReload((value) => value + 1);
    } catch (error) {
      setActionError(reviewsErrorMessage(error, "No se pudo resolver el reporte."));
    }
  }

  return (
    <section aria-labelledby="review-reports-heading" className="chat-reports">
      <h3 id="review-reports-heading">Reportes de reseñas</h3>
      {actionError ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          {actionError}
        </p>
      ) : null}
      {state.kind === "loading" ? <p aria-busy="true">Cargando reportes de reseñas…</p> : null}
      {state.kind === "error" ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          {state.message}
        </p>
      ) : null}
      {state.kind === "ready" && state.value.length === 0 ? (
        <p>No hay reportes de reseñas pendientes.</p>
      ) : null}
      {state.kind === "ready" && state.value.length > 0 ? (
        <ul aria-label="Reportes de reseñas" className="chat-reports__list">
          {state.value.map((report) => (
            <li key={report.id}>
              <ReviewBody review={report.review} />
              <p>
                <strong>Motivo del reporte:</strong> {report.reason}
              </p>
              <p>Reportada el {formatReviewDate(report.created_at)}</p>
              <button
                className="review-button"
                onClick={() => void handleResolve(report.id, "upheld")}
                type="button"
              >
                Confirmar y ocultar reseña
              </button>
              <button
                className="review-button review-button--secondary"
                onClick={() => void handleResolve(report.id, "dismissed")}
                type="button"
              >
                Descartar reporte
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  );
}
