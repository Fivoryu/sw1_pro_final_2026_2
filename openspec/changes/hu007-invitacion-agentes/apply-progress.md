# Apply progress — HU-007

## Estado

- **Fase:** `sdd-apply` con entrega particionada; las particiones backend y panel están implementadas y la verificación residual permanece abierta.
- **Resultado:** `partial` — la decisión de particionar la entrega fue explícita y ya no está pendiente; no se declara cierre porque CP-006 no fue ejecutado y permanecen coberturas explícitamente pendientes.
- **Cambio activo:** `hu007-invitacion-agentes`.
- **Artefactos consumidos:** `proposal.md`, `specs/agent-invitations/spec.md`, `design.md`, `tasks.md`, `openspec/config.yaml`.
- **Status estructurado consumido:** candidato aprobado por el parent, modo `repo-local`, `artifactStore=openspec`, raíces permitidas en el workspace; no se inventó ni persistió otro token. La selección ambigua del snapshot inicial fue resuelta por el contexto de adquisición aprobado del parent.
- **Decisión de entrega:** particionar por superficie, con backend y panel como particiones independientes.
- **Acción pendiente exacta:** completar únicamente las coberturas residuales y ejecutar CP-006 con evidencia independiente. La concurrencia real de PostgreSQL y las restricciones/downgrade ya fueron verificadas. No se eligió implícitamente `stacked-to-main`, `feature-branch-chain` ni `size:exception`.

## Commits verificados de las particiones

### Backend

- `9cf04ab` — modelo y migración de invitaciones de agentes.
- `c4163fe` — servicio, notificaciones y esquemas de invitaciones.
- `6aaa68e` — persistencia de invitaciones y pruebas backend HU-007.
- `f2ef8e5` — API de invitaciones de agentes.
- `fc8d76c` — cobertura API/security y ajustes finales de la API de invitaciones de agentes.

### Panel

- `46950ed` — flujo de invitaciones de agentes, pruebas y página de aceptación.

## TDD Cycle Evidence

| Unidad | Test | Capa | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| R1/G2 backend | `backend/tests/test_hu007_agent_invitations.py` | Unit | ✅ 72 tests existentes relevantes | ✅ import falló porque el módulo no existía | ✅ 7 tests | ✅ normalización inválida, contraseña no coincidente y fallo de entrega | ✅ ruff + focused 7/7 |
| R3/G3 API | `panel/src/data/agentInvitations.test.ts` | Unit | ✅ 11 tests panel relevantes | ✅ métodos inexistentes (2 fallos) | ✅ 2/2 | ✅ inspección pública y administración autenticada | ✅ focused panel 15/15 + build |
| G3 aceptación | `panel/src/features/agent-invitations/AgentInvitationAcceptancePage.test.tsx` | Component | N/A (archivo nuevo) | ✅ contrato de página nuevo | ✅ 2/2 | ✅ cuenta nueva solicita password; cuenta existente no | ✅ build y focused green |

### Test Summary

- Backend focused API/security suite: **61 passed**.
- Backend full suite: **226 passed**.
- Backend lint: **ruff clean**.
- Backend type check: **pyright 0 errors**.
- Panel full Vitest: **13 files / 53 tests passed**.
- Panel build: **passed**.
- PostgreSQL: Alembic upgrade verified at **`0013 (head)`**; migration verification completed.
- PostgreSQL constraints/downgrade probe: **passed transactionally**; tables, FKs, checks, indexes, partial pending index and tenant/user uniqueness were present. With HU-007 data, downgrade raised **`HU-007 tables contain data; downgrade is disabled`** and the tables remained after rollback.
- Real PostgreSQL concurrency probe: **passed**; concurrent acceptance produced exactly one `accepted` and one `InvitationUnavailableError`, exactly one global user and one pending membership. Concurrent reinvitation left exactly one usable pending invitation and one invalidated invitation.
- CP-006: **not executed**; it remains prepared/pending and is not declared closed.

Los resultados agregados de las suites son validación posterior. No sustituyen ni amplían la evidencia RED/GREEN/TRIANGULATE/REFACTOR ya registrada en la tabla; no se inventa una nueva secuencia TDD a partir de los conteos.

## Trabajo aplicado y checkboxes persistidos

Se mantienen marcadas las filas de implementación respaldadas por los commits verificados. Se marcaron las tareas de cobertura API/security, restricciones y downgrade protegido, concurrencia real PostgreSQL, suites completas, ruff y pyright/build con la evidencia disponible.

Quedan sin marcar las filas cuya evidencia todavía no fue reportada: pruebas backend RED adicionales, rollback ante fallo intermedio, materialización de invitaciones expiradas, mapeo de errores y estados restantes del panel, comprobación manual de no exposición para CP-006, revisión del límite y eliminación de legacy. No se marca ninguna de esas tareas por inferencia.

## Archivos cambiados

- Backend: `app/modules/tenant/models.py`, `schemas.py`, `main.py`.
- Backend nuevos: `agent_invitation_repository.py`, `agent_invitation_service.py`, `agent_invitation_notifications.py`, `agent_invitation_router.py`, migración `0013_hu007_agent_invitations.py`, `tests/test_hu007_agent_invitations.py`.
- Panel: `src/App.tsx`, `src/data/apiClient.ts`, `src/application/userManagementService.ts`, `src/features/user-management/UserManagementPage.tsx`.
- Panel nuevos: `AgentInvitationAcceptancePage.tsx`, pruebas de API y aceptación.
- No se modificaron HU-006, mobile, `docs/diagramas/Diagrama1.eapx` ni los archivos dirty/untracked preexistentes.

## Deuda / desviaciones

- El alcance implementado excedió el forecast de 380–400 líneas y motivó la decisión explícita de particionar la entrega. Las particiones backend y panel ya tienen los commits enumerados arriba; la decisión no debe volver a registrarse como pendiente.
- Los artefactos locales `panel/src/domain/user.ts`, `UserRepository.ts`, `InMemoryUserRepository.ts` y fixtures se dejaron intactos, tal como se solicitó; la página conserva compatibilidad con el seam legacy y existen consumidores/tests preexistentes.
- La migración PostgreSQL está verificada en `0013 (head)`. El probe transaccional confirmó restricciones y downgrade protegido: ante datos, el downgrade falló con `HU-007 tables contain data; downgrade is disabled` y las tablas permanecieron tras el rollback.
- El probe real de concurrencia PostgreSQL confirmó aceptación single-use y reinvitación atómica: exactamente un usuario global, una membresía pendiente y una invitación pendiente utilizable, además de una invitación invalidada por la reinvitación concurrente.
- CP-006 permanece no ejecutado. Las suites, lint, tipos, build, API/security y migración verificados no se presentan como ejecución de CP-006.

## Tareas restantes

- Completar pruebas backend RED adicionales de servicio/repositorio, atomicidad y rollback; verificar también la materialización de invitaciones expiradas.
- Completar cobertura Vitest de mapeo de errores, estados administrativos, expiración, reinvitación y contraseña condicional no cubierta por evidencia actual.
- Ejecutar CP-006 con evidencia independiente, fechada y reproducible; hasta entonces debe permanecer como no ejecutado.
- Confirmar en la revisión pendiente el límite de líneas y la eliminación de legacy únicamente si la búsqueda final demuestra que no existen consumidores.
