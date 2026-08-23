# Tareas — Registro de cliente con correo y contraseña (backend)

- **Cambio:** `registro-cliente` · **PB:** PB-001 · **HU:** HU-001 · **CU:** CU-001 · **Dominio:** `identity` · **Slice:** backend
- **Fuentes:** [spec.md](./spec.md) (REQ-01..07) · [design.md](./design.md) · patrón S0-10
- **Modo:** un solo actor de implementación; orden estricto T1→T2→T3→T4→T5 (no paralelizable).
- **Modo TDD:** estándar (strict TDD deshabilitado en `sdd-init`); los tests se escriben en T4 contra el módulo implementado, y cada unidad del chain DEBE quedar con `pytest` en verde.

## Reglas de apply (usuario)

- NO ejecutar `git commit` / `git push` hasta aviso explícito del usuario.
- Instalar dependencias solo dentro del venv del backend (`backend/.venv`); no instalar nada a nivel global ni del sistema.
- La aplicación NO crea tablas al arrancar (`create_all` prohibido); el esquema lo prepara únicamente Alembic.
- No hardcodear `DATABASE_URL` ni parámetros Argon2id en el código (S0-10: configuración solo por `.env`/entorno).

## Review Workload Forecast

| Field | Value |
| ------- | ------- |
| Estimated changed lines | ~850–950 (16 archivos nuevos + 1 sección de doc actualizada) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (T1) → PR 2 (T2) → PR 3 (T3) → PR 4 (T4+T5) |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

> Nota de forecast: el slice se divide en 4 unidades autónomas verificables (bootstrap / migración / módulo / tests+doc), cada una bajo ~400 líneas, pero el total supera el presupuesto. Por eso se recomienda chain de PRs con `pytest` en verde antes de encadenar. Como hoy rige "sin commits hasta aviso", la decisión de chain queda diferida al gate de entrega (acción de parent al final). Alternativa admisible solo con `size:exception`: PR único de todo el slice.

---

## T1 — Bootstrap del backend FastAPI (config, sesión, seguridad, plantilla de app)

- [x] T1 Crear el esqueleto funcional del backend: `pyproject.toml` (runtime: `fastapi`, `uvicorn`, `sqlalchemy>=2`, `pydantic[email]`, `pydantic-settings`, `argon2-cffi`, `alembic`, `psycopg[binary]`; dev: `pytest`, `httpx`, `ruff`), `backend/.env.example` con solo nombres y valores de desarrollo no sensibles, `backend/app/core/config.py` (Settings vía pydantic-settings: `DATABASE_URL`, `ARGON2_TIME_COST`, `ARGON2_MEMORY_COST`, `ARGON2_PARALLELISM`, `ARGON2_HASH_LEN`, `ARGON2_SALT_LEN`, `APP_ENV`; `get_settings()` cacheada, `extra="ignore"`), `backend/app/core/security.py` (fábrica `PasswordHasher(type=Type.ID, ...)` configurada desde settings), `backend/app/db/base.py` (DeclarativeBase), `backend/app/db/session.py` (engine, `sessionmaker(autoflush=False, expire_on_commit=False)`, `get_db()` generador que cierra la sesión en `finally`) y `backend/app/main.py` (fábrica `create_app()` que carga settings; el montaje del router `identity` y el handler 422 sanitizado llegan en T3). <!-- sdd-owner: implementation -->
  - **Criterio de terminado:** desde `backend/`, `python -c "from app.main import create_app; create_app()"` importa y ejecuta sin errores; `ruff check backend/` sin errores; `.env.example` no contiene secretos ni valores reales; `get_db()` garantiza cierre de sesión en `finally`.
  - **Archivos objetivo:** `backend/pyproject.toml`, `backend/.env.example`, `backend/app/__init__.py`, `backend/app/main.py`, `backend/app/core/__init__.py`, `backend/app/core/config.py`, `backend/app/core/security.py`, `backend/app/db/__init__.py`, `backend/app/db/base.py`, `backend/app/db/session.py`.
  - **Dependencias:** ninguna (primera tarea).
  - **Estimación:** M (~3 h) — escala S/M/L del Sprint 1.

> **Nota técnica (driver):** el design aprobado (§2.4, §3.3) fija sesión SQLAlchemy 2.x **síncrona** con driver `psycopg` (`postgresql+psycopg://`). Por eso T1 usa `psycopg[binary]` y NO `asyncpg` (driver asíncrono, incompatible con la sesión síncrona del diseño).

---

## T2 — Migración inicial Alembic (`usuario_global`)

- [x] T2 Inicializar Alembic en `backend/` (`alembic init alembic`), ajustar `alembic.ini` y `alembic/env.py` (apuntar a la metadata de `app.db.base` para revisión explícita) y escribir la revisión inicial con `down_revision = None` que habilita `pgcrypto` (`CREATE EXTENSION IF NOT EXISTS pgcrypto`) y crea ÚNICAMENTE `usuario_global`: `id` UUID PK default `gen_random_uuid()`, `correo` VARCHAR(255) NOT NULL + UNIQUE, `hash_password` VARCHAR(255) NOT NULL, `estado` VARCHAR(20) NOT NULL default `'activo'`, `correo_verificado` BOOLEAN NOT NULL default `false`, `creado_en` TIMESTAMPTZ NOT NULL default `now()`. El `downgrade` elimina solo la tabla; NO elimina `pgcrypto`. NO crear `sesion` ni otras tablas del Sprint 1 (GAP-092 parcial). <!-- sdd-owner: implementation -->
  - **Criterio de terminado:** `alembic upgrade head --sql` muestra `CREATE TABLE usuario_global` y NO contiene `sesion` ni otras tablas del Sprint 1; `alembic downgrade base --sql` genera el `DROP TABLE usuario_global`; la revisión está escrita a mano, sin autogeneración. La aplicación real de `upgrade head` contra PostgreSQL queda condicionada al entorno Docker/Floci (riesgo conocido del spec y del design §9).
  - **Archivos objetivo:** `backend/alembic.ini`, `backend/alembic/env.py`, `backend/alembic/script.py.mako`, `backend/alembic/versions/<rev>_crear_usuario_global.py`.
  - **Dependencias:** T1.
  - **Estimación:** S (~1.5 h).

---

## T3 — Módulo `identity` completo (models, schemas, repository, service, router) + integración en main

- [x] T3 Implementar `backend/app/modules/identity/`: `models.py` (`UsuarioGlobal` con `Mapped`/`mapped_column` idéntico columna a columna a la migración de T2), `schemas.py` (`RegistroRequest`: `correo` EmailStr requerido con límite 255; `password` SecretStr requerido `min_length=8` sin reglas de complejidad; `RegistroResponse` SOLO con `id`, `correo`, `estado`, `correo_verificado`, `creado_en`), `repository.py` (`UserRepositoryProtocol` con `buscar_por_correo` y `guardar`; adaptador SQLAlchemy con add/flush/commit/refresh, `rollback()` y traducción de `IntegrityError` estado `23505` a la excepción de dominio), `service.py` (normalización `strip().lower()` idempotente, pre-check de duplicado, `DuplicateEmailError` con el mensaje exacto del dominio, hash Argon2id vía `PasswordHasherProtocol`, mapeo explícito a datos públicos, nunca devuelve contraseña ni hash) y `router.py` (`POST /auth/registro` → 201 con `RegistroResponse`; 409 con `{"detail": "Ya existe una cuenta con este correo"}`; errores de BD NO relacionados con la restricción de correo se propagan, no se convierten en 409). En `main.py`: incluir `identity.router` con `prefix="/api/v1"` y registrar el handler sanitizado de `RequestValidationError` (422 sin `input` ni `password` en el cuerpo). <!-- sdd-owner: implementation -->
  - **Criterio de terminado:** desde `backend/`, smoke con TestClient en `python -c`: request inválido → 422 y el cuerpo NO contiene la contraseña enviada; la ruta figura en OpenAPI como `POST /api/v1/auth/registro`; `models.py` y la migración de T2 coinciden 1:1; no hay `DATABASE_URL` ni credenciales hardcodeados; el router no contiene SQL ni reglas de persistencia (S0-10).
  - **Archivos objetivo:** `backend/app/modules/__init__.py`, `backend/app/modules/identity/__init__.py`, `backend/app/modules/identity/models.py`, `schemas.py`, `repository.py`, `service.py`, `router.py`; modificación de `backend/app/main.py`.
  - **Dependencias:** T2.
  - **Estimación:** L (~5 h).

---

## T4 — Pruebas unitarias pytest (REQ-07: 7 casos, sin PostgreSQL)

- [ ] T4 Crear `backend/tests/unit/modules/identity/` con `test_service.py` (dobles: `FakeRepository` en memoria que simula duplicado en pre-check y `23505` en `guardar`; `PasswordHasher` Argon2id real) y `test_router.py` (TestClient de FastAPI con dependency overrides para repositorio/hasher). Casos mínimos: (1) registro válido → 201 con UUID, correo normalizado a minúsculas, `estado=activo`, `correo_verificado=false`, `creado_en` presente y una sola llamada de guardado; (2) correo inválido → 422, sin cuenta y sin altas; (3) password de 7 caracteres → 422 sin llamar al hasher; (4) duplicado exacto y variante con mayúsculas/espacios → 409 con el mensaje EXACTO `Ya existe una cuenta con este correo`, sin segundo guardado; (5) hash persistido ≠ plaintext y `verify()` de Argon2id acepta la correcta y rechaza otra; (6) ninguna respuesta 201/409/422 expone `hash_password` ni la contraseña; (7) carrera de unicidad simulando `23505` → rollback y mismo 409. <!-- sdd-owner: implementation -->
  - **Criterio de terminado:** desde `backend/` con el venv activo, `pytest -q` → todos los casos en verde; la suite corre sin PostgreSQL ni servicios externos (REQ-07 CA6); los 5 criterios de aceptación de la propuesta quedan cubiertos (REQ-07 CA1..CA5).
  - **Archivos objetivo:** `backend/tests/__init__.py`, `backend/tests/unit/__init__.py`, `backend/tests/unit/modules/__init__.py`, `backend/tests/unit/modules/identity/__init__.py`, `backend/tests/unit/modules/identity/test_service.py`, `backend/tests/unit/modules/identity/test_router.py`, `backend/tests/unit/modules/identity/conftest.py` (solo si hace falta para overrides compartidos).
  - **Dependencias:** T3.
  - **Estimación:** M (~3 h).

---

## T5 — Documentación del slice (S1-02 §2.1.4, consistente con el repositorio)

- [ ] T5 Actualizar `docs/scrum/sprint-1/02-proceso-por-hu.md` §2.1.4 (Implementación): agregar UN párrafo que marque como implementado el módulo S1-02 `identity` para PB-001/HU-001 en su slice backend-first (endpoint `POST /api/v1/auth/registro`, normalización a minúsculas, Argon2id, migración inicial `usuario_global`), precisando que GAP-092 queda parcialmente cubierto (solo la tabla inicial; el resto de las migraciones del Sprint 1 sigue pendiente), y con referencia relativa al change openspec (`openspec/changes/registro-cliente/spec.md` y `tasks.md`). NO tocar §2.1.5 (casos CP-001..CP-013 siguen `not executed`; GAP-087 y GAP-073 vigentes) ni §2.1.4.1 (GAP-088 vigente). El estado de la suite pytest en verde se registra en el apply-progress del change, no como CP ejecutado. <!-- sdd-owner: implementation -->
  - **Criterio de terminado:** párrafo presente en §2.1.4 con IDs estables (PB-001/HU-001) y enlace relativo válido; no se afirman pruebas CP ejecutadas ni diagramas; no se rompen IDs ni estados existentes del documento.
  - **Archivos objetivo:** `docs/scrum/sprint-1/02-proceso-por-hu.md`.
  - **Dependencias:** T4.
  - **Estimación:** S (~0.5 h).

---

## Acciones de orquestador (post-apply; NO las ejecuta el actor de implementación)

- [ ] Start or reuse bounded review del slice implementado (contraste con spec REQ-01..07 y design: criterios de terminado de T1..T5, ausencia de datos sensibles en respuestas, cobertura REQ-07). <!-- sdd-owner: parent -->
- [ ] Gate de entrega: consultar al usuario la estrategia de commits/PRs (hoy prohibidos hasta aviso) y resolver la chain strategy pendiente antes de cualquier operación git. <!-- sdd-owner: parent -->

## Trazabilidad rápida

| Tarea | REQ | HU-001 CA | Fuente de diseño |
| ------- | ----- | ----------- | ------------------ |
| T1 Bootstrap | REQ-06 | — | design §2.3, §2.4 |
| T2 Migración | REQ-05 | CA2 | design §3.1, §3.2 |
| T3 Módulo identity | REQ-01..04, REQ-06 | CA1..CA4 | design §2.2, §4, §5 |
| T4 Tests | REQ-07 | CA1..CA4 | design §7 |
| T5 Documentación | — | — | skill documentacion-software; GAP-087/088/092 |
