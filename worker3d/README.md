# Worker 3D

Dos responsabilidades conviven acá: la reconstrucción del plano y la escena a partir del paquete de captura (F07.7) y la detección de mobiliario, que incluye el piloto y los trabajos asíncronos F08.4.

1. **Reconstrucción de la captura espacial** (F07.7): implementada. La fotogrametría (Meshroom) queda excluida por decisión del plan maestro del 2026-10-19; el worker no reconstruye texturas ni mallas.
   - Entrada: el paquete de captura v1 (`docs/api/f07-capture-package.md`), un ZIP con `manifest.json` y, si el dispositivo lo permite, profundidad y confianza en PNG.
   - Salida: un borrador de escena v2 (`docs/api/f06-scene-contract.md`) y una lista de advertencias en español para la agencia. Nada se publica solo.
2. **Detección de mobiliario con IA preentrenada** (F08/F08.4): piloto de inferencia implementado y ejecutado; el procesamiento asíncrono por cola también está implementado. La API es la única escritora del estado de los trabajos.

## Reconstrucción de la captura (F07.7)

| Pieza | Ruta |
|---|---|
| Reconstrucción (función pura y CLI) | `worker3d/reconstruct.py` |
| Lector de PNG en escala de grises de 8/16 bits | `worker3d/png16.py` |
| Consumidor de trabajos asíncronos | `worker3d/reconstruction_worker.py` |

Solo usa la biblioteca estándar de Python (sin numpy ni Pillow).

```bash
# Reconstruye un paquete (carpeta descomprimida o ZIP) e imprime {sceneDraft, warnings}
.venv/Scripts/python.exe worker3d/reconstruct.py <carpeta|paquete.zip>
```

Algoritmo v1:

1. Valida el manifiesto (`schemaVersion` 1, `floorY` presente, al menos un ambiente). Un paquete inválido termina en `fail` con `retryable: false`.
2. Lleva los polígonos de los planos al mundo con su pose, ajusta un segmento de piso a cada pared y la asigna al ambiente de la muestra de trayectoria más cercana.
3. Propone el contorno de cada ambiente con las mismas reglas que la app de captura; un ambiente que no cierra contorno se omite con una advertencia.
4. Altura: plano de techo menos piso (`ceiling_plane`, medida) o 2,40 m con procedencia `assumed` y advertencia; una altura supuesta nunca se presenta como medida.
5. Volúmenes: proyecta la profundidad de los cuadros clave al mundo y agrupa los puntos ocupados en cajas sin clase ni precio (`source: "depth"`). Sin profundidad no genera volúmenes y lo advierte.
6. Escena: muros sobre la línea central, muros compartidos soldados, sin aberturas (la agencia las marca en el editor).
7. Si hay `reference`, reescala la escena y declara el factor aplicado.

### Sugerencias de clase por volumen

`reconstruct.py` conserva, por cada volumen `box-N`, el cuadro clave que lo observó con mayor área visible y su caja en píxeles (`ReconstructionResult.volume_views`, proyección con la pose y `manifest.image`; sin intrínsecos de imagen no hay vistas). `reconstruction_worker.py` corre después el detector de F08 una vez por cuadro elegido (modelo cargado una sola vez, umbral 0,5) y asocia a cada volumen la detección de mayor IoU (mínimo 0,3). Si hay coincidencias, `/complete` agrega `volumeSuggestions: {modelId, items: [{objectId, label, score, keyframe, box}]}` (máximo 100); sin coincidencias el campo se omite. Sin `torch` el trabajo no falla: no envía sugerencias y agrega la advertencia `Class suggestions skipped: detector unavailable`. Son sugerencias para la revisión humana de F08.5; nunca asignan clase al borrador de la escena.

### Límites declarados

1. Los umbrales (celdas de 5 cm, tamaño mínimo de un volumen, confianza mínima de profundidad, separación de las paredes) son heurísticas de v1, no tolerancias medidas.
2. La exactitud de la reconstrucción frente a medidas reales está **sin medir**; se prueba con paquetes sintéticos.
3. Una pared compartida vista desde ambos lados solo se suelda si las dos caras difieren aproximadamente en el espesor de la pared.
4. El contrato de escena no admite hoy `source: "reconstruction"`; el borrador solo usa los valores de procedencia admitidos (`heightSource`, `source: "depth"`).

## Detección de mobiliario (F08)

Detector COCO preentrenado que **sugiere** mobiliario en una fotografía de un inmueble. No inventa geometría métrica ni precio, y una sugerencia nunca se publica sola: la confirma una persona.

| Pieza | Ruta |
|---|---|
| CLI de inferencia | `worker3d/detect.py` |
| Consumidor de trabajos asíncronos | `worker3d/job_worker.py` |
| Descargador del conjunto CC0 | `worker3d/fetch_cc0_pilot_set.py` |
| Planchas de revisión manual | `worker3d/review_sheet.py` |
| Pruebas de contrato de detección | `worker3d/tests/` |
| Servicio (sólo CPU) | `infra/docker/compose.inference.yml`, `infra/docker/inference/` |

### Modelo

`torchvision` SSDLite320 + MobileNetV3-Large, pesos `SSDLite320_MobileNet_V3_Large_Weights.COCO_V1`. Código BSD-3-Clause; los pesos **no tienen licencia declarada aparte** y la documentación oficial de torchvision delega la verificación en quien los usa. Detalle y motivo del descarte de YOLO (AGPL-3.0) en `docs/ai/f08-ficha-candidato.md`.

### Comandos

```bash
# Categorías reales del modelo (descarga los pesos una sola vez, 13.4 MB)
docker compose -f infra/docker/compose.local.yml -f infra/docker/compose.inference.yml \
  run -T --rm inference --list-classes

# Inferencia sobre un conjunto autorizado
docker compose -f infra/docker/compose.local.yml -f infra/docker/compose.inference.yml \
  run -T --rm inference --images /work/pilot/input --out /work/pilot/out/detections.jsonl

# Planchas de contacto con las cajas dibujadas, para la revisión manual
docker compose -f infra/docker/compose.local.yml -f infra/docker/compose.inference.yml \
  run -T --rm --entrypoint python inference /work/review_sheet.py \
    --records /work/pilot/out/detections.jsonl --images /work/pilot/input \
    --out-dir /work/pilot/out/sheets

# Pruebas de contrato (no requieren torch ni Pillow)
.venv/Scripts/python.exe -m pytest worker3d/tests -q
```

El overlay es **aditivo**: `compose.local.yml` no se modifica, así que la evidencia verificada de F01 sigue válida.

### Resultados del piloto (2026-10-14)

24 fotos CC0 de Wikimedia Commons, umbral 0.5, sólo CPU.

| Métrica | Valor |
|---|---|
| Detecciones | 30 |
| Aciertos / falsos positivos | 25 / 5 |
| Latencia media / pico | 230.5 ms / 592.1 ms |
| Memoria residente pico | 541 MB |
| Imágenes con veredicto | 18 de 24 (5 no aplican, 1 no concluyente) |

Evidencia: `docs/ai/f08-bitacora-piloto.md`, `docs/ai/f08-revision-manual.json`, `docs/ai/f08-clases-modelo.json`, `docs/ai/f08-decision-empaquetado.md`, `docs/ai/f08-conjunto-cc0.json`.

### Límites declarados

1. **Cobertura de clases.** El modelo tiene **91 salidas**, no 80: incluye `__background__` y diez `N/A`, que el CLI filtra. **No** contiene puertas, ventanas ni escritorios (verificado, no supuesto): F08 no puede sugerirlos con este modelo base.
2. **Fotos de fuente pública, no inmuebles reales.** El conjunto es CC0 y su licencia está verificada archivo por archivo, pero no es el dominio del negocio. La calidad sobre fotos reales de una agencia queda **sin medir**.
3. **Sin métrica estadística.** 24 imágenes miden viabilidad, no precisión ni recall. No se reportan esas cifras.
4. **Mediciones de un equipo.** Latencia y memoria son de CPU acá; no se extrapolan a un despliegue ni a un teléfono. Memoria de GPU y estado térmico quedan **no medidos**.
5. **Revisión asistida.** La revisión manual del piloto la hizo el agente sobre las planchas, no una persona. No sustituye la validación humana.
6. **Peso del servicio.** La imagen pesa 1.40 GB y el proceso 541 MB de RSS: no convive con el contenedor de la API en una instancia pequeña.
7. **Revisión humana separada del worker.** F08.4 no modifica inventario ni escena. F08.5 se implementa en la API y el editor del panel mediante el [contrato de revisión humana](../docs/api/f08-furniture-review.md): una persona aporta medidas/precio/posición, confirma o descarta y vincula repetidos a un extra ya colocado. F06 v2 ya está integrada; no existe el bloqueo histórico por aquella rama. El avance local y sus comprobaciones se registran en `odd/tasks/f08-human-confirmation.md`, sin presumir integración en `main`. F08.6 se difiere expresamente: no se ejecutó ajuste fino ni un experimento nuevo de modelos.
