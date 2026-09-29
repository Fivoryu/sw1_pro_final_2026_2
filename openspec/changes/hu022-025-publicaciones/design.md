# Diseño técnico — Publicaciones HU-022 a HU-025

- **Cambio:** `hu022-025-publicaciones`
- **Trazabilidad:** PB-028, PB-029, PB-030 · HU-022, HU-023, HU-024, HU-025 · CU-024, CU-025, CU-026
- **Superficie:** API FastAPI/SQLAlchemy/PostgreSQL; consumidor Web futuro
- **Estado:** diseño; no se modificó producto, no se ejecutaron pruebas ni migraciones
- **Decisiones de producto adoptadas:** `revision-replacement`, `admin-approval-publish`, `existing-authorizer`, `existing-model`, `reuse-hu006-policy`

## 1. Decisión arquitectónica

La implementación conservará el flujo `router → application service/workflow → repositories` y hará que la transacción sea propiedad del servicio de comandos. El router solo obtiene la sesión JWT, valida DTOs/headers, resuelve dependencias y traduce errores. No aceptará `tenant_id`, actor, rol, permisos, estado, timestamps ni versión como autoridad.

El workflow existente (`PublicationRevisionWorkflow`) seguirá siendo la autoridad de las transiciones. La brecha se cerrará con un servicio HTTP de publicaciones que:

1. resuelva la autoridad del principal desde PostgreSQL;
2. reclame/reproduzca la clave de idempotencia;
3. ejecute el guard de suscripción y el workflow dentro de la misma transacción;
4. proyecte un DTO sin datos de autoridad o auditoría privada.

La operación de aprobación será la operación de publicación: no se agregará un estado público intermedio `aprobada`.

## 2. Archivos y superficies permitidos

Estos son los únicos archivos de producto que podrán entrar en `apply` para este cambio:

| Archivo | Responsabilidad | Cambio previsto |
|---|---|---|
| `backend/app/modules/publications/router.py` | Rutas públicas actuales y router mutador | Agregar router de workflow y traducción del envelope; conservar intactas las consultas de catálogo salvo regresiones verificadas. |
| `backend/app/modules/publications/schemas.py` | DTOs de entrada/salida | Agregar DTO completo de revisión, comando de observación, validación de headers/proyección y envelope auxiliar. |
| `backend/app/modules/publications/service.py` | Casos de uso, transacciones lógicas y mapeo al workflow | Agregar comandos HTTP, idempotencia, guards, concurrencia y gate de calidad; no duplicar reglas de estado. |
| `backend/app/modules/publications/repository.py` | Persistencia tenant-scoped | Agregar locks consistentes, CRUD de idempotencia y consultas de revisión/publicación. Ningún método hará `commit` o `rollback`. |
| `backend/app/modules/publications/models.py` | Modelo ORM del registro de idempotencia | Agregar solo la tabla de replay necesaria; no alterar las columnas inmutables de revisiones/transiciones. |
| `backend/app/modules/publications/authorizer.py` | Adaptador server-owned nuevo | Resolver actor, rol, tenant y suscripción usando administrador/membresía activa existentes. |
| `backend/app/modules/publications/quality.py` | Puerto de calidad/difusión nuevo | Definir únicamente Protocol/decisiones y el adaptador “unavailable”; no crear proveedor externo. |
| `backend/app/modules/tenant/context.py` | Contexto común | Permitir contexto de tenant sin `administrator_id` para un agente (`UUID | None`), preservando el caso administrador. |
| `backend/app/main.py` | Integración de router y errores globales | Incluir el router mutador, permitir `If-Match` en CORS y dar envelope `validation_error` solo a rutas de publicaciones. No cambiar el envelope histórico del catálogo. |
| `backend/alembic/versions/<next>_hu022_publication_idempotency.py` | Persistencia durable de idempotencia | Migración aditiva; el identificador y `down_revision` se resolverán contra el head real durante `tasks/apply`, no se inventan aquí. |
| `backend/tests/test_hu022_025_publicaciones.py` | Suite técnica nueva | Tests de contrato, workflow, aislamiento, transacción, idempotencia, guard, gate y regresión pública. |

No se permiten cambios en panel, Flutter, worker3d, Solidity, identidad/sesiones, reservas, propiedades, `docs/diagramas/Diagrama1.eapx` ni otros cambios OpenSpec. Este artefacto es el único archivo modificado en esta fase.

## 3. Contrato y seams

### 3.1 Router y DTOs

El `workflow_router` usará prefijo `/publications` y se incluirá bajo `/api/v1`; las rutas exactas son:

- `POST /api/v1/publications/{publication_id}/revisions` — crear/reemplazar borrador, `201`.
- `POST /api/v1/publication-revisions/{revision_id}/submit` — agente, `200`.
- `POST /api/v1/publication-revisions/{revision_id}/approve` — administrador, aprobación/publicación atómica, `200`.
- `POST /api/v1/publication-revisions/{revision_id}/reject` — administrador, `200`.
- `POST /api/v1/publications/{publication_id}/unpublish` — administrador, `200`.

Todas las mutaciones requieren `X-Idempotency-Key` no vacío y de longitud acotada por el DTO/header. El reemplazo admite opcionalmente `If-Match: "vN"`; el parser aceptará únicamente esa forma, y comparará contra `Publication.published_version`. Si no existe versión publicada, el precondicionamiento solo puede omitirse; un valor `vN` no coincidente devuelve `412 publication_version_conflict`.

`RevisionContentRequest` tendrá exactamente estos campos, todos requeridos, con tipos y límites físicos del modelo: `title`, `description`, `operation_type`, `price_amount`, `currency`, `location_policy`, `location_value`, `media_refs`, `model_3d_refs`, `attributes`. `extra="forbid"` rechazará campos de autoridad y desconocidos. No se agregará una lista de valores de negocio para `operation_type` o `location_policy` que no esté respaldada por el modelo/evidencia; esa ausencia queda registrada como blocker.

`ObservationRequest` tendrá exactamente `{ "observation": "..." }`; el servicio quitará espacios externos para validar y persistirá una observación no vacía. La creación usa la observación server-owned fija `Creación de revisión`, como en el workflow vigente.

`PublicationRevisionResponse` proyectará `id`, `publication_id`, `version`, `status`, los diez campos de contenido, `created_at`, `created_by_actor_id`, `created_by_role` y `published_at`. Nunca incluirá `tenant_id`, autoridad enviada por cliente ni transiciones. La respuesta de `unpublish` será la revisión que pasó a `despublicado`.

### 3.2 Autoridad server-owned y tenancy

`PublicationPrincipalAuthorizer` (en `authorizer.py`) resolverá, a partir de `MeResponse.id`, una única autoridad activa:

- administrador: `TenantAdministrator.activo`, usuario activo, invitación consumida y suscripción del tenant;
- agente: `TenantAgentMembership.status == active`, usuario activo y suscripción del tenant.

Devolverá `AuthorizedPublicationContext(actor, tenant_context)`, donde `actor` contiene `actor_id`, `role` y `tenant_id`, y `tenant_context` contiene `tenant_id` y `subscription_id`. Si el principal no tiene una autoridad inequívoca, o tiene contextos activos en varios tenants sin un selector server-side ya definido, fallará cerrado. Si tiene ambos roles en el mismo tenant, el rol administrativo será el único rol efectivo para ese contexto.

El adaptador conservará compatibilidad con el protocolo actual `authorize(tenant_id, principal_id)` del workflow, pero el `tenant_id` que reciba será el obtenido por el adaptador, nunca el request. Cada `get_revision`, `lock_publication` y `current_published` incluirá `tenant_id`; un recurso ajeno se traducirá a `404 resource_not_found`, sin distinguir inexistencia de pertenencia ajena.

Matriz mínima:

| Operación | Actor permitido | Capability HU-006 |
|---|---|---|
| crear/reemplazar revisión | agente autorizado (administrador también puede operar como actor autorizado) | `EDIT_PUBLICATION` |
| enviar a revisión | agente autorizado | `EDIT_PUBLICATION` |
| aprobar/publicar | administrador | `APPROVE_PUBLICATION` |
| rechazar | administrador | `APPROVE_PUBLICATION` |
| despublicar | administrador | `PUBLISH` |

La prohibición de autoaprobación se mantiene explícita aunque el rol de agente nunca tenga una ruta administrativa.

### 3.3 Service → workflow → repository

El servicio de comandos recibirá `Session`, `PublicationRevisionRepository`, `PublicationPrincipalAuthorizer`, `SubscriptionGuard`, `PublicationQualityGate` y clock. El router no instanciará el workflow directamente.

El workflow conservará estos seams conceptuales: `create_draft`, `submit_for_review`, `publish`, `reject`, `unpublish`. El servicio le pasará solo contexto server-owned y contenido validado. No se agregará un `UPDATE` de contenido: con `revision-replacement`, cada edición crea otra `PublicationRevision` completa, con siguiente versión, y deja intactas las anteriores.

El repositorio agregará, como mínimo:

- `lock_publication(tenant_id, publication_id)`;
- `get_revision_for_update(tenant_id, revision_id)`;
- `next_version` ejecutado después de bloquear la publicación;
- `current_published_for_update(tenant_id, publication_id)`;
- `claim_idempotency(tenant_id, key, request_hash, operation)`;
- `save_idempotency_result(record)`.

El servicio devolverá `409 invalid_revision_transition` para cualquier estado no permitido (`borrador → en_revision`, `en_revision → publicado|rechazado`, `publicado → despublicado`). No mutará antes de verificar estado, rol, observación, suscripción y gate aplicable.

## 4. Idempotencia, versionado y atomicidad

Se agregará `PublicationIdempotencyRecord` con:

- `id` UUID;
- `tenant_id` UUID no nullable;
- `idempotency_key` acotada y no nullable;
- `request_hash` SHA-256 del método, operación, target, body canónico e `If-Match`;
- `response_status` y `response_body` JSONB;
- `created_at` timestamptz;
- `UNIQUE (tenant_id, idempotency_key)`.

No se agregará FK al recurso: la purga futura no debe quedar acoplada a registros de replay. La clave es tenant-scoped y no puede reutilizarse para otra operación, recurso o contenido.

Secuencia transaccional para una clave nueva:

1. resolver autoridad y tenant server-side;
2. insertar/reclamar la clave con `ON CONFLICT DO NOTHING` y bloquear la fila existente;
3. si existe, comparar hash: replay exacto devuelve el `response_body` original; hash distinto devuelve `409 idempotency_key_reused` sin consultar/mutar el dominio;
4. para una clave nueva, ejecutar `SubscriptionGuard` (bloqueo de suscripción y plan), luego bloquear publicación y revisión en ese orden;
5. verificar `If-Match`, estado, rol, observación y gate de calidad;
6. insertar revisión/transiciones o cambiar estados y puntero de publicación;
7. serializar la respuesta DTO, guardar el resultado de idempotencia y hacer `commit` una sola vez.

El repositorio no hará commits parciales. Un error de validación de dominio, guard, gate, constraint o concurrencia hace rollback de revisión, transición, puntero y registro de idempotencia. En una carrera de la misma clave, PostgreSQL hará esperar al segundo reclamante; tras el commit, este devuelve el replay exacto. Si la primera transacción revierte, la segunda puede procesarse como nueva.

El lock order será `suscripción → plan → publicación → revisión → revisión publicada actual`. La creación serializa `next_version` mediante el lock de publicación y la unicidad `(tenant_id, publication_id, version)` es la defensa final. Una carrera que no pueda resolver un único resultado devuelve `409 concurrent_revision_conflict`.

La aprobación/publicación atómica hará, dentro de la misma transacción: bloquear publicación y target; confirmar `en_revision`; evaluar el gate; marcar la revisión anterior publicada como `despublicado` y registrar su transición; marcar la nueva como `publicado`, registrar su transición; actualizar `Publication.status`, `published_version` y timestamps. La versión anterior conserva contenido y `published_at` histórico. Mientras una revisión sea borrador, esté en revisión o rechazada, la versión publicada vigente no cambia.

La despublicación marcará la revisión actual como `despublicado`, `Publication.status` como `despublicado` y `unpublished_at`; conservará `published_version` como referencia histórica. El catálogo deja de verla porque exige simultáneamente estado de publicación y revisión `publicado`.

## 5. Suscripción y calidad/difusión

Cada comando mutador invocará el `SubscriptionGuard` existente de `app.modules.tenant.guards`, con el `TenantContext` server-owned y la capability de la matriz anterior. No se copiará `CAPABILITY_MATRIX` en `publications`. `SubscriptionRestrictedError` se traducirá a `409 subscription_mutation_blocked`; incluye como mínimo el bloqueo efectivo de `canceled_read_only`, `past_due` y `suspended` que reporte el seam. El catálogo anónimo no invocará este guard y conservará su política actual.

`PublicationQualityGate` será un Protocol sin proveedor concreto. Su resultado distinguirá `allowed`, `blocked` y `unavailable`, sin aceptar campos del cliente como evidencia. El servicio invocará el gate antes de aprobar/publicar; `blocked` produce `409 quality_or_diffusion_blocked` y `unavailable` produce `409 quality_or_diffusion_unavailable` cuando la política exija evaluación. Ambos ocurren antes de cualquier mutación. El adaptador por defecto será fail-closed/unavailable, no un simulador de calidad. La integración futura deberá leer una fuente verificable de reconstrucción/difusión sin ampliar este cambio.

## 6. Envelope de errores

Las rutas administrativas usarán siempre:

```json
{"code":"<stable_code>","message":"<safe_message>","details":null}
```

`details` solo contendrá errores de campos no sensibles. Mapeo:

| HTTP | `code` |
|---:|---|
| 400 | `request_malformed` (incluido header de idempotencia ausente/malformado) |
| 401 | `authentication_required` |
| 403 | `not_authorized` o `admin_required` |
| 404 | `resource_not_found` |
| 409 | `invalid_revision_transition`, `idempotency_key_reused`, `concurrent_revision_conflict`, `subscription_mutation_blocked`, `quality_or_diffusion_blocked`, `quality_or_diffusion_unavailable` |
| 412 | `publication_version_conflict` |
| 422 | `validation_error` |

No se expondrán mensajes de SQL, nombres de tenants ajenos, actor interno, secretos ni payloads de billing. El handler de validación de `main.py` se limitará a las rutas mutadoras; los envelopes históricos del catálogo (`detail`, `CATALOG_*`) no se cambiarán accidentalmente.

## 7. Catálogo público y regresión

No se agregará una ruta pública nueva. Se conservarán `GET /api/v1/catalog/publications` y `GET /api/v1/catalog/publications/{publication_id}` sin autenticación, sin `tenant_id` ni filtros controlados por cliente. Las pruebas deberán confirmar que solo se proyecta la revisión cuyo estado es `publicado`, que `published_version` coincide con la publicación, que no se muestran borradores/en revisión/rechazadas/despublicadas ni auditoría, y que una consulta posterior a `unpublish` ya no devuelve el recurso.

También se verificará la continuidad contractual ya existente: tenant `canceled_read_only` puede permanecer visible en el catálogo y tenant `purged` no. No se tocará `PublicationCatalogRepository` salvo que una prueba de regresión demuestre una incompatibilidad introducida por el workflow.

## 8. Migración y rollout

La migración de idempotencia es necesaria: una memoria local o una consulta check-then-insert no garantiza replay ni carreras entre procesos. Será una migración Alembic aditiva posterior al head real, con downgrade fail-closed si contiene filas. No se modificarán `0010_hu006_publication_revisions.py`, sus triggers append-only ni el esquema de publicaciones/revisiones: el dominio existente ya soporta el contenido, versionado y auditoría requeridos.

La implementación debe verificar el head Alembic y la disponibilidad del esquema antes de declarar listo el despliegue. La ejecución real de migraciones permanece fuera de esta fase y sigue siendo parte de GAP-092. El rollout debe desplegar primero la migración y después la aplicación; una incompatibilidad de gate o authorizer se resuelve deshabilitando las rutas mutadoras, no eliminando datos.

## 9. Estrategia TDD y verificación futura

En `test_hu022_025_publicaciones.py`, en orden RED → GREEN → TRIANGULATE → REFACTOR:

1. DTO exacto, campos extra de autoridad, observación vacía, header/idempotencia e `If-Match` inválidos.
2. `401`, `403`, actor server-owned, roles y aislamiento cross-tenant con respuesta no reveladora.
3. creación y reemplazo: diez campos, versiones monótonas, revisión anterior intacta, publicación vigente preservada.
4. flujo válido de envío, aprobación/publicación, rechazo y despublicación; autoaprobación prohibida.
5. estados inválidos sin cambio de estado, auditoría ni puntero.
6. hash de idempotencia, replay exacto, clave reutilizada, conflicto de `If-Match` y carreras/rollback con PostgreSQL.
7. guard HU-006 permitido/bloqueado por capability, sin matriz duplicada.
8. gate de calidad bloqueado/no disponible y ausencia de evidencia fabricada.
9. regresión del catálogo, tenant cancelado visible, purged excluido y desaparición inmediata tras despublicar.
10. migración aditiva, unicidad y downgrade fail-closed, cuando corresponda en la fase de verificación.

Estos tests serán evidencia técnica del backend. No se presentarán como ejecución de CP-009, CP-010, CP-011 o CP-012, que permanecen `not executed`; tampoco se afirmará ejecución contra PostgreSQL real en esta fase.

## 10. Rollback

El rollback primario es retirar el `workflow_router` de `main.py` o desplegar la versión anterior compatible. Se conservan publicaciones, revisiones, transiciones y registros de idempotencia; no se borran datos auditables. La migración no se degrada en una base con filas. Si ya existen filas, se conserva el esquema y se revierte únicamente la aplicación, porque la tabla adicional es compatible con versiones que no la consulten.

Toda aprobación/despublicación es transaccional; no existe rollback de una mitad del workflow. Ante fallo del authorizer o gate, el comportamiento seguro es `403`/`409` sin mutación y la desactivación temporal de comandos mutadores, manteniendo el catálogo público.

## 11. Blockers y riesgo de revisión

### Blockers técnicos no resueltos

1. El “authorizer existente” observado es un Protocol y un seam de tests; no hay una implementación productiva única que resuelva agente, administrador, tenant y suscripción. El adaptador propuesto debe validarse contra membresías/administradores reales antes de habilitar rutas.
2. `MeResponse` no contiene tenant ni rol y el sistema no documenta selección de tenant para principales con múltiples memberships. La resolución fail-closed propuesta bloquea ese caso; si el producto exige multi-tenant, hace falta una decisión server-side fuera de este cambio.
3. No se observó una fuente verificable de estado de difuminado/difusión o calidad de reconstrucción. Con el gate default unavailable, la aprobación positiva no será operable hasta conectar un seam real; no se inventará proveedor.
4. El modelo no expresa allowlists semánticas para `operation_type`/`location_policy`, límites de texto o política para múltiples revisiones candidatas simultáneas. La implementación debe evitar inventar reglas y registrar la decisión de producto que falte.
5. La idempotencia HTTP no existe hoy como tabla; el nombre de migración/head real y su compatibilidad con el entorno deben resolverse en `tasks`/`apply`. No se afirma que `0010` ni ninguna migración de publicaciones esté aplicada.

### Presupuesto

El diff de implementación (router, DTOs, adapter de autoridad, servicio, repositorio, gate, migración y tests) tiene **riesgo alto de superar 400 líneas cambiadas**. Bajo `ask-on-risk`, si la estimación o el diff real supera el presupuesto, se debe detener la entrega y solicitar decisión de partición; no se infiere `size:exception` ni una estrategia de chaining.

## Fuentes

`explore.md`, `preproposal.md`, `proposal.md`, `specs/publications/spec.md`, `backend/app/modules/publications/{models,service,repository,router,schemas}.py`, `backend/app/modules/tenant/{guards,context,models,repository,agent_membership_access}.py`, `backend/app/modules/identity/router.py`, `backend/app/main.py`, `backend/alembic/versions/0010_hu006_publication_revisions.py`, `backend/tests/test_hu006_slice3_catalog.py`, `backend/openspec/specs/tenant-subscription/spec.md` y GAP-092.

## Key Learnings

- El dominio de revisiones y auditoría ya existe; el trabajo principal es exponerlo sin romper su inmutabilidad.
- La autoridad debe resolverse antes de seleccionar recursos y todas las consultas deben estar tenant-scoped.
- Aprobar y publicar serán una sola transición administrativa atómica; crear una revisión nunca desplaza la versión pública vigente.
- Idempotencia durable y locks ordenados son necesarios para que replay, versionado y auditoría no dependan de memoria de proceso.
- La política de suscripción se consume mediante `SubscriptionGuard`; no se replica en publicaciones.
- Calidad/difusión queda como dependencia explícita fail-closed, no como proveedor inventado.
- Las pruebas técnicas futuras y el estado del código no cierran CP-009..CP-012 ni prueban migraciones reales.
