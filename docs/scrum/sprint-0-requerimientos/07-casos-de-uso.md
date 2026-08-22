# Sprint 0 — Casos de uso

| Campo | Valor |
| --- | --- |
| Módulo | S0-07 — CAPITULO 1, apartado 7 |
| Estado | done (formato del modelo: lista CU + actores + paquetes funcionales) |
| IDs | CU-001..CU-040 |
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
| CU-001 | Registro de cliente con correo sin verificar (modo pruebas) |
| CU-002 | Autenticación y renovación de sesión |
| CU-003 | Verificación de correo real con enlace de activación |
| CU-004 | Onboarding de inmobiliaria (checkout simulado + provisión) |
| CU-005 | Activación de trial y suscripción con evento firmado |
| CU-006 | Ciclo de suscripción: cuotas, upgrade/downgrade, cancelación y purga |
| CU-007 | Invitación de agente y aceptación |
| CU-008 | Gestión de membresías (una activa) |
| CU-009 | Gestión de permisos RBAC |
| CU-010 | Captura guiada (incluye difuminado automático) |
| CU-011 | Subida de capturas con progreso y reanudación |
| CU-012 | Validación de calidad y recaptura selectiva |
| CU-013 | Solicitud de reconstrucción (persistir job y encolar) |
| CU-014 | Seguimiento de estados y reintento del job |
| CU-015 | Ejecución del job en el worker (sistema) |
| CU-016 | Generación de artefactos: GLB, nubes y texturas (sistema) |
| CU-017 | Derivación de plano 2D básico (sistema) |
| CU-018 | Revisión con preview y aprobación/rechazo de reconstrucción |
| CU-019 | Composición espacial del inmueble |
| CU-020 | Recorrido 3D navegable (panel y app) |
| CU-021 | Consulta de medidas con confianza |
| CU-022 | Consulta del plano 2D del inmueble |
| CU-023 | Configuración visual con catálogo low-poly y fallback |
| CU-024 | Edición de borrador de publicación |
| CU-025 | Revisión y aprobación de publicación (verifica redacción) |
| CU-026 | Publicación/despublicación y visibilidad del catálogo |
| CU-027 | Versionado comercial de publicaciones |
| CU-028 | Gestión de favoritos |
| CU-029 | Solicitud de acceso temporal |
| CU-030 | Otorgamiento/revocación/vencimiento del acceso (7 días) |
| CU-031 | Gestión del catálogo maestro del tenant |
| CU-032 | Configuración de elementos y ajustes por publicación |
| CU-033 | Motor de precios con desglose y depósito |
| CU-034 | Simulación de precio con la configuración |
| CU-035 | Reserva con escrow de prueba |
| CU-036 | Aceptación atómica y rechazo de reservas competidoras |
| CU-037 | Expiración y reembolso idempotente de reservas |
| CU-038 | Notificación de eventos |
| CU-039 | Exportación de plano/GLB |
| CU-040 | Auditoría y retención del tenant |

| PAQUETE FUNCIONAL | CASOS DE USO RELACIONADOS | DESCRIPCIÓN |
| --- | --- | --- |
| Autenticación y administración | CU-001..CU-009 | Agrupa registro, autenticación, verificación de correo, onboarding, suscripción, invitación de agentes, membresías y permisos. |
| Captura y reconstrucción 3D | CU-010..CU-019 | Comprende captura guiada, subida, validación, solicitud y seguimiento de jobs, ejecución del worker, artefactos, plano 2D, aprobación y composición espacial. |
| Acceso y visualización | CU-020..CU-023, CU-029..CU-030 | Incluye recorrido 3D, medidas, plano 2D para cliente, configuración visual, solicitud y otorgamiento de acceso temporal. |
| Publicaciones y catálogo | CU-024..CU-028 | Agrupa borrador, revisión/aprobación, publicación/despublicación, versionado, catálogo global y favoritos. |
| Precios y reservas | CU-031..CU-037 | Incluye catálogo maestro, configuración de elementos, motor de precios, simulación, reserva con escrow, aceptación atómica y expiración. |
| Notificaciones, exportación y auditoría | CU-038..CU-040 | Comprende notificación de eventos, exportación restringida y auditoría/retención del tenant. |

> **GAP-071**: los flujos principales, alternativos y de excepción de cada CU se desarrollan en el módulo "02-proceso-por-hu" del sprint que la implementa (patrón del CAPITULO 2 del modelo).
>
> **Diagrama asociado**: tipo **Use Case** (diagrama de casos de uso CU-001..CU-040) — ver [`tipos-diagramas-modelo.md`](../../sprint-0/tipos-diagramas-modelo.md).
