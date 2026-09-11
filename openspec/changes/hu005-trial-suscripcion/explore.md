# Exploración — Activar prueba y suscribirse mensualmente (HU-005)

- **Cambio:** `hu005-trial-suscripcion`
- **Product Backlog:** PB-005
- **Historia:** HU-005 — Activar la prueba de 14 días y suscribirme mensualmente para operar mi tenant.
- **Caso de prueba:** CP-004
- **Prioridad / sprint / plataforma:** Alta / Sprint 1 / Web y Backend.
- **Estimación documentada:** 8 PHU.
- **Propósito:** permitir que el administrador de un tenant aprovisionado active una única prueba de 14 días y posteriormente convierta la suscripción mediante un evento firmado del simulador, conservando estados, fechas e idempotencia verificables.
- **Estado de esta exploración:** no se modificó código de producto ni se ejecutaron pruebas o migraciones.

## 1. Fuentes y método

Se revisaron la planificación y el proceso de Sprint 1, la auditoría de reglas de negocio de Sprint 0, el contexto OpenSpec, los artefactos de HU-004 disponibles en el checkout y el módulo actual `backend/app/modules/tenant/` (`router.py`, `schemas.py`, `service.py`, `repository.py`, `models.py`). CodeGraph no estuvo disponible: no existe `.codegraph/` en la raíz y no se dispone de un comando/MCP ejecutable en esta sesión; por eso la exploración estructural se hizo mediante los documentos y referencias directas, seguida de búsquedas acotadas. Las afirmaciones de ejecución permanecen sin confirmar porque no se lanzaron comandos.

## 2. Contexto canónico y criterios observables

La planificación de Sprint 1 define HU-005 como: “Como administrador quiero activar la prueba de 14 días y suscribirme mensualmente, para operar mi tenant”. Sus criterios son:

1. El trial comienza al activarse y dura 14 días.
2. La suscripción mensual queda en estado `active` después del evento firmado del simulador.
3. Los estados transicionan en el orden definido para la suscripción.

CP-004 (`docs/scrum/sprint-1/02-proceso-por-hu.md`) establece como precondiciones un tenant aprovisionado, un plan disponible y un evento firmado preparado. Sus tres pasos son: activar el trial (`trialing` durante 14 días), enviar el evento firmado (`active`) y reprocesarlo sin duplicar estado ni registros. CP-004 figura como `not executed`; no debe presentarse como evidencia de comportamiento.

La auditoría `docs/sprint-0/auditoria-br.md` agrega estas reglas relevantes:

- **BR-B3:** prueba de 14 días y tres planes mensuales en BOB, con cuotas diferenciadas.
- **BR-B4:** estados `trialing`, `active`, `past_due`, `suspended`, `canceled_read_only` y `purged`, con gracia de cobro de 3 días.
- **BR-B5:** cambios de plan inmediatos o al renovar, sin prorrateo real.
- **BR-B6:** al alcanzar una cuota se conservan datos y se bloquean nuevas altas/subidas/reconstrucciones.
- **BR-B7/BR-B8:** cancelación de 30 días en modo solo lectura y posterior purga, reglas que pertenecen principalmente a HU-006.
- **BR-B1 y BR-A2:** checkout/evento simulado claramente separado de la autorización multi-tenant; nunca usar un `tenant_id` enviado por el cliente como autorización.

Los nombres, precios y cantidades de planes siguen registrados como `GAP-061`; esta exploración no inventa valores.

## 3. Estado actual verificado

### 3.1 Hechos observados

- `router.py` ya registra `POST /api/v1/tenant/activar-prueba` y `POST /api/v1/tenant/suscribir`, además de las rutas de HU-004 y HU-006.
- `ActivarPruebaRequest` solo contiene `tenant_id`.
- `SuscribirRequest` contiene `tenant_id`, `plan_id`, `payload_firmado` e `idempotency_key`; no declara `extra="forbid"` ni un contrato de evento firmado equivalente al webhook de HU-004.
- `Suscripcion` persiste `tenant_id`, `plan_id`, `estado`, `trial_fin`, `periodo_fin` y `cancelado_en`; no hay en el modelo un campo específico que indique el inicio del trial, el evento que lo activó o una versión de transición.
- `activar_prueba` busca una suscripción por `tenant_id`, rechaza solo si `trial_fin` no es nulo, fija `estado = "trialing"`, calcula `trial_fin = ahora + timedelta(days=14)` y guarda la entidad.
- `suscribirse` hace primero un `evento_procesado` por `idempotency_key`; luego busca la suscripción, fija `estado = "active"`, reemplaza `plan_id` con el enviado por el cliente, calcula `periodo_fin = ahora + timedelta(days=30)`, registra un `EventoFacturacion` con el `payload_firmado` recibido y finalmente guarda la suscripción.
- El repositorio implementa `buscar_suscripcion`, `guardar_suscripcion`, `evento_procesado` y `registrar_evento_facturacion` como operaciones separadas. La persistencia de suscripción y evento no está encapsulada en una transacción de HU-005.
- `EventoFacturacion` sí tiene unicidad de `idempotency_key`, pero la ruta de HU-005 no usa el verificador HMAC que `TenantService.procesar_webhook` usa para HU-004. Tampoco se observó validación de correlación entre evento, tenant, plan y monto.
- La ruta de HU-005 convierte `ValueError` en `400` y `EventoDuplicadoError` en `409`; no se observó una política diferenciada para evento ausente, firma inválida, payload alterado, conflicto de clave o actor no autorizado.
- HU-004, según sus artefactos, deja una suscripción inicial en `active` y no activa el trial. También deja disponible una frontera de webhook autenticado e idempotente para onboarding; reutilizarla o crear una variante para cobro mensual requiere decisión de diseño, no se debe asumir equivalencia.

### 3.2 Inferencias y gaps derivados

- El cálculo de 14 días existe, pero no demuestra que el inicio del trial quede persistido ni que el trial solo pueda activarse desde un estado válido. `GAP-005-DATE-001`: definir/confirmar el dato de inicio y la semántica exacta del límite de 14 días.
- El guardado separado y el check-then-insert permiten carreras y efectos parciales. `GAP-005-IDEM-001`: definir idempotencia atómica, resultado del reintento idéntico y conflicto de la misma clave con payload diferente.
- El request de suscripción acepta datos de autoridad del cliente (`plan_id` y payload opaco) sin evidencia de fuente server-owned. `GAP-005-SERVER-001`: el evento debe correlacionarse con la suscripción/plan vigente y validar sus datos contra el servidor.
- El endpoint usa `tenant_id` del body y no muestra dependencia de identidad autenticada. `GAP-005-AUTH-001`: definir cómo se identifica al administrador y cómo se impone el límite tenant; no basta con confiar en el UUID recibido.
- `periodo_fin` calculado como 30 días es comportamiento actual, pero el requisito canónico solo exige suscripción mensual; la duración de calendario, fecha de renovación y relación con `trial_fin` deben ser decisión de producto, no una constante asumida.
- La tabla de estados del Sprint 1 documenta estados posteriores a HU-005, pero no especifica todas las transiciones, eventos permitidos ni el comportamiento de activación repetida o suscripción antes/después del trial. `GAP-005-STATE-001` debe cerrarse antes de tareas.
- No se encontraron en la evidencia revisada pruebas específicas de CP-004. El estado real de la suite no fue ejecutado en esta fase.

## 4. Slice mínimo coherente recomendado

El slice mínimo backend/API, consumible por Web y limitado a CP-004, debería incluir:

1. Activación autenticada y tenant-scoped de una prueba única: localizar la suscripción perteneciente al actor administrador, comprobar estado/precondiciones, registrar el instante de inicio y fijar fin exactamente 14 días después usando reloj inyectable.
2. Conversión a mensual mediante un evento del simulador con contrato cerrado, firma autenticada, correlación server-owned y transición válida a `active`.
3. Persistencia atómica de la transición y del evento de facturación, con unicidad/idempotencia persistente y recuperación del resultado original ante reintento exacto.
4. Máquina de estados mínima para HU-005: por lo menos `active` inicial de HU-004 → `trialing` → `active`, con rechazo explícito de transiciones inválidas y sin adelantar `past_due`, suspensión, cancelación o purga.
5. Respuestas API que expongan estado y fechas necesarias, sin payload firmado crudo, secretos ni datos de otro tenant.
6. Pruebas de contrato, servicio, concurrencia/idempotencia y regresión de las rutas de HU-004/HU-006 sin ampliar esas historias.

La UI Web puede consumir el contrato, pero no hay evidencia suficiente para fijar pantalla, navegación o copy. No se recomienda incluir React, Flutter ni pagos reales en este cambio.

## 5. Superficies afectadas y dependencias

| Superficie | Relación con HU-005 | Riesgo / límite |
| --- | --- | --- |
| `tenant/router.py` | Endpoints de activar trial y suscripción; mapeo de errores y dependencias | Debe permanecer delgado y aplicar identidad/tenant scope; no poner SQL ni reglas allí. |
| `tenant/schemas.py` | Requests/responses de activación y evento | Cerrar campos, tipos, extras prohibidos y ausencia de secretos. |
| `tenant/service.py` | Casos de uso, reloj, máquina de estados y validación | Sustituir lógica opaca por reglas verificables, sin modificar HU-006 salvo dependencias compartidas mínimas. |
| `tenant/repository.py` | Locks, transacción, eventos y consultas tenant-scoped | Evitar check-then-insert aislado; definir recuperación ante unicidad. |
| `tenant/models.py` / Alembic | Fechas, estados, unicidades y posible metadata de evento | Revisar compatibilidad con datos creados por HU-004 y migración existente. |
| `identity` / autorización | Actor administrador y pertenencia al tenant | HU-004 dejó pendiente la relación formal admin–tenant/membresía; decisión crítica antes de implementar. |
| Panel Web | Consumidor futuro de estados y fechas | Solo contrato; no implementar UI sin alcance aprobado. |

**Dependencia HU-004:** el tenant y la suscripción deben existir y el estado inicial de la suscripción debe ser conocido. HU-004 documenta suscripción inicial `active`, por lo que activar el trial debe ser una transición posterior y no parte del onboarding. La frontera de webhook, el secreto y el esquema de eventos pueden reutilizarse solo si el diseño confirma que sus semánticas y autorizaciones son compatibles.

**Dependencia HU-006:** HU-005 debe dejar estados y fechas que HU-006 pueda consultar y gestionar. No incluir cuotas operativas, upgrade/downgrade, cancelación, gracia de cobro, solo lectura ni purga salvo contratos mínimos imprescindibles para no romper la máquina de estados. HU-006 debe consumir una representación estable, no corregir retrospectivamente datos de HU-005.

## 6. Seguridad y límites de tenant

- La activación y consulta deben requerir una identidad de administrador y comprobar membresía/rol activo, o documentar explícitamente un seam de demo aislado si producto decide no usar JWT en este slice.
- `tenant_id` del cliente no es una autorización. La consulta de suscripción debe derivar el tenant autorizado de la identidad/contexto, o verificarlo contra una relación persistida segura.
- El evento mensual debe autenticarse como evento del simulador, con firma sobre bytes recibidos y protección contra replay; no debe confiar en un `payload_firmado` declarado por el cliente como texto libre.
- Plan, monto, tenant y periodo deben ser server-owned o verificarse contra la suscripción/checkout existente. No aceptar un `plan_id` que permita cambiar de plan como efecto lateral de HU-005.
- No registrar ni devolver secretos, firma completa, payload sensible o tokens. Los errores deben distinguir lo necesario sin revelar existencia de otros tenants.
- La transición debe ser atómica y resistente a reintentos concurrentes; una falla no debe dejar estado `active` sin evento o evento procesado con suscripción sin actualizar.

## 7. Datos, migración y riesgos

- La migración `0003_crear_tablas_tenant.py` ya contiene `suscripcion` y sus fechas, pero no prueba que el esquema actual soporte todas las invariantes de HU-005.
- Debe revisarse unicidad de una suscripción vigente por tenant, restricciones de estados y cualquier columna adicional para inicio del trial, renovación o referencia del evento. No agregar columnas hasta cerrar el contrato.
- Debe preservarse la compatibilidad con suscripciones creadas por HU-004 (`active`, fechas nulas). Una migración aditiva es preferible; un downgrade sobre datos reales no debe ser destructivo.
- Los eventos existentes de HU-004 pueden compartir tabla y clave de idempotencia con eventos mensuales. Se necesita separar tipos, correlación y replay para no interpretar un evento de onboarding como pago mensual.
- Riesgo alto: el estado actual usa `Mapped[str]` y cadenas abiertas; un `CHECK`, enum o catálogo debe coordinarse con HU-006 y datos existentes.
- Riesgo alto: PostgreSQL/Alembic y la suite no se ejecutaron en esta exploración; cualquier resultado operacional queda pendiente para verify.

## 8. Seams y plan de evidencia para la siguiente fase

Se recomienda conservar el patrón `router → service → repository`, reloj inyectable y dobles de repositorio. Los seams mínimos son:

- `FakeClock` para inicio, fin exacto de 14 días, renovación y límites.
- Repositorio fake para suscripción, evento, locks simulados, rollback y recuperación de replay.
- Verificador de firma del simulador inyectable, con casos de firma válida, ausente, inválida, cuerpo alterado y replay.
- Contexto de identidad/política de acceso inyectable para administrador autorizado, otro tenant, rol insuficiente y tenant inexistente.
- Pruebas de contrato/TestClient para códigos y cuerpos sin secretos.

CP-004 debe cubrir activación, fecha de fin, conversión firmada, transición inválida, reintento exacto, misma clave con payload distinto, evento no autenticado, falla transaccional y aislamiento de tenant. Debe distinguirse evidencia fake de PostgreSQL real. El comando de calidad documentado es `.venv/Scripts/python.exe -m pytest backend/tests -q`, acompañado por ruff, pyright y Alembic durante apply/verify; no se afirma ningún resultado aquí.

## 9. No objetivos explícitos

- No implementar pagos reales, proveedor externo, facturación productiva ni cobro real.
- No implementar UI Web/Flutter, navegación, copy ni notificaciones productivas.
- No implementar el ciclo completo de HU-006: consulta de cuotas/uso, upgrade/downgrade, `past_due`, suspensión, cancelación, solo lectura, purga o anonimización.
- No implementar invitaciones/membresías/RBAC completos de HU-007–HU-009 ni resolver por adelantado todo el modelo de identidad global.
- No modificar `docs/diagramas/Diagrama1.eapx`.
- No refactorizar el módulo tenant fuera de lo necesario para la frontera compartida y la regresión.
- No afirmar que CP-003, CP-004 o migraciones están ejecutados sin evidencia nueva.

## 10. Decisiones que la propuesta debe preguntar al Product Owner

1. **Autorización:** ¿HU-005 requiere JWT y una membresía/rol administrador ya persistido, o se autoriza un modo demo explícitamente acotado? Si la identidad formal del admin depende de HU-007, ¿cuál es el vínculo mínimo aceptable?
2. **Inicio y calendario:** ¿debe persistirse `trial_inicio` además de `trial_fin`? ¿“14 días” significa exactamente 14×24 horas desde activación y qué ocurre en el instante límite?
3. **Conversión:** ¿el evento firmado convierte solo una suscripción `trialing`, o también permite suscripción directa desde el estado inicial `active` de HU-004? ¿Qué pasa si llega antes, después o sin trial vigente?
4. **Mensualidad:** ¿la renovación es 30 días o fecha calendario mensual? ¿`periodo_fin` comienza al confirmar el evento o al terminar el trial? No asumir la constante actual de 30 días como decisión de producto.
5. **Evento e idempotencia:** ¿se reutiliza el contrato HMAC/webhook de HU-004 para el simulador mensual? ¿Qué campos server-owned contiene y cuál es la respuesta exacta para replay y conflicto de clave?
6. **Planes y precio:** ¿la suscripción mensual conserva el plan de HU-004 sin cambio de plan, y dónde se fija el catálogo/precio aprobado para validar el evento? `GAP-061` permanece abierto.
7. **Notificación y observabilidad:** ¿se necesita una notificación simulada al activarse o convertirse, o basta la respuesta API y el registro de evento?

## 11. Mapa de fuentes y recomendación

- `docs/scrum/sprint-1/01-sprint-planning.md` §HU-005: historia, prioridad, estimación y criterios.
- `docs/scrum/sprint-1/02-proceso-por-hu.md` §CP-004: precondiciones, pasos y estado `not executed`.
- `docs/sprint-0/auditoria-br.md` §B: reglas BR-B1–BR-B9 y gaps de planes.
- `openspec/project-context.md`: stack, TDD estricto, idioma, modo híbrido, comandos y restricciones heredadas.
- `openspec/changes/hu004-alta-inmobiliaria/{explore,proposal,specs/tenant-onboarding/spec,design,tasks}.md`: dependencias, frontera de webhook, estado inicial `active`, convenciones y límites de HU-004.
- `backend/app/modules/tenant/{router,schemas,service,repository,models}.py`: comportamiento actual verificado.
- `backend/alembic/versions/0003_crear_tablas_tenant.py`: esquema inicial de suscripción y eventos.

**Recomendación:** avanzar a `proposal` en modo interactivo, pero tratar `GAP-005-AUTH-001`, `GAP-005-STATE-001`, `GAP-005-IDEM-001` y la decisión de calendario/evento como bloqueantes de diseño. El primer slice debe ser backend/API, con contrato de evento firmado y pruebas CP-004; la UI y el ciclo HU-006 quedan explícitamente fuera.
