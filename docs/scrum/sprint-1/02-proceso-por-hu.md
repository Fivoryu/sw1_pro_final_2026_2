# 2. Proceso/Patrón de desarrollo por Historia de Usuario

## 2.1. Diseño

El proceso del Sprint 1 se documenta con los artefactos agrupados del incremento y con la trazabilidad de las 14 historias de usuario reales: HU-001, HU-002, HU-004..HU-009, HU-022..HU-026 y HU-028. HU-003 pertenece al Sprint 3 y no forma parte de este módulo. Las pruebas CP-003..CP-013 no se declaran ejecutadas (GAP-087); CP-001 y CP-002 cuentan con evidencia de ejecución de la superficie backend. La asignación de responsables por PB/HU queda documentada en este módulo: HU-001 y HU-002 permanecen con Calero Suyo Trevor Félix por su responsabilidad de implementación confirmada; las demás HUs se distribuyen por bloques funcionales entre Buceta Pesoa Luis Fernando, Ortiz Montero Luis Enrique, Rebollo Condori Renato y Vedia Barrios Sebastian. La asignación confirmada por el usuario y el equipo queda documentada, mientras que cualquier brecha aún abierta de responsabilidad de pruebas/documentación se mantiene explícitamente como GAP-073.

### 2.1.1. Diseño de la Arquitectura

El Sprint 1 utiliza un backend monolítico modular construido con FastAPI. PostgreSQL es la autoridad de los estados transaccionales y de los metadatos; S3 conserva los objetos binarios y SQS desacopla los trabajos asíncronos. El worker de reconstrucción 3D no forma parte del incremento SP-01 y se reserva para SP-02. La infraestructura de referencia se encuentra en [`09-infraestructura.md`](../sprint-0-requerimientos/09-infraestructura.md).

#### 2.1.1.1. Diagrama de Despliegue

- **Tipo:** Deployment
- **Referencia:** CAPITULO 2, sección 2.1.1.1 — GAP-088.

No se embebe ninguna imagen.

#### 2.1.1.2. Diagrama de Paquetes

- **Tipo:** Package
- **Referencia:** CAPITULO 2, sección 2.1.1.2 — GAP-088.

No se embebe ninguna imagen.

### 2.1.2. Diseño de Datos

#### 2.1.2.1. Diseño Conceptual

Las siguientes entidades representan el dominio de RoomForge para los 13 PB del Sprint 1 sobre PostgreSQL. Los binarios GLB, nubes y capturas no existen aún en SP-01; su modelo corresponde al pipeline de SP-02.

| Entidad | Descripción | Atributos clave | Relaciones |
| --- | --- | --- | --- |
| `usuario_global` | Cliente o persona única; cuenta global sin membresía. | id, correo, hash_password, estado, creado_en | 1..*`membresia_agente`; 1..* `favorito` |
| `tenant` | Inmobiliaria aprovisionada tras checkout simulado. | id, nombre, estado, creado_en | 1..*`membresia_agente`; 1..1 `suscripcion`; 1..* `publicacion`; 1..* `invitacion` |
| `membresia_agente` | Vínculo agente-tenant con una membresía activa por agente. | id, tenant_id, usuario_global_id, rol, estado, creado_en | N..1 `usuario_global`; N..1 `tenant`; 1..* `permiso_agente` |
| `invitacion` | Enlace de un solo uso para agentes. | id, tenant_id, correo, token_unico, expira_en, estado | N..1 `tenant` |
| `permiso_agente` | Permiso predefinido con alcance de tenant o inmueble. | id, membresia_agente_id, codigo_permiso, alcance, alcance_id | N..1 `membresia_agente`; N..1 `permiso_catalogo` |
| `permiso_catalogo` | Catálogo de permisos predefinidos. | codigo, nombre, descripcion, alcance_permitido | 1..*`permiso_agente`; 1..* `rol_permiso_base` |
| `rol_permiso_base` | Permisos por defecto para cada rol. | rol, codigo_permiso | N..1 `permiso_catalogo` |
| `plan` | Plan del simulador de suscripción. | id, nombre, precio_bob, cuotas | 1..* `suscripcion` |
| `suscripcion` | Ciclo de suscripción y sus estados. | id, tenant_id, plan_id, estado, trial_fin, periodo_fin, cancelado_en | N..1 `tenant`; N..1 `plan`; 1..* `evento_facturacion` |
| `evento_facturacion` | Evento firmado del simulador, con idempotencia. | id, suscripcion_id, tipo, payload_firmado, idempotency_key, estado | N..1 `suscripcion` |
| `publicacion` | Inmueble con flujo de borrador, revisión y publicación. | id, tenant_id, titulo, operacion, estado, aprobado_por, observaciones | N..1 `tenant`; 1..* `favorito` |
| `favorito` | Publicación guardada por un cliente. | id, usuario_global_id, publicacion_id, estado | N..1 `usuario_global`; N..1 `publicacion` |
| `auditoria` | Bitácora de acciones y notificaciones. | id, actor_type, actor_id, accion, entidad, entidad_id, detalle, creado_en | relación polimórfica |
| `sesion` | Sesión autenticada con refresh token revocable. | id, usuario_global_id, refresh_token_hash, expira_en, ultima_actividad, revocado | N..1 `usuario_global` |

**Reglas de integridad críticas:**

- Una sola `membresia_agente` activa por `usuario_global` (BR-006), mediante índice único parcial.
- `invitacion` pasa a `aceptada` una única vez y crea la membresía sin duplicar la cuenta (BR-005).
- `idempotency_key` es única en `evento_facturacion` (BR-023).
- Solo `publicacion.estado = 'publicado'` es visible en el catálogo global (BR-C3).
- `suscripcion` transiciona a `canceled_read_only` durante 30 días y luego a `purged`, conservando transacciones anonimizadas (BR-029/030).

#### 2.1.2.2. Diseño Lógico

Convenciones: IDs `UUID`; sellos de tiempo `TIMESTAMPTZ` con `DEFAULT now()`; aislamiento multi-tenant mediante `tenant_id` en las tablas del tenant; las consultas globales nunca reciben `tenant_id` del cliente (BR-C3/RF-021).

##### `usuario_global`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | UUID, PK |
| `correo` | VARCHAR(255), UNIQUE |
| `hash_password` | VARCHAR(255), obligatorio |
| `estado` | VARCHAR(20), default `activo` |
| `correo_verificado` | BOOLEAN, default FALSE; se exige en SP-03 |
| `creado_en` | TIMESTAMPTZ |

##### `tenant`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | UUID, PK |
| `nombre` | VARCHAR(120) |
| `estado` | VARCHAR(20), default `activo` |
| `creado_en` | TIMESTAMPTZ |

##### `membresia_agente`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | UUID, PK |
| `tenant_id` | UUID, FK a `tenant.id` |
| `usuario_global_id` | UUID, FK a `usuario_global.id` |
| `rol` | VARCHAR(20), CHECK `admin/agente` |
| `estado` | VARCHAR(20), CHECK `activa/inactiva/revocada` |
| `creado_en` | TIMESTAMPTZ |

Índice: UNIQUE parcial sobre `usuario_global_id` cuando `estado = 'activa'` (BR-006).

##### `invitacion`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | UUID, PK |
| `tenant_id` | UUID, FK a `tenant.id` |
| `correo` | VARCHAR(255) |
| `token_unico` | CHAR(64), UNIQUE; se persiste el hash |
| `expira_en` | TIMESTAMPTZ |
| `estado` | CHECK `pendiente/aceptada/expirada` |

##### `permiso_agente`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | UUID, PK |
| `membresia_agente_id` | UUID, FK a `membresia_agente.id` |
| `codigo_permiso` | FK a `permiso_catalogo.codigo` |
| `alcance` | CHECK `tenant/inmueble` |
| `alcance_id` | UUID NULL cuando el alcance es inmueble |

UNIQUE sobre `membresia_agente_id`, `codigo_permiso`, `alcance` y `alcance_id`.

##### `permiso_catalogo`

| Campo | Tipo / restricción |
| --- | --- |
| `codigo` | VARCHAR(40), PK |
| `nombre` | VARCHAR(60) |
| `descripcion` | VARCHAR(200) |
| `alcance_permitido` | CHECK `tenant/inmueble/ambos` |

##### `rol_permiso_base`

| Campo | Tipo / restricción |
| --- | --- |
| `rol` | Parte de PK; CHECK `admin/agente` |
| `codigo_permiso` | Parte de PK; FK a `permiso_catalogo.codigo` |

##### `plan`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | UUID, PK |
| `nombre` | VARCHAR(60) |
| `precio_bob` | NUMERIC(10,2) |
| `cuota_almacenamiento_gb` | INT |
| `cuota_inmuebles` | INT |
| `cuota_reconstrucciones_mes` | INT |
| `activo` | BOOLEAN |

Los valores concretos de cuotas y precios permanecen como GAP-061.

##### `suscripcion`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | UUID, PK |
| `tenant_id` | UUID, FK a `tenant.id` |
| `plan_id` | UUID, FK a `plan.id` |
| `estado` | CHECK `trialing/active/past_due/suspended/canceled_read_only/purged` |
| `trial_fin` | TIMESTAMPTZ NULL |
| `periodo_fin` | TIMESTAMPTZ NULL |
| `cancelado_en` | TIMESTAMPTZ NULL |

Índice sobre `tenant_id` y `estado` para la suscripción vigente.

##### `evento_facturacion`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | UUID, PK |
| `suscripcion_id` | UUID, FK a `suscripcion.id` |
| `tipo` | VARCHAR(40) |
| `payload_firmado` | TEXT |
| `idempotency_key` | VARCHAR(100), UNIQUE |
| `estado` | CHECK `recibido/procesado/fallido` |

##### `publicacion`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | UUID, PK |
| `tenant_id` | UUID, FK a `tenant.id` |
| `titulo` | VARCHAR(160) |
| `operacion` | CHECK `venta/alquiler` |
| `estado` | CHECK `borrador/en_revision/publicado/rechazado/despublicado` |
| `aprobado_por` | UUID NULL, FK a `usuario_global.id` |
| `observaciones` | TEXT NULL |
| `inmueble_ref` | VARCHAR(255) NULL; S3/escena de SP-02 |

Índice sobre `estado` y `tenant_id`; el catálogo global filtra únicamente `publicado`.

##### `favorito`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | UUID, PK |
| `usuario_global_id` | UUID, FK a `usuario_global.id` |
| `publicacion_id` | UUID, FK a `publicacion.id` |
| `estado` | CHECK `activo/no_disponible` |

UNIQUE sobre `usuario_global_id` y `publicacion_id` (BR-C7).

##### `auditoria`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | BIGSERIAL, PK |
| `actor_type` | VARCHAR(20) |
| `actor_id` | UUID NULL |
| `accion` | VARCHAR(80) |
| `entidad` | VARCHAR(60) |
| `entidad_id` | UUID NULL |
| `detalle` | JSONB NULL |
| `creado_en` | TIMESTAMPTZ |

Índice sobre `entidad`, `entidad_id` y `creado_en`; retención de 90 días (RNF-010).

##### `sesion`

| Campo | Tipo / restricción |
| --- | --- |
| `id` | UUID, PK |
| `usuario_global_id` | UUID, FK a `usuario_global.id` |
| `refresh_token_hash` | CHAR(64), UNIQUE |
| `expira_en` | TIMESTAMPTZ |
| `ultima_actividad` | TIMESTAMPTZ NULL |
| `revocado` | BOOLEAN, default FALSE |

Índices sobre `usuario_global_id` y `revocado`; limpieza por inactividad de 30 minutos (RF-002/RNF-006).

**Notas de normalización:**

- Cada atributo no clave depende solo de la PK de su tabla; no se mantienen dependencias parciales ni transitivas.
- Los catálogos se normalizan mediante `permiso_catalogo` y `rol_permiso_base`; los conjuntos cerrados se modelan con `VARCHAR + CHECK`.
- `auditoria.detalle` usa JSONB solo para metadatos variables.
- `publicacion` referencia el inmueble por `inmueble_ref` hasta que el modelo de escenas llegue en SP-02.

#### 2.1.2.3. Diseño Físico

El diseño físico tiene cobertura parcial mediante evidencia de las migraciones Alembic `0001` y `0002` ejecutadas contra PostgreSQL real; quedan 12 tablas/migraciones del Sprint 1 pendientes (GAP-092). No se afirma un diagrama físico adicional sin evidencia.

- Migraciones iniciales para las 14 tablas del Sprint 1: `0001` y `0002` fueron ejecutadas contra PostgreSQL real; las 12 restantes permanecen pendientes (GAP-092).
- Índices previstos: correo único en `usuario_global`, `idempotency_key` única, índice parcial de membresía activa, `refresh_token_hash` único en `sesion`, índice sobre (`usuario_global_id`, `revocado`) en `sesion` e índice por `tenant_id` en `publicacion`.

### 2.1.3. Diseño de la Lógica de Negocio

La lógica de negocio del SP-01 se expresa mediante máquinas de estado derivadas de las reglas de registro, autenticación, suscripción, membresías y publicación documentadas en el Sprint Planning y en el diseño de datos. Las transiciones se validan en el backend; un intento inválido no debe cambiar el estado persistido.

#### Estados de registro, autenticación y sesión

| Flujo | Estado inicial | Transición o evento | Estado resultante | Regla observable |
| --- | --- | --- | --- | --- |
| Registro | Cuenta no existente | Correo y contraseña válidos | Cuenta activa | En modo pruebas no se exige verificación; el correo duplicado se rechaza. |
| Registro | Cuenta no existente | Correo o contraseña inválidos | Cuenta no creada | Se informa un error y no se crea la cuenta. |
| Autenticación | Cuenta activa | Credenciales válidas | Sesión activa | Se emiten credenciales y se registra la actividad. |
| Autenticación | Cuenta activa | Credenciales inválidas | Cuenta activa, sin nueva sesión | Se informa un error genérico. |
| Sesión | Sesión activa | `logout` | Sesión revocada | El refresh token activo queda revocado. |
| Sesión | Sesión activa | 30 minutos sin actividad | Sesión expirada/revocada | Se solicita autenticación nuevamente. |

#### Estados de suscripción

| Estado o conjunto de estados | Evento | Resultado esperado |
| --- | --- | --- |
| Sin suscripción activa | Activación de la prueba | `trialing` durante 14 días. |
| `trialing` | Evento firmado de suscripción | `active`. |
| `active` | Incumplimiento de pago | `past_due` y, según la regla aplicable, `suspended`. |
| `active` o `trialing` | Cancelación | `canceled_read_only` durante 30 días. |
| `canceled_read_only` | Vencimiento del período de retención | `purged`, conservando transacciones anonimizadas. |
| Cualquier estado | Reprocesamiento del mismo evento firmado | Sin duplicación por `idempotency_key`. |

#### Estados de invitación y membresía

| Flujo | Estado inicial | Evento | Estado resultante | Regla observable |
| --- | --- | --- | --- | --- |
| Invitación | `pendiente` | Aceptación del enlace de un solo uso | `aceptada` y membresía creada | No se duplica la cuenta global ni se reutiliza el enlace. |
| Invitación | `pendiente` | Vencimiento | `expirada` | El enlace deja de ser aceptable. |
| Membresía | `activa` | Desactivación | `inactiva` | Se niega el acceso sin borrar la autoría histórica. |
| Membresía | `activa` | Revocación | `revocada` | Se niega el acceso sin borrar la autoría histórica. |
| Membresía | Otra membresía activa | Activación de una nueva | La anterior queda inactiva | Se conserva una sola membresía activa por agente. |

#### Estados de publicación

| Estado inicial | Evento | Estado resultante | Regla observable |
| --- | --- | --- | --- |
| `borrador` | Envío a revisión con permisos | `en_revision` | Se registra actor y fecha; el agente no puede autoaprobar. |
| `en_revision` | Aprobación administrativa | `publicado` | La revisión incluye la verificación del difuminado. |
| `en_revision` | Rechazo administrativo | `rechazado` | Las observaciones del rechazo son obligatorias. |
| `publicado` | Despublicación | `despublicado` | Desaparece del catálogo y la acción queda auditada. |
| Cualquier estado no permitido | Evento inválido | Estado sin cambios | El backend rechaza la transición. |

#### 2.1.3.1. Diagrama de Comunicación

- **Tipo:** Communication
- **Referencia:** CAPITULO 2, sección 2.1.3.1 — GAP-088.
- **Rótulos funcionales:** PB-001 Registro cliente; PB-002 Autenticación y sesión; PB-004 Alta de inmobiliaria; PB-007 Invitación y membresías; PB-028 Editor de publicación; PB-030 Publicación y catálogo.

No se embebe ninguna imagen.

#### 2.1.3.2. Diagrama de Secuencia

- **Tipo:** Sequence
- **Referencia:** CAPITULO 2, sección 2.1.3.2 — GAP-088.
- **Rótulos funcionales:** PB-001 Registro cliente; PB-002 Autenticación y sesión; PB-005 Trial y suscripción; PB-007 Invitación y membresías; PB-029 Revisión y aprobación; PB-030 Publicación y catálogo.

No se embebe ninguna imagen.

## 2.1.4. Implementación

La implementación prevista mantiene módulos separados dentro del monolito FastAPI, con PostgreSQL para persistencia transaccional y los adaptadores S3/SQS para objetos y trabajos asíncronos. Las migraciones Alembic del esquema del Sprint 1 tienen cobertura parcial: `0001` y `0002` fueron ejecutadas contra PostgreSQL real y quedan 12 tablas/migraciones pendientes (GAP-092). El worker 3D se incorpora en SP-02 y no se presenta como implementado en SP-01.

Como slice backend-first de PB-001/HU-001, se implementó el módulo `identity` con `POST /api/v1/auth/registro`, normalización del correo a minúsculas y hash Argon2id. Las migraciones `0001` (`usuario_global`) y `0002` (`sesion`) fueron ejecutadas contra PostgreSQL real; el GAP-092 queda parcialmente cubierto y restan 12 tablas/migraciones del Sprint 1 pendientes. La trazabilidad del cambio se conserva en la [spec](../../../openspec/changes/registro-cliente/spec.md) y las [tareas](../../../openspec/changes/registro-cliente/tasks.md); CP-003..CP-013 no se declaran ejecutados y se mantienen GAP-087 y GAP-073.

Como slice backend-first de PB-002/HU-002, se implementó la autenticación y sesión del cliente sobre el mismo módulo `identity`: `POST /api/v1/auth/login` (emite access JWT de 15 minutos y refresh opaco hasheado), `POST /api/v1/auth/refresh` (rotación atómica con revocación de la fila anterior), `POST /api/v1/auth/logout` (idempotente) y `GET /api/v1/auth/me` (sesión validada server-side contra la tabla `sesion`, con inactividad deslizante de 30 minutos según RNF-006). La migración `0002_crear_sesion` agrega la tabla `sesion` (`refresh_token_hash` CHAR(64) único, `expira_en`, `ultima_actividad`, `revocado`) y se añadió la dependencia PyJWT para el access token. La trazabilidad del cambio se conserva en la [spec](../../../openspec/changes/autenticacion/spec.md) y las [tareas](../../../openspec/changes/autenticacion/tasks.md); CP-002 cuenta con evidencia ejecutada y CP-003..CP-013 permanecen `not executed`, manteniéndose GAP-087 y GAP-073. La verificación complementaria del locking concurrente de sesiones para REQ-05 se documenta en [esta evidencia](evidencia/req05-refresh-concurrency-postgres.txt), sin modificar los contadores ni implicar aprobación global.

### 2.1.4.1. Diagrama de Componentes

- **Tipo:** Component
- **Referencia:** CAPITULO 2, sección 2.1.4.1 — GAP-088.

No se embebe ninguna imagen.

## 2.1.5. Pruebas

### 2.1.5.1. Plan de pruebas

El plan relaciona cada caso con el Product Backlog, la Historia de Usuario, la funcionalidad, la plataforma, el responsable y el estado. CP-003..CP-013 permanecen `not executed` y sin evidencia adjunta (GAP-087); CP-001 y CP-002 cuentan con evidencia real de la superficie backend. Los responsables de los casos corresponden a la asignación por PB/HU documentada en §1.3 (GAP-073 cerrado para la asignación de desarrollo).

| ID Prueba | PB | HU | Funcionalidad evaluada | Plataforma | Responsable | Estado |
| --- | --- | --- | --- | --- | --- | --- |
| CP-001 | PB-001 | HU-001 | Registro de cliente | App cliente / Backend (cobertura backend) | Calero Suyo Trevor Félix | executed |
| CP-002 | PB-002 | HU-002 | Autenticación y sesión con inactividad de 30 minutos | Backend / Apps / Web | Calero Suyo Trevor Félix | executed |
| CP-003 | PB-004 | HU-004 | Alta de inmobiliaria con checkout simulado | Web / Backend | Buceta Pesoa Luis Fernando | not executed |
| CP-004 | PB-005 | HU-005 | Activación de trial de 14 días y suscripción | Web / Backend | Buceta Pesoa Luis Fernando | not executed |
| CP-005 | PB-006 | HU-006 | Ciclo de suscripción, cuotas, cambios y cancelación | Web / Backend | Buceta Pesoa Luis Fernando | not executed |
| CP-006 | PB-007 | HU-007 | Invitación de agentes con enlace seguro | Web / Backend | Ortiz Montero Luis Enrique | not executed |
| CP-007 | PB-007 | HU-008 | Activación y desactivación de membresías | Web / Backend | Ortiz Montero Luis Enrique | not executed |
| CP-008 | PB-008 | HU-009 | Permisos RBAC por alcance | Web / Backend | Ortiz Montero Luis Enrique | not executed |
| CP-009 | PB-028 | HU-022 | Creación y edición del borrador de publicación | Web / Backend | Rebollo Condori Renato | not executed |
| CP-010 | PB-029 | HU-023 | Envío de publicación a revisión | Web / Backend | Rebollo Condori Renato | not executed |
| CP-011 | PB-029 | HU-024 | Aprobación o rechazo y verificación del difuminado | Web / Backend | Rebollo Condori Renato | not executed |
| CP-012 | PB-030 | HU-025/HU-026 | Publicación, despublicación y catálogo global | Backend / App / Web | Vedia Barrios Sebastian | not executed |
| CP-013 | PB-032 | HU-028 | Favoritos y estado de publicación | Backend / App cliente | Vedia Barrios Sebastian | not executed |

### 2.1.5.2. Casos de prueba funcionales de caja negra

Cada caso conserva el patrón del modelo: tabla de metadatos `CAMPO | DESCRIPCIÓN`, tabla de pasos `PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO`, responsable y resultado. CP-003..CP-013 permanecen `not executed` (GAP-087); CP-001 y CP-002 registran sus outcomes observados con evidencia adjunta.

HU-001: Registro con correo

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-001 |
| Product Backlog relacionado | PB-001 — Registro cliente |
| Descripción | Verificar registro válido y rechazo de correos duplicados o datos inválidos. |
| Precondiciones | Cuenta inexistente; servicio disponible; datos válidos, duplicados e inválidos preparados. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Ingresar correo válido no registrado y contraseña de al menos 8 caracteres. | HTTP 201; se crea una cuenta activa, con correo normalizado y sin exigir verificación en modo pruebas. | executed |
| 2 | Repetir el registro con el mismo correo y con la variante `Prueba@Ejemplo.INV`. | HTTP 409 con `Ya existe una cuenta con este correo`; no se duplica la cuenta. | executed |
| 3 | Enviar el correo inválido `no-es-correo`. | HTTP 422 sanitizado; no se crea la cuenta. | executed |
| 4 | Enviar una contraseña menor de 8 caracteres. | HTTP 422 sanitizado; no se crea la cuenta. | executed |

Nota: los pasos 3 y 4 desdoblan el paso 3 original del modelo, conservando la numeración de CP-001.

Responsable: Calero Suyo Trevor Félix
Resultado de la prueba: Satisfactorio
Adjunto: evidencia/cp001-registro-transcripto.txt

HU-002: Autenticación y sesión

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-002 |
| Product Backlog relacionado | PB-002 — Autenticación y sesión |
| Descripción | Verificar inicio de sesión, continuidad, logout e invalidación por inactividad. |
| Precondiciones | Cuenta activa, credenciales válidas e inválidas y servicio disponible. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Ingresar credenciales válidas. | Se inicia la sesión y se emiten credenciales de acceso y renovación. | executed |
| 2 | Ingresar credenciales inválidas. | Se muestra un error genérico y no se crea una sesión. | executed |
| 3 | Ejecutar una acción autenticada antes de 30 minutos de inactividad. | La sesión permanece activa. | executed |
| 4 | Dejar la sesión inactiva durante 30 minutos y ejecutar una acción. | La sesión se invalida y se solicita autenticación. | executed |
| 5 | Ejecutar `logout` y reutilizar el refresh token. | El token revocado es rechazado. | executed |

Responsable: Calero Suyo Trevor Félix
Resultado de la prueba: Satisfactorio
Adjunto: evidencia/cp002-autenticacion-transcripto.txt

Nota de alcance: la ejecución automatizada de requests verifica la superficie API y la base de datos local, pero no equivale a una prueba de caja negra desde la UI Flutter ni implica aprobación global del Sprint 1.

HU-004: Alta de inmobiliaria

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-003 |
| Product Backlog relacionado | PB-004 — Alta de inmobiliaria |
| Descripción | Verificar checkout simulado, evento firmado y aprovisionamiento idempotente del tenant. |
| Precondiciones | Plan disponible; simulador de checkout y receptor de eventos disponibles. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Seleccionar un plan y confirmar el checkout simulado. | Se muestran plan, monto en BOB y confirmación. | not executed |
| 2 | Enviar un evento firmado válido. | Se aprovisiona un tenant y su administrador inicial. | not executed |
| 3 | Reprocesar el mismo evento firmado. | No se duplica el tenant. | not executed |
| 4 | Intentar finalizar sin evento firmado válido. | No se aprovisiona el tenant. | not executed |

Responsable: Buceta Pesoa Luis Fernando
Resultado de la prueba: not executed
Adjunto: —

HU-005: Activar prueba y suscribirse

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-004 |
| Product Backlog relacionado | PB-005 — Trial y suscripción |
| Descripción | Verificar la activación del trial y el cambio a suscripción mensual. |
| Precondiciones | Tenant aprovisionado, plan disponible y evento firmado preparado. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Activar la prueba del tenant. | La suscripción queda en `trialing` por 14 días. | not executed |
| 2 | Enviar el evento firmado de suscripción. | La suscripción cambia a `active`. | not executed |
| 3 | Reprocesar el evento. | El estado no se duplica ni se crean registros repetidos. | not executed |

Responsable: Buceta Pesoa Luis Fernando
Resultado de la prueba: not executed
Adjunto: —

HU-006: Gestionar suscripción

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-005 |
| Product Backlog relacionado | PB-006 — Ciclo de suscripción |
| Descripción | Verificar cuotas, cambios de plan, cancelación y purga controlada. |
| Precondiciones | Administrador autenticado; suscripción activa y planes del simulador configurados. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Consultar la suscripción vigente. | Se muestran plan, cuotas y uso. | not executed |
| 2 | Solicitar upgrade y downgrade. | El upgrade es inmediato y el downgrade se aplica a la renovación. | not executed |
| 3 | Superar una cuota. | Se conservan los datos y se bloquean nuevas altas o reconstrucciones. | not executed |
| 4 | Cancelar la suscripción. | Pasa a `canceled_read_only` durante 30 días. | not executed |
| 5 | Cumplir el período de retención. | Pasa a `purged` y conserva transacciones anonimizadas. | not executed |

Responsable: Buceta Pesoa Luis Fernando
Resultado de la prueba: not executed
Adjunto: —

HU-007: Invitar agentes

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-006 |
| Product Backlog relacionado | PB-007 — Invitación y membresías |
| Descripción | Verificar la generación y aceptación de una invitación segura. |
| Precondiciones | Administrador autenticado; tenant activo y correo de agente disponible. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Crear una invitación para un agente. | Se genera un enlace de un solo uso con expiración. | not executed |
| 2 | Aceptar el enlace una vez. | Se crea la membresía sin duplicar la cuenta global. | not executed |
| 3 | Reutilizar el enlace o usarlo después de expirar. | La operación es rechazada. | not executed |

Responsable: Ortiz Montero Luis Enrique
Resultado de la prueba: not executed
Adjunto: —

HU-008: Activar o desactivar membresías

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-007 |
| Product Backlog relacionado | PB-007 — Invitación y membresías |
| Descripción | Verificar la regla de una membresía activa por agente. |
| Precondiciones | Administrador autenticado y agente con membresías registradas. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Activar una membresía de agente. | La membresía queda activa. | not executed |
| 2 | Activar otra membresía del mismo agente. | La anterior queda inactiva y solo una permanece activa. | not executed |
| 3 | Desactivar o revocar una membresía. | Se niega el acceso y se conserva la autoría histórica. | not executed |

Responsable: Ortiz Montero Luis Enrique
Resultado de la prueba: not executed
Adjunto: —

HU-009: Asignar permisos

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-008 |
| Product Backlog relacionado | PB-008 — Permisos RBAC |
| Descripción | Verificar permisos predefinidos y alcance de tenant o inmueble. |
| Precondiciones | Administrador autenticado, catálogo de permisos y agente activo. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Asignar un permiso con alcance tenant. | El agente accede a la función autorizada del tenant. | not executed |
| 2 | Asignar un permiso con alcance inmueble. | El agente accede solo al inmueble autorizado. | not executed |
| 3 | Solicitar una función sin asignación válida. | El acceso se deniega por defecto. | not executed |

Responsable: Ortiz Montero Luis Enrique
Resultado de la prueba: not executed
Adjunto: —

HU-022: Crear y editar borrador

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-009 |
| Product Backlog relacionado | PB-028 — Editor de publicación |
| Descripción | Verificar creación, edición y aislamiento del borrador de una publicación. |
| Precondiciones | Agente autenticado, tenant activo y permisos de edición. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Crear un borrador con título y operación. | Se crea una publicación en estado `borrador`. | not executed |
| 2 | Editar los datos del borrador y guardar. | Se guardan los cambios sin alterar otras publicaciones. | not executed |
| 3 | Consultar desde un tenant diferente. | El borrador no es visible. | not executed |

Responsable: Rebollo Condori Renato
Resultado de la prueba: not executed
Adjunto: —

HU-023: Enviar a revisión

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-010 |
| Product Backlog relacionado | PB-029 — Revisión y aprobación |
| Descripción | Verificar el envío de un borrador a revisión con permisos válidos. |
| Precondiciones | Publicación en `borrador`, agente autenticado y permisos requeridos. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Enviar el borrador a revisión. | Cambia a `en_revision` y registra actor y fecha. | not executed |
| 2 | Intentar autoaprobar como agente. | La aprobación es rechazada. | not executed |
| 3 | Enviar sin permiso requerido. | La transición es rechazada y el estado no cambia. | not executed |

Responsable: Rebollo Condori Renato
Resultado de la prueba: not executed
Adjunto: —

HU-024: Aprobar o rechazar publicaciones

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-011 |
| Product Backlog relacionado | PB-029 — Revisión y aprobación |
| Descripción | Verificar aprobación, rechazo y revisión del difuminado. |
| Precondiciones | Publicación en `en_revision` y administrador autenticado. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Revisar una publicación con difuminado válido. | La publicación puede aprobarse y pasa a `publicado`. | not executed |
| 2 | Rechazar una publicación. | Pasa a `rechazado` y exige observaciones. | not executed |
| 3 | Intentar aprobar sin verificar el difuminado. | La aprobación es rechazada. | not executed |

Responsable: Rebollo Condori Renato
Resultado de la prueba: not executed
Adjunto: —

HU-025/HU-026: Publicación y catálogo global

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-012 |
| Product Backlog relacionado | PB-030 — Publicación y catálogo |
| Descripción | Verificar visibilidad, despublicación y consulta del catálogo global. |
| Precondiciones | Publicaciones en estados `publicado` y `despublicado`; cliente autenticado. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Consultar el catálogo global. | Solo aparecen publicaciones `publicado`. | not executed |
| 2 | Despublicar un inmueble. | Desaparece inmediatamente del catálogo y se registra la auditoría. | not executed |
| 3 | Consultar enviando un `tenant_id` como autorización. | El servidor no concede acceso por ese valor. | not executed |

Responsable: Vedia Barrios Sebastian
Resultado de la prueba: not executed
Adjunto: —

HU-028: Guardar favoritos

| CAMPO | DESCRIPCIÓN |
| --- | --- |
| Caso de prueba | CP-013 |
| Product Backlog relacionado | PB-032 — Favoritos |
| Descripción | Verificar guardado, eliminación y estado de favoritos. |
| Precondiciones | Cliente autenticado y publicación visible en el catálogo. |

| PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO |
| --- | --- | --- | --- |
| 1 | Guardar una publicación como favorita. | Se crea un favorito único para el cliente y la publicación. | not executed |
| 2 | Quitar el favorito. | El favorito deja de estar activo. | not executed |
| 3 | Despublicar la publicación favorita. | El favorito queda `no_disponible` sin exponer contenido privado. | not executed |

Responsable: Vedia Barrios Sebastian
Resultado de la prueba: not executed
Adjunto: —

### 2.1.5.3. Reporte de prueba

El reporte refleja el avance parcial observado de CP-001 y CP-002 y no constituye el cierre ni la aprobación global del Sprint 1.

| RESULTADO GENERAL | VALOR |
| --- | --- |
| Total de historias de usuario probadas | 2 |
| Total de casos de prueba ejecutados | 2 |
| Casos satisfactorios | 2 |
| Casos fallidos | 0 |
| Porcentaje de cumplimiento | ≈15,4 % |
| Estado general del Sprint 1 | en ejecución |

CP-003..CP-013 siguen pendientes (`not executed`); el porcentaje y el estado son parciales y no declaran aprobación global del sprint.

**Gaps del modelo aplicables y no trasladados:** GAP-CH2-001 se respeta al no agregar diagramas en las secciones narrativas; GAP-CH2-002, GAP-CH2-003 y GAP-CH2-004 se conservan en sus módulos respectivos. GAP-CH2-005, GAP-CH2-006 y GAP-CH2-007 corresponden a variaciones e inconsistencias de Sprint 3 y no se inventan ni se trasladan al Sprint 1.
