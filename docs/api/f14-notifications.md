# API de notificaciones (F14.7)

Contrato de `backend/app/modules/notifications/`. Todas las rutas usan `Authorization: Bearer`. Los errores tienen la forma `{ "detail": "...", "code": "..." }` (`not_found`, `forbidden`, `unauthorized`).

**Transporte:** consulta periódica con la aplicación o el panel abiertos (sugerido: cada 30 s). No hay envío con la aplicación cerrada: esa entrega usa Firebase y queda para una segunda etapa (`odd/tasks/f14-notifications.md`, T4), que requiere un proyecto de Firebase creado por el dueño del repositorio.

**Contenido:** un aviso lleva identificadores y un tipo, nunca el texto de un mensaje ni la identidad del agente. Cada aplicación redacta el texto del aviso. El aviso al cliente nunca revela quién respondió (F14.6, S6).

## Rutas

| Método y ruta | Sesión | Qué hace |
| --- | --- | --- |
| `GET /api/v1/customer/notifications?limit=50` | cliente | Avisos del cliente, del más nuevo al más viejo, con el contador de pendientes. `limit` 1–100. |
| `POST /api/v1/customer/notifications/{id}/read` | cliente | Marca uno como leído (204). 404 si no es suyo o no existe. |
| `POST /api/v1/customer/notifications/read-all` | cliente | Marca todos como leídos (204). |
| `GET /api/v1/staff/notifications?limit=50` | agente o administrador de agencia | Igual que la del cliente. 403 para el personal de plataforma. |
| `POST /api/v1/staff/notifications/{id}/read` | agente o administrador de agencia | Marca uno como leído (204). 404 si es de otro destinatario. |
| `POST /api/v1/staff/notifications/read-all` | agente o administrador de agencia | Marca todos como leídos (204). |

Respuesta de listado: `{ "unread": int, "items": [Aviso] }`.
Aviso: `{ id, kind, conversation_id | null, reservation_id | null, detail | null, created_at, read }`.

## Tipos de aviso (`kind`)

| `kind` | Destinatarios | Cuándo |
| --- | --- | --- |
| `chat_message` | Cliente: cuando la agencia responde. Personal: el agente dueño de la conversación; mientras nadie la tomó, todos los agentes activos asignados al inmueble; si no hay ninguno, los administradores de la agencia. | Mensaje nuevo. |
| `chat_assigned` | El agente que recibe la conversación. | Reasignación manual o automática. |
| `chat_needs_admin` | Administradores de la agencia. | La conversación quedó sin agente activo (F14.6, `needs_admin`). |
| `chat_overdue` | Administradores de la agencia. | El cliente espera respuesta desde hace 24 h o más. |
| `reservation_status` | El cliente de la reserva y los administradores de la agencia del inmueble. `detail` trae el estado: `accepted`, `rejected`, `cancelled` o `expired`. | Cambio de estado de la reserva. |

## Reglas

- **Aislamiento:** un aviso solo es visible y modificable por su destinatario. Marcar como leído el aviso de otro devuelve 404, igual que uno inexistente.
- **Atomicidad:** el aviso se guarda en la misma transacción que el evento que lo causa; si el evento se revierte, el aviso también.
- **Escalada por falta de respuesta:** no hay tarea programada. El aviso `chat_overdue` se genera cuando un administrador de la agencia consulta su bandeja, una vez por administrador y por cada espera del cliente. Si nadie del personal consulta, el aviso no se crea hasta la próxima consulta; la marca `overdue` de la conversación (F14.6) sí se calcula siempre al consultarla.
- **Reservas vencidas:** el vencimiento de una reserva pendiente se aplica al consultar las reservas (comportamiento previo a F14.7); el aviso de `expired` se crea en ese momento.
- **Sin duplicados:** los avisos de reserva y de espera vencida son idempotentes por destinatario, estado y ventana de espera.

## Datos

Tabla `notification` (migración `0033_notifications`): `id`, `recipient_kind` (`customer` o `staff`), `recipient_id`, `kind`, `conversation_id`, `reservation_id`, `detail`, `dedupe_key` (única), `created_at`, `read_at`. Las claves foráneas a conversación y reserva eliminan el aviso en cascada.
