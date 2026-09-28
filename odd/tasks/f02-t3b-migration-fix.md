# F02-T3b — Reparar revision ID y verificar PostgreSQL

## Estado

**VERIFICADA CON LIMITACIÓN DOCUMENTADA; pendiente commit/revisión.** La R6 existente está en `0004_pending_staff_email_uniq` y contiene 7 tablas de aplicación más `alembic_version`. Tras corregir el normalizador de PostgreSQL, una comparación read-only independiente de todo el esquema pasó. El tercer pytest original terminó con exit 1 antes de corregir la representación `TRIM`; su salida se suprimió y no se afirma como PASS. La base ya está poblada: no repetir la fixture fresh-DB ni Alembic, ni limpiar. El volumen se preserva.

## Contexto verificado

- La revisión actual `0004_staff_invitation_pending_email_unique` mide 42 caracteres y excede `alembic_version.version_num VARCHAR(32)`.
- ID propuesto: `0004_pending_staff_email_uniq` (29 caracteres), sin revisiones descendientes ni referencias de grafo al ID largo. Se conserva el filename y `down_revision = "0003_agency_registry"`.
- El worktree F02 estaba limpio en `9792c5a`.
- El contenedor `roomforge-local-dev-postgres-1` estaba detenido, publicaba `127.0.0.1:5434` y montaba `roomforge-local-dev_postgres_data` en `/var/lib/postgresql/data`. Se inició temporalmente, se confirmó healthy y se volvió a detener; el volumen continúa montado.
- En los dos primeros intentos, la autenticación de las URLs locales fue rechazada. La comparación de solo lectura mostró que el URL del usuario no coincide con `POSTGRES_USER`/`POSTGRES_PASSWORD` del init config; los valores no se imprimieron y el init config no prueba la contraseña vigente del volumen persistente.
- Con permiso administrativo se usaron las credenciales declaradas por el contenedor solo en memoria para un tercer test. La lectura posterior por socket local confirmó el rol `roomforge_local`, 8 tablas no-sistema y `alembic_version=0004_pending_staff_email_uniq`.
- Antes de corregir el comparador, la lectura de metadata encontró dos representaciones equivalentes de `TRIM`. Después del fix, el verificador independiente repitió solo la comparación de metadata read-only y confirmó PASS para tablas, columnas/tipos/nullability/defaults, PK, FK, unique keys, indexes y checks. R6 quedó en la revisión corta actual; no se ejecutó fixture/Alembic en esa verificación. La salida original del pytest se suprimió, así que no se afirma que el comando de migración completo haya terminado en PASS ni se vuelve a comprobar el estado blank inicial.

## Alcance

### Edit surfaces autorizadas

- `backend/alembic/versions/0004_staff_invitation_pending_email_unique.py`
- `backend/tests/test_staff_identity_migration.py`
- `docs/migrations/f02-migration-verification.md`
- `odd/tasks/f02-base-ux-automation.md`
- `odd/tasks/f02-t3b-migration-fix.md`

### Excluido

- Cualquier otra base o contenedor, cambios de schema fuera de la revisión y datos preexistentes.
- PostgreSQL concurrency test, suite R6 completa, `DATABASE_URL` de otra base, Docker Compose, `down`, `rm`, `prune`, eliminación de volúmenes, cleanup, push o PR.
- Actualizar documentos de otras áreas (`plan-maestro`, `agency-management`) que describen el baseline/historial; conservar la evidencia histórica del ID largo y del primer fallo.

## Tareas y validación

1. **RED local:** añadir una prueba estructural que recorra las revisiones Alembic y falle si algún revision ID excede 32 caracteres. Ejecutar solo esa prueba con las variables R6 ausentes; debe detectar 42 caracteres sin PostgreSQL.
2. **GREEN local:** cambiar `revision` a `0004_pending_staff_email_uniq`; mantener filename, `down_revision` y cuerpo de migración. Repetir la prueba estructural y los casos SQLite de invitaciones/agencias.
3. **Validación local:** ejecutar backend pytest con `ROOMFORGE_R6_DATABASE_URL` eliminado y `DATABASE_URL` SQLite, Ruff y Pyright; los casos R6 deben omitirse. No instalar dependencias.
4. **Preflight del R6:** confirmar otra vez worktree y container/volume identity. Derivar y validar el URL objetivo en memoria sin exponer secretos. Iniciar únicamente `roomforge-local-dev-postgres-1`.
5. **No repetir fixture fresh-DB:** R6 contiene tablas y `alembic_version`; no ejecutar migraciones ni limpiar.
6. **Corregir comparador con TDD — HECHO:** regresión RED observada (1 failed, 1 passed); normalizador canoniza solo el default `TRIM(BOTH FROM expr)`; GREEN 2 passed. No cambia operaciones de migración.
7. **Verificar sin escritura — HECHO:** backend 135 passed/2 R6 skipped, Ruff PASS, Pyright 0; comparación read-only del esquema existente PASS. Contenedor detenido y volumen preservado.
8. **Evidencia y cierre:** documentar el exit 1 del pytest original y la limitación de no poder repetir el fixture; comprobar <400 líneas y preparar commit/revisión del slice local. No publicar.

## Criterios de aceptación

- El test estructural falla antes del cambio y pasa después.
- Los tests SQLite locales, Ruff y Pyright pasan.
- No afirmar que la invocación original del pytest R6 quedó verde; terminó con exit 1 y no se repitió sobre la base ahora poblada.
- El revision ID `0004_pending_staff_email_uniq` está en la DB y la comparación read-only corregida de metadata pasa.
- Volumen `roomforge-local-dev_postgres_data` conservado; contenedor existente restaurado a estado detenido; ninguna limpieza.
- Informe conserva auth retries, el exit 1 original, normalización PostgreSQL y comparación read-only PASS; el work-unit debe permanecer bajo 400 líneas.

## Resultado — 2026-09-28

- Revision-ID: `0004_pending_staff_email_uniq` (29 chars); test estructural RED/GREEN y 4 casos SQLite reportados PASS.
- Dos primeras invocaciones R6 con URL local fallaron autenticación. Una tercera invocación, autorizada con el init config del contenedor y output capturado, terminó exit 1. No se afirma que el comando completo del test migratorio pasó; su salida original se suprimió.
- El estado read-only posterior en R6: rol `roomforge_local`, 7 tablas de aplicación + `alembic_version`, con `version_num=0004_pending_staff_email_uniq` (head). La comparación inicial encontró que PostgreSQL representa `trim(email)` como `trim(both from email)`.
- Se corrigió solo el normalizador del comparador mediante TDD: RED 1 failed/1 passed; GREEN 2 passed. Verificación independiente: `python -m pytest tests -q -p no:cacheprovider` con Python 3.14.6, R6 env unset y SQLite in-memory: 135 passed/2 R6 skipped; `python -m ruff check app tests`: PASS. Pyright del venv local del checkout raíz sobre `app tests`: 0 errors/warnings/informationals. El verificador ejecutó únicamente la comparación de metadata read-only contra la DB ya poblada: PASS para tablas, columnas/types/nullability/defaults, PK/FK/unique/index/check constraints. No ejecutó fixture, SQL migration ni Alembic en esa comparación.
- El primer traceback incluyó accidentalmente una contraseña local; no se copia aquí ni en memoria; tratarla como expuesta y rotarla si es válida.
- El contenedor está `exited`; el volumen sigue montado. No limpiar ni repetir fixture fresh-DB en esta base poblada.
- Sin stage/commit/review hasta documentar la limitación y revisar el presupuesto. No hubo publicación.
