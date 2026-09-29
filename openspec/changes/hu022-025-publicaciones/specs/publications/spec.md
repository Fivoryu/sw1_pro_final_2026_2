# Publications Specification

## Purpose

Definir el contrato HTTP backend de publicaciones para PB-028, PB-029 y PB-030, trazado a HU-022, HU-023, HU-024 y HU-025 (CU-024, CU-025 y CU-026). El contrato expone el workflow existente al consumidor Web sin trasladar al cliente la autoridad sobre tenant, actor, rol, estado ni versión.

Esta especificación adopta `revision-replacement`, `admin-approval-publish`, `existing-authorizer`, `existing-model` y `reuse-hu006-policy`. HU-026, HU-009 y las superficies panel, mobile, worker 3D y Solidity quedan fuera de alcance.

## Requisitos

### Requirement: Contrato de autenticación, tenant y autoridad server-side

La API MUST requerir la sesión/autenticación vigente y MUST resolver actor, rol y tenant exclusivamente mediante el authorizer server-owned existente. Ningún `tenant_id`, actor, rol, permiso, estado, timestamp o versión enviado por el cliente MUST ser usado como autoridad. Un recurso ajeno MUST tratarse como no disponible, sin revelar su existencia.

#### Scenario: Actor autorizado opera dentro de su tenant

- GIVEN una sesión válida cuyo authorizer resuelve actor, rol y tenant autorizados
- WHEN el actor invoca una operación de publicaciones con un identificador del recurso de ese tenant
- THEN la operación se evalúa con la identidad, rol y tenant resueltos por el servidor

#### Scenario: El cliente intenta suplantar autoridad

- GIVEN una sesión válida y un payload que incluye `tenant_id`, `actor_id`, `role`, `status` o `version` como campos adicionales
- WHEN se envía una operación mutadora
- THEN la API rechaza los campos no contractuales con `422` y código `validation_error`, o los ignora únicamente si no son parte del payload aceptado; nunca los usa para autorizar ni para modificar el dominio

#### Scenario: Recurso de otro tenant

- GIVEN una sesión autorizada para el tenant A y una publicación o revisión perteneciente al tenant B
- WHEN el actor solicita o muta ese recurso
- THEN la API responde `404` con código `resource_not_found` y no revela si el identificador existe

#### Scenario: Sesión ausente o authorizer inválido

- GIVEN una solicitud sin sesión válida o cuyo authorizer no puede resolver una autoridad válida
- WHEN se invoca cualquier ruta administrativa
- THEN la API responde `401` con código `authentication_required` o `403` con código `not_authorized`, según corresponda, sin mutar datos

### Requirement: Creación y reemplazo inmutable de borradores (HU-022)

La API MUST exponer `POST /api/v1/publications/{publication_id}/revisions` para crear un borrador. El body MUST contener exactamente el contenido completo exigido por `PublicationRevision`: `title`, `description`, `operation_type`, `price_amount`, `currency`, `location_policy`, `location_value`, `media_refs`, `model_3d_refs` y `attributes`. Los valores MUST cumplir las validaciones del modelo existente y los campos desconocidos MUST rechazarse.

La operación MUST crear una nueva revisión con versión monótona siguiente y estado `borrador`; MUST NOT actualizar ninguna revisión existente. La respuesta exitosa MUST ser `201` y contener `id`, `publication_id`, `version`, `status`, los diez campos de contenido y `created_at`, junto con `created_by_actor_id` y `created_by_role` resueltos por el servidor. No MUST incluirse `tenant_id` recibido del cliente como dato de autoridad.

Una solicitud repetida con el mismo `Idempotency-Key` y el mismo contenido MUST devolver el mismo resultado lógico sin crear otra revisión. Reutilizar la clave con contenido o recurso diferente MUST responder `409` con código `idempotency_key_reused`.

Si existe una revisión publicada, crear o reemplazar un borrador MUST conservarla publicada y su `published_version`. El cliente MAY enviar `If-Match: "vN"` como precondición de concurrencia; si no coincide con la versión publicada actual, la API MUST responder `412` con código `publication_version_conflict` y no crear revisión.

#### Scenario: Crear un borrador completo

- GIVEN un agente autorizado, una publicación de su tenant y un body con los diez campos requeridos
- WHEN envía `POST /api/v1/publications/{publication_id}/revisions`
- THEN recibe `201` con una nueva revisión `borrador`, una versión mayor que las anteriores y una transición de creación auditada

#### Scenario: Reemplazar sin mutar la revisión anterior

- GIVEN una revisión borrador existente e inmutable de la misma publicación
- WHEN el agente envía un nuevo body completo con una nueva clave de idempotencia
- THEN se crea otra revisión `borrador`, la anterior conserva todos sus valores y ambas quedan en el historial

#### Scenario: Payload incompleto o inválido

- GIVEN un body que omite uno de los diez campos, agrega campos desconocidos o no cumple las validaciones del modelo
- WHEN se intenta crear el borrador
- THEN recibe `422` con código `validation_error` y no se crea revisión ni transición parcial

#### Scenario: Preservar publicación vigente

- GIVEN una publicación con revisión publicada de versión N
- WHEN se crea una revisión posterior en estado `borrador` o `en_revision`
- THEN la publicación pública continúa apuntando a la versión N hasta una publicación administrativa válida

### Requirement: Envío de una revisión a revisión (HU-023)

La API MUST exponer `POST /api/v1/publication-revisions/{revision_id}/submit` con body `{ "observation": "..." }`. Solo un agente autorizado por el authorizer existente MAY ejecutar este comando. La observación MUST ser no vacía después de quitar espacios.

El comando MUST permitir únicamente `borrador → en_revision`, registrar actor, rol, tenant, fecha y observación server-side, y responder `200` con la representación de la revisión actualizada. Una revisión en cualquier otro estado MUST responder `409` con código `invalid_revision_transition` sin mutación.

El comando MUST ser idempotente mediante `Idempotency-Key`: repetir la misma solicitud MUST devolver el resultado ya producido; no se crearán transiciones adicionales.

#### Scenario: Agente envía su borrador

- GIVEN un agente autorizado y una revisión `borrador` de su tenant
- WHEN envía una observación no vacía al endpoint de envío
- THEN recibe `200`, la revisión pasa a `en_revision` y se registra una transición auditada con autoridad server-side

#### Scenario: Agente intenta aprobar

- GIVEN una revisión `en_revision` creada por el mismo agente
- WHEN el agente invoca una operación de aprobación, publicación, rechazo o despublicación
- THEN recibe `403` con código `admin_required` y el estado e historial permanecen sin cambios

### Requirement: Aprobación, rechazo y publicación administrativa (HU-024/HU-025)

La API MUST exponer las siguientes rutas, todas con body `{ "observation": "..." }`:

- `POST /api/v1/publication-revisions/{revision_id}/approve`, que representa aprobación y publicación atómica;
- `POST /api/v1/publication-revisions/{revision_id}/reject`, que ejecuta `en_revision → rechazado`;
- `POST /api/v1/publications/{publication_id}/unpublish`, que despublica la revisión actualmente publicada.

Solo un administrador resuelto por el authorizer existente MAY ejecutar estas tres operaciones. La aprobación MUST equivaler al workflow existente `en_revision → publicado`; no habrá una transición pública intermedia `aprobada`. La aprobación MUST ser atómica: actualizar la revisión, la publicación vigente y las transiciones como una sola operación, y responder `200` con la revisión publicada. El rechazo MUST responder `200` con la revisión `rechazado`. La despublicación MUST responder `200` con la revisión `despublicado` y retirar inmediatamente la publicación de la proyección pública.

Toda observación MUST ser no vacía. Una solicitud que no corresponda al estado actual MUST responder `409` con código `invalid_revision_transition`; una solicitud repetida con la misma `Idempotency-Key` MUST devolver su resultado previo sin duplicar efectos. Un agente o administrador no autorizado MUST recibir `403` con código `admin_required` o `not_authorized`, sin mutación.

#### Scenario: Administrador aprueba y publica

- GIVEN una revisión `en_revision` y un administrador autorizado del tenant
- WHEN envía una observación a `POST /api/v1/publication-revisions/{revision_id}/approve`
- THEN recibe `200`, la revisión pasa a `publicado`, la publicación apunta a su versión y las transiciones quedan auditadas

#### Scenario: Administrador rechaza

- GIVEN una revisión `en_revision` y un administrador autorizado
- WHEN envía una observación no vacía a `POST /api/v1/publication-revisions/{revision_id}/reject`
- THEN recibe `200`, la revisión pasa a `rechazado` y la observación queda registrada

#### Scenario: Despublicar inmediatamente

- GIVEN una revisión `publicado` visible en el catálogo y un administrador autorizado
- WHEN invoca `POST /api/v1/publications/{publication_id}/unpublish` con observación
- THEN recibe `200`, la publicación queda `despublicado`, se audita la transición y una consulta posterior al catálogo ya no la incluye

#### Scenario: Observación ausente o vacía

- GIVEN una operación de transición sin observación o con una observación compuesta solo por espacios
- WHEN se invoca el endpoint
- THEN recibe `422` con código `validation_error` y no cambia estado ni historial

#### Scenario: Transición inválida

- GIVEN una revisión `rechazado`, `publicado` o `despublicado` para un comando que no admite su estado actual
- WHEN un administrador invoca el comando
- THEN recibe `409` con código `invalid_revision_transition`, sin alterar estado, versión publicada ni historial

### Requirement: Revisión, versionado y concurrencia

Las revisiones y transiciones MUST permanecer inmutables/append-only. Cada nueva revisión MUST recibir una versión única y monótona dentro de su publicación. La aprobación de una revisión nueva MUST reemplazar la revisión publicada anterior en una operación atómica, marcándola `despublicado` y preservando su contenido e historial. Una revisión en `borrador`, `en_revision` o `rechazado` MUST NOT alterar la versión publicada.

Las operaciones concurrentes que no puedan garantizar una transición única MUST responder `409` con código `concurrent_revision_conflict`; ningún error de concurrencia MUST dejar una transición o publicación parcialmente aplicada.

#### Scenario: Reemplazar una versión publicada

- GIVEN una publicación en versión N y una revisión posterior en `en_revision`
- WHEN un administrador la aprueba
- THEN la revisión nueva queda publicada, la anterior queda despublicada, `published_version` pasa a la nueva versión y el contenido anterior continúa disponible solo como historial

#### Scenario: Fallo atómico

- GIVEN un error al persistir una aprobación o despublicación
- WHEN termina la solicitud
- THEN no queda una combinación parcial de estados, versión publicada o transiciones

### Requirement: Guard de suscripción reutilizado

Cada comando mutador MUST consultar el seam existente de política de suscripción de HU-006 y MUST reutilizar su decisión, sin copiar ni redefinir estados en `publications`. Cuando la política indique que el tenant está bloqueado para la operación, la API MUST responder `409` con código `subscription_mutation_blocked` y no mutar el dominio. Esto incluye, como mínimo, los estados restrictivos observados `canceled_read_only`, `past_due` y `suspended` cuando el seam los reporte como bloqueantes.

Las consultas públicas del catálogo MUST conservar la política pública existente y no convertirse en una nueva historia de suscripción.

#### Scenario: Mutación bloqueada por suscripción

- GIVEN un tenant cuyo seam de HU-006 deniega el comando solicitado
- WHEN el actor invoca una operación mutadora
- THEN recibe `409` con `subscription_mutation_blocked`, sin crear revisión ni transición

#### Scenario: Mutación permitida por el seam

- GIVEN un tenant cuyo seam de HU-006 permite el comando
- WHEN un actor autorizado invoca una operación válida
- THEN el workflow continúa y no se aplica una regla paralela local

### Requirement: Dependencias de calidad y difusión

La aprobación/publicación MUST conservar seams explícitos para las comprobaciones externas de calidad de reconstrucción y difuminado/difusión documentadas por el dominio. La API MUST NOT aceptar afirmaciones del cliente como evidencia de esas comprobaciones ni inventar un proveedor o regla adicional. Si un seam disponible informa un bloqueo, la operación MUST responder `409` con código `quality_or_diffusion_blocked`; si informa que no puede evaluarse y la política del dominio exige evaluación, MUST responder `409` con código `quality_or_diffusion_unavailable`. En ambos casos no habrá mutación parcial.

Si no existe una integración verificable en el entorno de implementación, esta especificación no declara que las comprobaciones hayan sido ejecutadas; el diseño MUST dejar la dependencia identificada para resolución posterior, sin fabricar evidencia.

#### Scenario: Dependencia externa bloquea publicación

- GIVEN una revisión `en_revision`, un administrador y un seam que informa un defecto bloqueante de calidad o difusión
- WHEN se solicita aprobar/publicar
- THEN recibe `409` con `quality_or_diffusion_blocked` y la revisión permanece `en_revision`

#### Scenario: No se inventa evidencia

- GIVEN que no hay fuente verificable para evaluar una dependencia externa
- WHEN se diseña o implementa el endpoint
- THEN no se aceptan campos del cliente como prueba ni se afirma en documentación o pruebas que la calidad/difusión fue verificada

### Requirement: Errores y forma de respuesta

Todos los errores contractuales MUST usar un body JSON estable con `{ "code": string, "message": string, "details": object | null }`. La API MUST usar `400` solo para requests malformadas, `401` para autenticación ausente/inválida, `403` para autorización insuficiente, `404` para recursos no disponibles dentro del tenant, `409` para conflictos de workflow, suscripción, idempotencia o concurrencia, `412` para `If-Match` no satisfecho y `422` para validación semántica. Las respuestas de error MUST indicar el código estable y MUST NOT incluir secretos, autoridad interna ni datos de tenants ajenos.

#### Scenario: Consumidor recibe error procesable

- GIVEN una solicitud que falla por estado, permiso, validación o guard
- WHEN la API responde
- THEN el status HTTP y `code` identifican la clase de fallo de manera estable y no se produce una mutación parcial

### Requirement: Regresión del catálogo público

Las rutas públicas existentes `GET /api/v1/catalog/publications` y `GET /api/v1/catalog/publications/{publication_id}` MUST continuar sin aceptar `tenant_id` como autoridad. MUST mostrar únicamente revisiones con estado `publicado`, sus datos de contenido público y la versión publicada vigente. Las revisiones en borrador, en revisión, rechazadas o despublicadas, y el historial de auditoría, MUST permanecer fuera de la proyección pública.

#### Scenario: Catálogo excluye revisiones no publicadas

- GIVEN una publicación con revisiones en varios estados
- WHEN se consulta cualquiera de las rutas públicas del catálogo
- THEN solo se devuelve la revisión `publicado` vigente, si existe

#### Scenario: Catálogo tras despublicación

- GIVEN una publicación visible que un administrador acaba de despublicar
- WHEN se consulta el catálogo después de confirmar la operación
- THEN la publicación no aparece y no se expone su historial interno

## Exclusiones y evidencia

Este cambio no especifica HU-026 como nueva historia, el catálogo funcional adicional, HU-009 RBAC, panel React, apps Flutter, worker/Meshroom, S3/SQS, Solidity, pagos ni notificaciones generales. CP-009, CP-010, CP-011 y CP-012 permanecen `not executed`; las pruebas técnicas futuras no constituyen evidencia académica de esos casos. Tampoco se afirma la ejecución de migraciones reales ni la disponibilidad de calidad/difusión sin evidencia verificable.
