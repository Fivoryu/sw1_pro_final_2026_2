# F03 — Identity, roles, and agency access

## Objective

Deliver RoomForge identity and authorization behavior for customers and staff, agency-agent membership management, and server-side tenant isolation. Follow the F03 scope in the user-approved RoomForge roadmap. The user chose Organic Driven Development for this work.

The public read API for approved listings is explicitly deferred to F04 by the user. F03 will establish and test private tenant boundaries now, but this deferral remains an open F03.3 acceptance dependency; do not report the roadmap's complete public-catalog criterion as satisfied until F04 is integrated.

## Authorization and constraints

- The user authorized progressing F03 in a new worktree.
- Worktree: `D:/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final-f03-identity-agencies-wt`.
- Branch: `feat/f03-identity-agencies`.
- Base after the F03 rebase: `origin/feat/f02-base-ux-automation` at `7973ffa`. That ref already merged `main` (`e845ece`) and contains `main` `35ea8f7` plus the F02 health, common-error-envelope, timeout, capture-app, panel, and CI work. The original base `c38ac842` was an unmerged F02 snapshot whose line never reached `main`; F03 now sits on the integrated line.
- The root checkout stays dirty with two untracked files and was not edited. It holds `main` `35ea8f7`, which the rebased base contains.
- F02 is complete and committed on `origin/feat/f02-base-ux-automation` (`7973ffa`); F02 T4/T6 closed at `a047a71`. **Superseded during delivery:** F02 reached `main` through PRs #6-#9, so F03 was no longer stacked when it was delivered. See the delivery outcome at the end of this document.
- Reuse the staff identity/agency foundation already present at the selected base. Do not recreate it.
- Customer auth is now part of the rebased base as `backend/app/modules/customer_identity/` (originally `de534c7`). Do not port it again. F03-01 is narrowed to the two verified gaps recorded below, and the port plan is retired.
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
5. Panel/mobile session and role states follow the approved UX contract: restoration, expiry, access-denied, network/error, logout, and secure token handling. The former F02 T4 handoff blocker is cleared, since T4 closed at `a047a71`.
6. No fake listing data, public listing endpoint, offer/quote, wallet, or reservation behavior is added to this feature. The public catalog read acceptance is explicitly tracked as deferred to F04, not reported as complete.
7. Each behavior-changing unit has strict TDD evidence (RED, GREEN, triangulation, refactor), focused checks, and a work-unit commit on this branch. Record exact checks and commit identity.

## TDD, runners, and runtime constraints

- **Mode:** strict TDD, based on the user's prior explicit selection for RoomForge identity/agency work.
- **Backend runner source:** root `AGENTS.md`; this sibling worktree has no local `.venv`. From its `backend/`, invoke the existing shared tooling environment without modifying it: `../../proyecto_final/.venv/Scripts/python.exe -m pytest <test-paths> -q` and at closure `../../proyecto_final/.venv/Scripts/python.exe -m pytest tests -q`.
- **Backend static checks:** from this worktree's `backend/`, use `../../proyecto_final/.venv/Scripts/ruff.exe check app tests` and `../../proyecto_final/.venv/Scripts/pyright.exe app tests`.
- **Panel:** from `panel/staff-shell/`, use the package's `npm test` and `npm run build` scripts after inspecting the selected base.
- **Flutter:** use `flutter test`, `flutter analyze`, and `flutter build apk --debug` from each implemented app directory; do not claim device or iOS verification without running it.
- **Runtime harness:** backend FastAPI TestClient with SQLite fixtures; no external services. PostgreSQL migration/runtime verification is not authorized by this task unless the user grants a separate bounded authorization.

## Route and delivery

- Work routing: any writer touching 2+ non-trivial files must be one bounded `gentle-ai-worker` with exact allowed edit surfaces; no parallel writers in this worktree. Delegate command-running verification according to the current RDD plan.
- Keep one parent session responsible for task reconciliation, user decisions, and feature completion.
- Delivery strategy: `ask-on-risk` (default). Initial authored-change forecast: approximately 1,500–2,500 lines across backend, tests, and auth UI; refine after task slices are mapped. Keep cohesive work units and ask for a chain strategy before any commit if the candidate/forecast exceeds the 400-authored-line review budget.
- Each work unit records tests, runtime scenario or explicit N/A reason, rollback boundary, and commit identity. Do not push or open a PR.
- **F03-02 delivery (user-selected):** the 512-line source/test diff exceeded the 400-line review budget, so it was split into exactly two local commits, with no push: (1) agent invitation/onboarding and global email-claim tests; (2) agency-scoped agent listing, activation/deactivation, session revocation, and tests. Include the ODD feature plan with the first slice and keep each commit under the review budget.
- **Rollback boundaries:** slice 1 reverts the agent invitation endpoint/schema, shared invitation issuance extension, agent onboarding allowance, and invitation tests (restoring the original agency-admin invitation behavior); slice 2 reverts only the agent list/status endpoints/DTOs and their tests, leaving invitation/onboarding intact.

## Rebase and integration evidence

On the user's decision, `feat/f03-identity-agencies` was rebased from the unmerged F02 snapshot `c38ac842` onto `origin/feat/f02-base-ux-automation` `7973ffa`, which already contains `main`. The rebase replayed both F03-02 work units: `a9614ba` (agent invitations) then `0251015` (agent membership status). Conflicts were purely additive and confined to `backend/app/modules/agencies/router.py` and `backend/app/modules/agencies/schemas.py`; both sides were preserved (F02's wallet routes, pagination, and `_require_same_tenant_agency_admin` alongside F03's agent-membership additions), and the other six files auto-merged. A scripted conflict resolution initially misplaced one imported schema name and left three missing blank lines; both defects were corrected before `rebase --continue`, and Ruff reports no formatting rule violation.

Evidence recorded after the rebase, from `backend/`:

- Focused: `../../proyecto_final/.venv/Scripts/python.exe -m pytest tests/test_agencies.py tests/test_staff_identity.py tests/test_staff_identity_tdd.py tests/test_customer_identity.py -q` — **124 passed, 2 warnings**.
- Full: `../../proyecto_final/.venv/Scripts/python.exe -m pytest tests -q` — **403 passed, 2 skipped, 4 warnings**.
- Ruff: `../../proyecto_final/.venv/Scripts/ruff.exe check app tests` — **All checks passed**.
- Pyright: `../../proyecto_final/.venv/Scripts/pyright.exe app tests` — **33 errors, 0 warnings, 0 informations**. The normalized diagnostic set is identical to the same command run in the root `main` checkout, so the rebase introduced zero new diagnostics. All 33 pre-exist in catalog, reservations, customer-wallet, and agency-wallet code untouched by F03.
- Runtime harness: FastAPI TestClient with isolated SQLite fixtures; no PostgreSQL, Docker, or network checks were run.

## Tasks

- [x] **F03-00 — Establish isolated baseline and map existing implementation.** Created/registered the worktree; confirmed the root checkout remains untouched; mapped existing staff/agency code and customer-auth/catalog branch boundaries. Public listing deferral recorded per user choice. The baseline was clean before F03-02 implementation began. Later re-based onto the integrated F02 line as recorded above.
- [x] **F03-01 — Reconcile customer authentication with the approved F03 contract.** The rebased base already provides `register`, `login`, `refresh`, `logout`, and `me` under `/api/v1/customer/auth/*` with normalized unique email, Argon2id passwords of at least 8 characters, no email verification or auto-login, a 15-minute customer-audience access token, an opaque rotating refresh token, DB-backed `/me`, and a migrated `0005_customer_identity` that now depends on the stabilized `0004_pending_staff_email_uniq` revision. **Verified gaps:** (1) `backend/app/modules/customer_identity/service.py` sets `next_expiration = now + 7 days` on every rotation, so a session chain has no absolute 7-day lifetime from login; the fix must carry the chain's original `expires_at` forward while the existing 30-minute idle window keeps sliding. (2) Customer failures bypass the F02 common envelope: `backend/app/main.py:104-110` maps `CustomerApiError` to `{"error": {"code": ...}}`, and the customer router/schemas document that legacy shape, while F02 requires `{"detail": ..., "code": ...}` (`backend/app/core/errors.py`, `backend/tests/test_api_contract.py:21-26`). **Current state:** both gaps are implemented and verified. Gap 1 is commit `703186e`; gap 2 removes the bespoke customer error layer (9 files, 176 insertions, 109 deletions) and routes every customer failure through the shared F02 envelope using only the common `ErrorCode` values, keeping all status codes and success paths unchanged. Customer-facing clients must consume the new shape, which is tracked in F03-04.

  Allowed edit surfaces once started:
  - `backend/app/modules/customer_identity/service.py`
  - `backend/app/modules/customer_identity/models.py`
  - `backend/app/modules/customer_identity/errors.py`
  - `backend/app/modules/customer_identity/router.py`
  - `backend/app/modules/customer_identity/schemas.py`
  - `backend/app/main.py`
  - `backend/tests/test_customer_identity.py`
  - `backend/tests/test_catalog.py`
### F03-01 absolute-lifetime unit evidence (gap 1)

- **Change:** `backend/app/modules/customer_identity/service.py` no longer computes `next_expiration = now + 7 days` on every rotation; the successor session now inherits the predecessor's `expires_at`, so the chain keeps a single absolute deadline from login while `last_activity_at` continues to provide the 30-minute sliding window. No migration was needed: `CustomerSession.expires_at` and `last_activity_at` already existed, and `session.py` already enforces both bounds for access tokens.
- **RED (proven, not asserted):** restoring the pre-fix `service.py` and running the new test failed with `assert 200 == 401` at `backend/tests/test_customer_identity.py:314`, showing the pre-fix chain still served a refresh after the 7-day deadline.
- **GREEN:** `tests/test_customer_identity.py` — **26 passed**; broader regression set (`test_customer_identity.py`, `test_catalog.py`, `test_api_contract.py`, `test_staff_identity.py`) — **91 passed**; full suite — **404 passed, 2 skipped, 4 warnings**.
- **Static checks:** Ruff clean on the touched paths; Pyright on `app/modules/customer_identity tests/test_customer_identity.py` reports **8 errors identical to the `main` baseline** (same messages; only the line numbers shift by the 35 lines the new test added).
- **Triangulation:** the new test refreshes every 29 minutes across the whole 7-day window, so the idle window can never explain a rejection, and it asserts 401 only after the absolute deadline; the pre-existing tests keep proving that a gap beyond 30 minutes is rejected and that in-window refreshes rotate the token.
- **Rollback boundary:** restore `next_expiration` and `expires_at=next_expiration` in `service.py`, then remove `test_customer_refresh_cannot_extend_absolute_lifetime_beyond_login` and restore the two `expires_at` assertions in the wire-contract test.
- **Runtime harness:** FastAPI TestClient with isolated SQLite fixtures and the app's injectable clock; no external service.

### F03-01 shared-envelope unit evidence (gap 2)

- **Change:** deleted the bespoke `CustomerApiError` handler and the customer-specific `RequestValidationError` branch in `backend/app/main.py`; converted the raise sites in `customer_identity/router.py` and `customer_identity/session.py` (`_invalid_session`) to `HTTPException`; switched both customer routers to `responses=ERROR_RESPONSES`; removed `CustomerErrorDetail`/`CustomerErrorResponse`; updated the five 401 OpenAPI references in `backend/app/modules/reservations/router.py` to the shared `ErrorResponse`; and reduced `customer_identity/errors.py` to a docstring module.
- **Contract mapping:** every 401 becomes `unauthorized` with the generic detail `Authentication failed.` (an unknown email and a wrong password stay indistinguishable); every 409 becomes `conflict` with `The request conflicts with existing data.`; 422 uses `validation_error` through the shared fallback; 5xx redaction stays in the shared handler. No bespoke customer codes remain.
- **RED (proven, not asserted):** reverting the six application files and running `pytest tests/test_api_contract.py -k customer_errors_use_shared_envelope -q` failed all three cases (409 conflict, 401 unauthorized, 422 validation_error); the application files were then restored and the `git diff` hash verified byte-identical to the pre-revert state.
- **GREEN:** `tests/test_customer_identity.py` — **26 passed**; broader set (`test_catalog.py`, `test_api_contract.py`, `test_agencies.py`, `test_staff_identity.py`) — **117 passed**; reservations, which consume `get_active_customer` — **31 passed**; full suite — **407 passed, 2 skipped, 4 warnings**.
- **Static checks:** Ruff clean on the touched paths; Pyright reports exactly the 8 pre-existing diagnostics in `customer_identity/service.py` and `tests/test_customer_identity.py`, and none in `main.py`, `reservations/router.py`, `test_catalog.py`, or `test_api_contract.py`.
- **Rollback boundary:** restore the `CustomerApiError` class, its handler and the customer validation branch in `main.py`, the bespoke `_CUSTOMER_*` schemas and `responses` dictionaries, the `CustomerErrorResponse` 401 references in the reservations router, and revert the updated assertions.
- **Runtime harness:** FastAPI TestClient with isolated SQLite fixtures; no external service.

- [x] **F03-02 — Implement agency-agent membership lifecycle.** Add agency-admin agent invitation/listing/deactivation behavior with server-derived agency/role, global email-claim protections consistent with existing invitation invariants, and session revocation on deactivation. The base already had `StaffAccount.active`, the `agent` invitation role, and `StaffSession.revoked_at`, so no migration was needed. The routes are `POST /api/v1/agencies/agent-invitations`, `GET /api/v1/agencies/agents`, and `POST /api/v1/agencies/agents/{agent_id}/{activate|deactivate}`; the principal determines tenant scope. Strict-TDD RED was valid (`5 failed, 93 passed, 2 warnings`); focused GREEN passed, Ruff passed, and Pyright passed for the touched files. The test matrix covers invitation/claim conflicts, role/tenant derivation, pagination/agency scoping, account target restrictions, and revoke/reactivate behavior. The user authorized two local commits, no push. Slice 1 (invitation/onboarding with global email claims) is `a9614ba`; slice 2 (scoped listing/status/session revocation) is `0251015`. Both were replayed onto `7973ffa` by the rebase above.

  Edit surfaces used for this task:
  - `backend/app/modules/agencies/router.py`
  - `backend/app/modules/agencies/schemas.py`
  - `backend/app/modules/identity/invitations.py`
  - `backend/app/modules/identity/router.py`
  - `backend/tests/test_agencies.py`
  - `backend/tests/test_staff_identity.py`
  - `backend/tests/test_staff_identity_tdd.py`
### F03-02 work-unit verification evidence

- **Invitation/onboarding slice**, from `backend/`: `../../proyecto_final/.venv/Scripts/python.exe -m pytest tests/test_agencies.py::test_agency_admin_can_invite_agent_with_server_derived_role_and_tenant tests/test_agencies.py::test_agent_invitation_obeys_global_normalized_email_claims tests/test_staff_identity.py tests/test_staff_identity_tdd.py -q` — **51 passed, 2 warnings** on the original base. Runtime harness: FastAPI TestClient with isolated SQLite fixtures; no external service.
- **Listing/status slice**, from `backend/`: `../../proyecto_final/.venv/Scripts/python.exe -m pytest tests/test_agencies.py::test_agency_admin_lists_only_agents_in_its_own_agency tests/test_agencies.py::test_agent_deactivation_revokes_sessions_and_reactivation_requires_fresh_login tests/test_agencies.py::test_agents_cannot_manage_memberships_and_admins_cannot_change_other_accounts -q` — **3 passed, 1 warning** on the original base. Runtime harness: FastAPI TestClient with isolated SQLite fixtures; no external service.
- **Post-rebase re-verification:** the full-suite, Ruff, and Pyright results in the rebase section above supersede the original-base numbers for this feature.

- [x] **F03-03 — Enforce private tenant isolation.** Add actor/role/tenant authorization tests for implemented private agency operations, including cross-agency reads/writes and role escalation attempts. The rebased base already enforces `_require_same_tenant_agency_admin` on agency-wallet routes, and F03-02 covers the agent-membership routes, so this task became a bounded audit of the remaining private operations plus any missing coverage. Do not implement public listing reads; that is deferred to F04. **Current state:** complete; the audit found no missing server-side authorization, and the four missing denial tests were added with a mutation proof (see below).

### F03-03 isolation evidence

- **Audit:** all 37 declared route decorators were mapped with their auth dependency, role/tenant enforcement, whether the tenant derives from the principal, and any existing cross-tenant coverage. Verdict: no exploit path found. Agency-private operations are either platform-admin-only or agency-admin with a principal-derived tenant; customer records are principal-scoped; catalog reads are limited to published/approved listings. Before accepting the audit I independently re-verified four of its load-bearing claims: the PUT agency-wallet guard, the `_set_agent_active` role-plus-tenant filter, the inline catalog deposit check, and `ensure_reservation_action_eligible`.
- **Added tests:** `test_agency_admin_cannot_link_wallet_for_another_tenant` (`backend/tests/test_agency_wallets.py`: 403 with `forbidden` and no wallet row created), `test_agency_admin_cannot_activate_agent_from_another_agency` (`backend/tests/test_agencies.py`: 404 with `not_found` and the target agent stays inactive), `test_staff_chain_reconciliation_rejects_cross_agency_admin_before_chain_work` and `test_customer_chain_reconciliation_rejects_another_customers_reservation` (`backend/tests/test_reservation_chain_api.py`; both assert the reservations envelope, that the receipt verifier is never invoked, and that no chain row is written).
- **Mutation proof:** every added test was shown to fail when its own guard was temporarily removed — the wallet same-tenant call, the agent query's `tenant_id` filter, the staff tenant clause, and the customer ownership check — and each application file was then restored and verified clean. These are regression tests over already-enforced behavior, so no new behavior RED exists; the mutation run is their discrimination evidence.
- **Checks:** focused regression set (`test_agency_wallets.py`, `test_agencies.py`, `test_reservation_chain_api.py`, `test_reservations.py`, `test_reservation_authorization.py`) — **126 passed**; full backend suite — **411 passed, 2 skipped, 4 warnings**; Ruff clean; Pyright **3 errors identical to the `main` baseline** (unresolved `eth_*` imports in the same files).
- **Rollback boundary:** delete the four added tests; no application code changed.
- **Runtime harness:** FastAPI TestClient with isolated SQLite fixtures; no external service.

- [ ] **F03-04 — Integrate role-aware session UX.** Integrate customer auth in the client app and staff access states in the panel/capture surfaces, including secure token handling, restoration, expiry, denial, network errors, and logout. The former F02 T4 overlap is cleared: F02 T4/T6 closed at `a047a71` and the shell is committed on the rebased base, so this task must extend those surfaces rather than rewrite them. Any error-shape change from F03-01 must be reflected here. **Current state:** the client-app slice is delivered in six chained commits (`f7ba2e4`, `696c1a4`, `3b447ac`, `9c25b61`, `389b91d`, `24ec48a`) after the user scoped this first unit to `apps/cliente_mobile` with `flutter_secure_storage` as the token backend, and the panel slice followed in two more (`e262524` session expiry plus failure classification, `88444a2` denied/retry/expiry UI and proactive renewal). Still open: any staff session state in `apps/captura_mobile`, which first needs a mobile cookie design decision because the staff API refreshes with an HttpOnly `roomforge_refresh` cookie plus an `x-csrf-token` header (`backend/app/modules/identity/router.py:534-539`) rather than a body token, and login requires a second TOTP step.

### F03-04 client-app evidence

- **Layers:** `lib/data/services/customer_token_store.dart` (Keychain/Keystore refresh-token store behind an interface), `lib/data/services/customer_auth_failure.dart` (shared code vocabulary plus status and envelope mapping), `lib/data/services/customer_auth_api.dart` (the five `/api/v1/customer/auth/*` calls), `lib/domain/customer_session_controller.dart` (restoration, login, registration without auto-login, logout, denial, and offline states), and `lib/ui/features/auth/views/customer_account_screen.dart` wired into the shell's Cuenta tab.
- **Token handling:** only the opaque refresh token is persisted, through `flutter_secure_storage`; access tokens stay in memory and are requested per call. The backend base URL comes from `ROOMFORGE_API_BASE_URL`, defaulting to `http://10.0.2.2:8000` for the Android emulator.
- **Error contract:** the client consumes the F03-01 shared envelope `{detail, code}`, keeps an unparsed body from reaching the UI, and distinguishes a retryable transport failure (`network_error`) from a rejected session.
- **Test evidence:** `flutter test` in `apps/cliente_mobile` — **50 passed** (token store, failure mapping, API client, session controller, account screen, plus the original 11 shell tests); `flutter analyze` reports no issues. Discrimination was proven by mutation: four lifecycle mutations (rejected token not cleared, offline token discarded, registration creating a session, offline logout clearing the session) and four credential mutations (refresh token not persisted, rejected credentials kept signed in, offline sign-in reported as signed out, registration creating a session) each made the new tests fail, with every file restored byte-identically.
- **Chained delivery:** the agreed four-unit plan needed two extra commits to stay under the 400-authored-line budget: the session controller was split into lifecycle (307 lines) and credential flows (111), and the account UI into the widget (372) and the shell wiring (68).
- **Panel slice:** `restoreStaffSessionOutcome` now distinguishes a resolved session from `signed-out`, `unavailable`, and `denied`; `decodeAccessTokenExpiry` reads the JWT `exp` claim and `renewalDelayMs` plans a proactive renewal 30 seconds before expiry; the shell renders an access-denied view for an unusable role, a retry view when the API is unreachable, an explicit expiry notice, and renews the session in the background. Verification: `npm test` in `panel/staff-shell` — **69 passed** (52 baseline + 17 new); `npx tsc --noEmit` clean. The panel suite had been unrunnable here only because `node_modules` was missing; `npm ci --offline` resolved it from the local cache. Three mutations (denied classification, transport classification, expired-token sign-out) each made the suite fail, with byte-identical restores. An untyped `Error` is treated as a rejected session, not a network outage, which is why the transport classifier checks `TypeError` specifically.
- **Not run:** `flutter build apk --debug`, device, and iOS checks; they need an Android toolchain and network fetches this slice did not authorize. The panel's `npm test` could not run because `panel/staff-shell/node_modules` is absent and installing it needs the network.

- [x] **F03-05 — Verify and close the authorized F03 slice.** Run focused and full applicable backend/panel/mobile checks, record skipped/unavailable PostgreSQL/device checks, and keep the public catalog criterion visibly pending for F04. **Current state:** closure verification recorded below; the public catalog criterion stays explicitly pending for F04.

### F03-05 verification record

- Backend, from `backend/`: `../../proyecto_final/.venv/Scripts/python.exe -m pytest tests -q` — **411 passed, 2 skipped, 4 warnings**; Ruff clean; Pyright shows only pre-existing diagnostics identical to `main`.
- Cliente mobile, from `apps/cliente_mobile/`: `flutter test` — **50 passed**; `flutter analyze` — no issues.
- Capture mobile, from `apps/captura_mobile/`: `flutter test` — **15 passed**; `flutter analyze` — no issues (regression check only; F03 did not change this app).
- Not run, with reasons: the panel suite (`npm test`) because `panel/staff-shell/node_modules` is missing and installing needs the network; PostgreSQL, Docker, and the real migration chain because this slice had no such authorization; device, iOS, and `flutter build apk --debug` because they need an Android toolchain and network fetches.
- The public catalog read API remains deferred to F04 and is **not** reported as satisfied.

## Open findings

- **Reservation and quote error envelopes diverge from the documented F02 contract.** `docs/api/f02-api-contract.md:6` documents a single envelope `{"detail", "code"}`, but `backend/app/main.py:74-85` returns `{"code", "message", "request_id", "field_errors"}` for `ReservationApiError`, and the quote handler follows the same reserved shape. This divergence exists in the delivered F02 base inherited from the `main` merge and is not fixed by F03: unifying it would touch reservations/catalog handlers, their schemas, many existing tests, and the clients built against that shape, so it needs its own authorized decision coordinated with F03-04. F03-01 fixed only the customer surface, which the approved contract required.

## Progress and next step

The F03 worktree is on branch `feat/f03-identity-agencies`, rebased onto `7973ffa` so it now contains `main` plus all of F02. It holds the ODD task document, agent-membership tests, and implementation in the approved agency/identity files; no schema migration was added by F03. The root checkout was not modified. The worktree has no local `.venv`; use the existing root-project tooling via `../../proyecto_final/.venv/Scripts/` from the F03 `backend/`, without modifying the environment.

F03-01, F03-02, and F03-03 are complete in local commits with no push: `a9614ba` and `0251015` (agent membership), `2cec63d` (rebase record), `703186e` (absolute refresh lifetime), `a5f20e1` (shared customer envelope), and `e53eb59` (denial coverage). F03-04's client-app slice adds six more: `f7ba2e4`, `696c1a4`, `3b447ac`, `9c25b61`, `389b91d`, and `24ec48a`.

F03-04 still owes the staff session in `apps/captura_mobile`; the panel refinements were delivered in `e262524` and `88444a2`. The open reservation/quote envelope finding still needs its own authorized decision. F03-05 recorded the closure checks and keeps the public catalog criterion marked pending for F04.

## Closure record

The branch was frozen for handover at `4bd4ba1` with 16 commits, none pushed, and a clean worktree. Verification on that exact revision: backend **411 passed, 2 skipped, 4 warnings** with Ruff clean and Pyright unchanged from the `main` baseline (33 pre-existing diagnostics, identical normalized set); panel **69 passed** with `tsc --noEmit` clean; `apps/cliente_mobile` **50 passed** with `flutter analyze` clean; `apps/captura_mobile` **15 passed** with `flutter analyze` clean (untouched by F03; regression check only). Not run, with reasons: PostgreSQL, Docker and the real migration chain; the panel e2e suite, which needs a PostgreSQL container; device and iOS checks; and `flutter build apk --debug`. The capture-app work that followed touched only `apps/captura_mobile` and `docs/api/f02-api-contract.md` (verified with `git diff --name-only`), so the backend, panel, and client numbers above still describe the current revision; the capture app now reports **41 passed** with `flutter analyze` clean.

Two decisions remain in this record, one now implemented at the layer level and one resolved by documentation:

1. **Staff session in `apps/captura_mobile`.** The staff API is browser-shaped: `/api/v1/auth/refresh` reads the HttpOnly `roomforge_refresh` cookie and requires an `x-csrf-token` header (`backend/app/modules/identity/router.py:534-539`), and login needs a second TOTP step. **Delivered as the chosen design** in five commits: `aa31c31` (failure vocabulary and HTTP dependencies), `7648e80` (two-step login client), `1686e52` (refresh, logout, and `/me` over the cookie plus CSRF token), `e1bd2f3` (credential store and session restoration/revocation), and `43aab98` (two-step login flow). The client captures the refresh value from the `set-cookie` header of the TOTP-login response, persists only that value plus the CSRF token through `flutter_secure_storage`, and sends them back as `Cookie` and `x-csrf-token` on refresh and logout; the backend was not changed. **UI wired in a sixth commit, `6f4f81d`:** `AgentAccessScreen` now drives the controller through credentials → TOTP code → private drafts, with a restoration state, an offline retry, a signed-in identity view, and logout; the capture widget tests were migrated from prototype-only access to the real flow (including rejected credentials and session restoration). The capture app reports **45 passed** with `flutter analyze` clean, so F03-04 is complete on all three surfaces.
2. **Reservation and quote error envelopes — resolved by documentation.** `docs/api/f02-api-contract.md` now declares the reserved `{code, message, request_id, field_errors}` shape for `/api/v1/quotes`, `/api/v1/reservations`, and `/api/v1/staff/reservations` as a deliberate decision, and records that unifying both envelopes requires its own unit coordinated with the mobile clients. No handler, schema, test, or client changed.

The public catalog read API remains deferred to F04 and is not reported as satisfied.

### Delivery outcome

Everything above was written while the work was still local. What actually happened afterwards:

- F02 reached `main` through PRs #6-#9, so F03 was no longer stacked. `origin/main` had advanced nine maintenance commits beyond the original base: Alembic revision renames, the inherited Pyright fixes, the PostgreSQL R6 verification, and the panel E2E record.
- `origin/main` was merged into `feat/f03-identity-agencies` with **no conflicts**. The only overlapping files (`backend/tests/test_customer_identity.py`, `backend/tests/test_catalog.py`) auto-merged, and the merged tree passed backend **414 passed, 2 skipped** with Ruff clean.
- The branch was pushed and delivered as **PR #10**, whose four required checks passed (backend, panel, customer app, capture app). The first CI run failed on `dart format --set-exit-if-changed` for eight capture-app files that F03 had added without formatting them; commit `31d92f2` applied the formatter to exactly those files and the rerun was green.
- PR #10 merged into `main` as the merge commit `b791340`. `main` requires one approving review and the pull request belonged to the repository owner, so the merge used the administrator override with the owner's explicit authorization: the required review was **not** obtained and the merge is recorded as an administrator action.
- `main` now holds exactly the CI-verified tree (empty diff against `31d92f2`). The remote branch `feat/f03-identity-agencies` and the dedicated worktree were deleted afterwards, once both were confirmed fully contained in `main`.
- Still true: the public catalog read API is deferred to F04 and is not reported as satisfied.

## Nota posterior (2026-10-01): acceso de la app de captura contra la API real

Lo registrado arriba como completo para `apps/captura_mobile` se verificó solo contra `test/support/fake_staff_backend.dart`. Contra la API real, `login/totp`, `refresh` y `logout` respondían `403 Origin is not allowed` porque la app, como cliente nativo, no envía `Origin`, y el controlador descartaba el token de acceso tras el login. Ambos defectos se corrigen en `odd/tasks/f03-capture-staff-origin.md`; este registro no se reescribe.

## Nota posterior (2026-10-03): cierre de F03.3 con PR #12

El límite registrado arriba («the public catalog read API remains deferred to F04») quedó resuelto con la integración de `feat/f04-listings-completion` como PR #12 (merge `6541b1a`): la tarea F04C-T6 de `odd/tasks/f04-listings-completion.md` verificó el aislamiento entre agencias de F03.3 sobre las 9 rutas de inmueble — otra agencia y `platform_admin` `403`, ID ajeno en la ruta propia `404` idéntico a inexistente, sesión real requerida `401` y catálogo público transversal — con la matriz por actor en `docs/api/f04-publications-v1.md` y la suite backend en 506 aprobadas / 3 omitidas, Ruff y Pyright limpios. El plan maestro (§1.4.1 y sección F03) marca F03.3 ✅ y la fase F03 ✅ Completa con ese registro como evidencia. Este registro no se reescribe.
