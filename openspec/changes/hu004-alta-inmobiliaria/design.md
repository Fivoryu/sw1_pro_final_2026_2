# Diseño — Alta de inmobiliaria (HU-004)

- **Cambio:** `hu004-alta-inmobiliaria`
- **Product Backlog:** PB-004
- **Historia:** HU-004 — Alta de inmobiliaria
- **Caso de prueba:** CP-003
- **Slice:** backend y contrato API
- **Dominio:** `tenant` / onboarding
- **Estado:** diseño para implementación; no declara tests ni migraciones ejecutados
- **Límite:** máximo 600 líneas modificadas
- **Idioma del artefacto:** español profesional y neutral

## 1. Decisiones, alcance y gaps cerrados

Este diseño convierte la propuesta y la especificación aprobadas en un slice backend-first. El checkout simulado es una intención persistida; el webhook firmado es la única frontera que puede aprovisionar el tenant. El panel Web, Flutter, pagos reales, HU-005, HU-006, invitaciones de agentes, membresías generales y RBAC no se implementan ni se modifican funcionalmente.

### 1.1. Decisiones cerradas

1. **Checkout separado:** `GET /api/v1/tenant/plans` consulta el catálogo aprobado y `POST /api/v1/tenant/checkout` crea una intención mínima. Esta operación nunca crea `tenant`, `suscripcion`, `invitacion` ni `evento_facturacion`.
2. **Checkout público y acotado:** para CP-003, el simulador no requiere JWT porque todavía no existe un tenant ni una membresía que autorizar. El endpoint acepta únicamente plan, nombre de empresa y correo del primer administrador; no acepta `tenant_id` ni datos de cuotas como autoridad. La futura exposición fuera de un entorno de demo queda protegida por configuración/infraestructura y es un bloqueo de producto para el rollout productivo, no se inventa una política adicional.
3. **Webhook separado:** `POST /api/v1/tenant/webhook` no usa la identidad del iniciador del checkout. Se autentica exclusivamente con HMAC-SHA256 y el secreto del simulador. La correlación usa la referencia de checkout persistida.
4. **Autoridad del servidor:** el webhook recibe `checkout_id`, `plan_id`, `monto_bob` e `idempotency_key`; el servicio carga el checkout y el plan desde PostgreSQL. Nunca toma del evento un `tenant_id`, correo, nombre, cuota o precio como autoridad.
5. **Una intención, un aprovisionamiento:** `checkout_id` tendrá una unicidad parcial en `evento_facturacion`. Una segunda clave para el mismo checkout no reutiliza silenciosamente el alta; responde conflicto.
6. **Resultado idempotente:** una repetición con la misma clave y los mismos bytes de payload devuelve el resultado originalmente persistido. El primer procesamiento responde `201`; la repetición responde `200` con el mismo resultado de negocio e `idempotente: true`.
7. **Identidad diferida:** HU-004 solo persiste tenant, correo normalizado e invitación pendiente. No crea ni busca `usuario_global`, no crea membresía y no asigna rol. Se deja un puerto `FirstAdminIdentityHook` para HU-007, con adaptador nulo en esta fase.
8. **Notificación simulada:** el token crudo se entrega únicamente a un puerto inyectable después del commit. El adaptador por defecto no envía correo ni registra el token. Una falla de notificación no revierte un alta ya confirmada: la invitación sigue pendiente y la entrega real requiere una futura bandeja/outbox.

### 1.2. Gap que permanece como bloqueo de interacción

`GAP-004-AUTH-001` queda cerrado para la ejecución de CP-003 mediante la política explícita de checkout público de simulador. Permanece un **bloqueo de interacción para el rollout fuera de demo**: el responsable de producto debe decidir si el endpoint se mantiene público con controles de infraestructura o si se exige una cuenta autenticada antes de contratar. No se debe desplegar el endpoint a un entorno productivo con una política distinta sin esa decisión. La implementación conserva una dependencia `CheckoutAccessPolicy` para poder introducirla sin mezclarla con la provisión.

`GAP-004-DOM-001` no es un defecto que se resuelva inventando membresías: la activación de HU-004 consume el token y registra el estado, pero la cuenta global, la membresía y el rol siguen siendo trabajo de HU-007.

`GAP-004-NOTIF-001` se resuelve como interfaz/adaptador simulado. El canal real y el reintento durable permanecen fuera de alcance, sin bloquear CP-003 porque el fake de pruebas observa la entrega.

## 2. Arquitectura y mapa de archivos

La composición conserva el monolito modular FastAPI y el patrón existente `router → service → repository`. `main.py` ya incluye el router `tenant` bajo `/api/v1`; no requiere una nueva ruta de composición.

```text
backend/
├── app/
│   ├── core/
│   │   └── config.py                         # secreto HMAC y ventanas/TTL
│   └── modules/tenant/
│       ├── models.py                         # modelos existentes + campos HU-004
│       ├── schemas.py                        # contratos HTTP HU-004
│       ├── router.py                         # planes, checkout, webhook, activación
│       ├── service.py                        # reglas y orquestación HU-004
│       ├── repository.py                     # SQL, locks, transacciones y recuperación
│       ├── catalog.py                         # códigos/definiciones aprobadas
│       ├── signatures.py                      # HMAC sobre timestamp + bytes crudos
│       └── ports.py                           # reloj, notifier e identity hook
├── alembic/
│   ├── env.py                                # importa todas las entidades nuevas
│   └── versions/0004_hu004_onboarding.py    # esquema aditivo + seed idempotente
└── tests/
    └── test_tenant_onboarding.py             # contrato, servicio y concurrencia
```

| Componente | Responsabilidad | Límite obligatorio |
| --- | --- | --- |
| `tenant.router` | Leer el body crudo del webhook, resolver dependencias y mapear excepciones a HTTP | No consulta SQL ni calcula firmas/reglas |
| `tenant.schemas` | Validar forma, UUID, correo, strings y `Decimal`; declarar respuestas sin secretos | No aceptar precios/cuotas de checkout como autoridad |
| `tenant.service` | Normalizar, verificar firma/correlación, aplicar reglas de catálogo, crear comandos y respuestas | No conocer `select`, `IntegrityError` ni headers concretos |
| `tenant.repository` | Consultar catálogo/intenciones, ejecutar transacciones y locks, recuperar resultados originales | No decidir status HTTP ni construir mensajes de API |
| `tenant.signatures` | Validar formato, HMAC-SHA256, comparación constante y timestamp | No persistir secretos ni payloads en logs |
| `tenant.ports` | Protocolos `ActivationNotifier`, `FirstAdminIdentityHook` y política de acceso | El adaptador nulo no crea identidad ni membresía |
| `tenant.models` | Mapear exactamente las tablas SQL existentes y la extensión aditiva | No agregar columnas de RBAC o membership |
| `core.config` | Cargar `BILLING_WEBHOOK_SECRET`, tolerancia y TTL sin secretos en código | El endpoint webhook falla cerrado si falta el secreto |

Se conservan los métodos y las rutas de HU-005/HU-006 en sus bloques actuales. Solo se extraen o ajustan dependencias compartidas cuando sea necesario para que el router siga importando y funcionando; no se cambia su contrato ni su lógica de negocio.

## 3. Modelo de datos y representación server-owned

### 3.1. Catálogo de planes

El modelo `Plan` mantiene sus columnas existentes y agrega `codigo` y `max_agents`. El precio se mapea como `Decimal`, no como `float`:

| Campo API | Campo persistente | Tipo | Regla |
| --- | --- | --- | --- |
| `plan_id` | `plan.id` | UUID | Identificador estable |
| `codigo` | `plan.codigo` | `VARCHAR(20)` nullable para legacy | `basico`, `profesional`, `empresarial` |
| `nombre` | `plan.nombre` | `VARCHAR(60)` | Nombre aprobado |
| `precio_bob` | `plan.precio_bob` | `NUMERIC(10,2)` / `Decimal` | Se serializa como string con dos decimales |
| `moneda` | no persistido | literal `BOB` | No se acepta otra moneda en HU-004 |
| `max_agents` | `plan.max_agents` | `INTEGER` nullable para legacy | Cuota de agentes, no incluye al admin |
| `cuota_almacenamiento_gb` | igual | `INTEGER` | Cuota server-owned |
| `cuota_inmuebles` | igual | `INTEGER` | Cuota server-owned |
| `cuota_reconstrucciones_mes` | igual | `INTEGER` | Cuota server-owned |
| `activo` | igual | `BOOLEAN` | Solo los tres códigos aprobados y activos son contratables |

La API filtra por `codigo IN (basico, profesional, empresarial)` y `activo = true`, y ordena por el orden canónico del catálogo. Un plan legado activo sin código no aparece. Si falta cualquiera de los tres seeds, el catálogo responde `503` y no devuelve una lista parcial.

Las definiciones canónicas son:

| Código | Nombre | `precio_bob` | `max_agents` | Almacenamiento | Inmuebles | Reconstrucciones/mes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `basico` | Básico | `199.00` | 5 | 50 GB | 5 | 10 |
| `profesional` | Profesional | `449.00` | 15 | 200 GB | 20 | 40 |
| `empresarial` | Empresarial | `899.00` | 50 | 1.000 GB | 100 | 150 |

El campo `max_agents` representa exclusivamente agentes. No existe `max_users` ni se incrementa el contador al consumir la activación del primer administrador. La aplicación futura de cuotas pertenece a HU-006; HU-004 solo expone el catálogo y copia `plan_id` en la suscripción inicial.

### 3.2. Intención de checkout

Se agrega `checkout_intencion`:

| Campo | Tipo | Restricción/uso |
| --- | --- | --- |
| `id` | UUID | PK; referencia opaca entregada al consumidor |
| `plan_id` | UUID | FK a `plan.id`, NOT NULL |
| `nombre_empresa` | `VARCHAR(120)` | NOT NULL, normalizado/validado |
| `correo_admin` | `VARCHAR(255)` | NOT NULL, `strip().lower()` |
| `estado` | `VARCHAR(20)` | `confirmado` o `procesado` |
| `creado_en` | `TIMESTAMPTZ` | NOT NULL, hora inyectada/servidor |

No se guarda el monto enviado por el cliente: el plan es la autoridad. El estado pasa a `procesado` dentro de la misma transacción que crea los recursos iniciales. Un checkout confirmado sin webhook no tiene tenant asociado.

### 3.3. Extensión de onboarding existente

`Invitacion` conserva físicamente la columna `token_unico` por compatibilidad con `0003`, pero el modelo la expone/documenta como `token_hash`; su valor siempre es SHA-256 hexadecimal de un token aleatorio de alta entropía. Se agrega `consumido_en TIMESTAMPTZ NULL`. Los estados de HU-004 son `pendiente` y `consumida`.

`EventoFacturacion` conserva `payload_firmado` e `idempotency_key` y agrega:

- `checkout_id UUID NULL` con FK a `checkout_intencion.id`;
- `payload_hash CHAR(64) NULL` para compatibilidad con eventos heredados.

Los eventos nuevos establecen ambos campos. `payload_hash = SHA-256(bytes_crudos_del_body)`. La columna es nullable porque los eventos de HU-005/HU-006 que pudieran existir antes de esta migración no tienen correlación HU-004; si una clave coincide con uno de esos eventos heredados, se responde conflicto y nunca se presume idempotencia.

Se crea una unicidad parcial sobre `evento_facturacion.checkout_id` cuando no es nulo. La unicidad existente de `idempotency_key` sigue siendo la autoridad para reintentos.

## 4. Firma, autenticidad y replay

### 4.1. Esquema concreto

El simulador calcula:

```text
message = ASCII(timestamp) + b"." + raw_body_utf8
signature = HMAC-SHA256(BILLING_WEBHOOK_SECRET, message)
header = "v1=" + lowercase_hex(signature)
```

La solicitud `POST /api/v1/tenant/webhook` debe contener:

```text
Content-Type: application/json
X-RoomForge-Webhook-Timestamp: 1735689600
X-RoomForge-Webhook-Signature: v1=<64 caracteres hexadecimales>
```

El body que se firma es exactamente el arreglo de bytes recibido por FastAPI. No se vuelve a serializar, ordenar ni normalizar JSON antes de verificarlo. Por eso el simulador/test helper firma los mismos bytes que envía.

El secreto se carga como `BILLING_WEBHOOK_SECRET: str | None` desde `.env`/entorno. No tiene default operativo, no se imprime en configuración y no se incluye en `.env.example`. `WEBHOOK_TIMESTAMP_TOLERANCE_SECONDS` tiene default no secreto de `300`. Si falta el secreto, `get_webhook_verifier` falla cerrado y la ruta responde `503` con un error genérico; no se procesa ni persiste el evento.

### 4.2. Orden de verificación

1. `Request.body()` obtiene bytes una sola vez.
2. Se valida el header de firma y timestamp; valores ausentes, múltiples, malformados o con algoritmo diferente se rechazan.
3. Se calcula el HMAC esperado y se compara con `hmac.compare_digest`/equivalente de comparación constante. Nunca se usa `==` para decidir la firma.
4. Se obtiene `payload_hash` de los bytes y se valida el JSON contra `WebhookEventRequest` con campos extra prohibidos.
5. Se busca la clave existente **solo después de autenticar**. Si existe y su hash es idéntico, se devuelve el resultado original aunque la repetición esté fuera de la ventana; es un reintento autenticado exacto, no una nueva ejecución. Si la clave existe con hash diferente, se responde conflicto.
6. Para una clave nueva, el timestamp debe satisfacer `abs(now_epoch - header_epoch) <= 300`. La igualdad en el límite es válida; un timestamp futuro o atrasado fuera de la tolerancia responde `401`.
7. Solo entonces el servicio valida checkout, plan y monto, y delega la transacción de provisión.

Esta excepción para un duplicado exacto permite que un cliente recupere el resultado original sin regenerar recursos. No permite cambiar el body: una misma clave con bytes diferentes siempre se compara y se rechaza.

### 4.3. Fallos de seguridad

Todos los fallos de autenticidad responden `401` con:

```json
{"code":"WEBHOOK_UNAUTHORIZED","detail":"Evento no autorizado"}
```

La respuesta no distingue secreto ausente, header ausente, firma incorrecta o timestamp inválido. El body crudo, firma recibida, secreto y contenido del error no se escriben en logs. Un JSON válido con firma válida pero esquema inválido responde `422` sin persistencia; no se usa `401` para errores de forma posteriores a una autenticación correcta.

## 5. Contratos HTTP exactos

Los esquemas nuevos usan `extra="forbid"` cuando un dato adicional podría parecer autoridad. Los precios se muestran como strings `^[0-9]+\.[0-9]{2}$`; internamente se comparan como `Decimal("0.01")` cuantizado.

### 5.1. Consulta de catálogo

`GET /api/v1/tenant/plans`

Respuesta `200`:

```json
{
  "plans": [
    {
      "plan_id": "<uuid>",
      "codigo": "basico",
      "nombre": "Básico",
      "precio_bob": "199.00",
      "moneda": "BOB",
      "max_agents": 5,
      "cuota_almacenamiento_gb": 50,
      "cuota_inmuebles": 5,
      "cuota_reconstrucciones_mes": 10
    }
  ]
}
```

La respuesta contiene los tres elementos en el orden canónico. `activo` no es necesario para contratar y no se expone como una autorización del cliente.

### 5.2. Checkout simulado

`POST /api/v1/tenant/checkout`

Request:

```json
{
  "plan_id": "<uuid>",
  "nombre_empresa": "Inmobiliaria Ejemplo",
  "correo_admin": "admin@example.com"
}
```

El servicio recorta y normaliza el correo, valida que el nombre no quede vacío y carga el plan activo aprobado. No se aceptan `precio_bob`, `max_agents`, cuotas, `tenant_id` ni `payload_firmado`; con `extra="forbid"`, su presencia responde `422` y no crea intención.

Respuesta `201`:

```json
{
  "checkout_id": "<uuid>",
  "estado": "confirmado",
  "simulado": true,
  "plan": { "plan_id": "<uuid>", "codigo": "basico", "nombre": "Básico", "precio_bob": "199.00", "moneda": "BOB", "max_agents": 5, "cuota_almacenamiento_gb": 50, "cuota_inmuebles": 5, "cuota_reconstrucciones_mes": 10 }
}
```

No contiene `tenant_id`, token, password ni secreto. Plan inexistente/inactivo responde `404` con `PLAN_NOT_AVAILABLE` y no modifica onboarding. Error de validación responde `422`. Si el catálogo está incompleto responde `503` con `PLAN_CATALOG_UNAVAILABLE`.

### 5.3. Evento firmado y resultado

`POST /api/v1/tenant/webhook`

Payload autenticado:

```json
{
  "event_type": "tenant.onboarding.succeeded",
  "idempotency_key": "evt-demo-0001",
  "checkout_id": "<uuid>",
  "plan_id": "<uuid>",
  "monto_bob": "199.00"
}
```

No se admiten `tenant_id`, `nombre_empresa`, `correo_admin` ni cuotas en el evento. El checkout es la fuente de esos datos y el plan activo es la fuente de precio/cuotas.

Respuesta inicial `201` y repetición idempotente `200`:

```json
{
  "evento_id": "<uuid>",
  "tenant_id": "<uuid>",
  "suscripcion_id": "<uuid>",
  "estado_tenant": "activo",
  "estado_evento": "procesado",
  "activacion_admin": "pendiente",
  "idempotente": false
}
```

En la repetición, los identificadores y estados son los persistidos originalmente y `idempotente` es `true`. No se devuelve payload, correo, hash, token ni monto. La respuesta es el mecanismo de recuperación del resultado original; no se agrega un endpoint público de consulta por clave para no ampliar la superficie de enumeración.

Respuestas de rechazo:

| Situación | HTTP | Cuerpo |
| --- | ---: | --- |
| Firma/header ausente o inválida, timestamp inválido o stale | `401` | `WEBHOOK_UNAUTHORIZED` / `Evento no autorizado` |
| Secreto no configurado | `503` | `WEBHOOK_NOT_CONFIGURED` / `Webhook no disponible` |
| JSON/esquema inválido después de autenticar | `422` | detalle sanitizado de validación |
| Checkout inexistente, no confirmado o plan inactivo | `409` | `CHECKOUT_NOT_AVAILABLE` / `El checkout no está disponible` |
| `checkout_id`, `plan_id` o `monto_bob` no coinciden con servidor | `409` | `CHECKOUT_MISMATCH` / `Los datos del evento no coinciden con el checkout` |
| Misma clave con `payload_hash` distinto, o evento heredado sin hash | `409` | `IDEMPOTENCY_CONFLICT` / `La clave de idempotencia ya fue utilizada con otros datos` |
| Checkout ya asociado a otra clave | `409` | `CHECKOUT_ALREADY_PROVISIONED` / `El checkout ya fue procesado` |
| Falla de persistencia/rollback | `500` | `ONBOARDING_NOT_PROVISIONED` / `No se pudo completar el alta` |

Los `409` de correlación y los errores de persistencia no crean efectos parciales. Los mensajes no incluyen valores recibidos ni detalles de SQL.

### 5.4. Activación mínima

`POST /api/v1/tenant/activacion/consumir`

Request:

```json
{"token":"<token crudo recibido fuera de la API de onboarding>"}
```

Respuesta `200`:

```json
{"tenant_id":"<uuid>","estado":"consumida"}
```

El token se recibe como `SecretStr` o equivalente, nunca se loguea y no se devuelve. Token vacío/malformado responde `422`. Token desconocido, expirado o ya consumido responde `410` con:

```json
{"code":"ACTIVATION_UNAVAILABLE","detail":"El enlace de activación no está disponible"}
```

No se revela si el token existió, expiró o fue consumido. La activación no recibe password, no crea `usuario_global` y no crea membresía.

## 6. Flujo de datos y transacciones

### 6.1. Checkout

1. Router valida request y delega.
2. Service normaliza el correo y busca un plan aprobado activo.
3. Repository inserta una `CheckoutIntent` con UUID nuevo y estado `confirmado`, haciendo `flush/commit`.
4. Service proyecta el plan desde `Decimal` a la respuesta string.

Un fallo de inserción revierte solo la intención. No hay efectos de tenant para compensar.

### 6.2. Aprovisionamiento atómico

`TenantRepository.provisionar_onboarding(command)` es una única operación transaccional, no una secuencia pública de `guardar_*`:

```text
BEGIN
  SELECT evento_facturacion WHERE idempotency_key = :key FOR UPDATE
  si existe: comparar payload_hash y devolver resultado o conflicto
  SELECT checkout_intencion WHERE id = :checkout_id FOR UPDATE
  validar estado y plan; consultar evento por checkout_id
  INSERT tenant
  INSERT suscripcion (estado inicial "active", plan_id)
  INSERT invitacion (token_hash, pendiente, expira_en)
  INSERT evento_facturacion (checkout_id, payload_hash, key, payload crudo, procesado)
  UPDATE checkout_intencion SET estado = "procesado"
COMMIT
```

La suscripción inicial queda `active`: HU-004 aprovisiona el plan contratado; no activa el trial de HU-005 ni ejecuta cambios/cancelaciones de HU-006.

El servicio genera UUIDs del tenant, suscripción, evento e invitación antes del `flush`, y genera el token crudo solo en memoria. El repositorio hace `flush` y commit una sola vez. Cualquier excepción de inserción, FK o constraint ejecuta rollback y se traduce a `ONBOARDING_NOT_PROVISIONED`; no se captura toda `IntegrityError` como duplicado.

El nombre y correo del tenant se copian exclusivamente desde `CheckoutIntent`. El `monto_bob` del evento se parsea como `Decimal` y debe coincidir exactamente con `Plan.precio_bob` cuantizado; las cuotas no se reciben del evento y quedan representadas por el plan server-owned.

### 6.3. Idempotencia secuencial y concurrente

El pre-check de servicio solo optimiza el caso ya visible; la autoridad es la unicidad persistente y el lock/recuperación del repositorio.

- **Secuencial, misma clave y mismos bytes:** se busca el evento, se compara `payload_hash`, se carga el resultado por `evento → suscripcion → tenant` y se devuelve sin insertar. No se regenera token ni se vuelve a llamar al notifier.
- **Concurrente, misma clave y mismos bytes:** dos transacciones pueden no ver inicialmente la fila. La unicidad de `idempotency_key` hace que la segunda inserción espere a la primera; tras la violación única, el repositorio abre una lectura limpia, encuentra el evento comprometido, compara el hash y devuelve el resultado original. Si el primer commit falla, su rollback deja la clave libre y el segundo puede ser el único ganador.
- **Misma clave y bytes distintos:** después de verificar la firma, el hash difiere y se responde `409 IDEMPOTENCY_CONFLICT`. No se modifica el evento original ni el tenant.
- **Checkout repetido con otra clave:** el lock del checkout y la unicidad parcial de `evento.checkout_id` permiten recuperar el evento existente solo si también coincide la clave/hash; de lo contrario se responde `CHECKOUT_ALREADY_PROVISIONED`.
- **Falla intermedia:** el evento también está dentro de la transacción; no queda un registro que haga parecer procesado un aprovisionamiento incompleto.

El hash de idempotencia se calcula sobre bytes, no sobre una reserialización. Cambiar orden, espacios, monto o checkout produce un payload distinto y, para una clave usada, conflicto explícito.

### 6.4. Consumo del token

El servicio calcula `sha256(token.encode("utf-8")).hexdigest()`. La operación SQL equivalente es un update condicional bajo transacción:

```text
UPDATE invitacion
   SET estado = 'consumida', consumido_en = :now
 WHERE token_unico = :token_hash
   AND estado = 'pendiente'
   AND expira_en > :now
RETURNING tenant_id
```

Si no retorna fila, se responde `410`. La comparación del hash recuperado puede reforzarse con `hmac.compare_digest`; nunca se compara el token crudo ni se persiste. Dos consumos concurrentes compiten por la misma fila y solo uno puede cambiar `pendiente` a `consumida`.

La expiración por defecto es `now + 7 días`, con `ACTIVATION_TOKEN_TTL_DAYS` no secreto y clock inyectable. Al límite (`now == expira_en`) el token ya está expirado. El hook de identidad no cambia la transacción de consumo y el adaptador nulo no produce usuario/membresía.

## 7. Interfaces internas y dependencias

```text
PlanCatalogRepository
  list_active_approved() -> list[Plan]
  find_active(plan_id: UUID) -> Plan | None

TenantOnboardingRepository
  create_checkout(command) -> CheckoutIntent
  find_event_by_key(key, lock=False) -> ProvisionedResult | None
  provision_onboarding(command) -> ProvisionedResult
  consume_activation(token_hash, now) -> ActivationResult | None

WebhookSignatureVerifier
  verify(raw_body: bytes, timestamp: str, signature: str, now: datetime) -> None

ActivationNotifier
  deliver(*, tenant_id: UUID, email: str, token: str, expires_at: datetime) -> None

FirstAdminIdentityHook
  on_activation_consumed(*, tenant_id: UUID, email: str) -> None

CheckoutAccessPolicy
  authorize(actor) -> None
```

`FakeTenantRepository`, `FakeClock`, `FakeSignatureVerifier`, `RecordingActivationNotifier` y `NullFirstAdminIdentityHook` se inyectan mediante `app.dependency_overrides`. El `RecordingActivationNotifier` solo existe en pruebas y conserva el token para verificar el flujo; ningún logger o response lo recibe.

El `FirstAdminIdentityHook` no implementa `ensure_user`, `create_membership` ni `assign_role` en HU-004. Su contrato futuro debe recibir solamente tenant y correo normalizado; HU-007 decidirá si reutiliza o crea un `usuario_global` y cómo persiste membresía/rol.

## 8. Migración, seed y downgrade

### 8.1. Upgrade `0003 → 0004`

La revisión `0004_hu004_onboarding.py` tiene `down_revision = "0003"` y no modifica `0001`, `0002` ni sus tablas de identidad. El upgrade se ejecuta en este orden:

1. Agrega `plan.codigo` nullable y `plan.max_agents` nullable para no romper filas legadas.
2. Crea `checkout_intencion` y su FK a `plan`.
3. Agrega `invitacion.consumido_en`.
4. Agrega `evento_facturacion.checkout_id` nullable con FK y `payload_hash` nullable.
5. Crea `uq_plan_codigo` (los múltiples `NULL` de planes legados son válidos) y la unicidad parcial de checkout.
6. Ejecuta un seed idempotente de los tres códigos aprobados.
7. `alembic/env.py` importa `CheckoutIntent` junto con los modelos tenant ya existentes para que la metadata sea completa.

El seed usa `codigo` como clave natural y UUID determinístico por código, no `uuid4()` en cada upgrade. Para cada plan:

- si existe exactamente una fila con ese `codigo`, verifica nombre, precio, cuotas, `activo` y `max_agents`; si hay discrepancia, aborta la migración en lugar de sobrescribir datos;
- si no existe código pero hay exactamente una fila con el nombre y todos los valores aprobados, la adopta asignando el código y `max_agents`;
- si hay una colisión de nombre, más de una fila candidata o valores distintos, aborta con error explícito para intervención manual;
- si no hay candidata, inserta el plan aprobado;
- planes legados no relacionados permanecen intactos y no se exponen por el catálogo HU-004.

Así una base vacía recibe exactamente los tres planes, y una base con filas existentes no pierde ni corrige silenciosamente datos comerciales. La migración no crea seeds de HU-005/HU-006 ni aplica cuotas operativas.

### 8.2. Downgrade y datos existentes

El downgrade es solo para una base controlada y se niega si detecta datos propios de HU-004: intenciones en `checkout_intencion`, `evento_facturacion.checkout_id`/`payload_hash` no nulos o invitaciones con `consumido_en`. No elimina tenants, suscripciones, invitaciones ni eventos. Si no hay esos datos, elimina índices/columnas aditivas y la tabla de intenciones en orden inverso; conserva las filas de `plan` seed aunque pierdan `codigo`/`max_agents`.

En una base compartida o productiva no se ejecuta downgrade destructivo. Se deshabilita el webhook, se conserva la evidencia y se aplica un forward-fix. La aplicación anterior no debe ejecutarse contra un esquema parcialmente degradado sin verificar compatibilidad.

No se altera ninguna columna de `usuario_global` ni `sesion`; la activación no agrega FK a identidad para evitar afirmar un modelo de membership que todavía no existe.

## 9. Pruebas TDD y verificación

El modo TDD estricto exige escribir primero el contrato y los tests con dobles, luego implementar hasta verde. No se afirma ningún resultado en esta fase.

### 9.1. Casos enfocados

| Caso | Evidencia esperada | CP/REQ |
| --- | --- | --- |
| Catálogo | tres planes, nombres, `precio_bob` string exacto, BOB, cuotas y `max_agents` | CP-003.1 |
| Plan inválido/inactivo | `404`, código estable, cero escrituras | catálogo |
| Checkout válido | `201`, referencia, estado confirmado; repository no tiene tenant/suscripción/evento/invitación | CP-003.1 |
| Datos manipulados | campos extra o precio/cuota no aceptados; `422`/rechazo sin aprovisionar | CP-003.1 |
| Webhook válido | `201`, cuatro recursos, datos provenientes del checkout/plan | CP-003.2 |
| Firma ausente/inválida/alterada | `401`, cero escrituras y respuesta sin secreto/payload | CP-003.2 |
| Timestamp fuera de ventana | `401`; igualdad a 300 s válida; clave nueva no persiste | seguridad |
| Replay exacto conocido | devuelve `200` con IDs originales, incluso fuera de ventana; no notifica otra vez | CP-003.3 |
| Correlación inconsistente | `409`, ningún recurso parcial | CP-003.2 |
| Misma clave, payload distinto | `409 IDEMPOTENCY_CONFLICT`; se preserva el resultado inicial | CP-003.3 |
| Concurrencia | barrera/hilos con misma clave; una provisión y respuestas idempotentes, sin duplicados | CP-003.3 |
| Falla intermedia | fake que falla al insertar invitación/evento; rollback observable de todas las entidades | atomicidad |
| Activación emitida | hash persistido de 64 hex, token crudo solo en notifier fake, response sin token | CP-003.4 |
| Activación consumida | un consumo `200`, segundo/expirado/desconocido `410`; carrera permite uno | CP-003.4 |
| Identidad diferida | el hook nulo no crea usuario, membership ni rol; solo cambia invitación | GAP-004-DOM-001 |
| Regresión | suite completa; rutas de HU-005/HU-006 siguen registradas y sus tests existentes no cambian | límites |

La prueba de concurrencia del fake usa `RLock` y reproduce una sola transacción lógica; la verificación real de locks/constraints se hace además contra PostgreSQL cuando el entorno esté disponible. No se reemplaza la prueba de integración con una afirmación de que el fake es PostgreSQL.

### 9.2. Gates y migración

Desde la raíz se ejecutarán, sin declarar resultados por adelantado:

```text
.venv/Scripts/python.exe -m pytest backend/tests -q
.venv/Scripts/python.exe -m ruff check backend/app backend/tests
.venv/Scripts/pyright.exe backend/app backend/tests
.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head
```

La verificación de migración debe incluir al menos `upgrade 0001 → 0004`, inspección de columnas/FK/índices/planes y downgrade en una base vacía o fixture sin datos HU-004. Con datos existentes se verifica que el upgrade sea no destructivo y que el downgrade se bloquee según las condiciones anteriores. CP-003 sigue `not executed` hasta contar con evidencia real.

## 10. Rollout, rollback y observabilidad

### Rollout

1. Escribir tests de contrato/servicio y los puertos; no tocar UI ni HU-005/HU-006.
2. Implementar migración aditiva y comprobar el seed en una base vacía y una fixture con planes legados.
3. Configurar `BILLING_WEBHOOK_SECRET` fuera del repositorio; verificar que el webhook sin secreto responde `503`.
4. Ejecutar upgrade y los gates de calidad; revisar OpenAPI para confirmar las cuatro superficies HU-004.
5. Habilitar primero `GET plans` y `POST checkout` en el entorno de demo; el webhook solo acepta firmas del secreto configurado.
6. Observar conteos de conflictos, fallas de correlación, rollback y notificación, sin incluir body, token, correo completo ni secreto en logs.

Los logs pueden contener ruta, status, tipo de evento, código de resultado, `checkout_id`/`tenant_id` anonimizados y correlation id. Nunca contienen el body crudo, `payload_firmado`, firma completa, secreto, token crudo, token hash ni password.

### Rollback

- Ante defecto de verificación o provisión, deshabilitar el endpoint/webhook y conservar filas para trazabilidad.
- Revertir la versión de aplicación solo si es compatible con `0004`; no ejecutar automáticamente el downgrade.
- En producción, preferir forward-fix: la migración aditiva se conserva y los tenants ya aprovisionados no se borran.
- En una base descartable sin datos HU-004, ejecutar el downgrade guardado; si hay intenciones/eventos/consumos, el propio downgrade debe detenerse.
- Al restaurar el servicio, reprocesar eventos válidos con la misma clave; la recuperación idempotente devuelve el resultado existente sin duplicar.

## 11. Pronóstico de líneas modificadas y control de alcance

| Área | Pronóstico |
| --- | ---: |
| `models.py`, `catalog.py`, `ports.py`, `signatures.py` | 40–55 |
| `schemas.py` | 40–50 |
| `service.py` | 65–80 |
| `repository.py` | 70–85 |
| `router.py` y `core/config.py` | 35–50 |
| `0004_hu004_onboarding.py` y `alembic/env.py` | 75–90 |
| `tests/test_tenant_onboarding.py` | 140–170 |
| **Total estimado** | **465–580** |

El pronóstico queda dentro de 600 con una reserva máxima estimada de 20 líneas. Antes de `sdd-apply` se debe conservar esa reserva: reutilizar los modelos/schemas existentes, concentrar los tests de contrato en una suite, no crear endpoints de consulta adicionales y no refactorizar HU-005/HU-006. Si el desglose confirmado de tareas supera 600, es un **bloqueo de interacción de entrega**: se debe reducir el slice o aprobar una división antes de escribir código. No se incorpora una excepción automáticamente.

## 12. Trazabilidad y fuentes

| Decisión | Fuente/verificación |
| --- | --- |
| Checkout sin aprovisionamiento y webhook como frontera | Propuesta, spec `tenant-onboarding`, BR-B1, CP-003 |
| Planes, BOB y `max_agents` sin cuota del admin | Decisión aprobada de producto, propuesta y spec; BR-B3 |
| Activación de un solo uso sin contraseña | Propuesta, spec, BR-B2 |
| Separación router/service/repository, reloj y fakes | Propuesta y diseños archivados de `registro-cliente` y `autenticacion` |
| PostgreSQL/Alembic y cadena `0001`–`0003` | `project-context.md`, migraciones y `alembic/env.py` actuales |
| Identidad diferida | GAP-004-DOM-001 y alcance explícito de HU-007 |
| No UI, HU-005 ni HU-006 | Propuesta, spec, `config.yaml` y contexto aprobado |

Fuentes consultadas directamente:

- `openspec/changes/hu004-alta-inmobiliaria/proposal.md`.
- `openspec/changes/hu004-alta-inmobiliaria/specs/tenant-onboarding/spec.md`.
- `openspec/changes/hu004-alta-inmobiliaria/explore.md`.
- `openspec/project-context.md` y `openspec/config.yaml`.
- `openspec/changes/registro-cliente/design.md`.
- `openspec/changes/autenticacion/design.md`.
- `openspec/changes/prueba-hu001/design.md`.
- `backend/app/modules/tenant/{models,schemas,service,repository,router}.py` en la rama informada `feature/tenant-hu04-06`, commit `7429193`.
- `backend/app/core/{config,clock,tokens}.py`, `backend/app/main.py`, `backend/alembic/env.py`.
- `backend/alembic/versions/0001_crear_usuario_global.py`, `0002_crear_sesion.py` y `0003_crear_tablas_tenant.py`.

Este diseño no afirma que el webhook, las migraciones, CP-003 o los tests ya estén implementados o ejecutados.
