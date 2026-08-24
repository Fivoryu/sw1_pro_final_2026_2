# Diseño — Ejecución real de CP-001 contra PostgreSQL

- **Cambio:** `prueba-hu001`
- **Product Backlog / trazabilidad:** CP-001 = PB-001 / HU-001 según el documento canónico de Sprint 1. La solicitud original menciona PB-002/HU-001; esa discrepancia se conserva y no se corrige en este cambio.
- **Historia:** HU-001 — Registro con correo (modo pruebas)
- **Slice:** prueba de integración y evidencia documental; superficie API/backend
- **Requisitos cubiertos:** REQ-01..REQ-08
- **Estado:** diseño para ejecución

## 1. Decisiones y límites

Este cambio no introduce arquitectura de producto ni modifica el backend existente. Documenta la topología, la secuencia operativa y la evidencia necesaria para ejecutar CP-001 contra la cadena real FastAPI + PostgreSQL.

Decisiones cerradas:

- Se recomienda **uvicorn + cliente HTTP real (`httpx` o `curl`)**, sin overrides de dependencias. Es una prueba de caja negra genuina: el request atraviesa el router, el servicio, el repositorio, la sesión SQLAlchemy síncrona, el driver `psycopg` y PostgreSQL real.
- `TestClient` queda como fallback únicamente si uvicorn no puede arrancar. Se usará sin overrides y con los settings reales de `.env`; no se sustituirá `get_db` por un fake.
- Se conserva un único caso `CP-001` y se desdobla su tabla de pasos en cuatro outcomes: 201, 409, 422 por correo y 422 por contraseña. Los pasos 3 y 4 desdoblan el paso 3 original, conservando la numeración del modelo y la identidad del caso.
- La evidencia se redacta durante la ejecución y se guarda antes de detener o limpiar el contenedor. Nunca se registran passwords, `JWT_SECRET` ni credenciales completas de conexión; el hash Argon2id completo sí puede aparecer.
- La prueba cubre API/backend, no la UI cliente. La plataforma canónica `App cliente / Backend` se conserva en la documentación con esta aclaración.

Fuera de alcance: cambios en `backend/app`, cambios en `backend/tests`, nuevas migraciones, UI, CP-002..CP-013, el compose completo de PB-048, Floci/S3/SQS, GAP-073, GAP-088, push, PR y `docs/diagramas/Diagrama1.eapx`.

## 2. Topología de la prueba

La ejecución se ordena así:

```text
PostgreSQL postgres:16-alpine
  └─ Docker Compose: infra/docker/compose.postgres.yml
     ├─ proyecto Compose: roomforge
     ├─ host:5433 -> container:5432
     ├─ volumen nombrado: roomforge_pgdata
     └─ healthcheck: pg_isready
          ↓ conexión TCP real
backend/.env local, gitignored
  ├─ DATABASE_URL=postgresql+psycopg://roomforge:<password-local>@localhost:5433/roomforge
  ├─ JWT_SECRET=<dev-local>
  └─ APP_ENV=development
          ↓ cwd backend/
alembic upgrade head (0001 → 0002)
          ↓ esquema real: usuario_global, sesion, alembic_version
uvicorn app.main:app
          ↓ HTTP real mediante httpx/curl
cuatro outcomes de CP-001
          ↓ consultas SQL directas
verificación de fila y conteos
          ↓
docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt
```

El compose debe declarar el servicio PostgreSQL, la imagen `postgres:16-alpine`, el mapeo `5433:5432`, `roomforge_pgdata` y un healthcheck con `pg_isready`. El puerto 5433 es el recomendado porque 5432 está ocupado por `psico-db`. Si 5433 también está ocupado, se usará 5434 y se actualizarán conjuntamente el mapeo, `DATABASE_URL`, los comandos de verificación y el transcripto.

La línea base verificada para la ejecución es Docker 29.6.2 operativo, `infra/docker/` sin compose de RoomForge, venv `.venv/`, backend FastAPI con SQLAlchemy 2.x síncrono y `psycopg`, `.env.example` sin una URL de base configurada y cadena Alembic `0001` → `0002`. La prueba debe iniciar desde una base controlada; si el volumen ya contiene el correo elegido, se registra el baseline y no se mezclan ejecuciones.

## 3. Capas y flujo de datos

El código existente ya separa las responsabilidades que esta prueba debe atravesar:

| Capa | Elemento | Responsabilidad observable |
| --- | --- | --- |
| Transporte | `POST /api/v1/auth/registro` en `identity.router` | Recibe el request, delega y traduce duplicados a HTTP 409. |
| Validación | `RegistroRequest` y handler de `main.py` | Valida `EmailStr` y password mínima de 8; sanitiza los 422. |
| Servicio | `IdentityService.registrar` | Hace `strip().lower()` al correo, verifica duplicado y solicita el hash Argon2id. |
| Repositorio | `UserRepository` | Ejecuta consultas, `flush`/`commit`/`refresh` y traduce la restricción única. |
| Sesión/driver | `get_db`, SQLAlchemy 2.x sync, `psycopg` | Abre y cierra la sesión contra `DATABASE_URL`. |
| Persistencia | PostgreSQL real | Aplica el esquema `0001`/`0002`, unicidad y defaults de la fila. |

Flujo nominal:

1. El cliente HTTP envía un request al endpoint real.
2. FastAPI/Pydantic valida la forma. Un correo inválido o password corta termina en 422 sin invocar el alta.
3. El router obtiene una sesión mediante `get_db` y crea el servicio con el repositorio real y el hasher configurado.
4. El servicio normaliza el correo, consulta duplicados y genera el hash Argon2id; el plaintext no se entrega al repositorio.
5. El repositorio inserta en PostgreSQL y confirma la transacción. `UNIQUE(correo)` es la autoridad para el caso de carrera.
6. El router devuelve únicamente los campos públicos. La respuesta 201 no contiene `password` ni `hash_password`.
7. La verificación posterior consulta la fila real: correo en minúsculas, `estado = 'activo'`, `correo_verificado = false` y `hash_password` con prefijo `$argon2id$`.

## 4. Cadena de ejecución

### 4.1. Preparación y migraciones

1. Comprobar que 5433 está libre y levantar el compose con proyecto `roomforge`.
2. Esperar el estado `healthy` y comprobar `pg_isready` contra el puerto publicado.
3. Crear `backend/.env` local con `DATABASE_URL`, `JWT_SECRET` de desarrollo y `APP_ENV=development`; validar que `git check-ignore backend/.env` lo reconoce.
4. Desde `backend/` y usando `.venv`, ejecutar `alembic upgrade head` y después `alembic current`.
5. Consultar el catálogo y `alembic_version`; el head esperado es `0002`, con `usuario_global`, `sesion` y `alembic_version` presentes.

No se agregan migraciones. `0001` crea `usuario_global` y `0002`, encadenada a `0001`, crea `sesion`.

### 4.2. Arranque y outcomes HTTP

Arrancar desde `backend/` con `uvicorn app.main:app` y enviar requests al endpoint real. Se usa un correo controlado, ausente en el baseline, y una password de prueba que se muestra como `[REDACTED]` en toda evidencia.

| Paso CP-001 | Request | Resultado esperado | Verificación adicional |
| --- | --- | --- | --- |
| 1 | Correo válido no registrado + password de al menos 8 caracteres | HTTP 201; correo normalizado, estado `activo`, `correo_verificado: false` | Una fila creada; no hay campos sensibles en el cuerpo. |
| 2 | Repetir el correo, incluyendo otra combinación de mayúsculas | HTTP 409 y `Ya existe una cuenta con este correo` | El conteo de filas permanece en 1. |
| 3 | Correo inválido | HTTP 422 sanitizado | No se crea fila y el cuerpo no contiene `password`. |
| 4 | Password menor de 8 caracteres | HTTP 422 sanitizado | No se crea fila y el cuerpo no contiene `password`. |

La tabla conserva un solo CP-001. Una nota explícita indicará que los pasos 3 y 4 son el desdoblamiento del paso 3 original del modelo.

### 4.3. Verificación SQL

Después de los cuatro requests se ejecutarán consultas SQL directas, preferentemente con `psql` dentro del contenedor o con el cliente del venv, para capturar:

- estado inicial del correo controlado (`count = 0`, o baseline identificado);
- existencia de exactamente una fila al finalizar;
- `correo` persistido en minúsculas;
- `estado = 'activo'`;
- `correo_verificado = false`;
- `hash_password LIKE '$argon2id$%'` y hash distinto del plaintext;
- conteo sin incremento después del duplicado y de ambos 422.

## 5. Cronología y contrato de evidencia

El archivo único de evidencia es `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt`. Se escribirá en este orden para que la ejecución sea reconstruible:

1. **Cabecera y entorno:** fecha de ejecución, commit/entorno identificable, proyecto Compose `roomforge`, puerto efectivo y nota de que el password/secret están redactados.
2. **Infraestructura:** comandos acotados y salidas de `docker compose ps`, healthcheck y `pg_isready`. No copiar variables de entorno completas.
3. **Migración:** comando ejecutado desde `backend/` y salida de `alembic upgrade head`; luego salida de `alembic current` con `0002`.
4. **Esquema y baseline:** SQL de tablas y conteo previo del correo controlado, sin credenciales de conexión.
5. **API:** comando de arranque sin secretos y, en orden, request/respuesta HTTP crudos de los cuatro pasos. Los bodies de request muestran `"password": "[REDACTED]"`; las respuestas se conservan tal como fueron recibidas, auditando que no expongan secretos.
6. **SQL posterior:** consultas y salidas de conteo, correo, estado, verificación y hash. El hash Argon2id completo puede quedar en el transcripto.
7. **Auditoría final:** comprobación de que no aparecen passwords plaintext, `JWT_SECRET` ni credenciales completas, y que sí aparece `$argon2id$`.

Si la ejecución falla antes de obtener todos los resultados, se conserva el transcripto parcial con el punto de falla y CP-001 no se marca `executed`. No se inventan respuestas ni salidas.

## 6. Actualizaciones documentales previstas

Solo después de observar los cuatro resultados esperados y guardar la evidencia se modifica `docs/scrum/sprint-1/02-proceso-por-hu.md`:

- **§2.1.5.1:** CP-001 pasa a `executed`, mantiene PB-001/HU-001, `App cliente / Backend` y `Responsable: GAP-073`, agregando la aclaración de cobertura backend. CP-002..CP-013 no se toca y permanece `not executed`.
- **§2.1.5.2:** CP-001 conserva su metadato y numeración del modelo, incorpora cuatro pasos `executed` con los outcomes 201, 409, 422 por correo y 422 por password, la nota de desdoblamiento del paso 3 original, `Resultado de la prueba: Satisfactorio` y el adjunto `evidencia/cp001-registro-transcripto.txt`. Los casos CP-002..CP-013 quedan intactos.
- **§2.1.5.3:** se completa de forma parcial y honesta: 1 historia probada, 1 caso ejecutado de 13, 1 satisfactorio, 0 fallidos, aproximadamente 7,7 % de cumplimiento y estado general `en ejecución`. Se agrega la nota de que CP-002..CP-013 siguen pendientes; esto no es aprobación global del Sprint 1.
- **Narrativa:** la introducción de §2.1 pasa a referir CP-002..CP-013 como casos aún no ejecutados. En §2.1.2.3 y §2.1.4, GAP-092 se describe como parcialmente cubierto por las migraciones reales `0001` y `0002`; quedan 12 tablas pendientes. GAP-073 y GAP-088 permanecen abiertos.

No se adelanta ninguna afirmación de ejecución sobre CP-002..CP-013.

## 7. Diagrama de secuencia textual

```text
Ejecutor       Docker/Compose       PostgreSQL       Alembic       Uvicorn/API       Cliente HTTP       SQL
   |                 |                  |               |               |                |             |
   |-- up roomforge->|                  |               |               |                |             |
   |                 |-- postgres ----->|               |               |                |             |
   |                 |<-- healthy/pg_isready -----------|               |                |             |
   |-- .env + cwd backend ---------------------------------------------->|                |             |
   |                 |                  |<-- upgrade 0001/0002 ---------|                |             |
   |                 |                  |-------------- schema -------->|                |             |
   |<-- current 0002 / tablas ---------------------------|               |                |             |
   |-- start uvicorn --------------------------------------------------->|                |             |
   |                                                    |               |                |             |
   |------------------------------------------------------------------------------------->|             |
   |                                                    |<-- POST registro --------------|             |
   |                                                    |-- router -> service ---------->|             |
   |                                                    |   lower correo + Argon2id      |             |
   |                                                    |-- repository -> PG ------------>|             |
   |                                                    |<-- 201 público ----------------|             |
   |<-------------------------------------------------------------------------------------|             |
   |                                                    |               |                |             |
   |------------------------------------------------------------------------------------->|             |
   |                                                    |<-- POST duplicado/mayúsculas --|             |
   |                                                    |-- pre-check/UNIQUE ------------>|             |
   |                                                    |<-- 409 exacto ------------------|             |
   |<-------------------------------------------------------------------------------------|             |
   |---------------------------- repite POST inválido y password corta; recibe 422 --------------------|
   |                                                                                                    |
   |--------------------------------------------------------------------------------------------------->|
   |                                                    |               |                |<-- SELECT -->|
   |                                                    |               |                |<-- fila/conteos
   |<---------------------------------------------------------------------------------------------------|
   |-- guarda transcripto antes de down -------------->|               |                |             |
```

El diagrama es textual y no agrega un artefacto UML visual, conforme al formato del proyecto.

## 8. Riesgos y mitigaciones

| Riesgo | Mitigación operativa |
| --- | --- |
| **R1 — Puerto 5433 ocupado** | Detectarlo antes de `up`; usar 5434 como fallback y reflejarlo en compose, `DATABASE_URL` y evidencia. |
| **R2 — Docker no disponible o healthcheck fallido** | Detener el flujo; no marcar CP-001 como `executed` ni actualizar resultados como satisfactorios. |
| **R3 — cwd incorrecto para Alembic/Settings** | Ejecutar Alembic y uvicorn desde `backend/`, con `.venv` activo. |
| **R4 — Datos previos en el volumen** | Verificar baseline con SQL y usar un correo controlado; guardar el transcripto antes de cualquier limpieza. |
| **R5 — Riesgo para el working tree de PB-002** | Cambios aditivos, sin tocar `backend/app` ni `backend/tests`; `backend/.env` queda gitignored. |
| **R6 — uvicorn exige `.env` completo** | Crear el `.env` local con `DATABASE_URL`, `JWT_SECRET` y `APP_ENV`; nunca sustituir la configuración real por overrides en la ruta principal. |
| **R7 — Evidencia sensible** | Redactar passwords, JWT_SECRET y credenciales; revisar el archivo antes de considerarlo adjunto. |

La limpieza normal es `docker compose down` sin `-v`, preservando `roomforge_pgdata`. `down -v` y cualquier reinicio destructivo requieren autorización explícita.

## 9. Cambios de archivos, rollout y rollback

| Archivo | Tratamiento |
| --- | --- |
| `infra/docker/compose.postgres.yml` | Crear el compose mínimo de PostgreSQL para `roomforge`. |
| `backend/.env` | Crear solo localmente; gitignored, nunca parte del commit. |
| `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt` | Crear con evidencia real y redacción auditada. |
| `docs/scrum/sprint-1/02-proceso-por-hu.md` | Actualizar únicamente los puntos de §2.1, GAP-092 y CP-001 indicados en §6. |
| `backend/app/**`, `backend/tests/**`, migraciones existentes | No modificar. |

Rollout de prueba:

1. Crear el compose y el `.env` local.
2. Levantar PostgreSQL y comprobar salud.
3. Aplicar y verificar `0001` → `0002`.
4. Arrancar uvicorn y ejecutar los cuatro requests.
5. Ejecutar SQL, cerrar la evidencia y auditar secretos.
6. Solo con evidencia completa, actualizar la documentación Sprint 1 y ejecutar la suite pytest desde `backend/` para la no-regresión.

Rollback:

- Revertir el commit aditivo para retirar compose, evidencia y cambios documentales.
- Usar `docker compose down` para detener el contenedor sin borrar el volumen.
- Usar `down -v` o eliminar `roomforge_pgdata` solo con autorización explícita.
- Eliminar `backend/.env` local cuando ya no sea necesario; no existe rollback de migración dentro de este cambio porque no se agregan migraciones.

## 10. Trazabilidad y verificaciones de cierre

| Requisito | Decisión/diseño | Evidencia de apply |
| --- | --- | --- |
| REQ-01 | Compose PG real, healthcheck, puerto y volumen definidos | `docker compose ps`, `pg_isready`, inspección del volumen |
| REQ-02 | `.env` local con settings reales y fuera de Git | `git check-ignore`, `git status`, auditoría sin secretos |
| REQ-03 | Alembic desde `backend/`, head `0002`, tablas presentes | salidas Alembic y SQL |
| REQ-04 | Cuatro outcomes por HTTP real | requests/respuestas crudos y conteos |
| REQ-05 | SQL sobre fila y conteos reales | SELECT inicial/final, estado, correo y prefijo Argon2id |
| REQ-06 | Transcripto ordenado y seguro | lectura + búsquedas de secretos y `$argon2id$` |
| REQ-07 | CP-001/documentación parcial coherente | diff acotado; CP-002..CP-013 intactos |
| REQ-08 | No-regresión y ausencia de cambios de código | `pytest` desde `backend/` y `git diff --name-status` |

La prueba no se considera exitosa por la existencia del compose o por una respuesta aislada: debe existir la cadena completa de migración, cuatro outcomes HTTP, verificación SQL y transcripto auditable. La ejecución real y sus valores observados quedan para `sdd-apply`; este diseño no afirma que ya se hayan ejecutado.

## Fuentes verificadas

- [Propuesta de `prueba-hu001`](./proposal.md).
- [Spec de `prueba-hu001`, REQ-01..REQ-08](./spec.md).
- [Diseño de `registro-cliente`](../registro-cliente/design.md), usado como formato de decisiones, capas y secuencia.
- Implementación existente de `backend/app/main.py`, `backend/app/core/config.py`, `backend/app/db/session.py`, `backend/app/modules/identity/router.py`, `service.py`, `repository.py` y `schemas.py`.
- Migraciones existentes `backend/alembic/versions/0001_crear_usuario_global.py` y `0002_crear_sesion.py`.
- [Formato documental del proyecto](../../skills/documentacion-software/SKILL.md) y §2.1.5 de `docs/scrum/sprint-1/02-proceso-por-hu.md`.
