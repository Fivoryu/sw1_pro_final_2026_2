# CI: cero skips y cero warnings en la suite de backend

Header: llevar la suite de backend del CI a "todos los tests pasan y sin warnings": los 6 skips actuales
pasan a ejecutarse (PostgreSQL real y Floci como servicios del job, PowerShell vía pwsh) y los 4 warnings
desaparecen arreglando su causa, no silenciándolos sin criterio.

## Specs

- S1: "Pero que no pasen algunos tests, que todos pasen y sin warnings" — la suite debe correr
  completa: 0 skipped, 0 warnings, 0 failed, tanto local (con servicios) como en el CI.
- S2: Elección del usuario: "Cero skips en CI (completo)" — Postgres y Floci como servicios del CI,
  pwsh para el test de provisioning, fix del mock y fixes de warnings. El árbol puede mostrar skips
  condicionales solo si el servicio no está (p. ej. local sin Docker); el CI no debe tener ninguno.
- S3: Los fixes de warnings deben atacar la causa: cookies por-request → cookies del cliente;
  SAWarning de índice expresional → filtro documentado en el módulo que refleja; deprecation
  httpx/httpx2 → instalar httpx2 (existe) en dependencias dev.
- S4: El test de provisioning redrive es hermético (mockea docker): el mock debe interceptar también
  `docker.exe` (el script de infra lo invoca con extensión) y la detección de PowerShell debe aceptar
  pwsh para correr en Linux.

## Tasks

- T1 (S3): quitar warning de cookies por-request en test_staff_identity.py (usar cookies del cliente).
- T2 (S3): filtrar documentado el SAWarning de índice expresional en test_staff_identity_migration.py.
- T3 (S3): agregar httpx2 a dev extras y verificar que la StarletteDeprecationWarning desaparece.
- T4 (S4): mock de docker.exe + detección pwsh en test_detection_local_provisioning.py.
- T5 (S2): ci.yml — levantar postgres (compose.postgres.yml) y floci (compose.local.yml), crear DBs
  vírgenes roomforge_f04_runner y roomforge_r6_runner, exportar ROOMFORGE_POSTGRES_DATABASE_URL y
  ROOMFORGE_R6_DATABASE_URL para pytest.
- T6 (S1, S2): verificación — suite local sin warnings (skips solo por servicios ausentes), suite CI
  completa con 0 skipped y 0 warnings. Commit(s) convencionales por unidad; evidencia = runs de CI.

## Log

## Log

- L1 (2026-10-16): "Pero que no pasen algunos tests, que todos pasen y sin warnings" — pedido original
  verbatim tras cerrar el fix del hang de CI (PR #43).
- L4 (2026-10-16): CI verde en el run 5 (38929484719) — Backend "748 passed" sin SKIPPED ni
  warnings summary, ruff y pyright OK. Evidencia acumulada por run: run 1 (38920390857) expuso el
  test R6 roto (AttributeError, T7); run 2 (38923512885) expuso docker.exe exigido por
  set-staging-lifecycle.ps1; run 3 (38925259619) expuso el drift de defaults reflejados
  (nextval autoincrement + comillas de pg_get_expr, normalizados en el test, sin tocar migraciones
  inmutables ni el modelo); run 4 (38927261057) expuso el tipado httpx2 (23 errores pyright:
  Response + TestClient.app como _WrapASGI2) resuelto con httpx2 import y el helper
  tests/testclient_app.py. Commits: 7289a15, 0e5f964, ce2738c, e9af554, e5442d6, 8bfd7a1, dcf3a02,
  1d46a16, d3ed46d, 20c43f0. Pendiente: merge del PR #44 (decisión del humano).
- L2 (2026-10-16): Elección de alcance del usuario: "Cero skips en CI (completo)" (opción 1 de 3).
- L3 (2026-10-16): Hallazgos de exploración: 6 skips = 3 por DB real (ROOMFORGE_POSTGRES_DATABASE_URL /
  ROOMFORGE_R6_DATABASE_URL unset), 2 por Floci no corriendo (test_local_provisioning_lifecycle), 1 por
  PowerShell en Linux (test_detection_local_provisioning redrive). 4 warnings = StarletteDeprecationWarning
  (httpx→httpx2), DeprecationWarning cookies per-request (test_staff_identity.py:447), SAWarning x2
  (índice expresional uq_staff_invitation_pending_normalized_email en test_staff_identity_migration).
  Bug del mock: set-staging-lifecycle.ps1 llama `docker.exe` y el mock solo define `docker`. httpx2
  instalable (pip --dry-run ok). R6 comparte engine vía Base.metadata.info (migration corre primero
  alfabéticamente) → una sola DB R6 basta.
