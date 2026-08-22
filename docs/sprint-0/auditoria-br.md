# Auditoría de Reglas de Negocio — RoomForge (Sprint 0)

| Campo | Valor |
| --- | --- |
| Artefacto | Matriz consolidada de reglas de negocio (BR) |
| Estado | Borrador de auditoría — IDs provisionales |
| Fuentes | Decisiones `roomforge/*` en Engram (obs 2269–2405) |
| Uso | Alimenta el módulo de reglas de negocio y la matriz de trazabilidad del Sprint 0 |

> Convención: `BR-###` provisional; los IDs definitivos se asignan al derivar la trazabilidad. Cada regla cita su fuente para verificación. `GAP` = dato pendiente, no inventado.

## A. Identidad y tenancy

| ID prov | Regla | Actor / Ámbito | Fuente |
| --- | --- | --- | --- |
| BR-A1 | El cliente se registra por cuenta propia como usuario global, sin membresía en inmobiliaria; una cuenta consulta publicaciones de todos los tenants. | Cliente | obs-2301 |
| BR-A2 | Las inmobiliarias operan como tenants aislados (multi-tenant); las consultas globales nunca usan `tenant_id` del cliente como autorización. | Backend | obs-2302 |
| BR-A3 | El administrador del tenant crea las cuentas/membresías de sus agentes; el agente no se autorregistra ni solicita acceso libre. | Admin tenant | obs-2330 |
| BR-A4 | El admin ingresa identidad y correo del agente, nunca una contraseña; se genera invitación pendiente con enlace seguro de un solo uso. | Admin tenant / Agente | obs-2330 |
| BR-A5 | Un correo ya existente como usuario global se reutiliza: se agrega la membresía sin duplicar cuenta ni reemplazar credenciales. | Backend | obs-2330 |
| BR-A6 | Cada agente tiene como máximo **una membresía activa**; correo personal conserva miembros históricos y movilidad; correo corporativo queda vinculado al tenant. | Agente | obs-2331, obs-2332 |
| BR-A7 | `inactive` y `revoked` niegan acceso sin borrar autoría histórica; restricción transaccional única contra activaciones concurrentes. | Backend | obs-2332 |
| BR-A8 | Permisos predefinidos con alcance por inmueble o por tenant, asignados por el administrador. | Admin tenant | obs-2347 |
| BR-A9 | El agente es el actor autorizado para la composición espacial del inmueble (ensamblado de ambientes). | Agente | obs-2293 |
| BR-A10 | Permisos por defecto según rol: admin = todo tenant-scoped; agente = conjunto base por inmueble; el admin puede otorgar/denegar los de alcance por inmueble. | Admin | decisión 2026-08-22 |
| BR-A11 | `catalog.manage`: gestionar catálogo maestro y reglas de ajuste. Solo admin. | Admin (tenant) | decisión 2026-08-22 |
| BR-A12 | `prop.edit` / `prop.publish`: editar y publicar inmuebles. admin (tenant) y agente (por inmueble). | Admin / Agente | decisión 2026-08-22 |
| BR-A13 | `prop.approve`: aprobar/rechazar publicaciones. Solo admin. | Admin | decisión 2026-08-22 |
| BR-A14 | `capture.upload` / `recon.request`: subir capturas y solicitar reconstrucción. Por inmueble. | Agente | decisión 2026-08-22 |
| BR-A15 | `recon.approve`: aprobar/rechazar reconstrucción. Por inmueble. | Admin / Agente | decisión 2026-08-22 |
| BR-A16 | `compose.edit`: composición espacial del inmueble. Por inmueble. | Agente | decisión 2026-08-22 |
| BR-A17 | `pricing.adjust`: ajustar precios por publicación. Por inmueble. | Admin / Agente | decisión 2026-08-22 |
| BR-A18 | `reservation.decide`: aceptar/rechazar reservas. Tenant. | Admin / Agente | decisión 2026-08-22 |
| BR-A19 | `tour_access.decide`: aprobar/revocar acceso temporal. Por inmueble. | Admin / Agente | decisión 2026-08-22 |
| BR-A20 | `export.download`: exportar plano 2D / GLB. Tenant. | Admin / Agente | decisión 2026-08-22 |
| BR-A21 | `members.manage`: administrar agentes y membresías. Solo admin. | Admin | decisión 2026-08-22 |
| BR-A22 | `audit.view`: consultar auditoría. Solo admin. | Admin | decisión 2026-08-22 |

## B. Onboarding SaaS y planes

| ID prov | Regla | Actor / Ámbito | Fuente |
| --- | --- | --- | --- |
| BR-B1 | Checkout local **claramente simulado** antes de activar el tenant; un evento firmado del simulador autoriza la provisión. | Inmobiliaria backend | obs-2322 |
| BR-B2 | El primer administrador recibe enlace de un solo uso para establecer su contraseña; nunca se envían contraseñas. | Admin tenant | obs-2322 |
| BR-B3 | Prueba de 14 días; tres planes mensuales en BOB con las mismas funciones centrales y cuotas distintas (almacenamiento, inmuebles activos, reconstrucciones/mes). | Simulador | obs-2324, obs-2385 |
| BR-B4 | Estados de suscripción: `trialing`, `active`, `past_due`, `suspended`, `canceled_read_only`, `purged`; gracia de cobro 3 días. | Simulador / backend | obs-2324 |
| BR-B5 | Subida de plan inmediata; bajada al renovar, sin prorrateo real. | Simulador | obs-2324, obs-2385 |
| BR-B6 | Al alcanzar/caer bajo una cuota: se conservan datos existentes y se bloquean nuevas altas, subidas y reconstrucciones. Límites aplicados en servidor. | Backend | obs-2324, obs-2385 |
| BR-B7 | Al cancelar, el tenant pasa a `canceled_read_only` por **30 días conservando todo**: el catálogo publicado sigue visible y las reservas aceptadas siguen su curso. Se bloquean: publicaciones/ediciones nuevas, subidas de capturas, reconstrucciones, reservas nuevas y aprobaciones. | Backend | obs-2324, decisión 2026-08-22 |
| BR-B8 | A los 30 días, el tenant pasa a `purged`: se eliminan los datos del tenant y su contenido se despublica; se conservan únicamente las transacciones anonimizadas exigidas por retención. | Backend | decisión 2026-08-22 |
| BR-B9 | Nombres, precios y cantidades de los planes se fijan tras SPK-01/SPK-04 (GAP). | Equipo | GAP-061 |

## C. Publicaciones y catálogo

| ID prov | Regla | Actor / Ámbito | Fuente |
| --- | --- | --- | --- |
| BR-C1 | Estados de publicación: `borrador`, `en_revision`, `publicado`, `rechazado`, `despublicado`; cada transición registra actor, fecha y observaciones. | Admin / Agente | obs-2303 |
| BR-C2 | El agente no puede autoaprobar su borrador; la aprobación es responsabilidad del administrador. | Admin | obs-2303 |
| BR-C3 | El catálogo global muestra **solo publicaciones `publicado`**; borradores y contenidos internos visibles únicamente para el tenant propietario. | Backend | obs-2302 |
| BR-C4 | Cambios comerciales en una publicación activa crean una **nueva revisión en borrador**; la versión publicada sigue visible hasta aprobar; las reservas conservan la versión usada. | Admin / Backend | obs-2310 |
| BR-C5 | El administrador define el catálogo de elementos (muebles/electrodomésticos/categorías/reglas); tenant-scoped y versionado; el agente selecciona sin modificar el precio maestro. | Admin | obs-2308 |
| BR-C6 | Ubicación del inmueble: exacta / aproximada / oculta, según política de la inmobiliaria. | Admin | obs-2347 |
| BR-C7 | Si una publicación deja de estar publicada, permanece en favoritos como "ya no disponible", sin exponer contenido privado actualizado. | Cliente | obs-2318 |
| BR-C8 | Defectos funcionales de la reconstrucción bloquean la publicación (calidad mínima). | Backend | RNF rendimiento (obs-2386) |

## D. Configuración y precios

| ID prov | Regla | Actor / Ámbito | Fuente |
| --- | --- | --- | --- |
| BR-D1 | Todas las publicaciones son configurables; en venta las opciones modifican el **precio total**; en alquiler, la **mensualidad**. | Backend | obs-2306 |
| BR-D2 | Elementos clasificados como obligatorios, incluidos-removibles u opcionales-agregables. | Backend | obs-2306 |
| BR-D3 | El backend calcula y muestra el desglose; al crear la reserva congela versión, opciones y reglas. | Backend | obs-2306 |
| BR-D4 | Venta: depósito = % configurable del precio final, default `1%`. Alquiler: depósito = mensualidad final × multiplicador, default `1,0`. Sobrescribibles por tenant y por publicación. | Admin / Tenant | obs-2307 |
| BR-D5 | Ajustes de precio por elemento se configuran por publicación (agente y admin); el catálogo del tenant actúa como plantilla; la instancia conserva su ajuste real. | Agente / Admin | obs-2309 |
| BR-D6 | Catálogo 3D acotado low-poly reutilizable; fallback genérico (caja/panel) cuando no hay modelo; precio e identidad comercial no dependen del activo visual. | Equipo | obs-2344 |

## E. Acceso temporal al detalle

| ID prov | Regla | Actor / Ámbito | Fuente |
| --- | --- | --- | --- |
| BR-E1 | El cliente consulta la ficha pública y **solicita acceso** al contenido detallado; la solicitud notifica a agente y administrador. | Cliente / Backend | obs-2377 |
| BR-E2 | El agente aprueba como responsable principal; el administrador puede aprobar/revocar como respaldo. | Agente / Admin | obs-2377 |
| BR-E3 | El permiso dura **7 días** desde la aprobación y habilita recorrido 3D, plano 2D, medidas disponibles, hotspots/configuración y simulación de precio; la ubicación conserva su propia política. | Cliente | obs-2377 |
| BR-E4 | Al vencer, toda renovación exige nueva solicitud y aprobación. | Cliente / Agente | obs-2377 |
| BR-E5 | Rechazo o revocación exige motivo y auditoría. | Agente / Admin | obs-2377 |
| BR-E6 | Despublicar el inmueble revoca inmediatamente los permisos activos y notifica al cliente. | Backend | obs-2377 |

## F. Reservas y escrow

| ID prov | Regla | Actor / Ámbito | Fuente |
| --- | --- | --- | --- |
| BR-F1 | Reserva de **precio fijo** calculado por la configuración en venta y alquiler; sin negociación ni contraofertas. | Cliente | obs-2311 |
| BR-F2 | La reserva expresa intención y no constituye compraventa/alquiler legal; conserva inmueble, operación, configuración, precio, vigencia y versión de reglas. | Backend | obs-2311 |
| BR-F3 | Vigencia 72 h por defecto; configurable por tenant y sobrescribible por publicación; **congelada al crear** la reserva; independiente del acceso temporal (7 días). | Admin | obs-2315 |
| BR-F4 | Al vencer, transición única a `expirada` y reembolso idempotente del depósito. | Backend | obs-2315 |
| BR-F5 | Varias reservas pendientes simultáneas por inmueble; la aceptación es **atómica**: una pasa a aceptada, el inmueble queda bloqueado, las demás pasan a rechazadas con reembolso; sin carreras ni reembolsos duplicados. | Backend | obs-2312 |
| BR-F6 | Escrow con token de prueba sin valor real: bloqueado al confirmar, liberado al aceptar, reembolsado ante rechazo, expiración o cancelación previa a aceptación; transiciones únicas y acciones bloqueadas tras estado terminal. | Blockchain / Backend | obs-2269, obs-2270 |
| BR-F7 | Sin visitas presenciales en el MVP; la reserva es solo flujo comercial con configuración, precio y depósito de prueba. | Alcance | obs-2334 |

## G. Contenido 3D, captura y composición

| ID prov | Regla | Actor / Ámbito | Fuente |
| --- | --- | --- | --- |
| BR-G1 | Captura y reconstrucción por ambiente; el agente ensambla en editor 2D (posición, rotación, escala) y conecta accesos (puertas) para formar el inmueble. | Agente | obs-2292, obs-2293 |
| BR-G2 | Cada ambiente aceptado produce GLB navegable + plano 2D básico; las medidas se etiquetan `estimadas`/`calibradas` con confianza visible; sin referencia métrica externa siempre `estimada`. | Backend / UI | obs-2291, SPK-02 |
| BR-G3 | El trabajo se persiste en backend antes de encolarse; la indisponibilidad del worker no derriba catálogo, autenticación ni reservas; degradación explícita. | Backend | obs-2359 |
| BR-G4 | Difuminado automático (rostro/texto) + **revisión humana antes de publicar**; la redacción automática no sustituye la revisión. | App / Admin | obs-2366 |

## H. Exportación, retención y privacidad

| ID prov | Regla | Actor / Ámbito | Fuente |
| --- | --- | --- | --- |
| BR-H1 | Solo agentes autorizados y administradores descargan plano 2D y GLB; los clientes solo visualizan dentro de RoomForge. | Agente / Admin | obs-2338 |
| BR-H2 | Descargas con URLs firmadas de corta duración, validación de tenant/rol/permiso/alcance y auditoría; respeta el estado del tenant. | Backend | obs-2338 |
| BR-H3 | La exportación cubre derivados aprobados; no implica acceso a videos/fotos originales. | Backend | obs-2338 |
| BR-H4 | Capturas crudas (video/fotos) se eliminan automáticamente a los **30 días** de aceptar la reconstrucción. | Backend | obs-2364 |
| BR-H5 | Tras borrado definitivo, los derivados sobreviven **7 días** recuperables e inaccesibles al público y luego se purgan. | Backend | obs-2369 |

## I. Notificaciones

| ID prov | Regla | Actor / Ámbito | Fuente |
| --- | --- | --- | --- |
| BR-I1 | Canales: in-app (panel + apps Flutter) siempre con bandeja; push móvil opt-in; correo transaccional (Gmail dedicado) solo para eventos sin sesión o críticos; jamás contraseñas. | Backend | decisión 2026-08-22 |
| BR-I2 | Solicitud de acceso temporal notifica a agente y admin del tenant (BR-E1). | Backend | decisión 2026-08-22 |
| BR-I3 | Acceso aprobado/revocado/vencido notifica al cliente. | Backend | decisión 2026-08-22 |
| BR-I4 | Publicación en revisión/aprobada/rechazada notifica al agente autor (y al admin en revisión). | Backend | decisión 2026-08-22 |
| BR-I5 | Reserva pendiente nueva notifica agente/admin del tenant; aceptada/rechazada/expirada notifica al cliente. | Backend | decisión 2026-08-22 |
| BR-I6 | Reconstrucción terminada/fallida notifica al agente solicitante. | Backend | decisión 2026-08-22 |
| BR-I7 | Suscripción `past_due`/suspendida/cancelada/próxima a purgar notifica a los admins del tenant. | Backend | decisión 2026-08-22 |
| BR-I8 | Despublicación con accesos activos notifica a los clientes afectados (BR-E6). | Backend | decisión 2026-08-22 |
| BR-I9 | Toda notificación queda registrada en auditoría con motivo y destinatarios; son informativas post-evento con deep link (no bloquean flujos); los únicos enlaces firmados de un solo uso son activación/invitación. | Backend | decisión 2026-08-22 |

## Hallazgos de la auditoría

**Contradicciones duras: ninguna detectada.** Las reglas de reservas, acceso temporal, planes y publicación son mutuamente consistentes (plazos independientes, transiciones únicas, versionado sin reescritura).

**Gaps y ambigüedades a cerrar:**

| ID | Hallazgo | Acción |
| --- | --- | --- |
| GAP-060 | ~~`purged`: cuándo y cómo se purga un tenant cancelado~~ | **Cerrado (2026-08-22)** → BR-B7/BR-B8 |
| GAP-061 | Nombres, precios y cuotas de los 3 planes | Esperar SPK-01/SPK-04 |
| GAP-062 | ~~Lista concreta de permisos predefinidos (alcance inmueble/tenant) no está enumerada~~ | **Cerrado (2026-08-22)** → BR-A10…BR-A22 |
| GAP-063 | ~~Detalle de notificaciones (canales, triggers, destinatarios) solo está agregado en la línea base~~ | **Cerrado (2026-08-22)** → BR-I1…BR-I9 |
| GAP-064 | ~~Cancelación: qué bloquea el estado `canceled_read_only` exactamente~~ | **Cerrado (2026-08-22)** → BR-B7 |
| GAP-065 | Tolerancia numérica de medidas (calibrada/estimada) | Esperar SPK-02 |
| GAP-066 | Timeout técnico de jobs y concurrencia del worker | Esperar SPK-01 |
| GAP-067 | Límite mínimo para ocultar medidas por confianza | Esperar SPK-02 |

## Próximos pasos

1. Cerrar o aceptar como GAP los hallazgos de esta auditoría.
2. Asignar IDs definitivos `BR-###` y construir la matriz de trazabilidad RF/RNF/BR/PB/HU/CU.
