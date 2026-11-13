# F14.6 — Chat entre cliente y agencia con asignación de agentes

**Objetivo:** el cliente conversa con la agencia desde la ficha de un inmueble; un solo agente atiende cada conversación y la agencia conserva el control y la trazabilidad. **Plan:** `docs/plan-maestro-roomforge.md` F14.6. **Issue:** #75.
**Rama:** `feat/f14-agency-chat` desde `main` actualizado. **Entrega:** `ask-on-risk`; se prevén varios PR (backend, panel, apps).
**Ejecutores de pruebas:** `backend` con `<raiz>/.venv/Scripts/python.exe -m pytest`, Ruff y Pyright; apps con `flutter test` y `flutter analyze`; `panel` con `vitest`.

## Specs

Las citas entre comillas son texto literal del dueño del repositorio. **[Propuesta]** = planteada por el asistente y no objetada por el usuario; confirmar ante cualquier duda.

- **S1 — Superficies.** «Notificaciones y contacto via chat tanto en la app móvil y web» y «Tambien el agente tiene la app movil». El cliente usa la app cliente; el agente responde desde la app de captura y desde el panel; la conversación es la misma en ambas.
- **S2 — Entrada desde el inmueble.** «el cliente al ver un inmueble podrá ver como un botón o popup donde podrá charlar con el agente».
  - **[Propuesta]** Una conversación por cliente e inmueble; el cliente debe tener sesión iniciada; solo texto.
- **S3 — Agentes asignados al inmueble.** «en si la agencia pone que agente/s estaran en la inmobiliara». El administrador de la agencia asigna uno o más agentes a cada inmueble.
- **S4 — El primero que responde atiende.** «el primero que responda podrá hablar con el cliente y otro agente no podrá ver la conversación».
  - Aceptación: mientras nadie responde, la conversación es visible para los agentes asignados al inmueble; con la primera respuesta queda para ese agente y deja de ser visible para los demás.
  - **[Propuesta]** La toma es atómica: si dos agentes responden a la vez, gana uno y el otro recibe el aviso de que ya fue tomada.
- **S5 — Reasignación al inactivar.** «al menos que el admin de la agencia inactive al agente y el sistema automaticamente asigne a un agente disponible asignado al inmueble para poder seguir chateando con el cliente viendo el historial de la conversación».
  - Aceptación: al inactivar al agente, sus conversaciones abiertas pasan a otro agente activo asignado al mismo inmueble, que ve el historial completo.
  - **[Propuesta]** Se elige al agente con menos conversaciones abiertas; ocurre lo mismo si lo quitan del inmueble sin inactivarlo; si no queda ninguno, la conversación pasa al administrador de la agencia; si el agente vuelve a estar activo, la conversación no regresa; el administrador puede reasignar a mano.
- **S6 — Identidad visible y trazabilidad.** «En si el chat no se verá el nombre del agente sino de la inmobiliaria/agencia pero reportará a la agencia y dicha agencia podrá saber que agente fue el que provoco el problema (problema interno entre ellos fuera de alcance).»
  - Aceptación: ninguna respuesta de la API ni pantalla del cliente expone la identidad del agente; el administrador de la agencia ve el autor real de cada mensaje; el cliente puede reportar una conversación a la agencia.
  - Fuera de alcance, por decisión del usuario: cómo resuelve la agencia el problema con su agente.
  - **[Propuesta]** Los mensajes no se editan ni se borran, porque son la evidencia de los reportes.
- **S7 — Casos no cubiertos. [Propuesta]** Sin respuesta en 24 h, se avisa al administrador de la agencia. El reporte del cliente también llega al administrador de la plataforma. El agente puede reportar a un cliente y el administrador puede bloquearlo en su agencia. Si el inmueble se despublica o se reserva, el chat queda en solo lectura salvo para el cliente que lo reservó.
- **S8 — Transporte. [Propuesta]** Decisión técnica abierta entre consulta periódica y conexión persistente; elegir con evidencia en T1 y registrarla en `## Log`. El aviso con la aplicación cerrada pertenece a F14.7.

## Tasks

Estado: ☐ pendiente. Ruta por defecto: en línea.

| ID | Tarea | Specs | Ruta | Estado | Commit / evidencia |
| --- | --- | --- | --- | --- | --- |
| T1 | Leer los módulos `identity`, `agencies` y `catalog`; confirmar cómo se inactiva hoy un agente y cómo se aísla cada agencia; decidir el transporte (S8) y registrar la decisión. | S8 | en línea | ☑ | Decisión en L5 (sin commit de código) |
| T2 | Backend: asignación de agentes a un inmueble (modelo, migración con un solo head, API del administrador y aislamiento por agencia). | S3 | en línea | ☑ | `50e7a08` |
| T3 | Backend: conversaciones y mensajes, toma atómica, visibilidad por rol, ocultamiento de la identidad del agente y autoría para el administrador. | S2, S4, S6 | en línea | ☑ | `3595f94`, `b792f4b` |
| T4 | Backend: reasignación (inactivación, retiro del inmueble, manual), escalamiento por tiempo, reportes, bloqueo y solo lectura. | S5, S7 | en línea | ☑ | `3595f94` |
| T5 | App cliente: botón en la ficha, conversación y lista de conversaciones. | S1, S2, S6 | en línea | ☑ | `e5cb86a` |
| T6 | Panel: bandeja del agente, vista del administrador con autoría, asignación de agentes al inmueble y reasignación. | S1, S3, S5, S6 | en línea | ☑ | `0a013b5` |
| T7 | App de captura: bandeja y conversación del agente. | S1, S4 | en línea | ☑ | `1e568fc` |
| T8 | Cierre: contrato de API, documentación y filas del plan maestro. | — | en línea | ☑ | commit de cierre |

**Riesgo previsto:** T2–T4 nombran el ítem 2 (permisos y visibilidad entre agentes y agencias) y el ítem 4 (toma concurrente); T2 y T3 el ítem 1 (migraciones). Cada uno va en su propio commit.

**Estado verificado (2026-11-12, `main` en `9981b49`, búsqueda por palabras clave, no auditoría):** no se encontró asignación de agentes a inmuebles en `catalog/models.py`, ni módulo de chat en `backend/app/modules/`. No se ejecutó ninguna suite.

## Log

- **L1 (2026-11-12, usuario):** «Notificaciones y contacto via chat tanto en la app móvil y web»
- **L2 (2026-11-12, usuario):** «Tambien el agente tiene la app movil»
- **L3 (2026-11-12, usuario):** «Las calificaciones se harán dentro del inmueble, pero además el cliente podrá charlar con el agente. Para ello el cliente al ver un inmueble podrá ver como un botón o popup donde podrá charlar con el agente, en si la agencia pone que agente/s estaran en la inmobiliara, el primero que responda podrá hablar con el cliente y otro agente no podrá ver la conversación al menos que el admin de la agencia inactive al agente y el sistema automaticamente asigne a un agente disponible asignado al inmueble para poder seguir chateando con el cliente viendo el historial de la conversación (Si ves huechos ayudame a taparlos). En si el chat no se verá el nombre del agente sino de la inmobiliaria/agencia pero reportará a la agencia y dicha agencia podrá saber que agente fue el que provoco el problema (problema interno entre ellos fuera de alcance).»
- **L4 (2026-11-12):** el asistente propuso los puntos marcados **[Propuesta]** a pedido del usuario («Si ves huechos ayudame a taparlos»); el usuario no los objetó ni los confirmó uno por uno. Siguiente paso: T1.
- **L5 (2026-11-12, T1):** lectura de `identity`, `agencies`, `catalog`, `customer_identity` y `reservations` sobre `main` (`afc8f8c`); head Alembic `0029_listing_coordinate_indexes`. Hallazgos: (a) el agente se inactiva con `POST /api/v1/agencies/agents/{id}/deactivate` (`agencies/router.py:298-323`), que pone `StaffAccount.active=False` y revoca sus sesiones; no hay asignación agente-inmueble ni módulo de chat; (b) el aislamiento se hace con helpers por router (`tenant_id` contra `agency_id`), sin `require_role`; (c) «reservado» no es estado del inmueble: es una `Reservation` pending/accepted con índice único parcial por `listing_id`; (d) el cliente se identifica con `get_active_customer` (`id` uuid en `String(36)`); (e) `StaffAccount` y `CustomerAccount` no tienen nombre visible: el cliente verá el nombre de la agencia, que hay que resolver (`Agency` solo tiene `id`). **Transporte (S8): consulta periódica con cursor `since`.** Evidencia: no existe tiempo real en ningún cliente ni en el backend; la autenticación es solo `Authorization: Bearer`, que `EventSource` y `WebSocket` del navegador no envían; la cookie de refresco está limitada a `/api/v1/auth`; CORS no permite otros métodos ni cabeceras. La consulta periódica funciona en las tres superficies sin cambiar CORS ni infraestructura; se puede migrar a SSE después sin cambiar el modelo de datos. Hallazgo ajeno al alcance: `agencies/service.py:219` cuenta métricas con estados que no existen en la base (`in_review`, `published`).
- **L6 (2026-11-13, usuario):** «Agregalo el campo name, y continuamos». Se agregó `Agency.name` (String(120), NOT NULL; migración `0030_agency_name` con relleno `name = id`); `POST /api/v1/agencies` acepta `name` opcional (por defecto el `id`) y create/list lo devuelven. Suite del backend: 1053 pasaron, 16 omitidas; ruff y pyright limpios; head único `0030_agency_name`. La migración no se ejecutó contra PostgreSQL real. Sin commit todavía.
- **L7 (2026-11-13, usuario):** «De una vez dale con todo». Se interpreta como aprobación de las propuestas **[Propuesta]** de S4, S5, S6 y S7 tal como están redactadas, y de ejecutar T2–T8. Ruta: backend en línea (T2–T4); T5, T6 y T7 son tres unidades independientes con superficies disjuntas (cliente, panel, captura), que se delegan en paralelo una vez fijado el contrato de API; T8 en línea.
- **L8 (2026-11-13, T3–T8):** T3 y T4 se implementaron juntas en `3595f94`. El escritor del panel detectó que la API no daba `customer_id` al personal; se corrigió en `b792f4b` (solo para el administrador). El escalamiento de 24 h quedó como marca `overdue` calculada al consultar, sin proceso en segundo plano; el aviso es de F14.7. Verificación: backend 1075 pruebas pasaron y 16 omitidas antes de `b792f4b`, y 22 del chat después; panel 246 pruebas y build; captura y cliente con `flutter analyze` limpio en lo tocado y pruebas nuevas verdes (cliente 201 en total). Fuera de alcance: `flutter analyze` de captura marca un aviso previo en `spatial_capture_controller.dart:463`. Pendiente: migraciones contra PostgreSQL real y revisión nativa del backend.
