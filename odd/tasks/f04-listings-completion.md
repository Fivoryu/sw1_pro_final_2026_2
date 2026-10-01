# F04 — Completar inmuebles, publicaciones y catálogo

## Objetivo

Completar la Fase 4 del `docs/plan-maestro-roomforge.md` a partir del backend ya integrado (`odd/tasks/f04-publications.md`). Esta unidad prepara la base que necesitan las pantallas: acceso local de personal para probar con usuarios reales y rutas de personal para listar y consultar los inmuebles de una agencia. Las pantallas del panel, de la app de captura y de la app cliente se trabajan en unidades posteriores, cada una con su propio registro.

## Fuentes canónicas

Rige la regla del 2026-09-30 (`docs/plan-maestro-roomforge.md` §1.4.3): las únicas fuentes de requisitos son `docs/redefinicion-roomforge.md` y `docs/plan-maestro-roomforge.md`. `openspec/changes/hu022-025-publicaciones/` no se usa.

Reglas que gobiernan esta unidad:

- Redefinición, actores: el agente prepara borradores; el administrador de agencia aprueba o rechaza; el aislamiento multi-tenant protege los datos privados y las operaciones administrativas de cada agencia.
- Plan F04.3: el cliente no ve borradores y el agente no salta la aprobación.
- Plan F03.1: no mostrar contraseñas ni tokens en logs.
- Mapa UX aprobado (`docs/ux/f02-surface-map.md`): el agente crea y edita borradores en la app de captura; el panel concentra la revisión y publicación del administrador de agencia; el cliente explora desde su app.

Trazabilidad académica: PB-028/029/030, HU-022 a HU-026, CP-009 a CP-012. Los casos CP siguen `not executed`; la suite técnica no es evidencia académica.

## Estado de partida (verificado el 2026-10-01 en `main` `b4da312`)

| Superficie | Estado |
|---|---|
| Rutas de personal F04 (crear, editar, submit, approve, reject, publish, unpublish, transitions) | Implementadas y probadas |
| Catálogo público `GET /api/v1/listings` y detalle | Implementados y probados |
| Ruta de personal para **listar** inmuebles de la agencia | **No existe** |
| Ruta de personal para **consultar un** inmueble | **No existe** (solo su historial) |
| Envío de invitaciones de personal en local | **No disponible**: no hay transporte `STAFF_EMAIL_SENDER_FACTORY`, así que no se puede crear el primer administrador ni probar las pantallas con usuarios reales |
| Panel, app de captura y app cliente | Prototipos de F02 sin conexión a la API de F04 |
| Fotografías (F04.2) | Diferidas |

Verificación de entorno del mismo día, en contenedores desechables sobre el stack `roomforge-local-dev`: migraciones aplicadas hasta `0012_listing_transitions (head)` en el PostgreSQL local; backend 430 aprobadas y 3 omitidas; Ruff limpio; Pyright 0 errores; panel 70/70 y build; Hardhat 34/34.

## Decisiones tomadas (2026-10-01)

1. **Flujo:** ODD, igual que la unidad F04 anterior. No se crean artefactos SDD.
2. **Rutas de listado y consulta de personal:** se agregan al módulo `catalog`.
3. **Visibilidad del agente:** el listado muestra todos los inmuebles de su agencia, coherente con los permisos de edición vigentes (cualquier agente de la agencia puede editar cualquier inmueble de ella). No se agrega columna de autor ni migración.
4. **Acceso local:** se agrega un transporte de correo solo para desarrollo, cargado mediante `STAFF_EMAIL_SENDER_FACTORY`, sin modificar el código de identidad de F03. Para respetar F03.1 no escribe el enlace en logs: lo deja en un archivo de bandeja de salida dentro del contenedor y se niega a operar fuera de un origen de panel local.
5. **Fotografías (F04.2):** siguen diferidas.

## Alcance permitido

- `odd/tasks/f04-listings-completion.md` (este registro).
- Paso A: nuevo `backend/app/core/dev_email.py`; nuevo `backend/tests/test_dev_email.py`; `infra/docker/compose.local.yml` (solo la variable del servicio `api`); `infra/README.md`.
- Paso B: `backend/app/modules/catalog/{router,service,schemas}.py`; `backend/tests/test_f04_publications.py`; `docs/api/f04-publications-v1.md`.
- Cierre: `docs/plan-maestro-roomforge.md` (estado de F04).

Fuera de superficie: `identity`, `agencies`, `customer_identity`, `reservations`, `backend/alembic/versions/`, panel, apps Flutter, `contracts/`, `worker3d/`, `docs/diagramas/Diagrama1.eapx`, `openspec/`.

## Restricciones

- TDD estricto (RED → GREEN → REFACTOR) con pytest, más `ruff check app tests` y `pyright app tests`.
- Autoridad server-owned: la agencia, el actor y el rol salen de la sesión; nunca del cuerpo ni de la consulta.
- Inmueble ajeno e inexistente responden igual (`404`); otra agencia y `platform_admin` reciben `403`.
- El transporte de desarrollo no debe poder activarse fuera de un origen local.
- Sin commit ni push sin autorización explícita del usuario.

## Tareas

- [x] **F04C-T1 — Transporte de correo de desarrollo.** TDD: deja el enlace en la bandeja de salida, respeta el contrato `send_invitation(..., *, timeout_seconds)`, no escribe el enlace en logs y falla cerrado ante un origen no local.
- [x] **F04C-T2 — Activación local.** Variable en `compose.local.yml`, procedimiento de alta del primer administrador en `infra/README.md` y comprobación de punta a punta con el primer administrador real.
- [ ] **F04C-T3 — Listado de inmuebles de la agencia.** `GET /api/v1/staff/agencies/{agency_id}/listings` con filtros de estado y publicación, paginación `limit`/`offset`/`total` como `docs/api/f02-api-contract.md`, autorización y aislamiento probados.
- [ ] **F04C-T4 — Consulta de un inmueble.** `GET /api/v1/staff/agencies/{agency_id}/listings/{listing_id}`, con la misma autorización y `404` indistinguible.
- [ ] **F04C-T5 — Contrato y verificación.** Actualizar `docs/api/f04-publications-v1.md`; suite completa, Ruff y Pyright; regresión del catálogo público; estado de F04 en el plan maestro.

## Registro de ejecución

### F04C-T1 — Transporte de correo de desarrollo (2026-10-01)

- Nuevo `backend/app/core/dev_email.py`: `DevOutboxEmailSender` escribe cada invitación como un JSON (`email`, `link`, `expires_at`) en un archivo propio, creado con `O_EXCL` y permisos `0600`, dentro de `ROOMFORGE_DEV_OUTBOX_DIR` (por defecto `/tmp/roomforge-dev-outbox`). No usa logging. `create_dev_outbox_sender()` falla con `RuntimeError` si `STAFF_WEB_ORIGIN` no es `http(s)` con host `127.0.0.1` o `localhost`; `configured_email_sender()` ya convierte ese fallo en `EmailDeliveryUnavailable`, así que el transporte falla cerrado sin tocar código de identidad.
- TDD: `backend/tests/test_dev_email.py` (16 pruebas) observó RED por módulo inexistente (`ModuleNotFoundError` en la colección) y luego GREEN 16/16. Cubre escritura, archivos separados por invitación, creación de directorio, ausencia del token en logs, timeout no positivo, orígenes locales aceptados, orígenes no locales rechazados (incluidos `localhost.example.com` y `127.0.0.1.example.com`) y carga real mediante `STAFF_EMAIL_SENDER_FACTORY`.
- Verificación en contenedor desechable `python:3.12-slim` con el backend montado de solo lectura: suite completa 446 aprobadas, 3 omitidas, 4 advertencias (430 previas + 16 nuevas); Ruff `All checks passed!`; Pyright `0 errors, 0 warnings, 0 informations`.

### F04C-T2 — Activación local (2026-10-01)

- `infra/docker/compose.local.yml`: el servicio `api` define `STAFF_EMAIL_SENDER_FACTORY: app.core.dev_email:create_dev_outbox_sender`.
- `infra/README.md`: nueva sección «Acceso local de personal» con migraciones, `bootstrap`, lectura de la bandeja y aceptación de la invitación.
- Reconstruida la imagen `api` del stack `roomforge-local-dev`; volvió a `healthy` y `configured_email_sender()` devuelve `DevOutboxEmailSender` dentro del contenedor.
- Comprobación de punta a punta: con el correo de prueba `admin@example.test` elegido por el usuario, `python -m app.modules.identity.bootstrap` dentro del contenedor `api` terminó con código 0 y dejó un único archivo `0600` en la bandeja con el enlace `http://127.0.0.1:5173/invitations/accept/<token>`; el panel respondió `200` en esa ruta. El usuario aceptó la invitación, registró TOTP e inició sesión en el panel. Consulta de solo lectura en el PostgreSQL local: `staff_account` contiene `admin@example.test`, `platform_admin`, `active = t`, `totp_enabled = t`; `staff_invitation` quedó `accepted` con `delivery_status = sent`. Son datos de desarrollo del volumen `roomforge-local-dev_postgres_data`, no evidencia académica.
