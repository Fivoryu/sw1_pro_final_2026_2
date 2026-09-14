# Tareas de implementación — HU-008 Membresías de agentes

**Trazabilidad:** PB-007 / HU-008 / CU-008 / CP-007  
**Superficie:** `backend/` y contrato HTTP tenant-scoped  
**Orden obligatorio:** RED → GREEN → TRIANGULATE → REFACTOR  
**Límites:** no UI/mobile, publicaciones, contratos, producción, suscripciones/cuotas/facturación ni RBAC de HU-009.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 550–800 líneas (código, migración y pruebas) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1: persistencia/migración/repository; PR 2: service/router/correlación/seam; PR 3: integración PostgreSQL, regresión y evidencia |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

## Criterios de ejecución y parada

- [ ] Confirmar en `backend/` rama, estado base, suite, ruff y pyright; registrar archivos sucios y no sobrescribir cambios ajenos. <!-- sdd-owner: implementation -->
- [ ] Auditar `backend/app/modules/tenant/agent_invitation_repository.py`, `backend/app/modules/tenant/models.py`, `backend/tests/test_hu007_agent_invitations.py`, migraciones hasta `0013` y fixtures PostgreSQL; confirmar que HU-007 crea exactamente `pending` y que `backend/alembic/versions/0013_hu007_agent_invitations.py` no se modifica. <!-- sdd-owner: implementation -->
- [ ] Si el diff de `backend/app/`, `backend/alembic/versions/0014_hu008_membership_lifecycle.py` y `backend/tests/` supera 400 líneas cambiadas, conservar el último límite verde y detener la ampliación hasta acordar partición; no asumir `size:exception` ni continuar como una sola entrega. <!-- sdd-owner: implementation -->

## RED — pruebas primero

- [ ] En `backend/tests/test_hu008_agent_memberships.py`, escribir pruebas fallidas para toda la matriz: `pending→active`, `active→inactive`, `inactive→active`, `active→revoked`, transiciones inválidas, terminalidad de `revoked` e idempotencia sin cambios de timestamps ni auditoría. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_agent_memberships.py`, escribir pruebas RED de timestamps canónicos `created_at`, `activated_at`, `deactivated_at`, `revoked_at` y `occurred_at`: backfill de activos a `created_at`, activaciones efectivas, limpieza al reactivar, revocación única y conservación en idempotencias. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_agent_memberships.py`, escribir pruebas RED de reemplazo: conservar ambas filas, inactivar la activa previa, dejar una sola activa y producir una auditoría por transición en orden con el mismo `correlation_id`; cubrir un mismo usuario activo en dos tenants. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_agent_memberships.py`, escribir pruebas RED de autoridad e aislamiento: resolver el tenant exclusivamente con `TenantContextResolver`, rechazar actor sin administración con `TENANT_ADMIN_REQUIRED`, devolver el mismo `404` para inexistente/cross-tenant y rechazar `tenant_id` en body, query o headers. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_agent_memberships.py`, escribir pruebas RED de las rutas de `backend/app/modules/tenant/agent_membership_router.py`: 401, 403, 400, 404, 409 y 422; sobre `code`/`message`/`correlation_id` sin secretos, `reason` obligatorio/recortado/limitado/`extra=forbid`, respuestas 200 e idempotentes y correlación válida conservada o UUID generado. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_agent_memberships.py`, escribir pruebas RED de atomicidad y auditoría: fallo de inserción de auditoría o `flush` revierte estado, reemplazo y eventos; actor principal y contexto administrativo resuelto quedan registrados; no existe API ordinaria de update/delete. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_agent_memberships.py`, escribir pruebas RED del seam de `backend/app/modules/tenant/agent_membership_access.py`: únicamente `active` permite continuar; `pending`, `inactive` y `revoked` niegan sin RBAC, permisos, mutación de sesión ni credenciales. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_agent_membership_repository.py`, fijar contratos RED para `rollback()` previo, advisory lock determinista por `(tenant_id, usuario_global_id)`, `FOR UPDATE` ascendente por `id`, transacción única y mapeo de conflictos SQL. <!-- sdd-owner: implementation -->

## GREEN — implementación mínima

- [ ] Implementar `backend/alembic/versions/0014_hu008_membership_lifecycle.py` con `down_revision = "0013"`: añadir timestamps `TIMESTAMP WITH TIME ZONE`, backfillear solo activos (`activated_at = created_at`), ejecutar el precheck explícito de duplicados activos antes de soltar la unicidad histórica, reemplazarla de forma segura por el índice único parcial `(tenant_id, usuario_global_id) WHERE status = 'active'`, crear índices tenant-scoped, tabla/checks/FKs de auditoría, función y trigger append-only, y downgrade fail-closed solo para objetos y datos vacíos. <!-- sdd-owner: implementation -->
- [ ] Completar `backend/app/modules/tenant/models.py` con los timestamps y `AgentMembershipAudit`, incluyendo `actor_usuario_global_id`, `actor_administrator_id`, tenant efectivo, estados/transiciones permitidos y `occurred_at` UTC; preservar filas, identidad, `AgentInvitationEvent` y estados históricos. <!-- sdd-owner: implementation -->
- [ ] Implementar `backend/app/modules/tenant/agent_membership_repository.py` con `list_for_tenant`, `find_for_tenant`, `has_active_membership` y `transition_for_tenant`: rollback inicial, clave advisory determinista, locks de filas target/candidatas ordenados, validación bajo lock, reemplazo, timestamps, auditoría append-only, `flush`/`commit` únicos y rollback ante cualquier error. Los errores `40001` y `40P01` deben mapearse a 409 después de rollback, sin reintento automático. <!-- sdd-owner: implementation -->
- [ ] Implementar `backend/app/modules/tenant/schemas.py` con `reason` obligatorio, recortado, no vacío, máximo 500 y `extra="forbid"`; definir proyecciones/respuestas no sensibles y el sobre HU-008 con `code`, `message` y `correlation_id`. <!-- sdd-owner: implementation -->
- [ ] Implementar `backend/app/core/correlation.py` para conservar exactamente UUID canónico válido de `X-Correlation-ID` o generar UUID del servidor si falta/es inválido; integrar el valor en respuestas y auditorías efectivas. <!-- sdd-owner: implementation -->
- [ ] Implementar `backend/app/modules/tenant/agent_membership_service.py` y `backend/app/modules/tenant/agent_membership_router.py` con las cinco rutas exactas, dependencias actuales, resolución administrativa antes de mutar, tenant exclusivamente server-side, proyección segura y comandos conforme a la matriz. No recibir `tenant_id` como autoridad del cliente. <!-- sdd-owner: implementation -->
- [ ] Ajustar `backend/app/main.py` únicamente para adaptar 401 y 422 al sobre estable en `/api/v1/tenant/memberships...`; no instalar el sobre global ni alterar HU-007. <!-- sdd-owner: implementation -->
- [ ] Implementar `backend/app/modules/tenant/agent_membership_access.py` con consulta únicamente por tenant resuelto, principal y `status = 'active'`, devolviendo `ActiveMembershipContext` o `InactiveAgentMembershipError`; mantenerlo session-neutral y fuera de RBAC. <!-- sdd-owner: implementation -->
- [ ] Ajustar solo las guardas de `backend/app/modules/tenant/agent_invitation_repository.py` para consultar membresías activas y permitir historial no activo, sin cambiar router, payloads, `AgentInvitationEvent` ni la semántica de aceptación de HU-007. <!-- sdd-owner: implementation -->

## TRIANGULATE — verificación cruzada e integración

- [ ] En `backend/tests/test_hu007_agent_invitations.py`, añadir regresión puntual: una aceptación válida crea exactamente una membresía `pending`, conserva `AgentInvitationEvent(accepted)`, no crea `AgentMembershipAudit`, no altera historial/credenciales y mantiene contrato y sobres de HU-007. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_agent_membership_repository.py`, verificar con fakes y fallos inyectados orden determinista de locks, commit/rollback conjunto, reemplazo, actor y contexto administrativo, timestamps, multi-tenant, auditoría exacta y que `40001`/`40P01` producen rollback y 409 sin retry. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_postgresql.py` o fixture PostgreSQL existente, verificar upgrade `0013→0014` con filas existentes, precheck que falla antes de retirar la restricción ante activos duplicados, índice parcial, ausencia de unicidad histórica residual, checks/FKs y preservación de datos. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_postgresql.py` o fixture PostgreSQL existente, verificar trigger que rechaza `UPDATE` y `DELETE` de `agent_membership_audit`, y downgrade rechazado sin borrar cuando hay membresías/auditoría/dependencias y permitido únicamente en base completamente vacía. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_postgresql.py` o fixture PostgreSQL existente, ejecutar concurrencia real de dos activaciones del mismo `(tenant_id, usuario_global_id)` y de activate/deactivate/revoke en ambos órdenes; demostrar locks deterministas, serialización, latest committed transaction wins, ambas activaciones válidas 200, una sola activa y rollback sin auditoría parcial. <!-- sdd-owner: implementation -->
- [ ] En `backend/tests/test_hu008_postgresql.py` o fixture PostgreSQL existente, demostrar que el mismo usuario puede estar activo en dos tenants y que el seam activo-only no introduce RBAC ni invalida/modifica sesiones. <!-- sdd-owner: implementation -->
- [ ] Revisar el diff de los archivos permitidos contra `design.md`: no tocar `backend/alembic/versions/0013_hu007_agent_invitations.py`, panel React, apps Flutter, worker 3D, contratos Solidity, publicación, reservas/captura, `Plan.max_agents`, RBAC ni producción. <!-- sdd-owner: implementation -->

## REFACTOR — consolidación sin cambio semántico

- [ ] Ejecutar los comandos de `openspec/config.yaml`: `.venv/Scripts/python.exe -m pytest backend/tests -q`, `.venv/Scripts/python.exe -m ruff check backend/app backend/tests` y `.venv/Scripts/pyright.exe backend/app backend/tests`; corregir solo regresiones de HU-008 y conservar RED/GREEN/TRIANGULATE verdes. <!-- sdd-owner: implementation -->
- [ ] Extraer únicamente duplicación interna de errores, proyecciones, locks y helpers de pruebas en `backend/app/modules/tenant/agent_membership_*.py`, `backend/app/core/correlation.py` y `backend/tests/test_hu008_*.py`, sin ampliar `TenantService` ni alterar códigos, mensajes, correlación, timestamps o transacciones. <!-- sdd-owner: implementation -->
- [ ] Repetir en `backend/tests/test_hu008_postgresql.py` las verificaciones de migración, downgrade, trigger y concurrencia tras el refactor; registrar resultados reproducibles. <!-- sdd-owner: implementation -->

## Cierre y evidencia

- [ ] Preparar handoff técnico con archivos, comandos y resultados de suite/lint/tipos, migración 0014, precheck, índice parcial, trigger, rollback, locks y concurrencia; etiquetar la evidencia como verificación técnica, no como ejecución de CP-007. <!-- sdd-owner: parent -->
- [ ] Mantener CP-007 separado: registrar pasos y evidencia académica propia únicamente cuando se autorice, sin presentar pruebas unitarias, migraciones o probes PostgreSQL como CP-007. <!-- sdd-owner: parent -->
- [ ] Realizar revisión acotada y decidir antes de apply la partición/estrategia de PR si permanece el riesgo High de más de 400 líneas; no incorporar HU-009, publicaciones, UI/mobile, cuotas ni producción. <!-- sdd-owner: parent -->
