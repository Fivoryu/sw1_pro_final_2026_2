# Catálogo, ofertas y reservas de RoomForge

## Objetivo

Completar la superficie del cliente móvil para descubrir publicaciones aprobadas, obtener cotizaciones autoritativas del servidor y solicitar reservas con depósito de prueba. Entregar el contrato API y el escrow local necesarios para ese flujo, sin presentar prototipos como transacciones reales.

## Flujo y autorizaciones

- Workflow: Organic Driven Development (ODD), **sin SDD**, por instrucción explícita del usuario.
- El usuario autorizó trabajar en `apps/cliente_mobile/**`, `backend/**` y `contracts/**` para este flujo.
- En esta sesión, el usuario confirmó que rija el alcance integral de este documento, no solo el corte previo F04.4 + F05.
- No modificar `panel/**`, `apps/captura_mobile/**`, `worker3d/**`, el modelo EA ni otros worktrees.
- Sin commit, push, merge a main ni PR sin autorización explícita. Preservar los cambios de otros worktrees.
- TDD estricto para cambios de comportamiento. No declarar verdes pruebas que no se ejecutaron.

## Reglas de producto confirmadas

- El catálogo público contiene solamente publicaciones aprobadas/publicadas y es visible entre agencias.
- Filtros del cliente: ciudad/zona, operación (venta/alquiler), precio base, habitaciones y baños.
- El precio base no incluye muebles opcionales. Venta: extras de pago único; alquiler: base y extras mensuales. El servidor calcula y devuelve el desglose; ocultar un mueble en 3D no cambia la oferta.
- El recorrido será 3D sencillo de un inmueble de un piso con ambientes conectados manualmente; no se promete reconstrucción fotorrealista.
- La reserva usa una wallet externa y token de prueba; RoomForge no custodia claves de clientes ni de agencias. Decisión del usuario: el cliente mantiene una cuenta RoomForge y vincula/verifica su wallet; la wallet no reemplaza la cuenta.
- Depósito: monto fijo por inmueble, independiente del total de la oferta. La agencia dispone de 24 horas contadas desde la creación de la solicitud en la API.
- Solo puede existir una reserva pendiente por inmueble. Rechazo, cancelación mientras siga pendiente o vencimiento reembolsan el depósito; aceptación libera el depósito a la agencia.
- La wallet de la agencia ejecuta en cadena tanto la aceptación como el rechazo. Para que el escrow respete el timestamp API anterior al depósito, el usuario autorizó permisos EIP-712 firmados por una clave de servicio del backend; esa clave no representa ni custodia las wallets de cliente/agencia.
- La venta o alquiler legal sucede fuera del sistema. No implementar pago completo, suscripciones de agencias ni dinero real.

## Estado y base de trabajo

- CC-01 completada: app Flutter con shell honesto, pruebas de widget y runners Android/iOS. `flutter test` (2), `flutter analyze` y `flutter build apk --debug` pasan; iOS no compilado por Windows sin Xcode; no se afirma smoke en dispositivo.
- AGENCY-2 está incorporado en la base actual `b6a468a`: `Agency.id` es `String(36)`, `StaffAccount.tenant_id` referencia `agency.id`, y Alembic llega a `0004_staff_invitation_pending_email_unique`. El feature worktree se adelantó sin commit desde `17b4dc1`; los cambios Flutter no staged se conservaron y el checkout `main` sucio no se tocó.
- `identity/session.py:get_active_staff` valida Bearer/sesión de personal y devuelve rol/tenant; todavía no hay política genérica de roles para catálogo. Derivar tenant del principal autenticado y autorizar explícitamente por rol, sin reutilizar identidad staff como cliente.
- En `b6a468a` no hay autenticación de cliente, catálogo, precios ni reservas; `get_active_staff` es únicamente para personal. Mantener identidad/sesión y validación de cliente separadas; no reutilizar router, TOTP, `StaffSession` ni `get_active_staff`. La relación entre el signing key/audience de JWT de cliente y staff sigue sin decidir. `contracts/**` no contiene implementación Solidity/Hardhat.

## Decisiones no fijadas y guardas

- La moneda, precisión/redondeo y formato final de importes siguen pendientes: no inferir moneda ni convertir. Usar aritmética exacta, moneda explícita por oferta y validación; documentar cualquier convención técnica propuesta.
- El monto del depósito, símbolo/decimales/suministro del token y `chainId` no están elegidos. Contrato parametrizable; valores de pruebas son fixtures locales claramente marcados. Solo Hardhat local; no desplegar a testnet ni usar fondos reales sin aprobación posterior.
- El proveedor/SDK de wallet móvil y su configuración pública siguen pendientes; no incluir project IDs ni claves reales en Git. Para CC-03, decisión técnica propuesta: verificar la vinculación con un challenge EIP-191 `personal_sign` de un solo uso y TTL de 5 minutos, ligado a cuenta, dirección, propósito y nonce; no requiere fijar chainId para probar posesión de dirección. El permiso de depósito EIP-712 sigue siendo distinto.
- La cuenta de cliente y la wallet externa vinculada son identidades separadas. La reserva usa una wallet verificada del cliente autenticado; no aceptar direcciones arbitrarias del body.
- El usuario aprobó estas invariantes PB-001/PB-002 para CC-03A: email normalizado/único, password mínimo 8 con Argon2id, access JWT 15 min, refresh opaco rotatorio de 7 días por token e inactividad deslizante de 30 min; también eligió `JWT_SECRET` compartido + audience de cliente. El usuario aprobó el wire contract mínimo registrado abajo: cuenta lista para login inmediatamente, sin verificación/campos de activación ni auto-login. Las fuentes canónicas aportan los requisitos generales de autenticación segura, no el formato HTTP.
- Vincular la wallet de agencia mediante prueba de control; no confiar en una dirección enviada sin verificación.
- El permiso EIP-712 del backend vincula como mínimo la solicitud/quote, cliente, inmueble, versión comercial, monto/token configurado, `created_at`, expiración y nonce. La clave de firma debe venir de configuración secreta y fallar cerrado si falta; nunca persistir el secreto en el repo.
- Namespace de autenticación resuelto por el usuario: preservar `/api/v1/auth/*` actual para personal y separar cliente bajo `/api/v1/customer/auth/*`. La guía histórica que asigna `/api/v1/auth/register` al cliente debe señalarse como obsoleta para esta base y actualizarse sin mover las rutas staff.

## CC-03 work unit plan

### Allowed edit surfaces

- `backend/app/modules/customer_identity/**` — new customer account, session, and wallet-link module.
- `backend/app/main.py` — register the separate customer router.
- `backend/app/core/config.py` — customer session and wallet-challenge TTL settings.
- `backend/alembic/env.py` — import the new models for Alembic metadata.
- `backend/alembic/versions/0005_customer_identity.py` — new migration after revision `0004`.
- `backend/tests/test_customer_identity.py` — new focused behavior/regression tests.
- `backend/tests/test_staff_identity.py` and `backend/tests/test_staff_identity_tdd.py` — adjust only route-scope assertions/regressions required to preserve staff behavior while adding customer routes.
- `backend/pyproject.toml` — declare Ethereum message-recovery dependency.

No edits outside these surfaces in CC-03; do not change the existing staff router/models/session behavior or local `.env` files.

### CC-03A approved wire contract

- Namespace/routes: `/api/v1/customer/auth/{register,login,refresh,logout,me}`.
- `POST register`: JSON `{email, password}`; `201` with `{id, email}`; account can log in immediately; no auto-login, email verification, `estado`, or `correo_verificado`.
- `POST login`: JSON `{email, password}`; `200` with `{access_token, refresh_token, token_type: "Bearer", access_expires_in: 900}`; invalid credentials return generic `401`.
- `POST refresh`: JSON `{refresh_token}`; `200` with rotated tokens and `access_expires_in: 900`; invalid refresh/inactive session returns generic `401`.
- `POST logout`: JSON `{refresh_token}`; revoke the corresponding session; always `204`, without distinguishing unknown/expired tokens.
- `GET me`: Bearer access JWT signed with shared `JWT_SECRET`, `aud=roomforge-customer`, plus customer-only account/session validation; `200` with `{id, email}`.
- Errors use `{error:{code, fields?}}`: `409` email conflict, `422` validation, `401` credential/session; never include or log passwords/tokens. No email-recovery endpoint.

### Test and implementation evidence

- Baseline before backend source edits: full pytest `91 passed, 2 skipped`; Ruff clean; Pyright `0 errors, 0 warnings, 0 informations`.
- TDD is strict: add customer API/isolation tests first, observe RED, then implement and record GREEN. Wallet-proof tests belong to CC-03B, not this account/session slice.
- CC-03A resumed writer TDD: approved-contract tests observed RED (**7 failed, 1 warning**) then focused GREEN (**7 passed, 1 warning**) with `cd backend && PYTHONDONTWRITEBYTECODE=1 python -m pytest tests/test_customer_identity.py -q`. One intermediate test-only SQLite timestamp/string assertion was corrected before the passing rerun. No separate refactor pass was reported.
- Independent verification before remediation: full suite **2 failed, 96 passed, 2 skipped** due staff tests with global OpenAPI assertions; it also found that the global validation handler altered staff 422 bodies and OpenAPI omitted customer error schemas/email format. Ruff/Pyright were unavailable on PATH; Alembic graph/head passed (`0005` head; linear `0005→0004→0003→0002→0001`), no real DB upgrade. Starlette/httpx deprecation and migration-reflection warnings remain.
- Remediation TDD: tests first observed RED (**2 failed, 9 passed, 1 warning**), then GREEN (**11 passed, 1 warning**) with `cd backend && PYTHONDONTWRITEBYTECODE=1 python -m pytest tests/test_customer_identity.py tests/test_staff_identity.py::test_operator_invitation_is_one_time_and_not_exposed_by_public_route tests/test_staff_identity.py::test_malformed_staff_login_uses_default_fastapi_validation_response tests/test_staff_identity_tdd.py::test_bootstrap_is_not_exposed_as_a_public_api_route -q`. Staff path assertions are scoped; customer error schemas and email format are documented.
- Independent verification after first remediation: full suite **100 passed, 2 skipped, 4 warnings**; Ruff via `python -m ruff check app tests` passed. Pyright unavailable (`No module named pyright`). Customer OpenAPI/error tests and migration graph pass. A disposable SQLite upgrade stamped at `0004` through `0005` passed; full SQLite chain stops at `0002` (unsupported constraint alteration); PostgreSQL remains unverified. This pass found staff 422 differed from HEAD; the follow-up below restores it.
- Final 422 compatibility TDD: exact baseline staff response test observed RED (**1 failed, 1 warning**) then GREEN with the customer 422 regression (**2 passed, 1 warning**), using the commands recorded in the writer report. Non-customer errors now return `{"detail":"Request validation failed"}`; customer auth still returns its sanitized envelope.
- Independent verifier before the `/me` test: full suite **100 passed, 2 skipped, 4 warnings**; Ruff passed; Pyright unavailable in the worktree Python. OpenAPI, staff/customer 422 bodies, and migration graph passed; it found the missing direct `/me` activity test.
- Final independent verifier after that test: full suite **101 passed, 2 skipped, 4 warnings**; Ruff passed; focused `/me` test passed. It confirmed exact staff/customer 422 bodies, OpenAPI schemas, namespace and customer audience/session separation, Alembic head/history, and unchanged `git status`. Worktree Python lacked Pyright; the existing project `.venv/Scripts/pyright.exe` was run read-only against `app tests` and reported **0 errors, 0 warnings, 0 informations** (no install). SQLite `0004→0005` was previously verified; PostgreSQL migration remains unverified. Warnings: Starlette/httpx deprecation, per-request cookies, and two SQLAlchemy expression-index reflection warnings.
- `/me` sliding-inactivity coverage: test-only addition `test_customer_me_slides_idle_window_for_refresh` passed (**1 passed, 1 warning**); the full customer test file passed (**9 passed, 1 warning**). It verifies activity at 14 minutes and refresh 17 minutes later. RED was intentionally not run because this adds coverage for already-implemented behavior and changes no source.
- Writer changes: customer identity `errors.py`, models/schemas/service/session/router, `backend/app/main.py`, `backend/alembic/env.py`, migration `0005_customer_identity.py`, and `backend/tests/test_customer_identity.py`. Staff auth internals were not changed per writer report.
- The existing venv under the separate root checkout lacks `eth-account`; do not install into or otherwise alter that shared environment. If the new dependency is needed for GREEN, use a temporary isolated environment outside both worktrees and report exact commands.
- Customer tokens must not authenticate through staff routes or use staff sessions. Writer reports `aud=roomforge-customer` and customer-only account/session validation. Customer 422 remains sanitized; non-customer 422 now preserves the existing `HEAD` body `{"detail":"Request validation failed"}`.
- Wallet storage may support multiple verified addresses per account as an implementation proposal; this is not a confirmed product cardinality rule. Challenge is EIP-191 `personal_sign`, nonce-bound, one-use, and expires after five minutes.

## Tareas reconciliadas

- [x] **CC-01 — Base Flutter.** App shell, runners, widget tests, README y Android debug build verificados.
- [x] **CC-02 — Cerrar contrato API.** Propuesta técnica revisada en `docs/api/catalog-reservations-v1.md`; refleja la cuenta RoomForge + wallet vinculada y el namespace de cliente separado seleccionado por el usuario. `AGENTS.md` ahora señala como históricos los endpoints PB-001/PB-002 reemplazados en `b6a468a`.
- [x] **CC-03A — Cuenta y sesión de cliente.** **Estado: implementada y verificada; commit local autorizado y pendiente.** Suite **101 passed, 2 skipped**; Ruff y Pyright **0 errores**; OpenAPI, staff/customer 422 y separación de sesiones confirmadas; migración `0004→0005` verificada en SQLite desechable. PostgreSQL queda sin probar.
- [ ] **CC-03B — Vinculación de wallet cliente.** **Estado: pendiente de validación técnica.** La propuesta es un challenge EIP-191 `personal_sign` de un solo uso y verificación de titularidad; validar biblioteca, nonce/expiración/replay y contrato HTTP antes de implementación. No aceptar direcciones arbitrarias ni custodiar claves.
- [ ] **CC-04 — Backend de catálogo y ofertas.** Módulos/modelos/migraciones ligados a `agency.id`; listado/detalle público filtrable; cálculo server-authoritative; versión/quote inmutable. Rutas administrativas solo en backend si hacen falta para preparar/aprobar publicaciones; no crear UI de panel. Derivar tenant y permisos desde `get_active_staff`.
- [ ] **CC-05 — Backend de reservas y permisos.** Solicitud/idempotencia, bloqueo único por inmueble, plazo desde creación API, permisos EIP-712, wallet vinculada de cliente/agencia, reconciliación on-chain y estados coherentes con eventos; cubrir concurrencia/rollback en PostgreSQL cuando el entorno esté autorizado.
- [ ] **CC-06 — Escrow Solidity local.** Inicializar Hardhat reproducible; escrow y token de prueba parametrizables; depósito fijo, 24 h desde timestamp autorizado, refund por rechazo/cancelación/vencimiento y liberación por aceptación. La wallet de agencia ejecuta en cadena tanto la aceptación como el rechazo, mediante permisos EIP-712 firmados por el backend para respetar el timestamp autorizado. Quedan por definir los detalles de firma/payload, nonce/replay, envío y reconciliación. Cubrir carrera, reentrancia y eventos. Solo Hardhat local; sin testnet.
- [ ] **CC-07 — Cliente Flutter por capas.** Sesión de cuenta, vinculación de wallet, modelos inmutables, servicio HTTP, repositorio, ViewModel y UI de listado/detalle/filtros/cotización/estados; mostrar desglose del servidor y nunca fixtures como catálogo real.
- [ ] **CC-08 — Wallet cliente y flujo vertical.** Evaluar protocolo/SDK de wallet externa; firmar permiso/depósito con wallet vinculada e integrar estados API/escrow solo si red y configuración de desarrollo pueden probarse sin datos o fondos reales.
- [ ] **CC-09 — Verificación integrada y evidencia.** Backend pytest/Ruff/Pyright/migraciones; Hardhat tests; Flutter test/analyze/build Android; verificar límites, conciliación y README. Registrar iOS/runtime de dispositivo como no probado cuando corresponda.

## Verificaciones y evidencias previas

- Flutter: `cd apps/cliente_mobile && flutter test`, `flutter analyze`, `flutter build apk --debug` — PASS; APK generado e ignorado por Git. Build iOS omitido en Windows por falta de Xcode.
- La verificación independiente confirmó que los cambios Flutter quedaron bajo la app, el asset README iOS original está intacto y no se agregaron APIs/datos ficticios.
- El TDD RED del shell fue reportado por el worker inicial; el verificador independiente confirmó los resultados verdes, pero no observó el RED directamente.
- CC-02 es documental: la verificación independiente final confirmó que la propuesta API y `AGENTS.md` son internamente consistentes y están listos para revisión del usuario, no aprobados ni implementados. No se ejecutaron pruebas/OpenAPI de rutas nuevas porque aún no existen.
- Exploración CC-02 (solo lectura): FastAPI genera OpenAPI desde `create_app`; routers actuales usan prefijos `/api/v1/auth` y `/api/v1/agencies`; auth disponible es solo de personal vía sesión DB y rol/tenant persistidos. No hay patrón de paginación, schemas de respuesta compartidos ni módulos/endpoints de catálogo, precio o reserva. Contrato futuro debe distinguir hechos observados de propuestas.
- Exploración CC-03 (solo lectura): la base `b6a468a` solo tiene modelos/sesiones y JWT de personal. El router de personal usa refresh cookie+CSRF, TOTP y ventana de 30 días; el cliente no debe reutilizar router, modelos, TOTP ni sesión staff. Alembic head observado: `0004_staff_invitation_pending_email_unique`; tests usan SQLite in-memory/StaticPool y reloj controlado.
- Fuentes canónicas consultadas con autorización de solo lectura: `docs/plan-maestro-roomforge.md` F03.1 pide registro/login, validación de datos, hash seguro, sesiones/expiración/logout, almacenamiento móvil seguro y comportamiento seguro para credenciales incorrectas/sesión expirada/logout; prohíbe logs con credenciales/tokens. F03.4 deja recuperación de cuenta pendiente y prohíbe improvisar correo inexistente. `docs/redefinicion-roomforge.md` no añade detalles de auth. Ninguna fija rutas, payloads, response/status/error shape, auto-login, activación o verificación de correo.

## Siguiente paso

El propietario autorizó commits convencionales locales por unidades para el shell Flutter/docs y CC-03A en `feat/roomforge-mobile-3d`; no hacer push ni PR. Verificación: **101 passed, 2 skipped**, Ruff/Pyright pasan; PostgreSQL no se probó. RDD está efectivamente activo (`global: on`, `clone-local: unset`), pero la inspección nativa quedó bloqueada por selección explícita de untracked; no se capturó ninguna revisión. Tras los commits autorizados, detenerse en el handoff. CC-03B permanece pendiente de validación técnica EIP-191.
