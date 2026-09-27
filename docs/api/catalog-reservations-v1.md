# Propuesta de contrato API v1: catálogo, cotizaciones y reservas

**Estado: PROPUESTA para revisión; no implementada ni aprobada como contrato final.** CC-02 define el contrato para el flujo que se distribuirá entre CC-03 y CC-09, sin agregar rutas, esquemas ni comportamientos al backend actual. Los nombres de rutas, campos, enums y errores que siguen son decisiones técnicas propuestas, salvo donde se los identifica expresamente como reglas confirmadas o hechos actuales.

## Cómo leer esta propuesta

| Etiqueta | Significado |
|---|---|
| **CONFIRMADA** | Regla de producto adoptada por el usuario en `odd/tasks/cliente-catalog.md`. |
| **HECHO ACTUAL** | Comportamiento comprobado en el backend existente, con archivo fuente. |
| **PROPUESTA** | Opción de contrato para revisar; no implica aprobación ni implementación. |
| **PENDIENTE** | Decisión que debe cerrarse antes de depender de ella en una implementación. |

Los valores `EXAMPLE_*`, `EXAMPLE-CURRENCY` y las direcciones entre corchetes son marcadores, no datos de configuración. Los ejemplos monetarios ilustran strings decimales exactos; no establecen moneda, escala ni precisión.

## 1. Alcance y límites

**PROPUESTA — Incluido:** lectura pública de publicaciones visibles, consulta de detalle, cotización calculada por el servidor, ciclo de solicitud de reserva con depósito de prueba, autorización EIP-712 del servicio y decisiones on-chain de la agencia. Se incluyen también errores, paginación y la fuente de OpenAPI esperada.

**Fuera de este documento:** implementación de backend, rutas, modelos, migraciones, contrato Solidity, SDK o UI Flutter; compra/alquiler legal, pagos completos, fondos reales y custodia de claves; definición de escena o renderer 3D. Las rutas de publicación para personal son opcionales, fuera de CC-02 y corresponden a CC-04.

**Desglose de implementación adoptado:** CC-03 implementa cuenta/sesión de cliente y vinculación/verificación de su wallet, separado de autenticación de personal; CC-04 implementa catálogo/ofertas y, si se necesita, el workflow de publicación; CC-05 implementa reservas y permisos EIP-712; CC-06 implementa escrow Solidity solo en Hardhat local; CC-07 implementa Flutter; CC-08 integra el flujo vertical de wallet; CC-09 verifica el conjunto. Todo trabajo de cadena queda limitado a Hardhat local: sin testnet ni fondos reales salvo aprobación posterior.

## 2. Reglas de producto confirmadas

- **CONFIRMADA** El catálogo público muestra únicamente inmuebles aprobados y publicados, y sus publicaciones son visibles entre agencias.
- **CONFIRMADA** Los filtros de producto incluyen ciudad/zona, operación (venta/alquiler), precio base, habitaciones y baños. La semántica precisa de “habitaciones” no está fijada.
- **CONFIRMADA** El precio base no incluye muebles opcionales. Para venta, los extras son de pago único; para alquiler, el precio base y los extras son mensuales. El servidor calcula y devuelve el desglose; ocultar un mueble en la visita 3D no modifica la oferta.
- **CONFIRMADA** La visita 3D prevista es sencilla, de un inmueble de una planta con ambientes conectados manualmente; no se promete reconstrucción fotorrealista.
- **CONFIRMADA** El cliente debe tener una cuenta RoomForge y vincularle por separado una wallet externa verificada; la wallet no reemplaza la cuenta. Para reservar se requiere el cliente RoomForge autenticado y la wallet verificada vinculada a esa cuenta. No se acepta una dirección arbitraria enviada en el body como identidad o wallet de reserva.
- **CONFIRMADA** La reserva usa una wallet externa y un token de prueba. RoomForge no custodia claves de clientes ni de agencias.
- **CONFIRMADA** El depósito es un monto fijo por inmueble, independiente del total de la oferta. La agencia dispone de 24 horas desde la creación de la solicitud en la API.
- **CONFIRMADA** Solo puede haber una reserva pendiente por inmueble. El rechazo, la cancelación mientras la reserva siga pendiente y el vencimiento reembolsan el depósito; la aceptación lo libera a la agencia.
- **CONFIRMADA** La wallet externa de agencia ejecuta en cadena tanto la aceptación como el rechazo. Una firma EIP-712 de una clave de servicio backend autoriza el deadline creado por la API antes del depósito; es una autorización separada y no sustituye la ejecución de la wallet de agencia. Esa clave no representa ni custodia wallets de cliente o agencia. El payload exacto de firma, nonce/replay, envío a cadena, timing y reconciliación de eventos siguen pendientes.
- **CONFIRMADA** La venta o el alquiler legal ocurren fuera del sistema. No se implementan pago completo, suscripciones de agencias ni fondos reales. El trabajo de cadena queda limitado a Hardhat local: no usar testnet ni fondos reales sin aprobación posterior.

Estas reglas no aprueban nombres de rutas, campos, estados de máquina ni códigos de error.

## 3. Hechos actuales del backend

| Hecho verificado | Fuente |
|---|---|
| `create_app()` construye FastAPI y registra actualmente solo los routers de identidad y agencias. La instancia se titula `RoomForge Staff API`, versión `1.0.0`. | `backend/app/main.py` |
| El router de identidad usa el prefijo `/api/v1/auth` y la etiqueta `staff-auth`; `get_active_staff` valida Bearer/JWT contra una sesión persistida y devuelve `id`, `email`, `role` y `tenant_id` del personal activo. No es autenticación de cliente. | `backend/app/modules/identity/router.py`; `backend/app/modules/identity/session.py` |
| `StaffAccount` limita los roles actuales a `platform_admin`, `agency_admin` y `agent`; los dos últimos tienen `tenant_id`, mientras que `platform_admin` no. `Agency.id` es `String(36)`. | `backend/app/modules/identity/models.py` |
| El router de agencias demuestra una autorización puntual para `platform_admin`; no establece una política genérica de autorización para catálogo o reservas. | `backend/app/modules/agencies/router.py` |
| Los errores actuales no conforman todavía un sobre común: hay respuestas `detail` de FastAPI, un manejador genérico de validación `422`, y conflictos `409` en rutas existentes. | `backend/app/main.py`; `backend/app/modules/identity/session.py`; `backend/app/modules/agencies/router.py` |
| La superficie actual de módulos Python del backend contiene `identity` y `agencies`; no hay router/módulo de catálogo, cotización, cliente o reserva en esa superficie. | `backend/app/modules/`; `backend/app/main.py` |
| FastAPI genera el OpenAPI de la aplicación a partir de la instancia y sus rutas/esquemas; no se observó un esquema propio para catálogo o reservas. | `backend/app/main.py` |

**Consecuencia:** no existe autenticación de cliente en el backend actual. CC-03 debe implementar cuenta/sesión de cliente como superficie separada de `StaffAccount` y de la autenticación de personal; esta propuesta no trata una wallet como identidad de cliente. Tampoco existen todavía los endpoints aquí descritos. Las fuentes de arriba describen solo el estado actual y no autorizan las políticas futuras.

## 4. Tabla de rutas propuesta

Todos los nombres y métodos de esta tabla son **PROPUESTA**, no rutas ya existentes. Las decisiones de autorización están desarrolladas en la sección 5.

| Método y ruta propuestos | Propósito | Acceso propuesto / pendiente |
|---|---|---|
| `POST /api/v1/customer/auth/register` | Registrar una cuenta de cliente RoomForge. | Namespace separado seleccionado por el usuario; path y schema siguen siendo **PROPUESTA** hasta implementación. |
| `POST /api/v1/customer/auth/login` | Iniciar sesión de cliente. | **PROPUESTA**; sesión separada de staff. |
| `POST /api/v1/customer/auth/refresh` | Renovar sesión de cliente. | **PROPUESTA**; access JWT de 15 min y refresh opaco rotatorio con expiración absoluta de 7 días, recuperados de PB-002 histórico. |
| `POST /api/v1/customer/auth/logout` | Cerrar sesión de cliente. | **PROPUESTA**; revocación idempotente del refresh actual. |
| `GET /api/v1/customer/auth/me` | Leer el perfil de la cuenta autenticada y validar su sesión server-side. | **PROPUESTA**; ventana de inactividad deslizante de 30 min según PB-002 histórico. |
| `POST /api/v1/customer/wallet-challenges` | Emitir desafío de prueba de control para vincular una wallet externa. | **PROPUESTA técnica para CC-03**: EIP-191 `personal_sign`, mensaje ligado a cuenta, dirección y propósito, nonce de un solo uso y TTL de 5 minutos; no requiere chainId para probar posesión. |
| `POST /api/v1/customer/wallets` | Verificar y vincular wallet a la cuenta. | **PROPUESTA**; requiere challenge EIP-191 válido; relación uno-a-varios sugerida, no regla de producto confirmada. |
| `GET /api/v1/customer/wallets` | Listar wallets verificadas de la cuenta. | **PROPUESTA**; sesión de la cuenta titular. |
| `POST /api/v1/staff/agencies/{agency_id}/wallet-challenges` | Emitir desafío para acreditar control de la wallet de agencia. | **PROPUESTA para CC-05**; `agency_admin` del tenant autenticado, rol/permisos exactos pendientes. |
| `PUT /api/v1/staff/agencies/{agency_id}/wallet` | Verificar firma y vincular wallet a la agencia. | **PROPUESTA para CC-05**; `agency_admin` del tenant + challenge válido, rol/permisos exactos pendientes. |
| `GET /api/v1/listings` | Buscar publicaciones públicas con filtros y cursor. | Público; solo publicaciones aprobadas y publicadas (**regla CONFIRMADA**). |
| `GET /api/v1/listings/{listing_id}` | Leer el detalle de una publicación pública. | Público; la visibilidad sigue la regla confirmada. |
| `POST /api/v1/quotes` | Crear una cotización calculada por el servidor para una versión de oferta y extras seleccionados. | Público con controles antiabuso/rate limit (**PROPUESTA**); no requiere identidad de wallet. |
| `POST /api/v1/reservations` | Crear una solicitud pendiente y devolver la autorización de depósito. | Requiere el cliente RoomForge autenticado y una wallet verificada vinculada (**CONFIRMADA**); el body referencia su ID opaco. El servidor obtiene la dirección verificada, nunca confía en una dirección arbitraria. |
| `GET /api/v1/reservations/{reservation_id}` | Consultar estado y snapshot de una reserva propia. | Requiere autenticación de cliente y pertenencia de la reserva a esa cuenta; diseño exacto de respuesta **PROPUESTA**. |
| `POST /api/v1/reservations/{reservation_id}/cancel` | Solicitar cancelación de una reserva aún pendiente. | Ruta candidata; actor autorizado para cancelar y autorización requerida **PENDIENTES**. |
| `POST /api/v1/agency/reservations/{reservation_id}/decision` | Ruta propuesta para registrar o reconciliar la decisión ya ejecutada en cadena por la wallet externa de agencia. | **PROPUESTA**; no sustituye la ejecución on-chain de la wallet ni constituye autorización de agencia por sí sola. La wallet ejecuta aceptación y rechazo (**CONFIRMADO**); payload, nonce/replay, envío, timing y reconciliación de eventos **PENDIENTES**. |
| `POST /api/v1/reservations/{reservation_id}/chain-transactions` | Informar un hash para reconciliar un depósito, reembolso o liberación. | Ruta opcional propuesta; el cliente no acredita el resultado. Acceso, reconciliación y confirmaciones **PENDIENTES**. |

Todas las rutas de cliente, wallet, catálogo, cotización, reserva y agencia son propuestas, no endpoints existentes. El usuario decidió preservar `/api/v1/auth/*` para personal y separar los clientes bajo `/api/v1/customer/auth/*`; la guía histórica se actualizó para no presentar `POST /api/v1/auth/register` como ruta vigente de esta base. Los nombres/campos propuestos aún se verifican al implementar, sin cambiar el router actual de staff. La respuesta pública no debe exponer publicación no visible, dirección de wallet privada ni datos de reserva ajenos.

### Rutas de publicación para personal — opcionales, fuera de alcance de CC-02 y de CC-04

**PROPUESTA opcional — fuera de alcance de CC-02; si se adopta, corresponde a CC-04:** estas rutas son candidatas para discusión, no un workflow aprobado ni un permiso asignado:

| Método y ruta candidata | Uso tentativo | Estado de alcance/autorización |
|---|---|---|
| `POST /api/v1/staff/listings` | Crear un borrador. | Opcional; fuera de CC-02; posible trabajo de CC-04. Rol exacto **PENDIENTE**. |
| `PATCH /api/v1/staff/listings/{listing_id}` | Editar un borrador. | Opcional; fuera de CC-02; posible trabajo de CC-04. Reglas de edición y rol **PENDIENTES**. |
| `POST /api/v1/staff/listings/{listing_id}/publish` | Candidata para una acción de publicación. | Solo nombre ilustrativo; ruta, estados previos, aprobación y rol **PENDIENTES** para el workflow opcional de CC-04. |

Toda futura escritura de personal deberá autenticar con `get_active_staff`, derivar el tenant del principal del servidor y aplicar autorización explícita; no aceptar un `tenant_id` del cliente como autoridad.

**PENDIENTE:** decidir en CC-04 si hace falta alguna ruta de publicación antes del panel, cuál es el ciclo editorial opcional y qué roles exactos pueden crear, editar, aprobar o publicar. El rol `platform_admin` existente no recibe por este documento permisos cross-tenant nuevos.

## 5. Autenticación y autorización

| Actor/operación | Base comprobada o propuesta | Límite explícito |
|---|---|---|
| Lectura de catálogo/detalle | Público, según la regla confirmada de catálogo público (**PROPUESTA** de transporte sin sesión). | Solo contenido aprobado y publicado. |
| Cuenta de cliente | **CONFIRMADA**: se requiere cuenta RoomForge; el usuario eligió separarla de staff bajo `/api/v1/customer/auth/*`. **PROPUESTA basada en PB-001/PB-002 históricos**: email minúsculo único, password mínimo 8 con Argon2id, correo no verificado en modo pruebas, access JWT 15 min, refresh opaco con rotación y TTL absoluto 7 días, inactividad deslizante 30 min, errores no enumerativos. | No existe autenticación de cliente en el backend actual. No reutilizar modelos/sesiones/TOTP de staff; la autenticación de cliente valida su propia audiencia y tabla de sesiones. Los paths históricos no se restauran. |
| Vincular wallet de cliente | **CONFIRMADA**: wallet externa verificada y asociada a la cuenta; la wallet no reemplaza la cuenta. **PROPUESTA técnica para CC-03**: EIP-191 `personal_sign` con challenge de un solo uso, TTL de 5 minutos, ligado a cuenta, dirección, propósito y nonce. | El chainId no se usa para probar posesión de una dirección; SDK móvil y selección/multiplicidad de wallets siguen **PENDIENTES**. |
| Crear/usar cotización | **PROPUESTA**: acceso público con límites antiabuso/rate limit. | No es una cuestión pendiente de identidad de wallet; límites concretos **PENDIENTES**. |
| Cliente crea reserva | **CONFIRMADA**: requiere cuenta RoomForge autenticada y wallet externa verificada vinculada. **PROPUESTA**: body referencia el ID de wallet vinculada. | Servidor resuelve su dirección verificada; transacción de depósito debe originarse desde esa dirección. No se acepta wallet arbitraria ni prueba cruda por solicitud. |
| Cliente consulta/cancela | La consulta de una reserva propia se asocia a la cuenta autenticada; la autorización de cancelación y su actor quedan **PENDIENTES**. | No reutilizar `get_active_staff` ni JWT/TOTP de staff, ni usar la wallet como sustituto de la cuenta. |
| Personal de una agencia | Hecho actual: Bearer de staff validado por `get_active_staff`, con rol y `tenant_id`. | La política exacta de acceso administrativo está **PENDIENTE**; no extrapolar el permiso puntual de `platform_admin` existente. |
| Vincular wallet de agencia | **PROPUESTA**: `agency_admin` acredita control mediante challenge y vincula la wallet con la agencia de su tenant. | La ruta nunca confía en una dirección del body sin firma; multiplicidad y chain siguen **PENDIENTES**. |
| Decisión de agencia (aceptar o rechazar) | **CONFIRMADA**: la wallet externa de agencia ejecuta en cadena ambas decisiones; el backend firma solamente la autorización EIP-712 separada del deadline API antes del depósito. | La API de decisión, si se implementa, solo registra/reconcilia el resultado on-chain; no sustituye la wallet ni una autorización de staff. Payload, nonce/replay, envío a cadena, timing y reconciliación de eventos **PENDIENTES**. |
| Servicio backend → escrow | **CONFIRMADA**: clave de servicio firma una autorización EIP-712 acotada; no es clave de cliente/agencia. | La clave debe configurarse fuera del repositorio y el servicio debe fallar cerrado si falta; mecanismo operativo exacto pendiente de implementación. |

## 6. Convenciones de tipos y ejemplos

### Dinero y fechas

**PROPUESTA:** representar dinero de oferta con un objeto que contiene `amount` como string decimal base diez y `currency` explícita. No usar `float`, notación exponencial ni conversiones silenciosas. No se fija código de moneda, número de decimales, escala ni regla de redondeo. Cada cálculo debe ser exacto según la política que se resuelva antes de implementar.

Ejemplo sintáctico (no configuración; la cantidad de dígitos no establece escala):

```json
{
  "amount": "1234.56789",
  "currency": "EXAMPLE-CURRENCY"
}
```

**PROPUESTA:** para depósito en token, usar una cantidad entera decimal string en unidades mínimas del token (`amount_base_units`) y separar esos datos del importe de oferta. Token, símbolo, decimales, monto, cadena y contrato quedan **PENDIENTES**; no inferirlos del precio ni usar valores reales en ejemplos.

**PROPUESTA:** serializar timestamps como RFC 3339 en UTC. `api_created_at` es el instante asignado por el backend al aceptar la solicitud de reserva; no lo envía ni lo fija Flutter.

### Búsqueda y detalle público

**PROPUESTA:** parámetros de `GET /api/v1/listings`:

| Parámetro candidato | Uso | Estado |
|---|---|---|
| `city`, `zone` | Filtros geográficos. | Filtros confirmados; codificación y normalización **PENDIENTES**. |
| `operation` | Venta o alquiler; valores de wire posibles `sale` y `rent`. | Operaciones confirmadas; strings exactos **PROPUESTA**. |
| `min_base_price`, `max_base_price`, `currency` | Rango exacto dentro de una moneda. | Filtro confirmado; parámetros y comparación inclusiva **PROPUESTA**. No convertir ni mezclar monedas. |
| `min_rooms` | Filtro de habitaciones. | Filtro confirmado; nombre y semántica habitación/dormitorio **PENDIENTES**. |
| `min_bathrooms` | Filtro de baños. | Filtro confirmado; representación y semántica de conteo **PENDIENTES**. |
| `cursor`, `limit` | Continuación paginada. | Diseño **PROPUESTA**; formato, orden, valor predeterminado y límites **PENDIENTES**. |

Ejemplo de respuesta parcial; los nombres y tipos de propiedades son **PROPUESTA** y no definen el significado de “habitación”:

```json
{
  "items": [
    {
      "listing_id": "EXAMPLE_LISTING_ID",
      "offer_version": "EXAMPLE_OFFER_VERSION",
      "operation": "EXAMPLE_OPERATION",
      "base_price": {
        "amount": "1234.56789",
        "currency": "EXAMPLE-CURRENCY"
      },
      "city": "EXAMPLE_CITY",
      "zone": "EXAMPLE_ZONE"
    }
  ],
  "next_cursor": null
}
```

No se incluye un schema de escena 3D. El mobiliario/extras puede detallarse en el recurso si la implementación lo necesita; sus precios respetan las reglas confirmadas y la cotización autoritativa. La forma de publicar esos datos queda **PENDIENTE**.

## 7. Cotización: snapshot, versión y vigencia

**PROPUESTA:** `POST /api/v1/quotes` es público y recibe identificador de publicación, versión de oferta esperada y los IDs de extras seleccionados. Debe contar con controles antiabuso/rate limit; umbrales concretos **PENDIENTES**. No exige autenticación de wallet ni recibe total calculado por el cliente.

```json
{
  "listing_id": "EXAMPLE_LISTING_ID",
  "offer_version": "EXAMPLE_OFFER_VERSION",
  "selected_extra_ids": ["EXAMPLE_EXTRA_ID"]
}
```

**PROPUESTA:** el servidor valida que la publicación siga visible, que la versión corresponda y que cada extra pertenezca a esa oferta; calcula líneas y totales con datos autoritativos y conserva un snapshot inmutable. Una versión inexistente/obsoleta o cotización vencida puede responder `409` con código estable (ver errores propuestos).

```json
{
  "quote_id": "EXAMPLE_QUOTE_ID",
  "listing_id": "EXAMPLE_LISTING_ID",
  "offer_version": "EXAMPLE_OFFER_VERSION",
  "operation": "EXAMPLE_OPERATION",
  "lines": [
    {
      "kind": "EXAMPLE_LINE_KIND",
      "extra_id": "EXAMPLE_EXTRA_ID",
      "amount": "1234.56789",
      "currency": "EXAMPLE-CURRENCY",
      "charge_period": "EXAMPLE_CHARGE_PERIOD"
    }
  ],
  "one_time_total": {
    "amount": "1234.56789",
    "currency": "EXAMPLE-CURRENCY"
  },
  "monthly_total": {
    "amount": "0",
    "currency": "EXAMPLE-CURRENCY"
  },
  "created_at": "<UTC timestamp>",
  "expires_at": "<UTC timestamp>"
}
```

Los enums `kind`, `operation` y `charge_period`, así como la forma exacta de totals, son **PROPUESTA**. El ejemplo no fija el valor cero a una escala monetaria. Los períodos deben mantener la distinción confirmada: extras de venta de pago único; base y extras de alquiler mensuales.

**PENDIENTE:** duración/TTL de cotización y política para cambiar una oferta entre cotización y reserva. `expires_at` es un campo candidato y deberá generarlo el servidor una vez definida la vigencia. El cliente no prolonga la validez ni reescribe el snapshot.

## 8. Reserva, idempotencia y concurrencia

### Creación y reloj de 24 horas

**CONFIRMADA:** la reserva requiere una cuenta RoomForge autenticada y una wallet externa verificada vinculada a esa cuenta. **PROPUESTA:** `POST /api/v1/reservations` toma `quote_id` y el ID opaco de la wallet vinculada elegida. No recibe una dirección arbitraria ni firma de wallet en cada solicitud.

```json
{
  "quote_id": "EXAMPLE_QUOTE_ID",
  "customer_wallet_id": "EXAMPLE_LINKED_WALLET_ID"
}
```

El servidor autentica la cuenta, verifica que `customer_wallet_id` le pertenece y carga su dirección verificada desde almacenamiento. El depósito on-chain debe originarse desde esa dirección; el backend valida emisor y evento del escrow contra la wallet vinculada. La firma/challenge verifica control al vincular, no sustituye sesión de cliente ni se repite como identidad en cada request. La multiplicidad y selección de wallets quedan **PENDIENTES**. La autenticación de cliente todavía no está implementada; CC-03 debe construir cuenta/sesión separada de staff. La autorización técnica del depósito y su firma EIP-712 pertenecen a CC-05; el flujo Flutter/wallet a CC-07/CC-08.

**CONFIRMADA:** el depósito es fijo por inmueble, no se deriva del total cotizado; el plazo de decisión de agencia empieza cuando la API crea la solicitud, antes de que se deposite el token.

**PROPUESTA:** en una transacción atómica, el servidor valida cotización y autorización, captura `api_created_at` con su reloj y fija `decision_deadline_at = api_created_at + 24 horas`. La respuesta devuelve ese instante y un snapshot de oferta. Una retransmisión idempotente devuelve la reserva ya creada, sin reiniciar el reloj.

```json
{
  "reservation_id": "EXAMPLE_RESERVATION_ID",
  "status": "EXAMPLE_PENDING_STATUS",
  "api_created_at": "<UTC timestamp assigned by API>",
  "decision_deadline_at": "<api_created_at plus 24 hours>",
  "quote_snapshot": {
    "quote_id": "EXAMPLE_QUOTE_ID",
    "offer_version": "EXAMPLE_OFFER_VERSION"
  },
  "deposit": {
    "amount_base_units": "<configured integer string>",
    "token_address": "<PENDING>",
    "chain_id": "<PENDING>"
  }
}
```

`status` y campos exactos son **PROPUESTA**. Los placeholders no son valores permitidos de producción. La autorización EIP-712 que devuelve el servicio se describe en la sección 9.

### Invariante de una reserva pendiente

**CONFIRMADA:** como máximo una reserva pendiente por inmueble.

**PROPUESTA de integridad:** el backend y la base de datos deben hacer cumplir la unicidad de forma atómica bajo solicitudes concurrentes, usando la identidad canónica del inmueble. La reserva pasa a ocupar el inmueble en el momento de creación API, no cuando llega un depósito on-chain. La invariante se aplica mientras haya una reserva `pending`; si el inmueble puede aceptar otra reserva después de que la actual termine —incluida una aceptación— queda **PENDIENTE** (D-18). Cómo se relacionan `listing_id` e identidad de inmueble queda **PENDIENTE** (D-19). La respuesta de conflicto candidata es `409` con `listing_has_pending_reservation`.

**PROPUESTA de idempotencia:** requerir `Idempotency-Key` en la creación; misma clave y misma cuenta de cliente/cuerpo devuelve la misma respuesta lógica, mientras que clave reutilizada con cuerpo distinto produce `409 idempotency_key_reused`. No se elige acá longitud, retención, hash del cuerpo ni política de almacenamiento de claves. El alcance y tratamiento multi-dispositivo son **PENDIENTES** de concretar.

### Estados y transiciones

Los siguientes nombres son **PROPUESTA**, no estados ya implementados ni aprobados. La regla de negocio confirmada es el resultado indicado en la segunda columna.

| Estado candidato | Transición propuesta | Regla o decisión |
|---|---|---|
| `pending` | Creación API → `pending`; puede terminar como `accepted`, `rejected`, `cancelled` o `expired`. | La creación inicia las 24 horas y ocupa el inmueble (**CONFIRMADA**). |
| `accepted` | `pending` → `accepted`; depósito liberado a wallet de agencia. | La wallet externa de agencia ejecuta la aceptación en cadena (**CONFIRMADO**); la firma EIP-712 del backend autoriza por separado el deadline creado por la API antes del depósito. Envío wallet→contrato directo es **PROPUESTA**; payload, nonce/replay, timing y reconciliación de eventos **PENDIENTES**. |
| `rejected` | `pending` → `rejected`; depósito reembolsado si fue depositado. | Rechazo y reembolso son reglas **CONFIRMADAS**; la wallet externa de agencia ejecuta el rechazo en cadena (**CONFIRMADO**). Payload, nonce/replay, envío a cadena, timing y reconciliación de eventos **PENDIENTES**. |
| `cancelled` | `pending` → `cancelled`; depósito reembolsado si fue depositado. | Cancelación mientras sigue pendiente y reembolso confirmados; actor autorizado **PENDIENTE**. |
| `expired` | `pending` → `expired` al vencer el plazo; depósito reembolsado si fue depositado. | Vencimiento y reembolso confirmados; job/instante límite y carrera con transacciones **PENDIENTES**. |

**PROPUESTA:** mantener `deposit_status` separado de `status` para distinguir decisión comercial de ejecución on-chain. Los estados de depósito (por ejemplo, no enviado, pendiente de reconciliación, confirmado, reembolso pendiente/confirmado o liberación pendiente/confirmada) son solo categorías candidatas; strings, confirmaciones y fallos finales quedan **PENDIENTES** de la integración con Solidity. No anunciar depósito como confirmado a partir de un hash informado por Flutter.

## 9. Autorizaciones EIP-712 y wallet

Hay cuatro responsabilidades distintas; no son intercambiables:

1. **Cuenta del cliente:** requisito de identidad para iniciar sesión, crear reservas y acceder a las propias. La autenticación de cliente se implementa separada de staff; no reutiliza modelos ni sesiones/TOTP de staff y valida su propia audiencia de token. Se propone adaptar a `/api/v1/customer/auth/*` las invariantes históricas PB-001/PB-002: email normalizado/único, Argon2id, access JWT de 15 min, refresh opaco rotatorio con TTL absoluto de 7 días, inactividad deslizante de 30 min y errores no enumerativos. Estos valores son una propuesta recuperada, no rutas actuales.
2. **Wallet externa del cliente:** se vincula y verifica contra la cuenta mediante challenge firmado. Para CC-03 se propone EIP-191 `personal_sign`; el mensaje de un solo uso liga cuenta, dirección, propósito y nonce, con TTL de 5 minutos. El chainId no es necesario para demostrar control de dirección. La reserva referencia el ID de wallet vinculada; el backend carga su dirección verificada y el depósito debe originarse desde ella. SDK móvil y multiplicidad/selección siguen pendientes. La wallet no reemplaza la cuenta.
3. **Clave de servicio backend:** firma solamente la autorización EIP-712 separada que vincula el depósito con el deadline creado por la API antes del depósito. No representa a ninguna wallet de cliente/agencia y no custodia fondos.
4. **Wallet externa de agencia:** ejecuta en cadena tanto la aceptación como el rechazo (**CONFIRMADO**); el backend no decide ni ejecuta esas decisiones en su nombre. Payloads, nonces/replay, envío a cadena, timing y reconciliación de eventos quedan **PENDIENTES**. La ruta API de decisión, si se conserva, solo registra/reconcilia el resultado on-chain y no sustituye la wallet ni una autorización de staff.

**PROPUESTA de campos mínimos para el permiso de servicio**, derivados del alcance confirmado en `odd/tasks/cliente-catalog.md`; los tipos EIP-712 y nombres finales aún deben acordarse:

| Campo candidato | Propósito | Estado |
|---|---|---|
| Dominio `name`, `version`, `chainId`, `verifyingContract` | Delimitar contrato y red. | EIP-712 propuesto; todos los valores **PENDIENTES**. |
| `reservationId`, `quoteId` o `quoteHash` | Enlazar solicitud y snapshot cotizado. | Campos mínimos confirmados conceptualmente; forma/hash canónico **PENDIENTE**. |
| `customerWallet`, `listingId`, `offerVersion` | Enlazar la wallet verificada del cliente autenticado, el inmueble y la versión comercial. | Confirmados conceptualmente; `customerWallet` siempre corresponde a la cuenta RoomForge autenticada, no es una identidad independiente; tipos/nombres **PROPUESTA**. |
| `token`, `depositAmount` | Autorizar depósito fijo en unidades mínimas del token configurado. | Requisito confirmado; token/monto/decimales **PENDIENTES**. |
| `apiCreatedAt`, `expiresAt` | Probar el instante API previo al depósito y el límite asociado. | Requisito confirmado; tipos y semántica exacta del límite **PENDIENTES**. |
| `nonce` | Evitar repetición del permiso. | Requisito confirmado; generación/consumo y almacenamiento **PENDIENTES**. |

**PROPUESTA de seguridad:** firma solo en backend con clave de servicio leída de configuración secreta y nunca persistida en Git; fallar cerrado si la clave o la configuración necesaria faltan. El contrato valida dominio/red, permiso, nonce y vencimiento y lo consume una sola vez. No se fijan aquí algoritmo de hash, nombre/tipos Solidity, `chainId`, direcciones ni ventana de ejecución.

La wallet externa de agencia ejecuta en cadena la aceptación y el rechazo. La ruta API de decisión, si se conserva, sirve para registrar o reconciliar la decisión on-chain; no sustituye la ejecución de la wallet ni una autorización de staff. **PROPUESTA técnica:** que la wallet envíe la decisión directamente al contrato y que el backend reconcilie el evento. El payload exacto, nonces/replay, mecanismo de envío, timing, relayer/gas y reconciliación quedan **PENDIENTES**.

## 10. Errores y paginación

### Sobre común propuesto

El backend actual no usa este formato de manera uniforme. **PROPUESTA:** adoptar para las nuevas rutas una respuesta JSON estable, sin filtrar detalles internos:

```json
{
  "code": "EXAMPLE_ERROR_CODE",
  "message": "Descripción legible para personas",
  "request_id": "<request identifier>",
  "field_errors": []
}
```

Los nombres y `request_id` son **PROPUESTA**; `field_errors` puede omitirse cuando no aplica. No se prescribe todavía un estándar externo de media type. Mantener HTTP status semánticamente coherente y documentar respuestas en OpenAPI.

| HTTP candidato | Ejemplos de código candidato | Motivo general |
|---|---|---|
| `400` | `invalid_cursor`, `invalid_request` | Sintaxis de cursor/solicitud inválida. |
| `401` | `customer_authentication_required`, `customer_authentication_invalid` | Sesión de cuenta de cliente requerida o inválida; autenticación aún no implementada. |
| `403` | `customer_wallet_not_verified` | La cuenta autenticada no tiene una wallet vinculada y verificada cuando la operación la requiere. |
| `403` | `staff_role_required`, `tenant_access_denied` | Personal autenticado sin autorización. Política final pendiente. |
| `404` | `listing_not_found`, `reservation_not_found` | Recurso inexistente o no visible para quien consulta. |
| `409` | `listing_has_pending_reservation`, `offer_version_mismatch`, `quote_expired`, `reservation_not_pending`, `idempotency_key_reused` | Conflicto de estado, versión o idempotencia. |
| `422` | `invalid_amount_format`, `invalid_filter`, `invalid_signature` | Contenido semánticamente inválido. |
| `503` | `quote_configuration_unavailable`, `signature_service_unavailable` | Dependencia/configuración no disponible; fallo cerrado para escritura. |

Los códigos exactos y asignaciones HTTP son **PROPUESTA**. No copiar el formato `detail` existente como si ya fuera el contrato de estos endpoints.

### Paginación propuesta

Usar `cursor` opaco y `next_cursor` nullable como mecanismo candidato para `GET /api/v1/listings`, con filtros preservados entre páginas y orden estable definido por implementación. `limit` es un parámetro candidato con validación positiva; valor por defecto, máximo, política de orden, cursor expirado y respuesta vacía están **PENDIENTES**. No se fija ningún número de límite en esta propuesta.

## 11. OpenAPI reproducible desde FastAPI

**HECHO ACTUAL:** `backend/app/main.py:create_app()` crea la instancia FastAPI e incluye routers; no configura un documento OpenAPI manual para estos recursos.

**PROPUESTA para CC-03–CC-05:** definir rutas de cuenta/sesión (CC-03), catálogo/ofertas (CC-04) y reservas (CC-05) con modelos de request/response y estados de respuesta tipados en los módulos FastAPI; incluir esos routers desde `create_app()` y dejar que `app.openapi()` genere el documento, disponible en la ruta OpenAPI estándar de FastAPI salvo que una decisión explícita la cambie. Las rutas administrativas opcionales de publicación corresponden a CC-04. No editar a mano una copia JSON/YAML como fuente canónica.

**Reproducibilidad propuesta:** desde el entorno/backend fijado del proyecto, construir la misma `app` con la configuración de test segura, serializar su `app.openapi()` y verificar en pruebas posteriores los paths, métodos, schemas y respuestas documentados. Esa es una validación de implementación futura, no ejecutada por CC-02. No exponer secretos en schemas ni requerir wallet real para generar OpenAPI.

## 12. Registro de decisiones pendientes

| ID | Decisión pendiente | No asumir |
|---|---|---|
| D-01 | Moneda(s), precisión/escala y redondeo de importes. | Código de moneda, decimales fijos o conversión. |
| D-02 | Duración de vigencia de cotización y qué cambio de oferta invalida una quote. | TTL/default o vigencia ilimitada. |
| D-03 | Monto fijo del depósito por inmueble. | Valor derivado del precio o un monto de ejemplo. |
| D-04 | Token de prueba: símbolo, decimales, supply y direcciones; `chainId`, contrato y RPC local de Hardhat. | Testnet o fondos reales sin aprobación posterior; tokens, cadena o despliegues de producción. |
| D-05 | SDK/proveedor de wallet móvil y configuración pública. | SDK o project ID. No guardar secretos/configuración privada en Git. |
| D-06 | Para wallet de cliente, CC-03 propone EIP-191 `personal_sign` con nonce de un solo uso ligado a cuenta, dirección y propósito, con TTL de 5 minutos. Siguen pendientes el SDK móvil y la multiplicidad/selección; también el protocolo de prueba para vincular wallet de agencia. | Que la wallet reemplace la cuenta, que una dirección enviada en el body pruebe control o que la prueba de identidad requiera una cadena no elegida. |
| D-07 | Exactos roles y autorizaciones para publicación opcional y operaciones administrativas no decisorias sobre reservas. | Que un rol actual tenga permisos nuevos por inferencia o que la staff API baste para aceptar. |
| D-08 | Actor autorizado a cancelar una reserva pendiente y autorización requerida para esa cancelación. | Un actor o mecanismo de cancelación aprobado sin decisión explícita. |
| D-09 | Semántica del filtro “habitaciones” frente a dormitorios y representación del conteo de baños. | Que habitación equivalga a dormitorio o que baños admitan fracciones/enteros concretos. |
| D-10 | Schema de escena 3D, ambientes, conexiones y renderer. | Payload, geometría o formato de reconstrucción. |
| D-11 | Campos de sesión de cliente, TTL, refresh y revocación; rate controls para la ruta pública de cotización propuesta; titularidad de cotizaciones si se necesita consultar historial. | Que la wallet sustituya a la cuenta. La cuenta para reservar y la wallet vinculada/verificada son reglas confirmadas; el acceso público a quote es una propuesta técnica. |
| D-12 | Nombres y schemas finales de rutas, enums, errores, respuestas y versionado. | Que los nombres propuestos ya estén aprobados. |
| D-13 | Cursor, orden, default/máximo de página y límites de filtros. | Cualquier límite numérico. |
| D-14 | Idempotency-Key: scope, duración, digest y concurrencia entre dispositivos. | Una política temporal o de almacenamiento no acordada. |
| D-15 | Qué instante determina aceptación antes del deadline cuando API y cadena difieren; expiración, transacciones en vuelo, confirmaciones, reorgs y reconciliación. | Que hora de envío, hora de bloque o primera confirmación sea el criterio acordado. |
| D-16 | Dominio EIP-712 final, hash canónico de snapshot, ABI/eventos, gas payer y semántica de escrow. | Tipos Solidity, nombres de eventos, contrato ni configuración de red. |
| D-17 | Si CC-04 necesita rutas para publicación antes del panel y cuál será el workflow opcional de aprobación/publicación. | Que haya un workflow o rutas administrativas aprobadas. |
| D-18 | Disponibilidad de un inmueble después de una reserva aceptada y si puede iniciar otra reserva pendiente. | Que salir del estado `pending` vuelva automáticamente disponible la publicación. |
| D-19 | Identidad canónica del inmueble y su relación con el recurso público `listing_id` para aplicar unicidad. | Que cada publicación y cada inmueble sean necesariamente la misma entidad. |
| D-20 | Campos, schemas, expiración/refresh y revocación de sesión de cliente; los paths quedan propuestos bajo `/api/v1/customer/auth/*` por decisión del usuario. | Que esas rutas propuestas ya existan o que `/api/v1/auth` actual deje de ser staff-only. |

## 13. Criterio de salida de CC-02

Este artefacto entrega una propuesta para revisar; no afirma que la API esté implementada. La modalidad de identidad para reservar está **CONFIRMADA**: cuenta RoomForge autenticada más wallet externa vinculada y verificada; la wallet no la reemplaza. El namespace separado `/api/v1/customer/auth/*` fue elegido por el usuario; `/api/v1/auth/*` de personal se preserva. Antes de CC-03–CC-05, cerrar schemas/TTL/refresh de sesión, protocolo/multiplicidad de wallets, rate controls para quote público, permisos administrativos, versión/vigencia de quote, valores económicos/de red y carrera del deadline. CC-06 y CC-08 deben mantener el límite de Hardhat local: sin testnet ni fondos reales sin aprobación posterior. Las decisiones marcadas **PENDIENTE** no deben convertirse en defaults silenciosos; las etiquetas **PROPUESTA** requieren resolución por el trabajo antes de tratarlas como contrato.

## Key Learnings

1. La sesión de cliente y la sesión de personal deben permanecer separadas.
2. La wallet verificada se vincula a una cuenta RoomForge y no la reemplaza.
3. El depósito fijo necesita una autorización EIP-712 independiente de la aceptación de agencia.
