# Propuesta 2: RoomForge

Reconstrucción automática del plano y el modelo 3D de un espacio interior a partir de un video capturado con el teléfono.

## 1. Identificar las funcionalidades principales de la aplicación

RoomForge será una aplicación Android orientada a reconstruir automáticamente el plano y la geometría tridimensional de un espacio interior mediante un video capturado con la cámara del teléfono.

El usuario podrá recorrer una habitación, sala, cocina, oficina o aula mientras graba el entorno. La aplicación procesará las diferentes vistas y generará progresivamente una representación estructurada del espacio.

Sus funcionalidades principales serán:

* Iniciar el escaneo de un ambiente mediante la cámara.
* Registrar el movimiento del dispositivo durante la grabación.
* Utilizar información de:

  * Cámara RGB.
  * Acelerómetro.
  * Giroscopio.
  * ARCore cuando el dispositivo sea compatible.
* Estimar la posición y orientación de la cámara.
* Calcular profundidad aproximada a partir de múltiples vistas.
* Reconstruir progresivamente la geometría del ambiente.
* Detectar automáticamente:

  * Paredes.
  * Suelo.
  * Techo.
  * Puertas.
  * Ventanas.
* Identificar esquinas y límites de la habitación.
* Generar automáticamente un plano 2D.
* Generar un modelo 3D navegable.
* Estimar:

  * Largo.
  * Ancho.
  * Altura.
  * Superficie.
* Permitir introducir una medida real como referencia para mejorar la escala.
* Mostrar qué partes del ambiente ya fueron capturadas.
* Detectar zonas con información insuficiente.
* Guiar al usuario durante la grabación con mensajes como:

  * "Gira hacia la derecha".
  * "Falta capturar esta esquina".
  * "Acércate a la pared".
  * "Muévete más lentamente".
* Mostrar un nivel de confianza de las superficies reconstruidas.
* Permitir volver a escanear únicamente las zonas deficientes.
* Generar un modelo paramétrico donde paredes, puertas y ventanas sean elementos editables.
* Permitir corregir manualmente dimensiones.
* Visualizar el ambiente vacío, ocultando muebles cuando sea posible.
* Exportar el plano o modelo generado.

El flujo principal será:

```text
Grabar habitación
       ↓
Seguimiento de cámara
       ↓
Estimación de profundidad
       ↓
Reconstrucción 3D
       ↓
Detección estructural
       ↓
Plano 2D
       +
Modelo 3D
```

Para el MVP se trabajará con **un único ambiente interior por escaneo**, utilizando teléfonos Android y priorizando habitaciones de geometría relativamente sencilla.

## 2. El desafío desde el punto de vista del diseño

El principal desafío será conseguir que una persona sin experiencia en escaneo 3D pueda capturar correctamente un ambiente.

La aplicación no deberá limitarse a dejar que el usuario grabe libremente. Tendrá que guiarlo para conseguir suficiente información.

El flujo será:

1. Seleccionar "Escanear ambiente".
2. Comenzar la grabación.
3. Recorrer lentamente la habitación.
4. Recibir indicaciones durante la captura.
5. Completar las zonas faltantes.
6. Finalizar el escaneo.
7. Procesar la reconstrucción.
8. Revisar el plano y el modelo 3D.
9. Corregir dimensiones si es necesario.

Durante el proceso será necesario manejar:

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

La propuesta combinará **reconstrucción geométrica, comprensión semántica y guiado inteligente de captura** utilizando principalmente un teléfono Android sin requerir obligatoriamente sensores LiDAR.

El sistema tendrá como entrada:

* Video RGB.
* Movimiento del dispositivo.
* Datos de acelerómetro y giroscopio.
* Profundidad mediante ARCore cuando esté disponible.

El procesamiento incluirá:

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

### Escaneo guiado inteligente

Una de las principales características diferenciadoras será que RoomForge analizará en tiempo cercano al real qué partes del ambiente todavía necesitan información.

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

* Cantidad de frames que la observaron.
* Diferentes ángulos capturados.
* Calidad del tracking.
* Consistencia de profundidad.
* Oclusiones.

Esto permitirá recomendar automáticamente qué zona debería volver a escanearse.

Por tanto, RoomForge buscará diferenciarse mediante:

> **Android convencional + reconstrucción 3D + comprensión estructural + guiado inteligente + confianza geométrica.**

## 4. La forma de como monetizar la aplicación

RoomForge podría utilizar un modelo **freemium**, acompañado de planes profesionales.

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

También podrían comercializarse:

* Procesamiento avanzado en la nube.
* Exportación a formatos profesionales.
* Integraciones con software CAD/BIM.
* Almacenamiento en nube.
* Colaboración entre profesionales.

## 5. Explicar brevemente el stack tecnológico propuesto

### Aplicación Android

Se recomienda desarrollar de forma nativa debido al uso intensivo de cámara, sensores y ARCore.

* **Kotlin:** lenguaje principal.
* **Jetpack Compose:** interfaz.
* **CameraX:** captura de video.
* **ARCore:** seguimiento espacial y profundidad cuando esté disponible.
* **Android Sensor API:** acceso a acelerómetro y giroscopio.
* **Room Database:** almacenamiento local de proyectos.

### Reconstrucción y visión artificial

* **OpenCV:** procesamiento de frames.
* **Open3D:** nubes de puntos, mallas y procesamiento geométrico.
* **Visual SLAM / Visual Odometry:** estimación del movimiento de cámara.
* **Monocular Depth Estimation:** cálculo de profundidad utilizando video RGB.
* **PyTorch:** entrenamiento o adaptación de modelos.
* **YOLO:** detección de puertas, ventanas y objetos.
* **Modelos de segmentación:** identificación de paredes, suelo y techo.
* **ONNX Runtime Mobile:** ejecución optimizada de modelos en Android.

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

El MVP podrá realizar gran parte del procesamiento localmente o utilizar un servicio para operaciones más pesadas.

Cuando sea necesario:

* **FastAPI:** procesamiento remoto.
* **PostgreSQL:** usuarios y proyectos.
* **MinIO o S3:** almacenamiento de videos o modelos autorizados.

### Infraestructura

* **Docker:** servicios de procesamiento.
* **GitHub:** repositorio.
* **GitHub Actions:** pruebas e integración continua.
* **Servidor con GPU:** opcional para reconstrucciones de mayor complejidad.
* **ONNX:** distribución optimizada de modelos.
