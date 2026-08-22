# Sprint 0 — Requerimientos iniciales

| Campo | Valor |
| --- | --- |
| Módulo | S0-04 — CAPITULO 1, apartado 4 |
| Estado | done (formato del modelo: CÓDIGO/MÓDULO/REQUERIMIENTO/PRIORIDAD) |
| IDs | RF-001..041 · RNF-001..018 · BR-001..076 |
| Fuentes | `docs/sprint-0/ids-trazabilidad.md` §3–5; `docs/sprint-0/auditoria-br.md` |

## 4.1. Necesidades identificadas

1. **Recorrido inmobiliario sin visitas**: los clientes necesitan conocer el interior de un inmueble a distancia, mediante recorridos 3D navegables generados con capturas de celular.
2. **Publicación controlada**: las inmobiliarias necesitan configurar precios, elementos y reglas y publicar solo tras aprobación administrativa.
3. **Reserva demostrable**: el cliente necesita reservar un inmueble con precio congelado y depósito de prueba, sin pagos reales.
4. **SaaS demostrable**: la inmobiliaria necesita un ciclo completo de onboarding con suscripción simulada y cuotas.
5. **Cumplimiento docente**: frontend, backend y base de datos desplegados en un proveedor cloud (AWS).

## 4.2. Requerimientos generales del sistema

- **Aplicaciones móviles (Flutter)**: app de cliente (catálogo, recorridos, reservas) y app de captura (agente), en Android 10+.
- **Panel web (React/Vite)**: administración de tenant, agentes, publicaciones, catálogo maestro, reservas y auditoría.
- **Backend/API (FastAPI)**: recibe, valida y procesa la información; autoridad de estados con PostgreSQL; orquesta el pipeline 3D (S3/SQS) y el escrow de prueba.
- **Worker 3D (Python/Meshroom)**: reconstruye ambientes y genera GLB y plano 2D.
- **Blockchain (escrow de prueba)**: valida movimientos del token de prueba en red local Hardhat.

## 4.3. Requisitos funcionales

| CÓDIGO | MÓDULO | REQUERIMIENTO | PRIORIDAD |
| --- | --- | --- | --- |
| RF-01 | Identidad | El sistema debe permitir al cliente registrarse con correo (cualquiera, sin verificación en fases tempranas) y contraseña, para probar la plataforma. | Alta |
| RF-02 | Identidad | El sistema debe autenticar con Argon2id + JWT/refresh y cerrar sesión por inactividad de 30 minutos. | Alta |
| RF-03 | Onboarding | El sistema debe dar de alta una inmobiliaria mediante checkout simulado y aprovisionar el tenant tras un evento firmado. | Alta |
| RF-04 | Tenancy | El administrador debe invitar agentes con un enlace seguro de un solo uso. | Alta |
| RF-05 | Tenancy | El sistema debe aplicar permisos predefinidos por alcance (tenant o inmueble). | Alta |
| RF-06 | Tenancy | El sistema debe restringir al agente a una única membresía activa. | Alta |
| RF-07 | Planes | El sistema debe ofrecer prueba de 14 días y suscripción mensual simulada (3 planes, BOB). | Alta |
| RF-08 | Planes | El sistema debe gestionar estados de suscripción, cuotas y bloqueo cuando se supera una cuota. | Alta |
| RF-09 | Planes | El sistema debe aplicar subida de plan inmediata y bajada al renovar. | Media |
| RF-10 | Captura | La app de captura debe guiar al agente en la captura híbrida (video + fotos) de un ambiente. | Alta |
| RF-11 | Captura | El sistema debe difuminar automáticamente rostros y texto en las capturas. | Alta |
| RF-12 | Reconstrucción | El sistema debe solicitar reconstrucción asíncrona persistiendo el job antes de encolarlo (SQS). | Alta |
| RF-13 | Reconstrucción | El agente o administrador debe aprobar o rechazar la reconstrucción tras revisar el preview. | Alta |
| RF-14 | Reconstrucción | El sistema debe generar un GLB navegable y un plano 2D básico por ambiente. | Alta |
| RF-15 | Composición | El agente debe ensamblar ambientes en el editor 2D conectando puertas para formar el inmueble. | Alta |
| RF-16 | Visualización | El sistema debe permitir el recorrido 3D navegable en el panel web y en la app del cliente. | Alta |
| RF-17 | Visualización | El sistema debe ofrecer configuración visual con catálogo low-poly acotado y fallback genérico. | Media |
| RF-18 | Visualización | El sistema debe mostrar medidas etiquetadas como estimadas o calibradas con confianza visible. | Alta |
| RF-19 | Publicación | El sistema debe permitir el workflow de publicación con estados borrador, en revisión, publicado, rechazado y despublicado. | Alta |
| RF-20 | Publicación | El sistema debe versionar los cambios comerciales sin reescribir reservas existentes. | Alta |
| RF-21 | Catálogo | El catálogo global debe mostrar únicamente publicaciones en estado publicado. | Alta |
| RF-22 | Acceso | El sistema debe permitir solicitar y aprobar acceso temporal al detalle (7 días). | Alta |
| RF-23 | Acceso | El sistema debe revocar inmediatamente los accesos activos al despublicar el inmueble. | Alta |
| RF-24 | Precios | El sistema debe permitir configurar elementos por publicación (obligatorios, incluidos-removibles, opcionales-agregables). | Alta |
| RF-25 | Precios | El sistema debe calcular el precio con desglose y el depósito por operación (venta % / alquiler × multiplicador). | Alta |
| RF-26 | Precios | El sistema debe mantener el catálogo maestro del tenant y los ajustes de precio por publicación. | Alta |
| RF-27 | Reservas | El sistema debe crear una reserva de precio fijo y congelado con escrow de token de prueba. | Alta |
| RF-28 | Reservas | El sistema debe aceptar una reserva de forma atómica y rechazar/reembolsar las competidoras. | Alta |
| RF-29 | Reservas | El sistema debe aplicar la vigencia congelada y expirar de forma idempotente con reembolso. | Alta |
| RF-30 | Catálogo | El sistema debe conservar en favoritos las publicaciones ya no disponibles con su estado. | Media |
| RF-31 | Notificaciones | El sistema debe notificar in-app, push y correo con auditoría de motivo y destinatarios. | Media |
| RF-32 | Exportación | El sistema debe permitir exportar plano 2D y GLB solo a personal autorizado del tenant. | Media |
| RF-33 | Identidad | El sistema debe verificar el correo real con enlace de activación de un solo uso (habilitada en el Sprint 3). | Alta |
| RF-34 | Captura | La app debe ofrecer guía paso a paso de captura y subida con progreso y reanudación. | Alta |
| RF-35 | Captura | El sistema debe validar cantidad, resolución y cobertura mínimas de las capturas y avisar recaptura selectiva. | Alta |
| RF-36 | Reconstrucción | El sistema debe mantener estados de job pending, running, done, failed y delayed con reintentos acotados. | Alta |
| RF-37 | Reconstrucción | El worker debe ejecutar Meshroom con heartbeat, idempotencia y tolerancia a reentregas. | Alta |
| RF-38 | Reconstrucción | El sistema debe generar artefactos por ambiente: GLB optimizado, nubes de puntos y texturas. | Alta |
| RF-39 | Reconstrucción | El sistema debe derivar el plano 2D básico desde la reconstrucción aprobada. | Media |
| RF-40 | Reconstrucción | El sistema debe mostrar un preview (visor + plano) antes de aprobar o rechazar la reconstrucción. | Alta |
| RF-41 | Visualización | El cliente con acceso aprobado debe consultar el plano 2D del inmueble. | Media |

## 4.4. Requisitos no funcionales

| CÓDIGO | CATEGORÍA | REQUERIMIENTO |
| --- | --- | --- |
| RNF-01 | Precisión | Las medidas deben etiquetarse estimadas o calibradas, con confianza visible y ocultamiento ante baja confianza; la tolerancia numérica se fija tras SPK-02 (GAP-065). |
| RNF-02 | Rendimiento | La reconstrucción por ambiente debe completarse en ≤ 30 minutos (objetivo; a validar con SPK-01, GAP-066). |
| RNF-03 | Rendimiento | Las operaciones de API deben responder con p95 ≤ 2 segundos. |
| RNF-04 | Rendimiento | El visor 3D debe alcanzar 30 FPS objetivo / 24 FPS mínimo y primera vista ≤ 20 segundos. |
| RNF-05 | Disponibilidad | Los servicios centrales deben recuperarse en ≤ 5 minutos durante la demo; los jobs demorados continúan en cola. |
| RNF-06 | Seguridad | El sistema debe exigir TOTP administrativo, sesión por inactividad de 30 minutos y aislamiento multi-tenant. |
| RNF-07 | Privacidad | Las capturas crudas deben eliminarse a los 30 días; los derivados sobreviven 7 días recuperables. |
| RNF-08 | Privacidad | El difuminado automático debe complementarse con revisión humana obligatoria antes de publicar. |
| RNF-09 | Privacidad | Las cuentas eliminadas deben anonimizar las transacciones asociadas. |
| RNF-10 | Privacidad | Los logs técnicos deben conservarse 7 días y la auditoría 90 días. |
| RNF-11 | Compatibilidad | Las apps móviles deben operar en Android 10+, 64-bit y 4 GB de RAM. |
| RNF-12 | Compatibilidad | El panel web debe soportar las dos últimas versiones estables de Chrome y Edge. |
| RNF-13 | Compatibilidad | iOS debe mantenerse compatible en código sin build verificado (no ejecutado). |
| RNF-14 | Accesibilidad | El panel web debe cumplir WCAG 2.2 AA y ofrecer alternativa con plano 2D y ficha. |
| RNF-15 | Observabilidad | El sistema debe exponer panel y correo con métricas accionables. |
| RNF-16 | Disponibilidad | La indisponibilidad del worker debe mostrarse con degradación explícita sin caer los servicios transaccionales. |
| RNF-17 | Seguridad | Los enlaces de activación e invitación deben ser de un solo uso; jamás se envían contraseñas por correo. |
| RNF-18 | Costo | El despliegue AWS debe diferirse a días antes de la presentación para controlar costos. |

## 4.5. Reglas de negocio iniciales

Reglas completas en [`auditoria-br.md`](../../sprint-0/auditoria-br.md) (registro canónico, 76 reglas con fuente). Resumen por área:

1. **Identidad y tenancy (BR-001..BR-022)**: cliente global sin membresía; tenants aislados; agentes invitados por el admin; una membresía activa; permisos por alcance; RBAC con catálogo de 13 permisos.
2. **Onboarding, planes y suscripción (BR-023..BR-031)**: checkout simulado con evento firmado; trial 14 días; 3 planes con cuotas; over-quota conserva datos y bloquea altas; cancelación → solo lectura 30 días → purga conservando transacciones anonimizadas.
3. **Publicaciones y catálogo (BR-032..BR-039)**: estados versionados; aprobación administrativa; catálogo global solo de publicados; favoritos conservan estado; calidad mínima para publicar.
4. **Configuración y precios (BR-040..BR-045)**: elementos obligatorios/incluidos/opcionales; desglose y congelamiento al reservar; depósito 1% (venta) y multiplicador 1,0 (alquiler) configurables; catálogo maestro tenant-scoped; ajustes por publicación.
5. **Acceso temporal (BR-046..BR-051)**: solicitud notifica agente y admin; 7 días desde la aprobación; renovación requiere nueva aprobación; rechazo/revocación con motivo y auditoría; despublicación revoca inmediatamente.
6. **Reservas y escrow (BR-052..BR-058)**: precio fijo sin negociación; vigencia 72 h configurable congelada al crear; aceptación atómica; escrow de token de prueba con transiciones únicas; sin visitas presenciales.
7. **Contenido 3D (BR-059..BR-062)**: captura y reconstrucción por ambiente; medidas estimadas/calibradas; persistencia antes de encolar; difuminado + revisión humana.
8. **Exportación, retención y privacidad (BR-063..BR-067)**: exportación solo personal del tenant con URLs firmadas y auditoría; retención 30/7 días; derivados recuperables.
9. **Notificaciones (BR-068..BR-076)**: canales in-app/push/correo; triggers con destinatarios; registro de auditoría; enlaces firmados solo en activación/invitación.

## 4.6. Gaps vigentes

- **GAP-061**: nombres, precios y cuotas de los 3 planes (depende de SPK-01/SPK-04).
- **GAP-065**: tolerancia numérica de medidas (depende de SPK-02) → RNF-01.
- **GAP-066**: timeout técnico y concurrencia de jobs (depende de SPK-01) → RNF-02.
