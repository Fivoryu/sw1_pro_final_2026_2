# Sprint 0 — Ámbito, objetivos y descripción

| Campo | Valor |
| --- | --- |
| Módulo | S0-02 — CAPITULO 1, apartado 2 |
| Estado | done |
| IDs | OBJ-001..006; RF-001..041; RNF-001..018 |
| Fuentes | `docs/sprint-0/ids-trazabilidad.md`; línea base funcional (Engram obs-2346) |

## Ámbito del MVP

**RoomForge es un SaaS inmobiliario académico B2B2C multi-tenant**: las inmobiliarias (tenants) capturan ambientes reales con el celular, generan recorridos 3D y planos, configuran precios y publican inmuebles; los clientes globales consultan el catálogo, recorren inmuebles aprobados y reservan con un escrow de token de prueba.

### Incluido

- Identidad global de clientes (registro con correo, sin verificación hasta RF-033) y autenticación segura.
- Tenants, agentes, invitaciones, permisos RBAC y una membresía activa por agente.
- Onboarding SaaS con checkout simulado y suscripción mensual (3 planes, cuotas).
- Captura híbrida (video + fotos), difuminado automático, reconstrucción asíncrona por ambiente (worker Meshroom), GLB y plano 2D. La asistencia IA offline en la captura es un enfoque propuesto, pendiente de confirmación/formalización.
- Composición espacial 2D, recorrido 3D, medidas `estimadas`/`calibradas`, configuración visual low-poly.
- Publicaciones con aprobación administrativa y versionado; catálogo global solo de publicados.
- Acceso temporal al detalle (7 días, aprobación con auditoría).
- Motor de precios con desglose y depósito por operación.
- Reservas concurrentes con escrow de token de prueba y aceptación atómica.
- Favoritos, notificaciones, exportación restringida al tenant, auditoría y retención.
- Entregables cloud: frontend (app móvil + panel web), backend y base de datos en AWS.

### Excluido del MVP (explícito)

- Visitas presenciales agendadas (BR-058).
- Propietario como actor del sistema.
- Pagos reales y moneda real (todo simulado: facturación y escrow).
- CAD/BIM completo, IA generativa de paredes y detección automática obligatoria de contenido como condición para completar la captura. La asistencia IA offline propuesta no implica reconstrucción generativa ni constituye todavía un requisito aprobado.
- Elementos fijos configurables (cocinas, closets) como catálogo extenso; catálogo low-poly acotado.
- Publicación en Google Play/App Store y build iOS verificada (iOS queda como compatibilidad de código no probada — RNF-013).

## Objetivos

| ID | Objetivo | Fuente |
| --- | --- | --- |
| OBJ-001 | Catálogo inmobiliario multi-tenant con recorridos 3D navegables de inmuebles reales capturados con celular | línea base funcional |
| OBJ-002 | Inmobiliarias configuran precios, elementos y reglas y publican con aprobación administrativa | obs-2303..2310 |
| OBJ-003 | Reservas comerciales simuladas con escrow de token de prueba | obs-2311..2315 |
| OBJ-004 | SaaS completo demostrable: onboarding, suscripción simulada y cuotas | obs-2322, 2324, 2385 |
| OBJ-005 | Frontend (móvil + panel), backend y base de datos desplegados en AWS | requisito docente, obs-2391 |
| OBJ-006 | MVP en 2,5 meses con equipo de 6, priorizando demo funcional | planificación |

## Descripción funcional (resumen de la línea base)

1. El **cliente** se registra (correo cualquiera en fases tempranas), consulta el catálogo global, solicita acceso detallado a un inmueble y, una vez aprobado (7 días), recorre el 3D, revisa medidas y simula precios; puede reservar con depósito de prueba.
2. La **inmobiliaria** se da de alta con checkout simulado; su **administrador** activa el plan, invita agentes, asigna permisos, aprueba publicaciones y gestiona el catálogo maestro.
3. El **agente** captura ambientes con la app, puede recibir la asistencia IA offline propuesta durante el recorrido, solicita reconstrucciones, las aprueba tras un preview, compone el inmueble en 2D y publica con configuración de precios.
4. El **sistema/worker** reconstruye los ambientes de forma asíncrona (SQS + Meshroom), genera GLB y plano 2D, y mantiene los estados del dominio con PostgreSQL como autoridad.

## Actores y superficies

| Actor | Descripción | Superficies |
| --- | --- | --- |
| Cliente global | Usuario sin membresía; consulta catálogo, recorre, reserva | App móvil cliente (Android 10+) |
| Inmobiliaria | Tenant del SaaS; activa plan y opera el negocio | Panel web / backend |
| Administrador (tenant) | Controla plan, agentes, permisos, catálogo y aprobaciones | Panel web (Chrome/Edge) |
| Agente | Captura, compone y publica inmuebles | App de captura + panel web |
| Sistema / Worker 3D | Procesa reconstrucciones y notificaciones | Backend (FastAPI) + worker Python/Meshroom |
| Blockchain (escrow) | Registra y valida movimientos del token de prueba | Red local Hardhat + listener |

> Clasificación completa de plataformas por ítem del backlog: `docs/sprint-0/ids-trazabilidad.md` §6.1.
