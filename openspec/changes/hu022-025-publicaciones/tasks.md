# Tareas — Contrato backend de publicaciones HU-022 a HU-025

- **Cambio:** `hu022-025-publicaciones` · **PB:** PB-028, PB-029, PB-030 · **HU:** HU-022, HU-023, HU-024, HU-025 · **CU:** CU-024, CU-025, CU-026
- **Fuentes:** [explore.md](./explore.md) · [preproposal.md](./preproposal.md) · [proposal.md](./proposal.md) · [spec.md](./specs/publications/spec.md) · [design.md](./design.md)
- **Superficie:** únicamente backend y contrato HTTP consumible por Web.
- **Modo:** strict TDD, orden global obligatorio **RED → GREEN → TRIANGULATE → REFACTOR**. No paralelizar tareas dentro de una fase ni iniciar una fase posterior con fallos de la anterior.
- **Artefacto de esta fase:** solo este archivo `openspec/changes/hu022-025-publicaciones/tasks.md`; no ejecutar `apply`/`verify`, migraciones reales, commits ni pushes.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~1.100–1.500 (11 superficies de producto permitidas + suite HTTP/integración y migración) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1: RED y contratos/seams → PR 2: persistencia durable + authorizer/guards → PR 3: workflow HTTP/envelopes → PR 4: TRIANGULATE, regresión y REFACTOR |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

> El tamaño estimado supera el presupuesto de revisión de 400 líneas. El usuario confirmó `auto-chain` con estrategia `stacked-to-main`; la implementación debe mantener cada unidad revisable y a no más de 400 líneas. Si el diff de una unidad también supera 400 líneas, debe detenerse y subdividirla, sin inferir `size:exception`.

## Superficies permitidas y exclusiones

Todas las tareas de implementación quedan restringidas a estos archivos:

- `backend/app/modules/publications/router.py`
- `backend/app/modules/publications/schemas.py`
- `backend/app/modules/publications/service.py`
- `backend/app/modules/publications/repository.py`
- `backend/app/modules/publications/models.py`
- `backend/app/modules/publications/authorizer.py` (nuevo)
- `backend/app/modules/publications/quality.py` (nuevo)
- `backend/app/modules/tenant/context.py`
- `backend/app/main.py`
- `backend/alembic/versions/<next>_hu022_publication_idempotency.py` (nuevo; `revision` y `down_revision` se resuelven contra el head real durante apply)
- `backend/tests/test_hu022_025_publicaciones.py` (nuevo)

No tocar panel, Flutter, `worker3d`, `contracts`, identidad/sesiones, propiedades, reservas, catálogo de permisos RBAC de HU-009, política de suscripción de HU-006, `docs/diagramas/Diagrama1.eapx`, otros cambios OpenSpec ni documentación académica. HU-026 no se implementa como historia nueva. CP-009, CP-010, CP-011 y CP-012 permanecen **`not executed`**.

## RED — contratos y pruebas que deben fallar primero

### RED-1 — Contrato DTO, headers y envelopes

- [ ] Escribir en `backend/tests/test_hu022_025_publicaciones.py` pruebas RED con `TestClient`/overrides para: payload exacto de los diez campos (`title`, `description`, `operation_type`, `price_amount`, `currency`, `location_policy`, `location_value`, `media_refs`, `model_3d_refs`, `attributes`), `extra="forbid"`, observación ausente/blanca, `X-Idempotency-Key` ausente/blanco/excesivo, parser `If-Match` solo en forma `"vN"`, y envelope `{code,message,details}` para 400/401/403/404/409/412/422. <!-- sdd-owner: implementation -->
- **Superficie exacta:** `backend/tests/test_hu022_025_publicaciones.py`.
- **Verificación:** las pruebas fallan por ausencia de rutas/DTOs y no aceptan todavía una implementación parcial.
- **Dependencia:** ninguna dentro de RED-1; es la primera tarea.

### RED-2 — Autoridad, roles, tenant y guards fail-closed

- [ ] Añadir pruebas RED en `backend/tests/test_hu022_025_publicaciones.py` para autoridad derivada de sesión: agente puede crear/reemplazar y enviar; administrador puede aprobar/rechazar/despublicar; agente no puede ejecutar comandos administrativos ni autoaprobar; tenant ajeno y autoridad ambigua devuelven `404 resource_not_found` o `403` seguro sin enumeración; ningún `tenant_id`, actor, rol, estado o versión del body altera la autoridad; y el `SubscriptionGuard` de `app.modules.tenant.guards` recibe la capability correcta sin matriz duplicada. <!-- sdd-owner: implementation -->
- **Superficie exacta:** `backend/tests/test_hu022_025_publicaciones.py`; referencias de lectura únicamente a `backend/app/modules/tenant/guards.py` y `backend/app/modules/tenant/context.py`.
- **Verificación:** fallan por ausencia del adaptador productivo y del servicio HTTP; no se simulan permisos inventados.
- **Dependencia:** RED-1.

### RED-3 — Workflow, inmutabilidad, versionado, atomicidad e idempotencia

- [ ] Añadir pruebas RED para creación/reemplazo `revision-replacement`, diez campos, versión monótona, revisión previa intacta y publicación vigente preservada; flujo válido submit/approve(representa publish)/reject/unpublish; transiciones inválidas sin mutación; auditoría server-side; `If-Match` 412; clave nueva, replay exacto, hash distinto 409 y carreras; rollback completo ante error. Incluir la expectativa de migración aditiva con unicidad `(tenant_id,idempotency_key)` y downgrade fail-closed con filas. <!-- sdd-owner: implementation -->
- **Superficie exacta:** `backend/tests/test_hu022_025_publicaciones.py`; el archivo de migración permitido queda reservado para GREEN.
- **Verificación:** todas las pruebas RED fallan por seams faltantes, sin afirmar migración ejecutada ni PostgreSQL real.
- **Dependencia:** RED-2.

### RED-4 — Gate de calidad/difusión y regresión de catálogo

- [ ] Añadir pruebas RED para `PublicationQualityGate`: `blocked` → 409 `quality_or_diffusion_blocked`, `unavailable` → 409 `quality_or_diffusion_unavailable` antes de mutar, y ausencia de campos del cliente como evidencia; verificar además regresión de `GET /api/v1/catalog/publications` y `/{publication_id}`: solo revisión `publicado`, sin auditoría, tenant cancelado visible según política pública existente, purged excluido y desaparición inmediata tras despublicar. <!-- sdd-owner: implementation -->
- **Superficie exacta:** `backend/tests/test_hu022_025_publicaciones.py`; `backend/app/modules/publications/router.py` solo se inspecciona para fijar la regresión.
- **Verificación:** falla por falta del puerto fail-closed y de integración mutadora; no declara CP académicos ejecutados.
- **Dependencia:** RED-3.

**Gate RED:** conservar el registro de fallos y confirmar que las pruebas no pasan por razones ajenas al contrato antes de comenzar GREEN. <!-- sdd-owner: implementation -->

## GREEN — implementación mínima para hacer pasar RED

### GREEN-1 — Persistencia durable e idempotencia

- [ ] Implementar `PublicationIdempotencyRecord` en `backend/app/modules/publications/models.py` y la migración aditiva `backend/alembic/versions/<next>_hu022_publication_idempotency.py`: UUID, tenant, clave acotada, hash SHA-256, status/body JSONB, timestamp y `UNIQUE(tenant_id,idempotency_key)`; resolver el head real durante apply, no modificar `0010_hu006_publication_revisions.py`, y hacer downgrade fail-closed si existen filas. <!-- sdd-owner: implementation -->
- [ ] Extender `backend/app/modules/publications/repository.py` con `lock_publication`, `get_revision_for_update`, `next_version`, `current_published_for_update`, `claim_idempotency` y `save_idempotency_result`; respetar que el repositorio no hace `commit`/`rollback`, aplicar lock order `suscripción → plan → publicación → revisión → publicada`, y usar unicidad como defensa final. <!-- sdd-owner: implementation -->
- **Verificación:** tests RED-3 pasan para replay, clave reutilizada, versionado y rollback con dobles; los checks Alembic se dejan preparados para verificación posterior, sin ejecutar migraciones reales en esta fase.
- **Dependencia:** todo RED en verde; GREEN-1 precede GREEN-2.
- **Rollback:** retirar únicamente la tabla/registro de idempotencia y sus métodos si aún no hay datos; nunca borrar revisiones, transiciones ni publicaciones.

### GREEN-2 — Autorizer, contexto y seams fail-closed

- [ ] Implementar `PublicationPrincipalAuthorizer` en `backend/app/modules/publications/authorizer.py`, resolviendo desde `MeResponse.id` una única autoridad activa de administrador/agente, usuario activo, membresía/invitación vigente y tenant/suscripción server-owned; fallar cerrado ante autoridad ausente o multi-tenant ambiguo y priorizar rol administrador si ambos roles pertenecen al mismo tenant. Ajustar `backend/app/modules/tenant/context.py` solo para permitir `administrator_id: UUID | None` sin romper administradores existentes. <!-- sdd-owner: implementation -->
- [ ] Definir `PublicationQualityGate` y adaptador por defecto en `backend/app/modules/publications/quality.py` como Protocol/decisiones `allowed|blocked|unavailable`; el default es `unavailable` fail-closed, sin proveedor inventado ni aceptar afirmaciones del request. <!-- sdd-owner: implementation -->
- **Verificación:** RED-2 y RED-4 pasan para autoridad server-owned, capabilities y gate; no se afirma que calidad/difusión haya sido verificada.
- **Dependencia:** GREEN-1.
- **Rollback:** desactivar seams y rutas mutadoras manteniendo catálogo público; no eliminar datos auditables.

### GREEN-3 — DTOs, servicio de comandos y transacciones

- [ ] Implementar en `backend/app/modules/publications/schemas.py` los DTOs exactos de contenido, observación, respuesta proyectada y envelope de error, sin `tenant_id` ni autoridad cliente; en `backend/app/modules/publications/service.py` componer authorizer, guard HU-006, workflow existente, repositorio, clock, idempotencia, concurrencia y gate, sin duplicar reglas de estado ni agregar `UPDATE` de contenido. <!-- sdd-owner: implementation -->
- [ ] Implementar en `backend/app/modules/publications/service.py` las operaciones: crear/reemplazar borrador, submit, approve→published atómico, reject y unpublish; verificar autoridad, suscripción, locks, `If-Match`, estado, observación y gate antes de mutar; persistir respuesta de replay y hacer un único commit lógico. Mantener revisión publicada hasta aprobación válida y marcar la anterior `despublicado` al reemplazarla. <!-- sdd-owner: implementation -->
- **Verificación:** RED-1 y RED-3 pasan en errores estables, atomicidad lógica, auditoría, inmutabilidad y preservación de publicación.
- **Dependencia:** GREEN-1 y GREEN-2.
- **Rollback:** retirar la composición nueva del servicio sin modificar invariantes del workflow legado.

### GREEN-4 — Rutas HTTP e integración global

- [ ] Agregar en `backend/app/modules/publications/router.py` las cinco rutas diseñadas (`POST /api/v1/publications/{publication_id}/revisions`, submit, approve, reject y unpublish), con sesión JWT, headers y DTOs validados, delegación exclusiva al servicio y traducción segura de excepciones a envelopes; conservar el catálogo público sin cambios semánticos. <!-- sdd-owner: implementation -->
- [ ] Integrar en `backend/app/main.py` el router mutador y el handler de `RequestValidationError` limitado a estas rutas; permitir `If-Match` en CORS sin cambiar el envelope histórico del catálogo ni introducir SQL/lógica de persistencia en el router. <!-- sdd-owner: implementation -->
- **Verificación:** RED-1, RED-2 y RED-4 pasan mediante contrato HTTP; OpenAPI contiene solo las rutas incluidas y los errores no revelan SQL, secretos ni tenants ajenos.
- **Dependencia:** GREEN-3.
- **Rollback:** retirar el router mutador de `main.py`; mantener disponibles las rutas públicas de catálogo.

**Gate GREEN:** ejecutar únicamente en apply los tests técnicos focalizados y los quality gates configurados; si una unidad cruza 400 líneas, detener y pedir partición antes de continuar. <!-- sdd-owner: implementation -->

## TRIANGULATE — triangulación independiente y regresiones

### TRIANGULATE-1 — Contrato contra seams internos

- [ ] Contrastar `backend/tests/test_hu022_025_publicaciones.py` con `backend/app/modules/publications/service.py`, `repository.py`, `models.py`, `authorizer.py` y `quality.py`: comprobar que cada resultado HTTP proviene de una regla/seam real, que no hay autoridad desde request y que el workflow existente sigue siendo la autoridad de estados. <!-- sdd-owner: implementation -->
- **Verificación:** `pytest` focalizado verde; documentar cualquier blocker de modelo sobre allowlists, límites semánticos o múltiples revisiones sin inventar reglas.
- **Dependencia:** GREEN completo.

### TRIANGULATE-2 — Persistencia, concurrencia y migración

- [ ] Verificar mediante pruebas aisladas y revisión de SQL generado que la idempotencia es durable, tenant-scoped y atómica; que los locks respetan el orden; que una carrera no deja registros parciales; y que la migración es aditiva, tiene downgrade fail-closed y no se declara aplicada en PostgreSQL. <!-- sdd-owner: implementation -->
- **Superficie:** `backend/alembic/versions/<next>_hu022_publication_idempotency.py`, `backend/app/modules/publications/{models,repository}.py`, `backend/tests/test_hu022_025_publicaciones.py`.
- **Dependencia:** TRIANGULATE-1.

### TRIANGULATE-3 — Regresión pública y difusión de evidencia

- [ ] Reejecutar la suite de catálogo contra `backend/app/modules/publications/router.py` y confirmar que solo la proyección publicada queda pública, que despublicar retira inmediatamente el recurso y que el historial no se expone; separar en el registro de apply las pruebas técnicas de cualquier evidencia académica. <!-- sdd-owner: implementation -->
- **Verificación:** no etiquetar ni presentar estas pruebas como CP-009, CP-010, CP-011 o CP-012; todos permanecen `not executed`, y GAP-092 sobre migraciones reales permanece abierto.
- **Dependencia:** TRIANGULATE-2.

## REFACTOR — limpieza sin cambio de contrato

### REFACTOR-1 — Simplificar seams y proteger límites

- [ ] Refactorizar únicamente las superficies permitidas para eliminar duplicación entre router/servicio/repositorio, centralizar códigos/envelopes, mantener nombres de dominio en inglés y documentación de artefactos en español; conservar fail-closed del authorizer, guard HU-006 y quality gate, sin ampliar a HU-009 ni crear política paralela. <!-- sdd-owner: implementation -->
- **Verificación:** suite completa, ruff y pyright verdes; diff revisado contra la lista de archivos permitidos y sin cambios funcionales.
- **Dependencia:** TRIANGULATE completo.

### REFACTOR-2 — Gate final de alcance y rollback

- [ ] Auditar el diff final: solo los archivos permitidos fueron modificados durante apply; no hay ejecución de `apply`/`verify` en esta fase de planificación, no hay commits/pushes, no hay migración real declarada, no se inventa evidencia de calidad/difusión y el rollback conserva catálogo, publicaciones, revisiones, transiciones e idempotencia auditable. <!-- sdd-owner: implementation -->
- **Dependencia:** REFACTOR-1.

## Acciones del parent posteriores a la implementación

- [ ] Iniciar o reutilizar una revisión acotada contra `spec.md` y `design.md`, incluyendo autorización server-owned, guard de suscripción, gate fail-closed, idempotencia durable, envelopes, regresión de catálogo y límites de evidencia. <!-- sdd-owner: parent -->
- [ ] Aplicar la partición segura del forecast `High` con `auto-chain` y `stacked-to-main`, manteniendo cada unidad dentro de 400 líneas. No crear ramas, PRs, commits ni aplicar cambios desde esta fase. <!-- sdd-owner: parent -->

## Trazabilidad rápida

| Unidad | Cobertura | Archivos principales |
|---|---|---|
| RED-1..4 | Requisitos de contrato, autoridad, workflow, idempotencia, guard, gate y catálogo | `backend/tests/test_hu022_025_publicaciones.py` |
| GREEN-1 | Revisión/idempotencia/migración/transacción | `models.py`, `repository.py`, migración nueva |
| GREEN-2 | Authorizer, contexto, suscripción y calidad/difusión | `authorizer.py`, `quality.py`, `tenant/context.py` |
| GREEN-3 | DTOs y casos de uso | `schemas.py`, `service.py` |
| GREEN-4 | HTTP, envelopes e integración | `router.py`, `main.py` |
| TRIANGULATE | Consistencia técnica, SQL, catálogo y evidencia | superficies permitidas + suite |
| REFACTOR | Calidad, alcance y rollback | superficies permitidas |

## Key Learnings

- El cambio expone un workflow interno existente; no debe rediseñar publicaciones ni duplicar sus reglas.
- La edición es reemplazo por nueva revisión, y la revisión publicada permanece vigente hasta una aprobación/publicación administrativa válida.
- La autoridad, el tenant y la suscripción deben resolverse server-side; el cliente nunca aporta identidad, rol, estado o versión confiables.
- La idempotencia durable requiere migración aditiva, locks ordenados y replay transaccional; la ejecución real de Alembic queda fuera de esta fase.
- El quality/diffusion gate debe ser un seam explícito y fail-closed: no se fabrica proveedor ni evidencia.
- Las pruebas técnicas de implementación no cierran CP-009..CP-012; esos casos permanecen `not executed` hasta evidencia académica independiente.
