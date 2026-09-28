# Propuesta de contrato API v1: catálogo, cotizaciones y reservas

**Estado: PROPUESTA para revisión; no es un contrato final ni acredita despliegue.** El contrato de catálogo, cotizaciones y reservas sigue propuesto. Las rutas de cuenta/sesión de cliente (CC-03A) y wallet (CC-03B) están implementadas en esta rama, sin que eso apruebe el contrato general ni implique despliegue. CC-02 define la propuesta para el flujo restante; los nombres de rutas, campos, enums y errores siguen siendo propuestas salvo donde se los identifica expresamente como reglas confirmadas, hechos actuales o comportamiento implementado en esta rama.

## Cómo leer esta propuesta

| Etiqueta | Significado |
|---|---|
| **CONFIRMADA** | Regla de producto adoptada por el usuario en `odd/tasks/cliente-catalog.md`. |
| **HECHO ACTUAL — BASE `b6a468a`** | Comportamiento comprobado en los archivos fuente de esa revisión exacta; no describe el worktree actual ni acredita despliegue. |
| **IMPLEMENTADO EN ESTA RAMA** | Comportamiento presente en el worktree actual; no implica despliegue ni aprobación global del contrato. |
| **PROPUESTA** | Opción de contrato para revisar; no implica aprobación ni implementación. |
| **PENDIENTE** | Decisión que debe cerrarse antes de depender de ella en una implementación. |

Los valores `EXAMPLE_*` y las direcciones entre corchetes son marcadores, no datos de configuración. Los ejemplos de ofertas usan COP con dos decimales según la decisión confirmada para esta rama; los importes de depósito en token tienen unidades separadas y pendientes.

## 1. Alcance y límites

**PROPUESTA — Incluido:** lectura pública de publicaciones visibles, consulta de detalle, cotización calculada por el servidor, ciclo de solicitud de reserva con depósito de prueba, autorización EIP-712 del servicio y decisiones on-chain de la agencia. Se incluyen también errores, paginación y la fuente de OpenAPI esperada.

**Fuera de este documento:** implementación de backend, rutas, modelos, migraciones, contrato Solidity, SDK o UI Flutter; compra/alquiler legal, pagos completos, fondos reales y custodia de claves; definición de escena o renderer 3D. Las rutas de publicación para personal son opcionales, fuera de CC-02 y corresponden a CC-04.

**Desglose de trabajo:** CC-03A (cuenta/sesión), CC-03B (vinculación/verificación de wallet), CC-04A/B (catálogo y cotizaciones) y CC-05A/B (wallet/deposito de agencia y ciclo persistido de reserva) están implementados en esta rama, separados de la autenticación de personal. CC-05C (permisos EIP-712 y reconciliación), CC-06 (escrow Solidity en Hardhat local), CC-07 (Flutter), CC-08 (integración vertical de wallet) y CC-09 (verificación integrada) siguen pendientes. El contrato API completo de este documento continúa en estado **PROPUESTA**, sin aprobación global ni afirmación de despliegue. Todo trabajo de cadena queda limitado a Hardhat local: sin testnet ni fondos reales salvo aprobación posterior.

## 2. Reglas de producto confirmadas

- **CONFIRMADA** El catálogo público muestra únicamente inmuebles aprobados y publicados, y sus publicaciones son visibles entre agencias.
- **CONFIRMADA** Los filtros de producto incluyen ciudad/zona, operación (venta/alquiler), precio base, habitaciones y baños. Para esta rama, `min_rooms` cuenta dormitorios y `min_bathrooms` es un mínimo entero.
- **CONFIRMADA** Los importes de oferta se expresan en COP con dos decimales y aritmética `Decimal` exacta; los totales calculados usan `ROUND_HALF_UP`. La precisión `NUMERIC(18,2)` es un límite técnico de esta implementación, no una regla de producto.
- **CONFIRMADA para CC-04B** La cotización pública usa `POST /api/v1/quotes`, no requiere sesión ni wallet y crea un ID/snapshot nuevo en cada POST, incluso ante reintentos. `offer_version` es un entero y debe coincidir con la oferta actual; el snapshot vence exactamente a los 15 minutos y una actualización de versión lo invalida para uso futuro.
- **DECISIÓN DE ESTA RAMA — CC-04B** El límite es **10 solicitudes por IP cada minuto** en ventana móvil de 60 segundos. Se usa la IP directa del peer HTTP (no `X-Forwarded-For` sin configuración confiable) y se guarda solamente una clave HMAC; un despliegue detrás de proxy debe proporcionar un peer IP confiable.
- **CONFIRMADA** El precio base no incluye muebles opcionales. Para venta, los extras son de pago único; para alquiler, el precio base y los extras son mensuales. El servidor calcula y devuelve el desglose; ocultar un mueble en la visita 3D no modifica la oferta.
- **CONFIRMADA** Todo cambio de precio base, extras o condiciones comerciales incrementa `offer_version`; cotizaciones de versiones anteriores quedan invalidadas. La cotización inmutable y su TTL de 15 minutos pertenecen a CC-04B.
- **CONFIRMADA para la respuesta de detalle público** Incluir únicamente ID de publicación, versión de oferta, operación, precio base COP, ciudad/zona visibles, cantidades de dormitorios/baños y extras con ID estable, nombre visible y precio. Excluir descripción, fotos y dirección exacta.
- **CONFIRMADA** La visita 3D prevista es sencilla, de un inmueble de una planta con ambientes conectados manualmente; no se promete reconstrucción fotorrealista.
- **CONFIRMADA** El cliente debe tener una cuenta RoomForge y vincularle por separado una wallet externa verificada; la wallet no reemplaza la cuenta. Para reservar se requiere el cliente RoomForge autenticado y la wallet verificada vinculada a esa cuenta. No se acepta una dirección arbitraria enviada en el body como identidad o wallet de reserva.
- **CONFIRMADA para CC-03B** Cada cuenta puede vincular como máximo una wallet externa y cada dirección canonicalizada puede pertenecer a una sola cuenta en todo el sistema. La verificación usa EIP-191 `personal_sign`; cualquier firma inválida, incluso malformada, consume el challenge antes de responder con un error genérico. Challenge expirado o repetido falla cerrado. No se incluyen endpoints para desvincular o reemplazar la wallet ni se revela qué otra cuenta pudiera poseer una dirección.
- **CONFIRMADA** La reserva usa una wallet externa y un token de prueba. RoomForge no custodia claves de clientes ni de agencias.
- **CONFIRMADA** El depósito es un monto fijo por inmueble, independiente del total de la oferta. La agencia dispone de 24 horas desde la creación de la solicitud en la API.
- **CONFIRMADA** Solo puede haber una reserva pendiente por inmueble. El rechazo, la cancelación mientras la reserva siga pendiente y el vencimiento reembolsan el depósito; la aceptación lo libera a la agencia.
- **CONFIRMADA** La wallet externa de agencia ejecuta en cadena tanto la aceptación como el rechazo. Una firma EIP-712 de una clave de servicio backend autoriza el deadline creado por la API antes del depósito; es una autorización separada y no sustituye la ejecución de la wallet de agencia. Esa clave no representa ni custodia wallets de cliente o agencia. El payload exacto de firma, nonce/replay, envío a cadena, timing y reconciliación de eventos siguen pendientes.
- **CONFIRMADA** La venta o el alquiler legal ocurren fuera del sistema. No se implementan pago completo, suscripciones de agencias ni fondos reales. El trabajo de cadena queda limitado a Hardhat local: no usar testnet ni fondos reales sin aprobación posterior.

Estas reglas no aprueban nombres de rutas, campos, estados de máquina ni códigos de error.

## 3. Hechos del backend base y comportamiento de esta rama

### HECHO ACTUAL — BASE `b6a468a`

Los hechos de esta subsección se verificaron en los archivos versionados en el commit `b6a468a`. Describen esa revisión base, no el worktree actual, y no acreditan despliegue.

| Hecho verificado en `b6a468a` | Fuente en esa revisión |
|---|---|
| `create_app()` construye FastAPI, con título `RoomForge Staff API` y versión `1.0.0`, y registra únicamente los routers de identidad de personal y agencias. | `backend/app/main.py` |
| El router de identidad usa el prefijo `/api/v1/auth` y la etiqueta `staff-auth`; `get_active_staff` valida Bearer/JWT contra una sesión persistida y devuelve `id`, `email`, `role` y `tenant_id` del personal activo. No es autenticación de cliente. | `backend/app/modules/identity/router.py`; `backend/app/modules/identity/session.py` |
| `StaffAccount` limita los roles a `platform_admin`, `agency_admin` y `agent`; los dos últimos tienen `tenant_id`, mientras que `platform_admin` no. `Agency.id` es `String(36)`. | `backend/app/modules/identity/models.py` |
| El router de agencias aplica una autorización puntual para `platform_admin`; no establece una política genérica de autorización para catálogo o reservas. | `backend/app/modules/agencies/router.py` |
| Los errores no conforman un sobre común: hay respuestas `detail` de FastAPI, un manejador genérico de validación `422` y conflictos `409` en rutas existentes. | `backend/app/main.py`; `backend/app/modules/identity/session.py`; `backend/app/modules/agencies/router.py` |
| El árbol ejecutable de módulos contiene `identity` y `agencies`; no contiene `customer_identity`, ni módulos de catálogo/listings, cotización o reservas. `create_app()` tampoco registra routers de esos recursos. Por lo tanto, en esta base no hay rutas de cuenta/wallet de clientes, catálogo, cotización ni reservas. | `backend/app/modules/`; `backend/app/main.py` |
| La aplicación usa el OpenAPI generado por FastAPI a partir de sus rutas y esquemas; en esta base no hay rutas ni esquemas propios para catálogo o reservas ni una definición OpenAPI manual para esos recursos. | `backend/app/main.py` |

### IMPLEMENTADO EN ESTA RAMA — CC-03A/CC-03B/CC-04A/CC-04B/CC-05B

En el worktree actual, CC-03A implementa rutas y modelos de cuenta/sesión de cliente, CC-03B implementa rutas y modelos de vinculación de wallet, CC-04A implementa lectura pública de catálogo y persistencia de publicaciones/ofertas, CC-04B implementa creación pública de snapshots de cotización y su control de frecuencia, y CC-05B implementa creación, lectura y listado de reservas propias. Las identidades de cliente permanecen separadas de `StaffAccount` y de la autenticación de personal. `create_app()` registra sus routers desde `backend/app/modules/customer_identity/`, `backend/app/modules/catalog/` y `backend/app/modules/reservations/`; las rutas se detallan en la sección 4. Este comportamiento de rama no implica despliegue ni aprobación global del contrato.

**Alcance restante:** CC-05C/CC-06 incluyen las transiciones terminales basadas en eventos on-chain, cancelación, decisiones de agencia, reconciliación de eventos/recibos, autorización EIP-712 y contrato escrow. La implementación CC-05B no convierte esta propuesta general en un contrato aprobado ni autoriza testnet o fondos reales.

## 4. Tabla de rutas propuesta

Los nombres y métodos de esta tabla son **PROPUESTA** como contrato general. Las rutas de cuenta/sesión y wallet de CC-03 ya están implementadas, pero su presencia no cambia el estado de propuesta de este documento. Las decisiones de autorización están desarrolladas en la sección 5.

| Método y ruta propuestos | Propósito | Acceso propuesto / pendiente |
|---|---|---|
| `POST /api/v1/customer/auth/register` | Registrar una cuenta de cliente RoomForge. | **IMPLEMENTADO EN ESTA RAMA, CC-03A**; path y schema existen aquí. El contrato general sigue en propuesta. |
| `POST /api/v1/customer/auth/login` | Iniciar sesión de cliente. | **IMPLEMENTADO EN ESTA RAMA, CC-03A**; sesión separada de staff. |
| `POST /api/v1/customer/auth/refresh` | Renovar sesión de cliente. | **IMPLEMENTADO EN ESTA RAMA, CC-03A**; access JWT de 15 min y refresh opaco rotatorio con expiración absoluta de 7 días. |
| `POST /api/v1/customer/auth/logout` | Cerrar sesión de cliente. | **IMPLEMENTADO EN ESTA RAMA, CC-03A**; revocación idempotente del refresh actual. |
| `GET /api/v1/customer/auth/me` | Leer el perfil de la cuenta autenticada y validar su sesión server-side. | **IMPLEMENTADO EN ESTA RAMA, CC-03A**; ventana de inactividad deslizante de 30 min. |
| `POST /api/v1/customer/wallet-challenges` | Emitir desafío de prueba de control para vincular una wallet externa. | **IMPLEMENTADO EN ESTA RAMA, CC-03B**: EIP-191 `personal_sign`; mensaje exacto ligado a cuenta, dirección canonicalizada y propósito fijo; nonce criptográfico de un solo uso y TTL de 5 minutos. No requiere chainId para probar posesión. |
| `POST /api/v1/customer/wallets` | Verificar y vincular wallet a la cuenta. | **IMPLEMENTADO EN ESTA RAMA, CC-03B**: como máximo una wallet por cuenta y dirección globalmente única (**CONFIRMADO**); firma inválida consume el challenge y falla genéricamente; no hay unlink ni reemplazo. |
| `GET /api/v1/customer/wallets` | Listar wallets verificadas de la cuenta. | **IMPLEMENTADO EN ESTA RAMA, CC-03B**; requiere sesión de la cuenta titular y devuelve cero o una wallet. |
| `POST /api/v1/staff/agencies/{agency_id}/wallet-challenges` | Emitir un desafío de cinco minutos para acreditar control de la wallet de agencia. | **PROPUESTA de contrato; decisión CONFIRMADA para CC-05A e IMPLEMENTADA EN ESTA RAMA**: solo `agency_admin` del mismo tenant; EIP-191 de un solo uso; dirección globalmente única; no se permite reemplazar ni desvincular. |
| `PUT /api/v1/staff/agencies/{agency_id}/wallet` | Verificar firma y vincular wallet a la agencia. | **PROPUESTA de contrato; decisión CONFIRMADA para CC-05A e IMPLEMENTADA EN ESTA RAMA**: challenge consumido antes de recuperar firma; errores de prueba inválida genéricos; no se revela la agencia que pudiera tener una dirección duplicada. |
| `PATCH /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/deposit` | Configurar el depósito fijo de una publicación existente. | **PROPUESTA de ruta; regla CONFIRMADA para CC-05A e IMPLEMENTADA EN ESTA RAMA**: solo `agency_admin` del mismo tenant; monto positivo COP con dos decimales; solo cambia este campo y avanza `offer_version`; no crea, edita, aprueba ni publica publicaciones. |
| `GET /api/v1/listings` | Buscar publicaciones públicas con filtros y cursor. | **IMPLEMENTADO EN ESTA RAMA, CC-04A**; público, solo publicaciones aprobadas y publicadas (**regla CONFIRMADA**). La forma global del contrato sigue propuesta. |
| `GET /api/v1/listings/{listing_id}` | Leer el detalle mínimo de una publicación pública. | **IMPLEMENTADO EN ESTA RAMA, CC-04A**; público y con la visibilidad confirmada. La forma global del contrato sigue propuesta. |
| `POST /api/v1/quotes` | Crear una cotización calculada por el servidor para una versión de oferta y extras seleccionados. | **IMPLEMENTADO EN ESTA RAMA, CC-04B**: público, sin cuenta/wallet, 10 solicitudes por IP cada minuto; cada POST crea un snapshot nuevo. La aceptación global del contrato sigue en propuesta. |
| `POST /api/v1/reservations` | Crear una solicitud pendiente y devolver el snapshot de la reserva. | **PROPUESTA de contrato; implementado en esta rama, CC-05B.** Requiere sesión de cliente, wallet de cliente vinculada y wallet vinculada a la misma agencia. El body referencia `listing_id`, `quote_id` y el ID opaco de wallet; `Idempotency-Key` es obligatorio. El servidor obtiene las direcciones verificadas, nunca confía en direcciones arbitrarias. |
| `GET /api/v1/reservations` | Listar las reservas del cliente autenticado. | **PROPUESTA de ruta; implementada en esta rama, CC-05B.** Devuelve únicamente reservas de la cuenta autenticada. |
| `GET /api/v1/reservations/{reservation_id}` | Consultar estado y snapshot de una reserva propia. | **PROPUESTA de contrato; implementada en esta rama, CC-05B.** Una reserva ajena se trata como no encontrada. |
| `POST /api/v1/reservations/{reservation_id}/cancel` | Solicitar cancelación de una reserva aún pendiente. | Ruta candidata; actor autorizado para cancelar y autorización requerida **PENDIENTES**. |
| `POST /api/v1/agency/reservations/{reservation_id}/decision` | Ruta propuesta para registrar o reconciliar la decisión ya ejecutada en cadena por la wallet externa de agencia. | **PROPUESTA**; no sustituye la ejecución on-chain de la wallet ni constituye autorización de agencia por sí sola. La wallet ejecuta aceptación y rechazo (**CONFIRMADO**); payload, nonce/replay, envío, timing y reconciliación de eventos **PENDIENTES**. |
| `POST /api/v1/reservations/{reservation_id}/chain-transactions` | Informar un hash para reconciliar un depósito, reembolso o liberación. | Ruta opcional propuesta; el cliente no acredita el resultado. Acceso, reconciliación y confirmaciones **PENDIENTES**. |

En esta rama CC-04A implementa las dos rutas públicas de catálogo/listings y sus schemas, CC-04B implementa `POST /api/v1/quotes` con snapshot y rate limit, CC-05A implementa el challenge/vinculación de wallet de agencia y la configuración admin-only del depósito, y CC-05B implementa creación, lectura y listado de reservas propias. Las decisiones de agencia, cancelación, reconciliación de eventos y transiciones terminales basadas en cadena quedan fuera de CC-05B. Las rutas y schemas de cuenta/sesión de cliente y las tres rutas de wallet también están implementadas en esta rama; preservan `/api/v1/auth/*` para personal y usan `/api/v1/customer/*` para clientes. Su presencia no aprueba el contrato general ni cambia el router de staff. La configuración de depósito no crea, edita, aprueba ni publica listings. Las rutas de reservas no exponen direcciones de wallet ni datos de reservas ajenas.

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
| Cuenta de cliente | **CONFIRMADA**: se requiere cuenta RoomForge; el usuario eligió separarla de staff bajo `/api/v1/customer/auth/*`. **IMPLEMENTADO EN ESTA RAMA, CC-03A**: registro/login, email normalizado y único, Argon2id, access JWT de 15 min, refresh opaco con rotación y TTL absoluto de 7 días, inactividad deslizante de 30 min y errores no enumerativos. | Las rutas/schemas y la sesión de cliente existen en esta rama; esto no constituye aprobación global del contrato ni despliegue. No reutilizar modelos/sesiones/TOTP de staff; la autenticación de cliente valida su propia audiencia y tabla de sesiones. Los paths históricos no se restauran. |
| Vincular wallet de cliente | **CONFIRMADA**: wallet externa verificada y asociada a la cuenta; una por cuenta y dirección globalmente única; la wallet no reemplaza la cuenta. **IMPLEMENTADO EN ESTA RAMA, CC-03B**: EIP-191 `personal_sign` con challenge de un solo uso ligado a cuenta, dirección canonicalizada, propósito fijo, nonce criptográfico y timestamps UTC; TTL de 5 minutos; firma inválida consume el challenge antes de responder genéricamente; sin unlink ni reemplazo. | El chainId no se usa para probar posesión de una dirección; el SDK móvil sigue **PENDIENTE**. |
| Crear/usar cotización | **IMPLEMENTADO EN ESTA RAMA, CC-04B**: `POST /api/v1/quotes` es público, no requiere cuenta/wallet ni idempotencia; cada POST crea una cotización nueva. | Rate limit de rama: **10 solicitudes por IP cada minuto**, ventana móvil; IP directa de `request.client.host`, sin confiar en headers reenviados no configurados. No se agrega consulta/edición/borrado de cotización. El contrato global sigue en propuesta. |
| Cliente crea reserva | **CONFIRMADA**: requiere cuenta RoomForge autenticada y wallet externa verificada vinculada. **PROPUESTA**: body referencia el ID de wallet vinculada. | Servidor resuelve su dirección verificada; transacción de depósito debe originarse desde esa dirección. No se acepta wallet arbitraria ni prueba cruda por solicitud. |
| Cliente consulta/cancela | La consulta de una reserva propia se asocia a la cuenta autenticada; la autorización de cancelación y su actor quedan **PENDIENTES**. | No reutilizar `get_active_staff` ni JWT/TOTP de staff, ni usar la wallet como sustituto de la cuenta. |
| Personal de una agencia | **HECHO ACTUAL — BASE `b6a468a`**: Bearer de staff validado por `get_active_staff`, con rol y `tenant_id`. | La política exacta de acceso administrativo está **PENDIENTE**; no extrapolar el permiso puntual de `platform_admin` existente. |
| Vincular wallet de agencia | **PROPUESTA**: `agency_admin` acredita control mediante challenge y vincula la wallet con la agencia de su tenant. | La ruta nunca confía en una dirección del body sin firma; multiplicidad y chain siguen **PENDIENTES**. |
| Decisión de agencia (aceptar o rechazar) | **CONFIRMADA**: la wallet externa de agencia ejecuta en cadena ambas decisiones; el backend firma solamente la autorización EIP-712 separada del deadline API antes del depósito. | La API de decisión, si se implementa, solo registra/reconcilia el resultado on-chain; no sustituye la wallet ni una autorización de staff. Payload, nonce/replay, envío a cadena, timing y reconciliación de eventos **PENDIENTES**. |
| Servicio backend → escrow | **CONFIRMADA**: clave de servicio firma una autorización EIP-712 acotada; no es clave de cliente/agencia. | La clave debe configurarse fuera del repositorio y el servicio debe fallar cerrado si falta; mecanismo operativo exacto pendiente de implementación. |

## 6. Convenciones de tipos y ejemplos

### Dinero y fechas

**CONFIRMADA para esta rama; pendiente de revisión global del contrato:** representar dinero de oferta con `amount` como string decimal base diez y `currency: "COP"`; usar aritmética `Decimal` exacta, dos decimales y `ROUND_HALF_UP` para totales calculados. No usar `float` ni conversiones silenciosas. **PROPUESTA TÉCNICA CC-04A:** persistir en `NUMERIC(18,2)` (hasta 16 dígitos enteros); ese límite de almacenamiento no es una regla de producto.

```json
{
  "amount": "1234.50",
  "currency": "COP"
}
```

**PROPUESTA:** para depósito en token, usar una cantidad entera decimal string en unidades mínimas del token (`amount_base_units`) y separar esos datos del importe de oferta. Token, símbolo, decimales, monto, cadena y contrato quedan **PENDIENTES**; no inferirlos del precio ni usar valores reales en ejemplos. Para visualización de pruebas locales únicamente, se usa la relación `1 COP = 1` unidad de test-token mostrada; es una convención de display y **no** representa paridad ni conversión del mundo real.

**PROPUESTA:** serializar timestamps como RFC 3339 en UTC. `api_created_at` es el instante asignado por el backend al aceptar la solicitud de reserva; no lo envía ni lo fija Flutter.

### Búsqueda y detalle público

**PROPUESTA:** parámetros de `GET /api/v1/listings`:

| Parámetro candidato | Uso | Estado |
|---|---|---|
| `city`, `zone` | Filtros geográficos. | Parámetros **PROPUESTA**, implementados con igualdad exacta sobre claves `strip().casefold()`; se conserva la escritura visible. |
| `operation` | Venta o alquiler; valores de wire `sale` y `rent`. | Semántica confirmada; strings exactos **PROPUESTA**, implementados en esta rama. |
| `min_base_price`, `max_base_price` | Rango inclusivo del precio COP. | Filtro confirmado; parámetros **PROPUESTA**, límite y comparación inclusiva implementados en esta rama. |
| `min_rooms` | Mínimo de dormitorios. | Semántica confirmada; nombre **PROPUESTA**, conteo entero implementado en esta rama. |
| `min_bathrooms` | Mínimo entero de baños. | Semántica confirmada; nombre **PROPUESTA**, filtro entero implementado en esta rama. |
| `cursor`, `limit` | Continuación paginada. | **PROPUESTA TÉCNICA CC-04A:** cursor opaco por `created_at DESC, id DESC`; `limit` predeterminado 20 y máximo 100. |

Ejemplo de respuesta parcial; los nombres y tipos de propiedades son **PROPUESTA** y no definen el significado de “habitación”:

```json
{
  "items": [
    {
      "listing_id": "EXAMPLE_LISTING_ID",
      "offer_version": 1,
      "operation": "sale",
      "base_price": {
        "amount": "1234.50",
        "currency": "COP"
      },
      "city": "EXAMPLE_CITY",
      "zone": "EXAMPLE_ZONE"
    }
  ],
  "next_cursor": null
}
```

**PROPUESTA de respuesta de detalle mínima, implementada en esta rama:** agrega `bedrooms`, `bathrooms` y `extras`. Cada extra contiene únicamente `extra_id` estable, `name` visible y `price` COP; no se exponen descripción, fotos ni dirección exacta. La lista sigue limitada a los campos del ejemplo parcial y no incluye extras ni medios.

```json
{
  "listing_id": "EXAMPLE_LISTING_ID",
  "offer_version": 1,
  "operation": "sale",
  "base_price": {"amount": "1234.50", "currency": "COP"},
  "city": "EXAMPLE_CITY",
  "zone": "EXAMPLE_ZONE",
  "bedrooms": 2,
  "bathrooms": 1,
  "extras": [
    {
      "extra_id": "EXAMPLE_EXTRA_ID",
      "name": "EXAMPLE_DISPLAY_NAME",
      "price": {"amount": "123.45", "currency": "COP"}
    }
  ]
}
```

Los valores son ilustrativos, no fixtures de migración ni datos desplegados. No se incluye un schema de escena 3D ni se agregan rutas de publicación para personal.

## 7. Cotización: snapshot, versión y vigencia

**IMPLEMENTADO EN ESTA RAMA, CC-04B; el contrato global continúa PROPUESTA:** `POST /api/v1/quotes` es público, no requiere cuenta ni wallet y recibe `listing_id`, `offer_version` entero y los IDs de extras seleccionados. No recibe totales del cliente ni `Idempotency-Key`; cada POST bien formado crea un ID y snapshot nuevos, incluso si repite un request anterior. El servidor valida publicación visible, versión vigente y pertenencia/no duplicidad de extras. Los errores específicos de quote usan el sobre descrito en la sección 10.

```json
{
  "listing_id": "EXAMPLE_LISTING_ID",
  "offer_version": 3,
  "selected_extra_ids": ["EXAMPLE_EXTRA_ID"]
}
```

La respuesta exitosa usa HTTP `201` y persiste un snapshot inmutable de las líneas, versión y totales. El orden de extras es estable por ID. Para venta, base y extras seleccionados se suman a `one_time_total` y `monthly_total` es cero; para alquiler, base y extras se suman a `monthly_total` y `one_time_total` es cero. Se usa `Decimal` exacto, COP con dos decimales y `ROUND_HALF_UP`.

```json
{
  "quote_id": "EXAMPLE_QUOTE_ID",
  "listing_id": "EXAMPLE_LISTING_ID",
  "offer_version": 3,
  "operation": "sale",
  "lines": [
    {
      "kind": "base",
      "extra_id": null,
      "amount": "1234.50",
      "currency": "COP",
      "charge_period": "one_time"
    },
    {
      "kind": "extra",
      "extra_id": "EXAMPLE_EXTRA_ID",
      "amount": "123.45",
      "currency": "COP",
      "charge_period": "one_time"
    }
  ],
  "one_time_total": {"amount": "1357.95", "currency": "COP"},
  "monthly_total": {"amount": "0.00", "currency": "COP"},
  "created_at": "<UTC timestamp>",
  "expires_at": "<created_at plus exactly 15 minutes>"
}
```

La vigencia es exactamente 15 minutos según el reloj UTC del servidor. Un quote vencido o cuya `offer_version` ya no coincide con el listing no es válido para uso futuro; el helper de servicio preparado para CC-05 verifica ambas condiciones. La API no ofrece GET, modificación ni borrado de cotizaciones y nunca recalcula un snapshot existente.

**DECISIÓN DE ESTA RAMA — CC-04B:** el límite es **10 solicitudes por IP cada minuto** en ventana móvil compartida por workers mediante eventos persistidos en base de datos. La clave guardada es HMAC de la IP directa del peer HTTP, no la IP en texto claro; no se confía en `X-Forwarded-For` ni otros headers no configurados. Una instalación detrás de reverse proxy debe establecer un peer IP confiable antes de depender del límite por IP. El request 11 responde `429 rate_limit_exceeded` con `Retry-After`; intentos con body/schema inválido no alcanzan el endpoint ni se cuentan.

## 8. Reserva, idempotencia y concurrencia

### Creación y reloj de 24 horas

**CONFIRMADA:** la reserva requiere una cuenta RoomForge autenticada y una wallet externa verificada vinculada a esa cuenta. **PROPUESTA de contrato; implementada en esta rama, CC-05B:** `POST /api/v1/reservations` recibe `listing_id`, `quote_id` y el ID opaco de la wallet vinculada. Exige el header `Idempotency-Key`. No recibe una dirección arbitraria ni firma de wallet en cada solicitud.

```http
Idempotency-Key: <client-generated-key>
```

```json
{
  "listing_id": "EXAMPLE_LISTING_ID",
  "quote_id": "EXAMPLE_QUOTE_ID",
  "customer_wallet_id": "EXAMPLE_LINKED_WALLET_ID"
}
```

El servidor debe autenticar la cuenta, verificar que `customer_wallet_id` le pertenece y cargar su dirección verificada desde almacenamiento. El depósito on-chain debe originarse desde esa dirección; el backend deberá validar emisor y evento del escrow contra la wallet vinculada. La firma/challenge verifica control al vincular, no sustituye sesión de cliente ni se repite como identidad en cada request. **CONFIRMADO e IMPLEMENTADO EN ESTA RAMA, CC-03B:** como máximo una wallet por cuenta y dirección globalmente única; no hay selección, unlink ni reemplazo. CC-03A implementa cuenta/sesión separada de staff. La ruta de reserva y la autorización técnica de depósito/EIP-712 siguen propuestas para CC-05; el flujo Flutter/wallet, para CC-07/CC-08.

**CONFIRMADA:** el depósito es fijo por inmueble, no se deriva del total cotizado; el plazo de decisión de agencia empieza cuando la API crea la solicitud, antes de que se deposite el token.

**CONFIRMADA para CC-05B:** en una transacción atómica, el servidor valida la cotización y las wallets requeridas, captura `api_created_at` con su reloj y fija `decision_deadline_at = api_created_at + 24 horas`. Una publicación pública sin depósito (`deposit_amount_cop = null`) puede reservarse sin depósito; un monto positivo configurado se congela en la reserva. Una retransmisión idempotente devuelve la reserva ya creada, sin reiniciar el reloj.

```json
{
  "reservation_id": "EXAMPLE_RESERVATION_ID",
  "status": "EXAMPLE_PENDING_STATUS",
  "api_created_at": "<UTC timestamp assigned by API>",
  "decision_deadline_at": "<api_created_at plus 24 hours>",
  "quote_snapshot": {
    "quote_id": "EXAMPLE_QUOTE_ID",
    "offer_version": 1,
    "operation": "sale",
    "lines": [],
    "one_time_total": {"amount": "100000.00", "currency": "COP"},
    "monthly_total": {"amount": "0.00", "currency": "COP"}
  },
  "deposit_amount_cop": null
}
```

La forma global del contrato continúa **PROPUESTA**. En esta rama, CC-05B responde `status: "pending"`, congela el snapshot de quote, las direcciones de wallet verificadas y el depósito COP nullable. No genera ni devuelve autorización EIP-712; esa capacidad queda fuera de CC-05B. Los placeholders no son valores permitidos de producción.

### Invariante de una reserva pendiente

**CONFIRMADA para CC-05B:** como máximo una reserva `pending` o `accepted` por `listing_id`. La publicación queda bloqueada desde la creación API; `accepted` sigue bloqueando hasta una futura función explícita de liberación. El backend serializa la creación (SQLite `BEGIN IMMEDIATE`, PostgreSQL lock de la fila de listing) y una restricción única parcial protege el invariante en base de datos. El conflicto implementado es `409 listing_has_active_reservation`.

**CONFIRMADA para CC-05B:** misma cuenta + mismo `Idempotency-Key` + mismo body reproduce la reserva original; la misma clave con otro body devuelve `409 idempotency_key_reused`. Se guarda clave y fingerprint SHA-256 en la reserva, sin tabla temporal ni vencimiento separado.

**CONFIRMADA para CC-05B:** una quote puede reutilizarse mientras siga dentro de su TTL y mantenga el `offer_version` vigente, incluso luego de que una reserva anterior sea terminal. La quote no se consume por la creación de reserva.

### Estados y transiciones

La forma global de estados sigue **PROPUESTA**. CC-05B implementa `pending` y la expiración local `expired`; el modelo reserva los demás estados para trabajo posterior. Solo `pending` y `accepted` bloquean el listing.

| Estado candidato | Transición propuesta | Regla o decisión |
|---|---|---|
| `pending` | Creación API → `pending`; puede terminar como `accepted`, `rejected`, `cancelled` o `expired`. | La creación inicia las 24 horas y ocupa el inmueble (**CONFIRMADA**). |
| `accepted` | `pending` → `accepted`; depósito liberado a wallet de agencia. | La wallet externa de agencia ejecuta la aceptación en cadena (**CONFIRMADO**); la firma EIP-712 del backend autoriza por separado el deadline creado por la API antes del depósito. Envío wallet→contrato directo es **PROPUESTA**; payload, nonce/replay, timing y reconciliación de eventos **PENDIENTES**. |
| `rejected` | `pending` → `rejected`; depósito reembolsado si fue depositado. | Rechazo y reembolso son reglas **CONFIRMADAS**; la wallet externa de agencia ejecuta el rechazo en cadena (**CONFIRMADO**). Payload, nonce/replay, envío a cadena, timing y reconciliación de eventos **PENDIENTES**. |
| `cancelled` | `pending` → `cancelled`; depósito reembolsado si fue depositado. | Cancelación mientras sigue pendiente y reembolso confirmados; actor autorizado **PENDIENTE**. |
| `expired` | `pending` → `expired` al vencer el plazo si no se confirmó depósito. | **CONFIRMADA para CC-05B:** vencimiento sin depósito confirmado se aplica localmente y desbloquea el listing. Si el depósito está confirmado, la reserva sigue bloqueando hasta que CC-05C/CC-06 confirme el reembolso on-chain. |

**IMPLEMENTADO EN ESTA RAMA, CC-05B:** los accesos de lectura propia y los intentos de creación nuevos ejecutan la expiración local de pendientes vencidas sin depósito confirmado. La expiración es perezosa en estas rutas; no se agrega un scheduler en este unit. Una reserva con depósito confirmado no expira localmente ni libera el listing. La confirmación del reembolso, recepción de eventos y demás transiciones terminales basadas en cadena pertenecen a CC-05C/CC-06.

**PROPUESTA:** mantener `deposit_status` separado de `status` para distinguir decisión comercial de ejecución on-chain. Los estados de depósito (por ejemplo, no enviado, pendiente de reconciliación, confirmado, reembolso pendiente/confirmado o liberación pendiente/confirmada) son solo categorías candidatas; strings, confirmaciones y fallos finales quedan **PENDIENTES** de la integración con Solidity. No anunciar depósito como confirmado a partir de un hash informado por Flutter.

## 9. Autorizaciones EIP-712 y wallet

Hay cuatro responsabilidades distintas; no son intercambiables:

1. **Cuenta del cliente:** requisito de identidad para iniciar sesión, crear reservas y acceder a las propias. CC-03A implementa en esta rama las rutas `/api/v1/customer/auth/*`, separadas de staff; usa modelos/sesiones propios y valida su audiencia de token. El comportamiento de esta rama incluye email normalizado/único, Argon2id, access JWT de 15 min, refresh opaco rotatorio con TTL absoluto de 7 días, inactividad deslizante de 30 min y errores no enumerativos. Es comportamiento implementado en la rama, no aprobación global del contrato ni evidencia de despliegue.
2. **Wallet externa del cliente:** se vincula y verifica contra la cuenta mediante challenge firmado. CC-03B implementa EIP-191 `personal_sign`; el servidor persiste y devuelve el mensaje exacto, ligado a cuenta, dirección canonicalizada, propósito fijo, nonce criptográfico y timestamps UTC, con TTL de 5 minutos. Toda firma inválida (también malformada) consume el challenge antes de la recuperación; replay y expiración fallan cerrados. El chainId no es necesario para demostrar control de dirección. Se permite como máximo una wallet por cuenta y cada dirección es globalmente única; no hay unlink ni reemplazo. La reserva referencia el ID de wallet vinculada; el backend carga su dirección verificada y el depósito debe originarse desde ella. El SDK móvil sigue pendiente. La wallet no reemplaza la cuenta.
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

El backend actual no usa este formato de manera uniforme. **PROPUESTA para el contrato general:** adoptar para las nuevas rutas una respuesta JSON estable, sin filtrar detalles internos. **IMPLEMENTADO EN ESTA RAMA, CC-04B:** los errores de quote usan este sobre; la validación y errores existentes de staff/cliente conservan sus respuestas previas:

```json
{
  "code": "EXAMPLE_ERROR_CODE",
  "message": "Descripción legible para personas",
  "request_id": "<request identifier>",
  "field_errors": []
}
```

Para CC-04B, `code`, `message`, `request_id` y `field_errors` están implementados; `field_errors` es una lista vacía cuando no aplica. Esto no convierte el formato en una política global ni cambia el comportamiento de staff/cliente. No se prescribe todavía un estándar externo de media type. Mantener HTTP status semánticamente coherente y documentar respuestas en OpenAPI.

| HTTP candidato | Ejemplos de código candidato | Motivo general |
|---|---|---|
| `400` | `invalid_cursor`, `invalid_request` | Sintaxis de cursor/solicitud inválida. |
| `401` | `customer_authentication_required`, `customer_authentication_invalid` | Sesión de cuenta de cliente requerida o inválida. La sesión está implementada en esta rama; estos códigos y su uso en el contrato general siguen propuestos. |
| `403` | `customer_wallet_not_verified` | La cuenta autenticada no tiene una wallet vinculada y verificada cuando la operación la requiere. |
| `403` | `staff_role_required`, `tenant_access_denied` | Personal autenticado sin autorización. Política final pendiente. |
| `404` | `listing_not_found`, `reservation_not_found` | Recurso inexistente o no visible para quien consulta; `listing_not_found` está implementado en CC-04B. |
| `409` | `listing_has_pending_reservation`, `offer_version_mismatch`, `quote_expired`, `reservation_not_pending`, `idempotency_key_reused` | Conflicto de estado, versión o idempotencia; `offer_version_mismatch` está implementado al crear quotes. |
| `422` | `validation_error`, `invalid_extra_selection`, `invalid_amount_format`, `invalid_filter`, `invalid_signature` | Contenido inválido; los dos primeros códigos están implementados para CC-04B. |
| `429` | `rate_limit_exceeded` | Se excedieron las 10 solicitudes por IP en la ventana móvil de 60 segundos; responde `Retry-After` (**IMPLEMENTADO EN ESTA RAMA**). |
| `503` | `quote_service_unavailable`, `quote_configuration_unavailable`, `signature_service_unavailable` | Dependencia/configuración no disponible; CC-04B falla cerrado ante almacenamiento/dialecto de rate limit no disponible. |

Los códigos indicados como implementados describen solamente esta rama; los demás y la asignación global siguen **PROPUESTA**. No copiar el formato `detail` existente como si ya fuera el contrato de estos endpoints.

### Paginación propuesta

**PROPUESTA TÉCNICA CC-04A, implementada en esta rama:** `cursor` opaco y `next_cursor` nullable para `GET /api/v1/listings`; orden estable `created_at DESC, id DESC`; `limit` predeterminado 20 y máximo 100. Los cursores se validan antes de consultar y una forma inválida devuelve `400` (`invalid_cursor`). Los filtros deben conservarse al pedir páginas siguientes. El cursor no es una autorización ni una firma criptográfica. Estos defaults son elecciones técnicas de la rama, no aprobación global del contrato.

## 11. OpenAPI reproducible desde FastAPI

**HECHO ACTUAL — BASE `b6a468a`:** `backend/app/main.py:create_app()` crea la instancia FastAPI e incluye los routers de personal y agencias; no define rutas ni esquemas de catálogo/ofertas, cotizaciones o reservas, ni configura un documento OpenAPI manual para esos recursos.

**IMPLEMENTADO EN ESTA RAMA — CC-03A/CC-03B/CC-04A/CC-04B/CC-05B:** las rutas y modelos tipados de cuenta/sesión, wallet, lectura pública de catálogo, creación pública de quote y reservas están registrados desde `create_app()` y documentados por `app.openapi()`. CC-05B registra las rutas de reservas; no se registran rutas administrativas de publicación. Este avance no aprueba el contrato general ni acredita despliegue. No editar a mano una copia JSON/YAML como fuente canónica.

**Reproducibilidad propuesta:** construir la misma `app` con configuración de test segura y serializar `app.openapi()`; los tests verifican paths públicos, schemas mínimos y que la validación `422` de quote no altere las respuestas previas de staff/cliente. La propuesta global aún requiere revisión y no acredita despliegue ni verificación contra PostgreSQL. No exponer secretos en schemas ni requerir wallet real para generar OpenAPI.

## 12. Registro de decisiones pendientes

| ID | Decisión pendiente | No asumir |
|---|---|---|
| D-01 | **Resuelta para esta rama:** COP con dos decimales, aritmética `Decimal` exacta y `ROUND_HALF_UP` para totales; revisar globalmente junto con el contrato. | Conversión monetaria o tratar `NUMERIC(18,2)` como regla de producto. |
| D-02 | **Resuelta para esta rama/CC-04B:** snapshot inmutable, TTL de 15 minutos y cambios de `offer_version` invalidan quotes anteriores; su implementación pertenece a CC-04B. | Que el cliente calcule, extienda o reescriba una quote. |
| D-03 | Monto fijo del depósito por inmueble. | Valor derivado del precio o un monto de ejemplo. |
| D-04 | Token de prueba: símbolo, decimales, supply y direcciones; `chainId`, contrato y RPC local de Hardhat. | Testnet o fondos reales sin aprobación posterior; tokens, cadena o despliegues de producción. |
| D-05 | SDK/proveedor de wallet móvil y configuración pública. | SDK o project ID. No guardar secretos/configuración privada en Git. |
| D-06 | Para wallet de cliente, CC-03B implementa EIP-191 `personal_sign` con challenge de un solo uso ligado a cuenta, dirección canonicalizada y propósito, nonce criptográfico y timestamps UTC; TTL de 5 minutos. Se confirma una wallet por cuenta, dirección globalmente única, consumo ante firma inválida y ausencia de unlink/reemplazo. Siguen pendientes el SDK móvil y el protocolo de prueba de wallet de agencia. | Que la wallet reemplace la cuenta, que una dirección enviada en el body pruebe control o que la prueba de identidad requiera una cadena no elegida. |
| D-07 | Exactos roles y autorizaciones para publicación opcional y operaciones administrativas no decisorias sobre reservas. | Que un rol actual tenga permisos nuevos por inferencia o que la staff API baste para aceptar. |
| D-08 | Actor autorizado a cancelar una reserva pendiente y autorización requerida para esa cancelación. | Un actor o mecanismo de cancelación aprobado sin decisión explícita. |
| D-09 | **Resuelta para esta rama:** `min_rooms` cuenta dormitorios y `min_bathrooms` es un mínimo entero. | Fracciones de dormitorios o baños. |
| D-10 | Schema de escena 3D, ambientes, conexiones y renderer. | Payload, geometría o formato de reconstrucción. |
| D-11 | **Resuelta para esta rama, CC-04B:** quote público sin autenticación ni idempotencia, una cotización nueva por POST y límite de 10 solicitudes por IP cada minuto en ventana móvil, compartido por DB; se usa la IP directa del peer y solo se persiste su HMAC. Sigue pendiente la titularidad/historial si se agrega consulta. | Confiar en headers de proxy no configurados, persistir la IP en texto claro o tratar la decisión técnica de rama como aprobación global. La cuenta para reservar y la wallet vinculada/verificada son reglas confirmadas. |
| D-12 | Revisión y aprobación global de nombres, schemas, enums, errores, respuestas y versionado; los schemas de identidad/wallet existentes en esta rama no aprueban el contrato general. | Que los nombres propuestos ya estén aprobados o que un schema de rama implique implementación de catálogo/reservas. |
| D-13 | **Defaults técnicos propuestos e implementados en CC-04A:** keyset `created_at DESC, id DESC`; default 20 y máximo 100; filtros de precio no negativos con dos decimales COP. Requiere revisión global del contrato. | Presentar estos valores de implementación como reglas de producto o aprobación global. |
| D-14 | **Resuelta para CC-05B:** misma cuenta + misma clave + mismo body reproducen la reserva; body distinto da `409`; clave/fingerprint permanecen en la reserva sin tabla expirable. | No extrapolar esta política a operaciones distintas de crear reservas. |
| D-15 | Qué instante determina aceptación antes del deadline cuando API y cadena difieren; expiración, transacciones en vuelo, confirmaciones, reorgs y reconciliación. | Que hora de envío, hora de bloque o primera confirmación sea el criterio acordado. |
| D-16 | Dominio EIP-712 final, hash canónico de snapshot, ABI/eventos, gas payer y semántica de escrow. | Tipos Solidity, nombres de eventos, contrato ni configuración de red. |
| D-17 | Si CC-04 necesita rutas para publicación antes del panel y cuál será el workflow opcional de aprobación/publicación. | Que haya un workflow o rutas administrativas aprobadas. |
| D-18 | **Resuelta para CC-05B:** una reserva `accepted` sigue bloqueando el listing hasta una función futura explícita de liberación. | No liberar automáticamente por salir de `pending`. |
| D-19 | **Resuelta para CC-05B:** `listing_id` es la identidad de reserva y de bloqueo. | No inferir una entidad de inmueble distinta en este unit. |
| D-20 | Revisar y aprobar globalmente el contrato de cuenta/sesión implementado en esta rama por CC-03A (paths `/api/v1/customer/auth/*`, schemas, expiración/refresh y revocación). | Confundir el comportamiento implementado en esta rama con aprobación global o despliegue; cambiar `/api/v1/auth/*`, que sigue siendo staff-only. |

## 13. Criterio de salida de CC-02

Este artefacto conserva explícitamente el estado **PROPUESTA** para revisión y no afirma despliegue ni aprobación final. CC-03A/CC-03B/CC-04A/CC-04B y el unit CC-05B están implementados en esta rama; el contrato global de rutas, schemas y errores sigue sujeto a revisión. Para CC-04B se registran el acceso público sin autenticación/idempotencia, nuevo snapshot por POST, vigencia de 15 minutos, invalidación por `offer_version` y rate limit de 10 solicitudes por IP cada minuto. Para CC-05B se registra cuenta autenticada + wallet de cliente y agencia vinculadas, snapshot COP con depósito nullable, deadline de 24 horas, bloqueo por `listing_id`, idempotencia persistida y acceso propio. El vencimiento local sin depósito confirmado libera el bloqueo; si el depósito fue confirmado, el listing permanece bloqueado hasta una futura confirmación de reembolso on-chain. CC-05C/CC-06 conservan cancelación, decisiones de agencia, eventos/recibos, EIP-712 y escrow. Se preserva `/api/v1/auth/*` para personal y `/api/v1/customer/auth/*` para clientes. CC-06 y CC-08 deben mantener el límite de Hardhat local: sin testnet ni fondos reales sin aprobación posterior. Las decisiones marcadas **PENDIENTE** no deben convertirse en defaults silenciosos; las etiquetas **PROPUESTA** requieren resolución antes de tratarlas como contrato.

## Key Learnings

1. La sesión de cliente y la sesión de personal deben permanecer separadas.
2. La wallet verificada se vincula a una cuenta RoomForge y no la reemplaza.
3. El depósito fijo necesita una autorización EIP-712 independiente de la aceptación de agencia.
