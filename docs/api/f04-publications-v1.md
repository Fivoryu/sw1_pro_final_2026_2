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

Editar está permitido desde cualquier estado: reemplaza el contenido, devuelve el inmueble a `draft` y lo oculta del catálogo de inmediato. Confirmar o borrar una foto confirmada (F04.2) cuenta como edición. `submit` exige además al menos una foto confirmada. Una transición distinta de las indicadas responde `409 Conflict`; no se registra historial para una operación rechazada.

## Rutas

Todas las rutas nuevas son de personal y requieren una sesión autenticada mediante el mecanismo existente `get_active_staff`.

| Método y ruta | Resultado |
|---|---|
| `POST /api/v1/staff/agencies/{agency_id}/listings` | Crea un borrador (`201`). |
| `GET /api/v1/staff/agencies/{agency_id}/listings` | Lista los inmuebles de la agencia, paginados y filtrables (`200`). |
| `GET /api/v1/staff/agencies/{agency_id}/listings/{listing_id}` | Devuelve un inmueble de la agencia con sus campos privados (`200`). |
| `PUT /api/v1/staff/agencies/{agency_id}/listings/{listing_id}` | Reemplaza el contenido y reabre el borrador (`200`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/submit` | Envía a revisión (`200`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/approve` | Aprueba una solicitud pendiente (`200`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/reject` | Rechaza una solicitud pendiente con motivo (`200`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/publish` | Publica una oferta aprobada (`200`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/unpublish` | Retira una oferta del catálogo (`200`). |
| `GET /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/transitions` | Devuelve el historial ordenado del inmueble (`200`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/photos` | Reserva una foto pendiente y devuelve el enlace firmado de subida (`201`). |
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/photos/{photo_id}/confirm` | Valida, limpia y confirma una foto subida (`200`). |
| `GET /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/photos` | Lista las fotos confirmadas con enlaces de lectura (`200`). |
| `DELETE /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/photos/{photo_id}` | Borra una foto y su objeto (`204`). |

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

### Listado y consulta de personal

`GET /api/v1/staff/agencies/{agency_id}/listings` admite estos parámetros de consulta, todos opcionales:

| Parámetro | Valores | Efecto |
|---|---|---|
| `status` | `draft`, `pending`, `approved`, `rejected` | Filtra por estado de revisión. |
| `published` | `true`, `false` | Filtra por visibilidad en el catálogo público. |
| `limit` | Entero de 1 a 100; predeterminado 20 | Tamaño de la página. |
| `offset` | Entero mayor o igual a 0; predeterminado 0 | Posición de inicio. |

Ordena del más reciente al más antiguo (`created_at` descendente, luego `id` descendente) y responde con la misma forma de paginación que el listado de inmobiliarias de `docs/api/f02-api-contract.md`; `total` cuenta los resultados filtrados antes de paginar:

```json
{
  "listings": [
    {
      "listing_id": "…",
      "agency_id": "…",
      "operation": "sale",
      "base_price": "125000.00",
      "city": "Medellín",
      "zone": "El Poblado",
      "bedrooms": 3,
      "bathrooms": 2,
      "description": "Descripción opcional",
      "exact_address": "Dirección opcional",
      "approval_status": "pending",
      "is_published": false,
      "offer_version": 1,
      "created_at": "2026-10-01T12:00:00Z"
    }
  ],
  "pagination": {"limit": 20, "offset": 0, "total": 1}
}
```

Un parámetro fuera de contrato responde `422`; un `offset` posterior al último elemento devuelve `listings: []` con el `total` real. `GET /api/v1/staff/agencies/{agency_id}/listings/{listing_id}` devuelve un único elemento con la misma forma. Ambas rutas exponen `description` y `exact_address`, que el catálogo público omite, y nunca incluyen el historial ni las fotografías; las fotos tienen su propia ruta.

### Fotografías (F04.2)

Patrón estándar de S3: la API autoriza y firma, el cliente sube los bytes directamente al almacenamiento, y la API confirma. Los binarios nunca pasan por PostgreSQL; la tabla `listing_photo` (migración `0013_listing_photos.py`) guarda solo metadatos.

1. **Pedir subida.** `POST .../photos` con este cuerpo, sin campos adicionales:

   ```json
   {"content_type": "image/jpeg", "size_bytes": 2048}
   ```

   `content_type` es `image/jpeg`, `image/png` o `image/webp`; `size_bytes` es un entero de 1 a 5 242 880 (5 MB). La respuesta `201`:

   ```json
   {
     "photo_id": "…",
     "upload_url": "http://127.0.0.1:4566/roomforge-local-assets/agencies/…/listings/…/photos/…?X-Amz-…",
     "upload_method": "PUT",
     "upload_headers": {"Content-Type": "image/jpeg"},
     "expires_at": "2026-10-06T12:15:00Z"
   }
   ```

   La clave del objeto la decide el servidor: `agencies/{agency_id}/listings/{listing_id}/photos/{photo_id}`. El enlace y la foto pendiente vencen a los 15 minutos. Un inmueble admite hasta 10 fotos, contando las confirmadas y las pendientes vigentes; las pendientes vencidas se borran al pedir otra subida. Superar el límite responde `409`.
2. **Subir.** El cliente envía los bytes con `PUT` al `upload_url`, con las cabeceras de `upload_headers` y sin la sesión de personal.
3. **Confirmar.** `POST .../photos/{photo_id}/confirm`, sin cuerpo. La API lee el objeto y exige que sea una imagen del tipo declarado, de hasta 5 MB y 40 megapíxeles. Aplica la orientación y vuelve a codificar la imagen sin metadatos (EXIF, incluida la ubicación GPS, y XMP), para que una foto publicada no revele la dirección privada. Respuestas:
   - `200` con la foto confirmada. Confirmar de nuevo una foto ya confirmada también responde `200`, sin otro efecto.
   - `422` si el archivo no es una foto válida; el objeto y la reserva se borran.
   - `409` si todavía no hay objeto subido o si venció la ventana de subida; la foto sigue pendiente.
4. **Listar y borrar.** `GET .../photos` devuelve `{"photos": [...]}` con las fotos confirmadas, de la más antigua a la más reciente. `DELETE .../photos/{photo_id}` borra el objeto y la fila (`204`).

Forma de una foto confirmada:

```json
{
  "photo_id": "…",
  "content_type": "image/jpeg",
  "size_bytes": 345327,
  "url": "http://127.0.0.1:4566/roomforge-local-assets/…?X-Amz-…",
  "created_at": "2026-10-06T12:00:00Z"
}
```

**Reglas:**

- `url` es un enlace firmado de lectura que vence a los 10 minutos; cada consulta genera enlaces nuevos.
- La primera foto confirmada es la portada del catálogo; no hay reordenamiento.
- Confirmar o borrar una foto confirmada devuelve el inmueble a `draft`, lo retira del catálogo y registra `edit`, igual que editar la ficha. Las fotos no cambian `offer_version` ni invalidan cotizaciones: la versión visual va separada de la comercial. Borrar una foto pendiente no cambia el inmueble.
- `submit` sin foto confirmada responde `409`.
- Sin almacenamiento configurado (`S3_BUCKET_NAME`), las rutas de fotos responden `503`.
- Los enlaces se firman para `S3_PUBLIC_ENDPOINT_URL`, porque la firma SigV4 incluye el host. La API usa `S3_ENDPOINT_URL` para leer, escribir y borrar.

## Autorización

Matriz por actor (F03.3). «Agencia» es la agencia de la URL; la del actor sale siempre de su sesión de personal.

| Operación | `agency_admin` de la agencia | `agent` de la agencia | Personal de otra agencia | `platform_admin` | Cliente o anónimo |
|---|---:|---:|---:|---:|---:|
| Crear, editar, enviar a revisión, leer transiciones | Sí | Sí | `403` | `403` | `401` |
| Listar y consultar inmuebles de la agencia | Sí | Sí, todos los de su agencia | `403` | `403` | `401` |
| Aprobar, rechazar, publicar, retirar | Sí | `403` | `403` | `403` | `401` |
| Configurar el depósito (`PATCH .../deposit`) | Sí | `403` | `403` | `403` | `401` |
| Fotos: pedir subida, confirmar, listar y borrar | Sí | Sí | `403` | `403` | `401` |
| Catálogo público (`GET /api/v1/listings` y detalle) | Sí | Sí | Sí | Sí | Sí, sin sesión |

- **ID ajeno en la ruta propia:** un inmueble de otra agencia pedido con la URL de la agencia autorizada responde `404`, con el mismo cuerpo que un inmueble inexistente, en todas las rutas de inmueble (consulta, edición, envío, aprobación, rechazo, publicación, retiro, historial, depósito y fotos). Una foto de otro inmueble también responde `404`. No se modifica el inmueble ni se agrega historial.
- **Sesión:** sin `Authorization`, con un token mal formado o con un token de cliente (`aud=roomforge-customer`), las rutas de personal responden `401`.
- **Catálogo público:** solo inmuebles aprobados y publicados, de todas las agencias; un inmueble no visible responde `404` igual que uno inexistente, y el detalle no expone dirección exacta, descripción ni historial.

Pruebas que respaldan cada fila:

| Regla | Pruebas |
|---|---|
| Personal de otra agencia y `platform_admin` en cada ruta de inmueble, listado y alta | `test_actors_outside_the_agency_are_forbidden_on_every_listing_route`, `test_actors_outside_the_agency_cannot_list_or_create_its_listings`, `test_staff_list_and_detail_forbid_other_tenants_and_platform_admin`, `test_cross_tenant_listing_access_is_forbidden_without_mutation`, `test_platform_admin_is_forbidden_from_tenant_listing_routes` (`backend/tests/test_f04_publications.py`) |
| ID ajeno en la ruta propia | `test_foreign_listing_id_under_own_agency_path_is_indistinguishable_from_missing`, `test_staff_detail_of_foreign_or_missing_listing_is_an_identical_404` |
| El agente no aprueba, rechaza, publica ni retira | `test_agent_cannot_self_approve_or_run_admin_only_transitions` |
| Depósito solo para el `agency_admin` dueño | `test_only_owning_agency_admin_can_configure_listing_deposit` (`backend/tests/test_catalog.py`) |
| Sesión real requerida (anónimo, token inválido, token de cliente) | `test_staff_listing_routes_require_a_staff_session_with_real_authentication` |
| Catálogo público transversal y sin privados | `test_public_list_is_approved_published_and_cross_agency`, `test_missing_and_non_visible_listing_detail_return_same_404`, `test_detail_has_minimal_public_schema_and_hides_private_fields` (`backend/tests/test_catalog.py`) |
| Fotos: otra agencia y `platform_admin`, inmueble o foto ajenos, catálogo solo con fotos confirmadas de inmuebles publicados | `test_actors_outside_the_agency_are_forbidden_on_photo_routes`, `test_foreign_listing_or_photo_under_own_agency_is_indistinguishable_from_missing`, `test_public_catalog_shows_only_confirmed_photos_of_published_listings` (`backend/tests/test_listing_photos.py`) |

El catálogo público sigue siendo transversal entre agencias, sin exponer el historial privado.

## Errores

| HTTP | Uso |
|---:|---|
| `401` | Sin sesión de personal válida (incluye tokens de cliente). |
| `403` | Rol no autorizado, `platform_admin` o tenant distinto. |
| `404` | Inmueble inexistente o de otra agencia, pedido con la ruta de la agencia autorizada. |
| `409` | Acción incompatible con el estado actual; envío sin foto confirmada; límite de 10 fotos; foto todavía no subida o fuera de su ventana de subida. |
| `422` | Cuerpo inválido, campo extra, precio no positivo, motivo de rechazo vacío, tipo o tamaño de foto no admitidos, o archivo subido que no es una foto válida. |
| `503` | Almacenamiento de fotos no configurado o no disponible. |

Las rutas utilizan el formato de error HTTP existente; no cambian el manejador global.

## Historial y versión comercial

Cada creación, edición o transición exitosa agrega una fila en `listing_transition`, con actor y rol resueltos por el servidor, estados anterior y nuevo, observación y fecha. La mutación del inmueble y su fila de historial se confirman en una misma transacción. El historial solo está disponible en la ruta de personal.

La versión comercial comienza en `1` y la controlan los disparadores existentes de la migración `0007_catalog_offers.py`: cambia cuando cambia `base_price`, `operation` o los extras del inmueble. Una edición descriptiva (por ejemplo, de `description`) no cambia `offer_version` ni invalida una cotización; un cambio comercial sí. La API F04 no modifica extras. Una reserva aceptada conserva su instantánea comercial.

## Límites y estado de validación

- F04.2, fotografías: implementado el 2026-10-06 (`odd/tasks/f04-photos.md`). La columna antigua `listing.photos` sigue sin uso y no se acepta en los cuerpos. En el stack local, Floci no valida firmas: acepta enlaces alterados, vencidos o sin firma. El control de firma, vencimiento y `Content-Type` en el almacenamiento solo lo aplica S3 real y no se verificó en un entorno desplegado. No hay política de retención ni borrado automático de fotos; al retirar un inmueble, sus fotos se conservan.
- No se crean revisiones inmutables versionadas del inmueble. La edición modifica el registro existente y una publicación vuelve a requerir aprobación.
- La migración `0012_listing_transitions.py` se verificó después contra un PostgreSQL descartable (`docs/plan-maestro-roomforge.md` §1.4.2.bis) y el 2026-10-01 se aplicó en el PostgreSQL del stack local de desarrollo; no hay verificación en un entorno desplegado.
- Las rutas de listado y consulta de personal no requieren migración: usan columnas existentes.
- No se ejecutó ningún caso académico CP; la suite técnica no es evidencia de ejecución académica.
