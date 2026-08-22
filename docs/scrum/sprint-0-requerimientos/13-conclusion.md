# Sprint 0 — Conclusión

| Campo | Valor |
| --- | --- |
| Módulo | S0-13 — CAPITULO 1, apartado 13 |
| Estado | planned |
| IDs | OBJ-001..006; RF, RNF, BR, PB, HU, CU |
| Fuentes | módulos S0-01..12; `docs/sprint-0/` (análisis) |

## Resultado del Sprint 0

El Sprint 0 entregó la **línea base completa y trazable** del proyecto RoomForge:

| Entregable | Cantidad | Módulo |
| --- | --- | --- |
| Objetivos | 6 (OBJ-001..006) | S0-02 |
| Requerimientos funcionales | 41 (RF-001..041) | S0-04 |
| Requerimientos no funcionales | 18 (RNF-001..018) | S0-04 |
| Reglas de negocio | 76 (BR-001..076) | S0-04 / auditoría |
| Product Backlog | 49 ítems (PB-001..049) con plataformas y complejidad | S0-06 |
| Historias de usuario | 40 (HU-001..040) | S0-06 |
| Casos de uso | 40 (CU-001..040) | S0-07 |
| Riesgos | 10 (R1..R10) con mitigación | `riesgos.md` |
| Spikes | 4 bitácoras definidas (SPK-01/02/03/05) | `spikes/` |
| Modelos e infraestructura | Datos, artefactos 3D, SQS, escrow, stack y hosting | S0-09..11 |

## Decisiones clave tomadas

1. SaaS B2B2C multi-tenant con recorridos 3D por ambiente (captura con celular).
2. Registro con correo **sin verificación** durante el desarrollo; verificación real en el **Sprint 3** (RF-001/RF-033).
3. Facturación **simulada** local (sin Stripe) y escrow de **token de prueba** en red local Hardhat; ambos con fallback simulado.
4. Stack: Flutter + React/Vite + FastAPI + PostgreSQL/S3/SQS + Meshroom + GLB; Docker+Floci en local; AWS (ECS Express) en producción con despliegue diferido.
5. Equipo generalista de 6 (Trevor PO, Roberto SM), capacidad base 20 h/semana, sin inventario de capacidades.
6. Backlog granular (49 PB) para ejecución paso a paso en 3 sprints (división final → GAP-072).

## Gaps abiertos al cierre del Sprint 0

| Grupo | Gaps | Dependencia |
| --- | --- | --- |
| Números de spikes | GAP-061, GAP-065, GAP-066 | SPK-01/02/04 del equipo |
| Contratos | GAP-070 (criterios HU), GAP-071 (flujos CU) | validación con PO/equipo |
| Planificación | GAP-072 (división/horas), GAP-073 (responsables) | Sprint Planning SP-01 |
| Blockchain | GAP-074 (TBD escrow) | aprendizaje + TASKs |
| Infraestructura | GAP-091 (frontend hosting), R4 (cuenta AWS) | antes del despliegue |
| Modelos y evidencia | GAP-088 diagramas, GAP-082..090 (PAPS/anexos) | equipo/docente |

## Condiciones para iniciar el Sprint 1

- [ ] SPK-05 ejecutado por los integrantes (entorno local operativo) — pendiente.
- [ ] División final SP-01 confirmada en Sprint Planning (GAP-072).
- [ ] Criterios de aceptación de las HU de SP-01 redactados (GAP-070).
- [ ] Repositorio inicial y CI básica creados (PB-048/049).

> El Sprint 0 cierra como **planificación**; la ejecución de ceremonias, métricas y evidencia de cada sprint se registra en los módulos de Sprint 1–3.
