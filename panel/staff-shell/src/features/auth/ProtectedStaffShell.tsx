import { useEffect, useState } from "react";
import type { LoginCompletion } from "../../application/staffAuthApi";
import {
  completeStaffSession,
  endStaffSession,
  restoreStaffSession,
  type StaffRole,
  type StaffSession,
} from "../../application/staffSession";
import { StaffLoginShell } from "./StaffLoginShell";

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

  useEffect(() => {
    let isMounted = true;

    void restoreStaffSession()
      .then((restoredSession) => {
        if (isMounted) setSession(restoredSession);
      })
      .catch(() => {
        if (isMounted) setSession(null);
      })
      .finally(() => {
        if (isMounted) setIsRestoring(false);
      });

    return () => {
      isMounted = false;
    };
  }, []);

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

  if (!session) {
    return (
      <>
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
  const isAgencyAdmin = session.user.role === "agency_admin";

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
          {isAgencyAdmin ? (
            <section
              aria-labelledby="agency-review-queue-heading"
              className="protected-staff-review-queue"
            >
              <div className="protected-staff-review-queue__heading">
                <span className="protected-staff-review-queue__eyebrow">
                  PROTOTIPO · SIN CONEXIÓN
                </span>
                <h2 id="agency-review-queue-heading">Cola de revisión</h2>
              </div>
              <div className="protected-staff-review-queue__empty-state">
                <p className="protected-staff-review-queue__empty" role="status">
                  No se muestran solicitudes en este prototipo.
                </p>
                <p className="protected-staff-review-queue__note">
                  Esta vista no está conectada a solicitudes reales.
                </p>
              </div>
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
