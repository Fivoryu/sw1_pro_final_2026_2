import { useCallback, useEffect, useRef, useState } from "react";
import {
  listConversations,
  type StaffConversation,
} from "../../application/staffChatApi";
import { ChatReports } from "./ChatReports";
import { chatErrorMessage, ConversationView, formatChatDate } from "./ConversationView";

export const INBOX_POLL_MS = 15_000;

const TAKEN_NOTICE = "Otro agente ya tomó esta conversación. La bandeja se actualizó.";

interface ChatInboxProps {
  accessToken: string;
  isAgencyAdmin: boolean;
  /** Asks the inbox to open a conversation, for example from a notification.
   * Each request is a new object, so asking again for the same conversation
   * reopens it after the user closed it. */
  openRequest?: { conversationId: string } | null;
}

type InboxState =
  | { kind: "loading" }
  | { kind: "ready"; conversations: StaffConversation[] }
  | { kind: "error"; message: string };

function statusLabel(conversation: StaffConversation): string {
  if (conversation.status === "unclaimed") return "Sin atender";
  return conversation.mine ? "Atendida por ti" : "Atendida";
}

export function ChatInbox({ accessToken, isAgencyAdmin, openRequest = null }: ChatInboxProps) {
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;
  const [inbox, setInbox] = useState<InboxState>({ kind: "loading" });
  const [selectedId, setSelectedId] = useState<string | null>(openRequest?.conversationId ?? null);
  const [notice, setNotice] = useState<string | null>(null);
  const [reload, setReload] = useState(0);

  const refresh = useCallback(() => setReload((value) => value + 1), []);

  useEffect(() => {
    if (openRequest) setSelectedId(openRequest.conversationId);
  }, [openRequest]);

  useEffect(() => {
    let isCurrent = true;
    listConversations(tokenRef.current).then(
      (conversations) => {
        if (isCurrent) setInbox({ kind: "ready", conversations });
      },
      (error: unknown) => {
        if (isCurrent) {
          setInbox({ kind: "error", message: chatErrorMessage(error, "No se pudo cargar la bandeja.") });
        }
      },
    );
    return () => {
      isCurrent = false;
    };
  }, [reload]);

  useEffect(() => {
    const timer = window.setInterval(refresh, INBOX_POLL_MS);
    return () => window.clearInterval(timer);
  }, [refresh]);

  const selected =
    inbox.kind === "ready" && selectedId
      ? inbox.conversations.find((conversation) => conversation.id === selectedId)
      : undefined;

  function handleTaken() {
    setSelectedId(null);
    setNotice(TAKEN_NOTICE);
    refresh();
  }

  return (
    <section aria-labelledby="chat-inbox-heading" className="chat-inbox">
      <div className="protected-staff-review-queue__heading">
        <span className="protected-staff-review-queue__eyebrow">CONTACTO CON CLIENTES</span>
        <h2 id="chat-inbox-heading">Bandeja de chat</h2>
      </div>

      {notice ? (
        <p className="review-queue__message review-queue__message--error" role="alert">
          {notice}
        </p>
      ) : null}

      {selected ? (
        <ConversationView
          accessToken={accessToken}
          conversation={selected}
          isAgencyAdmin={isAgencyAdmin}
          onBack={() => setSelectedId(null)}
          onChanged={refresh}
          onTaken={handleTaken}
        />
      ) : (
        <>
          {inbox.kind === "loading" ? (
            <p aria-busy="true" className="review-queue__message">
              Cargando conversaciones…
            </p>
          ) : null}
          {inbox.kind === "error" ? (
            <div className="review-queue__message review-queue__message--error" role="alert">
              <p>{inbox.message}</p>
              <button className="review-button review-button--secondary" onClick={refresh} type="button">
                Reintentar
              </button>
            </div>
          ) : null}
          {inbox.kind === "ready" && inbox.conversations.length === 0 ? (
            <p className="review-queue__message">No hay conversaciones.</p>
          ) : null}
          {inbox.kind === "ready" && inbox.conversations.length > 0 ? (
            <ul aria-label="Conversaciones" className="chat-list">
              {inbox.conversations.map((conversation) => (
                <li key={conversation.id}>
                  <button
                    className="chat-list__item"
                    onClick={() => {
                      setNotice(null);
                      setSelectedId(conversation.id);
                    }}
                    type="button"
                  >
                    <span className="chat-list__customer">{conversation.customer_email}</span>
                    <span className="chat-list__meta">
                      Inmueble {conversation.listing_id}
                      {isAgencyAdmin && conversation.agent_email
                        ? ` · Agente ${conversation.agent_email}`
                        : ""}
                      {conversation.last_message_at
                        ? ` · ${formatChatDate(conversation.last_message_at)}`
                        : ""}
                    </span>
                    <span className="chat-list__badges">
                      <span className="review-list__badge">{statusLabel(conversation)}</span>
                      {conversation.read_only ? (
                        <span className="review-list__badge">Solo lectura</span>
                      ) : null}
                      {conversation.needs_admin ? (
                        <span className="review-list__badge chat-list__badge--alert">
                          Requiere administrador
                        </span>
                      ) : null}
                      {conversation.overdue ? (
                        <span className="review-list__badge chat-list__badge--alert">
                          Sin respuesta
                        </span>
                      ) : null}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
          {isAgencyAdmin ? <ChatReports accessToken={accessToken} showBlocks /> : null}
        </>
      )}
    </section>
  );
}
