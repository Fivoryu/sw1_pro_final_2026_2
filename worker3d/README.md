# Worker 3D

Dos responsabilidades conviven acá: la reconstrucción Meshroom sigue pendiente y la detección de mobiliario incluye el piloto y los trabajos asíncronos F08.4 implementados.

1. **Reconstrucción 3D con Meshroom** (F06/F07): pendiente de detalle.
   - Stack: ver `docs/scrum/sprint-0-requerimientos/09-infraestructura.md`
   - Repo destino futuro: `<pendiente de separación>`
   - Estado: estructura inicial, **sin código**.
2. **Detección de mobiliario con IA preentrenada** (F08/F08.4): piloto de inferencia implementado y ejecutado; el procesamiento asíncrono por cola también está implementado. La API es la única escritora del estado de los trabajos.

## Detección de mobiliario (F08)

Detector COCO preentrenado que **sugiere** mobiliario en una fotografía de un inmueble. No inventa geometría métrica ni precio, y una sugerencia nunca se publica sola: la confirma una persona.

| Pieza | Ruta |
|---|---|
| CLI de inferencia | `worker3d/detect.py` |
| Consumidor de trabajos asíncronos | `worker3d/job_worker.py` |
| Descargador del conjunto CC0 | `worker3d/fetch_cc0_pilot_set.py` |
| Planchas de revisión manual | `worker3d/review_sheet.py` |
| Pruebas de contrato (31) | `worker3d/tests/` |
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
