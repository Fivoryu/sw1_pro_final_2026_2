# F07 — Captura por video con sensores y reconstrucción en worker3d

Objetivo: implementar la issue #63 (decisión 2026-10-23 del plan maestro §F07). Rama: `feat/f07-video-capture`. Estrategia de entrega: `ask-on-risk`. Ejecución: inline, con commits por unidad de trabajo.
Corredores de prueba: backend `pytest`, `ruff`, `pyright` (desde `backend/`); `worker3d`: `python -m pytest worker3d/tests`; Flutter: `flutter test` en cada app; panel: el de su `package.json`.

## Specs

Las citas son textuales del dueño del repositorio, 2026-10-23 (incluidas sus faltas de ortografía). Los requisitos que no son cita se marcan como **supuesto**.

- **S1 — Captura.** «Descartemos ARCore y ARKit ya que no se encargará de la generación del 3d, sino todo lo hará el worker3d. El agente graba y lo envia al servidor.» y «Si me gusta eso los datos junto al video.» (los datos de sensores —giroscopio, acelerómetro, gravedad— se graban junto al video). Aceptación: la app de captura graba video y sensores y los sube sin ARCore ni ARKit. Check: pruebas de la app + prueba manual en S23 FE y en A53.
- **S2 — Reconstrucción íntegra en `worker3d`.** «el generador3d será genérico sin meter detalle de texturas, muchos vértices, etc.» Aceptación: `worker3d` produce, a partir del paquete v2, el plano 2D y la escena v2 paramétrica, sin mallas ni texturas. Check: pruebas de contrato y sintéticas de `worker3d`; piloto con cinta (S7).
- **S3 — Detección de muebles en el mismo trabajo.** «Al momento de que el video es lanzado al mismo tiempo que se genera el modelado 3d se debe de detectar los muebles, ubicándolo donde se encuentra al final de la generación.» Aceptación: el mismo trabajo de reconstrucción devuelve muebles detectados con su posición en la escena. Check: pruebas de `worker3d` y de integración con el backend.
- **S4 — Revisión final del agente.** «El agente se encarga de verificar al final si esta todo en orden y poder determianr si entra o no entra en el contrato» Aceptación: el agente confirma o rechaza cada mueble y define cuáles entran al contrato. Check: pruebas del backend de revisión de muebles (`confirmed` / `rejected` / `manual` ya existentes) y de la interfaz.
- **S5 — Solicitud del cliente para quitar un mueble.** «el cliente podrá solicitar a la agencia que quiere saber si un inmueble que el agente lo descargo, puede quitarlo del contrato y el agente podrá hacer dicho encargo.» (**supuesto:** «inmueble» se lee como «mueble» y «descargo» como «cargó»; confirmado implícitamente en la conversación). Aceptación: el cliente crea la solicitud; el agente la aprueba o la rechaza; si la aprueba, el mueble sale del contrato. Check: pruebas del backend (permisos, estados, auditoría) y de las interfaces.
- **S6 — Cuándo se puede pedir.** Respuesta del dueño: «Ambas» (antes y después de reservar) y «A» (después de reservar: cancelar y reservar de nuevo). Aceptación: antes de reservar se actualiza el inventario y caducan las cotizaciones abiertas; después de reservar solo con la reserva en `pending` (**supuesto** propuesto y aceptado en la conversación) se cancela, se cotiza de nuevo y se reserva otra vez; con la reserva `accepted` la solicitud se rechaza con un mensaje claro. `ReservationEscrow.sol` no cambia. Check: pruebas de `reservations` y del flujo con el escrow local.
- **S7 — Exactitud sin promesa.** (**supuesto**, plan maestro §F07 y issue #63) Piloto con tres habitaciones reales medidas con cinta antes de prometer exactitud. Aceptación: el error medido queda documentado. Check: informe del piloto.
- **S8 — Plan antes que código.** «Yo lo apruebo soy el dueño del repo» (decisión aprobada) y «Puede ser una implementación completa. Crea una issue» (una sola issue, #63). Aceptación: plan maestro, borrador del contrato y espejo de issues actualizados. Check: `git log` y los documentos.

## Tareas

Formato: ID, specs, ruta, estado, commit. Ruta `inline` salvo que se anote otra.

- [x] T0 · S8 · inline · hecha · `5637936` (decisión en el plan maestro, borrador del contrato v2, espejo de issues).
- [ ] T1 · S7, S2 · inline · pendiente · piloto: tres habitaciones reales con cinta; SfM disperso + ajuste de planos con gravedad; error medido; decidir si hace falta profundidad monocular. **Necesita los videos del equipo.**
- [ ] T2 · S2 · inline · pendiente · verificar COLMAP sin GPU y tiempo en CPU; confirmar licencias en los `LICENSE` oficiales.
- [ ] T3 · S1 · inline · pendiente · congelar el esquema `2` en `docs/api/f07-capture-package.md` y definir la compatibilidad con el esquema `1`.
- [ ] T4 · S1 · inline · pendiente · backend: ingreso del paquete v2, cola, retención de 30 días, migración Alembic si cambia el esquema de datos (una sola cabeza).
- [ ] T5 · S2 · inline · pendiente · `worker3d`: reconstrucción desde video + sensores a escena v2.
- [ ] T6 · S3 · inline · pendiente · `worker3d`: detección de muebles sobre cuadros del video, ubicados con poses, hacia las sugerencias de F08.5.
- [ ] T7 · S1 · inline · pendiente · app de captura: grabación de video + sensores, marcas de ambiente, medida de referencia y subida.
- [ ] T8 · S4 · inline · pendiente · flujo del agente: qué muebles entran al contrato; confirmar si la revisión de muebles incrementa `offer_version`.
- [ ] T9 · S5, S6 · inline · pendiente · entidad y API de solicitud de cambio de inventario (`solicitada → aprobada | rechazada`), con los dos casos.
- [ ] T10 · S5, S6 · inline · pendiente · interfaces de la solicitud en la app cliente y en el panel.
- [ ] T11 · S1 · inline · pendiente · retirar el código ARCore y su dependencia; actualizar documentación, ayuda y las filas de §1.4.1 y §1.4.5.

## Log

- L1 (2026-10-23, dueño del repositorio, textual): «Si me gusta eso los datos junto al video.» / «Descartemos ARCore y ARKit ya que no se encargará de la generación del 3d, sino todo lo hará el worker3d. El agente graba y lo envia al servidor.» / «Si el generador3d será genérico sin meter detalle de texturas, muchos vértices, etc.» / «Al momento de que el video es lanzado al mismo tiempo que se genera el modelado 3d se debe de detectar los muebles, ubicándolo donde se encuentra al final de la generación. El agente se encarga de verificar al final si esta todo en orden y poder determianr si entra o no entra en el contrato, el cliente podrá solicitar a la agencia que quiere saber si un inmueble que el agente lo descargo, puede quitarlo del contrato y el agente podrá hacer dicho encargo.» / «Ambas» / «A» / «Yo lo apruebo soy el dueño del repo» / «Puede ser una implementación completa. Crea una issue» / «commite y procedemos a implementar.»
- L2 (2026-10-23): Tamaño: **grande** (no se retoma desde el pedido y `git diff`; varias sesiones, varias superficies y piezas que esperan videos reales). Seguimiento y commits por unidad. Sin razón para escritores delegados por ahora: ruta inline.
- L3 (2026-10-23): Riesgo declarado: cambia un contrato que consumen la app, el backend y `worker3d` (ítem 3) y toca el flujo de reservas (cerca del ítem 1 si cambia el esquema de datos). Cada unidad con ese ítem va en su propio commit.
- L4 (2026-10-23): Hallazgo verificado: una cotización solo es válida si `quote.offer_version == listing.offer_version` (`backend/app/modules/reservations/service.py`); el escrow no admite ajustar el monto, por eso S6 usa cancelar y reservar de nuevo.
- L5 (2026-10-23): Siguiente paso: T1 necesita videos reales de tres habitaciones medidas con cinta; T2 y T3 no dependen de eso.
