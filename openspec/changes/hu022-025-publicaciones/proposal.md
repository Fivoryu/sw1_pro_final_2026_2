# Propuesta: Contrato backend de publicaciones HU-022 a HU-025

- **Cambio:** `hu022-025-publicaciones`
- **Product Backlog:** PB-028, PB-029 y PB-030
- **Historias:** HU-022 — Crear y editar borrador; HU-023 — Enviar a revisión; HU-024 — Aprobar o rechazar; HU-025 — Publicar o despublicar
- **Casos de uso:** CU-024, CU-025 y CU-026
- **Slice:** backend y contrato HTTP consumible por Web
- **Estado:** propuesta
- **Idioma del artefacto:** español profesional y neutral

## Intento y problema

RoomForge ya contiene un workflow interno de revisiones de publicaciones y un catálogo público, pero no expone un contrato HTTP para que un cliente administrativo ejecute el flujo de HU-022 a HU-025. En consecuencia, la capacidad está registrada como implementada por superficie, pero no existe evidencia de un flujo Web/API completo y verificable.

La propuesta convierte el workflow existente en una superficie backend-first, sin adelantar la implementación de panel, aplicaciones móviles, reconstrucción 3D ni contratos de blockchain. El contrato debe permitir que el cliente de Web consuma operaciones de publicación sin convertirse en autoridad de identidad, rol, tenant, estado o versión.

La exploración confirmó que las revisiones son inmutables y que las transiciones son append-only. También confirmó que CP-009, CP-010, CP-011 y CP-012 permanecen `not executed`; ninguna prueba técnica de este cambio se presentará como evidencia académica de esos casos.

## Objetivos

1. Exponer un contrato HTTP verificable para crear o reemplazar un borrador, enviarlo a revisión, aprobarlo, rechazarlo, publicarlo y despublicarlo.
2. Mantener la arquitectura backend existente `router → service → repository` y reutilizar `PublicationRevisionWorkflow` como autoridad de las transiciones.
3. Aplicar autorización server-owned y aislamiento por tenant en cada operación mutadora, sin aceptar `tenant_id`, actor, rol o permisos enviados por el cliente.
4. Preservar el historial inmutable de revisiones y transiciones, incluida la revisión publicada mientras exista una revisión posterior en borrador o en revisión.
5. Reutilizar la política de suscripción de HU-006 mediante su seam existente, sin duplicar reglas ni crear una política paralela.
6. Definir una base de pruebas TDD para el contrato HTTP y sus invariantes, manteniendo separadas la verificación técnica y la ejecución académica de CP-009..CP-012.

## Decisiones de producto confirmadas

Estas decisiones provienen de la prepropuesta validada y son restricciones de esta propuesta:

- **Edición:** `revision-replacement`. Editar un borrador significa crear una nueva revisión borrador completa; las revisiones anteriores permanecen inmutables como historial.
- **Responsabilidad:** `admin-approval-publish`. El administrador aprueba o rechaza y también publica o despublica. El agente crea y envía a revisión, pero no puede autoaprobar ni ejecutar operaciones reservadas al administrador.
- **Autorización:** `existing-authorizer`. Se reutiliza únicamente el authorizer server-owned observado; no se incorpora el catálogo RBAC completo de HU-009.
- **Contenido:** `existing-model`. El contrato usa el conjunto completo de campos y validaciones que ya exige `PublicationRevision`. Las comprobaciones de difuminado y calidad de reconstrucción se tratan como dependencias externas verificables, no se inventan nuevas reglas de contenido.
- **Suscripción:** `reuse-hu006-policy`. Las mutaciones consultan y reutilizan la política de estados de suscripción de HU-006 mediante su seam existente.

## Alcance incluido

### Contrato HTTP

Se definirá una superficie tenant-scoped para operaciones administrativas de publicaciones. Los nombres finales de rutas, payloads y respuestas se fijarán en `spec` y `design`, pero la dirección contractual es:

- una operación de creación o reemplazo de revisión `borrador` con contenido comercial completo;
- una operación para enviar una revisión `borrador` a `en_revision`;
- una operación administrativa para aprobar y llevar la revisión al estado publicado conforme al workflow existente;
- una operación administrativa para rechazar una revisión, con observación obligatoria;
- una operación administrativa para publicar o despublicar según la separación que resulte necesaria para representar HU-024 y HU-025 sin contradecir el workflow;
- respuestas de éxito y errores estables para autenticación, autorización, tenant inexistente o ajeno, validación, transición inválida, guard de suscripción y conflicto de versión;
- validación de esquemas sin permitir que el cliente establezca identidad, rol, tenant, estado, actor, timestamps o versión.

La API administrativa no expondrá el historial de auditoría en el catálogo público. Las rutas públicas actuales de catálogo continuarán proyectando únicamente revisiones publicadas.

### Dominio, persistencia y servicios

- Reutilizar `Publication`, `PublicationRevision`, `PublicationRevisionTransition` y sus invariantes actuales.
- Completar los seams de router, schemas, servicio y repositorio que hagan falta para volver consumible el workflow; no rediseñar identidad, tenancy, sesiones ni suscripciones.
- Mantener los cinco estados de dominio observados: `borrador`, `en_revision`, `publicado`, `rechazado` y `despublicado`.
- Rechazar transiciones inválidas sin mutar el estado ni producir una transición parcial.
- Registrar actor, rol, tenant, fecha y observación en las transiciones según el mecanismo de auditoría existente; las observaciones requeridas no pueden ser vacías.
- Mantener versionado monótono por publicación y conservar la versión publicada hasta que una nueva revisión válida sea aprobada/publicada.
- Evaluar una migración únicamente si el contrato requiere una modificación de esquema respaldada por la especificación. La ejecución real de migraciones queda fuera de esta fase.

### Autorización y aislamiento

El authorizer server-owned será la única fuente de actor, rol y tenant. La carga de una publicación o revisión se hará dentro del tenant autorizado y no mediante un `tenant_id` confiado al cliente.

La matriz mínima a especificar es:

- agente autorizado del tenant propietario: crear o reemplazar borradores y enviar sus revisiones a `en_revision`;
- administrador autorizado: aprobar, rechazar, publicar y despublicar;
- agente: no puede autoaprobar su propia revisión ni ejecutar operaciones administrativas reservadas;
- actor autenticado de otro tenant o sin autorización: no obtiene acceso ni puede inferir la existencia del recurso.

La propuesta no define un RBAC nuevo; el detalle de permisos finos se limita al seam necesario para este workflow y queda trazado a HU-009 como alcance posterior.

### Guard de suscripción

Cada comando mutador reutilizará la política de suscripción de HU-006 mediante su seam existente. La especificación deberá documentar qué operaciones se permiten o bloquean en estados restrictivos —incluidos los estados observados `canceled_read_only`, `past_due` y `suspended`— y cuál es el error estable para un comando bloqueado.

No se copiarán condiciones de suscripción dentro del módulo de publicaciones ni se modificará la política de HU-006 en este cambio.

## Ciclo de vida y versionado

El contrato respetará el flujo observado:

```text
borrador → en_revision → publicado
                         ↘ despublicado
              ↘ rechazado
```

Las transiciones no válidas deben responder con un error contractual y dejar intactos estado, versión publicada e historial. La observación es obligatoria para cada transición que el workflow registre.

Con `revision-replacement`, una edición no actualiza una revisión existente: crea una revisión borrador completa con la siguiente versión y deja la revisión reemplazada como historial inmutable. No se permitirá editar directamente una revisión `en_revision`, `publicado`, `rechazado` o `despublicado`.

La aprobación y la publicación deberán quedar representadas de forma inequívoca en el contrato: el comportamiento de dominio observado es `en_revision → publicado` para la operación administrativa `publish`, mientras que HU-024 describe la aprobación aceptada como cambio a `publicado`. `spec` y `design` deberán elegir la representación HTTP que reconcilie ambas expresiones sin conceder la operación a agentes ni duplicar transiciones.

Si existe una revisión publicada y se crea una revisión posterior, la publicación vigente no se reemplaza hasta la aprobación/publicación válida de la nueva revisión, conforme a BR-C4. La despublicación elimina inmediatamente la publicación de la proyección pública y queda auditada.

## Fuera de alcance y no objetivos

- Implementación del panel React o de cualquier UI Web.
- Integración de `apps/cliente_mobile`, `apps/captura_mobile` o cualquier otra aplicación móvil.
- Worker 3D, Meshroom, S3, SQS o validaciones de procesamiento de medios.
- Contratos Solidity, escrow, pagos, tokens o blockchain.
- HU-026 como nueva historia, favoritos, reservas, acceso temporal o catálogo adicional; solo se conserva el catálogo público existente como superficie de regresión.
- Implementación del catálogo RBAC completo de HU-009 o rediseño de membresías/tenancy.
- Nuevos servicios de calidad, difuminado o reconstrucción 3D; solo se dejan como dependencias verificables cuando corresponda.
- Endpoint público de auditoría o exposición del historial interno de transiciones.
- Cambios no necesarios en identidad, sesiones o la política de suscripción de HU-006.
- Ejecución de CP-009..CP-012, ejecución de migraciones contra PostgreSQL real, `apply`, `verify`, commits o pushes durante esta planificación.
- Modificación de `docs/diagramas/Diagrama1.eapx`.

## Áreas afectadas e impacto

- **Backend `publications`:** routers, schemas, servicio, repositorio y pruebas del contrato.
- **Persistencia:** uso de las tablas y restricciones de revisiones/transiciones existentes; cualquier cambio adicional deberá justificarse en `design`.
- **Core de autorización:** integración con el authorizer existente, sin trasladar autoridad al cliente.
- **Suscripciones:** consumo del seam de HU-006, con impacto potencial en los errores de comandos mutadores bloqueados.
- **Catálogo público:** regresión para asegurar que solo se muestran revisiones `publicado` y que la despublicación es inmediata.
- **Consumidores futuros:** Web y otras superficies podrán integrar el contrato posteriormente, pero no forman parte de este slice.
- **Documentación y trazabilidad:** `spec`, `design`, `tasks` y la documentación del Sprint 1 deberán enlazar PB-028..PB-030, HU-022..HU-025, CU-024..CU-026 y CP-009..CP-012 sin cambiar su estado académico.

## Verificación y límites de evidencia

La implementación posterior seguirá TDD estricto: RED → GREEN → TRIANGULATE → REFACTOR. El plan técnico deberá cubrir, como mínimo:

1. validación de payload completo y reemplazo inmutable de borrador;
2. flujo válido de envío, aprobación/rechazo y publicación/despublicación;
3. observaciones obligatorias y auditoría server-side;
4. transiciones inválidas sin mutación;
5. prohibición de autoaprobación y autorización por rol;
6. aislamiento cross-tenant y ausencia de confianza en campos de autoridad enviados por el cliente;
7. bloqueo según la política de suscripción reutilizada;
8. versionado y conservación de la publicación anterior;
9. desaparición inmediata del catálogo al despublicar y regresión de sus endpoints públicos;
10. errores HTTP y semántica de conflictos que se acuerden en `spec`.

Las pruebas unitarias/API con dobles, `TestClient` y overrides de dependencias demostrarán invariantes técnicas. No demostrarán por sí solas la ejecución de los casos académicos. CP-009, CP-010, CP-011 y CP-012 seguirán figurando como `not executed` hasta contar con su evidencia correspondiente. Tampoco se afirmará que `0010_hu006_publication_revisions.py` fue aplicada en PostgreSQL: esa validación permanece pendiente bajo GAP-092.

## Riesgos y mitigaciones

- **Contrato HTTP ambiguo:** las historias agrupan aprobación y publicación de forma distinta al workflow interno. Mitigación: fijar en `spec` una semántica única, códigos, respuestas e idempotencia antes de `tasks`.
- **Responsabilidades por rol:** exponer accidentalmente una mutación administrativa a agentes permitiría autoaprobación o publicación indebida. Mitigación: authorizer server-owned, matriz de autorización explícita y pruebas cross-role.
- **Aislamiento multi-tenant:** confiar en un tenant enviado por el cliente podría revelar o mutar publicaciones ajenas. Mitigación: resolver siempre el tenant desde el authorizer y devolver un error no revelador para recursos ajenos.
- **Edición e inmutabilidad:** tratar editar como `UPDATE` rompería los triggers y la trazabilidad. Mitigación: aplicar reemplazo por nueva revisión completa y probar que la revisión anterior no cambia.
- **Pérdida de la publicación vigente:** publicar una nueva revisión demasiado pronto podría exponer contenido no aprobado. Mitigación: mantener la versión publicada hasta una transición administrativa válida y atómica.
- **Guards duplicados o inconsistentes:** una copia local de la política de HU-006 puede divergir. Mitigación: consumir el seam existente y cubrir sus resultados contractuales sin redefinir estados.
- **Dependencias de calidad no observadas:** difuminado y defectos de reconstrucción pueden no tener una fuente consultable. Mitigación: mantenerlos como dependencia explícita y no declarar verificaciones inexistentes.
- **Migración no ejecutada:** el esquema observado puede no estar aplicado en el entorno real. Mitigación: separar pruebas unitarias de la prueba de migración y registrar la ejecución como trabajo posterior.
- **Presupuesto de revisión:** backend, contrato, guards y pruebas pueden superar las 400 líneas cambiadas. Mitigación: medir el diff; ante riesgo de superar el presupuesto, detenerse y solicitar decisión de partición conforme a `ask-on-risk`, sin inferir una excepción.
- **Evidencia académica confundida con pruebas técnicas:** una suite nueva podría interpretarse como cierre de CP-009..CP-012. Mitigación: etiquetar y documentar por separado ambos tipos de evidencia.

## Rollback

Deshabilitar o retirar las rutas administrativas nuevas y conservar el catálogo público existente. Revertir únicamente los cambios del slice backend y sus dependencias contractuales; no borrar revisiones, transiciones, cuentas, tenants ni datos auditables de forma destructiva.

Si se hubiera agregado una migración y aún no contiene datos, el entorno descartable podrá volver atrás mediante Alembic. Si existen datos, se conservará el esquema y se preparará una migración controlada. El rollback no debe eliminar la revisión publicada ni romper la proyección pública vigente; cualquier operación parcialmente aplicada deberá resolverse transaccionalmente.

## Criterios de éxito

- Existe un contrato HTTP documentado y verificable para HU-022, HU-023, HU-024 y HU-025, con payloads, respuestas, errores y autorización definidos.
- Crear o editar mediante reemplazo conserva revisiones inmutables, genera versiones monótonas y no reemplaza la publicación vigente antes de una aprobación/publicación válida.
- Solo el agente autorizado puede crear/enviar en su tenant y solo el administrador autorizado puede aprobar, rechazar, publicar o despublicar; la autoaprobación y el acceso cross-tenant son rechazados.
- Todas las transiciones válidas quedan auditadas y las inválidas no mutan el dominio.
- La política de suscripción de HU-006 se reutiliza sin duplicación, y los bloqueos tienen errores estables especificados.
- El catálogo público continúa mostrando únicamente publicaciones publicadas y deja de mostrar una publicación inmediatamente después de su despublicación.
- Las pruebas TDD técnicas cubren los criterios anteriores y pasan cuando se ejecute la fase de implementación/verificación.
- CP-009..CP-012 continúan explícitamente como `not executed` hasta obtener evidencia académica independiente.

## Fuentes y trazabilidad

- Exploración del cambio: `openspec/changes/hu022-025-publicaciones/explore.md`.
- Decisiones confirmadas: `openspec/changes/hu022-025-publicaciones/preproposal.md`.
- Trazabilidad PB/RF/HU/CU: `docs/sprint-0/ids-trazabilidad.md`.
- Reglas, criterios y proceso por HU: `docs/scrum/sprint-1/01-sprint-planning.md` y `docs/scrum/sprint-1/02-proceso-por-hu.md`.
- Reglas de negocio y auditoría: `docs/sprint-0/auditoria-br.md`.
- Modelo y workflow observado: `backend/app/modules/publications/models.py` y `backend/app/modules/publications/service.py`.
- Rutas y schemas públicos observados: `backend/app/modules/publications/router.py` y `backend/app/modules/publications/schemas.py`.
- Persistencia y restricciones observadas: `backend/alembic/versions/0010_hu006_publication_revisions.py`.
- Pruebas técnicas existentes: `backend/tests/test_hu006_slice3_catalog.py`.
- Política de suscripción reutilizable: `openspec/specs/tenant-subscription/spec.md`.
- Deuda de evidencia y migraciones: `docs/avance/sprint-1.md` y GAP-092.

## Decisiones abiertas para `spec`/`design`

No quedan decisiones de producto pendientes de consentimiento para habilitar la siguiente fase. Deben precisarse técnicamente, sin ampliar el alcance:

- nombres definitivos de rutas, comandos, payloads y respuestas;
- códigos y forma de los errores, incluyendo recursos ajenos y guard de suscripción;
- representación HTTP de aprobación frente a publicación y sus reglas de idempotencia/concurrencia;
- fuente verificable y momento de evaluación de difuminado y calidad de reconstrucción;
- necesidad exacta de cambios de persistencia y estrategia de locking/transacción;
- límites de tamaño, campos obligatorios ya presentes en el modelo y reglas de versión.

## Key Learnings

- El activo reutilizable es el workflow interno de revisiones; la brecha principal es su contrato HTTP, no un rediseño de dominio.
- La inmutabilidad obliga a tratar la edición como reemplazo por nueva revisión, manteniendo el historial y la publicación vigente.
- La seguridad del slice depende de autoridad server-owned y aislamiento por tenant, no de campos de contexto enviados por el consumidor.
- La aprobación/publicación debe expresarse con precisión porque las historias y el servicio existente usan agrupaciones diferentes.
- La existencia de código y pruebas internas no cierra CP-009..CP-012 ni demuestra que las migraciones estén ejecutadas.
