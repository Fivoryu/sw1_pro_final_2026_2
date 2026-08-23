# Archive report — registro-cliente (PB-001, slice backend)

- **Cambio:** `registro-cliente`
- **Product Backlog:** PB-001 · **Historia:** HU-001 — Registro con correo (modo pruebas) · **Caso de uso:** CU-001 · **Dominio:** `identity`
- **Slice:** backend (la pantalla de registro de la app cliente es slice posterior del mismo PB-001)
- **Fecha de cierre:** 2026-08-23
- **Estado del archive:** **PASS (archivo con observaciones no críticas)** — ver §7.
- **Cambio archivado:** sí (2026-08-23)

---

## 1. Resumen del cambio

El slice backend de PB-001 implementa el registro de la cuenta global del cliente (`usuario_global`) mediante `POST /api/v1/auth/registro` en el monolito modular FastAPI (`backend/`), con validación de correo y contraseña, normalización a minúsculas, unicidad case-insensitive respaldada por `UNIQUE(correo)`, hash Argon2id, migración Alembic inicial y pruebas unitarias reproducibles sin PostgreSQL.

Habilita los flujos posteriores del Sprint 1 (PB-002 autenticación) sin adelantar login, verificación real de correo (RF-033, Sprint 3) ni UI móvil. El registro no crea tenant, membresía ni permisos (BR-001).

## 2. Trazabilidad completa (proposal → spec → design → tasks → apply → verify)

| Fase | Artefacto | Estado al cierre |
| --- | --- | --- |
| Exploración | Engram `sdd/registro-cliente/explore` (obs 2430) | Completada; sin artefacto de archivo |
| Propuesta | `openspec/changes/registro-cliente/proposal.md` / Engram obs 2431 | Aprobada 2026-08-23; decisiones cerradas en ronda de preguntas |
| Spec | `openspec/changes/registro-cliente/spec.md` / Engram obs 2432 | REQ-01..REQ-07 definidos con criterios verificables |
| Diseño | `openspec/changes/registro-cliente/design.md` / Engram obs 2433 | Decisiones de arquitectura, datos y pruebas documentadas |
| Tareas | `openspec/changes/registro-cliente/tasks.md` / Engram obs 2434 | T1–T5 completas (`[x]`) |
| Apply | `openspec/changes/registro-cliente/apply-progress.md` / Engram obs 2435 | T1–T5 implementadas; evidencia TDD y verificación registrada |
| Verify | `openspec/changes/registro-cliente/verify-report.md` | VERIFY PASS tras resolución del blocker REQ-01 (2026-08-23) |
| Archive | `openspec/changes/registro-cliente/archive-report.md` (este archivo) / Engram `sdd/registro-cliente/archive-report` | Cierre registrado |

## 3. Resultados finales por requisito (estado al cierre, 2026-08-23)

| REQ | Resultado | Evidencia |
| --- | --- | --- |
| REQ-01 — Endpoint `POST /api/v1/auth/registro` (201/422/409) | **PASS** | Router y schemas en `backend/app/modules/identity/`; contrato 201/422/409 cubierto por tests. Blocker de verificación (clasificación de `23505` sin constraint) **resuelto**: `_is_duplicate_email_error` exige el constraint `uq_usuario_global_correo` y re-lanza cualquier otro `23505` (commits `404fd97`, `128cf34`); regresión `test_violacion_unica_ajena_no_se_clasifica_como_duplicado` agregada. |
| REQ-02 — Normalización a minúsculas y unicidad case-insensitive | **PASS** | `strip().lower()` en `service.py` antes de unicidad y persistencia; `UNIQUE(correo)` declarado en modelo y migración; test de duplicado con mayúsculas en verde. |
| REQ-03 — Política de contraseña en modo pruebas (mínimo 8) | **PASS** | `SecretStr(min_length=8)` en `schemas.py`; sin reglas de complejidad extra; valor exacto entregado al hasher; tests 201/422 en verde. |
| REQ-04 — Hash Argon2id; nunca en claro ni en respuestas | **PASS** | `PasswordHasher(Type.ID)` en `core/security.py`; solo `hash_password` persistido; `RegistroResponse` sin campos sensibles; verificación Argon2id y ausencia de `hash_password`/password en respuestas cubiertas por tests. |
| REQ-05 — Persistencia `usuario_global` + migración Alembic inicial | **NOT VERIFIED** (código verificado; ejecución real pendiente) | Modelo y revisión `0001_crear_usuario_global.py` coinciden 1:1 con la tabla especificada (solo `usuario_global`, sin `sesion` ni otras tablas). `alembic upgrade head --sql` / `downgrade --sql` verificados offline. **No se ejecutó `upgrade head` contra PostgreSQL real** por falta de entorno local (Docker/Floci) — **GAP-092**. |
| REQ-06 — Módulo `identity` según S0-10, config por entorno | **PASS** | `router.py`, `schemas.py`, `service.py`, `repository.py`, `models.py` presentes con responsabilidades separadas; router registrado bajo `/api/v1`; settings vía pydantic-settings/`.env`; sin URLs ni credenciales hardcodeadas. |
| REQ-07 — Pruebas unitarias pytest sin PostgreSQL | **PASS** | **8 tests en verde** (`pytest backend/tests -q` → `8 passed`), suite ejecutada al cierre 2026-08-23; `ruff check backend/app backend/tests` → `All checks passed!`. Sin dependencia de PostgreSQL (dobles y TestClient). 1 advertencia de deprecación Starlette/httpx (mantenimiento futuro). |

### Trazabilidad HU-001 (criterios de aceptación)

| CA | Resultado |
| --- | --- |
| CA1 — correo válido + contraseña ≥ 8 sin verificación | **PASS** |
| CA2 — cuenta `activo` y `correo_verificado = false` | **PASS** |
| CA3 — duplicado rechazado con mensaje claro | **PASS** (incluye la regresión del constraint `uq_usuario_global_correo`) |
| CA4 — Argon2id y sin exposición de password/hash | **PASS** |

## 4. Entregables

### Backend (33 archivos nuevos frente a `main` 65ed8c6; +2084 líneas, 0 borradas)

- `backend/pyproject.toml`, `backend/.env.example`, `backend/pyrightconfig.json`
- `backend/app/main.py`, `backend/app/core/config.py`, `backend/app/core/security.py`, `backend/app/db/base.py`, `backend/app/db/session.py`
- `backend/app/modules/identity/` → `models.py`, `schemas.py`, `repository.py`, `service.py`, `router.py`
- `backend/alembic.ini`, `backend/alembic/env.py`, `backend/alembic/script.py.mako`, `backend/alembic/versions/0001_crear_usuario_global.py`
- `backend/tests/__init__.py`, `backend/tests/test_registro.py` (8 casos: 201 válido normalizado, 422 correo inválido, 422 password corta, 409 duplicado con mayúsculas con mensaje exacto, hash Argon2id verificable, respuestas sin `hash_password`/password, carrera `23505` con rollback, y la regresión de violación única ajena)

### Documentación del repositorio

- `docs/scrum/sprint-1/02-proceso-por-hu.md` §2.1.4 — párrafo de implementación PB-001/HU-001 (T5); CP-001..CP-013 siguen `not executed`; GAP-087/GAP-073/GAP-088 intactos.

### Artefactos OpenSpec (este cambio)

- `openspec/changes/registro-cliente/{proposal,spec,design,tasks,apply-progress,verify-report,archive-report}.md`

## 5. Commits y ramas (estado verificado en git, 2026-08-23)

| Rama | Último commit | Contenido |
| --- | --- | --- |
| `feat/registro-cliente/t1-bootstrap` | `f774fdd` | Bootstrap del backend FastAPI (T1) |
| `feat/registro-cliente/t2-migracion` | `1ca6d92` | Migración inicial `usuario_global` (T2) |
| `feat/registro-cliente/t3-identity` | `404fd97` | Módulo identity (T3) + fix lint/integridad `71b0d1b` + **fix REQ-01** `404fd97`/`128cf34` |
| `feat/registro-cliente/t4-tests` | `aa397c1` | Tests T4 + doc T5 (`041aa47`) + PEP 563 y cierre del clasificador de duplicados (`aa397c1`, `128cf34`, `3752026`) |

- Las 4 ramas están pusheadas a `origin`. `main` (local y remoto) permanece en `65ed8c6`, sin merge: la integración vía PR queda como **acción del equipo, fuera del cambio SDD** (el usuario crea los PRs desde la web; `gh` no está disponible).
- URLs de comparación para los PRs pendientes (repo `Fivoryu/sw1_pro_final_2026_2`):
  - `compare/main...feat/registro-cliente/t1-bootstrap`
  - `compare/main...feat/registro-cliente/t2-migracion`
  - `compare/main...feat/registro-cliente/t3-identity`
  - `compare/main...feat/registro-cliente/t4-tests`

## 6. Decisiones tomadas

### De la ronda de preguntas de la propuesta (2026-08-23)

1. **Backend primero:** el slice entrega contrato API, persistencia y pruebas; la pantalla de registro de la app cliente queda como slice posterior de PB-001.
2. **Correo normalizado a minúsculas** (`strip().lower()` en capa de servicio) con unicidad case-insensitive respaldada por `UNIQUE(correo)`; sin `citext` ni restricciones adicionales (contrae S1-02 §2.1.2.2).
3. **Política de contraseña mínima:** solo 8 caracteres en modo pruebas; sin requisitos de complejidad adicionales.
4. **Duplicado:** HTTP 409 con el mensaje exacto `Ya existe una cuenta con este correo`, centralizado como constante de dominio.

### De implementación y verificación

1. **Fix REQ-01 (clasificación de duplicados):** `_is_duplicate_email_error` exige el constraint `uq_usuario_global_correo` (nombre o alias de PostgreSQL) y **re-lanza cualquier otro `23505`** en lugar de convertirlo en 409. Regresión dedicada agregada. Commits `404fd97`, `128cf34`.
2. **PEP 563 (`from __future__ import annotations`) en 13 archivos del backend** (commit `aa397c1`): higiene de tipado; no resolvió los diagnósticos LSP por intérprete stale, pero es práctica correcta y quedó marcada la evidencia.
3. **Sesión SQLAlchemy 2.x síncrona con driver `psycopg`** (no `asyncpg`), según el diseño aprobado (§2.4, §3.3).
4. **Layout de tests consolidado:** los casos viven en `backend/tests/test_registro.py` en lugar del árbol `tests/unit/modules/identity/` previsto en T4. Desviación de layout registrada por verify como WARNING; el comportamiento cubierto es el mismo y la suite pasa.
5. **Engine/sesión perezosos** para que `create_app()` sea importable y los 422 sanitizados no requieran PostgreSQL configurada (desviación funcional mínima documentada en apply-progress).

## 7. Observaciones al cierre (archive PASS con observaciones no críticas)

1. **REQ-05 NOT VERIFIED (GAP-092):** la migración está verificada por código y SQL offline, pero `alembic upgrade head` contra PostgreSQL real queda pendiente del entorno Docker/Floci (no crítico; diferido por diseño al entorno de integración).
2. **Sync canónico NO ejecutado:** no existe `sync-report.md`, no existe `openspec/specs/` ni `openspec/config.yaml`, y el orquestador no aprobó archive-time sync fallback ni instruyó el move. La spec quedó en la ruta plana `spec.md` como spec completa del dominio nuevo `identity`; la siembra de `openspec/specs/identity/spec.md` y el movido a `openspec/changes/archive/2026-08-23-registro-cliente/` quedan como **acción del orquestador/equipo**, no como obstáculo del registro de cierre. Los artefactos permanecen intactos en `openspec/changes/registro-cliente/` (trail de auditoría conservado).
3. **Evidencia TDD:** el `TDD Cycle Evidence` tabla cubre T1–T3; T4/T5 quedaron documentadas en prosa dentro de apply-progress (evidencia presente, formato no tabla). Registrado; no bloquea el cierre.
4. **apply-progress contiene copia histórica obsoleta** con T4/T5 sin marcar (líneas 86–87) que contradice el estado real; `tasks.md` persistido marca T1–T5 `[x]` y verify-report confirma que **no quedan tareas de implementación sin marcar** (ver §8). No se modificó (regla del usuario: solo crear el archive-report).
5. **Presupuesto de líneas:** el slice final midió 1007 líneas contra un presupuesto adquirido de 950 (settle registrado como `maintainer_decision`, sin reset automático). Registrado como nota de proceso; ya resuelto por el decisor al autorizar el cierre.
6. **Dependencia de pruebas:** advertencia de deprecación Starlette/httpx (sugerencia de mantenimiento futuro, no bloqueante).

## 8. Tareas de implementación pendientes

**Ninguna.** T1–T5 están marcadas `[x]` en `tasks.md`. No hay marcadores `- [ ]` de tareas de implementación. Las únicas líneas sin marcar son acciones explícitamente del orquestador (`sdd-owner: parent`), fuera del scope de implementación:

- `- [ ] Start or reuse bounded review del slice implementado…`
- `- [ ] Gate de entrega: consultar al usuario la estrategia de commits/PRs…`

## 9. Gaps al cierre

| Gap | Estado | Acción propuesta |
| --- | --- | --- |
| GAP-092 (migraciones Sprint 1) | Abierto (parcialmente cubierto: solo `usuario_global`) | Ejecutar `alembic upgrade head` con PostgreSQL local (Docker/Floci) y cubrir las 13 tablas restantes |
| GAP-073 (responsable de implementación) | Abierto | Asignar responsable en la documentación del proyecto |
| GAP-084 (fechas) | Abierto | Completar fechas pendientes en los artefactos de Scrum |
| GAP-087 (evidencia de ceremonias / CP-001..CP-013) | Abierto | Ejecutar y registrar las pruebas de caja negra del Sprint 1 |
| LSP tooling (Pyright stale) | Abierto | Reinicio completo de la app Pi para re-servir el intérprete del venv; los 55 diagnósticos eran false positives del intérprete stale (marcados con evidencia) |
| PRs de integración | Acción del equipo | Crear los 4 PRs desde las URLs de comparación (fuera del cambio SDD) |
| Sync canónico + move a archive | Acción del orquestador | Sembrar `openspec/specs/identity/spec.md` y mover a `openspec/changes/archive/2026-08-23-registro-cliente/` con aprobación explícita de sync fallback |
| RF-033 (verificación real de correo) | Futuro (Sprint 3) | Reemplazar el modo pruebas antes de la demo final |

## 10. Estado estructurado y contexto de acción

- `artifactStore`: hybrid (OpenSpec file-backed + Engram). No se ejecutó dispatcher nativo (no aplica a hybrid sin `openspec/specs/` canónico; estado resuelto desde artefactos y handoff del orquestador).
- `actionContext.mode`: repo-local; `workspaceRoot`: `D:\Universidad\Proyectos\2doSemestre2026\sw1\proyecto_final`; `allowedEditRoots`: raíz del repositorio. Sin restricción workspace-planning.
- `openspec/config.yaml`: ausente → no se aplican `rules.archive` adicionales.
- Cambios activos concurrentes en el mismo dominio: **ninguno** (únicamente `registro-cliente` bajo `openspec/changes/`).
- Merge destructivo / sync canónico: **no aplica** (no se ejecutó sync; sin REMOVED/MODIFIED sobre specs canónicas).
- Sin commits ni push en esta fase (regla del usuario); sin modificación de proposal/spec/design/tasks/apply-progress/verify-report.

## 11. IDs de memoria (Engram)

- `sdd/registro-cliente/explore` → obs **2430** · `proposal` → obs **2431** · `spec` → obs **2432** · `design` → obs **2433** · `tasks` → obs **2434** · `apply-progress` → obs **2435**
- `sdd/registro-cliente/archive-report` → guardado en esta fase (type `decision`)

---

**Estado global: archivado (2026-08-23).** Los PRs de integración quedan como acción del equipo, fuera del cambio SDD. Siguiente cambio sugerido: **PB-002 — autenticación/sesión** (depende de la cuenta global creada aquí).
