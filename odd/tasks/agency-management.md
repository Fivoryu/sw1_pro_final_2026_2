# Agency Management — ODD Execution Record

## Authorization and constraints

- The user authorized proceeding without an issue; the PR will not link an issue and will be reviewed/accepted by another person.
- The user confirmed `tenant_id` is the agency identifier, chose an ID-only agency (no name or additional agency fields), and selected `platform_admin` as the only actor for agency create/list/detail operations.
- The user authorized exactly this out-of-scope planning-file exception: `odd/tasks/agency-management.md`, plus its Engram mirror. All product code and tests must remain under `backend/**`; do not edit `panel/**` or the primary checkout.
- Worktree: `D:/Universidad/Proyectos/2doSemestre2026/sw1/roomforge-agency-management`
- Branch: `feat/agency-management`
- Base: refreshed `origin/main`, commit `848f28ce204295d88bac7f517de6536c5ef08721` at worktree creation.
- Do not merge, push to `main`, force-push, or clean/modify the primary checkout. Open a PR to `main`, do not link an issue, and ensure exactly one `type:*` label. Stop and ask if the required PR template is absent. Another person owns PR acceptance.

## Confirmed scope

- Add an Agency persistence entity whose identifier is compatible with the existing string `tenant_id` values.
- Preserve existing non-null tenant identifiers by backfilling distinct values from staff accounts and invitations before adding foreign-key constraints.
- Relate staff accounts and invitations to Agency; retain the existing platform-admin/null-tenant rule and agency-role/non-null-tenant rule.
- Add platform-admin-only `POST /api/v1/agencies`, `GET /api/v1/agencies`, and `GET /api/v1/agencies/{agency_id}` operations. Agency payloads contain only the ID.
- Working API contract for implementation and verification: POST request `{"id":"<tenant-id>"}` returns `201 {"id":"<tenant-id>"}`; collection returns `200 {"agencies":[{"id":"..."}]}` with no pagination in this first cut; detail returns `200 {"id":"..."}`. Expected errors: `401` without a valid active session, `403` for another role, `404` for a missing detail ID, `409` for a duplicate ID, and `422` for invalid payload. Share only the tested contract with the panel session.
- Keep update/delete, agency names, staff membership management, and agent invitations out of scope.

## Acceptance criteria

1. Agency IDs are persisted and unique, and every existing non-null account/invitation tenant ID is represented before referential constraints are applied.
2. Account/invitation tenant IDs reference valid agencies; platform-admin null-tenant behavior and existing role constraints remain intact.
3. Only an authenticated active `platform_admin` can create, list, or retrieve agencies; other roles and unauthenticated requests are denied.
4. The three routes expose only the agency ID and match the working request/response contract; expected status codes are 201/200 for success and 401/403/404/409/422 for the documented error cases.
5. Tests cover migration/backfill, referential integrity, allowed/denied roles, missing and duplicate agencies, and existing identity/authentication regressions.

## TDD and verification

- TDD mode: strict, explicitly selected by the user for this feature.
- TDD evidence per task: observe RED, implement to GREEN, TRIANGULATE with relevant edge cases, then REFACTOR while keeping tests green.
- Runner source: root `AGENTS.md` project guidance (its backend commands run from `backend/`); no `backend/AGENTS.md` exists in this worktree.
- Focused runner from the isolated worktree's `backend/` directory: `D:/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -m pytest <test-paths> -q`.
- Full runner from the isolated worktree's `backend/` directory: `D:/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -m pytest tests -q`.
- Also run the backend-prescribed Ruff and Pyright checks before PR. The shared virtual environment is used read-only; commands run with the isolated worktree's `backend/` as cwd.
- AGENCY-1 RED: the focused suite reported 5 failures and 2 errors (missing Agency metadata/foreign keys and migration); 34 passed, 1 skipped.
- AGENCY-1 GREEN and post-refactor: 41 passed, 1 skipped, 1 warning. Five targeted migration/schema cases passed. The optional PostgreSQL R6 test was skipped because `ROOMFORGE_R6_DATABASE_URL` was unset; SQLite migration and FK enforcement were exercised.
- `gentle_review assess` returned `risk=unassessable` because untracked files require explicit declaration. Its plan required independent verification; the separate read-only verifier completed with no merge-blocking findings. RDD remains off; no native review was started.
- Independent verifier reran the focused command: 41 passed, 1 skipped, 1 warning. SQLite migration/backfill/FK behavior was judged sound; actual PostgreSQL migration parity remains unverified because `ROOMFORGE_R6_DATABASE_URL` is unset.
- Runtime harness: in-process SQLite migration tests; no external service is required for AGENCY-1. Record the exact command and result per work unit.

## Work units

| ID | Task | Route | State | Verification / commit evidence |
| --- | --- | --- | --- | --- |
| AGENCY-1 | Add Agency persistence, tenant-ID backfill, foreign keys, and schema/migration regression tests. | Delegated direct: one bounded `gentle-ai-worker`; multi-file write trigger. | In progress — writer and independent verification complete; commit pending. | Focused pytest: 41 passed, 1 skipped, 1 warning; verifier found no blockers. Commit `feat(identity): add persisted agency registry` pending. |
| AGENCY-2 | Add platform-admin-only agency create/list/detail API and authorization/contract tests. | Delegated direct: one bounded `gentle-ai-worker`; multi-file write trigger. | Pending | Focused pytest; conventional commit TBD. |
| AGENCY-3 | Run full backend pytest, Ruff, and Pyright; inspect required PR template and open the PR to `main` with exactly one `type:*` label. | Delegated verification, then parent delivery. | Pending | Record exact outcomes and PR URL; never merge. |

## Review workload and delivery

- Estimated authored change: approximately 250–400 lines; re-evaluate from work-unit commits.
- Delivery strategy: `ask-on-risk` (default); keep one PR if the measured authored diff remains within the review budget, otherwise ask before changing to a chain strategy.
- Native review switch is off for this clone; do not start a native review. Follow the required read-only risk assessment after each work-unit commit and its returned verification plan.
- Rollback boundaries: AGENCY-1 is the agency table, tenant foreign keys/backfill migration, and its tests; AGENCY-2 is the agency router/schemas/wiring and its tests. Revert only the corresponding work-unit commit when rollback is needed.
