import { useEffect, useState, type FormEvent } from "react";
import {
  acceptStaffInvitation,
  verifyStaffEnrollment,
  type InvitationEnrollment,
} from "../../application/staffAuthApi";
import { AuthEditorialPanel } from "./AuthEditorialPanel";

export interface InvitationAcceptancePageProps {
  invitationToken: string | null;
  onComplete?: () => void;
}

function ArrowMark() {
  return (
    <svg aria-hidden="true" fill="none" viewBox="0 0 20 20">
      <path
        d="M4.2 10h11.2m0 0-4.5-4.5m4.5 4.5-4.5 4.5"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.5"
      />
    </svg>
  );
}

function PrimaryAction({
  children,
  disabled = false,
  onClick,
  type = "submit",
}: {
  children: string;
  disabled?: boolean;
  onClick?: () => void;
  type?: "button" | "submit";
}) {
  return (
    <button
      className="primary-action"
      disabled={disabled}
      onClick={onClick}
      type={type}
    >
      <span>{children}</span>
      <span className="primary-action__icon">
        <ArrowMark />
      </span>
    </button>
  );
}

export function InvitationAcceptancePage({
  invitationToken,
  onComplete,
}: InvitationAcceptancePageProps) {
  const hasInvitationToken =
    typeof invitationToken === "string" && invitationToken.trim().length > 0;
  const [password, setPassword] = useState("");
  const [passwordConfirmation, setPasswordConfirmation] = useState("");
  const [enrollment, setEnrollment] = useState<InvitationEnrollment | null>(null);
  const [verificationCode, setVerificationCode] = useState("");
  const [recoveryCodes, setRecoveryCodes] = useState<string[] | null>(null);
  const [isComplete, setIsComplete] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    if (!hasInvitationToken) {
      setPassword("");
      setPasswordConfirmation("");
      setEnrollment(null);
      setVerificationCode("");
      setRecoveryCodes(null);
      setIsComplete(false);
      setErrorMessage(null);
    }
  }, [hasInvitationToken]);

  async function handleAcceptanceSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!hasInvitationToken || invitationToken === null) return;

    if (password !== passwordConfirmation) {
      setErrorMessage("Las contraseñas no coinciden.");
      return;
    }

    setErrorMessage(null);
    setIsSubmitting(true);

    try {
      const setup = await acceptStaffInvitation({
        token: invitationToken,
        password,
        password_confirmation: passwordConfirmation,
      });
      setPassword("");
      setPasswordConfirmation("");
      setEnrollment(setup);
    } catch {
      setErrorMessage(
        "No pudimos validar la invitación. Comprueba que el enlace siga vigente e inténtalo nuevamente.",
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleVerificationSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!enrollment) return;

    setErrorMessage(null);
    setIsSubmitting(true);

    try {
      const completion = await verifyStaffEnrollment({
        enrollment_token: enrollment.enrollment_token,
        code: verificationCode.trim(),
      });
      setEnrollment(null);
      setVerificationCode("");
      setRecoveryCodes(completion.recovery_codes);
    } catch {
      setErrorMessage(
        "No pudimos verificar el código. Comprueba la hora de tu dispositivo e inténtalo nuevamente.",
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  function handleRecoveryAcknowledgement() {
    setRecoveryCodes(null);
    setPassword("");
    setPasswordConfirmation("");
    setVerificationCode("");
    setIsComplete(true);
    onComplete?.();
  }

  const heading = !hasInvitationToken
    ? "Invitación no válida"
    : recoveryCodes !== null
      ? "Guarda tus códigos de recuperación"
      : isComplete
        ? "Acceso activado"
        : enrollment
          ? "Configura la autenticación en dos pasos"
          : "Acepta tu invitación";

  return (
    <main className="staff-shell invitation-shell">
      <AuthEditorialPanel />

      <section className="auth-region" aria-labelledby="invitation-title">
        <div className="auth-shell">
          <div className="auth-card invitation-card">
            <div className="auth-card__topline">
              <p className="eyebrow">ACTIVACIÓN DE PERSONAL</p>
              <span className="secure-indicator">
                <span className="secure-indicator__dot" />
                ACCESO SEGURO
              </span>
            </div>

            <div className="auth-heading invitation-heading">
              <h1 id="invitation-title">{heading}</h1>
              {hasInvitationToken ? (
                <p>
                  {recoveryCodes !== null
                    ? "Guarda estos códigos en un lugar seguro. No volverán a mostrarse."
                    : isComplete
                      ? "Tu cuenta de personal está lista para usarse."
                      : enrollment
                        ? "Añade RoomForge a tu aplicación autenticadora y confirma el código generado."
                        : "Define una contraseña para activar tu acceso privado a RoomForge."}
                </p>
              ) : (
                <p>
                  El enlace de invitación no está disponible o ya no es válido. Solicita
                  una nueva invitación a la persona administradora.
                </p>
              )}
            </div>

            {!hasInvitationToken ? (
              <div className="invitation-status" role="status">
                No se puede continuar sin una invitación válida.
              </div>
            ) : recoveryCodes !== null ? (
              <section className="recovery-panel" aria-label="Códigos de recuperación">
                <ul className="recovery-code-list">
                  {recoveryCodes.map((code) => (
                    <li key={code}>
                      <code>{code}</code>
                    </li>
                  ))}
                </ul>
                <p className="help-copy">
                  Cada código se puede usar una sola vez. Cópialos ahora; por seguridad,
                  RoomForge no los guarda ni volverá a mostrarlos.
                </p>
                <PrimaryAction onClick={handleRecoveryAcknowledgement} type="button">
                  Ya guardé mis códigos
                </PrimaryAction>
              </section>
            ) : isComplete ? (
              <div className="invitation-status" role="status">
                La configuración terminó correctamente. Ya puedes iniciar sesión.
              </div>
            ) : enrollment ? (
              <>
                <div className="enrollment-details">
                  <div className="enrollment-value">
                    <span className="enrollment-value__label">Clave de configuración</span>
                    <code>{enrollment.totp_secret}</code>
                  </div>
                  <div className="enrollment-value">
                    <span className="enrollment-value__label">URI de configuración</span>
                    <code className="enrollment-uri">{enrollment.provisioning_uri}</code>
                  </div>
                  <a
                    className="authenticator-link"
                    href={enrollment.provisioning_uri}
                  >
                    Abrir en aplicación autenticadora
                  </a>
                </div>

                <form
                  aria-busy={isSubmitting}
                  className="credentials-form"
                  onSubmit={handleVerificationSubmit}
                >
                  <div className="form-field">
                    <label htmlFor="staff-enrollment-code">Código de autenticación</label>
                    <input
                      autoComplete="one-time-code"
                      autoFocus
                      id="staff-enrollment-code"
                      inputMode="numeric"
                      maxLength={6}
                      onChange={(event) => setVerificationCode(event.target.value)}
                      placeholder="000 000"
                      required
                      spellCheck={false}
                      type="text"
                      value={verificationCode}
                    />
                  </div>

                  {errorMessage ? (
                    <p className="form-message form-message--error" role="alert">
                      {errorMessage}
                    </p>
                  ) : null}

                  <PrimaryAction disabled={isSubmitting}>
                    {isSubmitting ? "Verificando…" : "Verificar TOTP"}
                  </PrimaryAction>
                </form>
              </>
            ) : (
              <form
                aria-busy={isSubmitting}
                className="credentials-form"
                onSubmit={handleAcceptanceSubmit}
              >
                <div className="form-field">
                  <label htmlFor="staff-new-password">Nueva contraseña</label>
                  <input
                    autoComplete="new-password"
                    id="staff-new-password"
                    onChange={(event) => setPassword(event.target.value)}
                    required
                    type="password"
                    value={password}
                  />
                </div>

                <div className="form-field">
                  <label htmlFor="staff-password-confirmation">Confirmar contraseña</label>
                  <input
                    autoComplete="new-password"
                    id="staff-password-confirmation"
                    onChange={(event) => setPasswordConfirmation(event.target.value)}
                    required
                    type="password"
                    value={passwordConfirmation}
                  />
                </div>

                {errorMessage ? (
                  <p className="form-message form-message--error" role="alert">
                    {errorMessage}
                  </p>
                ) : null}

                <PrimaryAction disabled={isSubmitting}>
                  {isSubmitting ? "Activando…" : "Continuar"}
                </PrimaryAction>
              </form>
            )}

            <p className="security-note">
              <span aria-hidden="true" className="security-note__mark">
                <svg fill="none" viewBox="0 0 20 20">
                  <path
                    d="M10 2.6 16 5v4.8c0 3.6-2.4 6.1-6 7.6-3.6-1.5-6-4-6-7.6V5l6-2.4Z"
                    stroke="currentColor"
                    strokeLinejoin="round"
                    strokeWidth="1.35"
                  />
                  <path
                    d="m7.5 9.9 1.6 1.6 3.5-3.6"
                    stroke="currentColor"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="1.35"
                  />
                </svg>
              </span>
              La activación de personal requiere verificación en dos pasos.
            </p>

            <div className="card-divider" />
            <p className="auth-legal">ROOMFORGE · ACCESO EXCLUSIVO PARA PERSONAL</p>
          </div>
        </div>
      </section>
    </main>
  );
}
