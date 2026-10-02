import { useEffect, useState } from "react";
import type { LoginCompletion } from "../../application/staffAuthApi";
import {
  completeStaffSession,
  endStaffSession,
  renewalDelayMs,
  renewStaffSession,
  restoreStaffSessionOutcome,
  type StaffRole,
  type StaffSession,
} from "../../application/staffSession";
import { AgencyReviewQueue } from "../listings/AgencyReviewQueue";
import { StaffLoginShell } from "./StaffLoginShell";

const RENEWAL_SKEW_MS = 30_000;
const EXPIRED_SESSION_NOTICE = "Tu sesión expiró. Inicia sesión nuevamente.";
const UNAVAILABLE_NOTICE = "No se pudo contactar el servicio.";
const DENIED_NOTICE = "Tu cuenta no tiene permisos para este panel.";

const rolePresentation: Record<StaffRole, { heading: string; navigation: string }> = {
  platform_admin: {
    heading: "Administración de plataforma",
    navigation: "Inicio de plataforma",
  },
  agency_admin: {
    heading: "Administración de inmobiliaria",
    navigation: "Inicio de inmobiliaria",
  },
  agent: {
    heading: "Área de agente",
    navigation: "Inicio del agente",
  },
};

export function ProtectedStaffShell() {
  const [session, setSession] = useState<StaffSession | null>(null);
  const [isRestoring, setIsRestoring] = useState(true);
  const [isLoggingOut, setIsLoggingOut] = useState(false);
  const [loginFormKey, setLoginFormKey] = useState(0);
  const [authenticationError, setAuthenticationError] = useState<string | null>(null);
  const [logoutError, setLogoutError] = useState<string | null>(null);
  const [sessionNotice, setSessionNotice] = useState<string | null>(null);
  const [failure, setFailure] = useState<"unavailable" | "denied" | null>(null);

  function applySession(nextSession: StaffSession | null) {
    if (
      nextSession !== null &&
      nextSession.accessExpiresAt !== null &&
      nextSession.accessExpiresAt <= Date.now()
    ) {
      setSession(null);
      setSessionNotice(EXPIRED_SESSION_NOTICE);
      return;
    }

    setSession(nextSession);
  }

  useEffect(() => {
    let isMounted = true;

    void (async () => {
      const outcome = await restoreStaffSessionOutcome();
      if (!isMounted) return;

      setFailure(
        outcome.kind === "unavailable" || outcome.kind === "denied"
          ? outcome.kind
          : null,
      );
      if (outcome.kind === "session") {
        setSessionNotice(null);
        applySession(outcome.session);
      } else {
        setSession(null);
      }
      setIsRestoring(false);
    })();

    return () => {
      isMounted = false;
    };
  }, []);

  useEffect(() => {
    if (!session) return;

    const delay = renewalDelayMs(
      session.accessExpiresAt,
      Date.now(),
      RENEWAL_SKEW_MS,
    );
    if (delay === null) return;

    const current = session;
    const timer = window.setTimeout(() => {
      void (async () => {
        const renewed = await renewStaffSession(current);
        if (renewed) {
          applySession(renewed);
          return;
        }
        setSession(null);
        setSessionNotice(EXPIRED_SESSION_NOTICE);
      })();
    }, delay);

    return () => window.clearTimeout(timer);
  }, [session]);

  async function handleAuthenticated(login: LoginCompletion) {
    setAuthenticationError(null);
    try {
      const resolvedSession = await completeStaffSession(login);
      setSession(resolvedSession);
    } catch {
      setAuthenticationError(
        "No se pudo confirmar la sesión. Inicia sesión nuevamente.",
      );
      setLoginFormKey((key) => key + 1);
    }
  }

  async function handleRetryRestoration() {
    setFailure(null);
    setIsRestoring(true);
    const outcome = await restoreStaffSessionOutcome();
    setFailure(
      outcome.kind === "unavailable" || outcome.kind === "denied"
        ? outcome.kind
        : null,
    );
    if (outcome.kind === "session") {
      setSessionNotice(null);
      applySession(outcome.session);
    } else {
      setSession(null);
    }
    setIsRestoring(false);
  }

  async function handleLogout() {
    if (!session || isLoggingOut) return;

    setIsLoggingOut(true);
    setLogoutError(null);
    try {
      await endStaffSession(session);
      setSession(null);
    } catch {
      setLogoutError("No se pudo cerrar la sesión. Inténtalo nuevamente.");
    } finally {
      setIsLoggingOut(false);
    }
  }

  if (isRestoring) {
    return (
      <main className="staff-session-loading" role="status">
        Comprobando la sesión de personal…
      </main>
    );
  }

  if (failure === "denied") {
    return (
      <main className="staff-session-error" role="alert">
        <p>{DENIED_NOTICE}</p>
        <button
          className="staff-logout-action"
          onClick={() => setFailure(null)}
          type="button"
        >
          Volver al inicio de sesión
        </button>
      </main>
    );
  }

  if (failure === "unavailable") {
    return (
      <main className="staff-session-error" role="alert">
        <p>{UNAVAILABLE_NOTICE}</p>
        <button
          className="staff-logout-action"
          onClick={() => void handleRetryRestoration()}
          type="button"
        >
          Reintentar
        </button>
      </main>
    );
  }

  if (!session) {
    return (
      <>
        {sessionNotice ? (
          <p className="staff-session-error" role="alert">
            {sessionNotice}
          </p>
        ) : null}
        {authenticationError ? (
          <p className="staff-session-error" role="alert">
            {authenticationError}
          </p>
        ) : null}
        <StaffLoginShell key={loginFormKey} onAuthenticated={handleAuthenticated} />
      </>
    );
  }

  const presentation = rolePresentation[session.user.role];
  const agencyId = session.user.tenant_id;

  return (
    <div className="protected-staff-workspace">
      <header className="protected-staff-header">
        <div className="protected-staff-brand" aria-label="RoomForge">
          <span className="protected-staff-brand__mark" aria-hidden="true">
            RF
          </span>
          <span className="brand-wordmark">ROOMFORGE</span>
        </div>
        <div className="protected-staff-identity">
          <span>{presentation.heading}</span>
          <span>{session.user.email}</span>
        </div>
        <button
          className="staff-logout-action"
          disabled={isLoggingOut}
          onClick={() => void handleLogout()}
          type="button"
        >
          {isLoggingOut ? "Cerrando sesión…" : "Cerrar sesión"}
        </button>
      </header>

      <div className="protected-staff-body">
        <nav aria-label="Navegación principal" className="protected-staff-navigation">
          <span aria-current="page">{presentation.navigation}</span>
        </nav>
        <main className="protected-staff-content">
          <p className="eyebrow">ESPACIO PRIVADO</p>
          <h1>{presentation.heading}</h1>
          {logoutError ? (
            <p className="staff-session-error" role="alert">
              {logoutError}
            </p>
          ) : null}
          {session.user.role === "agency_admin" && agencyId ? (
            <AgencyReviewQueue accessToken={session.accessToken} agencyId={agencyId} />
          ) : session.user.role === "agent" ? (
            <section className="protected-staff-placeholder" aria-label="Vista inicial">
              <span className="protected-staff-placeholder__eyebrow">
                ROOMFORGE · CAPTURA
              </span>
              <p>Los borradores de inmuebles se crean y editan en la app RoomForge Captura.</p>
              <p>Desde allí envías cada inmueble a revisión de tu inmobiliaria.</p>
            </section>
          ) : (
            <section className="protected-staff-placeholder" aria-label="Vista inicial">
              <span className="protected-staff-placeholder__eyebrow">
                ROOMFORGE · PERSONAL
              </span>
              <p>El espacio protegido está listo.</p>
            </section>
          )}
        </main>
      </div>
    </div>
  );
}
