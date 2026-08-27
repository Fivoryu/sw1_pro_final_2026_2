# 1. Sprint Planning

El Sprint Planning organiza el incremento funcional de RoomForge para el Sprint 1. El alcance comprende la identidad y autenticación, el onboarding de inmobiliarias, la suscripción simulada, la gestión de agentes y permisos, las publicaciones con aprobación, el catálogo global, los favoritos y el entorno local reproducible con CI básica.

## 1.1. Objetivos del Sprint

### 1.1.1. Objetivo general del Sprint 1

Implementar la base administrativa y comercial de RoomForge para que clientes, inmobiliarias, administradores y agentes puedan operar el flujo inicial de autenticación, suscripción, publicaciones y catálogo global.

### 1.1.2. Objetivos específicos

- Entregar el registro y la autenticación de clientes en modo pruebas, sin verificación real de correo.
- Entregar el onboarding de inmobiliarias mediante checkout simulado y aprovisionamiento del tenant tras el evento firmado.
- Entregar la activación del trial, la suscripción y la gestión de sus estados y cuotas.
- Entregar la invitación de agentes, las membresías y los permisos RBAC por alcance.
- Entregar la creación, revisión, aprobación, publicación y despublicación de inmuebles.
- Entregar el catálogo global con visibilidad exclusiva de publicaciones publicadas.
- Entregar favoritos, entorno local reproducible con Docker + Floci y CI básica.

## 1.2. Equipo Scrum

| INTEGRANTE | ROL SCRUM |
| --- | --- |
| Buceta Pesoa Luis Fernando | Developer |
| Calero Suyo Trevor Félix | Product Owner |
| Cervantes Arancibia Roberto Carlos | Scrum Master |
| Ortiz Montero Luis Enrique | Developer |
| Rebollo Condori Renato | Developer |
| Vedia Barrios Sebastian | Developer |

El Product Owner conserva su rol PO; la responsabilidad de implementación confirmada de HU-001 y HU-002 queda registrada para Calero Suyo Trevor Félix.

## 1.3. Historias de Usuario

### HU-001 Registro con correo (modo pruebas)

Descripción: Como cliente quiero registrarme con correo, que puede ser inventado en esta fase, y contraseña, para probar la plataforma.

Prioridad: Alta | Estimación: 4 PHU

Criterios de Aceptación

- El sistema acepta un correo con formato válido y una contraseña de mínimo 8 caracteres sin exigir verificación.
- La cuenta queda activa al registrarse.
- Un correo duplicado se rechaza con un mensaje claro.
- La contraseña se almacena con Argon2id y nunca en texto plano.

Desarrollador a cargo: Calero Suyo Trevor Félix

Prototipo

### HU-002 Iniciar sesión y mantener sesión

Descripción: Como cliente quiero iniciar sesión y mantener mi sesión activa, para acceder al catálogo.

Prioridad: Alta | Estimación: 8 PHU

Criterios de Aceptación

- Con credenciales válidas se emiten las credenciales de acceso y renovación.
- El refresh token es rotable y revocable.
- La sesión se invalida después de 30 minutos de inactividad.
- Las credenciales inválidas producen un error genérico sin revelar la existencia de la cuenta.
- `logout` revoca el refresh token activo.

Desarrollador a cargo: Calero Suyo Trevor Félix

Prototipo

### HU-004 Alta de inmobiliaria

Descripción: Como inmobiliaria quiero darme de alta con checkout simulado, para operar en la plataforma.

Prioridad: Alta | Estimación: 8 PHU

Criterios de Aceptación

- El checkout simulado muestra el plan, el monto en BOB y la confirmación.
- El tenant se aprovisiona únicamente después de verificar el evento firmado.
- Reprocesar el mismo evento no duplica el tenant.
- El primer administrador recibe un enlace de un solo uso.

Desarrollador a cargo: Buceta Pesoa Luis Fernando

Prototipo

### HU-005 Activar prueba y suscribirse

Descripción: Como administrador quiero activar la prueba de 14 días y suscribirme mensualmente, para operar mi tenant.

Prioridad: Alta | Estimación: 8 PHU

Criterios de Aceptación

- El trial comienza al activarse y dura 14 días.
- La suscripción mensual queda en estado `active` después del evento firmado del simulador.
- Los estados transicionan en el orden definido para la suscripción.

Desarrollador a cargo: Buceta Pesoa Luis Fernando

Prototipo

### HU-006 Gestionar suscripción

Descripción: Como administrador quiero gestionar mi suscripción, ver cuotas, cancelar y controlar la purga, para administrar el ciclo del servicio.

Prioridad: Alta | Estimación: 16 PHU

Criterios de Aceptación

- Se muestran el plan vigente, las cuotas y el uso actual.
- El upgrade entra en vigencia inmediatamente y el downgrade se aplica a la renovación.
- El exceso de cuota conserva los datos y bloquea nuevas altas o reconstrucciones.
- La cancelación pasa por `canceled_read_only` durante 30 días y luego por `purged`, conservando las transacciones anonimizadas.

Desarrollador a cargo: Buceta Pesoa Luis Fernando

Prototipo

### HU-007 Invitar agentes

Descripción: Como administrador quiero invitar agentes para que acepten con un enlace seguro, para incorporarlos al tenant.

Prioridad: Alta | Estimación: 4 PHU

Criterios de Aceptación

- La invitación genera un enlace de un solo uso con expiración.
- El administrador no define ni envía la contraseña del agente.
- Aceptar la invitación crea la membresía sin duplicar la cuenta global.

Desarrollador a cargo: Ortiz Montero Luis Enrique

Prototipo

### HU-008 Activar o desactivar membresías

Descripción: Como administrador quiero activar o desactivar membresías de agentes, para mantener una membresía activa por agente.

Prioridad: Alta | Estimación: 4 PHU

Criterios de Aceptación

- Solo existe una membresía activa por agente; al activar una nueva, la anterior queda inactiva.
- Una membresía `inactiva` o `revocada` niega el acceso.
- La autoría histórica se conserva sin borrar la cuenta ni los registros asociados.

Desarrollador a cargo: Ortiz Montero Luis Enrique

Prototipo

### HU-009 Asignar permisos

Descripción: Como administrador quiero asignar permisos por alcance a mis agentes, para controlar el acceso a las funciones del tenant y de los inmuebles.

Prioridad: Alta | Estimación: 8 PHU

Criterios de Aceptación

- La asignación utiliza únicamente códigos del catálogo de permisos.
- El alcance puede ser tenant o inmueble.
- Sin una asignación válida, el acceso se deniega por defecto.
- Los permisos por defecto provienen de la configuración del rol.

Desarrollador a cargo: Ortiz Montero Luis Enrique

Prototipo

### HU-022 Crear y editar borrador

Descripción: Como agente quiero crear y editar el borrador de una publicación, para preparar un inmueble antes de enviarlo a revisión.

Prioridad: Alta | Estimación: 8 PHU

Criterios de Aceptación

- Se crea el borrador con título y operación de venta o alquiler.
- Los cambios se guardan sin alterar publicaciones existentes.
- El borrador es visible únicamente para el tenant propietario.

Desarrollador a cargo: Rebollo Condori Renato

Prototipo

### HU-023 Enviar a revisión

Descripción: Como agente quiero enviar la publicación a revisión y conocer el resultado, para solicitar su aprobación.

Prioridad: Alta | Estimación: 4 PHU

Criterios de Aceptación

- La transición de `borrador` a `en_revision` registra actor y fecha.
- La operación requiere los permisos correspondientes.
- El agente no puede autoaprobar la publicación.

Desarrollador a cargo: Rebollo Condori Renato

Prototipo

### HU-024 Aprobar o rechazar publicaciones

Descripción: Como administrador quiero aprobar o rechazar publicaciones verificando el difuminado, para controlar la calidad del contenido publicado.

Prioridad: Alta | Estimación: 4 PHU

Criterios de Aceptación

- Aprobar cambia el estado a `publicado`.
- Rechazar cambia el estado a `rechazado` y exige observaciones.
- La revisión incluye la verificación de redacción y difuminado.

Desarrollador a cargo: Rebollo Condori Renato

Prototipo

### HU-025 Publicar o despublicar

Descripción: Como agente o administrador quiero publicar o despublicar un inmueble, para controlar su visibilidad en el catálogo.

Prioridad: Alta | Estimación: 4 PHU

Criterios de Aceptación

- Una publicación con estado `publicado` aparece en el catálogo global.
- Una publicación despublicada desaparece inmediatamente del catálogo.
- La despublicación queda registrada en auditoría.

Desarrollador a cargo: Vedia Barrios Sebastian

Prototipo

### HU-026 Consultar el catálogo global

Descripción: Como cliente quiero consultar el catálogo global de inmuebles, para encontrar publicaciones disponibles.

Prioridad: Alta | Estimación: 4 PHU

Criterios de Aceptación

- Solo se muestran publicaciones con estado `publicado`.
- La consulta no expone contenido interno del tenant.
- El cliente no puede utilizar un `tenant_id` como mecanismo de autorización.

Desarrollador a cargo: Vedia Barrios Sebastian

Prototipo

### HU-028 Guardar favoritos

Descripción: Como cliente quiero guardar favoritos y ver su estado, para conservar inmuebles de interés.

Prioridad: Media | Estimación: 4 PHU

Criterios de Aceptación

- El cliente puede guardar y quitar favoritos.
- Solo existe un favorito por publicación y cliente.
- Si la publicación se despublica, el favorito queda `no_disponible` sin exponer contenido privado.

Desarrollador a cargo: Vedia Barrios Sebastian

Prototipo

## 1.4. Contexto del sistema

El contexto del sistema en el Sprint 1 representa la interacción inicial entre los clientes, las inmobiliarias, los administradores, los agentes y los componentes principales de RoomForge. En esta etapa, el sistema se enfoca en habilitar el acceso seguro, el aprovisionamiento de tenants, la suscripción simulada, la gestión de membresías y permisos, el ciclo de publicaciones y la consulta del catálogo global. El entorno local con Docker + Floci y la CI básica forman parte del alcance técnico del incremento.

## 1.5. Sprint Backlog

SPRINT BACKLOG

Objetivo: Implementar la base administrativa y comercial operativa de RoomForge mediante autenticación, onboarding SaaS, suscripción simulada, gestión de agentes y permisos, publicaciones con aprobación, catálogo global, favoritos, entorno local reproducible y CI básica.

Sprint: 1                 Tiempo programado: 3 semanas

Fecha inicio: GAP-084                 Fecha finalización: GAP-084

| CÓDIGO | TAREA | HORAS |
| --- | --- | ---: |
| PB-001 | Registro cliente | 4 HRS |
| PB-002 | Autenticación y sesión | 8 HRS |
| PB-004 | Alta de inmobiliaria | 8 HRS |
| PB-005 | Trial y suscripción | 8 HRS |
| PB-006 | Ciclo de suscripción | 16 HRS |
| PB-007 | Invitación y membresías | 8 HRS |
| PB-008 | Permisos RBAC | 8 HRS |
| PB-028 | Editor de publicación | 8 HRS |
| PB-029 | Revisión y aprobación | 8 HRS |
| PB-030 | Publicación y catálogo | 8 HRS |
| PB-032 | Favoritos | 4 HRS |
| PB-048 | Entorno local (Docker + Floci) | 8 HRS |
| PB-049 | CI básica | 8 HRS |

**Carga planificada consolidada:** aproximadamente 107 HRS. La cifra corresponde a la planificación por valor esperado; las fechas exactas y la validación de la estimación permanecen pendientes (GAP-072 y GAP-084). HU-001 y HU-002 permanecen con Calero Suyo Trevor Félix por su responsabilidad de implementación confirmada; las demás HUs se distribuyen por bloques funcionales entre los cuatro desarrolladores restantes. La asignación confirmada por el usuario y el equipo queda documentada, mientras que cualquier brecha aún abierta de responsabilidad de pruebas/documentación se mantiene explícitamente como GAP-073.

La organización del Sprint Backlog sigue la dependencia funcional del producto: autenticación antes de onboarding, suscripciones, membresías y permisos; publicaciones después de disponer de autenticación y tenancy; y catálogo global después de la publicación. PB-049 depende del entorno local de PB-048.

No se agrega un tipo de diagrama en esta sección porque el modelo no lo especifica (GAP-CH2-001).
