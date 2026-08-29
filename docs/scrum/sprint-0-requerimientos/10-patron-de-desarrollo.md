# Sprint 0 — Patrón de desarrollo

| Campo | Valor |
| --- | --- |
| Módulo | S0-10 — CAPITULO 1, apartado 10 |
| Estado | planned (patrón definido; refinamiento por sprint) |
| IDs | ARCH/PAT; TASK-###, TC-### |
| Fuentes | stack (obs-2276, 2279); persistencia (obs-2395, 2406); blockchain-enfoque.md; estándar de documentación |

## Arquitectura (nivel base)

- **Backend**: monolito modular FastAPI, módulos por área de dominio (identidad, tenancy, catálogo, precios, reservas, jobs, notificaciones, exportación).
- **Fronteras de persistencia** (obs-2395):
  - PostgreSQL: entidades transaccionales, estados, versiones, referencias, metadatos semánticos y transformaciones locales TRS de escenas (obs-2406).
  - S3: binarios (capturas, nubes PLY/LAZ, GLB, texturas, planos); las referencias/versiones viven en PostgreSQL.
- **Asistencia IA de captura — enfoque propuesto, pendiente de confirmación/formalización**: la app Flutter empaqueta un modelo externo/open-source ajustado o entrenado localmente, exportado a ONNX/TFLite, para inferencia offline de calidad, cobertura y señales de elementos visibles. No ejecuta Meshroom ni la reconstrucción 3D completa.
- **Flujo 3D**: la API persiste el job antes de encolarlo (SQS); el worker (idempotente, con heartbeat) descarga inputs, ejecuta Meshroom y sube artefactos; PostgreSQL es la autoridad de estados. El worker puede ser real o simulado en local y la reconstrucción completa es asíncrona.
- **Flujo blockchain**: la API es la autoridad de la reserva; el contrato de escrow valida y registra movimientos de token de prueba en la red local Hardhat, independiente de Floci; un listener actualiza PostgreSQL idempotentemente; fallback simulado si el contrato no está listo. Detalle: [`blockchain-enfoque.md`](../../sprint-0/blockchain-enfoque.md).

## Patrón por HU (aplica en cada sprint)

Para cada HU, el módulo `02-proceso-por-hu.md` del sprint documenta:

1. **Diseño**
   - Arquitectura: componentes y flujo afectados (apéndice del patrón base).
   - Datos: tablas/objetos S3/eventos involucrados, con migración si aplica.
   - Lógica de negocio: reglas BR vinculadas y transiciones de estado.
2. **Implementación**: cambios por superficie (backend/móvil/web/worker/blockchain) con referencia a TASKs.
3. **Pruebas**: casos de caja negra `TC-###` con evidencia (setup, acción, esperado, real, resultado, evidencia).

## Convenciones de desarrollo

- **Commits**: conventional commits, uno por unidad de trabajo revisable (`TASK-###`).
- **CI**: tests + smoke test en verde antes de merge (PB-049).
- **Cliente API**: las apps consumen FastAPI mediante un cliente **OpenAPI generado**; el panel no actúa como segundo backend.
- **Configuración**: entornos (local/cloud) solo por configuración (`.env`/endpoints), nunca hardcodeada.
- **Privacidad**: difuminado automático + revisión humana antes de publicar (RNF-008); retención según BR-066/067.
- **IA como herramienta**: soporte al equipo generalista; el criterio de diseño y las decisiones son del equipo. La selección y licencia del modelo externo, junto con su ajuste local y compatibilidad móvil, deben formalizarse antes de adoptarlo.

## Estados de dominio (máquinas de estado base)

| Dominio | Estados |
| --- | --- |
| Publicación | `borrador` → `en_revision` → `publicado`/`rechazado`; `despublicado` (BR-034..039) |
| Job de reconstrucción | `pending` → `running` → `done`/`failed`; `delayed` (worker ausente); reintentos acotados |
| Suscripción | `trialing` → `active` → `past_due`/`suspended`; `canceled_read_only` → `purged` (BR-025..031) |
| Reserva | `pendiente` → `aceptada`/`rechazada`/`expirada`; aceptación atómica (BR-054..058) |
| Escrow (contrato) | `pending` → `escrowed` → `released`/`refunded`; transiciones únicas (BR-056) |

## Refinamiento por sprint

- Las TASKs nacen de dividir los PB con complejidad **A** (PB-006, 017, 022, 031, 037, 041, 042, 047).
- Los criterios de aceptación por HU se cierran en cada Sprint Planning (GAP-070/073).
- El patrón de diseño se detalla por HU en el módulo 02 del sprint correspondiente.
- Diagramas de lógica de negocio, según el modelo: **Communication** y **Sequence** por flujo clave (reserva/escrow, reconstrucción, suscripción) — se desarrollan en el módulo "02-proceso-por-hu" de cada sprint (ver [`tipos-diagramas-modelo.md`](../../sprint-0/tipos-diagramas-modelo.md)). Los estados de dominio de esta sección se expresan en esos diagramas. (GAP-071).
