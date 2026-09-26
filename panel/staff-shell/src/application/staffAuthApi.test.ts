import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  acceptStaffInvitation,
  completeStaffLogin,
  getStaffMe,
  logoutStaffSession,
  refreshStaffSession,
  startStaffLogin,
  verifyStaffEnrollment,
} from "./staffAuthApi";

const fetchMock = vi.fn<typeof fetch>();

function respondWithJson(body: unknown, status = 200) {
  fetchMock.mockResolvedValueOnce({
    ok: status >= 200 && status < 300,
    status,
    json: vi.fn().mockResolvedValue(body),
  } as unknown as Response);
}

function expectedJsonPost(body: unknown) {
  return {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

const staffUser = {
  id: "user-1",
  email: "owner@example.test",
  role: "platform_admin",
  tenant_id: null,
};

beforeEach(() => {
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("staff authentication API", () => {
  it("posts credentials to the staff login endpoint with cookie support", async () => {
    const credentials = {
      email: "owner@example.test",
      password: "not-a-real-secret",
    };
    respondWithJson({ challenge_token: "server-login-challenge" });

    const result = await startStaffLogin(credentials);

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/auth/login",
      expectedJsonPost(credentials),
    );
    expect(result).toEqual({ challenge_token: "server-login-challenge" });
  });

  it("surfaces a safe authentication detail for an HTTP rejection", async () => {
    respondWithJson({ detail: "Invalid email or password" }, 401);

    await expect(
      startStaffLogin({ email: "owner@example.test", password: "wrong" }),
    ).rejects.toThrow("Invalid email or password");
  });

  it("accepts an invitation without exposing a public-registration endpoint", async () => {
    const acceptance = {
      token: "one-time-invitation-token",
      password: "not-a-real-secret",
      password_confirmation: "not-a-real-secret",
    };
    const enrollment = {
      enrollment_token: "enrollment-challenge",
      totp_secret: "BASE32SECRET",
      provisioning_uri: "otpauth://totp/RoomForge:owner%40example.test",
    };
    respondWithJson(enrollment);

    const result = await acceptStaffInvitation(acceptance);

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/auth/invitations/accept",
      expectedJsonPost(acceptance),
    );
    expect(result).toEqual(enrollment);
  });

  it("verifies TOTP enrollment and returns one-time recovery codes", async () => {
    const verification = { enrollment_token: "enrollment-challenge", code: "123456" };
    const resultBody = { account: staffUser, recovery_codes: ["RF-AAAA-BBBB"] };
    respondWithJson(resultBody);

    const result = await verifyStaffEnrollment(verification);

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/auth/totp/enroll/verify",
      expectedJsonPost(verification),
    );
    expect(result).toEqual(resultBody);
  });

  it("completes MFA with a TOTP proof and includes the refresh cookie", async () => {
    const verification = { challenge_token: "login-challenge", code: "123456" };
    const completion = {
      access_token: "short-lived-access-token",
      csrf_token: "csrf-token",
      user: staffUser,
    };
    respondWithJson(completion);

    const result = await completeStaffLogin(verification);

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/auth/login/totp",
      expectedJsonPost(verification),
    );
    expect(result).toEqual(completion);
  });

  it("completes MFA with a recovery code as the only proof", async () => {
    const verification = {
      challenge_token: "login-challenge",
      recovery_code: "RF-AAAA-BBBB",
    };
    respondWithJson({ access_token: "access", csrf_token: "csrf", user: staffUser });

    await completeStaffLogin(verification);

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/v1/auth/login/totp",
      expectedJsonPost(verification),
    );
  });

  it("rotates the session with the CSRF header and browser-held cookie", async () => {
    const tokens = { access_token: "rotated-access", csrf_token: "rotated-csrf" };
    respondWithJson(tokens);

    const result = await refreshStaffSession("current-csrf");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/auth/refresh", {
      method: "POST",
      credentials: "include",
      headers: { "X-CSRF-Token": "current-csrf" },
    });
    expect(result).toEqual(tokens);
  });

  it("resolves the current staff identity with its bearer token", async () => {
    const responseBody = { user: staffUser };
    respondWithJson(responseBody);

    const result = await getStaffMe("short-lived-access-token");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/auth/me", {
      method: "GET",
      credentials: "include",
      headers: { Authorization: "Bearer short-lived-access-token" },
    });
    expect(result).toEqual(responseBody);
  });

  it("logs out using the CSRF header and lets the server clear its cookie", async () => {
    fetchMock.mockResolvedValueOnce({ ok: true, status: 204 } as Response);

    await logoutStaffSession("current-csrf");

    expect(fetchMock).toHaveBeenCalledWith("/api/v1/auth/logout", {
      method: "POST",
      credentials: "include",
      headers: { "X-CSRF-Token": "current-csrf" },
    });
  });
});
