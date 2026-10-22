import { useCallback, useEffect, useState } from "react";
import {
  createStripeConnectOnboardingLink,
  decideCardReservation,
  getStripeConnectStatus,
  listCardReservations,
  StripeCardPaymentsApiError,
  type CardReservation,
  type StripeConnectStatus,
} from "../../application/stripeCardPaymentsApi";

interface StripeCardPaymentsAdminProps {
  accessToken: string;
  agencyId: string;
}

function failureMessage(error: unknown): string {
  if (error instanceof StripeCardPaymentsApiError && error.status === 403) {
    return "Tu cuenta no tiene permisos para configurar pagos de esta inmobiliaria.";
  }
  return error instanceof Error ? error.message : "No se pudo cargar la gestión de pagos.";
}

export function StripeCardPaymentsAdmin({
  accessToken,
  agencyId,
}: StripeCardPaymentsAdminProps) {
  const [connect, setConnect] = useState<StripeConnectStatus | null>(null);
  const [reservations, setReservations] = useState<CardReservation[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setBusy(true);
    setError(null);
    try {
      const [status, queue] = await Promise.all([
        getStripeConnectStatus(accessToken, agencyId),
        listCardReservations(accessToken, agencyId),
      ]);
      setConnect(status);
      setReservations(queue);
    } catch (failure) {
      setError(failureMessage(failure));
    } finally {
      setBusy(false);
    }
  }, [accessToken, agencyId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function startOnboarding() {
    setBusy(true);
    setError(null);
    try {
      const url = await createStripeConnectOnboardingLink(accessToken, agencyId);
      window.location.assign(url);
    } catch (failure) {
      setError(failureMessage(failure));
      setBusy(false);
    }
  }

  async function decide(reservation: CardReservation, action: "accept" | "reject") {
    const consequence = action === "accept"
      ? "El depósito de prueba se transferirá a la cuenta Stripe Connect de la inmobiliaria."
      : "Stripe procesará el reembolso del depósito de prueba al cliente.";
    if (!window.confirm(`${action === "accept" ? "Aceptar" : "Rechazar"} la reserva ${reservation.reservation_id}? ${consequence}`)) {
      return;
    }
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const result = await decideCardReservation(accessToken, reservation.reservation_id, action);
      setNotice(action === "accept"
        ? `Reserva aceptada; transferencia ${result.payment_status}.`
        : `Reserva rechazada; ${result.payment_status}.`);
      await refresh();
    } catch (failure) {
      setError(failureMessage(failure));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="stripe-card-admin" aria-label="Pagos con tarjeta">
      <header className="stripe-card-admin__header">
        <div>
          <p className="eyebrow">PAGOS · MODO DE PRUEBA</p>
          <h2>Tarjetas y reservas</h2>
          <p className="stripe-card-admin__intro">
            Stripe procesa depósitos de prueba. La wallet sigue siendo un medio de pago independiente.
          </p>
        </div>
        <button className="review-button review-button--secondary" type="button" onClick={() => void refresh()} disabled={busy}>
          Actualizar
        </button>
      </header>

      <section className="stripe-card-admin__connect" aria-label="Cuenta de pagos">
        <div>
          <h3>Cuenta Stripe Connect</h3>
          <p>
            {connect?.connected
              ? "Cuenta habilitada para recibir transferencias de prueba."
              : "Completá la configuración segura de Stripe para recibir depósitos cuando aceptes una reserva."}
          </p>
          {connect ? (
            <p className="stripe-card-admin__status">
              Datos: {connect.details_submitted ? "completos" : "pendientes"} · Transferencias: {connect.payouts_enabled ? "habilitadas" : "pendientes"}
            </p>
          ) : null}
        </div>
        <button className="review-button" type="button" onClick={() => void startOnboarding()} disabled={busy || connect?.connected === true}>
          {connect?.details_submitted ? "Continuar configuración" : "Configurar Stripe Connect"}
        </button>
      </section>

      {error ? <p className="staff-session-error" role="alert">{error}</p> : null}
      {notice ? <p className="stripe-card-admin__notice" role="status">{notice}</p> : null}
      <div className="stripe-card-admin__queue-heading">
        <div>
          <h3>Reservas con tarjeta</h3>
          <p>Solo se muestran pagos confirmados por webhook y pendientes de decisión.</p>
        </div>
        <span>{reservations.length}</span>
      </div>
      {busy && reservations.length === 0 ? <p role="status">Cargando reservas…</p> : null}
      {!busy && reservations.length === 0 ? <p className="rates-admin__empty">No hay reservas con tarjeta pendientes.</p> : null}
      <ul className="stripe-card-admin__list">
        {reservations.map((reservation) => (
          <li key={reservation.reservation_id} className="stripe-card-admin__reservation">
            <div>
              <strong>Reserva {reservation.reservation_id}</strong>
              <p>Inmueble {reservation.listing_id} · Depósito {reservation.deposit_amount ?? "—"} {reservation.currency}</p>
              <p>Pago: {reservation.payment_status} · Vence {new Date(reservation.deadline_at).toLocaleString()}</p>
            </div>
            <div className="stripe-card-admin__actions">
              <button className="review-button" type="button" disabled={busy || !connect?.connected} onClick={() => void decide(reservation, "accept")}>
                Aceptar y transferir
              </button>
              <button className="review-button review-button--secondary" type="button" disabled={busy} onClick={() => void decide(reservation, "reject")}>
                Rechazar y reembolsar
              </button>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
