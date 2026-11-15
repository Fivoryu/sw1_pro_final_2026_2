import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  listNotifications,
  markAllNotificationsRead,
  markNotificationRead,
  StaffNotificationsApiError,
} from "./staffNotificationsApi";

const fetchMock = vi.fn<typeof fetch>();

function respond(body: unknown, status = 200) {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: vi.fn().mockResolvedValue(body),
  } as unknown as Response);
}

const bearer = { Authorization: "Bearer volatile-access" };
const item = {
  id: "n1",
  kind: "chat_message",
  conversation_id: "c1",
  reservation_id: null,
  detail: null,
  created_at: "2026-11-01T10:00:00Z",
  read: false,
};

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("staff notifications API", () => {
  it("lists notifications with the bearer token and limit", async () => {
    respond({ unread: 1, items: [item] });

    const result = await listNotifications("volatile-access", 20);

    expect(result).toEqual({ unread: 1, items: [item] });
    expect(fetchMock).toHaveBeenCalledWith("/api/v1/staff/notifications?limit=20", {
      method: "GET",
      headers: bearer,
    });
  });

  it("rejects a malformed response", async () => {
    respond({ unread: "1", items: [item] });
    await expect(listNotifications("volatile-access")).rejects.toBeInstanceOf(
      StaffNotificationsApiError,
    );
    respond({ unread: 0, items: [{ ...item, kind: "other" }] });
    await expect(listNotifications("volatile-access")).rejects.toBeInstanceOf(
      StaffNotificationsApiError,
    );
  });

  it("surfaces a 403 for non agency staff", async () => {
    respond({ detail: "Forbidden" }, 403);
    await expect(listNotifications("volatile-access")).rejects.toMatchObject({
      status: 403,
      message: "Forbidden",
    });
  });

  it("marks one notification as read", async () => {
    respond(null, 204);
    await markNotificationRead("volatile-access", "n 1");
    expect(fetchMock).toHaveBeenCalledWith("/api/v1/staff/notifications/n%201/read", {
      method: "POST",
      headers: bearer,
    });
  });

  it("marks all notifications as read and reports a 404", async () => {
    respond(null, 204);
    await markAllNotificationsRead("volatile-access");
    expect(fetchMock).toHaveBeenCalledWith("/api/v1/staff/notifications/read-all", {
      method: "POST",
      headers: bearer,
    });
    respond({}, 404);
    await expect(markNotificationRead("volatile-access", "x")).rejects.toMatchObject({
      status: 404,
    });
  });
});
