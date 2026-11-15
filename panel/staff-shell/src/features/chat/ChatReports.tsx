import { useEffect, useRef, useState } from "react";
import {
  listBlockedCustomers,
  listReports,
  unblockCustomer,
  type BlockedCustomer,
  type ChatReport,
} from "../../application/staffChatApi";
import { chatErrorMessage, formatChatDate } from "./ConversationView";

type LoadState<T> =
  | { kind: "loading" }
  | { kind: "ready"; value: T }
  | { kind: "error"; message: string };

const ROLE_LABELS: Record<ChatReport["reporter_role"], string> = {
  customer: "Cliente",
  agent: "Agente",
  admin: "Administrador",
};

interface ChatReportsProps {
  accessToken: string;
  /** Agency admins also manage blocked customers; platform admins only read reports. */
  showBlocks: boolean;
}

export function ChatReports({ accessToken, showBlocks }: ChatReportsProps) {
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;
  const [reports, setReports] = useState<LoadState<ChatReport[]>>({ kind: "loading" });
  const [blocked, setBlocked] = useState<LoadState<BlockedCustomer[]>>({ kind: "loading" });
  const [reload, setReload] = useState(0);
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => {
    let isCurrent = true;
    setReports({ kind: "loading" });
    listReports(tokenRef.current).then(
      (value) => {
        if (isCurrent) setReports({ kind: "ready", value });
      },
      (error: unknown) => {
        if (isCurrent) {
          setReports({ kind: "error", message: chatErrorMessage(error, "No se pudieron cargar los reportes.") });
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, []);

  useEffect(() => {
    if (!showBlocks) return;
    let isCurrent = true;
    setBlocked({ kind: "loading" });
    listBlockedCustomers(tokenRef.current).then(
      (value) => {
        if (isCurrent) setBlocked({ kind: "ready", value });
      },
      (error: unknown) => {
        if (isCurrent) {
          setBlocked({ kind: "error", message: chatErrorMessage(error, "No se pudieron cargar los bloqueos.") });
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [showBlocks, reload]);

  async function handleUnblock(customerId: string) {
    setActionError(null);
    try {
      await unblockCustomer(tokenRef.current, customerId);
      setReload((value) => value + 1);
    } catch (error) {
      setActionError(chatErrorMessage(error, "No se pudo desbloquear al cliente."));
    }
  }

  return (
    <section aria-labelledby="chat-reports-heading" className="chat-reports">
      <h3 id="chat-reports-heading">Reportes de conversaciones</h3>
      {reports.kind === "loading" ? <p aria-busy="true">Cargando reportes…</p> : null}
      {reports.kind === "error" ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          {reports.message}
        </p>
      ) : null}
      {reports.kind === "ready" && reports.value.length === 0 ? <p>No hay reportes.</p> : null}
      {reports.kind === "ready" && reports.value.length > 0 ? (
        <ul aria-label="Reportes" className="chat-reports__list">
          {reports.value.map((report) => (
            <li key={report.id}>
              <strong>{ROLE_LABELS[report.reporter_role]}</strong>
              <span>
                {" "}
                · Inmueble {report.listing_id} · {formatChatDate(report.created_at)}
              </span>
              <p>{report.reason}</p>
              {report.agent_ids.length > 0 ? (
                <span className="chat-reports__agents">Agentes: {report.agent_ids.join(", ")}</span>
              ) : null}
            </li>
          ))}
        </ul>
      ) : null}

      {showBlocks ? (
        <>
          <h3>Clientes bloqueados</h3>
          {actionError ? (
            <p className="review-queue__message review-queue__message--error" role="alert">
              {actionError}
            </p>
          ) : null}
          {blocked.kind === "loading" ? <p aria-busy="true">Cargando bloqueos…</p> : null}
          {blocked.kind === "error" ? (
            <p className="review-queue__message review-queue__message--error" role="alert">
              {blocked.message}
            </p>
          ) : null}
          {blocked.kind === "ready" && blocked.value.length === 0 ? (
            <p>No hay clientes bloqueados.</p>
          ) : null}
          {blocked.kind === "ready" && blocked.value.length > 0 ? (
            <ul aria-label="Clientes bloqueados" className="chat-reports__list">
              {blocked.value.map((entry) => (
                <li key={entry.customer_id}>
                  <span>
                    Cliente {entry.customer_id} · {formatChatDate(entry.created_at)}
                  </span>
                  <button
                    className="review-button review-button--secondary"
                    onClick={() => void handleUnblock(entry.customer_id)}
                    type="button"
                  >
                    Desbloquear
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
        </>
      ) : null}
    </section>
  );
}
