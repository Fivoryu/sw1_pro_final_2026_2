# Avance — Sprint 1

## Estado del registro

El registro de avance de este sprint es parcial. Seis historias cuentan con evidencia de completitud técnica: HU-001 y HU-002 como slices backend/API, y HU-004, HU-005, HU-006 y HU-008 mediante sus paquetes OpenSpec de verificación. Esta evidencia no representa una validación completa de todas las interfaces Flutter, web u otras plataformas, ni implica el cierre formal del caso de prueba académico correspondiente.

La distinción es explícita: los paquetes OpenSpec aportan evidencia de implementación e integración técnica, pero no modifican la línea base académica de pruebas. En [Proceso por historia de usuario del Sprint 1](../scrum/sprint-1/02-proceso-por-hu.md), CP-003, CP-004 y CP-005 continúan registrados como `not executed`, al igual que los demás casos académicos pendientes; CP-007 también permanece `not executed`. El archivo técnico de HU-008 no sustituye el registro académico de CP-007.

El Sprint 1 **no está globalmente cerrado**. Las historias implementadas solo por superficie, las historias pendientes y los casos de prueba académicos aún no ejecutados requieren seguimiento independiente.

## Historias con verificación técnica

| Historia | Caso académico relacionado | Estado | Alcance de la evidencia |
| --- | --- | --- | --- |
| HU-001 — Registro de cliente | CP-001 | Completada con verificación técnica (slice backend/API) | Registro válido, rechazo de duplicados y validaciones HTTP en la superficie backend. |
| HU-002 — Autenticación y sesión | CP-002 | Completada con verificación técnica (slice backend/API) | Login, continuidad de sesión, logout e invalidación por inactividad mediante la API y la base de datos local. |
| HU-004 — Alta de inmobiliaria | CP-003 | Completada con verificación técnica | El [informe OpenSpec de verificación](../../backend/openspec/changes/archive/2026-09-03-hu004-alta-inmobiliaria/verify-report.md) registra PASS, 36/36 tareas completas y 70 pruebas reportadas. CP-003 permanece `not executed` en el reporte académico del Sprint 1. |
| HU-005 — Trial y suscripción mensual | CP-004 | Completada con verificación técnica | El [informe OpenSpec de verificación](../../backend/openspec/changes/hu005-trial-suscripcion/verify-report.md) registra PASS, 36/36 tareas completas y 77 pruebas reportadas. La evidencia técnica de CP-004 no cambia el estado académico `not executed` de CP-004. |
| HU-006 — Ciclo de suscripción | CP-005 | Completada con verificación técnica | El [informe OpenSpec de verificación](../../backend/openspec/changes/archive/2026-09-11-hu006-ciclo-suscripcion/verify-report.md) registra PASS, 19/19 tareas completas, 209 pruebas backend y 49 pruebas panel; el [paquete técnico de evidencia de CP-005](../../backend/openspec/changes/archive/2026-09-11-hu006-ciclo-suscripcion/cp-005-evidence/) documenta CP-005.1–CP-005.8 como PASS. El registro académico de CP-005 permanece `not executed`. |
| HU-008 — Gestión de membresías | CP-007 | Completada con verificación técnica (backend) | El [informe OpenSpec de verificación](../../backend/openspec/changes/archive/2026-09-13-hu008-membresias-agentes/verify-report.md) y el [informe de archivo](../../backend/openspec/changes/archive/2026-09-13-hu008-membresias-agentes/archive-report.md) registran 33/33 tareas, suite fresca de 271 pruebas pasadas y 3 warnings, foco HU-007 + HU-008 de 61 pruebas pasadas, PostgreSQL real con 6 pruebas pasadas y Ruff/Pyright/py_compile limpios. El alcance se limita al ciclo de vida backend de membresías, autorización administrativa con alcance por tenant, unicidad parcial de membresías activas y verificación de auditoría, transacciones y concurrencia. CP-007 permanece `not executed` en la línea base académica. |

### Nota sobre la línea base académica

Los estados anteriores no deben interpretarse como una actualización de la tabla académica. El reporte [Proceso por historia de usuario del Sprint 1](../scrum/sprint-1/02-proceso-por-hu.md) conserva CP-003, CP-004 y CP-005 como `not executed`. Los informes y paquetes OpenSpec se enlazan aquí como evidencia técnica de implementación e integración, no como sustitutos de la ejecución formal de los casos académicos.

## Implementadas por superficie, sin cierre formal

Estas historias cuentan con observaciones de implementación o validación parcial, pero no se registran como completadas formalmente.

| Historia | Caso académico relacionado | Estado | Alcance y límites de la evidencia |
| --- | --- | --- | --- |
| HU-007 — Invitación de agentes | CP-006 | Implementada por superficie | Las superficies backend y panel están implementadas. El [apply-progress activo de OpenSpec](../../openspec/changes/hu007-invitacion-agentes/apply-progress.md) mantiene el resultado como `partial`; CP-006 continúa pendiente y `not executed`. |
| HU-022 — Crear y editar borrador | CP-009 | Implementada por superficie | Existe un flujo interno backend de publicación observado en la auditoría. CP-009 permanece `not executed` y no se cuenta con evidencia del flujo web/API completo. |
| HU-023 — Enviar a revisión | CP-010 | Implementada por superficie | Existe un flujo interno backend de publicación observado en la auditoría. CP-010 permanece `not executed` y no se cuenta con evidencia del flujo web/API completo. |
| HU-024 — Aprobar o rechazar publicaciones | CP-011 | Implementada por superficie | Existe un flujo interno backend de publicación observado en la auditoría. CP-011 permanece `not executed` y no se cuenta con evidencia del flujo web/API completo. |
| HU-025 — Publicar o despublicar un inmueble | CP-012 | Implementada por superficie | El flujo interno backend de publicación forma parte de la observación parcial. CP-012 permanece `not executed`; tampoco se evidencia el flujo web/API completo ni la integración integral con las superficies consumidoras. |
| HU-026 — Consultar el catálogo global | CP-012 | Implementada por superficie | Existe un catálogo backend y fue probado indirectamente. CP-012 y la integración completa con la aplicación cliente no cuentan con evidencia de ejecución. |

La implementación por superficie no implica cierre de la historia, aprobación académica ni disponibilidad productiva.

## Historias pendientes

Las siguientes historias permanecen explícitamente pendientes y no se declaran completadas:

| Historia | Caso académico relacionado | Estado |
| --- | --- | --- |
| HU-009 — Asignar permisos | CP-008 | Pendiente |
| HU-028 — Guardar favoritos | CP-013 | Pendiente |

No se observó evidencia suficiente para registrar estas historias como completadas.

## Evidencia y trazabilidad

- [Proceso por historia de usuario del Sprint 1](../scrum/sprint-1/02-proceso-por-hu.md): conserva la línea base académica, incluidos los casos `not executed`.
- [Evidencia de CP-001 — Registro](../scrum/sprint-1/evidencia/cp001-registro-transcripto.txt).
- [Evidencia de CP-002 — Autenticación](../scrum/sprint-1/evidencia/cp002-autenticacion-transcripto.txt).
- [Evidencia complementaria de concurrencia de refresh](../scrum/sprint-1/evidencia/req05-refresh-concurrency-postgres.txt).
- [Verificación técnica de HU-004](../../backend/openspec/changes/archive/2026-09-03-hu004-alta-inmobiliaria/verify-report.md).
- [Verificación técnica de HU-005](../../backend/openspec/changes/hu005-trial-suscripcion/verify-report.md).
- [Verificación técnica de HU-006](../../backend/openspec/changes/archive/2026-09-11-hu006-ciclo-suscripcion/verify-report.md) y [paquete cp-005-evidence](../../backend/openspec/changes/archive/2026-09-11-hu006-ciclo-suscripcion/cp-005-evidence/).
- [Progreso activo de HU-007](../../openspec/changes/hu007-invitacion-agentes/apply-progress.md).
- [Verificación técnica de HU-008](../../backend/openspec/changes/archive/2026-09-13-hu008-membresias-agentes/verify-report.md) y [informe de archivo de HU-008](../../backend/openspec/changes/archive/2026-09-13-hu008-membresias-agentes/archive-report.md).

La evidencia disponible permite reconocer seis historias con verificación técnica, sin alterar el estado de los casos académicos ni aprobar globalmente el Sprint 1. HU-008 no incluye HU-009/RBAC, publicaciones, UI/mobile, producción ni commits/pushes.

**Última actualización:** no registrada.
