import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  completeStaffSession,
  decodeAccessTokenExpiry,
  endStaffSession,
  renewStaffSession,
  restoreStaffSession,
  restoreStaffSessionOutcome,
  STAFF_CSRF_STORAGE_KEY,
  type StaffSessionStorage,
} from "./staffSession";
import {
  getStaffMe,
  logoutStaffSession,
  refreshStaffSession,
  StaffAuthApiError,
  type StaffUser,
} from "./staffAuthApi";

vi.mock("./staffAuthApi", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./staffAuthApi")>();
  return {
    ...actual,
    getStaffMe: vi.fn(),
    logoutStaffSession: vi.fn(),
    refreshStaffSession: vi.fn(),
  };
});

function createStorage(initial: Record<string, string> = {}) {
  const values = new Map(Object.entries(initial));
  const events: string[] = [];
  const storage: StaffSessionStorage = {
    getItem: vi.fn((key) => values.get(key) ?? null),
    setItem: vi.fn((key, value) => values.set(key, value)),
    removeItem: vi.fn((key) => {
      events.push(`remove:${key}`);
      values.delete(key);
    }),
  };

  return { storage, values, events };
}

function staffUser(role: string): StaffUser {
  return {
    id: "server-user",
    email: "server@example.test",
    role,
    tenant_id: role === "platform_admin" ? null : "agency-1",
  };
}

function fakeAccessToken(expSeconds: number): string {
  return `header.${btoa(JSON.stringify({ exp: expSeconds }))}.signature`;
}

beforeEach(() => {
  vi.mocked(getStaffMe).mockReset();
  vi.mocked(logoutStaffSession).mockReset();
  vi.mocked(refreshStaffSession).mockReset();
});

describe("staff session application lifecycle", () => {
  it("falls back to login without attempting refresh when CSRF is absent", async () => {
    const { storage } = createStorage();

    await expect(restoreStaffSession(storage)).resolves.toBeNull();

    expect(refreshStaffSession).not.toHaveBeenCalled();
    expect(getStaffMe).not.toHaveBeenCalled();
  });

  it("rotates the CSRF token before resolving identity from the server", async () => {
    const { storage } = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "old-csrf" });
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "rotated-access",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("agency_admin") });

    const session = await restoreStaffSession(storage);

    expect(refreshStaffSession).toHaveBeenCalledWith("old-csrf");
    expect(storage.setItem).toHaveBeenCalledWith(STAFF_CSRF_STORAGE_KEY, "rotated-csrf");
    expect(getStaffMe).toHaveBeenCalledWith("rotated-access");
    expect(session).toEqual({
      accessToken: "rotated-access",
      csrfToken: "rotated-csrf",
      accessExpiresAt: null,
      user: staffUser("agency_admin"),
    });
    expect(vi.mocked(refreshStaffSession).mock.invocationCallOrder[0]).toBeLessThan(
      vi.mocked(getStaffMe).mock.invocationCallOrder[0],
    );
  });

  it("shares one restoration request across concurrent calls using the same storage", async () => {
    const { storage } = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "old-csrf" });
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "rotated-access",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("agency_admin") });

    const sessions = await Promise.all([
      restoreStaffSession(storage),
      restoreStaffSession(storage),
    ]);

    expect(refreshStaffSession).toHaveBeenCalledTimes(1);
    expect(refreshStaffSession).toHaveBeenCalledWith("old-csrf");
    expect(getStaffMe).toHaveBeenCalledTimes(1);
    expect(getStaffMe).toHaveBeenCalledWith("rotated-access");
    expect(sessions[0]).toEqual({
      accessToken: "rotated-access",
      csrfToken: "rotated-csrf",
      accessExpiresAt: null,
      user: staffUser("agency_admin"),
    });
    expect(sessions[1]).toEqual(sessions[0]);
  });

  it.each(["refresh", "me"] as const)("clears CSRF when %s rejects restoration", async (failure) => {
    const { storage, values } = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "stored-csrf" });
    if (failure === "refresh") {
      vi.mocked(refreshStaffSession).mockRejectedValue(new Error("refresh rejected"));
    } else {
      vi.mocked(refreshStaffSession).mockResolvedValue({
        access_token: "rotated-access",
        csrf_token: "rotated-csrf",
      });
      vi.mocked(getStaffMe).mockRejectedValue(new Error("identity rejected"));
    }

    await expect(restoreStaffSession(storage)).resolves.toBeNull();

    expect(values.has(STAFF_CSRF_STORAGE_KEY)).toBe(false);
    expect(storage.removeItem).toHaveBeenCalledWith(STAFF_CSRF_STORAGE_KEY);
  });

  it("uses /me as the login identity and never stores either access token", async () => {
    const { storage, values } = createStorage();
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("agent") });

    const session = await completeStaffSession(
      {
        access_token: "volatile-access",
        csrf_token: "login-csrf",
        user: staffUser("platform_admin"),
      },
      storage,
    );

    expect(getStaffMe).toHaveBeenCalledWith("volatile-access");
    expect(session.user).toEqual(staffUser("agent"));
    expect([...values.entries()]).toEqual([[STAFF_CSRF_STORAGE_KEY, "login-csrf"]]);
  });

  it("clears the login CSRF token when identity resolution fails", async () => {
    const { storage, values } = createStorage();
    vi.mocked(getStaffMe).mockRejectedValue(new Error("identity rejected"));

    await expect(
      completeStaffSession(
        { access_token: "volatile-access", csrf_token: "login-csrf", user: staffUser("agent") },
        storage,
      ),
    ).rejects.toThrow("identity rejected");

    expect(values.has(STAFF_CSRF_STORAGE_KEY)).toBe(false);
  });

  it("rejects unknown roles and removes their stored CSRF token", async () => {
    const { storage, values } = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "stored-csrf" });
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "rotated-access",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("superuser") });

    await expect(restoreStaffSession(storage)).resolves.toBeNull();

    expect(values.has(STAFF_CSRF_STORAGE_KEY)).toBe(false);
  });

  it("revokes the session before clearing its tab-scoped CSRF token", async () => {
    const { storage, events } = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "rotated-csrf" });
    vi.mocked(logoutStaffSession).mockImplementation(async () => {
      events.push("logout");
    });
    const session = {
      accessToken: "volatile-access",
      csrfToken: "rotated-csrf",
      accessExpiresAt: null,
      user: { ...staffUser("platform_admin"), role: "platform_admin" as const },
    };

    await endStaffSession(session, storage);

    expect(logoutStaffSession).toHaveBeenCalledWith("rotated-csrf");
    expect(events).toEqual([`logout`, `remove:${STAFF_CSRF_STORAGE_KEY}`]);
    expect(storage.removeItem).toHaveBeenCalledWith(STAFF_CSRF_STORAGE_KEY);
  });
});

describe("staff session expiry and failure classification", () => {
  it("records the access-token expiry decoded from the token itself", async () => {
    const { storage } = createStorage();
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("agent") });

    const session = await completeStaffSession(
      {
        access_token: fakeAccessToken(1_800_000_000),
        csrf_token: "login-csrf",
        user: staffUser("agent"),
      },
      storage,
    );

    expect(session.accessExpiresAt).toBe(1_800_000_000_000);
  });

  it("reports an unavailable session when restoration cannot reach the API", async () => {
    const { storage, values } = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "stored-csrf" });
    vi.mocked(refreshStaffSession).mockRejectedValue(new TypeError("Failed to fetch"));

    await expect(restoreStaffSessionOutcome(storage)).resolves.toEqual({
      kind: "unavailable",
    });

    expect(values.get(STAFF_CSRF_STORAGE_KEY)).toBe("stored-csrf");
  });

  it("reports a signed-out session when the refresh token is rejected", async () => {
    const { storage, values } = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "stored-csrf" });
    vi.mocked(refreshStaffSession).mockRejectedValue(
      new StaffAuthApiError(401, "Authentication failed."),
    );

    await expect(restoreStaffSessionOutcome(storage)).resolves.toEqual({
      kind: "signed-out",
    });

    expect(values.has(STAFF_CSRF_STORAGE_KEY)).toBe(false);
  });

  it("reports access denied when the server forbids identity resolution", async () => {
    const { storage, values } = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "stored-csrf" });
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "rotated-access",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockRejectedValue(
      new StaffAuthApiError(403, "Staff tenant access is required"),
    );

    await expect(restoreStaffSessionOutcome(storage)).resolves.toEqual({
      kind: "denied",
    });

    expect(values.has(STAFF_CSRF_STORAGE_KEY)).toBe(false);
  });

  it("reports access denied for an unsupported role instead of a network failure", async () => {
    const { storage } = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "stored-csrf" });
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: "rotated-access",
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("superuser") });

    await expect(restoreStaffSessionOutcome(storage)).resolves.toEqual({
      kind: "denied",
    });
  });

  it("returns the resolved session on a successful restoration", async () => {
    const { storage } = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "stored-csrf" });
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: fakeAccessToken(1_800_000_000),
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("agency_admin") });

    const outcome = await restoreStaffSessionOutcome(storage);

    expect(outcome).toEqual({
      kind: "session",
      session: {
        accessToken: fakeAccessToken(1_800_000_000),
        csrfToken: "rotated-csrf",
        accessExpiresAt: 1_800_000_000_000,
        user: staffUser("agency_admin"),
      },
    });
  });

  it("renews an active session and rotates its CSRF token", async () => {
    const { storage, values } = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "old-csrf" });
    vi.mocked(refreshStaffSession).mockResolvedValue({
      access_token: fakeAccessToken(1_800_000_900),
      csrf_token: "rotated-csrf",
    });
    vi.mocked(getStaffMe).mockResolvedValue({ user: staffUser("agent") });
    const session = {
      accessToken: "expiring-access",
      csrfToken: "old-csrf",
      accessExpiresAt: 1_800_000_000,
      user: { ...staffUser("agent"), role: "agent" as const },
    };

    const renewed = await renewStaffSession(session, storage);

    expect(refreshStaffSession).toHaveBeenCalledWith("old-csrf");
    expect(values.get(STAFF_CSRF_STORAGE_KEY)).toBe("rotated-csrf");
    expect(renewed?.accessExpiresAt).toBe(1_800_000_900_000);
  });

  it("keeps the CSRF token when renewal fails on the network but clears it on rejection", async () => {
    const offline = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "old-csrf" });
    vi.mocked(refreshStaffSession).mockRejectedValueOnce(new TypeError("Failed to fetch"));
    const session = {
      accessToken: "expiring-access",
      csrfToken: "old-csrf",
      accessExpiresAt: 1_800_000_000,
      user: { ...staffUser("agent"), role: "agent" as const },
    };

    await expect(renewStaffSession(session, offline.storage)).resolves.toBeNull();
    expect(offline.values.get(STAFF_CSRF_STORAGE_KEY)).toBe("old-csrf");

    const rejected = createStorage({ [STAFF_CSRF_STORAGE_KEY]: "old-csrf" });
    vi.mocked(refreshStaffSession).mockRejectedValueOnce(
      new StaffAuthApiError(401, "Authentication failed."),
    );

    await expect(renewStaffSession(session, rejected.storage)).resolves.toBeNull();
    expect(rejected.values.has(STAFF_CSRF_STORAGE_KEY)).toBe(false);
  });

  it.each(["not-a-jwt", "header.%%%invalid%%%.signature"]) (
    "treats an undecodable access token (%s) as an unknown expiry",
    (accessToken) => {
      expect(decodeAccessTokenExpiry(accessToken)).toBeNull();
    },
  );

  it("ignores a payload without a numeric exp claim", () => {
    const token = `header.${btoa(JSON.stringify({ sid: "session" }))}.signature`;

    expect(decodeAccessTokenExpiry(token)).toBeNull();
  });
});
