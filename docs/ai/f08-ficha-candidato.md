# F08.1 — Ficha de candidato: detector de mobiliario preentrenado

- **Rama:** `feat/f08-furniture-ai-pilot` · **Base:** `origin/main` `452fcd7` · **Fecha:** 2026-10-14
- **Fase:** F08.1 del `docs/plan-maestro-roomforge.md`
- **Estado de evidencia:** evaluación documental. No se descargaron pesos, no se instaló ningún runtime de IA, no se compró ninguna licencia ni se contrató ningún servicio, no hay mediciones propias.

## Criterio de aceptación (F08.1, textual)

> «dependencia reproducible y permitida para la modalidad elegida; no comprar licencia ni contratar servicios sin autorización.»

F08.1 también pide «evaluar SSDLite/MobileNetV3 y alternativa YOLO pequeña. Revisar código, pesos y términos de datos».

## Candidato A — SSDLite320 + MobileNetV3-Large (torchvision, COCO_V1)

| Campo | Valor |
|---|---|
| Paquete | `torchvision`, módulo `torchvision.models.detection` |
| Constructor | `ssdlite320_mobilenet_v3_large` |
| Identificador de pesos | `SSDLite320_MobileNet_V3_Large_Weights.COCO_V1` |
| Licencia del código | BSD-3-Clause (licencia del proyecto PyTorch Vision) |
| Licencia de los pesos | **No declarada de forma separada** (ver cita abajo) |
| Dataset de entrenamiento | COCO: anotaciones del COCO Consortium bajo CC BY 4.0; el Consortium no posee el copyright de las imágenes, que provienen de Flickr y cuyo uso debe respetar los Términos de Uso de Flickr |
| Runtime | PyTorch, sólo CPU |
| Distribución de pesos | Se descargan desde el repositorio del proyecto al construir o ejecutar; no se revenden ni se redistribuyen |

**Cita textual de la documentación oficial** (`docs/source/models.rst` de `pytorch/vision`):

> «The pre-trained models provided in this library may have their own licenses or terms and conditions derived from the dataset used for training. It is your responsibility to determine whether you have permission to use the models for your use case.»

Es decir: el código es BSD-3-Clause, y para los pesos el proyecto que los publica **delega la verificación en quien los usa**. Eso se registra como límite, no como permiso.

**Clases relevantes** (el plan §F08.1 nombra sillas, sofás, camas, mesas de comedor, TV y refrigeradores). **Clases ausentes:** puertas, ventanas y escritorios: no son categorías de detección de COCO, y el plan prohíbe inferirlas. Consecuencia directa: F08 **no puede sugerir puertas, ventanas ni escritorios** con este modelo base, y esa limitación debe llegar al producto.

**Verificado en F08.2** ejecutando `weights.meta["categories"]` dentro del servicio de inferencia (`torchvision==0.29.1+cpu`). Salida completa en `f08-clases-modelo.json`:

| Resultado | Valor observado |
|---|---|
| Cantidad de categorías | **91** (no 80) |
| Clases de mobiliario presentes | `chair`, `couch`, `bed`, `dining table`, `tv`, `refrigerator` — las seis |
| Clases de mobiliario ausentes | ninguna |
| `door`, `window`, `desk` | **ausentes**, confirmado |

La diferencia entre 91 y 80 importa: las 91 ranuras incluyen `__background__` en el índice 0 y diez entradas `N/A` en los identificadores que COCO nunca definió. **El detector puede devolver `N/A` o `__background__` como etiqueta**, y ninguna de las dos es un objeto. Por eso el CLI filtra esas etiquetas antes de emitir una detección, con prueba propia (`test_non_object_labels_are_excluded_from_detections`).

## Candidato B — YOLO pequeña (familia Ultralytics)

- **Licencia:** AGPL-3.0. Cita del titular: «An Enterprise License is required if you want to use Ultralytics YOLO without open-sourcing your entire project.»
- **Consecuencia para RoomForge:** es un SaaS. Usar YOLO bajo AGPL-3.0 obligaría a liberar el proyecto completo; la única alternativa es una licencia Enterprise, y F08.1 prohíbe comprar licencias sin autorización. Por lo tanto **no cumple «permitida para la modalidad elegida»**.
- **Decisión:** descartado **por licencia, no por calidad técnica**. Si el dueño decide comprar la licencia Enterprise, esta decisión se reabre con autorización explícita.

## Candidato seleccionado: A

Cumple el criterio de aceptación sin costo: licencia de código permisiva y pesos descargables desde el proyecto que los publica. El punto abierto no es técnico sino de trayectoria de licencia de los pesos, y queda arriba como límite declarado.

## Límites registrados

1. **Pesos sin licencia separada declarada.** El proyecto que los publica traslada la verificación al usuario. No bloquea un piloto académico; sí es un riesgo a resolver antes de un uso comercial.
2. **Cobertura de clases incompleta.** Sin puertas, ventanas ni escritorios.
3. **Sin ajuste fino.** Un modelo COCO sin adaptación puede rendir mal en fotos de inmuebles; la magnitud se desconoce hasta medirla.
4. **Puntuaciones sin calibrar.** Una puntuación de salida no es una probabilidad.
5. **Sin mediciones propias.** Latencia, memoria y tamaño de imagen: **no medidos** hasta F08.2.
6. **Sin decisión de modalidad.** Teléfono offline frente a worker corresponde a F08.3.
7. **Etiquetas que no son objetos.** Las 91 ranuras del modelo incluyen `__background__` y diez `N/A`. Filtradas por el CLI; se registra porque afecta a cualquier consumidor futuro de la sugerencia.

## Decisión requerida del dueño del producto

- **P2 — resuelto con evidencia, queda la decisión de producto:** está confirmado que el modelo **no** puede sugerir puertas, ventanas ni escritorios (ausencia verificada, no supuesta). La decisión pendiente ya no es técnica: es si el producto acepta esa cobertura o si necesita otro modelo para aberturas.
- **P3 — pendiente:** ¿se confirma `torchvision` como candidato y se descarta YOLO, dado el motivo de licencia?

## Fuentes

- Documentación de torchvision, aviso general sobre pesos preentrenados: <https://github.com/pytorch/vision/blob/main/docs/source/models.rst>
- Modelo SSDLite320 + MobileNetV3-Large: <https://docs.pytorch.org/vision/stable/models/generated/torchvision.models.detection.ssdlite320_mobilenet_v3_large.html>
- Licencias de Ultralytics (AGPL-3.0 y Enterprise): <https://www.ultralytics.com/license/>
- Términos de Uso de COCO: <https://cocodataset.org/#termsofuse>

**Nota de honestidad documental:** la página de Términos de Uso de COCO se sirve por JavaScript y **no se pudo extraer directamente**; su contenido se registró desde fuentes secundarias que la reproducen y queda señalado para verificación humana. Las citas de torchvision y de Ultralytics provienen de la fuente primaria.
