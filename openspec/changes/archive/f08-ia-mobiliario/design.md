# Design — Servicio de inferencia y piloto de detección (F08.2–F08.3)

## 1. Por qué un servicio aislado y sólo CPU

El entorno virtual de la raíz es el árbitro real de `pytest`, `ruff` y `pyright` del backend (AGENTS.md §5). Instalar `torch` y `torchvision` ahí mezcla un runtime de cómputo pesado con el entorno de la API: cambia tiempos de instalación, arrastra dependencias binarias grandes y puede alterar la resolución de dependencias de FastAPI. Decisión del usuario: servicio en `infra/docker`.

Se descarta GPU: la modalidad evaluada es CPU y declarar requisitos de GPU inventaría una capacidad que no se midió.

## 2. Por qué un archivo Compose propio y no una línea más en `compose.local.yml`

`compose.local.yml` es evidencia verificada de F01: cuatro servicios (`postgres`, `floci`, `api`, `panel`), persistencia tras reinicio y proxies verificados. Agregarle un quinto servicio invalidaría esa evidencia y obligaría a reverificarla. Se usa un **overlay** que no cambia el arranque actual:

```bash
docker compose -f infra/docker/compose.local.yml -f infra/docker/compose.inference.yml <comando>
```

El overlay es aditivo: sin él, el stack local queda exactamente como estaba.

## 3. Superficie de trabajo de F08.2

| Ruta | Rol |
|---|---|
| `infra/docker/compose.inference.yml` | Overlay con el servicio de inferencia |
| `infra/docker/inference/Dockerfile` | Imagen CPU |
| `infra/docker/inference/requirements.txt` | Versiones exactas fijadas |
| `worker3d/detect.py` | CLI de inferencia (entrada: imágenes; salida: JSON) |
| `worker3d/tests/test_detect_contract.py` | Pruebas del contrato de salida y errores de entrada |
| `.gitignore` | Reglas nuevas para pesos, entradas y salidas del piloto |
| `docs/ai/` | Ficha, bitácora de corridas y decisión |

`worker3d/` es la ubicación que el propio plan asigna a F08 (§1.4.1: «`worker3d/` sólo contiene README; no hay detector, pesos, trabajos asíncronos ni confirmación de sugerencias»).

## 4. Resolución de versiones: se consultan, no se inventan

No se fijan versiones de memoria. Al arrancar F08.2 se consulta el índice real del paquete, se elige el par `torch`/`torchvision` compatible entre sí y con Python 3.12, y se registra en la bitácora:

- la versión exacta de cada paquete y su justificación;
- el digest de la imagen construida;
- el efecto declarado **antes** de instalar (descarga de cientos de MB, aumento del tamaño de la imagen).

`torchvision` exige una versión de `torch` determinada: la pareja se valida, no se adivina.

## 5. Contrato de salida del piloto

Un JSON por imagen, escrito en un archivo de resultados:

```json
{
  "image": "foto-01.jpg",
  "model": { "package": "torchvision", "version": "<exacta>", "weights_id": "SSDLite320_MobileNet_V3_Large_Weights.COCO_V1" },
  "score_threshold": 0.5,
  "detections": [ { "label": "chair", "score": 0.73, "box": [x1, y1, x2, y2] } ],
  "latency_ms": null,
  "not_measured": ["peak_memory_mb"]
}
```

Reglas del contrato:

- El campo se llama `score`, nunca `probability`: una puntuación no es una probabilidad calibrada.
- `not_measured` es una lista explícita y obligatoria: cada valor que la herramienta no exponga se declara ahí en vez de estimarse.
- El umbral usado viaja en el archivo, porque un umbral ajustado con el conjunto revisado impide presentarlo como prueba imparcial.

## 6. Alineación con el contrato compartido (§1.5 regla 6) — insumo, no implementación

El borrador de F06 declara `objects[]` como `{id, type, position, dimensions, color}`. Una sugerencia de IA necesita, además: procedencia (foto y caja), `label` de clase, `score`, estado de revisión (pendiente / confirmada / descartada) y el ID del inventario (`ListingExtra`) al confirmarse.

Ese conjunto de campos **no se congela en esta unidad**: F08.5 es quien lo necesita y F06 aún no está integrada. Se deja como propuesta, para la decisión que exige §1.5 regla 6.

## 7. Verificación

| Requisito | Cómo se verifica |
|---|---|
| R2 dependencia reproducible | Build desde cero y segunda ejecución sin descargas nuevas; digest registrado |
| R3 piloto | Corrida real sobre el conjunto autorizado; origen y permiso registrados |
| R4 honestidad | Informe con aciertos, falsos positivos y omisiones separados, con revisión manual |
| R5 medición | Comando, versión y hardware por medición; `not_measured` donde falte herramienta |
| R7 alcance | `git status` y lista de archivos de la unidad |
| R8 trazabilidad | Plan maestro §1.4.1 y §F08 actualizados sin marcar como ejecutado lo no ejecutado |

**Modo de pruebas.** F08 no cambia comportamiento de producto ni extiende una suite existente, así que **no hay RED/GREEN de producto que observar** y no se inventa uno. Sí hay una unidad con RED real y acotado: el contrato de salida del CLI (`worker3d/tests/test_detect_contract.py`), que se escribe primero y falla antes de existir `detect.py`. Los requisitos R3–R5 se verifican funcionalmente con la corrida real y su informe.

## 8. Límites declarados de este diseño

- El servicio no valida licencias ni términos por sí solo: la licencia se decide en F08.1 y se documenta.
- Un piloto con 20–40 fotos no mide precisión estadística: mide viabilidad.
- Sin las fotos autorizadas no hay evidencia experimental posible; el diseño puede construirse y verificarse en su estructura, pero R3–R5 quedan **pendientes**.
