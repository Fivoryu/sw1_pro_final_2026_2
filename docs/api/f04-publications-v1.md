# API F04 — Alta, revisión y publicación de inmuebles

## Alcance

La API usa el sustrato existente `catalog.Listing`. Los datos comerciales y de contenido se reemplazan sobre el mismo registro; el historial de acciones se agrega en `listing_transition`. El catálogo público conserva su contrato: devuelve únicamente publicaciones con `approval_status = approved` e `is_published = true`.

## Máquina de estados

```text
create / edit                 -> draft + is_published=false
 draft --submit--------------> pending
pending --approve------------> approved + is_published=false
pending --reject (motivo)----> rejected + is_published=false
approved, no publicado --publish--> approved + is_published=true
approved, publicado --unpublish--> approved + is_published=false
```

Editar está permitido desde cualquier estado: reemplaza el contenido, devuelve el inmueble a `draft` y lo oculta del catálogo de inmediato. Una transición distinta de las indicadas responde `409 Conflict`; no se registra historial para una operación rechazada.

## Rutas

Todas las rutas nuevas son de personal y requieren una sesión autenticada mediante el mecanismo existente `get_active_staff`.

| Método y ruta | Resultado |
|---|---|
| `POST /api/v1/staff/agencies/{agency_id}/listings` | Crea un borrador (`201`). |
| `PUT /api/v1/staff/agencies/{agency_id}/listings/{listing_id}` | Reemplaza el contenido y reabre el borrador (`200`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/submit` | Envía a revisión (`200`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/approve` | Aprueba una solicitud pendiente (`200`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/reject` | Rechaza una solicitud pendiente con motivo (`200`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/publish` | Publica una oferta aprobada (`200`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/unpublish` | Retira una oferta del catálogo (`200`). |
| `GET /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/transitions` | Devuelve el historial ordenado del inmueble (`200`). |

El cuerpo de alta y reemplazo admite únicamente estos campos:

```json
{
  "operation": "sale",
  "base_price": "125000.00",
  "city": "Medellín",
  "zone": "El Poblado",
  "bedrooms": 3,
  "bathrooms": 2,
  "description": "Descripción opcional",
  "exact_address": "Dirección opcional"
}
```

`operation` es `sale` o `rent`; `base_price` debe ser decimal positivo con hasta 18 dígitos y 2 decimales; `city` y `zone` son textos no vacíos de hasta 120 caracteres; `bedrooms` y `bathrooms` son enteros no negativos. El servidor deriva `city_key` y `zone_key` con `normalize_geo_key`. En `reject`, el cuerpo contiene `observation`, obligatoria y no vacía después de quitar espacios. Las demás acciones pueden omitirla o incluirla para el historial.

Los esquemas rechazan campos adicionales. No se aceptan autoridad, estado ni valores derivados del cliente, incluidos `tenant_id`, actor, rol, `status`, `is_published`, `offer_version`, timestamps, `city_key`, `zone_key` y `photos`.

## Autorización

| Operación | `agency_admin` de la agencia | `agent` de la agencia | Otro tenant | `platform_admin` |
|---|---:|---:|---:|---:|
| Crear, editar, enviar a revisión, leer transiciones | Sí | Sí | `403` | `403` |
| Aprobar, rechazar, publicar, retirar | Sí | `403` | `403` | `403` |

La agencia y el actor se obtienen de la sesión de personal. Un inmueble inexistente dentro de la agencia autorizada responde `404`; no se consultan recursos de otra agencia para determinar su existencia. El catálogo público sigue siendo transversal entre agencias, sin exponer el historial privado.

## Errores

| HTTP | Uso |
|---:|---|
| `403` | Rol no autorizado, `platform_admin` o tenant distinto. |
| `404` | Inmueble inexistente dentro de la agencia autorizada. |
| `409` | Acción incompatible con el estado actual. |
| `422` | Cuerpo inválido, campo extra, precio no positivo o motivo de rechazo vacío. |

Las rutas utilizan el formato de error HTTP existente; no cambian el manejador global.

## Historial y versión comercial

Cada creación, edición o transición exitosa agrega una fila en `listing_transition`, con actor y rol resueltos por el servidor, estados anterior y nuevo, observación y fecha. La mutación del inmueble y su fila de historial se confirman en una misma transacción. El historial solo está disponible en la ruta de personal.

La versión comercial comienza en `1` y la controlan los disparadores existentes de la migración `0007_catalog_offers.py`: cambia cuando cambia `base_price`, `operation` o los extras del inmueble. Una edición descriptiva (por ejemplo, de `description`) no cambia `offer_version` ni invalida una cotización; un cambio comercial sí. La API F04 no modifica extras. Una reserva aceptada conserva su instantánea comercial.

## Límites y estado de validación

- F04.2, fotografías: diferido. No se implementan carga, almacenamiento, validación ni estados; tampoco se acepta `photos` en estos cuerpos.
- No se crean revisiones inmutables versionadas del inmueble. La edición modifica el registro existente y una publicación vuelve a requerir aprobación.
- La migración `0012_listing_transitions.py` no se aplicó contra PostgreSQL.
- No se ejecutó ningún caso académico CP; la suite técnica no es evidencia de ejecución académica.
