# Tareas de implementación — HU-007: Invitación y aceptación de agentes

**Trazabilidad:** PB-007 · HU-007 · CU-007 · RF-004/RF-006 · CP-006  
**Fuentes:** `openspec/changes/hu007-invitacion-agentes/proposal.md`, `openspec/changes/hu007-invitacion-agentes/specs/agent-invitations/spec.md`, `openspec/changes/hu007-invitacion-agentes/design.md`  
**Orden obligatorio:** RED → GREEN → TRIANGULATE → REFACTOR.  
**Regla:** no modificar HU-006, mobile ni otros artefactos SDD; no realizar commits ni push.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Initial estimated changed lines | 380–400 líneas modificadas |
| Observed budget status | El alcance implementado excedió el umbral de 400 líneas |
| 400-line budget risk | High — el umbral fue excedido |
| Delivery partition | Aprobada explícitamente por el usuario |
| Suggested split | Partición por superficie: backend y panel |
| Delivery strategy | Entrega particionada |
| Chain strategy | No especificada; no se infiere una topología de ramas o PR |

Decision needed before apply: No — la decisión explícita fue particionar la entrega.
Completed partitions: backend (`9cf04ab`, `c4163fe`, `6aaa68`, `f2ef8e5`, `fc8d76c`) y panel (`46950ed`).
Remaining gate: ejecución de CP-006 y cobertura residual explícitamente pendiente.
400-line budget risk: High — se continúa únicamente con la verificación pendiente de cada partición.

## Límites funcionales y evidencia

- La aceptación crea únicamente `pending`; no activa, desactiva, revoca ni reactiva membresías. <!-- sdd-owner: implementation -->
- No implementar membresía operacional, activación/desactivación de HU-008, RBAC de HU-009, `Plan.max_agents`, cambios de HU-006 ni superficies móviles. <!-- sdd-owner: implementation -->
- CP-006 debe quedar preparado con trazabilidad Web + Backend; este cambio no puede declarar CP-006 ejecutado sin evidencia independiente, fechada y reproducible. <!-- sdd-owner: implementation -->

## RED — contratos y pruebas que deben fallar primero

### Unidad R1 — Contrato y reglas de dominio backend

Inicio: confirmar fixtures y convenciones existentes en `backend/tests/` y módulos `backend/app/modules/identity/` y `backend/app/modules/tenant/`. Fin: las pruebas codifican los contratos sin implementar producción. Rollback: eliminar únicamente las pruebas nuevas de esta unidad.

- [x] Crear `backend/tests/test_hu007_agent_invitations.py` con pruebas RED de normalización `trim + lowercase`, TTL de 7 días, estados, hash SHA-256 sin token claro y generación segura. <!-- sdd-owner: implementation -->
- [ ] Añadir pruebas RED del servicio/repositorio para emisión, reinvitación atómica, fallo de entrega observable, membresía existente, reutilización de `UsuarioGlobal`, contraseña Argon2id para cuenta nueva y ausencia de sesión/permisos. <!-- sdd-owner: implementation -->
- [ ] Añadir pruebas RED de rollback transaccional y de aceptación single-use para cuenta, membresía e invitación, usando los dobles de persistencia existentes. <!-- sdd-owner: implementation -->

### Unidad R2 — Contrato HTTP backend

Inicio: fijar en pruebas los contratos del diseño. Fin: API tests fallan por rutas, schemas o dependencias ausentes. Rollback: retirar solo los casos RED añadidos.

- [x] En `backend/tests/test_hu007_agent_invitations.py` cubrir `GET /api/v1/tenant/agent-invitations`, `POST /api/v1/tenant/agent-invitations`, `POST /api/v1/agent-invitations/inspect` y `POST /api/v1/agent-invitations/accept`, incluyendo 401/403/422/409/410, respuestas sin secretos y `tenant_id` rechazado. <!-- evidencia: cobertura API/security enfocada: 61 tests passed; suite backend completa: 226 passed. --> <!-- sdd-owner: implementation -->
- [x] Probar que la autoridad administrativa proviene de `TenantContextResolver` y del principal autenticado, nunca de body, query string o headers enviados por el cliente. <!-- evidencia: cobertura API/security enfocada: 61 tests passed. --> <!-- sdd-owner: implementation -->

### Unidad R3 — Contrato del panel

Inicio: identificar pruebas y seam actuales de `panel/src/`. Fin: Vitest expresa requests, errores y estados de UI antes de sustituir la memoria local. Rollback: retirar las pruebas nuevas sin tocar la UI existente.

- [x] Añadir pruebas Vitest para requests exactas, token solo en body y contratos autenticados/públicos. <!-- evidencia: commit de panel 46950ed; Vitest completa: 13 archivos/53 tests passed. --> <!-- sdd-owner: implementation -->
- [ ] Completar en las pruebas del panel el mapeo de errores y la cobertura de los servicios/seams indicados. <!-- sdd-owner: implementation -->
- [ ] Cubrir estados `pending/accepted/invalidated/expired`, reinvitación, expiración, token no utilizable, membresía existente, error de red y contraseña condicional en la ruta pública. <!-- sdd-owner: implementation -->

## GREEN — implementación mínima para satisfacer RED

### Unidad G1 — Modelo y migración

Inicio: partir de la cabeza Alembic `0012_hu006_purge.py`. Fin: esquema HU-007 migrable y reversible de forma fail-closed. Rollback: revertir solo `0013` y modelos HU-007; no tocar tablas ni migraciones HU-004–HU-006.

- [x] Implementar en `backend/app/modules/tenant/models.py` `AgentInvitation`, `TenantAgentMembership` y `AgentInvitationEvent`, con estados, FKs, checks, timestamps, delivery status y ausencia de token/contraseña en claro. <!-- sdd-owner: implementation -->
- [x] Crear `backend/alembic/versions/0013_hu007_agent_invitations.py` dependiente de `0012_hu006_purge.py`, con tablas, índices, `UNIQUE(token_hash)`, índice parcial de pendiente por tenant/correo, unicidad tenant/usuario e historial de auditoría. <!-- sdd-owner: implementation -->
- [x] Implementar downgrade que elimine tablas solo vacías y falle explícitamente si contienen datos; verificar que no altera `usuario_global`, `tenant`, `Invitacion`, `TenantAdministrator`, `plan` ni `suscripcion`. <!-- evidencia: probe transaccional confirmó tablas/FKs/checks/índices y `HU-007 tables contain data; downgrade is disabled`; tras el rollback las tablas permanecen. --> <!-- sdd-owner: implementation -->

### Unidad G2 — Repositorio, servicio, notifier y contratos backend

Inicio: reutilizar `UsuarioGlobal`, Argon2id, reloj, token y contexto existentes. Fin: flujo de emisión/inspección/aceptación funcional y transaccional. Rollback: deshabilitar rutas HU-007 y conservar datos creados.

- [x] Crear `backend/app/modules/tenant/agent_invitation_repository.py` con transacciones, `SELECT ... FOR UPDATE`, consultas por hash/correo, cambios de estado, mapeo controlado de `IntegrityError` y bloqueo de membresías. <!-- sdd-owner: implementation -->
- [x] Crear `backend/app/modules/tenant/agent_invitation_service.py` y `backend/app/modules/tenant/agent_invitation_notifications.py`: normalizar correo, generar/hash token, TTL configurable de 7 días, reinvitar, registrar eventos y notificar después del commit sin devolver ni persistir el secreto. <!-- sdd-owner: implementation -->
- [x] Extender `backend/app/modules/tenant/schemas.py` con payloads/respuestas `extra="forbid"` y errores `UNAUTHORIZED`, `TENANT_ADMIN_REQUIRED`, `CLIENT_AUTHORITY_FIELD_FORBIDDEN`, `INVALID_EMAIL`, conflictos y `INVITATION_UNAVAILABLE`. <!-- sdd-owner: implementation -->
- [x] Crear `backend/app/modules/tenant/agent_invitation_router.py` y registrarlo en `backend/app/main.py`, resolviendo el tenant mediante `TenantContextResolver` y sin consultar `Plan.max_agents`. <!-- sdd-owner: implementation -->

### Unidad G3 — Integración del panel Web

Inicio: conservar autenticación, suscripción y login actuales. Fin: ninguna mutación de `InMemoryUserRepository` para esta superficie y aceptación pública operativa sin sesión automática. Rollback: restaurar solo el seam de gestión local si la integración no es viable.

- [x] Actualizar `panel/src/data/apiClient.ts` con métodos tipados para los cuatro contratos HU-007, envío del token en body y códigos de error normalizados sin interpolarlo en URLs o mensajes. <!-- sdd-owner: implementation -->
- [x] Actualizar `panel/src/application/userManagementService.ts` para usar `SessionService.request` en administración y `ApiClient.request` público en inspección/aceptación, sin enviar `tenant_id`. <!-- sdd-owner: implementation -->
- [x] Actualizar `panel/src/App.tsx` y `panel/src/features/user-management/UserManagementPage.tsx` para listar estados, emitir/reinvitar y presentar conflictos/red sin UI de activación, permisos o RBAC. <!-- sdd-owner: implementation -->
- [x] Crear `panel/src/features/agent-invitations/AgentInvitationAcceptancePage.tsx`, leyendo `#token` solo en memoria, solicitando contraseña según `inspect` y mostrando estados no sensibles. <!-- sdd-owner: implementation -->
- [ ] Eliminar `panel/src/domain/user.ts`, `UserRepository.ts`, `InMemoryUserRepository.ts` o fixtures locales únicamente si una búsqueda final confirma que no tienen consumidores fuera de HU-007. <!-- sdd-owner: implementation -->

## TRIANGULATE — integración, PostgreSQL y evidencia reproducible

### Unidad T1 — Verificación real de base de datos y concurrencia

Inicio: disponer de PostgreSQL local y fixtures de integración existentes. Fin: evidencia de migración, restricciones y carreras; rollback: detener la ejecución de integración sin modificar datos fuera del esquema HU-007.

- [x] Ejecutar la migración con `.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head` y verificar que Alembic queda en `0013 (head)` sobre PostgreSQL; la migración PostgreSQL fue verificada. <!-- evidencia: upgrade aplicado y `0013 (head)` confirmado. --> <!-- sdd-owner: implementation -->
- [x] Completar la verificación independiente de FKs, checks, índice parcial, unicidad tenant/usuario y downgrade protegido con datos. <!-- evidencia: probe transaccional confirmó tablas/FKs/checks/índices; el downgrade protegido falló con `HU-007 tables contain data; downgrade is disabled` y las tablas permanecieron tras el rollback. --> <!-- sdd-owner: implementation -->
- [x] Añadir/ajustar prueba PostgreSQL en `backend/tests/test_hu007_agent_invitations_postgres.py` para dos aceptaciones concurrentes del mismo token y dos reinvitaciones concurrentes, demostrando una sola cuenta/membresía y un único pendiente utilizable. <!-- evidencia: probe PostgreSQL real; aceptación concurrente produjo exactamente un `accepted` y un `InvitationUnavailableError`, un usuario global y una membresía pendiente; la reinvitación concurrente dejó una invitación pendiente utilizable y una invalidada. --> <!-- sdd-owner: implementation -->
- [ ] Verificar rollback ante fallo intermedio y que una invitación expirada se materializa como `expired` sin crear cuenta ni membresía. <!-- sdd-owner: implementation -->

### Unidad T2 — Suite completa y CP-006

Inicio: todas las unidades GREEN integradas. Fin: resultados reproducibles y límites de evidencia explícitos. Rollback: corregir solo la unidad que falle y repetir su verificación.

- [x] Ejecutar `.venv/Scripts/python.exe -m pytest backend/tests -q` y Vitest del panel, registrando los resultados disponibles para el expediente: backend `226 passed`; panel `13 files/53 tests passed`. CP-006 permanece sin ejecutar y no se declara cerrado. <!-- evidencia: suite backend completa 226 passed; cobertura enfocada API/security 61 passed; Vitest completa 13 archivos/53 tests passed. --> <!-- sdd-owner: implementation -->
- [ ] Comprobar manualmente que no se expone token, contraseña, JWT, `tenant_id` de autoridad ni detalles de enumeración en respuestas, logs, UI o notificador fake; registrar CP-006 como preparado/pendiente salvo evidencia independiente. <!-- sdd-owner: implementation -->

## REFACTOR — calidad sin alterar comportamiento

### Unidad F1 — Lint, tipos y mantenibilidad

Inicio: suite funcional en verde. Fin: calidad autoritativa limpia y diff dentro del presupuesto. Rollback: revertir exclusivamente simplificaciones de esta unidad.

- [x] Ejecutar `.venv/Scripts/python.exe -m ruff check backend/app backend/tests` y corregir hallazgos sin silenciar reglas; repetir la suite backend. <!-- evidencia: ruff clean; suite backend completa 226 passed. --> <!-- sdd-owner: implementation -->
- [x] Ejecutar `.venv/Scripts/pyright.exe backend/app backend/tests` y corregir errores de tipos; verificar también el typecheck/build configurado del panel. <!-- evidencia: pyright 0 errors; panel build passed. --> <!-- sdd-owner: implementation -->
- [ ] Revisar transacciones, locks, nombres de estados, contratos y archivos cambiados; confirmar que el total de líneas modificadas no supera 400 y que no se incorporaron objetivos excluidos. <!-- sdd-owner: implementation -->

## Acciones posteriores del parent

- [ ] Iniciar o reutilizar una revisión acotada del diff de HU-007, verificando trazabilidad, no-objetivos, evidencia PostgreSQL y límites de CP-006. <!-- sdd-owner: parent -->
- [x] Registrar la decisión explícita de particionar la entrega cuando el diff supera 400 líneas; la partición aplicada separa backend y panel. No se eligió implícitamente `stacked-to-main`, `feature-branch-chain` ni `size:exception`. <!-- sdd-owner: parent -->
- [ ] Ejecutar el gate de ciclo de vida SDD correspondiente sin modificar otros artefactos durante esta fase. <!-- sdd-owner: parent -->
