# Membresías de agentes — Especificación

## Propósito

Definir el ciclo de vida administrativo de las membresías de agentes de RoomForge para PB-007 / HU-008 / CU-008, incluyendo autorización tenant-scoped, consulta, transiciones, auditoría, aislamiento y el contrato HTTP consumible por futuros clientes Web. Este cambio no implementa UI, mobile, publicación ni RBAC de HU-009.

## Requisitos

### Requisito: Autorización administrativa derivada server-side

El sistema MUST obtener el principal autenticado y resolver server-side el contexto administrativo del tenant antes de listar, obtener o modificar una membresía. El tenant efectivo MUST provenir del contexto autorizado y el sistema MUST ignorar o rechazar cualquier `tenant_id` suministrado por body, query string o header; ningún dato del cliente puede seleccionar el tenant objetivo.

#### Escenario: Administrador consulta su tenant

- GIVEN un principal autenticado con contexto de administrador resuelto para el tenant T1
- WHEN solicita una operación de membresía sin seleccionar un tenant en la petición
- THEN el sistema ejecuta la operación únicamente dentro de T1

#### Escenario: Actor autenticado sin administración

- GIVEN un principal autenticado sin contexto administrativo válido
- WHEN solicita listar, obtener o modificar una membresía
- THEN el sistema responde `403` con el código estable `TENANT_ADMIN_REQUIRED` y no revela datos de membresías

#### Escenario: Tenant manipulado por el cliente

- GIVEN un administrador de T1 que incluye `tenant_id=T2` en body, query o header
- WHEN solicita una operación
- THEN el sistema rechaza la petición con `400` y código `TENANT_SELECTION_NOT_ALLOWED`, sin usar T2 como autoridad ni devolver datos de T2

### Requisito: Visibilidad de membresías tenant-scoped

El sistema MUST exponer `GET /api/v1/tenant/memberships` para listar únicamente membresías del tenant administrativo resuelto y `GET /api/v1/tenant/memberships/{membership_id}` para obtener una sola membresía de ese tenant. Las respuestas MUST incluir identificadores no sensibles, `tenant_id` resuelto, `usuario_global_id`, estado y timestamps pertinentes, y MUST excluir credenciales, tokens, secretos y payloads sensibles.

#### Escenario: Listado propio

- GIVEN un administrador de T1 y membresías de T1 y T2
- WHEN solicita `GET /api/v1/tenant/memberships`
- THEN recibe solamente las membresías de T1, con respuesta `200`

#### Escenario: Obtención fuera del tenant

- GIVEN un administrador de T1 y un `membership_id` perteneciente a T2
- WHEN solicita `GET /api/v1/tenant/memberships/{membership_id}`
- THEN recibe `404` con código `MEMBERSHIP_NOT_FOUND`, indistinguible de una membresía inexistente

### Requisito: Máquina de estados de membresía

El sistema MUST conservar la misma fila de membresía y MUST permitir exactamente estas transiciones administrativas: `pending → active`, `active → inactive`, `inactive → active` y `active → revoked`. Toda transición no enumerada MUST rechazarse sin modificar la membresía ni crear auditoría. `revoked` MUST ser terminal. En cada activación efectiva (`pending → active` o `inactive → active`), `activated_at` MUST establecerse al instante de esa activación; en `active → inactive`, `deactivated_at` MUST establecerse; en toda reactivación, `deactivated_at` MUST limpiarse; y en `active → revoked`, `revoked_at` MUST establecerse una sola vez. Las operaciones idempotentes MUST conservar sus timestamps sin cambios.

#### Escenario: Activación inicial

- GIVEN una membresía `pending` del tenant del administrador
- WHEN ejecuta el comando de activación
- THEN la membresía pasa a `active`, establece `activated_at` y la respuesta devuelve su estado actualizado

#### Escenario: Desactivación reversible

- GIVEN una membresía `active` del tenant del administrador
- WHEN ejecuta el comando de inactivación
- THEN pasa a `inactive`, establece `deactivated_at` y deja de ser elegible para acceso operativo

#### Escenario: Reactivación

- GIVEN una membresía `inactive` del tenant del administrador
- WHEN ejecuta el comando de activación
- THEN pasa a `active`, actualiza `activated_at`, limpia `deactivated_at`, y no crea una cuenta global ni una nueva membresía

#### Escenario: Revocación terminal

- GIVEN una membresía `active` del tenant del administrador
- WHEN ejecuta el comando de revocación
- THEN pasa a `revoked`, establece `revoked_at` una sola vez y conserva su identidad y autoría histórica

#### Escenario: Estado revocado

- GIVEN una membresía `revoked`
- WHEN se solicita activarla o inactivarla
- THEN responde `409` con `MEMBERSHIP_STATE_CONFLICT`, permanece `revoked` y no se crea auditoría de transición

- GIVEN una membresía `revoked`
- WHEN se repite el comando de revocación
- THEN responde `200` idempotentemente, permanece `revoked` y no se crea una auditoría adicional

### Requisito: Unicidad activa y movilidad multi-tenant

El sistema MUST garantizar en PostgreSQL que exista como máximo una membresía `active` para cada `(tenant_id, usuario_global_id)`, incluso ante comandos concurrentes. La persistencia MUST permitir varias membresías históricas para el mismo par cuando sus estados no sean `active`, para soportar reemplazo y trazabilidad. MUST permitir que el mismo `usuario_global_id` tenga una membresía `active` en T1 y otra en T2. No debe aplicarse una unicidad activa global por usuario.

Cuando se active una membresía y exista otra `active` del mismo usuario en el mismo tenant, el comando MUST convertir la anterior a `inactive` dentro de la misma operación atómica antes de confirmar la activación. Cada transición resultante MUST quedar auditada.

#### Escenario: Reemplazo dentro del tenant

- GIVEN una membresía activa M1 del usuario U en T1 y otra membresía M2 de U en T1 no activa
- WHEN el administrador activa M2
- THEN M2 queda `active`, M1 queda `inactive`, existe como máximo una activa para `(T1,U)` y se conservan ambas filas

#### Escenario: Usuario en múltiples tenants

- GIVEN U tiene una membresía activa en T1
- WHEN un administrador de T2 activa una membresía de U en T2
- THEN la activación es válida y U mantiene una membresía activa independiente en cada tenant

#### Escenario: Carrera de activaciones

- GIVEN dos comandos concurrentes válidos intentan activar membresías distintas de U en el mismo tenant
- WHEN PostgreSQL serializa las transacciones
- THEN la transacción confirmada más tarde deja su membresía `active`, la membresía que estaba activa previamente queda `inactive`, ambas transiciones quedan auditadas y ninguna operación recibe `409` únicamente por haber competido; nunca se confirma un estado con dos activas

### Requisito: Comandos HTTP estables

El sistema MUST exponer estos comandos, todos tenant-scoped por el contexto server-side: `POST /api/v1/tenant/memberships/{membership_id}/activate`, `POST /api/v1/tenant/memberships/{membership_id}/deactivate` y `POST /api/v1/tenant/memberships/{membership_id}/revoke`. Los comandos MUST aceptar un JSON con `reason` obligatorio, no vacío y de 1 a 500 caracteres, y responder `200` con la representación actualizada. La respuesta MUST incluir `membership_id`, `tenant_id`, `usuario_global_id`, `status`, timestamps de ciclo de vida y `correlation_id`. Un `X-Correlation-ID` ausente o inválido MUST causar que el servidor genere un UUID; un valor válido y canónico MUST conservarse sin sustitución.

Solo estas rutas de HU-008 MUST usar el sobre de error estable con `code`, `message` y `correlation_id`; esta regla MUST NOT modificar el contrato ni los sobres de error de HU-007. En las rutas de HU-008, los errores MUST mapearse así: `401`/`AUTHENTICATION_REQUIRED` para principal ausente o inválido; `403`/`TENANT_ADMIN_REQUIRED` para falta de autorización; `404`/`MEMBERSHIP_NOT_FOUND` para inexistencia o tenant cruzado; `409`/`MEMBERSHIP_STATE_CONFLICT` para estado incompatible o conflicto de base de datos; y `422`/`INVALID_MEMBERSHIP_COMMAND` para payload inválido. Una carrera válida de activación MUST NOT producir `409` únicamente por concurrencia. Los mensajes no MUST revelar existencia cross-tenant.

#### Escenario: Comando válido

- GIVEN un administrador autorizado y un payload válido
- WHEN envía uno de los comandos definidos
- THEN recibe `200`, el estado resultante y un `correlation_id` trazable

#### Escenario: Correlación inválida o ausente

- GIVEN un comando de HU-008 sin `X-Correlation-ID` o con un valor que no sea UUID canónico válido
- WHEN se procesa la petición
- THEN el servidor genera un UUID y lo devuelve en el sobre o representación de respuesta

#### Escenario: Correlación válida

- GIVEN un comando de HU-008 con un `X-Correlation-ID` UUID canónico válido
- WHEN se procesa la petición
- THEN la respuesta y la auditoría conservan exactamente ese identificador

#### Escenario: Payload inválido

- GIVEN un comando con `reason` ausente, vacío o inválido
- WHEN se procesa la petición
- THEN responde `422` con `INVALID_MEMBERSHIP_COMMAND` y no modifica estado ni auditoría

### Requisito: Idempotencia de comandos repetidos

Los comandos MUST ser idempotentes respecto del estado objetivo. Repetir `activate` sobre una membresía ya `active`, `deactivate` sobre una ya `inactive` o `revoke` sobre una ya `revoked` MUST devolver `200` con la representación vigente, sin cambiar timestamps de transición y sin insertar una auditoría adicional. Un comando que solicite un estado distinto al permitido por la máquina MUST responder `409` sin cambios. Un conflicto de base de datos que no sea una carrera válida, incluidos conflictos de estado o de invariante, MUST responder `409` después de rollback.

#### Escenario: Repetición del mismo comando

- GIVEN una transición ya confirmada
- WHEN el mismo comando se repite una o más veces
- THEN cada repetición devuelve el estado vigente, sin duplicar efectos ni eventos de auditoría

#### Escenario: Comandos opuestos concurrentes

- GIVEN comandos concurrentes de activación e inactivación sobre la misma membresía
- WHEN ambos se serializan
- THEN cada resultado refleja el estado confirmado por su transacción; no hay actualización parcial, y solo una operación que resulte inválida por el estado confirmado o por un conflicto de base de datos recibe `409`, nunca una carrera válida por sí sola

### Requisito: Auditoría append-only y atómica

Cada transición efectiva MUST insertar exactamente un registro append-only con `audit_id`, `tenant_id`, `membership_id`, `usuario_global_id`, `actor_usuario_global_id` (o identificador equivalente del principal autenticado), el contexto del administrador de tenant resuelto server-side (incluyendo su identificador de usuario y tenant efectivo), `previous_status`, `new_status`, `reason`, `occurred_at` y `correlation_id`. El registro MUST ser inmutable para la aplicación ordinaria y MUST estar protegido por un trigger append-only que rechace UPDATE y DELETE. MUST no contener contraseñas, tokens, secretos ni payloads sensibles.

El cambio de estado, cualquier reemplazo de una membresía activa y sus registros de auditoría MUST confirmarse en una única transacción. Si falla la persistencia de la membresía, la auditoría o una invariante, MUST revertirse todo el conjunto. Los errores PostgreSQL de serialización `40001` y deadlock `40P01` MUST provocar rollback y mapearse a `409`; no debe quedar transición sin auditoría ni auditoría de una transición no confirmada.

#### Escenario: Transición auditada

- GIVEN una transición válida que cambia el estado
- WHEN la transacción confirma
- THEN existe el registro de auditoría con actor autenticado, contexto de administrador resuelto, todos los campos obligatorios y el estado nuevo es observable

#### Escenario: Fallo durante auditoría

- GIVEN una transición cuyo registro de auditoría no puede persistirse
- WHEN la operación termina
- THEN se revierte también el cambio de membresía y no queda ningún registro parcial

#### Escenario: Serialización o deadlock

- GIVEN una operación que falla con PostgreSQL `40001` o `40P01`
- WHEN el servicio maneja el error
- THEN ejecuta rollback, no persiste ninguna transición parcial y responde `409`

### Requisito: Seam de acceso para estados no activos

El sistema MUST ofrecer al enforcement operativo de membresías una condición explícita según la cual solo `active` habilita el acceso de agente dentro del tenant resuelto. `pending`, `inactive` y `revoked` MUST negar ese acceso. Este seam MUST permanecer fuera de RBAC y no MUST asignar permisos, roles o capacidades de HU-009, invalidar sesiones, modificar sesiones o modificar credenciales.

#### Escenario: Acceso con membresía no activa

- GIVEN una solicitud futura de recurso operativo con membresía `pending`, `inactive` o `revoked`
- WHEN el seam de membresía evalúa el acceso
- THEN deniega la operación con el error de autorización definido por el consumidor, sin borrar la membresía, su auditoría ni modificar sesiones

#### Escenario: Acceso con membresía activa

- GIVEN una solicitud futura con membresía `active` en el tenant autorizado
- WHEN el seam evalúa el acceso
- THEN la condición de membresía permite continuar hacia las verificaciones de permisos que quedan fuera de HU-008 y no muta sesiones

### Requisito: Migración y compatibilidad con HU-007

La evolución de persistencia MUST ser aditiva y MUST conservar filas, identidad global y eventos históricos existentes. La migración Alembic `0014` MUST ser una migración forward que, antes de eliminar la unicidad histórica por tenant/usuario, compruebe y rechace explícitamente la existencia de filas activas duplicadas; luego MUST aplicar la unicidad activa por `(tenant_id, usuario_global_id)`. Este precheck hace segura la evolución porque evita descartar una restricción histórica mientras existan datos incompatibles y no elimina ni transforma datos válidos. La aceptación de invitación de HU-007 MUST continuar creando exactamente una membresía `pending`, sin activarla, reemplazarla ni alterar la semántica de invitaciones. Los datos existentes deben poder actualizarse sin eliminar historial. El downgrade de `0014` MUST ser fail-closed: solo puede ejecutarse cuando los objetos nuevos y sus datos estén vacíos; ante cualquier fila o dependencia histórica, MUST fallar sin borrar auditoría ni membresías.

#### Escenario: Regresión de aceptación HU-007

- GIVEN una invitación válida aceptada según HU-007
- WHEN finaliza la aceptación
- THEN se crea exactamente una membresía `pending` y no se genera una transición de activación de HU-008

#### Escenario: Actualización con datos existentes

- GIVEN filas de membresía creadas por HU-007 antes de la migración y ningún duplicado activo para el mismo `(tenant_id, usuario_global_id)`
- WHEN se aplica la migración forward `0014`
- THEN el precheck permite continuar, se elimina únicamente la unicidad histórica reemplazada, se aplica la unicidad activa correcta, las filas permanecen consultables y no se elimina auditoría ni identidad histórica

#### Escenario: Migración bloqueada por duplicados

- GIVEN existen dos filas `active` para el mismo `(tenant_id, usuario_global_id)` bajo el esquema histórico
- WHEN se ejecuta `0014`
- THEN el precheck falla antes de eliminar la restricción histórica y no se realiza ningún cambio parcial

#### Escenario: Downgrade fail-closed

- GIVEN existen filas de auditoría, membresías o dependencias de los objetos introducidos por `0014`
- WHEN se solicita el downgrade
- THEN el downgrade falla sin borrar datos; solo un estado completamente vacío permite continuar

### Requisito: Exclusiones de alcance

HU-008 MUST NOT implementar RBAC, catálogo de permisos o autorización fina de HU-009; publicación, revisión o catálogo de inmuebles; `Plan.max_agents`, suscripciones, cuotas o facturación; panel React, aplicaciones Flutter, worker 3D, contratos Solidity, notificaciones generales ni operaciones de producción.

#### Escenario: Solicitud de capacidad fuera de HU-008

- GIVEN una petición para asignar roles/permisos o publicar un inmueble
- WHEN se evalúa el alcance de este cambio
- THEN no se modifica ni se considera satisfecha por el contrato de membresías de HU-008
