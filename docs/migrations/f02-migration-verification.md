# F02.2 — Evidencia de esquema y migraciones

> **Estado: parcial; PostgreSQL bloqueado.** Los cuatro casos SQLite aislados pasan. Bajo autorización explícita se intentó la suite PostgreSQL en una base R6 nueva; cuatro pruebas pasaron y dos fallaron durante setup porque Alembic no puede guardar el ID de revisión de 42 caracteres en `alembic_version.version_num VARCHAR(32)`. No se completó una migración. La base de prueba quedó vacía (`alembic_version` ausente, 0 tablas de aplicación), el contenedor `roomforge-local-dev-postgres-1` fue detenido y su volumen se conservó. No se tocaron esquemas de bases preexistentes.

## Alcance y fuentes

El criterio de F02.2 en [`../plan-maestro-roomforge.md`](../plan-maestro-roomforge.md) solicita probar creación desde una base vacía y actualización desde una versión anterior cuando exista, además de documentar recovery/rollback. La redefinición describe FastAPI/Alembic/PostgreSQL como arquitectura propuesta, no como evidencia de ejecución.

Esta nota registra las pruebas ejecutadas en este worktree. El intento PostgreSQL usó exclusivamente la base nueva `roomforge_r6_f02_t3_20260927`; no constituye una migración PostgreSQL completada ni autoriza modificar otras bases.

## Grafo de revisiones observado

La cadena de revisiones del código es lineal:

```text
0001_staff_identity
  → 0002_staff_identity_align
  → 0003_agency_registry
  → 0004_staff_invitation_pending_email_unique (head)
```

`python -m alembic -c alembic.ini heads` informó `0004_staff_invitation_pending_email_unique (head)`. Es una consulta estática del grafo; no se conectó a una base ni se comprobó la revisión aplicada en ningún entorno.

Fuentes: `backend/alembic/versions/0001_staff_identity.py` a `0004_staff_invitation_pending_email_unique.py`, sus campos `revision`/`down_revision` y `backend/alembic/env.py`.

## Verificación SQLite ejecutada

Comando reproducible desde `backend/` con el entorno Python del proyecto activo:

```bash
python -m pytest -p no:cacheprovider tests/test_staff_identity_migration.py -q \
  -k "agency_migration or pending_invitation_migration"
```

**Resultado observado:** 4 passed, 1 deselected. Se ejecutaron estos casos:

- `test_agency_migration_backfills_all_distinct_tenant_ids_before_foreign_keys`
- `test_agency_migration_preserves_role_tenant_rules_and_enforces_references`
- `test_pending_invitation_migration_enforces_normalized_global_uniqueness`
- `test_pending_invitation_migration_refuses_legacy_duplicates_without_cleanup`

Estos casos crean SQLite en memoria con datos sintéticos y aplican directamente las funciones de `0003`/`0004` a un esquema pre-agencia. Verifican backfill de tenants, referencias, reglas rol/tenant, unicidad de invitaciones pendientes y rechazo de duplicados heredados sin limpiarlos. No migran `0001`/`0002`, no prueban la cadena Alembic completa ni demuestran equivalencia con PostgreSQL. Pytest emitió dos `SAWarning` porque SQLite no refleja un índice basado en expresión.

## Intento PostgreSQL autorizado y resultado

Se ejecutaron únicamente `backend/tests/test_staff_identity_migration.py` y `backend/tests/test_staff_identity_postgres.py` con `ROOMFORGE_R6_DATABASE_URL` y `DATABASE_URL` apuntando a `roomforge_r6_f02_t3_20260927`, en `127.0.0.1:5434`. El contenedor iniciado fue solo el PostgreSQL existente `roomforge-local-dev-postgres-1`; no se iniciaron Floci, API ni panel. No se guardaron URLs con contraseña ni credenciales reales.

**Resultado:** 4 passed, 2 errors. Los cuatro casos SQLite pasaron. `test_blank_database_upgrade_matches_identity_metadata` y `test_postgres_racing_recovery_code_logins_create_one_session` fallaron durante setup, al actualizar `alembic_version` de `0003_agency_registry` a `0004_staff_invitation_pending_email_unique`: PostgreSQL informó `value too long for type character varying(32)`. El ID nuevo tiene 42 caracteres. La prueba concurrente no alcanzó su cuerpo, por lo que la posible FK sin agencia sembrada sigue sin verificarse.

Después del intento, una consulta read-only confirmó que la base R6 conserva cero tablas de aplicación y no tiene `alembic_version`; la transacción de migración no dejó el esquema parcial. El contenedor fue detenido y el volumen `roomforge-local-dev_postgres_data` quedó conservado. La base de prueba también debe conservarse; no ejecutar DROP ni limpieza.

No se encontraron pruebas que marquen una revisión anterior en `alembic_version` y ejecuten una actualización Alembic completa hasta `head`. Los casos SQLite anteriores solo ejercitan `0003`/`0004`; `0002` contiene operaciones específicas de PostgreSQL.

La fixture exige `ROOMFORGE_R6_DATABASE_URL` con `postgresql+psycopg`, host loopback, puerto explícito, prefijo `roomforge_r6_` y una base completamente vacía. No elimina la base al terminar.

## Datos, recuperación y límites

- Los casos ejecutados usan exclusivamente datos sintéticos en SQLite en memoria; no se leyeron ni modificaron datos de usuario o producción.
- Ningún `downgrade`, rollback ni recuperación se ejecutó. No asumir que `alembic downgrade -1` restaura datos o es reversible. En un entorno persistente, la recuperación requiere un respaldo/snapshot probado y un procedimiento aprobado antes de migrar.
- Para una prueba real, el operador debe proporcionar y validar una base desechable dedicada que cumpla la fixture R6. El test no crea ni destruye la base por sí mismo.
- Durante la lectura se observó un posible bloqueo no confirmado en una prueba de concurrencia PostgreSQL: crea un agente con un `tenant_id` que parece no estar sembrado, pese a la FK a `agency.id`. Revisar ese fixture antes de interpretar una eventual falla; no se ejecutó.
- El usuario autorizó el intento descrito arriba con límites explícitos, que se respetaron. Cualquier cambio de la revisión o repetición de pruebas queda pausado hasta nueva autorización.

## Próximos pasos (estado al cierre del primer intento)

1. No modificar migraciones ni reanudar Docker/PostgreSQL hasta que el usuario decida cómo resolver el ID de revisión demasiado largo.
2. Si se autoriza un cambio y repetición, usar exclusivamente la base R6 ya autorizada (confirmando que sigue vacía) o pedir autorización antes de crear otra; ejecutar solo estos mismos dos archivos de tests y conservar todos los recursos.
3. Si se exige upgrade desde una versión previa, definir y probar una revisión de partida explícita en una base desechable autorizada. No inferir cobertura completa de los casos SQLite.

## Resultado de T3b tras autorización — 2026-09-28

El usuario autorizó corregir el ID, validar R6 y usar la vía administrativa del contenedor; se preservaron el target y volumen existentes, sin limpieza ni publicación.

- Se acortó `revision` a `0004_pending_staff_email_uniq` (29 chars), conservando filename, `down_revision` y operaciones; se añadió el guard de 32 caracteres.
- Primeras dos invocaciones con URLs locales fallaron autenticación antes de la fixture. La URL añadida al `.env` pasó las guardas de driver/host/puerto/target, pero no autenticó. Comparación in-memory, sin mostrar valores, detectó que sus credenciales no coinciden con el `POSTGRES_USER`/`POSTGRES_PASSWORD` inicial del contenedor; esa configuración no demuestra el estado actual de un volumen persistente.
- Con permiso administrativo se hizo una tercera invocación usando el init config del contenedor, solo en memoria y sin imprimirlo. El pytest terminó con exit 1 y su salida se suprimió; no se afirma que el comando original terminara en PASS.
- Lectura read-only posterior: rol `roomforge_local`, 7 tablas de aplicación más `alembic_version` y `version_num=0004_pending_staff_email_uniq` (head). El comparador inicial encontró solo diferencias de representación equivalentes: `trim(email)` frente a `trim(both from email)`.
- Se corrigió `_normalize_sql` mediante TDD, limitando la equivalencia al default BOTH. RED: 1 failed/1 passed; GREEN: 2 passed. La suite backend independiente pasó 135 tests, 2 R6 SKIP; Ruff PASS; Pyright 0 issues.
- Verificador independiente aplicó el comparador de metadata directamente a la base ya poblada, sin invocar fixture ni Alembic: PASS para tablas, columnas/tipos/nullability/defaults, PK, FK, unique keys, índices y checks. Esto acredita el schema actual, pero no prueba retroactivamente que el primer estado estuviera blank ni convierte el pytest original en PASS.
- El contenedor quedó `exited`; `roomforge-local-dev_postgres_data` permanece montado y preservado. No se limpió ni se ejecutó otra migración.
- El primer traceback imprimió accidentalmente una contraseña local; no se reproduce aquí ni en memoria; tratarla como expuesta y rotarla si es válida. Los outputs posteriores se capturaron y suprimieron.
- El work-unit de migración/comparador se comprometió como `66076bb` (134 líneas). Native review de ese candidato (`review-cf05394c9a6e1d35`, 5 archivos) quedó aprobada y acknowledged; el resumen no devolvió hallazgos adicionales. No hubo push/PR.
