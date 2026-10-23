# Especificación: Integración pública de HU-003

## Propósito

Definir el comportamiento observable del flujo público de verificación de correo de RoomForge, desde el registro o la solicitud de activación hasta el consumo de un enlace y el login posterior. El alcance mantiene la trazabilidad `PB-003 → HU-003 → CU-003 → RF-033 → RNF-017 → Sprint 3` y se divide en dos slices independientes de aproximadamente 300 líneas modificadas cada uno, con un máximo agregado de 600.

Esta especificación define qué debe ocurrir. La estructura interna de servicios, repositorios, tablas, dependencias, wiring y estrategia concreta de despliegue queda para diseño, salvo las invariantes observables aquí indicadas.

No constituye evidencia de implementación, pruebas, disponibilidad de Mailpit, Flutter, web, Docker ni cumplimiento de Sprint 3.

## Decisiones y compatibilidad de contrato

- Las rutas públicas nuevas usan segmentos en inglés.
- La ruta viva de registro es `POST /api/v1/auth/register`; no se cambia nuevamente.
- Los nombres de campos JSON existentes se conservan en español. No se aprueba agregar, renombrar ni eliminar campos de registro en esta fase. La respuesta de registro conserva exactamente su forma vigente; la orientación al usuario puede resolverse en la superficie cliente sin alterar ese contrato.
- Las menciones antiguas a `POST /api/v1/auth/registro` en evidencia archivada son históricas, no representan el contrato vivo y no deben reescribirse.
- La activación válida verifica el correo, pero nunca crea una sesión automáticamente.
- Una cuenta no verificada no puede crear una sesión mediante login.
- La respuesta pública no revela existencia de cuentas, estados internos de tokens, límites ni fallos del proveedor.
- En el consumo, una solicitud estructuralmente inválida (cuerpo ausente, campo `token` faltante o tipo incompatible) responde `422`; un valor de `token` presente pero no utilizable responde `410` con el tratamiento genérico del enlace no disponible.

## Requisitos

### Requirement: Registro pendiente e integración de notificación

El sistema MUST crear una cuenta válida con `correo_verificado = false` y MUST mantenerla en estado pendiente de verificación. MUST iniciar una solicitud de activación asociada al correo normalizado, sin enviar la contraseña ni exponer el token. La respuesta HTTP de registro MUST conservar exactamente el contrato vigente, incluidos sus campos JSON en español, y MUST responder `201` cuando la cuenta se crea correctamente, sin informar el resultado interno del notificador.

#### Scenario: Registro válido

- GIVEN datos de registro válidos y un correo normalizado
- WHEN el cliente invoca `POST /api/v1/auth/register`
- THEN la cuenta se crea con `correo_verificado` igual a `false`
- AND la respuesta es `201` con la forma vigente de registro
- AND la cuenta queda apta para completar activación
- AND se inicia la solicitud inicial de activación
- AND la respuesta no contiene token crudo ni contraseña

#### Scenario: Fallo del notificador después de crear la cuenta

- GIVEN que la cuenta fue creada correctamente y el notificador falla después de la confirmación de persistencia
- WHEN finaliza el registro
- THEN la cuenta permanece no verificada
- AND la respuesta pública conserva el resultado genérico de registro pendiente y el código `201`
- AND la respuesta no identifica Mailpit, SMTP, la causa del fallo ni el estado de entrega
- AND el cliente puede usar posteriormente la solicitud o el reenvío genérico sujeto a límites

#### Scenario: Registro duplicado o inválido

- GIVEN un correo ya registrado o datos que no cumplen la validación vigente
- WHEN se invoca el registro
- THEN se conservan los códigos y cuerpos vigentes de conflicto o validación
- AND ningún error contiene contraseña, token, hash ni secreto
- AND no se crea una sesión por el registro

### Requirement: Login condicionado por verificación

El sistema MUST validar las credenciales y el estado de la cuenta antes de crear una sesión. MUST impedir la creación de access token, refresh token o sesión cuando las credenciales son válidas pero `correo_verificado` es `false`. Las cuentas verificadas MUST conservar el contrato exitoso vigente de login. Los intentos con credenciales inválidas MUST no disparar un envío automático.

#### Scenario: Login bloqueado para cuenta no verificada

- GIVEN una cuenta activa con credenciales válidas y `correo_verificado = false`
- WHEN el cliente invoca `POST /api/v1/auth/login`
- THEN no se crea sesión ni se emiten tokens de sesión
- AND la respuesta es el error público genérico vigente de credenciales, con código `401`
- AND el sistema puede intentar un reenvío automático únicamente después de validar las credenciales y si la política lo permite
- AND la respuesta no confirma que la cuenta exista o esté pendiente

#### Scenario: Login permitido para cuenta verificada

- GIVEN una cuenta activa con credenciales válidas y `correo_verificado = true`
- WHEN el cliente invoca `POST /api/v1/auth/login`
- THEN responde `200` con el `TokenResponse` vigente
- AND se crea la sesión conforme al contrato existente
- AND no se exige un envío adicional de activación

#### Scenario: Credenciales inválidas

- GIVEN un correo inexistente, una contraseña incorrecta o una cuenta que no supera la validación vigente
- WHEN se invoca el login
- THEN responde con el error genérico vigente y código `401`
- AND no se crea sesión ni se emiten tokens de sesión
- AND no se dispara reenvío automático
- AND la respuesta no permite distinguir la causa interna

#### Scenario: Reenvío automático acotado

- GIVEN credenciales válidas para una cuenta activa no verificada
- WHEN el sistema evalúa el reenvío automático del login
- THEN solo emite y entrega un nuevo enlace si no existe cooldown ni límite agotado
- AND la operación comparte el mismo cooldown, ventana y contador de las solicitudes explícitas
- AND si no puede reenviar, el login conserva el mismo error `401` genérico
- AND nunca se crea sesión antes de la verificación

### Requirement: Contrato público de solicitud y reenvío

El backend MUST exponer las operaciones siguientes bajo `/api/v1/auth`:

| Operación | Método y ruta | Cuerpo válido | Respuesta pública |
| --- | --- | --- | --- |
| Solicitud | `POST /api/v1/auth/email-verification/request` | `{ "correo": "usuario@example.com" }` | `202` y cuerpo genérico constante |
| Reenvío | `POST /api/v1/auth/email-verification/resend` | `{ "correo": "usuario@example.com" }` | `202` y exactamente el mismo cuerpo que solicitud |
| Consumo | `POST /api/v1/auth/email-verification/consume` | `{ "token": "valor-del-enlace" }` | `200` en éxito o `410` si no es utilizable |

Los cuerpos de solicitud y reenvío MUST aceptar el formato de correo vigente y normalizarlo como el registro. La respuesta `202` MUST ser la misma para correo inexistente, existente no verificado, existente verificado, cooldown, límite agotado, entrega aceptada y fallo del notificador. El cuerpo no debe contener correo, ID, token, hash, contador, `retry_after` ni causa interna. El texto exacto del mensaje genérico y los nombres adicionales, si fueran necesarios por compatibilidad, deben quedar fijados por diseño sin cambiar esta semántica.

#### Scenario: Solicitud con cualquier estado de cuenta

- GIVEN una petición estructuralmente válida con un correo inexistente, pendiente, verificado o limitado
- WHEN se invoca `POST /api/v1/auth/email-verification/request`
- THEN responde `202`
- AND el cuerpo tiene la misma forma y contenido público para todos los casos
- AND no confirma si se generó, omitió o entregó un mensaje

#### Scenario: Reenvío por cualquier superficie

- GIVEN una petición estructuralmente válida desde Flutter, web o un cliente HTTP
- WHEN se invoca `POST /api/v1/auth/email-verification/resend`
- THEN aplica la misma política y contador que la solicitud y el reenvío automático
- AND responde `202` con exactamente la misma respuesta genérica
- AND cambiar de endpoint o superficie no permite evadir los límites

#### Scenario: Petición mal formada

- GIVEN un cuerpo ausente, un campo requerido ausente o un valor de tipo/formato inválido
- WHEN se invoca solicitud o reenvío
- THEN responde `422` conforme al formato de validación vigente
- AND no revela existencia de la cuenta
- AND no incluye el valor sensible completo ni credenciales

### Requirement: Contrato de consumo de activación

El endpoint `POST /api/v1/auth/email-verification/consume` MUST recibir el token del enlace únicamente en el campo `token`. Ante un token válido, MUST responder `200` con una confirmación en español, cambiar la cuenta a verificada de forma efectiva y no crear sesión. Ante un valor de `token` presente pero alterado, inválido, expirado, invalidado, consumido o no asociado, MUST responder `410` con una forma y semántica públicas indistinguibles. Ante un cuerpo ausente, un campo `token` faltante o un tipo de token incompatible, MUST responder `422` sin reflejar el valor recibido.

#### Scenario: Consumo válido

- GIVEN un token activo, vigente y asociado a una cuenta no verificada
- WHEN se invoca el endpoint de consumo
- THEN responde `200` con confirmación de correo verificado y orientación al login
- AND la cuenta queda con `correo_verificado = true`
- AND el token deja de estar utilizable
- AND no se crea sesión ni se devuelve access token o refresh token

#### Scenario: Token presente pero no utilizable

- GIVEN un valor de `token` presente, pero alterado, inválido, expirado, invalidado, consumido o asociado a un contexto inexistente
- WHEN se invoca el endpoint de consumo
- THEN responde `410` con el mismo tratamiento público genérico
- AND no cambia ninguna cuenta
- AND no revela cuál condición interna ocurrió ni refleja el valor del token

#### Scenario: Cuerpo estructuralmente inválido

- GIVEN un cuerpo ausente, sin el campo `token` o con un tipo de token incompatible
- WHEN se invoca el consumo
- THEN responde `422`
- AND no devuelve el token, su hash ni detalles de validación interna

### Requirement: Token de un solo uso y límites temporales

El sistema MUST generar tokens aleatorios no predecibles y MUST persistir únicamente una representación derivada no reversible para validarlos. El token crudo MUST existir solo durante la construcción y uso del mensaje o URI. Cada cuenta MUST tener como máximo un token activo. El TTL MUST ser de 7 días desde la emisión. La emisión de un nuevo token permitido MUST invalidar el anterior antes de que el nuevo sea utilizable.

El primer envío de una cuenta nueva no cuenta como reenvío, pero inicia el cooldown y la ventana diaria. Los reenvíos automáticos, explícitos y originados por solicitud MUST compartir un cooldown de 15 minutos y un máximo de 3 reenvíos dentro de una ventana de 24 horas. El contador no puede reiniciarse cambiando de ruta o cliente.

#### Scenario: Emisión segura

- GIVEN una solicitud de activación permitida
- WHEN se emite el enlace
- THEN el valor crudo no se persiste ni se devuelve en la respuesta HTTP
- AND solo la representación derivada permite validarlo
- AND el token expira siete días después de su emisión
- AND existe como máximo un token activo para la cuenta

#### Scenario: Invalidación al reemitir

- GIVEN una cuenta con un token activo y sin cooldown ni límite agotado
- WHEN se autoriza un reenvío
- THEN el token anterior queda invalidado
- AND el nuevo token es el único token activo utilizable
- AND el reenvío incrementa el contador común

#### Scenario: Cooldown y límite diario

- GIVEN que transcurrieron menos de 15 minutos desde el último envío contado
- WHEN se solicita otro enlace
- THEN no se emite un token utilizable adicional
- AND la respuesta pública sigue siendo el acuse genérico `202`

- GIVEN que la cuenta alcanzó 3 reenvíos en la ventana vigente de 24 horas
- WHEN se solicita otro enlace
- THEN no se realiza un envío adicional
- AND la respuesta no informa el contador, el límite ni la existencia de la cuenta

### Requirement: Atomicidad, idempotencia y concurrencia

El consumo MUST verificar el token y cambiar el estado de la cuenta en una operación atómica. Una activación válida MUST producir como máximo una transición efectiva a verificada. Las solicitudes concurrentes con el mismo token MUST dejar el estado consistente. Las solicitudes repetidas después del consumo MUST ser inocuas y no crear sesiones.

#### Scenario: Dos consumos concurrentes

- GIVEN dos solicitudes concurrentes con el mismo token activo y válido
- WHEN ambas intentan consumirlo
- THEN exactamente una puede responder `200` y realizar la transición a verificado
- AND la otra responde `410`
- AND no se crean sesiones automáticamente

#### Scenario: Repetición del consumo

- GIVEN un token ya consumido
- WHEN se vuelve a invocar el consumo
- THEN responde `410` con la misma forma que cualquier token no utilizable
- AND no modifica la cuenta ni genera otro token

### Requirement: Seam de notificación y configuración local

El caso de uso de identidad MUST depender de un seam de notificación sustituible por un fake en pruebas. El notificador MUST recibir únicamente los datos efímeros mínimos necesarios para entregar el mensaje y MUST permanecer desacoplado de la persistencia y del contrato HTTP. Mailpit MAY utilizarse como adaptador local SMTP mediante Docker, pero no debe presentarse como proveedor productivo ni como garantía de entregabilidad externa.

La configuración de TTL, cooldown, máximo de reenvíos, URL de activación, remitente y conexión local MUST ser externa al código y no contener secretos versionados. Los valores concretos de host, puertos, imagen, scheme y URL quedan sujetos a confirmación en diseño y entorno; el default HTTP local no puede interpretarse como configuración productiva.

#### Scenario: Fake notifier

- GIVEN una prueba del flujo de registro, solicitud, reenvío o fallo de entrega
- WHEN se sustituye el notifier por un fake
- THEN el caso de uso puede verificarse sin SMTP ni Mailpit
- AND el fake permite comprobar destinatario y enlace sin persistir el token crudo
- AND la prueba no se presenta como evidencia de entrega real

#### Scenario: Mailpit disponible

- GIVEN Docker y Mailpit disponibles y correctamente configurados
- WHEN se entrega un mensaje a un correo de prueba
- THEN el mensaje es visible en Mailpit y contiene un enlace utilizable
- AND no contiene contraseña, hash, secreto ni token fuera del enlace
- AND la evidencia se clasifica explícitamente como evidencia real de Mailpit local

#### Scenario: Mailpit o SMTP indisponible

- GIVEN que Mailpit, Docker o el adaptador no están disponibles
- WHEN se intenta entregar un mensaje
- THEN la cuenta permanece no verificada
- AND la respuesta pública conserva la semántica genérica definida
- AND el fallo se registra como evidencia no disponible o fallo de entrega, nunca como entrega confirmada

### Requirement: Enlace y activación en web, de forma condicionada

Si `panel/` dispone de scaffold, entrypoint, router y runner reales al iniciar el slice 2B, la superficie web MUST proporcionar una ruta pública de activación que reciba el enlace, invoque el endpoint común, elimine el token de la URL tan pronto como sea posible, lo mantenga solo en memoria durante la solicitud y muestre confirmación o error genérico. Una activación válida MUST ofrecer una acción hacia login sin crear sesión.

Si no existe ese scaffold o no hay runner o entorno verificable, no se debe crear una aplicación web desde cero ni afirmar integración web completada. El resultado debe registrar la superficie como `N/A` o bloqueada, con la causa concreta y sin inventar evidencia.

#### Scenario: Web disponible y activación válida

- GIVEN un scaffold web real, un runner disponible y un enlace válido
- WHEN la página pública consume el enlace
- THEN invoca el endpoint común
- AND muestra confirmación
- AND ofrece navegación explícita al login
- AND no persiste el token ni crea sesión

#### Scenario: Web disponible y enlace no utilizable

- GIVEN un enlace inválido, expirado o ya consumido
- WHEN se abre la página pública
- THEN muestra un error genérico y una acción segura para solicitar otro enlace
- AND no distingue la causa interna
- AND no muestra el token en pantalla, consola ni telemetría

#### Scenario: Web no verificable

- GIVEN que `panel/` no tiene scaffold materializado, entrypoint, router o runner verificable
- WHEN comienza la evaluación del slice 2B
- THEN no se crea ni se declara un panel nuevo
- AND la integración web se marca `N/A` o bloqueada con causa
- AND la parte Flutter solo puede continuar si es verificable de manera independiente dentro del presupuesto

### Requirement: Integración Flutter y deep link, de forma condicionada

Si el entrypoint, `go_router`, el runner y la plataforma disponible permiten una integración verificable, Flutter MUST ofrecer una ruta pública de activación, consumir el mismo endpoint, mantener el token solo en memoria y mostrar confirmación antes de dirigir al login. El token de activación no puede guardarse como credencial ni restaurarse como sesión. El soporte de cada plataforma debe declararse únicamente si existe build, emulador o dispositivo comprobable.

Sin runner, build, emulador, dispositivo o configuración de plataforma disponible, el resultado debe marcarse `N/A` o bloqueado con causa; no se debe afirmar compatibilidad Android/iOS ni deep linking completo. No se prometen Universal Links ni App Links productivos sin dominio, certificados y archivos de asociación verificables.

#### Scenario: Deep link Flutter verificable

- GIVEN una app instalada, una plataforma comprobable y un deep link válido
- WHEN Flutter recibe el enlace
- THEN procesa el token una sola vez y llama al endpoint común
- AND muestra confirmación y una acción hacia login
- AND no guarda el token como credencial ni crea sesión automática

#### Scenario: Deep link inválido o repetido

- GIVEN un enlace inválido, expirado o ya consumido
- WHEN Flutter intenta procesarlo
- THEN muestra un estado genérico de enlace no disponible
- AND no modifica la cuenta ni crea sesión
- AND permite acceder a una solicitud genérica de reenvío cuando la superficie lo soporte

#### Scenario: Plataforma no verificable

- GIVEN que no existe runner, build, emulador o dispositivo disponible para la plataforma declarada
- WHEN se prepara la evidencia
- THEN la plataforma se marca `N/A` o bloqueada
- AND no se infiere PASS por la presencia de rutas, archivos o configuración

### Requirement: Seguridad, privacidad y no enumeración

El sistema MUST evitar que respuestas, logs, excepciones públicas, persistencia, URLs posteriores al consumo o evidencias inspeccionables contengan contraseñas, tokens crudos, hashes de tokens, credenciales SMTP/JWT u otros secretos. Los access logs y mecanismos de telemetría existentes MUST excluir o redactar los query strings de activación. Las respuestas de solicitud, reenvío y consumo inválido MUST impedir la enumeración de cuentas y estados internos.

#### Scenario: Inspección de superficies sensibles

- GIVEN una respuesta HTTP, mensaje, objeto persistido, log o artefacto de prueba del flujo
- WHEN se inspecciona su contenido
- THEN no contiene contraseña ni token crudo
- AND no contiene hash de token ni secreto de configuración
- AND no revela la causa interna del notificador o del repositorio

#### Scenario: Comparación anti-enumeración

- GIVEN correos inexistentes, pendientes, verificados y limitados
- WHEN se comparan solicitudes y reenvíos
- THEN mantienen el mismo código y forma pública `202`
- AND el cliente no puede determinar confiablemente el estado de la cuenta

### Requirement: Compatibilidad, aislamiento y rollback

El cambio MUST conservar el contrato de login verificado, refresh, logout, consulta de sesión, autorización, normalización de correo y hashing de contraseñas, excepto por la nueva condición de verificación previa para crear sesiones. MUST mantener separado el flujo de HU-003 del onboarding de HU-004 y de HU-005/HU-006. Las migraciones o ajustes de persistencia, si fueran imprescindibles, MUST ser aditivos y no alterar cuentas, sesiones ni estados existentes.

El rollback debe retirar el wiring y superficies de HU-003 sin borrar cuentas ni convertir cuentas no verificadas en verificadas. La ruta histórica `/api/v1/auth/registro` debe conservarse en artefactos históricos y no utilizarse como fallback de la ruta viva `register`.

#### Scenario: Cuenta existente no verificada

- GIVEN una cuenta existente con `correo_verificado = false`
- WHEN se aplica la integración
- THEN conserva sus credenciales, datos y estado no verificado
- AND queda sujeta al bloqueo de login y puede solicitar activación conforme a la política

#### Scenario: Activación de HU-004 aislada

- GIVEN tokens, entidades o rutas del onboarding de HU-004
- WHEN se ejecuta el flujo de HU-003
- THEN no se consumen, renombran, invalidan ni reinterpretan
- AND las regresiones de HU-004/HU-005/HU-006 permanecen fuera del cambio funcional de HU-003

#### Scenario: Rollback

- GIVEN que se requiere retirar la integración
- WHEN se ejecuta un rollback autorizado
- THEN se retiran únicamente endpoints, wiring, adaptadores y superficies agregadas por HU-003
- AND no se eliminan cuentas, sesiones ni datos de otros dominios
- AND ningún rollback convierte una cuenta no verificada en verificada

### Requirement: Límites de alcance y evidencia honesta

La implementación posterior MUST respetar dos slices no encadenados de aproximadamente 300 líneas modificadas, sin superar el máximo total de 600. El conteo debe incluir código, configuración de ejecución y pruebas authored, sin ocultar ampliaciones en archivos generados o documentación. Si un slice supera su límite, si la seguridad o las pruebas esenciales no caben, si el panel requiere crear un scaffold o si no existe un runner mínimo, el trabajo MUST detenerse y solicitar una decisión explícita.

La evidencia MUST distinguir fake, backend, PostgreSQL, Mailpit, Flutter, web y documentación de Sprint 3. Un archivo presente, una configuración escrita o un fake no constituyen evidencia de ejecución real.

#### Scenario: Evidencia disponible

- GIVEN que un runner y el entorno requerido están disponibles
- WHEN se ejecuta una validación o demostración
- THEN se registra el comando, alcance, resultado observable y artefacto sin secretos
- AND se clasifica la evidencia por superficie y fuente

#### Scenario: Evidencia no disponible

- GIVEN que Docker, Mailpit, Flutter, Node, un runner, emulador, dispositivo o scaffold no está disponible
- WHEN se prepara el reporte
- THEN se registra `N/A` o bloqueo con la causa concreta
- AND no se declara PASS ni se completan capturas, métricas o resultados de Sprint 3 no ejecutados

## No objetivos

Quedan fuera de esta especificación: proveedor SMTP productivo o entregabilidad externa; outbox, workers, colas distribuidas, Redis y observabilidad nueva; recuperación o cambio de contraseña, MFA, cambio de correo y rediseño general de sesiones; activación de administradores, invitaciones y onboarding de HU-004; modificación de HU-005/HU-006; panel web completo; Universal Links/App Links productivos; reescritura de evidencia histórica; cambios en `openspec/config.yaml`, gitlinks, ramas, commits o remotes.

## Dependencias

- `UsuarioGlobal.correo_verificado`, identidad, normalización y hashing existentes.
- Núcleo de tokens y persistencia de HU-003 ya observado, sin reimplementarlo ni modificar el cambio archivado.
- PostgreSQL/Alembic y un reloj controlable para TTL, cooldown, ventana y concurrencia.
- Seam de notificación y configuración local segura.
- Para web: scaffold, entrypoint, router, runner y entorno reales.
- Para Flutter: `go_router`, entrypoint, runner, configuración de plataforma y dispositivo o emulador verificable.
- Para evidencia: runners declarados por cada superficie y Docker/Mailpit cuando estén disponibles.

## Matriz de trazabilidad y criterios verificables

| Trazabilidad | Requisitos de esta especificación | Criterio verificable posterior |
| --- | --- | --- |
| `PB-003 → HU-003` | Registro pendiente; login condicionado; web/Flutter condicional | Registro deja `correo_verificado=false`; una cuenta activada inicia sesión; cada superficie disponible consume el enlace. |
| `HU-003 → CU-003` | Solicitud, reenvío, emisión, entrega y consumo | Las tres rutas públicas responden según contrato y completan el flujo sin auto-login. |
| `CU-003 → RF-033` | Token único, TTL, invalidación, límites e idempotencia | Solo un token activo; TTL de 7 días; 15 minutos; 3 reenvíos/24 horas; carrera con una sola activación. |
| `RF-033 → RNF-017` | Protección de secretos y no enumeración | No aparecen contraseña, token crudo, hash o secreto en respuestas, persistencia, logs o evidencia. |
| `HU-003 → Sprint 3` | Seam, Mailpit y evidencia clasificada | Fake y Mailpit se reportan por separado; N/A/bloqueo se conserva cuando el entorno no existe. |

## Riesgos y asuntos para diseño

- El diseño debe confirmar la forma exacta vigente de registro y login sin agregar campos no aprobados.
- Debe confirmar cómo se coordina la persistencia de la cuenta con la emisión inicial y el intento posterior de notificación, sin convertir un fallo de entrega en verificación.
- Debe fijar los textos exactos del acuse `202`, la confirmación `200` y el error `410`, conservando la semántica y los campos en español.
- Debe confirmar URL web, URI o esquema móvil, host, puertos, imagen Mailpit y configuración de plataforma sin atribuir disponibilidad no verificada.
- Debe confirmar el modelo de contadores y la estrategia de concurrencia sin compartir el almacenamiento de HU-004.
- Debe inspeccionar `panel/` antes de decidir si la parte web es realizable; no debe inventar un scaffold.
- Ninguno de estos pendientes autoriza a declarar implementación, pruebas o evidencia de Sprint 3 en esta fase.

## Estado de la fase

Esta especificación es el artefacto de la fase `spec`. La siguiente fase recomendada es `design`. No se ejecutaron tests, builds, migraciones, Docker, Flutter, web, commits ni cambios de código como parte de esta fase.
