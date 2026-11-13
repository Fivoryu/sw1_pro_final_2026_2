# F14.8 — Reseñas de agencia e inmueble

**Objetivo:** el cliente califica a la agencia y al inmueble desde la ficha del inmueble; la reseña de quien reservó pesa más. **Plan:** `docs/plan-maestro-roomforge.md` F14.8. **Issue:** #78.
**Rama:** `feat/f14-reviews` desde `main` actualizado, después de integrar F14.6. **Entrega:** `ask-on-risk`.
**Ejecutores de pruebas:** `backend` con `<raiz>/.venv/Scripts/python.exe -m pytest`, Ruff y Pyright; apps con `flutter test` y `flutter analyze`; `panel` con `vitest`.

## Specs

Las citas entre comillas son texto literal del dueño del repositorio. **[Aceptada]** = propuesta del asistente que el usuario aprobó de forma expresa. **[Propuesta]** = no objetada ni confirmada; confirmar ante cualquier duda.

- **S1 — Dónde se califica y a quién.** «Aparte del chat reseñas dentro de la app», «Las calificaciones se harán dentro del inmueble», «En si se calificará a la agencia.» y «Además que tambien se calificará el inmueble en si».
  - Aceptación: desde la ficha del inmueble el cliente deja una nota para la atención de la agencia y otra para el inmueble. La del inmueble se muestra en su ficha; la de la agencia se agrega entre todos sus inmuebles.
  - **[Propuesta]** Notas de 1 a 5 con comentario opcional; una reseña por cliente e inmueble, editable.
- **S2 — Quién puede calificar y con qué peso.** «Mi idea es que el cualquiera pueda calificar siempre y cuando haya chateado pero el que mayor peso tendra es aquel que haya reservado.»
  - Aceptación: sin conversación con la agencia sobre ese inmueble no se puede calificar; la reseña de quien tiene una reserva pesa más en el promedio y se muestra como verificada.
  - **[Propuesta]** Peso triple para la reseña verificada, como constante configurable. Si el cliente reserva después de calificar, su reseña pasa a verificada.
- **S3 — Tiempo máximo de respuesta.** «1. Que haya un tiempo máximo de respuesta para calificiar (habrá motivos por contestación lenta)».
  - Aceptación: el cliente puede calificar cuando la agencia le respondió al menos una vez, o cuando venció el tiempo máximo de respuesta sin contestación; así una respuesta lenta o ausente también puede calificarse.
  - **[Propuesta]** Tiempo máximo de 24 h, igual al escalamiento de F14.6 (S7), como constante configurable.
- **S4 — Quien no reservó. [Aceptada: «2. Bien»]** Al calificar el inmueble sin reserva se aclara que se califica la publicación y el recorrido 3D; la marca de verificada distingue a quien reservó.
- **S5 — Reseñas maliciosas. [Aceptada: «3. Sirve»]** No se impiden del todo: la agencia reporta la reseña y el administrador de la plataforma decide.
- **S6 — Pocas reseñas. [Aceptada: «4. Bien»]** Con menos de 3 reseñas se muestra «pocas calificaciones» en lugar del promedio. Junto al promedio se informa cuántas reseñas hay y cuántas son verificadas.
- **S7 — Respuesta de la agencia. [Aceptada: «5. Si»]** La agencia responde una vez por reseña y no puede borrarla.

## Tasks

Estado: ☐ pendiente. Ruta por defecto: en línea.

| ID | Tarea | Specs | Ruta | Estado | Commit / evidencia |
| --- | --- | --- | --- | --- | --- |
| T1 | Backend: modelo de reseñas (migración con un solo head), elegibilidad por conversación y por tiempo máximo, una por cliente e inmueble y edición. | S1, S2, S3 | en línea | ☑ | `bdfcdb1`: Migración `0034_listing_reviews`, módulo `reviews`: elegibilidad por conversación respondida o por 24 h sin respuesta, una reseña por cliente e inmueble editable. 17 pruebas con T2. |
| T2 | Backend: promedios ponderados de inmueble y agencia, marca de verificada, umbral de pocas reseñas, respuesta de la agencia y reporte. | S2, S5, S6, S7 | en línea | ☑ | `bdfcdb1`: Promedio ponderado (peso 3 a la verificada), umbral de pocas reseñas, respuesta única del administrador de agencia, reporte y resolución por el administrador de la plataforma (confirmar oculta la reseña). Suite 1104 verdes, Ruff y Pyright limpios. |
| T3 | App cliente: formulario, promedio y lista en la ficha del inmueble y en el perfil de la agencia. | S1, S4, S6 | en línea | ☐ | — |
| T4 | Panel y app de captura: ver reseñas, responder y reportar; resolución del reporte por el administrador de la plataforma en el panel. | S5, S7 | en línea | ☐ | — |
| T5 | Cierre: contrato de API, documentación y filas del plan maestro. | — | en línea | ☐ | — |

**Riesgo previsto:** T1 nombra el ítem 1 (migración) y el ítem 2 (elegibilidad: quién puede calificar).

**Estado verificado (2026-11-12, `main` en `9981b49`, búsqueda por palabras clave, no auditoría):** no se encontró módulo de reseñas en `backend/app/modules/`; depende de las conversaciones de F14.6, que tampoco existen. No se ejecutó ninguna suite.

## Log

- **L1 (2026-11-12, usuario):** «Aparte del chat reseñas dentro de la app»
- **L2 (2026-11-12, usuario):** «Las calificaciones se harán dentro del inmueble […] En si se calificará a la agencia.»
- **L3 (2026-11-12, usuario):** «Cómo lo hacen las apps donde se califican? Mi idea es que el cualquiera pueda calificar siempre y cuando haya chateado pero el que mayor peso tendra es aquel que haya reservado. Además que tambien se calificará el inmueble en si»
- **L4 (2026-11-12, usuario),** en respuesta a la tabla de cinco huecos: «1. Que haya un tiempo máximo de respuesta para calificiar (habrá motivos por contestación lenta) 2. Bien 3. Sirve 4. Bien 5. Si» — la fila 1 proponía exigir una respuesta de la agencia; el usuario agregó el tiempo máximo (S3).
- **L5 (2026-11-12):** el peso triple y las 24 h son propuestas del asistente sin confirmación expresa. Siguiente paso: T1, una vez integrada F14.6.
- **L6 (2026-11-13):** decisiones del asistente donde S1–S7 no las fijaban, a confirmar: (a) «verificada» significa reserva en estado `accepted` (no `pending`, para que reservar y cancelar no sirva para inflar el peso); se calcula al consultar, así que reservar después de calificar la vuelve verificada; (b) responder y reportar una reseña es solo del administrador de la agencia (el agente solo la ve), y el cliente nunca ve quién respondió; (c) si el administrador de la plataforma confirma un reporte, la reseña se oculta (no se borra) y deja de contar; (d) la reseña editada sigue siendo válida aunque ya no se cumpla la condición de conversación; (e) las 24 h, el peso triple y el umbral de 3 reseñas son constantes de `reviews/service.py`, no variables de entorno; (f) rutas públicas: `GET /api/v1/listings/{id}/reviews` y `GET /api/v1/public/agencies/{id}/reviews`.
