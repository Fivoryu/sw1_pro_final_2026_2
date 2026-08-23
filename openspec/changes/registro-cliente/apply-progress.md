# Apply progress — registro-cliente (PB-001)

## Structured status consumed

- `schemaName`: `gentle-ai.sdd-status`
- `changeName`: `registro-cliente`
- `artifactStore`: `openspec` (authoritative)
- `applyState`: `ready` at phase start
- `nextRecommended`: `apply`
- `actionContext`: `repo-local`; workspace root `D:\Universidad\Proyectos\2doSemestre2026\sw1\proyecto_final`; allowed edit root is the repository root; no warnings.
- Workload gate: `Decision needed before apply: Yes`, `Chained PRs recommended: Yes`, `Chain strategy: pending` in the task artifact, resolved by the parent prompt as four stacked-to-main slices using `stacked-to-main`.

## Completed implementation tasks

### T1 — Bootstrap

- Persisted checkbox updated from `- [ ]` to `- [x]` in `openspec/changes/registro-cliente/tasks.md` immediately after completion.
- Branch: `feat/registro-cliente/t1-bootstrap`.
- Commit/push/PR: pending until the slice is staged and committed.
- Implemented FastAPI package bootstrap, pydantic-settings configuration, Argon2id factory, SQLAlchemy declarative base/session dependency, project metadata, development dependency group, and non-secret `.env.example`.
- The database engine is created lazily only when a configured `DATABASE_URL` is used; application import does not create a local database or tables.

## TDD Cycle Evidence

| Task | RED | GREEN | TRIANGULATE | REFACTOR |
| --- | --- | --- | --- | --- |
| T1 | Temporary unittest importing `app.main.create_app` failed with `ModuleNotFoundError: No module named 'app'`. | The same test passed; `python -c "from app.main import create_app; create_app()"` passed. | `ruff check .`, `ruff format --check .`, and `git diff --check` passed. | Removed the temporary RED fixture after the passing focused cycle; no production files were changed after the final checks. |

## Verification evidence

- `backend/.venv/Scripts/python -m pip install -e ".[dev]"`: passed; dependencies installed only in `backend/.venv`.
- From `backend/`: `.venv/Scripts/python .sdd-red/t1_bootstrap_test.py`: passed (1 test).
- From `backend/`: `.venv/Scripts/python -c "from app.main import create_app; create_app()"`: passed.
- From `backend/`: `.venv/Scripts/ruff.exe check .`: passed.
- From `backend/`: `.venv/Scripts/ruff.exe format --check .`: passed (13 files already formatted).
- `git diff --check`: passed.
- No PostgreSQL connection or local database creation was attempted.

## Files changed in this batch

- `backend/pyproject.toml`
- `backend/.env.example`
- `backend/app/__init__.py`
- `backend/app/core/__init__.py`
- `backend/app/core/config.py`
- `backend/app/core/security.py`
- `backend/app/db/__init__.py`
- `backend/app/db/base.py`
- `backend/app/db/session.py`
- `backend/app/main.py`
- `backend/tests/__init__.py`
- `openspec/changes/registro-cliente/tasks.md`
- `openspec/changes/registro-cliente/apply-progress.md`

## Deviations

- No functional deviation from T1 design. The engine/session factory is lazy to keep `create_app()` importable without a configured database and to avoid creating a local database; `DATABASE_URL` remains environment-only.
- The task artifact says standard TDD, while the active phase contract requires strict TDD; this batch followed RED → GREEN → TRIANGULATE → REFACTOR.

## Remaining implementation tasks

- [ ] T2 Inicializar Alembic en `backend/` (`alembic init alembic`), ajustar `alembic.ini` y `alembic/env.py` (apuntar a la metadata de `app.db.base` para revisión explícita) y escribir la revisión inicial con `down_revision = None` que habilita `pgcrypto` (`CREATE EXTENSION IF NOT EXISTS pgcrypto`) y crea ÚNICAMENTE `usuario_global`: `id` UUID PK default `gen_random_uuid()`, `correo` VARCHAR(255) NOT NULL + UNIQUE, `hash_password` VARCHAR(255) NOT NULL, `estado` VARCHAR(20) NOT NULL default `'activo'`, `correo_verificado` BOOLEAN NOT NULL default `false`, `creado_en` TIMESTAMPTZ NOT NULL default `now()`. El `downgrade` elimina solo la tabla; NO elimina `pgcrypto`. NO crear `sesion` ni otras tablas del Sprint 1 (GAP-092 parcial). <!-- sdd-owner: implementation -->
- [ ] T3 Implementar `backend/app/modules/identity/`: `models.py` (`UsuarioGlobal` con `Mapped`/`mapped_column` idéntico columna a columna a la migración de T2), `schemas.py` (`RegistroRequest`: `correo` EmailStr requerido con límite 255; `password` SecretStr requerido `min_length=8` sin reglas de complejidad; `RegistroResponse` SOLO con `id`, `correo`, `estado`, `correo_verificado`, `creado_en`), `repository.py` (`UserRepositoryProtocol` con `buscar_por_correo` y `guardar`; adaptador SQLAlchemy con add/flush/commit/refresh, `rollback()` y traducción de `IntegrityError` estado `23505` a la excepción de dominio), `service.py` (normalización `strip().lower()` idempotente, pre-check de duplicado, `DuplicateEmailError` con el mensaje exacto del dominio, hash Argon2id vía `PasswordHasherProtocol`, mapeo explícito a datos públicos, nunca devuelve contraseña ni hash) y `router.py` (`POST /auth/registro` → 201 con `RegistroResponse`; 409 con `{"detail": "Ya existe una cuenta con este correo"}`; errores de BD NO relacionados con la restricción de correo se propagan, no se convierten en 409). En `main.py`: incluir `identity.router` con `prefix="/api/v1"` y registrar el handler sanitizado de `RequestValidationError` (422 sin `input` ni `password` en el cuerpo). <!-- sdd-owner: implementation -->
- [ ] T4 Crear `backend/tests/unit/modules/identity/` con `test_service.py` (dobles: `FakeRepository` en memoria que simula duplicado en pre-check y `23505` en `guardar`; `PasswordHasher` Argon2id real) y `test_router.py` (TestClient de FastAPI con dependency overrides para repositorio/hasher). Casos mínimos: (1) registro válido → 201 con UUID, correo normalizado a minúsculas, `estado=activo`, `correo_verificado=false`, `creado_en` presente y una sola llamada de guardado; (2) correo inválido → 422, sin cuenta y sin altas; (3) password de 7 caracteres → 422 sin llamar al hasher; (4) duplicado exacto y variante con mayúsculas/espacios → 409 con el mensaje EXACTO `Ya existe una cuenta con este correo`, sin segundo guardado; (5) hash persistido ≠ plaintext y `verify()` de Argon2id acepta la correcta y rechaza otra; (6) ninguna respuesta 201/409/422 expone `hash_password` ni la contraseña; (7) carrera de unicidad simulando `23505` → rollback y mismo 409. <!-- sdd-owner: implementation -->
- [ ] T5 Actualizar `docs/scrum/sprint-1/02-proceso-por-hu.md` §2.1.4 (Implementación): agregar UN párrafo que marque como implementado el módulo S1-02 `identity` para PB-001/HU-001 en su slice backend-first (endpoint `POST /api/v1/auth/registro`, normalización a minúsculas, Argon2id, migración inicial `usuario_global`), precisando que GAP-092 queda parcialmente cubierto (solo la tabla inicial; el resto de las migraciones del Sprint 1 sigue pendiente), y con referencia relativa al change openspec (`openspec/changes/registro-cliente/spec.md` y `tasks.md`). NO tocar §2.1.5 (casos CP-001..CP-013 siguen `not executed`; GAP-087 y GAP-073 vigentes) ni §2.1.4.1 (GAP-088 vigente). El estado de la suite pytest en verde se registra en el apply-progress del change, no como CP ejecutado. <!-- sdd-owner: implementation -->

## Deferred parent-owned lifecycle actions

- [ ] Start or reuse bounded review del slice implementado (contraste con spec REQ-01..07 y design: criterios de terminado de T1..T5, ausencia de datos sensibles en respuestas, cobertura REQ-07). <!-- sdd-owner: parent -->
- [ ] Gate de entrega: consultar al usuario la estrategia de commits/PRs (hoy prohibidos hasta aviso) y resolver la chain strategy pendiente antes de cualquier operación git. <!-- sdd-owner: parent -->

## Workload and PR boundary

- Approved delivery path: four stacked-to-main slices, strategy `stacked-to-main`; no merge to `main`.
- Current boundary: slice 1 of 4, T1 bootstrap only. Parent prompt explicitly authorizes branch commits and pushes for this change, overriding the older task note that prohibited them until notice.
- T2, T3, and T4+T5 remain separate child slices and will not be mixed into this commit.

## Gaps

- `GAP-073`: remains open (implementation/test responsible not assigned in project docs).
- `GAP-087`: remains open; CP-001..CP-013 remain `not executed`.
- `GAP-092`: remains open overall; T1 does not add migrations. T2 will cover only `usuario_global`.
- PostgreSQL integration / `alembic upgrade head` was not run because no local PostgreSQL was available; it remains `not executed` (GAP-092).

## Structured status produced

- After T1: implementation task T1 is complete; T2–T5 remain unchecked; parent-owned lifecycle rows remain unchanged; apply remains in progress and routes to the next implementation slice, not verify or parent lifecycle yet.
