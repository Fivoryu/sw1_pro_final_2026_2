export interface StaffCredentials {
  email: string;
  password: string;
}

export interface LoginChallenge {
  challenge_token: string;
}

export interface StaffUser {
  id: string;
  email: string;
  role: string;
  tenant_id: string | null;
}

export interface InvitationAcceptance {
  token: string;
  password: string;
  password_confirmation: string;
}

export interface InvitationEnrollment {
  enrollment_token: string;
  totp_secret: string;
  provisioning_uri: string;
}

export interface EnrollmentVerification {
  enrollment_token: string;
  code: string;
}

export interface EnrollmentCompletion {
  account: StaffUser;
  recovery_codes: string[];
}

export type StaffLoginVerification =
  | { challenge_token: string; code: string; recovery_code?: never }
  | { challenge_token: string; recovery_code: string; code?: never };

export interface LoginCompletion {
  access_token: string;
  csrf_token: string;
  user: StaffUser;
}

export interface StaffSessionTokens {
  access_token: string;
  csrf_token: string;
}

export interface StaffMeResponse {
  user: StaffUser;
}

export class StaffAuthApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "StaffAuthApiError";
  }
}

const AUTH_API_BASE = "/api/v1/auth";

async function request(path: string, init: RequestInit): Promise<Response> {
  const response = await fetch(`${AUTH_API_BASE}${path}`, {
    ...init,
    credentials: "include",
  });

  if (!response.ok) {
    let message = "Authentication request failed.";

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
      // Retain the generic message when the server has no JSON error body.
    }

    throw new StaffAuthApiError(response.status, message);
  }

  return response;
}

async function requestJson<T>(path: string, init: RequestInit): Promise<T> {
  const response = await request(path, init);
  return (await response.json()) as T;
}

function jsonPost(body: unknown): RequestInit {
  return {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

export function startStaffLogin(
  credentials: StaffCredentials,
): Promise<LoginChallenge> {
  return requestJson<LoginChallenge>("/login", jsonPost(credentials));
}

export function acceptStaffInvitation(
  acceptance: InvitationAcceptance,
): Promise<InvitationEnrollment> {
  return requestJson<InvitationEnrollment>(
    "/invitations/accept",
    jsonPost(acceptance),
  );
}

export function verifyStaffEnrollment(
  verification: EnrollmentVerification,
): Promise<EnrollmentCompletion> {
  return requestJson<EnrollmentCompletion>(
    "/totp/enroll/verify",
    jsonPost(verification),
  );
}

export function completeStaffLogin(
  verification: StaffLoginVerification,
): Promise<LoginCompletion> {
  return requestJson<LoginCompletion>("/login/totp", jsonPost(verification));
}

export function refreshStaffSession(
  csrfToken: string,
): Promise<StaffSessionTokens> {
  return requestJson<StaffSessionTokens>("/refresh", {
    method: "POST",
    headers: { "X-CSRF-Token": csrfToken },
  });
}

export function getStaffMe(accessToken: string): Promise<StaffMeResponse> {
  return requestJson<StaffMeResponse>("/me", {
    method: "GET",
    headers: { Authorization: `Bearer ${accessToken}` },
  });
}

export async function logoutStaffSession(csrfToken: string): Promise<void> {
  await request("/logout", {
    method: "POST",
    headers: { "X-CSRF-Token": csrfToken },
  });
}
