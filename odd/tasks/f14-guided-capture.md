# F14.2 — Captura guiada con checklist

**Objetivo:** el agente recorre los ambientes con una guía y el borrador solo se envía a revisión cuando la captura pasa la validación. **Plan:** `docs/plan-maestro-roomforge.md` F14.2. **Issue:** #36.
**Rama:** `feat/f14-captura-guiada` desde `main` (`ca9fc4e`). **Entrega:** `ask-on-risk`.
**Ejecutores de pruebas:** `apps/captura_mobile` con `flutter test` y `flutter analyze`.

## Specs

El alcance y los criterios de aceptación vienen de la issue #36. **[Aceptada]** = propuesta del asistente que el usuario eligió de forma expresa. **[Propuesta]** = decisión del asistente donde la issue no la fijaba; confirmar ante cualquier duda.

- **S1 — Checklist por ambiente.** Cobertura, luz y orden sugerido por ambiente, con avance visible.
  - **[Aceptada: «Derivados y editables»]** Living y cocina fijos, más un dormitorio y un baño por cada uno de la ficha; el agente agrega ambientes extra o marca uno como «No aplica» con motivo.
  - **[Propuesta]** Tres puntos por ambiente: luces y cortinas, foto desde la entrada con al menos dos paredes, y sin personas ni objetos personales a la vista.
- **S2 — Validación automática de calidad básica**, con heurísticas locales documentadas y sin prometer IA.
  - **[Aceptada: «Bloquea el envío»]** Una foto que no pasa no se sube y no cuenta para el ambiente; el borrador no se envía hasta que cada ambiente que aplica tenga una foto que pase.
  - **[Propuesta]** Reglas: lado menor ≥ 720 px, luma media entre 50 y 220 y varianza del laplaciano ≥ 25 sobre la foto reducida a 640 px. Umbrales elegidos a mano, sin calibrar.
- **S3 — Motivos claros** cuando la validación falla. El flujo F04.3 de revisión del panel no cambia.
- **S4 — Dónde se guarda. [Aceptada: «Local en el teléfono»]** La asociación foto → ambiente y la lista confirmada se guardan solo en el teléfono, por cuenta y por inmueble, sin backend ni migración.
- **S5 — Base reutilizable por F07**, documentada en `docs/guias/f14-captura-guiada.md`.
- **Fuera de alcance (issue):** ARCore, detección de calidad con IA y cambios al flujo de revisión del panel.

## Tasks

Estado: ☐ pendiente. Ruta por defecto: en línea.

| ID | Tarea | Specs | Ruta | Estado | Commit / evidencia |
| --- | --- | --- | --- | --- | --- |
| T1 | Diseño del checklist y de la validación de calidad, con reglas explícitas. | S1, S2 | en línea | ☑ | `CaptureChecklist`, `RoomCheck`, `assessPhoto` y `measureLuma` en `lib/domain/guided_capture/`. |
| T2 | Implementación en la app de captura sobre el flujo de borradores: guía, almacenamiento local y bloqueo del envío. | S1–S4 | en línea | ☑ | `GuidedCaptureController`, `FileGuidedCaptureStore`, `GuidedCaptureScreen` y sección «Captura guiada» del editor; `ListingPhotosController` separa elegir de subir para validar antes de subir. |
| T3 | Pruebas Flutter del checklist y la validación. | S1–S3 | en línea | ☑ | 14 pruebas en `test/guided_capture_test.dart` (ambientes, problemas, JSON, reglas de calidad, decodificación real de un PNG, bloqueo del envío, foto aceptada y rechazada, «No aplica» y ambiente extra). |
| T4 | Documentar cómo F07 reutilizará el checklist. | S5 | en línea | ☑ | `docs/guias/f14-captura-guiada.md`. |
| T5 | Recorrido manual en emulador o dispositivo. | — | en línea | ☐ | Pendiente: no hay emulador ni dispositivo en el entorno de esta sesión (2026-11-18). |

**Riesgo previsto:** T2 nombra el ítem 2 (un borrador que no debe enviarse a revisión) y el flujo de fotos de F04.2, compartido con el resto del editor.

## Log

- **L1 (2026-11-18, usuario):** pidió pasar a la siguiente issue después de #38.
- **L2 (2026-11-18, usuario),** ante tres preguntas: «Local en el teléfono», «Derivados y editables» y «Bloquea el envío» (S4, S1 y S2).
- **L3 (2026-11-18):** decisiones del asistente, a confirmar: los tres puntos de la lista; los umbrales de calidad; una foto que el teléfono no puede decodificar se rechaza; la guía solo se activa cuando la compilación tiene almacenamiento local (`guidedStore`), así que las pruebas y compilaciones sin él conservan el comportamiento anterior; las fotos subidas fuera de la guía no cuentan para ningún ambiente.
- **L4 (2026-11-18):** T1–T4 hechas en `feat/f14-captura-guiada`. Verificación: suite de la app de captura 679 verdes; `flutter analyze` sin avisos nuevos (el único es el preexistente de `spatial_capture_controller.dart:463`). Pendiente T5.
