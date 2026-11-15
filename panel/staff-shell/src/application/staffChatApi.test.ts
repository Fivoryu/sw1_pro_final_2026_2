import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  blockCustomer,
  listBlockedCustomers,
  listConversations,
  listMessages,
  listReports,
  reassignConversation,
  reportCustomer,
  sendMessage,
  StaffChatApiError,
  unblockCustomer,
} from "./staffChatApi";

const fetchMock = vi.fn<typeof fetch>();

function respond(body: unknown, status = 200) {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: vi.fn().mockResolvedValue(body),
  } as unknown as Response);
}

const bearer = { Authorization: "Bearer volatile-access" };
const jsonHeaders = { ...bearer, "Content-Type": "application/json" };

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("staff chat API", () => {
  it("lists conversations with the bearer token", async () => {
    respond({ conversations: [{ id: "c1" }] });

    const result = await listConversations("volatile-access");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/staff/chat/conversations", {
      method: "GET",
      headers: bearer,
    });
    expect(result).toEqual([{ id: "c1" }]);
  });

  it("polls messages after the last seen id and encodes the conversation id", async () => {
    const page = { messages: [], read_only: false };
    respond(page);

    const result = await listMessages("volatile-access", "c/1", 7);

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/staff/chat/conversations/c%2F1/messages?after=7",
      { method: "GET", headers: bearer },
    );
    expect(result).toEqual(page);
  });

  it("sends a message as JSON", async () => {
    respond({ id: 3, body: "Hola" }, 201);

    await sendMessage("volatile-access", "c1", "Hola");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/staff/chat/conversations/c1/messages", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify({ body: "Hola" }),
    });
  });

  it("maps 409 Conversation already taken to a recognizable error", async () => {
    respond({ detail: "Conversation already taken", code: "conflict" }, 409);

    const error = await sendMessage("volatile-access", "c1", "Hola").catch((e: unknown) => e);

    expect(error).toBeInstanceOf(StaffChatApiError);
    expect((error as StaffChatApiError).status).toBe(409);
    expect((error as StaffChatApiError).code).toBe("conflict");
    expect((error as StaffChatApiError).isConversationTaken).toBe(true);
  });

  it("does not treat a read-only 409 as taken", async () => {
    respond({ detail: "Conversation is read-only", code: "conflict" }, 409);

    const error = await sendMessage("volatile-access", "c1", "Hola").catch((e: unknown) => e);

    expect((error as StaffChatApiError).isConversationTaken).toBe(false);
    expect((error as StaffChatApiError).message).toBe("Conversation is read-only");
  });

  it("falls back to a generic message without a JSON error body", async () => {
    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: vi.fn().mockRejectedValue(new Error("no body")),
    } as unknown as Response);

    const error = await listConversations("volatile-access").catch((e: unknown) => e);

    expect((error as StaffChatApiError).status).toBe(500);
    expect((error as StaffChatApiError).message).toBe("Chat request failed.");
  });

  it("reassigns to a chosen agent or automatically with an empty body", async () => {
    respond(null, 200);
    respond(null, 200);

    await reassignConversation("volatile-access", "c1", "agent-2");
    await reassignConversation("volatile-access", "c1");

    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      "/api/v1/staff/chat/conversations/c1/reassign",
      { method: "POST", headers: jsonHeaders, body: JSON.stringify({ agent_id: "agent-2" }) },
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      "/api/v1/staff/chat/conversations/c1/reassign",
      { method: "POST", headers: jsonHeaders, body: "{}" },
    );
  });

  it("reports a customer with the reason as body", async () => {
    respond({ id: "r1" }, 201);

    await reportCustomer("volatile-access", "c1", "Insultos");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/staff/chat/conversations/c1/report", {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify({ body: "Insultos" }),
    });
  });

  it("lists reports and blocked customers", async () => {
    respond({ reports: [{ id: "r1" }] });
    respond({ blocked: [{ customer_id: "u1", created_at: "2026-11-01T00:00:00Z" }] });

    expect(await listReports("volatile-access")).toEqual([{ id: "r1" }]);
    expect(await listBlockedCustomers("volatile-access")).toEqual([
      { customer_id: "u1", created_at: "2026-11-01T00:00:00Z" },
    ]);
    expect(fetchMock).toHaveBeenNthCalledWith(1, "/api/v1/staff/chat/reports", {
      method: "GET",
      headers: bearer,
    });
    expect(fetchMock).toHaveBeenNthCalledWith(2, "/api/v1/staff/chat/blocks", {
      method: "GET",
      headers: bearer,
    });
  });

  it("blocks with PUT and unblocks with POST, tolerating empty 204 bodies", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 204,
      json: vi.fn().mockRejectedValue(new Error("empty")),
    } as unknown as Response);

    await blockCustomer("volatile-access", "u/1");
    await unblockCustomer("volatile-access", "u/1");

    expect(fetchMock).toHaveBeenNthCalledWith(1, "/api/v1/staff/chat/customers/u%2F1/block", {
      method: "PUT",
      headers: bearer,
    });
    expect(fetchMock).toHaveBeenNthCalledWith(2, "/api/v1/staff/chat/customers/u%2F1/unblock", {
      method: "POST",
      headers: bearer,
    });
  });
});
