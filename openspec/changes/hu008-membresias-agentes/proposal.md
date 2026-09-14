# Propuesta SDD — HU-008 Membresías de agentes

- **Cambio:** `hu008-membresias-agentes`
- **Product Backlog:** PB-007
- **Historia de usuario:** HU-008 — Activar o desactivar membresías de agentes.
- **Caso de uso:** CU-008 — Gestión de membresías (activar/inactivar).
- **Caso de prueba académico:** CP-007.
- **Superficie:** Backend y contrato HTTP consumible por Web; sin implementación de UI.
- **Estado:** Propuesta.
- **Idioma del artefacto:** Español profesional y neutral.

## 1. Intención y problema

RoomForge ya puede crear membresías `pending` durante el flujo de invitaciones de HU-007, pero no dispone de un ciclo de vida administrativo para activar, inactivar, reactivar o revocar esas membresías. Esto deja sin resolver quién puede habilitar el acceso operativo de un agente, cómo se conserva la autoría histórica y cómo se evita que activaciones concurrentes produzcan más de una membresía activa para el mismo agente dentro del tenant.

La propuesta agrega un ciclo de vida de membresías administrado desde el backend, con autorización derivada del contexto server-side del tenant, invariantes transaccionales en PostgreSQL y auditoría append-only de cada transición. El contrato quedará disponible para futuros consumidores Web, sin implementar esas superficies en este cambio.

## 2. Objetivos

1. Permitir a un administrador del tenant consultar y gestionar las membresías de agentes de su propio tenant.
2. Implementar activación inicial, desactivación reversible, reactivación desde `inactive` y revocación terminal.
3. Garantizar como máximo una membresía `active` por `(tenant_id, usuario_global_id)`.
4. Mantener la posibilidad de que un mismo usuario pertenezca a múltiples tenants, sin aplicar una unicidad activa global.
5. Impedir que estados `pending`, `inactive` o `revoked` otorguen acceso operativo como agente.
6. Registrar cada transición en datos de auditoría append-only, sin secretos.
7. Hacer que estado, auditoría e invariantes se resuelvan atómicamente aun bajo concurrencia PostgreSQL.
8. Verificar autorización, contratos, invariantes, regresiones de HU-007 y concurrencia con pruebas enfocadas.

## 3. Decisiones de producto confirmadas

Estas decisiones cierran los puntos pendientes identificados durante la exploración:

- La unicidad de membresía activa se define por `(tenant_id, usuario_global_id)`; un usuario puede tener membresías activas en múltiples tenants.
- `inactive` es un estado reactivable mediante una nueva transición a `active`.
- `revoked` es terminal: no puede volver a `active` ni a otro estado operativo.
- Solo un administrador del tenant puede ejecutar transiciones de estado.
- La autorización se deriva del principal autenticado y del contexto administrativo resuelto server-side; el cliente no elige el tenant objetivo mediante body, query o headers.
- Cada transición válida debe producir un registro de auditoría append-only con actor, tenant, membresía, estado anterior, estado nuevo, motivo, timestamp y correlación.
- La auditoría no contendrá contraseñas, tokens, secretos ni payloads sensibles.
- La operación conserva la fila de membresía y la identidad global; no crea otra cuenta ni reemplaza la autoría histórica.

## 4. Alcance

### 4.1 Incluido

#### Ciclo de vida

- `pending → active`: activación inicial.
- `active → inactive`: desactivación reversible.
- `inactive → active`: reactivación.
- `active → revoked`: revocación administrativa terminal.
- Rechazo de transiciones desde `revoked` y de cualquier transición no definida por la máquina de estados.
- Definición explícita del comportamiento de comandos repetidos y de errores para membresías inexistentes, ya pertenecientes a otro tenant o con estado incompatible.

#### Autorización y aislamiento

- Resolución del administrador y tenant mediante el seam existente de `TenantContextResolver`.
- Consultas y mutaciones tenant-scoped usando el tenant resuelto server-side.
- Rechazo uniforme de un actor no autorizado, sin filtrar existencia o datos de membresías de otro tenant.
- `active` como condición necesaria para el acceso operativo futuro de la membresía; la asignación detallada de capacidades queda fuera de HU-008.

#### Persistencia e invariantes

- Evolución aditiva del modelo y migración Alembic para datos de ciclo de vida y auditoría.
- Restricción/índice parcial PostgreSQL que garantice una única membresía `active` por `(tenant_id, usuario_global_id)`.
- Timestamps necesarios para reconstruir el ciclo de vida, sin sobrescribir la historia de transiciones.
- Bloqueos y orden deterministas para carreras de activación, desactivación y comandos opuestos.
- Traducción de conflictos de base de datos a respuestas de negocio estables.
- Transición y evento de auditoría en una única transacción; rollback conjunto ante fallo.

#### Contrato HTTP

- Operaciones administrativas para listar/obtener membresías del tenant resuelto.
- Comandos para activar, inactivar y revocar una membresía, incluyendo reactivación desde `inactive`.
- Esquemas de respuesta con identidad no sensible, estado y timestamps pertinentes.
- Códigos de error para autorización, tenant cruzado, estado inválido, conflicto de concurrencia y recurso inexistente, sin revelar información de más.
- Nombres definitivos de rutas, payloads y códigos a especificar en la fase `spec`, respetando los paths HTTP en inglés.

#### Verificación

- Pruebas de servicio para transiciones válidas e inválidas, terminalidad de `revoked`, reactivación de `inactive`, idempotencia definida, actor no autorizado y aislamiento tenant-scoped.
- Pruebas de API para autenticación, autorización derivada del contexto server-side, contratos y ausencia de filtración cross-tenant.
- Pruebas de repositorio para locks, persistencia atómica, rollback y auditoría.
- Integración con PostgreSQL para la migración, índice parcial y activaciones concurrentes dentro de un tenant.
- Regresión que confirme que la aceptación de HU-007 continúa creando exactamente una membresía `pending`.
- Registro separado entre resultados técnicos de implementación y ejecución académica de CP-007.

### 4.2 Exclusiones y no objetivos

Quedan explícitamente fuera de este cambio:

- HU-009: RBAC completo, catálogo de permisos, asignación de roles y autorización fina.
- Flujos de publicación, revisión o catálogo de inmuebles.
- `Plan.max_agents`, suscripciones, cuotas y facturación.
- Cambios al flujo de invitaciones o aceptación de HU-007, salvo la regresión necesaria para preservar su contrato.
- Cambios de credenciales, verificación de identidad o sesiones fuera del seam mínimo para hacer cumplir el estado de membresía.
- Panel React, aplicaciones Flutter, mobile, worker 3D y contratos Solidity.
- Notificaciones generales, integraciones externas y producción/operaciones.
- Refactors no requeridos por el ciclo de vida, la autorización, la auditoría o las invariantes.
- Modificación de `docs/diagramas/Diagrama1.eapx`.

## 5. Áreas afectadas

| Área | Impacto propuesto |
|---|---|
| `backend/app/modules/tenant/` | Modelo, repositorio, servicio y router para consulta y transiciones de membresía; reutilización del contexto administrativo existente. |
| `backend/app/` | Esquemas, errores o seams de enforcement estrictamente necesarios para el contrato y el acceso basado en estado. |
| `backend/alembic/versions/` | Migración aditiva para auditoría, timestamps/restricciones requeridos e índice parcial por tenant y usuario. |
| `backend/tests/` | Pruebas unitarias, de API, repositorio y enfoque PostgreSQL para invariantes y concurrencia. |
| Consumidores Web futuros | Contrato HTTP estable como dependencia, sin cambios de UI en esta propuesta. |
| HU-007 | Compatibilidad: aceptación mantiene la creación de membresías `pending`; no se altera su semántica de invitación. |

## 6. Enfoque técnico de alto nivel

La implementación seguirá la arquitectura existente `router → service → repository` y el TDD estricto configurado para el proyecto.

1. El router obtiene el principal autenticado.
2. El servicio resuelve el contexto administrativo del tenant server-side y valida el comando.
3. El repositorio bloquea las filas relevantes de forma determinista, valida el estado actual, aplica la transición y registra la auditoría en la misma transacción.
4. PostgreSQL respalda la invariante con un índice parcial único sobre la combinación tenant/usuario para filas `active`.
5. Los conflictos de concurrencia o violaciones de la restricción se traducen a un resultado de negocio sin dejar una transición parcial.
6. La auditoría se modela como historial append-only, con campos suficientes para reconstruir quién hizo qué, dónde, cuándo y por qué, además de un identificador de correlación. No se reutilizará la semántica específica de `AgentInvitationEvent` si eso mezcla eventos de invitación con eventos de membresía.

La fase `spec` deberá fijar la semántica exacta de idempotencia, los códigos HTTP, la obligatoriedad y límites del motivo, los timestamps expuestos y el punto preciso de enforcement de acceso. La fase `design` deberá documentar el orden de locks, la estrategia de transacción, la migración de filas existentes y el manejo de conflictos PostgreSQL.

## 7. Riesgos e impactos

| Riesgo | Impacto | Mitigación propuesta |
|---|---|---|
| Activaciones concurrentes en el mismo tenant | Dos membresías activas o respuestas inconsistentes | Locks deterministas, transacción única, índice parcial y pruebas reales contra PostgreSQL. |
| Confusión entre unicidad por tenant y unicidad global | Se impedirían membresías válidas en otros tenants | Aplicar la invariante únicamente a `(tenant_id, usuario_global_id)` y cubrir membresías multi-tenant. |
| Revocación accidental o mal modelada | Pérdida de acceso y estado no recuperable | Confirmar `revoked` terminal, motivo auditable y rechazar toda reactivación desde ese estado. |
| Autorización basada en un tenant enviado por el cliente | Acceso cross-tenant | Resolver el contexto server-side y probar body/query/header manipulados. |
| Auditoría incompleta o mutable | Pérdida de trazabilidad y dificultad de cumplimiento | Evento append-only, campos obligatorios de transición y prohibición explícita de secretos. |
| Migración sobre datos existentes de HU-007 | Fallos de upgrade o pérdida histórica | Migración aditiva, validación de estados/duplicados y downgrade que no borre historial. |
| Enforcement de acceso demasiado amplio | Adelanto involuntario de HU-009 o invalidación de sesiones | Definir solo el seam mínimo; dejar permisos y RBAC fuera del cambio. |
| Crecimiento del cambio por backend, migración y concurrencia | Revisión difícil o más de 400 líneas cambiadas | Medir el diff al aplicar; si supera el presupuesto canónico, pausar para decidir partición según `ask-on-risk`, sin asumir excepción. |

## 8. Rollback y recuperación

- El despliegue del cambio debe poder revertirse mediante la migración Alembic correspondiente sin borrar filas históricas de membresía ni eventos de auditoría ya confirmados.
- Si la aplicación presenta errores tras activar el contrato, se debe retirar o deshabilitar el enrutamiento de los nuevos comandos manteniendo intacto HU-007; no se deben eliminar manualmente estados ni auditoría.
- La recuperación ante una transición incorrecta se realizará mediante una nueva transición administrativa válida, nunca editando o borrando eventos append-only.
- Antes de aplicar un downgrade se deberán verificar dependencias del código y preservar explícitamente la información histórica; cualquier downgrade destructivo requerirá una decisión posterior y separada.

## 9. Criterios de éxito

La propuesta se considerará satisfecha cuando:

1. Un administrador autenticado pueda consultar y gestionar únicamente las membresías de su tenant.
2. `pending` pueda pasar a `active`; `active` pueda pasar a `inactive` o `revoked`; e `inactive` pueda volver a `active` sin duplicar usuario ni membresía.
3. `revoked` sea terminal y toda transición no permitida devuelva un error de negocio estable.
4. Nunca existan dos membresías `active` para el mismo `(tenant_id, usuario_global_id)`, incluso ante activaciones concurrentes en PostgreSQL.
5. Un mismo usuario pueda mantener membresías válidas en más de un tenant.
6. Cada transición válida produzca exactamente un registro append-only con actor, tenant, membresía, estado anterior/nuevo, motivo, timestamp y correlación, sin secretos.
7. La operación sea atómica: si falla la transición o la auditoría, no queda ninguna de las dos persistida.
8. Estados no activos no otorguen acceso operativo por el seam definido para HU-008, sin implementar RBAC de HU-009.
9. La suite enfocada y la regresión de HU-007 sean satisfactorias, incluyendo pruebas de concurrencia PostgreSQL cuando el entorno esté disponible.
10. La evidencia técnica de implementación quede diferenciada de la ejecución académica de CP-007.

## 10. Evidencia, trazabilidad y pendientes

### Evidencia disponible

- `openspec/changes/hu008-membresias-agentes/explore.md`: exploración completada sobre HU-007, módulo tenant, migración existente, reglas de negocio y riesgos.
- El artefacto de exploración identifica PB-007, HU-008, CU-008 y CP-007, además de la arquitectura backend y el estado actual sin endpoints de ciclo de vida.
- La exploración documenta que no se ejecutaron pruebas ni migraciones durante esa fase.

### Trazabilidad

| Necesidad | Respuesta propuesta | Verificación posterior |
|---|---|---|
| PB-007 / HU-008 | Ciclo de vida administrativo de membresías | Pruebas de servicio y API de estados y autorización |
| CU-008 | Activar, inactivar, reactivar y revocar | Casos de transición y errores |
| BR-A3 / BR-A21 | Solo administrador del tenant | Pruebas de actor y tenant cruzado |
| BR-A6 / BR-A7 | Una activa por tenant/usuario; estados históricos | Restricción PostgreSQL, pruebas de invariantes y acceso |
| CP-007 | Activar, reemplazar/inactivar y negar acceso conservando autoría | Ejecución académica separada, con evidencia propia |

### Pendientes para fases posteriores

- `spec`: contrato normativo de rutas, payloads, estados, idempotencia, errores y enforcement.
- `design`: esquema final de auditoría, estrategia de locks, transacciones, timestamps y migración.
- `tasks`: desglose TDD y orden de implementación.
- `verify`: evidencia de pruebas técnicas y, si se ejecuta, evidencia independiente de CP-007.

**CP-007 permanece no ejecutado en esta propuesta.** La existencia de criterios de éxito o de pruebas planificadas no constituye evidencia de ejecución académica.

## 11. Preguntas de propuesta

Las decisiones de producto suministradas para esta fase cierran las ambigüedades de alcance principal. No se agregan preguntas bloqueantes en la propuesta. Los detalles de contrato y diseño listados como pendientes se resolverán en las fases `spec` y `design`, sin ampliar el alcance de HU-008.

## 12. Próximo paso

Avanzar a `spec` para convertir esta intención y sus decisiones confirmadas en requisitos verificables del backend y contrato HTTP, preservando las exclusiones de HU-009, publicación, mobile, UI y operaciones de producción.
