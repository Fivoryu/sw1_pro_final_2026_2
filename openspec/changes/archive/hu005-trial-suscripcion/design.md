# Diseño técnico — Trial y suscripción mensual de tenant (HU-005)

- **Cambio:** `hu005-trial-suscripcion`
- **Trazabilidad:** `PB-005` / `HU-005` / `CU-005` / `CP-004`
- **Sprint / plataforma:** Sprint 1 / Web y Backend
- **Dominio:** `tenant.subscription`
- **Idioma:** español profesional y neutral
- **Estado:** diseño listo para la fase de tareas; no declara implementación, migraciones, tests, revisión, commits ni pushes ejecutados
- **Presupuesto duro:** exactamente `400` líneas modificadas como máximo; no existe excepción implícita

## 1. Decisión técnica resumida

Se extenderá el módulo FastAPI `tenant` conservando `router → service → repository`. La autorización administrativa usará el `get_current_user` existente de `identity`, que valida el Bearer/JWT y la sesión, más una tabla específica `tenant_administrator` enlazada al `UsuarioGlobal`, al `Tenant` y a la `Invitacion` inicial consumida por HU-004. No se creará una membresía general, catálogo de roles ni RBAC.

La activación y la inspección resolverán el tenant únicamente desde la asociación activa del principal JWT. El webhook continuará siendo máquina-a-máquina y reutilizará el verificador HMAC de HU-004 sobre los bytes originales. Una operación de repositorio transaccional bloqueará la suscripción, comprobará idempotencia, calculará las fechas y persistirá el cambio junto con el evento mensual. PostgreSQL será la autoridad para la unicidad y la recuperación de carreras.

El grafo implementado será únicamente:

```text
HU-004 initial active → trialing → active
```

La migración será aditiva, mantendrá nulos los nuevos campos para filas legacy y no modificará el plan ni las filas iniciales de HU-004. La revisión Alembic concreta no se inventa en este diseño: se determinará contra el head real y la revisión HU-004 presente en el submódulo antes de crearla.

## 2. Hechos del repositorio, decisiones y supuestos

### 2.1. Hechos verificados

- `backend/app/modules/tenant/models.py` contiene `Tenant`, `Plan`, `Suscripcion` y `EventoFacturacion`. `Suscripcion` ya tiene `tenant_id`, `plan_id`, `estado`, `trial_fin`, `periodo_fin` y `cancelado_en`, pero no `trial_inicio` ni `periodo_inicio`.
- `EventoFacturacion.idempotency_key` es único y `payload_hash` es nullable en el modelo actual. `suscripcion_id`, `tipo`, `payload_firmado`, `estado` y el vínculo legacy `checkout_id` ya forman parte de la frontera de eventos.
- `tenant.service` todavía recibe `tenant_id` para `activar_prueba` y `suscribirse`; muta la entidad y usa commits separados. El flujo actual no satisface la autorización, estado, HMAC ni atomicidad de HU-005.
- `tenant.router` ya expone `POST /api/v1/tenant/activar-prueba`, `POST /api/v1/tenant/suscribir` y `POST /api/v1/tenant/webhook`.
- `identity.router.get_current_user` usa `HTTPBearer`, `AuthenticationService.me` y devuelve `MeResponse` con `id` y `correo`. Esta dependencia será la fuente del principal para las operaciones administrativas; no se duplicará la validación JWT.
- `UsuarioGlobal` tiene `id`, `correo` y `estado`; `Sesion` vincula las sesiones al usuario global. La identidad y la sesión no se alteran por HU-005.
- `backend/alembic/versions/0003_crear_tablas_tenant.py` crea el esquema base de tenant y no contiene por sí sola todas las extensiones que los modelos actuales atribuyen a HU-004. El head efectivo y la revisión HU-004 deben verificarse en la fase de tareas/apply.
- El diseño de HU-004 establece la frontera HMAC versionada, el uso de raw bytes, `payload_hash`, la unicidad de `idempotency_key`, el resultado idempotente y la persistencia del evento. HU-005 reutilizará esa frontera y no creará una implementación criptográfica paralela.

### 2.2. Decisiones cerradas en este diseño

| Área | Decisión técnica |
| --- | --- |
| Bootstrap | `POST /api/v1/tenant/administrador/bootstrap`, JWT requerido y body vacío. El servidor localiza la invitación de primer administrador de HU-004 en estado `consumida` cuyo correo normalizado coincide con `MeResponse.correo`; crea o reconoce una única asociación. |
| Asociación | `tenant_administrator` guarda `tenant_id`, `usuario_global_id`, `invitacion_id`, `activo`, `creado_en` y `desactivado_en`, con FKs y unicidad. `invitacion_id` hace trazable el vínculo a HU-004 sin aceptar el token crudo. |
| Identidad | Se inyecta `Depends(get_current_user)` desde `identity.router`; el service recibe un principal reducido con `id` y correo normalizado. El evento firmado nunca suplanta ese principal. |
| Correlación mensual | El body firmado usa `subscription_id` como referencia opaca de la suscripción. No contiene `tenant_id`; el tenant y el plan se resuelven en PostgreSQL. |
| Evento mensual | `event_type = "subscription.monthly.succeeded"`; campos exactos: `event_type`, `idempotency_key`, `subscription_id`, `plan_id` y `monto_bob`. |
| Respuesta | La proyección administrativa usa `subscription_id`, `plan_id`, `estado`, `trial_inicio`, `trial_fin`, `periodo_inicio` y `periodo_fin`. No devuelve evento, body firmado, monto, firma, secreto ni datos administrativos completos. |
| Compatibilidad | `/suscribir` se conserva como alias deprecated de la misma tubería firmada de `/webhook`; no acepta el contrato legacy como autoridad ni ejecuta commits propios. El body antiguo sin HMAC/contrato mensual falla cerrado y no muta datos. |
| Replay | Se devuelve `200` con el resultado mensual persistido; un evento nuevo devuelve `201`. La respuesta idempotente conserva los identificadores y fechas originales. |
| Estados | Solo se implementan `active` inicial de HU-004, `trialing` y `active` convertido. Los estados de HU-006 siguen representables, pero no son transiciones de este slice. |
| Tiempo | Trial de `336` horas exactas mediante `timedelta(hours=336)`. Periodo mensual por fecha local en `America/La_Paz`, no por `30` días. |

### 2.3. Supuestos que deberán confirmarse como evidencia técnica

- La rama objetivo conserva el helper/verificador HMAC de HU-004 y su contrato de headers sin cambios incompatibles.
- La revisión Alembic de HU-004 y sus columnas de `EventoFacturacion` están presentes en el head real del backend. Si el head no las contiene, la integración de HU-005 no debe duplicarlas: debe detenerse y coordinar la dependencia de HU-004.
- El administrador global se registra/inicia sesión con el mismo correo normalizado que HU-004 guardó en `Invitacion.correo`. Si hay más de un candidato no asociado para el principal, el bootstrap falla cerrado en lugar de elegir por `tenant_id`.
- La evidencia de locks, carrera de unicidad, rollback y downgrade se obtendrá contra PostgreSQL; los fakes solo cubrirán reglas y contratos determinísticos.

## 3. Arquitectura y mapa de work units

### 3.1. Flujo de componentes

```text
HTTP
 ├─ identidad JWT/sesión → get_current_user → TenantPrincipal
 ├─ admin router → TenantService → TenantRepository
 │                         └────────────── PostgreSQL
 └─ webhook raw bytes → HMAC HU-004 → evento mensual → TenantRepository
                                             └────── PostgreSQL
```

El router solo lee el body crudo del webhook, obtiene headers, resuelve dependencias y traduce excepciones. El service contiene autorización de caso de uso, reglas de estado, fechas, validación del evento y proyección. El repository contiene `select`, `with_for_update`, restricciones, transacciones y recuperación de `IntegrityError`. Ningún método público de HU-005 combinará `guardar_suscripcion` y `registrar_evento_facturacion` como commits independientes.

### 3.2. Mapa de archivos bajo `backend/`

| Archivo | Work unit | Cambio previsto y límite |
| --- | --- | --- |
| `backend/app/modules/tenant/models.py` | `WU-005-DATA` | Agregar `trial_inicio`, `periodo_inicio` y `TenantAdministrator`; agregar únicamente las columnas de resultado mensual que no existan en HU-004. No agregar roles, permisos, memberships ni relación genérica. |
| `backend/app/modules/tenant/schemas.py` | `WU-005-CONTRACT` | Reemplazar requests inseguros de activación/suscripción por request vacío y evento mensual estricto; preservar el schema de onboarding HU-004; agregar proyección, bootstrap y respuesta mensual sin secretos. |
| `backend/app/modules/tenant/service.py` | `WU-005-RULES` | Introducir `TenantPrincipal`, bootstrap, activación derivada, inspección, cálculo calendario y conversión mensual. Reutilizar `HMACWebhookSignatureVerifier` y la tubería de webhook existente; no implementar otro HMAC. |
| `backend/app/modules/tenant/repository.py` | `WU-005-POSTGRES` | Agregar operaciones atómicas para bootstrap, autorización, activación, inspección y conversión; locks de filas, hash exacto, replay y carrera de unicidad. Mantener los métodos de HU-004/HU-006 compatibles. |
| `backend/app/modules/tenant/router.py` | `WU-005-HTTP` | Agregar bootstrap y `GET /suscripcion`, proteger activación/inspección con `get_current_user`, convertir `/webhook` y `/suscribir` en entradas a la misma tubería HMAC y mapear errores sanitizados. |
| `backend/alembic/versions/<next_revision>_hu005_trial_subscription.py` | `WU-005-MIGRATION` | Crear una revisión aditiva con `down_revision` resuelto al head real, sin fijar aquí un número inventado. Agregar campos, tabla, FKs e índices; downgrade fail-closed con datos HU-005. |
| `backend/tests/test_tenant_subscription.py` (o el módulo de pruebas tenant existente) | `WU-005-TDD` | Tests contractuales, de servicio, calendario, PostgreSQL, concurrencia, rollback y regresión. Se elegirá el nombre final sin crear una segunda suite redundante. |

No se modifica UI, `docs/diagramas/Diagrama1.eapx`, identidad, el catálogo de planes ni la configuración de otros módulos salvo el mínimo registro de modelos que la metadata Alembic requiera y que se confirme en apply.

## 4. Asociación mínima y bootstrap

### 4.1. Modelo `tenant_administrator`

La tabla `tenant_administrator` tendrá esta forma mínima:

| Campo | Tipo/constraint | Propósito |
| --- | --- | --- |
| `id` | UUID, PK | Identificador opaco de la asociación. |
| `tenant_id` | UUID, FK `tenant.id`, NOT NULL | Tenant al que pertenece la asociación. |
| `usuario_global_id` | UUID, FK `usuario_global.id`, NOT NULL | Principal global autenticado por JWT. |
| `invitacion_id` | UUID, FK `invitacion.id`, NOT NULL | Registro server-owned de activación inicial de HU-004. No es un token crudo. |
| `activo` | boolean, NOT NULL, default `true` | Habilita o bloquea activación/inspección. |
| `creado_en` | `TIMESTAMPTZ`, NOT NULL | Momento de creación/activación del vínculo. |
| `desactivado_en` | `TIMESTAMPTZ`, NULL | Reservado para una futura desactivación; HU-005 no la ejecuta. |

Restricciones:

- `UNIQUE (tenant_id, usuario_global_id)` evita duplicar el mismo vínculo.
- `UNIQUE (invitacion_id)` evita reutilizar la activación inicial para dos asociaciones.
- Índices sobre `(usuario_global_id, activo)` y `(tenant_id, activo)` soportan la resolución de autorización.
- No se agrega `rol`, `permiso`, `membership_type`, invitación de agente ni tabla de roles.

La asociación es válida para HU-005 solo si `activo = true`, el tenant está disponible, el `UsuarioGlobal` coincide con el principal y la `Invitacion` vinculada está `consumida`. El `invitacion_id` es una prueba de procedencia; el correo es solo el criterio de matching durante el bootstrap. La autorización posterior usa el FK y el estado de la asociación, no el correo ni un dato enviado por el cliente.

### 4.2. Endpoint de bootstrap

`POST /api/v1/tenant/administrador/bootstrap`

- **Auth:** `Authorization: Bearer <JWT>`; se resuelve mediante el `get_current_user` existente.
- **Body:** ninguno. Un objeto vacío `{}` puede aceptarse; cualquier campo, incluido `tenant_id`, responde `422` por `extra="forbid"`. No se acepta password, token de activación crudo, `tenant_id` selector ni una membresía como sustituto.
- **Resolución:** primero buscar una asociación activa ya vinculada al `usuario_global_id`; si existe exactamente el vínculo reconocido, devolverlo idempotentemente. Si no existe, buscar una `Invitacion` `consumida` de primer administrador cuyo `correo` normalizado coincida con `MeResponse.correo`, con tenant y suscripción existentes. El repository bloquea el candidato y verifica que no esté asociado.
- **Creación:** insertar `tenant_administrator` con el `usuario_global_id`, `tenant_id` e `invitacion_id` encontrados dentro de una transacción. La identidad del usuario se toma del JWT; la invitación y el tenant son datos server-owned.
- **Ambigüedad:** si hay múltiples candidatos no asociados, no se selecciona ninguno por orden o por un `tenant_id` aportado; se responde un error genérico de bootstrap no disponible y no se revela cantidad, correo o tenants.
- **Respuesta de creación:** `201` con `tenant_id`, `administrador_id`, `activo: true`, `idempotente: false`.
- **Respuesta repetida:** `200` con los mismos identificadores y `idempotente: true`.
- **Errores:** JWT ausente/inválido `401` (`INVALID_SESSION` del límite existente); vínculo server-owned inexistente, invitación no consumida o asociación no elegible `404` (`ADMIN_BOOTSTRAP_UNAVAILABLE`); asociación existente inactiva `409` (`ADMIN_ASSOCIATION_INACTIVE`). Todos los cuerpos son genéricos.

El bootstrap no crea `UsuarioGlobal`, no genera contraseña, no consume invitaciones, no envía notificaciones y no activa el trial. El consumo de la invitación continúa siendo la operación de HU-004; la asociación solo puede formarse después de ese hecho server-owned. Si HU-007 necesita memberships o roles, deberá introducir su propio modelo y migración sin reinterpretar esta tabla.

## 5. Contratos HTTP

### 5.1. `POST /api/v1/tenant/activar-prueba`

- **Auth:** JWT válido y asociación `tenant_administrator.activo = true`.
- **Request:** sin body. No se acepta ninguna autoridad tenant; un `tenant_id` enviado no puede seleccionar el tenant y debe producir `422`.
- **Resolución:** `TenantPrincipal.id` → asociación activa → `Suscripcion` del tenant. La consulta no recibe un tenant del cliente.
- **Éxito:** `200` con:

```json
{
  "subscription_id": "<uuid>",
  "plan_id": "<uuid>",
  "estado": "trialing",
  "trial_inicio": "2026-09-04T15:00:00Z",
  "trial_fin": "2026-09-18T15:00:00Z",
  "periodo_inicio": null,
  "periodo_fin": null
}
```

`trial_fin - trial_inicio` es exactamente `336` horas. Los nombres `trial_inicio` y `periodo_inicio` son persistentes y aparecen también en inspección.

- **Errores:** falta de asociación/suscripción accesible `404` (`TENANT_SUBSCRIPTION_UNAVAILABLE`); suscripción con estado incompatible, trial previo o datos inconsistentes `409` (`TRIAL_ALREADY_ACTIVATED` o `SUBSCRIPTION_STATE_CONFLICT`). No se devuelve información que permita comparar tenants. Un fallo transaccional `500` (`SUBSCRIPTION_UPDATE_FAILED`).

La operación de service no muta una entidad y luego llama a un commit genérico: delega `activar_trial(tenant_id, ahora)` al repository, que bloquea la fila y decide nuevamente la elegibilidad dentro de la transacción.

### 5.2. `GET /api/v1/tenant/suscripcion`

- **Auth:** JWT válido y asociación administrativa activa.
- **Query/body:** ninguno. Un `tenant_id` en query, body u otro header no altera la selección; el endpoint no acepta un selector de tenant.
- **Éxito:** `200` con la misma proyección mínima de la suscripción autorizada. Los valores no aplicables son `null`:

```json
{
  "subscription_id": "<uuid>",
  "plan_id": "<uuid>",
  "estado": "active",
  "trial_inicio": "2026-09-04T15:00:00Z",
  "trial_fin": "2026-09-18T15:00:00Z",
  "periodo_inicio": "2026-09-18T15:00:00Z",
  "periodo_fin": "2026-10-18T15:00:00Z"
}
```

- **Errores:** `401` para JWT inválido; `404 TENANT_SUBSCRIPTION_UNAVAILABLE` para asociación inexistente/inactiva o suscripción no accesible. El mismo cuerpo se usa sin revelar si el tenant o la suscripción existen.

La proyección no contiene `payload_firmado`, body mensual, `monto_bob`, firma, secreto, JWT, password, token, hash de token, hash completo de payload, correo completo ni datos de otro tenant. El `plan_id` se lee del vínculo server-owned y no es una capacidad de cambio.

### 5.3. `POST /api/v1/tenant/webhook`

- **Auth:** no JWT; HMAC de HU-004. Requiere `Content-Type: application/json`, exactamente un `X-RoomForge-Webhook-Timestamp` y exactamente un `X-RoomForge-Webhook-Signature`.
- **Raw body:** el router ejecuta `await request.body()` una sola vez y pasa esos bytes sin decodificar/reserializar al verificador y al cálculo de hash.
- **Evento mensual aceptado:**

```json
{
  "event_type": "subscription.monthly.succeeded",
  "idempotency_key": "evt-monthly-0001",
  "subscription_id": "<uuid>",
  "plan_id": "<uuid>",
  "monto_bob": "449.00"
}
```

`extra="forbid"` rechaza `tenant_id`, `checkout_id` usado como autoridad, correo, cuotas y cualquier campo adicional. `subscription_id` es una correlación, no una autorización. `plan_id` y `monto_bob` se comparan con el plan contratado; no actualizan el plan.

- **Éxito nuevo:** `201`:

```json
{
  "evento_id": "<uuid>",
  "subscription_id": "<uuid>",
  "estado": "active",
  "periodo_inicio": "2026-09-18T15:00:00Z",
  "periodo_fin": "2026-10-18T15:00:00Z",
  "idempotente": false
}
```

- **Replay exacto autenticado:** `200`, mismos `evento_id`, `subscription_id` y fechas persistidas, `idempotente: true`. Se permite recuperar este resultado aunque el timestamp de la repetición esté fuera de la ventana aplicable a eventos nuevos.
- **Errores:**

| Situación | HTTP/código | Efecto |
| --- | ---: | --- |
| Firma ausente, alterada, malformada o timestamp inválido/stale para clave nueva | `401 WEBHOOK_UNAUTHORIZED` | Sin lookup ni escritura de negocio. |
| Secreto no configurado | `503 WEBHOOK_NOT_CONFIGURED` | Falla cerrado. |
| JSON o schema inválido después de autenticar | `422` | Sin escritura. |
| Tipo mensual incorrecto o correlación/estado/trial/plan/monto incompatible | `409 SUBSCRIPTION_CONVERSION_CONFLICT` | Sin cambio de suscripción ni evento mensual. |
| Misma clave con bytes distintos, evento legacy sin hash o evento existente de otro tipo | `409 IDEMPOTENCY_CONFLICT` | Se conserva el primer resultado; no se presume replay. |
| Falla de persistencia | `500 SUBSCRIPTION_CONVERSION_FAILED` | Rollback completo. |

El handler de onboarding de HU-004 continúa aceptando `tenant.onboarding.succeeded` dentro de esta frontera compartida. El dispatch por `event_type` ocurre después de autenticar el raw body; cada tipo conserva su respuesta y reglas. Un evento de onboarding existente nunca se proyecta como resultado mensual.

### 5.4. Compatibilidad de `POST /api/v1/tenant/suscribir`

La ruta se conserva temporalmente como alias deprecated de `/webhook` para no romper el path de integración del simulador. Internamente comparte exactamente:

1. lectura del raw body y headers;
2. verificador HMAC HU-004;
3. parser discriminado del evento;
4. servicio de idempotencia y conversión mensual;
5. mapeo de status y respuesta.

No conservará la implementación actual que recibe `tenant_id`, `plan_id` o `payload_firmado` y hace dos commits. El contrato legacy no puede autorizar tenant, cambiar plan ni evadir HMAC. Una llamada legacy sin los headers HMAC falla con `401` sin lookup; con headers válidos pero body no mensual responde `422` o `409` según la validación, siempre sin mutación. La retirada futura del alias es una decisión posterior y no forma parte de HU-005.

No se agrega un endpoint para enumerar eventos o consultar por `idempotency_key`.

## 6. Estado, guards y flujo de datos

### 6.1. Activación

1. `get_current_user` valida JWT/sesión y entrega `MeResponse.id` y `MeResponse.correo`.
2. El service resuelve una asociación activa por `usuario_global_id`; no mira body/query.
3. El repository bloquea la única suscripción del tenant con `FOR UPDATE`.
4. La elegibilidad exige `estado == "active"`, `trial_inicio IS NULL`, `trial_fin IS NULL`, `periodo_inicio IS NULL`, `periodo_fin IS NULL` y ausencia de una conversión mensual previa.
5. Con el reloj inyectado, escribe `trial_inicio = ahora`, `trial_fin = ahora + timedelta(hours=336)`, `estado = "trialing"` y hace commit único.
6. Una segunda solicitud, incluso después de `trial_fin`, observa el row bloqueado ya iniciado y responde conflicto sin sobrescribir fechas, estado ni eventos.

Un tenant sin suscripción, una suscripción incompatible o fechas parcialmente pobladas no genera fechas sintéticas, no crea una suscripción y no crea evento.

### 6.2. Conversión mensual

Después de la autenticación HMAC y de validar el schema:

1. Se resuelve `EventoFacturacion` por `idempotency_key` dentro de la transacción. Si existe, se compara el hash de los bytes exactos y se exige que sea un evento mensual con resultado mensual persistido.
2. Para una clave nueva se resuelve `Suscripcion` por `subscription_id` y se bloquea con `SELECT ... FOR UPDATE`.
3. Se carga el `Plan` por el `plan_id` contratado de la suscripción y se verifica que siga activo y sea el plan aprobado. El `plan_id` del evento debe coincidir; nunca se asigna desde el evento.
4. Se exige `estado == "trialing"`, ambos límites de trial consistentes y `ahora < trial_fin`. La igualdad `ahora == trial_fin` es expirada.
5. Se calcula `periodo_inicio = ahora` y `periodo_fin` según la sección temporal.
6. Se actualiza la suscripción a `active` con ambas fechas.
7. Se inserta el evento con tipo mensual, key, raw body, `payload_hash`, `suscripcion_id` y referencias del resultado; se hace `flush` y un solo `COMMIT`.

Una clave diferente cuando la suscripción ya está `active` es conflicto de estado, no renovación ni segundo evento procesado. El estado persistente de un trial expirado sigue siendo `trialing`; HU-005 solo rechaza la conversión y deja la remediación a HU-006.

### 6.3. Grafo completo de guards

| Entrada | Guard | Resultado |
| --- | --- | --- |
| Bootstrap | JWT válido, usuario activo, invitación HU-004 consumida, correo coincidente, vínculo no usado | Asociación única activa; repetición idempotente. |
| Activación | Asociación activa, suscripción inicial `active`, trial/periodo nulos | `active → trialing`; fechas de 336 horas. |
| Activación repetida | Cualquier trial previo o estado posterior | `409`, sin cambios. |
| Conversión | HMAC válido, evento mensual, suscripción bloqueada `trialing`, `now < trial_fin`, plan/monto/correlación coincidentes | `trialing → active`; período persistido y evento. |
| Conversión en límite | `now >= trial_fin` | `409`, sin evento procesado ni nuevo estado. |
| Conversión desde initial `active` | No existe `trialing` válido | `409`, sin cambios. |
| Conversión post-conversión | Clave nueva y estado `active` convertido | `409`, sin segundo evento. |
| Replay | Misma key, mismo hash, evento mensual completo, HMAC válido | `200`, resultado original. |
| Reutilización conflictiva | Misma key con otro hash, correlación o tipo, o evento legacy incompleto | `409`, primer resultado intacto. |
| Estado futuro | `past_due`, `grace`, `suspended`, `canceled_read_only`, `purged` u otro | Rechazo sin transición; estados permanecen representables para HU-006. |

## 7. Tiempo, timestamps y calendario

- `ClockProtocol.now()` será la única fuente de tiempo del service. Debe entregar un `datetime` consciente de zona; un reloj naive es un error de programación en tests, no se interpreta silenciosamente como hora local.
- Las instancias se normalizan a UTC para persistencia en `DateTime(timezone=True)` / PostgreSQL `TIMESTAMPTZ`. La serialización HTTP es RFC 3339 con zona, preferentemente `Z` para instantes UTC.
- `trial_inicio` y `trial_fin` se almacenan como instantes. `trial_fin = trial_inicio + timedelta(hours=336)`; no se usa `days=14` si eso pudiera ocultar la regla absoluta, ni se calcula por fecha calendario.
- Expiración es `ahora >= trial_fin`. La comparación ocurre dentro de la transacción que tiene bloqueada la suscripción; no depende de un estado materializado `expired`.
- La zona de negocio para el periodo es `ZoneInfo("America/La_Paz")`.

Algoritmo determinista de `periodo_fin`:

```text
local = periodo_inicio.astimezone(ZoneInfo("America/La_Paz"))
mes_siguiente = local.year/local.month + 1
ultimo_dia = calendar.monthrange(mes_siguiente.year, mes_siguiente.month)[1]
dia = min(local.day, ultimo_dia)
fin_local = datetime.combine(
    date(mes_siguiente.year, mes_siguiente.month, dia),
    local.timetz(),
)
periodo_fin = fin_local.astimezone(UTC)
```

La construcción conserva hora, minuto, segundo y microsegundo locales, y solo clampa el día. `31 → 30/29/28`, enero → febrero y años bisiestos se prueban explícitamente. No se suma una duración fija de 30 días. `periodo_inicio` es el mismo instante de conversión, almacenado de forma consciente de zona; la zona solo determina el calendario del fin.

## 8. HMAC, evento mensual e idempotencia

### 8.1. Contrato compartido

El monthly event debe reutilizar exactamente el helper de HU-004:

```text
message = ASCII(timestamp) + b"." + raw_body
signature = HMAC-SHA256(BILLING_WEBHOOK_SECRET, message)
header = "v1=" + lowercase_hex(signature)
```

Headers exactos:

```text
Content-Type: application/json
X-RoomForge-Webhook-Timestamp: <unix timestamp>
X-RoomForge-Webhook-Signature: v1=<64 lowercase hexadecimal characters>
```

La secuencia obligatoria es:

1. leer `raw_body` una vez;
2. comprobar presencia, multiplicidad y formato de headers;
3. verificar HMAC con comparación constante usando el raw body y el timestamp ASCII;
4. parsear el evento autenticado con campos extra prohibidos;
5. calcular `SHA-256(raw_body)` para `payload_hash`;
6. recién entonces consultar idempotencia o cualquier dato de negocio;
7. para una clave nueva, aplicar la misma tolerancia de HU-004, incluida la igualdad del límite;
8. validar correlación, plan, monto, estado y periodo;
9. delegar la transacción al repository.

Un replay exacto ya autenticado puede recuperar el resultado persistido antes de aplicar la ventana de un evento nuevo. Esto no relaja la verificación HMAC: una firma ausente o inválida nunca puede usar el camino de replay. El body no se reserializa para verificar ni para calcular el hash.

### 8.2. Persistencia mensual

El `EventoFacturacion` mensual conservará `suscripcion_id`, `tipo`, `payload_firmado`, `idempotency_key`, `estado` y `payload_hash`. Si HU-004 todavía no provee referencias suficientes para devolver el resultado original, se agregarán únicamente:

- `resultado_periodo_inicio TIMESTAMPTZ NULL`;
- `resultado_periodo_fin TIMESTAMPTZ NULL`.

Para un evento mensual nuevo ambos se escriben en la misma transacción. La respuesta de replay se reconstruye desde esas referencias y `suscripcion_id`, no desde el body recibido ni desde datos actuales potencialmente modificados por HU-006. Los campos son null para eventos legacy.

`tipo = "subscription.monthly.succeeded"` distingue el evento mensual de `tenant.onboarding.succeeded`. Una fila con la misma key pero tipo distinto, hash null o referencias mensuales ausentes no es replay mensual exacto y responde `409 IDEMPOTENCY_CONFLICT`.

### 8.3. Orden de carrera y recuperación

El repository seguirá este patrón lógico, con una sesión/transacción exclusiva para toda la conversión:

```text
BEGIN
  localizar evento por idempotency_key después de HMAC
  si existe:
    verificar tipo mensual, payload_hash y resultado persistido
    devolver replay o conflicto
  bloquear suscripción por subscription_id FOR UPDATE
  volver a consultar evento por key dentro de la transacción
  validar trialing, now < trial_fin, plan, monto y correlación
  calcular periodo_inicio/periodo_fin
  actualizar suscripción
  insertar evento mensual con hash y resultado
  FLUSH
COMMIT
```

La reconsulta después del lock cubre el caso de dos solicitudes para la misma suscripción. El lock de la suscripción serializa claves diferentes para esa suscripción. Si dos suscripciones compiten por la misma key, la unicidad PostgreSQL de `idempotency_key` es la autoridad: la segunda transacción hace rollback y una lectura limpia del evento comprometido decide replay exacto o `409`, nunca éxito inferido por el texto de una excepción.

No se tratará cualquier `IntegrityError` como duplicado. Solo se recuperará una carrera cuando una lectura posterior encuentre la fila de la key y confirme hash/tipo/resultado; fallas de FK, nullabilidad, plan o columnas se traducen a error transaccional. Ante cualquier fallo después de validar, se ejecuta rollback de estado, fechas y evento conjuntamente.

## 9. Modelo PostgreSQL y migración aditiva

### 9.1. Cambios de esquema

La nueva revisión deberá agregar, sin sobrescribir datos:

- `suscripcion.trial_inicio TIMESTAMPTZ NULL`;
- `suscripcion.periodo_inicio TIMESTAMPTZ NULL`;
- tabla `tenant_administrator` con los campos, FKs y unicidades de la sección 4;
- índices de resolución de asociación activa;
- `evento_facturacion.resultado_periodo_inicio` y `resultado_periodo_fin` solo si la revisión HU-004 no los provee;
- cualquier columna de correlación/hash estrictamente ausente en HU-004, sin duplicar `suscripcion_id`, `idempotency_key` o `payload_hash` existentes.

No se agregan checks que enumeren solo los estados de HU-005. Los estados futuros de HU-006 deben seguir siendo almacenables. Las guards de transición son de aplicación y se aplican bajo lock.

El archivo debe tener un nombre de revisión nuevo y `down_revision` igual al head real descubierto en la fase de tareas/apply. No se fija `0004` ni otro número sin inspeccionar la cadena efectiva; `0003` es solo la revisión del archivo leído, no una prueba suficiente del head actual del submódulo.

### 9.2. Legacy HU-004

- Filas existentes de `suscripcion` en `active` conservan `plan_id`, estado y fechas existentes; los nuevos `trial_inicio` y `periodo_inicio` quedan `NULL`.
- No se crean trials sintéticos, asociaciones retroactivas, eventos mensuales ni cambios de precio/plan.
- Eventos HU-004 mantienen su `tipo` y sus datos. Un evento heredado sin `payload_hash` o sin resultado mensual no se presume replay.
- Si la tabla actual ya contiene extensiones de HU-004, la migración HU-005 solo agrega el delta después de comprobarlo. No se vuelve a crear `checkout_id`, `payload_hash` ni índices ya existentes.
- El upgrade debe probarse sobre una fixture con tenants, planes y suscripciones iniciales de HU-004 y confirmar que los conteos y valores no cambian.

### 9.3. Downgrade y forward-fix

El `downgrade()` debe inspeccionar antes de soltar columnas o tabla. Si existe una fila de `tenant_administrator`, cualquier valor HU-005 en `trial_inicio`/`periodo_inicio`, o un evento mensual con `tipo`/resultado asociado, debe abortar sin eliminar nada. Solo una base descartable sin datos HU-005 puede ejecutar el downgrade de columnas, índices y tabla en orden inverso.

En una base real con datos HU-005 se conserva el esquema y se aplica forward-fix. Nunca se elimina `tenant`, `suscripcion` o `evento_facturacion` como parte de rollback de aplicación. La compatibilidad de la versión anterior solo se admite si tolera las columnas aditivas; si no, se deshabilita la ruta mensual y se corrige hacia adelante.

## 10. Work units de Strict TDD y evidencia

Strict TDD está activo. La secuencia de implementación debe comenzar con tests fallidos y luego el mínimo código necesario:

1. **`WU-005-TDD-CONTRACT`:** fijar requests/responses, `extra="forbid"`, códigos HTTP, body sin `tenant_id`, proyección segura y alias `/suscribir`. Cubrir `CP-004.1`, `CP-004.2` y `CP-004.3` sin declarar ejecución.
2. **`WU-005-TDD-CALENDAR`:** cubrir reloj inyectado, `336` horas, `now == trial_fin`, `31 → mes corto`, febrero bisiesto/no bisiesto y serialización timezone-aware antes de integrar repository.
3. **`WU-005-TDD-AUTH`:** cubrir JWT ausente/inválido, asociación inexistente/inactiva, matching con invitación consumida, bootstrap repetido, candidato ambiguo y ausencia de leaks. Verificar que body/query/event `tenant_id` nunca sea autoridad.
4. **`WU-005-TDD-STATE`:** cubrir initial `active → trialing`, segunda activación, `trialing → active`, initial `active` directo, expirado, convertido, estados no soportados, plan/monto/correlación incompatibles y plan inmutable.
5. **`WU-005-TDD-HMAC`:** reutilizar el helper HU-004 y probar raw bytes, firma válida/ausente/alterada/malformada, timestamp stale/futuro/límite, autenticación antes de lookup, tipo mensual distinto y replay fuera de ventana.
6. **`WU-005-TDD-POSTGRES`:** contra PostgreSQL, probar unique key, lock de suscripción, activación concurrente, conversión concurrente, misma key con bytes distintos, recuperación de unique race y rollback de la actualización/evento como unidad.
7. **`WU-005-TDD-MIGRATION`:** probar upgrade desde el head HU-004 real, FKs/índices, preservación legacy y downgrade bloqueado con datos; el downgrade vacío es evidencia separada y descartable.
8. **`WU-005-TDD-REGRESSION`:** ejecutar la suite backend, lint, typecheck y gates de migración definidos por el proyecto. CP-004 permanece `not executed` hasta que estas evidencias reales se capturen.

Los fakes de clock, repository y firma verifican determinismo, orden de service y contratos; no se presentarán como evidencia de PostgreSQL. No se ejecutó ningún comando en esta fase. Los comandos posteriores previstos son exactamente:

```text
.venv/Scripts/python.exe -m pytest backend/tests -q
.venv/Scripts/python.exe -m ruff check backend/app backend/tests
.venv/Scripts/pyright.exe backend/app backend/tests
.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head
```

## 11. Rollout, observabilidad, privacidad y rollback

### Rollout seguro

1. Confirmar el head Alembic y el delta exacto de HU-004 antes de crear la revisión.
2. Introducir primero los tests contractuales y de reglas; no modificar UI ni estados de HU-006.
3. Aplicar la migración aditiva en una fixture HU-004 y en PostgreSQL de integración.
4. Configurar `BILLING_WEBHOOK_SECRET` fuera del repositorio y comprobar que su ausencia responde `503`.
5. Habilitar bootstrap, activación e inspección para identidades con invitación HU-004 consumida; habilitar conversión mensual solo con el event type exacto.
6. Revisar OpenAPI y métricas de conflicto antes de ampliar el uso del webhook.

### Señales seguras

Registrar solo agregados y códigos estables: `ADMIN_BOOTSTRAP_UNAVAILABLE`, activación exitosa/conflictiva, denegación de asociación, `WEBHOOK_UNAUTHORIZED`, `SUBSCRIPTION_CONVERSION_CONFLICT`, replay, conflicto de idempotencia, conversión exitosa, rollback y latencia. Se pueden usar `event_type`, route, status y un identificador irreversiblemente abreviado.

Nunca registrar raw body, `payload_firmado`, firma completa, secreto HMAC, JWT, password, token crudo, hashes de tokens, hash completo de payload cuando sea sensible, correo completo, valores de otro tenant ni detalles SQL. La auditoría funcional del webhook es la fila persistida de `EventoFacturacion`; no se agrega notifier, outbox ni proveedor.

### Rollback operativo

Ante un defecto, deshabilitar la entrada mensual o su feature/configuración sin borrar historia ni deshabilitar innecesariamente la inspección. Revertir aplicación solo contra un esquema compatible; con filas HU-005 se prefiere forward-fix. Conservar asociaciones, trials, períodos y eventos para que un reintento con la misma key pueda recuperar el resultado. El downgrade destructivo se limita a una base vacía/descartable y debe detenerse antes de eliminar datos HU-005.

## 12. No-goals y límites

Este diseño no incluye React/Web UI, Flutter, navegación, copy, clientes generados, pagos reales, invoice, nuevos planes/precios/cuotas, enforcement de cuotas, cambios de plan, renovaciones, `past_due`, grace, `suspended`, `canceled_read_only`, `purged`, expiración remediada, notificaciones, S3/SQS/worker, outbox, membresías generales, roles, RBAC, invitaciones de agentes, endpoint de historial de eventos, refactors no relacionados, commits, pushes ni cambios en metadata no relacionada.

La asociación administrativa es una costura explícita de HU-005, no una primera versión de HU-007. El `plan_id` contratado permanece server-owned y el evento no puede sustituirlo. La transición de initial `active` a `trialing` no significa que HU-004 haya sido una conversión mensual.

## 13. Riesgos, pendientes y trazabilidad

### Riesgos

| Riesgo | Mitigación de diseño |
| --- | --- |
| Head/migración de HU-004 no coincide con los modelos actuales | Inspección obligatoria del head antes de crear revisión; agregar solo delta y detener si falta la dependencia. |
| Bootstrap deriva en membership/RBAC | Tabla dedicada, FK a invitación inicial, body vacío y ningún rol/permiso. |
| Se confunde initial `active` con monthly `active` | Conversión exige `trialing`, fechas consistentes y evento mensual. |
| Se rompe la frontera HMAC por reutilizar el alias legacy | `/suscribir` delega la misma tubería raw-byte; el contrato inseguro falla cerrado. |
| Carrera de key o commits parciales | Locks, unicidad PostgreSQL, relectura después de rollback y una sola transacción. |
| Periodo incorrecto en fin de mes | `ZoneInfo("America/La_Paz")`, `calendar.monthrange` y pruebas de leap-year. |
| Replay devuelve estado mutado posteriormente | Persistencia de referencias de resultado mensual y proyección desde el evento. |
| Se supera el límite de `400` líneas | Forecast explícito, reutilización HU-004 y stop para decisión de alcance; no se elevan líneas automáticamente. |

### Pendientes de evidencia, no decisiones de producto

- Confirmar el nombre/export exacto del helper HMAC y sus headers en el head activo de HU-004.
- Confirmar qué columnas de `EventoFacturacion` fueron realmente entregadas por HU-004 antes de agregar referencias mensuales.
- Confirmar el head Alembic real y la revisión padre; no asumir que el archivo leído `0003` es el head.
- Confirmar el módulo de tests tenant existente para elegir entre extenderlo o crear `test_tenant_subscription.py` sin duplicación.

Estos puntos no autorizan cambiar duración, autorización, event type, plan, estados, alcance ni presupuesto.

### Pronóstico de líneas modificadas

| Área | Presupuesto de trabajo |
| --- | ---: |
| Modelos de suscripción/asociación y migración aditiva | 50 |
| Schemas y contratos HTTP | 38 |
| Router, dependencia JWT y mapeo | 26 |
| Service, guards y calendario | 62 |
| Repository, locks, transacción y replay | 78 |
| Tests enfocados y regresión | 92 |
| Costura de compatibilidad HMAC `/webhook`–`/suscribir` | 14 |
| **Trabajo estimado** | **360** |
| **Reserva máxima** | **40** |
| **Límite duro** | **400** |

La reserva no es permiso de excepción. Si el desglose confirmado de tareas excede `400` líneas, la fase de tareas debe reducir o dividir el slice y solicitar una decisión explícita antes de aplicar; no se eliminan silenciosamente guards aprobados.

### Trazabilidad

- `PB-005` / `HU-005` / `CU-005` / `CP-004`: alcance y evidencia del slice.
- `RF-007`, `BR-A2`, `BR-B3` y `BR-B4`: ciclo de suscripción, aislamiento tenant y autoridad del plan.
- HU-002: `get_current_user`, JWT/sesión y `MeResponse.id`/`MeResponse.correo`.
- HU-004: tenant, plan, suscripción inicial `active`, invitación inicial consumida, `EventoFacturacion`, HMAC raw-byte, timestamp tolerance, `payload_hash` e idempotencia.
- HU-006: estados posteriores, cuotas, cambios de plan, cancelación, grace, suspensión y purge; solo quedan representables, no implementados.

## 14. Dependencia de entrega y common directory

El planning SDD vive en el root, mientras que el código y el runtime de Alembic viven en el submódulo `backend/`. El root y el submódulo pueden tener Git common directories y estados distintos; el modified backend gitlink y el metadata OpenSpec/config no relacionado deben preservarse. Antes de apply/verify, la orquestación debe confirmar qué checkout y common directory gobiernan el ledger/runtime nativo, ejecutar los comandos de backend desde la raíz con `backend/` como contexto indicado y evitar contabilizar el gitlink como cambio de producto. Este diseño NO resuelve esa restricción: la deja como dependencia de implementación y entrega para no afirmar una integración nativa que no fue verificada.

No se han ejecutado tests, migraciones, comandos de calidad, revisión ni operaciones de entrega en esta fase.
