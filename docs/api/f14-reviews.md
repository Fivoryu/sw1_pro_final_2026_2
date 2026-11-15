# API de reseñas (F14.8)

Contrato de `backend/app/modules/reviews/`. Las rutas de cliente y de personal usan `Authorization: Bearer`; la lectura pública no. Los errores tienen la forma `{ "detail": "...", "code": "..." }` (`not_found`, `forbidden`, `conflict`, `validation_error`, `unauthorized`).

**Qué se califica:** desde la ficha del inmueble, el cliente deja dos notas de 1 a 5 y un comentario opcional (hasta 1000 caracteres): una para el inmueble (la publicación y el recorrido 3D) y otra para la atención de la agencia. La nota del inmueble se muestra en su ficha; la de la agencia se agrega entre todos los inmuebles de la agencia.

**Identidad:** una reseña nunca identifica al cliente. La respuesta de la agencia no dice qué miembro del personal la escribió.

## Quién puede calificar

El cliente puede calificar un inmueble publicado cuando tiene una conversación con la agencia sobre ese inmueble (F14.6) y se cumple una de dos condiciones:

- la agencia le respondió al menos una vez, o
- el cliente espera respuesta desde hace 24 horas o más (el tiempo máximo de respuesta), de modo que una atención lenta o ausente también puede calificarse.

Una reseña ya creada se puede editar aunque esa condición ya no se cumpla. Hay una reseña por cliente e inmueble.

## Verificada y peso

Una reseña es **verificada** cuando su autor tiene una reserva en estado `accepted` sobre ese inmueble. Se calcula en cada consulta, no se guarda: si el cliente reserva después de calificar, su reseña pasa a verificada. Las reservas `pending`, `rejected`, `cancelled` y `expired` no verifican.

El promedio es ponderado: la reseña verificada pesa 3 y las demás 1. Con menos de 3 reseñas no hay promedio (`average: null`, `few_ratings: true`); el resumen siempre trae `count` y `verified_count`. Las constantes (24 h, peso 3, umbral 3) están en `reviews/service.py`.

## Cliente (`/api/v1/customer/reviews`, sesión de cliente)

| Método y ruta | Qué hace |
| --- | --- |
| `GET /listings/{listing_id}` | `{ can_review, reason, review }`. `reason` es `no_conversation` o `awaiting_reply` cuando todavía no puede calificar. 404 si el inmueble no está aprobado y publicado. |
| `PUT /listings/{listing_id}` | Cuerpo `{ listing_rating, agency_rating, comment? }`. Crea (201) o edita (200). 403 si no cumple la condición (`detail` incluye el motivo); 422 si una nota no está entre 1 y 5. |

## Lectura pública (sin sesión)

| Método y ruta | Qué devuelve |
| --- | --- |
| `GET /api/v1/listings/{listing_id}/reviews` | `{ agency_id, agency_name, listing, agency, reviews }`: resumen de notas del inmueble, resumen de notas de la agencia y las reseñas del inmueble. 404 si no está publicado. |
| `GET /api/v1/public/agencies/{agency_id}/reviews` | `{ agency_name, summary, reviews }`: perfil de la agencia con todas sus reseñas. |

Resumen: `{ average | null, count, verified_count, few_ratings }`.
Reseña: `{ id, listing_id, listing_rating, agency_rating, comment | null, verified, created_at, updated_at, agency_reply | null, agency_reply_at | null }`. Las reseñas ocultas no aparecen.

## Personal (`/api/v1/staff/reviews`)

| Método y ruta | Rol | Qué hace |
| --- | --- | --- |
| `GET` | agente, administrador de agencia | Reseñas de su agencia con `summary` y la marca `reported` (reporte abierto). |
| `POST /{id}/reply` | administrador de agencia | Cuerpo `{ "body": "..." }` (1–1000). La agencia responde una vez por reseña (204); 409 si ya tiene respuesta. No puede borrarla. |
| `POST /{id}/report` | administrador de agencia | Cuerpo `{ "body": "motivo" }`. 201 `{ id }`; 409 si ya hay un reporte abierto. |
| `GET /reports?status=open` | administrador de plataforma | Cola de reportes (`open`, `upheld` o `dismissed`) con la reseña reportada. |
| `POST /reports/{id}/resolve` | administrador de plataforma | Cuerpo `{ "decision": "upheld" \| "dismissed" }` (204). Confirmar oculta la reseña (no se borra) y deja de contar en promedios y listas; descartar la mantiene. 409 si ya estaba resuelto. |

Otra agencia que intente responder o reportar recibe 404, igual que una reseña inexistente. Los agentes solo leen.

## Datos

`listing_review` (una fila por `listing_id` y `customer_id`, `agency_id` copiado del inmueble, notas con restricción 1–5, respuesta y `hidden_at`) y `review_report` (`status` `open`, `upheld` o `dismissed`), en la migración `0034_listing_reviews`.
