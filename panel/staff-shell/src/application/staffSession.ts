import {
  getStaffMe,
  logoutStaffSession,
  refreshStaffSession,
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
  user: StaffUser & { role: StaffRole };
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
      throw new Error("The staff account has an unsupported role.");
    }

    return {
      accessToken,
      csrfToken,
      user: { ...user, role: user.role },
    };
  } catch (error) {
    storage.removeItem(STAFF_CSRF_STORAGE_KEY);
    throw error;
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
