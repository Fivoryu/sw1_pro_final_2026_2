# F14.7 — Notificaciones

**Objetivo:** el cliente y el personal de la agencia se enteran de los mensajes nuevos y de los cambios de estado de la reserva. **Plan:** `docs/plan-maestro-roomforge.md` F14.7. **Issue:** #77.
**Rama:** `feat/f14-notifications` desde `main` actualizado, después de integrar F14.6. **Entrega:** `ask-on-risk`.
**Ejecutores de pruebas:** `backend` con `<raiz>/.venv/Scripts/python.exe -m pytest`, Ruff y Pyright; apps con `flutter test` y `flutter analyze`; `panel` con `vitest`.

## Specs

Las citas entre comillas son texto literal del dueño del repositorio. **[Propuesta]** = planteada por el asistente y no objetada por el usuario; confirmar ante cualquier duda.

- **S1 — Superficies.** «Notificaciones y contacto via chat tanto en la app móvil y web» y «Tambien el agente tiene la app movil». Hay notificaciones en la app cliente, la app de captura y el panel.
- **S2 — Firebase después.** «firebase será lo posterior.» La primera entrega no usa Firebase: bandeja y contador que se actualizan con la aplicación o el panel abiertos. El aviso con la aplicación cerrada es una segunda entrega y requiere un proyecto de Firebase que debe crear el dueño del repositorio.
- **S3 — Eventos. [Propuesta]** Mensaje nuevo de chat, conversación asignada o reasignada, conversación sin respuesta escalada al administrador, y reserva aceptada, rechazada, cancelada o vencida.
  - Aceptación: cada evento genera un aviso solo para sus destinatarios; el aviso al cliente nunca revela la identidad del agente (F14.6, S6).
- **S4 — Bandeja. [Propuesta]** Lista de avisos con marca de leído, contador de pendientes y acceso directo a la conversación o la reserva.

## Tasks

Estado: ☐ pendiente. Ruta por defecto: en línea.

| ID | Tarea | Specs | Ruta | Estado | Commit / evidencia |
| --- | --- | --- | --- | --- | --- |
| T1 | Backend: modelo de avisos (migración con un solo head), generación desde los eventos de chat y de reservas, listado, contador y marca de leído, con aislamiento por destinatario. | S3, S4 | en línea | ☐ | — |
| T2 | App cliente: bandeja, contador y navegación al destino. | S1, S4 | en línea | ☐ | — |
| T3 | Panel y app de captura: bandeja, contador y navegación al destino. | S1, S4 | en línea | ☐ | — |
| T4 | **Segunda entrega, bloqueada hasta que exista el proyecto de Firebase:** registro del dispositivo y envío del aviso con la aplicación cerrada. | S2 | en línea | ☐ | — |
| T5 | Cierre: contrato de API, documentación y filas del plan maestro. | — | en línea | ☐ | — |

**Riesgo previsto:** T1 nombra el ítem 2 (un aviso no debe llegar a quien no corresponde) y el ítem 1 (migración); T4 el ítem 5 (dependencia y credenciales externas).

**Estado verificado (2026-11-12, `main` en `9981b49`, búsqueda por palabras clave, no auditoría):** no se encontró rastro de Firebase ni de registro de dispositivos; los estados de reserva existen en `backend/app/modules/reservations/`. No se ejecutó ninguna suite.

## Log

- **L1 (2026-11-12, usuario):** «Notificaciones y contacto via chat tanto en la app móvil y web»
- **L2 (2026-11-12, usuario):** «Tambien el agente tiene la app movil»
- **L3 (2026-11-12, usuario):** «firebase será lo posterior.»
- **L4 (2026-11-12):** el asistente propuso S3 y S4; el usuario no los objetó ni los confirmó de forma expresa. Siguiente paso: T1, una vez integrada F14.6.
