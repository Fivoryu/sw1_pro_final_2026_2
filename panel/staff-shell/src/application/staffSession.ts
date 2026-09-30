import {
  getStaffMe,
  logoutStaffSession,
  refreshStaffSession,
  StaffAuthApiError,
  type LoginCompletion,
  type StaffSessionTokens,
  type StaffUser,
} from "./staffAuthApi";

export const STAFF_CSRF_STORAGE_KEY = "roomforge.staff.csrf";

export type StaffRole = "platform_admin" | "agency_admin" | "agent";

export interface StaffSessionStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export interface StaffSession {
  accessToken: string;
  csrfToken: string;
  /** Milliseconds since the epoch, decoded from the access token; null when unreadable. */
  accessExpiresAt: number | null;
  user: StaffUser & { role: StaffRole };
}

/** Result of trying to restore a stored staff session. */
export type StaffRestoreOutcome =
  | { kind: "session"; session: StaffSession }
  | { kind: "signed-out" }
  | { kind: "unavailable" }
  | { kind: "denied" };

/** Raised when the authenticated staff account holds a role the panel cannot use. */
export class UnsupportedStaffRoleError extends Error {
  constructor() {
    super("The staff account has an unsupported role.");
    this.name = "UnsupportedStaffRoleError";
  }
}

/**
 * Reads the `exp` claim of an access token so the panel can renew proactively.
 * Returns null when the token is not a readable JWT or has no numeric expiry.
 */
export function decodeAccessTokenExpiry(accessToken: string): number | null {
  const segments = accessToken.split(".");
  if (segments.length !== 3) return null;

  try {
    const normalized = segments[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    const payload: unknown = JSON.parse(atob(padded));
    if (typeof payload !== "object" || payload === null) return null;

    const exp = (payload as { exp?: unknown }).exp;
    return typeof exp === "number" && Number.isFinite(exp) ? exp * 1000 : null;
  } catch {
    return null;
  }
}

/**
 * A transport failure, as opposed to a server rejection or an unusable role.
 * `fetch` rejects with a TypeError when the request never reached the server;
 * any other error is treated as a rejection of the stored session.
 */
function isNetworkFailure(error: unknown): boolean {
  return error instanceof TypeError;
}

/**
 * Milliseconds until a proactive renewal should run, or null when there is
 * nothing to schedule. An already expired token is never renewed silently;
 * the caller signs the staff member out instead.
 */
export function renewalDelayMs(
  accessExpiresAt: number | null,
  now: number,
  skewMs: number,
): number | null {
  if (accessExpiresAt === null || accessExpiresAt <= now) return null;
  return Math.max(0, accessExpiresAt - now - skewMs);
}

function failureOutcome(error: unknown): StaffRestoreOutcome {
  if (
    error instanceof UnsupportedStaffRoleError ||
    (error instanceof StaffAuthApiError && error.status === 403)
  ) {
    return { kind: "denied" };
  }

  return { kind: "signed-out" };
}

const supportedRoles = new Set<StaffRole>([
  "platform_admin",
  "agency_admin",
  "agent",
]);

const inFlightRestorations = new WeakMap<
  StaffSessionStorage,
  Promise<StaffSession | null>
>();

export function isSupportedStaffRole(role: string): role is StaffRole {
  return supportedRoles.has(role as StaffRole);
}

function browserSessionStorage(): StaffSessionStorage {
  return window.sessionStorage;
}

async function resolveStaffSession(
  accessToken: string,
  csrfToken: string,
  storage: StaffSessionStorage,
): Promise<StaffSession> {
  try {
    storage.setItem(STAFF_CSRF_STORAGE_KEY, csrfToken);
    const { user } = await getStaffMe(accessToken);
    if (!isSupportedStaffRole(user.role)) {
      throw new UnsupportedStaffRoleError();
    }

    return {
      accessToken,
      csrfToken,
      accessExpiresAt: decodeAccessTokenExpiry(accessToken),
      user: { ...user, role: user.role },
    };
  } catch (error) {
    storage.removeItem(STAFF_CSRF_STORAGE_KEY);
    throw error;
  }
}

/**
 * Restores a stored session and reports why it failed, so the UI can tell an
 * expired session apart from a network outage or a forbidden account.
 */
export async function restoreStaffSessionOutcome(
  storage: StaffSessionStorage = browserSessionStorage(),
): Promise<StaffRestoreOutcome> {
  const currentCsrfToken = storage.getItem(STAFF_CSRF_STORAGE_KEY);
  if (!currentCsrfToken) return { kind: "signed-out" };

  let rotatedTokens: StaffSessionTokens;
  try {
    rotatedTokens = await refreshStaffSession(currentCsrfToken);
  } catch (error) {
    if (isNetworkFailure(error)) return { kind: "unavailable" };

    storage.removeItem(STAFF_CSRF_STORAGE_KEY);
    return failureOutcome(error);
  }

  try {
    const session = await resolveStaffSession(
      rotatedTokens.access_token,
      rotatedTokens.csrf_token,
      storage,
    );
    return { kind: "session", session };
  } catch (error) {
    return failureOutcome(error);
  }
}

/**
 * Renews an active session before its access token expires.
 *
 * Returns null when renewal fails; the stored CSRF token is kept only for a
 * transport failure, so a retry stays possible without a new login.
 */
export async function renewStaffSession(
  session: StaffSession,
  storage: StaffSessionStorage = browserSessionStorage(),
): Promise<StaffSession | null> {
  const csrfToken =
    storage.getItem(STAFF_CSRF_STORAGE_KEY) ?? session.csrfToken;

  try {
    const rotatedTokens = await refreshStaffSession(csrfToken);
    return await resolveStaffSession(
      rotatedTokens.access_token,
      rotatedTokens.csrf_token,
      storage,
    );
  } catch (error) {
    if (isNetworkFailure(error)) return null;

    storage.removeItem(STAFF_CSRF_STORAGE_KEY);
    return null;
  }
}

async function restoreStaffSessionFromStorage(
  storage: StaffSessionStorage,
): Promise<StaffSession | null> {
  const currentCsrfToken = storage.getItem(STAFF_CSRF_STORAGE_KEY);
  if (!currentCsrfToken) return null;

  let rotatedTokens: StaffSessionTokens;
  try {
    rotatedTokens = await refreshStaffSession(currentCsrfToken);
  } catch {
    storage.removeItem(STAFF_CSRF_STORAGE_KEY);
    return null;
  }

  try {
    return await resolveStaffSession(
      rotatedTokens.access_token,
      rotatedTokens.csrf_token,
      storage,
    );
  } catch {
    return null;
  }
}

export function restoreStaffSession(
  storage: StaffSessionStorage = browserSessionStorage(),
): Promise<StaffSession | null> {
  const existingRestoration = inFlightRestorations.get(storage);
  if (existingRestoration) return existingRestoration;

  const restoration = restoreStaffSessionFromStorage(storage);
  inFlightRestorations.set(storage, restoration);

  const clearRestoration = () => {
    if (inFlightRestorations.get(storage) === restoration) {
      inFlightRestorations.delete(storage);
    }
  };
  void restoration.then(clearRestoration, clearRestoration);

  return restoration;
}

export function completeStaffSession(
  login: LoginCompletion,
  storage: StaffSessionStorage = browserSessionStorage(),
): Promise<StaffSession> {
  return resolveStaffSession(login.access_token, login.csrf_token, storage);
}

export async function endStaffSession(
  session: StaffSession,
  storage: StaffSessionStorage = browserSessionStorage(),
): Promise<void> {
  await logoutStaffSession(session.csrfToken);
  storage.removeItem(STAFF_CSRF_STORAGE_KEY);
}
