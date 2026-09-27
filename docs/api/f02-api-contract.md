# Contrato de API de F02

Errores y paginación implementados en F02; no agrega rutas de F03–F10.

## Formato de errores
Cada respuesta contiene exactamente `detail` (cadena legible, compatible con clientes existentes del panel) y `code` (identificador estable): `{"detail":"La solicitud no pudo completarse","code":"validation_error"}`.
Códigos: `validation_error` — cuerpo/ruta/parámetros fuera del contrato (400, 422); `unauthorized` — sesión ausente o credencial rechazada (401); `forbidden` — sin autorización (403); `not_found` — recurso/ruta inexistente (404).
`conflict` — operación incompatible con un recurso existente (409); `dependency_unavailable` — servicio requerido no disponible (502, 503, 504); `internal_error` — error interno no clasificado, otros estados no mapeados; especialmente 500.
Todos los detalles de errores HTTP 5xx se redactan y sustituyen por mensajes genéricos; nunca se devuelven detalles de origen, excepciones, credenciales ni secretos. 502/503/504 usan `dependency_unavailable`; 500 usa `internal_error`.

## Listado de inmobiliarias
`GET /api/v1/agencies` requiere sesión autenticada de administrador de plataforma; ordena por `id` ascendente y `total` cuenta todos los resultados antes de paginar.
Parámetros: `limit` predeterminado 20, entero entre 1 y 100 inclusive; `offset` predeterminado 0, entero mayor o igual a 0.
Respuesta: conserva `agencies` y agrega `pagination`: `{"agencies":[{"id":"agency-a"},{"id":"agency-b"}],"pagination":{"limit":20,"offset":0,"total":2}}`.
Valores fuera de rango producen 422 con el formato común y `validation_error`; un `offset` posterior al último elemento devuelve `agencies: []` y mantiene el `total` real.
