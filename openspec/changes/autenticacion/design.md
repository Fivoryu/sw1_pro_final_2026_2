# Diseño — Autenticación y sesión del cliente

- **Cambio:** `autenticacion`
- **Product Backlog:** PB-002
- **Historia:** HU-002 — Iniciar sesión y mantener sesión
- **Caso de uso:** CU-002
- **Slice:** backend
- **Dominio:** `identity`
- **Requisitos cubiertos:** REQ-01..REQ-12
- **Estado:** diseño para implementación

## 1. Decisiones de diseño y límites

El slice extiende el módulo `identity` del monolito modular FastAPI existente. Reutiliza `UserRepository.buscar_por_correo`, `UsuarioGlobal`, `estado` y el protocolo/verificador Argon2id de PB-001. No agrega UI, catálogo, roles, membresías, recuperación de contraseña ni integración PostgreSQL como requisito de la suite unitaria.

### 1.1. Decisiones cerradas

- **Librería JWT:** `PyJWT` 2.x, únicamente HS256. La dependencia se declara como `PyJWT>=2.8,<3`.
- **Access:** JWT de 15 minutos, firmado con el secreto configurado. Además de `sub`, `type`, `iat` y `exp`, contiene `sid`, el UUID de la fila `sesion` a la que queda vinculado.
- **Refresh:** valor opaco generado con `secrets.token_urlsafe`; solo su SHA-256 hexadecimal se persiste en `refresh_token_hash`.
- **Autoridad de sesión:** `sesion` es la autoridad server-side para revocación, expiración absoluta e inactividad. No se adopta una estrategia stateless ni Redis.
- **Vínculo access ↔ sesión:** cada access contiene `sid`; `/auth/me` decodifica y valida la firma, busca exactamente `sesion.id = sid`, verifica que `sesion.usuario_global_id == sub` y valida la fila. No se selecciona la última sesión del usuario mediante `sub`, porque eso mezclaría sesiones concurrentes y no permitiría revocación precisa.
- **Revocación inmediata del access:** logout revoca la fila identificada por el refresh; el access asociado tiene el mismo `sid` y queda rechazado inmediatamente en `/auth/me`. Una rotación revoca la fila anterior y emite el nuevo access con el `sid` de la nueva fila.
- **Rotación:** operación atómica dentro de una transacción SQLAlchemy síncrona. El repositorio bloquea la fila anterior con `SELECT ... FOR UPDATE`, la revalida bajo el lock, la revoca y crea la nueva fila antes de hacer commit.
- **TTL:** access 15 minutos; cada refresh emitido tiene expiración propia de 7 días (`now + refresh_ttl`). La rotación no modifica la expiración del refresh anterior ni revive un refresh revocado. Por lo tanto, la continuidad activa puede emitir nuevas expiraciones de siete días, pero ningún artefacto individual supera su TTL.
- **Inactividad:** ventana deslizante server-side de 30 minutos. La condición de invalidez es `ahora > ultima_actividad + 30 minutos`; exactamente al límite todavía es válida. Una sesión inactiva se marca `revocado = true` de manera lazy al primer intento de validación y se rechaza. La limpieza física queda fuera de alcance.
- **Clock:** todas las comparaciones y emisiones temporales reciben un `Clock` inyectable que devuelve `datetime` aware en UTC. No se usa `datetime.now()` directamente en servicios ni fakes.
- **Login:** responde `200 OK`, no `201`, porque autentica y no crea un recurso direccionable por el cliente. Usa `INVALID_CREDENTIALS_MESSAGE = "Correo o contraseña inválidos"` para correo inexistente, password incorrecto y cuenta no activa.
- **Sesión inválida:** refresh, logout posterior, `/auth/me` y cualquier access ausente, malformado, expirado, revocado o inactivo usan `INVALID_SESSION_MESSAGE = "Sesión inválida o expirada"`; no se revela la causa.
- **Cuenta inactiva:** se verifica la contraseña contra el hash real cuando existe y luego se rechaza si `estado != "activo"`. Para un correo inexistente se ejecuta una verificación contra un hash Argon2id ficticio válido, reduciendo la diferencia temporal observable.
- **Payload de `/auth/me`:** `{ "id": UUID, "correo": string }`. `UsuarioGlobal` no tiene rol actualmente; no se agrega `rol: null`. La autorización por roles pertenece a otro cambio.

### 1.2. Nomenclatura del response de tokens

La spec fija el contrato JSON con `access_token`, `refresh_token` y `expira_en`. En el diseño, los términos coloquiales `access` y `refresh` refieren a esos dos campos. `expira_en` es la expiración absoluta del refresh emitido. No se agrega `expires_in` en esta fase porque REQ-01 define el cuerpo canónico y todos los requisitos usan `expira_en`; un cambio a nombres o a un TTL numérico requiere modificar la spec antes de tasks.

### 1.3. Configuración del secreto

La spec exige fail-closed y no permite un secreto comprometedor hardcodeado. Por eso `JWT_SECRET` no tiene un valor productivo por defecto: se carga desde `.env`/entorno y se valida como no vacío al construir la dependencia de tokens. Los tests inyectan explícitamente `Settings(jwt_secret="test-secret...")`. Un `.env.example` puede documentar el nombre y un placeholder, pero nunca contiene un secreto operativo.

Esto resuelve la tensión entre un "default dev" conveniente y REQ-10: el valor de desarrollo debe estar explícito en el entorno local, no embebido en el código. `APP_ENV=production` exige además un secreto provisto por el entorno; la aplicación no debe arrancar con un secreto vacío o ausente cuando se habilitan rutas de autenticación.

### 1.4. Límites

Quedan fuera del slice: familia de refresh y revocación de todas sus ramas ante reuso, detección avanzada de robo, auditoría de seguridad, job de purga, TOTP, recuperación de contraseña, autorización de recursos, roles, tenants, UI y migraciones distintas de `sesion`.

## 2. Arquitectura del slice

### 2.1. Estructura de paquetes y archivos

```text
backend/
├── app/
│   ├── core/
│   │   ├── clock.py             # ClockProtocol y SystemClock UTC
│   │   ├── config.py            # secreto JWT y TTLs configurables
│   │   ├── security.py          # Argon2id existente + hash ficticio para login
│   │   └── tokens.py            # TokenServiceProtocol y adaptador PyJWT
│   ├── db/
│   │   ├── base.py              # Base declarativa existente
│   │   └── session.py           # SQLAlchemy 2.x síncrono existente
│   ├── modules/
│   │   └── identity/
│   │       ├── router.py        # registro + login/refresh/logout/me
│   │       ├── schemas.py       # request/responses públicos
│   │       ├── service.py       # IdentityService + AuthenticationService
│   │       ├── repository.py    # usuarios + SessionRepository SQLAlchemy
│   │       └── models.py        # UsuarioGlobal + Sesion
│   └── main.py                  # composición y dependencias
├── alembic/
│   ├── env.py                   # importa todos los modelos para metadata
│   └── versions/
│       ├── 0001_crear_usuario_global.py
│       └── 0002_crear_sesion.py
├── pyproject.toml               # PyJWT 2.x
└── tests/
    ├── test_registro.py         # patrón PB-001 existente
    └── test_autenticacion.py    # fakes, clock y TestClient
```

### 2.2. Responsabilidades y dependencias

| Componente | Responsabilidad | No debe hacer |
| --- | --- | --- |
| `main.py` | Crear la app, handlers y composición de dependencias | Implementar login, consultar SQL o crear tablas |
| `core/config.py` | Leer `JWT_SECRET`, TTL de access, TTL de refresh y ventana de inactividad | Contener secretos operativos o lógica de sesión |
| `core/clock.py` | Proveer hora UTC del sistema y contrato sustituible | Dormir, congelar tiempo global o consultar DB |
| `core/tokens.py` | Firmar/verificar access, generar refresh y calcular SHA-256 | Consultar `sesion`, decidir HTTP o revocar filas |
| `identity/router.py` | Validar request, delegar casos de uso y traducir excepciones a HTTP | Ejecutar SQL, hashear passwords o decidir locks |
| `identity/schemas.py` | Validar correo/password/refresh y limitar la respuesta pública | Exponer password, hashes, ORM completo o detalles de JWT |
| `identity/service.py` | Coordinar credenciales, emisión, rotación, actividad y logout | Conocer `select`, `with_for_update` o detalles de psycopg |
| `identity/repository.py` | Encapsular consultas, transacciones, locks y estado de `sesion` | Crear JWT, conocer headers HTTP o devolver mensajes de API |
| `identity/models.py` | Mapear exactamente `usuario_global` y `sesion` | Agregar roles, tenants o columnas de access no especificadas |
| `tests/test_autenticacion.py` | Probar contrato y reglas con fakes/overrides | Abrir PostgreSQL o depender de tiempo real |

### 2.3. Composición y DI

Se conservan las dependencias existentes y se agregan:

- `get_session_repository(db)` → `SessionRepository(db)`.
- `get_token_service(settings)` → `PyJWTTokenService(settings)`, validando `JWT_SECRET`.
- `get_clock()` → `SystemClock()`.
- `get_auth_service(...)` → `AuthenticationService(user_repository, session_repository, password_hasher, token_service, clock, settings)`.

`get_identity_service` sigue componiendo el registro de PB-001. En tests, `app.dependency_overrides` reemplaza `get_auth_service`, o sus dependencias individuales, por un servicio construido con `FakeUserRepository`, `FakeSessionRepository`, `FakeTokenService` y `FakeClock`. La producción sigue usando `Session` de SQLAlchemy 2.x y `psycopg` mediante `postgresql+psycopg://`.

## 3. Diseño de datos

### 3.1. Tabla `sesion`

El modelo y la migración replican columna a columna REQ-04. `ultima_actividad` admite `NULL` por compatibilidad con el esquema lógico, pero toda sesión creada por login/refresh la inicializa; una fila con `NULL` se considera inválida y se revoca lazy al validarse.

| Columna | SQLAlchemy 2.x | PostgreSQL | Restricción/default |
| --- | --- | --- | --- |
| `id` | `UUID(as_uuid=True)` | `UUID` | PK, `server_default=gen_random_uuid()`; el servicio puede proporcionar UUID para emitir `sid` antes del flush |
| `usuario_global_id` | `UUID(as_uuid=True)` | `UUID` | NOT NULL, FK → `usuario_global.id` |
| `refresh_token_hash` | `CHAR(64)` | `CHAR(64)` | NOT NULL, UNIQUE, SHA-256 hexadecimal |
| `expira_en` | `DateTime(timezone=True)` | `TIMESTAMPTZ` | NOT NULL |
| `ultima_actividad` | `DateTime(timezone=True)` | `TIMESTAMPTZ` | NULL en esquema; siempre inicializada por los casos de uso |
| `revocado` | `Boolean` | `BOOLEAN` | NOT NULL, `server_default=false` |

Restricciones e índice:

- `UNIQUE(refresh_token_hash)`, con nombre estable `uq_sesion_refresh_token_hash`.
- `INDEX(usuario_global_id, revocado)`, con nombre estable `ix_sesion_usuario_global_revocado`.
- FK de `sesion.usuario_global_id` hacia `usuario_global.id`.
- No se agrega una columna `jti`: el UUID de sesión se transporta como `sid` y es la clave de la autoridad server-side. No se necesita una tabla de mapeo access-token → sesión.

### 3.2. Migración `0002_crear_sesion.py`

`revision = "0002"` y `down_revision = "0001"`. `upgrade()` crea únicamente `sesion`, su FK, UNIQUE e índice. No modifica `usuario_global`, no habilita extensiones nuevas y no crea otras tablas. `downgrade()` elimina únicamente `sesion`. La extensión `pgcrypto` ya es responsabilidad de `0001`.

`alembic/env.py` debe importar `UsuarioGlobal` y `Sesion` antes de exponer `Base.metadata`; esto evita que el metadata de Alembic omita modelos por imports perezosos. La revisión sigue siendo explícita y no depende de autogeneración accidental.

### 3.3. Ciclo de vida de las filas

- Login: crea una fila activa con `sid`, hash del refresh, `expira_en = now + 7 días` y `ultima_actividad = now`.
- Actividad en `/me`: conserva la fila y actualiza `ultima_actividad = now` dentro de una transacción con lock.
- Refresh: revoca la fila anterior y crea una fila nueva con nuevo `sid`, hash, expiración y actividad. La fila anterior no se elimina para que el rechazo del reuso sea observable y auditable técnicamente.
- Logout: marca la fila encontrada por hash como `revocado = true`; si no existe o ya está revocada, no cambia el contrato `204`.
- Inactividad o expiración detectada: marca `revocado = true` lazy y responde rechazo genérico. No hay job de limpieza en este cambio.

## 4. Servicio de tokens y contratos internos

### 4.1. `app/core/tokens.py`

El archivo aloja el protocolo y su adaptador, no lógica HTTP ni de repositorio:

```text
TokenServiceProtocol
  generar_refresh() -> str
  hash_refresh(refresh: str) -> str
  emitir_access(*, usuario_id, sesion_id, emitido_en, expira_en) -> str
  decodificar_access(*, token: str, ahora: datetime) -> AccessClaims

AccessClaims
  usuario_id: UUID
  sesion_id: UUID
  emitido_en: datetime
  expira_en: datetime
```

`PyJWTTokenService` usa `jwt.encode(..., algorithm="HS256")` y `jwt.decode(..., algorithms=["HS256"])`. El decode requiere `sub`, `sid`, `type`, `iat` y `exp`, rechaza `type != "access"`, firma inválida, UUIDs inválidos y timestamps imposibles. Para que la prueba de tiempo sea determinista, la verificación criptográfica de PyJWT se mantiene, pero la comparación de `exp` se ejecuta explícitamente contra `ahora` inyectado; no se confía en el reloj global del proceso.

`generar_refresh()` usa `secrets.token_urlsafe(32)` o una entropía equivalente. `hash_refresh()` devuelve únicamente `hashlib.sha256(refresh.encode("utf-8")).hexdigest()`. El valor claro solo vive en memoria durante el caso de uso y la respuesta HTTP; no se incorpora al modelo ORM, logs, excepciones ni mensajes de error.

### 4.2. Interfaces de repositorio

Se agregan al protocolo de usuarios:

```text
UserRepositoryProtocol
  buscar_por_correo(correo: str) -> UsuarioGlobal | None
  buscar_por_id(usuario_id: UUID) -> UsuarioGlobal | None
  guardar(usuario: UsuarioGlobal) -> UsuarioGlobal
```

El `SessionRepositoryProtocol` expone operaciones que preservan la frontera de persistencia:

```text
crear(usuario_global_id, refresh_token_hash, expira_en, ultima_actividad, session_id) -> Sesion
buscar_por_hash(refresh_token_hash) -> Sesion | None
buscar_por_id(session_id) -> Sesion | None
rotar_por_hash(hash_anterior, nueva_sesion, ahora, ventana) -> Sesion
validar_y_actualizar_actividad(session_id, usuario_id, ahora, ventana) -> Sesion
revocar_por_hash(refresh_token_hash) -> None
revocar(session: Sesion) -> None
```

`rotar_por_hash` es la operación que usa el servicio; no se implementa como `buscar_por_hash` seguido de `rotar`, porque ese patrón tiene una ventana TOCTOU. `buscar_por_hash` queda disponible para consultas controladas y pruebas, pero nunca autoriza por sí sola un refresh.

### 4.3. `AuthenticationService`

El servicio recibe `Clock`, `TokenServiceProtocol`, repositorios, hasher y settings. Las excepciones de dominio son internas (`InvalidCredentialsError`, `InvalidSessionError`) y el router las convierte a las constantes contractuales. Ninguna excepción contiene el token claro ni el password.

## 5. Contratos de endpoints

Los esquemas de request usan `SecretStr` para password y refresh. Pydantic valida forma antes de invocar el servicio; una entrada inválida responde `422` sin consultar credenciales ni crear/modificar sesiones.

| Endpoint | Request | Éxito | Rechazo contractual |
| --- | --- | --- | --- |
| `POST /api/v1/auth/login` | `{ "correo": EmailStr, "password": string >= 8 }` | `200` `{ "access_token": string, "refresh_token": string, "expira_en": timestamptz }` | `401` `{"detail":"Correo o contraseña inválidos"}`; `422` por schema |
| `POST /api/v1/auth/refresh` | `{ "refresh_token": string no vacío }` | `200` con el mismo esquema de par nuevo | `401` `{"detail":"Sesión inválida o expirada"}`; `422` por schema |
| `POST /api/v1/auth/logout` | `{ "refresh_token": string no vacío }` | `204` sin cuerpo, incluso si el refresh es desconocido, revocado, expirado o inactivo | `422` solo por cuerpo ausente/malformado |
| `GET /api/v1/auth/me` | `Authorization: Bearer <access_token>` | `200` `{ "id": UUID, "correo": string }` | `401` `{"detail":"Sesión inválida o expirada"}` para header ausente/malformado, JWT inválido/expirado o sesión no usable |

La ruta protegida usa `HTTPBearer(auto_error=False)` para evitar el `403` predeterminado de FastAPI y traducir ausencia/malformación a `401`. El `HTTPException` devuelve solo el `detail` contractual.

## 6. Flujo de datos y lógica de negocio

### 6.1. Login

1. Pydantic valida `correo` y `password`; una falla termina en `422`.
2. `AuthenticationService` normaliza el correo como PB-001: `strip().lower()`.
3. Busca el usuario y siempre ejecuta una verificación Argon2id: hash real si existe, hash ficticio válido si no existe.
4. Si el password no coincide, el usuario no existe o `estado != "activo"`, lanza `InvalidCredentialsError`. No se crea sesión.
5. Obtiene `now = clock.now()`, genera `session_id`, refresh opaco y su hash; calcula `access_exp = now + 15 min` y `refresh_exp = now + 7 días`.
6. Emite el access con `sub = usuario.id` y `sid = session_id`.
7. Llama a `SessionRepository.crear(...)`; el repositorio hace flush/commit. Si falla, no se devuelve el par.
8. Devuelve el par y `refresh_exp` como `expira_en`.

El UUID se genera antes de emitir el access para que el token y la fila compartan identidad aun cuando la PK tenga `gen_random_uuid()` como default server-side.

### 6.2. Refresh rotatorio

1. Pydantic valida que haya un string no vacío.
2. El servicio obtiene `now`, calcula SHA-256 del valor recibido y genera internamente un nuevo UUID, refresh, hash y expiración.
3. Emite un access candidato con el nuevo `sid`; todavía no lo devuelve.
4. `rotar_por_hash` inicia una transacción, busca el hash anterior con `with_for_update()`, verifica bajo lock `revocado`, `expira_en`, `ultima_actividad` y la ventana de 30 minutos.
5. Si es inválido, marca la fila existente como revocada cuando corresponde, hace commit de esa invalidación lazy y lanza `InvalidSessionError`.
6. Si es válido, marca la fila anterior como revocada, inserta la fila nueva y hace flush/commit de ambas operaciones en la misma transacción.
7. Solo después del commit devuelve el par nuevo. El refresh anterior nunca vuelve a ser válido.

Dos llamadas simultáneas para el mismo hash compiten por la misma fila. La primera que obtiene el lock revoca e inserta; la segunda espera, vuelve a leer la fila ya revocada y responde `401`. La unicidad del hash es una defensa adicional, no el mecanismo principal.

### 6.3. `/auth/me`

1. `HTTPBearer` extrae el bearer sin rechazar automáticamente.
2. El servicio decodifica firma y claims contra `clock.now()`. Se exige `type=access`, `sub`, `sid` y expiración vigente.
3. Busca la fila exacta por `sid` y verifica que su `usuario_global_id` coincida con `sub`.
4. `validar_y_actualizar_actividad` toma lock, comprueba `revocado=false`, `expira_en > now`, `ultima_actividad` no nula y `now <= ultima_actividad + 30 min` (igualdad permitida).
5. Si está inactiva/expirada, marca `revocado=true`, persiste y rechaza. Si es válida, actualiza `ultima_actividad=now` y persiste.
6. Busca el usuario por `sub`; si no existe, rechaza como sesión inválida. Devuelve únicamente `id` y `correo`.

Este lookup por request es intencional: es el costo necesario para que logout y la inactividad server-side invaliden un access antes de su `exp`.

### 6.4. Logout

1. Pydantic valida el cuerpo.
2. El servicio calcula el hash y llama a `revocar_por_hash`.
3. La operación es idempotente: si no hay fila o ya está revocada, no cambia la respuesta.
4. El router devuelve `204` sin cuerpo. No se consulta usuario, no se distinguen causas y no se registra el refresh claro.

## 7. Estrategia de locking y consistencia

La implementación real usa SQLAlchemy 2.x síncrono con la `Session` por request ya existente:

```text
BEGIN
  SELECT sesion
    WHERE refresh_token_hash = :old_hash
    FOR UPDATE
  validar estado, expira_en e inactividad bajo lock
  UPDATE sesion SET revocado = true WHERE id = :old_id
  INSERT sesion (... nuevo hash, nuevo sid, now ...)
COMMIT
```

El repositorio no hace un `commit` intermedio entre invalidar la fila vieja e insertar la nueva. Ante `IntegrityError` del hash único, realiza rollback; el servicio no devuelve tokens y traduce el resultado a `INVALID_SESSION_MESSAGE` cuando la causa es la carrera del refresh. Los errores de infraestructura no se silencian ni se convierten arbitrariamente en una sesión válida.

Para `/me`, la actualización de `ultima_actividad` también se hace bajo lock y commit único. Así dos requests concurrentes no pueden aceptar una fila que otra request ya revocó. La granularidad de una fila por refresh permite que un access viejo quede inválido al rotar sin revocar otras sesiones iniciadas por el mismo usuario.

En el fake se usa un `threading.RLock` alrededor de `rotar_por_hash` y `validar_y_actualizar_actividad`. No se intenta simular internamente el motor PostgreSQL: se reproduce el postulado observable de single-writer, una sola rotación exitosa y rechazo del perdedor. Una prueba de integración con PostgreSQL queda como verificación posterior del `FOR UPDATE` real.

## 8. Pruebas TDD y verificación

### 8.1. Dobles y tiempo controlado

`backend/tests/test_autenticacion.py` reutiliza el patrón de `tests/test_registro.py`, `create_app()` y `dependency_overrides`.

- `FakeClock`: conserva `current: datetime` UTC y permite `advance(timedelta(...))`. El servicio, repositorio fake y token service reciben el mismo reloj.
- `FakeUserRepository`: conserva usuarios por correo/UUID y permite estados `activo` e inactivos.
- `FakeSessionRepository`: conserva filas `Sesion` en memoria, solo guarda hashes, implementa validación lazy, revocación idempotente y rotación protegida por `RLock`. Expone las filas para comprobar que no exista el refresh claro.
- `FakeTokenService`: puede usarse para tests de orquestación; para el contrato criptográfico se usa `PyJWTTokenService` con un secreto explícito de test. En ambos casos `decodificar_access` recibe `ahora` y no depende del reloj del sistema.
- `RecordingHasher`/Argon2id real: se usa el fake para probar llamadas y el hasher Argon2id real para comprobar que el hash ficticio y el hash de usuario siguen el protocolo existente.

El test de expiración no espera quince minutos: crea el token con `iat/exp` controlados y avanza `FakeClock`; el adaptador valida `exp` contra el reloj inyectado. El test de inactividad fija `ultima_actividad` o avanza 29/31 minutos y no usa `sleep`.

### 8.2. Casos mínimos

| Caso | Verificación | REQ / CP |
| --- | --- | --- |
| Login válido | `200`, tres campos públicos, sesión activa, hash persistido igual a SHA-256(refresh) y distinto del refresh | REQ-01, REQ-03, CP-002 paso 1 |
| Password incorrecto vs. correo inexistente | mismo `401` y mismo `detail`; no se crea sesión; se ejecuta verificación en ambos caminos | REQ-02, CP-002 paso 2 |
| Cuenta no activa | mismo `401` genérico y ninguna sesión | REQ-02 |
| JWT emitido | HS256, `sub`, `sid`, `type=access`, `iat`, `exp`, TTL de 900 s | REQ-03 |
| `/me` válido | `200` con solo `id` y `correo`; `ultima_actividad` avanza | REQ-08/09, CP-002 paso 3 |
| Actividad a 29 min | sigue válida y actualiza actividad | REQ-09, CP-002 paso 3 |
| Inactividad a 31 min | `/me` y refresh responden `401`, la fila queda `revocado=true` y no se revive | REQ-06/08/09, CP-002 paso 4 |
| Refresh válido | `200`, par distinto, fila vieja revocada, fila nueva activa con nuevo `sid` y TTL | REQ-05/06, CP-002 paso 3 |
| Reuso de refresh rotado | `401` genérico, sin segundo par; el par nuevo sigue válido | REQ-05/06, CP-002 paso 5 |
| Carrera de refresh fake | dos rotaciones del mismo hash producen como máximo una fila nueva activa | REQ-05 |
| Logout | `204` sin cuerpo, fila revocada, refresh posterior `401`; repetir logout sigue en `204` | REQ-07, CP-002 paso 5 |
| `/me` inválido | ausente, malformed, firma incorrecta, `type` incorrecto, expirado, `sid` inexistente y sesión revocada responden `401` genérico | REQ-03/08 |
| Validación | correo/password/request refresh inválidos responden `422`, sin acceso a repositorio ni creación de sesión | REQ-01/06/07 |
| No exposición | ni response, fake ni logs contienen refresh claro, hash_password o password | REQ-01/03/12 |

La suite debe ejecutarse desde `backend/` con `pytest` y, para la iteración acotada, `pytest -q tests/test_autenticacion.py`. No se afirma ejecución en esta fase de diseño. Ruff/type checking se ejecutan después de la implementación sin alterar el contenido revisado.

### 8.3. Orden TDD

1. Escribir primero los casos de contrato y reglas con los fakes.
2. Implementar schemas, constantes y dependencias mínimas hasta obtener verde.
3. Implementar tokens y `sid`, verificando firma y expiración con `FakeClock`.
4. Implementar repositorio fake y servicio de login/me/logout.
5. Implementar modelo, repositorio SQLAlchemy y migración con la misma interfaz.
6. Ejecutar refactor, Ruff y la suite completa sin PostgreSQL.
7. Dejar la prueba de locking real como verificación de integración posterior, sin convertirla en requisito de los nueve casos mínimos.

## 9. Archivos a crear o modificar en apply

| Archivo | Cambio previsto |
| --- | --- |
| `backend/pyproject.toml` | Agregar `PyJWT>=2.8,<3`; conservar SQLAlchemy 2.x, psycopg, pytest y httpx |
| `backend/app/core/config.py` | Agregar secreto JWT, `access_token_ttl_seconds=900`, `refresh_token_ttl_days=7`, `session_inactivity_minutes=30`; validación fail-closed |
| `backend/app/core/clock.py` | Crear protocolo de clock y `SystemClock` UTC |
| `backend/app/core/tokens.py` | Crear protocolo, claims, hashing de refresh, generación opaca y adaptador PyJWT HS256 |
| `backend/app/core/security.py` | Exponer/centralizar verificación Argon2id ficticia para el camino de correo inexistente, sin duplicar el hasher |
| `backend/app/modules/identity/models.py` | Agregar modelo `Sesion` y tipos/índices de la tabla |
| `backend/app/modules/identity/repository.py` | Agregar `buscar_por_id`, `SessionRepositoryProtocol`, adapter SQLAlchemy, transacciones y `FOR UPDATE` |
| `backend/app/modules/identity/schemas.py` | Agregar requests de login/refresh/logout, response de tokens y response mínima de `/me` |
| `backend/app/modules/identity/service.py` | Agregar `AuthenticationService`, errores de dominio y flujo de login/refresh/logout/me |
| `backend/app/modules/identity/router.py` | Agregar las cuatro rutas, DI, `HTTPBearer(auto_error=False)` y mapeo de errores |
| `backend/app/main.py` | Mantener composición y, si corresponde, validar configuración de autenticación al arranque |
| `backend/alembic/env.py` | Importar explícitamente `UsuarioGlobal` y `Sesion` para metadata |
| `backend/alembic/versions/0002_crear_sesion.py` | Crear únicamente `sesion`, FK, UNIQUE e índice; downgrade solo de `sesion` |
| `backend/tests/test_autenticacion.py` | Crear fakes, clock controlado y casos TDD de REQ-01..REQ-12/CP-002 |
| `backend/.env.example` | Documentar `JWT_SECRET` y los TTLs sin secretos reales, si el archivo existente se incorpora al apply |

No se modifica la migración `0001` ni se agregan tablas de usuarios, roles, tenants o catálogo.

## 10. Rollout, rollback y observabilidad

### Rollout

1. Agregar PyJWT, configuración explícita y archivos de core sin cambiar el contrato de registro.
2. Implementar tests con fakes y dejar verde la suite sin PostgreSQL.
3. Aplicar `alembic upgrade head`; verificar que `0002` crea solo `sesion` y que `0001` sigue intacta.
4. Configurar `JWT_SECRET` fuera del repositorio y comprobar que el backend no habilita autenticación con secreto vacío.
5. Levantar la API y verificar OpenAPI/rutas, login, `/me`, refresh, logout y mensajes genéricos.
6. Habilitar el consumo por la futura UI; catálogo y almacenamiento cliente quedan en slices posteriores.

Los logs operativos pueden registrar evento, route, status, `sid` anonimizado o hash técnico de la sesión, y correlation id. Nunca registran access/refresh completos, passwords, hash de password ni `refresh_token_hash` en claro (el hash de sesión tampoco se devuelve al cliente).

### Rollback

- Revertir código y dependencia PyJWT sin tocar `usuario_global`.
- En una base descartable, ejecutar `alembic downgrade 0001` para retirar solo `sesion`.
- En un entorno compartido, deshabilitar las rutas y revocar sesiones activas; no eliminar filas ni cuentas destructivamente sin migración controlada.
- Si se cambia el secreto, todos los access JWT existentes dejan de validar; el cliente deberá renovar si el refresh sigue válido, o autenticarse nuevamente si las sesiones fueron revocadas.

## 11. Trazabilidad de requisitos

| Requisito | Decisión implementable | Verificación principal |
| --- | --- | --- |
| REQ-01 | Router login, schemas, Argon2id, sesión inicial y `200/401/422` | Login válido, inválido y validación |
| REQ-02 | Verificación uniforme, hash ficticio, estado activo y constante genérica | Comparación de respuestas y cuenta inactiva |
| REQ-03 | `tokens.py`, PyJWT HS256, `sid`, SHA-256 y no exposición | Decodificación, firma, hash y logs/fake |
| REQ-04 | Modelo/migración exactos, FK, UNIQUE e índice | Inspección de `0002` y prueba de metadata/integración |
| REQ-05 | Protocolos y repositorio; `rotar_por_hash` con `FOR UPDATE` | Fake single-writer y prueba real posterior |
| REQ-06 | Refresh hashado, validación, rotación y TTL por emisión | Refresh válido, expirado, inactivo y reusado |
| REQ-07 | Revocación por hash idempotente y `204` | Logout válido, desconocido y repetido |
| REQ-08 | `sid` → PK de sesión, `sub` consistente, actividad y payload mínimo | `/me` válido y variantes `401` |
| REQ-09 | `Clock`, ventana `> 30 min`, actualización y revocación lazy | Avance de 29/31 minutos |
| REQ-10 | Settings por entorno y tokens en `app/core/` | Configuración explícita, dependencia y árbol |
| REQ-11 | Separación router/service/repository/models y DI | OpenAPI, inspección estructural y overrides |
| REQ-12 | TDD con fakes, TestClient y sin PostgreSQL | Suite mínima y casos CP-002 |

## 12. Riesgos residuales y gaps

- **Costo por request:** `/auth/me` consulta y actualiza `sesion` en cada actividad válida. Es el costo aceptado para revocación inmediata e inactividad server-side; optimizarlo requeriría cambiar la semántica.
- **Relojes distribuidos:** la comparación usa el reloj del proceso y timestamps de PostgreSQL en persistencia; una futura topología multi-nodo debe garantizar UTC y sincronización razonable. Los tests controlan el clock local, no una infraestructura distribuida.
- **Reuso de refresh:** el reuso solo responde `401` y deja el evento para logging técnico; no revoca una familia completa porque no existe `familia_id` y esa conducta está fuera de alcance.
- **PostgreSQL no disponible en unit tests:** los fakes prueban el contrato y la single-writer lógica, pero no demuestran el comportamiento real de `FOR UPDATE`, tipos `CHAR(64)` o la FK. La integración de migración/locking es un GAP de entorno, no una razón para introducir PostgreSQL en REQ-12.
- **Secreto de desarrollo:** exigir un valor explícito evita un secreto público hardcodeado, pero requiere configurar `.env` o `Settings(...)` en cada entorno de test/desarrollo. Se documentará sin persistir valores reales.
- **Nomenclatura `expires_in`:** el resumen del trabajo usa `expires_in`, mientras REQ-01 y la convención de la spec fijan `expira_en`. El diseño conserva la spec como contrato autoritativo y deja la eventual compatibilidad numérica para una revisión posterior.
- **GAP-073:** responsable y fecha de aprobación siguen pendientes en la documentación del proyecto.
- **GAP-092:** la migración de este cambio cubre solo `sesion`; las restantes tablas del Sprint 1 permanecen fuera de alcance.

## Fuentes verificadas

- [Propuesta del cambio](./proposal.md), PB-002/HU-002.
- [Spec del cambio](./spec.md), REQ-01..REQ-12.
- [Diseño PB-001](../registro-cliente/design.md), patrón de FastAPI, SQLAlchemy 2.x síncrono, psycopg, fakes y `dependency_overrides`.
- `backend/app/modules/identity/router.py`, `schemas.py`, `service.py`, `repository.py` y `models.py` existentes.
- `backend/app/core/config.py`, `security.py`, `backend/app/db/base.py`, `backend/app/db/session.py` y `backend/app/main.py` existentes.
- `backend/alembic/versions/0001_crear_usuario_global.py` y `backend/alembic/env.py`.
- `backend/pyproject.toml` y `backend/tests/test_registro.py`.

No se afirma ejecución de tests ni migración en esta fase; quedan como trabajo de `sdd-apply`/`sdd-verify`.
