# Sprint 0 — Casos de uso

| Campo | Valor |
| --- | --- |
| Módulo | S0-07 — CAPITULO 1, apartado 7 |
| Estado | done (formato del modelo: lista CU + actores + paquetes funcionales) |
| IDs | CU-01..CU-40 |
| Fuentes | `docs/sprint-0/ids-trazabilidad.md` §8 (canónico) |

## 7.1. Identificación de actores

| ACTOR | DESCRIPCIÓN |
| --- | --- |
| Cliente | Usuario global sin membresía. Consulta el catálogo, solicita acceso al detalle, recorre en 3D, simula precios y reserva con depósito de prueba. |
| Inmobiliaria | Entidad que se da de alta mediante checkout simulado y opera como tenant del SaaS. |
| Administrador (tenant) | Usuario con el mayor nivel de control del tenant. Gestiona suscripción, agentes, permisos, catálogo maestro, publicaciones, reservas y auditoría. |
| Agente | Usuario de la inmobiliaria que captura ambientes, solicita reconstrucciones, compone inmuebles, configura precios y publica. |
| Sistema / Worker 3D | Actor automático: procesa jobs de reconstrucción (Meshroom), genera artefactos, expira reservas y notifica. |
| Blockchain (escrow) | Actor secundario: valida y registra los movimientos del token de prueba del escrow. |

## 7.2. Paquetes y casos de uso

| ID | CASO DE USO |
| --- | --- |
| CU-01 | Registro de cliente con correo sin verificar (modo pruebas) |
| CU-02 | Autenticación y renovación de sesión |
| CU-03 | Verificación de correo real con enlace de activación |
| CU-04 | Onboarding de inmobiliaria (checkout simulado + provisión) |
| CU-05 | Activación de trial y suscripción con evento firmado |
| CU-06 | Ciclo de suscripción: cuotas, upgrade/downgrade, cancelación y purga |
| CU-07 | Invitación de agente y aceptación |
| CU-08 | Gestión de membresías (una activa) |
| CU-09 | Gestión de permisos RBAC |
| CU-10 | Captura guiada (incluye difuminado automático) |
| CU-11 | Subida de capturas con progreso y reanudación |
| CU-12 | Validación de calidad y recaptura selectiva |
| CU-13 | Solicitud de reconstrucción (persistir job y encolar) |
| CU-14 | Seguimiento de estados y reintento del job |
| CU-15 | Ejecución del job en el worker (sistema) |
| CU-16 | Generación de artefactos: GLB, nubes y texturas (sistema) |
| CU-17 | Derivación de plano 2D básico (sistema) |
| CU-18 | Revisión con preview y aprobación/rechazo de reconstrucción |
| CU-19 | Composición espacial del inmueble |
| CU-20 | Recorrido 3D navegable (panel y app) |
| CU-21 | Consulta de medidas con confianza |
| CU-22 | Consulta del plano 2D del inmueble |
| CU-23 | Configuración visual con catálogo low-poly y fallback |
| CU-24 | Edición de borrador de publicación |
| CU-25 | Revisión y aprobación de publicación (verifica redacción) |
| CU-26 | Publicación/despublicación y visibilidad del catálogo |
| CU-27 | Versionado comercial de publicaciones |
| CU-28 | Gestión de favoritos |
| CU-29 | Solicitud de acceso temporal |
| CU-30 | Otorgamiento/revocación/vencimiento del acceso (7 días) |
| CU-31 | Gestión del catálogo maestro del tenant |
| CU-32 | Configuración de elementos y ajustes por publicación |
| CU-33 | Motor de precios con desglose y depósito |
| CU-34 | Simulación de precio con la configuración |
| CU-35 | Reserva con escrow de prueba |
| CU-36 | Aceptación atómica y rechazo de reservas competidoras |
| CU-37 | Expiración y reembolso idempotente de reservas |
| CU-38 | Notificación de eventos |
| CU-39 | Exportación de plano/GLB |
| CU-40 | Auditoría y retención del tenant |

| PAQUETE FUNCIONAL | CASOS DE USO RELACIONADOS | DESCRIPCIÓN |
| --- | --- | --- |
| Autenticación y administración | CU-01..CU-09 | Agrupa registro, autenticación, verificación de correo, onboarding, suscripción, invitación de agentes, membresías y permisos. |
| Captura y reconstrucción 3D | CU-10..CU-19 | Comprende captura guiada, subida, validación, solicitud y seguimiento de jobs, ejecución del worker, artefactos, plano 2D, aprobación y composición espacial. |
| Acceso y visualización | CU-20..CU-23, CU-29..CU-30 | Incluye recorrido 3D, medidas, plano 2D para cliente, configuración visual, solicitud y otorgamiento de acceso temporal. |
| Publicaciones y catálogo | CU-24..CU-28 | Agrupa borrador, revisión/aprobación, publicación/despublicación, versionado, catálogo global y favoritos. |
| Precios y reservas | CU-31..CU-37 | Incluye catálogo maestro, configuración de elementos, motor de precios, simulación, reserva con escrow, aceptación atómica y expiración. |
| Notificaciones, exportación y auditoría | CU-38..CU-40 | Comprende notificación de eventos, exportación restringida y auditoría/retención del tenant. |

> **GAP-071**: los flujos principales, alternativos y de excepción de cada CU se desarrollan en el módulo "02-proceso-por-hu" del sprint que la implementa (patrón del CAPITULO 2 del modelo).
>
> **Diagrama asociado**: tipo **Use Case** (diagrama de casos de uso CU-01..CU-40) — ver [`tipos-diagramas-modelo.md`](../../sprint-0/tipos-diagramas-modelo.md).
