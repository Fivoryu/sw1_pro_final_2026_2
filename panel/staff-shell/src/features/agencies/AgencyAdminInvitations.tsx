import { useEffect, useId, useRef, useState, type FormEvent } from "react";
import {
  AgencyAdminInvitationsApiError,
  getAgencies,
  sendAgencyAdminInvitation,
  type AgencySummary,
} from "../../application/agencyAdminInvitationsApi";

interface AgencyAdminInvitationsProps {
  accessToken: string;
}

type AgencyLoadState =
  | { kind: "loading" }
  | { kind: "ready"; agencies: AgencySummary[] }
  | { kind: "error"; message: string };

const LOAD_FALLBACK = "No se pudieron cargar las inmobiliarias.";
const SUBMIT_FALLBACK = "No se pudo enviar la invitación. Inténtalo nuevamente.";
const SESSION_EXPIRED = "Tu sesión expiró. Cierra sesión y vuelve a ingresar.";
const FORBIDDEN = "Tu cuenta no tiene permisos para enviar invitaciones.";

function apiErrorMessage(error: unknown, fallback: string): string {
  if (error instanceof AgencyAdminInvitationsApiError && error.status === 401) {
    return SESSION_EXPIRED;
  }
  if (error instanceof AgencyAdminInvitationsApiError && error.status === 403) {
    return FORBIDDEN;
  }
  if (error instanceof AgencyAdminInvitationsApiError) return error.message;
  if (error instanceof Error && error.message) return error.message;
  return fallback;
}

export function AgencyAdminInvitations({ accessToken }: AgencyAdminInvitationsProps) {
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;
  const [reload, setReload] = useState(0);
  const [agencies, setAgencies] = useState<AgencyLoadState>({ kind: "loading" });
  const [selectedAgency, setSelectedAgency] = useState("");
  const [email, setEmail] = useState("");
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const agencyId = useId();
  const emailId = useId();

  useEffect(() => {
    let isCurrent = true;
    setAgencies({ kind: "loading" });
    void getAgencies(tokenRef.current).then(
      (response) => {
        if (!isCurrent) return;
        setAgencies({ kind: "ready", agencies: response.agencies });
        setSelectedAgency((current) =>
          response.agencies.some((agency) => agency.id === current)
            ? current
            : response.agencies[0]?.id ?? "",
        );
      },
      (error: unknown) => {
        if (isCurrent) {
          setAgencies({ kind: "error", message: apiErrorMessage(error, LOAD_FALLBACK) });
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [reload]);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (isSubmitting || !selectedAgency || !email.trim()) return;

    setIsSubmitting(true);
    setSubmitError(null);
    setNotice(null);
    try {
      await sendAgencyAdminInvitation(tokenRef.current, selectedAgency, email.trim());
      setEmail("");
      setNotice("La invitación se envió al outbox local de desarrollo.");
    } catch (error) {
      setSubmitError(apiErrorMessage(error, SUBMIT_FALLBACK));
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <section aria-labelledby="agency-admin-invitations-heading" className="agency-admin-invitations">
      <div className="protected-staff-review-queue__heading">
        <span className="protected-staff-review-queue__eyebrow">ADMINISTRACIÓN DE PLATAFORMA</span>
        <h2 id="agency-admin-invitations-heading">Invitar administrador de inmobiliaria</h2>
        <p>La invitación se entrega al outbox local de desarrollo.</p>
      </div>

      {agencies.kind === "loading" ? (
        <p aria-busy="true" className="review-queue__message" role="status">
          Cargando inmobiliarias…
        </p>
      ) : null}
      {agencies.kind === "error" ? (
        <div className="review-queue__message review-queue__message--error" role="alert">
          <p>{agencies.message}</p>
          <button className="review-button review-button--secondary" onClick={() => setReload((value) => value + 1)} type="button">
            Reintentar
          </button>
        </div>
      ) : null}
      {agencies.kind === "ready" ? (
        <form aria-label="Enviar invitación de administrador" className="agency-admin-invitations__form" onSubmit={(event) => void handleSubmit(event)}>
          {agencies.agencies.length === 0 ? <p>No hay inmobiliarias disponibles.</p> : null}
          <div className="rates-admin__field">
            <label htmlFor={agencyId}>Inmobiliaria</label>
            <select disabled={agencies.agencies.length === 0 || isSubmitting} id={agencyId} onChange={(event) => setSelectedAgency(event.target.value)} value={selectedAgency}>
              {agencies.agencies.map((agency) => <option key={agency.id} value={agency.id}>{agency.id}</option>)}
            </select>
          </div>
          <div className="rates-admin__field">
            <label htmlFor={emailId}>Correo del administrador</label>
            <input disabled={isSubmitting} id={emailId} onChange={(event) => setEmail(event.target.value)} required type="email" value={email} />
          </div>
          {notice ? <p className="review-notice" role="status">{notice}</p> : null}
          {submitError ? <p className="review-queue__message review-queue__message--error" role="alert">{submitError}</p> : null}
          <button className="review-button" disabled={isSubmitting || agencies.agencies.length === 0} type="submit">
            {isSubmitting ? "Enviando…" : "Enviar invitación"}
          </button>
        </form>
      ) : null}
    </section>
  );
}
