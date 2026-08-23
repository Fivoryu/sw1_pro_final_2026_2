# Sprint 1 — Burndown y BurnUp

| Campo | Valor |
| --- | --- |
| Módulo | S1-06 |
| Estado | pending / not executed (GAP-087) |
| Referencia del modelo | CAPITULO 2, sección 6 — Burndown y BurnUp |
| IDs | SP-01; PB-001, PB-002, PB-004..PB-008, PB-028..PB-030, PB-032, PB-048, PB-049; HU-001, HU-002, HU-004..HU-009, HU-022..HU-026, HU-028 |
| Evidencia | GAP-087 — series no ejecutadas; GAP-CH2-002 — series no recuperables del modelo |

## 6.1. Cálculo de la Gráfica Burndown

El Burndown se calculará usando los puntos PHU comprometidos en el Sprint Backlog. SP-01 planifica **107 PHU totales** como equivalencia de la estimación en horas documentada en `01-sprint-planning.md` (§1.3). Para cada fecha de medición se registrará el trabajo pendiente:

`PHU pendientes del día = 107 PHU − PHU completados observados`

| Elemento | Valor / estado |
| --- | --- |
| Puntos PHU iniciales | 107 PHU |
| Unidad de medición | PHU completados y pendientes por fecha de seguimiento |
| Serie planificada | Pendiente de fechas y mediciones; not executed |
| Serie real | not executed |
| Estado del artefacto | not executed |

**Tipo de referencia:** **Gráfica Burndown**. No se embebe una imagen ni se inventan series, fechas, ejes o valores (GAP-CH2-002).

## 6.2. Cálculo de la Gráfica BurnUp

El BurnUp se calculará acumulando los PHU completados y comparándolos con el alcance total de 107 PHU del Sprint Backlog. La serie observada solo se incorporará después de registrar ejecuciones reales y fechas verificables.

| Elemento | Valor / estado |
| --- | --- |
| Alcance total | 107 PHU |
| Unidad de medición | PHU completados acumulados por fecha de seguimiento |
| Serie planificada | Pendiente de fechas y mediciones; not executed |
| Serie real | not executed |
| Estado del artefacto | not executed |

**Tipo de referencia:** **Gráfica BurnUp**. No se embebe una imagen ni se inventan series, fechas, ejes o valores (GAP-CH2-002).

## 6.3. Evidencia pendiente

- Fechas de medición y valores diarios: `not executed` (GAP-087).
- Puntos PHU realmente completados: `not executed` (GAP-087).
- Gráficas Burndown y BurnUp: pendientes de generación con datos observados.
- Responsable de consolidación: GAP-073.
