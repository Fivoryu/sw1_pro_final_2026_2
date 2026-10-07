import { InvitationAcceptancePage } from "./features/auth/InvitationAcceptancePage";
import { ProtectedStaffShell } from "./features/auth/ProtectedStaffShell";
import { SceneViewer } from "./features/editor3d/SceneViewer";

const INVITATION_PATH = "/accept-invitation";
const BACKEND_INVITATION_PATH = "/invitations/accept";
const BACKEND_INVITATION_PREFIX = `${BACKEND_INVITATION_PATH}/`;
const URL_SAFE_INVITATION_TOKEN = /^[A-Za-z0-9_-]+$/;

function getPathInvitationToken(pathname: string) {
  if (pathname === BACKEND_INVITATION_PATH) {
    return { isInvitationRoute: true, token: null };
  }

  if (!pathname.startsWith(BACKEND_INVITATION_PREFIX)) {
    return { isInvitationRoute: false, token: null };
  }

  const encodedToken = pathname.slice(BACKEND_INVITATION_PREFIX.length);
  if (encodedToken.includes("/")) {
    return { isInvitationRoute: true, token: null };
  }

  try {
    const token = decodeURIComponent(encodedToken);
    return {
      isInvitationRoute: true,
      token: URL_SAFE_INVITATION_TOKEN.test(token) ? token : null,
    };
  } catch {
    return { isInvitationRoute: true, token: null };
  }
}

export function App() {
  const currentUrl = new URL(window.location.href);
  const pathInvitation = getPathInvitationToken(currentUrl.pathname);

  // --- RUTA EXCLUSIVA PARA TU VISOR 3D ---
  if (currentUrl.pathname === "/visor3d") {
    return <SceneViewer />;
  }

  if (pathInvitation.isInvitationRoute) {
    return <InvitationAcceptancePage invitationToken={pathInvitation.token} />;
  }

  if (currentUrl.pathname === INVITATION_PATH) {
    return (
      <InvitationAcceptancePage
        invitationToken={currentUrl.searchParams.get("token")}
      />
    );
  }

  return <ProtectedStaffShell />;
}
