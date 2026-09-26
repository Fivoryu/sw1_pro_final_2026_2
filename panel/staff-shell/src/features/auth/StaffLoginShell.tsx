import { useState, type FormEvent } from "react";
import {
  completeStaffLogin,
  startStaffLogin,
  type LoginChallenge,
  type LoginCompletion,
  type StaffLoginVerification,
} from "../../application/staffAuthApi";
import { AuthEditorialPanel } from "./AuthEditorialPanel";

interface StaffLoginShellProps {
  onAuthenticated?: (session: LoginCompletion) => void;
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
}: {
  children: string;
  disabled?: boolean;
}) {
  return (
    <button className="primary-action" disabled={disabled} type="submit">
      <span>{children}</span>
      <span className="primary-action__icon">
        <ArrowMark />
      </span>
    </button>
  );
}

export function StaffLoginShell({
  onAuthenticated,
}: StaffLoginShellProps = {}) {
  const [isPasswordVisible, setIsPasswordVisible] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginChallenge, setLoginChallenge] = useState<LoginChallenge | null>(null);
  const [verificationCode, setVerificationCode] = useState("");
  const [isRecoveryMode, setIsRecoveryMode] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleCredentialsSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setErrorMessage(null);
    setIsSubmitting(true);

    try {
      const challenge = await startStaffLogin({
        email: email.trim(),
        password,
      });
      setPassword("");
      setVerificationCode("");
      setIsRecoveryMode(false);
      setLoginChallenge(challenge);
    } catch {
      setErrorMessage(
        "No pudimos validar tus credenciales. Revisa los datos e inténtalo nuevamente.",
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleMfaSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!loginChallenge) return;

    setErrorMessage(null);
    setIsSubmitting(true);
    const proof: StaffLoginVerification = isRecoveryMode
      ? {
          challenge_token: loginChallenge.challenge_token,
          recovery_code: verificationCode.trim(),
        }
      : {
          challenge_token: loginChallenge.challenge_token,
          code: verificationCode.trim(),
        };

    try {
      const session = await completeStaffLogin(proof);
      onAuthenticated?.(session);
    } catch {
      setErrorMessage("No pudimos verificar tu identidad. Inténtalo nuevamente.");
    } finally {
      setIsSubmitting(false);
    }
  }

  const isMfaStep = loginChallenge !== null;

  return (
    <main className="staff-shell">
      <AuthEditorialPanel />

      <section className="auth-region" aria-labelledby="auth-title">
        <div className="auth-shell">
          <div className="auth-card">
            <div className="auth-card__topline">
              <p className="eyebrow">ESPACIO DE TRABAJO</p>
              <span className="secure-indicator">
                <span className="secure-indicator__dot" />
                ACCESO SEGURO
              </span>
            </div>

            <div className="auth-heading">
              <h1 id="auth-title">
                {isMfaStep ? "Verificación en dos pasos" : "Acceso de personal"}
              </h1>
              <p>
                {isMfaStep
                  ? isRecoveryMode
                    ? "Usa uno de tus códigos de recuperación de un solo uso."
                    : "Confirma tu identidad con el código de autenticación."
                  : "Ingresa con las credenciales de tu cuenta autorizada."}
              </p>
            </div>

            {isMfaStep ? (
              <form
                aria-busy={isSubmitting}
                className="credentials-form"
                onSubmit={handleMfaSubmit}
              >
                <input
                  name="challenge_token"
                  readOnly
                  type="hidden"
                  value={loginChallenge.challenge_token}
                />
                <div className="form-field">
                  <label htmlFor="staff-mfa-code">
                    {isRecoveryMode ? "Código de recuperación" : "Código de autenticación"}
                  </label>
                  <input
                    autoCapitalize={isRecoveryMode ? "characters" : "none"}
                    autoComplete={isRecoveryMode ? "off" : "one-time-code"}
                    autoFocus
                    id="staff-mfa-code"
                    inputMode={isRecoveryMode ? "text" : "numeric"}
                    name={isRecoveryMode ? "recovery_code" : "code"}
                    onChange={(event) => setVerificationCode(event.target.value)}
                    placeholder={isRecoveryMode ? "RF-XXXX-XXXX" : "000 000"}
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
                  {isSubmitting ? "Verificando…" : "Verificar acceso"}
                </PrimaryAction>

                <button
                  aria-pressed={isRecoveryMode}
                  className="proof-mode-switch"
                  onClick={() => {
                    setIsRecoveryMode((recoveryMode) => !recoveryMode);
                    setVerificationCode("");
                    setErrorMessage(null);
                  }}
                  type="button"
                >
                  {isRecoveryMode
                    ? "Usar el código de autenticación"
                    : "Usar un código de recuperación"}
                </button>
              </form>
            ) : (
              <form
                aria-busy={isSubmitting}
                className="credentials-form"
                onSubmit={handleCredentialsSubmit}
              >
                <div className="form-field">
                  <label htmlFor="staff-email">Correo electrónico</label>
                  <input
                    autoComplete="username"
                    autoCapitalize="none"
                    id="staff-email"
                    name="email"
                    onChange={(event) => setEmail(event.target.value)}
                    placeholder="nombre@inmobiliaria.com"
                    required
                    type="email"
                    value={email}
                  />
                </div>

                <div className="form-field">
                  <label htmlFor="staff-password">Contraseña</label>
                  <div className="password-control">
                    <input
                      autoComplete="current-password"
                      id="staff-password"
                      name="password"
                      onChange={(event) => setPassword(event.target.value)}
                      placeholder="Ingresa tu contraseña"
                      required
                      type={isPasswordVisible ? "text" : "password"}
                      value={password}
                    />
                    <button
                      aria-label={isPasswordVisible ? "Ocultar contraseña" : "Mostrar contraseña"}
                      className="password-toggle"
                      onClick={() => setIsPasswordVisible((visible) => !visible)}
                      type="button"
                    >
                      {isPasswordVisible ? "Ocultar" : "Mostrar"}
                    </button>
                  </div>
                </div>

                {errorMessage ? (
                  <p className="form-message form-message--error" role="alert">
                    {errorMessage}
                  </p>
                ) : null}
                <PrimaryAction disabled={isSubmitting}>
                  {isSubmitting ? "Validando…" : "Continuar"}
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
              Tu acceso requiere verificación en dos pasos.
            </p>

            <div className="card-divider" />
            <p className="help-copy">
              ¿Necesitas acceso? Solicita una invitación a la persona administradora de tu organización.
            </p>
          </div>
        </div>

        <p className="auth-legal">ROOMFORGE · ACCESO EXCLUSIVO PARA PERSONAL</p>
      </section>
    </main>
  );
}
