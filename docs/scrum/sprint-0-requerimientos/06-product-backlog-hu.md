# Sprint 0 — Product Backlog / HU

| Campo | Valor |
| --- | --- |
| Módulo | S0-06 — CAPITULO 1, apartado 6 |
| Estado | done (formato del modelo: PB + HU con ID/ROL/HISTORIA/PRIORIDAD/SPRINT/PLATAFORMA) |
| IDs | PB-001..049 · HU-001..040 |
| Fuentes | `docs/sprint-0/ids-trazabilidad.md` §6–7 (canónico) |

## 6.1. Lista de historias de usuario (Product Backlog)

| PRODUCT BACKLOG | | | |
| --- | --- | --- | --- |
| PROYECTO | RoomForge — SaaS inmobiliario con recorridos 3D | VERSIÓN | 1.0 |
| PRODUCT OWNER | Calero Suyo Trevor Félix | FECHA | GAP-084 (planificación) |

| PB | HISTORIA DE USUARIO | DESCRIPCIÓN | PRIORIDAD |
| --- | --- | --- | --- |
| PB-01 | Registro cliente | Permitir al cliente registrarse con correo (inventado en esta fase) y contraseña. | Alta |
| PB-02 | Autenticación y sesión | Permitir iniciar sesión con sesión persistente e inactividad de 30 min. | Alta |
| PB-03 | Verificación de correo real | Activar la cuenta con enlace de un solo uso (Sprint 3). | Alta |
| PB-04 | Alta de inmobiliaria | Dar de alta una inmobiliaria con checkout simulado y evento firmado. | Alta |
| PB-05 | Trial y suscripción | Activar prueba de 14 días y suscripción mensual simulada. | Alta |
| PB-06 | Ciclo de suscripción | Gestionar estados, cuotas, upgrade/downgrade, cancelación y purga. | Alta |
| PB-07 | Invitación y membresías | Invitar agentes con enlace seguro y respetar una membresía activa. | Alta |
| PB-08 | Permisos RBAC | Asignar permisos predefinidos por alcance tenant/inmueble. | Alta |
| PB-09 | Guía de captura | Guiar la captura de video + fotos por ambiente en la app. | Alta |
| PB-10 | Subida de capturas | Subir capturas con progreso y reanudación. | Alta |
| PB-11 | Validación de calidad | Validar cantidad/resolución/cobertura y avisar recaptura selectiva. | Alta |
| PB-12 | Difuminado automático | Reducir rostros y texto en las capturas antes de subir. | Alta |
| PB-13 | Solicitud de reconstrucción | Persistir el job y encolarlo para reconstrucción asíncrona. | Alta |
| PB-14 | Estados de job | Mantener pending/running/done/failed/delayed con reintentos. | Alta |
| PB-15 | Cola SQS | Aplicar visibility timeout y tolerar reentregas. | Alta |
| PB-16 | Worker: heartbeat | Reportar vida del worker e idempotencia. | Alta |
| PB-17 | Worker: Meshroom | Ejecutar el pipeline de reconstrucción en la GPU. | Alta |
| PB-18 | GLB optimizado | Generar el modelo GLB navegable por ambiente. | Alta |
| PB-19 | Nubes y texturas | Almacenar nubes de puntos y texturas en S3. | Alta |
| PB-20 | Plano 2D | Derivar el plano 2D básico de la reconstrucción. | Alta |
| PB-21 | Preview y aprobación | Revisar el preview (3D + plano) y aprobar o rechazar. | Alta |
| PB-22 | Composición espacial | Ensamblar ambientes y conectar puertas en el editor 2D. | Alta |
| PB-23 | Recorrido 3D web | Recorrer el inmueble en 3D en el panel web. | Alta |
| PB-24 | Recorrido 3D app | Recorrer el inmueble en 3D desde la app del cliente. | Alta |
| PB-25 | Medidas con confianza | Mostrar medidas estimadas/calibradas con confianza visible. | Alta |
| PB-26 | Plano 2D cliente | Permitir al cliente consultar el plano 2D con acceso aprobado. | Alta |
| PB-27 | Configuración visual | Ofrecer catálogo low-poly acotado con fallback genérico. | Media |
| PB-28 | Editor de publicación | Crear y editar el borrador de publicación. | Alta |
| PB-29 | Revisión y aprobación | Enviar a revisión, aprobar o rechazar con verificación de difuminado. | Alta |
| PB-30 | Publicación y catálogo | Publicar/despublicar y exponer el catálogo global solo de publicados. | Alta |
| PB-31 | Versionado | Versionar cambios comerciales sin reescribir reservas. | Alta |
| PB-32 | Favoritos | Guardar inmuebles y ver su estado de publicación. | Media |
| PB-33 | Solicitud de acceso | Solicitar acceso al contenido detallado del inmueble. | Alta |
| PB-34 | Aprobación/revocación | Aprobar o revocar accesos temporales con vigencia de 7 días. | Alta |
| PB-35 | Catálogo maestro | Administrar elementos, categorías y reglas del tenant. | Alta |
| PB-36 | Configuración de elementos | Configurar elementos por publicación (obligatorios/incluidos/opcionales). | Alta |
| PB-37 | Motor de precios | Calcular precio con desglose y depósito por operación. | Alta |
| PB-38 | Ajustes por publicación | Aplicar ajustes de precio por elemento en cada publicación. | Alta |
| PB-39 | Simulación de precio | Permitir al cliente simular el precio con la configuración. | Alta |
| PB-40 | Reserva congelada | Crear reserva con precio fijo y congelado con depósito. | Alta |
| PB-41 | Escrow de prueba | Registrar y validar movimientos del token de prueba en el contrato. | Alta |
| PB-42 | Aceptación atómica | Aceptar una reserva y rechazar/reembolsar las competidoras. | Alta |
| PB-43 | Expiración de reserva | Aplicar vigencia congelada y expiración idempotente. | Alta |
| PB-44 | Notificaciones | Notificar in-app, push y correo con auditoría. | Media |
| PB-45 | Exportación | Exportar plano 2D y GLB solo a personal autorizado del tenant. | Media |
| PB-46 | Auditoría y retención | Registrar acciones y aplicar retención/anonimización. | Alta |
| PB-47 | Infraestructura AWS | Desplegar frontend, backend y BD en AWS (ECS Express). | Alta |
| PB-48 | Entorno local | Levantar Docker Compose + Floci por integrante. | Alta |
| PB-49 | CI básica | Ejecutar tests y smoke test en cada merge. | Alta |

## 6.2. Historias de usuario

| ID | ROL | HISTORIA DE USUARIO | PRIORIDAD | SPRINT | PLATAFORMA |
| --- | --- | --- | --- | --- | --- |
| HU-01 | Cliente | Como cliente quiero registrarme con correo (puede ser inventado) y contraseña para probar la plataforma. | Alta | 1 | App cliente |
| HU-02 | Cliente | Como cliente quiero iniciar sesión y mantener mi sesión activa para acceder al catálogo. | Alta | 1 | App cliente |
| HU-03 | Cliente | Como cliente quiero verificar mi correo real con un enlace de activación para confirmar mi cuenta. | Alta | 3 | App cliente |
| HU-04 | Inmobiliaria | Como inmobiliaria quiero darme de alta con checkout simulado para operar en la plataforma. | Alta | 1 | Web |
| HU-05 | Administrador | Como administrador quiero activar la prueba de 14 días y suscribirme mensualmente para operar mi tenant. | Alta | 1 | Web |
| HU-06 | Administrador | Como administrador quiero gestionar mi suscripción, ver cuotas, cancelar y controlar la purga. | Alta | 1–2 | Web |
| HU-07 | Administrador | Como administrador quiero invitar agentes para que acepten con enlace seguro. | Alta | 1 | Web |
| HU-08 | Administrador | Como administrador quiero activar o desactivar membresías de agentes para mantener una activa. | Alta | 1 | Web |
| HU-09 | Administrador | Como administrador quiero asignar permisos por alcance a mis agentes. | Alta | 1 | Web |
| HU-10 | Agente | Como agente quiero capturar un ambiente siguiendo la guía en la app. | Alta | 2 | App captura |
| HU-11 | Agente | Como agente quiero subir mis capturas con progreso y reanudación. | Alta | 2 | App captura |
| HU-12 | Agente | Como agente quiero ver avisos de calidad y recapturar un ambiente. | Alta | 2 | App captura |
| HU-13 | Agente | Como agente quiero solicitar una reconstrucción y seguir el estado del job. | Alta | 2 | App captura |
| HU-14 | Agente | Como agente quiero ver el detalle de un fallo y reintentar la reconstrucción. | Alta | 2 | App captura |
| HU-15 | Agente / Administrador | Como agente o administrador quiero revisar el preview (3D + plano) y aprobar o rechazar la reconstrucción. | Alta | 2 | Web |
| HU-16 | Agente | Como agente quiero ensamblar ambientes y conectar puertas del inmueble. | Alta | 2 | Web |
| HU-17 | Agente / Administrador | Como agente o administrador quiero recorrer el inmueble en 3D desde el panel. | Alta | 2 | Web |
| HU-18 | Cliente | Como cliente quiero recorrer el inmueble en 3D desde la app. | Alta | 3 | App cliente |
| HU-19 | Cliente | Como cliente quiero ver las medidas y su confianza (estimada/calibrada). | Alta | 2–3 | App cliente |
| HU-20 | Cliente | Como cliente quiero ver el plano 2D del inmueble. | Alta | 3 | App cliente |
| HU-21 | Agente | Como agente quiero configurar los elementos visuales de la publicación. | Media | 3 | Web |
| HU-22 | Agente | Como agente quiero crear y editar el borrador de una publicación. | Alta | 1 | Web |
| HU-23 | Agente | Como agente quiero enviar la publicación a revisión y conocer el resultado. | Alta | 1 | Web |
| HU-24 | Administrador | Como administrador quiero aprobar o rechazar publicaciones verificando el difuminado. | Alta | 1 | Web |
| HU-25 | Agente / Administrador | Como agente o administrador quiero publicar o despublicar un inmueble. | Alta | 1 | Web |
| HU-26 | Cliente | Como cliente quiero consultar el catálogo global de inmuebles. | Alta | 1 | App cliente |
| HU-27 | Agente / Administrador | Como agente o administrador quiero revisar que los cambios comerciales quedan versionados. | Alta | 3 | Web |
| HU-28 | Cliente | Como cliente quiero guardar favoritos y ver su estado. | Media | 1 | App cliente |
| HU-29 | Cliente | Como cliente quiero solicitar acceso al contenido detallado. | Alta | 3 | App cliente |
| HU-30 | Agente / Administrador | Como agente o administrador quiero aprobar o revocar accesos temporales. | Alta | 3 | Web |
| HU-31 | Administrador | Como administrador quiero mantener el catálogo maestro de elementos y reglas. | Alta | 2 | Web |
| HU-32 | Agente | Como agente quiero configurar elementos y ajustes de precio de un inmueble. | Alta | 2 | Web |
| HU-33 | Agente / Administrador | Como agente o administrador quiero ver el desglose del precio y el depósito calculado. | Alta | 2 | Web |
| HU-34 | Cliente | Como cliente quiero simular el precio con la configuración. | Alta | 2 | App cliente |
| HU-35 | Cliente | Como cliente quiero reservar un inmueble con depósito de prueba. | Alta | 2 | App cliente |
| HU-36 | Agente / Administrador | Como agente o administrador quiero aceptar o rechazar reservas pendientes. | Alta | 2–3 | Web |
| HU-37 | Cliente | Como cliente quiero ver el estado de mi reserva y su expiración. | Alta | 2–3 | App cliente |
| HU-38 | Todos | Como usuario quiero recibir notificaciones de eventos relevantes. | Media | 3 | App cliente / App captura / Web |
| HU-39 | Agente / Administrador | Como agente o administrador quiero exportar el plano y el GLB de mis inmuebles. | Media | 3 | Web |
| HU-40 | Administrador | Como administrador quiero consultar la auditoría y retención del tenant. | Alta | 3 | Web |

> Nota: la prioridad del modelo usa Alta/Media/Baja; nuestro Must → Alta y Should → Media. Los criterios de aceptación formales de cada HU (contrato del estándar) se redactan en el Sprint Planning que la implementa (GAP-070).
