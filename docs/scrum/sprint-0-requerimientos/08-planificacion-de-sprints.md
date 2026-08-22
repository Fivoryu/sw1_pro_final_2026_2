# Sprint 0 — Planificación de Sprints

| Campo | Valor |
| --- | --- |
| Módulo | S0-08 — CAPITULO 1, apartado 8 |
| Estado | done (estructura replicada del modelo: una fila por PB; fechas → GAP-084) |
| IDs | SP-01 · SP-02 · SP-03; PB-001..049; HU-001..040 |
| Referencia del modelo | Grupo#12 — Capítulo 1, sección 8 (páginas impresas 121–130; extracción `docs/modelo_doc/extracto-sprints-p85-150.txt`) |
| Fuentes | `docs/sprint-0/ids-trazabilidad.md` §6–10 |

La planificación de Sprints organiza el desarrollo en incrementos funcionales, con avance progresivo y coherente con la prioridad del Product Backlog. Se definen **tres Sprints principales**, además del Sprint 0 utilizado para la planificación, preparación del entorno, definición inicial del producto, organización documental y diseño preliminar de la solución.

Cada Sprint concentra un bloque funcional sin mezclar funcionalidades base con módulos avanzados: primero las fundaciones (identidad, suscripción, publicaciones); luego el núcleo 3D y comercial (captura, reconstrucción, precios, reservas); finalmente el cierre (correo real, acceso temporal, notificaciones, exportación y despliegue). La distribución toma como base los **49 elementos del Product Backlog**: el Sprint 1 agrupa **13 elementos**, el Sprint 2 concentra **22 elementos** y el Sprint 3 agrupa **14 elementos**, manteniendo entrega progresiva, verificable y alineada con las dependencias funcionales.

## 8.1. Duración de los Sprints

Cada Sprint tendrá una duración aproximada de **21 días calendario**, siguiendo un ciclo de planificación, desarrollo, revisión y retrospectiva. El Sprint 0 es la fase inicial de preparación (definición documental, técnica y organizativa) con duración propia no fijada aún.

| NRO. | SPRINT | FECHA DE INICIO | FECHA DE FINALIZACIÓN | DURACIÓN | PROPÓSITO PRINCIPAL |
| --- | --- | --- | --- | --- | --- |
| 1 | Sprint 0 | GAP-084 | GAP-084 | GAP-084 | Planificación, definición del producto, arquitectura inicial y preparación del entorno |
| 2 | Sprint 1 | GAP-084 | GAP-084 | 21 días (propuesta) | Base administrativa y comercial: identidad, suscripción, agentes, publicaciones |
| 3 | Sprint 2 | GAP-084 | GAP-084 | 21 días (propuesta) | Núcleo 3D y comercial: captura, reconstrucción, precios, reservas |
| 4 | Sprint 3 | GAP-084 | GAP-084 | 21 días (propuesta) | Cierre: correo real, acceso temporal, notificaciones, exportación y despliegue AWS |

**Diagrama de Gantt general de los Sprints**: pendiente de fechas reales (GAP-084); se incorporará al fijar el calendario con el equipo.

## 8.2. Criterios para la división de Sprints

La división no se realizó únicamente por cantidad de ítems, sino por **dependencia funcional, prioridad, complejidad técnica, equilibrio de carga, valor incremental y trazabilidad**, para que cada Sprint entregue un incremento coherente, verificable y útil.

| CRITERIO | APLICACIÓN EN EL PROYECTO |
| --- | --- |
| Dependencia funcional | Primero identidad/tenancy/publicaciones (SP-01); luego la cadena 3D completa (captura → jobs → worker → artefactos → composición) y precios→reservas (SP-02); finalmente acceso temporal, correo real, notificaciones, exportación y AWS (SP-03). |
| Prioridad de negocio | Se priorizan las funciones necesarias para operar: autenticación, suscripción, agentes, publicaciones y catálogo; los Media (favoritos, notificaciones, exportación) quedan al final. |
| Complejidad técnica | Los ítems de complejidad A (worker Meshroom PB-017, composición PB-022, motor de precios PB-037) se ubican en SP-02 y se dividen en TASKs; escrow (PB-041), versionado (PB-031) y despliegue (PB-047) cierran en SP-03. |
| Equilibrio de carga | Los 49 elementos del Product Backlog se distribuyen en tres Sprints: **13 en Sprint 1, 22 en Sprint 2 y 14 en Sprint 3**. |
| Valor incremental | Cada Sprint entrega una parte funcional revisable y testeable: catálogo navegable con publicaciones (SP-01) → recorrido 3D con reservas (SP-02) → demo SaaS completa con despliegue (SP-03). |
| Trazabilidad | Cada PB mantiene relación con HU, CU, RF y entregables del Sprint correspondiente (matriz en ids-trazabilidad). |

## 8.3. Sprint 1 — Base administrativa y comercial

**Objetivo**: implementar la base administrativa y comercial del sistema, incluyendo identidad y autenticación, onboarding SaaS con suscripción simulada, gestión de agentes y permisos, publicaciones con aprobación, catálogo global, favoritos y el entorno local reproducible con CI.

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
| PB-048 | Entorno local | Alta | Cada integrante levanta el entorno Docker Compose + Floci. |
| PB-049 | CI básica | Alta | Los tests y el smoke test corren en cada merge. |

**Entregable principal del Sprint 1**: incremento funcional con autenticación, onboarding SaaS, administración de agentes, publicaciones con aprobación y catálogo global consultable.

## 8.4. Sprint 2 — Núcleo 3D y comercial

**Objetivo**: implementar el núcleo del producto: captura guiada con difuminado, pipeline de reconstrucción asíncrona (jobs, worker Meshroom, artefactos GLB y plano 2D), composición espacial, recorrido 3D web, medidas con confianza, motor de precios y reservas con escrow.

| PB | HISTORIA DE USUARIO | PRIORIDAD | RESULTADO ESPERADO |
| --- | --- | --- | --- |
| PB-009 | Guía de captura | Alta | La app guía al agente en la captura de video + fotos por ambiente. |
| PB-010 | Subida de capturas | Alta | El agente sube capturas con progreso y reanudación. |
| PB-011 | Validación de calidad | Alta | El sistema valida cantidad/resolución/cobertura y el agente recaptura selectivamente. |
| PB-012 | Difuminado automático | Alta | El sistema reduce rostros y texto en las capturas antes de subir. |
| PB-013 | Solicitud de reconstrucción | Alta | El job se persiste y encola para reconstrucción asíncrona. |
| PB-014 | Estados de job | Alta | El agente sigue los estados pending/running/done/failed/delayed y reintenta fallos. |
| PB-015 | Cola SQS | Alta | El sistema aplica visibility timeout y tolera reentregas. |
| PB-016 | Worker: heartbeat | Alta | El worker reporta vida e idempotencia. |
| PB-017 | Worker: Meshroom | Alta | El worker ejecuta el pipeline de reconstrucción en la GPU. |
| PB-018 | GLB optimizado | Alta | El sistema genera el modelo GLB navegable por ambiente. |
| PB-019 | Nubes y texturas | Alta | El sistema almacena nubes de puntos y texturas en S3. |
| PB-020 | Plano 2D | Alta | El sistema deriva el plano 2D básico de la reconstrucción. |
| PB-021 | Preview y aprobación | Alta | El agente/administrador revisa el preview (3D + plano) y aprueba o rechaza la reconstrucción. |
| PB-022 | Composición espacial | Alta | El agente ensambla ambientes y conecta puertas en el editor 2D. |
| PB-023 | Recorrido 3D web | Alta | El agente/administrador recorre el inmueble en 3D desde el panel web. |
| PB-025 | Medidas con confianza | Alta | El cliente ve las medidas estimadas/calibradas con confianza visible. |
| PB-035 | Catálogo maestro | Alta | El administrador mantiene el catálogo maestro de elementos y reglas. |
| PB-036 | Configuración de elementos | Alta | El agente configura elementos (obligatorios/incluidos/opcionales) por publicación. |
| PB-037 | Motor de precios | Alta | El sistema calcula el precio con desglose y el depósito por operación. |
| PB-038 | Ajustes por publicación | Alta | El agente/administrador aplica ajustes de precio por elemento en cada publicación. |
| PB-039 | Simulación de precio | Alta | El cliente simula el precio con la configuración. |
| PB-040 | Reserva congelada | Alta | El cliente reserva con precio fijo congelado y depósito de prueba. |

**Entregable principal del Sprint 2**: incremento funcional con reconstrucción 3D por ambiente, recorrido navegable, precios configurables y reservas con escrow de token de prueba.

## 8.5. Sprint 3 — Cierre, acceso y despliegue

**Objetivo**: integrar las funciones avanzadas y cerrar la entrega: verificación de correo real, acceso temporal al detalle, recorrido 3D en app, plano 2D para cliente, versionado comercial, escrow completo, notificaciones, exportación, auditoría y despliegue en AWS días antes de la presentación.

| PB | HISTORIA DE USUARIO | PRIORIDAD | RESULTADO ESPERADO |
| --- | --- | --- | --- |
| PB-003 | Verificación de correo real | Alta | El cliente verifica su correo real con un enlace de activación (reemplaza el modo pruebas). |
| PB-024 | Recorrido 3D app | Alta | El cliente recorre el inmueble en 3D desde la app móvil. |
| PB-026 | Plano 2D cliente | Alta | El cliente consulta el plano 2D del inmueble con acceso aprobado. |
| PB-027 | Configuración visual | Media | La publicación usa catálogo low-poly acotado con fallback genérico. |
| PB-031 | Versionado | Alta | Los cambios comerciales se versionan sin alterar lo publicado. |
| PB-033 | Solicitud de acceso | Alta | El cliente solicita acceso al contenido detallado del inmueble. |
| PB-034 | Aprobación/revocación | Alta | El agente/administrador aprueba o revoca accesos temporales con vigencia de 7 días y auditoría. |
| PB-041 | Escrow de prueba | Alta | El contrato registra y valida los movimientos del token de prueba (listener + reconciliación). |
| PB-042 | Aceptación atómica | Alta | Se acepta una reserva y se rechazan/reembolsan las competidoras sin carreras. |
| PB-043 | Expiración de reserva | Alta | La vigencia congelada expira con reembolso idempotente. |
| PB-044 | Notificaciones | Media | Los usuarios reciben notificaciones in-app, push y correo con auditoría. |
| PB-045 | Exportación | Media | El personal autorizado exporta plano 2D y GLB con URLs firmadas. |
| PB-046 | Auditoría y retención | Alta | Se registran las acciones y se aplica retención/anonimización. |
| PB-047 | Infraestructura AWS | Alta | Frontend, backend y base de datos se despliegan en AWS (ECS Express). |

**Entregable principal del Sprint 3**: SaaS completo desplegado — identidad verificada, acceso temporal seguro, recorridos 3D en móvil y web, reservas con escrow y panel de administración operativo — listo para la presentación.

## Definition of Done (extensión del equipo, DoD por HU)

- Criterios de aceptación de la HU cumplidos (GAP-070) y BR vinculadas verificadas.
- Pruebas de caja negra ejecutadas con evidencia (TC-###) o `not executed` explícito.
- Código en el repositorio con commit convencional y CI en verde.
- Documentación del sprint actualizada (diseño/implementación/pruebas).
- Sin defectos funcionales para publicar (BR-040).

## Gaps de la planificación

| GAP | Descripción |
| --- | --- |
| GAP-084 | Fechas de inicio/fin y Gantt: se fijan con el equipo antes del Sprint Planning de SP-01 |
| GAP-072 | Repartición confirmada 13/22/14; SP-01 estimado ≈ 107 h (módulo S1-01) — validación del equipo y horas de SP-02/03 pendientes |
| GAP-073 | Responsables por PB/HU considerando plataforma (ids §6.1) |
