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
| PB-001 | Registro cliente | Permitir al cliente registrarse con correo (inventado en esta fase) y contraseña. | Alta |
| PB-002 | Autenticación y sesión | Permitir iniciar sesión con sesión persistente e inactividad de 30 min. | Alta |
| PB-003 | Verificación de correo real | Activar la cuenta con enlace de un solo uso (Sprint 3). | Alta |
| PB-004 | Alta de inmobiliaria | Dar de alta una inmobiliaria con checkout simulado y evento firmado. | Alta |
| PB-005 | Trial y suscripción | Activar prueba de 14 días y suscripción mensual simulada. | Alta |
| PB-006 | Ciclo de suscripción | Gestionar estados, cuotas, upgrade/downgrade, cancelación y purga. | Alta |
| PB-007 | Invitación y membresías | Invitar agentes con enlace seguro y respetar una membresía activa. | Alta |
| PB-008 | Permisos RBAC | Asignar permisos predefinidos por alcance tenant/inmueble. | Alta |
| PB-009 | Guía de captura | Guiar la captura de video + fotos por ambiente en la app. | Alta |
| PB-010 | Subida de capturas | Subir capturas con progreso y reanudación. | Alta |
| PB-011 | Validación de calidad | Validar cantidad/resolución/cobertura y avisar recaptura selectiva. | Alta |
| PB-012 | Difuminado automático | Reducir rostros y texto en las capturas antes de subir. | Alta |
| PB-013 | Solicitud de reconstrucción | Persistir el job y encolarlo para reconstrucción asíncrona. | Alta |
| PB-014 | Estados de job | Mantener pending/running/done/failed/delayed con reintentos. | Alta |
| PB-015 | Cola SQS | Aplicar visibility timeout y tolerar reentregas. | Alta |
| PB-016 | Worker: heartbeat | Reportar vida del worker e idempotencia. | Alta |
| PB-017 | Worker: Meshroom | Ejecutar el pipeline de reconstrucción en la GPU. | Alta |
| PB-018 | GLB optimizado | Generar el modelo GLB navegable por ambiente. | Alta |
| PB-019 | Nubes y texturas | Almacenar nubes de puntos y texturas en S3. | Alta |
| PB-020 | Plano 2D | Derivar el plano 2D básico de la reconstrucción. | Alta |
| PB-021 | Preview y aprobación | Revisar el preview (3D + plano) y aprobar o rechazar. | Alta |
| PB-022 | Composición espacial | Ensamblar ambientes y conectar puertas en el editor 2D. | Alta |
| PB-023 | Recorrido 3D web | Recorrer el inmueble en 3D en el panel web. | Alta |
| PB-024 | Recorrido 3D app | Recorrer el inmueble en 3D desde la app del cliente. | Alta |
| PB-025 | Medidas con confianza | Mostrar medidas estimadas/calibradas con confianza visible. | Alta |
| PB-026 | Plano 2D cliente | Permitir al cliente consultar el plano 2D con acceso aprobado. | Alta |
| PB-027 | Configuración visual | Ofrecer catálogo low-poly acotado con fallback genérico. | Media |
| PB-028 | Editor de publicación | Crear y editar el borrador de publicación. | Alta |
| PB-029 | Revisión y aprobación | Enviar a revisión, aprobar o rechazar con verificación de difuminado. | Alta |
| PB-030 | Publicación y catálogo | Publicar/despublicar y exponer el catálogo global solo de publicados. | Alta |
| PB-031 | Versionado | Versionar cambios comerciales sin reescribir reservas. | Alta |
| PB-032 | Favoritos | Guardar inmuebles y ver su estado de publicación. | Media |
| PB-033 | Solicitud de acceso | Solicitar acceso al contenido detallado del inmueble. | Alta |
| PB-034 | Aprobación/revocación | Aprobar o revocar accesos temporales con vigencia de 7 días. | Alta |
| PB-035 | Catálogo maestro | Administrar elementos, categorías y reglas del tenant. | Alta |
| PB-036 | Configuración de elementos | Configurar elementos por publicación (obligatorios/incluidos/opcionales). | Alta |
| PB-037 | Motor de precios | Calcular precio con desglose y depósito por operación. | Alta |
| PB-038 | Ajustes por publicación | Aplicar ajustes de precio por elemento en cada publicación. | Alta |
| PB-039 | Simulación de precio | Permitir al cliente simular el precio con la configuración. | Alta |
| PB-040 | Reserva congelada | Crear reserva con precio fijo y congelado con depósito. | Alta |
| PB-041 | Escrow de prueba | Registrar y validar movimientos del token de prueba en el contrato. | Alta |
| PB-042 | Aceptación atómica | Aceptar una reserva y rechazar/reembolsar las competidoras. | Alta |
| PB-043 | Expiración de reserva | Aplicar vigencia congelada y expiración idempotente. | Alta |
| PB-044 | Notificaciones | Notificar in-app, push y correo con auditoría. | Media |
| PB-045 | Exportación | Exportar plano 2D y GLB solo a personal autorizado del tenant. | Media |
| PB-046 | Auditoría y retención | Registrar acciones y aplicar retención/anonimización. | Alta |
| PB-047 | Infraestructura AWS | Desplegar frontend, backend y BD en AWS (ECS Express). | Alta |
| PB-048 | Entorno local | Levantar Docker Compose + Floci por integrante. | Alta |
| PB-049 | CI básica | Ejecutar tests y smoke test en cada merge. | Alta |

## 6.2. Historias de usuario

| ID | ROL | HISTORIA DE USUARIO | PRIORIDAD | SPRINT | PLATAFORMA |
| --- | --- | --- | --- | --- | --- |
| HU-001 | Cliente | Como cliente quiero registrarme con correo (puede ser inventado) y contraseña para probar la plataforma. | Alta | 1 | App cliente |
| HU-002 | Cliente | Como cliente quiero iniciar sesión y mantener mi sesión activa para acceder al catálogo. | Alta | 1 | App cliente |
| HU-003 | Cliente | Como cliente quiero verificar mi correo real con un enlace de activación para confirmar mi cuenta. | Alta | 3 | App cliente |
| HU-004 | Inmobiliaria | Como inmobiliaria quiero darme de alta con checkout simulado para operar en la plataforma. | Alta | 1 | Web |
| HU-005 | Administrador | Como administrador quiero activar la prueba de 14 días y suscribirme mensualmente para operar mi tenant. | Alta | 1 | Web |
| HU-006 | Administrador | Como administrador quiero gestionar mi suscripción, ver cuotas, cancelar y controlar la purga. | Alta | 1–2 | Web |
| HU-007 | Administrador | Como administrador quiero invitar agentes para que acepten con enlace seguro. | Alta | 1 | Web |
| HU-008 | Administrador | Como administrador quiero activar o desactivar membresías de agentes para mantener una activa. | Alta | 1 | Web |
| HU-009 | Administrador | Como administrador quiero asignar permisos por alcance a mis agentes. | Alta | 1 | Web |
| HU-010 | Agente | Como agente quiero capturar un ambiente siguiendo la guía en la app. | Alta | 2 | App captura |
| HU-011 | Agente | Como agente quiero subir mis capturas con progreso y reanudación. | Alta | 2 | App captura |
| HU-012 | Agente | Como agente quiero ver avisos de calidad y recapturar un ambiente. | Alta | 2 | App captura |
| HU-013 | Agente | Como agente quiero solicitar una reconstrucción y seguir el estado del job. | Alta | 2 | App captura |
| HU-014 | Agente | Como agente quiero ver el detalle de un fallo y reintentar la reconstrucción. | Alta | 2 | App captura |
| HU-015 | Agente / Administrador | Como agente o administrador quiero revisar el preview (3D + plano) y aprobar o rechazar la reconstrucción. | Alta | 2 | Web |
| HU-016 | Agente | Como agente quiero ensamblar ambientes y conectar puertas del inmueble. | Alta | 2 | Web |
| HU-017 | Agente / Administrador | Como agente o administrador quiero recorrer el inmueble en 3D desde el panel. | Alta | 2 | Web |
| HU-018 | Cliente | Como cliente quiero recorrer el inmueble en 3D desde la app. | Alta | 3 | App cliente |
| HU-019 | Cliente | Como cliente quiero ver las medidas y su confianza (estimada/calibrada). | Alta | 2–3 | App cliente |
| HU-020 | Cliente | Como cliente quiero ver el plano 2D del inmueble. | Alta | 3 | App cliente |
| HU-021 | Agente | Como agente quiero configurar los elementos visuales de la publicación. | Media | 3 | Web |
| HU-022 | Agente | Como agente quiero crear y editar el borrador de una publicación. | Alta | 1 | Web |
| HU-023 | Agente | Como agente quiero enviar la publicación a revisión y conocer el resultado. | Alta | 1 | Web |
| HU-024 | Administrador | Como administrador quiero aprobar o rechazar publicaciones verificando el difuminado. | Alta | 1 | Web |
| HU-025 | Agente / Administrador | Como agente o administrador quiero publicar o despublicar un inmueble. | Alta | 1 | Web |
| HU-026 | Cliente | Como cliente quiero consultar el catálogo global de inmuebles. | Alta | 1 | App cliente |
| HU-027 | Agente / Administrador | Como agente o administrador quiero revisar que los cambios comerciales quedan versionados. | Alta | 3 | Web |
| HU-028 | Cliente | Como cliente quiero guardar favoritos y ver su estado. | Media | 1 | App cliente |
| HU-029 | Cliente | Como cliente quiero solicitar acceso al contenido detallado. | Alta | 3 | App cliente |
| HU-030 | Agente / Administrador | Como agente o administrador quiero aprobar o revocar accesos temporales. | Alta | 3 | Web |
| HU-031 | Administrador | Como administrador quiero mantener el catálogo maestro de elementos y reglas. | Alta | 2 | Web |
| HU-032 | Agente | Como agente quiero configurar elementos y ajustes de precio de un inmueble. | Alta | 2 | Web |
| HU-033 | Agente / Administrador | Como agente o administrador quiero ver el desglose del precio y el depósito calculado. | Alta | 2 | Web |
| HU-034 | Cliente | Como cliente quiero simular el precio con la configuración. | Alta | 2 | App cliente |
| HU-035 | Cliente | Como cliente quiero reservar un inmueble con depósito de prueba. | Alta | 2 | App cliente |
| HU-036 | Agente / Administrador | Como agente o administrador quiero aceptar o rechazar reservas pendientes. | Alta | 2–3 | Web |
| HU-037 | Cliente | Como cliente quiero ver el estado de mi reserva y su expiración. | Alta | 2–3 | App cliente |
| HU-038 | Todos | Como usuario quiero recibir notificaciones de eventos relevantes. | Media | 3 | App cliente / App captura / Web |
| HU-039 | Agente / Administrador | Como agente o administrador quiero exportar el plano y el GLB de mis inmuebles. | Media | 3 | Web |
| HU-040 | Administrador | Como administrador quiero consultar la auditoría y retención del tenant. | Alta | 3 | Web |

> Nota: la prioridad del modelo usa Alta/Media/Baja; nuestro Must → Alta y Should → Media. Los criterios de aceptación formales de cada HU (contrato del estándar) se redactan en el Sprint Planning que la implementa (GAP-070).
