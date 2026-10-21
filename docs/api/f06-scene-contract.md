# Contrato de Escena 3D (F06)

Define la estructura JSON estandarizada para representar inmuebles paramétricos antes de su renderizado.

## Estructura v2 — muros como fuente de verdad (vigente)

Desde el 2026-10-19 el contrato es **v2**: los muros son la fuente de verdad y las habitaciones
son complemento derivado (decisión del operador, `odd/tasks/f06-scene-contract-v2.md`). Las
aberturas son paramétricas: viven en una colección propia y se ubican con `wallId` más `position`
(0..1 a lo largo del muro), no con coordenadas absolutas. Mover un muro mueve sus aberturas; las
habitaciones nunca discrepan de los muros porque no guardan contornos.

```json
{
  "version": "2.0",
  "unit": "meters",
  "walls": [
    { "id": "wall-north", "start": { "x": 0, "z": 0 }, "end": { "x": 4, "z": 0 },
      "height": 2.4, "thickness": 0.15 }
  ],
  "openings": [
    { "id": "door_1", "wallId": "wall-north", "position": 0.5,
      "width": 0.9, "height": 2.1, "type": "door" }
  ],
  "rooms": [
    { "id": "room_main", "name": "Estar",
      "wallIds": ["wall-north", "wall-east", "wall-south", "wall-west"] }
  ],
  "objects": [
    { "id": "ref_cube_1", "type": "placeholder",
      "position": { "x": 1, "y": 0, "z": 1 },
      "dimensions": { "width": 0.5, "height": 0.5, "depth": 0.5 }, "color": "red" }
  ]
}
```

Reglas del documento v1:

- `walls[]`: `start`/`end` distintos entre sí (metros), `height` > 0, `thickness` > 0. `color`
  opcional por muro.
- `openings[]`: `type` es `door` o `window`; `position` ∈ [0,1] medido desde `start` del muro y
  centrado en ese punto; `width`/`height` > 0; `sillHeight` ≥ 0 (ventanas, default 0.9).
  `wallId` debe referenciar un muro del mismo documento.
- `rooms[]` (complemento): `wallIds` con al menos 3 ids distintos que forman un ciclo; el polígono
  se deriva encadenando los extremos de esos muros en orden. `name` y `color` opcionales.
  Los muros pueden compartirse entre habitaciones (tabique).
- `objects[]`: igual que en v1; `objects[].id` es el `extra_id` publicado (ver «Objetos y oferta»).

### Procedencia de la captura (F07, campos opcionales)

La app de captura (F07) declara de dónde sale cada medida. Son campos **aditivos y opcionales**:
un documento sin ellos sigue siendo válido, y cuando no se envían tampoco aparecen en la respuesta
(no se agregan valores por defecto). Si se envían, se validan:

- `walls[].heightSource`: procedencia de `height`. Valores admitidos:
  - `ceiling_plane`: altura medida contra un plano de techo detectado.
  - `wall_point`: altura medida con un punto marcado sobre el muro.
  - `manual`: altura ingresada a mano por el agente.
  - `assumed`: altura supuesta; **no fue medida** y no debe presentarse como medición.
- `objects[].source`: procedencia del volumen; `depth` (extraído de datos de profundidad durante el
  recorrido) o `manual` (ubicado a mano).
- `objects[].confidence`: número en [0, 1] con la confianza declarada por la captura.

Un valor fuera de dominio (por ejemplo `heightSource: "laser"` o `confidence: 1.5`) se rechaza con
`422 scene_invalid` y la ruta del campo en el detalle. Estos campos no asignan clase ni precio a un
objeto: la oferta sigue dependiendo de `objects[].id` (ver «Objetos y oferta»).

Validación (estilo `readProject` de openPlan3D): rechazo con `422 scene_invalid` y detalle con
ruta (`openings[0].wallId must refer to an existing wall`), integridad referencial completa,
ids duplicados por colección y rangos numéricos. Un documento almacenado que ya no valida contra
el contrato vigente se lee como `404 scene_not_defined` en staff y público: el cliente muestra su
estado honesto y el staff debe re-guardar. No se promete retrocompatibilidad de lectura de
documentos v1.

El recorrido colisiona contra los muros (segmentos con los tramos de abertura restados) y el
margen de cámara respeta el espesor: radio de cámara + `thickness/2` (distancia al borde pintado,
no a la línea central). `rooms` es metadato complementario: el visor la tolera ausente o
incompleta y nunca la usa para colisionar.

## Historia: v1 (superada, solo referencia)

Hasta el 2026-10-19 el contrato era `version: "1.0"`: habitaciones con `contours` absolutos y
aberturas con `position {x,y,z}` absoluta dentro de cada habitación. Se reemplaza por v2; no se
ofrece lectura retrocompatible (ver regla de `scene_not_defined` arriba).

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
  "objects": []
}
```

## Fixture canónica

El documento de referencia de la escena para todas las superficies es
`docs/api/f06-scene-fixture.json`, en v2: cuatro muros de espesor 0.15 m que cierran la
habitación `room_main` de 4 m × 3 m con 2.4 m de altura (los `wallIds` de la habitación forman el
ciclo); una abertura `door_1` tipo puerta centrada en `wall-north` (`position: 0.5`, 0.9 m × 2.1 m);
y tres cubos placeholder de 0.5 m por lado: `ref_cube_1` rojo en (1,0,1), `ref_cube_2` verde en
(3,0,1) y `ref_cube_3` azul en (2,0,2).

La fixture se consume sin alteraciones en:

- `backend/tests/test_listing_scene.py`, para la prueba de ida y vuelta PUT/GET de staff.
- `backend/tests/test_public_listing_scene.py`, para la lectura pública.
- `panel/staff-shell/src/application/sceneContract.test.ts`, que compara
  `DEFAULT_SCENE_DOCUMENT` con el archivo JSON.
- `apps/cliente_mobile/test/scene_fixture_test.dart`, cuyo parser conserva los
  números como números.
- `backend/tests/test_f10_agency_customer_journey.py`, para la prueba E2E entre
  superficies.

Si cambia la fixture, `DEFAULT_SCENE_DOCUMENT` en
`panel/staff-shell/src/application/sceneContract.ts` también debe cambiar en el
mismo commit: una prueba vitest fija la igualdad entre ambos documentos.

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
  documento completo del contrato v2; no aplica parches ni combina campos con una escena anterior.
  Un documento válido responde `200` con la escena almacenada. La validación estricta rechaza
  versiones o unidades no admitidas y campos extra con `422` (`code: "scene_invalid"`). Un
  inmueble inexistente responde `404` (`code: "listing_not_found"`), y el acceso desde otra
  agencia responde `403` (`code: "forbidden"`).

Los errores conservan el sobre común `{ "detail": "...", "code": "..." }`. La escena se crea
al primer `PUT`; cada guardado posterior sustituye el documento y actualiza `updated_at` y
`updated_by`.

## Versionado (F07.5)

La fila de `listing_scene` lleva una columna `revision` (entero, migración
`0024_listing_scene_revision`): la escena se crea con `revision = 1` y cada `PUT` exitoso la
incrementa en uno. Las escenas existentes antes de la migración quedan en `1`.

- `GET` y `PUT` de staff con respuesta `200` incluyen la cabecera `ETag: "<revision>"` (etiqueta
  fuerte, entre comillas). El cuerpo no cambia: sigue siendo el documento de escena.
- `PUT` acepta precondiciones opcionales:
  - `If-Match: "<n>"`: el guardado se aplica solo si existe una escena y su revisión es `n`.
    `If-Match: *` se cumple con cualquier escena existente. Una etiqueta débil (`W/"n"`) nunca se
    cumple, porque la comparación es fuerte.
  - `If-None-Match: *`: el guardado se aplica solo si el inmueble todavía no tiene escena (alta
    sin duplicar).
  - Si la precondición no se cumple, responde `412` con
    `{ "detail": "Scene was modified by another writer; reload it and retry", "code": "scene_conflict" }`
    y, si existe una escena, con la cabecera `ETag` de la revisión vigente. La escena almacenada
    no cambia.
- Sin precondiciones, el `PUT` conserva el comportamiento incondicional anterior (el panel sigue
  guardando así).
- Orden de evaluación: `422 scene_invalid` (documento), luego `404 listing_not_found`, luego
  `412 scene_conflict`. La precondición se evalúa dentro de la misma transacción, después de
  bloquear la fila del inmueble (`SELECT ... FOR UPDATE`), de modo que dos escritores con la misma
  revisión no pueden ganar ambos.
- CORS: la API expone `ETag` (`Access-Control-Expose-Headers`) y admite `If-Match` e
  `If-None-Match` en las solicitudes del origen del panel.
- La lectura pública (`GET /api/v1/listings/{listing_id}/scene`) no expone `ETag` ni la revisión.

## Lectura pública (F06.4)

La app cliente lee la escena de un inmueble publicado sin sesión ni credenciales:

- `GET /api/v1/listings/{listing_id}/scene` devuelve `200` con el documento completo del
  contrato v2. Es de solo lectura: no expone `updated_by`, la revisión ni rutas de escritura.
- Si el inmueble no existe o no está publicado y aprobado, responde `404` con el error común
  `{ "detail": "Listing not found", "code": "listing_not_found" }`: un borrador o rechazado es
  indistinguible de un inmueble inexistente.
- Si el inmueble está publicado pero todavía no tiene escena, responde `404` con
  `{ "detail": "Scene is not defined for this listing", "code": "scene_not_defined" }`, el mismo
  código de la ruta de staff, para que el cliente muestre su estado honesto de "recorrido no
  disponible".

El documento servido es exactamente el almacenado por F06.3; el cliente valida `version` y
`unit` antes de construir el recorrido y degrada con su estado de error si no coinciden.

## Objetos y oferta (F06.5)

Al tocar un objeto, el visor envía su identificador y la app abre la ficha del
objeto. Al confirmar, abre una pantalla mínima de cotización que llama a
`POST /api/v1/quotes` con `selected_extra_ids: [objectId]` y muestra la
instantánea devuelta. Por eso, `objects[].id` debe ser el `extra_id` de un extra
publicado del inmueble. Si no corresponde a un extra publicado, se muestra el
estado «Este objeto es parte del recorrido; no tiene precio publicado.» en
lugar de inventar un precio.

Un fallo de renderizado no modifica un precio ni una cotización y nunca crea una
reserva.

Las colisiones, las aberturas transitables y los límites del recorrido los decide
`apps/cliente_mobile/assets/viewer/geometry.mjs`, mediante funciones puras, no el
renderizador. El módulo está cubierto por 14 pruebas con `node --test`.
