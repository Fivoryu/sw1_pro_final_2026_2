# Propuesta 2: RoomForge

RoomForge propone generar el plano y el modelo 3D de un espacio interior a partir de capturas del teléfono, con asistencia inteligente durante la captura y reconstrucción final asíncrona fuera del dispositivo.

> **Enfoque propuesto — pendiente de confirmación/formalización:** la app Flutter de captura podría incorporar un modelo externo/open-source, ajustado o entrenado localmente, exportado a ONNX/TFLite y ejecutado offline en el teléfono. Esta IA asistiría la calidad y cobertura de la captura; no ejecutaría Meshroom ni la reconstrucción 3D completa en el móvil.

## 1. Identificar las funcionalidades principales de la aplicación

RoomForge será una aplicación móvil orientada a capturar un espacio interior y a coordinar su reconstrucción posterior. La app de captura ofrecerá asistencia local durante el recorrido, mientras que el procesamiento 3D final se ejecutará de forma asíncrona en el worker3d.

El usuario podrá recorrer una habitación, sala, cocina, oficina o aula mientras graba el entorno. La aplicación registrará las vistas y, cuando exista conectividad, sincronizará las capturas para solicitar la reconstrucción.

Sus funcionalidades principales serán:

* Iniciar el escaneo de un ambiente mediante la cámara.
* Registrar el movimiento del dispositivo durante la grabación.
* Utilizar información de:

  * Cámara RGB.
  * Acelerómetro.
  * Giroscopio.
  * ARCore cuando el dispositivo sea compatible.

La asistencia de IA en la app de captura tendrá un alcance acotado y podrá ejecutarse sin conexión:

* Evaluar la calidad básica de los fotogramas y advertir movimiento excesivo, desenfoque o iluminación insuficiente.
* Estimar la cobertura observada y señalar zonas que requieran una nueva toma.
* Proporcionar señales sobre puertas, ventanas, paredes, suelo, techo y superficies visibles.
* Guiar al usuario durante la grabación con mensajes como:

  * "Gira hacia la derecha".
  * "Falta capturar esta esquina".
  * "Acércate a la pared".
  * "Muévete más lentamente".
* Mostrar el progreso de la captura y una confianza orientativa para la asistencia.
* Continuar funcionando offline y sincronizar el resultado al recuperar conectividad.

El pipeline de reconstrucción 3D, fuera del teléfono, podrá:

* Estimar la posición y orientación de la cámara.
* Calcular profundidad aproximada a partir de múltiples vistas.
* Reconstruir progresivamente la geometría del ambiente.
* Detectar y modelar paredes, suelo, techo, puertas y ventanas.
* Identificar esquinas y límites de la habitación.
* Generar automáticamente un plano 2D y un modelo 3D navegable.
* Estimar largo, ancho, altura y superficie.
* Permitir introducir una medida real como referencia para mejorar la escala.
* Mostrar qué partes del ambiente fueron capturadas y permitir volver a escanear zonas deficientes.
* Mostrar un nivel de confianza de las superficies reconstruidas, diferenciando lo observado de lo inferido.
* Generar un modelo paramétrico donde paredes, puertas y ventanas sean elementos editables.
* Permitir corregir manualmente dimensiones.
* Visualizar el ambiente vacío, ocultando muebles cuando sea posible.
* Exportar el plano o modelo generado.

El flujo principal será:

```text
Capturar ambiente
       ↓
Asistencia IA offline
       ↓
Sincronizar al reconectar
       ↓
API persiste el job
       ↓
SQS
       ↓
Worker 3D / Meshroom
       ↓
Plano 2D + modelo 3D
```

Para el MVP se trabajará con **un único ambiente interior por escaneo**, utilizando teléfonos Android y priorizando habitaciones de geometría relativamente sencilla.

## 2. El desafío desde el punto de vista del diseño

El principal desafío será conseguir que una persona sin experiencia en escaneo 3D pueda capturar correctamente un ambiente.

La aplicación no deberá limitarse a dejar que el usuario grabe libremente. Tendrá que guiarlo para conseguir suficiente información.

El flujo será:

1. Seleccionar "Escanear ambiente".
2. Comenzar la grabación.
3. Recorrer lentamente la habitación.
4. Recibir indicaciones de asistencia local durante la captura.
5. Completar las zonas faltantes.
6. Finalizar el escaneo y guardar la captura localmente.
7. Sincronizar al recuperar conectividad y solicitar la reconstrucción asíncrona.
8. Revisar el plano y el modelo 3D generados fuera del teléfono.
9. Corregir dimensiones si es necesario.

Durante el proceso será necesario manejar los siguientes casos. La asistencia local podrá advertir algunos de ellos, pero no sustituye la validación de la reconstrucción final:

* Movimiento demasiado rápido.
* Imágenes borrosas.
* Mala iluminación.
* Paredes sin textura.
* Objetos que ocultan superficies.
* Esquinas no capturadas.
* Reflexiones.
* Cambios bruscos de cámara.
* Escala incorrecta.
* Habitaciones no completamente rectangulares.
* Dispositivos Android con diferentes capacidades.

La aplicación deberá mostrar la cobertura del ambiente.

Por ejemplo:

```text
Cobertura: 76 %

✓ Suelo
✓ Pared norte
✓ Pared oeste
⚠ Pared este incompleta
✗ Falta esquina de entrada
```

También deberá diferenciar claramente entre zonas:

* Bien reconstruidas.
* Parcialmente reconstruidas.
* Inferidas.
* Sin información suficiente.

Otro desafío será evitar que el usuario interprete las medidas como exactas cuando sean estimadas.

Por ejemplo:

**≈ 4,21 m**

en lugar de presentar una falsa precisión.

## 3. La innovación

La innovación de RoomForge no consistirá simplemente en producir una malla 3D a partir de un video.

La propuesta combinará **reconstrucción geométrica, comprensión semántica y guiado inteligente de captura** utilizando principalmente un teléfono Android sin requerir obligatoriamente sensores LiDAR. La asistencia inteligente se apoyará en un modelo externo/open-source, pero su selección, licencia, ajuste y métricas todavía deben confirmarse y formalizarse.

El sistema tendrá como entrada:

* Video RGB.
* Movimiento del dispositivo.
* Datos de acelerómetro y giroscopio.
* Profundidad mediante ARCore cuando esté disponible.

La asistencia de IA en el teléfono podrá incluir:

* Evaluación de calidad de imagen y movimiento.
* Estimación de cobertura durante el recorrido.
* Señales sobre puertas, ventanas y superficies relevantes.
* Indicaciones para completar zonas faltantes.

El pipeline de reconstrucción, ejecutado fuera del teléfono por el worker3d, incluirá:

* Estimación de movimiento.
* Visual Odometry o SLAM.
* Estimación de profundidad.
* Fusión de múltiples vistas.
* Reconstrucción geométrica.
* Detección de planos.
* Segmentación semántica.
* Reconocimiento de puertas y ventanas.
* Evaluación de cobertura.
* Estimación de confianza.

La salida será:

* Plano 2D.
* Modelo 3D.
* Dimensiones aproximadas.
* Elementos estructurales editables.
* Mapa de confianza.

### Modelo externo, ajuste local e inferencia offline

> **Enfoque propuesto — pendiente de confirmación/formalización.**

El desarrollo partirá de un modelo externo/open-source apropiado para asistir la captura. El equipo deberá revisar su licencia y compatibilidad antes de incorporarlo. El ajuste o entrenamiento se realizará localmente en una PC propia, sin depender de una API cloud paga. Luego el modelo se exportará a ONNX o TFLite y se empaquetará en la app Flutter para ejecutar inferencia offline.

La app podrá sincronizar capturas, resultados de asistencia y metadatos cuando vuelva la conectividad. La inferencia local no implica que el teléfono ejecute Meshroom, reconstrucción SfM/MVS completa, generación final de GLB ni derivación final del plano 2D.

| En la app móvil, offline | Fuera del teléfono, de forma asíncrona |
| --- | --- |
| Calidad de captura, cobertura, señales de puertas/ventanas/superficies y guía al usuario | Reconstrucción 3D con Meshroom, fusión de vistas, artefactos GLB, plano 2D y procesamiento geométrico final |

### Escaneo guiado inteligente

Una de las principales características diferenciadoras será que RoomForge analizará en tiempo cercano al real qué partes del ambiente todavía necesitan información, utilizando la asistencia local propuesta.

En lugar de:

```text
Grabar
   ↓
Terminar
   ↓
Descubrir que faltó una pared
```

se buscará:

```text
Grabar
   ↓
Analizar cobertura
   ↓
Detectar zona faltante
   ↓
Guiar al usuario
   ↓
Completar reconstrucción
```

### Reconstrucción semántica

El sistema no deberá considerar una habitación únicamente como millones de puntos.

Deberá convertir la reconstrucción en elementos como:

```text
Habitación
├── Pared norte
├── Pared sur
├── Pared este
├── Pared oeste
├── Suelo
├── Techo
├── Puerta
└── Ventanas
```

Esto permitirá obtener un modelo editable y reutilizable.

### Reconstrucción de superficies parcialmente ocultas

Cuando una pared se encuentre parcialmente cubierta por muebles, el sistema podrá utilizar la continuidad geométrica de las regiones visibles para estimar la superficie estructural detrás de ellos.

Estas regiones deberán marcarse como **inferidas**, no como superficies observadas directamente.

### Confianza geométrica

Cada superficie podrá recibir un indicador de confianza utilizando factores como:

* Cantidad de fotogramas que la observaron.
* Diferentes ángulos capturados.
* Calidad del tracking.
* Consistencia de profundidad.
* Oclusiones.

Esto permitirá recomendar automáticamente qué zona debería volver a escanearse.

Por tanto, RoomForge buscará diferenciarse mediante:

> **Android convencional + reconstrucción 3D + comprensión estructural + guiado inteligente + confianza geométrica.**

## 4. Forma de monetizar la aplicación

La implementación académica tendrá como objetivo un **coste monetario cero**: entrenamiento o ajuste en hardware propio, inferencia local, Floci y Hardhat en local y sin depender de una API cloud paga. La revisión de la licencia del modelo externo sigue siendo necesaria antes de incorporarlo.

Como hipótesis posterior de producto, RoomForge podría utilizar un modelo **freemium**, acompañado de planes profesionales. Esta hipótesis no constituye una dependencia de infraestructura para el MVP.

### Versión gratuita

Podría incluir:

* Número limitado de escaneos.
* Reconstrucción de una habitación.
* Plano 2D básico.
* Visualización 3D.
* Medidas aproximadas.

### Versión premium

Podría ofrecer:

* Escaneos ilimitados.
* Modelos de mayor calidad.
* Exportaciones avanzadas.
* Historial.
* Mayor cantidad de ambientes.
* Edición avanzada.
* Eliminación de muebles.
* Mediciones adicionales.
* Exportación de modelos 3D.

### Plan para profesionales

Podría dirigirse a:

* Arquitectos.
* Diseñadores de interiores.
* Constructores.
* Empresas de remodelación.
* Instaladores.
* Agentes inmobiliarios.

Podría incluir:

* Proyectos ilimitados.
* Organización de múltiples ambientes.
* Exportación profesional.
* Herramientas de medición.
* Planos de mayor calidad.
* Gestión de proyectos.

### Servicios para inmobiliarias

Una inmobiliaria podría utilizar RoomForge para digitalizar rápidamente ambientes y generar modelos tridimensionales para:

* Catálogos.
* Presentaciones.
* Planificación de remodelaciones.
* Medición preliminar.

### Servicios adicionales

También podrían comercializarse posteriormente:

* Procesamiento avanzado en la nube.
* Exportación a formatos profesionales.
* Integraciones con software CAD/BIM.
* Almacenamiento en nube.
* Colaboración entre profesionales.

Estos servicios son hipótesis de monetización y no forman parte de la ruta local de coste monetario cero propuesta para el MVP.

## 5. Explicar brevemente el stack tecnológico propuesto

### Aplicación móvil de captura

La aplicación existente se plantea con Flutter y Dart. La app de captura utilizará las APIs de cámara y sensores, con ARCore cuando el dispositivo sea compatible, y almacenará localmente las capturas pendientes de sincronización.

* **Flutter/Dart:** interfaz y lógica de la app.
* **Cámara RGB:** captura de video y fotos.
* **ARCore:** seguimiento espacial y profundidad cuando esté disponible.
* **Sensores del dispositivo:** acelerómetro y giroscopio.
* **Almacenamiento local:** proyectos y capturas pendientes.

### IA de asistencia de captura

* **Modelo externo/open-source:** selección y revisión de licencia pendientes.
* **PyTorch u otra herramienta compatible:** ajuste o entrenamiento local.
* **ONNX o TFLite:** formatos de exportación para distribución.
* **ONNX Runtime Mobile o runtime TFLite:** inferencia offline en Android.

Esta capa asiste la calidad, cobertura y señales de puertas, ventanas y superficies. No ejecuta Meshroom ni genera por sí sola el GLB o el plano 2D final.

### Reconstrucción y visión artificial fuera del teléfono

* **OpenCV:** procesamiento de fotogramas.
* **Open3D:** nubes de puntos, mallas y procesamiento geométrico.
* **Visual SLAM / Visual Odometry:** estimación del movimiento de cámara.
* **Monocular Depth Estimation:** cálculo de profundidad utilizando video RGB.
* **Modelos de detección o segmentación:** apoyo a la identificación estructural.

### Procesamiento geométrico

* Detección de planos.
* Reconstrucción de esquinas.
* Fusión de múltiples vistas.
* Cálculo de dimensiones.
* Generación del plano 2D.
* Reconstrucción paramétrica.
* Análisis de cobertura.
* Cálculo del nivel de confianza.

### Visualización 3D

Se podrá utilizar:

* **OpenGL ES** o motor compatible para Android.
* Alternativamente **Filament** para renderizado 3D.

La visualización permitirá rotar, ampliar y recorrer el ambiente reconstruido.

### Backend

El backend coordinará la sincronización y el procesamiento asíncrono; no sustituye la inferencia offline empaquetada en la app ni convierte a Floci en un ejecutor de Meshroom.

* **FastAPI:** API y orquestación de jobs.
* **PostgreSQL:** usuarios, proyectos, estados y metadatos.
* **S3 compatible:** almacenamiento de videos o modelos autorizados.
* **SQS:** cola para trabajos asíncronos.
* **Worker3d:** ejecución de Meshroom en una PC/GPU o proceso separado.

### Infraestructura

* **Docker:** servicios de procesamiento local.
* **Floci:** emulación local de S3/SQS; no ejecuta Meshroom ni blockchain.
* **Hardhat:** red local para el escrow de token de prueba, independiente de Floci.
* **GitHub:** repositorio.
* **GitHub Actions:** pruebas e integración continua.
* **PC con GPU:** ejecución prevista del worker3d para reconstrucciones.
* **ONNX/TFLite:** distribución de la asistencia IA en la app.
