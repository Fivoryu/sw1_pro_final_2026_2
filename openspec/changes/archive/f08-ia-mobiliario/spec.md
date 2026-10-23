# Spec — Detector de mobiliario preentrenado (F08.1–F08.3)

Cada requisito es verificable y tiene un criterio de aceptación observable. Fuente: `docs/plan-maestro-roomforge.md` §F08 y §1.5.

## R1 — Ficha de candidato con licencia verificable (F08.1)

Se documenta al menos un candidato con nombre y versión exactos del paquete y del identificador de pesos, y al menos la alternativa YOLO pequeña evaluada.

**Aceptación:** la ficha declara la licencia del código y de los pesos con su fuente citada, enumera las clases útiles y las ausentes, y registra los límites. Cuando los términos de los pesos no estén declarados por el proyecto que los publica, eso se escribe como límite, no como permiso. No se compró ninguna licencia ni se contrató ningún servicio.

## R2 — Dependencia reproducible

El servicio de inferencia se construye desde una definición versionada en el repositorio, con versiones exactas fijadas y sin pasos manuales no registrados.

**Aceptación:** desde un estado limpio, una única invocación documentada construye el servicio y ejecuta la inferencia; las versiones exactas y el digest de la imagen quedan registrados en el documento de evidencia. Una segunda ejecución no requiere descargar nada nuevo salvo lo que el registro declare.

## R3 — Piloto sobre fotos autorizadas

Se ejecuta el detector sobre 20–40 fotos con autorización registrada. No se descarga COCO completo ni se piden miles de fotos propias.

**Aceptación:** el documento identifica el origen y el permiso del conjunto; cada imagen produce clases, cajas y puntuaciones observables; el conjunto no se reutiliza como prueba imparcial si con él se ajustó algún umbral.

## R4 — Separación honesta de resultados

Los resultados se clasifican en aciertos, falsos positivos y omisiones, con revisión manual registrada.

**Aceptación:** el informe presenta las tres categorías por separado con el conteo observado; una puntuación se reporta como puntuación, nunca como probabilidad calibrada; no se declara exactitud, precisión ni recall del detector sobre datos que no se revisaron.

## R5 — Medición propia o declaración de no medido

Latencia y memoria se miden con la herramienta disponible, separando preparación de evidencia experimental.

**Aceptación:** cada medición registra comando, versión, hardware y condiciones; todo valor que la herramienta no exponga se escribe **no medido**. No se cita ningún benchmark ajeno ni el tamaño de los pesos como consumo propio.

## R6 — Decisión de ubicación y empaquetado

Se decide entre teléfono offline y worker en PC/servidor, y se decide la representación (PyTorch o ONNX).

**Aceptación:** la decisión documenta las ventajas y desventajas de cada opción, se apoya en las mediciones de R5 o declara explícitamente por qué no pudo cerrarse, y si se elige ONNX registra que la conversión conservó un comportamiento aceptable medido. Si la decisión se difiere, queda registrada como pendiente con su desbloqueo nombrado.

## R7 — Límite de alcance declarado

La unidad no implementa F08.4, F08.5 ni F08.6, no toca el backend de producto, el panel ni las apps, y no congela el contrato de sugerencias de IA.

**Aceptación:** `git status` y la lista de archivos de la unidad muestran sólo `infra/docker/`, `worker3d/`, `docs/ai/`, `.gitignore`, los artefactos SDD, el registro ODD y las dos actualizaciones de trazabilidad (`docs/plan-maestro-roomforge.md`, `worker3d/README.md`). El plan maestro declara F08 como pendiente con el piloto documentado, no como completa.

## R8 — Trazabilidad actualizada

Al cerrar se actualizan `docs/plan-maestro-roomforge.md` (§1.4.1 y §F08) y `worker3d/README.md`, sin marcar como ejecutado nada que no se haya ejecutado.

**Aceptación:** los documentos citan las rutas reales de la evidencia, distinguen preparación de experimento ejecutado, y mantienen visibles los GAPs y casos académicos que sigan pendientes.
