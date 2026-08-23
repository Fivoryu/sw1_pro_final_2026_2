# Diseño — Registro de cliente con correo y contraseña

- **Cambio:** `registro-cliente`
- **Product Backlog:** PB-001
- **Historia:** HU-001 — Registro con correo (modo pruebas)
- **Caso de uso:** CU-001
- **Slice:** backend
- **Dominio:** `identity`
- **Requisitos cubiertos:** REQ-01..REQ-07
- **Estado:** diseño para implementación

## 1. Decisiones de diseño y límites

El slice se implementa como un módulo de identidad dentro del monolito modular FastAPI existente como estructura inicial. El repositorio contiene actualmente el esqueleto de `backend/`, pero no código funcional; por lo tanto, el primer paso de implementación incluye el bootstrap de la aplicación, configuración, sesión de base de datos, Alembic y pruebas.

Decisiones cerradas:

- El endpoint es `POST /api/v1/auth/registro`.
- El correo se normaliza en el servicio con `strip()` y `lower()` antes de consultar unicidad y antes de persistir.
- La unicidad efectiva se apoya en el valor ya normalizado y en `UNIQUE(correo)` de PostgreSQL.
- La contraseña solo exige ocho caracteres como mínimo en este modo de pruebas; no se agregan reglas de mayúsculas, números o símbolos.
- El hash se genera con Argon2id mediante `argon2-cffi` y se persiste únicamente en `hash_password`.
- La cuenta se crea con `estado = 'activo'` y `correo_verificado = false`.
- La respuesta pública se construye con un esquema que no contiene `hash_password` ni `password`.
- La migración inicial crea únicamente `usuario_global`; no crea `sesion`, tenant, membresías, permisos ni otras tablas del Sprint 1.
- No se agrega una clave de idempotencia al request. La idempotencia del efecto consiste en que un correo normalizado solo puede producir una cuenta; los reintentos posteriores responden `409` y no agregan filas.

Fuera de alcance: login, JWT, refresh, logout, sesiones, TOTP, verificación real de correo, tenants, membresías, permisos, UI móvil, S3, SQS y worker 3D. La verificación real será parte de RF-033 en Sprint 3.

## 2. Arquitectura del slice

### 2.1. Estructura de paquetes y archivos

La implementación prevista es:

```text
backend/
├── app/
│   ├── main.py
│   ├── core/
│   │   ├── config.py          # Settings de pydantic-settings y .env
│   │   └── security.py        # Fábrica/adaptador de PasswordHasher Argon2id
│   ├── db/
│   │   ├── base.py            # DeclarativeBase y metadata
│   │   └── session.py         # engine, sessionmaker y get_db
│   └── modules/
│       └── identity/
│           ├── __init__.py
│           ├── router.py       # Superficie HTTP /auth/registro
│           ├── schemas.py      # Request, response y validaciones Pydantic
│           ├── service.py      # Caso de uso de registro
│           ├── repository.py   # Lectura/escritura de usuario_global
│           └── models.py       # Modelo SQLAlchemy UsuarioGlobal
├── alembic/
│   ├── env.py
│   └── versions/
│       └── <revision>_crear_usuario_global.py
├── alembic.ini
├── tests/
│   └── unit/
│       └── modules/
│           └── identity/
│               ├── test_service.py
│               └── test_router.py
├── pyproject.toml             # Dependencias runtime y dev
└── .env.example               # Variables sin secretos reales
```

El árbol sigue S0-10: el router no contiene consultas ni reglas de persistencia; el servicio coordina el caso de uso; el repositorio encapsula SQLAlchemy; el modelo representa la tabla; la configuración y la sesión son transversales.

### 2.2. Responsabilidades y dependencias

| Componente | Responsabilidad | No debe hacer |
| --- | --- | --- |
| `main.py` | Crear la aplicación, registrar handlers y montar el router bajo `/api/v1` | Crear tablas con `create_all()` o contener reglas de registro |
| `config.py` | Leer URL de DB y parámetros de Argon2id desde `.env`/variables de entorno | Contener credenciales en código |
| `security.py` | Construir `PasswordHasher(type=Type.ID, ...)` con parámetros de settings | Registrar contraseñas o hashes |
| `db/base.py` | Declarar `DeclarativeBase` y exponer metadata para Alembic | Ejecutar migraciones al importar la aplicación |
| `db/session.py` | Crear engine/sesiones y proveer `get_db()` para FastAPI | Compartir una sesión global entre requests |
| `identity/router.py` | Recibir el request, invocar el servicio y traducir excepciones a HTTP | Normalizar, hashear o ejecutar SQL |
| `identity/schemas.py` | Validar forma/tipo/longitud del request y definir la respuesta pública | Incluir `hash_password` en el response model |
| `identity/service.py` | Normalizar, verificar duplicado, hashear y orquestar el alta | Conocer detalles de SQLAlchemy o devolver datos sensibles |
| `identity/repository.py` | Consultar y guardar `UsuarioGlobal`, confirmar la transacción y traducir `23505` | Decidir el contrato HTTP |
| `identity/models.py` | Mapear exactamente `usuario_global` | Añadir columnas de sesiones, tenant o membresía |

### 2.3. Integración con FastAPI

`main.py` expone una fábrica `create_app()` para permitir pruebas aisladas y crea la instancia de aplicación para ejecución normal. La composición es:

1. `create_app()` registra el handler sanitizado de `RequestValidationError`.
2. Incluye `identity.router` con `prefix="/api/v1"`.
3. `identity.router` usa un prefijo propio `/auth`; su operación es `/registro`.
4. FastAPI resuelve `get_identity_service()` mediante dependencias: settings → `get_db()` → `UserRepository` → `IdentityService`.
5. `get_db()` abre una sesión por request, la entrega al repositorio y la cierra en `finally`.
6. La aplicación no crea tablas automáticamente. El esquema se prepara con Alembic antes de arrancar el entorno integrado.

Resultado de la composición: `POST /api/v1` + `/auth` + `/registro` = `POST /api/v1/auth/registro`.

### 2.4. Configuración y sesión de base de datos

`app/core/config.py` usa `pydantic-settings` 2.x con `BaseSettings` y `SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")`. Como mínimo, el contrato de configuración contiene:

- `DATABASE_URL`, con una URL PostgreSQL compatible con el driver seleccionado, por ejemplo `postgresql+psycopg://...`.
- `ARGON2_TIME_COST`.
- `ARGON2_MEMORY_COST`.
- `ARGON2_PARALLELISM`.
- `ARGON2_HASH_LEN`.
- `ARGON2_SALT_LEN`.
- `APP_ENV` u otros valores no sensibles necesarios para el arranque.

Los valores reales viven en `.env` o en variables del entorno de ejecución; `.env.example` solo documenta nombres y valores de desarrollo no sensibles. `get_settings()` se cachea en runtime y se puede reemplazar en tests mediante dependency override.

La sesión usa SQLAlchemy 2.x síncrono para mantener el primer slice pequeño y facilitar dobles de repositorio:

- `create_engine(settings.database_url, ...)`.
- `sessionmaker(bind=engine, class_=Session, autoflush=False, expire_on_commit=False)`.
- `get_db()` como generador de FastAPI que garantiza el cierre de la sesión.
- El repositorio ejecuta `flush`/`commit` y hace `rollback` antes de traducir una violación de unicidad.

S3, SQS, Floci y AWS no participan en este flujo; permanecen en las fronteras de infraestructura definidas por S0-09 y S0-10.

### 2.5. Referencia del diagrama de componentes

| Diagrama | Tipo | Sección del modelo | Estado |
| --- | --- | --- | --- |
| Componentes del slice de registro de cliente | **Component** | 2.1.4.1 — Diagrama de Componentes | Referencia de diseño; no se embebe imagen |

Relaciones que deberá representar el diagrama **Component** cuando se cree en el artefacto visual del proyecto: cliente HTTP → FastAPI `main` → `identity.router` → `identity.service` → `identity.repository` → sesión SQLAlchemy → PostgreSQL `usuario_global`; `identity.service` consume el adaptador Argon2id y settings alimenta la sesión y el hasher. Este documento conserva solamente el tipo y la relación textual, conforme a la convención de no insertar imágenes.

## 3. Diseño de datos

### 3.1. Modelo lógico implementado

Se implementa exactamente la parte de `usuario_global` fijada en S1-02 §2.1.2.2:

| Columna | SQLAlchemy 2.x | PostgreSQL | Restricción/default |
| --- | --- | --- | --- |
| `id` | `UUID(as_uuid=True)` | `UUID` | PK, `server_default=gen_random_uuid()` |
| `correo` | `String(255)` | `VARCHAR(255)` | NOT NULL, UNIQUE |
| `hash_password` | `String(255)` | `VARCHAR(255)` | NOT NULL |
| `estado` | `String(20)` | `VARCHAR(20)` | NOT NULL, default `'activo'` |
| `correo_verificado` | `Boolean` | `BOOLEAN` | NOT NULL, default `false` |
| `creado_en` | `DateTime(timezone=True)` | `TIMESTAMPTZ` | NOT NULL, default `now()` |

El modelo declarativo `UsuarioGlobal` usa `Mapped[...]` y `mapped_column(...)`. Los defaults de identidad y tiempo son defaults del servidor, no valores calculados por el router; así PostgreSQL conserva la autoridad de los estados y timestamps.

La normalización produce un correo canónico antes de consultar y guardar. Por eso `UNIQUE(correo)` es case-insensitive en el comportamiento del sistema aunque la columna sea `VARCHAR`: nunca se persiste una variante en mayúsculas. No se agrega `citext`, un índice alternativo ni una segunda restricción porque el contrato de S1-02 fija `UNIQUE(correo)`.

No se agregan columnas de borrado físico, tenant, membresía, permisos, sesiones, auditoría ni verificación de correo. `estado` permite la futura desactivación prevista por RNF-009 sin introducir un delete en este slice.

### 3.2. Extensión y migración Alembic

Alembic se inicializa en el backend con `alembic init alembic`. `alembic/env.py` importa `Base.metadata` y `UsuarioGlobal` para que la revisión sea explícita y no dependa de autogeneración accidental.

La primera revisión tiene `down_revision = None` y realiza solamente:

1. Habilitar `pgcrypto` si el entorno aún no lo tiene, para disponer de `gen_random_uuid()`.
2. Crear la tabla `usuario_global` con las seis columnas anteriores.
3. Crear la restricción única de `correo`.

La extensión no es una tabla de dominio; la única tabla creada por la revisión es `usuario_global`. El `downgrade` elimina esa tabla en entornos descartables y no elimina `pgcrypto`, porque una extensión puede ser compartida por futuras migraciones. No se incluyen `sesion` ni las demás tablas del Sprint 1. Esto cubre el slice inicial de **GAP-092**, no el gap completo de las migraciones del Sprint 1.

Operaciones previstas:

```text
alembic upgrade head
alembic downgrade base   # solo entorno descartable o rollback controlado
```

### 3.3. Dependencias de implementación

Dependencias runtime previstas:

- `fastapi` y servidor ASGI seleccionado por el bootstrap.
- `pydantic[email]` y `pydantic-settings`.
- `sqlalchemy>=2`.
- `psycopg` para PostgreSQL.
- `alembic`.
- `argon2-cffi`.

Dependencias de desarrollo previstas en el apply:

- `pytest`.
- `httpx` para el cliente HTTP de pruebas/TestClient.

## 4. Contrato API

### 4.1. Request

`identity.schemas.RegistroRequest` contiene:

```json
{
  "correo": "Usuario@Example.com",
  "password": "password"
}
```

Contrato de campos:

- `correo`: `EmailStr` de Pydantic, requerido, con límite máximo compatible con `VARCHAR(255)`. La forma validada no se persiste directamente: el servicio aplica `strip()` y `lower()`.
- `password`: `SecretStr` de Pydantic, requerido, mínimo de 8 caracteres. El valor se extrae únicamente dentro del servicio para hashearlo. No se aplica `strip()`, truncamiento ni cambio de caracteres; espacios internos y caracteres especiales válidos se conservan exactamente.

El modelo no agrega reglas de complejidad. La validación de forma y longitud ocurre antes de invocar el caso de uso. Para garantizar que una respuesta 422 no revele `password`, el handler de `RequestValidationError` debe eliminar campos `input` y contextos que puedan contener valores, o responder con un detalle sanitizado que conserve el campo y el tipo de error sin el valor recibido.

### 4.2. Response 201

`identity.schemas.RegistroResponse` es un esquema de salida independiente del modelo ORM:

```json
{
  "id": "uuid",
  "correo": "usuario@example.com",
  "estado": "activo",
  "correo_verificado": false,
  "creado_en": "2026-08-23T12:00:00Z"
}
```

Campos:

- `id`: UUID generado por PostgreSQL.
- `correo`: correo canónico en minúsculas y sin espacios extremos.
- `estado`: valor inicial `activo`.
- `correo_verificado`: `false`.
- `creado_en`: timestamp con zona horaria.

El esquema no declara `password` ni `hash_password`. La respuesta se construye por mapeo explícito desde la entidad, no por serialización indiscriminada del ORM.

### 4.3. Errores

| Situación | HTTP | Cuerpo contractual |
| --- | --- | --- |
| Correo malformado o password menor a 8 | `422` | Error de validación Pydantic sanitizado, sin password ni `input` |
| Correo ya existente, detectado por pre-check o por `23505` | `409` | `{"detail":"Ya existe una cuenta con este correo"}` |

La cadena `Ya existe una cuenta con este correo` es exacta y se centraliza como constante del dominio para no variar entre el pre-check y la ruta de carrera. Los errores de base de datos no relacionados con la restricción de correo no se convierten en `409`; se propagan a un handler genérico sin detalles internos.

## 5. Lógica de negocio y flujo de datos

### 5.1. Caso de uso `registrar`

El router recibe el request y delega a `IdentityService.registrar(...)`. El flujo es:

1. **Validar:** FastAPI/Pydantic valida `EmailStr` y la longitud mínima de `SecretStr`. Si falla, responde `422` y no se ejecuta el servicio ni se guarda una fila.
2. **Normalizar:** el servicio convierte el correo a `str(correo).strip().lower()`. La misma entrada normalizada dos veces produce el mismo valor canónico. La contraseña queda intacta.
3. **Verificar duplicado:** el servicio consulta `repository.buscar_por_correo(correo_normalizado)`. Si encuentra una cuenta, lanza `DuplicateEmailError` antes de hashear y responde `409`.
4. **Hashear:** el servicio obtiene temporalmente el valor de `SecretStr` y usa un `PasswordHasher` configurado con `Type.ID`. Argon2id genera el salt y devuelve el hash codificado. El plaintext no sale del proceso de servicio ni se entrega al repositorio.
5. **Insertar:** el servicio crea `UsuarioGlobal` con correo normalizado, hash, `estado='activo'` y `correo_verificado=False`; los defaults de `id` y `creado_en` los completa PostgreSQL. El repositorio hace `add`, `flush`, `commit` y `refresh`.
6. **Responder:** el router mapea solo los campos públicos al `RegistroResponse` y devuelve `201`.

### 5.2. Duplicados, carrera e idempotencia

El pre-check reduce trabajo y permite la respuesta rápida para duplicados conocidos, pero no es la autoridad de unicidad. Dos requests concurrentes pueden pasar el pre-check; la restricción `UNIQUE(correo)` decide cuál inserción gana.

El repositorio captura `sqlalchemy.exc.IntegrityError`, ejecuta `rollback()` y examina el estado SQL de PostgreSQL (`23505`) junto con la restricción de correo. Solo en ese caso lanza `DuplicateEmailError`; el router traduce la excepción al `409` contractual. La cuenta ganadora permanece única y la request perdedora no deja una transacción abierta ni una fila parcial.

El comportamiento de reintento es de efecto idempotente: el primer request crea una cuenta; repetirlo con cualquier combinación de mayúsculas o espacios extremos encuentra el mismo correo canónico o recibe la misma violación única y devuelve `409`. No se realiza un segundo insert, no se reintenta automáticamente y no se crea tenant/membresía.

### 5.3. Seguridad y logging

- Argon2id es la única representación persistida de la contraseña.
- El hasher se configura desde settings; no se hardcodean credenciales ni parámetros operativos de entorno.
- No se loguean `password`, `SecretStr` desenmascarado, `hash_password` ni el correo completo.
- Los logs pueden registrar evento, resultado HTTP, duración, correlation/request id y nombre de restricción; no deben registrar el texto de una `IntegrityError`, porque su detalle podría incluir el correo.
- El handler 409 usa el mensaje contractual sin incluir el correo recibido.
- El handler 422 no devuelve el valor de entrada; en particular, no devuelve la contraseña corta.
- No se envía correo de verificación y no se registra ningún enlace de activación en este slice.

## 6. Interfaces internas

Las dependencias se inyectan para que el caso de uso sea testeable sin PostgreSQL:

```text
UserRepositoryProtocol
  buscar_por_correo(correo: str) -> UsuarioGlobal | None
  guardar(usuario: UsuarioGlobal) -> UsuarioGlobal

PasswordHasherProtocol
  hash(password: str) -> str
  verify(password: str, encoded_hash: str) -> bool

IdentityService
  registrar(request: RegistroRequest) -> UsuarioGlobal
```

`UserRepository` es el adaptador SQLAlchemy de `UserRepositoryProtocol`. En pruebas se usa un fake que conserva una colección en memoria y puede simular tanto un duplicado detectado en `buscar_por_correo` como una excepción de carrera en `guardar`. El contrato HTTP queda en el router y no se filtra hacia el repositorio.

## 7. Pruebas de diseño

### 7.1. Estructura y estrategia

Las pruebas unitarias se ubican en `backend/tests/unit/modules/identity/` y no requieren una instancia PostgreSQL real. Se usan dobles del repositorio, un hasher Argon2id real o controlado según el caso, y overrides de dependencias de FastAPI para el router.

Casos mínimos:

| Caso | Verificación | REQ |
| --- | --- | --- |
| Registro válido | `201`, UUID, correo normalizado, `activo`, `correo_verificado=false`, timestamp y una sola llamada de guardado | REQ-01, REQ-02, REQ-05, REQ-07 |
| Correo inválido | `422`, handler sanitizado y repositorio sin lectura/escritura de alta | REQ-01, REQ-07 |
| Contraseña corta | `422`, no se crea cuenta y no se llama al hasher | REQ-01, REQ-03, REQ-07 |
| Duplicado exacto | `409` con `Ya existe una cuenta con este correo`, sin segundo guardado | REQ-01, REQ-07 |
| Duplicado con mayúsculas/espacios | mismo `409`, consulta con el valor canónico y cantidad de cuentas sin cambios | REQ-02, REQ-07 |
| Hash persistido | hash diferente del plaintext y `argon2.PasswordHasher.verify(...)` exitoso; una contraseña diferente falla | REQ-04, REQ-07 |
| Respuesta pública | ningún response `201`, `409` o `422` contiene `hash_password` ni la contraseña | REQ-04, REQ-07 |
| Carrera de unicidad | fake/repository simula `23505`; se hace rollback y se devuelve el mismo `409` | REQ-01, REQ-02, REQ-05 |

Los cinco criterios de aceptación de la propuesta quedan cubiertos por los casos de registro válido, cuenta activa, duplicados, hash/response pública y validaciones. La prueba de 422 inspecciona además que el cuerpo no contenga la contraseña enviada.

### 7.2. Ejecución

`pytest` y `httpx` se agregarán como dependencias de desarrollo durante `sdd-apply`; no se afirma ejecución en esta fase de diseño. Con el entorno instalado, desde `backend/` se ejecutará:

```text
pytest
pytest -q tests/unit/modules/identity
```

La integración real con PostgreSQL y la validación transaccional contra Docker/Floci se mantiene como trabajo posterior del entorno SPK-05/PB-048. La suite unitaria debe correr sin servicios externos, como exige REQ-07.

## 8. Archivos a crear o modificar en apply

| Archivo | Cambio previsto |
| --- | --- |
| `backend/pyproject.toml` o manifiesto equivalente | Dependencias FastAPI, Pydantic, SQLAlchemy, psycopg, Alembic, argon2-cffi, pytest y httpx según runtime/dev |
| `backend/app/main.py` | Fábrica FastAPI, handler 422 sanitizado e inclusión del router `/api/v1` |
| `backend/app/core/config.py` | Settings desde `.env`/entorno |
| `backend/app/core/security.py` | Adaptador/fábrica Argon2id |
| `backend/app/db/base.py` | Base declarativa y metadata |
| `backend/app/db/session.py` | Engine, sessionmaker y dependencia `get_db` |
| `backend/app/modules/identity/models.py` | Entidad `UsuarioGlobal` exacta |
| `backend/app/modules/identity/schemas.py` | Request/response y validaciones Pydantic |
| `backend/app/modules/identity/repository.py` | Pre-check, persistencia, rollback y traducción de `23505` |
| `backend/app/modules/identity/service.py` | Caso de uso de registro |
| `backend/app/modules/identity/router.py` | `POST /auth/registro`, status codes y mapeo de excepciones |
| `backend/alembic.ini`, `backend/alembic/env.py` | Bootstrap y metadata de Alembic |
| `backend/alembic/versions/<revision>_crear_usuario_global.py` | Migración inicial únicamente de `usuario_global` |
| `backend/.env.example` | Nombres de configuración sin secretos |
| `backend/tests/unit/modules/identity/test_service.py` | Casos del servicio y dobles de repositorio |
| `backend/tests/unit/modules/identity/test_router.py` | Contrato HTTP y ausencia de datos sensibles |

No se modifican las tablas o módulos de otras áreas del Sprint 1.

## 9. Despliegue, rollout y rollback

### Rollout

1. Agregar dependencias y archivos de bootstrap sin crear tablas desde el arranque de FastAPI.
2. Crear `.env` local a partir de `.env.example` y configurar `DATABASE_URL` y parámetros Argon2id por entorno.
3. Ejecutar `alembic upgrade head` contra el PostgreSQL del entorno.
4. Levantar la API y verificar el contrato HTTP con la suite unitaria; la prueba integrada real queda condicionada a la disponibilidad del entorno Docker/Floci.
5. Habilitar el endpoint para el slice backend. La app cliente y el cliente OpenAPI generado se integran en un slice posterior.

La migración es aditiva respecto de un backend vacío y crea únicamente `usuario_global`. No requiere S3, SQS ni cambios de infraestructura AWS.

### Rollback

- Revertir el commit de código/dependencias mediante commits convencionales separados por unidad de trabajo.
- En una base descartable, ejecutar `alembic downgrade base` para quitar `usuario_global`.
- Si ya existen cuentas, no ejecutar una eliminación destructiva en un entorno compartido: deshabilitar la ruta y conservar la tabla hasta definir una migración controlada.
- No eliminar `pgcrypto` como parte del downgrade.

## 10. Trazabilidad, convenciones y gaps

| Elemento de diseño | Trazabilidad |
| --- | --- |
| Endpoint y contratos 201/409/422 | REQ-01, HU-001, RF-001, CU-001 |
| Normalización y unicidad | REQ-02, BR-001, S1-02 §2.1.2.2 |
| Política de password | REQ-03, HU-001 CA1 |
| Argon2id y respuesta segura | REQ-04, HU-001 CA4, RF-002, RNF-006 |
| Tabla y migración | REQ-05, S1-02 §2.1.2.2, GAP-092 |
| Módulo FastAPI y configuración | REQ-06, S0-10, S0-09 |
| Suite reproducible | REQ-07, PB-049, S0-10 |

Convenciones que se conservan:

- Documentación y este diseño en español.
- IDs estables PB-001, HU-001, CU-001, REQ-01..07, RF/BR/RNF existentes; no se reciclan IDs.
- `GAP-092` permanece abierto para las migraciones restantes del Sprint 1; este cambio cubre solo la tabla inicial.
- `GAP-073` permanece como responsable de implementación y pruebas sin asignar.
- La referencia de diagrama es **Component** de §2.1.4.1; no se embeben imágenes.
- Commits con Conventional Commits y una unidad de trabajo revisable por TASK asignada durante la fase de tareas.
- No se hardcodean URLs, credenciales, endpoints ni parámetros de entorno.

## Fuentes verificadas

- [Spec aprobada del cambio](./spec.md), REQ-01..REQ-07.
- [Propuesta del cambio](./proposal.md).
- Exploración SDD persistida en Engram, topic `sdd/registro-cliente/explore` — leída como insumo de esta fase.
- [Diseño lógico y patrón de Sprint 1](../../../docs/scrum/sprint-1/02-proceso-por-hu.md), §2.1.1, §2.1.2.2, §2.1.3, §2.1.4.1.
- [Patrón de desarrollo S0-10](../../../docs/scrum/sprint-0-requerimientos/10-patron-de-desarrollo.md).
- [Infraestructura S0-09](../../../docs/scrum/sprint-0-requerimientos/09-infraestructura.md).
- [Trazabilidad de IDs](../../../docs/sprint-0/ids-trazabilidad.md), PB-001/HU-001/RF-001.

La ruta de la exploración no es un archivo local; su contenido fuente fue leído desde el topic `sdd/registro-cliente/explore` de Engram. No se presenta como un artefacto nuevo del repositorio.
