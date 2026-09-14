# Exploración — Activación y desactivación de membresías de agentes (HU-008)

- **Cambio:** `hu008-membresias-agentes`
- **Product Backlog:** PB-007
- **Historia:** HU-008 — Activar o desactivar membresías de agentes.
- **Caso de uso:** CU-008 — Gestión de membresías (activar/inactivar).
- **Caso de prueba:** CP-007.
- **Sprint / superficies:** Sprint 1 / Backend; contrato consumible por Web, sin implementar UI.
- **Estado:** exploración; no se modificó código de producto, no se ejecutaron pruebas ni migraciones y no se crearon artefactos posteriores.
- **Propósito acotado:** permitir que un administrador autorizado del tenant controle el ciclo de vida de membresías de agentes (`pending`, `active`, `inactive`, `revoked`), incluida la reactivación, con autorización derivada del contexto server-side, auditoría e invariantes concurrentes en PostgreSQL.

## 1. Fuentes y método

Se revisaron `openspec/config.yaml`, los artefactos de HU-007 (`proposal.md`, `specs/agent-invitations/spec.md`, `design.md`, `apply-progress.md`), la planificación/proceso de Sprint 1, la auditoría de reglas de negocio de Sprint 0 y el módulo `backend/app/modules/tenant/` (modelos, contexto, repositorio y router), además de la migración Alembic `0013_hu007_agent_invitations.py`.

La configuración confirma artefactos en español, código en inglés, arquitectura `router → service → repository`, TDD estricto y PostgreSQL/Alembic. CodeGraph/MCP no estuvo disponible en esta sesión; por ello el análisis estructural se hizo con referencias directas y búsquedas acotadas. No se afirma estado de `git`, pruebas o migraciones porque no se ejecutaron comandos de shell.

## 2. Contexto canónico

La planificación de Sprint 1 describe HU-008 como “Como administrador quiero activar o desactivar membresías de agentes para mantener una membresía activa por agente”. CP-007 exige:

1. Activar una membresía y dejarla `active`.
2. Activar otra del mismo agente, dejando la anterior `inactive` y solo una activa.
3. Desactivar o revocar una membresía, negando acceso y conservando la autoría histórica.

La auditoría fija además:

- **BR-A3:** solo el administrador del tenant incorpora y administra agentes.
- **BR-A6:** cada agente tiene como máximo una membresía activa; se conservan miembros históricos y existe movilidad.
- **BR-A7:** `inactive` y `revoked` niegan acceso sin borrar autoría histórica; la unicidad debe ser transaccional contra activaciones concurrentes.
- **BR-A21:** `members.manage` es una capacidad exclusiva del administrador; la autorización de capacidades y RBAC completo pertenecen a HU-009.

## 3. Estado actual verificado

### 3.1 Modelo y restricciones de HU-007

`backend/app/modules/tenant/models.py` ya contiene:

- `AgentMembershipStatus`: `pending`, `active`, `inactive`, `revoked`.
- `TenantAgentMembership` en `tenant_agent_membership`, con `tenant_id`, `usuario_global_id`, `invitation_id`, `status` y `created_at`.
- `UNIQUE(tenant_id, usuario_global_id)` (`uq_agent_membership_tenant_user`), que permite como máximo una fila histórica por usuario dentro de un tenant.
- `UNIQUE(invitation_id)` y check de los cuatro estados.

La migración `0013_hu007_agent_invitations.py` confirma las mismas restricciones. No existe índice parcial único sobre membresías `active`; por tanto, la unicidad operacional de HU-008 aún no está respaldada específicamente para carreras entre tenants o activaciones concurrentes. La fila de membresía no registra `activated_at`, `deactivated_at`, `revoked_at`, actor ni motivo.

HU-007 solo crea una membresía `pending`, no la activa, no cambia una existente y deriva activación/reactivación a HU-008. Su repositorio bloquea la membresía por `(tenant_id, usuario_global_id)` durante aceptación y conserva la fila histórica.

### 3.2 Autorización y superficies existentes

`TenantContextResolver.resolve_admin(principal_id)` obtiene un `TenantContext` desde `TenantRepository.resolver_contexto_administrador`; el contexto contiene `tenant_id`, `subscription_id` y `administrator_id`. El router de HU-007 ya demuestra el patrón correcto: principal JWT mediante `get_current_user`, resolución server-side y rechazo de `tenant_id` enviado por body, query o headers. HU-008 debe reutilizar este seam y nunca aceptar el tenant objetivo como autoridad del cliente.

No se observó endpoint, servicio ni prueba de ciclo de vida de membresía. El router de invitaciones expone estados de invitación y aceptación, no comandos de membresía. No se debe inferir que un agente autenticado tiene permisos de administración: la operación requiere el contexto de administrador del tenant.

### 3.3 Auditoría existente y límite

`AgentInvitationEvent` audita emisión, reemplazo, aceptación, expiración, invalidación y fallo de entrega, pero exige `invitation_id`. Es insuficiente como auditoría natural de activación, desactivación, revocación y reactivación, especialmente para registrar actor, transición, motivo y resultado. HU-008 deberá decidir entre una tabla/evento de ciclo de vida de membresía separada o una extensión compatible que no altere la semántica de HU-007.

## 4. Slice mínimo coherente

El cambio debería limitarse a backend y contrato HTTP:

1. **Consulta administrativa tenant-scoped:** listar u obtener membresías sin permitir seleccionar otro tenant; incluir identidad no sensible, estado y timestamps de ciclo de vida.
2. **Activación:** `pending` → `active`, con actor administrador autorizado.
3. **Desactivación:** `active` → `inactive`, negando acceso futuro y manteniendo la fila y autoría histórica.
4. **Revocación:** transición explícita a `revoked`, con motivo/actor auditables y política de terminalidad definida.
5. **Reactivación:** `inactive` (y, si el producto lo decide, `revoked`) → `active`, aplicando nuevamente la única membresía activa y registrando el evento. No crear una fila nueva ni duplicar cuenta global.
6. **Conflicto de activación:** al activar una membresía cuando otra del mismo agente está activa, desactivar la anterior dentro de la misma transacción, o rechazar si la política final no permite reemplazo; no dejar dos activas.
7. **Persistencia atómica:** bloqueo de filas relevantes, transición y auditoría en una transacción; restricciones PostgreSQL como última barrera, con traducción de conflictos a resultado de negocio.
8. **Autorización y acceso:** `active` es condición necesaria para acceso operativo futuro; `pending`, `inactive` y `revoked` no deben otorgarlo. La asignación de permisos queda fuera de este slice.

Los nombres de rutas, payloads y códigos deben fijarse en proposal/spec/design, no asumirse como contrato vigente.

## 5. Decisión crítica pendiente: alcance de “una activa”

Hay una tensión que debe cerrarse antes del diseño:

- `UNIQUE(tenant_id, usuario_global_id)` existente limita una fila por tenant, no una membresía activa global.
- La auditoría BR-A6 y el texto de HU-007 reservan para HU-008 una regla de una sola membresía activa por agente, mientras que también describen movilidad entre tenants.

La interpretación más fuerte y coherente con BR-A6/BR-A7 es un índice parcial único PostgreSQL sobre `usuario_global_id WHERE status = 'active'`, que impide simultáneamente dos tenants activos para el mismo agente. Si “una activa” significa solo por tenant, el índice debe ser `(tenant_id, usuario_global_id) WHERE status = 'active'`, aunque la unicidad de fila actual ya haga redundante la segunda columna. El diseño debe documentar explícitamente la elección, migración de datos existentes y qué ocurre al activar en un tenant mientras otro está activo.

Para reemplazar una activa por otra en forma segura, una estrategia candidata es tomar locks deterministas sobre las membresías del usuario, actualizar la anterior a `inactive`, actualizar la nueva a `active`, insertar auditoría y confirmar una única transacción. El índice parcial debe respaldar la garantía, no depender únicamente del orden de aplicación. La alternativa de constraint diferible o reintento controlado también debe evaluarse según PostgreSQL y SQLAlchemy.

## 6. Transiciones y reglas a cerrar

Debe acordarse la máquina mínima, incluyendo:

- `pending → active` como activación inicial.
- `active → inactive` como desactivación reversible.
- `active → revoked` como revocación administrativa.
- `inactive → active` como reactivación.
- Si `revoked → active` es reactivación permitida o estado terminal; el encargo menciona reactivación, pero la documentación actual no define esta transición.
- Rechazo de activación de una membresía inexistente, de otro tenant o ya activa, con errores no filtrantes.
- Idempotencia de repetir el mismo comando y comportamiento ante comandos concurrentes opuestos.
- Motivo obligatorio u opcional para revocar/desactivar y retención de timestamps de cada transición.

No cambiar credenciales de `UsuarioGlobal`, no crear membresías nuevas durante reactivación y no convertir una activación en asignación de rol o permisos.

## 7. Riesgos y gaps

- **GAP-HU008-SCOPE:** alcance global versus tenant de la única membresía activa; bloquea el índice y el comportamiento de movilidad.
- **GAP-HU008-STATE:** terminalidad de `revoked`, transiciones inválidas e idempotencia no están especificadas.
- **GAP-HU008-AUDIT:** el evento existente está ligado a invitaciones; falta contrato de auditoría de membresía (actor, transición, motivo, resultado y timestamps).
- **Concurrencia PostgreSQL:** dos activaciones, o activación y desactivación simultáneas, pueden violar invariantes sin locks deterministas e índice parcial; requiere pruebas reales PostgreSQL, no solo fakes.
- **Datos existentes:** HU-007 ya puede haber creado filas `pending`; la migración debe ser aditiva, validar duplicados y proteger downgrade sin borrar historial.
- **Autorización:** reutilizar `TenantContextResolver` sin aceptar `tenant_id`; revisar que toda consulta y mutación filtre por tenant resuelto y administrador activo.
- **Acceso efectivo:** login/sesiones y autorización de recursos pueden no consultar todavía `TenantAgentMembership`; HU-008 debe definir el seam mínimo de enforcement sin adelantar RBAC ni invalidar sesiones fuera de alcance.
- **Presupuesto:** backend, migración, auditoría y concurrencia pueden acercarse al límite canónico de 400 líneas. Si lo supera, pausar y solicitar partición; no inferir `size:exception`.

## 8. Exclusiones explícitas

Este cambio **no** incluye HU-009 (RBAC, catálogo/asignación de permisos ni autorización fina), publicación/revisión/catálogo de inmuebles, `Plan.max_agents`, suscripciones/cuotas, invitaciones o aceptación de HU-007, cambios de credenciales/verificación, React/panel, Flutter/mobile, worker 3D, contratos Solidity, notificaciones generales ni refactors no necesarios. Tampoco debe modificar `docs/diagramas/Diagrama1.eapx`.

## 9. Evidencia recomendada para la siguiente fase

Antes de apply: cerrar alcance de la invariancia y la máquina de estados; fijar contrato de auditoría y política de sesiones/acceso; identificar datos existentes y estrategia de migración. Durante TDD:

- tests de servicio para cada transición, actor no autorizado, tenant cruzado, idempotencia y estados inválidos;
- tests API sin `tenant_id` como autoridad y sin filtración de otros tenants;
- tests de repositorio para locks, rollback y auditoría atómica;
- integración PostgreSQL para índice parcial, migración, dos activaciones concurrentes, activación cruzada de tenants y comandos opuestos;
- regresión de HU-007, verificando que aceptación siga creando exactamente `pending`.

CP-007 permanece `not executed`; esta exploración no crea evidencia de ejecución.

## 10. Recomendación

Avanzar a `proposal` solo después de resolver `GAP-HU008-SCOPE` y `GAP-HU008-STATE`, usando como primer slice un backend/API tenant-scoped con auditoría y pruebas PostgreSQL. Mantener Web, mobile, publicación y HU-009 fuera del cambio; un consumidor UI podrá integrarse posteriormente contra el contrato estabilizado.
