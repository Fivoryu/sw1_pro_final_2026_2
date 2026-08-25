# Informe de sync — `autenticacion`

- **Cambio:** `autenticacion`
- **Product Backlog:** PB-002 · **Historia:** HU-002 — Iniciar sesión y mantener sesión · **Caso de uso:** CU-002 · **Dominio:** `identity`
- **Slice:** backend (la pantalla de login de la app cliente es slice posterior del mismo PB-002)
- **Fecha de sync:** 2026-08-23
- **Estado del sync:** **SYNC PASS (report-only)** — verificación limpia; merge canónico **N/A** en este proyecto (ver §5).
- **El cambio permanece ACTIVO** — esta fase no mueve `openspec/changes/autenticacion/` a archive ni ejecuta gates parent-owned.

---

## 1. Resumen del cambio

El slice backend de PB-002 implementa autenticación y sesión del cliente sobre la cuenta global de PB-001: `POST /api/v1/auth/login` (200/401/422 con error genérico no enumerativo), `POST /api/v1/auth/refresh` (rotación atómica con `SELECT ... FOR UPDATE`), `POST /api/v1/auth/logout` (204 idempotente) y `GET /api/v1/auth/me` (ruta protegida con `sid`), con access JWT HS256 de 15 min, refresh opaco hasheado SHA-256 (`sesion.refresh_token_hash CHAR(64) UNIQUE`), TTL de refresh 7 días por emisión, inactividad server-side deslizante de 30 min y pruebas TDD sin PostgreSQL (patrón fakes + `dependency_overrides`).

Completa la cadena proposal → spec → design → tasks → apply → verify → **sync** con trazabilidad verificable (REQ-01..REQ-12, CP-002, HU-002 CA1).

## 2. Estado de verificación (consumido de `verify-report.md`)

**VERIFY PASS — remediación confirmada** (2026-08-23, commit `09b5a1a`):

- Los tres blockers de la verificación anterior quedaron **resueltos**: REQ-06 (refresco sin `buscar_por_hash` previo; rotación atómica conserva `FOR UPDATE` y copia `usuario_global_id`), REQ-10 (`create_app()` fail-closed sin `JWT_SECRET`; sin secreto operativo hardcodeado) y REQ-12/TDD (suite ampliada + tabla TDD reconciliada en apply-progress).
- Evidencia ejecutada con el CLI del venv autorizado: `pytest tests -q` → **33 passed, 3 warnings**; `ruff check app tests` → **All checks passed**; `pyright app tests` → **0 errors, 0 warnings, 0 informations**; Alembic offline `upgrade head --sql` y `downgrade 0002:0001 --sql` correctos.
- **Blockers críticos: ninguno.** Sin tareas de implementación unchecked. `sync` está habilitado para esta fase (verify-report presente y sin FAIL/BLOCKED/CRITICAL pendientes).

## 3. Requisitos: lo que queda sincronizado/cerrado vs pendiente

| REQ | Veredicto | Estado para sync/cierre |
| --- | --- | --- |
| REQ-01 — login `200/401/422` | **PASS** | Cerrado en este slice |
| REQ-02 — error genérico no enumerativo | **PASS** | Cerrado en este slice |
| REQ-03 — access HS256 + refresh opaco SHA-256 | **PASS** | Cerrado en este slice |
| REQ-04 — modelo y migración `0002` | **PASS** | Cerrado (verificación offline; ejecución PG real → pendiente, ver §6) |
| REQ-05 — `SessionRepository` | **NOT VERIFIED — GAP-092 esperado** | **Pendiente únicamente por entorno** (locking real contra PostgreSQL) |
| REQ-06 — refresh rotatorio | **PASS** | Cerrado en este slice |
| REQ-07 — logout `204` idempotente | **PASS** | Cerrado en este slice |
| REQ-08 — `/auth/me` protegido | **PASS** | Cerrado en este slice |
| REQ-09 — inactividad sliding 30 min | **PASS** | Cerrado en este slice |
| REQ-10 — configuración y tokens en `app/core/` | **PASS** | Cerrado en este slice |
| REQ-11 — estructura S0-10 y DI | **PASS** | Cerrado en este slice |
| REQ-12 — TDD, TestClient, fakes y CP-002 | **PASS** | Cerrado en este slice (cobertura automatizada; ejecución de caja negra → pendiente, ver §6) |

Cobertura CP-002 (5 pasos): **PASS automatizado** en los cinco pasos (login válido, no enumeración, actividad 29 min/rotación, inactividad 31 min, logout + reuse rechazado). La documentación del sprint mantiene CP-002 como `not executed` (ejecución de caja negra documentada pendiente, GAP-087).

### Deltas de requisitos (semántica del helper nativo)

- **ADDED:** REQ-01..REQ-12 — spec completa de dominio nuevo `identity` en ruta plana (convención del proyecto; ver §5).
- **MODIFIED / REMOVED / RENAMED:** ninguno — no existe spec canónica previa en `openspec/specs/` y no hay REMOVED sobre nada sincronizable.

## 4. Snapshot sincronizado (verificado en git, 2026-08-23)

| Campo | Valor |
| --- | --- |
| Rama | `feat/autenticacion/t4-endpoints` |
| HEAD | `09b5a1aec442a0ba4e2f8e767968071634b13f19` — `fix(auth): remediate authentication verify blockers` |
| Cadena de commits del slice | `5d2a94d` (T1), `fc71daf` (T2), `e6a6ecd` (T3), `2df56f2` (T4), `e6c3b4b` (doc), `23d0674` (apply-progress), `09b5a1a` (remediación) |
| Working tree | `M docs/diagramas/Diagrama1.eapx` (modificado por EA, preexistente, fuera de scope) + `?? openspec/changes/autenticacion/verify-report.md` + `?? openspec/changes/autenticacion/sync-report.md` (este archivo) |
| Estado | **Normal antes de delivery**: sin cambios de código pendientes; solo artefacto de diagrama ajeno al slice y artefactos OpenSpec generados por las fases |

Sin commits, push, ramas nuevas ni PRs en esta fase (regla del usuario: solo crear el sync-report). La integración vía PR apilados queda como acción parent-owned (§7) y del equipo.

## 5. Sync canónico y merge de specs

- **Merge canónico: N/A.** No existe `openspec/specs/` ni `openspec/config.yaml` en el repositorio; ambos cambios del proyecto (`registro-cliente` archivado y `autenticacion`) usan la convención de spec plana `openspec/changes/{cambio}/spec.md` como spec completa de dominio nuevo (instrucción del orquestador, mismo patrón que PB-001).
- **Guardrail legacy flat specs — WARNING registrado:** el formato plano se detecta y se reporta, sin merge improvisado. La spec de `autenticacion` ya documenta que al archivar podrá sembrarse `openspec/specs/identity/spec.md`; esa siembra y el subsequente move a archive requieren aprobación explícita del orquestador (mismo criterio que el cierre de `registro-cliente`: "Sync canónico NO ejecutado… acción del orquestador/equipo").
- **Archivos canónicos actualizados:** ninguno (no existe árbol canónico). **Dominio sync-reporteado:** `identity`.
- **Collisiones:** ninguna — `registro-cliente` está archivado (no activo); no hay otro cambio activo sobre `identity`.
- **Sync destructivo / aprobaciones:** no aplica — sin REMOVED ni MODIFIED grandes sobre specs canónicas. No se requirió aprobación destructiva.

## 6. Observaciones abiertas (no bloquean el sync)

1. **GAP-092 — PostgreSQL real:** `REQ-05 NOT VERIFIED` (esperado y explícito). La migración `0002` y el locking `FOR UPDATE` se verificaron offline/fakes; `alembic upgrade head` contra PostgreSQL real queda pendiente del entorno (Docker/Floci). Acción propuesta: cubrir al habilitarse el entorno de integración (también cubre las tablas restantes del Sprint 1).
2. **CP-002 sin ejecución de caja negra:** los cinco pasos tienen cobertura automatizada reproducible (unit/API con fakes), pero la documentación del sprint mantiene CP-002 como `not executed`; falta la ejecución de caja negra documentada con su reporte (§2.1.5.3). GAP-087 abierto.
3. **RDD off clone-local (verificado):** `gentle-ai review mode status` → `receipt-driven development: off (decided by clone_local)`; `global: on`, `clone-local: off`. Los gates de entrega de este clon corren bajo política ordinaria del repositorio (hooks/tests/CI); la fila parent-owned de bounded review queda como decisión del orquestador, no como gate automático.
4. **Warnings no bloqueantes de verify:** tres warnings de assertion quality (líneas `test_autenticacion.py:105`, `test_session_repository.py:47`, `test_tokens_core.py:90-92`) y tres warnings/deprecaciones del runner (Starlette/httpx, FastAPI `on_event`). Mantenimiento futuro; no alteran el sync.

## 7. Acciones parent-owned pendientes (exactas de `tasks.md`; no las ejecuta el sync)

```text
- [ ] Start or reuse bounded review del slice implementado (contraste con spec REQ-01..REQ-12 y design: criterios de terminado de T1..T5, ausencia de refresh/password/hashes en respuestas y logs, cobertura CP-002 y REQ-12, resolución del vínculo access↔`sesion` vía `sid`). <!-- sdd-owner: parent -->
- [ ] Gate de entrega chain (`auto-chain` → `stacked-to-main`): verificar por T que el diff ≤ ~400 líneas (dividiendo internamente una T si cruza el umbral), validar `pytest -q` verde por PR, correr los gates de entrega por PR (pre-commit/pre-pr) y crear en secuencia las ramas `feat/autenticacion/tN-<slug>` y sus PRs a `main` (5 PRs según el split del forecast; documentar cada PR en el apply-progress). <!-- sdd-owner: parent -->
```

- Forecast de review workload: `~1450–1650` líneas; riesgo de presupuesto de 400 líneas **High**; chained PRs **Yes**; estrategia registrada `auto-chain` / `stacked-to-main`; sin `size:exception`.
- Estas dos filas son `deferredParentActions` (2 pendientes), no trabajo de implementación: `taskProgress` de implementación está en 5/5 completadas.

## 8. Trazabilidad completa (proposal → spec → design → tasks → apply → verify → sync)

| Fase | Artefacto | Estado al sync |
| --- | --- | --- |
| Exploración | `openspec/changes/autenticacion/` (sin archivo plano) / Engram obs **2437** | Completada |
| Propuesta | `openspec/changes/autenticacion/proposal.md` / Engram obs **2438** | Aprobada; decisiones cerradas (PyJWT, TTLs, mensaje genérico) |
| Spec | `openspec/changes/autenticacion/spec.md` / Engram obs **2440** | REQ-01..REQ-12 definidos con criterios verificables |
| Diseño | `openspec/changes/autenticacion/design.md` / Engram obs **2442** | Decisiones de arquitectura, datos y pruebas documentadas |
| Tareas | `openspec/changes/autenticacion/tasks.md` / Engram obs **2443** | T1–T5 `[x]`; 2 acciones parent-owned pendientes |
| Apply | `openspec/changes/autenticacion/apply-progress.md` / Engram obs **2445** | T1–T5 implementadas; evidencia TDD reconciliada |
| Verify | `openspec/changes/autenticacion/verify-report.md` / Engram obs **2447** | VERIFY PASS (2026-08-23) contra `09b5a1a` |
| Sync | `openspec/changes/autenticacion/sync-report.md` (este archivo) / Engram `sdd/autenticacion/sync-report` | Registrado; cambio permanece activo |

## 9. Estado estructurado y `actionContext`

```yaml
schemaName: gentle-ai.sdd-status
changeName: autenticacion
artifactStore: openspec          # resolución del motor nativo (existe openspec/); store de sesión: hybrid
sessionArtifactStore: hybrid
planningHome: repo-local/openspec
artifacts: proposal=done, specs=done, design=done, tasks=done, applyProgress=done, verifyReport=done, syncReport=done
taskProgress: total=5, completed=5, remaining=0, unchecked=[]
deferredParentActions: total=2, completed=0, remaining=2   # bounded review + delivery gate (sdd-owner: parent)
taskArtifactErrors: []
applyState: all_done
dependencies:
  apply: all_done
  verify: ready                  # VERIFY PASS sin FAIL/BLOCKED/CRITICAL pendientes
  sync: complete                 # report-only; merge canónico N/A (convención plana del proyecto)
  archive: blocked               # condicionado: reconciliar las 2 acciones parent-owned en sus boundaries nativos
actionContext:
  mode: repo-local
  workspaceRoot: D:\Universidad\Proyectos\2doSemestre2026\sw1\proyecto_final
  allowedEditRoots:
    - D:\Universidad\Proyectos\2doSemestre2026\sw1\proyecto_final
  warnings: []
nextRecommended: sdd-archive     # cuando las acciones parent-owned de review/delivery estén reconciliadas
isNonAuthoritative: false
```

Hallazgos de status:

- Selección `autenticacion` explícita y no ambigua; artefactos confirmados en disco y en Engram.
- `actionContext.mode=repo-local`; raíz autorizada coincide con el workspace; paths de escritura de esta fase (sync-report en `openspec/changes/autenticacion/`) dentro de `allowedEditRoots`. Sin restricción workspace-planning.
- No se ejecutó el dispatcher nativo en esta fase (fase sin runtime; estado resuelto desde artefactos, handoff del orquestador y verificación de git).
- `openspec/config.yaml` ausente → no se aplican `rules.sync` adicionales.

## 10. Validaciones y checks ejecutados en esta fase

| Check | Resultado |
| --- | --- |
| `git branch --show-current` | `feat/autenticacion/t4-endpoints` |
| `git log -1` / cadena de commits | HEAD `09b5a1a`; T1–T5 + doc + remediación presentes |
| `git status --porcelain` | Working tree normal antes de delivery: solo `Diagrama1.eapx` modificado (EA, fuera de scope) + verify-report/sync-report untracked |
| `gentle-ai review mode status --cwd <repo> --scope clone` | RDD `off (decided by clone_local)`; `global: on`, `clone-local: off` |
| Lectura de `verify-report.md` | Sin FAIL/BLOCKED/CRITICAL; REQ-05 NOT VERIFIED solo por GAP-092 (excepción explícita) |
| Lectura de `tasks.md` | 0 líneas unchecked de implementación; 2 filas `sdd-owner: parent` intactas |
| Evidencia de verify (no re-ejecutada) | 33 passed · ruff clean · pyright 0 (comandos y salidas registrados en verify-report) |

No se re-ejecutaron pruebas ni se modificaron proposal/spec/design/tasks/apply-progress/verify-report (regla del usuario: el sync solo crea sync-report).

## 11. Conclusión

**SYNC PASS (report-only).** La implementación verificada de PB-002/HU-002 está sincronizada y cerrada para el slice: 11/12 REQ PASS, 1 NOT VERIFIED únicamente por GAP-092 (entorno PostgreSQL real), sin blockers críticos, sin colisiones y sin sync destructivo. El cambio permanece **activo** con 2 acciones parent-owned pendientes (bounded review + delivery chain) y 3 observaciones abiertas (GAP-092, CP-002 caja negra, RDD off clone-local).

**Próximo paso recomendado:** `sdd-archive` una vez que el orquestador reconcilie las acciones parent-owned de bounded review y delivery gate en sus boundaries nativos; en archive, ejecutar con aprobación explícita la siembra de `openspec/specs/identity/spec.md` (merge canónico diferido, pendiente en el proyecto).
