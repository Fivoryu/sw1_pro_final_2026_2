# Paquete de captura F07 → worker3d

> **Correcciones de integridad, 2026-11-17:** la sección «Endurecimiento aditivo» al final precisa la validación de subida, referencia y salida privada. Sustituye las descripciones anteriores que permiten aplicar un borrador sin escala. No acredita QA física.

> **Estado:** este documento contiene dos contratos.
> - **Esquema `2` (vigente para la captura por video, congelado el 2026-11-15):** primera parte. Sustituye al borrador `docs/api/f07-capture-package-v2-borrador.md`. Dirección aprobada el 2026-10-23 (plan maestro §F07, «Decisión 2026-10-23»).
> - **Esquema `1` (heredado, congelado el 2026-10-21):** segunda parte. Es el contrato del código ARCore existente, que lo sigue consumiendo. Plan maestro §F07, decisión 2026-10-21, F07.7.
>
> **Valores no medidos:** todos los parámetros del esquema `2` (códec, resolución, tasas, límites, formas de la referencia) son **supuestos** fijados para que la app, el backend y `worker3d` compartan un único contrato. Ninguno está medido ni verificado con una grabación real, y la primera grabación real (tarea T1 del registro `odd/tasks/f07-video-capture-reconstruction.md`) puede obligar a reabrirlos. Este documento **no promete ninguna exactitud** de medidas.

# Parte 1 — Esquema `2` (captura por video, vigente)

## Propósito (esquema `2`)

El teléfono **no reconstruye ni usa ARCore ni ARKit**: graba un video del recorrido y los datos de sus sensores, y los entrega a `worker3d`. `worker3d` estima las poses de cámara, ajusta piso, paredes y techo, genera la escena v2 paramétrica y detecta muebles en el mismo trabajo. Los muebles detectados entran solo como sugerencias de F08.5, nunca como inventario.

## Qué no es (esquema `2`)

- No es fotogrametría densa: no se generan texturas ni mallas; la salida es la escena v2 paramétrica.
- No es una escena publicada: el resultado es un borrador que el agente revisa.
- No incluye profundidad ni poses del teléfono: todo se estima en el servidor.

## Estructura del paquete

ZIP con cuatro archivos:

```text
manifest.json
video.mp4        # recorrido completo, sin pista de audio
frames.jsonl     # una línea por cuadro del video
sensors.jsonl    # una línea por muestra de sensor
```

## `video.mp4`

| Parámetro | Valor (supuesto, no medido) |
|---|---|
| Códec y contenedor | H.264/AVC en MP4 |
| Resolución | Negociada con la cámara: la app prefiere 1440×1080 (4:3) y cae a 1280×960 o, como último recurso, 1280×720 (16:9); el tamaño elegido queda en `video.width` y `video.height` |
| Cuadros por segundo | 30 |
| Tasa de bits objetivo | 3,5 Mbps para 1440×1080; para los otros tamaños, proporcional a los píxeles con piso de 3 Mbps |
| Audio | **Sin pista de audio** (privacidad) |
| Estabilización electrónica | Desactivada cuando el dispositivo lo permita (deforma los cuadros y degrada la geometría) |

## `frames.jsonl`

Una línea JSON por cuadro del video:

```json
{ "i": 0, "t": 1234567000 }
```

- `i`: índice del cuadro, desde 0; los valores son consecutivos (la línea de posición `n` lleva `i = n`).
- `t`: marca original `SENSOR_TIMESTAMP` de Camera2, en nanosegundos. Coincide con `elapsedRealtimeNanos` solo si `timestampSource` es `realtime`; con `unknown` no se presume sincronía con sensores. Debe ser **estrictamente creciente**.
- Máximo 20 000 líneas (límite elegido durante la implementación, no medido); el archivo debe tener al menos una. Las líneas vacías se ignoran.

## `sensors.jsonl`

Una línea JSON por muestra, ordenada por `t`:

```json
{ "t": 1234567000, "type": "gyro", "x": 0.01, "y": -0.02, "z": 0.00 }
{ "t": 1234567010, "type": "accel", "x": 0.10, "y": 9.78, "z": 0.20 }
{ "t": 1234567020, "type": "gravity", "x": 0.01, "y": 9.80, "z": 0.05 }
{ "t": 1234567030, "type": "mag", "x": 21.0, "y": -3.5, "z": 40.2 }
```

- `t`: nanosegundos del reloj de eventos de sensores Android (`elapsedRealtimeNanos`). Solo se alinea con cuadros y `video.startedAtNs` cuando Camera2 declara `realtime`. El archivo debe estar ordenado por `t` (no decreciente); un archivo desordenado se rechaza.
- Máximo 400 000 líneas (límite elegido durante la implementación, no medido). Cada línea necesita `t` entero, un `type` conocido y `x`, `y`, `z` numéricos.
- `type`: `gyro` (rad/s), `accel` (m/s²), `gravity` (m/s²) o `mag`. `mag` es opcional y `worker3d` **no lo usa**; se registra pero no es un dato confiable.
- Frecuencia solicitada: 100 Hz. Es la tasa pedida al sistema operativo; la tasa real entregada no está medida.
- Los valores van en **ejes crudos del dispositivo Android** (convención de `TYPE_GRAVITY` para `gravity`). `mag` se acepta y el worker lo ignora.
- `worker3d` usa la gravedad para decidir qué es «arriba» (piso frente a techo), no para medir distancias.

## `manifest.json`

```json
{
  "schemaVersion": 2,
  "captureId": "uuid generado en el teléfono",
  "listingId": "uuid de la publicación",
  "device": { "model": "SM-S711B", "os": "android", "osVersion": "14" },
  "video": {
    "file": "video.mp4",
    "width": 1440,
    "height": 1080,
    "fps": 30,
    "startedAtNs": 1234567000,
    "sensorOrientation": 90,
    "framesFile": "frames.jsonl",
    "timestampSource": "realtime"
  },
  "sensors": { "file": "sensors.jsonl", "rateHz": 100 },
  "rooms": [
    { "id": "room-1", "name": "Sala", "fromNs": 1234567000, "toNs": 1244567000 },
    { "id": "room-2", "name": "Dormitorio 1", "fromNs": 1244567000, "toNs": 1254567000 }
  ],
  "reference": {
    "kind": "object",
    "label": "Puerta",
    "lengthM": 2.0,
    "surface": "floor",
    "frameNs": 1234900000,
    "p1": { "x": 0.31, "y": 0.80 },
    "p2": { "x": 0.33, "y": 0.12 }
  }
}
```

| Campo | Regla |
|---|---|
| `schemaVersion` | Entero `2`. |
| `captureId` | Identificador generado en el teléfono; coincide con el de la API de capturas. |
| `listingId` | Obligatorio y no vacío. Identificador de la publicación. |
| `device` | `{ model, os, osVersion }`. |
| `video` | `{ file, width, height, fps, startedAtNs, sensorOrientation, framesFile, timestampSource }`. `timestampSource` es `"realtime"` o `"unknown"`; con `"unknown"` los relojes de cuadros y sensores no se pueden asumir alineados y el worker lo advierte. |
| `sensors` | `{ file, rateHz }`. `rateHz` es la frecuencia solicitada. |
| `video.sensorOrientation` | Obligatorio. Entero `0`, `90`, `180` o `270` (`SENSOR_ORIENTATION` de Camera2). Solo cámara trasera. Los cuadros se guardan **sin rotar** y no se establece indicador de rotación en el MP4. |
| `rooms[]` | `{ id, name, fromNs, toNs }`. Al menos uno. Los intervalos no se superponen y son semiabiertos `[fromNs, toNs)`: ambientes adyacentes pueden compartir frontera; un cuadro exactamente en `toNs` pertenece al ambiente siguiente; el `toNs` del último ambiente es la marca del último cuadro más 1. El agente marca el cambio con «Siguiente ambiente»; cada ambiente cubre un intervalo del video en el reloj `elapsedRealtimeNanos`. |
| `reference` | Opcional. Ver «Referencia de escala». |
| Intrínsecos de cámara | No se envían: el SfM los estima. |

### Referencia de escala (`reference`)

Antes de grabar, el agente elige un objeto de tamaño conocido (hoja A4, tarjeta, baldosa, puerta estándar editable o un valor libre) y marca sus dos extremos sobre un cuadro del video.

- `kind`: `"object"`.
- `label`: nombre del objeto, por ejemplo `"Puerta"`.
- `lengthM`: longitud real entre los dos puntos, en metros.
- `surface`: `"floor"` o `"wall"`; indica sobre qué superficie está apoyado el objeto.
- `frameNs`: marca de tiempo (mismo reloj) del cuadro sobre el que se marcaron los puntos. Debe ser una marca listada en `frames.jsonl` y caer dentro de un intervalo de `rooms[]`. La referencia se marca sobre un cuadro congelado al inicio de la grabación, antes de que el agente empiece a caminar; no puede marcarse antes de iniciar la grabación porque el cuadro debe existir en el video. Si la referencia no queda cubierta, la app la descarta y avisa.
- `p1`, `p2`: extremos marcados sobre ese cuadro, normalizados a 0..1 con origen arriba a la izquierda, sobre el cuadro **tal como está almacenado en `video.mp4`** (sin rotar), no sobre una vista previa rotada.
- `rect` (opcional, aditivo; decisión 2026-11-16 del dueño: detección automática del objeto de referencia como rectángulo): el objeto es un rectángulo de medidas reales conocidas apoyado sobre `surface`. Campos:
  - `widthM`, `heightM`: lados reales en metros, con `widthM >= heightM`. **Invariante:** `widthM == lengthM`; el lado largo es el que va de `p1` a `p2`.
  - `corners`: cuatro puntos `{x, y}` normalizados 0..1 con el mismo origen y el mismo cuadro que `p1`/`p2`, en orden de recorrido que empieza en `p1`: `corners[0] == p1`, `corners[1] == p2` (lado largo, `widthM`), `corners[2]` y `corners[3]` cierran el rectángulo (`corners[1]→corners[2]` es el lado corto, `heightM`).
  - `source`: `"auto"` (detectado por la app y confirmado por el agente), `"adjusted"` (detectado y corregido a mano) o `"manual"` (marcado a mano).
  - Un paquete sin `rect` sigue siendo válido y se interpreta como hasta ahora (solo `p1`/`p2`). `p1`, `p2` y `lengthM` siguen siendo obligatorios aunque haya `rect`, para que los consumidores del esquema `2` anteriores sigan funcionando. Un `rect` incoherente con ellos (`widthM != lengthM`, `corners[0] != p1` o `corners[1] != p2`, esquinas fuera de 0..1 o `heightM > widthM`) se rechaza como paquete inválido.

Con `rect`, `worker3d` calcula **dos** estimaciones de escala sobre el mismo plano: `widthM` contra la distancia reconstruida entre `corners[0]` y `corners[1]`, y `heightM` contra la distancia entre `corners[1]` y `corners[2]`. Si difieren más de un **8 %** (**supuesto, no medido**) emite una advertencia (el objeto pudo estar inclinado o mal detectado) y usa la estimación del lado largo; si coinciden, usa el promedio ponderado por longitud. Cuando hay una biblioteca de visión disponible, el worker puede además refinar las esquinas a precisión de subpíxel sobre el cuadro de referencia; sin ella, usa las esquinas tal como llegan y no falla. Ninguna de estas cifras es una exactitud medida.

`worker3d` intersecta los rayos de `p1` y `p2` con el plano ajustado indicado por `surface` para obtener la distancia reconstruida entre ambos puntos; la escala métrica es `lengthM` dividida por esa distancia. La referencia se filma solo al inicio: el resto del recorrido no la necesita a la vista mientras la reconstrucción sea una sola pieza.

Sin `reference`, el modelo queda **sin escala métrica** y el worker lo advierte. Las medidas obtenidas con esta escala son **estimadas** hasta que el agente las confirme (registro de procedencia del flujo de planos); no se promete exactitud.

## Límites

| Límite | Valor (supuesto, no medido) |
|---|---|
| Tamaño máximo del ZIP | El `MAX_PACKAGE_BYTES` vigente: 150 MiB |
| Duración máxima | 5 minutos; la app corta la grabación a ese tiempo |
| Líneas de `frames.jsonl` / `sensors.jsonl` | 20 000 / 400 000 (límites elegidos durante la implementación, no medidos) |

**Diferencia conocida:** el límite de 150 MiB se mide de forma distinta según quién lo aplica. La app y el backend cuentan el tamaño del **ZIP**; `worker3d` cuenta los bytes **sin comprimir** de `video.mp4`, `frames.jsonl` y `sensors.jsonl` (no incluye `manifest.json`). No se ha unificado; un paquete puede pasar el límite del ZIP y ser rechazado por el worker.

El tamaño típico de un paquete de este esquema está **sin medir**. A 3,5 Mbps (el valor objetivo de 1440×1080), 5 minutos de video ocuparían del orden de 125 MiB (unos 131 MB) sin contar sensores; es una cuenta aritmética sobre el valor objetivo, no una medición.

## Subida

Usa el flujo vigente de la API de capturas, sin cambios (ver «API» en la parte 2): registro, subida con URL prefirmada y completado. La app recorre este flujo con una máquina de etapas reanudable; no hay subida por tramos. El backend trata el ZIP como **opaco** (solo verifica el tamaño declarado frente al límite); **la validación del contenido la hace `worker3d`**, y un paquete inválido termina en `failed` con motivo, sin reintentos (`retryable: false`).

## Compatibilidad entre esquemas `1` y `2`

> **Implementado en backend (T4):** no hay código nuevo; el backend ya cumple este contrato porque trata el ZIP como opaco. Límite de 150 MiB sobre el ZIP (`422` al registrar), mismo mensaje de cola para ambos esquemas y retención de 30 días desde la subida o al aceptar, fijados por `backend/tests/test_reconstruction_v2.py`. El rechazo de `schemaVersion` desconocido ocurre en `worker3d`, no en el backend.


- El esquema se identifica por `manifest.json` → `schemaVersion`.
- Un paquete `1` (ARCore) y uno `2` (video) son formatos distintos y no se convierten entre sí; ningún campo del esquema `1` se reinterpreta en el `2`.
- `reconstruct.py` y su worker siguen consumiendo el esquema `1` sin cambios; la reconstrucción desde video convive con ellos y consume solo el esquema `2`.
- La API de capturas y el flujo de subida son los mismos para ambos; el contrato de salida no cambia.
- Un `schemaVersion` desconocido o un archivo faltante hace que el worker rechace el paquete como inválido, sin reintentar.

## Recomendaciones de captura (por validar en el piloto)

- Recorrer el perímetro a velocidad baja y constante, con buena luz, con solapamiento amplio entre cuadros y sin giros bruscos.
- Incluir elementos con textura (cuadros, marcos, zócalos): las paredes lisas son el caso difícil del SfM.
- Filmar la referencia de escala al inicio del recorrido.

## Guía en vivo durante la grabación (S8)

La guía visual usa copias asíncronas de la vista previa, hasta 192×192 y una por segundo, con un solo análisis en vuelo. Evalúa luz, detalle y coincidencias locales sin depender de giroscopio. Los pasos se avanzan explícitamente; las muestras útiles indican solapamiento local, no paredes ni cobertura 3D verificadas. Puede desactivarse y su indisponibilidad no impide grabar/guardar. Los candidatos rectangulares no identifican A4 ni medidas: las esquinas se ajustan y las dimensiones reales en cm se confirman sobre el cuadro codificado al finalizar. No se guardan imágenes de análisis ni se cambia el esquema.

`CaptureGuidance.kt` conserva las señales de sensores heredadas descritas abajo; no acreditan cobertura ni posición y no sustituyen la guía visual en la pantalla de video.

| Aviso | Señal | Umbral (supuesto, no medido) |
| --- | --- | --- |
| Movimiento brusco | Magnitud del giroscopio suavizada (constante de tiempo 0,3 s) | 2,0 rad/s |
| Giro rápido («velocidad») | Misma señal | 0,8 rad/s |
| Poca luz | `SENSOR_SENSITIVITY` (ISO) de Camera2 | 1600 o más durante 15 capturas seguidas (~0,5 s) |
| Cerrar el recorrido | Rumbo integrado del giroscopio sobre el eje de la gravedad | Tras 60 s, con 300° de giro acumulado y el rumbo neto de vuelta a una vuelta completa (±30°); se sugiere una sola vez |

Límites declarados: la «velocidad» es la de giro (el acelerómetro no se integra a velocidad de marcha porque deriva); el cierre se basa en el rumbo, no en la posición, así que puede avisar sin que el agente esté cerca del inicio. **«Pared faltante» no se implementa**: el contrato no define una señal de sensor para detectarla (queda como pendiente abierto; el worker ya advierte «Pared sin observar» al reconstruir). Ningún umbral fue medido; el piloto T1 puede reabrirlos.

## Salida de `worker3d`

Sin cambios respecto del esquema `1` (ver «Resultado» en la parte 2): `sceneDraft` (escena v2), `warnings` en español y, cuando haya detección, `volumeSuggestions`, con las mismas reglas.

Muebles del esquema `2` (F07 T6): no hay mapa de profundidad, así que `worker3d` corre el detector de F08 sobre hasta 40 cuadros muestreados y ubica cada caja con las poses estimadas y los puntos dispersos que caen dentro de ella (huella y altura del volumen sobre el piso ajustado). El resultado son volúmenes `occupancy` simples (sin clase ni precio) y `volumeSuggestions` con las mismas reglas que el esquema `1`; `keyframe` es el índice `i` de `frames.jsonl` más 1. Sin detector disponible no hay sugerencias y se agrega una advertencia; si hubo detecciones pero ningún punto las respalda, la advertencia es «Sin profundidad: no se generaron volúmenes». Las sugerencias quedan pendientes de la revisión humana de F08.5 y su exactitud no se midió.

Advertencias nuevas previstas para el esquema `2`:

- «Sin medida de referencia: el modelo no tiene escala métrica».
- «Pared sin observar entre…».
- «Gravedad no disponible: no se distinguió piso de techo».
- Aviso cuando el «arriba» derivado de la gravedad difiere del plano de piso o techo ajustado en más de 10° (tolerancia heurística, no medida).
- Sin referencia utilizable, la escena queda en unidades arbitrarias con un aviso: no existe escala de respaldo (la decisión D3 sigue abierta).
- Para ensamblar exclusivamente contornos sin escala se normaliza la extensión de trayectoria a 10 unidades **adimensionales**, haciendo las heurísticas relativas a ella; no son metros ni una escala física de respaldo. Las piezas métricas conservan su factor medido y sus validaciones.

Otros comportamientos: un `schemaVersion` explícito distinto de 1 o 2 se rechaza como `unsupported schemaVersion`, y la app rechaza antes de subir un paquete superior a 150 MiB. Estos valores y tolerancias son supuestos no medidos.

## Privacidad y retención (esquema `2`)

- El video muestra el interior del inmueble: es privado de la agencia y nunca público. **No tiene pista de audio.**
- Se borra del almacenamiento cuando la agencia acepta la escena generada o a los **30 días** desde la subida, lo que ocurra primero (decisión del operador, 2026-10-21). Hasta entonces se puede reprocesar.
- El `sceneDraft` y el `manifest.json` se conservan como registro de la captura.

## Pendiente (esquema `2`)

1. **Piloto de medición con una grabación real (T1):** tres habitaciones reales medidas con cinta, para medir la exactitud, el tiempo de CPU sin GPU y el comportamiento en paredes lisas antes de prometer nada. Hasta entonces todos los valores de este esquema son supuestos.
2. Confirmar la licencia de cada componente (COLMAP y los demás que se evalúen) en su `LICENSE` oficial; no está verificada.
3. Sin medir: tasa real de muestreo de sensores, tamaño típico del paquete, calidad de sincronización cuadro/sensor entre dispositivos (S23 FE y A53).
4. Respaldo de escala cuando no hay objeto de referencia (decisión D3, depende de T1).
5. Los signos y mapeos de ejes de la gravedad para las orientaciones 0, 180 y 270 están derivados y aún no probados en un dispositivo; confundir la orientación 90 con la 270 podría pasar sin detectarse.

# Parte 2 — Esquema `1` (heredado, ARCore)

> **Estado de esta parte:** congelado, versión de esquema `1` (2026-10-21). Plan maestro §F07, decisión 2026-10-21, F07.7. Es el contrato del código ARCore existente; la captura por video usa el esquema `2`.
> Cambios incompatibles del esquema `1` requieren `schemaVersion` nuevo y actualizar primero el plan maestro.

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
| `POST /api/v1/reconstruction/jobs/{job_id}/complete` | Token del worker + `X-Reconstruction-Claim-Token`. Cuerpo `{ "sceneDraft", "warnings", "volumeSuggestions"? }`; la API valida `sceneDraft` con la validación estricta de la escena v2 antes de guardarlo. `volumeSuggestions` es opcional (ver «Resultado»). |
| `POST /api/v1/reconstruction/jobs/{job_id}/fail` | Token del worker + claim token. Cuerpo `{ "reason", "retryable" }`. |

La API es la única que escribe el estado; los leases vencidos se recuperan por barrido; los reintentos son acotados y un paquete inválido (`retryable: false`) termina en `failed` con motivo, sin reintentar.

## Resultado

- `sceneDraft`: escena v2 completa (contrato `docs/api/f06-scene-contract.md`) que usa solo los campos de procedencia que ese contrato admite (`walls[].heightSource`; `objects[].source: "depth"` con `confidence`); volúmenes sin clase ni precio (F07.6). `worker3d` etiqueta las alturas derivadas del video como `heightSource: "estimated"` cuando se ajustó un techo y como `assumed` en caso contrario; el agente las confirma pasándolas a `manual`. La procedencia «reconstrucción» de todo el borrador la registra la captura en la API, no cada elemento de la escena.
- `warnings`: lista de textos para la agencia (por ejemplo, «Pared sin observar entre…», «Sin profundidad: no se generaron volúmenes»).
- Los muebles con clase sugerida por el detector entran como sugerencias de F08.5, nunca como inventario.
- `volumeSuggestions` (opcional, aditivo): `{ "modelId": str (1..64), "items": [ { "objectId": str (1..64), "label": str (1..64), "score": 0..1, "keyframe": entero ≥ 1, "box": [x1, y1, x2, y2] } ] }`, máximo 100 ítems. Cada `objectId` debe ser un objeto `occupancy` del `sceneDraft` y no repetirse; de lo contrario `422` con `code: "volume_suggestions_invalid"` y la captura sigue en `processing`. Se guarda en `listing_capture.volume_suggestions` (migración `0026_capture_volume_suggestions`) y solo lo lee la revisión de F08.5; nunca modifica la escena ni el inventario. Sin el campo el comportamiento es idéntico al anterior y se guarda `NULL`.
- La agencia carga el borrador en el editor (F06.3) y lo guarda con el `PUT` de escena existente; nada se publica solo.

## Privacidad y retención (decisión del operador, 2026-10-21)

- Los cuadros muestran el interior del inmueble: son privados de la agencia, nunca públicos.
- Se borran del almacenamiento cuando la agencia acepta la escena generada, o a los **30 días** desde la subida si nadie la revisa, lo que ocurra primero. Hasta entonces se pueden reprocesar.
- El `sceneDraft` y el `manifest.json` sin imágenes se conservan como registro de la captura.

## Grabar sin conexión (S10)

La app de captura permite grabar sin red y enviar después, con un modo acotado:

- **Entrada**: solo al abrir la app sin red **con una sesión ya guardada** en el teléfono (cookie de renovación, CSRF e id de cuenta en el almacén seguro). Sin sesión guardada se muestra el acceso de siempre.
- **Qué permite**: lista local de los inmuebles ya descargados (solo id y una etiqueta «ciudad · zona», por cuenta), grabar el recorrido de uno de ellos y ver la cola de envíos pendientes. No muestra ni edita otros datos del servidor y no hay token de acceso: ninguna llamada autenticada sale en este estado.
- **Envío**: el paquete queda en el teléfono y en la cola. Al volver la red («Reintentar conexión») se hace la renovación real de la sesión; solo entonces la cola se envía sola. Si la renovación es rechazada (no una falla de red), la sesión y la caché local se descartan como siempre y los paquetes en cola **no se borran**.
- **Cierre de sesión**: borra la sesión guardada, el id de cuenta y la caché de inmuebles. Cambiar de cuenta también borra la caché anterior.
- **Sin límite de vigencia**: este modo no impone un plazo de acceso sin conexión; queda como decisión abierta del dueño del producto.

## Endurecimiento aditivo — 2026-11-17

- El paquete sigue usando esquema 1 o 2. El nuevo APK añade `reference.dimensionsSource: "user_confirmed"` tras confirmación explícita de las dimensiones reales; un preset no acredita una medición. Referencias antiguas siguen siendo legibles, con confirmación pendiente.
- En video, la referencia se marca **al terminar**, sobre el primer cuadro real del MP4 mediante el decodificador del teléfono. Debe filmarse el objeto al inicio. No se usa el bitmap de TextureView como evidencia del cuadro codificado.
- Android contrasta número de cuadros y PTS del MP4 con Camera2 antes de empaquetar; el worker vuelve a contrastar la secuencia completa antes de SfM. Se toleran 2 ms de cuantización en tiempos relativos: es una guarda operativa no medida, no una garantía del offset absoluto sensor/codificador. La correspondencia física requiere QA con dispositivo.
- `CaptureRegistration` admite `sha256` opcional, calculado por el APK sobre el ZIP. Repetir un captureId con tamaño/hash distinto produce conflicto. `/complete` comprueba existencia, tamaño, CRC, límites e identidad del manifiesto; escribe y relee una copia verificada en una clave que no tiene URL PUT. Solo entonces devuelve `uploadVerified: true`, encola y permite liberar el ZIP local después de persistir el estado. Una respuesta antigua sin ese indicador conserva la copia local. Los errores recuperables mantienen la captura.
- El claim incorpora `capture_id`, `listing_id`, `size_bytes`, `package_sha256` y `lease_seconds`; el worker contrasta bytes y manifiesto antes de reconstruir. `POST /api/v1/reconstruction/jobs/{job_id}/renew` requiere autenticación y `X-Reconstruction-Claim-Token` vigente; no resucita leases vencidas. La terminación sigue siendo idempotente. Un resultado se conserva en la caché privada persistente hasta recibir confirmación del servidor.
- Los borradores de video incluyen `measurement: {source: "sfm", scale: "reference" | "unscaled", alignment: "connected" | "disconnected", clock: "realtime" | "unknown", referenceConfirmed: boolean}`. Sin escala para **todas** las piezas, `unit` es `arbitrary`; únicamente el borrador de captura admite ese valor. La API rechaza su aceptación, guardado como escena del inmueble y publicación. También bloquea reloj no fiable, piezas desconectadas o referencia no confirmada. Catálogo y visor públicos siguen recibiendo exclusivamente metros. Las cajas de video declaran `source: "sfm_estimated"`; las fuentes `depth` y `manual` existentes se conservan.
- `scale.mode: "proportional"` identifica además la normalización relativa de Trevor. El factor nominal se mantiene separado de la escala por referencia y nunca convierte las coordenadas a metros. Las capturas históricas proporcionales que declaraban `unit: "meters"` se exponen como `arbitrary`, sin modificar su evidencia durante GET. Confirmar una altura o abertura no cambia esta modalidad. Véase el [informe de integración](../integracion/f07-20261118/README.md).
- La escala requiere intersecciones dentro del soporte finito del suelo o de la pared observada; se rechaza extrapolación fuera de segmentos. Si el rectángulo no intersecta o sus dos escalas son inconsistentes, se conserva un borrador sin escala y se informa: ya no se toma silenciosamente el lado largo ni se recupera una escala alternativa a partir de la misma referencia dudosa.
- El worker usa la distorsión SIMPLE_RADIAL tanto al proyectar como al formar rayos. Ninguna de estas correcciones mide exactitud física. Sin gravedad utilizable, la reconstrucción queda bloqueada para aceptación métrica. Las piezas desconectadas se conservan como propuesta con ubicación relativa desconocida y no pueden aceptarse como inmueble conectado.
- El retorno de Internet validado despierta la cola; una sesión offline se renueva antes de enviar. Las escrituras por propietario son serializadas, con temporal único, backup y etapas monótonas; los journals nativos recuperan paquetes aún no encolados después de un reinicio. Una interrupción intenta finalizar y conservar la toma; una muerte de proceso con MP4 sin finalizar no se declara recuperada sin prueba física.
- La revisión `0036_capture_integrity` conserva checksum y manifiesto nullable para los registros existentes. Desplegar primero esta migración y el backend compatible, después el worker y el APK/panel. Los datos históricos no adquieren procedencia verificada por migración. No se retiran ARCore, captura manual ni importación de planos.

Los límites de 300 cuadros SfM, cuatro hilos, extracción de características hasta 1600 px, 1800 s para PyCOLMAP, matching secuencial con vecindad diez cuando hay más de veinte imágenes y contenedor de 6 GiB/4 CPU son **guardas operativas, no SLA ni tolerancias de exactitud**. El presupuesto y la cobertura de recorridos de 30/90/300 s requieren medición. Los originales de staging y el snapshot se incluyen en la limpieza; el almacenamiento desplegado debe aplicar una caducidad a objetos de staging recreados mediante URLs previas todavía vigentes.

## Corrección residual R01–R12

- Una captura purgada o vencida sin recibo verificado no puede reabrirse: registro/completado
  responden `410`, sin URL nueva ni snapshot. Un recibo ya verificado sigue consultable tras
  su borrado legal; esto confirma entrega histórica y no reactiva almacenamiento/procesamiento.
- Un SHA histórico nulo se reconcilia con bytes remotos si existen. En `awaiting_upload` sin objeto
  puede fijar una expectativa; nunca constituye prueba de entrega. Tamaño, identidad y hash en
  conflicto siguen rechazándose. Capturas históricas sin manifiesto se verifican por `/complete`
  sin reiniciar el trabajo ni extender su retención. Sin objeto verificable, se conserva la copia
  local y se responde un error recuperable explícito; la migración no inventa evidencia.
- `/complete` valida CRC con plazo de 120 s y realiza I/O fuera de la transacción. Una segunda
  transacción corta revalida estado, identidad y retención bajo bloqueo de fila. Cada candidato
  nuevo tiene clave propia; el perdedor elimina solo su candidato. El almacenamiento debe tener
  caducidad para candidatos huérfanos tras muerte de proceso/fallo de limpieza; no hay barrido
  remoto de huérfanos certificado aquí.
- Los fallos de publicación o mensajes no reclamados no consumen intentos de reconstrucción.
  Solo fallos de ejecución o leases de ejecución vencidas consumen la cuota existente.
- `/accept` exige una escena persistida con el mismo `captureId`, evidencia compatible y escala
  válida. Un `If-Match` suministrado debe coincidir con la revisión actual; conflicto: `412`.
  El bloqueo del inmueble serializa aceptación con guardado. Repetir una aceptación confirmada
  sigue siendo idempotente; no se atribuye evidencia retroactiva a registros antiguos.
- El claim añade `cache_delete_after`. La caché privada vence al menor plazo entre esa fecha y
  `RECONSTRUCTION_CACHE_RETENTION_SECONDS` (máximo 30 días); incluye cachés antiguas y temporales.
  Su capacidad predeterminada es 128 MiB. Se aplica contrapresión en vez de expulsar resultados
  ambiguos vigentes. Un estado terminal confirmado elimina su resultado; tras vencer la política
  no se promete reutilización indefinida. El sweep se ejecuta mientras el worker está activo;
  volúmenes de workers retirados deben limpiarse operacionalmente.
- Android distingue descarte explícito de segundo plano: finaliza grabación o empaqueta un MP4
  finalizado. Conserva sidecars y checkpoints privados; solo borra raw tras verificar CRC del ZIP,
  sincronizarlo y persistir el journal de recuperación. Un reinicio puede recuperar el MP4
  finalizado y validado, filtrando propietario. Un MP4 no finalizado se conserva para rescate,
  sin declarar captura válida ni fabricar referencia confirmada.
  Si se interrumpe el marcado, `reference-draft.json` conserva entradas sin confirmar dentro
  del ZIP; el worker no lo usa para escalar ni lo confunde con `manifest.reference`.

Los controles MP4/Camera2 de conteo y tiempos relativos mantienen su tolerancia de 2 ms.
El offset absoluto y el comportamiento físico del dispositivo siguen pendientes, según
[el procedimiento residual](../../odd/tasks/f07-residual-hardening.md).
