# F02.2 — Evidencia de esquema y migraciones

> **Estado: completo (2026-09-29).** Los cuatro casos SQLite aislados pasan y la verificación PostgreSQL quedó completada bajo autorización explícita del usuario: base vacía → `head` con **12 pruebas en verde**, actualización desde `0004_pending_staff_email_uniq` en base desechable con datos que sobrevivieron, R6 real actualizada a `0011_reservation_chain_txns` sin diferencias de metadata, y downgrade/upgrade de un paso verificados. La cadena ya no contiene IDs de 42 caracteres: todas las revisiones miden ≤ 32. Las secciones siguientes conservan el registro histórico de los intentos previos y de la limitación, ya superada.

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

## Reactivación y verificación PostgreSQL completa — 2026-09-29

El usuario autorizó reactivar T3b para cerrar F02. Se trabajó sobre `main` en `be13a44` (F02 ya mergeado). El contenedor `roomforge-local-dev-postgres-1` permaneció **detenido** y su volumen `roomforge-local-dev_postgres_data` conservado; el puerto original 5434 estaba ocupado por un contenedor de otro proyecto (`ynab-postgres-1`), así que la R6 se montó en contenedores temporales con puerto de loopback aleatorio. No se detuvo ningún contenedor ajeno ni se eliminó volumen alguno.

Aclaración de identidad: el volumen contiene dos bases; la R6 objetivo es **`roomforge_r6_f02_t3_20260927`** (8 tablas al inicio: 7 de aplicación más `alembic_version`). La base `roomforge_local` del mismo volumen está **vacía** y no es el objeto de esta verificación.

### 1. Base vacía → `head` en PostgreSQL real

Contenedor descartable `postgres:16-alpine` con `--tmpfs` (sin volúmenes) y base con el prefijo exigido por la fixture:

```bash
python -m pytest tests/test_staff_identity_migration.py tests/test_staff_identity_postgres.py -q
```

**Resultado: 12 passed, exit 0.** La fixture aplicó `alembic upgrade head` desde una base completamente vacía y la comparación de metadata contra los modelos pasó sin diferencias: tablas, columnas/tipos/nullability/defaults, PK, FK, unique keys, índices y check constraints.

### 2. Actualización desde una revisión anterior, con datos presentes

En una base desechable: `alembic upgrade 0004_pending_staff_email_uniq`, sembrado de una `agency` y un `staff_account`, y luego `alembic upgrade head` (0005→0011).

**Resultado:** revisión final `0011_reservation_chain_txns`, **19 tablas** coincidentes con los modelos, la fila sembrada intacta (con su FK válida) y `_metadata_differences` sin diferencias. Esto cierra el punto de F02.2 sobre actualización desde una versión anterior.

### 3. R6 real actualizada a `head`

Respaldo previo: `pg_dump --format=custom` de la R6 a `D:\tmp\t3b-backups\r6_backup_before_upgrade.dump` (18 308 bytes). La R6 estaba en `0004_pending_staff_email_uniq` con **0 filas** en `agency` y `staff_account`, por lo que no había datos de usuario en riesgo.

**Resultado de `alembic upgrade head`:** revisión `0011_reservation_chain_txns`, **20 tablas** en `public` (19 de aplicación más `alembic_version`) y diferencias de metadata **ninguna**. La actualización quedó persistida en el volumen, verificado con un contenedor de comprobación posterior a la limpieza.

### 4. Reversibilidad (alcance declarado)

En la base desechable se ejecutó `alembic downgrade 0010_reservations` (la tabla `reservation_chain_transaction` desapareció y la revisión quedó en `0010_reservations`) y después `alembic upgrade head` (la tabla volvió y la revisión regresó a `0011_reservation_chain_txns`), con la fila sembrada intacta. Esto acredita **un paso** de la última revisión, no reversibilidad universal: la recuperación real depende de un respaldo probado, como el dump tomado antes de migrar la R6.

### 5. Defectos reales encontrados y corregidos

La reactivación encontró tres problemas que los intentos previos no habían podido observar:

1. **Test de concurrencia R6 con FK inválida.** `test_postgres_racing_recovery_code_logins_create_one_session` insertaba un `staff_account` con un `tenant_id` sin `agency` sembrada; PostgreSQL lo rechazaba con `ForeignKeyViolation`. Corregido sembrando `Agency(id=tenant_id)` antes de la cuenta.
2. **Defaults de servidor no declarados en el modelo.** La migración `0007` define `server_default` para `listing.approval_status` (`'draft'`), `listing.is_published` (`false`) y `listing.offer_version` (`1`), pero el modelo ORM solo tenía defaults de Python, así que la metadata no describía el esquema real. Corregido declarando `server_default=text("'draft'")`, `server_default=false()` y `server_default=text("1")`.
3. **Comparador de metadata incompleto frente a PostgreSQL.** Faltaba canonizar dos representaciones: los casts numéricos de literales (`base_price >= 0::numeric`) y el predicado de índices parciales tal como lo devuelve el inspector (`((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying])::text[]))`). Corregido con TDD, incluido un test de regresión con el texto exacto de `pg_indexes.indexdef`.

### 6. Verificación local y estado

- Suite local: **401 passed, 2 skipped**; Ruff `All checks passed!`; pyright **0 errores**.
- Contenedores temporales detenidos y eliminados; sin residuales; el contenedor original sigue detenido y el volumen `roomforge-local-dev_postgres_data` conservado.
- La credencial local que apareció en un traceback anterior sigue pendiente de rotación por decisión del dueño; no se reproduce en ningún registro nuevo.
