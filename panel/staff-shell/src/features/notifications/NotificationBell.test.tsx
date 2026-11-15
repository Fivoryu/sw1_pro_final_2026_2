import { act, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  listNotifications,
  markAllNotificationsRead,
  markNotificationRead,
  type StaffNotification,
} from "../../application/staffNotificationsApi";
import { NOTIFICATIONS_POLL_MS, NotificationBell } from "./NotificationBell";

vi.mock("../../application/staffNotificationsApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../application/staffNotificationsApi")>();
  return {
    ...actual,
    listNotifications: vi.fn(),
    markNotificationRead: vi.fn(),
    markAllNotificationsRead: vi.fn(),
  };
});

function notice(overrides: Partial<StaffNotification> = {}): StaffNotification {
  return {
    id: "n1",
    kind: "chat_message",
    conversation_id: "c1",
    reservation_id: null,
    detail: null,
    created_at: "2026-11-01T10:00:00Z",
    read: false,
    ...overrides,
  };
}

beforeEach(() => {
  vi.mocked(listNotifications)
    .mockReset()
    .mockResolvedValue({
      unread: 2,
      items: [
        notice(),
        notice({ id: "n2", kind: "reservation_status", conversation_id: null, reservation_id: "r1" }),
      ],
    });
  vi.mocked(markNotificationRead).mockReset().mockResolvedValue(undefined);
  vi.mocked(markAllNotificationsRead).mockReset().mockResolvedValue(undefined);
});

afterEach(() => {
  vi.useRealTimers();
});

describe("NotificationBell", () => {
  it("shows the unread count and the notices", async () => {
    render(<NotificationBell accessToken="staff-access" onOpenChat={vi.fn()} />);

    expect(await screen.findByLabelText("2 sin leer")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: /Notificaciones/ }));

    expect(screen.getByText("Nuevo mensaje en una conversación")).toBeInTheDocument();
    expect(screen.getByText("Cambió el estado de una reserva")).toBeInTheDocument();
    expect(listNotifications).toHaveBeenCalledWith("staff-access", 30);
  });

  it("marks a chat notice as read and opens the chat", async () => {
    const onOpenChat = vi.fn();
    render(<NotificationBell accessToken="staff-access" onOpenChat={onOpenChat} />);
    await screen.findByLabelText("2 sin leer");
    await userEvent.click(screen.getByRole("button", { name: /Notificaciones/ }));

    await userEvent.click(screen.getByText("Nuevo mensaje en una conversación"));

    expect(markNotificationRead).toHaveBeenCalledWith("staff-access", "n1");
    expect(onOpenChat).toHaveBeenCalledWith("c1");
    expect(screen.getByLabelText("1 sin leer")).toBeInTheDocument();
  });

  it("only marks a reservation notice as read", async () => {
    const onOpenChat = vi.fn();
    render(<NotificationBell accessToken="staff-access" onOpenChat={onOpenChat} />);
    await screen.findByLabelText("2 sin leer");
    await userEvent.click(screen.getByRole("button", { name: /Notificaciones/ }));

    await userEvent.click(screen.getByText("Cambió el estado de una reserva"));

    expect(markNotificationRead).toHaveBeenCalledWith("staff-access", "n2");
    expect(onOpenChat).not.toHaveBeenCalled();
  });

  it("marks everything as read", async () => {
    render(<NotificationBell accessToken="staff-access" onOpenChat={vi.fn()} />);
    await screen.findByLabelText("2 sin leer");
    await userEvent.click(screen.getByRole("button", { name: /Notificaciones/ }));

    await userEvent.click(screen.getByRole("button", { name: "Marcar todo como leído" }));

    expect(markAllNotificationsRead).toHaveBeenCalledWith("staff-access");
    expect(screen.queryByLabelText(/sin leer/)).not.toBeInTheDocument();
  });

  it("polls every 30 seconds, survives a failed poll and clears the timer on unmount", async () => {
    vi.useFakeTimers();
    const { unmount } = render(
      <NotificationBell accessToken="staff-access" onOpenChat={vi.fn()} />,
    );
    await act(async () => {});
    expect(listNotifications).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(NOTIFICATIONS_POLL_MS);
    });
    expect(listNotifications).toHaveBeenCalledTimes(2);

    vi.mocked(listNotifications).mockRejectedValue(new Error("down"));
    await act(async () => {
      await vi.advanceTimersByTimeAsync(NOTIFICATIONS_POLL_MS);
    });
    expect(listNotifications).toHaveBeenCalledTimes(3);
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();

    // The service comes back: the next tick delivers again instead of staying dead.
    vi.mocked(listNotifications).mockResolvedValue({ unread: 4, items: [] });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(NOTIFICATIONS_POLL_MS);
    });
    expect(listNotifications).toHaveBeenCalledTimes(4);
    expect(screen.getByLabelText(/4/)).toBeInTheDocument();

    unmount();
    expect(vi.getTimerCount()).toBe(0);
  });

  it("clears the pending timer when unmounted while polling", async () => {
    vi.useFakeTimers();
    const { unmount } = render(
      <NotificationBell accessToken="staff-access" onOpenChat={vi.fn()} />,
    );
    await act(async () => {});
    expect(vi.getTimerCount()).toBe(1);

    unmount();
    expect(vi.getTimerCount()).toBe(0);
    await vi.advanceTimersByTimeAsync(NOTIFICATIONS_POLL_MS);
    expect(listNotifications).toHaveBeenCalledTimes(1);
  });
});
