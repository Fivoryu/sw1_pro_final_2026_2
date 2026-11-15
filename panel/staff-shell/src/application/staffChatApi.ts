export interface StaffConversation {
  id: string;
  listing_id: string;
  customer_email: string;
  status: "unclaimed" | "claimed";
  mine: boolean;
  read_only: boolean;
  needs_admin: boolean;
  overdue: boolean;
  created_at: string;
  last_message_at: string | null;
  /** Only present for the agency admin. */
  agent_id?: string | null;
  agent_email?: string | null;
  /** Present only if the API exposes it; blocking a customer needs it. */
  customer_id?: string | null;
}

export interface StaffMessage {
  id: number;
  sender: "customer" | "agent" | "admin";
  mine: boolean;
  body: string;
  created_at: string;
  /** Only present for the agency admin. */
  author_id?: string | null;
  author_email?: string | null;
}

export interface StaffMessagePage {
  messages: StaffMessage[];
  read_only: boolean;
}

export interface ChatReport {
  id: string;
  conversation_id: string;
  listing_id: string;
  agency_id: string;
  reporter_role: "customer" | "agent" | "admin";
  reason: string;
  created_at: string;
  agent_ids: string[];
}

export interface BlockedCustomer {
  customer_id: string;
  created_at: string;
}

export const CONVERSATION_TAKEN_MESSAGE = "Conversation already taken";

export class StaffChatApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code?: string,
  ) {
    super(message);
    this.name = "StaffChatApiError";
  }

  /** The first-reply claim was won by another agent. */
  get isConversationTaken(): boolean {
    return this.status === 409 && this.message === CONVERSATION_TAKEN_MESSAGE;
  }
}

const BASE = "/api/v1/staff/chat";

async function request(url: string, init: RequestInit): Promise<Response> {
  const response = await fetch(url, init);
  if (!response.ok) {
    let message = "Chat request failed.";
    let code: string | undefined;
    try {
      const payload: unknown = await response.json();
      if (typeof payload === "object" && payload !== null) {
        if ("detail" in payload && typeof payload.detail === "string") {
          message = payload.detail;
        }
        if ("code" in payload && typeof payload.code === "string") {
          code = payload.code;
        }
      }
    } catch {
      // Keep the generic message when the server has no JSON error body.
    }
    throw new StaffChatApiError(response.status, message, code);
  }
  return response;
}

async function requestJson<T>(url: string, init: RequestInit): Promise<T> {
  return (await (await request(url, init)).json()) as T;
}

function bearer(accessToken: string): Record<string, string> {
  return { Authorization: `Bearer ${accessToken}` };
}

function jsonInit(accessToken: string, method: string, body: unknown): RequestInit {
  return {
    method,
    headers: { ...bearer(accessToken), "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

function conversationPath(conversationId: string): string {
  return `${BASE}/conversations/${encodeURIComponent(conversationId)}`;
}

export async function listConversations(accessToken: string): Promise<StaffConversation[]> {
  const payload = await requestJson<{ conversations: StaffConversation[] }>(
    `${BASE}/conversations`,
    { method: "GET", headers: bearer(accessToken) },
  );
  return payload.conversations;
}

export function listMessages(
  accessToken: string,
  conversationId: string,
  after: number,
): Promise<StaffMessagePage> {
  const query = new URLSearchParams({ after: String(after) });
  return requestJson<StaffMessagePage>(
    `${conversationPath(conversationId)}/messages?${query.toString()}`,
    { method: "GET", headers: bearer(accessToken) },
  );
}

export function sendMessage(
  accessToken: string,
  conversationId: string,
  body: string,
): Promise<StaffMessage> {
  return requestJson<StaffMessage>(
    `${conversationPath(conversationId)}/messages`,
    jsonInit(accessToken, "POST", { body }),
  );
}

/** Reassigns to `agentId`, or lets the server pick the least-loaded agent when omitted. */
export async function reassignConversation(
  accessToken: string,
  conversationId: string,
  agentId?: string,
): Promise<void> {
  await request(
    `${conversationPath(conversationId)}/reassign`,
    jsonInit(accessToken, "POST", agentId === undefined ? {} : { agent_id: agentId }),
  );
}

export async function reportCustomer(
  accessToken: string,
  conversationId: string,
  reason: string,
): Promise<void> {
  await request(
    `${conversationPath(conversationId)}/report`,
    jsonInit(accessToken, "POST", { body: reason }),
  );
}

export async function listReports(accessToken: string): Promise<ChatReport[]> {
  const payload = await requestJson<{ reports: ChatReport[] }>(`${BASE}/reports`, {
    method: "GET",
    headers: bearer(accessToken),
  });
  return payload.reports;
}

export async function listBlockedCustomers(accessToken: string): Promise<BlockedCustomer[]> {
  const payload = await requestJson<{ blocked: BlockedCustomer[] }>(`${BASE}/blocks`, {
    method: "GET",
    headers: bearer(accessToken),
  });
  return payload.blocked;
}

export async function blockCustomer(accessToken: string, customerId: string): Promise<void> {
  await request(`${BASE}/customers/${encodeURIComponent(customerId)}/block`, {
    method: "PUT",
    headers: bearer(accessToken),
  });
}

export async function unblockCustomer(accessToken: string, customerId: string): Promise<void> {
  await request(`${BASE}/customers/${encodeURIComponent(customerId)}/unblock`, {
    method: "POST",
    headers: bearer(accessToken),
  });
}
