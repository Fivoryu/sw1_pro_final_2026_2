# F04 — Inmuebles, publicaciones y catálogo

## Objetivo

Cerrar F04.1, F04.2 y F04.3 del `docs/plan-maestro-roomforge.md`, más la regresión de F04.4. No implementar UI (panel/apps), 3D, blockchain ni suscripciones.

## Hallazgo bloqueante (2026-09-30)

El paquete `openspec/changes/hu022-025-publicaciones/` (proposal, design, spec, tasks) **no es ejecutable en este repositorio**: describe un módulo `publications` con `Publication`, `PublicationRevision`, `PublicationRevisionTransition`, `PublicationRevisionWorkflow` y la migración `0010_hu006_publication_revisions.py` que no existen acá, y exige reutilizar una política de suscripción de HU-006 que tampoco existe. Evidencia completa en `docs/plan-maestro-roomforge.md` §1.4.3.

Estado real del sustrato, verificado por lectura del árbol en `main` (`8e86464`):

| Superficie | Estado |
|---|---|
| `GET /api/v1/listings` y `GET /api/v1/listings/{id}` | Implementado y probado (`backend/tests/test_catalog.py`) |
| `POST /api/v1/quotes` | Implementado (F05) |
| `PATCH` de depósito del inmueble | Implementado (`catalog/router.py`, `set_listing_deposit`) |
| Modelo `catalog.Listing` | Existe con `approval_status IN ('draft','pending','approved','rejected')` e `is_published`, `agency_id`, `operation`, `base_price`, `offer_version`, `city`, `zone`, `bedrooms`, `bathrooms`, `description`, `exact_address`, `photos` (JSON) y `ListingExtra` |
| Alta/edición de inmueble (F04.1) | **No existe**: los `Listing` solo se crean en fixtures de tests |
| Flujo de revisión/publicación (F04.3) | **No existe**: hay columnas de estado, ninguna transición, historial ni ruta |
| Fotografías (F04.2) | **No existe**: `photos` es un JSON sin validación, sin claves, sin estados y sin almacenamiento |
| Autorizador server-owned | Existe: `identity.session.get_active_staff` devuelve `ActiveStaff` con `role` y `tenant_id` |
| Suscripciones | **No existe** ningún módulo |

## Decisiones tomadas (2026-09-30)

1. **Sustrato:** sobre `catalog.Listing`, camino corto. Se descarta crear un módulo `publications` con revisiones inmutables versionadas: no tiene sustrato en este repositorio y multiplica el alcance sin pedido del plan maestro.
2. **Versionado:** editar un inmueble publicado lo devuelve a `draft` y lo retira del catálogo de inmediato; vuelve a publicarse solo con una aprobación administrativa nueva. La versión anterior no se conserva visible. Consecuencia asumida y declarada: el cliente ve desaparecer el inmueble mientras dura la revisión.
3. **Fotos (F04.2):** diferidas a su propio cambio. F04 cierra sin subida, validación ni estados de fotografías; `Listing.photos` queda como está (JSON sin validación) y el pendiente se registra en el plan.

Máquina de estados resultante, sobre las columnas existentes (`approval_status IN ('draft','pending','approved','rejected')` + `is_published`):

```text
draft    --submit (agente)-----------> pending
pending  --approve (admin)-----------> approved
pending  --reject (admin, motivo)----> rejected
approved --publish (admin)-----------> approved + is_published = true
approved + publicado --unpublish-----> approved + is_published = false
cualquiera --edit (agente)-----------> draft + is_published = false
```

El motivo es obligatorio en `reject`; en el resto de las transiciones la observación es opcional y siempre queda registrada.

## Alcance permitido

- `backend/app/modules/catalog/{router,schemas,service,models}.py` — rutas administrativas tenant-scoped y transiciones.
- `backend/alembic/versions/00XX_*.py` — solo si la persistencia lo exige (historial de transiciones), aditiva.
- `backend/tests/test_f04_publications.py` — suite nueva TDD estricto.
- `docs/api/f02-api-contract.md` — contrato del envelope y rutas nuevas.
- Este archivo y `docs/plan-maestro-roomforge.md`.

Fuera de superficie: `identity`, `agencies`, `reservations`, panel, apps Flutter, `contracts/`, `worker3d/`, `docs/diagramas/Diagrama1.eapx`.

## Restricciones

- TDD estricto (RED → GREEN → TRIANGULATE → REFACTOR) con el runner del proyecto: `<raiz>/.venv/Scripts/python.exe -m pytest tests -q` desde `backend/`, más `ruff check app tests` y `pyright app tests`.
- Autoridad siempre server-owned: nunca aceptar `tenant_id`, actor, rol, estado, timestamps ni versión desde el cliente.
- No ejecutar migraciones contra PostgreSQL real sin autorización explícita (GAP-092 sigue abierto).
- CP-009, CP-010, CP-011 y CP-012 permanecen `not executed`: la suite técnica no es evidencia académica.
- Esta sesión **no** tiene bloque `## SDD Session Preflight`, así que no se crean artefactos de fases SDD (proposal/spec/design/tasks) ni se lanzan subagentes de fase SDD. El trabajo se ejecuta como ODD y, al cerrar, el paquete OpenSpec viejo queda marcado como obsoleto.
- Presupuesto: si el diff supera las ~400 líneas, hay que detenerse y proponer partición (el propio paquete viejo lo advierte).

## Tareas

- [x] **F04-T0 — Resolver la decisión pendiente** con el usuario y registrar la respuesta en este archivo. Decidido el 2026-09-30: sustrato `catalog.Listing`, edición devuelve a borrador, fotos diferidas.
- [ ] **F04-T1 — Autorización y tenancy reutilizados.** Rutas administrativas que resuelven actor, rol y tenant con `get_active_staff`; recurso ajeno → `404` no revelador; agente sin permisos administrativos → `403`.
- [ ] **F04-T2 — Alta y edición de borrador (HU-022 / F04.1 / T1 del paquete).** Crear y reemplazar borrador con validación de payload; estado inicial `draft`; nunca mutar una versión previa si se elige el camino versionado.
- [ ] **F04-T3 — Envío a revisión (HU-023 / F04.3).** `draft → pending` con observación obligatoria y transición auditada.
- [ ] **F04-T4 — Aprobación y rechazo (HU-024 / F04.3).** Solo administrador; aprobación = `pending → approved` + publicación atómica; rechazo con motivo obligatorio; prohibición explícita de autoaprobación.
- [ ] **F04-T5 — Publicar y despublicar (HU-025 / F04.3).** `is_published` como proyección pública; la despublicación debe desaparecer del catálogo en la consulta siguiente.
- [ ] **F04-T6 — Historial mínimo.** Registro append-only de transiciones (actor, rol, tenant, fecha, observación) y su no exposición en el catálogo público.
- [ ] ~~**F04-T7 — Fotos y privacidad (F04.2)**~~ **Diferida** por decisión del usuario. No entra en esta unidad; queda registrada como pendiente de F04 en el plan maestro.
- [ ] **F04-T8 — Verificación y cierre.** pytest + ruff + pyright; regresión de `GET /api/v1/listings` (solo aprobados y publicados); límites y fallos declarados.

## Registro de ejecución

(vacío — se completa por work unit, con evidencia y límites)
