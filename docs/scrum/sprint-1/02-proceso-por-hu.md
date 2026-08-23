# Sprint 1 — Proceso/patrón por HU: Diseño (datos)

| Campo | Valor |
| --- | --- |
| Módulo | S1-02 — CAPITULO 2, sección 2 (inicio: Diseño de Datos del Sprint 1) |
| Estado | in progress (diseño conceptual + lógico completos; físico pendiente) |
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

## 2.1.2.2. Diseño Lógico (Sprint 1)

Convenciones: IDs `UUID`; sellos de tiempo `TIMESTAMPTZ` con `DEFAULT now()`; aislamiento multi-tenant por `tenant_id` en todas las tablas del tenant; las consultas globales nunca reciben `tenant_id` del cliente (BR-C3/RF-021).

| Tabla | PK | FK / UNIQUE / CHECK | Índices y reglas |
| --- | --- | --- | --- |
| `usuario_global` | `id` UUID | `correo` VARCHAR(255) **UNIQUE**; `hash_password` VARCHAR(255); `estado` VARCHAR(20) default `activo`; `correo_verificado` BOOLEAN default FALSE (se exige en SP-03, RF-033) | UNIQUE(`correo`); sin borrado físico (desactivación, RNF-009) |
| `tenant` | `id` UUID | `nombre` VARCHAR(120); `estado` VARCHAR(20) default `activo` | — |
| `membresia_agente` | `id` UUID | `tenant_id` FK→`tenant.id`; `usuario_global_id` FK→`usuario_global.id`; `rol` VARCHAR(20) CHECK (admin/agente); `estado` VARCHAR(20) CHECK (activa/inactiva/revocada) | **UNIQUE parcial** (`usuario_global_id`) WHERE `estado`='activa' (BR-006) |
| `invitacion` | `id` UUID | `tenant_id` FK→`tenant.id`; `token_unico` CHAR(64) **UNIQUE** (hash); `expira_en` TIMESTAMPTZ; `estado` CHECK (pendiente/aceptada/expirada) | UNIQUE(`token_unico`); transición única a `aceptada` (BR-005) |
| `permiso_agente` | `id` UUID | `membresia_agente_id` FK→`membresia_agente.id`; `codigo_permiso` FK→`permiso_catalogo.codigo`; `alcance` CHECK (tenant/inmueble); `alcance_id` UUID NULL (inmueble si aplica) | UNIQUE(`membresia_agente_id`, `codigo_permiso`, `alcance`, `alcance_id`) |
| `permiso_catalogo` | `codigo` VARCHAR(40) PK | `nombre` VARCHAR(60); `descripcion` VARCHAR(200); `alcance_permitido` CHECK (tenant/inmueble/ambos) | Catálogo de 12 códigos (BR-A11..A22); crea permisos predefinidos |
| `rol_permiso_base` | (`rol`, `codigo_permiso`) PK | `rol` CHECK (admin/agente); `codigo_permiso` FK→`permiso_catalogo.codigo` | Asignación por defecto según rol (BR-A10) |
| `plan` | `id` UUID | `nombre` VARCHAR(60); `precio_bob` NUMERIC(10,2); `cuota_almacenamiento_gb` INT; `cuota_inmuebles` INT; `cuota_reconstrucciones_mes` INT; `activo` BOOLEAN | Valores de cuotas → **GAP-061** |
| `suscripcion` | `id` UUID | `tenant_id` FK→`tenant.id`; `plan_id` FK→`plan.id`; `estado` VARCHAR(20) CHECK (trialing/active/past_due/suspended/canceled_read_only/purged); `trial_fin`, `periodo_fin`, `cancelado_en` TIMESTAMPTZ NULL | Índice (`tenant_id`, `estado`) para la suscripción vigente (BR-025..031) |
| `evento_facturacion` | `id` UUID | `suscripcion_id` FK→`suscripcion.id`; `tipo` VARCHAR(40); `payload_firmado` TEXT; `idempotency_key` VARCHAR(100) **UNIQUE**; `estado` CHECK (recibido/procesado/fallido) | UNIQUE(`idempotency_key`) (BR-023) |
| `publicacion` | `id` UUID | `tenant_id` FK→`tenant.id`; `titulo` VARCHAR(160); `operacion` CHECK (venta/alquiler); `estado` VARCHAR(20) CHECK (borrador/en_revision/publicado/rechazado/despublicado); `aprobado_por` UUID NULL FK→`usuario_global.id`; `observaciones` TEXT NULL; `inmueble_ref` VARCHAR(255) NULL (S3/escena, SP-02) | Índice (`estado`, `tenant_id`) — catálogo global solo `publicado` (BR-C3) |
| `favorito` | `id` UUID | `usuario_global_id` FK→`usuario_global.id`; `publicacion_id` FK→`publicacion.id`; `estado` CHECK (activo/no_disponible) | UNIQUE(`usuario_global_id`, `publicacion_id`) (BR-C7) |
| `auditoria` | `id` BIGSERIAL | `actor_type` VARCHAR(20); `actor_id` UUID NULL; `accion` VARCHAR(80); `entidad` VARCHAR(60); `entidad_id` UUID NULL; `detalle` JSONB NULL; `creado_en` TIMESTAMPTZ | Índice (`entidad`, `entidad_id`, `creado_en`); retención 90 días (RNF-010) |
| `sesion` | `id` UUID | `usuario_global_id` FK→`usuario_global.id`; `refresh_token_hash` CHAR(64) **UNIQUE**; `expira_en` TIMESTAMPTZ; `ultima_actividad` TIMESTAMPTZ NULL; `revocado` BOOLEAN default false | UNIQUE(`refresh_token_hash`); índice (`usuario_global_id`, `revocado`); limpieza por inactividad 30 min (RF-002/RNF-006) |

Notas de normalización (auditoría 3NF):

- Sin dependencias parciales ni transitivas: cada atributo no clave depende solo de la PK de su tabla; no hay redundancias derivadas.
- Catálogos normalizados como tablas (`permiso_catalogo`, `rol_permiso_base`); los enums cerrados (estados, roles, alcances, operaciones) se modelan como VARCHAR + CHECK por ser conjuntos finitos del dominio.
- `auditoria.detalle` usa JSONB únicamente para metadatos variables (decisión de persistencia obs-2395/2406).
- `publicacion` referencia el inmueble por `inmueble_ref` (clave S3) hasta que el modelo de escenas llegue en SP-02 (BR-059..062).
- `sesion` habilita revocación y limpieza por inactividad del refresh token (RF-002).

## 2.1.2.3. Diseño Físico (pendiente)

- Migraciones iniciales (Alembic) para las **14 tablas** del Sprint 1 (GAP-092).
- Índices: correo único en `usuario_global`, `idempotency_key` única, índice parcial de membresía activa, `refresh_token_hash` único en `sesion`, índice (`usuario_global_id`, `revocado`) en `sesion`, índice por `tenant_id` en `publicacion`.

## Diagramas asociados

| Diagrama (nombre) | Tipo a insertar | Sección del modelo |
| --- | --- | --- |
| Clases de persistencia — Sprint 1 | **Class** (ERD conceptual) | CAPITULO 2 — 2.1.2.1 Diseño Conceptual |
| Modelo lógico — Sprint 1 | ERD lógico (relacional) | 2.1.2.2 |
| Esquema físico — Sprint 1 | Tablas físicas | 2.1.2.3 |

> Solo se registra el **tipo** (y nombre) del diagrama; no se embeben imágenes (regla del proyecto, ver [`tipos-diagramas-modelo.md`](../../sprint-0/tipos-diagramas-modelo.md)). Creación pendiente: GAP-088.

## Gaps del diseño de datos

- **GAP-061**: cuotas y precios de los planes (SPK-01/04).
- **GAP-092**: migraciones Alembic y diseño físico (se completa al implementar PB-048/049 y las HUs de auth).
- **GAP-088**: creación/verificación de los diagramas de diseño en Enterprise Architect.

## 2.1.1. Diseño de la Arquitectura

El Sprint 1 utiliza un backend monolítico modular construido con FastAPI. PostgreSQL es la autoridad de los estados transaccionales y de los metadatos; S3 conserva los objetos binarios y SQS desacopla los trabajos asíncronos. El worker de reconstrucción 3D no forma parte del incremento SP-01 y se reserva para SP-02. La infraestructura de referencia se encuentra en [`09-infraestructura.md`](../sprint-0-requerimientos/09-infraestructura.md).

### 2.1.1.1. Diagrama de Despliegue

| Diagrama | Tipo | Referencia | Estado de creación |
| --- | --- | --- | --- |
| Diagrama de Despliegue — Sprint 1 | **Deployment** | CAPITULO 2, 2.1.1.1 | GAP-088 |

No se embebe ninguna imagen. La referencia queda limitada al tipo de diagrama indicado por el modelo.

### 2.1.1.2. Diagrama de Paquetes

| Diagrama | Tipo | Referencia | Estado de creación |
| --- | --- | --- | --- |
| Diagrama de Paquetes — Sprint 1 | **Package** | CAPITULO 2, 2.1.1.2 | GAP-088 |

No se embebe ninguna imagen. La referencia queda limitada al tipo de diagrama indicado por el modelo.

## 2.1.3. Diseño de la Lógica de Negocio

La lógica de negocio del SP-01 se expresa mediante máquinas de estado derivadas de las reglas de registro, autenticación, suscripción, membresías y publicación documentadas en el Sprint Planning y en el diseño de datos. Las transiciones se validan en el backend; un intento inválido no debe cambiar el estado persistido.

### Estados de registro, autenticación y sesión

| Flujo | Estado inicial | Transición o evento | Estado resultante | Regla observable |
| --- | --- | --- | --- | --- |
| Registro | Cuenta no existente | Correo válido y contraseña válida | Cuenta activa | En modo pruebas no se exige verificación de correo; el correo duplicado se rechaza. |
| Registro | Cuenta no existente | Correo o contraseña inválidos | Cuenta no creada | Se informa un error de validación y no se crea la cuenta. |
| Autenticación | Cuenta activa | Credenciales válidas | Sesión activa | Se emiten credenciales de sesión y se registra la actividad. |
| Autenticación | Cuenta activa | Credenciales inválidas | Cuenta activa, sin nueva sesión | Se informa un error genérico sin revelar la existencia de la cuenta. |
| Sesión | Sesión activa | Logout | Sesión revocada | El refresh token activo queda revocado. |
| Sesión | Sesión activa | 30 minutos sin actividad | Sesión expirada/revocada | Se requiere autenticación nuevamente (RF-002/RNF-006). |

### Estados de suscripción

| Estado o conjunto de estados | Evento | Resultado esperado |
| --- | --- | --- |
| Sin suscripción activa | Activación de la prueba | `trialing` durante 14 días. |
| `trialing` | Evento firmado de suscripción | `active`. |
| `active` | Incumplimiento de pago | `past_due` y, según la regla aplicable, `suspended`. |
| `active` o `trialing` | Cancelación | `canceled_read_only` durante 30 días. |
| `canceled_read_only` | Vencimiento del período de retención | `purged`, conservando las transacciones anonimizadas. |
| Cualquier estado | Reprocesamiento del mismo evento firmado | Sin duplicación; se aplica idempotencia mediante `idempotency_key`. |

### Estados de invitación y membresía

| Flujo | Estado inicial | Evento | Estado resultante | Regla observable |
| --- | --- | --- | --- | --- |
| Invitación | `pendiente` | Aceptación del enlace de un solo uso | `aceptada` y membresía creada | No se duplica la cuenta global ni se reutiliza el enlace. |
| Invitación | `pendiente` | Vencimiento | `expirada` | El enlace deja de ser aceptable. |
| Membresía | `activa` | Desactivación | `inactiva` | Se niega el acceso sin borrar la autoría histórica. |
| Membresía | `activa` | Revocación | `revocada` | Se niega el acceso sin borrar la autoría histórica. |
| Membresía | Otra membresía activa | Activación de una nueva membresía del mismo agente | La anterior queda inactiva | Se conserva una sola membresía activa por agente (BR-006). |

### Estados de publicación

| Estado inicial | Evento | Estado resultante | Regla observable |
| --- | --- | --- | --- |
| `borrador` | Envío a revisión con permisos requeridos | `en_revision` | Se registra actor y fecha; el agente no puede autoaprobar. |
| `en_revision` | Aprobación administrativa | `publicado` | La revisión incluye la verificación del difuminado. |
| `en_revision` | Rechazo administrativo | `rechazado` | Las observaciones del rechazo son obligatorias. |
| `publicado` | Despublicación | `despublicado` | El inmueble deja de aparecer en el catálogo global y la acción queda auditada. |
| Cualquier estado no permitido | Evento inválido | Estado sin cambios | El backend rechaza la transición. |

### 2.1.3.1. Diagrama de Comunicación

| Diagrama | Tipo | Referencia | Estado de creación |
| --- | --- | --- | --- |
| Comunicación — Alta de inmobiliaria | **Communication** | CAPITULO 2, 2.1.3.1 | GAP-088 |

No se embebe ninguna imagen.

### 2.1.3.2. Diagrama de Secuencia

| Diagrama | Tipo | Referencia | Estado de creación |
| --- | --- | --- | --- |
| Secuencia — Autenticación y sesión | **Sequence** | CAPITULO 2, 2.1.3.2 | GAP-088 |

No se embebe ninguna imagen.

## 2.1.4. Implementación

La implementación prevista mantiene módulos separados dentro del monolito FastAPI, con PostgreSQL para persistencia transaccional y los adaptadores S3/SQS para objetos y trabajos asíncronos. Las migraciones Alembic del esquema del Sprint 1 están pendientes (GAP-092). El worker 3D se incorpora en SP-02 y no se presenta como implementado en SP-01.

### 2.1.4.1. Diagrama de Componentes

| Diagrama | Tipo | Referencia | Estado de creación |
| --- | --- | --- | --- |
| Componentes — Backend Sprint 1 | **Component** | CAPITULO 2, 2.1.4.1 | GAP-088 |

No se embebe ninguna imagen.

## 2.1.5. Pruebas

### 2.1.5.1. Plan de pruebas

El plan relaciona cada caso con el PB y la HU correspondiente. Los casos permanecen pendientes porque no se ejecutaron pruebas ni se adjuntó evidencia (GAP-087). La asignación del responsable sigue pendiente (GAP-073).

| ID Prueba | PB | HU | Funcionalidad evaluada | Plataforma | Responsable | Estado |
| --- | --- | --- | --- | --- | --- | --- |
| CP-001 | PB-001 | HU-001 | Registro de cliente | App cliente / Backend | GAP-073 | Pendiente (no ejecutado) |
| CP-002 | PB-002 | HU-002 | Autenticación y sesión con inactividad de 30 minutos | Backend / Apps / Web | GAP-073 | Pendiente (no ejecutado) |
| CP-003 | PB-004 | HU-004 | Alta de inmobiliaria con checkout simulado | Web / Backend | GAP-073 | Pendiente (no ejecutado) |
| CP-004 | PB-005 | HU-005 | Activación de trial de 14 días y suscripción | Web / Backend | GAP-073 | Pendiente (no ejecutado) |
| CP-005 | PB-006 | HU-006 | Ciclo de suscripción, cuotas, cambios y cancelación | Web / Backend | GAP-073 | Pendiente (no ejecutado) |
| CP-006 | PB-007 | HU-007 | Invitación de agentes con enlace seguro | Web / Backend | GAP-073 | Pendiente (no ejecutado) |
| CP-007 | PB-007 | HU-008 | Activación y desactivación de membresías | Web / Backend | GAP-073 | Pendiente (no ejecutado) |
| CP-008 | PB-008 | HU-009 | Permisos RBAC por alcance | Web / Backend | GAP-073 | Pendiente (no ejecutado) |
| CP-009 | PB-028 | HU-022 | Creación y edición del borrador de publicación | Web / Backend | GAP-073 | Pendiente (no ejecutado) |
| CP-010 | PB-029 | HU-023 | Envío de publicación a revisión | Web / Backend | GAP-073 | Pendiente (no ejecutado) |
| CP-011 | PB-029 | HU-024 | Aprobación o rechazo y verificación del difuminado | Web / Backend | GAP-073 | Pendiente (no ejecutado) |
| CP-012 | PB-030 | HU-025/HU-026 | Publicación, despublicación y catálogo global | Backend / App / Web | GAP-073 | Pendiente (no ejecutado) |
| CP-013 | PB-032 | HU-028 | Favoritos y estado de publicación | Backend / App cliente | GAP-073 | Pendiente (no ejecutado) |

### 2.1.5.2. Casos de prueba funcionales de caja negra

Cada caso sigue el patrón del modelo Grupo#12: metadatos, pasos observables, responsable, resultado y adjunto. Los estados de los pasos no constituyen resultados de ejecución; permanecen `not executed` hasta contar con evidencia.

#### Prueba de Historia de Usuario HU-001: Registro con correo

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-001 |
| Product Backlog relacionado | PB-001 — Registro cliente |
| Descripción | Verificar que un cliente pueda registrarse con un correo válido y una contraseña válida, y que las entradas inválidas o duplicadas sean rechazadas. |
| Precondiciones | Cuenta de prueba inexistente; servicio de registro disponible al momento de ejecutar; datos válidos, duplicados e inválidos preparados. Estado actual: not executed. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Ingresar un correo válido no registrado y una contraseña de al menos 8 caracteres; enviar el formulario. | Se crea una cuenta activa y se permite continuar sin verificación de correo en modo pruebas. | not executed |
| 2 | Repetir el registro con un correo ya registrado. | La operación se rechaza con un mensaje claro y no se crea una segunda cuenta. | not executed |
| 3 | Ingresar un correo con formato inválido y una contraseña válida. | La validación rechaza la solicitud y no se crea la cuenta. | not executed |
| 4 | Ingresar un correo válido y una contraseña de menos de 8 caracteres. | La validación rechaza la solicitud y no se crea la cuenta. | not executed |

**Responsable:** GAP-073
**Resultado de la prueba:** not executed
**Adjunto:** —

#### Prueba de Historia de Usuario HU-002: Autenticación y sesión

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-002 |
| Product Backlog relacionado | PB-002 — Autenticación y sesión |
| Descripción | Verificar el inicio de sesión con credenciales válidas e inválidas, la continuidad de la sesión durante la actividad y su invalidación después de 30 minutos de inactividad. |
| Precondiciones | Cuenta activa y credenciales válidas disponibles; credenciales inválidas preparadas; servicio de autenticación disponible al momento de ejecutar; para el límite de inactividad se requiere dejar transcurrir 30 minutos o utilizar un mecanismo de prueba validado. Estado actual: not executed. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Ingresar credenciales válidas y solicitar el inicio de sesión. | Se inicia la sesión y se emiten las credenciales de acceso y renovación correspondientes. | not executed |
| 2 | Ingresar un correo o contraseña inválidos. | Se muestra un error genérico, sin revelar si la cuenta existe, y no se crea una sesión. | not executed |
| 3 | Realizar una acción autenticada antes de cumplir 30 minutos de inactividad. | La sesión permanece activa y la actividad queda considerada para el control de inactividad. | not executed |
| 4 | Dejar la sesión sin actividad durante 30 minutos y realizar una nueva acción autenticada. | La sesión se invalida y se solicita autenticación nuevamente. | not executed |
| 5 | Ejecutar logout y volver a usar el refresh token revocado. | El logout revoca el refresh token y su reutilización es rechazada. | not executed |

**Responsable:** GAP-073
**Resultado de la prueba:** not executed
**Adjunto:** —

### 2.1.5.3. Reporte de prueba

El siguiente reporte es una plantilla de cierre. Se completará únicamente cuando se ejecuten los casos CP-001 a CP-013 y exista evidencia verificable.

| RESULTADO GENERAL | VALOR |
| --- | --- |
| Total HU probadas | not executed |
| Total casos ejecutados | not executed |
| Satisfactorios | not executed |
| Fallidos | not executed |
| Porcentaje de cumplimiento | — |
| Estado general del Sprint 1 | not executed |

> La plantilla se llena al ejecutar las pruebas y conservar sus evidencias (GAP-087). No se declara cumplimiento ni aprobación sin resultados observados.
