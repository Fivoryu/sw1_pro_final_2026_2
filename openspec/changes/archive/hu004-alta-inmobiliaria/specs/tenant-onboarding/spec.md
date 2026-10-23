# Especificación de Alta de Inmobiliaria

## Propósito

Definir el contrato observable del slice backend/API de HU-004 y CP-003 para confirmar una contratación simulada y aprovisionar una inmobiliaria únicamente ante un evento firmado válido. El panel visual, los pagos reales, HU-005, HU-006 y las membresías/RBAC completos no forman parte de esta especificación.

## Requisitos

### Requirement: Catálogo de planes mensuales aprobado

El sistema MUST exponer únicamente como planes contratables los tres planes activos aprobados, con datos propiedad del servidor:

| Plan | Monto mensual | Agentes | Almacenamiento | Inmuebles activos | Reconstrucciones mensuales |
| --- | ---: | ---: | ---: | ---: | ---: |
| Básico | 199 BOB | 5 | 50 GB | 5 | 10 |
| Profesional | 449 BOB | 15 | 200 GB | 20 | 40 |
| Empresarial | 899 BOB | 50 | 1.000 GB | 100 | 150 |

El contrato MUST incluir explícitamente la cuota de agentes y MUST representar el monto sin depender de aritmética binaria de punto flotante. La cuota de agentes MUST excluir al primer administrador.

#### Scenario: Consulta de planes aprobados

- GIVEN que el catálogo está disponible
- WHEN un consumidor consulta los planes contratables
- THEN recibe los tres planes con sus nombres, montos en BOB y cuotas exactas, incluida la cuota de agentes
- AND no recibe planes de HU-005 o HU-006 como parte de este flujo

#### Scenario: Plan inexistente o inactivo

- GIVEN que una solicitud referencia un plan inexistente o inactivo
- WHEN se intenta iniciar o confirmar el alta
- THEN la operación es rechazada de forma explícita
- AND no se crea ni modifica ningún recurso de onboarding

### Requirement: Checkout simulado separado del aprovisionamiento

El sistema MUST ofrecer una operación de checkout claramente simulada que acepte la selección de un plan activo y devuelva una referencia correlacionable, los datos del plan provenientes del servidor y un estado de confirmación. Confirmar el checkout MUST registrar únicamente la intención mínima necesaria y MUST NOT crear un tenant, una suscripción, una invitación ni un evento de aprovisionamiento.

#### Scenario: Confirmación de checkout válida

- GIVEN que se selecciona un plan activo
- WHEN el consumidor confirma el checkout simulado
- THEN recibe la referencia de operación, el identificador y nombre del plan, el monto mensual en BOB, sus cuotas y un estado de confirmación
- AND la referencia puede correlacionarse con un evento posterior
- AND no existe todavía un tenant aprovisionado por esta acción

#### Scenario: Datos de plan manipulados en el checkout

- GIVEN que la solicitud incluye un monto o una cuota distinta a la del catálogo del servidor
- WHEN se procesa el checkout
- THEN el sistema no toma esos datos como autoridad
- AND rechaza la solicitud o responde utilizando exclusivamente los datos vigentes del servidor
- AND no aprovisiona recursos

### Requirement: Evento firmado como frontera de confianza

El sistema MUST recibir el evento de aprovisionamiento mediante una operación independiente del checkout y MUST verificar su autenticidad e integridad antes de producir cualquier efecto de negocio. El evento MUST estar correlacionado con una referencia de checkout válida y con un plan activo; los identificadores, montos y cuotas enviados por el evento MUST validarse contra esa correlación y el catálogo del servidor.

#### Scenario: Evento válido y correlacionado

- GIVEN un checkout confirmado y un evento con firma válida, contenido íntegro y correlación compatible
- WHEN el sistema procesa el evento
- THEN habilita el aprovisionamiento del tenant, la suscripción inicial, el registro del evento y la activación pendiente del primer administrador
- AND la respuesta expone solo el identificador y estado de alta necesarios para el consumidor API

#### Scenario: Firma ausente, inválida o payload alterado

- GIVEN un evento sin firma válida, con firma inválida o cuyo contenido no coincide con la firma
- WHEN el sistema lo recibe
- THEN lo rechaza antes de modificar estado o persistir efectos de negocio
- AND no crea tenant, suscripción, invitación ni registro de aprovisionamiento
- AND no expone secretos ni material sensible de verificación

#### Scenario: Evento no correlacionado o inconsistente

- GIVEN un evento válido criptográficamente pero asociado a otro checkout, plan inexistente/inactivo o datos incompatibles
- WHEN el sistema lo procesa
- THEN lo rechaza explícitamente
- AND no crea efectos parciales de onboarding

### Requirement: Aprovisionamiento atómico del alta

Ante un evento aceptado, el sistema MUST crear como una unidad atómica el tenant de la inmobiliaria, su suscripción inicial al plan aprobado, el registro lógico del evento y una invitación pendiente del primer administrador. Si falla cualquier parte de la operación, el sistema MUST revertir el conjunto y MUST dejar observable un resultado de error sin recursos parciales.

#### Scenario: Alta completa

- GIVEN un evento firmado, íntegro y correlacionado que aún no fue procesado
- WHEN finaliza el aprovisionamiento
- THEN existe exactamente un tenant, una suscripción inicial, un registro lógico del evento y una invitación pendiente vinculada al tenant y al correo normalizado del primer administrador
- AND las cuotas de la suscripción corresponden al plan del servidor

#### Scenario: Falla durante el aprovisionamiento

- GIVEN que falla la creación o persistencia de cualquiera de los recursos iniciales
- WHEN se procesa el evento
- THEN la operación informa el fallo
- AND no quedan tenant, suscripción, invitación o registro de evento creados parcialmente

### Requirement: Idempotencia y conflicto de eventos

El sistema MUST aplicar una identidad única y persistente al evento o clave de idempotencia, asociada a una representación verificable del payload. Repetir la misma clave con el mismo payload MUST ser idempotente tanto secuencial como concurrentemente, devolviendo el resultado original o un estado equivalente sin duplicar recursos. Reutilizar la misma clave con un payload, checkout o plan diferente MUST producir un conflicto explícito y MUST NOT reutilizar silenciosamente el alta original.

#### Scenario: Reintento secuencial

- GIVEN un evento que ya completó el alta
- WHEN se procesa nuevamente con la misma clave y payload
- THEN el sistema devuelve el resultado original o un estado idempotente
- AND mantiene como máximo un tenant, una suscripción, una invitación y un registro lógico del evento

#### Scenario: Reintentos concurrentes

- GIVEN dos o más solicitudes concurrentes con la misma clave y payload
- WHEN se procesan
- THEN como máximo una solicitud produce los efectos de alta
- AND las demás reciben el resultado idempotente o una respuesta de procesamiento equivalente
- AND no se generan duplicados ni efectos parciales

#### Scenario: Misma clave con payload diferente

- GIVEN una clave ya utilizada
- WHEN llega un payload, checkout, plan o dato de alta diferente
- THEN el sistema responde con un conflicto explícito
- AND conserva el resultado previamente asociado a la clave
- AND no modifica ni duplica el onboarding existente

### Requirement: Activación mínima del primer administrador

El sistema MUST crear una activación pendiente vinculada al tenant y al correo normalizado del primer administrador, con expiración, estado pendiente y una representación hasheada del token. El token MUST ser de un solo uso; el sistema MUST NOT persistirlo en claro, devolverlo en respuestas API ni registrarlo en logs. La entrega podrá realizarse mediante un adaptador simulado o integrable, sin requerir un proveedor real de correo. HU-004 MUST NOT crear invitaciones de agentes, membresías generales ni RBAC.

#### Scenario: Emisión de activación

- GIVEN un aprovisionamiento exitoso
- WHEN se genera la activación del primer administrador
- THEN existe una invitación pendiente con correo normalizado, expiración y hash del token
- AND el adaptador controlado puede recibir el token crudo para simular su entrega
- AND las respuestas API y los logs no contienen el token crudo, contraseñas ni secretos

#### Scenario: Activación válida de un token pendiente

- GIVEN un token no consumido y aún vigente
- WHEN el primer administrador lo presenta para activar su acceso
- THEN el sistema acepta el token una sola vez y registra su consumo
- AND no persiste ni transmite una contraseña generada por el alta
- AND la relación de identidad global, membresía y rol queda limitada a la decisión posterior de HU-007

#### Scenario: Activación expirada o ya consumida

- GIVEN un token expirado o previamente consumido
- WHEN se intenta utilizar
- THEN el sistema lo rechaza
- AND no crea ni modifica una activación válida
- AND no revela el token almacenado ni información sensible adicional

### Requirement: Contrato backend consumible y límites de alcance

El sistema MUST documentar y exponer contratos de solicitud, respuesta y estados suficientes para que un consumidor Web consulte planes, confirme el checkout y observe el resultado del alta. La especificación MUST mantener separadas las operaciones de checkout y evento firmado y MUST NOT requerir una interfaz visual, navegación, copy de UI, aplicación Flutter, pago real, proveedor de correo real, HU-005, HU-006 o el sistema completo de membresías/RBAC.

#### Scenario: Consumo sin panel visual

- GIVEN un consumidor que utiliza únicamente el contrato API
- WHEN consulta planes, confirma checkout y consulta el resultado de un evento procesado
- THEN puede observar los datos y estados definidos sin depender de una pantalla implementada en este cambio
- AND no se altera el comportamiento funcional de HU-005 ni HU-006

## Dependencias y riesgos de diseño

- `GAP-004-API-001`: el diseño MUST cerrar antes de las tareas la ruta, headers, algoritmo, canonicalización y formato exacto de la firma; esta especificación exige la propiedad de firma válida, pero no inventa una elección criptográfica.
- `GAP-004-AUTH-001`: el diseño MUST definir la política de autenticación del checkout simulado y distinguir al iniciador del receptor del evento, sin usar un `tenant_id` enviado por el cliente como autorización.
- `GAP-004-DOM-001`: HU-004 se limita a tenant + invitación pendiente + correo normalizado; la creación o reutilización de `usuario_global`, membresía y rol persistente requiere diseño y alcance de HU-007.
- `GAP-004-NOTIF-001`: el diseño MUST definir el contrato del adaptador simulado de entrega sin introducir un proveedor real ni filtrar el token.
- `GAP-092`: la operatividad de migraciones y PostgreSQL deberá verificarse durante la fase de verificación.

El límite de 600 líneas modificadas es una restricción de implementación y no un requisito de comportamiento.

## Trazabilidad

- HU-004 / PB-004 y CP-003: checkout, evento firmado, idempotencia y activación del primer administrador.
- BR-B1: checkout simulado y frontera de evento firmado.
- BR-B2: activación de un solo uso sin contraseña.
- BR-B3 y decisión aprobada de planes: catálogo y cuotas.
- Gaps `GAP-004-*` y `GAP-092`: dependencias y riesgos explícitos.
