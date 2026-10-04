import { useEffect, useId, useRef, useState, type FormEvent } from "react";
import {
  createExchangeRate,
  ExchangeRatesApiError,
  getCurrentExchangeRates,
  getExchangeRateHistory,
  type CurrentExchangeRate,
  type ExchangeRateRecord,
  type RateCurrency,
} from "../../application/exchangeRatesApi";

type LoadState<T> =
  | { kind: "loading" }
  | { kind: "ready"; value: T }
  | { kind: "error"; message: string };

interface RatesValue {
  current: CurrentExchangeRate[];
  history: ExchangeRateRecord[];
}

interface ExchangeRatesAdminProps {
  accessToken: string;
}

const RATE_CURRENCIES: RateCurrency[] = ["BOB", "USDT"];

const CURRENCY_LABELS: Record<CurrentExchangeRate["currency"], string> = {
  BOB: "Bolivianos (BOB)",
  USD: "Dólares (USD)",
  USDT: "Tether (USDT)",
};

const NO_ADMINISTERED_RATE = "Sin tasa administrada";
const SESSION_EXPIRED = "Tu sesión expiró. Cierra sesión y vuelve a ingresar.";
const FORBIDDEN = "Tu cuenta no tiene permisos para administrar las tasas de cambio.";
const VALIDATION_MESSAGE =
  "Ingresa una tasa positiva con hasta ocho decimales.";
const SUBMIT_FALLBACK = "No se pudo registrar la tasa. Inténtalo nuevamente.";
const LOAD_FALLBACK = "No se pudieron cargar las tasas de cambio.";
const SUCCESS_NOTICE = "Tasa registrada.";

/** Client mirror of the server rule: positive decimal with at most eight places. */
const UNITS_PER_USD_PATTERN = /^\d+(\.\d{1,8})?$/;

function isValidUnitsPerUsd(value: string): boolean {
  const trimmed = value.trim();
  if (!UNITS_PER_USD_PATTERN.test(trimmed)) return false;
  return Number(trimmed) > 0;
}

function formatDate(value: string | null): string {
  if (value === null) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? value
    : new Intl.DateTimeFormat("es-CO", { dateStyle: "medium", timeStyle: "short" }).format(
        date,
      );
}

function errorMessage(error: unknown, fallback: string): string {
  if (error instanceof ExchangeRatesApiError && error.status === 401) {
    return SESSION_EXPIRED;
  }
  if (error instanceof ExchangeRatesApiError && error.status === 403) {
    return FORBIDDEN;
  }
  if (error instanceof ExchangeRatesApiError) {
    return error.message;
  }
  return fallback;
}

export function ExchangeRatesAdmin({ accessToken }: ExchangeRatesAdminProps) {
  // The shell rotates the access token; keep the latest without refetching on rotation.
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;

  const [ratesReload, setRatesReload] = useState(0);
  const [rates, setRates] = useState<LoadState<RatesValue>>({ kind: "loading" });
  const [currency, setCurrency] = useState<RateCurrency>("BOB");
  const [unitsPerUsd, setUnitsPerUsd] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const currencyId = useId();
  const unitsId = useId();

  useEffect(() => {
    let isCurrent = true;
    setRates({ kind: "loading" });
    Promise.all([
      getCurrentExchangeRates(tokenRef.current),
      getExchangeRateHistory(tokenRef.current),
    ]).then(
      ([current, history]) => {
        if (isCurrent) {
          setRates({ kind: "ready", value: { current: current.rates, history: history.rates } });
        }
      },
      (error: unknown) => {
        if (isCurrent) {
          setRates({
            kind: "error",
            message: errorMessage(error, LOAD_FALLBACK),
          });
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [ratesReload]);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (isSubmitting) return;

    if (!isValidUnitsPerUsd(unitsPerUsd)) {
      setFormError(VALIDATION_MESSAGE);
      return;
    }

    setIsSubmitting(true);
    setFormError(null);
    setNotice(null);
    try {
      await createExchangeRate(tokenRef.current, {
        currency,
        unitsPerUsd: unitsPerUsd.trim(),
      });
      setNotice(SUCCESS_NOTICE);
      setUnitsPerUsd("");
      setRatesReload((value) => value + 1);
    } catch (error) {
      setFormError(errorMessage(error, SUBMIT_FALLBACK));
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <section
      aria-labelledby="exchange-rates-admin-heading"
      className="rates-admin"
    >
      <div className="protected-staff-review-queue__heading">
        <span className="protected-staff-review-queue__eyebrow">
          ADMINISTRACIÓN DE PLATAFORMA
        </span>
        <h2 id="exchange-rates-admin-heading">Tasas de cambio</h2>
        <p className="rates-admin__intro">
          La tasa vigente se aplica a las cotizaciones nuevas; las cotizaciones
          existentes conservan la tasa congelada al momento de crearse.
        </p>
      </div>

      {rates.kind === "loading" ? (
        <p aria-busy="true" className="review-queue__message">
          Cargando tasas de cambio…
        </p>
      ) : null}
      {rates.kind === "error" ? (
        <div className="review-queue__message review-queue__message--error" role="alert">
          <p>{rates.message}</p>
          <button
            className="review-button review-button--secondary"
            onClick={() => setRatesReload((value) => value + 1)}
            type="button"
          >
            Reintentar
          </button>
        </div>
      ) : null}

      {rates.kind === "ready" ? (
        <>
          <section>
            <h3>Tasas vigentes</h3>
            <ul aria-label="Tasas vigentes" className="rates-admin__current">
              {rates.value.current.map((rate) => (
                <li key={rate.currency}>
                  <span className="rates-admin__currency">
                    {CURRENCY_LABELS[rate.currency]}
                  </span>
                  <span className="rates-admin__value">
                    {rate.units_per_usd === null
                      ? NO_ADMINISTERED_RATE
                      : `${rate.currency} ${rate.units_per_usd}`}
                  </span>
                  <span className="rates-admin__date">
                    {rate.currency === "USD"
                      ? "Referencia fija de conversión"
                      : formatDate(rate.created_at)}
                  </span>
                </li>
              ))}
            </ul>
          </section>

          <section>
            <h3>Historial de tasas</h3>
            {rates.value.history.length === 0 ? (
              <p className="rates-admin__empty">Aún no hay tasas registradas.</p>
            ) : (
              <ol aria-label="Historial de tasas" className="rates-admin__history">
                {rates.value.history.map((rate) => (
                  <li key={rate.id}>
                    <span className="rates-admin__value">
                      {rate.currency} {rate.units_per_usd}
                    </span>
                    <span className="rates-admin__date">
                      Vigente desde {formatDate(rate.created_at)}
                    </span>
                  </li>
                ))}
              </ol>
            )}
          </section>

          <form
            aria-label="Registrar nueva tasa"            className="rates-admin__form"
            onSubmit={(event) => void handleSubmit(event)}
          >
            <h3>Registrar nueva tasa</h3>
            <p className="rates-admin__form-intro">
              La tasa expresa cuántas unidades de la moneda equivalen a 1 USD.
              La moneda USD es la referencia y se mantiene fija en 1.
            </p>
            {notice ? (
              <p className="review-notice" role="status">
                {notice}
              </p>
            ) : null}
            {formError ? (
              <p className="review-queue__message review-queue__message--error" role="alert">
                {formError}
              </p>
            ) : null}
            <div className="rates-admin__controls">
              <div className="rates-admin__field">
                <label htmlFor={currencyId}>Moneda</label>
                <select
                  id={currencyId}
                  onChange={(event) => setCurrency(event.target.value as RateCurrency)}
                  value={currency}
                >
                  {RATE_CURRENCIES.map((option) => (
                    <option key={option} value={option}>
                      {option}
                    </option>
                  ))}
                </select>
              </div>
              <div className="rates-admin__field">
                <label htmlFor={unitsId}>Unidades por USD</label>
                <input
                  id={unitsId}
                  inputMode="decimal"
                  onChange={(event) => setUnitsPerUsd(event.target.value)}
                  placeholder="6.96000000"
                  type="text"
                  value={unitsPerUsd}
                />
              </div>
              <button
                className="review-button"
                disabled={isSubmitting}
                type="submit"
              >
                {isSubmitting ? "Registrando…" : "Registrar tasa"}
              </button>
            </div>
          </form>
        </>
      ) : null}
    </section>
  );
}
