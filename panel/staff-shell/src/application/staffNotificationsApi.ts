export type StaffNotificationKind =
  | "chat_message"
  | "chat_assigned"
  | "chat_needs_admin"
  | "chat_overdue"
  | "reservation_status";

export interface StaffNotification {
  id: string;
  kind: StaffNotificationKind;
  conversation_id: string | null;
  reservation_id: string | null;
  detail: string | null;
  created_at: string;
  read: boolean;
}

export interface StaffNotificationList {
  unread: number;
  items: StaffNotification[];
}

export class StaffNotificationsApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "StaffNotificationsApiError";
  }
}

const BASE = "/api/v1/staff/notifications";
const KINDS: readonly string[] = [
  "chat_message",
  "chat_assigned",
  "chat_needs_admin",
  "chat_overdue",
  "reservation_status",
];

async function request(url: string, init: RequestInit): Promise<Response> {
  const response = await fetch(url, init);
  if (!response.ok) {
    let message = "Notifications request failed.";
    try {
      const payload: unknown = await response.json();
      if (
        typeof payload === "object" &&
        payload !== null &&
        "detail" in payload &&
        typeof payload.detail === "string"
      ) {
        message = payload.detail;
      }
    } catch {
      // Keep the generic message when the server has no JSON error body.
    }
    throw new StaffNotificationsApiError(response.status, message);
  }
  return response;
}

function bearer(accessToken: string): Record<string, string> {
  return { Authorization: `Bearer ${accessToken}` };
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function isNotification(value: unknown): value is StaffNotification {
  if (typeof value !== "object" || value === null) return false;
  const item = value as Record<string, unknown>;
  return (
    typeof item.id === "string" &&
    typeof item.kind === "string" &&
    KINDS.includes(item.kind) &&
    isNullableString(item.conversation_id) &&
    isNullableString(item.reservation_id) &&
    isNullableString(item.detail) &&
    typeof item.created_at === "string" &&
    typeof item.read === "boolean"
  );
}

export async function listNotifications(
  accessToken: string,
  limit?: number,
): Promise<StaffNotificationList> {
  const query = limit === undefined ? "" : `?${new URLSearchParams({ limit: String(limit) })}`;
  const response = await request(`${BASE}${query}`, {
    method: "GET",
    headers: bearer(accessToken),
  });
  const payload: unknown = await response.json();
  if (
    typeof payload !== "object" ||
    payload === null ||
    typeof (payload as { unread?: unknown }).unread !== "number" ||
    !Array.isArray((payload as { items?: unknown }).items) ||
    !(payload as { items: unknown[] }).items.every(isNotification)
  ) {
    throw new StaffNotificationsApiError(response.status, "Unexpected notifications response.");
  }
  return payload as StaffNotificationList;
}

export async function markNotificationRead(
  accessToken: string,
  notificationId: string,
): Promise<void> {
  await request(`${BASE}/${encodeURIComponent(notificationId)}/read`, {
    method: "POST",
    headers: bearer(accessToken),
  });
}

export async function markAllNotificationsRead(accessToken: string): Promise<void> {
  await request(`${BASE}/read-all`, { method: "POST", headers: bearer(accessToken) });
}
