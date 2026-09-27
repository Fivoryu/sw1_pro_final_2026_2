# F02.2 — Evidencia de esquema y migraciones

> **Estado: parcial.** Se verificaron los casos SQLite aislados de `0003`/`0004` y se inspeccionó el head estático. No se ejecutó PostgreSQL, Alembic contra una base, Docker ni Compose. La verificación real PostgreSQL queda pendiente de autorización explícita.

## Alcance y fuentes

El criterio de F02.2 en [`../plan-maestro-roomforge.md`](../plan-maestro-roomforge.md) solicita probar creación desde una base vacía y actualización desde una versión anterior cuando exista, además de documentar recovery/rollback. La redefinición describe FastAPI/Alembic/PostgreSQL como arquitectura propuesta, no como evidencia de ejecución.

Esta nota registra únicamente las pruebas ejecutadas en este worktree. No constituye evidencia de migración contra una base PostgreSQL real ni autoriza modificar bases compartidas.

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

## Cobertura existente no ejecutada

`backend/tests/test_staff_identity_migration.py::test_blank_database_upgrade_matches_identity_metadata` prepara una base PostgreSQL R6 vacía, ejecuta `alembic upgrade head` y compara el esquema con `Base.metadata`. También existe cobertura PostgreSQL en `backend/tests/test_staff_identity_postgres.py`.

No se encontraron pruebas que marquen una revisión anterior en `alembic_version` y ejecuten una actualización Alembic completa hasta `head`. Los casos SQLite anteriores solo ejercitan `0003`/`0004`; `0002` contiene operaciones específicas de PostgreSQL.

La fixture de PostgreSQL exige `ROOMFORGE_R6_DATABASE_URL` con `postgresql+psycopg`, host loopback, puerto explícito, nombre con prefijo `roomforge_r6_` y una base completamente vacía. Ejecuta migraciones y deja datos/esquema en esa base; no la elimina al terminar. No se registran URLs ni credenciales en esta nota.

## Datos, recuperación y límites

- Los casos ejecutados usan exclusivamente datos sintéticos en SQLite en memoria; no se leyeron ni modificaron datos de usuario o producción.
- Ningún `downgrade`, rollback ni recuperación se ejecutó. No asumir que `alembic downgrade -1` restaura datos o es reversible. En un entorno persistente, la recuperación requiere un respaldo/snapshot probado y un procedimiento aprobado antes de migrar.
- Para una prueba real, el operador debe proporcionar y validar una base desechable dedicada que cumpla la fixture R6. El test no crea ni destruye la base por sí mismo.
- Durante la lectura se observó un posible bloqueo no confirmado en una prueba de concurrencia PostgreSQL: crea un agente con un `tenant_id` que parece no estar sembrado, pese a la FK a `agency.id`. Revisar ese fixture antes de interpretar una eventual falla; no se ejecutó.
- El responsable F01 indicó que no puede autorizar una base desechable ni operaciones Docker. La verificación PostgreSQL permanece pausada hasta recibir del usuario autorización y límites explícitos.

## Próximos pasos

1. Mantener sin cambios Docker/PostgreSQL hasta contar con autorización explícita del usuario.
2. Con una base R6 desechable aprobada, ejecutar el caso de creación vacía y la suite PostgreSQL pertinente; registrar resultados exactos y cualquier corrección de fixture por separado.
3. Si se exige upgrade desde una versión previa, definir y probar una revisión de partida explícita en otra base desechable. No inferir cobertura completa de los casos SQLite.
