# Exploración — Alta de inmobiliaria (HU-004)

- **Cambio:** `hu004-alta-inmobiliaria`
- **Product Backlog:** PB-004
- **Historia:** HU-004 — Alta de inmobiliaria
- **Caso de prueba relacionado:** CP-003
- **Slice recomendado:** backend-first, con contrato consumible por el panel Web; no se implementa UI en esta fase.
- **Idioma del artefacto:** español profesional y neutral.
- **Estado:** exploración completada; no se modificó código de producto.

## 1. Evidencia y contexto

El contexto de OpenSpec confirma un monorepo con backend FastAPI, SQLAlchemy 2.x, PostgreSQL y Alembic; el backend activo está en la rama `feature/tenant-hu04-06`, commit `7429193`. El cambio tiene límite de 600 líneas modificadas y excluye explícitamente HU-005 y HU-006.

La ficha de HU-004 en `docs/scrum/sprint-1/01-sprint-planning.md` define prioridad Alta, estimación 8 PHU y cuatro criterios: checkout simulado con plan/monto en BOB/confirmación; aprovisionamiento solo después de verificar evento firmado; reprocesamiento sin duplicar tenant; y enlace de un solo uso para el primer administrador. CP-003 en `02-proceso-por-hu.md` repite esos cuatro escenarios y permanece `not executed`.

Las reglas de negocio auditadas (`docs/sprint-0/auditoria-br.md`) agregan que el checkout debe ser claramente simulado (BR-B1), nunca se envían contraseñas y el primer administrador establece la suya mediante enlace de un solo uso (BR-B2), existen tres planes con cuotas diferenciadas (BR-B3), y los nombres, precios y cuotas concretos siguen abiertos en GAP-061 (BR-B9).

## 2. Estado actual del backend

Existe ya un módulo `backend/app/modules/tenant/` registrado en `backend/app/main.py` bajo `/api/v1`:

- `router.py` expone `POST /api/v1/tenant/alta` con `AltaTenantRequest`/`AltaTenantResponse`.
- `schemas.py` recibe `nombre_empresa`, `correo_admin`, `plan_id`, `payload_firmado` e `idempotency_key`.
- `service.py` busca el plan, crea `Tenant`, `Invitacion`, `Suscripcion` y `EventoFacturacion`, y calcula un hash SHA-256 del token de invitación.
- `repository.py` persiste las cuatro entidades en una transacción y tiene una restricción única para `idempotency_key`.
- `models.py` representa `tenant`, `invitacion`, `plan`, `suscripcion` y `evento_facturacion`.
- `alembic/versions/0003_crear_tablas_tenant.py` crea esas cinco tablas después de `0002`.

La implementación encontrada también contiene endpoints y lógica de HU-005 y HU-006 (`/activar-prueba`, `/suscribir`, `/cambiar-plan`, `/cancelar`, `/ejecutar-purga`). Eso es evidencia de código existente, no una autorización para incluirlos en este cambio. Deben permanecer fuera de la especificación y de las tareas de HU-004.

No hay `backend/tests/test_tenant.py` en el checkout; la búsqueda no encontró pruebas de tenant, checkout o idempotencia para CP-003. Por tanto, la cobertura actual de HU-004 no está demostrada.

## 3. Slice mínimo completo recomendado

El slice mínimo que satisface HU-004 es un flujo backend de onboarding compuesto por:

1. **Checkout simulado para Web:** contrato para seleccionar un plan y confirmar una operación local, mostrando nombre, monto BOB y confirmación. El formato exacto de pantalla, ruta del panel, copy y navegación son GAP-004-UI-001; no deben inventarse en la propuesta.
2. **Recepción/procesamiento del evento:** una frontera backend que acepte el evento del simulador, verifique su firma y solo entonces habilite la provisión. La ruta HTTP, headers, algoritmo y formato de firma no están definidos en la documentación ni en el código actual: GAP-004-API-001.
3. **Aprovisionamiento atómico:** crear tenant, suscripción inicial, registro del evento y la invitación del primer administrador en una única transacción. La invitación debe contener únicamente un token no reversible/hasheado, expiración y estado pendiente; nunca una contraseña.
4. **Respuesta consumible por Web:** devolver el identificador/estado del tenant y una confirmación sin exponer el token crudo, payload sensible ni secretos. El mecanismo real de entrega del enlace (correo, bandeja o respuesta de demo) no está definido: GAP-004-NOTIF-001.
5. **Pruebas de CP-003:** cubrir los cuatro pasos de la prueba de caja negra, además de carrera/reintento para demostrar la invariancia de idempotencia.

El alta debe ser backend-first, siguiendo el patrón de los cambios archivados: router delgado, service para el caso de uso, repository para SQL/transacciones, modelos para persistencia y tests con fakes/TestClient. La futura UI Web consume el contrato; no se incorpora Flutter ni una UI dentro de este slice.

## 4. Contratos y límites de integración

### Backend/API

La ruta existente `POST /api/v1/tenant/alta` puede ser un punto de partida, pero su contrato actual mezcla datos de checkout y un supuesto evento ya firmado en el mismo request. Debe decidirse en proposal/spec si se conserva como endpoint de demo o se separan `checkout` y `webhook/evento`. No asumir una ruta nueva sin cerrar esa decisión.

El servicio debe reutilizar los contratos transversales existentes: `ClockProtocol` para expiraciones y `usuario_global`/`identity` para la cuenta global. Sin embargo, `Tenant` no tiene FK a `usuario_global`, e `Invitacion` solo guarda correo; por lo tanto, el vínculo formal entre primer administrador, cuenta global y membresía no existe todavía. La regla BR-B2 exige el enlace de activación, pero la creación/aceptación de membresía pertenece a HU-007 y no debe adelantarse. GAP-004-DOM-001: definir si HU-004 crea una invitación pendiente sin membresía, o si necesita una mínima relación administrativa que quede explícitamente acotada.

### Panel Web

El panel necesita al menos seleccionar un `Plan`, presentar `nombre` y `precio_bob`, confirmar el checkout simulado y mostrar el resultado del alta. La implementación React/TypeScript no fue necesaria para esta exploración y no se debe inferir un componente, ruta de navegación o contrato de estado. La integración debe esperar el contrato API cerrado.

### Identidad/autenticación

`identity` ya ofrece registro, login, JWT access con `sid`, refresh hasheado y `GET /api/v1/auth/me`. Es una base reutilizable, pero el usuario que inicia el alta y el receptor del evento son actores distintos y no deben confundirse. El router tenant actual no exige autenticación. GAP-004-AUTH-001: definir si el checkout de alta es público/simulador o requiere una cuenta autenticada; si requiere autorización de tenant/admin, ese modelo no existe aún en el checkout inicial.

## 5. Invariantes de seguridad e idempotencia

- Nunca aprovisionar por una confirmación de checkout sin evento firmado válido (BR-B1/HU-004 CA2).
- Verificar autenticidad e integridad del evento antes de cambiar estado o persistir efectos. El código actual almacena `payload_firmado`, pero no contiene un verificador de firma observable; esto es un riesgo crítico de cumplimiento.
- No aceptar contraseñas en el alta ni enviarlas; el enlace del primer administrador debe ser de un solo uso, expirable y persistido como hash.
- No devolver ni registrar el token crudo de invitación, secretos de firma ni datos sensibles del payload.
- La clave del evento debe tener unicidad persistida y el efecto tenant/invitación/suscripción/evento debe ser atómico.
- Un reintento concurrente del mismo evento debe producir como máximo un aprovisionamiento. El patrón actual `evento_procesado()` seguido de insert tiene una carrera TOCTOU; la restricción única evita duplicación de filas, pero el contrato de respuesta para el segundo intento y la recuperación del recurso original aún no están definidos.
- La misma `idempotency_key` con payload o plan distinto debe rechazarse, no reutilizarse silenciosamente. GAP-004-IDEM-001: definir código/mensaje y si se compara un hash canónico del evento.
- Validar que el evento corresponde al plan/checkout solicitado y que el plan está activo. Los nombres, precios y cuotas concretos siguen bajo GAP-061.
- Mantener aislamiento multi-tenant futuro; no autorizar por un `tenant_id` enviado por el cliente. La autorización completa, roles y membresías quedan fuera de HU-004 salvo la decisión mínima sobre el primer administrador.

## 6. Migración y datos

La revisión `0003_crear_tablas_tenant.py` ya declara `plan`, `tenant`, `invitacion`, `suscripcion` y `evento_facturacion`, con FK y unicidad de `token_unico`/`idempotency_key`. La migración no incluye datos semilla de planes, aunque CP-003 requiere un plan disponible. GAP-004-DATA-001: decidir si los tres planes se cargan mediante migración/seed de demo o fixture de pruebas; no inventar precios ni cuotas.

También deben revisarse antes de implementar:

- `Numeric(10,2)`/`Mapped[float]` para importes BOB: evitar pérdida de precisión en el contrato y decidir representación JSON.
- defaults y nulabilidad alineados entre modelo y migración (`Plan.activo`, UUID y fechas).
- downgrade seguro y orden de eliminación de FKs.
- ejecución real de Alembic: el contexto registra GAP-092 sobre migraciones pendientes/entorno PostgreSQL; no se debe declarar integración real sin ejecutarla.
- posible necesidad de constraints para un único onboarding por evento y consistencia entre `evento_facturacion.suscripcion_id` y el payload firmado.

## 7. Seams de prueba

Se pueden seguir los seams de los cambios archivados (`registro-cliente` y `autenticacion`): `TenantService` con `FakeTenantRepository` y `FakeClock`, router con dependency overrides y pruebas de validación sin PostgreSQL. La suite debe incluir:

- checkout: plan, monto BOB y confirmación;
- firma válida aprovisiona; firma ausente, inválida o alterada no aprovisiona;
- atomicidad: no quedan entidades parciales si falla una inserción;
- repetición secuencial y concurrente del evento;
- misma clave con payload diferente;
- token de invitación hasheado, expiración, estado pendiente y no exposición;
- plan inexistente/inactivo y payload inconsistente;
- regresión: ninguna ruta/lógica de HU-005/HU-006 se modifica como parte de este cambio.

La ejecución declarada por el proyecto es `.venv/Scripts/python.exe -m pytest backend/tests -q`, con ruff, pyright y Alembic como gates posteriores. No se ejecutaron comandos en esta exploración.

## 8. No objetivos explícitos

Quedan fuera: HU-005 (activar trial y suscripción mensual), HU-006 (cambios de plan, cancelación, cuotas, purga), membresías y RBAC completos, invitación/aceptación de agentes de HU-007, verificación real de correo, UI Flutter, integración de pagos reales, S3/SQS/worker 3D, catálogo, publicaciones, notificaciones productivas y auditoría completa. La existencia de código de HU-005/HU-006 en la rama no cambia estos límites.

## 9. Riesgos y decisiones para la propuesta

| ID | Riesgo o decisión pendiente | Impacto | Próxima acción |
| --- | --- | --- | --- |
| GAP-004-API-001 | No existe contrato verificable de firma, algoritmo, header ni ruta del evento. | Crítico: no se puede garantizar CA2. | Cerrar contrato del simulador antes de tasks. |
| GAP-004-IDEM-001 | El check-then-insert actual tiene carrera y no define respuesta de reintento/conflicto de payload. | Alto: duplicados o respuestas ambiguas. | Diseñar idempotencia transaccional y prueba concurrente. |
| GAP-004-DOM-001 | No existe relación tenant–`usuario_global`/membresía para el primer administrador. | Alto: CA4 puede quedar solo en un correo, sin onboarding utilizable. | Decidir límite exacto frente a HU-007. |
| GAP-004-DATA-001 / GAP-061 | No hay planes semilla ni valores aprobados de nombre/precio/cuotas. | Alto: checkout no es reproducible. | Confirmar datos de demo y estrategia de seed. |
| GAP-004-NOTIF-001 | No está definido cómo se entrega el enlace ni qué devuelve la API. | Medio/alto: CA4 no es observable de extremo a extremo. | Definir adaptador simulado y contrato sin filtrar token. |
| GAP-004-AUTH-001 | No está decidido si el checkout es público o autenticado. | Medio: afecta middleware y actor. | Resolver con producto en proposal. |
| GAP-004-UI-001 | No hay contrato visual/navegación Web verificable. | Medio: riesgo de alcance y >600 líneas. | Mantener Web como consumidor y acotar una sola pantalla/flujo. |
| GAP-092 | Migraciones y PostgreSQL real no están plenamente verificadas. | Medio/alto: riesgo de despliegue. | Ejecutar upgrade/downgrade en entorno disponible durante verify. |

## 10. Mapa de fuentes

- `openspec/project-context.md`, `openspec/config.yaml`: stack, límites, idioma, modo TDD, store híbrido y presupuesto.
- `docs/scrum/sprint-1/01-sprint-planning.md` §HU-004: historia, prioridad, estimación y criterios.
- `docs/scrum/sprint-1/02-proceso-por-hu.md` §CP-003: escenarios de prueba y estado `not executed`.
- `docs/sprint-0/auditoria-br.md` BR-A1–A8 y BR-B1–B9: aislamiento, invitación, checkout simulado, planes y gaps.
- `backend/app/modules/tenant/{models,schemas,service,repository,router}.py`: implementación actual y sus límites.
- `backend/app/modules/identity/{models,router,service}.py` y `backend/app/core/{config,tokens}.py`: contratos actuales de identidad/autenticación.
- `backend/alembic/versions/0003_crear_tablas_tenant.py`: esquema de tenant existente.
- `openspec/changes/registro-cliente/{proposal,design}.md` y `openspec/changes/autenticacion/{spec,design}.md`: convenciones de slice backend-first, separación router/service/repository, clocks inyectables, pruebas con fakes y límites explícitos.

## 11. Recomendación de siguiente fase

Avanzar a `proposal` en modo interactivo, llevando como decisiones obligatorias: contrato del evento firmado, semántica de idempotencia concurrente, relación mínima del primer administrador con `identity`, estrategia de planes seed y frontera exacta Web/backend. No avanzar a diseño o tareas mientras los gaps críticos no estén resueltos.
