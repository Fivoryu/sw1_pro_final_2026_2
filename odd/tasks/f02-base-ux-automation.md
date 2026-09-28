# F02 — Base de aplicación, UX y automatización

## Objetivo

Completar únicamente F02 del `plan-maestro-roomforge.md`: base API y modularidad, esquema/migraciones iniciales, prototipos navegables de las tres superficies y CI inicial reproducible. No convertir los prototipos en los flujos de negocio de F03–F10.

## Autoridad y alcance

- Requisitos autorizados exclusivamente: `docs/redefinicion-roomforge.md` y `docs/plan-maestro-roomforge.md` (F02.1–F02.4). F01 cerró en `origin/main` en `b8a07e3`; esos documentos están disponibles en la base actual.
- El usuario eligió F02 según el plan y rechazó ampliar este cambio a F03–F10. No implementar sus APIs, reglas de negocio, esquemas o integración end-to-end en esta rama.
- El alta pagada de agencias y las suscripciones quedan fuera del MVP según la redefinición.
- F02.1 debe definir estructura modular, validaciones, errores homogéneos, paginación y configuración; documentar contrato y disponibilidad. `/api/v1/listings` es un ejemplo no aprobado, no una ruta autorizada.
- F02.2 debe verificar creación desde base vacía y actualización desde una versión anterior cuando corresponda; documentar recuperación/rollback sin prometer reversibilidad universal.
- F02.3 entrega mapa de pantallas, navegación y contratos de estado para login, gestión, publicación, catálogo, selección y reserva. Es prototipado UX, no implementación funcional de F03–F10. Revisar recorridos antes del detalle visual; cubrir carga, vacío, error, offline y permisos, accesibilidad, foco, contraste y confirmación de acciones irreversibles.
- F02.4 fija runners/versiones desde manifiestos reales, checks separados por superficie y paridad local/CI; proteger secretos y no desplegar desde contribuciones no confiables. No inventar cobertura numérica.
- Decisiones directas del usuario para fases futuras: representar solicitud/aprobación de acceso temporal de siete días; calcular ofertas como precio base más ajustes elegidos y usar dos decimales. En F02 solo pueden aparecer como estados/reglas de prototipo; no se implementa su lógica comercial. Moneda y otras condiciones comerciales siguen pendientes en las fuentes autorizadas.
- Asignación UX aprobada por el usuario: todo el borrador del agente (captura, ambientes, geometría/objetos y preparación de oferta) se realiza en la app Android de captura; el panel web cubre administración/revisión; la app cliente móvil explora y reserva. F02 implementa solo prototipos.
- No consultar documentos históricos de backlog/BR/HU/IDs como autoridad de producto. No crear issue.

## Modo y entrega

- Flujo ODD directo, por elección explícita del usuario; no ejecutar SDD/OpenSpec para este cambio.
- Strict TDD solicitado previamente por el usuario: aplicar RED → GREEN → TRIANGULATE → REFACTOR a cada cambio de comportamiento. Confirmar el runner real de cada superficie antes de iniciar su tarea; nunca reportar PASS si no se ejecutó.
- Crear commits convencionales por unidad de trabajo en esta rama, con sus pruebas y documentación. Medir líneas añadidas + eliminadas por unidad; si el alcance supera 400 líneas, detenerse para acordar slices/estrategia antes de preparar PRs. No se autoriza `size:exception`.
- Por autorización del usuario, F02-T2 se divide antes de codificar en tres unidades revisables: T2a errores+paginación, T2b límites DB/correo, T2c health/readiness+Compose. Cada unidad debe mantenerse bajo 400 líneas cambiadas; si una se excede, detenerse y acordar otro corte.
- Preparar localmente la rama para revisión. No hacer push ni abrir PR sin confirmación explícita al cerrar.

## Estado y coordinación

- Worktree: `D:/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final-f02-base-ux-automation-wt`.
- Rama: `feat/f02-base-ux-automation`, rebased localmente sobre `origin/main` en `b8a07e3726074531696faf401048108e70fff9cb`.
- El checkout raíz conserva cambios ajenos y no se modifica. Rebasar F02 solo después de que el responsable F01 confirme el push final de sus documentos a `origin/main`.
- F01-T3/T4 fueron reportadas completas; no se realizarán operaciones Docker hasta coordinar pruebas F02.
- Handoff móvil recibido desde `feat/roomforge-mobile-3d`; commits locales, sin push: `64c59c02b51d3db3194a51c4e8fd54dbd5c63843` (shell Flutter; candidato F02), `f9d37842876cb0bbe1b7791b9796a73e7048bdf4` (propuesta/documentación API; fuera de autoridad F02), `de534c779ea723ba3eab7168ca45f5d2449dbb6b` (identidad cliente/migración/tests; fuera de F02) y `f762286` (registro de tarea). El dueño reportó 101 passed/2 skipped, Ruff y Pyright OK, SQLite 0004→0005 OK; PostgreSQL no verificado. Antes de integrar, revisar rutas del commit candidato y confirmar que no acopla el prototipo F02 a la implementación F03 de identidad. No copiar ni integrar los commits fuera de F02.
- F02-T1 cerró con `a156a53`; F02-T2a con `5d0cc8a`; F02-T2b con `eeda6e7`; F02-T2c con `447c8ec`; F02-T3a con `0952252`. T3b permanece en diagnóstico de solo lectura tras el error `VARCHAR(32)`; el usuario revocó toda autorización de fix/retest. T4a–T4c del cliente móvil ya están implementados/verificados; falta resolver contenido de detalle y los prototipos de captura/panel.

## Hallazgos base F02.1 (exploración de solo lectura)

- `backend/app/main.py:create_app()` carga configuración, crea DB/session factory, registra CORS, routers de identidad/agencias y solo el handler seguro de validación. No existen rutas de catálogo/reserva ni un endpoint público de salud.
- La única colección HTTP actual es `GET /api/v1/agencies`, sin paginación, con `{agencies:[...]}`. El panel lee errores de `detail` cuando es string; mantener ese campo preserva compatibilidad.
- Errores 422 actuales son `{"detail":"Request validation failed"}`; HTTPException usa `{"detail":"..."}`. No hay esquema común ni handler global de errores 500. Las rutas usan `response_model=None`; el OpenAPI generado puede no reflejar el envelope común si las respuestas no se declaran.
- Compose local verifica DB, Floci y OpenAPI; el probe API actual tiene timeout total de 5s y el TCP Floci 2s. No hay contrato público liveness/readiness. DB aún no declara deadlines. `EmailSender` es solo un Protocol y la fábrica carga un plugin externo; no hay proveedor concreto en el repo. Un timeout de thread/Future no puede detener un envío síncrono de forma segura.
- `apps/cliente_mobile/README.md` describe registro/login de cliente que no coincide con las rutas actuales de identidad staff. No conectar prototipos F02 a esa implementación F03 ni usar el README como fuente de requisitos.
- El scout propuso, pero no ejecutó, pruebas enfocadas en `backend/tests/test_api_contract.py`, `test_config.py`, `test_agencies.py` y regresión `test_staff_identity.py`; el panel tiene `staffAuthApi.test.ts`. No hay cambios ni pruebas T2 hechos.

### Contratos F02.1 aprobados por el usuario

1. Errores: mantener `detail` como string y añadir `code`; códigos estables `validation_error`, `unauthorized`, `forbidden`, `not_found`, `conflict`, `dependency_unavailable`, `internal_error`. El 500 no revela excepciones ni secretos.
2. Paginación: aplicar solo a `GET /api/v1/agencies`; `limit=20` por defecto, máximo `100`, `offset=0`; mantener `agencies` y añadir `pagination:{limit,offset,total}`.
3. Deadlines configurables por dependencia: DB conexión/adquisición de pool `5s`, sentencia `10s`, proveedor de correo `10s`. No añadir timeout global de request que no cancele trabajo síncrono. El usuario autorizó ampliar el Protocol del plugin para que reciba/exija el límite nativo; no existe un proveedor concreto en este repositorio, por lo que su enforcement real quedará externo y sin verificar.
4. Disponibilidad: `GET /health/live` para proceso y `GET /health/ready` para DB+Floci; respuestas seguras sin detalle interno y Compose usa readiness. El probe Compose actual de 5s es menor que el presupuesto secuencial DB (5+10s)+Floci (2s); el timeout externo deberá superar los límites internos y ser validado. La lectura de Floci es TCP (no certifica una operación S3).

## Hallazgos base F02.2 (exploración de solo lectura)

- El grafo estático es lineal: `0001_staff_identity → 0002_staff_identity_align → 0003_agency_registry → 0004_staff_invitation_pending_email_unique` (head de código; no se consultó una base conectada).
- Hay pruebas PostgreSQL de base vacía a head que requieren `ROOMFORGE_R6_DATABASE_URL` dedicado y completamente vacío. No se encontró un upgrade Alembic completo desde revisión previa.
- Las pruebas SQLite existentes cubren directamente `0003`/`0004` sobre esquema pre-agencia; no validan `0001`/`0002` ni sustituyen PostgreSQL. `0002` tiene operaciones específicas del dialecto PostgreSQL.
- Se observó posible inconsistencia en test de concurrencia PostgreSQL: inserta agente con `tenant_id` sin sembrar `Agency`, pese a FK declarada; no está probado si bloquea la suite.
- El usuario autorizó un intento acotado contra la DB R6 vacía; falló durante setup porque el revision ID de `0004` excede `VARCHAR(32)`. La decisión posterior limita T3b a diagnóstico de solo lectura: no cambiar migraciones, repetir pruebas ni usar Docker/PostgreSQL sin nueva autorización.

## Tareas

- [x] **F02-T1 — Proponer mapa UX y contratos de estado.** **CERRADA.** Entregable aprobado: `docs/ux/f02-surface-map.md`; commit `a156a53`. La aprobación precede al detalle visual.
- [x] **F02-T2a — Errores y paginación.** **CERRADA.** Errores homogéneos, 5xx sanitizados, OpenAPI y paginación de agencias; commit `5d0cc8a` (393 líneas).
- [x] **F02-T2b — Deadlines DB y proveedor de correo.** **CERRADA.** Timeouts PostgreSQL-only y EmailSender nativo; provider externo no disponible; commit `eeda6e7` (395 líneas).
- [x] **F02-T2c — Salud API y Compose.** **CERRADA.** `/health/live` y `/health/ready` DB+Floci TCP, Compose usa readiness; commit `447c8ec` (276 líneas). Tests 132 PASS/2 SKIP, Ruff PASS, Pyright 0; Docker no ejecutado por coordinación.
- [x] **F02-T3a — Verificación SQLite y evidencia de migración.** **CERRADA.** Evidencia y límites de SQLite/head estático en `docs/migrations/f02-migration-verification.md`; commit `0952252` (78 líneas).
- [ ] **F02-T3b — Verificación real PostgreSQL.** **PAUSADA; diagnóstico-only.** `docs/migrations/f02-migration-verification.md` registra 4 PASS y 2 errores de setup: el ID de `0004` tiene 42 caracteres y `alembic_version.version_num` es `VARCHAR(32)`. Evidencia y estado en commit `c7849b3` (34 líneas). DB R6 vacía, contenedor detenido y volumen preservado. No fix, retest, Docker ni PostgreSQL sin nueva autorización.
- [ ] **F02-T4 — Entregar prototipos UX de las tres superficies.** **EN CURSO.** Cliente T4a–T4c comprometidos por unidad: `b154888` (129), `49a853d` (352), `ce5028e` (336); accesibilidad verificada y revisión nativa aprobada. Panel: cola vacía `agency_admin` en commit `a7a8572` (181 líneas), 52 tests + build PASS, revisión `review-db28560ab5d7d35c` aprobada/acknowledged; R2-001 informativo. T4d espera decisión sobre muestra; captura Android sigue pendiente. Mantener cada slice <400 líneas; no implementar APIs ni negocio F03–F10.
- [x] **F02-T5 — Añadir CI inicial y paridad local.** Workflow y guía local para backend, panel y app cliente, con jobs separados y permisos mínimos; captura móvil y E2E Docker/PostgreSQL excluidos. Commit `8002648` (171 líneas); revisión nativa `review-ccaef90d54cbf2cf` aprobada (`approved`) y acknowledged (`acknowledged`). PyYAML parse PASS; `actionlint` no está instalado, así que la semántica GitHub queda sin validar. No se hizo push; el workflow no se ejecutó en GitHub.
- [ ] **F02-T6 — Integrar, verificar y preparar revisión.** Ejecutar los runners disponibles, reportar todo PASS/FAIL/SKIP/BLOCKED, medir cada slice y registrar commits/evidencia. Resolver o declarar explícitamente cada verificación PostgreSQL/móvil no disponible. Detenerse antes de publicar.

## Evidencia de cierre

| Tarea | Commit | Verificación observada | Estado |
|---|---|---|---|
| F02-T1 | `a156a53` | `git diff --cached --check` PASS; referencias relativas 2/2 PASS; N/A runtime (documentación sin límite de ejecución) | Hecho |
| F02-T2a | `5d0cc8a` | 98 backend PASS; 9 Vitest PASS; OpenAPI/whitespace PASS; 393 líneas | Hecho |
| F02-T2b | `eeda6e7` | 125 PASS/2 SKIP; Ruff PASS; Pyright 0; guard/README corregidos; 395 líneas | Hecho |
| F02-T2c | `447c8ec` | 132 PASS/2 SKIP; Ruff PASS; Pyright 0; 276 líneas; Compose runtime no ejecutado | Hecho |
| F02-T3a | `0952252` | 4 SQLite PASS; Alembic head; enlaces/whitespace PASS; PG no ejecutado | Hecho |
| F02-T3b | `c7849b3` | 4 SQLite PASS; 2 errores PG en setup por revision ID de 42 caracteres vs `VARCHAR(32)`; diagnóstico-only, sin fix/retest; DB/volumen preservados; 34 líneas | Pausada |
| F02-T4 | `b154888`, `49a853d`, `ce5028e`, `a7a8572` | Cliente: T4a 129, T4b 352, T4c 336 líneas; 8 widget tests/analyze PASS; review aprobado. Panel: 181 líneas, 52 Vitest + build PASS, `review-db28560ab5d7d35c` approved/acknowledged; R2-001 informativo. T4d espera muestra; captura Android pendiente | En curso |
| F02-T5 | `8002648` | Workflow y guía local; 171 líneas, 3 jobs, `contents: read`, sin secretos/servicios; PyYAML PASS; revisión nativa `review-ccaef90d54cbf2cf` de `8002648` sobre `a5223a645f0b1d63e8f54d49f846ecc7e50aaa48` (4 rutas, 171 líneas), cuatro lentes completadas, `approved` y `acknowledged`; cierre ofreció acknowledgement y no ofreció ruta de corrección. No se expuso resumen de hallazgos. GitHub semantics no verificadas localmente y workflow no ejecutado por no publicar | Hecho (limitación documentada) |
| F02-T6 | Pendiente | Pendiente | Pendiente |
