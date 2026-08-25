# Tareas — Autenticación y sesión del cliente (backend)

- **Cambio:** `autenticacion` · **PB:** PB-002 · **HU:** HU-002 · **CU:** CU-002 · **Dominio:** `identity` · **Slice:** backend
- **Fuentes:** [spec.md](./spec.md) (REQ-01..REQ-12) · [design.md](./design.md) · patrón S0-10 · referencia de formato [registro-cliente/tasks.md](../registro-cliente/tasks.md)
- **Modo:** un solo actor de implementación; orden estricto T1→T2→T3→T4→T5 (no paralelizable). Cada T es una unidad autónoma entregable como PR apilado a `main`.
- **Modo TDD:** estricto — RED→GREEN por unidad verificable donde hay lógica pura (T1 servicio de tokens, T3 repositorio de sesiones) y suite de contrato API completa en T5; la evidencia TDD se registra en el apply-progress (patrón del proyecto).
- **Delivery:** `auto-chain` · **Chain:** `stacked-to-main` — cada PR apunta a `main` en secuencia; ramas `feat/autenticacion/tN-<slug>`.

## Reglas de apply (usuario)

- Siguen las reglas del change PB-001 salvo las excepciones de entrega de este slice (auto-chain activo): aplicar y verificar una T a la vez; al pasar el gate de la T, crear su PR a `main` y encadenar la siguiente.
- NO hardcodear secreto JWT, TTLs ni `DATABASE_URL` en el código (S0-10); credenciales solo por `.env`/entorno, con placeholders (nunca valores operativos) en `.env.example`.
- La aplicación NO crea tablas al arrancar (`create_all` prohibido); el esquema lo prepara únicamente Alembic. Dependencias solo dentro del venv del backend (`backend/.venv`).
- NUNCA registrar, persistir ni devolver el refresh en claro, el password ni `hash_password` (REQ-01/03/12); en logs operativos, máximo `sid` anonimizado o correlation id.
- No modificar `0001_crear_usuario_global.py` ni las tablas/lógica existentes de PB-001; reutilizar `buscar_por_correo`, verificación Argon2id y el patrón de constantes de PB-001 sin duplicarlos.

## Review Workload Forecast

| Field | Value |
| ------- | ------- |
| Estimated changed lines | ~1450–1650 (15 archivos tocados + 1 sección de doc actualizada, en 5 T) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR1 (T1 core) → PR2 (T2 migración) → PR3 (T3 repositorio) → PR4 (T4 endpoints) → PR5 (T5 tests+doc) |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

> Nota de forecast: el slice completo supera ampliamente el presupuesto de 400 líneas, por eso se recomienda chain de PRs apilados a `main` con `pytest` en verde antes de encadenar (auto-chain, `stacked-to-main`). Estimación por T: T1 ≈ 310 · T2 ≈ 125 · T3 ≈ 385 · T4 ≈ 405–440 · T5 ≈ 385–420. T3/T4/T5 rozan o superan ligeramente el umbral de 400 líneas; si el diff real de una T cruza el umbral, apply divide esa T en PRs apilados adicionales (p. ej. `t4a-service` / `t4b-router`; `t5a-tests` / `t5b-doc`), documentándolo en el apply-progress. No se requiere `size:exception` bajo auto-chain.

---

## T1 — Núcleo de tokens y configuración (`app/core/`): PyJWT, clock y settings

- [x] T1 Implementar el núcleo de seguridad en `backend/app/core/`: agregar `PyJWT>=2.8,<3` a `pyproject.toml` (sin `python-jose` ni `authlib`); crear `core/config.py` con settings configurables por `.env`/entorno (`JWT_SECRET` sin default operativo y validado no vacío al construir la dependencia de tokens, `access_token_ttl_seconds=900`, `refresh_token_ttl_days=7`, `session_inactivity_minutes=30`); crear `core/clock.py` (`ClockProtocol` + `SystemClock` UTC, datetime aware; sin `datetime.now()` directo en servicios); crear `core/tokens.py` (`TokenServiceProtocol`: `generar_refresh()` con `secrets.token_urlsafe(32)`, `hash_refresh()` → `sha256().hexdigest()`, `emitir_access(*, usuario_id, sesion_id, emitido_en, expira_en)` → JWT HS256 con `sub`/`sid`/`type:"access"`/`iat`/`exp`, `decodificar_access(*, token, ahora)` → claims validando firma, `type`, UUIDs y `exp` contra el clock inyectado) y exponer en `core/security.py` la verificación Argon2id ficticia uniforme para el camino de correo inexistente sin duplicar el hasher de PB-001. Añadir `JWT_SECRET`/TTLs como placeholders (sin secretos) en `.env.example`. <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-03, REQ-10):** a T1 le acompaña un unit test RED→GREEN `backend/tests/test_tokens_core.py` que prueba: firma HS256 valida con el secreto inyectado y rechaza otro; claims `sub`/`sid`/`type:"access"` presentes; `exp - iat == 900`; rechazo por `type != "access"`, firma inválida y `exp` pasado (avanzando un reloj `FakeClock`/fecha controlada sin `sleep`); `refresh_token` es opaco (distinto del hash) y `hash_refresh` = `sha256` hexadecimal; `pytest -q backend/tests/test_tokens_core.py` verde sin PostgreSQL. REQ-10 CA1: sin `JWT_SECRET` en entorno, la construcción del servicio de tokens falla con error de configuración (no arranca con secreto vacío/default).
  - **Nota de secreto:** el design §1.3 y REQ-10 CA1 rechazan un default operativo hardcodeado; el "default dev" es un valor explícito en el entorno local/`.env` (tests inyectan `Settings(jwt_secret="test-secret-...")`), nunca embebido en el código. `APP_ENV=production` exige `JWT_SECRET` provisto por entorno.
  - **Archivos objetivo:** `backend/pyproject.toml`, `backend/.env.example`, `backend/app/core/__init__.py`, `backend/app/core/config.py`, `backend/app/core/clock.py`, `backend/app/core/tokens.py`, `backend/app/core/security.py`, `backend/tests/test_tokens_core.py`.
  - **Dependencias:** ninguna (primera tarea; sobre la base de PB-001).
  - **Estimación:** M (~3.5 h) — escala S/M/L del Sprint 1.

---

## T2 — Modelo `Sesion` y migración Alembic `0002_crear_sesion.py`

- [x] T2 Agregar el modelo `Sesion` en `backend/app/modules/identity/models.py` replicando columna a columna REQ-04/design §3.1 (`id` UUID PK default `gen_random_uuid()`, `usuario_global_id` UUID NOT NULL FK → `usuario_global.id`, `refresh_token_hash` CHAR(64) NOT NULL UNIQUE, `expira_en` TIMESTAMPTZ NOT NULL, `ultima_actividad` TIMESTAMPTZ NULL, `revocado` BOOLEAN NOT NULL default `false`) con `UNIQUE(refresh_token_hash)` nombrado `uq_sesion_refresh_token_hash` e índice (`usuario_global_id`, `revocado`) nombrado `ix_sesion_usuario_global_revocado`; escribir a mano la migración `backend/alembic/versions/0002_crear_sesion.py` con `revision="0002"`, `down_revision="0001"` que crea ÚNICAMENTE `sesion` (FK, UNIQUE e índice) y cuyo `downgrade` retira solo `sesion`; actualizar `backend/alembic/env.py` para importar explícitamente `UsuarioGlobal` y `Sesion` antes de exponer `Base.metadata`. NO modificar `0001`. <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-04):** desde `backend/`, `alembic upgrade head --sql` muestra `CREATE TABLE sesion` (con FK a `usuario_global.id`, UNIQUE y el índice) y NO contiene otras tablas del Sprint 1; `alembic downgrade 0001 --sql` genera el `DROP TABLE sesion` y conserva `usuario_global`; el modelo coincide 1:1 con la migración `0002` (sin columna `jti`; `sid` es la PK de sesión). La aplicación real contra PostgreSQL queda condicionada al entorno de integración (GAP-092; la suite unitaria no la requiere).
  - **Archivos objetivo:** `backend/app/modules/identity/models.py`, `backend/alembic/versions/0002_crear_sesion.py`, `backend/alembic/env.py`.
  - **Dependencias:** T1 (base de settings/tokens intacta; `models.py` ya existe por PB-001).
  - **Estimación:** S (~1.5 h).

---

## T3 — `SessionRepository` (protocolo + adaptador SQLAlchemy + fake) con rotación transaccional

- [x] T3 Implementar en `backend/app/modules/identity/repository.py` el `SessionRepositoryProtocol` y el adaptador SQLAlchemy: `crear(usuario_global_id, refresh_token_hash, expira_en, ultima_actividad, session_id)`, `buscar_por_hash` y `buscar_por_id` (búsqueda por hash, nunca por valor en claro), `rotar_por_hash(hash_anterior, nueva_sesion, ahora, ventana)` transaccional y única con `SELECT ... FOR UPDATE` (sin TOCTOU: busca y valida bajo lock, revoca la fila anterior e inserta la nueva en la misma transacción con commit único; ante `IntegrityError` del hash único hace rollback y no deja estados parciales), `validar_y_actualizar_actividad(session_id, usuario_id, ahora, ventana)` (rechaza `revocado=true`, `expira_en` pasado, `ultima_actividad` NULL o `ahora > ultima_actividad + ventana`; revocación lazy y commit al invalidar; update de actividad bajo lock al validar), y `revocar_por_hash` / `revocar` idempotentes. Crear `FakeSessionRepository` para tests con `threading.RLock` alrededor de rotación y validación (single-writer observable), que solo guarda hashes y nunca texto claro. <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-05):** a T3 le acompaña un unit test RED→GREEN `backend/tests/test_session_repository.py` (sobre el fake): crear → fila `revocado=false`, hash único e `ultima_actividad` inicial; rotar → el hash anterior queda `revocado=true` y reutilizarlo es rechazado (`sesion_valida=false`); dos rotaciones concurrentes del mismo hash → como máximo un par válido (single-writer); actividad a 29 min válida vs. 31 min → rechazo y revocación lazy sin revivir; `revocar` idempotente; `pytest -q backend/tests/test_session_repository.py` verde sin PostgreSQL. Las validaciones de sesión se expresan mediante un método/protocolo de dominio (`sesion_valida`) del que dependen refresh, `me` y reuso.
  - **Archivos objetivo:** `backend/app/modules/identity/repository.py`, `backend/tests/test_session_repository.py`.
  - **Dependencias:** T2 (modelo `Sesion`).
  - **Estimación:** M–L (~4 h).

---

## T4 — Endpoints de autenticación, `get_current_user` y composición en `main.py`

- [x] T4 Implementar la superficie HTTP del slice en el módulo `identity` siguiendo S0-10: `schemas.py` (requests `LoginRequest` `correo` EmailStr + `password` SecretStr ≥ 8, `RefreshRequest`/`LogoutRequest` con `refresh_token` SecretStr no vacío, `TokenResponse` SOLO `access_token`/`refresh_token`/`expira_en`, `MeResponse` SOLO `id`/`correo`; nunca exponen password, hashes ni `expires_in`); `service.py` (`AuthenticationService` con `login` — normaliza `strip().lower()`, verifica Argon2id uniforme contra hash real o ficticio, rechazo por `estado != "activo"`, emite access con `sid` y crea la sesión con `ultima_actividad=now` —, `refresh` rotatorio con TTL absoluto por emisión sin revivir, `logout` idempotente y no enumerativo, y `me` con payload mínimo; excepciones internas `InvalidCredentialsError`/`InvalidSessionError` que nunca contienen tokens/password); `router.py` con `POST /auth/login` (200/401 `INVALID_CREDENTIALS_MESSAGE`/422), `POST /auth/refresh` (200/401 `INVALID_SESSION_MESSAGE`/422), `POST /auth/logout` (204 idempotente/422) y `GET /auth/me` (200/401) usando `HTTPBearer(auto_error=False)` para traducir ausencia/malformación a 401 (nunca 403); constantes de dominio `INVALID_CREDENTIALS_MESSAGE = "Correo o contraseña inválidos"` e `INVALID_SESSION_MESSAGE = "Sesión inválida o expirada"`; y la dependency `get_current_user` con validación server-side de la sesión (decodifica `sid`, verifica `sesion.id == sid` y `usuario_global_id == sub`, rechaza revocado/`expira_en`/inactividad sliding con `Clock` inyectable). Registrar en `app/main.py` el router `identity` bajo `prefix="/api/v1"` (extendiendo el registro de PB-001). <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-01/02/06/07/08/10/11):** desde `backend/`, el OpenAPI lista las cuatro rutas `/api/v1/auth/{login,refresh,logout,me}`; request malformado → 422 sin consultar credenciales ni crear sesión; login válido → 200 con los tres campos y sin `hash_password`/password/hash de refresh; login inexistente vs. contraseña incorrecta → mismo 401 y mismo `detail`; refresh anterior rotado o logout → 401 `Sesión inválida o expirada`; logout con refresh desconocido/ya revocado → 204; `me` válido → 200 `{id, correo}` y `me` sin header/token inválido → 401 (no 403); el router no contiene SQL ni lógica de persistencia ni llamadas a `datetime.now()`.
  - **Archivos objetivo:** `backend/app/modules/identity/__init__.py`, `backend/app/modules/identity/schemas.py`, `backend/app/modules/identity/service.py`, `backend/app/modules/identity/router.py`, `backend/app/main.py`.
  - **Dependencias:** T1 (tokens/clock/config), T3 (repositorio y fake).
  - **Estimación:** L (~5 h).

---

## T5 — Suite de tests TDD de contrato (REQ-12, CP-002) y documentación §2.1.4

- [x] T5 Crear `backend/tests/test_autenticacion.py` (espejo del patrón de `tests/test_registro.py` con `create_app()` y `dependency_overrides` sobre `FakeUserRepository`, `FakeSessionRepository`, `FakeTokenService`/`PyJWTTokenService` y `FakeClock`, todos sin instancia PostgreSQL real) cubriendo CP-002 completo (5 pasos) y los 9 casos mínimos de REQ-12: (1) login válido emite access+refresh+`expira_en` y persiste en el fake solo SHA-256 del refresh; (2) correo inexistente vs. contraseña incorrecta → mismo 401 y mismo `detail` (no enumeración); (3) actividad autenticada a 29 min → sigue válida y actualiza `ultima_actividad`; (4) sin actividad 31 min → `/me` y refresh rechazan con genérico y la fila queda `revocado=true`; (5) logout revoca el refresh y su reutilización responde `401`; (6) rotación: el refresh anterior reutilizado responde 401 genérico y el par nuevo sigue válido; (7) `/me` rechaza access ausente, malformado, expirado y de sesión inválida con 401 (nunca 403); (8) ningún refresh en claro en respuestas ni en la persistencia del fake; (9) los 401 de login y de sesión usan exactamente sus constantes y 422 por validación. Actualizar `docs/scrum/sprint-1/02-proceso-por-hu.md` §2.1.4 (Implementación) con UN párrafo que marque implementado el módulo S1-02 `identity` para PB-002/HU-002 en su slice backend (login/refresh/logout/me, access JWT + refresh opaco hasheado, tabla `sesion` migración `0002`, inactividad sliding 30 min), con referencia relativa a `openspec/changes/autenticacion/spec.md`/`tasks.md`; NO tocar §2.1.5 (CPs siguen `not executed`; GAP-087/073) ni §2.1.4.1. <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-12, HU-002 CA):** desde `backend/` con el venv activo, `pytest -q` deja TODA la suite en verde (incluye `test_tokens_core.py`, `test_session_repository.py` y `test_autenticacion.py`) sin PostgreSQL ni servicios externos; los 5 pasos de CP-002 y los 6 criterios de aceptación del slice tienen cobertura reproducible; el párrafo de §2.1.4 existe con IDs estables (PB-002/HU-002) y enlace relativo válido, el estado de la suite en verde se registra en el apply-progress y no se afirman CP ejecutados ni diagramas.
  - **Archivos objetivo:** `backend/tests/__init__.py`, `backend/tests/test_autenticacion.py`, `docs/scrum/sprint-1/02-proceso-por-hu.md`.
  - **Dependencias:** T1, T3 (fakes/clock y unit tests previos), T4 (contrato HTTP).
  - **Estimación:** L (~5 h).

---

## Acciones de orquestador (post-apply; NO las ejecuta el actor de implementación)

- [ ] Start or reuse bounded review del slice implementado (contraste con spec REQ-01..REQ-12 y design: criterios de terminado de T1..T5, ausencia de refresh/password/hashes en respuestas y logs, cobertura CP-002 y REQ-12, resolución del vínculo access↔`sesion` vía `sid`). <!-- sdd-owner: parent -->
- [ ] Gate de entrega chain (`auto-chain` → `stacked-to-main`): verificar por T que el diff ≤ ~400 líneas (dividiendo internamente una T si cruza el umbral), validar `pytest -q` verde por PR, correr los gates de entrega por PR (pre-commit/pre-pr) y crear en secuencia las ramas `feat/autenticacion/tN-<slug>` y sus PRs a `main` (5 PRs según el split del forecast; documentar cada PR en el apply-progress). <!-- sdd-owner: parent -->

## Trazabilidad rápida

| Tarea | REQ | HU-002 CA | Fuente de diseño |
| ------- | ----- | ----------- | ------------------ |
| T1 Núcleo de tokens | REQ-03, REQ-10 | CA1 | design §1.1, §1.3, §4.1, §2.1 |
| T2 Modelo + migración `0002` | REQ-04 | CA1 | design §3.1, §3.2 |
| T3 SessionRepository + fake | REQ-05 | CA1 | design §4.2, §5, §7 |
| T4 Endpoints + `get_current_user` | REQ-01, REQ-02, REQ-06, REQ-07, REQ-08, REQ-11 | CA1, CA error genérico, CA inactividad | design §1.1, §5, §6, §9 |
| T5 Tests + doc | REQ-12 | CA1 | design §8, skill documentacion-software; GAP-092 |
