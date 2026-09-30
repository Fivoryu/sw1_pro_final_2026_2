# Contrato de API de F02

Errores y paginación implementados en F02; no agrega rutas de F03–F10.

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

## Salud del servicio
`GET /health/live` confirma únicamente que el proceso de la API responde; no consulta dependencias. `GET /health/ready` ejecuta `SELECT 1` mediante la fábrica de sesión inyectada y comprueba por TCP la disponibilidad del host/puerto de `S3_ENDPOINT_URL`. No usa `FLOCI_ENDPOINT_URL`, que puede apuntar al loopback del host y no ser accesible desde el contenedor. La conexión TCP solo confirma alcanzabilidad de red: no demuestra que Floci/S3 pueda ejecutar operaciones de almacenamiento.

Si falla alguna dependencia, readiness responde 503 con el sobre común `ErrorResponse`, código `dependency_unavailable` y detalle genérico; no incluye errores de conexión, configuración ni secretos. Compose consulta `/health/ready` con un límite HTTP de 35 s y un límite de healthcheck Docker de 40 s. La envolvente considera conexión y espera de pool (5 s cada una), sentencia (10 s), Floci (2 s) y margen para pre-ping/overhead. Estos límites externos no cancelan el trabajo síncrono de la API; los plazos de las dependencias siguen siendo los límites efectivos.
