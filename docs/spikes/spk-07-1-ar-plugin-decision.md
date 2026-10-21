# SPK-07.1 — Decisión de integración de realidad aumentada para la app de captura

- **Fase**: F07.1 (issue #23). Trazabilidad: `odd/tasks/f07-spatial-capture.md`, S1, S2, S9 y decisión L2(a).
- **Fecha**: 2026-10-21.
- **Dispositivo objetivo**: Samsung Galaxy S23 FE (SM-S711B, Android 16) con Servicios de Google Play para RA.
- **Alcance**: solo Android. iOS queda fuera de F07.

## 1. Pregunta

¿Qué base técnica usa la app Flutter `apps/captura_mobile` para abrir una sesión ARCore, detectar el piso, informar el estado del seguimiento y medir distancias y alturas sin grabar video?

## 2. Criterios

| Criterio | Qué se exige |
| --- | --- |
| Soporte Android | Funciona con ARCore actual en Android 16 y con la cadena de compilación del proyecto (AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14, `compileSdk`/`targetSdk` 36). |
| Mantenimiento | Publicaciones recientes y dependencias que no estén abandonadas. |
| Licencia | Compatible con un proyecto académico de código abierto. |
| Dependencia de render | Qué motor dibuja la cámara y la escena; si depende de Sceneform (archivado). |
| Acceso a la API | Acceso a `TrackingFailureReason`, tipos de plano, `isPoseInPolygon`, anclas y Depth API (imagen de confianza en bruto). |

## 3. Comparativa

Las celdas marcadas **(verificado)** se comprobaron en la fuente primaria indicada el 2026-10-21. Las marcadas **(supuesto)** no se verificaron.

| Opción | Soporte Android | Mantenimiento | Licencia | Render | Acceso a la API |
| --- | --- | --- | --- | --- | --- |
| `arcore_flutter_plugin` | Solo Android **(verificado)** | Última versión estable 0.1.0, publicada el 2023-02-20 **(verificado)** | MIT **(verificado)** | Requiere Sceneform 1.8.0 en el `build.gradle` de la app **(verificado)** | Subconjunto expuesto por el plugin **(supuesto)** |
| `ar_flutter_plugin` (y sus forks) | Android e iOS **(verificado)** | Última versión 0.7.3, publicada el 2022-11-19; 107 issues abiertas **(verificado)**. Hay 342 forks; no se evaluó ninguno en particular **(no verificado)** | MIT **(verificado)** | Su `android/build.gradle` declara `com.google.ar.sceneform:core:1.15.0` y `sceneform-ux:1.17.1` **(verificado)** | Subconjunto expuesto por el plugin **(supuesto)** |
| `augen` | Android, iOS y web **(verificado)** | Versión 1.5.0, publicada el 2026-10-01; el publicador figura como no verificado **(verificado)** | MIT **(verificado)** | Usa `com.google.ar:core:1.54.0` directamente en su `android/build.gradle` **(verificado)**; el motor de dibujo de la escena no se revisó **(no verificado)** | Si expone Depth API en bruto y `TrackingFailureReason`: **no verificado** |
| SceneView (`sceneview-android`, `flutter_sceneview`) | Android estable; el paquete Flutter figura como Alpha **(verificado)** | Proyecto activo, versión 4.60.0 **(verificado)**; fecha del último commit no verificada | Apache-2.0 **(verificado)** | Filament; el SDK Android está construido sobre Jetpack Compose **(verificado)** | El puente Flutter expone "un subconjunto de la API nativa" **(verificado)** |
| ARCore directo + módulo Kotlin propio | ARCore 1.57.0 resuelve desde Google Maven y compila con la cadena del proyecto **(verificado en este repositorio)** | Lo mantiene Google; última versión listada en el `maven-metadata.xml` el 2026-10-15 **(verificado)** | El SDK se distribuye bajo los «ARCore Additional Terms of Service» (declarado en el POM de 1.57.0) **(verificado)** | Render propio mínimo: textura OES de la cámara en `GLSurfaceView` y una vista Android superpuesta | API completa de ARCore **(verificado: es el SDK)** |

Fuentes:

- <https://pub.dev/packages/arcore_flutter_plugin> y <https://pub.dev/api/packages/arcore_flutter_plugin>
- <https://pub.dev/packages/ar_flutter_plugin>, <https://pub.dev/api/packages/ar_flutter_plugin> y <https://github.com/CariusLars/ar_flutter_plugin/blob/main/android/build.gradle>
- <https://pub.dev/packages/augen>, <https://pub.dev/api/packages/augen> y <https://github.com/AminMemariani/augen/blob/main/android/build.gradle>
- <https://github.com/SceneView/sceneview-android>
- Sceneform archivado por Google el 2020-07-28: <https://github.com/google-ar/sceneform-android-sdk>
- ARCore en Google Maven: <https://dl.google.com/android/maven2/com/google/ar/core/maven-metadata.xml> y el POM de `core-1.57.0`.

## 4. Decisión

Se usa **ARCore directo con un módulo Kotlin propio** (`ArCaptureActivity`) y un `MethodChannel('roomforge/ar_capture')` hacia Flutter.

Motivos:

1. Los dos plugins Flutter más conocidos dependen de Sceneform, archivado desde 2020. Eso los deja sin mantenimiento y expuestos a incompatibilidades con Android y AGP actuales.
2. `augen` usa ARCore sin Sceneform, pero es reciente, su publicador no está verificado y no se comprobó que exponga la Depth API en bruto ni los motivos de pérdida de seguimiento. Ambos datos son necesarios para S1 y S9.
3. El SDK Android de SceneView exige Jetpack Compose y su puente Flutter está en Alpha. Para una pantalla de medición sin modelos 3D, agrega un motor (Filament) que no se necesita.
4. La captura solo necesita la imagen de la cámara, planos, anclas, hit-tests y profundidad. Para eso alcanza un render mínimo, y el acceso directo evita depender de un subconjunto de la API.

## 5. Límites de la decisión

- Solo Android: no hay captura en iOS.
- La pantalla de captura es nativa (Android Views), no un widget Flutter. Flutter recibe únicamente el resultado final por el canal.
- El render es deliberadamente mínimo: fondo de cámara y una superposición 2D (retícula, esquinas, aristas con longitud). No se dibujan planos ni mallas.
- La cámara es solo vista previa en vivo: no se graba video ni se guardan fotogramas.
- Se mantiene código Kotlin propio: el equipo asume las actualizaciones del SDK de ARCore.
- Las medidas se expresan en el sistema de coordenadas de mundo de ARCore (metros, y hacia arriba). La normalización la hace el dominio Dart.
- Las tolerancias reales se miden en la corrida del S23 FE (T6). Este documento no declara ninguna precisión.

## 6. Depth API

La sesión activa `Config.DepthMode.AUTOMATIC` solo si `session.isDepthModeSupported(AUTOMATIC)` devuelve verdadero. En caso contrario la profundidad queda desactivada, el botón «Medir alto del mueble» se deshabilita y el alto del mueble queda `null` para que la app lo pida a mano.

Qué se medirá en el dispositivo:

| Medición | Cómo se obtiene | Valor en S23 FE |
| --- | --- | --- |
| Soporte de profundidad | `metrics.depthSupported` del resultado (`isDepthModeSupported(AUTOMATIC)`) | **Soportado**: el 2026-10-21 la sesión abierta en el S23 FE (`SM-S711B`, Android 16) mostró «profundidad disponible» en la línea de estado, que refleja `isDepthModeSupported(AUTOMATIC)`. Esto solo prueba el soporte; no mide calidad ni confianza. |
| Disponibilidad de la confianza en bruto | `frame.acquireRawDepthConfidenceImage()` en el píxel central; si lanza `NotYetAvailableException` o no está soportada, `confidence` es `null` | pendiente de corrida en S23 FE |
| Valores de confianza observados | `confidence` de cada mueble (valor en bruto / 255) | pendiente de corrida en S23 FE |
| Alto de mueble frente a cinta métrica | `boxes[].height` comparado con una medida independiente | pendiente de corrida en S23 FE |

Notas de método:

- La confianza se lee en el píxel de la imagen de confianza que corresponde al centro de la pantalla. La conversión usa `transformCoordinates2d(VIEW → IMAGE_NORMALIZED)`, que supone que la imagen de profundidad tiene el mismo encuadre que la imagen de CPU. Es un supuesto a confirmar en el dispositivo.
- El alto del mueble es la coordenada `y` del impacto central (preferentemente un `DepthPoint`) menos la altura del piso fijada por la primera esquina.

## 7. Modo de marcado por paredes (2026-10-21)

**Por qué.** Las esquinas del piso son el peor lugar para apuntar: quedan en sombra, no tienen textura (ARCore no detecta el piso hasta el rincón) y suelen estar tapadas por muebles. Marcar la esquina obligaba a aceptar un impacto aproximado justo donde el error importa más.

**Cómo.** La pantalla nativa ya no marca esquinas: con «Marcar punto de pared» el agente marca dos puntos del piso al pie de cada pared, en cualquier tramo visible (idealmente separados 50 cm o más; un segundo punto a menos de 30 cm se rechaza), recorriendo las paredes en orden alrededor del ambiente. Cada par define una recta sobre el plano x/z; cada esquina es la intersección de la pared *i* con la *i + 1*, y la última se cierra con la primera (`WallLines.cornersFromWallLines`, función pura con pruebas JVM). Los puntos usan las mismas reglas de piso que antes (plano horizontal con seguimiento, impacto dentro de su polígono y a 10 cm del primer punto, que ahora fija el piso). Al terminar, las esquinas se recalculan con las poses actuales de los anclajes; el canal devuelve `corners` como hasta ahora, más `metrics.method = "wall_lines"`, y `metrics.cornerHitDistances` pasa a tener una distancia por punto de pared. La escala absoluta se ajusta después en Dart con una referencia de cinta o láser.

**Límites.**

- Supone paredes rectas: una pared curva o con un quiebre no marcado produce una esquina falsa; cada quiebre debe marcarse como otra pared.
- Dos paredes consecutivas deben formar al menos 15°; si no, la captura se rechaza indicando qué paredes revisar (por ejemplo, un tramo de pared intermedio sin marcar).
- Una intersección a más de 20 m de los puntos de cualquiera de las dos paredes se trata como degenerada y no se entrega.
- El orden de marcado es responsabilidad del agente; un orden equivocado puede producir un polígono autocruzado que se valida después en el dominio Dart.
- Sigue sin haber exactitud declarada: la tolerancia real se documenta solo contra medidas de referencia (S5).

## 8. Modo recorrido (2026-10-21)

**Por qué.** Decisión del operador (captura «como CubiCasa», plan maestro §F07, decisión 2026-10-21): el modo principal deja de pedir puntos marcados. El canal acepta `captureRoom` con `mode: "walkthrough"`; sin `mode`, o con un valor desconocido, se usa el modo por paredes de la sección 7, que no cambia.

**Qué se registra.** Entre «Iniciar recorrido» y «Terminar recorrido», con la cámara en estado `TRACKING` y a 10 Hz:

- **Nivel del piso:** el plano `HORIZONTAL_UPWARD_FACING` con seguimiento más bajo visto hasta el momento (solo baja, nunca sube).
- **Paredes:** cada plano `VERTICAL` con seguimiento y sin `subsumedBy` se pasa a coordenadas del mundo y se proyecta sobre el piso (x/z); el segmento sigue su eje principal (PCA) y su extensión va del mínimo al máximo de la proyección de los vértices. Se guardan `area` (`extentX * extentZ`), `minY` y `maxY`. Paredes de menos de 30 cm se descartan.
- **Pisos:** polígonos x/z de los planos horizontales hacia arriba a ±0,10 m del nivel del piso.
- **Trayectoria:** posición x/z de la cámara, agregada cuando se movió 0,25 m o más desde la última muestra.

Paredes y pisos se toman de los planos con seguimiento en el momento de «Terminar recorrido» (ARCore los refina durante el recorrido); los que se vieron pero quedaron en pausa o detenidos no se entregan. Sin piso o con menos de 3 paredes, la captura se rechaza con la cantidad detectada y la sugerencia de usar el modo por paredes. La pérdida de seguimiento pausa el muestreo y suma `trackingLossCount`; no se registra nada mientras dura. El resultado lleva `corners: []`, `metrics.method = "walkthrough"` y `observations` (contrato en `odd/tasks/f07-spatial-capture.md`); las esquinas las propone el dominio Dart.

**Por qué no se guarda video ni imágenes.** La cámara sigue siendo solo vista previa: el recorrido entrega geometría observada (planos y trayectoria), que alcanza para proponer el contorno, pesa unos pocos kilobytes y no expone el interior del inmueble ni a las personas presentes. La fotogrametría sigue excluida (decisión 2026-10-19).

**Límites.**

- ARCore no detecta paredes lisas y sin textura (pintura uniforme, poca luz): esas paredes faltan en la propuesta y se completan a mano o con el modo por paredes.
- Los planos verticales se fusionan o se parten con el tiempo: una pared larga puede llegar como dos segmentos, y dos paredes vecinas casi coplanares como uno. El dominio Dart agrupa y ordena; el agente corrige.
- Un mueble alto pegado a la pared (placard, heladera) puede detectarse como pared.
- El nivel del piso solo baja: un plano espurio por debajo del piso real lo desplaza. Una altura medida antes de que el piso baje queda referida al nivel anterior.
- No hay exactitud declarada: la escala exacta la da después la medida de referencia (S5).
