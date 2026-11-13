import { useEffect, useId, useRef, useState, type FormEvent } from "react";
import {
  listAgencyAgents,
  type AgencyAgent,
} from "../../application/listingAgentsApi";
import {
  blockCustomer,
  listMessages,
  reassignConversation,
  reportCustomer,
  sendMessage,
  StaffChatApiError,
  type StaffConversation,
  type StaffMessage,
} from "../../application/staffChatApi";

export const MESSAGE_POLL_MS = 3_000;

const SESSION_EXPIRED = "Tu sesión expiró. Cierra sesión y vuelve a ingresar.";

export function chatErrorMessage(error: unknown, fallback: string): string {
  if (error instanceof StaffChatApiError && error.status === 401) return SESSION_EXPIRED;
  if (error instanceof StaffChatApiError) return error.message;
  if (error instanceof Error && error.message) return error.message;
  return fallback;
}

export function formatChatDate(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString("es-BO");
}

const SENDER_LABELS: Record<StaffMessage["sender"], string> = {
  customer: "Cliente",
  agent: "Agente",
  admin: "Administrador",
};

interface ConversationViewProps {
  accessToken: string;
  conversation: StaffConversation;
  isAgencyAdmin: boolean;
  onBack: () => void;
  /** The inbox must reload: ownership or state may have changed. */
  onChanged: () => void;
  /** Another agent won the first-reply claim. */
  onTaken: () => void;
}

export function ConversationView({
  accessToken,
  conversation,
  isAgencyAdmin,
  onBack,
  onChanged,
  onTaken,
}: ConversationViewProps) {
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;
  const lastIdRef = useRef(0);
  const [messages, setMessages] = useState<StaffMessage[]>([]);
  const [pageReadOnly, setPageReadOnly] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [draft, setDraft] = useState("");
  const [isSending, setIsSending] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const draftId = useId();

  const readOnly = conversation.read_only || pageReadOnly;

  function merge(incoming: StaffMessage[]) {
    if (incoming.length === 0) return;
    setMessages((current) => {
      const known = new Set(current.map((message) => message.id));
      const fresh = incoming.filter((message) => !known.has(message.id));
      return fresh.length === 0 ? current : [...current, ...fresh];
    });
    lastIdRef.current = Math.max(lastIdRef.current, ...incoming.map((message) => message.id));
  }

  useEffect(() => {
    let isCurrent = true;
    lastIdRef.current = 0;
    setMessages([]);
    setIsLoading(true);
    setLoadError(null);

    async function poll(initial: boolean) {
      try {
        const page = await listMessages(tokenRef.current, conversation.id, lastIdRef.current);
        if (!isCurrent) return;
        merge(page.messages);
        setPageReadOnly(page.read_only);
        setLoadError(null);
      } catch (error) {
        if (isCurrent) {
          setLoadError(chatErrorMessage(error, "No se pudieron cargar los mensajes."));
        }
      } finally {
        if (isCurrent && initial) setIsLoading(false);
      }
    }

    void poll(true);
    const timer = window.setInterval(() => void poll(false), MESSAGE_POLL_MS);
    return () => {
      isCurrent = false;
      window.clearInterval(timer);
    };
  }, [conversation.id]);

  async function handleSend(event: FormEvent) {
    event.preventDefault();
    const body = draft.trim();
    if (readOnly || isSending || !body) return;

    setIsSending(true);
    setSendError(null);
    try {
      const sent = await sendMessage(tokenRef.current, conversation.id, body);
      setDraft("");
      merge([sent]);
      onChanged();
    } catch (error) {
      if (error instanceof StaffChatApiError && error.isConversationTaken) {
        onTaken();
      } else {
        setSendError(chatErrorMessage(error, "No se pudo enviar el mensaje."));
      }
    } finally {
      setIsSending(false);
    }
  }

  return (
    <article aria-label="Conversación" className="chat-conversation">
      <button className="review-button review-button--link" onClick={onBack} type="button">
        Volver a la bandeja
      </button>
      <header className="chat-conversation__header">
        <h3>{conversation.customer_email}</h3>
        <p>Inmueble {conversation.listing_id}</p>
        {isAgencyAdmin && conversation.agent_email ? (
          <p>Atiende: {conversation.agent_email}</p>
        ) : null}
      </header>

      {isLoading ? (
        <p aria-busy="true" className="review-queue__message">
          Cargando mensajes…
        </p>
      ) : null}
      {loadError ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          {loadError}
        </p>
      ) : null}

      <ol aria-label="Mensajes" className="chat-messages">
        {messages.map((message) => (
          <li
            className={`chat-message chat-message--${message.sender}${
              message.mine ? " chat-message--mine" : ""
            }`}
            key={message.id}
          >
            <span className="chat-message__meta">
              {SENDER_LABELS[message.sender]}
              {message.mine ? " (tú)" : ""}
              {isAgencyAdmin && message.author_email ? ` · ${message.author_email}` : ""} ·{" "}
              {formatChatDate(message.created_at)}
            </span>
            <span className="chat-message__body">{message.body}</span>
          </li>
        ))}
      </ol>

      {readOnly ? (
        <p className="review-notice" role="status">
          Esta conversación es de solo lectura.
        </p>
      ) : null}
      {sendError ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          {sendError}
        </p>
      ) : null}
      <form className="chat-compose" onSubmit={(event) => void handleSend(event)}>
        <label htmlFor={draftId}>Mensaje</label>
        <textarea
          disabled={readOnly || isSending}
          id={draftId}
          maxLength={2000}
          onChange={(event) => setDraft(event.target.value)}
          rows={3}
          value={draft}
        />
        <button
          className="review-button"
          disabled={readOnly || isSending || !draft.trim()}
          type="submit"
        >
          {isSending ? "Enviando…" : "Enviar"}
        </button>
      </form>

      <ConversationModeration
        accessToken={accessToken}
        conversation={conversation}
        isAgencyAdmin={isAgencyAdmin}
        onChanged={onChanged}
      />
    </article>
  );
}

interface ConversationModerationProps {
  accessToken: string;
  conversation: StaffConversation;
  isAgencyAdmin: boolean;
  onChanged: () => void;
}

function ConversationModeration({
  accessToken,
  conversation,
  isAgencyAdmin,
  onChanged,
}: ConversationModerationProps) {
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;
  const [reason, setReason] = useState("");
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const reasonId = useId();

  async function run(action: () => Promise<void>, success: string, fallback: string) {
    if (busy) return;
    setBusy(true);
    setNotice(null);
    setError(null);
    try {
      await action();
      setNotice(success);
    } catch (caught) {
      setError(chatErrorMessage(caught, fallback));
    } finally {
      setBusy(false);
    }
  }

  async function handleReport(event: FormEvent) {
    event.preventDefault();
    const text = reason.trim();
    if (!text) return;
    await run(
      async () => {
        await reportCustomer(tokenRef.current, conversation.id, text);
        setReason("");
      },
      "Reporte enviado.",
      "No se pudo enviar el reporte.",
    );
  }

  return (
    <section aria-label="Moderación" className="chat-moderation">
      {isAgencyAdmin ? (
        <ReassignControl
          accessToken={accessToken}
          conversationId={conversation.id}
          onDone={onChanged}
        />
      ) : null}

      <form aria-label="Reportar cliente" onSubmit={(event) => void handleReport(event)}>
        <label htmlFor={reasonId}>Motivo del reporte</label>
        <textarea
          disabled={busy}
          id={reasonId}
          maxLength={2000}
          onChange={(event) => setReason(event.target.value)}
          rows={2}
          value={reason}
        />
        <button
          className="review-button review-button--secondary"
          disabled={busy || !reason.trim()}
          type="submit"
        >
          Reportar cliente
        </button>
      </form>

      {isAgencyAdmin && conversation.customer_id ? (
        <button
          className="review-button review-button--secondary"
          disabled={busy}
          onClick={() =>
            void run(
              () => blockCustomer(tokenRef.current, conversation.customer_id ?? ""),
              "Cliente bloqueado.",
              "No se pudo bloquear al cliente.",
            )
          }
          type="button"
        >
          Bloquear cliente
        </button>
      ) : null}

      {notice ? (
        <p className="review-notice" role="status">
          {notice}
        </p>
      ) : null}
      {error ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          {error}
        </p>
      ) : null}
    </section>
  );
}

interface ReassignControlProps {
  accessToken: string;
  conversationId: string;
  onDone: () => void;
}

function ReassignControl({ accessToken, conversationId, onDone }: ReassignControlProps) {
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;
  const [agents, setAgents] = useState<AgencyAgent[]>([]);
  const [target, setTarget] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const selectId = useId();

  useEffect(() => {
    let isCurrent = true;
    listAgencyAgents(tokenRef.current).then(
      (list) => {
        if (isCurrent) setAgents(list.filter((agent) => agent.active));
      },
      (caught: unknown) => {
        if (isCurrent) setError(chatErrorMessage(caught, "No se pudieron cargar los agentes."));
      },
    );
    return () => {
      isCurrent = false;
    };
  }, []);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setNotice(null);
    setError(null);
    try {
      await reassignConversation(tokenRef.current, conversationId, target || undefined);
      setNotice("Conversación reasignada.");
      onDone();
    } catch (caught) {
      setError(chatErrorMessage(caught, "No se pudo reasignar la conversación."));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form aria-label="Reasignar conversación" onSubmit={(event) => void handleSubmit(event)}>
      <label htmlFor={selectId}>Reasignar a</label>
      <select disabled={busy} id={selectId} onChange={(event) => setTarget(event.target.value)} value={target}>
        <option value="">Automático (menos conversaciones)</option>
        {agents.map((agent) => (
          <option key={agent.id} value={agent.id}>
            {agent.email}
          </option>
        ))}
      </select>
      <button className="review-button review-button--secondary" disabled={busy} type="submit">
        Reasignar
      </button>
      {notice ? (
        <p className="review-notice" role="status">
          {notice}
        </p>
      ) : null}
      {error ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          {error}
        </p>
      ) : null}
    </form>
  );
}
