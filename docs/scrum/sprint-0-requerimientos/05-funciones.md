# Sprint 0 — Funciones

| Campo | Valor |
| --- | --- |
| Módulo | S0-05 — CAPITULO 1, apartado 5 |
| Estado | done (formato del modelo: FUNCIÓN/DESCRIPCIÓN/BACKLOG por superficie) |
| IDs | RF-001..041; PB-001..049 |
| Fuentes | `docs/sprint-0/ids-trazabilidad.md` §3 y §6 |

Las funciones se describen organizadas por módulo y plataforma, tomando como base los **49 elementos del Product Backlog** (registro canónico: ids-trazabilidad §6).

## 5.1. Funciones del panel web

| FUNCIÓN | DESCRIPCIÓN | BACKLOG |
| --- | --- | --- |
| Alta de inmobiliaria | Permite dar de alta una inmobiliaria con checkout simulado y evento firmado. | PB-04 |
| Gestión de suscripción | Permite activar trial, suscribirse y gestionar cuotas, cancelación y purga. | PB-05, PB-06 |
| Gestión de agentes | Permite invitar agentes y gestionar sus membresías (una activa). | PB-07 |
| Gestión de permisos | Permite asignar permisos predefinidos por alcance (tenant/inmueble). | PB-08 |
| Catálogo maestro | Permite administrar elementos, categorías y reglas del tenant. | PB-35 |
| Editor de publicación | Permite crear y editar el borrador del inmueble con su configuración. | PB-28, PB-36, PB-38 |
| Revisión y aprobación | Permite revisar y aprobar o rechazar publicaciones (verifica difuminado). | PB-29 |
| Publicación y catálogo | Permite publicar/despublicar y consultar el estado del catálogo global. | PB-30 |
| Versionado comercial | Permite revisar cambios versionados sin alterar lo publicado. | PB-31 |
| Composición espacial | Permite ensamblar ambientes y conectar puertas en el editor 2D. | PB-22 |
| Recorrido 3D web | Permite recorrer el inmueble en 3D en el navegador. | PB-23 |
| Configuración visual | Permite configurar elementos visuales con catálogo low-poly y fallback. | PB-27 |
| Gestión de reservas | Permite ver, aceptar o rechazar reservas pendientes. | PB-42 |
| Acceso temporal | Permite aprobar o revocar los accesos temporales de clientes. | PB-34 |
| Exportación | Permite descargar plano 2D y GLB (solo personal autorizado). | PB-45 |
| Auditoría | Permite consultar la bitácora y retención del tenant. | PB-46 |

## 5.2. Funciones de la app móvil del cliente

| FUNCIÓN | DESCRIPCIÓN | BACKLOG |
| --- | --- | --- |
| Registro y login | Permite registrarse con correo (inventado en fases tempranas) e iniciar sesión. | PB-01, PB-02 |
| Catálogo global | Permite consultar publicaciones activas de todas las inmobiliarias. | PB-30 |
| Favoritos | Permite guardar inmuebles y ver su estado de publicación. | PB-32 |
| Solicitud de acceso | Permite solicitar acceso al contenido detallado del inmueble. | PB-33 |
| Recorrido 3D | Permite recorrer el inmueble en 3D desde el móvil. | PB-24 |
| Plano 2D | Permite consultar el plano 2D del inmueble con acceso aprobado. | PB-26 |
| Medidas | Permite ver las medidas y su confianza (estimada/calibrada). | PB-25 |
| Simulación de precio | Permite simular el precio con la configuración elegida. | PB-39 |
| Reserva | Permite reservar con precio congelado y depósito de prueba. | PB-40 |
| Verificación de correo | Permite activar el correo real con enlace de un solo uso (Sprint 3). | PB-03 |
| Notificaciones | Permite recibir notificaciones in-app y push. | PB-44 |

## 5.3. Funciones de la app de captura (agente)

| FUNCIÓN | DESCRIPCIÓN | BACKLOG |
| --- | --- | --- |
| Guía de captura | Permite seguir los pasos de video + fotos por ambiente. | PB-09 |
| Difuminado automático | Reduce rostros y texto en las capturas antes de subir. | PB-12 |
| Subida con progreso | Permite subir capturas con progreso y reanudación. | PB-10 |
| Validación de calidad | Informa calidad mínima y permite recaptura selectiva. | PB-11 |
| Solicitud de reconstrucción | Permite solicitar la reconstrucción y seguir el estado del job. | PB-13, PB-14 |
| Revisión del preview | Permite revisar el preview 3D + plano y aprobar o rechazar. | PB-21 |

## 5.4. Funciones del worker 3D y del sistema

| FUNCIÓN | DESCRIPCIÓN | BACKLOG |
| --- | --- | --- |
| Cola de jobs | Persiste el job antes de encolar; SQS con visibility timeout y reentrega. | PB-15 |
| Worker 3D | Ejecuta Meshroom con heartbeat e idempotencia. | PB-16, PB-17 |
| Artefactos | Genera GLB optimizado, nubes y texturas en S3. | PB-18, PB-19 |
| Plano 2D | Deriva el plano 2D básico de la reconstrucción aprobada. | PB-20 |
| Escrow de prueba | Registra y valida los movimientos del token de prueba (contrato + listener). | PB-41 |
| Expiración de reservas | Aplica vigencia y reembolso idempotente. | PB-43 |
| Notificaciones | Envía eventos in-app/push/correo con auditoría. | PB-44 |
| Infraestructura | Entorno local (Docker + Floci), CI y despliegue AWS. | PB-47, PB-48, PB-49 |
