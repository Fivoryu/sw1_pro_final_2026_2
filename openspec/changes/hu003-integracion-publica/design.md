# Diseño técnico: integración pública de HU-003

## Resumen ejecutivo y decisión de arquitectura

Este diseño conecta el núcleo de verificación de correo que ya existe en `backend/` con la identidad pública, sin reimplementarlo ni modificar el cambio archivado `hu003-verificacion-correo`. La primera unidad de entrega es **Slice 2A — backend público**, con dos commits de persistencia deliberados para registro, notificación posterior al commit, contrato HTTP, bloqueo de login no verificado y adaptador SMTP local sustituible. La segunda es **Slice 2B — Flutter condicionado**, sin crear un panel React/Vite inexistente.

Las dos unidades son no encadenadas como estrategia de entrega, de aproximadamente 300 líneas authored cada una y con un máximo agregado de 600. Slice 2B consume el contrato estable de 2A, pero no requiere una cadena de PRs. Este documento no afirma implementación, tests, builds, migraciones ejecutadas, disponibilidad de Docker/Mailpit/Flutter/web ni cumplimiento de Sprint 3.

La decisión pública central queda fijada así:

- Un cuerpo de consumo ausente, el campo `token` faltante o un tipo de token incompatible es un error estructural y responde **`422`**.
- Un valor de `token` presente y de tipo compatible, aunque sea vacío, alterado, inválido, expirado, invalidado, consumido o no asociado, es un enlace no utilizable y responde **`410`** con el mismo cuerpo genérico.
- Un fallo de persistencia es una falla interna y responde **`500`** con un cuerpo genérico seguro; nunca se transforma en `410`.
- El notificador se invoca después del commit de la persistencia. Un fallo de entrega conserva la cuenta no verificada y el resultado público genérico aprobado.

## 1. Fuentes, clasificación y realidad del workspace

### 1.1 Fuentes leídas

Se leyeron las versiones actuales de:

- `openspec/changes/hu003-integracion-publica/{proposal,spec,explore}.md`.
- Las observaciones Engram de `sdd/hu003-integracion-publica/{proposal,spec,explore}`.
- `backend/app/modules/identity/{models,verification,repository,router,service,schemas}.py`.
- `backend/app/core/{config}.py`, `backend/app/main.py`, `backend/app/db/session.py`.
- `backend/alembic/{env.py,versions/0006_hu003_email_verification.py}`.
- `backend/tests/{test_registro,test_autenticacion,test_verificacion_correo}.py` y `backend/pyproject.toml`.
- `infra/docker/compose.postgres.yml`.
- `apps/cliente_mobile/pubspec.yaml`, `lib/main.dart`, `lib/app.dart`, el servicio/repositorio/modelos/ViewModel/pantallas de autenticación, almacenamiento seguro, `web/index.html`, `web/manifest.json`, `AndroidManifest.xml` e `Info.plist`.
- `panel/README.md`.
- El cambio archivado `hu003-verificacion-correo` únicamente como contexto histórico y técnico de lectura; no se modifica ni se duplica.

### 1.2 Hechos, decisiones e inferencias

| Clasificación | Contenido | Fuente o límite |
| --- | --- | --- |
| Hecho | El backend actual ya contiene `UsuarioGlobal.correo_verificado`, `EmailVerificationToken`, generación/hash, política, repositorio transaccional, migración `0006` y tests focalizados. | Checkout actual. |
| Hecho | `UserRepository.guardar` hace `flush`, `commit` y `refresh`; `EmailVerificationRepository.emit_initial`, `resend` y `consume` trabajan con transacciones y locks propios. | Código actual. |
| Hecho | El router solo publica registro, login, refresh, logout y `me`; los tres endpoints públicos de verificación aún no están conectados. | `router.py`. |
| Hecho | Registro y login actuales no reciben un servicio de verificación; el login actual puede crear sesión para una cuenta no verificada. | `service.py`, router y tests actuales. |
| Hecho | Flutter ya tiene `http`, `go_router`, repositorio, ViewModel, pantallas de registro/login y `flutter_secure_storage`; no tiene activación ni configuración de deep link. | Código actual. |
| Hecho | `panel/README.md` describe React/TypeScript/Vite y estructura inicial; no hay scaffold React verificable para diseñar una integración de panel. | Panel actual y exploración. |
| Hecho | Compose contiene PostgreSQL `postgres:16-alpine` en `5434` y no contiene Mailpit. | Compose actual. |
| Decisión aprobada | Las rutas públicas usan segmentos ingleses; el registro vivo es `POST /api/v1/auth/register`; los campos JSON existentes permanecen en español. | Proposal y spec corregidas. |
| Decisión aprobada | Login no verificado: `401` genérico, sin sesión ni tokens de sesión; la activación válida nunca hace auto-login. | Spec corregida. |
| Decisión de diseño cerrada | Cuenta e inicialización de token usan dos commits existentes, con comportamiento retry-safe y sin afirmar atomicidad distribuida. | Este diseño, §3. |
| Decisión de diseño cerrada | Fallo de persistencia conocido: `500` y `{"detail":"No se pudo completar la operación."}`; no se confunde con `410`. | Este diseño, §4. |
| Condicionado | La entrega Mailpit, la URL/URI efectiva y el deep link solo se declaran después de ejecutar sus prechecks reales. | Restricción de entorno. |

### 1.3 CodeGraph

El contexto de ejecución confirma que CodeGraph está disponible y actualizado en este workspace. Por lo tanto, este diseño **no** repite la afirmación anterior de que no existía un ejecutable o índice CodeGraph. Durante la lectura dirigida, el archivo esperado `.codegraph/status.json` no estuvo accesible en esa ruta concreta; esa es una limitación puntual de la superficie de lectura, no una conclusión de ausencia de CodeGraph. No se reindexa ni se convierte esa limitación en evidencia de arquitectura. Las referencias concretas de este diseño se contrastan con los archivos actuales enumerados arriba y con la estructura CodeGraph disponible en el workspace.

## 2. Arquitectura actual y composición elegida

### 2.1 Capas y dependencias

La integración conserva la arquitectura síncrona actual de FastAPI + SQLAlchemy + PostgreSQL:

```text
FastAPI / identity.router
  └─ schemas y mapeo HTTP seguro
      └─ IdentityService / AuthenticationService
          └─ VerificationService
              ├─ VerificationRepositoryProtocol → EmailVerificationRepository
              ├─ VerificationNotifierProtocol → SMTP Mailpit o fake
              ├─ VerificationTokenGeneratorProtocol
              └─ ClockProtocol

get_db() → una Session SQLAlchemy por request
  ├─ UserRepository(db)
  ├─ SessionRepository(db)
  └─ EmailVerificationRepository(db, settings)
```

El router no construye hashes, tokens ni URLs. Los servicios no contienen SQL. El repositorio conserva la autoridad de transacciones, locks, constraints y rollback. El notifier no conoce modelos, sesiones ni errores públicos.

### 2.2 DI del backend

Se agregan dependencias al router existente, sin crear un router paralelo:

1. `get_verification_repository(db, settings)` construye `EmailVerificationRepository` con la misma `Session` del request.
2. `get_verification_notifier(settings)` devuelve `SmtpVerificationNotifier` cuando existen host y URL válidos; si falta una configuración imprescindible, devuelve `UnavailableVerificationNotifier`, que produce un fallo de entrega seguro sin conexión accidental a SMTP.
3. `get_verification_service(repository, notifier, clock, settings)` compone el servicio con el generador seguro.
4. `get_identity_service` recibe el servicio de verificación obligatorio en producción.
5. `get_auth_service` recibe el mismo tipo de servicio para el reenvío automático posterior a credenciales válidas.
6. Los tests sustituyen `get_verification_service`, `get_identity_service` o `get_auth_service` mediante `app.dependency_overrides`, igual que los seams actuales.

FastAPI reutiliza las dependencias por request; así, los repositorios de usuario y verificación observan la misma sesión, pero los límites de commit siguen siendo explícitos. No se agrega un singleton mutable ni un contenedor nuevo.

### 2.3 Servicio de verificación

`VerificationService` actual conserva `emit_initial`, `resend`, `consume` y el contrato de errores. Se agrega una operación de aplicación `request_or_resend(user_id)` con esta regla:

1. Intentar `emit_initial`.
2. Si el resultado es `already_issued`, intentar `resend` con la misma política y las mismas filas.
3. Devolver `emitted`, `delivery_failed`, `cooldown`, `resend_limit`, `already_verified` o `user_not_found` sin serializar el resultado interno.

El servicio calcula SHA-256 inmediatamente en `consume`; el repositorio recibe únicamente el hash. El token crudo se entrega al notifier únicamente después de que el repositorio confirma el token hash y antes de liberar la ejecución del caso de uso.

Para registro, la emisión inicial debe terminar en `emitted` o `delivery_failed`. Un estado incompatible para un usuario recién guardado se trata como `VerificationPersistenceError` y llega al mapeo interno `500`; no se fabrica un `201` que afirme que la solicitud inicial quedó preparada.

## 3. Persistencia de cuenta, token inicial y atomicidad

### 3.1 Decisión explícita: dos commits retry-safe

La decisión es **no refactorizar en este slice el propietario de transacciones de `UserRepository.guardar`**. Ese método actual confirma la cuenta en su propio `commit`, mientras que `EmailVerificationRepository.emit_initial` confirma el token hash en una segunda transacción. El método `add_initial` existente solo hace `flush` y no constituye por sí mismo una unidad de trabajo compartida; conectarlo requeriría transferir la propiedad transaccional del registro y reevaluar el presupuesto.

El flujo de registro será, por tanto:

```text
1. normalizar correo y hashear password
2. UserRepository.guardar(usuario no verificado)
   → COMMIT DE CUENTA
3. VerificationService.emit_initial(usuario.id)
   → lock usuario/tokens, INSERT token_hash, COMMIT DE TOKEN
4. notifier.deliver(... raw_token ...)
   → FUERA DE LA TRANSACCIÓN Y DEL LOCK
5. responder con el contrato público
```

Esto es una elección de límites de persistencia, no una afirmación de atomicidad distribuida. Se preserva la seguridad porque:

- La cuenta siempre se crea con `correo_verificado = false`.
- Una falla antes del commit de la cuenta no llama al notifier.
- Una falla al persistir el token no llama al notifier ni marca la cuenta como verificada. La cuenta puede quedar creada y no verificada; una solicitud pública posterior vuelve a intentar la emisión inicial o el reenvío según el historial observado.
- Un resultado ambiguo del commit no provoca una emisión paralela automática: una solicitud posterior relee el historial bajo lock y aplica `emit_initial`/`resend` y sus límites.
- Una falla de entrega posterior al commit no elimina la cuenta ni el token. El registro conserva `201`; la solicitud y el reenvío conservan `202`. El cliente dispone de la operación genérica posterior, sujeta a cooldown y límite.

La observabilidad pública de una falla de persistencia es un `500` genérico, aunque la cuenta pueda haber quedado confirmada en el primer commit. Esa respuesta no expone si el token existe, no contiene secretos y permite que el proceso operativo o una solicitud posterior reconcilien el estado. No se promete rollback distribuido ni se borra automáticamente la cuenta creada.

### 3.2 Alcance del modelo y migración

No se agrega migración ni se modifican `models.py`, `0006_hu003_email_verification.py` o `alembic/env.py` en el plan normal:

- La tabla actual `email_verification_token` ya tiene UUID, FK a `usuario_global`, `token_hash` único, estado, fechas, `es_reenvio`, checks e índice único parcial de un token `active` por usuario.
- El contador se deriva del historial de tokens y de `es_reenvio`; no se crea una tabla de estado ni se comparte almacenamiento con HU-004.
- `activation_ttl_days` queda reservado a HU-004. HU-003 conserva `email_verification_token_ttl_days = 7`.
- No se hace backfill, no se cambian cuentas existentes y no se toca `Sesion`.
- Antes de aplicar se debe comprobar `alembic heads` y `alembic current`. Si la base no coincide con `0006`, existen múltiples heads o se necesita alterar una tabla no perteneciente a HU-003, se detiene la aplicación.

### 3.3 Locks, límites y concurrencia

Se conserva el orden único **usuario → tokens** del repositorio actual:

- Emisión: `SELECT ... FOR UPDATE` sobre `UsuarioGlobal`, luego tokens del usuario ordenados por `emitido_en DESC, id DESC`; se valida estado, cooldown, ventana y límite; se invalida el activo y se inserta el reemplazo en la misma transacción.
- Consumo: se busca inicialmente por hash para localizar el usuario; después se bloquea el usuario y se vuelve a cargar/bloquear el token por ID y hash. La transición válida marca token `consumed`, `consumido_en = now` y `correo_verificado = true` antes del commit.
- El índice parcial es una defensa adicional; no sustituye el lock.
- El primer envío tiene `es_reenvio = false`, inicia cooldown y ventana, pero no consume uno de los tres reenvíos.
- Los reenvíos explícitos y automáticos comparten cooldown de 15 minutos, máximo de 3 en 24 horas y el mismo historial, incluso si el SMTP falla después del commit.
- En `now >= expira_en`, el token no es utilizable.

Dos consumos concurrentes del mismo token se serializan en el lock del usuario. El primero puede devolver `200`; el segundo observa el estado terminal y devuelve `410`. Ninguna rama de consumo crea `Sesion`, llama al servicio JWT ni revoca sesiones existentes.

## 4. Contratos HTTP y mapeo completo de estados

Todos los paths son ingleses y se montan bajo el router actual `/api/v1/auth`. Los campos nuevos de JSON usan `mensaje`; los campos existentes de registro y sesión no se renombrarán ni se ampliarán.

### 4.1 Tabla HTTP normativa

| Operación | Request | Éxito | Entrada estructural inválida | Persistencia | Otros estados públicos |
| --- | --- | --- | --- | --- | --- |
| Registro `POST /api/v1/auth/register` | `RegistroRequest` vigente: `correo`, `password` | `201` y exactamente `RegistroResponse`: `id`, `correo`, `estado`, `correo_verificado`, `creado_en` | `422` del handler vigente | `500`, `{"detail":"No se pudo completar la operación."}` | Duplicado conserva `409` y su cuerpo actual |
| Solicitud `POST /api/v1/auth/email-verification/request` | `{ "correo": "usuario@example.com" }` | `202`, `{"mensaje":"Si corresponde, se enviará un enlace para verificar el correo."}` | `422` vigente | `500`, cuerpo interno genérico | Correo inexistente, verificado, cooldown, límite, usuario desaparecido y entrega fallida mantienen `202` y el mismo body |
| Reenvío `POST /api/v1/auth/email-verification/resend` | Igual a solicitud | `202` con exactamente el mismo body byte-a-byte | `422` vigente | `500`, cuerpo interno genérico | Los mismos estados de solicitud mantienen `202` y el mismo body |
| Consumo `POST /api/v1/auth/email-verification/consume` | `{ "token": "valor-del-enlace" }` | `200`, `{"mensaje":"Correo verificado. Puede iniciar sesión."}` | `422` si falta el body, falta `token` o el tipo no es compatible | `500`, `{"detail":"No se pudo completar la operación."}` | Token string presente pero no utilizable: `410`, `{"detail":"El enlace de verificación no es válido o ya no está disponible"}` |
| Login `POST /api/v1/auth/login` | `LoginRequest` vigente | `200` y `TokenResponse` vigente solo para cuenta activa y verificada | `422` vigente | Fallo de reenvío interno no cambia el contrato: se mantiene `401` genérico | Credenciales inválidas o cuenta no verificada: `401`, `{"detail":"Correo o contraseña inválidos"}` |

Los nombres existentes no se renombrarán.

### 4.2 Distinción obligatoria `422` frente a `410`

El schema de consumo debe usar un secreto de tipo string (`SecretStr` o equivalente estricto) **sin `min_length` ni regex que convierta el contenido en error estructural**. La validación de schema solo decide presencia del campo y compatibilidad de tipo:

| Payload | Resultado |
| --- | --- |
| Sin body | `422` |
| `{}` | `422` |
| `{"token": null}` | `422` |
| `{"token": 123}` o un array/objeto | `422` |
| `{"token": ""}` | `410`; string presente, valor no utilizable |
| `{"token": "alterado"}` | `410` |
| String de token expirado, invalidado, consumido o no asociado | `410` |
| String activo, vigente y asociado | `200` |

El cuerpo `422` se produce mediante el handler actual de `RequestValidationError`, que conserva solo ubicación, mensaje y tipo, sin `input`; no debe reflejar el valor sensible. Los estados `invalid`, `expired`, `already_consumed`, `already_verified` y cualquier valor presente no utilizable se unifican en `410`. Un `VerificationPersistenceError` se captura antes de esa clasificación y se convierte en `500`, porque la base no pudo determinar que el enlace fuera inválido.

### 4.3 Solicitud, reenvío y registro

- Un cuerpo válido para solicitud/reenvío se normaliza igual que registro: `strip` y minúsculas después de la validación de correo.
- Si no hay usuario, si la cuenta ya está verificada, si hay cooldown o si se agotó el límite, la operación termina en el acuse `202` constante.
- Para una cuenta no verificada, el servicio usa emisión inicial si no hay historial y reenvío si ya existe historial. Cambiar entre solicitud, reenvío o login no reinicia el contador.
- `NotificationDeliveryError` se convierte en estado interno `delivery_failed`; no sale al router. La respuesta de solicitud/reenvío sigue siendo `202` y la de registro sigue siendo `201`.
- `VerificationPersistenceError` no se oculta como entrega aceptada: solicitud/reenvío y registro responden `500` con el detalle genérico exacto de la tabla. El cuerpo no contiene correo, ID, token, hash, proveedor, SQL ni excepción.
- En login, una falla de persistencia o entrega del reenvío automático se absorbe dentro de la respuesta `401` genérica aprobada; nunca genera `410`, `500` específico ni sesión.

### 4.4 Consumo y ausencia de sesión

En el único camino `200`, el router devuelve solo el mensaje de confirmación. El servicio no llama a `AuthenticationService`, `TokenService` ni `SessionRepository`. El cliente debe mostrar una acción explícita hacia login; no recibe access token ni refresh token.

El `410` es único para todos los valores string presentes no utilizables. No distingue alteración, formato no reconocido, expiración, invalidación, consumo previo, asociación inexistente o cuenta ya verificada. No se refleja el token ni se incluye su hash.

## 5. Notificación, configuración y Mailpit

### 5.1 Puerto y adaptadores

El puerto existente `VerificationNotifierProtocol.deliver(user_id, email, token, expires_at)` se conserva en `verification.py`. El token es un argumento efímero y no forma parte de `EmissionResult` ni de las respuestas HTTP.

Se crea `backend/app/modules/identity/notifier.py` con:

- `SmtpVerificationNotifier`, basado exclusivamente en `email.message.EmailMessage` y `smtplib`; no agrega dependencia de proveedor productivo.
- `UnavailableVerificationNotifier`, cuyo `deliver` lanza `NotificationDeliveryError` sin detalles.
- Construcción de una URL a partir de una base configurada sin query ni fragmento, agregando `token` con codificación URL. El token aparece únicamente en el enlace del mensaje que necesita el destinatario.
- Mensaje de texto plano sin contraseña, hash, JWT, credenciales SMTP, excepción, estado interno ni URL adicional innecesaria.
- Conversión de errores de conexión/configuración (`OSError`, `smtplib.SMTPException`, `ValueError`) a `NotificationDeliveryError` sin conservar el texto del proveedor.
- Sin logger nuevo. Si más adelante se usa logging existente, solo podrá registrar una categoría constante sin correo, URL, query string, token, hash, excepción completa o credencial.

La configuración se inyecta; el notifier no lee `os.environ` directamente y no conoce el router. La URL configurada es una base y debe terminar en la ruta que la superficie elegida expone, sin `?token=` ya incorporado. No se fija un host HTTP productivo en código.

### 5.2 Settings elegidos

Se conservan sin cambios los settings de política actuales:

| Setting existente | Alias | Valor por defecto | Uso |
| --- | --- | ---: | --- |
| `email_verification_token_ttl_days` | `EMAIL_VERIFICATION_TOKEN_TTL_DAYS` | `7` | TTL de HU-003 |
| `email_verification_resend_cooldown_minutes` | `EMAIL_VERIFICATION_RESEND_COOLDOWN_MINUTES` | `15` | Cooldown común |
| `email_verification_max_resends_24h` | `EMAIL_VERIFICATION_MAX_RESENDS_24H` | `3` | Reenvíos por 24 horas |

Se agregan únicamente settings externos, sin secretos versionados:

| Setting | Alias | Default seguro | Decisión |
| --- | --- | --- | --- |
| `email_verification_smtp_host` | `EMAIL_VERIFICATION_SMTP_HOST` | `None` | Ausencia significa notificador no disponible; no se asume `localhost`. |
| `email_verification_smtp_port` | `EMAIL_VERIFICATION_SMTP_PORT` | `1025` | Puerto local convencional de Mailpit. |
| `email_verification_smtp_from` | `EMAIL_VERIFICATION_SMTP_FROM` | `no-reply@roomforge.local` | Remitente de demo, no identidad productiva. |
| `email_verification_smtp_timeout_seconds` | `EMAIL_VERIFICATION_SMTP_TIMEOUT_SECONDS` | `10` | Timeout acotado. |
| `email_verification_activation_url` | `EMAIL_VERIFICATION_ACTIVATION_URL` | `None` | Obligatoria para una entrega utilizable; sin default HTTP. |

No se agregan usuario, password, API key, JWT o TLS productivo. No se modifica el `.env` local ni se versionan secretos. La ausencia de `email_verification_activation_url` no rompe el registro por un error de configuración de proveedor: usa el notificador no disponible y conserva el resultado genérico de entrega. Una persistencia correcta con URL ausente no se convierte en `500` por SMTP.

La URL concreta es una decisión de configuración del entorno, no un segundo contrato público: se usa una sola base por ejecución. Para Flutter nativo local puede ser `roomforge://email-verification`; para una superficie web verificable debe ser una URL HTTP/HTTPS de esa ruta. La implementación elige una sola según el runner y la plataforma realmente disponibles. No se afirma hoy que ninguna de esas direcciones sea accesible.

### 5.3 Compose local

Si el precheck confirma que agregar un servicio no reestructura el entorno, se añade a `infra/docker/compose.postgres.yml` un servicio mínimo y versionado:

```yaml
  mailpit:
    image: axllent/mailpit:v1.21.8
    ports:
      - "1025:1025"
      - "8025:8025"
```

Se conserva intacto el servicio PostgreSQL y sus volúmenes. El backend ejecutado en host usa `127.0.0.1`; un backend containerizado usaría `mailpit`. La UI local sería `http://localhost:8025`. No se agrega volumen de secretos, autenticación SMTP ni garantía de entregabilidad externa. Si la imagen, puertos o topología no son utilizables, Mailpit queda `N/A`; el fake notifier no se presenta como evidencia real.

## 6. Plan exacto de Slice 2A

### 6.1 Archivos, anclajes y presupuesto

El plan normal no toca modelos, migraciones, artefactos históricos, configuraciones OpenSpec ni `.env` locales. Los rangos son anclajes del checkout actual y el número es un forecast de líneas authored modificadas, no un conteo ejecutado.

| Archivo | Anclaje actual | Trabajo previsto | Forecast |
| --- | --- | --- | ---: |
| `backend/app/core/config.py` | settings HU-003 actuales en líneas 44–57 | Agregar cinco settings SMTP/URL, sin tocar `activation_ttl_days` ni 7/15/3. | 10 |
| `backend/app/modules/identity/verification.py` | `VerificationService` en líneas 76–118 | Agregar protocolo/fachada `request_or_resend` y clasificación interna mínima; conservar hash, notifier y errores. | 15 |
| `backend/app/modules/identity/notifier.py` | Archivo nuevo | SMTP local, adapter no disponible, URL efímera y traducción segura de errores. | 45 |
| `backend/app/modules/identity/schemas.py` | Después de `TokenResponse`/`MeResponse`, líneas 9–43 | Schemas de solicitud, consumo y `MessageResponse`; token string secreto sin restricción de contenido que fuerce `422`. | 10 |
| `backend/app/modules/identity/service.py` | `IdentityService` línea 38, registro línea 47, login línea 80 | Inyección obligatoria, emisión inicial después del commit, guard previo a sesión y reenvío solo tras credenciales válidas. | 32 |
| `backend/app/modules/identity/router.py` | DI líneas 62–99 y endpoints desde línea 101 | DI del servicio/notifier, tres rutas, helper de `500`, tabla de mapeos `200/202/410`, sin modificar paths históricos. | 50 |
| `infra/docker/compose.postgres.yml` | Servicio actual líneas 4–21 | Servicio Mailpit mínimo versionado, solo si el precheck lo permite. | 8 |
| `backend/tests/test_registro.py` | fixtures línea 85 y tests desde línea 95 | Inyección fake, `201` pendiente, notifier posterior al commit, entrega fallida y persistencia segura. | 12 |
| `backend/tests/test_autenticacion.py` | fixture línea 56 y login desde línea 93 | Fixture verificada para regresiones, cuenta no verificada bloqueada, no sesión y reenvío posterior a password válida. | 18 |
| `backend/tests/test_verificacion_correo.py` | helper línea 137 y tests desde línea 154 | `request_or_resend` y preservación de estados/errores del núcleo. | 8 |
| `backend/tests/test_verificacion_publica.py` | Archivo nuevo | Contrato HTTP, tabla de estados, `422/410/500`, notifier fake, secretos, login y concurrencia disponible. | 64 |
| **Subtotal authored forecast** | — | — | **272** |
| **Reserva de Slice 2A** | — | No se consume para ocultar seguridad o tests; si se consume, se detiene. | **28** |
| **Límite máximo del slice** | — | No superar. | **300** |

`backend/app/modules/identity/models.py`, `repository.py`, `backend/alembic/versions/0006_hu003_email_verification.py` y `backend/alembic/env.py` quedan en **cero líneas previstas**. Si la integración revela una incompatibilidad imprescindible en esas superficies, se detiene la unidad y se solicita decisión de alcance antes de modificarla; no se copia el núcleo archivado dentro de otros archivos. No se incluye `backend/.env.example` en el plan: la configuración se inyecta externamente y no se edita ningún archivo local de secretos.

### 6.2 Flujo de tests de Slice 2A

`test_verificacion_publica.py` debe cubrir como mínimo:

1. OpenAPI lista `register`, `login`, `email-verification/request`, `email-verification/resend` y `email-verification/consume` bajo `/api/v1/auth`.
2. Registro válido conserva exactamente las cinco claves actuales, deja `correo_verificado=false`, inicia emisión y no devuelve password, token ni hash.
3. Fallo del notifier después del commit conserva `201`, cuenta no verificada, token hash persistido y respuesta sin proveedor.
4. Falla la persistencia inicial: no se llama al notifier y se responde `500` con el body exacto; la cuenta no se presenta como verificada y la solicitud posterior puede recuperar el flujo.
5. Solicitud/reenvío para correo inexistente, verificado, pendiente, cooldown, límite y entrega fallida devuelve `202` y el body constante idéntico.
6. Payload inválido de solicitud/reenvío devuelve `422` sin revelar estado de cuenta.
7. Consumo sin body, sin `token`, `null`, entero y objeto devuelve `422`; un string vacío, alterado, expirado, invalidado o consumido devuelve el mismo `410`.
8. Consumo válido devuelve `200`, marca la cuenta y el token como consumido, no crea `Sesion` ni devuelve JWT.
9. Error de persistencia durante consumo devuelve exactamente `500` y no `410`; la cuenta y el token no se presentan como modificados si la transacción hizo rollback.
10. Login de cuenta verificada conserva `200`/`TokenResponse`; login no verificado devuelve `401`, no crea sesión y solo intenta reenvío después de password válida; password inválida no llama al notifier.
11. El fake notifier permite inspeccionar destinatario/enlace efímero sin persistir token crudo; el adapter SMTP elimina detalles de excepciones.
12. Si el runner PostgreSQL está disponible en apply, se agrega la prueba de dos consumos concurrentes con exactamente un `200`; el fake no se cuenta como evidencia de lock real.

Los tests actuales de `test_registro.py`, `test_autenticacion.py` y `test_verificacion_correo.py` se adaptan sin perder sus regresiones. Los usuarios de éxito de login deben declarar `correo_verificado=true`; los casos no verificados se agregan explícitamente. No se rebajan asserts de seguridad para hacer entrar la integración en el presupuesto.

## 7. Slice 2B: viabilidad real de Flutter y panel

### 7.1 Panel web: resultado actual `N/A`

El único archivo actual del panel leído es `panel/README.md`, que declara React + TypeScript + Vite y estado de estructura inicial sin código. No se diseñan ni se prometen `package.json`, entrypoint, router, scripts, componentes o tests React inexistentes. Tampoco se crea un scaffold para llenar el límite de 300 líneas.

Resultado de diseño:

> **Panel React/Vite: `N/A` o bloqueado para HU-003.** La causa es la falta de scaffold, entrypoint, router, package manager y runner verificables. La ausencia del panel no bloquea por sí sola la parte Flutter si esta puede verificarse independientemente; no se presentará una pantalla Flutter web como evidencia del panel React.

Si una lectura posterior del submódulo encontrara un scaffold materializado, tasks debe revisar su alcance y presupuesto antes de incluirlo. La presencia de archivos tampoco será evidencia de runner o integración ejecutada.

### 7.2 Flutter: scaffold existente y límites

La aplicación cliente sí tiene una ruta de integración técnicamente concreta:

```text
main.dart
  → AuthApiService(http.Client, API_BASE_URL)
  → AuthRepository(AuthApi, CredentialStorage)
  → AuthViewModel(ChangeNotifier)
  → AuthApp(MaterialApp.router + GoRouter)
```

Hechos actuales relevantes:

- `pubspec.yaml` ya incluye `go_router`, `http` y `flutter_secure_storage`; no hay plugin específico de deep link.
- `auth_api_service.dart` centraliza `_request`, `_ensureSuccess` y parsing; `AuthApi` contiene registro, login, refresh, logout y `me`.
- `auth_repository.dart` es el seam correcto para delegar operaciones de activación sin tocar almacenamiento de sesión.
- `credential_storage.dart` persiste únicamente access token, refresh token y expiración. El diseño prohíbe pasarle el token de activación.
- `auth_view_model.dart` usa `ChangeNotifier`; registro y login ya exponen `notice`/`errorMessage` para las pantallas.
- `app.dart` usa `GoRouter`; las únicas rutas actuales son `/`, `/login`, `/register` y `/home`, y el redirect solo permite login/registro como públicas.
- `AndroidManifest.xml` tiene launcher e Internet, pero no un `VIEW`/`BROWSABLE` para activación. `Info.plist` no declara un URL scheme ni associated domains.
- `web/index.html` y `web/manifest.json` son scaffolds de Flutter Web. No constituyen el panel React y no existe evidencia ejecutada de Flutter.

El texto actual de registro es exactamente: **`"Cuenta creada. Ya podés iniciar sesión."`**. La integración debe reemplazar esa orientación incorrecta por una indicación de revisión/activación del correo; no debe alterar la respuesta JSON de backend ni afirmar que la entrega se realizó.

### 7.3 Plan condicional de Flutter

Solo si los prechecks de `flutter test`, `flutter analyze` y un build/plataforma disponible resultan ejecutables, Slice 2B puede incluir:

1. `lib/data/services/auth_api_service.dart`: agregar a `AuthApi` y `AuthApiService` métodos para solicitud, reenvío y consumo contra los paths exactos; recibir `correo` y `token`; mantener `_ensureSuccess` y el fallback seguro.
2. `lib/data/repositories/auth_repository.dart`: delegar esos métodos sin leer/escribir `CredentialStorage`.
3. `lib/ui/features/auth/view_models/auth_view_model.dart`: agregar comandos y estados mínimos de activación, sin guardar el token; mantener separado el estado de sesión.
4. `lib/ui/features/auth/views/register_screen.dart`: actualizar la orientación posterior al registro y navegar a la solicitud genérica o al login según el espacio disponible.
5. `lib/ui/features/auth/views/login_screen.dart`: si cabe, ofrecer la misma acción genérica de solicitud; no mostrar una CTA que confirme que la cuenta existe.
6. `lib/ui/features/email_verification/views/email_verification_screen.dart` y, si el presupuesto lo permite, `request_email_verification_screen.dart`: UI delgada que delega en el ViewModel, muestra confirmación/error genérico y ofrece navegación explícita a login.
7. `lib/app.dart`: agregar `/email-verification` y la ruta de solicitud como públicas, permitirlas durante restauración y no redirigirlas por ausencia de sesión. La ruta consume query una sola vez.
8. Tests existentes/nuevos de servicio, repositorio, ViewModel, router y widget según los runners actuales. No se modifica `credential_storage.dart` salvo un test negativo que demuestre que nunca recibe el token; la implementación no le agrega API.

El token se extrae del `state.uri.queryParameters['token']`, se copia a estado efímero de la pantalla/controlador, se reemplaza la ubicación por `/email-verification` sin query y se envía una única vez. Luego se elimina la referencia de memoria. No se imprime la URI, no se guarda en preferencias, cache, secure storage, logs ni estado de sesión.

### 7.4 Deep link, cold start, resume y fallback

La ruta lógica elegida es `/email-verification`; para una prueba nativa local, el scheme candidato es `roomforge://email-verification`. El `AndroidManifest.xml` solo puede recibir un `intent-filter` y `Info.plist` solo puede recibir `CFBundleURLTypes` si el build y la prueba de la plataforma están disponibles. No se prometen Universal Links, App Links, dominio, certificados, fingerprints, Team ID, AASA ni `assetlinks.json`.

La evidencia se divide así:

- **Ruta Flutter/web:** prueba de `go_router`, extracción efímera, limpieza de query y llamada HTTP, si `flutter test`/build web están disponibles.
- **Deep link cold start:** solo PASS si una app instalada recibe la URI inicial y procesa una vez en la plataforma probada.
- **Deep link resume:** solo PASS si una URI posterior al arranque llega y se procesa una vez; `go_router` por sí solo no se toma como evidencia de resume.
- **Fallback:** si el entorno no puede abrir el scheme o no hay dispositivo/emulador, se registra `N/A` o bloqueado. Una ejecución Flutter Web, si existe, se clasifica como Flutter Web, no como panel React.

La configuración `EMAIL_VERIFICATION_ACTIVATION_URL` usa una sola base por ejecución: URI nativa si se verifica el scheme, o URL web si se verifica una superficie web. Si no existe un destino verificable, el notifier queda no disponible y no se afirma entrega utilizable.

## 8. TDD estricto, validación y evidencia

Esta fase no ejecuta tests, builds, migraciones, Docker ni comandos de aplicación. La implementación deberá respetar `RED → GREEN → TRIANGULATE → REFACTOR`.

### 8.1 Secuencia obligatoria

- **RED:** adaptar primero los dobles de DI y agregar los casos de contrato, `422/410/500`, registro pendiente, login bloqueado, no sesión, fallos de notifier y ausencia de secretos.
- **GREEN:** implementar solo schemas, wiring, `request_or_resend`, mapeos, notifier y UI mínima necesarios para los tests rojos.
- **TRIANGULATE:** cruzar los fakes con la suite backend; ejecutar PostgreSQL real para migración/locks solo si está disponible; separar Mailpit real de fake; verificar Flutter/web solo con sus runners y plataformas reales.
- **REFACTOR:** limpiar duplicación y revisar excepciones/secretos después de la triangulación, antes de congelar el candidato. No cambiar contratos ni exceder el límite.

Runners previstos por el contexto del proyecto, aún no ejecutados en esta fase:

```text
.venv/Scripts/python.exe -m pytest backend/tests -q
.venv/Scripts/python.exe -m ruff check backend/app backend/tests
.venv/Scripts/pyright.exe backend/app backend/tests
.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head
flutter test                         # desde apps/cliente_mobile
flutter analyze                      # desde apps/cliente_mobile
```

Para PostgreSQL/Mailpit se comprobará primero la topología de Compose. Para el panel solo se ejecutará el runner que exista; actualmente no se afirma ninguno.

### 8.2 Evidencia por superficie

| Superficie | Evidencia requerida | Si no está disponible |
| --- | --- | --- |
| Fake backend | Tests de contrato, estados, DI, notifier y no filtración. | Puede demostrar lógica aislada, no infraestructura. |
| Backend completo | Pytest, Ruff y Pyright con comandos y resultado real. | `N/A`/bloqueado con causa; no se declara PASS. |
| PostgreSQL/Alembic | `heads/current`, upgrade, constraints, locks y carrera concurrente. | No se sustituye por fake; se registra `N/A`. |
| Mailpit | Contenedor real, mensaje visible, enlace utilizable y revisión sin secretos fuera del token necesario en el enlace. | `N/A` o fallo de entrega; nunca se presenta el fake como Mailpit. |
| Flutter | `flutter test`, `flutter analyze`, requests exactos, estados y no escritura en secure storage. | `N/A`/bloqueado por SDK o runner. |
| Flutter deep link | Build, app instalada, cold start y resume únicamente si fueron probados. | Declarar solo la plataforma realmente comprobada. |
| Panel React/Vite | Scaffold, runner, ruta y prueba real. | Actualmente `N/A`/bloqueado; no crear scaffold. |
| Sprint 3 | Artefactos ejecutados, clasificados y sin secretos. | Mantener gap documental; no crear capturas ni métricas. |

La presencia de archivos, configuración escrita, un fake, una ruta declarada o una imagen de Docker no constituye evidencia de ejecución ni PASS.

## 9. Compatibilidad, aislamiento y rollback

### Compatibilidad

- Se conserva `POST /api/v1/auth/register`; no se crea alias ni fallback a `/api/v1/auth/registro`.
- Las referencias históricas a `/api/v1/auth/registro` no se reescriben.
- `RegistroResponse`, `TokenResponse`, refresh, logout, `me`, normalización, Argon2id y hashing de refresh se mantienen.
- Las cuentas existentes no verificadas conservan sus datos y quedan bloqueadas para nuevos logins después del guard; no se marcan por migración.
- Las sesiones existentes no se revocan automáticamente.
- HU-004 conserva `Invitacion`, `activation_ttl_days`, rutas, eventos y almacenamiento propios; HU-005/HU-006 no se tocan.

### Rollback

- Slice 2A: retirar endpoints, DI, servicio de notifier, settings de SMTP y servicio Mailpit agregados por HU-003. No eliminar usuarios, sesiones ni datos de otros dominios.
- No ejecutar downgrade de `0006` si existen tokens; la migración existente continúa siendo la autoridad del esquema y no se copia ni se reescribe.
- Si hay tokens activos al retirar código, no se convierten cuentas ni se eliminan tokens automáticamente. Cualquier invalidación o limpieza requiere una operación explícita posterior.
- Una cuenta creada antes de una falla de token no se borra durante rollback; queda no verificada y puede ser reconciliada por la operación pública cuando el código vuelva a estar disponible.
- Slice 2B: retirar únicamente rutas, vistas, comandos y configuración nativa de Flutter agregados por HU-003. No tocar credenciales de sesión existentes.
- Detener Mailpit solo afecta el entorno local y no se presenta como una falla de negocio de la cuenta.
- Ningún rollback modifica `openspec/config.yaml`, `project-context.md`, cambios históricos, gitlinks, ramas, commits, remotes ni la ruta histórica documentada.

## 10. Trazabilidad y criterios de cierre

| Trazabilidad | Decisión de diseño | Verificación posterior |
| --- | --- | --- |
| `PB-003 → HU-003` | Registro crea cuenta pendiente; login exige verificación; superficies clientes son condicionales. | `201` con `correo_verificado=false`; `401` previo; login exitoso posterior. |
| `HU-003 → CU-003` | Solicitud, reenvío y consumo bajo `/api/v1/auth`; notifier desacoplado. | OpenAPI, tests de las tres rutas y flujo completo si el entorno existe. |
| `CU-003 → RF-033` | Hash, un activo, TTL 7 días, cooldown 15 minutos, tres reenvíos/24 horas, consumo único. | Tests de política, constraints y carrera PostgreSQL cuando esté disponible. |
| `RF-033 → RNF-017` | Token efímero; no password, hash o secreto en response/log/persistencia; URL limpia en cliente. | Inspección de respuestas, modelos, fake, logs disponibles y URI. |
| `HU-003 → Sprint 3` | Fake, backend, PostgreSQL, Mailpit, Flutter, panel y evidencia se clasifican por separado. | Reporte posterior con resultados reales o `N/A` justificado. |

El diseño queda listo para tasks cuando las tareas respetan estos invariantes:

- HTTP: `422` estructural, `410` para cualquier string presente no utilizable, `500` interno genérico y `200/202/201` según tabla.
- Persistencia: dos commits explícitos, notifier post-commit, cuenta no verificada ante cualquier fallo de entrega/persistencia, sin afirmación de atomicidad distribuida.
- Concurrencia: orden usuario → token, una activación efectiva y cero sesión automática.
- Slice 2A: plan de 272 líneas más 28 de reserva; máximo 300.
- Slice 2B: Flutter solo con runner/plataforma verificables; panel React `N/A` mientras no exista scaffold.
- Evidencia: ningún PASS inferido por presencia de archivos.

## 11. Riesgos y condiciones de detención

| Riesgo | Mitigación | Detener si… |
| --- | --- | --- |
| Dos commits de cuenta/token dejan una cuenta pendiente sin token tras una falla | Respuesta `500` segura, sin notifier, solicitud posterior retry-safe y sin afirmar atomicidad distribuida. | Se exige atomicidad cuenta+token dentro de 300 líneas o una transacción distribuida. |
| Persistencia confundida con token inválido | Clasificar `VerificationPersistenceError` antes de mapear estados y usar `500` exacto. | El backend exige otro contrato público incompatible con este body. |
| Contradicción estructural de consumo | Schema valida solo presencia/tipo; string presente siempre llega a la ruta `410` si no es utilizable. | Una restricción de framework obliga a exponer contenido sensible o a cambiar `422/410`. |
| Falla del proveedor SMTP | Adapter seguro, entrega posterior al commit y respuestas genéricas. | El proveedor obliga a revelar causa, correo, token o credencial. |
| Mailpit no existe en Compose o no puede levantarse | Servicio opcional mínimo y evidencia separada. | Requiere reestructurar infraestructura, secretos o un proveedor productivo. |
| No enumeración en solicitud/reenvío | Un único `202`/body para estados de negocio; `500` solo para una falla interna real. | La implementación refleja estado interno, contador o proveedor. |
| Login no verificado rompe fixtures existentes | Fixtures de éxito se vuelven explícitamente verificadas; se conserva `401` genérico. | No puede agregarse el guard antes de generar JWT/sesión. |
| Carrera concurrente no demostrable | PostgreSQL es la única evidencia de locks; fake queda separado. | No existe base/runner y la historia exige declarar la carrera como PASS. |
| Panel vacío | Resultado `N/A`; no se crea scaffold. | Afirmar web exige modificar más de la superficie existente. |
| Deep link no verificable | No se declara plataforma sin build, app instalada, cold/resume comprobados. | Para continuar se requiere prometer Universal/App Links sin prerequisitos. |
| Presupuesto | Forecast 272 + 28 de reserva para 2A y 300 para 2B; conteo authored después de cada etapa. | Slice >300, total >600 o seguridad/tests esenciales quedan fuera. |
| Revisión histórica o de otros dominios | Solo lectura del archivo archivado; paths HU-004/HU-005/HU-006 fuera. | Una corrección exige editar el cambio archivado, gitlink o configuración protegida. |

No queda una decisión de producto pendiente para pasar a tasks. Las decisiones de entorno —host/URL efectiva, ejecución Mailpit, runner Flutter y plataforma deep link— son precondiciones operativas que tasks/apply debe comprobar y reportar, no permisos para inventar disponibilidad.

## 12. Orden siguiente

1. `tasks` descompone Slice 2A y Slice 2B con los anclajes y límites de este documento.
2. Apply inicia Slice 2A en RED y realiza el precheck de Alembic, Compose y runners sin editar superficies protegidas.
3. Tras el contrato backend y su evidencia real, apply evalúa la viabilidad de Flutter; panel permanece `N/A` si no aparece un scaffold verificable.
4. Verify separa resultados fake, backend, PostgreSQL, Mailpit, Flutter, deep link, panel y Sprint 3.
5. Archive solo registra resultados realmente ejecutados.

**Estado:** diseño corregido y listo para `tasks`. No se ejecutaron tests, builds, migraciones, Docker, Mailpit, Flutter, web, commits ni cambios de código como parte de esta fase.
