# API de favoritos y búsquedas guardadas (F14.3)

Contrato de `backend/app/modules/favorites/`. Todas las rutas son de cliente y usan `Authorization: Bearer` con la sesión de cliente; sin sesión responden 401. Los errores tienen la forma `{ "detail": "...", "code": "..." }` (`not_found`, `conflict`, `validation_error`, `unauthorized`).

**Aislamiento:** cada cliente lee, agrega y borra solo lo suyo. Un favorito ajeno no existe para otro cliente, y una búsqueda ajena responde 404, igual que una inexistente. El catálogo público (`GET /api/v1/listings`) no cambia para nadie: no informa favoritos ni depende de la sesión.

**Privacidad:** una búsqueda guardada nunca incluye el punto ni el radio de la búsqueda por zona (`latitude`, `longitude` y `radius_km`). La ubicación del cliente viaja solo como parámetro de la consulta y no se guarda (F14.5, S4); un cuerpo que la incluya se rechaza con 422.

## Favoritos (`/api/v1/customer/favorites`)

| Método y ruta | Qué hace |
| --- | --- |
| `GET` | `{ items }`, los más recientes primero. Cada favorito es `{ listing_id, favorited_at, available, listing }`. |
| `PUT /{listing_id}` | Marca el inmueble como favorito (204). Es idempotente: repetirlo no duplica. 404 si el inmueble no está aprobado y publicado. 409 `favorite_limit` al llegar a 100 favoritos. |
| `DELETE /{listing_id}` | Quita el favorito (204). Es idempotente: un favorito que no existe también responde 204. |

`listing` tiene la forma del ítem del catálogo público (`listing_id`, `offer_version`, `operation`, `base_price`, `city`, `zone`, `cover_photo_url`, `latitude`, `longitude`). Si el inmueble dejó de estar publicado, el favorito se conserva con `available: false` y `listing: null`: no se muestra ningún dato de un inmueble que ya no es público, y el cliente puede quitarlo.

## Búsquedas guardadas (`/api/v1/customer/saved-searches`)

| Método y ruta | Qué hace |
| --- | --- |
| `GET` | `{ items }`, las más recientes primero. |
| `POST` | Cuerpo `{ name, filters }`. 201 con la búsqueda creada. 409 `saved_search_name_taken` si el cliente ya tiene una con ese nombre (sin distinguir mayúsculas); 409 `saved_search_limit` al llegar a 20; 422 si el nombre o los filtros no son válidos. |
| `DELETE /{id}` | Borra la búsqueda (204); 404 si no existe o es de otro cliente. |

Búsqueda: `{ id, name, filters, created_at }`. `name` va de 1 a 80 caracteres y se guarda sin espacios al inicio ni al final.

`filters` admite las claves del catálogo público, con sus mismas reglas: `city` y `zone` (hasta 120 caracteres, no vacías), `operation` (`sale` o `rent`), `min_base_price` y `max_base_price` (decimales como texto, mayores o iguales que 0, con hasta 2 decimales, el mínimo no mayor que el máximo), `min_rooms` y `min_bathrooms` (enteros mayores o iguales que 0). Toda otra clave se rechaza. La respuesta trae todas las claves, con `null` en las que no se usaron; aplicar la búsqueda equivale a consultar `GET /api/v1/listings` con esos parámetros.

## Datos

`customer_favorite` (una fila por `customer_id` y `listing_id`) y `customer_saved_search` (nombre único por cliente y `filters` como JSON), en la migración `0035_customer_favorites`. Borrar el cliente o el inmueble borra sus filas.
