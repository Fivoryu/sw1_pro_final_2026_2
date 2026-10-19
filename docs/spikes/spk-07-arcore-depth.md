# SPK-07 — ARCore básico + Depth API en captura_mobile (preparación)

> **Estado:** solo preparación. No hay experimento ejecutado ni elección de integración. Este
> documento registra el sondeo de vías con evidencia; la corrida en dispositivo es T4–T5 del
> registro `odd/tasks/f07-arcore-spike.md` y nada acá se declara medido sin corrida.

**Fecha de preparación:** 2026-10-19 · **Base:** `origin/main` 8f1c9b4 (con PR #51 integrado)
**Unidad:** F07.1 (issue #23) + gate de F07.6 · **Registro:** `odd/tasks/f07-arcore-spike.md`

## 1. Objetivo y límite

Evaluar vías de integración de ARCore en `apps/captura_mobile/` (sesión, detección de planos,
estado de seguimiento, permiso de cámara) y medir la disponibilidad/calidad de la Depth API en el
dispositivo Android disponible del usuario — no el S23 FE histórico del plan. Esta prueba técnica
no completa F07.1 ni decide F07.6: declara viabilidad y límites.

**Requisito de dispositivo (decisión 2026-10-19):** cualquier Android compatible con ARCore que
soporte Depth API; el modelo real se declara en la corrida. Sin dispositivo disponible, solo se
cierra preparación (regla del plan: campo no observable = no medido).

## 2. Vías de integración sondeadas (con fuente)

| Vía | Evidencia registrada (fecha del sondeo) | Riesgo declarado |
| --- | --- | --- |
| `augen` (plugin Flutter, Dart puro) | pub.dev 1.5.0, publicado 17 días antes del sondeo; detección de planos ARCore nativa | Muy joven: sin historial de producción verificable |
| `ar_flutter_plugin_2` | pub.dev 0.0.3, hace 19 meses; fork del original (sin mantenimiento desde 2022) migrado a `sceneview_android` | Mantenimiento intermitente |
| `ar_flutter_plugin_plus` | pub.dev 1.1.3, hace 8 meses; bug documentado de tracking si la app se compila `debuggable: true` | Conocido pero frágil; exige build de release para juzgar el seguimiento |
| `sceneview` (Sceneform mantenido, Kotlin) | sceneview.github.io: sucesor comunitario de Sceneform (deprecado por Google en 2021); mavenCentral; Depth soportado | Es módulo Kotlin, no plugin: más integración propia, menos capa abandonable |
| SDK oficial `google-ar/arcore-android-sdk` | Samples `hello_ar_kotlin` (OpenGL) y Depth API quickstart en Java; C API en `arcore_c_api.h` | Referencia de comportamiento, no vía de integración directa |

**Fuente del sondeo:** búsqueda web 2026-10-19 (pub.dev, github.com/google-ar, developers.google.com,
sceneview.github.io). La vigencia de cada dato se re-verifica en T3 antes de confiar en él.

## 3. Lo que la preparación ya sabe (de la documentación, no medido acá)

- ARCore entrega **planos** horizontales/verticales con pose, tamaño y orientación; el Depth API
  añade un mapa de profundidad por frame (hardware o depth-from-motion según dispositivo).
- El Depth API **no produce volúmenes segmentados**: F07.6 tendrá que derivar volúmenes de
  ocupación (posición + dimensiones) desde profundidad + planos, con límites declarados — no
  detecta "una mesa" ni promete una malla limpia de cada mueble.
- Estado de seguimiento `TRACKING`/`LOST_TRACKING` es observable por frame; F07.1 exige mostrarlo
  y no producir medidas ficticias al perderlo.
- El error de tracking documentado de `ar_flutter_plugin_plus` con `debuggable: true` obliga a
  que cualquier medición de fluidez en esta familia se haga en build de release.

## 4. Pendientes de la corrida (T3–T5)

1. Dispositivo disponible del usuario (modelo/Android/versión de ARCore/Google Play Services for AR) o emulador ARCore como respaldo.
2. Elección de vía de integración (T3) tras releer el estado de cada candidato contra la versión actual de pub.dev.
3. Fixture de prueba congelada en la bitácora antes de medir: misma sala, misma luz, misma secuencia (con los valores numéricos de umbrales **pendientes de aceptación humana**).
4. Campos a registrar por corrida: fecha, commit, rama, dispositivo, estado de seguimiento observado, planos detectados, disponibilidad del modo depth, calidad observada del mapa, volúmenes aproximados y su estabilidad. Campo no observable = no medido.

## 5. Decisión humana pendiente

Ninguna vía queda elegida por este documento. La recomendación técnica nace en T3 con la
corrida; F07.6 solo se declara viable (o inviable) con la evidencia del spike de Depth API.
