# f07 — ARCore básico + spike de Depth API (dispositivo de referencia propio)

Unidad de captura espacial F07.1 (issue #23) con el gate de F07.6 resuelto en la misma rama:
evaluación de integración ARCore y medición de Depth API en el dispositivo Android disponible
del usuario, no en el S23 FE histórico del plan.

## Specs

- **S1** — Verbatim del usuario: «Me parece bien, para hacerlo en un worktree.»
- **S2** — Verbatim del usuario: «Eres capaz de hacerlo bien? Me refiero si tu entrenamiento incluye algunos software parecidos a eso o no te parece mirar mejor los demás softwares o repos, opensource que tienen un trabajo parecido?» → la evaluación de integración se hace con evidencia de repos reales, no por memoria.
- **S3** — Verbatim del usuario: «Cómo lo hacemos si no tengo el s23? La idea es que sea para cualquier teléfono con buenas capacidadees para hacer F07» → el requisito es «dispositivo Android compatible con ARCore que soporte Depth API», no un modelo concreto; el dispositivo real se declara con modelo/Android/ARCore en la bitácora.
- **S4** — F07.1 (plan): sesión ARCore, detección de suelo, estado/calidad de seguimiento visible, permiso de cámara no bloquea la app; pérdida de seguimiento se informa y no produce medidas ficticias.
- **S5** — F07.6 (plan, decisión 2026-10-19): volúmenes de ocupación sin etiqueta con procedencia (`depth`/`manual`) y confianza; ARCore entrega planos horizontales/verticales, no volumen libre; los límites se declaran, no se prometen.
- **S6** — Regla del plan: campo no observable = **no medido**, nunca estimación; umbrales de FPS/memoria pendientes de aceptación humana.

## Tasks

| ID | Specs | Route | Commit |
|---|---|---|---|
| T1 | S1, S2 | Sondeo de vías de integración con evidencia (augen, ar_flutter_plugin_2/plus, sceneview Kotlin, SDK oficial) registrado en `docs/spikes/spk-07-arcore-depth.md` | docs |
| T2 | S3 | Corregir la referencia de dispositivo en el plan (F06.1 y F07): S23 FE → dispositivo real disponible, con el mismo criterio de «campo no observable = no medido» | docs |
| T3 | S4 | Evaluación de integración: pantalla ARCore básica en `apps/captura_mobile/` (sesión, detección de planos, estado de seguimiento, permiso de cámara) por la vía elegida en T1 | feat |
| T4 | S5 | Spike de Depth API sobre la misma sesión: disponibilidad del modo depth, calidad observada del mapa y volúmenes aproximados; límites declarados | feat |
| T5 | S6 | Corrida en dispositivo/emulador ARCore con mediciones observables; bitácora con modelo/Android/ARCore y campos no medidos declarados | test |
| T6 | S4–S6 | Cierre: evidencia en issue #23, fila F07 de §1.4.1 y decisión de viabilidad de F07.6 | docs |

## Log

- **L1** (verbatim): «Cómo lo hacemos si no tenemos el s23? La idea es que sea para cualquier teléfono con buenas capacidadees para hacer F07» — el plan queda corregido a dispositivo real (T2).
- **L2** (verbatim): «Me parece bien, para hacerlo en un worktree.» / «Eres capaz de hacerlo bien? …no te parece mirar mejor los demás softwares o repos, opensource que tienen un trabajo parecido?» — worktree `pf-worktrees/f07-arcore-spike`, rama `feat/f07-arcore-spike` desde `origin/main` (8f1c9b4, con PR #51 integrado); la evaluación de integración exige evidencia de repos reales (T1).
- **L3** — Sondeo inicial (web, 2026-10-19): `arcore_flutter_plugin` original sin mantenimiento confirmado; candidatos vivos: `augen` (17 días de vida, Dart puro), `ar_flutter_plugin_2` (fork con sceneview_android, 19 meses), `ar_flutter_plugin_plus` (bug documentado de tracking con `debuggable: true`), `sceneview` (Sceneform mantenido, Kotlin, Depth soportado), SDK oficial con samples `hello_ar_kotlin` y Depth quickstart en Java. La elección final se hace con T1, no en este Log.
- **L4** — Pendiente del usuario: modelo del dispositivo Android disponible (o emulador ARCore como respaldo) para T3–T5.
