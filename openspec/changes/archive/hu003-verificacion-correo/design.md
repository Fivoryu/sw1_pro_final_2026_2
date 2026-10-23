# Diseño: Verificación de correo del cliente (HU-003)

- **Cambio:** `hu003-verificacion-correo`
- **Producto:** RoomForge, SW1 2026-2, Grupo #12
- **Trazabilidad:** `PB-003 → HU-003 → CU-003 → RF-033 → RNF-017 → Sprint 3`
- **Almacén:** híbrido (OpenSpec + Engram)
- **Idioma del artefacto:** español profesional
- **Límite de implementación informado:** 400 líneas modificadas por slice/revisión
- **Estado:** diseño listo para descomposición en tareas; no es evidencia de implementación

## 1. Base de diseño y clasificación de evidencia

Este diseño se basa en la propuesta aprobada (`proposal.md`), la especificación (`specs/verificacion-correo/spec.md`), sus registros Engram 3227 y 3228, y la decisión de producto Engram 3226. Se verificaron además los puntos de integración disponibles en el repositorio.

### Hechos observados

- El backend es FastAPI con SQLAlchemy 2.x síncrono, PostgreSQL, Alembic, Argon2id, PyJWT y pytest.
- La identidad existente está en `backend/app/modules/identity`; `UsuarioGlobal.correo_verificado` ya existe y tiene valor por defecto `false`.
- El router actual publica `POST /api/v1/auth/registro`, `POST /api/v1/auth/login`, refresh, logout y `GET /api/v1/auth/me`.
- `IdentityService.registrar` persiste la cuenta y `AuthenticationService.login` todavía no verifica `correo_verificado`.
- Las migraciones observadas llegan a `0005_hu005_trial_subscription.py`. HU-004 y HU-005 agregan tablas/cambios propios que no deben modificarse.
- HU-004 tiene un patrón de token hash/consumo/notificación, pero su entidad `Invitacion`, sus rutas y su `ActivationNotifier` pertenecen a otro bounded context.
- `apps/cliente_mobile` ya usa `go_router`, `http`, almacenamiento seguro, servicios, repositorios, ViewModels y pantallas de login/registro. No tiene activación ni deep link.
- `panel/` contiene únicamente un README que describe React/TypeScript/Vite; no se encontró `package.json` ni un entrypoint en el checkout inspeccionado.
- `infra/docker/compose.postgres.yml` contiene PostgreSQL y no contiene Mailpit.
- El servidor Engram no respondió durante la lectura por consulta de tópico, pero las observaciones explícitas 3226, 3227 y 3228 sí fueron recuperadas por ID. El diseño quedó persistido también en Engram como la observación 3231; el fallo de búsqueda por tópico fue operativo y no impidió la persistencia final.

### Decisiones de este diseño

Las siguientes decisiones cierran gaps técnicos sin cambiar las decisiones de producto:

1. Se crea un bounded context de verificación dentro de `identity`, con tabla y repositorio propios. No se reutiliza `Invitacion` de HU-004.
2. Se usa PostgreSQL como autoridad para tokens, cooldown, ventana y concurrencia; no se agrega Redis ni una cola distribuida para el slice local.
3. El token crudo se genera con `secrets.token_urlsafe(32)`, se hashea con SHA-256 hexadecimal y existe únicamente en memoria hasta formar el mensaje de correo.
4. La emisión y el cambio de contadores se confirman en una transacción; el correo se intenta después del commit, en primer plano. Si falla, el usuario sigue no verificado y puede usar la misma acción genérica de reintento.
5. Un reintento que necesita enviar otro mensaje genera un token nuevo, invalida el anterior y cuenta como reenvío. No se intenta reconstruir un token crudo que nunca se persistió.
6. La primera emisión no consume el contador de reenvíos, pero sí inicia el cooldown de 15 minutos y la ventana de 24 horas. Cada reintento posterior se cuenta antes de llamar al adaptador, incluso si Mailpit falla; así el fallo no permite evadir límites.
7. Las rutas públicas de solicitud/reintento devuelven siempre el mismo acuse genérico `202`, tanto si el correo no existe, está verificado, está limitado, se envía o falla Mailpit. El cuerpo incluye una acción de reintento constante, no el estado interno.
8. El registro conserva `201` y sus campos actuales, agregando un bloque de orientación a activación. El bloque no declara si la entrega tuvo éxito; la UI ofrece reintentar si el mensaje no llega. Esto evita convertir el resultado del proveedor en un mecanismo de enumeración.
9. El login conserva el error público genérico existente (`401`, `Correo o contraseña inválidos`) para credenciales inválidas, cuenta inactiva y cuenta no verificada. Solo después de validar las credenciales se intenta el reenvío automático; nunca se crea sesión para una cuenta no verificada.
10. El enlace canónico local es web (`http://localhost:5173/activar-correo?token=...`) y el mismo token se ofrece en el mensaje mediante un URI alternativo `roomforge://activar-correo?token=...`. Ambos consumen el mismo endpoint. Para un entorno publicado se podrá sustituir por App Links/Universal Links HTTPS sin cambiar el caso de uso.
11. Se agrega `EMAIL_VERIFICATION_ENFORCED=true` como interruptor operativo de emergencia, con valor predeterminado obligatorio. No es una opción de producto ni se expone al cliente; solo permite rollback coordinado sin marcar cuentas como verificadas.

## 2. Arquitectura y límites

### Capas backend

```text
HTTP/FastAPI router
    ↓ schemas y mapeo de errores públicos
IdentityService / AuthenticationService
    ↓ casos de uso y política de verificación
EmailVerificationService
    ↓ puertos TokenGenerator, Clock, Repository, Notifier
SQLAlchemy repositories + PostgreSQL       Mailpit SMTP adapter
```

- **Router:** valida la forma de la petición, invoca servicios y traduce resultados internos a respuestas públicas. Nunca construye hashes, tokens ni URLs.
- **Servicios de identidad:** conservan normalización de correo, Argon2id, credenciales, sesiones y el bloqueo de login. No contienen SQL.
- **Servicio de verificación:** es dueño de emisión, consumo, límites, estado de entrega observable internamente y construcción de mensajes. No crea sesiones.
- **Repositorio:** es dueño de transacciones, locks, `UPDATE ... RETURNING`, constraints y recuperación de errores SQL.
- **Notificador:** solo recibe un mensaje efímero con destinatario, asunto, cuerpo y URL. No conoce modelos de persistencia ni modifica cuentas.
- **Reloj:** se inyecta mediante el `ClockProtocol` existente para que TTL, cooldown y ventanas sean deterministas.

### Límites con HU-004/HU-005/HU-006

- HU-003 agrega `EmailVerificationToken` y `EmailVerificationState` en `identity`; no toca `Invitacion`, `TenantService`, `TenantRepository`, `tenant.router` ni sus migraciones.
- `activation_ttl_days` se mantiene para HU-004. HU-003 usa `email_verification_ttl_days`; no hay alias implícito entre ambos.
- La migración de HU-003 solo agrega tablas nuevas relacionadas con `usuario_global`; no agrega columnas a `tenant`, `invitacion`, `suscripcion` ni `evento_facturacion`.
- No se modifican archivos no versionados de HU-004/HU-005 ni se usan como almacenamiento, fixture o base de código de HU-003.
- HU-006 permanece fuera de alcance. Las regresiones se ejecutan únicamente sobre contratos afectados y no implican editar sus artefactos.

## 3. Módulos e interfaces backend

Los nombres de código nuevos se proponen en inglés para respetar la convención del proyecto; los nombres de tabla/columna siguen el vocabulario persistente existente en español.

### `backend/app/modules/identity/email_verification.py` (nuevo)

Responsabilidades:

- `EmailVerificationTokenGenerator` protocol con `generate() -> str`.
- `SecureEmailVerificationTokenGenerator`, basado en `secrets.token_urlsafe(32)`.
- `EmailVerificationMessage` (`recipient`, `subject`, `body`, `expires_at`), dataclass inmutable; no se persiste.
- `EmailVerificationRequestResult` interno (`attempted`, `delivery_succeeded`, `created_new_token`) sin serializar directamente.
- `EmailVerificationConsumeResult` interno (`activated`, `email`) sin serializar directamente.
- `EmailVerificationService`, construido con `EmailVerificationRepositoryProtocol`, `UserRepositoryProtocol`, `EmailVerificationNotifier`, generador, reloj y settings.

Interfaz propuesta:

```python
class EmailVerificationNotifier(Protocol):
    def send(self, message: EmailVerificationMessage) -> None: ...

class EmailVerificationRepositoryProtocol(Protocol):
    def create_initial_for_new_user(
        self, *, user: UsuarioGlobal, token_hash: str,
        issued_at: datetime, expires_at: datetime
    ) -> None: ...

    def issue_for_user(
        self, *, user_id: UUID, token_hash: str,
        issued_at: datetime, expires_at: datetime,
        count_as_resend: bool
    ) -> bool: ...

    def consume_atomically(
        self, *, token_hash: str, now: datetime
    ) -> bool: ...

    def has_unverified_user(self, user_id: UUID) -> bool: ...
```

El contrato real podrá devolver DTOs de persistencia en vez de `bool`; lo importante es que nunca devuelva el token crudo y que `issue_for_user` sea una única transacción con lock. El método de registro se implementa en el mismo `Session`/unidad transaccional que inserta el usuario para evitar una cuenta creada sin solicitud inicial si la persistencia falla.

Casos de uso del servicio:

- `register_new_user(request)`: normaliza, hashea, crea usuario no verificado, crea estado y token inicial en una transacción; después del commit intenta entregar.
- `request_activation(email, reason)`: normaliza; si el usuario no existe, está verificado o está limitado, no revela el motivo y retorna el resultado público genérico; si procede, emite y entrega.
- `auto_resend_after_valid_login(user)`: se llama únicamente después de verificar contraseña y `estado == activo`; nunca para usuario inexistente o contraseña incorrecta.
- `consume(token)`: deriva el hash y delega el consumo atómico. Si es válido, cambia `correo_verificado` a `true`; no inicia sesión.

### Cambios en `service.py`

- `IdentityService` recibe el servicio de verificación o una fachada de registro que lo contenga. El hash de contraseña se crea antes de la transacción y jamás se agrega al mensaje.
- `AuthenticationService` recibe `EmailVerificationService` opcionalmente solo para preservar la construcción de dobles durante una transición de tests; la dependencia de producción siempre se inyecta.
- En `login`, el orden es: normalizar correo → buscar usuario → verificar contraseña de forma uniforme → validar estado activo → si `correo_verificado` es falso, solicitar reenvío automático y lanzar `InvalidCredentialsError` → si es verdadero, crear sesión como hoy.
- Un fallo del notificador en el camino automático no cambia la respuesta pública ni permite crear sesión.
- `refresh`, `logout`, `me` y el contrato de sesión no se rediseñan.

### Cambios en `repository.py`

Se agregan implementaciones concretas `EmailVerificationRepository` y, si el registro necesita una unidad transaccional compartida, `UserRepository.create_with_initial_verification`. El repositorio:

- Bloquea `usuario_global` con `SELECT ... FOR UPDATE` antes de leer o modificar estado de verificación.
- Bloquea `verificacion_correo_estado` y el token activo en ese orden estable.
- Invalida el token anterior y actualiza contadores antes de insertar el nuevo.
- Traduce una violación de constraints propia a un error de concurrencia interno; no filtra SQL al router.
- Hace `rollback` ante cualquier error antes del commit.
- No hace una segunda búsqueda pública para decidir si una cuenta existe.

## 4. Modelo de datos y migración

### 4.1 `EmailVerificationState` → `verificacion_correo_estado`

Una fila por usuario que haya entrado al flujo HU-003. No se hace backfill de cuentas existentes para conservar la migración aditiva y permitir crear el estado bajo demanda.

| Columna | Tipo | Restricciones / uso |
| --- | --- | --- |
| `usuario_global_id` | UUID | PK y FK a `usuario_global.id`; `ON DELETE CASCADE` decidido para limpiar estado huérfano. |
| `ultimo_envio_en` | timestamptz | NOT NULL; inicio del cooldown después de cualquier emisión/intento. |
| `ventana_reenvio_inicio` | timestamptz | NOT NULL; ancla de la ventana de 24 horas. |
| `reenvios_en_ventana` | integer | NOT NULL DEFAULT 0; CHECK `>= 0`; solo cuenta reenvíos, no el primer envío. |

No se guarda mensaje de error SMTP, destinatario duplicado, URL ni token. El resultado de entrega se observa por eventos internos acotados.

### 4.2 `EmailVerificationToken` → `verificacion_correo_token`

| Columna | Tipo | Restricciones / uso |
| --- | --- | --- |
| `id` | UUID | PK con `gen_random_uuid()`. |
| `usuario_global_id` | UUID | NOT NULL, FK a `usuario_global.id` con `ON DELETE CASCADE`. |
| `token_hash` | CHAR(64) | NOT NULL, UNIQUE; SHA-256 hexadecimal en minúsculas. |
| `emitido_en` | timestamptz | NOT NULL, tomado del reloj inyectado. |
| `expira_en` | timestamptz | NOT NULL; `emitido_en + 7 días`. |
| `estado` | varchar(20) | NOT NULL; CHECK `activo`, `invalidado` o `consumido`. |
| `invalidado_en` | timestamptz | NULL; se completa al reemplazar token. |
| `consumido_en` | timestamptz | NULL; se completa en activación válida. |

Índices y constraints:

- `uq_verificacion_correo_token_hash` sobre `token_hash`.
- `uq_verificacion_correo_un_token_activo` como índice único parcial sobre `usuario_global_id` WHERE `estado = 'activo'`.
- Índice de búsqueda `usuario_global_id, estado` para emisión/inspección interna.
- La expiración no se expresa con un índice temporal: se verifica siempre contra el reloj en la transacción.

La regla de un token activo se garantiza en dos niveles: lock de la fila de usuario, que serializa todas las rutas, e índice parcial, que funciona como última barrera.

### 4.3 Alembic

Nuevo archivo: `backend/alembic/versions/0006_hu003_email_verification.py`, con `down_revision = "0005"` según las migraciones observadas. Antes de implementar se debe confirmar el head real del submódulo; si HU-004/HU-005 agregaran otra revisión no publicada, `0006` debe conservar la cadena vigente sin editar dichas migraciones.

`upgrade`:

1. Crear `verificacion_correo_estado`.
2. Crear `verificacion_correo_token` con sus FKs y checks.
3. Crear índices únicos y de consulta.
4. No modificar ni rellenar `usuario_global`, por lo que `correo_verificado` conserva todos sus valores.

`downgrade`:

1. Rechazar downgrade si el procedimiento operativo no ha invalidado tokens o si existe una política de despliegue que impida perder enlaces activos; la decisión final se ejecuta de forma explícita, nunca automáticamente.
2. Eliminar índices y tabla de tokens.
3. Eliminar tabla de estado.
4. No eliminar ni modificar cuentas, contraseñas, sesiones, `correo_verificado` ni tablas de HU-004/HU-005.

Un rollback de código con la migración ya aplicada puede dejar las tablas huérfanas, pero no rompe el esquema existente; su limpieza se realiza en una reversión coordinada.

## 5. Token, TTL, emisión y consumo

### Emisión

1. Normalizar el correo con la misma regla de identidad (`strip().lower()`) antes de buscar o persistir.
2. Obtener `now` en UTC mediante `ClockProtocol`.
3. Generar `raw_token = token_generator.generate()` y calcular `sha256(raw_token.encode("utf-8")).hexdigest()`.
4. Calcular `expires_at = now + timedelta(days=settings.email_verification_ttl_days)`.
5. En la transacción, bloquear usuario y estado; invalidar el token activo anterior con `invalidado_en = now`; insertar el nuevo hash en estado `activo`; actualizar el estado de envío.
6. Hacer commit.
7. Construir el enlace web y el URI app en memoria y llamar a `notifier.send` solo después del commit.
8. Liberar referencias al mensaje/token al terminar la operación; no incluirlos en logs, excepciones públicas ni DTOs.

### Consumo

1. Validar que el campo token existe y tiene entre 1 y 512 caracteres; un token alterado o con formato no reconocido se trata como no utilizable.
2. Derivar el hash SHA-256; nunca buscar por token crudo.
3. Buscar el usuario asociado al hash sin lock solo para conocer el `usuario_global_id`; si no existe, responder genéricamente.
4. Iniciar transacción y bloquear primero `usuario_global`, después la fila del token por hash.
5. Revalidar `estado == activo` y `expira_en > now` dentro de la transacción.
6. Marcar token `consumido`, establecer `consumido_en = now` y marcar `usuario_global.correo_verificado = true`.
7. Commit. Si cualquier condición falla, no se actualiza ninguna fila.
8. Retornar confirmación sin correo, ID, token ni sesión.

El orden usuario → token es obligatorio tanto para emisión como para consumo y evita el deadlock que produciría invertir el orden. Dos consumos concurrentes del mismo token se serializan; exactamente uno encuentra el token activo y el segundo recibe el tratamiento genérico de no utilizable.

### Reenvío y contadores

- Primer envío de una cuenta nueva: `reenvios_en_ventana = 0`, `ventana_reenvio_inicio = now`, `ultimo_envio_en = now`.
- Cuenta previa a HU-003 sin estado: primer token bajo demanda usa la misma inicialización y no consume reenvío.
- Reenvío posterior: si `now < ultimo_envio_en + 15 minutos`, no se emite; si `now >= ventana_reenvio_inicio + 24 horas`, se reinicia la ventana y contador antes de contar el nuevo reenvío.
- Si la ventana sigue vigente y `reenvios_en_ventana >= 3`, no se emite.
- Si procede, se incrementa `reenvios_en_ventana` y `ultimo_envio_en = now` en la misma transacción que reemplaza el token.
- El límite se comparte entre registro recuperable, solicitud pública, reintento y login automático; no existe una ruta que reinicie el contador.
- El cooldown se aplica a todos los intentos contados y también al primer envío. El `retry_after` no se devuelve para no proyectar estado interno.
- Un fallo SMTP posterior al commit conserva la emisión y el incremento. El siguiente intento, cuando sea permitido, crea otro token; nunca se persiste el valor crudo del primero.

## 6. Contrato HTTP definitivo

Todos los prefijos son los actuales: `/api/v1/auth`.

### 6.1 Registro

`POST /api/v1/auth/registro`

- Request existente: `{ "correo": EmailStr, "password": string }`.
- `201`: conserva `id`, `correo`, `estado`, `correo_verificado`, `creado_en` y agrega el bloque de orientación a activación:

```json
{
  "activacion": {
    "estado": "pendiente",
    "mensaje": "Revisá tu correo. Si no recibís el enlace, podés solicitar otro.",
    "reintento_disponible": true
  }
}
```

El bloque es constante para todo registro exitoso y no dice si Mailpit entregó el mensaje. El correo crudo, token, contador y URL no aparecen.

- `409`: conserva `Ya existe una cuenta con este correo` para el contrato vigente de registro. No se transforma en una ruta de activación.
- `422`: validación existente; el sanitizador actual no debe incluir contraseña en errores.
- La creación de usuario, estado y token se confirma antes de llamar a Mailpit. Si Mailpit falla, el caso de registro sigue siendo una cuenta creada/pediente y la respuesta mantiene el resultado de orientación genérica; la UI ofrece la acción de reintento. No se activa la cuenta ni se envía contraseña.

### 6.2 Solicitud pública

`POST /api/v1/auth/activacion/solicitar`

Request:

```json
{ "correo": "usuario@example.com" }
```

Response `202` para correo inexistente, existente verificado, existente pendiente, cooldown, máximo diario, entrega aceptada o fallo de Mailpit:

```json
{
  "estado": "solicitud_recibida",
  "mensaje": "Si el correo puede activarse, recibirás un enlace. Si no llega, podés intentarlo nuevamente más tarde.",
  "reintento_disponible": true
}
```

No contiene `user_id`, token, hash, contador, causa, `retry_after` ni resultado de proveedor. Un `422` solo corresponde a un cuerpo ausente o correo que no cumple la forma de `EmailStr`; no se usa para revelar estados de negocio.

### 6.3 Reintento explícito

`POST /api/v1/auth/activacion/reintentar`

Usa exactamente el mismo request y la misma respuesta que `solicitar`. Internamente se marca `reason=explicit_retry`, pero ambos caminos invocan la misma política y repositorio. Así, cambiar de web a Flutter o usar el login no evita límites.

La acción cliente es segura aunque el adaptador esté caído: la API confirma únicamente que recibió la solicitud, no que el correo se entregó. El usuario puede volver a intentarlo cuando el cooldown lo permita; el intento fallido ya quedó contado si correspondía.

### 6.4 Consumo

`POST /api/v1/auth/activacion/consumir`

Request:

```json
{ "token": "valor-recibido-en-el-enlace" }
```

Éxito `200`:

```json
{
  "estado": "activado",
  "mensaje": "Correo verificado. Ya podés iniciar sesión."
}
```

Token inexistente, alterado, expirado, invalidado, consumido o inconsistente: `410` con el mismo cuerpo:

```json
{ "detail": "El enlace de activación no está disponible." }
```

No se diferencia un estado del otro, no se devuelve cuenta ni se crea sesión. Una petición con campo ausente o tipo incompatible puede ser `422` por validación de estructura, sin incluir el valor recibido.

### 6.5 Login

`POST /api/v1/auth/login` conserva `200` y el `TokenResponse` para cuenta activa y verificada.

Para cuenta no verificada con contraseña correcta:

- se intenta el reenvío automático solo si la política lo permite;
- no se crea `Sesion`, access token ni refresh token;
- se responde `401 {"detail":"Correo o contraseña inválidos"}` igual que una contraseña incorrecta o correo inexistente.

La UI no depende de distinguir el caso: siempre puede ofrecer “Reenviar enlace de activación”, que llama a la solicitud pública genérica. Esta decisión evita que login se convierta en un oráculo de existencia y mantiene el contrato de error actual.

## 7. Mailpit, configuración y wiring

### Adaptador

Nuevo `backend/app/modules/identity/email_delivery.py`:

- `MailpitEmailNotifier` implementa `EmailVerificationNotifier` usando `smtplib.SMTP` y `email.message.EmailMessage`, sin incorporar una dependencia externa al `pyproject.toml`.
- Usa conexión SMTP con timeout acotado, `send_message`, cierre en `finally` y excepción interna `EmailDeliveryError` sin mensaje de proveedor en la respuesta.
- Asunto: `Verificá tu correo de RoomForge`.
- Cuerpo de texto plano mínimo: destinatario, explicación de activación, URL web y URI app alternativo, fecha de vencimiento legible. Nunca incluye contraseña, hash, settings ni secretos.
- La URL no se registra. Si una librería produce una excepción con el mensaje SMTP, se conserva solo como diagnóstico interno no serializado o se descarta.
- El servicio se construye por dependency injection en `identity.router`; los tests sustituyen el puerto por un fake.

### Settings

Agregar a `backend/app/core/config.py`, sin modificar `activation_ttl_days`:

| Setting | Alias | Default local | Uso |
| --- | --- | --- | --- |
| `email_verification_ttl_days` | `EMAIL_VERIFICATION_TTL_DAYS` | `7` | TTL HU-003. |
| `email_verification_cooldown_minutes` | `EMAIL_VERIFICATION_COOLDOWN_MINUTES` | `15` | Cooldown. |
| `email_verification_max_resends` | `EMAIL_VERIFICATION_MAX_RESENDS` | `3` | Máximo por ventana. |
| `email_verification_enforced` | `EMAIL_VERIFICATION_ENFORCED` | `true` | Kill switch operativo de emergencia. |
| `activation_web_base_url` | `ACTIVATION_WEB_BASE_URL` | `http://localhost:5173` | Host/ruta web base. |
| `activation_app_scheme` | `ACTIVATION_APP_SCHEME` | `roomforge` | URI app local. |
| `mailpit_host` | `MAILPIT_HOST` | `127.0.0.1` | Backend ejecutado en host. |
| `mailpit_smtp_port` | `MAILPIT_SMTP_PORT` | `1025` | SMTP Mailpit. |
| `mailpit_from` | `MAILPIT_FROM` | `no-reply@roomforge.local` | Remitente demo. |
| `mailpit_timeout_seconds` | `MAILPIT_TIMEOUT_SECONDS` | `5` | Timeout SMTP. |

Los valores numéricos deben validarse positivos, con `max_resends >= 1`; producción debe exigir HTTPS para la URL web. El default HTTP es exclusivamente para demo local.

### Docker

Extender `infra/docker/compose.postgres.yml` sin cambiar el servicio PostgreSQL:

```yaml
  mailpit:
    image: axllent/mailpit:v1.21.8
    ports:
      - "1025:1025"
      - "8025:8025"
```

La etiqueta de imagen es un default local elegido para reproducibilidad; debe confirmarse contra la política de imágenes disponible antes de aplicarla. El backend en host usa `127.0.0.1`; un backend containerizado usa `mailpit` mediante `MAILPIT_HOST=mailpit`. La bandeja queda en `http://localhost:8025`. No se agregan credenciales al compose.

El envío es síncrono y posterior al commit porque el objetivo es una demo local. Alternativa descartada para el primer slice: outbox + worker, que resolvería reintentos y durabilidad de entrega pero agrega tablas, proceso operativo y complejidad fuera de la historia.

## 8. Web y Flutter

### 8.1 Web

Como `panel/` no tiene entrypoint verificable, se planifica una superficie pública mínima sin asumir router existente. Si el submódulo se materializa después con un scaffold diferente, se integra en su entrypoint sin reemplazar funciones ajenas.

Ruta pública: `/activar-correo?token=<raw-token>`.

Responsabilidades:

- `ActivationPage` obtiene el token solo desde `window.location`, lo mantiene en memoria durante la llamada y elimina el query mediante `history.replaceState` inmediatamente.
- Llama `POST ${VITE_API_BASE_URL}/auth/activacion/consumir`.
- En `200`, muestra confirmación y un botón explícito “Ir al login”; no guarda token ni crea sesión.
- En `410`, red, `4xx` o `5xx`, muestra “El enlace no está disponible” y botón “Solicitar otro enlace”, sin decir inválido/expirado/consumido ni mostrar la respuesta del proveedor.
- `RequestActivationPage` recibe el correo manualmente y siempre muestra el acuse genérico `202`.
- El documento HTML envía `Referrer-Policy: no-referrer`; no se agrega analytics sobre URLs de activación. El cliente no imprime la URL completa en consola.
- El login existente del panel, si aparece durante la materialización, se conserva; la ruta de activación no requiere sesión.

### 8.2 Flutter

Se conserva la separación UI → ViewModel → Repository → HTTP service:

- `AuthApiService` agrega métodos `requestActivation`, `retryActivation` y `consumeActivation`, o se extrae una interfaz hermana `EmailVerificationApi` para no contaminar dobles no relacionados. La decisión preferida es una interfaz hermana si la cantidad de fakes crece.
- `AuthRepository` traduce respuestas a modelos de dominio y nunca guarda token de activación en `CredentialStorage`.
- `EmailActivationViewModel` maneja `initial/loading/success/invalid/failure` y expone mensajes seguros. No tiene acceso a `BuildContext`.
- `EmailActivationScreen` recibe `state.uri.queryParameters['token']`; procesa el enlace una sola vez, reemplaza la URI por `/activar-correo` y no lo muestra.
- `RequestActivationScreen` invoca la solicitud/reintento con el correo introducido y muestra siempre el resultado genérico.
- `RegisterScreen`, al recibir `201`, informa “Cuenta creada. Revisá tu correo...” y dirige a `/activar-correo/solicitar` con el correo solo como `extra` de navegación interna; si la pantalla se recarga, solicita el dato de nuevo.
- `LoginScreen` conserva el error genérico y agrega una CTA “Reenviar enlace de activación” que abre la solicitud genérica; esta CTA no prueba que la cuenta exista.
- La activación exitosa muestra confirmación y CTA “Ir al login”. No se ejecuta `login`, no se guardan credenciales y no se restaura sesión.

Rutas `go_router`:

```text
/login
/register
/activar-correo                 ← pública, query token
/activar-correo/solicitar       ← pública, formulario de correo
/home                           ← protegida como hoy
```

`redirect` debe considerar ambas rutas de activación como públicas y nunca redirigirlas al login por ausencia de sesión.

### 8.3 Deep link local

No se agrega plugin: Flutter ya usa `MaterialApp.router` y `go_router`, y el handler predeterminado de deep links es suficiente para el primer slice.

- Android: agregar un `intent-filter` BROWSABLE/VIEW en `MainActivity` para `roomforge://activar-correo` y conservar el launcher existente.
- iOS: agregar `CFBundleURLTypes` con esquema `roomforge` en `Info.plist`. No se declara Universal Link local porque no existe un dominio HTTPS verificable en el repositorio.
- Fallback: el mismo correo contiene el enlace web; si el sistema no abre la app, el navegador completa el consumo con el mismo token y endpoint.
- En una futura URL HTTPS se podrá reemplazar el filtro por Android App Links y Associated Domains, pero no se agrega `assetlinks.json` ni AASA sin dominio, paquete firmado y Team ID verificables.

## 9. Semántica de fallos y transacciones

| Falla | Estado de cuenta | Estado token/control | Respuesta pública | Acción |
| --- | --- | --- | --- | --- |
| Persistencia antes de commit | Sin cambios | Sin token nuevo | Error genérico de operación | Reintentar solicitud. |
| Mailpit falla después del commit inicial | `correo_verificado=false` | Token activo; cooldown iniciado | Registro conserva orientación pendiente; solicitud pública `202` | Reintentar después del cooldown. |
| Mailpit falla en reenvío | No verificada | Token nuevo activo, anterior invalidado; reenvío contado | `202` genérico | Esperar cooldown y volver a solicitar. |
| Token inválido/expirado/consumido | Sin cambios | Sin cambios | `410` genérico | Solicitar otro enlace. |
| Dos consumos concurrentes | Una sola cuenta pasa a verificada | Un token consumido | Uno `200`, otro `410` | Ninguna sesión automática. |
| Credencial inválida en login | Sin cambios | No se crea ni reenvía token | `401` existente | CTA genérica opcional, sin envío automático. |
| Credencial válida, cuenta no verificada | Sin sesión | Reenvío si la política permite | `401` existente | CTA genérica/manual si no llegó. |

No se hace rollback de una cuenta creada porque un correo SMTP no sea entregable: la cuenta es una operación válida y queda recuperable; el rollback de la activación solo significa no marcarla verificada.

## 10. Observabilidad segura

Eventos internos con nombres acotados:

- `email_verification.issue.initial`
- `email_verification.issue.resend`
- `email_verification.delivery.success`
- `email_verification.delivery.failure`
- `email_verification.delivery.throttled`
- `email_verification.consume.success`
- `email_verification.consume.rejected`
- `identity.login.email_unverified`

Cada evento puede incluir `operation`, `outcome`, `reason_class` acotada y un correlation/request ID si el runtime ya lo provee. No incluye correo, dominio, URL, query string, token, hash, contraseña, body, excepción SMTP completa, credencial o variable de entorno. Si se requiere distinguir usuarios para depuración, usar el UUID interno solo en un sink protegido y nunca en la respuesta; la métrica agregada no debe etiquetarse por usuario.

Los access logs deben excluir query strings de rutas de activación o aplicar redacción; el diseño no agrega middleware de logging que pueda copiar el token. Las pruebas inspeccionan `response.text`, objetos persistidos y registros capturados para confirmar ausencia de secretos.

## 11. Matriz TDD y seams de prueba

No se ejecutan pruebas en la fase de diseño. La implementación debe seguir RED → GREEN → TRIANGULATE → REFACTOR con `.venv/Scripts/python.exe -m pytest backend/tests -q` para backend.

| Caso de prueba de diseño | Requisito / aceptación | Seam |
| --- | --- | --- |
| Token aleatorio, hash y TTL exacto | Emisión, protección de secretos | Fake token generator, `FakeClock`, repositorio fake. |
| Registro deja cuenta pendiente y no envía password | Registro pendiente | Fake notifier que inspecciona mensaje; repo transaccional. |
| Notifier solo se llama después de commit | Falla de entrega / no parcialidad | Probe de commit del fake notifier. |
| Adapter falla y cuenta no se verifica | Falla recuperable | Notifier que lanza `EmailDeliveryError`. |
| Token anterior invalidado al reemitir | Nueva emisión | Fake/SQL repo; consulta de estados. |
| Cooldown bloquea solicitud | Límites | Avance del `FakeClock` por 14:59 y 15:00. |
| Tres reenvíos y cuarto bloqueado | Máximo diario | Estado de control bajo demanda. |
| Ventana reinicia a las 24 horas | Ventana temporal | `FakeClock` en borde exacto. |
| Rutas solicitud/reintento/login comparten límites | No bypass | Repo compartido y llamadas por cada entry point. |
| Mailpit no permite enumeración | Respuestas genéricas | Comparar cuerpos/status de inexistente, verificado, limitado y fallo. |
| Login no verificado no crea sesión | Bloqueo previo | `FakeSessionRepository` vacío; notifier llamado solo tras credenciales válidas. |
| Login verificado conserva TokenResponse | Compatibilidad | Regresión de `test_autenticacion.py`. |
| Credenciales inválidas no disparan correo | Anti-enumeración | Notifier sin llamadas. |
| Consume válido cambia una sola vez | Consumo único | Repositorio fake y API. |
| Consume expirado/inválido/consumido devuelve el mismo `410` | Estados genéricos | Variantes de hash/fecha/estado. |
| Dos consumes concurrentes | Concurrencia | PostgreSQL real o dos transacciones bloqueantes; exactamente un `200`. |
| Migración upgrade/downgrade aditivo | Persistencia/compatibilidad | Alembic contra Postgres; snapshot de `usuario_global` y `sesion`. |
| No hay token crudo en modelo, respuesta o log | RNF-017 | Inspección de atributos, cuerpo y caplog. |
| API Flutter forma requests exactos | Contrato cliente | `RecordingClient`. |
| Flutter no guarda token de activación | Seguridad | Fake `CredentialStorage`. |
| Flutter procesa deep link una vez | Deep link | Router/test de widget con `Uri`. |
| Éxito Flutter/web muestra confirmación y login CTA | Superficies | Widget/component test; sin sesión en dobles. |
| Error de activación habilita solicitud genérica | Fallo accionable | Fake API 410/network/202. |

Para documentación del Sprint 3, estos casos se deben vincular a `CP-031..CP-038` solo después de reconciliar la numeración vigente del modelo: la exploración registró una discrepancia entre el plan del Sprint 3 y su reporte. No se declara aquí que esos CP estén ejecutados.

Validadores posteriores previstos:

- Backend: pytest, Ruff y Pyright según `openspec/project-context.md`.
- Migración: `.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head` contra PostgreSQL.
- Flutter: `flutter test` y `flutter analyze` desde `apps/cliente_mobile`.
- Web: `npm test`/`npm run build` solo después de confirmar el package manager y scripts del submódulo `panel`; hoy no hay evidencia de esos comandos.
- Demo: Mailpit visible en `http://localhost:8025`, activación web, deep link, login bloqueado/permitido y evidencia sin token.

## 12. Mapa de archivos

### Backend

| Archivo | Cambio |
| --- | --- |
| `backend/app/core/config.py` | Nuevos settings HU-003, sin tocar `activation_ttl_days`. |
| `backend/app/modules/identity/models.py` | `EmailVerificationState` y `EmailVerificationToken`. |
| `backend/app/modules/identity/email_verification.py` | Generador, DTOs, puertos, política y casos de uso. |
| `backend/app/modules/identity/email_delivery.py` | Puerto/adaptador SMTP Mailpit y mensaje. |
| `backend/app/modules/identity/repository.py` | Repositorio transaccional, locks, emisión y consumo. |
| `backend/app/modules/identity/schemas.py` | Requests/responses de solicitud, reintento, consumo y bloque de registro. |
| `backend/app/modules/identity/service.py` | Registro pendiente, guard de login y reenvío automático. |
| `backend/app/modules/identity/router.py` | DI y tres endpoints HU-003; login conserva error genérico. |
| `backend/alembic/versions/0006_hu003_email_verification.py` | Migración aditiva posterior al head vigente. |
| `backend/tests/test_email_verification.py` | Tests unitarios/API de token, límites, entrega, consumo y contrato. |
| `backend/tests/test_registro.py` | Regresión y casos de registro con activación pendiente. |
| `backend/tests/test_autenticacion.py` | Login no verificado, auto-reenvío, no sesión y regresiones verificadas. |
| `backend/tests/test_email_delivery.py` | Fake SMTP, cuerpo sin secretos y errores seguros. |

No se cambian `backend/app/modules/tenant/*`, `0003_crear_tablas_tenant.py`, `0004_hu004_onboarding.py`, `0005_hu005_trial_subscription.py` ni sus tests.

### Infraestructura

| Archivo | Cambio |
| --- | --- |
| `infra/docker/compose.postgres.yml` | Agregar servicio Mailpit y puertos demo; conservar PostgreSQL. |

### Flutter

| Archivo | Cambio |
| --- | --- |
| `apps/cliente_mobile/lib/domain/models/email_verification_models.dart` | Modelos inmutables de solicitud/consumo/resultado. |
| `apps/cliente_mobile/lib/data/services/email_verification_api_service.dart` | Servicio HTTP e interfaz; puede integrarse en el servicio de auth si no aumenta acoplamiento. |
| `apps/cliente_mobile/lib/data/repositories/email_verification_repository.dart` | Traducción a dominio y no persistencia del token. |
| `apps/cliente_mobile/lib/ui/features/email_verification/view_models/email_verification_view_model.dart` | Estado y comandos de activación/reintento. |
| `apps/cliente_mobile/lib/ui/features/email_verification/views/email_activation_screen.dart` | Consumo del deep link, confirmación y CTA login. |
| `apps/cliente_mobile/lib/ui/features/email_verification/views/request_activation_screen.dart` | Formulario de solicitud genérica. |
| `apps/cliente_mobile/lib/app.dart` | Rutas públicas, redirect y `go_router`. |
| `apps/cliente_mobile/lib/main.dart` | Inyección de servicio/repositorio de verificación. |
| `apps/cliente_mobile/lib/ui/features/auth/views/register_screen.dart` | Estado pendiente y navegación a solicitud. |
| `apps/cliente_mobile/lib/ui/features/auth/views/login_screen.dart` | CTA de reenvío genérica. |
| `apps/cliente_mobile/android/app/src/main/AndroidManifest.xml` | Intent filter para `roomforge://activar-correo`. |
| `apps/cliente_mobile/ios/Runner/Info.plist` | URL scheme `roomforge`. |
| `apps/cliente_mobile/test/...` | Tests de API, repositorio, ViewModel, router y widgets. |
| `apps/cliente_mobile/pubspec.yaml` | Preferentemente sin dependencia nueva; confirmar deep link predeterminado en la implementación. |

### Web

El checkout actual no permite identificar entrypoint. Mapa propuesto para la superficie mínima, sujeto a confirmar el submódulo antes de escribir:

| Archivo | Cambio |
| --- | --- |
| `panel/package.json` | Crear o extender dependencias/scripts si el submódulo realmente está vacío. |
| `panel/src/features/email-verification/emailVerificationApi.ts` | Cliente fetch y contrato seguro. |
| `panel/src/features/email-verification/ActivationPage.tsx` | Ruta `/activar-correo`. |
| `panel/src/features/email-verification/RequestActivationPage.tsx` | Solicitud/reintento sin enumeración. |
| `panel/src/App.tsx` o router equivalente | Registrar rutas públicas sin romper el panel existente. |
| `panel/src/main.tsx` / `panel/index.html` | Solo si no existe scaffold; no reemplazar un entrypoint materializado. |
| `panel/src/features/email-verification/*.test.tsx` | Pruebas de token en memoria, 200/410 y CTA. |

**Gap técnico explícito:** `panel/` no ofrece hoy evidencia suficiente para afirmar el nombre del entrypoint o del package manager. Esto no es un gap de producto; la tarea de web debe comenzar verificando el submódulo y elegir el punto de integración equivalente, sin modificar HU-004/HU-005.

## 13. Slices y presupuesto de revisión

El flujo completo mínimo —persistencia, API, Mailpit, login, web, Flutter, deep links, tests y evidencia— se estima en **700–950 líneas modificadas**, sin contar archivos binarios ni documentación generada. No cabe de forma segura en el límite de 400 líneas y no debe comprimirse en una sola revisión.

Slices reviewables propuestos:

1. **Slice 1 — Núcleo backend de identidad (aprox. 280–380 líneas):** modelos, migración `0006`, settings, generador/política, repositorio, tests unitarios de emisión/consumo/límites. No altera aún el router de clientes salvo wiring mínimo; deja una base compilable.
2. **Slice 2 — API, login y Mailpit (aprox. 300–390 líneas):** schemas, endpoints, registro/login, adaptador SMTP, compose y tests contractuales/integración. Requiere confirmar el head Alembic y la configuración de demo. Este slice hace utilizable el backend pero todavía no completa superficies visuales.
3. **Slice 3 — Flutter y web (aprox. 300–420 líneas):** modelos/servicios/repositorios/ViewModels, rutas, pantallas, deep links, página web y tests de UI. Puede requerir dividirse en 3A Flutter y 3B web si el panel necesita scaffold nuevo.
4. **Slice 4 — Evidencia y documentación Sprint 3:** transcriptos, pruebas reales, demo Mailpit, trazabilidad y reporte. No se usa para ocultar cambios de producto ni resultados no ejecutados.

El primer bounded slice recomendado para `sdd-apply` es **Slice 1**. Su criterio de salida es que el núcleo sea testeable con fakes y Postgres, no que HU-003 esté completo para demo. Si el cálculo real supera 400 líneas, se divide entre 1A (modelo/migración/política) y 1B (repositorio/consumo), sin rebasar presupuesto ni tocar trabajo preexistente. La estrategia `ask-on-risk` exige confirmar el límite antes de comenzar un slice que el conteo real haga exceder 400.

## 14. Rollback, compatibilidad y activación operacional

- Antes de desplegar, aplicar migración y código en orden coordinado; la migración es aditiva y no transforma usuarios.
- Para rollback sin datos compartidos, retirar código HU-003 y luego hacer downgrade explícito; los enlaces existentes dejarán de ser válidos, pero no se eliminan cuentas.
- Si las tablas ya tienen datos, preferir dejar tablas y revocar tokens activos antes que destruirlas. No borrar `usuario_global` ni sesiones.
- Si el código debe retirarse con tablas presentes, usar temporalmente `EMAIL_VERIFICATION_ENFORCED=false` solo con decisión operativa documentada; esto restaura login legado y no marca cuentas verificadas.
- Mailpit puede detenerse solo en demo; su indisponibilidad nunca equivale a activación.
- Una cuenta verificada antes o después de la migración conserva acceso normal. Una cuenta antigua con `correo_verificado=false` queda bloqueada al nuevo login y obtiene su primer token bajo demanda en el próximo intento válido o solicitud.
- Sesiones ya existentes antes del enforcement no se revocan en este slice, porque la decisión de producto exige verificación antes de crear nuevos logins y no rediseña sesiones. Revocación retroactiva requeriría una decisión adicional.
- Refresh, logout, `/me`, tenants, membresías, trial y autorización no cambian.

## 15. Aceptación y evidencia esperada

La evidencia final debe demostrar, sin secretos:

1. Registro con `correo_verificado=false`, mensaje visible en Mailpit y ninguna contraseña en el cuerpo.
2. Login previo bloqueado sin access/refresh/sesión; credenciales inválidas sin correo.
3. Consumo válido web con confirmación y llegada al login.
4. Consumo válido Flutter mediante `roomforge://activar-correo`, confirmación y llegada al login.
5. Login posterior permitido y sesión normal.
6. Repetición, expiración e invalidación con el mismo `410` genérico.
7. Cooldown, tres reenvíos, cuarto bloqueado y reinicio de ventana, sin bypass entre rutas.
8. Fallo de Mailpit conservando cuenta no verificada y una acción segura de reintento; no se revela proveedor, cuenta ni token.
9. Carrera concurrente con una sola transición a verificado.
10. Inspección de tablas, respuestas y logs sin token crudo, hash de contraseña ni secreto SMTP/JWT.
11. Regresiones de HU-004/HU-005/HU-006 y contratos de identidad no relacionados.
12. Resultados de pytest, Ruff, Pyright, migración, Flutter/web y transcriptos de demo fechados solo cuando se ejecuten.

La matriz de trazabilidad que debe acompañar el cierre es:

```text
PB-003
  └── HU-003: verificar correo real con enlace
       └── CU-003: emitir, entregar, abrir y consumir activación
            ├── RF-033: enlace de un solo uso y reenvío acotado
            ├── RNF-017: no contraseñas por correo; secreto no persistido
            └── Sprint 3: entrega, pruebas y evidencia de la historia
```

## 16. Alternativas y tradeoffs registrados

- **Reusar `Invitacion` de HU-004:** menos tablas, pero mezcla actor, ciclo de vida y migraciones de onboarding; rechazado por aislamiento y riesgo de regresión.
- **Guardar el token crudo cifrado:** permitiría reintentar exactamente el mismo enlace, pero aumenta impacto de compromiso y contradice el requisito de persistir solo representación derivada; rechazado.
- **Reutilizar token en reintento:** sería más amable con enlaces ya entregados, pero el token crudo no puede reconstruirse tras una falla; el diseño emite uno nuevo y aplica límites explícitos.
- **Contar el primer envío dentro de los tres:** reduciría la capacidad del usuario a dos reenvíos; rechazado porque la decisión dice máximo de tres reenvíos. El primer envío sí inicia cooldown.
- **Redis para rate limit:** útil en múltiples réplicas, pero no existe en el stack observado y aumenta infraestructura; PostgreSQL con lock es suficiente para la demo y mantiene una sola autoridad.
- **Outbox/worker:** mejora entrega asíncrona y reintentos, pero requiere otra persistencia y operación; se deja para una historia de notificaciones.
- **403 específico para correo no verificado:** facilita UX, pero permite inferir credenciales válidas; se conserva `401` genérico y se ofrece una CTA pública segura.
- **App Links/Universal Links HTTPS:** mejor experiencia productiva, pero faltan dominio, certificados, fingerprints y AASA/asset links verificables; se usa esquema local con fallback web.

## 17. Gaps remanentes y cierre

- `GAP-DESIGN-001`: confirmar el head Alembic real al iniciar implementación, porque el repositorio contiene trabajo posterior a `0002` y HU-004/HU-005 no deben editarse.
- `GAP-DESIGN-002`: confirmar el scaffold/entrypoint real del submódulo `panel`; el diseño fija responsabilidades y rutas, pero no afirma un archivo inexistente como hecho.
- `GAP-DESIGN-003`: confirmar que la versión de imagen Mailpit elegida esté permitida por el entorno; el tag es un default local de diseño, no evidencia de disponibilidad.
- `GAP-DESIGN-004`: validar deep linking en las versiones Android/iOS efectivamente usadas; la ruta, URI y fallback ya están definidos, pero no se han ejecutado builds.

No quedan gaps de producto: verificación obligatoria, dos superficies, confirmación sin auto-sesión, Mailpit de demo, respuestas genéricas, reenvío automático y límites están cerrados. Los cuatro gaps restantes son verificaciones de checkout, herramienta o entorno y deben resolverse durante tareas/aplicación sin iniciar investigación externa.
