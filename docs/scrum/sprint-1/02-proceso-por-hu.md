# Sprint 1 — Proceso/patrón por HU: Diseño (datos)

| Campo | Valor |
| --- | --- |
| Módulo | S1-02 — CAPITULO 2, sección 2 (inicio: Diseño de Datos del Sprint 1) |
| Estado | in progress (diseño conceptual de datos; lógico/físico pendientes) |
| IDs | SP-01; HU-001..009, HU-022..026, HU-028; PB-001..08, 28..30, 32, 48..49 |
| Referencia del modelo | Grupo#12 — CAPITULO 2, 2.1.2 Diseño de Datos (Conceptual/Lógico/Físico) |
| Fuentes | `docs/sprint-0/auditoria-br.md`; `docs/sprint-0/ids-trazabilidad.md`; br-esp: reglas BR-001..045, BR-068..076 |

> El patrón completo por HU (2.1.1 Arquitectura, 2.1.3 Lógica de Negocio, 2.1.4 Implementación, 2.1.5 Pruebas) se completa por HU dentro de este módulo (GAP-070/071). Este documento fija primero el **modelo de datos** del Sprint 1.

## 2.1.2.1. Diseño Conceptual (Sprint 1)

Entidades del dominio que implementan los 13 PB del Sprint 1 sobre **PostgreSQL** (autoridad de estados). Los binarios (GLB, nubes, capturas) no existen aún en SP-01; su modelo llega con el pipeline en SP-02.

| Entidad | Descripción | Atributos clave | Relaciones |
| --- | --- | --- | --- |
| `usuario_global` | Cliente o persona única; cuenta global sin membrecía (BR-001) | id, correo (sin verificar en modo pruebas, RF-001), hash_password (Argon2id), estado, creado_en | 1..*`membresia_agente`; 1..* `favorito` |
| `tenant` | Inmobiliaria aprovisionada tras checkout simulado (BR-023) | id, nombre, estado, creado_en | 1..*`membresia_agente`; 1..1 `suscripcion` (activa); 1..* `publicacion`; 1..* `invitacion` |
| `membresia_agente` | Vínculo agente-tenant; **una activa por agente** (BR-006) | id, tenant_id, usuario_global_id, rol (admin/agente), estado (activa/inactiva/revocada), creado_en | N..1 `usuario_global`; N..1 `tenant`; 1..* `permiso_agente` |
| `invitacion` | Enlace de un solo uso para agentes (BR-004/005, RNF-017) | id, tenant_id, correo, token_unico, expira_en, estado (pendiente/aceptada/expirada) | N..1 `tenant` |
| `permiso_agente` | Asignación de permiso predefinido con alcance (BR-007..019) | id, membresia_agente_id, codigo_permiso (13 predefinidos), alcance (tenant/inmueble), alcance_id | N..1 `membresia_agente` |
| `plan` | Uno de los 3 planes del simulador (BR-024; números → GAP-061) | id, nombre, precio_bob, cuota_almacenamiento_gb, cuota_inmuebles, cuota_reconstrucciones_mes | 1..* `suscripcion` |
| `suscripcion` | Ciclo de suscripción con estados (BR-025..031) | id, tenant_id, plan_id, estado (trialing/active/past_due/suspended/canceled_read_only/purged), trial_fin, periodo_fin, cancelado_en | N..1 `tenant`; N..1 `plan` |
| `evento_facturacion` | Evento firmado del simulador; idempotente (BR-023) | id, tipo, payload_firmado, idempotency_key (única), estado, procesado_en | 1..1 `suscripcion` (origen) |
| `publicacion` | Inmueble en workflow con estados (BR-034..039) | id, tenant_id, inmueble_ref (S3/escena en SP-02), estado (borrador/en_revision/publicado/rechazado/despublicado), aprobado_por, observaciones, creado_en | N..1 `tenant`; 1..* `favorito` |
| `favorito` | Guardado de publicación con estado visible (BR-C7) | id, usuario_global_id, publicacion_id, estado (activo/no_disponible) | N..1 `usuario_global`; N..1 `publicacion` |
| `auditoria` | Bitácora de acciones y notificaciones (RNF-010, BR-076) | id, actor_type, actor_id, accion, entidad, entidad_id, detalle, creado_en | polimórfica |

### Reglas de integridad críticas

- **Unicidad transaccional**: una sola `membresia_agente` activa por `usuario_global` (BR-006) → índice único parcial `WHERE estado = 'activa'`.
- **Aceptación de invitación**: `invitacion` pasa a `aceptada` una única vez; crea la membresía sin duplicar cuenta (BR-005).
- **Idempotencia de facturación**: `idempotency_key` única en `evento_facturacion` (BR-023).
- **Catálogo global**: solo `publicacion.estado = 'publicado'` es visible (BR-C3) — el estado se valida en servidor, nunca por `tenant_id` del cliente.
- **Cancelación**: `suscripcion` transiciona a `canceled_read_only` (30 días) y luego `purged` conservando transacciones anonimizadas (BR-029/030).

## 2.1.2.2. Diseño Lógico (pendiente)

- Normalización y claves foráneas explícitas por tabla (GAP-092).
- Partición lógica por tenant en consultas globales (baseline multi-tenant, RNF-006) — GAP-092.

## 2.1.2.3. Diseño Físico (pendiente)

- Migraciones iniciales (Alembic) para las 11 tablas del Sprint 1 (GAP-092).
- Índices: correo único en `usuario_global`, `idempotency_key` única, índice parcial de membresía activa, índice por `tenant_id` en `publicacion`.

## Diagramas asociados

| Diagrama (nombre) | Tipo a insertar | Sección del modelo |
| --- | --- | --- |
| Clases de persistencia — Sprint 1 | **Class** (ERD conceptual) | CAPITULO 2 — 2.1.2.1 Diseño Conceptual |
| Modelo lógico — Sprint 1 | ERD lógico (relacional) | 2.1.2.2 |
| Esquema físico — Sprint 1 | Tablas físicas | 2.1.2.3 |

> Solo se registra el **tipo** (y nombre) del diagrama; no se embeben imágenes (regla del proyecto, ver [`tipos-diagramas-modelo.md`](../../sprint-0/tipos-diagramas-modelo.md)). Creación pendiente: GAP-088.

## Gaps del diseño de datos

- **GAP-061**: cuotas y precios de los planes (SPK-01/04).
- **GAP-092**: normalización completa, migraciones y diseño físico (se completa al implementar PB-048/49 y las HUs de auth).
- **GAP-088**: creación/verificación del diagrama Class en Enterprise Architect.
