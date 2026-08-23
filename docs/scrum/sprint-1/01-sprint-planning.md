# Sprint 1 — Sprint Planning

| Campo | Valor |
| --- | --- |
| Módulo | S1-01 — CAPITULO 2, sección 1 |
| Estado | draft (estimación de valor esperado aplicada; validación del equipo pendiente — GAP-072) |
| IDs | SP-01; PB-001..049 (§8.3); HU-001..040 |
| Referencia del modelo | Grupo#12 — CAPITULO 2, sección 1 (Sprint Planning, pág. 151+); PAPS §5.1 (valor esperado) |
| Fuentes | `docs/sprint-0/ids-trazabilidad.md` §10; `docs/scrum/sprint-0-requerimientos/08-planificacion-de-sprints.md` |

## 1.1.1. Objetivo general del Sprint 1

Implementar la base administrativa y comercial del sistema: identidad y autenticación, onboarding SaaS con suscripción simulada, gestión de agentes y permisos, publicaciones con aprobación, catálogo global, favoritos y el entorno local reproducible (Docker + Floci) con CI básica.

## 1.1.2. Objetivos específicos del Sprint 1

1. Entregar registro y autenticación de clientes (modo pruebas: correo sin verificar).
2. Entregar el onboarding de inmobiliarias con checkout simulado y suscripción.
3. Entregar invitación de agentes, membresías y permisos RBAC.
4. Entregar borrador, revisión/aprobación y publicación con catálogo global.
5. Entregar favoritos, entorno local reproducible y CI verde.

## 1.2. Alcance del Sprint (13 PB / 14 HU)

| PB | HISTORIA DE USUARIO | PRIORIDAD | RESULTADO ESPERADO |
| --- | --- | --- | --- |
| PB-001 | Registro cliente | Alta | El cliente puede registrarse con correo (inventado en esta fase) y contraseña desde la app. |
| PB-002 | Autenticación y sesión | Alta | El cliente inicia sesión y mantiene su sesión activa con inactividad de 30 minutos. |
| PB-004 | Alta de inmobiliaria | Alta | La inmobiliaria se da de alta con checkout simulado y su tenant se aprovisiona tras el evento firmado. |
| PB-005 | Trial y suscripción | Alta | El administrador activa la prueba de 14 días y se suscribe mensualmente. |
| PB-006 | Ciclo de suscripción | Alta | El administrador gestiona estados, cuotas, upgrade/downgrade, cancelación y purga. |
| PB-007 | Invitación y membresías | Alta | El administrador invita agentes con enlace seguro; se respeta una membresía activa. |
| PB-008 | Permisos RBAC | Alta | El administrador asigna permisos predefinidos por alcance (tenant/inmueble). |
| PB-028 | Editor de publicación | Alta | El agente crea y edita el borrador de la publicación. |
| PB-029 | Revisión y aprobación | Alta | El agente envía a revisión y el administrador aprueba o rechaza verificando el difuminado. |
| PB-030 | Publicación y catálogo | Alta | El inmueble se publica/despublica y el catálogo global muestra solo publicados. |
| PB-032 | Favoritos | Media | El cliente guarda inmuebles y ve su estado de publicación. |
| PB-048 | Entorno local (Docker + Floci) | Alta | Cada integrante levanta el entorno Docker Compose + Floci. |
| PB-049 | CI básica | Alta | Los tests y el smoke test corren en cada merge. |

> Las HU asociadas por PB se mantienen en el registro canónico (`ids-trazabilidad.md` §9.3) y en el módulo S0-06.

**Entregable principal del Sprint 1**: incremento funcional con autenticación, onboarding SaaS, administración de agentes, publicaciones con aprobación y catálogo global consultable.

## 1.3. Estimación con valor esperado

Método: valor esperado E = (O + 4·P + Pe) / 6, con escenarios optimista (O), probable (P) y pesimista (Pe) en horas. Escala base: S ≈ 4 h, M ≈ 8 h, L ≈ 16 h (aprobada por el equipo, 2026-08-22). *Estimación sin validar: se confirma con el equipo en el Sprint Planning (GAP-072).*

| PB | Complejidad | O (h) | P (h) | Pe (h) | E (h) |
| --- | --- | --- | --- | --- | --- |
| PB-001 | S | 3 | 4 | 6 | 4,2 |
| PB-002 | M | 5 | 8 | 12 | 8,2 |
| PB-004 | M | 6 | 8 | 12 | 8,3 |
| PB-005 | M | 5 | 8 | 12 | 8,2 |
| PB-006 | A | 10 | 16 | 24 | 16,3 |
| PB-007 | M | 6 | 8 | 12 | 8,3 |
| PB-008 | M | 5 | 8 | 12 | 8,2 |
| PB-028 | M | 6 | 8 | 12 | 8,3 |
| PB-029 | M | 5 | 8 | 12 | 8,2 |
| PB-030 | M | 6 | 8 | 12 | 8,3 |
| PB-032 | S | 2 | 4 | 6 | 4,0 |
| PB-048 | M | 6 | 8 | 12 | 8,3 |
| PB-049 | M | 5 | 8 | 12 | 8,2 |
| **Total** | | | | | **≈ 107 h** |

## 1.4. Capacidad vs. carga

- Duración propuesta: **21 días calendario** (3 semanas, GAP-084 para fechas exactas).
- Capacidad del equipo: **20 h/semana base** (total equipo) + hasta **20 h variables** → 60 h base / 120 h total por sprint.
- Carga estimada: **≈ 107 h** → entra con **capacidad variable (~36 h/semana promedio)**, pero **supera la base conservadora (~60 h)**.

**Decisión tomada (2026-08-22): Opción A** — se compromete la **capacidad variable**: entran los **13 PB (≈ 107 h)**. PB-006 (ciclo de suscripción) y PB-032 (favoritos) permanecen en SP-01; si el consumo real supera la holgura, PB-032 se reagenda primero (menor prioridad). Validación final con el equipo en el Sprint Planning (GAP-072).

## 1.5. Dependencias y condición de entrada

- **SPK-05 ejecutado por los integrantes** (entorno local operativo) antes de iniciar la implementación.
- La cadena de autenticación (PB-001/02) precede a onboarding (PB-004/05/06) y agente/RBAC (PB-007/08).
- Publicaciones (PB-028/29/30) requieren auth y tenancy; catálogo global depende de publicación.
- PB-049 (CI) depende de PB-048 (entorno local).

## 1.6. Definition of Done del Sprint 1

- DoD por HU completo (criterios GAP-070, pruebas TC-### con evidencia, CI verde, commits convencionales).
- "Sin defectos funcionales para publicar" (BR-040) aplicado a publicaciones.
- Documentación del sprint actualizada (diseño/implementación/pruebas en S1-02).

## 1.7. Riesgos propios del Sprint 1

| Riesgo | Mitigación |
| --- | --- |
| R5: capacidad (107 h vs 60 h base) | Decisión de alcance en el Sprint Planning (sección 1.4) |
| Entorno local sin validar (SPK-05) | Bloqueo de inicio hasta smoke test del equipo |
| Stripe fuera de alcance (simulador) | Flujo ya definido: evento firmado del simulador (BR-023) |
| Registro sin verificación de correo | Libre para pruebas; la verificación llega en SP-03 (RF-033) |

## 1.9. Fichas de historias de usuario (SP-01)

Escala del proyecto: **1 PHU = 1 hora estimada** (valor esperado E del sprint, sección 1.3). Desarrollador a cargo: **GAP-073** (asignación en el Sprint Planning). El rótulo `Prototipo` cierra cada ficha; no habilita imágenes embebidas.

### HU-001 — Registro con correo (modo pruebas)

- **Descripción**: Como cliente quiero registrarme con correo (puede ser inventado) y contraseña para probar la plataforma.
- **Prioridad**: Alta · **Estimación**: 4 PHU
- **Criterios de Aceptación**:
  - El sistema acepta un correo de formato válido sin exigir verificación y una contraseña de mínimo 8 caracteres.
  - La cuenta queda activa al registrarse (sin confirmación de correo, RF-001 en SP-01/02).
  - Un correo duplicado se rechaza con mensaje claro.
  - La contraseña se almacena con Argon2id; nunca en claro.
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-002 — Iniciar sesión y mantener sesión

- **Descripción**: Como cliente quiero iniciar sesión y mantener mi sesión activa para acceder al catálogo.
- **Prioridad**: Alta · **Estimación**: 8 PHU
- **Criterios de Aceptación**:
  - Con credenciales válidas se emiten access + refresh; el refresh rotaba y es revocable (tabla `sesion`).
  - La sesión se invalida tras 30 minutos de inactividad (RNF-006).
  - Credenciales inválidas producen un error genérico sin revelar existencia de cuenta.
  - `logout` revoca el refresh activo.
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-004 — Alta de inmobiliaria

- **Descripción**: Como inmobiliaria quiero darme de alta con checkout simulado para operar en la plataforma.
- **Prioridad**: Alta · **Estimación**: 8 PHU
- **Criterios de Aceptación**:
  - El checkout simulado muestra el plan, monto (BOB) y confirmación.
  - El tenant se aprovisiona solo tras verificar el evento firmado (BR-023); la página de éxito por sí sola no crea el tenant.
  - Reprocesar el mismo evento no duplica el tenant (idempotencia).
  - El primer administrador recibe un enlace de un solo uso (BR-024).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-005 — Activar prueba y suscribirse

- **Descripción**: Como administrador quiero activar la prueba de 14 días y suscribirme mensualmente para operar mi tenant.
- **Prioridad**: Alta · **Estimación**: 8 PHU
- **Criterios de Aceptación**:
  - El trial comienza en la activación y dura 14 días.
  - La suscripción mensual quede en `active` tras el evento firmado del simulador.
  - Los estados transicionan en el orden definido (BR-025..031).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-006 — Gestionar suscripción

- **Descripción**: Como administrador quiero gestionar mi suscripción, ver cuotas, cancelar y controlar la purga.
- **Prioridad**: Alta · **Estimación**: 16 PHU
- **Criterios de Aceptación**:
  - Muestra plan vigente, cuotas y uso actual.
  - Upgrade entra en vigencia inmediata; downgrade se aplica a la renovación.
  - Over-quota conserva datos y bloquea nuevas altas/reconstrucciones.
  - Cancelar → `canceled_read_only` (30 días) → `purged` conservando transacciones anonimizadas (BR-029/030).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-007 — Invitar agentes

- **Descripción**: Como administrador quiero invitar agentes para que acepten con enlace seguro.
- **Prioridad**: Alta · **Estimación**: 4 PHU
- **Criterios de Aceptación**:
  - La invitación genera un enlace de un solo uso con expiración (BR-004, RNF-017).
  - El administrador nunca define ni envía la contraseña.
  - Aceptar crea la membrecía sin duplicar la cuenta global (BR-005).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-008 — Activar/desactivar membrecías

- **Descripción**: Como administrador quiero activar o desactivar membrecías de agentes para mantener una activa.
- **Prioridad**: Alta · **Estimación**: 4 PHU
- **Criterios de Aceptación**:
  - Solo una membrecía activa por agente: activar una nueva inactiva la anterior (BR-006).
  - `inactiva`/`revocada` niega acceso sin borrar autoría histórica (BR-007).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-009 — Asignar permisos

- **Descripción**: Como administrador quiero asignar permisos por alcance a mis agentes.
- **Prioridad**: Alta · **Estimación**: 8 PHU
- **Criterios de Aceptación**:
  - La asignación usa solo los códigos del catálogo (`permiso_catalogo`, BR-A11..A22).
  - El alcance puede ser tenant o inmueble; sin asignación = denegación por defecto.
  - Los defaults por rol provienen de `rol_permiso_base` (BR-A10).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-022 — Crear y editar borrador

- **Descripción**: Como agente quiero crear y editar el borrador de una publicación.
- **Prioridad**: Alta · **Estimación**: 8 PHU
- **Criterios de Aceptación**:
  - Se crea el borrador con título y operación (venta/alquiler); estado `borrador`.
  - Los cambios se guardan sin alterar publicaciones existentes.
  - El borrador es visible solo para el tenant propietario (BR-C3).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-023 — Enviar a revisión

- **Descripción**: Como agente quiero enviar la publicación a revisión y conocer el resultado.
- **Prioridad**: Alta · **Estimación**: 4 PHU
- **Criterios de Aceptación**:
  - La transición `borrador`→`en_revision` registra actor y fecha.
  - Requiere permiso `prop.edit`/`prop.publish`; el agente no puede autoaprobar (BR-C2).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-024 — Aprobar o rechazar publicaciones

- **Descripción**: Como administrador quiero aprobar o rechazar publicaciones verificando el difuminado.
- **Prioridad**: Alta · **Estimación**: 4 PHU
- **Criterios de Aceptación**:
  - Aprueba → `publicado`; rechaza → `rechazado` con observaciones obligatorias (BR-034).
  - La revisión incluye verificación de redacción (RNF-008).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-025 — Publicar o despublicar

- **Descripción**: Como agente o administrador quiero publicar o despublicar un inmueble.
- **Prioridad**: Alta · **Estimación**: 4 PHU
- **Criterios de Aceptación**:
  - `publicado` aparece en el catálogo global; `despublicado` desaparece de inmediato.
  - La despublicación queda registrada en auditoría (y en SP-03 revoca accesos activos, BR-E6).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-026 — Consultar el catálogo global

- **Descripción**: Como cliente quiero consultar el catálogo global de inmuebles.
- **Prioridad**: Alta · **Estimación**: 4 PHU
- **Criterios de Aceptación**:
  - Solo se muestran publicaciones `publicado` (BR-C3).
  - La consulta nunca expone contenido interno del tenant ni acepta `tenant_id` del cliente como autorización (RF-021).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

### HU-028 — Guardar favoritos

- **Descripción**: Como cliente quiero guardar favoritos y ver su estado.
- **Prioridad**: Media · **Estimación**: 4 PHU
- **Criterios de Aceptación**:
  - Guardar y quitar favoritos; único por publicación (UNIQUE en `favorito`).
  - Si la publicación se despublica, el favorito queda `no_disponible` sin exponer contenido privado (BR-C7).
- **Desarrollador a cargo**: GAP-073 · **Prototipo**

## 1.10. Sprint Backlog (SP-01)

| SPRINT BACKLOG | | | |
| --- | --- | --- | --- |
| **Objetivo** | Base administrativa y comercial operativa (autenticación, suscripción, agentes, publicaciones y catálogo) | | |
| **Sprint** | 1 | **Tiempo programado** | 3 semanas |
| **Fecha inicio** | GAP-084 | **Fecha finalización** | GAP-084 |

| ID | TAREA | ESTIMACIÓN | RESPONSABLE | ESTADO | PLATAFORMA |
| --- | --- | --- | --- | --- | --- |
| PB-001 | Registro cliente | 4 HRS | GAP-073 | Pendiente | App cliente / Backend |
| PB-002 | Autenticación y sesión | 8 HRS | GAP-073 | Pendiente | Backend / Apps / Web |
| PB-004 | Alta de inmobiliaria | 8 HRS | GAP-073 | Pendiente | Web / Backend |
| PB-005 | Trial y suscripción | 8 HRS | GAP-073 | Pendiente | Web / Backend |
| PB-006 | Ciclo de suscripción | 16 HRS | GAP-073 | Pendiente | Web / Backend |
| PB-007 | Invitación y membrecías | 8 HRS | GAP-073 | Pendiente | Web / Backend |
| PB-008 | Permisos RBAC | 8 HRS | GAP-073 | Pendiente | Web / Backend |
| PB-028 | Editor de publicación | 8 HRS | GAP-073 | Pendiente | Web / Backend |
| PB-029 | Revisión y aprobación | 8 HRS | GAP-073 | Pendiente | Web / Backend |
| PB-030 | Publicación y catálogo | 8 HRS | GAP-073 | Pendiente | Backend / App / Web |
| PB-032 | Favoritos | 4 HRS | GAP-073 | Pendiente | Backend / App cliente |
| PB-048 | Entorno local (Docker + Floci) | 8 HRS | GAP-073 | Pendiente | DevOps / Backend |
| PB-049 | CI básica | 8 HRS | GAP-073 | Pendiente | DevOps |

> Estimación en horas (E); 1 PHU = 1 hora. Responsable y estado se completan en el Sprint Planning (GAP-072/073).

## 1.11. Próximos pasos

- Validar estimaciones, fichas HU y Sprint Backlog con el equipo (GAP-072/073: responsables por plataforma — ids §6.1).
- Criterios de aceptación de las 14 HU del Sprint 1 redactados (sección 1.9); validación final pendiente (GAP-070).
- Confirmar fechas de inicio/fin y Gantt (GAP-084).
