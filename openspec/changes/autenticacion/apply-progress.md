# Apply progress — autenticacion

## Estado

- Fase: `sdd-apply`
- Cambio: `autenticacion` (PB-002 / HU-002)
- Artifact store solicitado: `hybrid`; `openspec` es la autoridad local de tasks y apply-progress.
- Estado estructurado consumido: `applyState: ready`, `nextRecommended: apply`, `blockedReasons: []`, `actionContext.mode: repo-local`, `allowedEditRoots: [workspace root]`.
- Runtime attempt authority: intento 1 activo, work unit `sdd-apply T1-T5 backend auth slice`, presupuesto nativo 3 intentos / 1650 líneas; se continuó el intento existente reportado por `gentle-ai sdd-status`.
- Delivery: `auto-chain`, `stacked-to-main`; PRs/push no ejecutados por responsabilidad del parent.
- Rama actual: `feat/autenticacion/t1-core`.

## TDD Cycle Evidence

| Unidad | RED | GREEN | TRIANGULATE | REFACTOR |
| --- | --- | --- | --- | --- |
| T1 — núcleo de tokens | `pytest -q tests/test_tokens_core.py` falló en colección con `ModuleNotFoundError: No module named 'jwt'` antes de implementar el núcleo. | Después de agregar PyJWT, settings, clock y servicio de tokens: `4 passed`. | Pendiente de completar con la suite acumulada y revisión de casos de configuración/seguridad. | Ruff aplicado al núcleo; pendiente cierre de la unidad tras verificación y commit. |

## T1 completado

- Checkbox persistido: `openspec/changes/autenticacion/tasks.md` T1 marcado `[x]`.
- Implementado:
  - `backend/app/core/config.py`: secreto JWT fail-closed y TTLs configurables.
  - `backend/app/core/clock.py`: `ClockProtocol` y `SystemClock` UTC aware.
  - `backend/app/core/tokens.py`: PyJWT HS256, claims `sub/sid/type/iat/exp`, verificación contra clock inyectado, refresh opaco y SHA-256.
  - `backend/app/core/security.py`: verificación Argon2id uniforme con hash ficticio, reutilizando el adaptador existente.
  - `backend/.env.example`: placeholders no operativos.
  - `backend/pyproject.toml`: dependencia `PyJWT>=2.8,<3`.
  - `backend/tests/test_tokens_core.py`: pruebas de firma, claims, TTL, rechazo y hash.
- Dependencia instalada únicamente en el venv del proyecto con `uv pip install --python .venv/Scripts/python.exe PyJWT>=2.8,<3` (`PyJWT 2.13.0`); no se instaló PostgreSQL.

## Verificación acumulada

- Ejecutado: `cd backend && .venv/Scripts/python.exe -m pytest -q tests/test_tokens_core.py` → `4 passed`.
- Ejecutado: `cd backend && .venv/Scripts/python.exe -m ruff check app/core tests/test_tokens_core.py` → verde después de autofix de imports.
- La suite completa y las verificaciones de migración quedan para T2–T5.

## Archivos y cambios

- Código/test/configuración modificados según T1 arriba.
- `0001_crear_usuario_global.py`, `docs/diagramas/Diagrama1.eapx` y el archivo no relacionado `nul` no fueron modificados por esta unidad.

## Pendiente

- T2, T3, T4 y T5 siguen sin completar.
- Acciones parent-owned permanecen diferidas byte-for-byte: bounded review y gates/PR chain.
- No se ejecutaron PRs, push ni gates de entrega.

## Desviaciones y riesgos

- El `sdd-status` nativo reportó `artifactStore: openspec` aunque el contexto de fase solicita `hybrid`; se usó OpenSpec como fuente autoritativa y se debe persistir también el espejo Engram al cierre si el backend vuelve a estar disponible.
- El servidor Engram no respondió durante la lectura (`127.0.0.1:7437`); no se afirma persistencia Engram en este punto.
- La migración real y PostgreSQL permanecen fuera de alcance; se verificará offline como exige GAP-092.

## T2 completado

- Checkbox persistido: `openspec/changes/autenticacion/tasks.md` T2 marcado `[x]`.
- Implementado:
  - `backend/app/modules/identity/models.py`: modelo `Sesion` con UUID PK, FK, CHAR(64), timestamps, revocación, UNIQUE e índice nombrados.
  - `backend/alembic/versions/0002_crear_sesion.py`: revisión `0002`, `down_revision="0001"`, upgrade/downgrade únicamente de `sesion`.
  - `backend/alembic/env.py`: imports explícitos de `UsuarioGlobal` y `Sesion` antes de `Base.metadata`.
- Verificación de migración offline:
  - `DATABASE_URL=postgresql+psycopg://user:pass@localhost/db python -m alembic upgrade head --sql` mostró `CREATE TABLE usuario_global`, `CREATE TABLE sesion`, FK, `uq_sesion_refresh_token_hash` e `ix_sesion_usuario_global_revocado`; no se ejecutó contra PostgreSQL.
  - `python -m alembic downgrade 0002:0001 --sql` mostró `DROP INDEX ix_sesion_usuario_global_revocado` y `DROP TABLE sesion`; `usuario_global` no se elimina.
  - La forma literal `downgrade 0001 --sql` no es aceptada por Alembic offline (requiere rango `0002:0001`); se usó la forma equivalente válida.
- `ruff check app alembic` → verde.

## Ramas y commits

- T1: `feat/autenticacion/t1-core`, commit `5d2a94d feat(auth): add JWT token core`.
- T2 actual: `feat/autenticacion/t2-sesion`; commit pendiente después de la verificación acumulada.

## T3 completado

- Checkbox persistido: `openspec/changes/autenticacion/tasks.md` T3 marcado `[x]`.
- TDD RED: `pytest -q tests/test_session_repository.py` falló en colección porque aún no existía `FakeSessionRepository`.
- TDD GREEN: implementados el protocolo, adaptador SQLAlchemy y fake; `pytest -q tests/test_session_repository.py` → `5 passed`.
- Implementado en `backend/app/modules/identity/repository.py`:
  - `UserRepository.buscar_por_id` para el vínculo de identidad.
  - `SessionRepositoryProtocol` y `SessionRepository` con búsqueda por hash/ID, `SELECT ... FOR UPDATE`, rotación atómica, rollback ante `IntegrityError`, validación de expiración/inactividad y revocación idempotente.
  - `FakeSessionRepository` con `RLock`, hash-only storage, rotación single-writer observable y revocación lazy por inactividad.
  - `sesion_valida` como regla de dominio compartida.
- Verificación acumulada: `pytest tests -q` → `17 passed`; `ruff check app tests` → verde; `pyright app tests` → `0 errors`.
- Ajuste TDD: el caso de actividad se hizo temporalmente coherente (29 minutos actualiza la marca y la comprobación posterior de inactividad usa 61 minutos desde el origen).

## Ramas y commits

- T1: `feat/autenticacion/t1-core`, commit `5d2a94d feat(auth): add JWT token core`.
- T2: `feat/autenticacion/t2-sesion`, commit `fc71daf feat(auth): add session persistence migration`.
- T3: `feat/autenticacion/t3-repository`, commit `e6a6ecd feat(auth): add session repositories`.

## Corrective rerun — T4/T5 blocked by contract conflict

- Structured status consumed from native `gentle-ai sdd-status autenticacion --cwd . --json --instructions`: `artifactStore: openspec`, `applyState: ready`, `nextRecommended: apply`, `blockedReasons: []`, `actionContext.mode: repo-local`, and `allowedEditRoots` contains the workspace root. The status also reported the active native attempt token, which was continued with `sdd-attempt acquire` before runtime work.
- Current branch verified as `feat/autenticacion/t4-endpoints`; no checkout, push, PR, or commit was performed in this rerun. T1/T2/T3 remain complete at commits `5d2a94d`, `fc71daf`, and `e6a6ecd`. The unrelated pre-existing modification to `docs/diagramas/Diagrama1.eapx` was left untouched.
- Safety-net/full-suite evidence: `.venv/Scripts/python.exe -m pytest backend/tests -q` → `25 passed, 1 failed`; the only failure is `test_me_returns_minimal_identity_and_updates_activity` (`401 == 200`). Focused execution produced the same result (`8 passed, 1 failed`).
- Proven diagnosis: login emits an access JWT with the configured 900-second (15-minute) expiration. The test advances the injected clock by 29 minutes and then reuses that same access token. `AuthenticationService.me` correctly passes the injected time to `decodificar_access`, so the token is expired before server-side session validation and the route correctly returns `401`. This is not a dependency or route-wiring failure.
- T4/T5 were not marked complete because making this test return `200` would require either accepting an expired access JWT, extending the access TTL beyond the spec/design's 15 minutes, or changing the test flow to refresh/use a new access token before `/auth/me`. The first two options violate REQ-03/REQ-08 and T5's required expired-access case; the last option changes the explicitly protected test. A maintainer/product decision is required before implementation can continue.
- Additional checks on the preserved partial work: Ruff currently reports three E501 violations in `backend/tests/test_autenticacion.py`; the root-invoked pyright reports missing `argon2` imports (the prescribed backend working-directory invocation remains to be run after the decision). No task checkbox was changed in this blocked rerun; persisted tasks remain T1/T2/T3 `[x]` and T4/T5 `[ ]`, with parent-owned rows deferred unchanged.

### Remaining implementation tasks

- [ ] T4 Implement the authentication endpoints and `get_current_user` semantics after resolving the 15-minute access-token versus 29-minute `/me` scenario.
- [ ] T5 Complete the contract suite and §2.1.4 implementation paragraph after T4 is resolved.

### Workload / PR boundary

- Parent-resolved delivery path: `auto-chain`, `stacked-to-main`; assigned work-unit boundary is T4/T5 on the existing `feat/autenticacion/t4-endpoints` branch. No parent-owned bounded review, delivery gate, branch creation, push, or PR action was started.

### TDD Cycle Evidence — corrective rerun

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T4 corrective diagnosis | `backend/tests/test_autenticacion.py` | Integration/API | `25 passed, 1 failed` (known preserved failure) | Existing 29-minute `/me` scenario fails with 401 | Not reached: acceptance conflicts with 15-minute JWT contract | Not reached | Not reached |
| T5 | `backend/tests/test_autenticacion.py` | Integration/API | Blocked by T4 | Not started | Not started | Not started | Not started |

## Phase result

- Status: `blocked` pending resolution of the contradictory acceptance scenario.
- Action-context warning: none; all intended edit targets are under the authorized workspace root. Review and delivery lifecycle actions remain parent-owned and were not started.

## RESOLVED — conflicto del test de actividad (decisión del orquestador)

- **Decisión:** se preserva el contrato de access JWT de 15 minutos (REQ-03/REQ-08) y la ventana de inactividad deslizante de 30 min (RNF-006). El escenario de CP-002 paso 3 ("actividad autenticada antes de 30 min mantiene la sesión") se modela como lo hace un cliente real: renovación por `refresh` dentro de la ventana y luego `/me` con el access nuevo (20 min → refresh → +9 min → /me 200). La alternativa de subir el TTL del access o aceptar un access expirado viola la spec y fue descartada.
- **Fix aplicado:** `backend/tests/test_autenticacion.py::test_me_returns_minimal_identity_and_updates_activity` — reutilizaba un access de 15 min a los 29 min (401 legítimo por expiración); ahora refresca a los 20 min y valida `/me` a los 29 min (sesión activa, `ultima_actividad` actualizada en la fila no revocada).
- **Evidencia final:** `pytest tests -q` → **26 passed**; `ruff check app tests` → **All checks passed!**; `pyright app tests` → **0 errors** (rápidos del LSP stale descartados; pyright CLI autoritativo).
- **Commits T4/T5 (rama `feat/autenticacion/t4-endpoints`):** `2df56f2 feat(auth): add login refresh logout me endpoints`; `e6c3b4b docs(scrum): note PB-002 backend implementation`.
- **Archivos T4/T5:** backend/app/main.py, backend/app/modules/identity/ (router/schemas/service), backend/tests/test_autenticacion.py (9 casos), docs/scrum/sprint-1/02-proceso-por-hu.md §2.1.4 (párrafo PB-002).
- **Pendiente parent-owned:** revisión bounded del slice (row 90) y gate de entrega chain stacked-to-main (row 91).
