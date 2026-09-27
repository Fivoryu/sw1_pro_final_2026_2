# F03 — Identity, roles, and agency access

## Objective

Deliver RoomForge identity and authorization behavior for customers and staff, agency-agent membership management, and server-side tenant isolation. Follow the F03 scope in the user-approved RoomForge roadmap. The user chose Organic Driven Development for this work.

The public read API for approved listings is explicitly deferred to F04 by the user. F03 will establish and test private tenant boundaries now, but this deferral remains an open F03.3 acceptance dependency; do not report the roadmap's complete public-catalog criterion as satisfied until F04 is integrated.

## Authorization and constraints

- The user authorized progressing F03 in a new worktree.
- Worktree: `D:/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final-f03-identity-agencies-wt`.
- Branch: `feat/f03-identity-agencies`.
- Base: committed F02 branch `c38ac842` (`feat/f02-base-ux-automation`), descended from local `origin/main` `b8a07e3`.
- The root checkout is dirty and 14 commits behind local `origin/main`; do not edit, stage, clean, reset, or otherwise disturb it.
- F02's separate worktree has in-progress, uncommitted T3b migration-verification and T4 mobile-shell work. This F03 worktree intentionally excludes those changes. Coordinate before creating Alembic migrations after `0004`; do not modify `0004` here.
- Reuse the staff identity/agency foundation already present at the selected base. Do not recreate it.
- Customer auth exists as commit `de534c7` on the diverged `feat/roomforge-mobile-3d` branch. Do not cherry-pick that commit wholesale: its `backend/app/main.py` changes remove the F02 health router, common error handlers, and configured DB timeout arguments. Port only customer-auth behavior and tests while preserving the F02 base; do not import wallet, catalog, quote, reservation, or unrelated task changes.
- Do not implement listing CRUD/publication, offers, quotes, wallet flows, reservations, escrow, or account-recovery email in this feature. Public listing reads are an explicit F04 deferral.
- Do not start external services or use PostgreSQL unless separately authorized for this worktree. Use isolated SQLite/TestClient checks by default and report PostgreSQL evidence as pending if unavailable.
- Preserve all other worktrees. No push, PR, merge to main, or publication is requested.

## Approved behavior and decisions

- **Roles:** `platform_admin`, `agency_admin`, `agent`, and customer identity remain distinct. Role and agency/tenant authority come from server-side records, never client-supplied role/tenant fields.
- **Agency identity:** existing `tenant_id` identifies the agency. Agencies are ID-only in the current approved registry; do not invent agency profile fields.
- **Agency administration:** platform admins retain agency provisioning/admin-invitation authority. Agency admins manage agents only within their own agency; agents cannot self-promote or administer another agency.
- **Customer identity:** keep customer auth separate from staff auth under `/api/v1/customer/auth/*`; do not reuse staff TOTP/session machinery. Preserve the approved contract: normalized unique email, password length at least 8 with Argon2id, no email verification or automatic login at registration, 15-minute customer-audience access JWT, opaque rotating refresh token with 7-day absolute lifetime and 30-minute sliding inactivity, and DB-backed `/me`. Routes are `register`, `login`, `refresh`, `logout`, and `me`; logout revokes the session and returns 204. Do not invent email-based password recovery.
- **API errors:** use the F02 common `ErrorResponse` envelope `{"detail":"...","code":"..."}` and its stable codes/statuses, including generic redaction for 5xx. Do not preserve a legacy customer-auth error envelope if it conflicts with the common contract.
- **Agent deactivation (user-selected):** mark the membership inactive, deny protected operations, revoke that agent's active sessions, and preserve the account and history. Reactivation requires a fresh login.
- **Tenant privacy:** private staff operations and data are agency-scoped and enforced server-side. Approved listings may be public across agencies, but their read API is deferred to F04 as noted above.
- **Session behavior:** preserve safe refresh/expiry/logout behavior and remove access to private screens after logout or authorization loss.

## Acceptance criteria

1. Customer and staff authentication/session namespaces remain separate; customer registration/login/refresh/logout/me behavior is covered by tests and staff auth regressions remain green.
2. Agency admins can manage agents within their own agency using invitation-backed, server-derived roles/tenant; unauthorized roles and cross-agency attempts fail closed.
3. Deactivating an agent denies subsequent protected operations and revokes active sessions without deleting the account or history; reactivation requires a new login.
4. Tenant ownership is checked on every implemented private agency operation; changing an agency/record ID cannot expose or mutate another agency's private data.
5. Panel/mobile session and role states follow the approved UX contract: restoration, expiry, access-denied, network/error, logout, and secure token handling. Wait for the F02 surface handoff before editing overlapping mobile-shell paths.
6. No fake listing data, public listing endpoint, offer/quote, wallet, or reservation behavior is added to this feature. The public catalog read acceptance is explicitly tracked as deferred to F04, not reported as complete.
7. Each behavior-changing unit has strict TDD evidence (RED, GREEN, triangulation, refactor), focused checks, and a work-unit commit on this branch. Record exact checks and commit identity.

## TDD, runners, and runtime constraints

- **Mode:** strict TDD, based on the user's prior explicit selection for RoomForge identity/agency work.
- **Backend runner source:** root `AGENTS.md`; this sibling worktree has no local `.venv`. From its `backend/`, invoke the existing shared tooling environment without modifying it: `../../proyecto_final/.venv/Scripts/python.exe -m pytest <test-paths> -q` and at closure `../../proyecto_final/.venv/Scripts/python.exe -m pytest tests -q`.
- **Backend static checks:** from this worktree's `backend/`, use `../../proyecto_final/.venv/Scripts/ruff.exe check app tests` and `../../proyecto_final/.venv/Scripts/pyright.exe app tests`.
- **Panel:** from `panel/staff-shell/`, use the package's `npm test` and `npm run build` scripts after inspecting the selected base.
- **Flutter:** use `flutter test`, `flutter analyze`, and `flutter build apk --debug` from each implemented app directory once the F02 shell is committed/handed off; do not claim device or iOS verification without running it.
- **Runtime harness:** backend FastAPI TestClient with SQLite fixtures; no external services. PostgreSQL migration/runtime verification is not authorized by this task unless the user grants a separate bounded authorization.

## Route and delivery

- Work routing: delegated read-only mapping was completed before choosing the base. Any writer touching 2+ non-trivial files must be one bounded `gentle-ai-worker` with exact allowed edit surfaces; no parallel writers in this worktree. Delegate command-running verification according to the current RDD plan.
- Keep one parent session responsible for task reconciliation, user decisions, and feature completion.
- Delivery strategy: `ask-on-risk` (default). Initial authored-change forecast: approximately 1,500–2,500 lines across backend, tests, and auth UI; refine after task slices are mapped. Keep cohesive work units and ask for a chain strategy before any commit if the candidate/forecast exceeds the 400-authored-line review budget.
- Each work unit records tests, runtime scenario or explicit N/A reason, rollback boundary, and commit identity. Do not push or open a PR.
- **F03-02 delivery (user-selected):** the 512-line source/test diff (505 additions, 7 deletions) exceeds the 400-line review budget, so split into exactly two local commits, with no push: (1) agent invitation/onboarding and global email-claim tests; (2) agency-scoped agent listing, activation/deactivation, session revocation, and tests. Include the ODD feature plan with the first slice and keep each commit under the review budget.
- **Rollback boundaries:** slice 1 reverts the agent invitation endpoint/schema, shared invitation issuance extension, agent onboarding allowance, and invitation tests (restoring the original agency-admin invitation behavior); slice 2 reverts only the agent list/status endpoints/DTOs and their tests, leaving invitation/onboarding intact.

## Tasks

- [x] **F03-00 — Establish isolated baseline and map existing implementation.** Created/registered the worktree at `c38ac842`; confirmed the root checkout remains untouched; mapped existing staff/agency code and customer-auth/catalog branch boundaries. Public listing deferral recorded per user choice. The baseline was clean before F03-02 implementation began.
- [ ] **F03-01 — Integrate customer authentication backend.** Port/reconcile only the approved customer identity/session unit from `de534c7`, preserving F02 contracts and staff behavior; exclude wallet/catalog/task changes. Coordinate the `0004` migration parent with F02 T3b before adding a new revision. The existing `0005_customer_identity` in `de534c7` depends on the long `0004_staff_invitation_pending_email_unique` ID and must follow F02's stabilized replacement ID. **Current state:** pending; Git-object comparison found `de534c7` also removes F02 health/error/timeout behavior from `main.py`, so it must not be cherry-picked wholesale. No source files changed.
- [x] **F03-02 — Implement agency-agent membership lifecycle.** Add agency-admin agent invitation/listing/deactivation behavior with server-derived agency/role, global email-claim protections consistent with existing invitation invariants, and session revocation on deactivation. The current base already has `StaffAccount.active`, the `agent` invitation role, and `StaffSession.revoked_at`, so avoid a migration unless implementation evidence proves one is required. The test-defined routes are `POST /api/v1/agencies/agent-invitations`, `GET /api/v1/agencies/agents`, and `POST /api/v1/agencies/agents/{agent_id}/{activate|deactivate}`; the principal determines tenant scope. **Current state:** in progress; strict-TDD RED is valid (`5 failed, 93 passed, 2 warnings`). Implementation covers these routes, schemas, shared invitation issuance, and agent onboarding via existing TOTP; deactivation revokes active sessions in the same transaction and reactivation preserves revocation. Focused GREEN passed (`98 passed, 2 warnings`), Ruff passed, and after adding explicit null guards Pyright passed (`0 errors`). The test matrix covers invitation/claim conflicts, role/tenant derivation, pagination/agency scoping, account target restrictions, and revoke/reactivate behavior; the shared invitation helper refactor passed focused regression checks. Full backend suite passed (`137 passed, 2 skipped, 4 warnings`). The user authorized two local commits, no push. Slice 1 (invitation/onboarding with global email claims) is commit `f6c2bf4`; slice 2 (scoped listing/status/session revocation) is this commit, `feat(agencies): manage agent membership status` (parent `f6c2bf4`).

  Allowed edit surfaces for this task:
  - `backend/app/modules/agencies/router.py`
  - `backend/app/modules/agencies/schemas.py`
  - `backend/app/modules/identity/invitations.py`
  - `backend/app/modules/identity/router.py`
  - `backend/tests/test_agencies.py`
  - `backend/tests/test_staff_identity.py`
  - `backend/tests/test_staff_identity_tdd.py`
### F03-02 work-unit verification evidence

- **Invitation/onboarding slice**, from `backend/`: `../../proyecto_final/.venv/Scripts/python.exe -m pytest tests/test_agencies.py::test_agency_admin_can_invite_agent_with_server_derived_role_and_tenant tests/test_agencies.py::test_agent_invitation_obeys_global_normalized_email_claims tests/test_staff_identity.py tests/test_staff_identity_tdd.py -q` — **51 passed, 2 warnings**. Runtime harness: FastAPI TestClient with isolated SQLite fixtures; no external service.
- **Listing/status slice**, from `backend/`: `../../proyecto_final/.venv/Scripts/python.exe -m pytest tests/test_agencies.py::test_agency_admin_lists_only_agents_in_its_own_agency tests/test_agencies.py::test_agent_deactivation_revokes_sessions_and_reactivation_requires_fresh_login tests/test_agencies.py::test_agents_cannot_manage_memberships_and_admins_cannot_change_other_accounts -q` — **3 passed, 1 warning**. Runtime harness: FastAPI TestClient with isolated SQLite fixtures; no external service.
- **Combined and regression checks**, from `backend/`: focused agency/staff suite — **98 passed, 2 warnings**; Ruff — **all checks passed**; Pyright `app tests` — **0 errors, 0 warnings, 0 informations**; full `pytest tests -q` — **137 passed, 2 skipped, 4 warnings**. No PostgreSQL, Docker, or network check was run.

- [ ] **F03-03 — Enforce private tenant isolation.** Add actor/role/tenant authorization tests for implemented private agency operations, including cross-agency reads/writes and role escalation attempts. Do not implement public listing reads; that is deferred to F04.
- [ ] **F03-04 — Integrate role-aware session UX.** Integrate customer auth in the client app and staff access states in the panel/capture surfaces, including secure token handling, restoration, expiry, denial, network errors, and logout. Avoid overlap with F02 T4 until its shell is handed off.
- [ ] **F03-05 — Verify and close the authorized F03 slice.** Run focused and full applicable backend/panel/mobile checks, record skipped/unavailable PostgreSQL/device checks, and keep the public catalog criterion visibly pending for F04.

## Progress and next step

The new F03 worktree is on branch `feat/f03-identity-agencies`, based at commit `c38ac842`. It contains the ODD task document, agent-membership tests, and implementation in the approved agency/identity files; no schema migration was added. Root `main` remains dirty and behind; it was not modified. The base includes staff identity and agency provisioning; customer auth is isolated on the mobile feature branch. F02 T3b/T4 work remains uncommitted in its own worktree. Source inspection confirmed the existing account-active flag, agent invitation role, and session revocation field, so F03-02 needed no schema change. The worktree has no local `.venv`; use existing root-project tooling via `../../proyecto_final/.venv/Scripts/` from F03 `backend/`, without modifying the environment. Strict-TDD RED was observed (`5 failed, 93 passed, 2 warnings`); focused GREEN passed (`98 passed, 2 warnings`), Ruff passed, and after explicit null guards Pyright passed (`0 errors`). The targeted test matrix checks global invitation claims, trusted role/tenant derivation, cross-agency denial, pagination, and session revocation/reactivation. The full backend suite passed (`137 passed, 2 skipped, 4 warnings`). The user selected two local commits (no push) because the source/test diff has 512 authored diff lines (505 insertions, 7 deletions): invitation/onboarding plus global email claims is commit `f6c2bf4`; tenant-scoped list/status/session revocation is this commit, `feat(agencies): manage agent membership status`, with parent `f6c2bf4`. Immutable Git-object comparison confirmed that `de534c7` is not directly compatible with the F02 base: its app factory drops health registration, common error handling, and DB timeout configuration; its migration 0005 also points to the current long 0004 revision. F03-01 remains pending until T3b stabilizes that parent.
