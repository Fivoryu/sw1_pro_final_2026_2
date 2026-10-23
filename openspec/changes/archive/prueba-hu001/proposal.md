# Propuesta: Ejecución real de CP-001 contra PostgreSQL

- **Cambio:** `prueba-hu001`
- **Product Backlog / trazabilidad:** PB-002/HU-001 según la solicitud del cambio. El documento canónico de Sprint 1 registra actualmente CP-001 como PB-001/HU-001; este cambio conservará esa trazabilidad documental y no la corregirá silenciosamente.
- **Historia:** HU-001 — Registro con correo
- **Slice:** integración backend, PostgreSQL y evidencia documental del Sprint 1
- **Estado:** propuesta

## Problema y contexto

HU-001 está implementada y sus reglas fueron verificadas mediante pruebas con fakes, pero CP-001 permanece como `not executed` en el Sprint 1 (GAP-087). La cadena de persistencia real nunca se ha ejecutado contra PostgreSQL y las migraciones Alembic todavía no cuentan con evidencia de ejecución en una base real (GAP-092).

La prueba unitaria no demuestra por sí sola que la configuración, las migraciones, el driver PostgreSQL, la sesión real ni la restricción de unicidad funcionen juntos. La ejecución autorizada con Docker permitirá cerrar esa incertidumbre sin modificar el backend ni adelantar la UI cliente.

## Usuarios y actores

- **Equipo de desarrollo y QA:** necesita evidencia reproducible de que el registro funciona sobre la infraestructura prevista.
- **Cliente global de RoomForge:** actor funcional representado por las solicitudes de registro.
- **Backend de RoomForge:** valida los datos, persiste la cuenta y devuelve los resultados HTTP.
- **PostgreSQL en Docker:** autoridad de persistencia para esta prueba.

La prueba será contra la API real; no incluirá la pantalla de la app cliente. La plataforma declarada de CP-001 conservará el valor canónico `App cliente / Backend`, con una aclaración de que esta ejecución cubre la superficie backend.

## Objetivo y resultados esperados

Ejecutar CP-001 de extremo a extremo sobre FastAPI + PostgreSQL real, con una instancia mínima reproducible en Docker, y registrar evidencia verificable en Sprint 1.

Resultados esperados:

1. Levantar PostgreSQL `postgres:16-alpine` en el puerto host `5433`, con volumen nombrado `roomforge_pgdata` y healthcheck mediante `pg_isready`. Esto aporta parcialmente a PB-048, únicamente en la parte de PostgreSQL.
2. Configurar `backend/.env` local y gitignored con `DATABASE_URL`, `JWT_SECRET` y `APP_ENV=development`; ningún secreto local se incorporará al commit.
3. Ejecutar `alembic upgrade head` desde `backend/`, verificar `alembic current` en `0002` y comprobar las tablas `usuario_global`, `sesion` y `alembic_version`.
4. Arrancar la API y ejecutar los cuatro outcomes de CP-001 contra la API y PostgreSQL reales:
   - registro válido: HTTP 201;
   - correo duplicado, incluyendo variante de mayúsculas: HTTP 409 y mensaje claro;
   - correo inválido: HTTP 422;
   - contraseña menor de 8 caracteres: HTTP 422.
5. Verificar mediante SQL que solo el registro válido creó una fila, que el correo está en minúsculas, el estado es `activo`, `correo_verificado` es falso y `hash_password` tiene formato Argon2id (`$argon2id$`).
6. Guardar el transcripto de migraciones, solicitudes, respuestas y consultas en `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt`.
7. Actualizar el plan, el caso CP-001 y el reporte parcial de pruebas del Sprint 1 sin declarar ejecutados CP-002..CP-013.

## Reglas de negocio y decisiones de ejecución

1. **Registro en modo pruebas:** un correo válido, aunque sea inventado, puede crear una cuenta sin exigir verificación.
2. **Normalización:** el correo se convierte a minúsculas antes de persistir y de evaluar duplicados.
3. **Cuenta única:** un correo repetido no crea otra fila y responde HTTP 409 con `Ya existe una cuenta con este correo`.
4. **Contraseña:** la única condición de este slice es una longitud mínima de 8 caracteres.
5. **Seguridad:** la contraseña no se persiste ni se expone en respuestas o evidencia; la base contiene únicamente el hash Argon2id.
6. **Estado inicial:** el registro válido queda `activo` y con `correo_verificado = false`.
7. **Errores de validación:** los 422 sanitizados por `main.py`, sin referencias sensibles a `password`, son el comportamiento esperado y no constituyen un fallo.
8. **Migraciones:** se verificará la cadena `0001` → `0002`; no se agregan migraciones nuevas en este cambio.

### Decisión sobre los pasos de CP-001

Se propone conservar un único caso `CP-001`, pero registrar **cuatro pasos numerados** en §2.1.5.2: 1) registro válido, 2) duplicado, 3) correo inválido y 4) contraseña corta. Los pasos 3 y 4 desdoblan el paso 3 original del documento, que actualmente fusiona ambos errores.

Esta decisión mantiene la identidad y trazabilidad de CP-001, pero permite asignar un estado y una evidencia independiente a cada outcome HTTP. No se crearán casos de prueba adicionales ni se alterará el alcance funcional.

## Alcance incluido

- Compose mínimo para PostgreSQL en `infra/docker/compose.postgres.yml` con `postgres:16-alpine`, puerto `5433`, volumen `roomforge_pgdata` y healthcheck.
- Configuración local gitignored de `backend/.env` para la conexión real.
- Ejecución y verificación de Alembic `0001` y `0002` contra PostgreSQL.
- Arranque de la API y ejecución de los cuatro outcomes de CP-001 mediante solicitudes HTTP reales.
- Verificación SQL de unicidad, normalización, estado, correo no verificado y hash Argon2id.
- Evidencia textual en `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt`, sin contraseñas ni secretos.
- Actualización de `docs/scrum/sprint-1/02-proceso-por-hu.md` en §2.1.5.1, §2.1.5.2 y §2.1.5.3. También se corregirán únicamente las referencias narrativas que queden obsoletas sobre el estado de CP-001 y la cobertura parcial de GAP-092.
- Entrega en la rama `feat/pruebas/cp001-postgres`, sin push, con un único commit aditivo al finalizar, cuando el usuario lo decida.

## Alcance excluido

- UI, navegación o automatización de la app cliente.
- CP-002 a CP-013.
- Cambios de código backend; la prueba utilizará la cadena real existente mediante `get_db`.
- Nuevas migraciones o ampliación del modelo de datos.
- Compose completo de PB-048: Floci, S3 y SQS quedan fuera; solo se aporta PostgreSQL.
- Cierre completo de GAP-092, porque las demás tablas del Sprint 1 siguen pendientes.
- Cierre de GAP-073, relacionado con la asignación de responsables.
- Cierre de GAP-088, relacionado con diagramas.
- Push, publicación de PR o cambios en `docs/diagramas/Diagrama1.eapx`.

## Áreas afectadas

- **Infraestructura local:** nuevo compose de PostgreSQL y volumen de desarrollo.
- **Configuración:** `backend/.env` local, excluido del control de versiones.
- **Pruebas y evidencia:** nuevo transcripto de CP-001.
- **Documentación Sprint 1:** plan de pruebas, pasos de CP-001, reporte parcial y referencias de estado.
- **Persistencia:** ejecución real de las migraciones existentes; no se modifica el código de persistencia.

## Criterios de aceptación

1. El contenedor PostgreSQL está saludable y acepta conexiones en el puerto configurado.
2. `alembic upgrade head` finaliza correctamente desde `backend/`; `alembic current` identifica `0002` y existen `alembic_version`, `usuario_global` y `sesion`.
3. El registro válido devuelve 201, crea exactamente una cuenta, normaliza el correo, deja la cuenta activa y no expone secretos.
4. Repetir el correo con otra combinación de mayúsculas devuelve 409 con el mensaje acordado y no incrementa la cantidad de filas.
5. Un correo inválido devuelve 422 y no crea una fila.
6. Una contraseña menor de 8 caracteres devuelve 422 y no crea una fila.
7. La consulta SQL confirma el hash Argon2id, el correo en minúsculas, `estado = 'activo'` y `correo_verificado = false`.
8. La evidencia queda guardada en la ruta acordada y permite reconstruir la ejecución sin contener contraseñas, secretos ni credenciales reutilizables.
9. El documento marca CP-001 como `executed`, registra los cuatro pasos como satisfactorios cuando los resultados observados coincidan y mantiene CP-002..CP-013 como `not executed`.
10. El reporte §2.1.5.3 refleja honestamente una ejecución parcial del Sprint 1 y no declara aprobación global del sprint.

## Riesgos y gaps

- **R1 — Puerto ocupado:** `5433` podría estar ocupado. Se verificará antes de levantar Docker; cualquier puerto alternativo deberá quedar reflejado en `DATABASE_URL` y en la evidencia.
- **R2 — Docker o healthcheck no disponible:** la prueba quedará bloqueada y no se marcará CP-001 como ejecutado hasta contar con una conexión real saludable.
- **R3 — Configuración por cwd:** Alembic y `Settings` leen `.env` relativo a `backend/`; ejecutar desde otro directorio puede producir una falsa falla de configuración.
- **R4 — Datos de ejecuciones previas:** el volumen puede contener el correo de prueba. Se usará un correo controlado y se verificará el estado inicial; no se mezclará evidencia de ejecuciones distintas.
- **R5 — Pérdida de datos locales:** `docker compose down -v` elimina el volumen. La limpieza destructiva no será parte del flujo normal y requerirá una decisión explícita.
- **R6 — Evidencia sensible:** el transcripto debe omitir contraseñas, secretos JWT y credenciales completas de conexión.
- **R7 — Alcance de plataforma:** la ejecución cubre API/backend, no UI; esto se declarará en el caso para evitar sobreinterpretar el resultado.
- **GAP-087:** se cubre para CP-001 con evidencia; permanecen CP-002..CP-013 y las demás evidencias de Sprint 1.
- **GAP-092:** se cubre parcialmente al ejecutar las migraciones existentes `0001` y `0002`; no se cierra para las restantes.
- **GAP-073 y GAP-088:** permanecen abiertos.

## Rollback

- Revertir el commit aditivo para retirar el compose, la evidencia y las actualizaciones documentales.
- Eliminar o conservar el contenedor mediante `docker compose down`, preservando el volumen por defecto para no destruir datos locales. Usar `down -v` solo con autorización explícita y entendiendo que borra `roomforge_pgdata`.
- Eliminar `backend/.env` local si ya no se necesita; no se requiere una migración de rollback porque no se agregan cambios de esquema.
- Si la ejecución deja datos de prueba, limpiar únicamente el entorno descartable o restablecer el volumen con una operación explícita; nunca eliminar datos de un entorno compartido o productivo.

## Criterios de éxito

- PostgreSQL real queda disponible y saludable mediante el compose mínimo.
- Las migraciones `0001` y `0002` se ejecutan y verifican con evidencia.
- Los cuatro outcomes de CP-001 producen los códigos y reglas esperados contra API + PostgreSQL reales.
- La base contiene una sola cuenta válida con correo normalizado, estado activo, correo no verificado y hash Argon2id.
- La evidencia es reproducible, auditable y no contiene secretos.
- CP-001 deja de figurar como `not executed`; CP-002..CP-013 y los gaps fuera de alcance permanecen explícitamente abiertos.
- El reporte del Sprint 1 muestra, de forma parcial y honesta, 1 caso ejecutado de 13, 1 satisfactorio, 0 fallidos y aproximadamente 7,7 % de cumplimiento, con estado general `en ejecución`.

## Decisiones para el usuario

Se solicita confirmar estas dos decisiones de documentación antes de aplicar el cambio:

1. **Split de pasos:** aceptar cuatro pasos en CP-001 (201, 409, 422 por correo y 422 por contraseña), manteniendo un único identificador CP-001 y aclarando que los pasos 3 y 4 desdoblan el paso 3 original.
2. **Reporte §2.1.5.3:** aceptar el llenado parcial honesto del formato del modelo: 1 historia probada, 1 caso ejecutado, 1 satisfactorio, 0 fallidos, 7,7 % de cumplimiento y estado `en ejecución`, con nota explícita de que CP-002..CP-013 siguen pendientes. La alternativa es conservar la plantilla, pero perdería trazabilidad de la evidencia obtenida.

La recomendación de esta propuesta es aceptar ambas decisiones: separan los cuatro resultados observables y evitan ocultar una ejecución real detrás de una plantilla vacía, sin convertirla en aprobación del Sprint 1 completo.

## Preguntas abiertas restantes

- Confirmar el split de cuatro pasos o solicitar conservar literalmente los tres renglones actuales.
- Confirmar el reporte parcial o solicitar mantener la plantilla hasta completar CP-001..CP-013.
- La diferencia entre la identificación solicitada `PB-002/HU-001` y la trazabilidad canónica `PB-001/HU-001` queda documentada; este cambio no la resolverá sin una instrucción específica.
