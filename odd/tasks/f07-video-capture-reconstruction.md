# F07 — Captura por video con sensores y reconstrucción en `worker3d` (sin ARCore obligatorio)

**Objetivo:** el agente graba un recorrido del inmueble con el teléfono (video + sensores) y `worker3d` genera la escena v2 con medidas reales y los muebles como volúmenes simples, sin depender de ARCore. **Issue:** #63 (leerla completa antes de arrancar); relacionadas #70 y #71.
**Trabajo previo que debe reconciliarse antes de T1:** la rama `feat/f07-video-capture` ya existe (6 commits sin integrar, 31 detrás de `main` al 2026-11-12) y contiene otro registro, `odd/tasks/f07-video-capture.md`, el borrador del contrato v2 y el modo «incluido» de los muebles ya implementado en `catalog`. Este documento no la reemplaza: leer ambos, conservar lo válido de esa rama y resolver con el dueño cuál de los dos registros continúa.
**Rama:** continuar `feat/f07-video-capture` actualizada con `main`, salvo que el dueño decida otra cosa. **Entrega:** `ask-on-risk`; un PR por corte, `Closes #63` solo en el último.
**Ejecutores de pruebas:** `worker3d` y `backend` con `<raiz>/.venv/Scripts/python.exe -m pytest`; `apps/captura_mobile` con `flutter test` y `flutter analyze`; `panel` con `vitest`. Árbitros de backend: Ruff, Pyright y pytest.

## Specs

Las citas entre comillas son texto literal del dueño del repositorio (ver `## Log`). Lo marcado **[Supuesto]** no lo pidió el usuario: viene de la issue #63 o de la recomendación de la sesión de diseño y debe confirmarse antes de construirlo.

- **S1 — Captura por grabación.** «que el usuario haga un recorrido por el inmueble por grabación y pueda el 3dworker trabajar y generar un plano tridimensional y dimensional». La app de captura graba video y registra sensores con marca de tiempo; no reconstruye en el teléfono.
  - Aceptación: un recorrido grabado en un teléfono sin ARCore funcional sube al servidor y produce un borrador de escena v2 revisable en el editor del panel.
  - **[Supuesto]** Sensores: giroscopio, acelerómetro y gravedad; magnetómetro grabado pero no usado como dato confiable. Cada cuadro lleva marca de tiempo en el mismo reloj que los sensores (implica Camera2, no la grabadora simple).
- **S2 — Salida.** «generar un plano tridimensional y dimensional». La salida de `worker3d` es la escena v2 (`docs/api/f06-scene-contract.md`): de ella derivan el 3D del visor y el plano 2D del editor.
  - Aceptación: la escena valida contra el contrato v2 y la fixture canónica; no se genera malla ni textura (decisión 2026-10-19 del plan maestro, F07.6).
- **S3 — Muebles como volúmenes simples.** «Donde se mostraran los muebles, neveras (general pero no detallado como cubos o algo así)».
  - Aceptación: los muebles detectados llegan como cajas con clase sugerida a la revisión humana de F08.5; nunca se publican sin esa revisión.
- **S4 — Sin cinta métrica.** «La idea es poder hacerlo sin una cinta real, que la app móvil facilite el recorrido».
  - Aceptación: el agente obtiene una escena en metros sin medir nada a mano.
- **S5 — Objeto de referencia elegido por el agente.** «No tiene que ser un hoja a4 siempre, lo que se puede hacer es que antes de iniciar el recorrido pueda seleccionar un objeto como referencia al tamaño, no importa el tipo de objeto quizás se ponga el ancho de un armario, la altura de una puerta, etc.»
  - Aceptación: antes de grabar, el agente marca los dos extremos de un objeto y elige o escribe su tamaño; `worker3d` escala la escena con esa referencia.
  - **[Supuesto]** Lista de tamaños conocidos (hoja A4, tarjeta, baldosas, puerta estándar editable) más valor libre. El objeto debe estar apoyado en piso o pared.
- **S6 — Recorrido fluido.** «cómo lo hacemos para que no siempre esta la vista, ya que la idea es que sea fluido el recorrido, no tendría que llevar todo el rato una puerta o un boligrafo en el momento del recorrido».
  - Aceptación: la referencia se filma solo al inicio; el resto del recorrido no la necesita a la vista.
  - **[Supuesto]** Si la reconstrucción queda partida en piezas, la pieza sin referencia se escala con un respaldo (altura de puertas o estatura del agente) y lleva una advertencia visible en el editor.
- **S7 — Medidas con procedencia.** **[Supuesto]** Las medidas obtenidas así se registran como estimadas hasta que el agente las confirme, reutilizando el registro de procedencia ya existente del flujo de planos (PR #74). No se promete una exactitud que no se midió (regla de GAPs, `AGENTS.md` §7).
- **S8 — Guía en vivo.** «que la app móvil facilite el recorrido». **[Supuesto]** Avisos de velocidad o movimiento brusco, poca luz y pared faltante, y sugerencia de cerrar el recorrido cerca del inicio.

**Decisiones abiertas — son del dueño del repositorio; no asumirlas:**

- **D1.** ARCore: la issue #63 pide retirarlo; en la sesión se recomendó dejarlo como camino opcional cuando el dispositivo lo soporta. Sin respuesta del usuario.
- **D2.** Muebles incluidos en el contrato y solicitud de exclusión del cliente (alcance de #63 que toca cotizaciones y reservas): se recomendó separarlo en otra issue. Sin respuesta del usuario; **queda fuera de este documento** hasta que se decida.
- **D3.** Respaldo de escala cuando no hay objeto de referencia (estatura, puertas, o cruce de sensores con video): depende del resultado de T1.

## Tasks

Estado: ☐ pendiente. Ruta por defecto: en línea. T1 bloquea a todas las demás.

| ID | Tarea | Specs | Ruta | Estado | Commit / evidencia |
| --- | --- | --- | --- | --- | --- |
| T1 | **Piloto de medición en `worker3d`** (script, sin tocar app ni backend): video + sensores de tres habitaciones reales → poses por SfM disperso → piso/paredes/techo con gravedad → escala por objeto de referencia. Registrar el error frente a la medida real, el tiempo en CPU sin GPU y el comportamiento en paredes lisas. Confirmar cada licencia en su `LICENSE` oficial (COLMAP, y si se evalúan: ORB-SLAM3, VINS-Mono, `stella_vslam`, modelos de profundidad). Los videos y las medidas reales los aporta una persona del equipo. | S1, S2, S4, S5, S6 | en línea | ☐ | — |
| T2 | Presentar el resultado de T1 y resolver D1–D3 con el dueño. Si el error no es aceptable, detenerse con un resultado **Necesita tu decisión**. | — | en línea | ☐ | — |
| T3 | Congelar el esquema `2` del paquete de captura en `docs/api/f07-capture-package.md` (base: `docs/api/f07-capture-package-v2-borrador.md`): códec, resolución, tamaño máximo, frecuencia de sensores, referencia de escala, marcas de ambiente, subida reanudable y compatibilidad con el esquema `1`. | S1, S5 | en línea | ☐ | — |
| T4 | Backend: ingreso del paquete v2, cola, retención de 30 días y límites de tamaño, sobre el módulo de capturas existente. Si hay migración Alembic, verificar un solo head (GAP-093). | S1 | en línea | ☐ | — |
| T5 | `worker3d`: reconstrucción desde video + sensores a escena v2, con advertencias y pruebas sintéticas y de contrato; convive con `reconstruct.py` (paquete v1). | S1, S2, S6, S7 | en línea | ☐ | — |
| T6 | `worker3d`: detección de muebles sobre cuadros del video, ubicados con las poses estimadas, hacia las sugerencias de F08.5. | S3 | en línea | ☐ | — |
| T7 | App de captura: selección del objeto de referencia, grabación de video + sensores, marcas de cambio de ambiente, guía en vivo y subida. Probar en el S23 FE y en el A53. | S1, S4, S5, S6, S8 | en línea | ☐ | — |
| T8 | Panel: mostrar en el editor las advertencias de escala y las medidas estimadas pendientes de confirmar. | S6, S7 | en línea | ☐ | — |
| T9 | Cierre: documentación y ayuda, fila F07 de §1.4.1 y tabla §1.4.5 del plan maestro, y lo que resulte de D1 sobre el código ARCore. | — | en línea | ☐ | — |

**Riesgo previsto:** T4 puede nombrar el ítem 1 (migración); T3 el ítem 3 (contrato consumido por la app y el worker); T1/T5 el ítem 5 si agregan dependencias. Declararlo en la línea de riesgo de cada commit.

**Estado verificado al crear este documento (2026-11-12, `main` en `9981b49`):**

- `worker3d/` contiene `reconstruct.py` y `reconstruction_worker.py`, que consumen el paquete v1 (planos, poses y profundidad de ARCore). No hay SfM ni reconstrucción desde video.
- Sin ARCore ya existen la captura manual guiada y la interpretación de planos o croquis (PR #74).
- Fila F07 de §1.4.1: en el S23 FE (Android 16) ARCore no detecta planos. La issue #63 reporta lo mismo en un A53. No está medido.
- El recorrido del cliente (F06.4), el visor y el editor 2D↔3D (F06.3) ya consumen la escena v2; no requieren cambios para S2.
- No se ejecutó ninguna suite en esta sesión.

## Log

- **L1 (2026-11-12, usuario):** «Mi idea que yo quiero es que el usuario haga un recorrido por el inmueble por grabación y pueda el 3dworker trabajar y generar un plano tridimensional y dimensional. Donde se mostraran los muebles, neveras (general pero no detallado como cubos o algo así)»
- **L2 (2026-11-12, usuario):** «Pero podemos hacer que la app aparte de grabar el recorrido también vea las dimensiones, profundidad e ir midiendo y se enviaran junto a la grabación, no?» — Análisis: medir profundidad en vivo con una sola cámara es lo que hace ARCore; sin él, la app envía sensores, datos de cámara, referencia de escala y marcas, y la medición ocurre en `worker3d`. Que el S23 FE no tiene sensor de profundidad no se verificó contra la ficha oficial.
- **L3 (2026-11-12, usuario):** «No podemos añadir a la app un forma que pueda medir? La idea es poder hacerlo sin una cinta real, que la app móvil facilite el recorrido»
- **L4 (2026-11-12, usuario):** pegó una propuesta de arquitectura (captura ligera, reconstrucción en servidor, VIO propio, calibración con objeto conocido, soporte híbrido, guía de UX) y preguntó «QUe te parece?». Ajustes señalados: la salida es escena v2 y no malla; VIO propio es lo más difícil y queda como experimento de T1; licencias sin verificar; el camino sin ARCore es el principal.
- **L5 (2026-11-12, usuario):** «No tiene que ser un hoja a4 siempre, lo que se puede hacer es que antes de iniciar el recorrido pueda seleccionar un objeto como referencia al tamaño, no importa el tipo de objeto quizás se ponga el ancho de un armario, la altura de una puerta, etc.»
- **L6 (2026-11-12, usuario):** «Y cómo lo hacemos para que no siempre esta la vista, ya que la idea es que sea fluido el recorrido, no tendría que llevar todo el rato una puerta o un boligrafo en el momento del recorrido» — Análisis: la escala es un único factor para toda la reconstrucción; basta filmar la referencia al inicio mientras la reconstrucción sea una sola pieza.
- **L7 (2026-11-12, usuario):** «No. Te encargaras de crear el odd para que otro agente lo haga» — Se crea este documento; no se escribió código. Siguiente paso: T1, tras confirmar quién graba y mide las tres habitaciones.
