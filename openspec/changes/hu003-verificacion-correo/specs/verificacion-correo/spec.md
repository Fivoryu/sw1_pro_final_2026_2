# Especificación: Verificación de correo del cliente

## Propósito

Definir el comportamiento verificable de HU-003 para que una cuenta de cliente confirme la posesión de su correo antes de iniciar sesión. La especificación cubre identidad, activación web y Flutter, reenvío limitado, entrega local mediante Mailpit, seguridad, persistencia y compatibilidad. No constituye evidencia de implementación ni selecciona arquitectura cuando la propuesta dejó una decisión técnica abierta.

## Clasificación normativa

- **Decisiones de producto:** verificación obligatoria, activación web y Flutter, confirmación con redirección al login sin sesión automática, Mailpit para la demo, respuestas genéricas, reenvío automático para cuentas existentes no verificadas y política de límites.
- **Restricciones:** aislamiento de HU-004/HU-005/HU-006; migración aditiva; no enviar contraseñas; no persistir tokens crudos; TDD estricto; no afirmar capacidades de un proveedor no verificado.
- **Supuestos:** `UsuarioGlobal.correo_verificado` continúa siendo la señal de acceso; el registro inicia la primera solicitud de activación; las credenciales se validan antes del reenvío automático.
- **Decisiones técnicas pendientes:** nombres exactos de rutas públicas, códigos/cuerpos definitivos, esquema de deep link, host/URL de demo, adaptador y variables de Mailpit, representación de contadores y estrategia concreta de concurrencia. Se identifican como GAP y deben resolverse en diseño antes de implementar.

## Trazabilidad

`PB-003 → HU-003 → CU-003 → RF-033 → RNF-017 → Sprint 3`

## Requisitos

### Requirement: Verificación obligatoria antes del login

El sistema MUST impedir la creación de una sesión de cliente cuando las credenciales sean válidas pero `correo_verificado` sea falso. El sistema MUST permitir el login normal después de una activación válida, sin alterar las credenciales existentes.

#### Scenario: Login bloqueado para cuenta no verificada

- GIVEN una cuenta existente con credenciales válidas y correo no verificado
- WHEN el cliente intenta iniciar sesión
- THEN no se crean access token, refresh token ni sesión
- AND se devuelve la respuesta pública definida para activación pendiente
- AND se evalúa la oportunidad de reenvío conforme a la política de este documento

#### Scenario: Login permitido después de activar

- GIVEN una cuenta con credenciales válidas y correo verificado
- WHEN el cliente inicia sesión
- THEN se conserva el contrato de login exitoso existente
- AND se crea la sesión sin requerir una activación adicional

#### Scenario: Credenciales inválidas

- GIVEN un correo inexistente o credenciales incorrectas
- WHEN se intenta iniciar sesión
- THEN no se crea una sesión
- AND no se envía un correo de activación
- AND la respuesta no permite distinguir si el correo existe

### Requirement: Registro pendiente de verificación

El sistema MUST conservar una cuenta recién registrada con `correo_verificado = false` y MUST iniciar la solicitud de activación sin enviar la contraseña. La respuesta de registro MUST orientar al estado pendiente sin exponer un secreto ni confirmar información más allá del contrato aprobado.

#### Scenario: Registro de cliente

- GIVEN datos de registro válidos y un correo normalizado
- WHEN se crea la cuenta
- THEN la cuenta queda no verificada y activa para el flujo de activación
- AND se crea o programa la solicitud inicial de activación
- AND el mensaje contiene únicamente el enlace y la información aprobada para activación

#### Scenario: Fallo de entrega inicial

- GIVEN que la cuenta fue creada pero el adaptador de entrega no logra entregar el mensaje
- WHEN finaliza la solicitud inicial
- THEN la cuenta permanece no verificada
- AND no se crea una sesión
- AND la respuesta o la superficie cliente muestra un error accionable con opción de reintento
- AND el reintento respeta cooldown y límite diario

### Requirement: Emisión y seguridad del token

El sistema MUST generar una credencial aleatoria no predecible para cada activación, MUST persistir solamente una representación derivada no reversible para validación y MUST transportar el valor utilizable únicamente en el enlace. Cada cuenta MUST tener como máximo un token activo. El token MUST expirar a los 7 días desde su emisión.

#### Scenario: Emisión de token

- GIVEN una solicitud de activación que puede emitir un token
- WHEN el sistema genera el mensaje
- THEN persiste hash y metadatos necesarios, nunca el token crudo
- AND el enlace contiene el token crudo solo en el canal de entrega
- AND el token tiene una fecha de expiración de siete días

#### Scenario: Nueva emisión

- GIVEN una cuenta con un token activo
- WHEN se emite otro token permitido
- THEN el token anterior queda invalidado antes de que el nuevo sea utilizable
- AND solo el nuevo token puede completar la activación

#### Scenario: Protección de secretos

- GIVEN cualquier respuesta, registro de aplicación, error, persistencia o evidencia inspeccionable
- WHEN contiene datos del flujo de activación
- THEN no contiene token crudo, contraseña, credencial de proveedor ni secreto de configuración

### Requirement: Solicitud y reenvío limitado

El sistema MUST ofrecer una operación de solicitud/reenvío con semántica genérica. Debe aplicar un cooldown de 15 minutos y un máximo de 3 reenvíos por cada ventana de 24 horas, sin permitir que un cliente evada los límites mediante rutas o superficies distintas. El primer envío del registro y los reenvíos posteriores deben distinguirse en el conteo conforme al contrato que cierre diseño; el conteo exacto MUST quedar documentado antes de implementar.

#### Scenario: Reenvío automático por login válido

- GIVEN una cuenta existente no verificada y credenciales válidas
- WHEN ocurre el siguiente intento de login
- THEN no se crea sesión
- AND el sistema puede iniciar el reenvío automático si no hay cooldown ni límite agotado
- AND no se realiza ese envío para credenciales inválidas o correo inexistente

#### Scenario: Cooldown vigente

- GIVEN que la cuenta está dentro de los 15 minutos desde el último envío contado
- WHEN se solicita un reenvío
- THEN no se envía un mensaje adicional
- AND la respuesta es genérica y controlada
- AND no se crea ni se habilita un segundo token activo

#### Scenario: Máximo diario

- GIVEN que la cuenta alcanzó 3 reenvíos en la ventana de 24 horas
- WHEN se solicita otro reenvío
- THEN no se envía un mensaje
- AND la respuesta no revela el contador ni la existencia de la cuenta
- AND el sistema conserva la seguridad del token activo sin crear otro

#### Scenario: Reintento después de fallo de entrega

- GIVEN un fallo confirmado del adaptador de entrega y un token aún válido
- WHEN el cliente solicita reintentar
- THEN la operación es accionable y se somete a cooldown y límite diario
- AND diseño debe decidir si reutiliza el token vigente o emite uno nuevo; si emite uno nuevo, invalida el anterior y lo cuenta con la misma política

### Requirement: Contrato de API de activación y reenvío

El backend MUST exponer operaciones equivalentes a: solicitar activación, consumir activación y solicitar reintento. Cada operación MUST tener una ruta versionada o compatible con el router de identidad existente, método HTTP, esquema de entrada y salida, y códigos definidos en diseño sin revelar existencia de cuentas o estados internos. Los nombres exactos de ruta son `GAP-HU003-002` y no deben inventarse fuera de diseño.

#### Scenario: Contrato lógico de solicitud

- GIVEN una petición con correo normalizable
- WHEN se invoca la operación de solicitud
- THEN acepta un cuerpo con el correo según el formato de registro
- AND devuelve una respuesta genérica común para correo existente, inexistente, ya verificado, cooldown y límite
- AND no devuelve token, hash, contador ni causa interna
- AND el código HTTP y el cuerpo final son una decisión pendiente de diseño, con pruebas de contrato asociadas

#### Scenario: Contrato lógico de consumo

- GIVEN una petición con el valor de activación recibido en el enlace
- WHEN se invoca la operación de consumo
- THEN valida formato, hash, vigencia, estado activo y asociación al cliente
- AND un resultado válido verifica la cuenta y devuelve una confirmación sin sesión
- AND un valor inválido, expirado o consumido usa el mismo tratamiento público genérico
- AND los códigos HTTP, nombres de campos y ruta exacta quedan en `GAP-HU003-002`

#### Scenario: Contrato lógico de reintento

- GIVEN una cuenta que puede reintentar desde una superficie cliente
- WHEN se invoca el reintento
- THEN aplica la misma política de cooldown, máximo diario y token activo
- AND devuelve éxito genérico o error accionable según el resultado observable permitido
- AND no expone si el correo existe, el motivo interno del rechazo ni el proveedor

### Requirement: Activación atómica y de un solo uso

El consumo de un token MUST verificar y cambiar el estado de la cuenta de forma atómica. Una activación válida MUST poder producir una sola transición efectiva a verificada. El sistema MUST rechazar o neutralizar consumos repetidos y MUST conservar el estado consistente ante carreras concurrentes.

#### Scenario: Consumo válido concurrente

- GIVEN dos solicitudes concurrentes con el mismo token válido
- WHEN ambas intentan activarlo
- THEN como máximo una modifica `correo_verificado` y marca el token consumido
- AND la otra recibe la respuesta genérica de token no utilizable
- AND no se crean sesiones automáticamente

#### Scenario: Token consumido

- GIVEN un token que ya completó la activación
- WHEN se intenta consumir nuevamente
- THEN no cambia ningún estado
- AND la respuesta no diferencia consumido de inválido o expirado

#### Scenario: Token expirado o inválido

- GIVEN un token expirado, alterado, ausente o no asociado
- WHEN se intenta consumir
- THEN la cuenta no se verifica
- AND la respuesta es genérica
- AND no se filtran detalles de persistencia o validación

### Requirement: Activación web

La superficie web MUST proporcionar una ruta o página mínima capaz de recibir el enlace, invocar el consumo común y mostrar el resultado. Una activación válida MUST mostrar confirmación y dirigir al login sin crear sesión automática. Los nombres de host, ruta final y mecanismo de navegación son `GAP-HU003-004`.

#### Scenario: Activación web exitosa

- GIVEN un enlace válido abierto en la web
- WHEN el backend confirma el consumo
- THEN la web muestra confirmación de cuenta activada
- AND dirige al login
- AND no conserva ni muestra el token crudo después del consumo salvo lo imprescindible para la solicitud

#### Scenario: Activación web no utilizable

- GIVEN un enlace inválido, expirado o consumido
- WHEN se abre en la web
- THEN se muestra un resultado genérico y una acción segura para solicitar activación nuevamente
- AND no se revela cuál estado interno ocurrió

### Requirement: Activación Flutter y deep link

La app cliente Flutter MUST aceptar el enlace de activación mediante deep link, invocar el mismo caso de uso de backend y mostrar confirmación antes de dirigir al login. Debe existir un fallback web documentado para enlaces abiertos fuera de la app o cuando el deep link no pueda resolverse. El esquema, rutas de plataforma y configuración exacta son `GAP-HU003-004`.

#### Scenario: Deep link Flutter exitoso

- GIVEN un dispositivo o emulador con la app cliente instalada y un deep link válido
- WHEN Flutter recibe y procesa el enlace
- THEN consume la activación una sola vez
- AND muestra confirmación
- AND dirige al login sin crear sesión automática

#### Scenario: Enlace abierto fuera de Flutter

- GIVEN que el enlace no puede abrir la app
- WHEN el usuario lo abre en un navegador
- THEN el fallback web permite completar el mismo consumo
- AND conserva la semántica de confirmación, redirección y errores genéricos

#### Scenario: Deep link inválido o repetido

- GIVEN un deep link inválido, expirado o ya consumido
- WHEN la app intenta procesarlo
- THEN muestra un error genérico y una acción de reenvío segura
- AND no crea sesión ni modifica la cuenta

### Requirement: Entrega local con Mailpit

La demo MUST usar Mailpit ejecutado mediante Docker como mecanismo local de visualización del mensaje. El sistema MUST separar el puerto/adaptador de notificación del caso de uso de identidad y MUST tratar la indisponibilidad de Mailpit como fallo de entrega, no como activación válida. La plantilla, URL pública, puertos, variables y wiring son `GAP-HU003-003`.

#### Scenario: Mensaje visible en Mailpit

- GIVEN Mailpit disponible y una emisión autorizada
- WHEN se entrega el mensaje
- THEN el mensaje es visible para el correo normalizado de prueba
- AND contiene un enlace utilizable
- AND no contiene contraseña, token fuera del enlace ni secretos de configuración

#### Scenario: Mailpit indisponible

- GIVEN que Docker/Mailpit o el adaptador no está disponible
- WHEN se intenta entregar
- THEN no se verifica la cuenta
- AND se retorna un error accionable
- AND un reintento posterior respeta la política de límites

### Requirement: Persistencia e invariantes

La persistencia de HU-003 MUST ser específica o inequívocamente aislada del dominio de activación de HU-004. Una migración MUST ser aditiva y compatible con cuentas existentes. Debe conservar hash del token, cuenta, emisión, expiración, estado de consumo/invalidación y metadatos suficientes para cooldown y ventana de reenvío, sin persistir el valor crudo. La representación concreta de columnas y relación queda para diseño bajo `GAP-HU003-006`.

#### Scenario: Cuenta existente durante la migración

- GIVEN una cuenta existente antes de aplicar el cambio
- WHEN se ejecuta la migración
- THEN conserva correo, credenciales, sesiones y valor actual de `correo_verificado`
- AND no se marca como verificada por defecto
- AND puede completar activación o seguir bloqueada según su estado

#### Scenario: Separación de HU-004

- GIVEN datos y tokens del flujo de onboarding de HU-004
- WHEN se ejecuta HU-003
- THEN no se consumen, renombran, invalidan ni reinterpretan como tokens de cliente
- AND las regresiones de HU-004 permanecen aplicables

### Requirement: Respuestas genéricas y anti-enumeración

Las operaciones públicas de solicitud, consumo y reenvío MUST evitar diferencias observables innecesarias que permitan enumerar correos, cuentas o estados de tokens. Los mensajes y cuerpos no deben revelar existencia, verificación previa, cooldown, contador, expiración, consumo, causa del adaptador ni detalles de almacenamiento. Los errores accionables por fallo de entrega MUST permitir reintentar sin contradecir esta regla.

#### Scenario: Comparación de solicitudes

- GIVEN una solicitud para correo inexistente, existente no verificado, existente verificado o limitada
- WHEN el cliente observa la respuesta
- THEN no puede determinar confiablemente cuál caso interno ocurrió a partir del contrato público

#### Scenario: Comparación de tokens

- GIVEN tokens inválidos, expirados, consumidos o pertenecientes a otra cuenta
- WHEN se consumen
- THEN la respuesta pública conserva la misma semántica genérica
- AND ninguna cuenta cambia de estado

### Requirement: Compatibilidad y regresión

El cambio MUST conservar registro, refresh, logout, autorización y sesiones existentes fuera de la nueva exigencia de verificación. MUST mantener la normalización de correo y el hashing de contraseñas. MUST incluir regresiones para login verificado y no verificado, registro, activación separada de HU-004 y superficies no involucradas.

#### Scenario: Flujo existente de cuenta verificada

- GIVEN una cuenta previamente verificada y un cliente compatible
- WHEN usa registro/login/sesión según corresponda
- THEN los contratos no relacionados con activación continúan funcionando

#### Scenario: Trabajo no relacionado

- GIVEN cambios o archivos preexistentes de HU-004/HU-005/HU-006
- WHEN se implementa HU-003
- THEN no se modifican ni se usan como almacenamiento de HU-003 sin una decisión explícita posterior

### Requirement: Evidencia TDD y criterios de aceptación

La implementación MUST demostrar, mediante pruebas y evidencia posterior, registro pendiente, bloqueo previo, activación web y Flutter, confirmación sin sesión, consumo único, expiración, invalidación anterior, cooldown, máximo diario, reenvío automático, fallo de entrega, concurrencia, anti-enumeración, ausencia de secretos y regresiones. En esta fase no se ejecutan ni se declaran pruebas.

#### Scenario: Evidencia backend

- GIVEN la implementación de un requisito backend
- WHEN se aplica TDD estricto
- THEN se registra evidencia RED, GREEN, TRIANGULATE y REFACTOR con el runner `.venv/Scripts/python.exe -m pytest backend/tests -q`
- AND se vincula cada caso a HU-003/CU-003 y a su requisito

#### Scenario: Evidencia de superficies

- GIVEN la implementación web, Flutter y Mailpit
- WHEN se verifica la demo
- THEN se documenta el escenario, correo de prueba normalizado, resultado observable y artefacto de respaldo sin secretos
- AND no se presenta esta especificación como resultado cumplido

## Contratos y gaps obligatorios para diseño

| ID | Pendiente | Criterio de cierre |
| --- | --- | --- |
| GAP-HU003-001 | Mapeo de RF-033 a reglas BR-001..022 | Documentar únicamente reglas aplicables con fuente verificable. |
| GAP-HU003-002 | Rutas, métodos, cuerpos, códigos HTTP y mensajes | Publicar contrato definitivo y pruebas de contrato sin filtración. |
| GAP-HU003-003 | Mailpit: adaptador, variables, puertos, plantilla y URL | Definir configuración real de Docker y límites del entorno demo. |
| GAP-HU003-004 | Deep link, fallback, host y navegación | Definir esquema/rutas de plataforma y comportamiento web equivalente. |
| GAP-HU003-005 | Semántica observable de login, registro y reenvío | Fijar respuestas para cuenta nueva, existente, inválida, limitada y sesión previa. |
| GAP-HU003-006 | Modelo de token, reloj, contadores y concurrencia | Definir columnas, zona temporal, transacción y prueba de carrera sin cambiar las decisiones de producto. |

## Fuera de alcance

Quedan fuera administradores, invitaciones, onboarding de HU-004, HU-005/HU-006, notificaciones multi-canal, proveedor productivo, recuperación/cambio de contraseña, cambio de correo, MFA, rediseño general de sesiones, panel administrativo completo y garantías de entregabilidad externa.

## Criterio de finalización de la especificación

La especificación se considera completa para pasar a diseño cuando los requisitos anteriores son trazables a PB-003/HU-003/CU-003/RF-033/RNF-017/Sprint 3, cada requisito tiene escenarios observables, los gaps técnicos permanecen explícitos y ningún resultado de prueba, configuración o demo se afirma como realizado.
