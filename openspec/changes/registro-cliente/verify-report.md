# Verification report — registro-cliente (PB-001 backend slice)

## Status

**BLOCKED / FAIL for clean verification.** The focused implementation behavior is largely green, but verification cannot be clean because:

- Native SDD status is blocked by `maintainer_decision` for the runtime attempt/changed-line budget.
- Strict TDD is active and the persisted evidence is incomplete: the `TDD Cycle Evidence` table covers only T1–T3; T4–T5 evidence is prose outside the required table.
- The repository maps a PostgreSQL `23505` error with no constraint name to the duplicate-email response, so an unrelated unique violation can incorrectly become HTTP 409.

## Executive summary by requirement

| Requirement | Result | Evidence and finding |
| --- | --- | --- |
| REQ-01 — `POST /api/v1/auth/registro`, 201/422/409 contract | **PASS** | Route and response mapping are present in `backend/app/modules/identity/router.py:33-50`; request/response schemas are in `backend/app/modules/identity/schemas.py:7-19`; tests pass for valid, invalid, duplicate, and sanitized responses (`backend/tests/test_registro.py:86-155,184-205`). However, `backend/app/modules/identity/repository.py:46-54` accepts any SQLSTATE `23505` when `constraint_name` is `None`, allowing unrelated unique violations to become the email-duplicate 409. This conflicts with the design/task rule that only the email uniqueness violation maps to 409.
| REQ-02 — lowercase normalization and case-insensitive uniqueness | **PASS** | Service applies `strip().lower()` before lookup and persistence at `backend/app/modules/identity/service.py:29-41`; the model declares the named unique constraint at `backend/app/modules/identity/models.py:11-13`; uppercase duplicate behavior passes at `backend/tests/test_registro.py:137-155`. The code covers surrounding-space normalization, although the executed test uses the uppercase variant without spaces.
| REQ-03 — minimum eight-character test-mode password policy | **PASS** | `SecretStr` with `min_length=8` at `backend/app/modules/identity/schemas.py:7-9`; the service passes `get_secret_value()` unchanged to the hasher at `backend/app/modules/identity/service.py:34`; valid lowercase password and short-password tests pass at `backend/tests/test_registro.py:86-135`.
| REQ-04 — Argon2id, no plaintext/hash exposure | **PASS** | `Type.ID` is configured at `backend/app/core/security.py:1-8`; the service persists only `hash_password` at `backend/app/modules/identity/service.py:34-41`; the public schema excludes both sensitive fields at `backend/app/modules/identity/schemas.py:12-19`; Argon2id verification and response sanitization pass at `backend/tests/test_registro.py:158-205`. No application logging calls were found in the changed backend flow.
| REQ-05 — `usuario_global` persistence and initial Alembic migration | **NOT VERIFIED** | The model and migration statically match the requested UUID, fields, defaults, and unique constraint (`backend/app/modules/identity/models.py:11-36`; `backend/alembic/versions/0001_crear_usuario_global.py:15-59`). The revision creates only `usuario_global` and its downgrade drops only that table. Per instruction, no `alembic upgrade` or live PostgreSQL execution was run; DB execution remains **NOT VERIFIED (GAP-092)**.
| REQ-06 — modular `identity` structure and environment configuration | **PASS** | The required `router.py`, `schemas.py`, `service.py`, `repository.py`, and `models.py` are present. Router registration is at `backend/app/main.py:23-36`; environment-backed settings are at `backend/app/core/config.py:7-35`; Argon2 parameters are injected into the factory at `backend/app/core/security.py:6-8`; the session uses environment `DATABASE_URL` and closes in `finally` at `backend/app/db/session.py:13-34`. No hardcoded connection URL or sensitive parameter values were found by the targeted backend grep.
| REQ-07 — pytest, six or more reproducible cases, no PostgreSQL | **PASS** | Development dependencies include `httpx`, `pytest`, and `ruff` at `backend/pyproject.toml:21-25`. Seven cases exist in `backend/tests/test_registro.py:86-222`, using repository/session doubles and an in-process TestClient; all passed without PostgreSQL. The task text names a `tests/unit/modules/identity/` layout, but the implementation consolidates the coverage in `backend/tests/test_registro.py`; this is reported as a workload/layout warning, not an untested behavior.

## HU-001 acceptance traceability

| HU-001 criterion | Result | Evidence |
| --- | --- | --- |
| CA1 — valid email, minimum eight-character password, no verification required | **PASS** | `backend/tests/test_registro.py:86-103`; request schema at `backend/app/modules/identity/schemas.py:7-9`; no verification flow is invoked by the router/service.
| CA2 — account active and `correo_verificado=false` | **PASS** | Service defaults at `backend/app/modules/identity/service.py:35-40`; assertions at `backend/tests/test_registro.py:97-102`.
| CA3 — duplicate rejected with clear message | **PASS for covered path** | Duplicate behavior and exact message at `backend/tests/test_registro.py:137-155`; race/rollback path at `207-222`. The unrelated-`23505` mapping defect remains a REQ-01 blocker.
| CA4 — Argon2id and no plaintext exposure | **PASS** | Argon2id hash/verification at `backend/tests/test_registro.py:158-181`; public responses at `184-205`; response schema at `backend/app/modules/identity/schemas.py:12-19`.

## Task completion

- `tasks.md` has T1, T2, T3, T4, and T5 checked `[x]`.
- **No unchecked implementation task lines remain in `openspec/changes/registro-cliente/tasks.md`.**
- The two unchecked lines are explicitly parent-owned lifecycle actions, not implementation tasks:
  - `- [ ] Start or reuse bounded review del slice implementado (contraste con spec REQ-01..07 y design: criterios de terminado de T1..T5, ausencia de datos sensibles en respuestas, cobertura REQ-07). <!-- sdd-owner: parent -->`
  - `- [ ] Gate de entrega: consultar al usuario la estrategia de commits/PRs (hoy prohibidos hasta aviso) y resolver la chain strategy pendiente antes de cualquier operación git. <!-- sdd-owner: parent -->`
- **WARNING:** `apply-progress.md` contains a stale historical copy of unchecked T4/T5 implementation rows at lines 86–87, despite later stating that T4/T5 are complete and despite `tasks.md` being checked. Reconcile this contradictory progress copy before archive.

## Structured status and action context

- `schemaName`: `gentle-ai.sdd-status`
- `changeName`: `registro-cliente`
- `artifactStore`: `openspec` (authoritative)
- `planningHome`: repo-local `openspec`
- Artifacts available: proposal, spec, design, tasks, and apply-progress. Verify report was missing before this report.
- Native `nextRecommended`: `resolve-blockers`
- Native blocker: runtime execution for `registro-cliente` is blocked by `maintainer_decision`; the attempt/changed-line budget requires maintainer resolution.
- `actionContext.mode`: `repo-local`
- `workspaceRoot`: `D:\Universidad\Proyectos\2doSemestre2026\sw1\proyecto_final`
- `allowedEditRoots`: repository root above; verification report is inside the authorized root.
- No workspace-planning edit-root restriction applies.
- `openspec/config.yaml` was not present. Strict TDD was nevertheless active from the phase contract and apply-progress evidence.

## Validation commands

### Required pytest command

Command executed exactly:

```text
.venv/Scripts/python -m pytest backend/tests -v
```

Raw output tail:

```text
backend\tests\test_registro.py::test_registro_valido_responde_201_y_normaliza_correo PASSED [ 14%]
backend\tests\test_registro.py::test_correo_invalido_responde_422_sin_crear_cuenta PASSED [ 28%]
backend\tests\test_registro.py::test_password_corta_responde_422_y_no_llama_al_hasher PASSED [ 42%]
backend\tests\test_registro.py::test_duplicado_con_mayusculas_responde_409_con_mensaje_exacto PASSED [ 57%]
backend\tests\test_registro.py::test_hash_argon2id_es_verificable_y_no_es_plano PASSED [ 71%]
backend\tests\test_registro.py::test_respuestas_no_exponen_hash_ni_password PASSED [ 85%]
backend\tests\test_registro.py::test_carrera_de_unicidad_hace_rollback_y_responde_409 PASSED [100%]

======================== 7 passed, 1 warning in 2.88s =========================
```

Warning:

```text
StarletteDeprecationWarning: Using `httpx` with `starlette.testclient` is deprecated; install `httpx2` instead.
```

### Required Ruff command

Command executed exactly:

```text
.venv/Scripts/python -m ruff check backend/app backend/tests
```

Raw output:

```text
All checks passed!
```

No Alembic upgrade was run. The migration result is therefore code-verified only; live DB execution is not verified.

## Strict TDD compliance

Strict TDD is active for this verification.

| Check | Result | Details |
| --- | --- | --- |
| TDD evidence table present | **PASS** | `openspec/changes/registro-cliente/apply-progress.md:23-29` contains a `TDD Cycle Evidence` table.
| Evidence complete for all implementation tasks | **FAIL — CRITICAL** | The table has rows only for T1–T3. T4 and T5 are documented later in prose at `apply-progress.md:120-132`, not as table rows. The required evidence is therefore incomplete.
| T4 test file exists | **PASS** | `backend/tests/test_registro.py` exists and contains seven cases.
| GREEN remains true | **PASS** | The required full suite passed 7/7 in this verification.
| Triangulation | **PASS** | The seven cases cover valid registration, invalid email, short password, duplicate normalization, Argon2id verification, public response sanitization, and `23505` rollback.
| Safety-net evidence | **NOT VERIFIED** | The persisted table has no SAFETY NET column/evidence for the implementation tasks.

**TDD conclusion:** **CRITICAL incomplete evidence**. Do not claim strict-TDD compliance until T4/T5 evidence is reconciled into the required table format and the safety-net evidence is accounted for.

### Test-layer distribution

- In-process API/component tests: 7 tests in 1 file, using FastAPI TestClient plus repository/session doubles.
- External integration tests: 0.
- E2E tests: 0.
- PostgreSQL dependency: none for the executed suite.
- Coverage analysis: skipped; no coverage tool was available in the declared development dependencies.

### Assertion quality

**All assertions reviewed are behavior-oriented; no CRITICAL or WARNING assertion-quality violations found.** There are no tautologies, empty ghost loops, type-only-only assertions, smoke-only tests, or CSS/internal-state assertions. The response loop iterates over three explicitly created responses, so it is not a ghost loop. The rollback call-count assertion is tied to the required transactional rollback behavior.

## Review workload and PR boundary

- Task forecast: chained PRs recommended; suggested split was T1 → T2 → T3 → T4+T5.
- Apply-progress records the current boundary as slice 4 of 4 on `feat/registro-cliente/t4-tests` with `stacked-to-main`.
- The implementation slice contains the expected T4 test file and T5 documentation paragraph. The T5 paragraph is present at `docs/scrum/sprint-1/02-proceso-por-hu.md:175` and preserves CP-001..CP-013 as not executed and GAP-087/GAP-073/GAP-088.
- **WARNING:** HEAD also contains `backend/pyrightconfig.json` from `848e015 (chore(backend): add pyright config and root venv convention)`, which is outside the T4/T5 task target list. Review should decide whether to retain this extra change in the slice.
- **BLOCKER:** apply-progress records the final candidate at 1007 changed lines against a 950-line acquired budget, with settle blocked as `maintainer_decision`. No automatic reset was performed.
- No code, commit, push, or Alembic execution was performed by this verification phase.

## Exact blockers and remaining gaps

1. **CRITICAL — strict-TDD evidence incomplete:** TDD table omits T4/T5 and has no safety-net evidence.
2. **CRITICAL — duplicate error classification:** `backend/app/modules/identity/repository.py:46-54` treats a nameless `23505` as an email duplicate; unrelated unique violations must propagate instead of returning HTTP 409.
3. **BLOCKED — native runtime budget:** maintainer decision required for the recorded 1007-vs-950 changed-line budget.
4. **NOT VERIFIED — live PostgreSQL migration execution:** no local PostgreSQL; GAP-092 remains open.
5. **WARNING — stale apply-progress checkboxes:** historical unchecked T4/T5 rows conflict with the completed task state.
6. **WARNING — T4 layout/scope:** task text names split unit test files under `tests/unit/modules/identity`, while the implementation uses one consolidated `backend/tests/test_registro.py`; behavior is covered, but the planned file boundary was not followed.
7. **SUGGESTION — test dependency warning:** address the Starlette/httpx deprecation warning in a future dependency maintenance change.

## Resolución del blocker REQ-01 (2026-08-23)

- `_is_duplicate_email_error` ahora exige `constraint_name` `uq_usuario_global_correo` (o alias postgres) y re-lanza cualquier otro 23505 (commits `128cf34`, `404fd97`).
- Regresión agregada: `test_violacion_unica_ajena_no_se_clasifica_como_duplicado` (pytest: 8 passed; ruff: clean).
- REQ-01 → PASS; REQ-05 (migración) sigue NOT VERIFIED hasta ejecución sobre PostgreSQL (GAP-092).
