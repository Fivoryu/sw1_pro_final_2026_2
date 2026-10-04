# Contrato de API de F02

Este contrato documenta los errores y la paginación establecidos en F02, junto con las rutas de tasas administradas incorporadas en F05M-T2.

## Formato de errores
Cada respuesta contiene exactamente `detail` (cadena legible, compatible con clientes existentes del panel) y `code` (identificador estable): `{"detail":"La solicitud no pudo completarse","code":"validation_error"}`.
Códigos: `validation_error` — cuerpo/ruta/parámetros fuera del contrato (400, 422); `unauthorized` — sesión ausente o credencial rechazada (401); `forbidden` — sin autorización (403); `not_found` — recurso/ruta inexistente (404).
`conflict` — operación incompatible con un recurso existente (409); `dependency_unavailable` — servicio requerido no disponible (502, 503, 504); `internal_error` — error interno no clasificado, otros estados no mapeados; especialmente 500.
Todos los detalles de errores HTTP 5xx se redactan y sustituyen por mensajes genéricos; nunca se devuelven detalles de origen, excepciones, credenciales ni secretos. 502/503/504 usan `dependency_unavailable`; 500 usa `internal_error`.

### Envolvente reservada de cotizaciones y reservas
Las rutas de cotizaciones (`/api/v1/quotes`) y de reservas (`/api/v1/reservations`, `/api/v1/staff/reservations`) no usan el sobre común: responden `{"code":<str>,"message":<str>,"request_id":<uuid>,"field_errors":[{"field":<str>,"message":<str>}]}` con sus propios códigos estables (por ejemplo `validation_error`, `reservation_not_found`, `reservation_action_forbidden`). Es una decisión deliberada y documentada, no una deuda pendiente: unificar ambos sobres exigiría cambiar handlers, esquemas, pruebas y los clientes ya construidos contra esta forma. Cualquier cambio futuro debe decidirse como una unidad propia y coordinarse con los clientes móviles antes de tocar el contrato.

## Listado de inmobiliarias
`GET /api/v1/agencies` requiere sesión autenticada de administrador de plataforma; ordena por `id` ascendente y `total` cuenta todos los resultados antes de paginar.
Parámetros: `limit` predeterminado 20, entero entre 1 y 100 inclusive; `offset` predeterminado 0, entero mayor o igual a 0.
Respuesta: conserva `agencies` y agrega `pagination`: `{"agencies":[{"id":"agency-a"},{"id":"agency-b"}],"pagination":{"limit":20,"offset":0,"total":2}}`.
Valores fuera de rango producen 422 con el formato común y `validation_error`; un `offset` posterior al último elemento devuelve `agencies: []` y mantiene el `total` real.

## Límites de dependencias
Los valores predeterminados de F02 son: conexión PostgreSQL 5 s, espera de adquisición del pool SQLAlchemy 5 s y `statement_timeout` PostgreSQL 10 s; el protocolo externo `EmailSender.send_invitation` recibe un plazo nativo de 10 s. Se configuran mediante `DATABASE_CONNECT_TIMEOUT_SECONDS`, `DATABASE_POOL_TIMEOUT_SECONDS`, `DATABASE_STATEMENT_TIMEOUT_SECONDS` y `STAFF_EMAIL_SEND_TIMEOUT_SECONDS`; todos deben ser enteros positivos. Los argumentos propios de psycopg y los límites de pool se aplican únicamente al motor PostgreSQL; las fábricas de sesión inyectadas, incluidas las de SQLite en pruebas, no reciben esos argumentos.

Cada proveedor implementa `EmailSender.send_invitation(..., *, timeout_seconds)` y aplica el plazo obligatorio en su transporte nativo. La aplicación no convierte el envío síncrono en una operación limitada por hilo o `Future`. No hay un proveedor concreto implementado, por lo que la aplicación del plazo en tiempo de ejecución queda externamente sin verificar.

## Tasas de cambio administradas (F05M-T2)

Las tasas se administran en la plataforma; no se consultan APIs externas. `units_per_usd` expresa cuántas unidades de la moneda indicada equivalen a 1 USD. Solo se almacenan filas BOB y USDT: USD es fija en `1.00000000` y no se puede crear como tasa. Cada alta se aplica inmediatamente, conserva el historial y registra `created_by` como el identificador UUID del personal que la creó.

### Crear una tasa

`POST /api/v1/platform/exchange-rates` requiere sesión de `platform_admin` y acepta tasas BOB o USDT como cadenas decimales positivas de hasta ocho posiciones decimales. Por ejemplo:

```json
{"currency":"BOB","units_per_usd":"6.96000000"}
```

Responde 201 con el registro creado:

```json
{
  "id": 1,
  "currency": "BOB",
  "units_per_usd": "6.96000000",
  "created_at": "2026-10-03T12:00:00Z",
  "created_by": "550e8400-e29b-41d4-a716-446655440000"
}
```

Rechaza USD, tasas cero o negativas, entradas que no sean cadenas decimales y valores con más de ocho decimales mediante 422 (`validation_error`).

### Consultar historial y tasa vigente

`GET /api/v1/platform/exchange-rates` requiere `platform_admin` y devuelve `{"rates":[...]}` con el historial completo en orden descendente por `created_at` y, para empates, por `id`. Cada fila incluye `id`, `currency`, `units_per_usd`, `created_at` y `created_by`.

`GET /api/v1/exchange-rates/current` es pública y devuelve `{"rates":[...]}` con una entrada por BOB, USD y USDT. Cada entrada incluye `currency`, `units_per_usd` y `created_at`. Para USD, `units_per_usd` es siempre `"1.00000000"` y `created_at` es `null`; si BOB o USDT aún no tienen una tasa administrada, ambos campos son `null`. La tasa actual es la fila más reciente según `created_at DESC, id DESC`.

| Actor | Crear tasa | Consultar historial de plataforma | Consultar tasas actuales |
| --- | --- | --- | --- |
| `platform_admin` autenticado | 201 | 200 | 200 |
| `agency_admin` o `agent` autenticado | 403 | 403 | 200 |
| Cliente autenticado | 403 | 403 | 200 |
| Sin autenticación | 401 | 401 | 200 |

Los errores de autorización y validación usan el sobre común `{"detail":...,"code":...}`.

### Semántica de conversión

La conversión calcula origen → USD → destino con aritmética `Decimal`; nunca usa `float`. Para convertir desde una moneda distinta de USD se divide por sus unidades por USD; para convertir a una moneda distinta de USD se multiplica por sus unidades por USD. Se redondea una sola vez al resultado final de dos decimales con `ROUND_HALF_UP`. BOB→BOB conserva el importe y solo aplica el formato comercial final de dos decimales. Si falta una tasa administrada necesaria para cualquiera de los lados de una conversión, esta falla de forma cerrada; no se supone una paridad ni se obtiene una tasa externa.

## Salud del servicio
`GET /health/live` confirma únicamente que el proceso de la API responde; no consulta dependencias. `GET /health/ready` ejecuta `SELECT 1` mediante la fábrica de sesión inyectada y comprueba por TCP la disponibilidad del host/puerto de `S3_ENDPOINT_URL`. No usa `FLOCI_ENDPOINT_URL`, que puede apuntar al loopback del host y no ser accesible desde el contenedor. La conexión TCP solo confirma alcanzabilidad de red: no demuestra que Floci/S3 pueda ejecutar operaciones de almacenamiento.

Si falla alguna dependencia, readiness responde 503 con el sobre común `ErrorResponse`, código `dependency_unavailable` y detalle genérico; no incluye errores de conexión, configuración ni secretos. Compose consulta `/health/ready` con un límite HTTP de 35 s y un límite de healthcheck Docker de 40 s. La envolvente considera conexión y espera de pool (5 s cada una), sentencia (10 s), Floci (2 s) y margen para pre-ping/overhead. Estos límites externos no cancelan el trabajo síncrono de la API; los plazos de las dependencias siguen siendo los límites efectivos.
