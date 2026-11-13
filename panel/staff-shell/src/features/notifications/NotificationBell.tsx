import { useCallback, useEffect, useRef, useState } from "react";
import {
  listNotifications,
  markAllNotificationsRead,
  markNotificationRead,
  type StaffNotification,
  type StaffNotificationKind,
} from "../../application/staffNotificationsApi";
import { formatChatDate } from "../chat/ConversationView";
import "./NotificationBell.css";

export const NOTIFICATIONS_POLL_MS = 30_000;
const NOTIFICATIONS_LIMIT = 30;

const KIND_TEXT: Record<StaffNotificationKind, string> = {
  chat_message: "Nuevo mensaje en una conversación",
  chat_assigned: "Se te asignó una conversación",
  chat_needs_admin: "Una conversación requiere al administrador",
  chat_overdue: "Una conversación lleva tiempo sin respuesta",
  reservation_status: "Cambió el estado de una reserva",
};

export function notificationText(notification: StaffNotification): string {
  return KIND_TEXT[notification.kind];
}

interface NotificationBellProps {
  accessToken: string;
  /** Opens the chat area; receives the conversation the notice refers to. */
  onOpenChat: (conversationId: string) => void;
}

export function NotificationBell({ accessToken, onOpenChat }: NotificationBellProps) {
  const tokenRef = useRef(accessToken);
  tokenRef.current = accessToken;
  const [unread, setUnread] = useState(0);
  const [items, setItems] = useState<StaffNotification[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [failed, setFailed] = useState(false);

  const load = useCallback(async () => {
    const list = await listNotifications(tokenRef.current, NOTIFICATIONS_LIMIT);
    setUnread(list.unread);
    setItems(list.items);
    setFailed(false);
  }, []);

  useEffect(() => {
    let isCurrent = true;
    let timer: number | undefined;
    // A failed poll is skipped quietly and retried on the next tick; only the
    // first load reports a failure.
    function schedule() {
      timer = window.setTimeout(() => {
        load().then(
          () => {
            if (isCurrent) schedule();
          },
          () => {
            if (isCurrent) schedule();
          },
        );
      }, NOTIFICATIONS_POLL_MS);
    }
    load().then(
      () => {
        if (isCurrent) schedule();
      },
      () => {
        if (isCurrent) setFailed(true);
      },
    );
    return () => {
      isCurrent = false;
      if (timer !== undefined) window.clearTimeout(timer);
    };
  }, [load]);

  async function handleSelect(notification: StaffNotification) {
    if (!notification.read) {
      setItems((current) =>
        current.map((item) => (item.id === notification.id ? { ...item, read: true } : item)),
      );
      setUnread((count) => Math.max(0, count - 1));
      try {
        await markNotificationRead(tokenRef.current, notification.id);
      } catch {
        // The next poll restores the real state.
      }
    }
    if (notification.kind !== "reservation_status" && notification.conversation_id) {
      setIsOpen(false);
      onOpenChat(notification.conversation_id);
    }
  }

  async function handleReadAll() {
    setItems((current) => current.map((item) => ({ ...item, read: true })));
    setUnread(0);
    try {
      await markAllNotificationsRead(tokenRef.current);
    } catch {
      // The next poll restores the real state.
    }
  }

  return (
    <div className="notification-bell">
      <button
        aria-expanded={isOpen}
        className="notification-bell__button"
        onClick={() => setIsOpen((value) => !value)}
        type="button"
      >
        Notificaciones
        {unread > 0 ? (
          <span aria-label={`${unread} sin leer`} className="notification-bell__badge">
            {unread}
          </span>
        ) : null}
      </button>
      {isOpen ? (
        <section aria-label="Bandeja de notificaciones" className="notification-bell__panel">
          <button
            className="review-button review-button--secondary"
            disabled={unread === 0}
            onClick={() => void handleReadAll()}
            type="button"
          >
            Marcar todo como leído
          </button>
          {failed ? (
            <p className="review-queue__message review-queue__message--error" role="alert">
              No se pudieron cargar las notificaciones.
            </p>
          ) : null}
          {!failed && items.length === 0 ? (
            <p className="review-queue__message">No hay notificaciones.</p>
          ) : null}
          {items.length > 0 ? (
            <ul aria-label="Notificaciones" className="notification-bell__list">
              {items.map((notification) => (
                <li key={notification.id}>
                  <button
                    className={
                      notification.read
                        ? "notification-bell__item"
                        : "notification-bell__item notification-bell__item--unread"
                    }
                    onClick={() => void handleSelect(notification)}
                    type="button"
                  >
                    {notificationText(notification)}
                    <span className="notification-bell__date">
                      {formatChatDate(notification.created_at)}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
        </section>
      ) : null}
    </div>
  );
}
