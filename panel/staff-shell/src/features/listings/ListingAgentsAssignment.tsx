import { useEffect, useId, useRef, useState, type FormEvent } from "react";
import {
  getListingAgents,
  ListingAgentsApiError,
  listAgencyAgents,
  putListingAgents,
  type AgencyAgent,
} from "../../application/listingAgentsApi";

interface ListingAgentsAssignmentProps {
  accessToken: string;
  agencyId: string;
  listingId: string;
}

type LoadState =
  | { kind: "loading" }
  | { kind: "ready"; agents: AgencyAgent[] }
  | { kind: "error"; message: string };

function errorMessage(error: unknown, fallback: string): string {
  if (error instanceof ListingAgentsApiError && error.status === 401) {
    return "Tu sesión expiró. Cierra sesión y vuelve a ingresar.";
  }
  if (error instanceof ListingAgentsApiError) return error.message;
  if (error instanceof Error && error.message) return error.message;
  return fallback;
}

export function ListingAgentsAssignment({
  accessToken,
  agencyId,
  listingId,
}: ListingAgentsAssignmentProps) {
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;
  const [state, setState] = useState<LoadState>({ kind: "loading" });
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [reload, setReload] = useState(0);
  const [isSaving, setIsSaving] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const headingId = useId();

  useEffect(() => {
    let isCurrent = true;
    setState({ kind: "loading" });
    Promise.all([
      listAgencyAgents(tokenRef.current),
      getListingAgents(tokenRef.current, agencyId, listingId),
    ]).then(
      ([agents, assigned]) => {
        if (!isCurrent) return;
        setState({ kind: "ready", agents: agents.filter((agent) => agent.active) });
        setSelected(new Set(assigned.map((agent) => agent.id)));
      },
      (error: unknown) => {
        if (isCurrent) {
          setState({
            kind: "error",
            message: errorMessage(error, "No se pudieron cargar los agentes."),
          });
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [agencyId, listingId, reload]);

  function toggle(agentId: string) {
    setNotice(null);
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(agentId)) next.delete(agentId);
      else next.add(agentId);
      return next;
    });
  }

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (isSaving) return;
    setIsSaving(true);
    setNotice(null);
    setSaveError(null);
    try {
      const saved = await putListingAgents(tokenRef.current, agencyId, listingId, [...selected]);
      setSelected(new Set(saved.map((agent) => agent.id)));
      setNotice("Agentes asignados guardados.");
    } catch (error) {
      setSaveError(errorMessage(error, "No se pudo guardar la asignación."));
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <section aria-labelledby={headingId} className="review-agents">
      <h4 id={headingId}>Agentes asignados</h4>
      {state.kind === "loading" ? <p aria-busy="true">Cargando agentes…</p> : null}
      {state.kind === "error" ? (
        <div className="review-queue__message review-queue__message--error" role="alert">
          <p>{state.message}</p>
          <button
            className="review-button review-button--secondary"
            onClick={() => setReload((value) => value + 1)}
            type="button"
          >
            Reintentar
          </button>
        </div>
      ) : null}
      {state.kind === "ready" ? (
        <form aria-label="Asignar agentes" onSubmit={(event) => void handleSubmit(event)}>
          {state.agents.length === 0 ? <p>No hay agentes activos en la inmobiliaria.</p> : null}
          {state.agents.map((agent) => (
            <label className="review-agents__option" key={agent.id}>
              <input
                checked={selected.has(agent.id)}
                disabled={isSaving}
                onChange={() => toggle(agent.id)}
                type="checkbox"
              />
              {agent.email}
            </label>
          ))}
          {notice ? (
            <p className="review-notice" role="status">
              {notice}
            </p>
          ) : null}
          {saveError ? (
            <p className="review-queue__message review-queue__message--error" role="alert">
              {saveError}
            </p>
          ) : null}
          <button
            className="review-button"
            disabled={isSaving || state.agents.length === 0}
            type="submit"
          >
            {isSaving ? "Guardando…" : "Guardar asignación"}
          </button>
        </form>
      ) : null}
    </section>
  );
}
