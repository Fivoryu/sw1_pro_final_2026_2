# RoomForge — Documentación

Índice de la documentación del proyecto. Si es la primera vez que llega acá, empiece por el plan maestro: dice qué se construye, en qué estado está cada fase y qué falta.

## Empezar por acá

| Documento | Para qué sirve |
| --- | --- |
| [Plan maestro](plan-maestro-roomforge.md) | Fuente de verdad del alcance y del estado por fase (§1.4.1) y espejo de las issues (§1.4.5). |
| [Redefinición del producto](redefinicion-roomforge.md) | Reglas de producto vigentes; el plan maestro la referencia. |
| [IDs y trazabilidad](sprint-0/ids-trazabilidad.md) | Registro canónico de IDs (`PB`, `HU`, `CU`, `CP`, `GAP`, etc.); los IDs no se reciclan. |
| [Guías de traspaso](guias/) | Cómo levantar, probar y cerrar una fase en otro equipo: [F07 en dispositivo](guias/f07-guia-prueba-dispositivo.md) y [cierre de F09](guias/f09-guia-cierre.md). |

## Documentación académica

Sigue el orden del documento modelo (`modelo_doc/Documento Final - Grupo#12 - estandar de cod.pdf`): PAPS → Proceso Scrum → Capítulo 1 (Sprint 0) → Capítulo 2 (Sprints 1–3) → Bibliografía → Anexos.

| Módulo | Ubicación | Estado |
| --- | --- | --- |
| PAPS (introducción, problema, métricas, estimación, riesgos, tiempo, recursos, organización, seguimiento) | — | Pendiente de redactar: GAP-082 a GAP-087. Insumos: [riesgos](sprint-0/riesgos.md) y [spikes](spikes/). |
| Proceso de desarrollo Scrum | [scrum/](scrum/README.md) | Con contenido |
| Capítulo 1 — Requerimientos (Sprint 0) | [scrum/sprint-0-requerimientos/](scrum/sprint-0-requerimientos/01-proposito.md), módulos 01 a 13 | Con contenido |
| Capítulo 2 — Sprint 1 | [scrum/sprint-1/](scrum/sprint-1/01-sprint-planning.md), módulos 01 a 08 y evidencia | Con contenido |
| Capítulo 2 — Sprint 2 | [scrum/sprint-2/](scrum/sprint-2/01-sprint-planning.md), módulos 01 a 08 | Con contenido |
| Capítulo 2 — Sprint 3 | [scrum/sprint-3/](scrum/sprint-3/01-sprint-planning.md), módulos 01 a 08 y evidencia | Con contenido |
| Avance por historia de usuario | [avance/](avance/README.md) | Histórico; el plan maestro (F13) lo cita |
| Bibliografía | — | Pendiente: GAP-089 |
| Anexos | — | Pendiente: GAP-090 |

**Análisis del Sprint 0** (insumos de los capítulos): [auditoría de reglas de negocio](sprint-0/auditoria-br.md), [riesgos](sprint-0/riesgos.md), [enfoque blockchain](sprint-0/blockchain-enfoque.md) y [tipos de diagramas](sprint-0/tipos-diagramas-modelo.md).

**Documento modelo:** [modelo_doc/](modelo_doc/) contiene el PDF del Grupo #12, sus extractos y la [guía del Capítulo 2](modelo_doc/guia-capitulo2-modelo.md). En `modelo_doc/referencias/` quedan tres `.docx` de referencia que ningún documento cita.

**Diagramas:** [diagramas/](diagramas/) contiene el proyecto de Enterprise Architect `Diagrama1.eapx`. Solo se referencia el tipo de diagrama y su ubicación; no se embeben imágenes.

## Documentación técnica

| Carpeta | Contenido |
| --- | --- |
| [api/](api/) | Contratos de API: [catálogo, cotizaciones y reservas](api/catalog-reservations-v1.md) (aprobado con observaciones), [publicaciones F04](api/f04-publications-v1.md), [escena F06](api/f06-scene-contract.md), [paquete de captura F07](api/f07-capture-package.md), [trabajos de detección F08](api/f08-detection-jobs.md) y [revisión de mobiliario F08](api/f08-furniture-review.md). |
| [ai/](ai/) | Piloto de IA de mobiliario (F08): bitácora, ficha del modelo, mediciones y conjunto CC0. `f08-conjunto-cc0.json` lo lee `worker3d/fetch_cc0_pilot_set.py`; no moverlo. |
| [spikes/](spikes/) | Bitácoras de spikes SPK-01 a SPK-07. SPK-01/02/03/05 siguen sin ejecutar (GAP-020, GAP-021, GAP-030 y GAP-031). |
| [ux/](ux/f02-surface-map.md) | Mapa de superficies de la interfaz. |
| [capturas/](capturas/README.md) | Capturas del panel que escribe la prueba E2E `panel/staff-shell/e2e/staff-login.e2e.test.mjs`; no moverla. |
| [ci/](ci/f02-initial-ci.md) y [migrations/](migrations/f02-migration-verification.md) | Evidencia de F02: CI inicial y verificación de migraciones. |

## Historial

| Ubicación | Contenido |
| --- | --- |
| [archivo/](archivo/) | Documentos superados que se conservan para reconciliar diferencias, como la [propuesta original](archivo/propuesta-roomforge-original.md). |
| `odd/tasks/` | Registros de ejecución por fase; los de trabajo cerrado están en `odd/tasks/archivo/`. No son fuente de requisitos. |
| `openspec/changes/archive/` | Artefactos SDD de los cambios anteriores al plan maestro. |
