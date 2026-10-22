# Paquete de captura F07 → worker3d

> **Estado:** congelado, versión de esquema `1` (2026-10-21). Plan maestro §F07, decisión 2026-10-21, F07.7.
> Cambios incompatibles requieren `schemaVersion: 2` y actualizar primero el plan maestro.

## Propósito

El teléfono **no reconstruye**: registra el recorrido con la información que ARCore ya calcula y la entrega a `worker3d`, que genera el plano 2D, la escena v2 y los volúmenes de muebles. Este documento fija qué contiene el paquete, cómo viaja y qué garantiza cada parte.

## Qué no es

- No es video continuo: solo **cuadros clave** seleccionados con seguimiento activo.
- No es fotogrametría: no se reconstruyen texturas ni mallas; la salida es la escena v2 paramétrica.
- No es una escena publicada: el resultado es un borrador que la agencia revisa (F06.3).

## Unidad: una sesión de recorrido

Un paquete corresponde a **una sesión de ARCore**, que puede abarcar varios ambientes. Todos los cuadros comparten el mismo sistema de coordenadas, por lo que los ambientes quedan alineados sin unión manual. El agente marca el cambio de ambiente con «Siguiente ambiente»; cada cuadro clave lleva el ambiente activo. Si la sesión se reinicia, se abre un paquete nuevo y la alineación entre paquetes vuelve al respaldo manual por puertas de F07.4.

## Estructura del ZIP

```text
manifest.json
frames/000001.jpg        # imagen de cámara (CPU image de ARCore), JPEG calidad 80
depth/000001.png         # profundidad en milímetros, PNG de 16 bits (opcional)
confidence/000001.png    # confianza de profundidad 0–255, PNG de 8 bits (opcional)
```

## `manifest.json`

```json
{
  "schemaVersion": 1,
  "captureId": "uuid generado en el teléfono",
  "listingId": "id del inmueble",
  "capturedAt": "2026-10-21T22:10:00Z",
  "device": { "model": "SM-S711B", "arcoreVersion": "1.57.0", "depthSupported": true },
  "image": { "width": 640, "height": 480, "fx": 0, "fy": 0, "cx": 0, "cy": 0 },
  "depth": { "width": 160, "height": 120, "fx": 0, "fy": 0, "cx": 0, "cy": 0 },
  "floorY": -1.42,
  "rooms": [{ "id": "room-1", "name": "Dormitorio 1" }],
  "planes": [
    {
      "id": "p1",
      "type": "floor",
      "pose": [0, 0, 0, 0, 0, 0, 1],
      "polygon": [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0]]
    }
  ],
  "trajectory": [[0, 0.0, 0.0, "room-1"]],
  "keyframes": [
    {
      "index": 1,
      "timestampNs": 0,
      "roomId": "room-1",
      "pose": [0, 0, 0, 0, 0, 0, 1],
      "image": "frames/000001.jpg",
      "depth": "depth/000001.png",
      "confidence": "confidence/000001.png"
    }
  ],
  "reference": { "meters": 3.20, "from": [0, 0, 0], "to": [3.2, 0, 0] }
}
```

## Reglas

| Campo | Regla |
|---|---|
| Sistema de coordenadas | Mundo de ARCore de la sesión: metros, `y` hacia arriba. |
| `pose` | Cámara (o plano) → mundo, `[tx, ty, tz, qx, qy, qz, qw]`. La cámara mira hacia su `-z` local (convención de ARCore). |
| `image` / `depth` | Intrínsecos de cada resolución por separado; la profundidad va en su propia resolución, sin reescalar. |
| `floorY` | Altura del piso detectado en el mundo; `null` si no se detectó (el worker rechaza el paquete). |
| `rooms` | Al menos uno; `id` único dentro del paquete; `name` es el que escribió el agente. |
| `planes[].type` | `floor`, `wall` o `ceiling`. `polygon` en coordenadas locales `x/z` del plano, como lo entrega ARCore. Estado al cerrar la sesión. |
| `trajectory` | `[t_ms, x, z, roomId]` desde el inicio, una muestra cada ≥ 0,25 m. |
| Cuadros clave | Solo con `TRACKING`; uno nuevo cuando pasaron ≥ 0,5 s **y** la cámara se movió ≥ 0,25 m o giró ≥ 15°. Máximo 600 por paquete. |
| `depth` / `confidence` | `null` cuando el dispositivo no soporta Depth API; el worker no inventa profundidad. |
| `reference` | Medida de referencia opcional para la escala; `null` si no se tomó. |
| Tamaño | Máximo 150 MB por ZIP; la API rechaza paquetes más grandes. El tamaño típico está **sin medir** (estimado: 6–25 MB por ambiente). |

## API (staff, aislada por agencia como el resto de `/api/v1/staff`)

| Método y ruta | Uso |
|---|---|
| `POST /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/captures` | Registra la captura. Cuerpo: `{ "captureId", "sizeBytes" }`. Idempotente por `captureId`: repetir devuelve la misma captura. Responde `201` (o `200` al repetir) con `{ "captureId", "status", "uploadUrl", "expiresAt" }`. |
| `PUT {uploadUrl}` | Subida directa del ZIP al almacenamiento de objetos (URL firmada, corta duración). |
| `POST …/captures/{capture_id}/complete` | Confirma la subida y encola la reconstrucción. Idempotente. `202` con `{ "captureId", "status": "queued" }`. |
| `GET …/captures` | Lista las capturas del inmueble, de la más nueva a la más vieja: `{ "captures": [ …mismo cuerpo que el `GET` individual… ] }`. Agregada el 2026-10-22 para que el panel descubra las capturas sin conocer sus ids (cambio aditivo). |
| `GET …/captures/{capture_id}` | Estado: `awaiting_upload`, `queued`, `processing`, `completed`, `failed`, `accepted`; si hay resultado, incluye `sceneDraft` (escena v2) y `warnings`; si falló, `failureReason`. |
| `POST …/captures/{capture_id}/accept` | La agencia aceptó el borrador (lo guardó en el editor): pasa a `accepted` y programa el borrado de los cuadros. Solo desde `completed`; idempotente. |

### Worker (interno, mismo patrón que `/api/v1/detection/jobs` de F08.4)

| Método y ruta | Uso |
|---|---|
| Mensaje de cola | `{ "job_id": "…" }` en una cola propia de reconstrucción. |
| `POST /api/v1/reconstruction/jobs/{job_id}/claim` | Token del worker. Responde `{ "job_id", "status": "running", "download_url", "claim_token" }` o un estado terminal si no hay trabajo que hacer. |
| `POST /api/v1/reconstruction/jobs/{job_id}/complete` | Token del worker + `X-Reconstruction-Claim-Token`. Cuerpo `{ "sceneDraft", "warnings" }`; la API valida `sceneDraft` con la validación estricta de la escena v2 antes de guardarlo. |
| `POST /api/v1/reconstruction/jobs/{job_id}/fail` | Token del worker + claim token. Cuerpo `{ "reason", "retryable" }`. |

La API es la única que escribe el estado; los leases vencidos se recuperan por barrido; los reintentos son acotados y un paquete inválido (`retryable: false`) termina en `failed` con motivo, sin reintentar.

## Resultado

- `sceneDraft`: escena v2 completa (contrato `docs/api/f06-scene-contract.md`) que usa solo los campos de procedencia que ese contrato admite (`walls[].heightSource`; `objects[].source: "depth"` con `confidence`); volúmenes sin clase ni precio (F07.6). La procedencia «reconstrucción» de todo el borrador la registra la captura en la API, no cada elemento de la escena.
- `warnings`: lista de textos para la agencia (por ejemplo, «Pared sin observar entre…», «Sin profundidad: no se generaron volúmenes»).
- Los muebles con clase sugerida por el detector entran como sugerencias de F08.5, nunca como inventario.
- La agencia carga el borrador en el editor (F06.3) y lo guarda con el `PUT` de escena existente; nada se publica solo.

## Privacidad y retención (decisión del operador, 2026-10-21)

- Los cuadros muestran el interior del inmueble: son privados de la agencia, nunca públicos.
- Se borran del almacenamiento cuando la agencia acepta la escena generada, o a los **30 días** desde la subida si nadie la revisa, lo que ocurra primero. Hasta entonces se pueden reprocesar.
- El `sceneDraft` y el `manifest.json` sin imágenes se conservan como registro de la captura.
