# Sprint 0 — Propósito

| Campo | Valor |
| --- | --- |
| Módulo | S0-01 — CAPITULO 1, apartado 1 |
| Estado | done |
| IDs | OBJ-001..006 |
| Fuentes | `docs/sprint-0/ids-trazabilidad.md` §2; decisiones `roomforge/*` (Engram) |

## Propósito del Sprint 0

El Sprint 0 tiene como objetivo **levantar y congelar la línea base de requerimientos y planificación** del proyecto RoomForge antes de que comience el desarrollo en los Sprint 1–3. No produce código del producto: produce **decisiones verificables** que los sprints de desarrollo consumen.

## Qué entrega

1. **Ámbito y objetivos** del MVP (OBJ-001..006) — [módulo 02](02-ambito-objetivos-descripcion.md).
2. **Equipo Scrum** y acuerdos de trabajo — [módulo 03](03-equipo-scrum.md).
3. **Requerimientos iniciales**: 41 RF, 18 RNF y 76 reglas de negocio trazables — [módulo 04](04-requerimientos-iniciales.md).
4. **Product Backlog granular** (49 PB, 40 HU) y **casos de uso** (40 CU) — [módulos 06](06-product-backlog-hu.md) y [07](07-casos-de-uso.md).
5. **Infraestructura y patrón de desarrollo** decididos (stack, hosting, entorno local, blockchain) — [módulos 09](09-infraestructura.md) y [10](10-patron-de-desarrollo.md).
6. **Criterios de calidad** medibles — [módulo 12](12-criterios-de-calidad.md).
7. **Riesgos, spikes y gaps** registrados para seguimiento — [riesgos](../../sprint-0/riesgos.md) y bitácoras [SPK](../../spikes/spk-01-bitacora.md).

## Trazabilidad con los objetivos

El propósito del Sprint 0 se justifica por los objetivos del proyecto:

| OBJ | Objetivo | Cómo lo habilita el Sprint 0 |
| --- | --- | --- |
| OBJ-001 | Catálogo multi-tenant con recorridos 3D | RF-010..041 y cadena 3D definidos |
| OBJ-002 | Configuración y publicación con aprobación | BR-032..045 y PB-028..031 |
| OBJ-003 | Reservas con escrow de prueba | BR-052..058, PB-040..043, enfoque blockchain |
| OBJ-004 | SaaS demostrable con suscripción simulada | BR-023..031, PB-004..006 |
| OBJ-005 | Despliegue cloud (frontend, backend, BD) | RNF-018, PB-047, hosting ECS Express |
| OBJ-006 | MVP en 2,5 meses | Backlog granular y división de sprints (GAP-072) |

## Registro de decisiones que habilita este módulo

- Línea base funcional consolidada (identidad, tenancy, captura/reconstrucción por ambiente, composición, publicaciones, acceso temporal, precios, reservas, notificaciones, exportación).
- Stack: Flutter (Android 10+) + React/Vite + FastAPI + PostgreSQL/S3/SQS + Meshroom + GLB + Solidity/Hardhat; Docker + Floci en local; AWS en producción.
- Registro con correo: en fases tempranas se acepta correo cualquiera sin verificación (RF-001); la verificación con correo real se habilita en el Sprint 3 (RF-033).

> Los números de los RNF dependientes de spike (RNF-001, RNF-002) y los límites de planes quedan **abiertos** hasta ejecutar SPK-01/SPK-02 (GAP-061, GAP-065, GAP-066).
