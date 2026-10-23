# Especificación de invitación y aceptación de agentes — HU-007

## Propósito

Definir el primer slice de incorporación administrada de agentes para PB-007 / HU-007 / CU-007, cubriendo Web y Backend. La aceptación incorpora al usuario al tenant con membresía `pending`; no activa acceso ni asigna permisos. Los nombres de rutas HTTP, payloads y códigos concretos quedan para diseño cuando no estén respaldados por código vigente.

## Requisitos

### Requirement: Autorización administrativa derivada del contexto del tenant

El Backend MUST autorizar la creación de invitaciones únicamente cuando el principal autenticado por JWT corresponda a un administrador autorizado por la membresía server-side del tenant. El `tenant_id` efectivo MUST derivarse del JWT y de la resolución server-side del contexto; el contrato MUST ignorar o rechazar un `tenant_id` enviado en body, query string o headers como mecanismo de selección de autoridad.

#### Scenario: Administrador autorizado

- GIVEN un JWT válido y una membresía administrativa vigente
- WHEN el administrador solicita crear una invitación
- THEN el Backend usa el tenant resuelto desde el principal y procesa la operación

#### Scenario: Intento de seleccionar otro tenant

- GIVEN un administrador autenticado con un tenant resuelto
- WHEN la solicitud incluye un identificador de otro tenant para seleccionar autoridad
- THEN la solicitud es rechazada y no se crea ninguna invitación en el tenant indicado

#### Scenario: Principal no autorizado

- GIVEN un JWT ausente, inválido, expirado o sin membresía administrativa vigente
- WHEN se solicita crear una invitación
- THEN el Backend rechaza la operación sin revelar datos de otros tenants ni persistir cambios

### Requirement: Creación de invitación trazable

El Backend MUST permitir que un administrador autorizado emita una invitación para un agente, persistiendo el estado `pending`, la referencia del tenant, el correo normalizado, la fecha de emisión y la expiración. La operación MUST entregar al notificador el enlace necesario y una referencia no sensible al cliente, sin hacer recuperable el secreto desde la persistencia.

#### Scenario: Emisión válida

- GIVEN un administrador autorizado y un correo válido
- WHEN se crea la invitación
- THEN se persiste una invitación `pending`, se establece su vencimiento a siete días desde la emisión y se entrega el enlace al seam de notificación

#### Scenario: Solicitud inválida

- GIVEN una solicitud con correo ausente o inválido
- WHEN se intenta crear la invitación
- THEN la operación es rechazada sin persistir una invitación ni enviar un enlace

#### Scenario: Fallo de entrega

- GIVEN una invitación cuya transacción de emisión es válida
- WHEN el notificador falla
- THEN el fallo queda observable para reintento o diagnóstico y el secreto no se expone ni se obtiene desde la base de datos

### Requirement: Normalización consistente del correo

El sistema MUST aplicar trim y lowercase al correo antes de validarlo para unicidad, buscar `usuario_global`, comparar invitaciones o membresías y persistirlo. La misma dirección escrita con diferencias de espacios o mayúsculas MUST referir al mismo correo normalizado.

#### Scenario: Variaciones equivalentes

- GIVEN dos solicitudes con el mismo correo expresado con espacios o mayúsculas distintas
- WHEN se comparan o persisten
- THEN ambas usan un único valor normalizado para las búsquedas y restricciones de unicidad

### Requirement: Token seguro, hasheado, de un solo uso y con expiración

El Backend MUST generar el token con una fuente criptográficamente segura, persistir únicamente su hash SHA-256 y entregar el token en claro solo al notificador. El token en claro MUST NOT almacenarse, registrarse en logs ni incluirse en respuestas administrativas. Cada invitación MUST expirar siete días después de su emisión. Un token inválido, expirado, invalidado, reemplazado o ya consumido MUST ser rechazado.

#### Scenario: Inspección de persistencia y logs

- GIVEN una invitación emitida
- WHEN se inspeccionan sus registros, logs y respuesta administrativa
- THEN no aparece el token en claro y solo existe el material hash permitido para validarlo

#### Scenario: Token expirado

- GIVEN un token cuya fecha actual es posterior a siete días desde su emisión
- WHEN se intenta aceptar
- THEN se rechaza, la invitación se considera `expired` y no se crean ni modifican cuenta o membresía

#### Scenario: Token consumido una vez

- GIVEN una invitación aceptada previamente
- WHEN se reutiliza su token
- THEN se rechaza la operación y no se producen efectos adicionales

### Requirement: Reinvitación reemplaza el pendiente anterior

Si ya existe una invitación `pending` para el mismo tenant y correo normalizado, una nueva emisión MUST invalidar atómicamente el enlace anterior y crear su reemplazo. El enlace anterior MUST quedar inutilizable aunque no haya expirado, y MUST existir como máximo un flujo pendiente para la combinación tenant-correo.

#### Scenario: Reinvitación de una invitación pendiente

- GIVEN una invitación `pending` para un tenant y correo normalizado
- WHEN un administrador autorizado vuelve a invitar ese correo
- THEN la invitación anterior pasa a `invalidated`, se crea una nueva `pending` y solo el enlace nuevo puede aceptarse

#### Scenario: Carreras de reinvitación

- GIVEN dos solicitudes concurrentes de reinvitación para el mismo tenant y correo
- WHEN ambas intentan reemplazar la invitación pendiente
- THEN las restricciones y la transacción dejan un único pendiente utilizable, sin enlaces concurrentemente válidos ni duplicados

### Requirement: Reutilización de cuenta global sin reemplazo de credenciales

Al aceptar una invitación, si existe `usuario_global` para el correo normalizado, el sistema MUST reutilizar exactamente esa cuenta. La aceptación MUST NOT reemplazar, restablecer, modificar ni reenviar sus credenciales, estado de verificación o sesiones existentes.

#### Scenario: Usuario global existente

- GIVEN una invitación válida y una cuenta global cuyo correo coincide normalizadamente
- WHEN el destinatario acepta
- THEN se reutiliza el identificador global existente, se conservan sus credenciales y no se crea una segunda cuenta

### Requirement: Creación segura de contraseña para cuenta nueva

Si no existe `usuario_global`, la aceptación MUST requerir que el agente defina y confirme una contraseña válida. El sistema MUST persistir únicamente un hash Argon2id; la contraseña MUST NOT enviarse al administrador, almacenarse en claro ni incluirse en logs o respuestas.

#### Scenario: Cuenta nueva con contraseña válida

- GIVEN una invitación válida para un correo sin cuenta global
- WHEN el agente proporciona y confirma una contraseña válida
- THEN se crea una cuenta global con hash Argon2id y se continúa con la creación de la membresía pendiente

#### Scenario: Contraseña ausente o no coincidente

- GIVEN una invitación válida para una cuenta inexistente
- WHEN falta la contraseña, no coincide la confirmación o incumple la política vigente
- THEN se rechaza la aceptación sin crear cuenta, membresía ni consumir la invitación

### Requirement: Aceptación produce exactamente una membresía pendiente

La aceptación válida MUST crear exactamente una membresía para el usuario y tenant con estado `pending`, consumir la invitación y no crear una membresía `active`. La operación MUST NOT iniciar sesión automáticamente, otorgar acceso operativo, asignar permisos ni asociar inmuebles o publicaciones.

#### Scenario: Aceptación de usuario nuevo o existente

- GIVEN un token válido y utilizable
- WHEN el agente completa la aceptación con los datos requeridos
- THEN la cuenta nueva se crea o la existente se reutiliza, se crea exactamente una membresía `pending` y la invitación queda consumida

#### Scenario: No activación ni permisos

- GIVEN una aceptación completada
- WHEN se inspeccionan la membresía, la sesión y las autorizaciones del agente
- THEN la membresía no está `active`, no existe sesión iniciada por esta operación y no se asignan permisos

### Requirement: Membresías existentes se rechazan y se difieren a HU-008

El sistema MUST impedir una membresía duplicada para el mismo usuario y tenant. Si existe una membresía `active`, `inactive` o `revoked`, la invitación no MUST crear otra membresía ni reactivar o cambiar la existente; el resultado MUST comunicar un conflicto o equivalente de negocio y derivar la resolución a HU-008.

#### Scenario: Membresía activa, inactiva o revocada

- GIVEN una invitación válida cuyo usuario ya tiene en el tenant una membresía `active`, `inactive` o `revoked`
- WHEN se acepta o se intenta emitir una invitación incompatible
- THEN no se crea una membresía adicional ni se cambia el estado existente, y el caso queda diferido a HU-008

#### Scenario: Membresía pendiente existente

- GIVEN que ya existe la membresía `pending` correspondiente
- WHEN se intenta aceptar otra invitación para el mismo usuario y tenant
- THEN la operación no duplica la membresía y devuelve un resultado de conflicto o idempotencia definido en diseño

### Requirement: Aceptación atómica y segura ante concurrencia

La validación del token, la creación o reutilización de la cuenta, la creación de la membresía y el consumo de la invitación MUST ejecutarse como una única operación transaccional. El sistema MUST usar garantías persistentes suficientes para que aceptaciones concurrentes produzcan como máximo una cuenta nueva y una membresía para el tenant, sin efectos parciales.

#### Scenario: Dos aceptaciones concurrentes

- GIVEN dos solicitudes concurrentes con el mismo token utilizable
- WHEN ambas intentan completar la aceptación
- THEN solo una puede finalizar; la otra recibe rechazo idempotente o conflicto y no deja una cuenta, membresía o consumo adicional

#### Scenario: Falla durante la aceptación

- GIVEN una falla de persistencia en cualquier paso de la aceptación
- WHEN la transacción termina
- THEN se revierten conjuntamente la cuenta nueva, la membresía y el consumo de la invitación

### Requirement: Exclusión explícita de cuota, RBAC y ciclos de otras historias

HU-007 MUST NOT consultar ni aplicar `Plan.max_agents`, implementar RBAC o permisos, ni modificar el ciclo de suscripción de HU-006. HU-007 MUST NOT activar, desactivar, revocar o reactivar membresías; esas decisiones pertenecen a HU-008 y HU-009 según corresponda.

#### Scenario: Tenant sobre la cuota o sin política RBAC

- GIVEN un tenant cuyo plan tiene `max_agents` alcanzado, excedido o no definido
- WHEN se ejecuta una invitación o aceptación de HU-007
- THEN no se aplica una decisión de cuota por ese campo ni se alteran sus datos de HU-006

#### Scenario: Estado posterior a la aceptación

- GIVEN una aceptación válida
- WHEN termina el flujo de HU-007
- THEN no se activa, desactiva, revoca ni reactiva la membresía y no se asigna ningún permiso RBAC

### Requirement: Manejo de estados y errores en Web

La Web MUST representar de forma comprensible los estados `pending`, `accepted`, `invalidated` y `expired`, además de los resultados de enlace reemplazado, utilizado, membresía existente y error de red. La ruta pública de aceptación MUST solicitar contraseña y confirmación solo cuando corresponda a una cuenta nueva. La interfaz MUST ocultar tokens, secretos y detalles internos; los contratos HTTP y payloads concretos no fijados por código vigente MUST definirse en diseño.

#### Scenario: Gestión administrativa de invitaciones

- GIVEN un administrador autorizado que consulta la superficie de invitaciones
- WHEN una invitación cambia entre sus estados soportados o se solicita reinvitación
- THEN la Web muestra el estado y la acción disponible sin exponer el enlace secreto ni permitir seleccionar otro tenant

#### Scenario: Enlace no utilizable

- GIVEN un enlace expirado, reemplazado, ya utilizado o inválido
- WHEN el agente abre la ruta pública o intenta aceptar
- THEN la Web muestra un mensaje no sensible y no presenta la operación como activación exitosa

#### Scenario: Membresía existente

- GIVEN que el Backend informa un conflicto por membresía `active`, `inactive`, `revoked` o `pending`
- WHEN la Web recibe el resultado
- THEN muestra un conflicto accionable y no promete alta, reactivación ni permisos; la reactivación se deriva a HU-008

#### Scenario: Error de red

- GIVEN que la solicitud administrativa o pública no puede alcanzar el Backend
- WHEN la Web recibe el fallo de red
- THEN muestra un estado de error y opción de reintento sin duplicar silenciosamente la operación ni revelar secretos

### Requirement: Evidencia y trazabilidad de HU-007

La implementación MUST dejar pruebas preparadas para autorización, normalización, token, expiración, reinvitación, reutilización o creación de cuenta, membresía, duplicados, atomicidad, concurrencia y estados Web. La documentación MUST distinguir pruebas preparadas de evidencia ejecutada; CP-006 MUST NOT declararse ejecutado por este cambio.

#### Scenario: Reporte de evidencia

- GIVEN que se revisan los artefactos de HU-007 antes de ejecutar las pruebas
- WHEN se informa el estado de CP-006
- THEN se indica que queda preparado o pendiente, salvo que exista evidencia de ejecución independiente y verificable
