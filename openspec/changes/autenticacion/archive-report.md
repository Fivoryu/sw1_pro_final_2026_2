# Archive report — autenticacion (PB-002, slice backend)

- **Cambio:** `autenticacion`
- **Product Backlog:** PB-002 · **Historia:** HU-002 — Iniciar sesión y mantener sesión · **Caso de uso:** CU-002 · **Dominio:** `identity`
- **Slice:** backend (la pantalla de login de la app cliente es slice posterior del mismo PB-002)
- **Fecha de cierre:** 2026-08-23
- **Estado del archive:** **PASS (archivo con observaciones no críticas)** — ver §7.
- **Cambio archivado:** sí (2026-08-23). Registro de cierre en `openspec/changes/autenticacion/`; sin move a `openspec/changes/archive/` ni siembra canónica por instrucción explícita del orquestador (mismo criterio que PB-001, ver §10).

---

## 1. Resumen del cambio

El slice backend de PB-002 implementa autenticación y sesión del cliente sobre la cuenta global de PB-001: `POST /api/v1/auth/login` (200/401/422 con error genérico no enumerativo), `POST /api/v1/auth/refresh` (rotación atómica con `SELECT ... FOR UPDATE`), `POST /api/v1/auth/logout` (204 idempotente) y `GET /api/v1/auth/me` (ruta protegida con `sid`), con access JWT HS256 de 15 minutos, refresh opaco hasheado SHA-256 (`sesion.refresh_token_hash CHAR(64) UNIQUE`), TTL de refresh de 7 días por emisión, inactividad server-side deslizante de 30 minutos (RNF-006) y pruebas TDD sin PostgreSQL (patrón fakes + `dependency_overrides`).

Cierra la cadena proposal → spec → design → tasks → apply → verify → sync → **archive** con trazabilidad verificable (REQ-01..REQ-12, CP-002, HU-002 CA1–CA4). La integración vía PRs apilados queda como acción del equipo (ramas locales sin push); la UI de login de la app cliente es slice posterior del mismo PB-002.

## 2. Trazabilidad completa (proposal → spec → design → tasks → apply → verify → sync → archive)

| Fase | Artefacto | Estado al cierre |
| --- | --- | --- |
| Exploración | Engram `sdd/autenticacion/explore` (obs **2437**) | Completada; sin artefacto de archivo |
| Propuesta | `openspec/changes/autenticacion/proposal.md` / Engram obs **2438** | Aprobada 2026-08-23; decisiones cerradas (PyJWT, TTLs, mensaje genérico) |
| Spec | `openspec/changes/autenticacion/spec.md` / Engram obs **2440** | REQ-01..REQ-12 definidos con criterios verificables |
| Diseño | `openspec/changes/autenticacion/design.md` / Engram obs **2442** | Decisiones de arquitectura, datos, locking y pruebas documentadas |
| Tareas | `openspec/changes/autenticacion/tasks.md` / Engram obs **2443** | T1–T5 completas (`[x]`); 2 acciones parent-owned pendientes |
| Apply | `openspec/changes/autenticacion/apply-progress.md` / Engram obs **2445** | T1–T5 implementadas; evidencia TDD reconciliada (tabla strict mode T1–T5) |
| Verify | `openspec/changes/autenticacion/verify-report.md` / Engram obs **2447** | VERIFY PASS tras remediación (2026-08-23, commit `09b5a1a`) |
| Sync | `openspec/changes/autenticacion/sync-report.md` / Engram obs **2449** | SYNC PASS (report-only); merge canónico N/A |
| Archive | `openspec/changes/autenticacion/archive-report.md` (este archivo) / Engram `sdd/autenticacion/archive-report` | Cierre registrado |

## 3. Resultados finales por requisito (estado al cierre, 2026-08-23)

| REQ | Resultado | Evidencia |
| --- | --- | --- |
| REQ-01 — login `200/401/422` | **PASS** | `router.py`, `schemas.py` y `service.py:80-116` implementan el contrato con normalización, verificación uniforme, sesión inicial y payload público; cobertura en `test_autenticacion.py`. |
| REQ-02 — error genérico no enumerativo | **PASS** | `service.py:83-91` rechaza correo inexistente, password incorrecto y cuenta inactiva con el mismo `401` + `Correo o contraseña inválidos`; tests de no enumeración y cuenta inactiva idénticos. |
| REQ-03 — access HS256 + refresh opaco SHA-256 | **PASS** | `app/core/tokens.py:49-110` (PyJWT HS256, claims `sub/sid/type/iat/exp`, `secrets.token_urlsafe`, SHA-256 hexadecimal); `test_login_persists_exact_sha256_hash_without_plaintext` compara exactamente contra `hashlib.sha256(...)`. Sin logging del refresh en `app/`. |
| REQ-04 — modelo y migración `0002` | **PASS** | `models.py` y `0002_crear_sesion.py` coinciden (UUID PK, FK, `CHAR(64)`, timestamps, `revocado`, UNIQUE e índice); Alembic offline `upgrade head --sql` / `downgrade 0002:0001 --sql` correctos. Ejecución real contra PostgreSQL → GAP-092. |
| REQ-05 — `SessionRepository` | **NOT VERIFIED — GAP-092 esperado** | Protocolo, adaptador SQLAlchemy (`SELECT ... FOR UPDATE`, validación, rotación, revocación, actividad) y fake presentes; `test_session_repository.py` con 5 casos verdes. No se afirma locking real contra PostgreSQL. |
| REQ-06 — refresh rotatorio | **PASS** | `service.py:118-156` llama directamente a `rotar_por_hash` (sin preconsulta); `repository.py:154-172` bloquea, valida, copia `usuario_global_id`, revoca e inserta en transacción única. Regresión `test_refresh_uses_atomic_rotation_without_prior_hash_lookup` en verde. |
| REQ-07 — logout `204` idempotente | **PASS** | `router.py:143-149` `204` sin cuerpo; `service.py:159-162` revoca por hash; cobertura de logout válido, repetido, desconocido y reutilización rechazada. |
| REQ-08 — `/auth/me` protegido | **PASS** | `HTTPBearer(auto_error=False)` traduce ausencia/malformación a `401` (nunca `403`); `service.py:164-182` valida JWT, `sid`, `sub`, sesión e inactividad; matriz de variantes inválidas en verde. |
| REQ-09 — inactividad sliding 30 min | **PASS** | `repository.py:321-325` expiración por inactividad + revocación lazy; tests de actividad a 29 min, rechazo > 30 min, refresh dentro de ventana y rechazo de `/me`/refresh inactivos. |
| REQ-10 — configuración y tokens en `app/core/` | **PASS** | `config.py` lee `JWT_SECRET`/TTLs del entorno sin secreto operativo; `create_app()` falla cerrado sin `JWT_SECRET` (`main.py:37-46`) y el default app valida en startup (`main.py:49-62`); `pyproject.toml` declara `PyJWT>=2.8,<3`. |
| REQ-11 — estructura S0-10 y DI | **PASS** | `router.py`/`schemas.py`/`service.py`/`repository.py`/`models.py` con responsabilidades separadas; router sin SQL; módulo registrado bajo `/api/v1`; reuso de `buscar_por_correo` y Argon2id de PB-001; OpenAPI lista las cuatro rutas. |
| REQ-12 — TDD, TestClient, fakes y CP-002 | **PASS** | `test_autenticacion.py` con 16 casos; suite completa **33 passed**; cobertura de cuenta inactiva, SHA-256 exacto/no plaintext, refresh expirado, rotación atómica, matriz `/me` 401-not-403, fail-closed y `422`. Los 5 pasos de CP-002 reproducibles sin PostgreSQL. |

### Trazabilidad HU-002 (criterios de aceptación)

| CA | Resultado | Evidencia |
| --- | --- | --- |
| CA1 — credenciales válidas emiten access + refresh; refresh rota y es revocable (tabla `sesion`) | **PASS** | REQ-01/03/05/06: login emite par y persiste solo SHA-256; rotación atómica revoca el anterior (`revocado=true`) y rechaza el reuso; migración `0002` con FK/UNIQUE/índice. |
| CA2 — sesión inválida tras 30 minutos de inactividad (RNF-006) | **PASS** | REQ-09: ventana deslizante server-side vía `ultima_actividad`; 29 min válida, 31 min rechazada con revocación lazy. |
| CA3 — error genérico sin revelar existencia de cuenta | **PASS** | REQ-02: mismo `401` y mismo `detail` para correo inexistente, password incorrecto y cuenta no activa. |
| CA4 — logout revoca el refresh activo | **PASS** | REQ-07: `204` idempotente, fila `revocado=true`, reutilización posterior → `401` `Sesión inválida o expirada`. |

Cobertura CP-002 (5 pasos): **PASS automatizado** (login válido, no enumeración, actividad 29 min/rotación, inactividad 31 min, logout + reuse rechazado). La documentación del sprint mantiene CP-002 `not executed` (ejecución de caja negra documentada pendiente — GAP-087).

## 4. Entregables

### Backend

- `backend/pyproject.toml` (dependencia `PyJWT>=2.8,<3`), `backend/.env.example` (placeholders `JWT_SECRET`/TTLs, sin secretos operativos)
- `backend/app/core/` → `config.py` (settings fail-closed por entorno), `clock.py` (ClockProtocol + SystemClock UTC), `tokens.py` (TokenServiceProtocol + adaptador PyJWT HS256, refresh opaco y SHA-256), `security.py` (verificación Argon2id uniforme con hash ficticio)
- `backend/app/modules/identity/` → `models.py` (modelo `Sesion`), `schemas.py` (requests/responses públicos), `repository.py` (`SessionRepositoryProtocol` + adaptador SQLAlchemy con `FOR UPDATE` + `FakeSessionRepository`), `service.py` (`AuthenticationService`), `router.py` (login/refresh/logout/me)
- `backend/app/main.py` (composición `/api/v1` y fail-closed de configuración)
- `backend/alembic/env.py`, `backend/alembic/versions/0002_crear_sesion.py` (crea solo `sesion`; `down_revision="0001"`)
- `backend/tests/` → `test_tokens_core.py`, `test_session_repository.py`, `test_autenticacion.py` (16 casos); `test_registro.py` ajustado (setting de test explícito para composición fail-closed)

### Documentación del repositorio

- `docs/scrum/sprint-1/02-proceso-por-hu.md` §2.1.4 — párrafo de implementación PB-002/HU-002 (módulo `identity`, login/refresh/logout/me, access JWT + refresh opaco hasheado, tabla `sesion` migración `0002`, inactividad sliding 30 min) con referencia relativa a `openspec/changes/autenticacion/spec.md`/`tasks.md`. §2.1.5 intacto (CPs siguen `not executed`; GAP-087/GAP-073 intactos).

### Artefactos OpenSpec (este cambio)

- `openspec/changes/autenticacion/{proposal,spec,design,tasks,apply-progress,verify-report,sync-report,archive-report}.md`

## 5. Commits y ramas (estado verificado en git, 2026-08-23)

| Rama | Último commit | Contenido |
| --- | --- | --- |
| `feat/autenticacion/t1-core` | `5d2a94d` | Núcleo de tokens, clock y settings (T1) |
| `feat/autenticacion/t2-sesion` | `fc71daf` | Modelo `Sesion` + migración `0002_crear_sesion.py` (T2) |
| `feat/autenticacion/t3-repository` | `e6a6ecd` | `SessionRepository` + fake (T3) |
| `feat/autenticacion/t4-endpoints` | `09b5a1a` | T4 endpoints (`2df56f2`), doc §2.1.4 (`e6c3b4b`), apply-progress reconciliado (`23d0674`), **remediación de verify** (`09b5a1a`) |

- **Las 4 ramas son LOCALES ÚNICAMENTE, NO pusheadas a `origin`** (verificado: 0 ramas remotas `autenticacion`). `main` (local y remoto) permanece en `65ed8c6`, sin merge: la integración vía PRs apilados `stacked-to-main` queda como **acción del equipo/usuario, fuera del cambio SDD** (el usuario crea los PRs; `gh` no está disponible), igual que en PB-001.
- HEAD verificado del slice: `09b5a1aec442a0ba4e2f8e767968071634b13f19` — `fix(auth): remediate authentication verify blockers`.

## 6. Decisiones tomadas

### De la propuesta y la spec (2026-08-23)

1. **Backend-first:** el slice entrega contrato API, persistencia y pruebas; la pantalla de login de la app cliente queda como slice posterior de PB-002.
2. **PyJWT 2.x (HS256) para el access + refresh opaco hasheado SHA-256:** se descartaron `python-jose`/`authlib` y tokens opacos para ambos; el refresh nunca se persiste ni responde en claro (RF-002, tabla `sesion` §2.1.2.2).
3. **TTLs configurables:** access 15 minutos, refresh 7 días como TTL **absoluto por refresh emitido** (sin revivir revocados), inactividad server-side **sliding** de 30 minutos (RNF-006/CP-002 paso 3).
4. **Login responde `200`** (autentica, no crea recurso direccionable; `201` queda reservado a registro/creación) y usa la constante exacta `INVALID_CREDENTIALS_MESSAGE = "Correo o contraseña inválidos"`.
5. **`INVALID_SESSION_MESSAGE = "Sesión inválida o expirada"`** introducido en la spec para refresh/me/reutilización, sin distinguir causa; extendido el 401 genérico a cuentas con `estado != "activo"` (anti-enumeración defensiva).

### Del diseño

1. **Vínculo access ↔ sesión vía `sid`:** cada access lleva el UUID de la fila `sesion`; `/auth/me` valida `sesion.id == sid` y `usuario_global_id == sub`. Esto permite revocación inmediata del access (logout/rotación) sin seleccionar "la última sesión" del usuario. No se agrega `jti`.
2. **Rotación transaccional única:** `rotar_por_hash` con `SELECT ... FOR UPDATE`, revalidación bajo lock, revocación + inserción en una sola transacción/commit (sin TOCTOU); `IntegrityError` → rollback. Fake con `RLock` single-writer.
3. **Clock inyectable UTC** (`ClockProtocol`/`SystemClock`); sin `datetime.now()` directo en servicios ni fakes; `HTTPBearer(auto_error=False)` para traducir ausencia/malformación a `401`, nunca `403`.

### De implementación y remediación (apply/verify)

1. **Fix REQ-06:** `AuthenticationService.refresh` eliminó la consulta previa `buscar_por_hash` (transacción SQLAlchemy implícita) antes de `rotar_por_hash`; el repositorio copia el `usuario_global_id` de la fila bloqueada a la sesión reemplazo. Regresión dedicada agregada.
2. **Fix REQ-10 (fail-closed):** `create_app()` construye `PyJWTTokenService` sincrónicamente y falla con `SecurityConfigurationError` sin `JWT_SECRET`; el default app valida la misma configuración en su startup hook. Sin secreto operativo hardcodeado; factories de tests de PB-001 inyectan el setting de test explícito.
3. **Resolución del escenario de actividad (conflicto de contrato):** el test original reutilizaba un access de 15 min a los 29 min (401 legítimo por expiración). Decisión del orquestador: preservar el contrato (REQ-03/REQ-08) y modelar CP-002 paso 3 como un cliente real — refresh a los 20 min → `/me` a los 29 min con el access nuevo → 200. Alternativas (subir TTL o aceptar access expirado) violaban la spec y fueron descartadas.
4. **REQ-12/TDD:** se agregaron los casos faltantes (cuenta inactiva, SHA-256 exacto/no plaintext, refresh expirado, rotación atómica, matriz `/me` 401-not-403, fail-closed de configuración) y se reconcilió la tabla **TDD Cycle Evidence — strict mode** T1–T5 en apply-progress.

## 7. Observaciones al cierre (archive PASS con observaciones no críticas)

1. **REQ-05 NOT VERIFIED (GAP-092):** el repositorio está verificado por código/fakes y la migración por Alembic offline, pero `alembic upgrade head` y el locking `FOR UPDATE` contra PostgreSQL real quedan pendientes del entorno (Docker/Floci). Excepción esperada y explícita, no bloqueante (diferida por diseño al entorno de integración).
2. **Sync canónico NO ejecutado:** no existe `openspec/specs/` ni `openspec/config.yaml`; `sync-report.md` es **SYNC PASS (report-only)** y el orquestador no aprobó archive-time sync fallback ni instruyó el move. La spec quedó en la ruta plana `spec.md` como spec completa del dominio `identity`; la siembra de `openspec/specs/identity/spec.md` (merge ADDED REQ-01..REQ-12 si se siembra) y el movido a `openspec/changes/archive/2026-08-23-autenticacion/` quedan como **acción del orquestador/equipo**, no como obstáculo del registro de cierre. Los artefactos permanecen intactos en `openspec/changes/autenticacion/` (trail de auditoría conservado; no se modificó proposal/spec/design/tasks/apply-progress/verify-report/sync-report).
3. **Desviaciones de proceso registradas (transparencia):**
   - **Presupuesto de líneas:** el intento 1 de apply midió ~2338 líneas contra un presupuesto adquirido de 1650 → **reset de intento nativo autorizado por el maintainer** (`maintainer_decision`), sin reset automático; el conteo final post-remediación no fue re-medido en verify.
   - **Verify intento 1 FAILED** (blockers REQ-06/REQ-10/REQ-12) → remediación en commit `09b5a1a` → **VERIFY PASS final** (33 passed, ruff clean, pyright 0).
   - **Apply worker agotó timeout dos veces**; se completó mediante corrective reruns (verificado contra el estado nativo `applyState: ready`).
   - **Scope-creep detectado y revertido:** ediciones en `skills/diagramas-uml-ea` ajenas al slice fueron revertidas; el slice tocó únicamente `backend/` + `docs/scrum` + artefactos OpenSpec.
4. **RDD off a nivel clone** (`receipt-driven development: off (decided by clone_local)`; `global: on`, `clone-local: off`): la entrega de este clon sigue la política ordinaria del repositorio (hooks/tests/CI); **no hay receipt de review gobernando este candidato** y la fila parent-owned de bounded review queda como decisión del orquestador, no como gate automático.
5. **Warnings no bloqueantes:** tres de assertion quality (`test_autenticacion.py:105`, `test_session_repository.py:47`, `test_tokens_core.py:90-92`) y tres deprecaciones del runner (Starlette/httpx, FastAPI `on_event`). Mantenimiento futuro.
6. **apply-progress contiene snapshots históricos obsoletos** (T1-only y rerun T4/T5 bloqueado) que contradicen el estado real; la tabla reconciliada TDD T1–T5 los supersede, y `tasks.md` persistido marca T1–T5 `[x]`. No se modificó (regla del usuario: solo crear el archive-report).
7. **Ramas sin push:** las 4 ramas `feat/autenticacion/*` son locales. La creación de los 5 PRs apilados a `main` (split del forecast T1→T5) queda como acción del equipo.

## 8. Tareas de implementación pendientes

**Ninguna.** T1–T5 están marcadas `[x]` en `tasks.md` (verificado: 0 líneas `- [ ]` con `sdd-owner: implementation`). Las únicas líneas sin marcar son acciones explícitamente del orquestador (`sdd-owner: parent`), fuera del scope de implementación:

```text
- [ ] Start or reuse bounded review del slice implementado (contraste con spec REQ-01..REQ-12 y design: criterios de terminado de T1..T5, ausencia de refresh/password/hashes en respuestas y logs, cobertura CP-002 y REQ-12, resolución del vínculo access↔`sesion` vía `sid`). <!-- sdd-owner: parent -->
- [ ] Gate de entrega chain (`auto-chain` → `stacked-to-main`): verificar por T que el diff ≤ ~400 líneas (dividiendo internamente una T si cruza el umbral), validar `pytest -q` verde por PR, correr los gates de entrega por PR (pre-commit/pre-pr) y crear en secuencia las ramas `feat/autenticacion/tN-<slug>` y sus PRs a `main` (5 PRs según el split del forecast; documentar cada PR en el apply-progress). <!-- sdd-owner: parent -->
```

## 9. Gaps al cierre

| Gap | Estado | Acción propuesta |
| --- | --- | --- |
| GAP-092 (PostgreSQL real: migración `0002`, locking `FOR UPDATE`, REQ-05) | Abierto (parcialmente cubierto: solo `sesion`) | Ejecutar `alembic upgrade head` con PostgreSQL local (Docker/Floci) y cubrir las 13 tablas restantes del Sprint 1 |
| GAP-087 (evidencia de ceremonias / CP-002 caja negra) | Abierto | Ejecutar y registrar la caja negra de CP-002 con su reporte (§2.1.5.3); los 5 pasos ya tienen cobertura automatizada reproducible |
| GAP-073 (responsable de implementación) | Abierto | Asignar responsable en la documentación del proyecto; fecha de aprobación de la propuesta pendiente de registro |
| GAP-088 (diagrama Sequence — autenticación y sesión) | Abierto | Generar el diagrama de secuencia del flujo auth/sesión en el sprint |
| LSP tooling (Pyright stale) | Abierto | Ruido del intérprete stale descartado como evidencia; Pyright CLI autoritativo (0 errores); reinicio de la app Pi cuando aplique |
| PRs de integración (5 ramas locales sin push) | Acción del equipo | Crear los PRs apilados `stacked-to-main` desde las ramas locales `feat/autenticacion/t1..t5` (fuera del cambio SDD) |
| Sync canónico + move a archive | Acción del orquestador | Sembrar `openspec/specs/identity/spec.md` y mover a `openspec/changes/archive/2026-08-23-autenticacion/` con aprobación explícita de sync fallback |
| UI de login (resto de PB-002) | Slice posterior | Implementar la pantalla de login de la app cliente consumiendo este contrato |
| Catálogo real (PB-030) | Futuro | `/auth/me` es solo ruta protegida de demostración; el catálogo es otro PB |

## 10. Estado estructurado y contexto de acción

- `artifactStore`: hybrid (OpenSpec file-backed + Engram). No se ejecutó dispatcher nativo en esta fase (fase sin runtime; estado resuelto desde artefactos, handoff del orquestador y verificación de git). El motor nativo identifica `artifactStore: openspec` porque existe `openspec/`; store de sesión: hybrid.
- `actionContext.mode`: repo-local; `workspaceRoot`: `D:\Universidad\Proyectos\2doSemestre2026\sw1\proyecto_final`; `allowedEditRoots`: raíz del repositorio (el path de escritura de esta fase — `openspec/changes/autenticacion/archive-report.md` — está dentro). Sin restricción workspace-planning ni problema de autoridad de edición.
- `openspec/config.yaml`: ausente → no se aplican `rules.archive` adicionales.
- Cambios activos concurrentes en el mismo dominio: **ninguno** (solo `autenticacion` activo bajo `openspec/changes/`; `registro-cliente` archivado).
- Merge destructivo / sync canónico: **no aplica** (no se ejecutó sync; sin REMOVED/MODIFIED sobre specs canónicas; siembra futura = ADDED REQ-01..REQ-12).
- `reviewGate`: estructuralmente ausente (RDD off clone-local; sin review iniciado para este candidato) → la entrega procede bajo política ordinaria del repositorio; no se ejecutaron gates de entrega en esta fase.
- Sin commits ni push en esta fase (regla del usuario); sin modificación de proposal/spec/design/tasks/apply-progress/verify-report/sync-report. Working tree al cierre: solo `M docs/diagramas/Diagrama1.eapx` (EA abierto, preexistente, excluido) + `??` verify-report/sync-report/archive-report (generados por las fases).

## 11. IDs de memoria (Engram)

- `sdd/autenticacion/explore` → obs **2437** · `proposal` → obs **2438** · `spec` → obs **2440** · `design` → obs **2442** · `tasks` → obs **2443** · `apply-progress` → obs **2445** · `verify-report` → obs **2447** · `sync-report` → obs **2449**
- `sdd/autenticacion/archive-report` → guardado en esta fase (type `architecture`)

---

**Estado global: archivado (2026-08-23).** Los PRs de integración quedan como acción del equipo, fuera del cambio SDD. Siguiente cambio sugerido: **slice UI de login de PB-002** (pantalla cliente) o el siguiente PB del Sprint 1 sobre este contrato.
