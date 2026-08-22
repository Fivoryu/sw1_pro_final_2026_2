# Plan de documentación

> Completado con evidencia del repositorio (2026-08-22). Los datos sin respaldo se marcan `GAP-###`; no se convierten supuestos en hechos. La división en archivos facilita la lectura, pero el orden conceptual sigue el documento modelo.

## Proyecto y convenciones

- **Proyecto:** RoomForge — SaaS inmobiliario académico con recorridos 3D (MVP)
- **Objetivo documental:** que un lector pueda verificar la trazabilidad problema → objetivos → RF/RNF/BR → PB/HU/CU → sprints → diseño → implementación → pruebas → cierre
- **Documento modelo/índice:** `docs/modelo_doc/Documento Final - Grupo#12 - estandar de cod.pdf`
- **Idioma y convenciones:** Español; nomenclatura del proyecto, IDs estables, Markdown y enlaces relativos
- **Fecha / responsable:** GAP-080 (fecha y autor del plan sin respaldo institucional)

## Fuentes y evidencia

| Fuente | Ubicación/alcance | Hecho que respalda | Estado |
| --- | --- | --- | --- |
| `docs/propuesta-roomforge-original.md` | Propuesta inicial | Problema y origen del proyecto (parcialmente supersedida) | verified |
| `docs/sprint-0/auditoria-br.md` | Secciones A–I | 76 reglas de negocio con fuente por regla | derived |
| `docs/sprint-0/ids-trazabilidad.md` | Secciones 1–10 | IDs canónicos OBJ/RF/RNF/BR/PB/HU/CU, plataformas y matriz | derived |
| `docs/sprint-0/riesgos.md` | Registro R1–R10 | Riesgos, mitigación y seguimiento | derived |
| `docs/sprint-0/blockchain-enfoque.md` | Secciones 1–7 | Plan de aprendizaje y TBD del escrow (GAP-074) | proposed |
| `docs/spikes/spk-01-bitacora.md` | Tabla de corridas | Benchmark Meshroom (pendiente de ejecución) | not executed |
| `docs/spikes/spk-02-precisión.md` | Tablas de medición | Exactitud/precisión geométrica (pendiente) | not executed |
| `docs/spikes/spk-03-inventario-gpu.md` | Tabla por integrante | Inventario GPU (pendiente) | not executed |
| `docs/spikes/spk-05-smoke-test-local.md` | Checklist | Entorno Docker+Floci (pendiente) | not executed |
| Engram `roomforge/*` (obs 2269–2417) | Decisiones del análisis | Línea base funcional, RNF, stack, hosting, planes | verified |
| `skills/documentacion-software/` | SKILL.md + references | Contrato de documentación y estándar modular | verified |

Registros pendientes por agregar cuando existan: capturas, prototipos, métricas medidas, ceremonias, taskboards y resultados de pruebas → `GAP-###` hasta entonces.

## Módulos a planificar

Estado actual: módulos del Sprint 0 y PAPS marcados según avance; Sprint 1–3 quedan `planned` hasta cada sprint. Este orden es el índice del modelo; `docs/README.md` solo navega.

| Orden | Ruta | Sección del índice / propósito | IDs | Fuentes/evidencia | Gaps | Validación | Estado |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 00 | `docs/README.md` | Índice de navegación y estado de todos los módulos | OBJ/RF/RNF/BR/PB/HU/CU/SP | ids-trazabilidad.md | GAP-080 | enlaces y orden revisados | in progress |
| PAPS-01 | `docs/paps/01-introduccion.md` | PAPS 1 — Introducción | OBJ-001..006 | propuesta, ids | GAP-081 | referencias | planned |
| PAPS-02 | `docs/paps/02-descripcion-del-problema.md` | PAPS 2 — Descripción del problema | OBJ/RF | propuesta | GAP-081 | evidencia del problema | planned |
| PAPS-03 | `docs/paps/03-metricas.md` | PAPS 3 — Métricas: ActivityWach, Kimai y Worklenz | MET | modelo, GAP | GAP-082 (capturas/MOT/MOF) | métricas verificadas | planned |
| PAPS-04 | `docs/paps/04-definiciones-para-la-estimacion.md` | PAPS 4 — Definiciones para la estimación | EST | modelo | GAP-083 | términos y fuentes | planned |
| PAPS-05 | `docs/paps/05-metodos-de-estimacion.md` | PAPS 5 — Métodos de estimación | EST/MET | modelo | GAP-083 | método aplicado | planned |
| PAPS-06 | `docs/paps/06-analisis-de-riesgos.md` | PAPS 6 — Análisis de riesgos | RISK/R1..R10 | riesgos.md | — | riesgos y seguimiento | planned |
| PAPS-07 | `docs/paps/07-planificacion-del-tiempo.md` | PAPS 7 — Planificación del tiempo | PLAN/SP | ids sección 10 | GAP-084 (fechas) | fechas solo evidenciadas | planned |
| PAPS-08 | `docs/paps/08-recursos.md` | PAPS 8 — Recursos | RES | spk-03, equipo | GAP-085 | recursos respaldados | planned |
| PAPS-09 | `docs/paps/09-organizacion-interna.md` | PAPS 9 — Organización interna | ROLE | módulo S0-03 | GAP-086 | roles y acuerdos | planned |
| PAPS-10 | `docs/paps/10-seguimiento-control.md` | PAPS 10 — Seguimiento/control | CTRL/MET | ceremonia modelo | GAP-087 | indicadores y evidencias | planned |
| SCRUM | `docs/scrum/README.md` | PROCESO DE DESARROLLO SCRUM y navegación de Sprint 0–3 | SP-01/02/03 | ids sección 10 | GAP-072 | orden del proceso | in progress |
| S0-01 | `docs/scrum/sprint-0-requerimientos/01-proposito.md` | CAPITULO 1 / Sprint 0 — Propósito | OBJ-001..006 | ids-trazabilidad | — | propósito trazable | done |
| S0-02 | `docs/scrum/sprint-0-requerimientos/02-ambito-objetivos-descripcion.md` | Ámbito, objetivos y descripción | OBJ/RF/RNF | ids, línea base | GAP-065/066 | alcance | done |
| S0-03 | `docs/scrum/sprint-0-requerimientos/03-equipo-scrum.md` | Equipo Scrum | ROLE | obs-2287, obs-2347 | GAP-085 | roles evidenciados | done |
| S0-04 | `docs/scrum/sprint-0-requerimientos/04-requerimientos-iniciales.md` | Requerimientos iniciales | RF-001..041, RNF-001..018, BR-001..076 | ids, auditoría | GAP-065/066 | requisitos y fuentes | planned |
| S0-05 | `docs/scrum/sprint-0-requerimientos/05-funciones.md` | Funciones | RF/RNF | ids | — | funciones trazadas | planned |
| S0-06 | `docs/scrum/sprint-0-requerimientos/06-product-backlog-hu.md` | Product Backlog / HU | PB-001..049, HU-001..040 | ids | GAP-070 | contrato HU y criterios | planned |
| S0-07 | `docs/scrum/sprint-0-requerimientos/07-casos-de-uso.md` | Casos de uso | CU-001..040 | ids | GAP-071 | contrato CU y flujos | planned |
| S0-08 | `docs/scrum/sprint-0-requerimientos/08-planificacion-de-sprints.md` | Planificación de Sprints | SP-01/02/03 | ids sección 10 | GAP-072, GAP-073 | dependencias y alcance | planned |
| S0-09 | `docs/scrum/sprint-0-requerimientos/09-infraestructura.md` | Infraestructura | INF | obs-2276..2405, spk-05 | GAP-061 | entorno evidenciado | planned |
| S0-10 | `docs/scrum/sprint-0-requerimientos/10-patron-de-desarrollo.md` | Patrón de desarrollo | ARCH/PAT | blockchain-enfoque, stack | — | decisiones y fuentes | planned |
| S0-11 | `docs/scrum/sprint-0-requerimientos/11-modelos-iniciales.md` | Modelos iniciales | MODEL | obs-2395, obs-2406 | GAP-088 (diagramas) | modelos y referencias | planned |
| S0-12 | `docs/scrum/sprint-0-requerimientos/12-criterios-de-calidad.md` | Criterios de calidad | RNF/QA | ids sección 4, riesgos | GAP-065/066 | criterios verificables | planned |
| S0-13 | `docs/scrum/sprint-0-requerimientos/13-conclusion.md` | Conclusión del Sprint 0 | OBJ/RF/HU/CU | ids | — | cierre de requerimientos | planned |
| S1-01…S1-08 | `docs/scrum/sprint-1/` | Sprint 1 — 8 secciones del índice | SP-01/HU/PB/TASK/TC | por sprint | GAP-072 | traza HU→diseño→implementación→prueba | planned |
| S2-01…S2-08 | `docs/scrum/sprint-2/` | Sprint 2 — 8 secciones del índice | SP-02/HU/PB/TASK/TC | por sprint | GAP-072 | traza HU→diseño→implementación→prueba | planned |
| S3-01…S3-08 | `docs/scrum/sprint-3/` | Sprint 3 — 8 secciones del índice | SP-03/HU/PB/TASK/TC | por sprint | GAP-072 | traza HU→diseño→implementación→prueba | planned |
| BIB | `docs/bibliografia.md` | BIBLIOGRAFIA — fuentes citadas | REF | fuentes oficiales citadas | GAP-089 | referencias resueltas | planned |
| ANX | `docs/anexos/` | ANEXOS — capturas, prototipos, artefactos y evidencia de apoyo | ANX/EVID | spk-*, diagramas | GAP-090 | enlaces y correspondencia | planned |

## IDs y trazabilidad

- **Prefijos adoptados:** `OBJ-###`, `RF-###`, `RNF-###`, `BR-###`, `HU-###`, `CU-###`, `PB-###`, `SP-##`, `TASK-###`, `TC-###`, `REV-##`, `GAP-###` (registro canónico: `docs/sprint-0/ids-trazabilidad.md`).
- **Regla de estabilidad:** los IDs se asignan una única vez y no se reciclan; la próxima numeración continúa la secuencia. Quién modifica el registro: el equipo, con registro en la matriz.
- **Cadena:** `PAPS/problema/objetivos → RF/RNF/BR → HU/CU/PB → SP/TASK → diseño → implementación → TC → REV/cierre`.
- **Gaps de cobertura:** GAP-065, GAP-066 (spikes), GAP-070, GAP-071 (módulos 06/07), GAP-072 (planificación), GAP-073 (asignación), GAP-074 (blockchain TBD) — ver tabla siguiente.

## Evidencia faltante y decisiones

| ID | Ausencia/contradicción | Módulo afectado | Impacto | Acción pendiente | Estado |
| --- | --- | --- | --- | --- | --- |
| GAP-061 | Nombres/precios/cuotas de planes | S0-09, 12 | Límites sin fijar | SPK-01/SPK-04 | open |
| GAP-065 | Tolerancia de medidas | S0-04, 12 | RNF-001 sin número | SPK-02 | open |
| GAP-066 | Timeout y concurrencia de jobs | S0-04, 12 | RNF-002 sin número | SPK-01 | open |
| GAP-070 | Criterios de aceptación de HU | S0-06 | Contrato HU incompleto | Escribir criterios | open |
| GAP-071 | Flujos alternativos de CU | S0-07 | Contrato CU incompleto | Escribir flujos | open |
| GAP-072 | División final SP-01/02/03 y horas | S0-08 | Planificación provisional | Planificar con equipo | open |
| GAP-073 | Responsables por PB/HU | S0-08, sprints | Asignación | Cada sprint planning | open |
| GAP-074 | TBD del escrow blockchain | S0-10, Sprint 2 | Inicio de contratos | Aprendizaje + TASKs | open |
| GAP-080 | Fecha/autor del plan | 00 | Metadatos | Registrar | open |
| GAP-081 | Contexto histórico del problema (capturas/encuestas) | PAPS-01/02 | Evidencia de problema | Recopilar | open |
| GAP-082 | Capturas/prototipos y MOT/MOF de ActivityWatch/Kimai/Worklenz | PAPS-03 | Métricas del modelo | Elaborar | open |
| GAP-083 | Método de estimación seleccionado con fuente | PAPS-04/05 | Estimación | Decidir método | open |
| GAP-084 | Fechas de inicio/fin de sprints | PAPS-07 | Cronograma | Fijar con equipo | open |
| GAP-085 | Fallo de disponibilidad del equipo (decidido no inventariar) | PAPS-08, S0-03 | Capacidad | Usar 20 h base | open |
| GAP-086 | Acuerdos formales de organización | PAPS-09 | Organización | Registrar actas | open |
| GAP-087 | Ceremonias y métricas de seguimiento | PAPS-10, sprints | Control | Ejecutar ceremonias | open |
| GAP-088 | Diagramas UML/C4 iniciales | S0-11 | Modelos | Elaborar con EA | open |
| GAP-089 | Referencias bibliográficas formateadas | BIB | Bibliografía | Completar citas | open |
| GAP-090 | Capturas/prototipos del sistema | ANX | Anexos | Capturar durante sprints | open |

No se inventan capturas, prototipos, fechas, métricas, esfuerzo, asistencia, estados de taskboard, aprobaciones ni resultados de pruebas. Estados: `planned`, `in progress`, `done`, `blocked`, `deferred`, `not executed`, `unknown`.

## Validación de salida

- [x] El árbol modular conserva el orden PAPS → Scrum → Sprint 0 → Sprint 1→3 → Bibliografía → Anexos.
- [x] `docs/README.md` enlaza los módulos y estados; rutas locales resuelven (parcial: se verifica al completar cada batch).
- [ ] `docs/paps/` contiene los capítulos 1–10 con sus nombres y alcance correctos.
- [x] Sprint 0 contiene los 13 apartados del índice (en progreso).
- [ ] Sprint 1, 2 y 3 repiten las mismas ocho secciones.
- [ ] Cada `02-proceso-por-hu.md` contiene Diseño (arquitectura, datos, lógica de negocio), Implementación y Pruebas.
- [ ] Cada HU, CU, requisito, tarea y prueba tiene ID estable y relación trazable; no hay huérfanos.
- [ ] Cada prueba de caja negra registra resultado y evidencia; `pass` solo tras ejecución observada.
- [x] Fuentes, IDs, evidencia, gaps, estados y validaciones completados o marcados pendientes.
- [x] No se presentaron métricas, resultados, fechas o aprobaciones sin respaldo.
