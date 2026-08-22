# IDs y matriz de trazabilidad — RoomForge (Sprint 0)

| Campo | Valor |
| --- | --- |
| Artefacto | Registro canónico de IDs y matriz de trazabilidad |
| Estado | Propuesto — validación del equipo pendiente (v3: backlog granular 49 PB / 40 HU / 40 CU) |
| Convención fuente | `references/estandar-documentacion.md` (IDs estables, sin reciclar) |
| Naturaleza | Derivado de las decisiones `roomforge/*` y de `docs/sprint-0/auditoria-br.md` |

## 1. Convención de IDs

- Sintaxis única del proyecto: `OBJ-###`, `RF-###`, `RNF-###`, `BR-###`, `PB-###`, `HU-###`, `CU-###`, `SP-##`, `TASK-###`, `TC-###`, `REV-##`, `GAP-###`.
- Nunca se recicla un ID; el registro definitivo vivirá en `docs/README.md` cuando exista.
- Cadena de trazabilidad: **PAPS objetivos → RF/RNF/BR → PB/HU/CU → SP/TASK → diseño → implementación → TC → REV**.
- La columna *Sprint (propuesta)* es provisional: la división final se fija en el módulo 08 (planificación).
- *Complejidad* (S/M/L) es una estimación relativa propuesta para ordenar el trabajo; las horas puntuales se definen en la planificación (GAP-072). Un PB con complejidad A (alta) debe partirse en TASKs dentro del sprint.

## 2. Objetivos (OBJ)

| ID | Objetivo | Fuente |
| --- | --- | --- |
| OBJ-001 | Catálogo inmobiliario multi-tenant con recorridos 3D navegables de inmuebles reales capturados con celular | línea base funcional |
| OBJ-002 | Inmobiliarias configuran precios, elementos y reglas y publican con aprobación administrativa | obs-2303..2310 |
| OBJ-003 | Reservas comerciales simuladas con escrow de token de prueba | obs-2311..2315 |
| OBJ-004 | SaaS completo demostrable: onboarding, suscripción simulada y cuotas | obs-2322, 2324, 2385 |
| OBJ-005 | Frontend (móvil + panel), backend y base de datos desplegados en AWS | requisito docente, obs-2391 |
| OBJ-006 | MVP en 2,5 meses con equipo de 6, priorizando demo funcional | planificación |

## 3. Requisitos funcionales (RF)

| ID | Requisito | Área | Sprint (propuesta) | Fuente |
| --- | --- | --- | --- | --- |
| RF-001 | Registro de cliente con correo (cualquiera, sin verificación) y contraseña; admite correo inventado para pruebas | Identidad | 1–2 | decisión 2026-08-22 |
| RF-002 | Autenticación Argon2id + JWT/refresh + sesión por inactividad | Identidad | 1 | RNF-006 |
| RF-003 | Alta de inmobiliaria vía checkout simulado con evento firmado y provisión de tenant | Onboarding | 1 | obs-2322 |
| RF-004 | Gestión de agentes por admin: invitación con enlace de un solo uso | Tenancy | 1 | obs-2330 |
| RF-005 | RBAC con permisos predefinidos por alcance tenant/inmueble | Tenancy | 1 | BR-005..017 |
| RF-006 | Restricción: una membresía activa por agente | Tenancy | 1 | obs-2332 |
| RF-007 | Trial 14 días + suscripción mensual simulada (3 planes, BOB) | Planes | 1 | obs-2324, 2385 |
| RF-008 | Estados de suscripción, cuotas y bloqueo over-quota | Planes | 1–2 | obs-2324 |
| RF-009 | Upgrade inmediato / downgrade a renovación | Planes | 2 | obs-2324 |
| RF-010 | Captura híbrida (video guiado + fotos) desde app móvil Android | Captura | 2 | obs-2292 |
| RF-011 | Difuminado automático de rostros y texto en capturas | Captura | 2 | obs-2366 |
| RF-012 | Solicitud de reconstrucción asíncrona (SQS) con persistencia previa al encolado | 3D | 2 | obs-2279, 2359 |
| RF-013 | Aprobación/rechazo de reconstrucción por agente/admin | 3D | 2 | BR-015 |
| RF-014 | Generación de GLB navegable + plano 2D básico por ambiente | 3D | 2 | obs-2291 |
| RF-015 | Composición espacial 2D: ensamblado de ambientes y conexión de puertas | Composición | 2 | obs-2292, 2293 |
| RF-016 | Recorrido 3D navegable (visor Three.js/WebView y app) | Visualización | 2–3 | obs-2276 |
| RF-017 | Configuración visual: catálogo low-poly acotado + fallback genérico | Visualización | 3 | obs-2344 |
| RF-018 | Medidas etiquetadas `estimadas`/`calibradas` con confianza visible | Visualización | 2–3 | obs-2386, SPK-02 |
| RF-019 | Workflow de publicación con aprobación y estados (editor + revisión) | Publicación | 1 | obs-2303 |
| RF-020 | Versionado de cambios comerciales sin reescribir reservas | Publicación | 3 | obs-2310 |
| RF-021 | Catálogo global solo con publicaciones `publicado` | Catálogo | 1 | obs-2302 |
| RF-022 | Solicitud/aprobación de acceso temporal detallado (7 días) | Acceso | 3 | obs-2377 |
| RF-023 | Revocación inmediata de accesos al despublicar | Acceso | 3 | obs-2377 |
| RF-024 | Configuración de elementos por publicación (obligatorios/incluidos/opcionales) | Precios | 2 | obs-2306 |
| RF-025 | Motor de precios con desglose y cálculo de depósito por operación | Precios | 2 | obs-2306, 2307 |
| RF-026 | Catálogo maestro de tenant + ajustes por publicación | Precios | 2 | obs-2308, 2309 |
| RF-027 | Reserva de precio fijo con escrow de token de prueba | Reservas | 2 | obs-2311, 2312 |
| RF-028 | Aceptación atómica con rechazo y reembolso de competidoras | Reservas | 2–3 | obs-2312 |
| RF-029 | Vigencia de reserva congelada y expiración idempotente | Reservas | 2–3 | obs-2315 |
| RF-030 | Favoritos con estado "ya no disponible" | Catálogo | 1 | obs-2318 |
| RF-031 | Notificaciones in-app/push/correo con auditoría | Notificaciones | 3 | BR-068..076 |
| RF-032 | Exportación de plano/GLB restringida a personal autorizado del tenant | Exportación | 3 | obs-2338 |
| RF-033 | Verificación de correo real con enlace de activación de un solo uso y reenvío acotado (reemplaza el modo "correo cualquiera" en la demo final) | Identidad | 3 | decisión 2026-08-22 |
| RF-034 | Guía de captura en la app (pasos de video + fotos) y subida con progreso y reanudación | Captura | 2 | obs-2292 |
| RF-035 | Validación mínima de capturas (cantidad, resolución, cobertura) con aviso de recaptura selectiva | Captura | 2 | obs-2386, derivado |
| RF-036 | Estados de job: `pending`, `running`, `done`, `failed`, `delayed` (worker ausente); reintentos y expiración acotados | 3D | 2 | obs-2359 |
| RF-037 | Worker 3D: heartbeat, idempotencia, descarga de inputs desde S3, reentrega tolerada | 3D | 2 | obs-2279, SPK-01 |
| RF-038 | Artefactos por ambiente: GLB optimizado, nubes de puntos (intermedias), texturas | 3D | 2 | obs-2291, SPK-01 |
| RF-039 | Derivación de plano 2D básico desde la reconstrucción (proyección de ambientes) | 3D | 2–3 | obs-2291 |
| RF-040 | Preview de reconstrucción (visor + plano) antes de aprobar/rechazar | 3D | 2 | obs-2386 |
| RF-041 | Consulta del plano 2D del inmueble por el cliente con acceso aprobado | Visualización | 3 | obs-2377 |

## 4. Requisitos no funcionales (RNF)

| ID | Requisito | Categoría | Fuente | Número |
| --- | --- | --- | --- | --- |
| RNF-001 | Medidas etiquetadas y tolerancia de exactitud | Precisión | obs-2386 | tras SPK-02 (GAP-065) |
| RNF-002 | Reconstrucción por ambiente ≤ 30 min (objetivo) | Rendimiento | obs-2386 | validar SPK-01 (GAP-066) |
| RNF-003 | Operaciones de API p95 ≤ 2 s | Rendimiento | obs-2386 | fijo |
| RNF-004 | Visor 3D: 30 FPS objetivo, 24 FPS mínimo; primera vista ≤ 20 s | Rendimiento | obs-2386 | fijo |
| RNF-005 | Recuperación de servicios centrales ≤ 5 min en demo; jobs demorados continúan | Disponibilidad | obs-2359, 2386 | fijo |
| RNF-006 | TOTP administrativo, sesión inactiva 30 min, baseline multi-tenant | Seguridad | obs-2386 | fijo |
| RNF-007 | Capturas crudas: 30 días; derivados: 7 días recuperables | Privacidad | obs-2364, 2369 | fijo |
| RNF-008 | Difuminado automático + revisión humana antes de publicar | Privacidad | obs-2366 | fijo |
| RNF-009 | Cuentas eliminadas anonimizan transacciones | Privacidad | obs-2386 | fijo |
| RNF-010 | Logs técnicos 7 días; auditoría 90 días | Privacidad | obs-2386 | fijo |
| RNF-011 | Android 10+, 64-bit, 4 GB RAM | Compatibilidad | obs-2245 | fijo |
| RNF-012 | Chrome y Edge (2 últimas versiones estables) | Compatibilidad | obs-2373 | fijo |
| RNF-013 | iOS: compatible en código, no verificado (gap declarado) | Compatibilidad | obs-2274 | no ejecutado |
| RNF-014 | Accesibilidad WCAG 2.2 AA + alternativa plano 2D y ficha | Accesibilidad | obs-2386 | fijo |
| RNF-015 | Observabilidad: panel + correo, métricas accionables | Observabilidad | obs-2386 | fijo |
| RNF-016 | Degradación explícita ante indisponibilidad del worker | Disponibilidad | obs-2359 | fijo |
| RNF-017 | Enlaces de un solo uso para activación/invitación; jamás contraseñas por correo (activo en Sprint 3 con RF-033) | Seguridad | BR-004, 024 | fijo |
| RNF-018 | Costo AWS controlado; despliegue diferido a días antes de la presentación | Costo | decisión 2026-08-22 | fijo |

## 5. Reglas de negocio (BR)

Numeración definitiva: se conserva el orden de `docs/sprint-0/auditoria-br.md` (secciones A→I):

| Rango final | Sección de auditoría | Tema |
| --- | --- | --- |
| BR-001 … BR-022 | BR-A1 … BR-A22 | Identidad, tenancy y permisos RBAC |
| BR-023 … BR-031 | BR-B1 … BR-B9 | Onboarding SaaS, planes y ciclo de suscripción |
| BR-032 … BR-039 | BR-C1 … BR-C8 | Publicaciones y catálogo |
| BR-040 … BR-045 | BR-D1 … BR-D6 | Configuración y precios |
| BR-046 … BR-051 | BR-E1 … BR-E6 | Acceso temporal al detalle |
| BR-052 … BR-058 | BR-F1 … BR-F7 | Reservas y escrow |
| BR-059 … BR-062 | BR-G1 … BR-G4 | Contenido 3D, captura y composición |
| BR-063 … BR-067 | BR-H1 … BR-H5 | Exportación, retención y privacidad |
| BR-068 … BR-076 | BR-I1 … BR-I9 | Notificaciones |

> El texto completo de cada regla vive en la auditoría; este archivo solo fija el mapeo canónico de IDs.

## 6. Product Backlog (PB) — granular

| ID | Ítem | Prioridad | Complejidad | Sprint (prop.) | RF | HU | CU |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PB-001 | Registro de cliente con correo cualquiera y contraseña | Must | S | 1 | RF-001 | HU-001 | CU-001 |
| PB-002 | Autenticación y sesión (JWT/refresh + inactividad 30 min) | Must | M | 1 | RF-002 | HU-002 | CU-002 |
| PB-003 | Verificación de correo real con enlace de un solo uso | Must | M | 3 | RF-033 | HU-003 | CU-003 |
| PB-004 | Alta de inmobiliaria con checkout simulado y evento firmado | Must | M | 1 | RF-003 | HU-004 | CU-004 |
| PB-005 | Trial 14 días y suscripción mensual simulada | Must | M | 1 | RF-007 | HU-005 | CU-005 |
| PB-006 | Ciclo de suscripción: estados, cuotas, upgrade/downgrade, cancelación y purga | Must | A | 1–2 | RF-008, RF-009 | HU-006 | CU-006 |
| PB-007 | Invitación y membresías de agentes (una activa) | Must | M | 1 | RF-004, RF-006 | HU-007, HU-008 | CU-007, CU-008 |
| PB-008 | Permisos RBAC por alcance tenant/inmueble | Must | M | 1 | RF-005 | HU-009 | CU-009 |
| PB-009 | Guía de captura en la app (video + fotos) | Must | S | 2 | RF-034 | HU-010 | CU-010 |
| PB-010 | Subida de capturas con progreso y reanudación | Must | M | 2 | RF-034 | HU-011 | CU-011 |
| PB-011 | Validación de calidad mínima y recaptura selectiva | Must | M | 2 | RF-035 | HU-012 | CU-012 |
| PB-012 | Difuminado automático rostro/texto | Must | M | 2 | RF-011 | — (soporta HU-010) | CU-010 |
| PB-013 | Solicitud de reconstrucción: persiste job y encola | Must | M | 2 | RF-012 | HU-013 | CU-013 |
| PB-014 | Estados de job y reintentos (pending/running/done/failed/delayed) | Must | M | 2 | RF-036 | HU-013, HU-014 | CU-014 |
| PB-015 | Cola SQS: visibility timeout, reentrega tolerada | Must | M | 2 | RF-012, RF-037 | — (soporta CU-013) | CU-015 |
| PB-016 | Worker: heartbeat e idempotencia | Must | M | 2 | RF-037 | — (sistema) | CU-015 |
| PB-017 | Worker: ejecución de Meshroom | Must | A | 2 | RF-037 | — (sistema) | CU-015 |
| PB-018 | GLB optimizado por ambiente | Must | M | 2 | RF-038 | — (sistema) | CU-016 |
| PB-019 | Nubes y texturas intermedias a S3 | Must | M | 2 | RF-038 | — (sistema) | CU-016 |
| PB-020 | Derivación de plano 2D básico | Must | M | 2–3 | RF-039 | — (sistema) | CU-017 |
| PB-021 | Preview y aprobación/rechazo de reconstrucción | Must | M | 2 | RF-013, RF-040 | HU-015 | CU-018 |
| PB-022 | Composición espacial 2D con conexión de puertas | Must | A | 2 | RF-015 | HU-016 | CU-019 |
| PB-023 | Recorrido 3D navegable en panel web | Must | M | 2 | RF-016 | HU-017 | CU-020 |
| PB-024 | Recorrido 3D navegable en app móvil | Must | M | 3 | RF-016 | HU-018 | CU-020 |
| PB-025 | Medidas `estimadas`/`calibradas` con confianza visible | Must | M | 2–3 | RF-018 | HU-019 | CU-021 |
| PB-026 | Plano 2D del inmueble para cliente con acceso | Must | S | 3 | RF-041 | HU-020 | CU-022 |
| PB-027 | Configuración visual con catálogo low-poly y fallback | Should | M | 3 | RF-017 | HU-021 | CU-023 |
| PB-028 | Editor de borrador de publicación | Must | M | 1 | RF-019 | HU-022 | CU-024 |
| PB-029 | Revisión y aprobación administrativa de publicaciones | Must | M | 1 | RF-019 | HU-023, HU-024 | CU-025 |
| PB-030 | Publicación/despublicación y catálogo global | Must | M | 1 | RF-021 | HU-025, HU-026 | CU-026 |
| PB-031 | Versionado de cambios comerciales | Must | A | 3 | RF-020 | HU-027 | CU-027 |
| PB-032 | Favoritos con estado "ya no disponible" | Should | S | 1 | RF-030 | HU-028 | CU-028 |
| PB-033 | Solicitud de acceso temporal al detalle | Must | M | 3 | RF-022 | HU-029 | CU-029 |
| PB-034 | Aprobación/revocación/vencimiento del acceso (7 días) | Must | M | 3 | RF-022, RF-023 | HU-030 | CU-030 |
| PB-035 | Catálogo maestro del tenant | Must | M | 2 | RF-026 | HU-031 | CU-031 |
| PB-036 | Configuración de elementos por publicación | Must | M | 2 | RF-024 | HU-032 | CU-032 |
| PB-037 | Motor de precios con desglose y cálculo de depósito | Must | A | 2 | RF-025 | HU-033 | CU-033 |
| PB-038 | Ajustes de precio por publicación | Must | M | 2 | RF-026 | HU-032 | CU-032 |
| PB-039 | Simulación de precio para el cliente | Must | S | 2 | RF-025 | HU-034 | CU-034 |
| PB-040 | Reserva con precio congelado | Must | M | 2 | RF-027 | HU-035 | CU-035 |
| PB-041 | Escrow de token de prueba (contrato) | Must | A | 2–3 | RF-027 | — (sistema) | CU-035 |
| PB-042 | Aceptación atómica y rechazo de competidoras | Must | A | 2–3 | RF-028 | HU-036 | CU-036 |
| PB-043 | Vigencia, expiración y reembolso idempotente | Must | M | 2–3 | RF-029 | HU-037 | CU-037 |
| PB-044 | Notificaciones in-app/push/correo | Should | M | 3 | RF-031 | HU-038 | CU-038 |
| PB-045 | Exportación de plano/GLB restringida | Should | M | 3 | RF-032 | HU-039 | CU-039 |
| PB-046 | Auditoría y retención (logs 7/90 días, anonimización) | Must | M | 3 | RNF-009, RNF-010 | HU-040 | CU-040 |
| PB-047 | Infraestructura AWS y despliegue final | Must | A | 3 | RNF-005, RNF-018 | — | — |
| PB-048 | Entorno local reproducible (Docker + Floci) | Must | M | 1 | SPK-05 | — | — |
| PB-049 | CI básica (tests + smoke test) | Must | M | 1 | SPK-05 | — | — |

## 6.1 Plataformas por PB

Clasificación de superficies que tocará cada ítem, para orientar la asignación. Leyenda: **BE**=backend FastAPI/PostgreSQL/S3/SQS · **WEB**=panel React · **APP-C**=app móvil cliente · **APP-X**=app móvil captura (agente) · **W3D**=worker 3D Python/Meshroom · **BC**=blockchain Solidity/Hardhat · **DEV**=infraestructura/Docker/CI/AWS

| PB | Plataforma | PB | Plataforma | PB | Plataforma |
| --- | --- | --- | --- | --- | --- |
| PB-001 | BE + APP-C | PB-018 | W3D + BE | PB-034 | WEB + BE + APP-C |
| PB-002 | BE + APP-C + APP-X + WEB | PB-019 | W3D + BE | PB-035 | BE + WEB |
| PB-003 | BE + APP-C | PB-020 | W3D + BE | PB-036 | BE + WEB |
| PB-004 | BE + WEB | PB-021 | BE + WEB | PB-037 | BE + WEB + APP-C |
| PB-005 | BE + WEB | PB-022 | BE + WEB | PB-038 | BE + WEB |
| PB-006 | BE + WEB | PB-023 | WEB | PB-039 | BE + APP-C |
| PB-007 | BE + WEB | PB-024 | APP-C | PB-040 | BE + APP-C |
| PB-008 | BE + WEB | PB-025 | BE + APP-C + WEB | PB-041 | BC + BE |
| PB-009 | APP-X | PB-026 | BE + APP-C | PB-042 | BE + BC + WEB |
| PB-010 | APP-X + BE | PB-027 | BE + WEB | PB-043 | BE + BC |
| PB-011 | APP-X + BE | PB-028 | WEB + BE | PB-044 | BE + APP-C + APP-X + WEB |
| PB-012 | APP-X | PB-029 | WEB + BE | PB-045 | BE + WEB + APP-X |
| PB-013 | APP-X + BE | PB-030 | BE + APP-C + WEB | PB-046 | BE + WEB |
| PB-014 | BE + APP-X + WEB | PB-031 | BE + WEB | PB-047 | DEV |
| PB-015 | BE | PB-032 | BE + APP-C | PB-048 | DEV + BE |
| PB-016 | W3D + BE | PB-033 | APP-C + BE | PB-049 | DEV |
| PB-017 | W3D | — | — | — | — |

> Un integrante puede tocar varias superficies; la clasificación solo indica qué módulos se ven afectados al asignar (GAP-073: asignación final por capacidad en cada sprint planning).

Contrato mínimo; los criterios de aceptación completos se desarrollan en el módulo 06 del Sprint 0 (GAP-070).

| ID | Historia (rol: quiero… para…) | Actor | Prioridad | Sprint (prop.) | Relaciona |
| --- | --- | --- | --- | --- | --- |
| HU-001 | Registrarme con correo (puede ser inventado) y contraseña para probar la plataforma | Cliente | Must | 1 | PB-001, CU-001 |
| HU-002 | Iniciar sesión y mantener mi sesión activa | Cliente | Must | 1 | PB-002, CU-002 |
| HU-003 | Verificar mi correo real con un enlace de activación | Cliente | Must | 3 | PB-003, CU-003 |
| HU-004 | Dar de alta mi inmobiliaria con checkout simulado | Inmobiliaria | Must | 1 | PB-004, CU-004 |
| HU-005 | Activar la prueba de 14 días y suscribirme mensualmente | Admin tenant | Must | 1 | PB-005, CU-005 |
| HU-006 | Gestionar mi suscripción, ver cuotas, cancelar y controlar la purga | Admin tenant | Must | 1–2 | PB-006, CU-006 |
| HU-007 | Invitar agentes y que acepten con enlace seguro | Admin tenant | Must | 1 | PB-007, CU-007 |
| HU-008 | Desactivar/activar membresías de agentes (una activa) | Admin tenant | Must | 1 | PB-007, CU-008 |
| HU-009 | Asignar permisos por alcance a mis agentes | Admin tenant | Must | 1 | PB-008, CU-009 |
| HU-010 | Capturar un ambiente siguiendo la guía en la app | Agente | Must | 2 | PB-009, PB-012, CU-010 |
| HU-011 | Subir mis capturas con progreso y reanudación | Agente | Must | 2 | PB-010, CU-011 |
| HU-012 | Ver avisos de calidad y recapturar un ambiente | Agente | Must | 2 | PB-011, CU-012 |
| HU-013 | Solicitar una reconstrucción y seguir el estado del job | Agente | Must | 2 | PB-013, PB-014, CU-013, CU-014 |
| HU-014 | Ver el detalle de un fallo y reintentar | Agente | Must | 2 | PB-014, CU-014 |
| HU-015 | Revisar el preview (3D + plano) y aprobar o rechazar | Agente/Admin | Must | 2 | PB-021, CU-018 |
| HU-016 | Ensamblar ambientes y conectar puertas del inmueble | Agente | Must | 2 | PB-022, CU-019 |
| HU-017 | Recorrer el inmueble en 3D desde el panel | Agente/Admin | Must | 2 | PB-023, CU-020 |
| HU-018 | Recorrer el inmueble en 3D desde la app | Cliente | Must | 3 | PB-024, CU-020 |
| HU-019 | Ver las medidas y su confianza (estimada/calibrada) | Cliente | Must | 2–3 | PB-025, CU-021 |
| HU-020 | Ver el plano 2D del inmueble | Cliente | Must | 3 | PB-026, CU-022 |
| HU-021 | Configurar los elementos visuales de la publicación | Agente | Should | 3 | PB-027, CU-023 |
| HU-022 | Crear y editar el borrador de una publicación | Agente | Must | 1 | PB-028, CU-024 |
| HU-023 | Enviar la publicación a revisión y conocer el resultado | Agente | Must | 1 | PB-029, CU-025 |
| HU-024 | Aprobar o rechazar publicaciones (incluye verificación de difuminado) | Admin tenant | Must | 1 | PB-029, CU-025 |
| HU-025 | Publicar o despublicar un inmueble | Agente/Admin | Must | 1 | PB-030, CU-026 |
| HU-026 | Consultar el catálogo global | Cliente | Must | 1 | PB-030, CU-026 |
| HU-027 | Revisar que los cambios comerciales quedan versionados sin alterar lo publicado | Agente/Admin | Must | 3 | PB-031, CU-027 |
| HU-028 | Guardar favoritos y ver su estado | Cliente | Should | 1 | PB-032, CU-028 |
| HU-029 | Solicitar acceso al contenido detallado | Cliente | Must | 3 | PB-033, CU-029 |
| HU-030 | Aprobar o revocar accesos temporales | Agente/Admin | Must | 3 | PB-034, CU-030 |
| HU-031 | Mantener el catálogo maestro de elementos y reglas | Admin tenant | Must | 2 | PB-035, CU-031 |
| HU-032 | Configurar elementos y ajustes de precio de un inmueble | Agente | Must | 2 | PB-036, PB-038, CU-032 |
| HU-033 | Ver el desglose del precio y el depósito calculado | Agente/Admin | Must | 2 | PB-037, CU-033 |
| HU-034 | Simular el precio con la configuración | Cliente | Must | 2 | PB-039, CU-034 |
| HU-035 | Reservar un inmueble con depósito de prueba | Cliente | Must | 2 | PB-040, PB-041, CU-035 |
| HU-036 | Aceptar o rechazar reservas pendientes | Agente/Admin | Must | 2–3 | PB-042, CU-036 |
| HU-037 | Ver el estado de mi reserva y su expiración | Cliente | Must | 2–3 | PB-043, CU-037 |
| HU-038 | Recibir notificaciones de eventos relevantes | Todos | Should | 3 | PB-044, CU-038 |
| HU-039 | Exportar el plano y el GLB de mis inmuebles | Agente/Admin | Should | 3 | PB-045, CU-039 |
| HU-040 | Consultar la auditoría y retención del tenant | Admin tenant | Must | 3 | PB-046, CU-040 |

## 8. Casos de uso (CU)

| ID | CU | Actor primario | Sprint (prop.) | Relaciona |
| --- | --- | --- | --- | --- |
| CU-001 | Registro de cliente con correo sin verificar (modo pruebas) | Cliente | 1 | HU-001, RF-001 |
| CU-002 | Autenticación y renovación de sesión | Cliente/Agente/Admin | 1 | HU-002, RF-002 |
| CU-003 | Verificación de correo real con enlace de activación | Cliente | 3 | HU-003, RF-033 |
| CU-004 | Onboarding de inmobiliaria (checkout simulado + provisión) | Inmobiliaria | 1 | HU-004, RF-003 |
| CU-005 | Activación de trial/suscripción con evento firmado | Admin tenant | 1 | HU-005, RF-007 |
| CU-006 | Ciclo de suscripción: cuotas, upgrade/downgrade, cancelación y purga | Admin tenant | 1–2 | HU-006, RF-008, RF-009 |
| CU-007 | Invitación de agente y aceptación | Admin tenant / Agente | 1 | HU-007, RF-004, RF-006 |
| CU-008 | Gestión de membresías (activar/inactivar) | Admin tenant | 1 | HU-008, RF-006 |
| CU-009 | Gestión de permisos RBAC | Admin tenant | 1 | HU-009, RF-005 |
| CU-010 | Captura guiada (incluye difuminado automático) | Agente | 2 | HU-010, RF-010, RF-011, RF-034 |
| CU-011 | Subida de capturas con progreso y reanudación | Agente | 2 | HU-011, RF-034 |
| CU-012 | Validación de calidad y recaptura selectiva | Agente | 2 | HU-012, RF-035 |
| CU-013 | Solicitud de reconstrucción: persistir job y encolar | Agente | 2 | HU-013, RF-012 |
| CU-014 | Seguimiento de estados y reintento del job | Agente | 2 | HU-013, HU-014, RF-036 |
| CU-015 | Ejecución del job en el worker (sistema) | Sistema | 2 | RF-037, RF-012 |
| CU-016 | Generación de artefactos: GLB, nubes, texturas (sistema) | Sistema | 2 | RF-038 |
| CU-017 | Derivación de plano 2D básico (sistema) | Sistema | 2–3 | RF-039 |
| CU-018 | Revisión con preview y aprobación/rechazo de reconstrucción | Agente/Admin | 2 | HU-015, RF-013, RF-040 |
| CU-019 | Composición espacial del inmueble | Agente | 2 | HU-016, RF-015 |
| CU-020 | Recorrido 3D navegable (panel y app) | Cliente/Agente/Admin | 2–3 | HU-017, HU-018, RF-016 |
| CU-021 | Consulta de medidas con confianza | Cliente | 2–3 | HU-019, RF-018 |
| CU-022 | Consulta del plano 2D del inmueble | Cliente | 3 | HU-020, RF-041 |
| CU-023 | Configuración visual con catálogo y fallback | Agente | 3 | HU-021, RF-017 |
| CU-024 | Edición de borrador de publicación | Agente | 1 | HU-022, RF-019 |
| CU-025 | Revisión y aprobación de publicación (verifica redacción) | Admin tenant | 1 | HU-023, HU-024, RF-019, RNF-008 |
| CU-026 | Publicación/despublicación y visibilidad del catálogo | Agente/Admin | 1 | HU-025, HU-026, RF-021 |
| CU-027 | Versionado comercial de publicaciones | Agente/Admin | 3 | HU-027, RF-020 |
| CU-028 | Gestión de favoritos | Cliente | 1 | HU-028, RF-030 |
| CU-029 | Solicitud de acceso temporal | Cliente | 3 | HU-029, RF-022 |
| CU-030 | Otorgamiento/revocación/vencimiento del acceso | Agente/Admin | 3 | HU-030, RF-022, RF-023 |
| CU-031 | Gestión del catálogo maestro | Admin tenant | 2 | HU-031, RF-026 |
| CU-032 | Configuración de elementos y ajustes por publicación | Agente/Admin | 2 | HU-032, RF-024, RF-026 |
| CU-033 | Motor de precios con desglose y depósito | Agente/Admin | 2 | HU-033, RF-025 |
| CU-034 | Simulación de precio con la configuración | Cliente | 2 | HU-034, RF-025 |
| CU-035 | Reserva con escrow de prueba | Cliente | 2 | HU-035, RF-027 |
| CU-036 | Aceptación atómica y rechazo de reservas competidoras | Agente/Admin | 2–3 | HU-036, RF-028 |
| CU-037 | Expiración y reembolso idempotente de reservas | Sistema/Cliente | 2–3 | HU-037, RF-029 |
| CU-038 | Notificación de eventos | Sistema | 3 | HU-038, RF-031 |
| CU-039 | Exportación de plano/GLB | Agente/Admin | 3 | HU-039, RF-032 |
| CU-040 | Auditoría y retención del tenant | Admin tenant | 3 | HU-040, RNF-009, RNF-010 |

## 9. Matriz de trazabilidad

### 9.1 Objetivos → RF

| OBJ | Cubre |
| --- | --- |
| OBJ-001 | RF-014, RF-016, RF-021, RF-041 |
| OBJ-002 | RF-019..026 |
| OBJ-003 | RF-027..029 |
| OBJ-004 | RF-003, RF-007..009 |
| OBJ-005 | RNF-005, RNF-018, PB-047 |
| OBJ-006 | Todo el backlog priorizado Must |

### 9.2 RF → BR

| Área RF | Reglas que la soportan |
| --- | --- |
| Identidad/tenancy (RF-001..006, RF-033) | BR-001..022 |
| Onboarding/planes (RF-003, 007..009) | BR-023..031 |
| Publicaciones/catálogo (RF-019..021, 030) | BR-032..039 |
| Precios (RF-024..026) | BR-040..045 |
| Acceso temporal (RF-022, 023) | BR-046..051 |
| Reservas (RF-027..029) | BR-052..058 |
| 3D/captura (RF-010..018, 034..040) | BR-059..062 |
| Exportación/retención (RF-032) | BR-063..067 |
| Notificaciones (RF-031) | BR-068..076 |

### 9.3 PB → HU/CU

La relación por ítem está integrada en la tabla PB (columnas HU y CU), de modo que cada PB indica sus historias y casos asociados. Verificación inversa en 9.4.

### 9.4 Verificación de consistencia

- [x] 49 PB, 40 HU, 40 CU; toda HU tiene PB y CU relacionados (sin huérfanos).
- [x] Todo CU tiene HU y RF relacionados (los de actor *Sistema* se vinculan al PB/RF de soporte).
- [x] Todo PB tiene RF vinculadas; cada RF tiene BR de soporte (o está marcado como infraestructura).
- [x] RF-001 (correo cualquiera) y RF-033 (correo real) conviven: RF-033 reemplaza al modo pruebas en la demo final.
- [x] Los PB con complejidad A (PB-006, 017, 022, 031, 037, 041, 042, 047) se partirán en TASKs dentro del sprint.
- [x] RNF con números dependientes de spike quedan marcados (GAP-065, GAP-066).
- [x] Todo PB tiene su clasificación de plataforma (sección 6.1) para orientar la asignación.
- [ ] Criterios de aceptación completos por HU → módulo 06 (GAP-070).
- [ ] Flujos alternativos/excepciones por CU → módulo 07 (GAP-071).
- [ ] División final en SP-01/02/03 y estimación de horas → módulo 08 (GAP-072).

## 10. Resumen propuesto por sprint

| Sprint | Foco | PB incluidos |
| --- | --- | --- |
| SP-01 | Fundaciones: identidad, suscripción, agentes/RBAC, publicaciones básicas, favoritos, backend local + CI | PB-001, 002, 004..008, 028, 029, 030, 032, 048, 049 (13) |
| SP-02 | Núcleo 3D y comercial: captura, pipeline, worker, composición, recorrido web, precios, reservas | PB-009..023, 025, 035..040 (22) |
| SP-03 | Cierre: correo real, acceso temporal, visual app, plano, versionado, escrow, notificaciones, exportación, auditoría, AWS | PB-003, 024, 026, 027, 031, 033, 034, 041..047 (14) |

## Gaps asociados

| ID | Descripción |
| --- | --- |
| GAP-065 | Tolerancia numérica de medidas (SPK-02) |
| GAP-066 | Timeout técnico y concurrencia de jobs (SPK-01) |
| GAP-070 | Criterios de aceptación completos por HU → módulo 06 |
| GAP-071 | Flujos alternativos y excepciones por CU → módulo 07 |
| GAP-072 | División definitiva del backlog en Sprint 1/2/3 y estimación → módulo 08 |
| GAP-073 | Asignación de responsables por PB/HU considerando plataforma → cada sprint planning |
| GAP-074 | TBD del escrow blockchain: setup, contrato, eventos, listener, integración, pruebas → ver `docs/sprint-0/blockchain-enfoque.md` |
