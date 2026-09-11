# Tareas de implementación — Alta de inmobiliaria (HU-004)

- **Cambio:** `hu004-alta-inmobiliaria`
- **PB/HU/CP:** PB-004 / HU-004 / CP-003
- **Slice:** backend y contrato API; sin UI, Flutter, pagos reales, HU-005, HU-006 ni membresías/RBAC.
- **Idioma:** documentación en español; código e identificadores en inglés.
- **Estrategia:** TDD estricto, en orden RED → GREEN → TRIANGULATE → REFACTOR.
- **Límite:** máximo 600 líneas modificadas; no realizar commits, push ni implementación durante esta fase.
- **Checkout:** público únicamente para el simulador del entorno de demo. El rollout productivo queda bloqueado hasta una decisión futura y no pertenece a este slice.

## Review Workload Forecast

| Field | Value |
| ------- | ------- |
| Estimated changed lines | 465–580 |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1: contrato, catálogo, firma y seams; PR 2: aprovisionamiento, idempotencia, activación y migración; integración/gates al cierre |
| Delivery strategy | ask-on-risk |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

## Reglas de ejecución y límites

- Mantener el patrón `router → service → repository` y reutilizar estructuras existentes en `backend/app/modules/tenant/`.
- Mantener sin cambios funcionales las rutas de HU-005/HU-006; cualquier ajuste compartido debe ser mínimo, justificado y cubierto por regresión.
- La estrategia de entrega quedó resuelta como `stacked-to-main`; implementar las unidades en orden y mantener cada una como una unidad revisable.
- Si la estimación concreta supera 600 líneas, detener la implementación y solicitar reducción de alcance o decisión explícita; no aplicar una excepción automáticamente.
- No agregar endpoints de consulta de eventos, UI, proveedor de correo, contraseña, `usuario_global`, membership, RBAC ni reglas operativas de cuotas.

## PR 1 — Contrato, catálogo y frontera de confianza

### RED — contratos y seams

- [ ] Crear `backend/tests/test_tenant_onboarding.py` con fixtures, `TestClient`/overrides y dobles `FakeTenantRepository`, `FakeClock`, `FakeSignatureVerifier`, `RecordingActivationNotifier` y `NullFirstAdminIdentityHook`; dejar documentados los límites de cada doble. <!-- sdd-owner: implementation -->
- [ ] Añadir pruebas RED para `GET /api/v1/tenant/plans` y `POST /api/v1/tenant/checkout`: tres planes aprobados en orden canónico, `precio_bob` como string decimal de dos posiciones, moneda BOB, `max_agents`, normalización de correo, estado confirmado y ausencia de tenant/suscripción/invitación/evento. <!-- sdd-owner: implementation -->
- [ ] Añadir pruebas RED de plan inexistente/inactivo, catálogo incompleto (`404`/`503` y cero escrituras) y campos de autoridad enviados al checkout (`extra="forbid"`, `422`, sin intención). <!-- sdd-owner: implementation -->
- [ ] Añadir pruebas RED de firma HMAC sobre `timestamp + b"." + raw_body`, headers requeridos, comparación constante, secreto ausente, payload alterado, timestamp inválido/fuera de ventana e igualdad exacta en el límite de 300 segundos. <!-- sdd-owner: implementation -->
- [ ] Añadir pruebas RED de contrato del webhook (`201` inicial, `200` idempotente) y de activación (`200`/`410`), verificando que respuestas y capturas de logs no expongan token, hash, body, password ni secreto. <!-- sdd-owner: implementation -->

### GREEN — modelos de contrato y componentes de confianza

- [ ] Implementar `backend/app/modules/tenant/catalog.py` con las definiciones canónicas `basico`, `profesional` y `empresarial`, sus cuotas aprobadas y orden estable, incluyendo que `max_agents` excluye al primer administrador. <!-- sdd-owner: implementation -->
- [ ] Ajustar `backend/app/modules/tenant/models.py` para `Plan.codigo`, `Plan.max_agents`, `CheckoutIntent`, `Invitacion.consumido_en`, `EventoFacturacion.checkout_id` y `payload_hash`, usando `Decimal`/`NUMERIC(10,2)` para el monto y sin columnas de identidad/RBAC. <!-- sdd-owner: implementation -->
- [ ] Implementar `backend/app/modules/tenant/schemas.py` para los cuatro contratos HTTP exactos, validación de UUID/correo/nombre/Decimal, `extra="forbid"` donde corresponda y respuestas que no incluyan secretos ni token. <!-- sdd-owner: implementation -->
- [ ] Implementar `backend/app/modules/tenant/signatures.py` y la configuración en `backend/app/core/config.py`: HMAC-SHA256, formato `v1=<lowercase hex>`, body crudo, tolerancia configurable por defecto 300, secreto sin default operativo y fallo cerrado. <!-- sdd-owner: implementation -->
- [ ] Implementar `backend/app/modules/tenant/ports.py` con `ActivationNotifier`, `FirstAdminIdentityHook`, `CheckoutAccessPolicy` y reloj inyectable; el adaptador nulo no crea identidad, membership ni rol. <!-- sdd-owner: implementation -->

### TRIANGULATE — contrato y seguridad

- [ ] Comparar los contratos implementados con `specs/tenant-onboarding/spec.md` y `design.md`, cubriendo CA1–CA4, BR-B1–B3 y los códigos HTTP definidos sin ampliar el alcance. <!-- sdd-owner: implementation -->
- [ ] Verificar mediante pruebas que la búsqueda de idempotencia ocurre solo después de autenticar el webhook, que el body firmado son los bytes recibidos y que un duplicado exacto autenticado puede recuperarse fuera de ventana. <!-- sdd-owner: implementation -->

### REFACTOR — primer límite de integración

- [ ] Mantener interfaces pequeñas y mover únicamente duplicación necesaria dentro de `backend/app/modules/tenant/`; preservar la importación del router existente y el comportamiento de HU-005/HU-006. <!-- sdd-owner: implementation -->

**Fin PR 1:** contratos, catálogo, configuración, firma y seams verificables; todavía sin aprovisionamiento funcional. Rollback: revertir este work unit sin eliminar datos de onboarding.

## PR 2 — Aprovisionamiento, idempotencia, activación y esquema

### RED — persistencia y concurrencia

- [ ] Completar en `backend/tests/test_tenant_onboarding.py` pruebas RED de webhook válido y correlacionado, fuente server-owned de nombre/correo/precio/cuotas, estados y cuatro recursos exactamente. <!-- sdd-owner: implementation -->
- [ ] Añadir pruebas RED de checkout inexistente/no confirmado, plan inactivo, `plan_id`/`checkout_id`/`monto_bob` inconsistentes, checkout ya procesado y eventos heredados sin `payload_hash`, todos sin efectos parciales. <!-- sdd-owner: implementation -->
- [ ] Añadir pruebas RED de rollback ante falla en cada etapa relevante, repetición secuencial, misma clave con payload distinto y reintentos concurrentes con `RLock`; exigir como máximo un tenant, suscripción, invitación y evento. <!-- sdd-owner: implementation -->
- [ ] Añadir pruebas RED de emisión/consumo de activación: hash SHA-256 de 64 hex, TTL de siete días, token solo en notifier fake, consumo único, expiración, desconocido y carrera concurrente; comprobar hook de identidad nulo. <!-- sdd-owner: implementation -->
- [ ] Añadir pruebas RED de migración: upgrade `0001 → 0004`, columnas/FK/índices, seed idempotente, adopción segura de plan legacy, colisiones/discrepancias abortadas, upgrade no destructivo y downgrade bloqueado con datos HU-004. <!-- sdd-owner: implementation -->

### GREEN — servicio, repositorio, rutas y migración

- [ ] Implementar `backend/app/modules/tenant/repository.py` con `create_checkout`, consultas de catálogo, transacción única de `provision_onboarding`, locks `FOR UPDATE`, unicidades persistentes y recuperación del resultado original tras conflicto concurrente. <!-- sdd-owner: implementation -->
- [ ] Implementar en `backend/app/modules/tenant/service.py` la normalización, política de checkout público de demo, correlación server-owned, verificación de monto con `Decimal`, mapeo de conflictos y generación en memoria del token/UUIDs. <!-- sdd-owner: implementation -->
- [ ] Implementar en `backend/app/modules/tenant/service.py` el consumo condicional de activación (`pendiente`, vigente, un solo uso), invocar el notifier únicamente después del commit y mantener `FirstAdminIdentityHook` nulo sin crear usuario/membership/RBAC. <!-- sdd-owner: implementation -->
- [ ] Ajustar `backend/app/modules/tenant/router.py` para `GET /api/v1/tenant/plans`, `POST /api/v1/tenant/checkout`, `POST /api/v1/tenant/webhook` y `POST /api/v1/tenant/activacion/consumir`; leer el body crudo una sola vez y mapear excepciones a los contratos definidos sin SQL ni reglas en router. <!-- sdd-owner: implementation -->
- [ ] Implementar `backend/alembic/versions/0004_hu004_onboarding.py` con `down_revision="0003"`, cambios aditivos, FK, unicidad de código, unicidad parcial por checkout, seed determinístico/idempotente y downgrade protegido; actualizar `backend/alembic/env.py` para importar `CheckoutIntent`. <!-- sdd-owner: implementation -->

### TRIANGULATE — integración y amenazas

- [ ] Ejecutar contra dobles y, si está disponible, PostgreSQL real la concurrencia, constraints, locks, rollback, recuperación idempotente y consumo único; distinguir evidencia fake de evidencia PostgreSQL y no declarar resultados no ejecutados. <!-- sdd-owner: implementation -->
- [ ] Revisar OpenAPI generado desde `backend/app/main.py` y las rutas tenant para confirmar las cuatro superficies, estados, códigos y ausencia de campos sensibles; comprobar que HU-005/HU-006 sigan registrados sin cambios funcionales. <!-- sdd-owner: implementation -->
- [ ] Auditar logs y excepciones de `backend/app/modules/tenant/` y `backend/app/core/config.py` para impedir body crudo, firma completa, secreto, token/hash, correo completo, password y detalles SQL. <!-- sdd-owner: implementation -->

### REFACTOR — estabilización

- [ ] Eliminar duplicación sin alterar contratos, conservar compatibilidad con datos legacy y mantener el diff dentro de 600 líneas; no refactorizar módulos fuera de HU-004. <!-- sdd-owner: implementation -->

**Fin PR 2:** flujo HU-004 completo, migración aditiva y rollback definido. Rollback operativo: deshabilitar webhook y preferir forward-fix; downgrade solo en base descartable sin datos HU-004.

## Gates y cierre de implementación

- [ ] Registrar en `backend/tests/test_tenant_onboarding.py` la trazabilidad de cada caso a CP-003/CA1–CA4 y mantener CP-003 como `not executed` hasta obtener evidencia real. <!-- sdd-owner: implementation -->
- [ ] Ejecutar desde la raíz, únicamente durante apply/verify y no en esta fase: `.venv/Scripts/python.exe -m pytest backend/tests -q`, `.venv/Scripts/python.exe -m ruff check backend/app backend/tests`, `.venv/Scripts/pyright.exe backend/app backend/tests` y `.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head`; conservar resultados y fallos como evidencia. <!-- sdd-owner: implementation -->
- [ ] Verificar upgrade/downgrade en una base vacía o fixture controlada y documentar cualquier limitación de PostgreSQL bajo `GAP-092`; no ejecutar downgrade destructivo sobre una base con onboarding. <!-- sdd-owner: implementation -->
- [ ] Confirmar antes de entrega que no se modificaron UI, Flutter, pagos reales, correo real, HU-005, HU-006, membresías/RBAC ni `docs/diagramas/Diagrama1.eapx`, y que no hubo commits ni push. <!-- sdd-owner: implementation -->

## Acciones explícitas del parent

La estrategia de cadena aprobada es `stacked-to-main`: cada unidad se mantiene como una PR revisable hacia `main`, en orden. Esta fase no autoriza commits, push ni ejecución de implementación/tests.
