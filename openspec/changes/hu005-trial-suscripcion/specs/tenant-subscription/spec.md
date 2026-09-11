# Especificación de suscripción de tenant — HU-005

## Propósito y trazabilidad

Esta especificación define el slice backend/API de **PB-005**, **HU-005** y **CU-005** para Sprint 1, plataformas Web/Backend: un administrador de un tenant aprovisionado activa una prueba única de 14 días, consulta su proyección y convierte la suscripción mediante un evento mensual firmado. Su criterio de prueba asociado es **CP-004**, que permanece `not executed` hasta disponer de evidencia nueva. La especificación no declara pruebas, migraciones, revisión, commits ni pushes realizados.

El comportamiento reutiliza la identidad JWT de HU-002, el tenant, el plan contratado, la suscripción inicial `active`, la persistencia de eventos y la frontera HMAC de HU-004. RF-007 y las reglas de suscripción BR-B3/BR-B4 son la trazabilidad funcional; BR-A2 sustenta el aislamiento tenant. Los estados posteriores y la gestión completa pertenecen a HU-006.

## Requisitos

### Requirement: Asociación administrativa mínima y aislamiento tenant

El sistema MUST mantener una asociación mínima `tenant–administrador` para el principal JWT, con identificadores, estado activo/inactivo y timestamps necesarios para autorizar HU-005. MUST permitir activar e inspeccionar únicamente cuando la asociación esté activa y corresponda al tenant de la suscripción. MUST NOT usar un `tenant_id` del body, query o evento como fuente de autorización. MUST NOT crear un sistema general de membresías, RBAC o permisos.

La composición HTTP exacta del bootstrap de esta asociación queda diferida a diseño, pero el resultado MUST ser una asociación server-owned y trazable al administrador inicial de HU-004.

#### Scenario: Administrador activo autorizado

- GIVEN un JWT válido y una asociación administrativa activa para un tenant aprovisionado
- WHEN solicita activar o inspeccionar la suscripción
- THEN el sistema opera únicamente sobre la suscripción de ese tenant
- AND no requiere ni confía en un `tenant_id` aportado por el cliente

#### Scenario: Principal ausente, inválido, inactivo, no administrador o de otro tenant

- GIVEN una solicitud sin JWT válido, con asociación inexistente/inactiva, rol insuficiente o asociación para otro tenant
- WHEN solicita activar o inspeccionar una suscripción
- THEN el sistema rechaza la operación con un error sanitizado
- AND no revela si existe la suscripción, tenant o asociación consultada
- AND no cambia ninguna suscripción ni evento

### Requirement: Bootstrap acotado del administrador

El sistema MUST crear o reconocer como activa la asociación administrativa mínima solo mediante el bootstrap autorizado y server-owned definido para HU-005. MUST vincularla al administrador inicial de HU-004 sin aceptar contraseñas, tokens de activación crudos ni una membresía general como sustituto. La operación MUST ser idempotente para el mismo vínculo y MUST NOT crear asociaciones de agentes, invitaciones generales, roles catalogados ni permisos.

#### Scenario: Bootstrap válido repetido

- GIVEN un administrador inicial de HU-004 y un tenant válido sin asociación activa
- WHEN se ejecuta el bootstrap autorizado
- THEN se crea una única asociación activa
- AND repetir la operación devuelve el vínculo existente o un resultado equivalente sin duplicarlo

#### Scenario: Bootstrap sin vínculo server-owned

- GIVEN un principal que no corresponde al administrador inicial asociado por HU-004
- WHEN intenta crear una asociación para un tenant
- THEN el sistema rechaza la solicitud
- AND no usa el body `tenant_id` para conceder acceso

### Requirement: Activación única del trial

El sistema MUST exponer la operación de activación de prueba en la familia de tenant, actualmente `POST /api/v1/tenant/activar-prueba`, protegida por JWT y asociación administrativa activa. El request MUST carecer de autoridad tenant; campos extra o un `tenant_id` enviado no pueden seleccionar el tenant. La activación válida MUST aplicar solamente a la suscripción inicial `active` de HU-004, sin `trial_inicio` ni `trial_fin` previos.

Al activarse, MUST persistir `trial_inicio` igual al instante de activación y `trial_fin` igual a `trial_inicio + 14 × 24 horas` (336 horas), con timestamps conscientes de zona. MUST cambiar el estado a `trialing` en la misma transacción. La activación es de una sola vez: toda segunda activación es conflicto y no modifica fechas, estado ni eventos.

#### Scenario: Activación válida

- GIVEN un administrador activo, una suscripción inicial HU-004 en `active` y un reloj que devuelve `T`
- WHEN activa la prueba
- THEN la suscripción queda en `trialing`
- AND `trial_inicio = T`
- AND `trial_fin = T + 336 horas`
- AND la respuesta contiene el identificador, estado y ambas fechas

#### Scenario: Segunda activación

- GIVEN una suscripción con trial ya iniciado, incluso si ya alcanzó `trial_fin`
- WHEN se solicita otra activación
- THEN el sistema responde conflicto
- AND conserva estado, fechas y eventos exactamente sin cambios

#### Scenario: Estado inicial ausente o incompatible

- GIVEN un tenant sin suscripción o una suscripción que no es la inicial `active`, o que tiene datos de trial inconsistentes
- WHEN se solicita activar
- THEN el sistema rechaza la operación
- AND no crea fechas, eventos ni una nueva suscripción

#### Scenario: Activaciones concurrentes

- GIVEN dos solicitudes autorizadas concurrentes para la misma suscripción elegible
- WHEN ambas intentan activar el trial
- THEN como máximo una persiste `trialing` y sus fechas
- AND la otra recibe el resultado de conflicto sin sobrescribirlas

### Requirement: Expiración exacta y transición mínima

El sistema MUST considerar expirado el trial cuando `now >= trial_fin`. MUST rechazar una conversión nueva después de ese límite sin crear un estado persistente adicional. MUST aceptar únicamente la transición `trialing → active` para conversión mensual. No MUST convertir directamente la suscripción inicial HU-004 `active`, ni implementar aquí `past_due`, `suspended`, `canceled_read_only`, `purged`, gracia o renovación.

#### Scenario: Límite exacto

- GIVEN una suscripción `trialing` cuyo `trial_fin` es `T`
- WHEN una conversión nueva se procesa con `now = T`
- THEN se rechaza por trial expirado
- AND no cambia la suscripción ni registra un evento procesado

#### Scenario: Conversión desde el estado incorrecto

- GIVEN una suscripción inicial `active`, una suscripción ya convertida `active` o cualquier estado no soportado
- WHEN llega una clave mensual nueva
- THEN se rechaza como conflicto de estado
- AND no cambia el plan, fechas, estado ni eventos

### Requirement: Proyección e inspección de suscripción

El sistema MUST exponer una consulta protegida por JWT y asociación administrativa activa, actualmente `GET /api/v1/tenant/suscripcion`, derivando el tenant del principal. La respuesta MUST incluir solo la proyección necesaria: `subscription_id` (o el identificador contratado), `plan_id`, `estado`, `trial_inicio`, `trial_fin`, `periodo_inicio` y `periodo_fin`, con valores nulos cuando aún no correspondan. MUST preservar el `plan_id` contratado por HU-004.

La respuesta MUST NOT incluir payload de evento, monto firmado recibido, firma, secreto, JWT, password, token, hashes de tokens, datos completos del administrador ni datos de otro tenant. La ausencia o falta de autorización MUST tener un resultado que no permita enumerar suscripciones.

#### Scenario: Consulta autorizada

- GIVEN un administrador activo de un tenant con suscripción
- WHEN consulta la suscripción
- THEN recibe únicamente la proyección de su tenant, su plan, estado y fechas
- AND no recibe el evento ni datos sensibles

#### Scenario: Consulta no autorizada o tenant inexistente

- GIVEN un principal no autorizado o una asociación que no conduce a una suscripción accesible
- WHEN consulta
- THEN recibe un error sanitizado indistinguible respecto de la existencia de otro tenant

### Requirement: Evento mensual firmado y autenticado

El sistema MUST procesar la conversión mediante la frontera compartida de HU-004, actualmente `POST /api/v1/tenant/webhook`, usando el mismo contrato HMAC versionado, headers, secreto, tolerancia y verificación sobre `ASCII(timestamp) + b"." + raw_body`. MUST leer y verificar los bytes recibidos sin reserializar JSON, mediante comparación constante. MUST autenticar antes de buscar idempotencia, checkout, suscripción o cualquier dato de negocio.

El evento MUST tener un tipo mensual distinto del onboarding de HU-004 (el token propuesto es `subscription.monthly.succeeded`, sujeto a confirmación técnica), una correlación estable de suscripción/operación, `plan_id`, monto del simulador e `idempotency_key`. Los nombres exactos de campos y el token final quedan diferidos a diseño, sin alterar estas propiedades. MUST rechazar campos de autoridad como `tenant_id` si pretenden seleccionar el tenant.

#### Scenario: Evento autenticado con body íntegro

- GIVEN headers HMAC válidos, raw body exacto, timestamp dentro de la tolerancia y un evento mensual bien formado
- WHEN se recibe el webhook
- THEN continúa la validación de negocio
- AND ninguna búsqueda de idempotencia o correlación ocurre antes de autenticar

#### Scenario: Firma ausente, alterada, malformada o timestamp inválido

- GIVEN un webhook con firma/header ausente, body alterado, formato inválido o timestamp fuera de tolerancia para una clave nueva
- WHEN se recibe
- THEN responde como no autorizado
- AND no consulta ni persiste datos de negocio
- AND no expone qué parte de la autenticación falló

### Requirement: Correlación server-owned y conversión mensual

Después de autenticar el evento, el sistema MUST resolver la suscripción, tenant y plan desde PostgreSQL y MUST validar la correlación, el tipo mensual, el estado `trialing`, la vigencia del trial, el `plan_id` contratado y el monto del plan server-owned. El evento MUST NOT cambiar el `plan_id`, cuotas, precio o tenant. Un plan inexistente/inactivo, monto discordante, correlación incorrecta o suscripción incompatible MUST rechazarse sin mutación.

Al aceptar la conversión, MUST fijar el estado a `active`, `periodo_inicio` al instante de conversión y calcular `periodo_fin` como la misma fecha calendario local del mes siguiente en `America/La_Paz`, ajustada al último día si esa fecha no existe. MUST persistir los instantes resultantes como timestamps conscientes de zona. No se crea un proveedor de cobro real.

#### Scenario: Conversión válida

- GIVEN un evento mensual autenticado, correlacionado y una suscripción `trialing` vigente
- WHEN se procesa
- THEN la suscripción pasa a `active`
- AND conserva el `plan_id` de HU-004
- AND persiste inicio y fin del período según `America/La_Paz`
- AND persiste el evento asociado

#### Scenario: Datos server-owned incompatibles

- GIVEN un evento autenticado cuyo plan, monto, correlación o tipo no coincide con el servidor
- WHEN se procesa
- THEN responde conflicto o validación según corresponda
- AND no cambia suscripción, plan, fechas ni evento

#### Scenario: Fin de mes y año bisiesto

- GIVEN una conversión cuyo día local no existe en el mes siguiente, incluyendo 31→mes corto o febrero bisiesto/no bisiesto
- WHEN se calcula el período
- THEN `periodo_fin` usa el último día del mes siguiente en `America/La_Paz`
- AND la fecha almacenada representa ese instante sin usar una duración fija de 30 días

### Requirement: Idempotencia, replay y unicidad

El sistema MUST imponer unicidad persistente de `idempotency_key` y conservar una huella verificable de los bytes recibidos. Una repetición autenticada exacta MUST devolver HTTP `200` con HTTP/resultado original, aun fuera de la ventana de timestamp aplicable a eventos nuevos. La misma clave con bytes, datos o correlación diferente MUST devolver HTTP `409` y conservar el primer resultado. Un evento de HU-004 heredado sin la huella necesaria MUST NOT presumirse como replay mensual exacto.

La autoridad final de unicidad y recuperación MUST ser PostgreSQL bajo concurrencia; no es suficiente un check-then-insert aislado. Una clave diferente después de la conversión MUST ser conflicto de estado y no una segunda conversión.

#### Scenario: Replay exacto secuencial

- GIVEN una conversión mensual ya confirmada
- WHEN llega el mismo evento autenticado con la misma clave y bytes
- THEN responde `200` con los identificadores, estado y resultado originalmente persistidos
- AND no cambia fechas ni crea otro evento

#### Scenario: Replay exacto concurrente

- GIVEN solicitudes concurrentes con la misma clave y bytes
- WHEN se procesan
- THEN como máximo una conversión y un evento quedan persistidos
- AND las demás recuperan el resultado original o un resultado idempotente equivalente

#### Scenario: Misma clave con datos distintos

- GIVEN una clave ya persistida y un body diferente
- WHEN llega un webhook autenticado
- THEN responde `409`
- AND conserva íntegramente la conversión y evento originales

### Requirement: Atomicidad y rollback

La actualización de suscripción y la persistencia del evento mensual MUST pertenecer a una única transacción. La operación MUST bloquear o serializar la suscripción y hacer que la restricción única sea efectiva bajo concurrencia. Si falla cualquier escritura, MUST revertir conjuntamente estado, fechas y evento; no debe quedar una suscripción `active` sin evento ni un evento procesado sin conversión.

#### Scenario: Falla de persistencia

- GIVEN una conversión válida y un fallo en cualquier escritura posterior a la validación
- WHEN termina la transacción
- THEN no queda ningún cambio de suscripción ni evento mensual parcial
- AND un reintento válido puede procesarse según la semántica de idempotencia

### Requirement: Persistencia aditiva y compatibilidad

La migración MUST agregar solo los datos necesarios para HU-005, incluyendo como mínimo el inicio del trial, el inicio del período y la asociación administrativa, además de cualquier correlación/huella que HU-004 aún no provea. MUST conservar `trial_fin`, `periodo_fin`, la tabla de eventos y las relaciones existentes. La forma exacta de columnas, índices, revisión Alembic y tratamiento de filas legacy queda diferida a diseño.

MUST preservar las filas HU-004 con suscripción inicial `active` y fechas de trial nulas; no puede crear trials sintéticos, cambiar planes ni reinterpretar esas filas como conversiones mensuales. Las restricciones de estados MUST seguir siendo compatibles con el catálogo futuro de HU-006. Un rollback contra datos reales que contengan asociaciones, trials, períodos o eventos HU-005 MUST ser no destructivo; debe preferirse un forward-fix. Un downgrade destructivo solo MAY verificarse en una base descartable y controlada.

#### Scenario: Upgrade con datos HU-004

- GIVEN una base con tenants, planes y suscripciones iniciales `active` de HU-004
- WHEN se aplica la migración HU-005
- THEN los datos existentes permanecen intactos
- AND las nuevas columnas son compatibles con sus valores legacy
- AND no se crea un trial ni se modifica un plan

#### Scenario: Rollback con datos reales HU-005

- GIVEN una base que contiene asociaciones, fechas o eventos HU-005
- WHEN se solicita un downgrade
- THEN la operación destructiva se bloquea o se rechaza
- AND no elimina tenants, suscripciones ni eventos comprometidos

### Requirement: Seguridad, privacidad y no divulgación

El sistema MUST aplicar aislamiento multi-tenant en toda consulta de activación e inspección y MUST autenticar eventos antes de lookup. MUST responder errores sanitizados que no permitan enumerar tenants, usuarios, suscripciones, claves o eventos. MUST NOT devolver ni registrar raw bodies, firmas completas, secretos HMAC, JWTs, passwords, tokens, hashes de tokens, hashes de payload completos cuando sean sensibles, correos completos ni datos de tenants no autorizados. Los logs MAY incluir ruta, código estable, tipo de evento y un identificador irreversiblemente abreviado.

#### Scenario: Auditoría de respuesta y logs

- GIVEN una activación, consulta, fallo HMAC, replay o conflicto
- WHEN se genera la respuesta y el registro técnico
- THEN ninguno contiene los valores sensibles prohibidos
- AND los datos de otro tenant no aparecen en respuesta, error ni log

### Requirement: Alcance explícito de HU-005

HU-005 MUST limitarse a API/backend, contrato consumible por Web, asociación administrativa mínima, trial, inspección, evento mensual firmado, proyección de suscripción, idempotencia, persistencia aditiva y evidencia CP-004. MUST NOT incluir UI React/Flutter, pagos o billing reales, nuevos planes/precios/cuotas, enforcement de cuotas, cambios de plan, ciclo completo `past_due`/grace/suspended/cancel/purge, RBAC o memberships generales, notificaciones, consultas públicas de eventos, refactors no relacionados, commits o pushes.

#### Scenario: Consumidor Web sin UI incluida

- GIVEN un consumidor que usa únicamente el contrato API
- WHEN activa, inspecciona y convierte una suscripción
- THEN puede consumir los estados y fechas definidos
- AND no requiere que este cambio implemente una pantalla, navegación o copy
- AND no se agregan proveedores de notificación ni billing real

## Aceptación y evidencia CP-004

| Criterio / paso | Evidencia requerida | Estado actual |
| --- | --- | --- |
| CP-004.1 Activación | JWT + asociación activa; no autoridad de body; `trialing`; `trial_inicio`; diferencia exacta de 336 horas; respuesta con fechas | `not executed` |
| CP-004.2 Conversión | HMAC HU-004 sobre raw bytes; solo `trialing → active`; plan conservado; período calendarizado en `America/La_Paz` | `not executed` |
| CP-004.3 Replay | Replay exacto `200` con resultado original; mismo key/datos distintos `409`; sin duplicados | `not executed` |
| Seguridad | Casos missing/invalid/inactive/wrong-tenant/non-admin, no existencia leaks, autenticación antes de lookup y no divulgación | `not executed` |
| Concurrencia y atomicidad | PostgreSQL real para locks, unicidad, rollback y recuperación concurrente | `not executed` |
| Migración | Upgrade desde HU-004, preservación de legacy y downgrade seguro solo en base descartable | `not executed` |

Los tests con fake clock, repositorios fake o dobles de firma son evidencia determinística útil, pero **no sustituyen** la evidencia PostgreSQL de migraciones, locks, constraints, concurrencia y rollback. CP-004 solo podrá cambiar de `not executed` cuando exista evidencia verificable de los pasos y gates correspondientes.

## Decisiones diferidas a diseño

Diseño MUST cerrar, sin reabrir decisiones de producto:

- composición y nombre exactos del endpoint de bootstrap de `tenant_administrator`;
- nombres exactos de campos del evento mensual y token final de su tipo, manteniendo su distinción de HU-004;
- revisión Alembic, columnas/índices exactos, estrategia de compatibilidad de filas legacy y restricciones compatibles con HU-006;
- forma concreta de implementar locks, recuperación de la carrera de unicidad y representación interna/serialización de timestamps.

Estas decisiones técnicas no autorizan ampliar alcance, cambiar la duración del trial, permitir conversión desde el `active` inicial, cambiar el plan, alterar la frontera HMAC, introducir notificaciones o superar el presupuesto estricto de **400 líneas modificadas** para implementación.

## Fuentes

- `openspec/changes/hu005-trial-suscripcion/proposal.md` y `explore.md`.
- `docs/scrum/sprint-1/01-sprint-planning.md` y `02-proceso-por-hu.md`.
- `docs/sprint-0-requerimientos/04-requerimientos-iniciales.md`, `07-casos-de-uso.md`, `10-patron-de-desarrollo.md`, `11-modelos-iniciales.md` e `ids-trazabilidad.md`.
- `docs/sprint-0/auditoria-br.md` (BR-A2, BR-B1–BR-B9; ruta localizada por la exploración).
- `openspec/changes/hu004-alta-inmobiliaria/{explore,proposal,specs/tenant-onboarding/spec,design,tasks}.md`.
- Contratos actuales: `backend/app/modules/tenant/{models,schemas,router,service,repository}.py`.
- `openspec/project-context.md` y `openspec/config.yaml`.
