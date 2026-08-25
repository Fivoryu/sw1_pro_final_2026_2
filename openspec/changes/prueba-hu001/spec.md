# Spec — Ejecución real de CP-001 contra PostgreSQL (HU-001)

- **Cambio:** `prueba-hu001`
- **Trazabilidad canónica:** CP-001 = **PB-001 / HU-001** — Registro de cliente (el documento canónico de Sprint 1 registra así el caso). La solicitud del cambio mencionó `PB-002/HU-001`; esa discrepancia queda documentada en la propuesta y NO se corrige silenciosamente el documento canónico.
- **Historia:** HU-001 — Registro con correo (modo pruebas) · **Caso de prueba:** CP-001
- **Slice:** integración backend + PostgreSQL real y evidencia documental del Sprint 1; sin UI cliente
- **Estado:** especificado (propuesta aprobada)
- **Ruta OpenSpec:** plano `openspec/changes/prueba-hu001/spec.md` (convención del proyecto, igual que `registro-cliente` y `autenticacion`; no existe spec canónica en `openspec/specs/`)

## Propósito

Definir el comportamiento verificable de la ejecución real de CP-001 (HU-001) contra FastAPI + PostgreSQL en Docker, cerrando la incertidumbre que las pruebas con fakes no cubren: configuración, migraciones Alembic, driver PostgreSQL, sesión real y restricción de unicidad funcionando juntos. El cambio produce infraestructura mínima reproducible, evidencia transcripta y la actualización honesta del plan, caso y reporte de pruebas del Sprint 1, sin modificar código backend ni adelantar la UI cliente.

## Convenciones

- `DEBE` = MUST/SHALL (RFC 2119); `DEBERÍA` = SHOULD; `PUEDE` = MAY.
- Trazabilidad canónica: CP-001 se documenta como **PB-001/HU-001** en todo el Sprint 1; esta spec no altera esa identidad.
- Códigos HTTP esperados: `201` creación, `409` conflicto de duplicado con mensaje exacto `Ya existe una cuenta con este correo`, `422` error de validación. Los `422` sanitizados por `main.py` — sin referencias sensibles a `password` — son comportamiento esperado, no fallo.
- Seguridad de evidencia: el transcripto NUNCA contiene contraseñas, `JWT_SECRET` ni credenciales completas de conexión. El hash Argon2id completo SÍ puede mostrarse: es el dato real verificado en la base, no es reversible y su exhibición no expone el secreto.
- Ejecución desde `backend/` (cwd correcto): Alembic y `Settings` leen `.env` relativo a `backend/`; ejecutar desde otro directorio produce falsas fallas de configuración.
- Toda afirmación trazable a fuentes del repositorio: propuesta `prueba-hu001`, ficha HU-001 (`docs/scrum/sprint-1/01-sprint-planning.md` §1.9), diseño lógico (§2.1.2.2 de `docs/scrum/sprint-1/02-proceso-por-hu.md`) y skill `documentacion-software` (formatos §2.1.5.1/§2.1.5.2/§2.1.5.3).

---

## REQ-01 — Compose mínimo de PostgreSQL (`infra/docker/compose.postgres.yml`)

### Qué

El cambio DEBE agregar `infra/docker/compose.postgres.yml` que defina un servicio PostgreSQL con imagen `postgres:16-alpine`, publicación del puerto host `5433` (container `5432`), volumen nombrado `roomforge_pgdata` y healthcheck mediante `pg_isready`. El servicio DEBE quedar `healthy` y aceptar conexiones antes de cualquier paso de migración. Aporta parcialmente a PB-048 únicamente en la parte de PostgreSQL.

### Por qué

Sin una instancia PostgreSQL real reproducible no se puede ejecutar ni evidenciar CP-001 contra la cadena de persistencia prevista. El compose mínimo es la autoridad de persistencia para la prueba y queda fuera del scope completo de PB-048 (Floci, S3 y SQS no se incluyen).

### Criterios de aceptación verificables

1. Dado el archivo `infra/docker/compose.postgres.yml`, cuando se inspecciona su contenido, entonces declara imagen `postgres:16-alpine`, mapeo `5433:5432`, volumen nombrado `roomforge_pgdata` y healthcheck `pg_isready`. (Proposal objetivo 1)
2. Dado Docker disponible y puerto host `5433` libre, cuando se ejecuta `docker compose -f infra/docker/compose.postgres.yml up -d`, entonces el contenedor queda `running` y el estado reportado es `healthy` (p. ej. `docker compose ps`). (Criterio de aceptación 1 de la propuesta)
3. Dado el contenedor healthy, cuando se ejecuta `pg_isready -h localhost -p 5433`, entonces responde que el servidor acepta conexiones. (Proposal objetivo 1)
4. Dado el volumen declarado, cuando se inspecciona con `docker volume ls`, entonces existe `roomforge_pgdata` y persiste entre reinicios. (Proposal R5)
5. Dado el compose levantado, cuando se detiene con `docker compose down` (sin `-v`), entonces el volumen se preserva; la limpieza destructiva NO forma parte del flujo normal. (Proposal R5)

### Método de verificación

Inspección del archivo, `docker compose ps`, `docker inspect` del healthcheck y `pg_isready` contra `localhost:5433`.

### Evidencia esperada

Salida del `up` (bounded), `docker compose ps` con `healthy` y salida de `pg_isready`; todo incorporado al transcripto (REQ-06).

### Referencias

Proposal (objetivo 1, alcance, R2, R5) · PB-048 (parcial: solo PostgreSQL)

---

## REQ-02 — Configuración local `backend/.env` gitignored

### Qué

El cambio DEBE dejar un `backend/.env` local y gitignored con `DATABASE_URL=postgresql+psycopg://roomforge:<password-local>@localhost:5433/roomforge`, un `JWT_SECRET` de desarrollo y `APP_ENV=development`. Ningún secreto local DEBE incorporarse al commit.

### Por qué

La cadena real requiere que la aplicación resuelva la base desde configuración de entorno (patrón S0-10), y la evidencia no debe filtrar secretos. El `.env` es local al entorno de ejecución; el repositorio no lo contiene.

### Criterios de aceptación verificables

1. Dado `backend/.env` creado localmente, cuando se lee, entonces contiene las tres variables: `DATABASE_URL` con esquema `postgresql+psycopg://roomforge:<password-local>@localhost:5433/roomforge`, `JWT_SECRET` de desarrollo y `APP_ENV=development`. (Proposal objetivo 2)
2. Dado el `.gitignore` del repositorio, cuando se ejecuta `git check-ignore backend/.env`, entonces confirma que el archivo está ignorado. (Proposal objetivo 2)
3. Dado el cambio listo para commit, cuando se inspecciona `git status` y el contenido del commit, entonces `backend/.env` NO aparece y no hay secretos locales incluidos. (Proposal R6)
4. Dado el backend con este `.env`, cuando arranca la API (REQ-04), entonces la configuración se resuelve desde el archivo local y no desde constantes del código. (S0-10; Proposal R3)

### Método de verificación

Lectura del archivo local, `git check-ignore backend/.env`, `git status` y revisión del contenido del commit.

### Evidencia esperada

Salida de `git check-ignore` (el path ignorado) y `git status` sin `backend/.env`; las variables se verifican sin exponer el password en el transcripto.

### Referencias

Proposal (objetivo 2, R3, R6) · S0-10 (configuración solo por entorno)

---

## REQ-03 — Migraciones Alembic reales (`alembic upgrade head`)

### Qué

El cambio DEBE ejecutar `alembic upgrade head` desde `backend/` (cwd correcto) contra PostgreSQL real, verificar `alembic current` en la revisión `0002` y comprobar la existencia de las tablas `usuario_global`, `sesion` y `alembic_version`. La salida DEBE capturarse como evidencia. No se agregan migraciones nuevas: se ejecuta la cadena existente `0001` → `0002`.

### Por qué

Es la cobertura parcial de GAP-092 que este cambio puede cerrar con evidencia: las migraciones del Sprint 1 dejan de ser afirmación de diseño y pasan a tener ejecución comprobada sobre la base real. `0002` es el head actual (migración de `sesion` del cambio `autenticacion`).

### Criterios de aceptación verificables

1. Dado PostgreSQL healthy (REQ-01) y `.env` configurado (REQ-02), cuando se ejecuta `alembic upgrade head` desde `backend/`, entonces finaliza sin error y su salida queda capturada. (Proposal objetivo 3)
2. Dada la migración aplicada, cuando se ejecuta `alembic current` desde `backend/`, entonces la revisión activa es `0002` (head). (Criterio de aceptación 2 de la propuesta)
3. Dada la base migrada, cuando se consulta el catálogo de tablas (p. ej. `information_schema.tables` o `\dt`), entonces existen `usuario_global`, `sesion` y `alembic_version`. (Criterio de aceptación 2 de la propuesta)
4. Dada la base migrada, cuando se consulta `alembic_version`, entonces contiene exactamente la revisión `0002`. (Proposal regla 8)
5. Dado un entorno ya migrado, cuando se re-ejecuta `alembic upgrade head`, entonces la operación es idempotente y no produce cambios. (Proposal regla 8)

### Método de verificación

Comandos Alembic ejecutados desde `backend/` con el venv del proyecto; verificación de tablas mediante consulta SQL directa.

### Evidencia esperada

Salidas de `alembic upgrade head` y `alembic current` y de la consulta de tablas, incorporadas al transcripto (REQ-06).

### Referencias

Proposal (objetivo 3, regla 8, R3) · GAP-092 (cobertura parcial) · spec `autenticacion` REQ-04 (migración `0002`)

---

## REQ-04 — Ejecución real de los cuatro outcomes de CP-001 (API + PostgreSQL)

### Qué

El cambio DEBE arrancar la API real (uvicorn, desde `backend/` con `.env`) y ejecutar los cuatro outcomes de CP-001 contra API + PostgreSQL reales:

1. registro válido → `201 Created`;
2. correo duplicado, incluida la variante con mayúsculas → `409 Conflict` con el mensaje exacto `Ya existe una cuenta con este correo`;
3. correo inválido → `422 Unprocessable Entity`;
4. contraseña de menos de 8 caracteres → `422 Unprocessable Entity`.

Los `422` sanitizados por `main.py`, sin referencias sensibles a `password`, son el comportamiento esperado y NO constituyen un fallo. El uso de un correo controlado con verificación previa del estado inicial evita mezclar evidencia de ejecuciones previas.

### Por qué

CP-001 está declarado `not executed` (GAP-087). La prueba unitaria con fakes no demuestra que configuración, migraciones, driver, sesión real y unicidad funcionen juntos; esta ejecución produce los resultados observables que el documento del Sprint 1 exige para marcar el caso como ejecutado.

### Criterios de aceptación verificables

1. Dada la API arrancada contra PostgreSQL real, cuando se envía `POST /api/v1/auth/registro` con un correo válido no registrado (p. ej. `prueba@ejemplo.inv`) y password de al menos 8 caracteres, entonces responde `201` con `id` UUID, `correo` normalizado, `estado: "activo"`, `correo_verificado: false` y `creado_en`, sin `hash_password` ni password. (Proposal objetivo 4, criterio 3; HU-001 CA1/CA2)
2. Dado el correo ya registrado, cuando se repite el registro con el mismo correo, entonces responde `409` con el mensaje exacto `Ya existe una cuenta con este correo` y no se incrementa el número de filas. (Proposal criterio 4; HU-001 CA3)
3. Dada la cuenta registrada en minúsculas, cuando se envía el mismo correo con distinta combinación de mayúsculas (p. ej. `Prueba@Ejemplo.INV`), entonces responde `409` con el mismo mensaje exacto (unicidad case-insensitive) y no crea una segunda fila. (Proposal objetivo 4, regla 2)
4. Dado un correo sin formato válido (p. ej. `no-es-correo`), cuando se envía al endpoint, entonces responde `422` y no se crea ninguna fila. (Proposal objetivo 4)
5. Dada una contraseña de 7 caracteres o menos, cuando se envía al endpoint, entonces responde `422` y no se crea ninguna fila. (Proposal objetivo 4, regla 4)
6. Dadas las respuestas `422` de los pasos anteriores, cuando se inspecciona el cuerpo, entonces no contienen la cadena sensible `password` (sanitización esperada, no fallo). (Proposal regla 7)
7. Dado el estado inicial de la base (REQ-05 CA1), cuando comienza la ejecución, entonces el correo de prueba está ausente o identificado como baseline, de modo que la evidencia corresponde a una sola ejecución. (Proposal R4)

### Método de verificación

Solicitudes HTTP reales (curl o httpx) contra la API en ejecución, con captura de status y cuerpo; conteo de filas antes/después para los casos 409/422.

### Evidencia esperada

Requests (con password redactado), status y cuerpos de respuesta de los cuatro outcomes, capturados en el transcripto (REQ-06).

### Referencias

Proposal (objetivo 4, reglas 1–4 y 7, R4, R7) · HU-001 CA1–CA3 · decisión de split en 4 pasos (proposal) · spec `registro-cliente` REQ-01/02/03

---

## REQ-05 — Verificación SQL en PostgreSQL

### Qué

El cambio DEBE verificar por SQL directo que: el estado inicial es controlado; la ejecución completa dejó exactamente 1 fila; el correo persistido está en minúsculas; `estado = 'activo'`; `correo_verificado = false`; y `hash_password` tiene formato Argon2id (prefijo `$argon2id$`), distinto del plaintext.

### Por qué

La verificación SQL es la evidencia de que la cadena real (y no un fake) persistió con las reglas de negocio: una sola cuenta, normalización, estado inicial y hash Argon2id (HU-001 CA2/CA4).

### Criterios de aceptación verificables

1. Dado el estado inicial, cuando se consulta `SELECT count(*)` de `usuario_global` para el correo de prueba, entonces es `0` (o el baseline quedó identificado antes de ejecutar). (Proposal R4)
2. Dada la ejecución completa de REQ-04, cuando se consultan las filas del correo de prueba, entonces existe exactamente 1 fila. (Criterio de aceptación 3 de la propuesta)
3. Dada la fila creada, cuando se lee el valor de `correo`, entonces está en minúsculas, incluso si la solicitud original usó mayúsculas. (Criterio de aceptación 7 de la propuesta; regla 2)
4. Dada la fila creada, cuando se leen `estado` y `correo_verificado`, entonces `estado = 'activo'` y `correo_verificado = false`. (Criterio de aceptación 7 de la propuesta; regla 6)
5. Dada la fila creada, cuando se lee `hash_password`, entonces comienza con `$argon2id$` y difiere de la contraseña original (el plaintext no se expone). (Criterio de aceptación 7 de la propuesta; regla 5; HU-001 CA4)
6. Dados los intentos de duplicado y de validación (409/422), cuando se vuelve a contar el total de filas del correo, entonces el número no cambió (sigue en 1). (Proposal criterios 4–6)

### Método de verificación

Consultas SQL directas contra PostgreSQL (`psql` en el contenedor, `docker exec` o cliente del venv), con salidas capturadas.

### Evidencia esperada

Salidas de las consultas SQL (conteos, correo, estado, `correo_verificado`, hash completo) incorporadas al transcripto (REQ-06). El hash Argon2id completo puede mostrarse: es el dato real verificado y no expone el secreto.

### Referencias

Proposal (objetivo 5, reglas 2, 5 y 6, R4) · HU-001 CA2/CA4 · spec `registro-cliente` REQ-04/05

---

## REQ-06 — Evidencia transcripta en `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt`

### Qué

El cambio DEBE guardar un transcripto en `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt` que permita reconstruir la ejecución: comandos de migración con salida, solicitudes HTTP (con password redactado), respuestas con status y cuerpo, y consultas SQL con salida. El transcripto DEBE omitir contraseñas, `JWT_SECRET` y credenciales completas de conexión; el hash Argon2id completo SÍ puede aparecer (política de evidencia: el hash no es un secreto reutilizable).

### Por qué

El documento Sprint 1 exige evidencia verificable para declarar un caso `executed`; sin transcripto, la actualización de CP-001 sería una afirmación sin sustento (riesgo de la skill `documentacion-software`: no inventar resultados).

### Criterios de aceptación verificables

1. Dada la ejecución completa (REQ-03 a REQ-05), cuando se escribe el transcripto en la ruta acordada, entonces contiene: salidas de migraciones (`upgrade head`, `current`), los requests de los cuatro outcomes (con password redactado), sus status y cuerpos, y las consultas SQL con salida. (Proposal objetivo 6)
2. Dado el transcripto, cuando se busca el plaintext del password de prueba, entonces NO aparece en ningún momento (los requests lo muestran redactado). (Proposal R6, regla 5)
3. Dado el transcripto, cuando se buscan `JWT_SECRET`, credenciales completas de conexión o secretos reutilizables, entonces NO aparecen. (Proposal R6)
4. Dado el transcripto, cuando se busca el prefijo `$argon2id$`, entonces aparece al menos el hash completo de la fila creada. (Proposal objetivo 5; política de hash)
5. Dado el transcripto, cuando se intenta reconstruir la ejecución, entonces es posible reproducir pasos y resultados sin ambigüedad (URLs, puerto, códigos y salidas presentes). (Proposal objetivo 6)

### Método de verificación

Lectura del archivo, búsquedas `grep` de marcadores sensibles (password, `JWT_SECRET`) con cero aciertos y del prefijo `$argon2id$` con al menos un acierto; auditoría manual de redacción.

### Evidencia esperada

Archivo creado en la ruta acordada con las secciones de migraciones, requests/responses y SQL; checks grep documentados.

### Referencias

Proposal (objetivo 6, R6, regla 5) · skill `documentacion-software` (evidencia real, sin inventar resultados)

---

## REQ-07 — Actualización del documento Sprint 1 (§2.1.5 y narrativa GAP-092)

### Qué

El cambio DEBE actualizar `docs/scrum/sprint-1/02-proceso-por-hu.md` en:

- **§2.1.5.1 Plan de pruebas:** fila CP-001 → `executed`, conservando PB-001/HU-001, la plataforma canónica `App cliente / Backend` con aclaración de que esta ejecución cubre la superficie backend, y `Responsable: GAP-073` (no se cierra GAP-073). CP-002..CP-013 permanecen `not executed` sin tocar.
- **§2.1.5.2 Caso CP-001:** cuatro pasos con estados `executed` y resultados esperados por outcome (1) registro válido 201, 2) duplicado 409, 3) correo inválido 422, 4) contraseña corta 422), conservando la numeración del modelo con nota explícita de que los pasos 3 y 4 desdoblan el paso 3 original; `Resultado de la prueba: Satisfactorio`; `Adjunto` apuntando a `evidencia/cp001-registro-transcripto.txt`.
- **§2.1.5.3 Reporte de prueba:** llenado parcial honesto — 1 historia probada, 1 caso ejecutado, 1 satisfactorio, 0 fallidos, ≈7,7 % de cumplimiento y estado general `en ejecución`, con nota explícita de que CP-002..CP-013 siguen pendientes y sin declarar aprobación global del sprint.
- **Narrativa:** la frase introductoria de §2.1 pasa de "CP-001..CP-013" a "CP-002..CP-013" (CP-001 ya no es una prueba sin ejecutar); §2.1.2.3 y §2.1.4 actualizan la mención de GAP-092 para reflejar la cobertura parcial (migraciones `0001` y `0002` ejecutadas y evidenciadas contra PostgreSQL real; el resto del esquema sigue pendiente).

### Por qué

CP-001 obtiene evidencia real (GAP-087 se cierra solo para este caso); el formato del modelo exige plan, caso y reporte coherentes con los resultados observados. El reporte parcial honesto evita ocultar una ejecución real detrás de una plantilla vacía y evita convertirla en aprobación del Sprint 1 completo (decisiones aceptadas en la propuesta).

### Criterios de aceptación verificables

1. Dada la fila CP-001 de §2.1.5.1, cuando se lee, entonces `Estado = executed`, `PB = PB-001`, `HU = HU-001`, plataforma conservada con aclaración backend y `Responsable = GAP-073`. (Proposal objetivo 7, regla de plataforma)
2. Dadas las filas CP-002..CP-013 de §2.1.5.1, cuando se leen, entonces permanecen `not executed` sin ninguna modificación. (Proposal alcance excluido)
3. Dado el caso CP-001 de §2.1.5.2, cuando se leen los pasos, entonces son cuatro con estados `executed` y resultados por outcome, con la nota de desdoblamiento del paso 3 original, `Resultado de la prueba: Satisfactorio` y `Adjunto` con la ruta del transcripto. (Proposal decisión de split, criterio 9)
4. Dada la tabla de §2.1.5.3, cuando se leen los valores, entonces son `1` historia probada, `1` caso ejecutado, `1` satisfactorio, `0` fallidos, `≈7,7 %` y estado `en ejecución`, con nota de CP-002..CP-013 pendientes. (Proposal criterio 10, criterio de éxito del reporte)
5. Dada la frase introductoria de §2.1, cuando se lee, entonces menciona "CP-002..CP-013" como pruebas no declaradas ejecutadas (no "CP-001..CP-013"). (Proposal objetivo 7)
6. Dadas las secciones §2.1.2.3 y §2.1.4, cuando se leen las menciones de GAP-092, entonces reflejan cobertura parcial (migraciones `0001`/`0002` ejecutadas con evidencia; resto pendiente). (Proposal GAP-092)
7. Dados los casos CP-002..CP-013 en §2.1.5.2, cuando se leen, entonces sus pasos y estados permanecen `not executed` sin cambios. (Proposal alcance excluido)

### Método de verificación

Lectura del archivo tras el cambio y `git diff` del commit para confirmar que solo cambiaron CP-001, el reporte y las menciones narrativas acordadas.

### Evidencia esperada

Diff del commit acotado a: fila CP-001, caso CP-001, reporte §2.1.5.3, frase intro §2.1, §2.1.2.3 y §2.1.4; sin diferencias en CP-002..CP-013.

### Referencias

Proposal (objetivo 7, decisiones 1 y 2, GAP-087/092) · skill `documentacion-software` (formatos §2.1.5.1/§2.1.5.2/§2.1.5.3, GAP-CH2 aplicados)

---

## REQ-08 — No-regresión y no modificación de código backend

### Qué

El cambio DEBE dejar la suite pytest completa en verde (los fakes y pruebas existentes no se ven afectados) y NO DEBE modificar código backend (`backend/app`) ni pruebas (`backend/tests`): el cambio es aditivo (infraestructura, configuración local, evidencia y documentación).

### Por qué

La propuesta delimita el slice a integración y evidencia; preservar la suite en verde garantiza que la ejecución real no introdujo regresiones y que los fakes siguen siendo la vía reproducible sin Docker.

### Criterios de aceptación verificables

1. Dado el venv del proyecto, cuando se ejecuta la suite completa con `pytest` desde `backend/`, entonces pasa en verde sin fallos (los fakes no dependen de PostgreSQL real). (Proposal criterio de éxito 1; spec `registro-cliente` REQ-07 CA6)
2. Dado el commit del cambio, cuando se listan los archivos modificados (p. ej. `git diff --name-status`), entonces no hay cambios en `backend/app` ni en `backend/tests`; solo se agregan el compose, la evidencia y las actualizaciones documentales, quedando `backend/.env` excluido. (Proposal alcance excluido)
3. Dado el entorno sin PostgreSQL (CI o máquina sin Docker), cuando se ejecuta la suite, entonces continúa corriendo sin servicios externos. (Proposal R2; spec `registro-cliente` REQ-07 CA6)

### Método de verificación

`pytest` desde `backend/` en verde; `git diff --name-status` (o `--stat`) sobre el commit aditivo.

### Evidencia esperada

Salida de pytest (N passed, 0 failed) y el listado de paths del commit sin archivos de código backend.

### Referencias

Proposal (alcance excluido, criterio de éxito 1, R2) · spec `registro-cliente` REQ-07 (suite con fakes)

---

## Fuera de alcance (NREQ)

| NREQ | Restricción |
| --- | --- |
| NREQ-01 | NO se implementa UI, navegación ni automatización de la app cliente; la ejecución cubre la superficie API/backend (la plataforma canónica de CP-001 se conserva con aclaración). |
| NREQ-02 | NO se ejecutan ni declaran CP-002..CP-013; quedan `not executed` (GAP-087 permanece para ellos). |
| NREQ-03 | NO se crea el compose completo de PB-048 (Floci, S3, SQS); solo PostgreSQL. |
| NREQ-04 | NO se agregan migraciones nuevas ni se amplía el modelo de datos; se ejecuta la cadena existente `0001` → `0002`. |
| NREQ-05 | NO se modifica código backend (`backend/app`) ni pruebas (`backend/tests`). |
| NREQ-06 | NO se toca `docs/diagramas/Diagrama1.eapx`. |
| NREQ-07 | NO hay push ni PR; entrega en rama `feat/pruebas/cp001-postgres` con un único commit aditivo cuando el usuario lo decida. |
| NREQ-08 | NO se cierra GAP-092 completo (resto de tablas del Sprint 1), ni GAP-073 (responsables) ni GAP-088 (diagramas). |
| NREQ-09 | NO se usa `docker compose down -v` en el flujo normal; la limpieza destructiva del volumen `roomforge_pgdata` requiere decisión explícita. |

---

## Matriz de trazabilidad

| REQ | Comportamiento verificable | Fuente principal | Evidencia |
| --- | --- | --- | --- |
| REQ-01 | Compose PG `postgres:16-alpine`, puerto 5433, volumen `roomforge_pgdata`, healthcheck; contenedor healthy | Proposal objetivo 1; PB-048 (parcial) | `docker compose ps` (healthy), `pg_isready` |
| REQ-02 | `backend/.env` gitignored con DATABASE_URL/JWT_SECRET/APP_ENV; sin secretos en git | Proposal objetivo 2; S0-10 | `git check-ignore`, `git status` |
| REQ-03 | `alembic upgrade head` desde `backend/` → current `0002`; tablas `usuario_global`, `sesion`, `alembic_version` | Proposal objetivo 3; regla 8; GAP-092 | Salidas Alembic y SQL capturadas |
| REQ-04 | Cuatro outcomes CP-001 contra API + PG: 201, 409 (incl. mayúsculas) con mensaje exacto, 422 correo, 422 password; 422 sanitizados | Proposal objetivo 4; reglas 1–4, 7; HU-001 CA1–CA3 | Requests/responses capturados |
| REQ-05 | SQL: 1 fila, correo en minúsculas, `activo`, `correo_verificado=false`, hash `$argon2id$` | Proposal objetivo 5; reglas 2, 5, 6; HU-001 CA2/CA4 | Salidas SQL capturadas |
| REQ-06 | Transcripto en `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt`; sin passwords ni secretos; hash OK | Proposal objetivo 6; R6 | Archivo + greps de auditoría |
| REQ-07 | §2.1.5.1 CP-001 executed; §2.1.5.2 4 pasos executed + Adjunto; §2.1.5.3 reporte 1/13 "en ejecución"; narrativa GAP-092 y frase intro; CP-002..013 intactos | Proposal objetivo 7; decisiones 1 y 2; skill §2.1.5.x | Diff del commit + lectura |
| REQ-08 | pytest verde con fakes; sin cambios en `backend/app` ni `backend/tests` | Proposal alcance excluido; criterio de éxito 1 | Salida pytest + `git diff --name-status` |

## Riesgos y gaps abiertos para la implementación

- **R1 — Puerto 5433 ocupado:** verificar disponibilidad antes de `up`; si se usa otro puerto, DEBE quedar reflejado en `DATABASE_URL` y en la evidencia.
- **R2 — Docker o healthcheck no disponible:** la prueba queda bloqueada y CP-001 no se marca `executed` sin conexión real saludable.
- **R3 — Configuración por cwd:** ejecutar Alembic y la API desde `backend/`; otro cwd produce falsas fallas de configuración.
- **R4 — Datos previos en el volumen:** usar correo controlado y verificar el estado inicial; no mezclar evidencia de ejecuciones distintas.
- **R5 — Pérdida de datos locales:** `docker compose down -v` elimina `roomforge_pgdata`; no es parte del flujo normal y exige decisión explícita.
- **R6 — Evidencia sensible:** el transcripto debe omitir passwords, `JWT_SECRET` y credenciales completas; el hash Argon2id completo puede mostrarse.
- **R7 — Alcance de plataforma:** la ejecución cubre API/backend; se declara en el caso para evitar sobreinterpretar el resultado como prueba de UI.
- **GAP-087:** se cubre solo para CP-001 con evidencia; CP-002..CP-013 permanecen pendientes.
- **GAP-092:** cobertura parcial (migraciones `0001`/`0002` ejecutadas sobre PostgreSQL real); el resto de las tablas del Sprint 1 sigue pendiente.
- **GAP-073 y GAP-088:** permanecen abiertos; el responsable de CP-001 continúa como `GAP-073`.
- **Nota de ruta OpenSpec:** la spec se entrega en la ruta plana `openspec/changes/prueba-hu001/spec.md` por convención del proyecto (igual que `registro-cliente` y `autenticacion`), con instrucción del orquestador; no existe spec canónica previa en `openspec/specs/`.
