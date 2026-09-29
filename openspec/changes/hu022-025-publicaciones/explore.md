# Exploración — Publicaciones HU-022 a HU-025

- **Cambio:** `hu022-025-publicaciones`
- **Historias:** HU-022 crear y editar borrador; HU-023 enviar a revisión; HU-024 aprobar o rechazar; HU-025 publicar o despublicar.
- **Product Backlog:** PB-028, PB-029 y PB-030.
- **Casos de uso:** CU-024, CU-025 y CU-026.
- **Casos académicos:** CP-009, CP-010, CP-011 y CP-012 (CP-012 también cubre HU-026).
- **Superficie propuesta:** backend y contrato HTTP consumible por Web; sin implementación de panel, mobile, worker 3D ni contratos Solidity.
- **Estado:** exploración; no se modificó código de producto, no se ejecutaron pruebas, migraciones ni comandos `apply`/`verify`.
- **Idioma:** español profesional y neutral para artefactos; identificadores y rutas HTTP en inglés.

## 1. Fuentes y método

Se revisaron la configuración OpenSpec, la trazabilidad de Sprint 0, las reglas de negocio, la planificación y el proceso por HU de Sprint 1, el avance del Sprint 1, los módulos backend de `publications`, las migraciones Alembic relacionadas, las pruebas existentes y los artefactos archivados de HU-006. CodeGraph/MCP no estuvo disponible como herramienta en esta sesión; el análisis estructural se realizó mediante lectura y búsquedas acotadas de referencias directas. No se afirma estado de `git`, pruebas o migraciones porque no se ejecutaron comandos de shell.

La configuración del repositorio establece fases `explore → proposal → spec → design → tasks → apply → verify → archive`, artefactos en español, TDD estricto, arquitectura FastAPI/SQLAlchemy/PostgreSQL/Alembic y prohibición de commits durante SDD. El preflight de esta sesión fija además el backend de artefactos OpenSpec, ejecución automática, estrategia `ask-on-risk` y presupuesto de revisión de 400 líneas.

## 2. Hechos canónicos del producto

### 2.1 Trazabilidad

La matriz `docs/sprint-0/ids-trazabilidad.md` relaciona:

- **PB-028 / RF-019 / HU-022 / CU-024:** editor de borrador de publicación.
- **PB-029 / RF-019 / HU-023-HU-024 / CU-025:** revisión y aprobación administrativa.
- **PB-030 / RF-021 / HU-025-HU-026 / CU-026:** publicación/despublicación y catálogo global.

Las cuatro historias son de prioridad `Must`, están asignadas al Sprint 1 y las plataformas registradas son principalmente Web + Backend para PB-028/PB-029, y Backend + app cliente + Web para PB-030. El alcance solicitado para este cambio queda limitado al contrato backend; HU-026 no se incorpora como historia a implementar, aunque su catálogo existente sea una dependencia observable.

### 2.2 Criterios y reglas observados

`docs/scrum/sprint-1/01-sprint-planning.md` y `02-proceso-por-hu.md` documentan:

- HU-022: crear el borrador con título y operación de venta o alquiler; guardar cambios sin alterar publicaciones existentes; visibilidad exclusiva del tenant propietario.
- HU-023: `borrador → en_revision`, registrando actor y fecha; requiere permisos; el agente no puede autoaprobar.
- HU-024: aprobación o rechazo administrativo, con verificación de redacción y difuminado; rechazo con observaciones obligatorias.
- HU-025: una publicación publicada aparece en el catálogo; una despublicada desaparece inmediatamente; la despublicación queda auditada.
- Estados previstos: `borrador`, `en_revision`, `publicado`, `rechazado` y `despublicado`; las transiciones inválidas no deben mutar el estado.

La auditoría `docs/sprint-0/auditoria-br.md` agrega BR-C1 (actor, fecha y observaciones por transición), BR-C2 (el agente no puede autoaprobar), BR-C3 (catálogo solo publicado), BR-C4 (cambios comerciales crean una nueva revisión y conservan la versión publicada hasta aprobar), BR-C8 (defectos funcionales de reconstrucción bloquean publicación) y BR-B7/B8 (política durante cancelación y purga del tenant). Estas reglas son evidencia de negocio, no evidencia de ejecución.

### 2.3 Estado académico de evidencia

`docs/avance/sprint-1.md` registra HU-022, HU-023, HU-024 y HU-025 como “implementadas por superficie”, pero declara que no existe evidencia del flujo Web/API completo. CP-009, CP-010, CP-011 y CP-012 permanecen `not executed`. Por lo tanto, la existencia de código interno no permite declarar cerrado ningún caso académico ni afirmar integración productiva.

## 3. Estado backend observado

### 3.1 Modelo y persistencia

`backend/app/modules/publications/models.py` contiene:

- `Publication`, tenant-scoped, asociada a `Property`, con estado, versión publicada y timestamps de publicación/despublicación.
- `PublicationRevision`, con versión monótona por publicación, contenido comercial completo, actor creador, rol, estado y `published_at`.
- `PublicationRevisionTransition`, con publicación/revisión, estado anterior y nuevo, actor, rol, timestamp y observación.
- Enumeraciones con los cinco estados funcionales, usando nombres de código en inglés y valores de dominio en español.

La migración `backend/alembic/versions/0010_hu006_publication_revisions.py` crea revisiones y transiciones, unicidad de versión, índice de revisión publicada y triggers PostgreSQL para impedir actualizar/eliminar revisiones y mutar el historial de transiciones. También define downgrade que falla si ya existen datos. No se ejecutó esa migración en esta exploración.

### 3.2 Workflow interno

`backend/app/modules/publications/service.py` expone `PublicationRevisionWorkflow` como seam interno:

- `create_draft(...)` autoriza actor y tenant, bloquea la publicación, exige el conjunto completo de contenido y crea una nueva revisión `borrador` con versión siguiente y transición auditada.
- `submit_for_review(...)` permite únicamente `borrador → en_revision`.
- `publish(...)` permite únicamente `en_revision → publicado`, exige administrador y evita que un agente apruebe su propia revisión; despublica la versión anterior cuando corresponde.
- `reject(...)` permite `en_revision → rechazado` y exige administrador.
- `unpublish(...)` permite `publicado → despublicado` y exige administrador.
- Cada transición exige una observación no vacía y utiliza un authorizer server-owned que devuelve actor, rol y tenant.

El workflow no expone por sí mismo rutas HTTP. Además, `create_draft` crea una revisión nueva y no existe una operación explícita observada para editar una revisión `borrador`; la revisión es inmutable en base de datos. Esto hace necesario definir si “editar” significa reemplazar/crear una nueva revisión o actualizar un borrador mediante otra representación, sin romper la inmutabilidad documentada.

### 3.3 Rutas HTTP actuales

`backend/app/modules/publications/router.py` registra únicamente `GET /api/v1/catalog/publications` y `GET /api/v1/catalog/publications/{publication_id}`. Estas rutas son una proyección pública de revisiones publicadas, rechazan parámetros no permitidos y no reciben `tenant_id` como autoridad. No se observó un router HTTP para crear/editar borradores, enviar a revisión, aprobar, rechazar, publicar o despublicar.

Los esquemas actuales (`schemas.py`) describen solo la respuesta pública del catálogo. No se observaron esquemas de comando ni respuestas administrativas para el workflow.

### 3.4 Pruebas y trabajo previo

`backend/tests/test_hu006_slice3_catalog.py` verifica seams internos: autorización fail-closed, aislamiento de tenant, uso del rol/identidad del authorizer, creación de revisiones, transición de envío, prohibición de autoaprobación, publicación administrativa, versionado y triggers append-only. Estas son pruebas técnicas del workflow interno; no sustituyen CP-009..CP-012 ni prueban un contrato HTTP completo.

El workflow fue introducido como parte del cambio archivado de HU-006 y también está reflejado en `openspec/specs/tenant-subscription/spec.md`: revisiones completas e inmutables, estados del workflow, prohibición de autoaprobación y auditoría no pública. Este cambio debe reutilizar y aclarar ese contrato, no duplicar reglas incompatibles.

## 4. Propuesta de alcance para la siguiente fase

La fase `proposal` debería convertir el workflow interno existente en un contrato backend/API verificable, manteniendo la arquitectura `router → service → repository` y el authorizer server-owned:

1. Definir operaciones tenant-scoped para consultar el contexto de publicación y ejecutar creación/edición de borrador, envío, aprobación, rechazo, publicación y despublicación.
2. Definir rutas, métodos, payloads, respuestas, códigos de error, autenticación y autorización sin aceptar tenant, actor, rol o estado como autoridad del cliente.
3. Preservar la revisión publicada mientras exista una nueva revisión en borrador o en revisión, según BR-C4.
4. Mantener historial de transiciones append-only con actor, fecha y observación; evitar exponerlo en el catálogo público.
5. Hacer explícita la relación entre aprobar (`en_revision → publicado`) y publicar/despublicar de HU-025, porque la documentación académica agrupa responsabilidades de agente/admin de forma más amplia que el workflow actual.
6. Cubrir con TDD el contrato HTTP, autorización cross-tenant, estados inválidos, observaciones, aislamiento de catálogo y regresión del catálogo público. La ejecución académica de CP-009..CP-012 debe permanecer separada de la verificación técnica.

No se propone todavía un nombre concreto de ruta, payload final, política de idempotencia, mecanismo de permisos finos ni cambios de modelo: deben fijarse en `proposal`, `spec` y `design` con evidencia adicional.

## 5. Gaps y decisiones bloqueantes

- **GAP-HU022-EDIT:** no está definido cómo editar un borrador si las revisiones son inmutables y `create_draft` solo crea una nueva revisión. Debe decidirse si se edita una entidad borrador separada, se reemplaza mediante nueva revisión o se delimita HU-022 a creación más una operación aún no observada.
- **GAP-HU022-CONTENT:** el workflow exige los diez campos de contenido completos, mientras que la aceptación académica solo menciona título y operación. Deben fijarse campos obligatorios, validaciones y valores permitidos sin inventar requisitos.
- **GAP-HU023-ROLES:** el backend observado autoriza agentes y administradores mediante un seam, pero no existe router de workflow ni contrato público de permisos. Debe conectarse el authorizer con el contexto de membresía/RBAC vigente sin adelantar HU-009.
- **GAP-HU024-HU025-RESPONSIBILITY:** la aceptación de HU-024 dice que aprobar cambia a `publicado`, mientras HU-025 habla de publicar/despublicar y permite agente/admin. El servicio observado reserva aprobación/publicación y despublicación al administrador. Esta diferencia debe resolverse antes de especificar rutas y actores.
- **GAP-HU024-QUALITY:** la verificación de difuminado y la condición de calidad de reconstrucción están documentadas como reglas, pero no se observó un servicio, contrato o fuente de estado que permita comprobarlas desde el workflow.
- **GAP-HU025-VERSIONING:** debe fijarse si toda nueva revisión aprobada reemplaza automáticamente la versión publicada (comportamiento parcialmente observado en `publish`) y cómo se distingue aprobación de reemplazo/publicación explícita.
- **GAP-HU025-AUDIT:** existe auditoría de transición con observación, pero no se observó un endpoint administrativo para consultar historial ni se debe asumir que ese historial será público.
- **GAP-HU-SUBSCRIPTION:** las reglas de suscripción bloquean ciertas mutaciones en estados `canceled_read_only`, `past_due` y `suspended`; debe definirse el guard aplicable a cada comando sin duplicar la política de HU-006.
- **GAP-HU-HTTP:** no existe contrato HTTP administrativo observado: faltan rutas definitivas, códigos de error, respuestas, idempotencia y límites de payload.
- **GAP-HU-CP:** CP-009..CP-012 siguen `not executed`; cualquier prueba nueva de implementación no constituye evidencia académica de esos casos.
- **GAP-HU-MIGRATION:** el repositorio registra migraciones del Sprint 1 pendientes de ejecución real (GAP-092). No debe afirmarse que las tablas de publicaciones están aplicadas en PostgreSQL sin una ejecución verificable.
- **Presupuesto:** backend, contrato HTTP, posibles guards y pruebas podrían superar el presupuesto de 400 líneas. Si el diff lo supera, la estrategia `ask-on-risk` exige detenerse y decidir partición; no se infiere una excepción.

## 6. Exclusiones explícitas

Este cambio no implementa ni especifica como entregable principal:

- HU-026 catálogo global como nueva historia, favoritos, reservas, precios/versionado comercial adicional o acceso temporal.
- HU-009 RBAC completo, catálogo de permisos o autorización fina no existente; solo el seam mínimo necesario para autorizar el workflow.
- Panel React, aplicaciones Flutter, integración visual, worker 3D, Meshroom, S3/SQS, contratos Solidity, pagos, notificaciones generales o producción.
- Verificación académica de CP-009..CP-012, ejecución de migraciones, pruebas de integración real o `verify` en esta fase.
- Rediseño no necesario de identidad, sesiones, tenancy o suscripciones.
- Edición de `docs/diagramas/Diagrama1.eapx`.
- Commits, pushes y cambios de código de producto.

## 7. Recomendación

Avanzar a `proposal` únicamente como contrato backend-first, después de resolver al menos `GAP-HU022-EDIT`, `GAP-HU024-HU025-RESPONSIBILITY`, `GAP-HU023-ROLES` y `GAP-HU-HTTP`. La siguiente fase debe conservar como hechos el workflow interno y el catálogo público existentes, presentar las rutas administrativas como propuesta, y no declarar HU-022..HU-025 completadas mientras CP-009..CP-012 continúen sin ejecución.
