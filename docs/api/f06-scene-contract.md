# Contrato de Escena 3D (F06)

Define la estructura JSON estandarizada para representar inmuebles paramétricos antes de su renderizado.

## Estructura Base (Fixture Sintético)

```json
{
  "version": "1.0",
  "unit": "meters",
  "rooms": [
    {
      "id": "room_main",
      "height": 2.4,
      "contours": [
        { "x": 0, "z": 0 },
        { "x": 4, "z": 0 },
        { "x": 4, "z": 3 },
        { "x": 0, "z": 3 }
      ],
      "openings": [
        {
          "id": "door_1",
          "type": "door",
          "position": { "x": 2, "y": 0, "z": 0 },
          "width": 0.9,
          "height": 2.1
        }
      ]
    }
  ],
  "objects": [
    {
      "id": "ref_cube_1",
      "type": "placeholder",
      "position": { "x": 1, "y": 0, "z": 1 },
      "dimensions": { "width": 0.5, "height": 0.5, "depth": 0.5 },
      "color": "red"
    }
  ]
}
```

## Persistencia (F06.3)

La escena se persiste por inmueble en una fila de `listing_scene`; `listing_id` es la clave
primaria y una clave foránea a `listing.id` con borrado en cascada. La fila contiene el documento
completo en `scene` (JSONB), la fecha de guardado en `updated_at` y el identificador del miembro
del staff que lo guardó en `updated_by`.

Las rutas de staff requieren un miembro de la agencia del inmueble (`agency_admin` o `agent`):

- `GET /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/scene` devuelve `200` con el
  documento completo. Si todavía no hay una fila de escena, responde `404` con el error común
  `{ "detail": "Scene is not defined for this listing", "code": "scene_not_defined" }`.
  Si no existe el inmueble, conserva el `404` del detalle de staff de F04 (`code: "not_found"`).
- `PUT /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/scene` recibe y reemplaza el
  documento completo del contrato v1; no aplica parches ni combina campos con una escena anterior.
  Un documento válido responde `200` con la escena almacenada. La validación estricta rechaza
  versiones o unidades no admitidas y campos extra con `422` (`code: "scene_invalid"`). Un
  inmueble inexistente responde `404` (`code: "listing_not_found"`), y el acceso desde otra
  agencia responde `403` (`code: "forbidden"`).

Los errores conservan el sobre común `{ "detail": "...", "code": "..." }`. La escena se crea
al primer `PUT`; cada guardado posterior sustituye el documento y actualiza `updated_at` y
`updated_by`.
