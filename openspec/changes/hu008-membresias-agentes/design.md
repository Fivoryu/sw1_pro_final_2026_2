# Diseño técnico — HU-008 Membresías de agentes

- **Cambio:** `hu008-membresias-agentes`
- **Trazabilidad:** PB-007 / HU-008 / CU-008 / CP-007
- **Superficie:** backend FastAPI y contrato HTTP tenant-scoped
- **Idioma:** español profesional y neutral
- **Estado:** diseño aprobado para desglosarse en `tasks`; no implica implementación ni ejecución de CP-007

## 1. Objetivo y límites

Se implementará el ciclo de vida administrativo de una membresía conservando la misma fila y la misma identidad global:

```text
pending  ──activar──> active ──desactivar──> inactive ──activar──> active
                              └─revocar──> revoked
```

`revoked` es terminal. La unicidad operacional será por `(tenant_id, usuario_global_id)`, no por usuario global: un usuario puede estar activo en T1 y T2 simultáneamente. Las filas no activas se conservan y pueden coexistir como historial.

Quedan fuera UI, mobile, publicaciones, catálogo de inmuebles, worker 3D, contratos Solidity, cuotas/facturación y RBAC de HU-009. HU-008 no asigna roles, permisos o capacidades; solo ofrece la condición mínima de membresía activa.

## 2. Decisiones de arquitectura

1. Se añade un slice independiente `agent_membership_*` dentro de `backend/app/modules/tenant/`; no se amplía el `TenantService` monolítico salvo que una dependencia estrictamente necesaria lo requiera.
2. El router recibe únicamente el principal autenticado y los datos del comando. El servicio resuelve el contexto administrativo mediante `TenantContextResolver`; el cliente nunca selecciona el tenant.
3. El repositorio es dueño de la transacción de transición: locks, validación del estado observado, reemplazo de la activa, actualización de timestamps, inserción de auditoría, `flush` y `commit`.
4. La base de datos respalda la invariante con un índice único parcial. El lock transaccional serializa los comandos de aplicación; el índice es la última barrera frente a escritores inesperados.
5. La auditoría de membresías será una entidad separada de `AgentInvitationEvent`. Los eventos de invitación de HU-007 mantienen su semántica y tabla actuales.
6. La repetición del comando se resuelve por estado actual, no mediante una nueva clave de idempotencia: el mismo estado objetivo devuelve `200` sin efectos adicionales.

## 3. Modelo de persistencia

### 3.1 Evolución de `tenant_agent_membership`

La migración nueva será `backend/alembic/versions/0014_hu008_membership_lifecycle.py`, con `down_revision = "0013"`. No se modifica el archivo de migración 0013.

`0013_hu007_agent_invitations.py` creó actualmente:

- `tenant_agent_membership` con `tenant_id`, `usuario_global_id`, `invitation_id`, `status` y `created_at`;
- `UNIQUE(tenant_id, usuario_global_id)` con nombre `uq_agent_membership_tenant_user`;
- `UNIQUE(invitation_id)` y el check de los cuatro estados.

La 0014 hará lo siguiente, en este orden:

1. Añadirá nullable, sin perder filas, los campos `activated_at`, `deactivated_at` y `revoked_at` (`TIMESTAMP WITH TIME ZONE`). `created_at` continuará siendo inmutable.
2. Para filas existentes con `status = 'active'`, inicializará `activated_at = created_at`. No inventará actor, motivo ni evento de auditoría para estados anteriores a HU-008; no existe evidencia para hacerlo.
3. Ejecutará, antes de eliminar o reemplazar la unicidad histórica, un precheck que compruebe que no haya más de una fila `active` por `(tenant_id, usuario_global_id)`. Si existe una anomalía, la migración fallará antes de soltar la restricción histórica y el DDL transaccional no dejará un cambio parcial.
4. Creará el índice único parcial `uq_agent_membership_active_tenant_user` sobre `(tenant_id, usuario_global_id)`, con predicado `status = 'active'`.
5. Soltará y reemplazará `uq_agent_membership_tenant_user` una vez superado el precheck. Esta sustitución es de la restricción, no de los datos: la unicidad de `invitation_id`, las claves foráneas y el check de estado permanecen.
6. Creará índices no únicos para las consultas tenant-scoped, al menos `(tenant_id, created_at, id)` en la membresía y `(tenant_id, occurred_at, audit_id)` en auditoría.

La 0014 es una evolución forward que preserva datos: aunque elimina/reemplaza la restricción histórica, no elimina ni transforma filas válidas, identidades globales, invitaciones ni historial. El precheck de activos duplicados hace segura esa sustitución. La combinación de los pasos 4 y 5 conserva una única activa durante la transición de esquema y luego habilita múltiples filas históricas no activas. No se crea un índice parcial global por `usuario_global_id`.

### 3.2 Entidad de auditoría

La entidad ORM será `AgentMembershipAudit`, en `agent_membership_models.py` o en el módulo de modelos tenant existente, y la tabla será `agent_membership_audit`. Sus columnas obligatorias serán:

| Columna | Tipo/semántica |
|---|---|
| `audit_id` | UUID, PK, generado por servidor o por la aplicación |
| `tenant_id` | UUID, FK a `tenant.id`, no nulo |
| `membership_id` | UUID, FK a `tenant_agent_membership.id`, no nulo |
| `usuario_global_id` | UUID, FK a `usuario_global.id`, no nulo |
| `actor_usuario_global_id` | UUID, FK a `usuario_global.id`, no nulo; es el principal autenticado |
| `actor_administrator_id` | UUID, FK a `tenant_administrator.id`, no nulo; fija el contexto administrativo usado |
| `previous_status` | `String(20)`, no nulo |
| `new_status` | `String(20)`, no nulo |
| `reason` | `String(500)`, no nulo, recortado y no vacío |
| `occurred_at` | timestamp con zona horaria, UTC, no nulo |
| `correlation_id` | UUID, no nulo |

Se añadirán checks para que ambos estados pertenezcan al enum y para que el par sea exactamente uno de `pending→active`, `active→inactive`, `inactive→active` o `active→revoked`. Los valores de identidad y tenant se toman de la fila bloqueada, nunca del body.

Este conjunto de columnas es el mínimo obligatorio para la auditoría: el actor es el ID del usuario principal autenticado (`actor_usuario_global_id`) junto con el contexto de administrador resuelto server-side (`actor_administrator_id` y su `tenant_id` efectivo). La auditoría no guardará contraseñas, tokens, secretos, payloads de petición ni contenido libre distinto de `reason`. No se expone una ruta para editar o borrar auditoría.

### 3.3 Enforcement append-only

La 0014 creará una función PostgreSQL y un trigger `BEFORE UPDATE OR DELETE` sobre `agent_membership_audit`. El trigger lanzará una excepción y rechazará ambas operaciones. El repositorio solo tendrá una operación interna de inserción; no habrá `update_audit` ni `delete_audit` en su protocolo.

El trigger protege la aplicación ordinaria y los escritores SQL normales. Una migración privilegiada puede administrar el esquema, pero cualquier bypass administrativo queda fuera del flujo de negocio y requiere una operación separada, no una corrección silenciosa. El downgrade eliminará el trigger únicamente después de comprobar que el entorno está vacío y que no se pierde historial.

## 4. Contrato HTTP y correlación

### 4.1 Rutas

El router nuevo (`backend/app/modules/tenant/agent_membership_router.py`) expondrá:

```text
GET  /api/v1/tenant/memberships
GET  /api/v1/tenant/memberships/{membership_id}
POST /api/v1/tenant/memberships/{membership_id}/activate
POST /api/v1/tenant/memberships/{membership_id}/deactivate
POST /api/v1/tenant/memberships/{membership_id}/revoke
```

Los tres comandos reciben exclusivamente:

```json
{"reason": "motivo administrativo"}
```

El esquema es `extra="forbid"`, exige `reason`, recorta espacios, rechaza vacío y limita el valor recortado a 500 caracteres. `tenant_id` es inválido aunque se envíe en body, query string o headers; no se ignora silenciosamente.

La representación `AgentMembershipResponse` incluye `membership_id`, `tenant_id` resuelto, `usuario_global_id`, `status`, `created_at`, `activated_at`, `deactivated_at` y `revoked_at`. Los comandos añaden `correlation_id`. Listado y obtención usan orden estable `created_at DESC, id DESC`; no exponen credenciales, tokens, secretos ni eventos de invitación.

### 4.2 Sobre de error estable

El sobre de error estable se aplica únicamente a las rutas de HU-008 de este router (listado, obtención y comandos); no se instala como contrato global y no modifica el contrato ni los sobres de error de HU-007.

Toda respuesta de error de estas rutas tendrá exactamente, como mínimo, las claves públicas:

```json
{
  "code": "MEMBERSHIP_STATE_CONFLICT",
  "message": "La transición de membresía no está permitida.",
  "correlation_id": "uuid"
}
```

Mapeo público:

| HTTP | `code` | Mensaje fijo |
|---:|---|---|
| 400 | `TENANT_SELECTION_NOT_ALLOWED` | El tenant no puede ser seleccionado por el cliente. |
| 401 | `AUTHENTICATION_REQUIRED` | Se requiere autenticación. |
| 403 | `TENANT_ADMIN_REQUIRED` | Se requiere un administrador del tenant. |
| 404 | `MEMBERSHIP_NOT_FOUND` | La membresía no existe. |
| 409 | `MEMBERSHIP_STATE_CONFLICT` | La transición de membresía no está permitida. |
| 422 | `INVALID_MEMBERSHIP_COMMAND` | El comando de membresía no es válido. |
| 500 | `MEMBERSHIP_OPERATION_FAILED` | No se pudo completar la operación. |

La misma respuesta `404` se usa para una membresía inexistente y una membresía de otro tenant; no se revela existencia cross-tenant. Violaciones del índice, `40001` y `40P01` se traducen a `409` después de rollback. Los mensajes de excepción de SQLAlchemy no salen de la API.

`app/core/correlation.py` centralizará `resolve_correlation_id(request)`: aceptará un `X-Correlation-ID` que sea UUID canónico válido y conservará exactamente ese valor, sin sustituirlo; generará un UUID del servidor (`uuid4()`) si el header falta o es inválido. El UUID se enviará en el sobre, se guardará en cada evento efectivo y, opcionalmente, también en la respuesta `X-Correlation-ID`.

El router usará ese valor antes de resolver el servicio. La dependencia de autenticación se ejecuta antes del handler, por lo que `app/main.py` deberá adaptar únicamente para rutas `/api/v1/tenant/memberships...` las respuestas de `HTTPException` 401 y `RequestValidationError` 422 al mismo sobre, sin alterar los contratos existentes de otras rutas. Los errores de validación no incluirán valores de `reason` ni otros datos sensibles.

## 5. Seams exactos `router → service → repository`

### 5.1 Router y dependencias

El router tendrá dependencias separadas, reutilizando los componentes actuales:

- `get_current_user` para obtener `MeResponse`; no se acepta un actor en el body.
- `get_db` para una única `Session` por request.
- `TenantRepository(db)` usado por `TenantContextResolver`.
- `AgentMembershipRepository(db)` para la operación de membresía.
- `get_clock()` para un reloj inyectable.
- `AgentMembershipService(repository, context_resolver, clock)`.

El router solo verifica presencia de campos de autoridad, valida el payload, resuelve la correlación, llama al servicio y mapea excepciones. No consulta membresías, no decide el tenant y no muta ORM.

### 5.2 Servicio

El servicio tendrá un protocolo equivalente a:

```python
list_memberships(principal_id: UUID, correlation_id: UUID) -> list[MembershipProjection]
get_membership(principal_id: UUID, membership_id: UUID, correlation_id: UUID) -> MembershipProjection
transition(
    principal_id: UUID,
    membership_id: UUID,
    target: MembershipTarget,
    reason: str,
    correlation_id: UUID,
) -> MembershipTransitionResult
```

En cada método llama primero a `TenantContextResolver.resolve_admin(principal_id)`. `TenantAdminRequiredError` se transforma en `TENANT_ADMIN_REQUIRED`. El resolver conserva el seam actual: principal activo, administrador activo, invitación de administración consumida y un contexto único; si no existe un contexto administrativo válido, no se intenta inferirlo desde la petición.

El servicio normaliza/valida el comando y delega la decisión transaccional al repositorio. Proyecta solo campos no sensibles y no expone una excepción interna. No recibe `tenant_id` ni de ruta, ni de query, ni de body.

### 5.3 Repositorio

`AgentMembershipRepository` expondrá como mínimo:

```python
list_for_tenant(tenant_id: UUID) -> list[TenantAgentMembership]
find_for_tenant(tenant_id: UUID, membership_id: UUID) -> TenantAgentMembership | None
transition_for_tenant(
    context: TenantContext,
    membership_id: UUID,
    target: MembershipTarget,
    actor_usuario_global_id: UUID,
    reason: str,
    occurred_at: datetime,
    correlation_id: UUID,
) -> MembershipTransitionResult
has_active_membership(tenant_id: UUID, usuario_global_id: UUID) -> bool
```

`find_for_tenant` siempre incluye ambos predicados `id = membership_id` y `tenant_id = context.tenant_id`; una ausencia es indistinguible de tenant cruzado. Las consultas de listado también filtran por el tenant resuelto. El repositorio valida que `actor_administrator_id` y `actor_usuario_global_id` correspondan al `TenantContext` entregado antes de insertar auditoría; no confía en un identificador recibido del cliente.

## 6. Locks y concurrencia PostgreSQL

Todos los comandos de estado usan la misma secuencia, incluyendo activate, deactivate y revoke. El plan usa bloqueos deterministas de PostgreSQL con filas tenant/target (fila target y filas candidatas filtradas por tenant): el alcance de serialización es `(tenant_id, usuario_global_id)`, y las filas target/candidatas se bloquean siempre en el mismo orden.

1. El servicio resuelve el contexto administrativo antes de iniciar la mutación. La resolución actual puede tomar sus locks de administrador/suscripción; ningún comando de membresía toma locks de membresía antes de esta etapa.
2. El repositorio hace `rollback()` de cualquier estado pendiente de la sesión y lee el `usuario_global_id` de la membresía objetivo con filtro de tenant, **sin lock**, solo para obtener la clave de serialización. Si no existe, devuelve `MEMBERSHIP_NOT_FOUND` sin cambiar datos.
3. En PostgreSQL toma `pg_advisory_xact_lock` con dos claves derivadas determinísticamente de `(tenant_id, usuario_global_id)`, usando la representación UUID y un hash PostgreSQL estable. Se toma antes de cualquier lock de fila de membresía. En fakes se modela como un mutex por la misma tupla.
4. Selecciona con `FOR UPDATE` todas las filas de membresía de ese tenant/target `(tenant_id, usuario_global_id)`, ordenadas ascendentemente por `id`; así se bloquean target y candidatas en el mismo orden para todos los comandos.
5. Verifica nuevamente la existencia y el estado del target. En una activación, comprueba las activas distintas del target en el conjunto bloqueado; una anomalía de más de una activa es conflicto y provoca rollback.
6. Aplica actualizaciones en orden ascendente de `id`: primero cada activa reemplazada a `inactive`, luego el target a `active`. Inserta el evento de cada transición en ese mismo orden. Solo después hace `flush` y `commit`.

El lock advisory se obtiene antes del `FOR UPDATE` de filas precisamente para evitar el ciclo `M1-row → advisory` / `M2-row → advisory` entre dos activaciones distintas. Commands opuestos sobre la misma membresía o sobre otra membresía del mismo usuario/tenant comparten la misma clave y la misma secuencia. No se usan locks adquiridos en orden dependiente de la llegada de comandos.

Dos activaciones válidas concurrentes del mismo tenant/target se serializan: la transacción confirmada más tarde es la que gana (`latest committed transaction wins`), su membresía queda `active` y la activa previa queda `inactive`. Ambas operaciones válidas responden `200`; competir no es por sí solo un `409`, y cada transición resultante se audita con el mismo `correlation_id` dentro de su operación. Nunca se confirma un estado con dos activas. Si una operación falla con `40001` o `40P01`, se hace rollback y se devuelve `409`, sin reintento automático.

## 7. Máquina de estados e idempotencia

La decisión se toma bajo los locks, con esta matriz:

| Estado observado | `activate` | `deactivate` | `revoke` |
|---|---|---|---|
| `pending` | `200`, cambia a `active`, un audit `pending→active` | `409`, sin cambio ni audit | `409`, sin cambio ni audit |
| `active` | `200` idempotente, conserva timestamps, sin audit; si hubiera anomalía global, `409` | `200`, cambia a `inactive`, un audit `active→inactive` | `200`, cambia a `revoked`, un audit `active→revoked` |
| `inactive` | `200`, cambia a `active`, un audit `inactive→active`; puede reemplazar otra activa | `200` idempotente, conserva timestamps, sin audit | `409`, sin cambio ni audit |
| `revoked` | `409`, terminal, sin audit | `409`, sin cambio ni audit | `200` idempotente, conserva timestamps, sin audit |
| inexistente/otro tenant | `404`, sin revelar cuál | `404`, sin revelar cuál | `404`, sin revelar cuál |

Los comandos opuestos concurrentes no se consideran idempotentes entre sí. El segundo adquiere el lock, vuelve a leer y devuelve `200` si su transición aún es válida o `409` si el estado confirmado ya no permite su operación. Cada respuesta representa el commit de su propia transacción.

Semántica normativa de timestamps (los nombres públicos y persistidos son exactamente `created_at`, `activated_at`, `deactivated_at`, `revoked_at` y `occurred_at`):

- `activated_at` se establece en cada transición efectiva hacia `active`; repetir `activate` no lo cambia.
- `deactivated_at` se establece en cada `active→inactive`; al reactivar se limpia para representar que la fila está activa nuevamente.
- `revoked_at` se establece una sola vez en `active→revoked`; `revoked` no puede salir de ese estado.
- En el reemplazo, la membresía anterior conserva `activated_at` y recibe `deactivated_at`; la nueva recibe `activated_at`.
- Las filas históricas existentes sin evidencia de transición conservan sus timestamps nuevos en `NULL`, excepto `active`, cuyo `activated_at` se backfillea con `created_at` durante 0014.

## 8. Transacción, rollback y errores de base de datos

`transition_for_tenant` es una unidad atómica. Dentro de una sola transacción PostgreSQL se realizan lock, cambio de todas las filas reemplazadas, cambio del target, inserción de todos los eventos, `flush` y `commit`.

Ante cualquier excepción de dominio, `IntegrityError`, error de serialización, deadlock o error de auditoría:

1. se ejecuta `session.rollback()`;
2. se descarta tanto el cambio de membresía como todos los eventos de esa operación;
3. los errores PostgreSQL `40001` y `40P01` se traducen a `409` después del rollback;
4. no se hace reintento automático, no se reintenta parcialmente ni se inserta una auditoría compensatoria.

Una violación del índice parcial se trata como `MEMBERSHIP_STATE_CONFLICT`. Los locks advisory son transaccionales y se liberan con commit o rollback. Las operaciones de lectura no abren una transacción de escritura ni generan auditoría; una lectura cross-tenant termina como `404`.

Los fakes deberán modelar commit/rollback y permitir inyectar un fallo al insertar auditoría para demostrar que el estado también se revierte. El repositorio real no debe usar commits separados para la membresía y la auditoría.

## 9. Seam mínimo de acceso activo

Se añadirá `backend/app/modules/tenant/agent_membership_access.py` con un seam pequeño y explícito:

```python
require_active_membership(
    context: TenantContext,
    principal_id: UUID,
) -> ActiveMembershipContext
```

Su repositorio consulta únicamente `tenant_agent_membership` con `tenant_id = context.tenant_id`, `usuario_global_id = principal_id` y `status = 'active'`. Si no encuentra una fila activa, lanza `InactiveAgentMembershipError`; no distingue públicamente `pending`, `inactive` y `revoked` si el consumidor no lo requiere. Devuelve la membresía activa para que un consumidor posterior continúe hacia sus propias verificaciones.

Este seam no asigna permisos, no interpreta roles, no usa `Plan.max_agents`, no invalida sesiones, no modifica credenciales y no se conecta todavía a publicación, captura, reservas o cualquier otro recurso. HU-009 será quien defina autorización fina.

## 10. Compatibilidad con HU-007

La aceptación de HU-007 continuará creando exactamente una fila `tenant_agent_membership` con `status = 'pending'`, la misma `invitation_id`, la invitación `accepted` y su `AgentInvitationEvent(accepted)` dentro de la transacción existente. No se generará auditoría de HU-008 ni se activará la membresía automáticamente.

La eliminación de `uq_agent_membership_tenant_user` exige un ajuste de compatibilidad acotado en `agent_invitation_repository.py`: los guardas de emisión/aceptación deben consultar si existe una membresía **activa**, no si existe cualquier fila histórica. Así una invitación válida posterior a una membresía `inactive` o `revoked` puede crear otra fila `pending`; la invitación no puede elegir el estado `active`. Se conservan sin cambios el contrato HTTP, los sobres de error y las respuestas de HU-007, y una membresía activa existente puede seguir produciendo el conflicto de membresía definido por HU-007. No se cambia el router de invitaciones ni el esquema de sus payloads.

La regresión obligatoria verificará que una aceptación nueva produce una sola membresía pending, no crea `agent_membership_audit`, no cambia una fila histórica y no altera credenciales de `UsuarioGlobal`. `AgentInvitationEvent` seguirá siendo exclusivamente de invitación.

## 11. Seguridad de upgrade/downgrade

### Upgrade

- La 0014 depende de 0013 y usa DDL transaccional de PostgreSQL.
- Es una evolución forward que preserva datos: se reemplaza la unicidad histórica por la unicidad activa correcta, pero no se eliminan ni transforman filas, identidades globales o eventos válidos.
- Se aplica antes de desplegar el código que emite comandos; el código HU-007 existente puede seguir leyendo/escribiendo las columnas antiguas durante la migración.
- Se hace fail-closed si hay duplicados activos o si alguna precondición de esquema no coincide; el precheck ocurre antes de soltar la restricción histórica y no se eliminan filas ni eventos.
- El backfill solo copia `created_at` a `activated_at` de filas ya activas; no fabrica auditoría.
- Tras el upgrade se verifican el índice parcial, trigger, checks, FKs y la ausencia de una unicidad histórica residual.

### Downgrade

El downgrade es deliberadamente fail-closed. Antes de cambiar el esquema comprueba que `agent_membership_audit` y `tenant_agent_membership` estén vacías y que no haya duplicados para reinstalar la unicidad histórica. Si existe cualquier fila, lanza un error y no elimina ni historial ni timestamps. Solo en una base vacía elimina trigger/función, tabla de auditoría, índices y columnas nuevas, y reinstala `uq_agent_membership_tenant_user`.

Un rollback de aplicación se hará deshabilitando el enrutamiento de los nuevos comandos, no modificando estados ni borrando auditoría. Una corrección funcional posterior debe ser otra transición administrativa válida.

## 12. Límites de archivos

### Archivos que podrá tocar la implementación de HU-008

- `backend/app/modules/tenant/models.py`: campos lifecycle, enum ya existente y entidad ORM de auditoría.
- `backend/app/modules/tenant/schemas.py`: request de comando, proyecciones y respuesta de membresía.
- `backend/app/modules/tenant/agent_membership_router.py`: rutas, dependencias, autoridad de cliente y mapeo de errores.
- `backend/app/modules/tenant/agent_membership_service.py`: contexto, validación de negocio y proyección.
- `backend/app/modules/tenant/agent_membership_repository.py`: locks, transacción, reemplazo y auditoría.
- `backend/app/modules/tenant/agent_membership_access.py`: seam de estado activo.
- `backend/app/modules/tenant/agent_invitation_repository.py`: ajuste mínimo de guardas para que HU-007 distinga historial no activo.
- `backend/app/core/correlation.py`: validación/generación de correlación.
- `backend/app/main.py`: adaptación acotada de 401/422 de las rutas de membresías al sobre estable.
- `backend/alembic/versions/0014_hu008_membership_lifecycle.py`: migración, índice parcial, tabla y trigger append-only.
- `backend/tests/test_hu008_agent_memberships.py`: fakes y servicio/API enfocados.
- `backend/tests/test_hu008_agent_membership_repository.py`: repositorio, rollback y contratos de locks.
- `backend/tests/test_hu008_postgresql.py` o fixture PostgreSQL existente: migración, índice y concurrencia real.
- `backend/tests/test_hu007_agent_invitations.py`: regresión puntual de aceptación pending.

### Archivos que no se deben tocar

- Panel React, apps Flutter, worker 3D y contratos Solidity.
- Módulos de publicación, reservas o captura para integrar enforcement.
- RBAC, catálogo de permisos y `Plan.max_agents`.
- `backend/alembic/versions/0013_hu007_agent_invitations.py`.
- `docs/diagramas/Diagrama1.eapx`.
- Tareas SDD, propuesta, spec y artefactos de otras HU.

## 13. Verificación enfocada

### Fakes y servicio

- Cada transición permitida y cada transición inválida de la matriz.
- Terminalidad e idempotencia de `revoked`.
- Repetición sin cambio de timestamps ni auditoría.
- Reemplazo: dos cambios, dos auditorías, un solo active.
- Actor no administrador y contexto ambiguo.
- Tenant no aportado por el cliente y aislamiento en listado/obtención.
- Fallo de auditoría con rollback conjunto.
- Correlación válida conservada, ausente/inválida generada y ningún secreto en mensajes.

### API

- 401 sin bearer o bearer inválido con sobre `AUTHENTICATION_REQUIRED`.
- 403 con `TENANT_ADMIN_REQUIRED`.
- 400 para `tenant_id` en body, query o headers.
- 404 indistinguible para ID inexistente y ID de T2.
- 422 para `reason` ausente, vacío, solo espacios, mayor a 500 o campos extra.
- 200 de comandos válidos e idempotentes con `correlation_id`.
- Respuestas sin password, token, secreto o payload sensible.

### Repositorio y PostgreSQL

- Constraints/checks y migración 0013→0014 con filas pending existentes.
- Sustitución de la unicidad histórica por el índice parcial activo.
- Dos tenants con el mismo usuario, ambos activos sin conflicto.
- Dos filas históricas no activas del mismo tenant/usuario.
- Dos activaciones concurrentes del mismo usuario/tenant.
- Activación concurrente con desactivación o revocación, en ambos órdenes.
- Fallo de `flush`/insert de auditoría y comprobación de rollback completo.
- Trigger que rechaza `UPDATE` y `DELETE` de auditoría.
- Downgrade rechazado cuando hay membresías o auditoría y permitido solo en base vacía.

Los tests PostgreSQL reales son necesarios para locks, índice parcial, trigger y migración; los fakes no constituyen evidencia de concurrencia. CP-007 se ejecutará y documentará por separado, sin presentarlo como resultado de esta verificación técnica.

## 14. Resultado SDD y siguiente fase

- **Resultado:** diseño técnico completo para HU-008, alineado con la propuesta aprobada y la spec normativa.
- **Persistencia:** este artefacto queda escrito en `openspec/changes/hu008-membresias-agentes/design.md`.
- **Cambios de código realizados en esta fase:** ninguno.
- **Cambios de tareas realizados en esta fase:** ninguno.
- **Commits/push:** ninguno.
- **Riesgos controlados:** unicidad tenant-scoped, deadlocks por orden de locks, auditoría parcial, fuga cross-tenant, downgrade destructivo y adelanto de RBAC.
- **Siguiente fase autorizable:** `tasks`, con desglose TDD por los límites de archivo anteriores. La implementación no debe comenzar antes de que existan tareas autorizadas.
- **Gates preservados:** no se asume ejecución de CP-007, no se autoriza UI/mobile/publicación/RBAC, y cualquier diff que exceda el presupuesto de revisión deberá detenerse para una decisión de partición conforme a `ask-on-risk`.

**skill_resolution:** `none` (no se inyectó una ruta de skill SDD específica; el diseño se realizó con el contrato OpenSpec y las instrucciones del proyecto).
