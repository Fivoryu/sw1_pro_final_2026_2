import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  listReviews,
  replyToReview,
  reportReview,
  type ReviewSummary,
  type StaffReview,
  type StaffReviewList,
} from "../../application/staffReviewsApi";
import { ReviewBody, reviewsErrorMessage } from "./ReviewCard";

type LoadState =
  | { kind: "loading" }
  | { kind: "ready"; value: StaffReviewList }
  | { kind: "error"; message: string };

function SummaryHeader({ summary }: { summary: ReviewSummary }) {
  return (
    <p className="reviews-summary">
      {summary.few_ratings || summary.average === null ? (
        <strong>Pocas calificaciones</strong>
      ) : (
        <strong>Promedio {summary.average.toFixed(1)} de 5</strong>
      )}
      {" · "}
      {summary.count} {summary.count === 1 ? "reseña" : "reseñas"}
      {" · "}
      {summary.verified_count} {summary.verified_count === 1 ? "verificada" : "verificadas"}
    </p>
  );
}

interface ReasonFormProps {
  label: string;
  submitLabel: string;
  onSubmit: (body: string) => Promise<void>;
}

function TextForm({ label, submitLabel, onSubmit }: ReasonFormProps) {
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (!body.trim()) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(body.trim());
    } catch (caught) {
      setError(reviewsErrorMessage(caught, "No se pudo enviar."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={(event) => void handleSubmit(event)}>
      <label>
        {label}
        <textarea onChange={(event) => setBody(event.target.value)} value={body} />
      </label>
      {error ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          {error}
        </p>
      ) : null}
      <button
        className="review-button review-button--secondary"
        disabled={busy || !body.trim()}
        type="submit"
      >
        {submitLabel}
      </button>
    </form>
  );
}

interface ReviewItemProps {
  review: StaffReview;
  canAct: boolean;
  onReply: (reviewId: string, body: string) => Promise<void>;
  onReport: (reviewId: string, body: string) => Promise<void>;
}

function ReviewItem({ review, canAct, onReply, onReport }: ReviewItemProps) {
  const [reporting, setReporting] = useState(false);
  return (
    <li>
      <ReviewBody review={review} />
      {canAct && !review.agency_reply ? (
        <TextForm
          label="Tu respuesta"
          onSubmit={(body) => onReply(review.id, body)}
          submitLabel="Responder"
        />
      ) : null}
      {canAct && !review.reported ? (
        reporting ? (
          <TextForm
            label="Motivo del reporte"
            onSubmit={async (body) => {
              await onReport(review.id, body);
              setReporting(false);
            }}
            submitLabel="Enviar reporte"
          />
        ) : (
          <button
            className="review-button review-button--secondary"
            onClick={() => setReporting(true)}
            type="button"
          >
            Reportar reseña
          </button>
        )
      ) : null}
    </li>
  );
}

interface AgencyReviewsProps {
  accessToken: string;
  /** Only the agency admin replies and reports; agents read. */
  isAgencyAdmin: boolean;
}

export function AgencyReviews({ accessToken, isAgencyAdmin }: AgencyReviewsProps) {
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;
  const [state, setState] = useState<LoadState>({ kind: "loading" });
  const [reload, setReload] = useState(0);

  useEffect(() => {
    let isCurrent = true;
    listReviews(tokenRef.current).then(
      (value) => {
        if (isCurrent) setState({ kind: "ready", value });
      },
      (error: unknown) => {
        if (isCurrent) {
          setState({ kind: "error", message: reviewsErrorMessage(error, "No se pudieron cargar las reseñas.") });
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [reload]);

  async function handleReply(reviewId: string, body: string) {
    await replyToReview(tokenRef.current, reviewId, body);
    setReload((value) => value + 1);
  }

  async function handleReport(reviewId: string, body: string) {
    await reportReview(tokenRef.current, reviewId, body);
    setReload((value) => value + 1);
  }

  return (
    <section aria-labelledby="agency-reviews-heading" className="agency-reviews">
      <h2 id="agency-reviews-heading">Reseñas</h2>
      {state.kind === "loading" ? <p aria-busy="true">Cargando reseñas…</p> : null}
      {state.kind === "error" ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          {state.message}
        </p>
      ) : null}
      {state.kind === "ready" ? (
        <>
          <SummaryHeader summary={state.value.summary} />
          {state.value.reviews.length === 0 ? <p>Todavía no hay reseñas.</p> : null}
          {state.value.reviews.length > 0 ? (
            <ul aria-label="Lista de reseñas" className="chat-reports__list">
              {state.value.reviews.map((review) => (
                <ReviewItem
                  canAct={isAgencyAdmin}
                  key={review.id}
                  onReply={handleReply}
                  onReport={handleReport}
                  review={review}
                />
              ))}
            </ul>
          ) : null}
        </>
      ) : null}
    </section>
  );
}
