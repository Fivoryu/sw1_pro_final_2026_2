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
- [x] **F04C-T3 — Listado de inmuebles de la agencia.** `GET /api/v1/staff/agencies/{agency_id}/listings` con filtros de estado y publicación, paginación `limit`/`offset`/`total` como `docs/api/f02-api-contract.md`, autorización y aislamiento probados.
- [x] **F04C-T4 — Consulta de un inmueble.** `GET /api/v1/staff/agencies/{agency_id}/listings/{listing_id}`, con la misma autorización y `404` indistinguible.
- [x] **F04C-T5 — Contrato y verificación.** Actualizar `docs/api/f04-publications-v1.md`; suite completa, Ruff y Pyright; regresión del catálogo público; estado de F04 en el plan maestro.

- [x] **F04C-T6 — Aislamiento entre agencias (F03.3).** Matriz de autorización por actor en el contrato y pruebas de acceso cruzado para cada ruta de inmueble: personal de otra agencia y `platform_admin` (`403`), ID ajeno en la ruta propia (`404` idéntico a inexistente), sesión real requerida (`401`) y catálogo público transversal. Agregada el 2026-10-02 con aprobación del usuario.

- [x] **F04C-T7 — PostgreSQL real.** Ejecutar `test_f04_publications_postgres.py` contra un PostgreSQL descartable y extenderlo con el listado y la consulta de personal, que solo estaban probados con SQLite. Ampliación de superficie aprobada por el usuario el 2026-10-02: `backend/tests/test_f04_publications_postgres.py`.

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
- Commit de work unit `176cb42` (`feat(infra): deliver local staff invitations to a dev outbox`), autorizado por el usuario; sin push.

### F04C-T3/T4 — Listado y consulta de personal (2026-10-01)

- `catalog/service.py`: `list_staff_listings(...)` filtra siempre por la agencia recibida, aplica los filtros opcionales de estado y publicación, cuenta el total filtrado y pagina por `created_at DESC, id DESC`. La consulta de un inmueble reutiliza `get_staff_listing`, ya existente.
- `catalog/schemas.py`: alias único `ListingApprovalStatus` (usado también por `ListingAuthoringResponse`), `StaffListingPagination` y `StaffListingPage` con la forma `{listings, pagination: {limit, offset, total}}` del listado de inmobiliarias de `docs/api/f02-api-contract.md`.
- `catalog/router.py`: `GET /api/v1/staff/agencies/{agency_id}/listings` (`status`, `published`, `limit` 1–100 por defecto 20, `offset` ≥ 0) y `GET .../listings/{listing_id}`, ambos con `_require_listing_editor`: `agency_admin` y `agent` de la agencia; otra agencia y `platform_admin` reciben `403`; un inmueble de otra agencia y uno inexistente responden el mismo `404`.
- TDD: 15 pruebas nuevas en `test_f04_publications.py` observaron RED (rutas inexistentes) con las 16 previas en verde; luego GREEN 31/31. El helper `_seed_listing` ganó un `created_at` opcional para fijar el orden, sin cambiar las pruebas existentes. Cubren aislamiento por agencia y orden, filtros, paginación y `total`, `offset` posterior al final, cinco parámetros fuera de contrato (`422`), visibilidad completa del agente, `403` para otra agencia y `platform_admin` en ambas rutas sin filtrar datos, campos privados en el detalle, `404` idéntico ajeno/inexistente, documentación OpenAPI y regresión del catálogo público.
- Ruff marcó `typing.Literal` sin uso tras el refactor del alias; se eliminó el import.

### F04C-T5 — Contrato y verificación (2026-10-01)

- `docs/api/f04-publications-v1.md`: rutas, parámetros, forma de respuesta y fila de autorización nuevas; el límite sobre la migración `0012` se corrigió con la verificación en PostgreSQL descartable registrada en el plan (§1.4.2.bis) y la aplicación en el stack local.
- `docs/plan-maestro-roomforge.md`: línea de avance en la sección F04, marcada como no integrada; el cuadro §1.4.1 no se modifica porque describe solo lo integrado en `main`.
- Verificación en contenedor desechable `python:3.12-slim`: suite backend 461 aprobadas, 3 omitidas, 4 advertencias; `test_f04_publications.py` + `test_catalog.py` 82 aprobadas; Ruff `All checks passed!`; Pyright `0 errors, 0 warnings, 0 informations`.
- Stack local: imagen `api` reconstruida y `healthy`; el OpenAPI publica `GET` en ambas rutas y la ruta de listado sin sesión responde `401`.
- Prueba manual de punta a punta en el stack local (2026-10-01), ejecutada por el usuario desde PowerShell contra la API real con PostgreSQL y sesiones TOTP reales; los resultados se contrastaron con los logs de acceso del contenedor `api`. Como `platform_admin` (`admin@example.test`): `POST /api/v1/agencies` (`agencia-demo`) `201` y `POST .../admin-invitations` `201`; la invitación llegó a la bandeja de desarrollo y el usuario la aceptó con TOTP. Como `agency_admin` (`agencia@example.test`): dos `POST .../listings` `201` y un `submit` `200`; `GET .../listings` `200`, `GET .../listings?status=pending` `200` y `GET .../listings/{listing_id}` `200`, con los valores que el usuario confirmó como esperados. Negativos: otra agencia `403`, `platform_admin` sobre la agencia `403`, inmueble inexistente `404` y sin sesión `401`; el catálogo público respondió `200` sin los inmuebles en borrador o revisión. Durante la prueba, un login construido con JSON literal en PowerShell 5.1 devolvió `422` por cuerpo mal formado; se resolvió serializando con `ConvertTo-Json` y enviando bytes UTF-8, sin cambios de código. Son datos de desarrollo locales, no evidencia académica.
- Sin ejecutar: `test_f04_publications_postgres.py` (se omite sin `ROOMFORGE_POSTGRES_DATABASE_URL` y requiere una base descartable; ejecutada después en F04C-T7); casos académicos CP-009 a CP-012.

### F04C-T6 — Aislamiento entre agencias, F03.3 (2026-10-02)

- Objetivo: cerrar la dependencia de F03.3 que `odd/tasks/f03-identity-agencies.md` dejó abierta hasta tener F04 («cambiar IDs no permite leer ni editar datos ajenos; los clientes sí ven anuncios publicados de varias agencias») y producir la matriz por actor que pide el plan.
- Cobertura previa revisada: el agente no ejecuta acciones de administración; otra agencia no edita; listado y detalle prohíben otras agencias y `platform_admin`; ID ajeno en la ruta propia solo probado para el detalle; depósito y catálogo público probados en `test_catalog.py`. Faltaban el ID ajeno en el resto de las rutas, las acciones con la URL de otra agencia más allá de editar y una prueba con autenticación real (las existentes reemplazan `get_active_staff`).
- `backend/tests/test_f04_publications.py`: 40 casos nuevos parametrizados sobre las 9 rutas de inmueble (consulta, edición, envío, aprobación, rechazo, publicación, retiro, historial y depósito), cada una sembrada en un estado en el que la acción sería válida para un actor autorizado: ID ajeno en la ruta propia → `404` idéntico a inexistente (9); admin y agente de otra agencia y `platform_admin` → `403` en cada ruta (27) y en listado y alta (3); sin sesión, token mal formado y token real de cliente → `401` en las 11 rutas de personal, con control positivo de una sesión real de personal (1). Cada caso comprueba además que el inmueble no cambió y que no se agregó historial.
- **Sin fase RED:** los 40 casos pasaron en la primera ejecución porque el código ya aplicaba el aislamiento (el servicio filtra por `Listing.id` y `Listing.agency_id`; los guards comparan rol y agencia). Es una verificación, no la corrección de un defecto. Para comprobar que las pruebas detectan un hueco real, se hizo un sabotaje sobre una copia descartable del backend dentro del contenedor (sin tocar el repositorio): buscar solo por ID → 9 fallas; guard sin comparar agencia → 15 fallas (los 15 restantes siguen en `403` por rol, como corresponde); `get_active_staff` aceptando cualquier token → 1 falla.
- `docs/api/f04-publications-v1.md`: matriz con columna de cliente o anónimo y filas de depósito y catálogo público, reglas de ID ajeno y de sesión, y tabla que asocia cada regla con sus pruebas; errores `401` y `404` precisados.
- Verificación en `roomforge-backend-dev:local`: suite backend 506 aprobadas, 3 omitidas, 4 advertencias; Ruff `All checks passed!`; Pyright `0 errors, 0 warnings, 0 informations`.
- Límite: el criterio de F03.3 queda verificado en la rama; el estado de F03.3 en el plan y la nota de `f03-identity-agencies.md` se actualizan al integrar en `main`. Fotografías originales privadas (F04.2) siguen diferidas.

### F04C-T7 — PostgreSQL real (2026-10-02)

- Entorno: contenedor `postgres:16-alpine` (PostgreSQL 16.15) descartable y aparte del stack, base nueva `roomforge_f04_check`; la prueba corrió en `roomforge-backend-dev:local` compartiendo la red del contenedor para cumplir sus guardas (driver `postgresql+psycopg`, host loopback con puerto explícito, prefijo `roomforge_f04_`, base vacía). Cada contenedor se eliminó al terminar.
- Primera corrida, prueba sin cambios: `1 passed`. Aplicó la cadena completa de migraciones hasta `0012_listing_transitions` y recorrió alta, edición descriptiva y de precio (disparador real de `offer_version`), envío, aprobación, publicación, historial, retiro, rechazo con motivo, publicación de un rechazado `409`, agente `403`, otra agencia `403` e ID ajeno `404`. Estado final: 3 inmuebles y 11 transiciones.
- Hueco: el listado y la consulta de personal (`F04C-T3/T4`) solo estaban probados con SQLite, donde `created_at` (`server_default=func.now()`) tiene precisión de segundos; en PostgreSQL es `now()` de la transacción, con microsegundos. Orden, total y filtros no se habían comprobado contra la base real.
- Extensión de la misma prueba: tres borradores más en la agencia uno; listado completo en orden exacto de creación inverso con `total` 5 y sin el inmueble de la otra agencia; filtros `status=draft` (3), `status=approved&published=false` (1) y `published=true` (0); paginación `limit=2&offset=1`; el agente ve los mismos 5; consulta con campos privados `200`; ID ajeno `404` con cuerpo idéntico al inexistente.
- Segunda corrida con base nueva: `1 passed`; estado final 6 inmuebles y 14 transiciones; Ruff y Pyright limpios en el archivo. Sin fase RED: la extensión verifica comportamiento existente. Sabotaje sobre una copia descartable (orden ascendente en `list_staff_listings`): la prueba falla en la nueva aserción del listado (línea 367).
- Límite: sigue sin haber verificación en un entorno desplegado.
