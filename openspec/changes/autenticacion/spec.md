# Spec — Autenticación y sesión del cliente (backend)

- **Cambio:** `autenticacion`
- **Product Backlog:** PB-002 · **Historia:** HU-002 — Iniciar sesión y mantener sesión · **Caso de uso:** CU-002
- **Slice:** backend (la pantalla de login de la app cliente es slice posterior del mismo PB-002)
- **Estado:** especificado (propuesta aprobada; fecha de aprobación pendiente de registro en la ficha — GAP-073)
- **Dominio OpenSpec:** `identity` (spec completa de dominio nuevo; no existe spec canónica previa en `openspec/specs/`)

## Propósito

Definir el comportamiento verificable del slice backend que permite a un cliente registrado con PB-001 iniciar sesión (`POST /api/v1/auth/login`), mantenerla mediante acceso JWT de corta duración y refresh opaco rotatorio respaldado por la tabla `sesion`, renovarla (`POST /api/v1/auth/refresh`), cerrarla (`POST /api/v1/auth/logout`) y demostrar el estado autenticado (`GET /api/v1/auth/me`), con control de inactividad server-side deslizante de 30 minutos y error de login no enumerativo. Este slice entrega el contrato y la lógica backend de HU-002 sin adelantar la UI del cliente ni el catálogo.

## Convenciones

- `DEBE` = MUST/SHALL (RFC 2119); `DEBERÍA` = SHOULD; `PUEDE` = MAY.
- Códigos de estado HTTP: `200` autenticación y renovación exitosas, `204` logout exitoso, `401` credenciales o sesión inválidas, `422` cuerpo de request malformado. `201` queda reservado a la creación de recursos (registro, PB-001); el login autentica y no crea un recurso direccionable por el cliente, por lo que responde `200`.
- Constantes de dominio exactas (patrón paralelo a `DUPLICATE_EMAIL_MESSAGE` de PB-001, sin reutilizar ese mensaje):
  - `INVALID_CREDENTIALS_MESSAGE = "Correo o contraseña inválidos"` — único cuerpo de error de login (401).
  - `INVALID_SESSION_MESSAGE = "Sesión inválida o expirada"` — único cuerpo de error de sesión en refresh, acceso protegido y reutilización (401). No se distingue la causa (revocado, expirado, inactivo, desconocido o reutilizado).
- TTLs configurables con los valores aprobados: access JWT 15 minutos; refresh 7 días como TTL absoluto por refresh emitido (sin revivir un refresh revocado); inactividad server-side 30 minutos con ventana deslizante (`ultima_actividad`).
- El refresh token es opaco y nunca se persiste, responde ni registra en texto claro; solo se guarda su hash SHA-256 hexadecimal.
- Toda afirmación trazable a fuentes del repositorio: ficha HU-002 (`docs/scrum/sprint-1/01-sprint-planning.md` §1.9), CP-002 (`docs/scrum/sprint-1/02-proceso-por-hu.md` §2.1.5.2), modelo lógico de `sesion` (`02-proceso-por-hu.md` §2.1.2.2), RF-002/RNF-006 (`docs/scrum/sprint-0-requerimientos/04-requerimientos-iniciales.md`) y el patrón S0-10 (`docs/scrum/sprint-0-requerimientos/10-patron-de-desarrollo.md`).

---

## REQ-01 — Endpoint `POST /api/v1/auth/login`

### Qué

El sistema DEBE exponer `POST /api/v1/auth/login`, que acepta un cuerpo JSON con `correo` (string con formato de correo) y `password` (string, mínimo 8 caracteres, igual política que PB-001) y responde:

- `200 OK` con cuerpo `{ "access_token": string, "refresh_token": string, "expira_en": timestamptz }` cuando las credenciales pertenecen a una cuenta activa registrada con PB-001; `expira_en` es la expiración absoluta del refresh emitido.
- `401 Unauthorized` con exactamente `Correo o contraseña inválidos` cuando el correo no existe o la contraseña es incorrecta (REQ-02); no se crea ninguna sesión.
- `422 Unprocessable Entity` cuando el cuerpo no es válido (correo malformado o contraseña fuera de política); no consulta credenciales ni crea sesión.

El endpoint DEBE verificar la contraseña con Argon2id (reutilizando el verificador de PB-001), reutilizar la búsqueda por correo normalizado de PB-001 y DEBE inicializar `ultima_actividad` de la sesión creada en la hora de emisión. La respuesta NO DEBE contener `hash_password`, el hash del refresh ni la contraseña.

### Por qué

HU-002 exige que con credenciales válidas se emitan access + refresh; el contrato API es la primera superficie entregable del backend (backend-first, mismo orden que PB-001) y la base que consumirán la futura UI de login y el catálogo.

### Criterios de aceptación verificables

1. Dado un request válido con credenciales de una cuenta activa registrada con PB-001, cuando se envía a `POST /api/v1/auth/login`, entonces responde `200` con `access_token`, `refresh_token` y `expira_en`, sin campos de contraseña ni hashes. (HU-002 CA1; Proposal CA1)
2. Dado el `access_token` de la respuesta del login, cuando se decodifica su firma, entonces es un JWT HS256 con expiración a 15 minutos e identidad `sub`, `type: "access"`, `iat` y `exp` presentes. (Proposal Decisión 2 y 3)
3. Dado el `refresh_token` de la respuesta, cuando se contrasta con lo persistido en `sesion`, entonces lo persistido es `sha256(refresh_token)` hexadecimal, distinto del valor emitido. (Proposal Decisión 2; REQ-03)
4. Dado un request con `correo` sin formato válido o `password` de menos de 8 caracteres, cuando se envía al endpoint, entonces responde `422` y no se crea sesión. (Convención PB-001)
5. Dado un request con credenciales de una cuenta inexistente, cuando se envía al endpoint, entonces responde `401` y no se crea sesión. (CP-002 paso 2)
6. Dado el login exitoso, cuando se inspecciona la fila `sesion` creada, entonces `ultima_actividad` es igual a la hora de emisión y `revocado = false`. (Proposal Decisión 5)

### Referencias

HU-002 (CA1) · RF-002 · RNF-006 · CP-002 (pasos 1 y 2) · CU-002 · PB-002 · §2.1.2.2 `sesion` · §1.9 ficha HU-002

---

## REQ-02 — Error genérico no enumerativo en login

### Qué

El sistema DEBE responder `401 Unauthorized` con el cuerpo de error que contiene exactamente `Correo o contraseña inválidos` (constante `INVALID_CREDENTIALS_MESSAGE`) para: correo inexistente, contraseña incorrecta y cuenta cuyo `estado` no es `activo`. El cuerpo y el código DEBEN ser idénticos en los tres casos, de modo que el cliente no pueda inferir si una cuenta existe ni su estado. El endpoint DEBE ejecutar la verificación de forma uniforme (por ejemplo, verificando la contraseña contra un hash ficticio cuando el correo no existe) para que tampoco el tiempo de respuesta distinga los casos.

### Por qué

El criterio de aceptación CA4 del slice exige que correo inexistente y contraseña incorrecta respondan indistinguiblemente (`Correo o contraseña inválidos`, HTTP 401), para no revelar la existencia de una cuenta. La extensión a cuentas no activas preserva la misma propiedad; el mensaje de duplicado de PB-001 no se reutiliza porque su claridad deliberada sería una filtración en login.

### Criterios de aceptación verificables

1. Dado un correo inexistente, cuando se llama a login, entonces responde `401` con exactamente `Correo o contraseña inválidos`. (Proposal CA4)
2. Dado un correo existente con contraseña incorrecta, cuando se llama a login, entonces responde `401` con exactamente `Correo o contraseña inválidos`. (Proposal CA4)
3. Dado ambos casos ejecutados en la misma suite, cuando se comparan las respuestas, entonces código y cuerpo son idénticos. (CP-002 paso 2; no enumeración)
4. Dado una cuenta cuyo `estado` no es `activo`, cuando se llama a login con sus credenciales, entonces responde `401` con el mismo mensaje genérico y no crea sesión. (Criterio de aceptación 1 del slice, solo cuentas activas; decisión anti-enumeración)
5. Dado cualquier respuesta de login (200, 401, 422), cuando se inspecciona el cuerpo, entonces no contiene `hash_password`, contraseña ni hash del refresh. (REQ-03; Proposal CA1)

### Referencias

HU-002 (CA "error genérico") · Proposal Decisión 4 y CA4 · CP-002 (paso 2) · RF-002

---

## REQ-03 — Emisión de tokens: access JWT HS256 y refresh opaco hasheado

### Qué

El sistema DEBE implementar el servicio de tokens en `app/core/` con dos artefactos:

- **Access token:** JWT firmado con HS256 (PyJWT 2.x), con payload mínimo `sub` (id del usuario global), `type: "access"`, `iat` y `exp`, con TTL de 15 minutos. El sistema DEBE rechazar un access cuya firma no valida, cuyo `type` no es `access` o cuyo `exp` pasó.
- **Refresh token:** valor opaco generado con `secrets.token_urlsafe`, no derivado del access y sin claims; el sistema DEBE persistir únicamente `sha256(refresh_token)` en hexadecimal en `sesion.refresh_token_hash` y DEBE comparar por hash. El refresh NO DEBE aparecer en texto claro en persistencia, respuestas ni logs.

El vínculo exacto entre el access JWT y la fila de `sesion` (para aplicar revocación e inactividad) DEBE quedar definido en el diseño y DEBE ser verificable por CP-002, dado que un JWT autocontenido no puede revocarse por sí solo.

### Por qué

RF-002 fija explícitamente `Argon2id + JWT/refresh`; la propuesta aprobada descarta tokens opacos para ambos (contradice RF-002) y JWT para el refresh (el diseño lógico exige `refresh_token_hash CHAR(64)`, refresh opaco hasheado). El TTL corto de 15 minutos reduce la ventana de exposición del access y obliga a renovar por refresh antes de prolongar la sesión.

### Criterios de aceptación verificables

1. Dado un login exitoso, cuando se decodifica `access_token` con el secreto configurado, entonces la firma valida, `type == "access"`, `sub` es el id del cliente y `exp - iat == 900` segundos. (Proposal Decisión 3)
2. Dado un access con `type` distinto de `access` o firma inválida, cuando se presenta a una ruta protegida, entonces se rechaza. (REQ-08)
3. Dado el refresh emitido por login, cuando se busca en `sesion` por `refresh_token_hash`, entonces el hash coincide con `sha256(refresh_token)` y no existe ninguna columna con el valor en claro. (Proposal Decisión 2; CA2 del slice)
4. Dado el flujo de login y refresh, cuando se inspeccionan los logs de aplicación, entonces no aparece ningún refresh en texto claro. (Proposal Criterios de éxito 3)
5. Dado el proyecto, cuando se inspecciona la dependencia JWT, entonces es PyJWT 2.x sin `python-jose`, `authlib` ni otra librería JWT. (Proposal Decisión 2)

### Referencias

RF-002 · Proposal Decisión 2 y 3 · §2.1.2.2 `refresh_token_hash CHAR(64) UNIQUE` · RNF-006

---

## REQ-04 — Persistencia de `sesion` y migración Alembic `0002_crear_sesion.py`

### Qué

El sistema DEBE persistir la sesión en la tabla `sesion` con exactamente el esquema lógico de §2.1.2.2:

| Columna | Tipo | Restricción |
| --- | --- | --- |
| `id` | UUID | PK, default `gen_random_uuid()` |
| `usuario_global_id` | UUID | NOT NULL, FK → `usuario_global.id` |
| `refresh_token_hash` | CHAR(64) | NOT NULL, UNIQUE (hash SHA-256 hexadecimal) |
| `expira_en` | TIMESTAMPTZ | NOT NULL |
| `ultima_actividad` | TIMESTAMPTZ | NULL |
| `revocado` | BOOLEAN | NOT NULL, default `false` |

El sistema DEBE incluir la migración Alembic `0002_crear_sesion.py` con `down_revision = "0001"` (patrón de `0001_crear_usuario_global.py`), que crea únicamente la tabla `sesion` con UNIQUE(`refresh_token_hash`) y el índice por (`usuario_global_id`, `revocado`). La migración NO DEBE crear ni modificar otras tablas; un `downgrade` desde `0002` DEBE retirar solo `sesion` sin afectar `usuario_global`.

### Por qué

La tabla `sesion` es la autoridad server-side de la sesión (revocación, expiración absoluta e inactividad, RF-002/RNF-006). El diseño lógico §2.1.2.2 fija la estructura, la unicidad del hash y el índice de búsqueda por usuario y estado; la FK preserva la continuidad deliberada con PB-001 (reutiliza `usuario_global`).

### Criterios de aceptación verificables

1. Dado un entorno con Alembic en `head`, cuando se inspecciona el esquema, entonces existe la tabla `sesion` con las columnas, restricciones, UNIQUE(`refresh_token_hash`) e índice (`usuario_global_id`, `revocado`) de la tabla anterior. (Proposal Alcance; §2.1.2.2)
2. Dado el script `0002_crear_sesion.py`, cuando se inspecciona, entonces `down_revision == "0001"` y crea únicamente `sesion`, sin tocar `usuario_global` ni las demás tablas del Sprint 1. (Proposal Alcance)
3. Dado un entorno descartable, cuando se ejecuta `downgrade` hasta `0001`, entonces la tabla `sesion` desaparece y `usuario_global` permanece intacta. (Proposal Rollback)
4. Dado un login que crea sesión dos veces, cuando se inspeccionan los hashes persistidos, entonces cada sesión tiene `refresh_token_hash` único (nunca colisión ni reemplazo por el UNIQUE). (Proposal Decisión 2)
5. Dada la migración, cuando se verifica la FK, entonces `sesion.usuario_global_id` referencia `usuario_global.id`. (Proposal Alcance)

### Referencias

RF-002 · RNF-006 · §2.1.2.2 `sesion` · GAP-092 (deuda: resto de las 14 tablas) · Proposal (Alcance, Rollback)

---

## REQ-05 — `SessionRepository`: operaciones de sesión

### Qué

El sistema DEBE exponer un `SessionRepository` (protocolo + adaptador de persistencia, patrón de PB-001) que soporte al menos:

- **crear**(`usuario_global_id`, `refresh_token_hash`, `expira_en`, `ultima_actividad`) → fila nueva no revocada.
- **buscar_por_hash**(`refresh_token_hash`) → fila de sesión o ausencia; la búsqueda es por el hash SHA-256, nunca por el valor en claro.
- **rotar**(sesión) → revoca la sesión recibida e inserta la nueva en la misma transacción.
- **revocar**(sesión) → marca `revocado = true`.
- **actualizar_actividad**(sesión) → actualiza `ultima_actividad` al momento actual.
- **rechazar** sesiones inválidas: la validación de una sesión DEBE considerar inválida (y por tanto no usable ni renovable) toda sesión `revocado = true`, con `expira_en` pasado o con `ultima_actividad` anterior a la ventana de inactividad (REQ-09).

La rotación DEBE ejecutarse como operación transaccional y única: dos rotaciones concurrentes sobre el mismo refresh DEBEN producir como máximo un par válido y el refresh anterior DEBE quedar revocado y rechazado (no reutilizable). El sistema DEBERÍA rechazar la creación con un `refresh_token_hash` duplicado sin dejar estados parciales.

### Por qué

CP-002 y los criterios 2, 3 y 5 del slice exigen rotación con invalidación del anterior, actividad deslizante y rechazo del refresh reutilizado. La tabla `sesion` es la única autoridad de sesión (sin Redis ni estrategia stateless, fuera de alcance), por lo que el repositorio concentra la semántica revocable.

### Criterios de aceptación verificables

1. Dado un login exitoso, cuando se llama a `crear`, entonces la fila existe con `revocado = false`, hash único y `ultima_actividad` inicializado. (REQ-01 CA6)
2. Dado un refresh rotado, cuando se consulta `buscar_por_hash` con el hash del refresh anterior, entonces la fila existe con `revocado = true`. (Proposal Decisión 5)
3. Dado un refresh rotado, cuando se usa el refresh anterior, entonces se rechaza como sesión inválida (REQ-06). (Proposal Decisión 2)
4. Dada una sesión sin actividad durante más de 30 minutos, cuando se valida, entonces se rechaza y `actualizar_actividad` no la revive. (CP-002 paso 4; Proposal Decisión 3)
5. Dadas dos llamadas concurrentes a `rotar` sobre el mismo refresh, cuando termina la transacción, entonces el hash antiguo está revocado y solo el par emitido por una de ellas es válido. (Proposal Riesgo "carrera de rotación")

### Referencias

CP-002 · Proposal Decisión 5 y Riesgos · §2.1.2.2 `sesion` · Patrón repository de PB-001 (`backend/app/modules/identity/repository.py`)

---

## REQ-06 — Endpoint `POST /api/v1/auth/refresh` (rotación)

### Qué

El sistema DEBE exponer `POST /api/v1/auth/refresh`, que acepta el refresh token (opaco) en el cuerpo y responde:

- `200 OK` con un par nuevo `{ "access_token", "refresh_token", "expira_en" }` cuando la sesión es válida (hash conocido, no revocada, `expira_en` futuro y dentro de la ventana de inactividad). El refresh recibido DEBE quedar revocado en la misma transacción (rotación) y la nueva fila DEBE heredar o actualizar `ultima_actividad` al momento de la renovación.
- `401 Unauthorized` con exactamente `Sesión inválida o expirada` para refresh desconocido, revocado, reutilizado, expirado o inactivo; el cuerpo NO DEBE distinguir la causa y NO DEBE emitir tokens nuevos.
- `422 Unprocessable Entity` cuando el cuerpo no es válido.

La renovación válida DEBE contar como actividad para el control de inactividad (actualiza `ultima_actividad`), pero NO DEBE extender `expira_en` de un refresh ya emitido: la expiración absoluta de 7 días aplica por refresh emitido y un refresh expirado no revive.

### Por qué

HU-002 exige "refresh rotado y revocable (tabla `sesion`)" y el criterio 2 del slice exige que el refresh anterior quede invalidado y su reutilización rechazada. El refresh de 7 días permite continuidad sin reautenticar, limitando la vida absoluta del artefacto de renovación.

### Criterios de aceptación verificables

1. Dado un refresh válido dentro de la ventana, cuando se llama a refresh, entonces responde `200` con un par nuevo distinto del anterior. (HU-002 CA1; CP-002 paso 3)
2. Dado el refresh anterior de una rotación exitosa, cuando se reutiliza en refresh, entonces responde `401` con `Sesión inválida o expirada` y no emite tokens. (Proposal CA2)
3. Dado un refresh con `expira_en` pasado, cuando se llama a refresh, entonces responde `401` con el mensaje genérico y no se renueva. (Proposal Decisión 3)
4. Dado un refresh de una sesión sin actividad durante más de 30 minutos, cuando se llama a refresh, entonces responde `401` y no se renueva. (CP-002 paso 4)
5. Dado un refresh de una sesión ya revocada por logout, cuando se llama a refresh, entonces responde `401` con el mensaje genérico. (CP-002 paso 5)
6. Dado un refresh válido, cuando se llama a refresh y luego se inspecciona `sesion`, entonces el hash anterior está revocado y existe una fila nueva con nuevo hash y `ultima_actividad` actualizada. (Proposal Decisión 5)

### Referencias

HU-002 (CA1) · CP-002 (pasos 3–5) · Proposal CA2 y Decisión 3 y 5 · RF-002

---

## REQ-07 — Endpoint `POST /api/v1/auth/logout`

### Qué

El sistema DEBE exponer `POST /api/v1/auth/logout`, que acepta el refresh token (opaco) en el cuerpo y DEBE revocar la sesión activa correspondiente (`revocado = true`). El endpoint DEBE responder:

- `204 No Content` sin cuerpo cuando el refresh tiene formato válido, independientemente de si la sesión existía, estaba ya revocada, expirada o inactiva (logout idempotente y no enumerativo).
- `422 Unprocessable Entity` solo cuando el cuerpo no tiene un refresh con formato válido.

El endpoint NO DEBE devolver información que permita confirmar si otro refresh pertenece a una cuenta, ni emitir tokens. Un refresh revocado por logout DEBE ser rechazado por `POST /api/v1/auth/refresh` con el error genérico de REQ-06.

### Por qué

HU-002 exige un refresh revocable y el criterio 5 del slice exige que el refresh activo quede revocado y su reutilización responda como sesión inválida. El 204 idempotente evita que el logout se use como oráculo de existencia de sesiones.

### Criterios de aceptación verificables

1. Dado un refresh válido, cuando se llama a logout y luego a refresh con el mismo refresh, entonces el logout responde `204` y el refresh responde `401` con `Sesión inválida o expirada`. (CP-002 paso 5; Proposal CA5)
2. Dado el logout exitoso, cuando se inspecciona la fila, entonces `revocado = true`. (Proposal Decisión 5)
3. Dado un refresh desconocido o ya revocado, cuando se llama a logout, entonces responde `204` igualmente, sin distinguir. (Proposal Decisión 5: no confirmar pertenencia)
4. Dado un cuerpo sin refresh o malformado, cuando se llama a logout, entonces responde `422`. (REQ-01 convención)
5. Dado logout repetido sobre la misma sesión, cuando se ejecuta dos veces, entonces ambas respuestas son `204` y no se produce error. (Idempotencia, REQ-07 Qué)

### Referencias

CP-002 (paso 5) · Proposal CA5 y Decisión 5 · HU-002 (CA1: refresh revocable)

---

## REQ-08 — Endpoint `GET /api/v1/auth/me` (ruta protegida)

### Qué

El sistema DEBE exponer `GET /api/v1/auth/me` como ruta protegida mínima que exige un access JWT válido (header `Authorization: Bearer <access_token>`) y responde:

- `200 OK` con la identidad de la sesión válida: `{ "id": uuid, "correo": string }` del `usuario_global` autenticado.
- `401 Unauthorized` con el cuerpo genérico (REQ-06) o el equivalente de credenciales ausentes, cuando el access falta, está malformado, tiene firma inválida, `type` incorrecto, `exp` pasado, o está asociado a una sesión revocada, expirada o inactiva (vínculo con `sesion` según REQ-03). El cuerpo NO DEBE distinguir la causa de rechazo.

Toda actividad autenticada válida en esta ruta DEBE aplicar el control de inactividad deslizante (REQ-09): si la sesión está dentro de la ventana, el sistema DEBE actualizar `ultima_actividad`; si está fuera, DEBE rechazar la petición. Esta ruta NO DEBE adelantar catálogo, permisos ni membresías (fuera de alcance).

### Por qué

El criterio 6 del slice exige una ruta protegida que devuelva la identidad de una sesión válida y rechace credenciales ausentes, malformadas, expiradas o asociadas a una sesión inválida. Es la demostración mínima del estado autenticado que consumirán las pantallas posteriores.

### Criterios de aceptación verificables

1. Dado un access válido de una sesión activa, cuando se llama a `/auth/me`, entonces responde `200` con el `id` y `correo` del cliente. (Proposal CA6)
2. Dado un request sin header de autorización o con token malformado, cuando se llama a `/auth/me`, entonces responde `401`. (Proposal CA6)
3. Dado un access firmado con un secreto distinto o con `type` distinto de `access`, cuando se llama a `/auth/me`, entonces responde `401`. (REQ-03 CA2)
4. Dado un access expirado (más de 15 minutos), cuando se llama a `/auth/me`, entonces responde `401`. (REQ-03; Proposal CA6)
5. Dado un access válido de una sesión revocada por logout o inactiva, cuando se llama a `/auth/me`, entonces responde `401`. (Proposal CA6; REQ-09)
6. Dado un access válido dentro de la ventana, cuando se llama a `/auth/me` y luego se consulta `ultima_actividad`, entonces la marca se actualizó al momento de la llamada. (CP-002 paso 3)

### Referencias

Proposal CA6 · CP-002 (pasos 3 y 4) · RF-002 · HU-002 (CA: inactividad 30 min)

---

## REQ-09 — Inactividad server-side deslizante de 30 minutos

### Qué

El sistema DEBE aplicar la regla de sesión por inactividad de RNF-006/RF-002 con ventana deslizante de 30 minutos basada en `sesion.ultima_actividad`:

- `ultima_actividad` DEBE inicializarse en la emisión (login) y DEBE actualizarse cuando ocurre actividad autenticada válida — acceso a ruta protegida o renovación válida — dentro de la ventana.
- Una sesión DEBE considerarse inválida cuando `ahora > ultima_actividad + 30 minutos` (sin actividad en la ventana), además de cuando está revocada o `expira_en` pasó. Una sesión inactiva NO DEBE poder renovarse ni continuar; el cliente DEBE autenticarse nuevamente.
- La ventana NO DEBE extender la expiración absoluta (`expira_en`); la inactividad es deslizante pero el TTL del refresh es absoluto por refresh emitido (REQ-06).
- La invalidación por inactividad DEBE ocurrir server-side al validar la sesión (rechazo lazy); la limpieza física programada de sesiones queda fuera de alcance.

### Por qué

RNF-006 fija "sesión por inactividad de 30 minutos" y CP-002 (pasos 3 y 4) demanda que la actividad quede considerada para el control (ventana deslizante, no fija) y que más de 30 minutos sin actividad invalide la sesión. El diseño lógico ya contiene `ultima_actividad` para esta regla.

### Criterios de aceptación verificables

1. Dada una sesión con actividad autenticada a los 29 minutos, cuando se valida, entonces permanece activa y `ultima_actividad` se actualiza. (CP-002 paso 3)
2. Dada una sesión sin actividad durante 31 minutos, cuando se usa su refresh o un access asociado en `/auth/me`, entonces se rechaza con el error genérico y no se renueva. (CP-002 paso 4)
3. Dada una sesión recién creada por login, cuando se consulta, entonces `ultima_actividad` está inicializada a la emisión. (REQ-01 CA6)
4. Dada una renovación válida, cuando se consulta la nueva fila, entonces su `ultima_actividad` quedó actualizada y su `expira_en` corresponde al nuevo refresh (7 días), sin revivir el anterior. (REQ-06 CA6; Proposal Decisión 3)
5. Dado un refresh expirado aunque con actividad reciente dentro de la ventana, cuando se valida, entonces se rechaza: la inactividad no revive ni extiende el TTL absoluto. (REQ-06 CA3)

### Referencias

RNF-006 · RF-002 · CP-002 (pasos 3 y 4) · §2.1.2.2 (limpieza por inactividad 30 min) · Proposal Decisión 3

---

## REQ-10 — Configuración de seguridad y servicio de tokens en `app/core/`

### Qué

El sistema DEBE agregar los settings configurables — leídos de `.env`/variables de entorno, nunca hardcodeados — para: secreto JWT (sin valor por defecto comprometedor en el código y validado al arranque), TTL del access (default 15 minutos), TTL del refresh (default 7 días) y ventana de inactividad (default 30 minutos). El servicio de tokens (firma/verificación JWT, generación de refresh opaco y cálculo del hash SHA-256) DEBE vivir en `app/core/` y DEBE inyectarse por protocolo/DI al módulo de identidad; la lógica de tokens NO DEBE dispersarse en el router ni en el módulo de identidad de forma ad hoc.

### Por qué

La propuesta fija los valores como configurables para ajustarlos sin cambiar el contrato, exige el secreto fuera del código y ubica el servicio de tokens en `app/core/` para que no quede acoplado a un módulo de dominio; la validación de configuración mitiga el riesgo de secreto ausente o débil.

### Criterios de aceptación verificables

1. Dado `.env` sin secreto JWT, cuando arranca la aplicación, entonces falla con error de configuración (no arranca con secreto vacío o default). (Proposal Riesgo "exposición de secretos")
2. Dado un entorno con un secreto JWT distinto, cuando se firma y verifica un access, entonces la verificación usa el secreto configurado y rechaza firmas del otro. (REQ-03 CA2)
3. Dado el código del slice, cuando se busca el secreto, TTLs o ventana de inactividad, entonces no aparecen como constantes hardcodeadas. (S0-10; Proposal Decisión 3)
4. Dado el árbol de `app/core/`, cuando se inspecciona, entonces existe el servicio de tokens con firma/verificación JWT, generación de refresh y hash SHA-256, sin lógica de endpoints. (Proposal Alcance)
5. Dado `pyproject.toml`, cuando se inspecciona, entonces PyJWT 2.x está declarado como dependencia. (REQ-03 CA5)

### Referencias

Proposal Decisión 3 y Riesgos · S0-10 (configuración por entorno) · RNF-006 · RF-002

---

## REQ-11 — Estructura del módulo según patrón S0-10

### Qué

El sistema DEBE organizar el slice siguiendo el patrón S0-10 del monolito modular FastAPI: los endpoints `POST /api/v1/auth/login`, `POST /api/v1/auth/refresh`, `POST /api/v1/auth/logout` y `GET /api/v1/auth/me` DEBEN registrarse bajo el prefijo `/api/v1` (extendiendo el router de identidad de PB-001, que ya sirve `/api/v1/auth/registro`), con separación de responsabilidades router/schemas/service/repository/models, protocolos de repositorio y servicio inyectados por DI (`dependency_overrides` en pruebas), y manejo de errores consistente con el patrón de constantes de PB-001. El modelo `Sesion` DEBE replicar columna a columna la migración de REQ-04. La búsqueda por correo de login DEBE reutilizar `UserRepository.buscar_por_correo` y la verificación Argon2id de PB-001, sin duplicarlos en este slice.

### Por qué

S0-10 fija el monolito modular por dominios y la configuración por entorno; mantener la misma estructura de PB-001 desde el primer slice evita deuda y deja el contrato listo para la UI del cliente y el catálogo.

### Criterios de aceptación verificables

1. Dado el arranque de la aplicación, cuando se consulta el OpenAPI, entonces las cuatro rutas `/api/v1/auth/{login,refresh,logout,me}` están disponibles. (REQ-01/06/07/08; S0-10)
2. Dado el árbol del módulo de identidad, cuando se inspecciona, entonces existen `router.py`, `schemas.py`, `service.py`, `repository.py` y `models.py`, con el modelo `Sesion` y sin lógica de persistencia en `router.py`. (S0-10; REQ-05)
3. Dado el código de login, cuando se inspecciona, entonces reutiliza el repositorio y el verificador Argon2id de PB-001 (sin copias). (Proposal Áreas afectadas: Identity)
4. Dado `app/core/`, cuando se inspecciona, entonces aloja el servicio de tokens sin duplicar su lógica en el módulo de identidad. (REQ-10)
5. Dado un entorno de pruebas, cuando la app usa `dependency_overrides`, entonces los fakes reemplazan repositorio y servicio sin tocar producción. (REQ-12)

### Referencias

S0-10 · Proposal (Áreas afectadas: Identity, Core/configuración) · REQ-06 de PB-001 (estructura de módulo)

---

## REQ-12 — Pruebas unitarias TDD sin PostgreSQL

### Qué

El sistema DEBE incluir pruebas unitarias con pytest + `TestClient` que cubran los cinco pasos de CP-002 y la rotación del refresh, usando fakes de persistencia y `dependency_overrides` (patrón de `tests/test_registro.py` de PB-001). DEBEN existir al menos 9 casos: (1) login válido emite access + refresh; (2) credenciales inválidas no distinguen correo inexistente de contraseña incorrecta (mismo código y cuerpo); (3) actividad autenticada antes de 30 minutos mantiene la sesión y actualiza `ultima_actividad`; (4) más de 30 minutos sin actividad invalida la sesión y exige autenticación; (5) logout revoca el refresh y su reutilización es rechazada; (6) rotación: el refresh anterior reutilizado responde como sesión inválida; (7) me rechaza access ausente, malformado, expirado y de sesión inválida; (8) ningún refresh aparece en claro en respuestas (ni en la persistencia del fake); (9) el 401 de login y el 401 de sesión usan exactamente sus mensajes constantes. Los seis criterios de aceptación del slice DEBEN tener cobertura reproducible. Las pruebas NO DEBEN depender de una instancia PostgreSQL real.

### Por qué

El criterio de éxito de la propuesta exige pruebas TDD reproducibles en verde para los seis criterios de aceptación y cobertura completa de CP-002; el entorno PostgreSQL/Docker de integración sigue siendo deuda del Sprint 1 (riesgo declarado), por lo que la suite unitaria debe correr sin servicios externos.

### Criterios de aceptación verificables

1. Dado el entorno con dependencias de desarrollo instaladas, cuando se ejecuta `pytest`, entonces los 9 casos mínimos corren y pasan en verde, sin PostgreSQL. (Proposal Criterios de éxito 1; Riesgos)
2. Dado el caso "login válido", cuando se ejecuta, entonces verifica `200`, presencia de `access_token`, `refresh_token` y `expira_en`, y que el hash persistido por el fake es SHA-256 del refresh. (CP-002 paso 1; REQ-01/03)
3. Dado el caso "no enumeración", cuando se ejecuta, entonces compara cuerpo y código de correo inexistente vs. contraseña incorrecta y ambos son `401` + `Correo o contraseña inválidos`. (CP-002 paso 2; REQ-02)
4. Dado el caso "inactividad", cuando el fake fija `ultima_actividad` a 31 minutos antes, entonces `/auth/me` y refresh responden rechazo genérico. (CP-002 paso 4; REQ-09)
5. Dado el caso "logout", cuando se revoca y reutiliza el refresh, entonces la reutilización responde `401` con `Sesión inválida o expirada`. (CP-002 paso 5; REQ-07)
6. Dado el caso "rotación", cuando se usa el refresh anterior después de un refresh exitoso, entonces responde `401` genérico y el par nuevo sigue siendo válido. (Proposal CA2; REQ-06)
7. Dado un entorno sin PostgreSQL (CI o máquina sin Docker), cuando se ejecuta la suite, entonces corre sin requerir servicios externos. (Proposal Riesgos)

### Referencias

CP-002 · Proposal (Criterios de éxito, Riesgos) · S0-10 (pruebas) · Patrón `tests/test_registro.py` de PB-001

---

## Matriz de trazabilidad

| REQ | Comportamiento verificable | HU-002 CA | RF / RNF / CP | Fuente documental |
| --- | --- | --- | --- | --- |
| REQ-01 | POST /api/v1/auth/login con 200/401/422, access + refresh + expiración | CA1 | RF-002, RNF-006, CP-002 pasos 1–2 | 01-sprint-planning §1.9; 02-proceso-por-hu §2.1.5.2 |
| REQ-02 | Error genérico `Correo o contraseña inválidos` (constante), 401 no enumerativo | CA "error genérico" | CP-002 paso 2 | Proposal Decisión 4 y CA4 |
| REQ-03 | Access JWT HS256 15 min + refresh opaco hasheado SHA-256; nunca en claro | CA1 | RF-002, RNF-006 | Proposal Decisión 2 y 3; §2.1.2.2 |
| REQ-04 | Tabla `sesion` (UUID, FK, CHAR(64) UNIQUE, TIMESTAMPTZ, revocado) + migración `0002` | CA1 | RF-002, RNF-006 | 02-proceso-por-hu §2.1.2.2; GAP-092 |
| REQ-05 | SessionRepository: crear/buscar/rotar/revocar/actividad/rechazo; rotación transaccional | CA1 | CP-002 pasos 3–5 | Proposal Decisión 5 y Riesgos |
| REQ-06 | POST /api/v1/auth/refresh: rotación, revocación del anterior, rechazo genérico | CA1 | CP-002 pasos 3–5, CA2 | Proposal CA2, Decisión 3 y 5 |
| REQ-07 | POST /api/v1/auth/logout: 204 idempotente, revoca refresh, no enumerativo | CA1 | CP-002 paso 5, CA5 | Proposal CA5, Decisión 5 |
| REQ-08 | GET /api/v1/auth/me: protegida, identidad, rechazo 401 genérico | CA inactividad | CP-002 pasos 3–4, CA6 | Proposal CA6 |
| REQ-09 | Inactividad sliding server-side 30 min vía `ultima_actividad` | CA inactividad | RNF-006, RF-002, CP-002 pasos 3–4 | 04-requerimientos-iniciales; §2.1.2.2 |
| REQ-10 | Settings JWT/TTLs/ventana por entorno; servicio de tokens en `app/core/` | — | S0-10 | Proposal Decisión 3 y Riesgos |
| REQ-11 | Estructura S0-10, router `/api/v1`, DI por protocolo, reuso PB-001 | — | S0-10 | 10-patron-de-desarrollo; Proposal Áreas afectadas |
| REQ-12 | pytest + TestClient + fakes: 9 casos mínimos, CP-002 completo, sin PostgreSQL | CA1 | CP-002, PB-049 | Proposal Criterios de éxito y Riesgos |

## Riesgos y gaps abiertos para la implementación

- **Decisión de código HTTP del login (cerrada en esta spec):** `200 OK` — el login autentica y no crea un recurso direccionable por el cliente; `201` queda reservado a la creación (registro, PB-001). Si el equipo prefiere `201` por analogía de "sesión creada", debe cambiarse aquí antes de tasks, no en la implementación.
- **Vínculo access JWT ↔ `sesion`:** un JWT autocontenido no puede revocarse por sí solo; el diseño (fase siguiente) DEBE fijar cómo `/auth/me` y `/auth/refresh` resuelven la sesión (p. ej. `sub` → sesión vigente) para aplicar revocación e inactividad. Sin esa definición, CA6 y el paso 4 de CP-002 no son verificables.
- **Mensaje de sesión inválida (decisión de esta spec):** se introduce `INVALID_SESSION_MESSAGE = "Sesión inválida o expirada"` para refresh/me/reutilización; la propuesta no lo fijaba. Confirmar con producto antes de tasks si se desea otro texto.
- **Cuenta no activa en login (asumido):** la propuesta solo garantiza no enumeración entre correo inexistente y contraseña incorrecta; esta spec extiende el 401 genérico a cuentas con `estado != "activo"` (y sugiere verificación contra hash ficticio para igualar tiempos). PB-001 solo crea cuentas `activo`, así que el caso es defensivo.
- **Carrera de rotación:** la estrategia exacta de locking (transaccional/única) queda para el diseño; la spec fija el resultado observable (un solo par válido, anciano revocado).
- **Escritura por request:** actualizar `ultima_actividad` en rutas protegidas agrega un UPDATE por actividad; aceptado para el primer slice, optimización por lotes diferida (proposal Riesgos).
- **TTL de 7 días confirmado por refresh emitido:** la spec fija TTL absoluto por refresh emitido (no por familia, no revive revocados); la propuesta lo marcó como confirmación de producto pendiente — si producto decide familia completa, REQ-06/REQ-09 cambian.
- **GAP-073:** responsable de implementación y pruebas aún sin asignar; fecha de aprobación de la propuesta pendiente de registro.
- **GAP-092 / entorno:** la migración `0002` y la integración real con PostgreSQL siguen siendo deuda del Sprint 1 (solo la tabla `sesion` se cubre aquí); los tests unitarios no requieren PostgreSQL (REQ-12), pero la prueba de migración real queda para el entorno de integración.
- **Nota de formato OpenSpec:** la spec se entrega en la ruta plana `openspec/changes/autenticacion/spec.md` (instrucción del orquestador, mismo patrón que PB-001) como spec completa de dominio nuevo; al archivar podrá sembrar `openspec/specs/identity/spec.md` y no puede archivarse en silencio ignorando esa forma plana.
