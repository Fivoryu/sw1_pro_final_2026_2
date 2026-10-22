# Paquete de captura F07 → worker3d (borrador de contrato)

> **Estado:** borrador para congelar antes de implementar (plan maestro §F07, decisión 2026-10-21, F07.7).
> **Versión del esquema:** `1`.

## Propósito

El teléfono **no reconstruye**: registra el recorrido con la información que ARCore ya calcula y la entrega a `worker3d`, que genera el plano 2D, la escena v2 y los volúmenes de muebles. Este documento fija qué contiene el paquete y qué garantiza cada parte.

## Qué no es

- No es video continuo: solo **cuadros clave** seleccionados con seguimiento activo.
- No es fotogrametría: no se reconstruyen texturas ni mallas; la salida sigue siendo la escena v2 paramétrica.
- No es una escena publicada: el resultado es un borrador que la agencia revisa (F06.3).

## Estructura

Un paquete por ambiente capturado, empaquetado como ZIP:

```text
manifest.json
frames/000001.jpg        # imagen de cámara (CPU image de ARCore), JPEG
depth/000001.png         # profundidad en milímetros, PNG de 16 bits (opcional)
confidence/000001.png    # confianza de profundidad 0–255, PNG de 8 bits (opcional)
```

## `manifest.json`

```json
{
  "schemaVersion": 1,
  "captureId": "uuid generado en el teléfono",
  "listingId": "id del inmueble",
  "roomName": "Dormitorio 1",
  "capturedAt": "2026-10-21T22:10:00Z",
  "device": { "model": "SM-S711B", "arcoreVersion": "1.57.0", "depthSupported": true },
  "image": { "width": 640, "height": 480, "fx": 0, "fy": 0, "cx": 0, "cy": 0 },
  "depth": { "width": 160, "height": 120, "fx": 0, "fy": 0, "cx": 0, "cy": 0 },
  "floorY": -1.42,
  "planes": [
    {
      "id": "p1",
      "type": "floor | wall | ceiling",
      "pose": [0, 0, 0, 0, 0, 0, 1],
      "polygon": [[0.0, 0.0], [1.0, 0.0]]
    }
  ],
  "trajectory": [[0, 0.0, 0.0]],
  "keyframes": [
    {
      "index": 1,
      "timestampNs": 0,
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
| `pose` | Cámara (o plano) → mundo, `[tx, ty, tz, qx, qy, qz, qw]`. La cámara mira hacia su `-z` local, convención de ARCore. |
| `image` / `depth` | Intrínsecos de cada resolución por separado; la profundidad se publica en su propia resolución, sin reescalar. |
| `planes[].polygon` | Contorno en coordenadas locales `x/z` del plano, como lo entrega ARCore. |
| `trajectory` | `[t_ms, x, z]` desde el inicio del recorrido, una muestra cada ≥ 0,25 m. |
| Selección de cuadros clave | Solo con `TRACKING`; un cuadro nuevo cuando pasaron ≥ 0,5 s **y** la cámara se movió ≥ 0,25 m o giró ≥ 15°; máximo 600 por ambiente. |
| `depth` / `confidence` | `null` cuando el dispositivo no soporta Depth API; el worker no inventa profundidad. |
| `reference` | Medida de referencia opcional para la escala; `null` si no se tomó. |

## Flujo

1. El teléfono arma el paquete localmente y lo conserva hasta confirmar la subida (F07.5: sin duplicar ni perder).
2. La API emite una subida firmada al almacenamiento de objetos y registra un trabajo de reconstrucción, con el mismo patrón de cola, lease y reintentos de F08.4.
3. `worker3d` procesa el paquete y escribe un **borrador** de escena v2 con procedencia `reconstruction`; los muebles detectados entran como sugerencias de F08.5, nunca como inventario.
4. La agencia revisa el borrador en el editor (F06.3).

## Privacidad y retención

- Los cuadros muestran el interior del inmueble: son privados de la agencia, nunca públicos.
- Se borran del almacenamiento cuando el trabajo termina y la escena se acepta; el plazo exacto queda por definir.

## Pendiente para congelar

- Plazo de retención de los cuadros.
- Tamaño máximo del paquete y calidad JPEG (estimado de 6–25 MB por ambiente, **no medido**).
- Algoritmo del worker (ajuste de planos, contorno y ubicación de muebles por pose y profundidad): se decide en F07.7.
