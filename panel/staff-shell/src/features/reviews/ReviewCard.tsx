import { StaffReviewsApiError, type StaffReview } from "../../application/staffReviewsApi";

const SESSION_EXPIRED = "Tu sesión expiró. Cierra sesión y vuelve a ingresar.";

export function reviewsErrorMessage(error: unknown, fallback: string): string {
  if (error instanceof StaffReviewsApiError && error.status === 401) return SESSION_EXPIRED;
  if (error instanceof Error && error.message) return error.message;
  return fallback;
}

export function formatReviewDate(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString("es-BO");
}

interface ReviewBodyProps {
  review: StaffReview;
}

/** Read-only part of a review; the customer is never identified. */
export function ReviewBody({ review }: ReviewBodyProps) {
  return (
    <>
      <p>
        {review.verified ? <strong className="review-badge">Verificada</strong> : null}
        {review.reported ? <strong className="review-badge review-badge--alert"> Reportada</strong> : null}
      </p>
      <p>
        Inmueble {review.listing_id} · {formatReviewDate(review.created_at)}
      </p>
      <p>Inmueble: {review.listing_rating} de 5</p>
      <p>Atención de la agencia: {review.agency_rating} de 5</p>
      {review.comment ? <p>{review.comment}</p> : null}
      {review.agency_reply ? (
        <blockquote>
          <strong>Respuesta de la agencia</strong>
          {review.agency_reply_at ? ` · ${formatReviewDate(review.agency_reply_at)}` : ""}
          <p>{review.agency_reply}</p>
        </blockquote>
      ) : null}
    </>
  );
}
