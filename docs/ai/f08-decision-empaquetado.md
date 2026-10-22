# F08.3 — Decisión de ubicación y empaquetado

- **Rama:** `feat/f08-furniture-ai-pilot` · **Fecha:** 2026-10-14
- **Insumo:** mediciones propias de `docs/ai/f08-bitacora-piloto.md` §2.4, producidas por la imagen `roomforge-local-dev-inference` (digest `sha256:100a36e1…cb4d`) sobre 24 fotos CC0.
- **Regla que se respeta:** ni un benchmark ajeno ni el tamaño de los pesos se presentan como consumo propio (F08.3).

## 1. Los números medidos

| Magnitud | Valor observado | Cómo se obtuvo |
|---|---|---|
| Latencia por imagen, media | **230.5 ms** | `latency_ms` por registro, 24 imágenes |
| Latencia por imagen, pico | **592.1 ms** | ídem |
| Memoria residente pico del proceso | **541.05 MB** | `ru_maxrss` dentro del contenedor |
| Tamaño de la imagen del servicio | **1 497 591 016 bytes (≈ 1.40 GB)** | `docker image inspect` |
| Paquete `torch` instalado | **769 MB** | `du` dentro del contenedor |
| Archivo de pesos | **13.4 MB** (`ssdlite320_mobilenet_v3_large_coco-a79551df.pth`) | `ls` en la caché de `TORCH_HOME` |
| Memoria de GPU, uso de GPU, estado térmico | **no medido** | declarado en `not_measured` en cada registro |

**Advertencia sobre el número de 13.4 MB.** Es el tamaño de los **pesos**, no el consumo del sistema. NO debe leerse como «la IA móvil pesa 13 MB»: el runtime que los ejecuta es lo grande (769 MB sólo de `torch` en esta imagen). Presentarlo como consumo total sería exactamente lo que F08.3 prohíbe.

## 2. Las dos opciones, según el plan

> «comparar teléfono offline contra worker en PC/AWS. Servidor simplifica actualización pero requiere sincronizar; móvil evita red pero compite con AR y aumenta integración.»

| | **A — Worker en PC/servidor** (lo construido) | **B — Teléfono offline (ONNX)** |
|---|---|---|
| Evidencia medida | **Sí:** latencia, memoria, artefacto y digest | **Ninguna.** No se ejecutó en dispositivo ni se convirtió a ONNX |
| Actualización del modelo | Se cambia la imagen y listo | Requiere liberar la app: ciclo de tienda |
| Red | Requiere subir la foto y esperar | No requiere red |
| Competencia por recursos del teléfono | Ninguna | Compite con AR (F07) por CPU, memoria y batería |
| Integración adicional | Baja: es un servicio como los demás del Compose | Alta: runtime embebido, puentes por plataforma, tamaño de la app |
| Encaje con F08.4 (trabajos asíncronos) | Directo: el plan describe API → cola → worker | No aplica: no hay cola |
| Costo declarado | 1.40 GB de imagen y 541 MB de RSS: **no cabe dentro del contenedor de la API** | No medido |

## 3. Decisión

**Se adopta A: worker en PC/servidor, ejecutado con PyTorch y sólo CPU.** Es la única opción con evidencia propia, y es la que el plan describe para F08.4.

**ONNX queda NO EVALUADO, no descartado.** El plan pide «PyTorch inicial u ONNX tras validar operadores y resultados». No se validaron operadores ni se comparó comportamiento, así que declarar una conversión sería inventar evidencia. Su condición de desbloqueo, concreta: exportar a ONNX, comparar las detecciones sobre **las mismas 24 imágenes** contra este resultado y registrar la diferencia. Recién entonces esta decisión se puede reabrir.

**La opción móvil (B) queda sin veredicto.** No se midió en dispositivo, así que no se la puede declarar peor: se la declara **no medida**. Atribuirle un costo por el tamaño de los pesos sería el error que F08.3 prohíbe.

## 4. Consecuencias operativas que hay que dejar anotadas

1. **Dimensionamiento.** 1.40 GB de imagen y 541 MB de RSS significan que la inferencia **no puede convivir** con el contenedor de la API en una instancia pequeña. F11 (AWS) tiene que dimensionarla aparte y decidir si el servicio arranca bajo demanda.
2. **Descarga única de pesos.** El archivo de pesos vive en un volumen nombrado (`inference_torch_cache`), no en la imagen. Se descargó una vez, mide 13.4 MB y sobrevive a `run --rm`.
3. **Sin GPU.** La latencia reportada es de CPU. Un despliegue con GPU tendría otro número, que **no se midió** y no se extrapola.
4. **Trazabilidad de reconstrucción.** `infra/docker/inference/requirements.txt` fija las dependencias directas y `requirements.lock.txt` registra el árbol completo instalado; el digest de la imagen identifica el artefacto exacto que produjo estas mediciones.
5. **Propiedad de archivos.** Las planchas y resultados escritos por el contenedor quedan propiedad de `root` en el directorio montado. En Linux eso obliga a borrarlos desde el contenedor; no afecta a Windows con Docker Desktop.

## 5. Estado de la subfase

F08.3 **cerrada** con la decisión tomada y sus límites declarados. Lo que F08.3 **no** autoriza: escribir el endpoint de sugerencias, la cola de trabajos (F08.4) ni la pantalla de confirmación (F08.5). Ambas siguen pendientes y la segunda sigue bloqueada por F06.
