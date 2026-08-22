# RoomForge — Documentación de Ingeniería de Software

Índice de navegación del proyecto. El **orden conceptual** sigue el documento modelo `docs/modelo_doc/Documento Final - Grupo#12 - estandar de cod.pdf`:

`PAPS → PROCESO DE DESARROLLO SCRUM → CAPITULO 1 – REQUERIMIENTOS (Sprint 0) → CAPITULO 2 - PROCESO DE DESARROLLO DE SOFTWARE (Sprint 1–3) → BIBLIOGRAFIA → ANEXOS`

## Convención de IDs

Registro canónico: [`docs/sprint-0/ids-trazabilidad.md`](sprint-0/ids-trazabilidad.md) — `OBJ-###`, `RF-###`, `RNF-###`, `BR-###`, `PB-###`, `HU-###`, `CU-###`, `SP-##`, `TASK-###`, `TC-###`, `REV-##`, `GAP-###`. Los IDs se asignan una vez y no se reciclan.

## Módulos

| # | Módulo | Estado | Evidencia/fuentes |
| --- | --- | --- | --- |
| PAPS-01 | [Introducción](paps/01-introduccion.md) | planned | propuesta, ids |
| PAPS-02 | [Descripción del problema](paps/02-descripcion-del-problema.md) | planned | propuesta |
| PAPS-03 | [Métricas](paps/03-metricas.md) | planned | modelo (GAP-082) |
| PAPS-04 | [Definiciones para la estimación](paps/04-definiciones-para-la-estimacion.md) | planned | modelo (GAP-083) |
| PAPS-05 | [Métodos de estimación](paps/05-metodos-de-estimacion.md) | planned | modelo (GAP-083) |
| PAPS-06 | [Análisis de riesgos](paps/06-analisis-de-riesgos.md) | planned | [riesgos](sprint-0/riesgos.md) |
| PAPS-07 | [Planificación del tiempo](paps/07-planificacion-del-tiempo.md) | planned | ids §10 (GAP-084) |
| PAPS-08 | [Recursos](paps/08-recursos.md) | planned | spk-03 (GAP-085) |
| PAPS-09 | [Organización interna](paps/09-organizacion-interna.md) | planned | S0-03 (GAP-086) |
| PAPS-10 | [Seguimiento/control](paps/10-seguimiento-control.md) | planned | ceremonias (GAP-087) |
| SCRUM | [Proceso de desarrollo Scrum](scrum/README.md) | in progress | ids §10 |
| S0-01 | [Sprint 0 — Propósito](scrum/sprint-0-requerimientos/01-proposito.md) | done | ids |
| S0-02 | [Sprint 0 — Ámbito, objetivos y descripción](scrum/sprint-0-requerimientos/02-ambito-objetivos-descripcion.md) | done | ids, línea base |
| S0-03 | [Sprint 0 — Equipo Scrum](scrum/sprint-0-requerimientos/03-equipo-scrum.md) | done | obs-2287/2347 |
| S0-04 | [Sprint 0 — Requerimientos iniciales](scrum/sprint-0-requerimientos/04-requerimientos-iniciales.md) | done | ids, auditoría |
| S0-05 | [Sprint 0 — Funciones](scrum/sprint-0-requerimientos/05-funciones.md) | done | ids |
| S0-06 | [Sprint 0 — Product Backlog / HU](scrum/sprint-0-requerimientos/06-product-backlog-hu.md) | done | ids (GAP-070) |
| S0-07 | [Sprint 0 — Casos de uso](scrum/sprint-0-requerimientos/07-casos-de-uso.md) | done | ids (GAP-071) |
| S0-08 | [Sprint 0 — Planificación de sprints](scrum/sprint-0-requerimientos/08-planificacion-de-sprints.md) | done | ids §10 (GAP-072/073) |
| S0-09 | [Sprint 0 — Infraestructura](scrum/sprint-0-requerimientos/09-infraestructura.md) | done | obs-2276..2405, spk-05 |
| S0-10 | [Sprint 0 — Patrón de desarrollo](scrum/sprint-0-requerimientos/10-patron-de-desarrollo.md) | done | stack, blockchain-enfoque |
| S0-11 | [Sprint 0 — Modelos iniciales](scrum/sprint-0-requerimientos/11-modelos-iniciales.md) | done | obs-2395/2406 (GAP-088) |
| S0-12 | [Sprint 0 — Criterios de calidad](scrum/sprint-0-requerimientos/12-criterios-de-calidad.md) | done | ids §4 (GAP-065/066) |
| S0-13 | [Sprint 0 — Conclusión](scrum/sprint-0-requerimientos/13-conclusion.md) | done | ids |
| S1-01…08 | [Sprint 1](scrum/sprint-1/01-sprint-planning.md) | planned | por sprint |
| S2-01…08 | [Sprint 2](scrum/sprint-2/01-sprint-planning.md) | planned | por sprint |
| S3-01…08 | [Sprint 3](scrum/sprint-3/01-sprint-planning.md) | planned | por sprint |
| BIB | [Bibliografía](bibliografia.md) | planned | GAP-089 |
| ANX | [Anexos](anexos/README.md) | planned | GAP-090 |

## Artefactos de análisis (evidencia del Sprint 0)

| Artefacto | Rol |
| --- | --- |
| [Auditoría de reglas de negocio](sprint-0/auditoria-br.md) | 76 BR con fuente, gaps y decisiones cerradas |
| [IDs y matriz de trazabilidad](sprint-0/ids-trazabilidad.md) | Registro canónico de IDs, plataformas y matrices |
| [Riesgos](sprint-0/riesgos.md) | R1–R10 con mitigación y seguimiento |
| [Enfoque blockchain](sprint-0/blockchain-enfoque.md) | Plan de aprendizaje y TBD del escrow |
| [SPK-01](spikes/spk-01-bitacora.md) · [SPK-02](spikes/spk-02-precisión.md) · [SPK-03](spikes/spk-03-inventario-gpu.md) · [SPK-05](spikes/spk-05-smoke-test-local.md) | Bitácoras de spikes (pendientes de ejecución) |
| [Diagramas EA](diagramas/) | Proyecto Enterprise Architect (UML) |

## Estado de evidencias clave

- Spikes SPK-01/02/03/05: **not executed** (pendientes del equipo) → sus resultados alimentan RNF-001/002 y los límites de planes (GAP-061/065/066).
- División definitiva de sprints y estimación: **GAP-072** (módulo S0-08).
- Asignación de responsables: **GAP-073** (cada sprint planning).
