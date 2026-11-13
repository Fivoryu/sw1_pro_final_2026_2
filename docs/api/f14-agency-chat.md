# API del chat con la agencia (F14.6)

Contrato de `backend/app/modules/chat/`. Todas las rutas usan `Authorization: Bearer`. Los errores tienen la forma `{ "detail": "...", "code": "..." }` (`not_found`, `forbidden`, `conflict`, `validation_error`, `unauthorized`).

**Transporte:** consulta periódica. El cliente pide `GET …/messages?after=<último id>` cada pocos segundos (sugerido: 3 s con la conversación abierta, 15 s en la bandeja). No hay SSE ni WebSocket; la autenticación es solo `Authorization: Bearer`, que esas APIs del navegador no envían (decisión T1, `odd/tasks/f14-agency-chat.md`, L5).

**Identidad:** el cliente solo ve el nombre de la agencia. El agente real de cada mensaje lo ve únicamente el administrador de la agencia.

## Cliente (`/api/v1/customer/chat`, sesión de cliente)

| Método y ruta | Qué hace |
| --- | --- |
| `POST /listings/{listing_id}/conversation` | Abre (201) o recupera (200) la conversación del cliente con ese inmueble publicado. 404 si el inmueble no está aprobado y publicado; 403 si la agencia bloqueó al cliente. |
| `GET /conversations` | Lista las conversaciones del cliente. |
| `GET /conversations/{id}/messages?after=0&limit=50` | Mensajes con `id > after`, en orden. `limit` 1–100. |
| `POST /conversations/{id}/messages` | Cuerpo `{ "body": "..." }` (1–2000 caracteres, sin espacios solos). 201; 409 si es solo lectura; 403 si está bloqueado. |
| `POST /conversations/{id}/report` | Cuerpo `{ "body": "motivo" }`. 201 `{ "id" }`. |

Conversación: `{ id, listing_id, agency_name, read_only, created_at, last_message_at }`.
Mensaje: `{ id, sender: "customer" | "agency", body, created_at }`. La página de mensajes trae además `read_only`.

## Personal (`/api/v1/staff/chat`, agente o administrador de agencia)

| Método y ruta | Rol | Qué hace |
| --- | --- | --- |
| `GET /conversations` | agente, admin | Agente: las suyas más las sin responder de sus inmuebles asignados. Admin: todas las de su agencia. |
| `GET /conversations/{id}/messages?after=&limit=` | agente, admin | Mensajes. 404 si el agente no puede ver la conversación. |
| `POST /conversations/{id}/messages` | agente, admin | Responde. El primer agente que responde se queda con la conversación (toma atómica). 409 `Conversation already taken` si otro agente respondió primero; 409 si es solo lectura. |
| `POST /conversations/{id}/reassign` | admin | Cuerpo `{ "agent_id": "..." }` o `{}` para elegir automáticamente al agente con menos conversaciones. El agente debe estar activo y asignado al inmueble. |
| `POST /conversations/{id}/report` | agente, admin | Reporta al cliente. |
| `GET /reports` | admin de agencia, admin de plataforma | Reportes con `agent_ids` de los autores. |
| `GET /blocks` | admin | Clientes bloqueados por la agencia. |
| `PUT /customers/{customer_id}/block` | admin | Bloquea al cliente en la agencia (204). |
| `POST /customers/{customer_id}/unblock` | admin | Desbloquea (204). Es `POST` porque CORS no permite `DELETE`. |

Conversación del personal: `{ id, listing_id, customer_email, status: "unclaimed" | "claimed", mine, read_only, needs_admin, overdue, created_at, last_message_at, agent_id?, agent_email? }`. `agent_id` y `agent_email` solo para el administrador.
Mensaje del personal: `{ id, sender: "customer" | "agent" | "admin", mine, body, created_at, author_id?, author_email? }`. `author_*` solo para el administrador.

- `needs_admin`: no quedó ningún agente activo asignado; el administrador debe responder o reasignar.
- `overdue`: el cliente espera respuesta desde hace 24 h o más. Se calcula al consultar; el aviso es de F14.7.

## Asignación de agentes (`/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/agents`, admin de esa agencia)

- `GET` → `{ "agents": [{ id, email, active }] }`.
- `PUT` con `{ "agent_ids": [...] }` reemplaza la lista. Cada agente debe estar activo y pertenecer a la agencia (422 si no). Quitar a un agente reasigna sus conversaciones de ese inmueble.
- La lista de agentes de la agencia ya existe: `GET /api/v1/agencies/agents`; inactivar: `POST /api/v1/agencies/agents/{id}/deactivate` (reasigna sus conversaciones).

## Solo lectura

La conversación es de solo lectura (409 al escribir, `read_only: true`) cuando el inmueble deja de estar aprobado y publicado, o cuando otro cliente lo reservó. El cliente que reservó puede seguir conversando.

## Reasignación automática

Al inactivar al agente o quitarlo del inmueble, cada conversación suya pasa al agente activo asignado con menos conversaciones (desempate por `id`); conserva el historial. Si no queda ninguno, queda sin dueño con `needs_admin: true`. Si el agente vuelve a activarse, la conversación no regresa.

## Nombre de la agencia

`POST /api/v1/agencies` acepta `name` opcional (por defecto el `id`); la respuesta y el listado lo devuelven.
