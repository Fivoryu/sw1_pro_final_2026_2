# Paquete de captura F07 v2 (borrador) → worker3d

> **Estado:** **sustituido el 2026-11-15** por la sección del esquema `2` de `docs/api/f07-capture-package.md`, que es el contrato vigente. Este borrador se conserva solo como registro histórico; sus valores «por definir» quedaron resueltos (como supuestos no medidos) en el documento vigente.

## Propósito

El teléfono **no reconstruye ni usa ARCore ni ARKit**: graba un video del recorrido y los datos de sus sensores, y los entrega a `worker3d`. `worker3d` estima las poses de cámara, ajusta piso, paredes y techo, genera el plano 2D y la escena v2 paramétrica, y detecta muebles en el mismo trabajo.

## Qué no es

- No es fotogrametría densa: no se generan texturas ni mallas detalladas; la salida es la escena v2 paramétrica.
- No es una escena publicada: el resultado es un borrador que el agente revisa y decide qué muebles entran al contrato.
- No incluye profundidad ni poses del teléfono: todo se estima en el servidor.

## Estructura del paquete

```text
manifest.json
video.mp4        # recorrido completo; códec y resolución por definir
sensors.jsonl    # una muestra de sensores por línea, con marca de tiempo
```

## `sensors.jsonl`

Una línea JSON por muestra, ordenada por `t`:

```json
{ "t": 1234567890, "type": "gyro", "x": 0.01, "y": -0.02, "z": 0.00 }
{ "t": 1234567891, "type": "accel", "x": 0.10, "y": 9.78, "z": 0.20 }
{ "t": 1234567892, "type": "gravity", "x": 0.01, "y": 9.80, "z": 0.05 }
```

- `t`: nanosegundos de un reloj monótono, el **mismo reloj** que usa `video.startedAtNs` del manifiesto, para poder sincronizar sensores y cuadros.
- `type`: `gyro` (rad/s), `accel` (m/s²) o `gravity` (m/s²).
- La frecuencia de muestreo está **por definir**; el worker usa la gravedad solo para decidir qué es «arriba» (piso frente a techo), no para medir distancias.

## `manifest.json`

```json
{
  "schemaVersion": 2,
  "captureId": "uuid generado en el teléfono",
  "listingId": "uuid de la publicación",
  "device": { "model": "SM-S711B", "os": "android", "osVersion": "14" },
  "video": {
    "file": "video.mp4",
    "width": 1920,
    "height": 1080,
    "fps": 30,
    "startedAtNs": 1234567000
  },
  "sensors": { "file": "sensors.jsonl" },
  "rooms": [
    { "id": "room-1", "name": "Sala", "fromNs": 1234567000, "toNs": 1244567000 }
  ],
  "reference": { "kind": "tape", "lengthM": 3.2, "note": "ancho de la pared norte" }
}
```

| Campo | Regla |
|---|---|
| `rooms[]` | El agente marca con «Siguiente ambiente» el instante de cambio; cada ambiente cubre un intervalo del video. Los intervalos no se superponen. |
| `reference` | Opcional pero recomendada: sin una medida real el modelo queda **sin escala métrica**, y el worker lo advierte. |
| intrínsecos de cámara | No se envían: el SfM los estima. Si el sistema operativo expone la distancia focal, puede añadirse como pista (por definir). |

## Recomendaciones de captura (por validar en el piloto)

- Desactivar la estabilización electrónica del video si el teléfono lo permite: deforma los cuadros y degrada la geometría.
- Recorrer el perímetro a velocidad baja y constante, con buena luz, con solapamiento amplio entre cuadros y sin giros bruscos.
- Incluir en el recorrido elementos con textura (cuadros, marcos, zócalos): las paredes lisas son el caso difícil del SfM.
- Registrar una medida de referencia real de cada recorrido.

## Salida de `worker3d`

Sin cambios respecto del esquema `1`: `sceneDraft` (escena v2), `warnings` en español y, cuando haya detección, `volumeSuggestions`, con las mismas reglas de `docs/api/f07-capture-package.md` (§Resultado). Las advertencias nuevas previstas: «Sin medida de referencia: el modelo no tiene escala métrica», «Pared sin observar entre…», «Gravedad no disponible: no se distinguió piso de techo».

## Privacidad y retención

Igual que en el esquema `1` (decisión del operador, 2026-10-21): el video muestra el interior del inmueble, es privado de la agencia, nunca público, y se borra cuando la agencia acepta la escena generada o a los **30 días** de la subida, lo que ocurra primero. El tamaño máximo y el costo de almacenamiento del video están **por definir**.

## Pendiente

1. Aprobación del operador (plan maestro §F07, «Propuesta 2026-10-23»).
2. Piloto: tres habitaciones reales medidas con cinta, para medir la exactitud antes de prometerla.
3. Definir códec, resolución, tamaño máximo, frecuencia de sensores y subida por tramos o reanudable.
4. Confirmar licencias de cada componente en su `LICENSE` oficial.
