# F04 — Inmuebles, publicaciones y catálogo

## Objetivo

Cerrar F04.1, F04.2 y F04.3 del `docs/plan-maestro-roomforge.md`, más la regresión de F04.4. No implementar UI (panel/apps), 3D, blockchain ni suscripciones.

## Fuentes canónicas (regla del 2026-09-30)

Por decisión del usuario, las **únicas** fuentes canónicas de requisitos son `docs/redefinicion-roomforge.md` y `docs/plan-maestro-roomforge.md`. Ningún artefacto de `openspec/changes/` es fuente de requisitos ni de alcance para esta unidad; en particular, `openspec/changes/hu022-025-publicaciones/` **no se usa**, y se deja constancia de que describe un módulo `publications` con la migración `0010_hu006_publication_revisions.py` que no existen en este repositorio (evidencia en `docs/plan-maestro-roomforge.md` §1.4.3).

Reglas canónicas que gobiernan F04:

- Redefinición, actores: el agente prepara borradores; el administrador de agencia administra el contenido de su agencia y **aprueba o rechaza** lo preparado por agentes; el aislamiento multi-tenant protege datos privados y operaciones administrativas, y el catálogo aprobado es visible entre agencias.
- Redefinición, publicaciones: el borrador no aparece en el catálogo hasta la aprobación; **editar no debe reescribir la oferta asociada a una reserva ya aceptada**; los estados de revisión incluyen la reapertura tras cambios.
- Plan F04.1: ficha del inmueble con propietario inmobiliario, validación de entradas, sin inventar precisión geográfica.
- Plan F04.2: fotografías y privacidad — diferida por decisión del usuario.
- Plan F04.3: borrador por agente, envío a revisión, aprobación/rechazo con motivo, publicación y retiro; salida verificable con historial mínimo; el cliente no ve borradores y el agente no salta la aprobación; cambiar una publicación no reescribe una oferta reservada.
- Plan F04.4: catálogo y detalle del cliente (ya implementado; se protege como regresión).

Estado real del sustrato, verificado por lectura del árbol en `main` (`45ca956`):

| Superficie | Estado |
|---|---|
| `GET /api/v1/listings` y `GET /api/v1/listings/{id}` | Implementado y probado (`backend/tests/test_catalog.py`) |
| `POST /api/v1/quotes` | Implementado (F05) |
| `PATCH` de depósito del inmueble | Implementado (`catalog/router.py`, `set_listing_deposit`) |
| Modelo `catalog.Listing` | Existe con `approval_status IN ('draft','pending','approved','rejected')` e `is_published`, `agency_id`, `operation`, `base_price`, `offer_version`, `city`, `zone`, `bedrooms`, `bathrooms`, `description`, `exact_address`, `photos` (JSON) y `ListingExtra` |
| Alta/edición de inmueble (F04.1) | **No existe**: los `Listing` solo se crean en fixtures de tests |
| Flujo de revisión/publicación (F04.3) | **No existe**: hay columnas de estado, ninguna transición, historial ni ruta |
| Fotografías (F04.2) | **No existe**: `photos` es un JSON sin validación, sin claves, sin estados y sin almacenamiento |
| Autorizador server-owned | Existe: `identity.session.get_active_staff` devuelve `ActiveStaff` con `role` y `tenant_id` |
| Suscripciones | **No existe** ningún módulo |

## Decisiones tomadas (2026-09-30)

1. **Sustrato:** sobre `catalog.Listing`, camino corto. Se descarta crear un módulo `publications` con revisiones inmutables versionadas: no tiene sustrato en este repositorio y multiplica el alcance sin pedido del plan maestro.
2. **Versionado:** editar un inmueble publicado lo devuelve a `draft` y lo retira del catálogo de inmediato; vuelve a publicarse solo con una aprobación administrativa nueva. La versión anterior no se conserva visible. Consecuencia asumida y declarada: el cliente ve desaparecer el inmueble mientras dura la revisión.
3. **Fotos (F04.2):** diferidas a su propio cambio. F04 cierra sin subida, validación ni estados de fotografías; `Listing.photos` queda como está (JSON sin validación) y el pendiente se registra en el plan.

Máquina de estados resultante, sobre las columnas existentes (`approval_status IN ('draft','pending','approved','rejected')` + `is_published`):

```text
draft    --submit (agente)-----------> pending
pending  --approve (admin)-----------> approved
pending  --reject (admin, motivo)----> rejected
approved --publish (admin)-----------> approved + is_published = true
approved + publicado --unpublish-----> approved + is_published = false
cualquiera --edit (agente)-----------> draft + is_published = false
```

El motivo es obligatorio en `reject`; en el resto de las transiciones la observación es opcional y siempre queda registrada.

## Alcance permitido

- `backend/app/modules/catalog/{router,schemas,service,models}.py` — rutas administrativas tenant-scoped y transiciones.
- `backend/alembic/versions/00XX_*.py` — solo si la persistencia lo exige (historial de transiciones), aditiva.
- `backend/tests/test_f04_publications.py` — suite nueva TDD estricto.
- `docs/api/f02-api-contract.md` — contrato del envelope y rutas nuevas.
- Este archivo y `docs/plan-maestro-roomforge.md`.

Fuera de superficie: `identity`, `agencies`, `reservations`, panel, apps Flutter, `contracts/`, `worker3d/`, `docs/diagramas/Diagrama1.eapx`.

## Restricciones

- TDD estricto (RED → GREEN → TRIANGULATE → REFACTOR) con el runner del proyecto: `<raiz>/.venv/Scripts/python.exe -m pytest tests -q` desde `backend/`, más `ruff check app tests` y `pyright app tests`.
- Autoridad siempre server-owned: nunca aceptar `tenant_id`, actor, rol, estado, timestamps ni versión desde el cliente.
- No ejecutar migraciones contra PostgreSQL real sin autorización explícita (GAP-092 sigue abierto).
- CP-009, CP-010, CP-011 y CP-012 permanecen `not executed`: la suite técnica no es evidencia académica.
- Esta sesión **no** tiene bloque `## SDD Session Preflight`, así que no se crean artefactos de fases SDD ni se lanzan subagentes de fase SDD. El trabajo se ejecuta como ODD sobre las dos fuentes canónicas; ningún artefacto de `openspec/changes/` se lee, cita ni usa como requisito.
- Presupuesto: el diff final fue de **~1.160 líneas agregadas** (10 archivos). El usuario autorizó explícitamente subir el cap de ~400 para cerrar F04 como una sola unidad de trabajo, después de que el escritor se detuviera en el límite sin inventar una excepción.

## Tareas

- [x] **F04-T0 — Resolver la decisión pendiente** con el usuario y registrar la respuesta en este archivo. Decidido el 2026-09-30: sustrato `catalog.Listing`, edición devuelve a borrador, fotos diferidas.
- [x] **F04-T1 — Autorización y tenancy reutilizados.** Las ocho rutas usan `Depends(get_active_staff)`; el rol y el tenant salen del servidor; `platform_admin` y tenant distinto → `403`; inmueble ausente dentro de la agencia autorizada → `404`, indistinguible de un inmueble ajeno (probado).
- [x] **F04-T2 — Alta y edición de borrador (F04.1).** Alta y reemplazo de contenido con validación; estado inicial `draft`; editar un publicado lo devuelve a `draft` y lo retira del catálogo; `city_key`/`zone_key` se derivan en el servidor. `offer_version` **no** se toca desde el servicio: solo avanza con cambios comerciales (`base_price`, `operation`, extras) por los disparadores de la migración `0007`, así que una edición descriptiva no invalida cotizaciones.
- [x] **F04-T3 — Envío a revisión (F04.3).** `draft → pending` con observación auditada; repetir el envío devuelve conflicto sin sumar historial.
- [x] **F04-T4 — Aprobación y rechazo (F04.3).** Solo administrador de agencia; aprobación `pending → approved`; rechazo con motivo obligatorio; un agente que intenta aprobar recibe `403` (prueba dedicada de no autoaprobación).
- [x] **F04-T5 — Publicar y despublicar (F04.3 / F04.4).** `is_published` como proyección pública; la despublicación desaparece del catálogo en la consulta siguiente (probado por HTTP).
- [x] **F04-T6 — Historial mínimo.** Tabla `listing_transition` append-only con actor, rol, agencia, fecha y observación, escrita en la misma transacción que el cambio de estado; no se expone en el catálogo público. Una falla al escribir el historial revierte el cambio de estado (probado por inyección).
- [ ] ~~**F04-T7 — Fotos y privacidad (F04.2)**~~ **Diferida** por decisión del usuario. No entra en esta unidad; queda registrada como pendiente de F04 en el plan maestro.
- [x] **F04-T8 — Verificación y cierre.** pytest + ruff + pyright; regresión de `GET /api/v1/listings` (solo aprobados y publicados); límites y fallos declarados. Cerrada con un límite explícito: `pyright` sigue saliendo con error (18 diagnósticos), ver abajo.

## Registro de ejecución

### F04 — registro de ejecución

- Implementadas el alta y edición de borradores, el flujo de envío/revisión/publicación/retiro y la consulta de historial, con autorización por rol y agencia y escritura transaccional del historial.
- `offer_version` comienza en 1 y queda bajo los disparadores comerciales existentes de `0007_catalog_offers.py`: cambia con `base_price`, `operation` o extras; una edición descriptiva no invalida cotizaciones.
- Evidencia técnica propia del escritor: suite F04, 16 pruebas aprobadas; suite backend, 430 aprobadas y 2 omitidas; Ruff sin hallazgos.
- **Corrección posterior a la verificación independiente:** el escritor atribuyó los 18 errores de `pyright` a dependencias faltantes (`eth_account`/`eth_utils`); eso es **falso**. El verificador comprobó en el mismo `.venv` que ambos paquetes están instalados e importables. Lo que sí es cierto: los 18 diagnósticos están en archivos que esta unidad no tocó y no hay diagnósticos nuevos. La causa de la no-resolución de esos imports por parte de `pyright` queda sin explicar y es deuda del entorno del proyecto, no de F04.
- **Verificación independiente (16 puntos):** confirmó la matriz de autorización ruta por ruta, el rechazo de campos de autoridad con `422`, la máquina de estados, la atomicidad (inyectó fallas de escritura del historial y el cambio de estado revirtió), la semántica de `offer_version`, la regresión del catálogo público, la estructura de la migración `0012` (solo tabla e índices, encadenada al `down_revision` real) y sondas adversarias propias: agente aprobando `403`, administrador aprobando desde `draft` `409`, tenant distinto `403`, `platform_admin` con campos forjados `422`, e inmueble ajeno y ausente con respuestas idénticas. No encontró ningún defecto de F04.
- **Límites declarados:** la evidencia RED se recuperó corriendo los tests ya corregidos contra la implementación revertida (11 fallos por rutas ausentes), pero un caso de historial falló con `KeyError` antes de su aserción y no constituye RED válido; las tres pruebas de `offer_version` se escribieron después de implementar y son de caracterización, no test-first. La migración `0012` no se aplicó contra PostgreSQL y el comportamiento de los disparadores en PostgreSQL no se ejecutó.
- La migración aditiva 0012 crea únicamente la tabla y sus índices; no se ejecutó contra PostgreSQL. No se ejecutó ningún caso académico CP. Fotografías siguen diferidas y no se crean revisiones inmutables del inmueble.
