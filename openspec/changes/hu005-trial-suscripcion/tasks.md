# Plan de implementación — HU-005 Trial y suscripción mensual

- **Cambio:** `hu005-trial-suscripcion`
- **Trazabilidad:** `PB-005` / `HU-005` / `CU-005` / `CP-004`
- **Sprint / plataforma:** Sprint 1 / Web y Backend
- **Almacén de artefactos:** Hybrid (OpenSpec + Engram)
- **Modo TDD:** Strict TDD activo; orden obligatorio RED → GREEN → TRIANGULATE → REFACTOR
- **Estrategia de entrega:** `ask-on-risk`
- **Límite duro:** exactamente `400` líneas modificadas como máximo; no existe excepción implícita
- **Estado actual:** implementación y TRIANGULATE completados para el candidato actual; calidad, migración y evidencia conductual de PostgreSQL disposable pasan; `CP-004` y `CP-004.1/.2/.3` están respaldados. REFACTOR permanece pendiente.
- **Límites de implementación:** solo backend/API, asociación `tenant_administrator`, trial, inspección, webhook mensual firmado, idempotencia, persistencia aditiva y evidencia CP-004. No UI, billing real, nuevos planes/precios/cuotas, ciclo HU-006, RBAC/memberships generales, notificaciones ni refactors no relacionados.

## Review Workload Forecast

| Campo | Valor |
| ------- | ------- |
| Estimated changed lines | 372 líneas (estimación recalculada; adiciones + eliminaciones) |
| 400-line budget risk | Medium |
| Chained PRs recommended | No |
| Suggested split | PR único, con work units internos y límite de 400 líneas |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

| Work unit | Fase principal | Estimación |
| --- | --- | ---: |
| `WU-005-TDD` — módulo enfocado de pruebas RED | RED | 88 |
| `WU-005-DATA` — modelos y migración aditiva | GREEN | 50 |
| `WU-005-CONTRACT` — schemas y proyección | GREEN | 36 |
| `WU-005-RULES` — service, guards y calendario | GREEN | 60 |
| `WU-005-POSTGRES` — repository, locks, transacción y replay | GREEN | 78 |
| `WU-005-HTTP-HMAC` — router y costura HMAC/alias | GREEN | 27 |
| `WU-005-TRIANGULATE` — PostgreSQL, migración y regresión | TRIANGULATE | 25 |
| `WU-005-REFACTOR` — simplificación posterior a evidencia | REFACTOR | 8 |
| **Total estimado** | | **372** |
| **Reserva restante** | | **28** |
| **Límite duro** | | **400** |

La reserva de 28 líneas no autoriza ampliar alcance. Si la suma real de cambios supera `400`, la consecuencia exacta de `ask-on-risk` es **detener `sdd-apply`, no aplicar una excepción y solicitar una decisión explícita**: reducir o dividir el slice conservando los guards aprobados. No se eliminan silenciosamente requisitos, tests de seguridad ni evidencia de PostgreSQL.

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Medium

## Dependencias, límites y evidencia

1. El planning vive en el repositorio raíz; el código, tests y Alembic viven en el submódulo Git `backend/`.
2. Antes de modificar código, `sdd-apply` debe confirmar el checkout, Git common directory y autoridad del runtime nativo para root/submódulo. El conteo de líneas debe excluir el gitlink modificado y metadata raíz no relacionada.
3. Debe verificarse el head Alembic real y el delta efectivamente entregado por HU-004, incluyendo helper/export HMAC y columnas de `EventoFacturacion`; no asumir `0003`, nombres no confirmados ni columnas duplicadas.
4. Cada work unit tiene una frontera de finalización y rollback. Si falla una frontera, conservar cambios previos compatibles, revertir únicamente el work unit incompleto y no ejecutar cleanup, commits, pushes ni cambios de rama.
5. Los fakes prueban reglas determinísticas; únicamente PostgreSQL prueba locks, unicidad, rollback, concurrencia y migración. Ningún checkbox de este documento afirma ejecución actual.

## RED — contratos y pruebas fallidas primero

### `WU-005-RED-01` — Preflight técnico y delimitación

- [ ] Confirmar en `backend/` el head Alembic real, la revisión padre disponible, el módulo de tests tenant y los exports exactos de `HMACWebhookSignatureVerifier`, headers y tolerancia de HU-004; registrar los paths y gaps encontrados sin inventar valores. La evidencia es una nota de apply/preflight; si faltan extensiones HU-004, detener la integración y coordinar la dependencia. <!-- sdd-owner: implementation -->
- [ ] Confirmar en `backend/app/modules/tenant/{models,schemas,service,repository,router}.py` los seams actuales descritos por el diseño y en `backend/tests/` elegir o reutilizar un único módulo enfocado para HU-005; la evidencia es el mapa de archivos final y la ausencia de una segunda suite redundante. <!-- sdd-owner: implementation -->

### `WU-005-RED-02` — Contrato HTTP y CP-004

- [ ] En `backend/tests/test_tenant_subscription.py` o en el módulo tenant elegido, escribir tests fallidos para `POST /api/v1/tenant/administrador/bootstrap`, `POST /api/v1/tenant/activar-prueba`, `GET /api/v1/tenant/suscripcion`, `POST /api/v1/tenant/webhook` y el alias `/suscribir`: body vacío/`extra="forbid"`, respuestas `201/200`, errores sanitizados y proyección mínima. La evidencia debe demostrar tests RED y mapear `CP-004.1`, `CP-004.2` y `CP-004.3`, sin afirmar que corrieron en esta fase. <!-- sdd-owner: implementation -->
- [ ] En el mismo módulo, fijar tests fallidos para que `tenant_id` en body/query/evento no sea autoridad y para que la respuesta no exponga payload, firma, secreto, JWT, password, token, hashes sensibles, correo completo ni datos de otro tenant. La evidencia será el conjunto de assertions de contrato y no una ejecución declarada. <!-- sdd-owner: implementation -->

### `WU-005-RED-03` — Autorización y bootstrap

- [ ] Escribir tests fallidos para `get_current_user`, `TenantPrincipal` y el bootstrap server-owned vinculado a `Invitacion` HU-004 consumida: JWT ausente/inválido, usuario inactivo, asociación inexistente/inactiva, correo no coincidente, candidato ambiguo, repetición idempotente y vínculo ya usado. La evidencia debe cubrir no enumeración y ausencia de password/token crudo/membership general. <!-- sdd-owner: implementation -->

### `WU-005-RED-04` — Estado y calendario

- [ ] Escribir tests fallidos con reloj inyectado para `active` inicial → `trialing`, `trial_inicio`, `trial_fin = +336 horas`, activación repetida, datos inconsistentes y activaciones concurrentes. La evidencia debe comprobar que solo una solicitud escribe y la otra conserva fechas/estado/eventos. <!-- sdd-owner: implementation -->
- [ ] Escribir tests fallidos para `now >= trial_fin`, solo `trialing → active`, rechazo de conversión desde initial `active`, active convertido y estados HU-006; incluir `America/La_Paz`, 31→mes corto, febrero bisiesto/no bisiesto, zona y serialización timezone-aware. La evidencia debe distinguir el límite exacto de una duración fija de 30 días. <!-- sdd-owner: implementation -->

### `WU-005-RED-05` — HMAC, evento e idempotencia

- [ ] Escribir tests fallidos que reutilicen el helper HU-004 para raw bytes, `ASCII(timestamp) + b"." + raw_body`, comparación constante, headers exactos, firma ausente/alterada/malformada, secreto ausente, timestamps stale/future/límite y autenticación antes de cualquier lookup. La evidencia debe incluir que no se consulta ni persiste negocio ante `401`. <!-- sdd-owner: implementation -->
- [ ] Escribir tests fallidos para `event_type = "subscription.monthly.succeeded"`, schema `extra="forbid"`, correlación por `subscription_id`, plan/monto server-owned, diferencia frente a `tenant.onboarding.succeeded`, replay fuera de ventana, misma key con bytes distintos, evento legacy sin hash y key distinta post-conversión. La evidencia debe fijar `201` nuevo, `200` replay y `409` conflictivo. <!-- sdd-owner: implementation -->

### `WU-005-RED-06` — Persistencia, migración y regresión

- [ ] Escribir tests fallidos para una única transacción de suscripción/evento, rollback ante falla de cada escritura, unicidad persistente de `idempotency_key`, carrera de unique key, locks `FOR UPDATE`, replay concurrente y ausencia de duplicados. La evidencia debe identificar explícitamente qué casos requieren PostgreSQL real. <!-- sdd-owner: implementation -->
- [ ] Escribir tests fallidos de migración desde el head HU-004 real: columnas aditivas, tabla/índices/FKs, legacy `active` intacto, ningún trial sintético, no cambio de plan, downgrade bloqueado con datos HU-005 y downgrade vacío solo en base descartable. La evidencia debe incluir que nunca se hace downgrade destructivo sobre datos reales. <!-- sdd-owner: implementation -->
- [ ] Fijar el caso de regresión HU-004/HU-006 en el mismo módulo o fixtures existentes: onboarding `tenant.onboarding.succeeded` sigue funcionando, identidad HU-002 no se altera y los estados/catálogo de HU-006 siguen representables. La evidencia permanece pendiente hasta ejecutar la suite. <!-- sdd-owner: implementation -->

**Frontera RED:** termina cuando todos los contratos anteriores existen como tests fallidos, el head/delta técnico está documentado y ningún código productivo de HU-005 fue añadido. Rollback: eliminar solo el bloque RED si el contrato requiere corrección, sin tocar tests HU-004/HU-006.

## GREEN — implementación mínima

### `WU-005-GREEN-01` — Modelo y migración aditiva

- [ ] Modificar `backend/app/modules/tenant/models.py` para agregar `Suscripcion.trial_inicio`, `Suscripcion.periodo_inicio` y `TenantAdministrator` con UUID, FKs, estado/timestamps, unicidades e índices acordados; agregar en `EventoFacturacion` solo referencias de resultado mensual o delta ausente tras la verificación HU-004. La evidencia es metadata coherente y ausencia de roles, permisos, memberships o duplicación HMAC/evento. <!-- sdd-owner: implementation -->
- [ ] Crear `backend/alembic/versions/<next_revision>_hu005_trial_subscription.py` usando el head real confirmado, con upgrade aditivo y downgrade fail-closed cuando existan asociaciones, valores HU-005 o eventos mensuales; preservar legacy y no imponer un check que bloquee estados futuros HU-006. La evidencia es el diff de migración y tests preparados para upgrade/downgrade; no se afirma ejecución. <!-- sdd-owner: implementation -->

### `WU-005-GREEN-02` — Schemas y proyección

- [ ] Modificar `backend/app/modules/tenant/schemas.py` para reemplazar contratos HU-005 inseguros por request vacío/bootstrap, evento mensual estricto y `SuscripcionResponse` con `subscription_id`, `plan_id`, `estado`, `trial_inicio`, `trial_fin`, `periodo_inicio` y `periodo_fin`; preservar schemas HU-004/HU-006. La evidencia es OpenAPI/model validation con `extra="forbid"` y sin secretos. <!-- sdd-owner: implementation -->

### `WU-005-GREEN-03` — Service, guards y calendario

- [ ] Modificar `backend/app/modules/tenant/service.py` para introducir principal reducido, bootstrap idempotente, autorización por asociación activa, activación derivada del JWT, inspección segura y errores estables; no aceptar `tenant_id` de cliente ni alterar identidad HU-002. La evidencia son los tests RED de auth/contrato satisfechos. <!-- sdd-owner: implementation -->
- [ ] Implementar en `backend/app/modules/tenant/service.py` el reloj `ClockProtocol`, `timedelta(hours=336)`, expiración `now >= trial_fin`, transición exclusiva `trialing → active`, plan inmutable y cálculo mensual con `ZoneInfo("America/La_Paz")`/`calendar.monthrange`. La evidencia son los casos determinísticos de estado/calendario; no usar 30 días. <!-- sdd-owner: implementation -->

### `WU-005-GREEN-04` — Repository, locks e idempotencia atómica

- [ ] Modificar `backend/app/modules/tenant/repository.py` para resolver asociación/tenant server-owned, bootstrap, inspección y activación bajo `with_for_update`, conservando APIs HU-004/HU-006 compatibles. La evidencia es que el servicio ya no usa `guardar_suscripcion` como commit aislado para HU-005. <!-- sdd-owner: implementation -->
- [ ] Implementar en `backend/app/modules/tenant/repository.py` la conversión mensual en una transacción: lookup de key, relectura tras lock, validación de trial/plan/monto/correlación, actualización, inserción de evento con raw body/hash/referencias y un solo commit. La evidencia es una ruta de rollback única y no hay evento sin conversión ni conversión sin evento. <!-- sdd-owner: implementation -->
- [ ] Recuperar en `backend/app/modules/tenant/repository.py` únicamente carreras donde una lectura posterior confirma key, tipo mensual, hash y resultado; traducir otras `IntegrityError` a fallo transaccional. La evidencia es replay original estable, `409` para conflicto y ninguna inferencia basada en texto de excepción. <!-- sdd-owner: implementation -->

### `WU-005-GREEN-05` — Router, HMAC y compatibilidad

- [ ] Modificar `backend/app/modules/tenant/router.py` para inyectar `Depends(get_current_user)` en bootstrap, activación e inspección; leer raw body una sola vez en webhook, validar `Content-Type` y multiplicidad de headers y mapear errores sanitizados. La evidencia es autenticación antes de lookup y respuestas sin existencia leaks. <!-- sdd-owner: implementation -->
- [ ] Convertir `/webhook` y `/suscribir` en entradas de la misma tubería HMAC/parser/service, conservar `tenant.onboarding.succeeded` para HU-004 y hacer fallar cerrado el contrato legacy sin HMAC o sin evento mensual. La evidencia es compatibilidad HU-004 y ausencia de commits propios del alias. <!-- sdd-owner: implementation -->

**Frontera GREEN:** termina cuando todos los tests RED pasan en los dobles determinísticos y el diff sigue en o debajo de `400` líneas, sin ejecutar todavía la afirmación de CP-004 completo. Rollback: revertir por work unit sin borrar migraciones o datos existentes; cualquier dependencia HU-004 faltante bloquea la continuación.

## TRIANGULATE — evidencia de infraestructura y regresión

- [x] Ejecutar una base PostgreSQL de integración para confirmar locks, activación/conversión concurrente, unique key, replay exacto concurrente, misma key con bytes distintos, rollback conjunto y key distinta post-conversión; registrar comandos, conteos, IDs opacos y resultados reproducibles. Evidencia parent: `sha256:9d2b44780ac326b5f22982350474e5d9473e7ff1f3fc59e7754e3c348ac4783f`. <!-- sdd-owner: implementation -->
- [x] Ejecutar upgrade desde el head Alembic HU-004 real y downgrade únicamente en una base descartable vacía; verificar FKs/índices, preservación de filas initial `active`, nulabilidad legacy y bloqueo de downgrade con datos HU-005. En una base real con datos HU-005, usar forward-fix y no downgrade destructivo. Evidencia disposable: `sha256:eacf82d375fa76332ccc9eae6114c6326330f5d8ad0650ef78f59eb5fb926fcd`. <!-- sdd-owner: implementation -->
- [x] Ejecutar los comandos exactos definidos por el proyecto: `.venv/Scripts/python.exe -m pytest backend/tests -q`, `.venv/Scripts/ruff check backend/app backend/tests`, `.venv/Scripts/pyright.exe backend/app backend/tests` y `.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head`; la evidencia de calidad y migración quedó separada de CP-004. <!-- sdd-owner: implementation -->
- [x] Confirmar con tests/log inspection que no se agregaron UI/Flutter, billing/notifier, nuevos planes/precios/cuotas, lifecycle HU-006, RBAC/memberships generales, endpoint público de eventos ni cambios en `docs/diagramas/Diagrama1.eapx`; documentar compatibilidad HU-004/HU-006. <!-- sdd-owner: implementation -->

**Frontera TRIANGULATE:** completada con evidencia determinística, PostgreSQL, migración y calidad/regresión separadas; la base disposable fue eliminada y el downgrade con datos HU-005 falló cerrado. Rollback: preservar la evidencia y no ejecutar downgrade destructivo sobre datos reales.

## REFACTOR — solo después de evidencia

- [ ] Solo después de GREEN y TRIANGULATE, simplificar duplicación mínima en `backend/app/modules/tenant/{service,repository,router,schemas}.py` sin cambiar contratos, guards, errores, queries, HMAC, calendario o respuestas; la evidencia debe ser diff ≤ `400` y repetición de los checks afectados. <!-- sdd-owner: implementation -->
- [ ] Revisar logs, errores y comentarios para garantizar no divulgación y confirmar que `/suscribir` sigue siendo alias deprecated de la tubería firmada; la evidencia debe conservar el resultado de regresión y registrar cualquier warning sin presentarlo como PASS. <!-- sdd-owner: implementation -->

**Frontera REFACTOR:** termina con código equivalente y verificable, sin nueva funcionalidad. Rollback: revertir únicamente la simplificación si altera evidencia; no abrir otro ciclo de cambios sin una nueva decisión de alcance.

## Matriz de trazabilidad requisito → tarea → evidencia

| Requisito / criterio | Tareas | Evidencia requerida |
| --- | --- | --- |
| Asociación mínima, bootstrap e aislamiento | `RED-03`, `GREEN-03`, `GREEN-01` | JWT, invitación consumida, vínculo único, no leaks |
| Activación única y CP-004.1 | `RED-02`, `RED-04`, `GREEN-03/04` | `trialing`, `trial_inicio`, `trial_fin`, 336 h, conflicto sin mutación |
| Expiración y transición mínima | `RED-04`, `GREEN-03/04` | `now == trial_fin`, solo `trialing → active`, estados HU-006 intactos |
| Inspección segura | `RED-02/03`, `GREEN-02/03/05` | proyección mínima, errores indistinguibles, sin datos sensibles |
| HMAC y CP-004.2 | `RED-05`, `GREEN-05` | raw bytes, headers/tolerancia HU-004, auth antes de lookup |
| Correlación, plan y calendario | `RED-04/05`, `GREEN-03/04` | plan conservado, monto/correlación, `America/La_Paz`, fin de mes |
| Replay, conflictos y CP-004.3 | `RED-05/06`, `GREEN-04` | `201` nuevo, `200` original, `409` distinto, sin duplicados |
| Atomicidad y concurrencia | `RED-06`, `GREEN-04`, `TRIANGULATE-01` | PostgreSQL locks, unique race, rollback conjunto |
| Migración y legacy | `RED-06`, `GREEN-01`, `TRIANGULATE-02` | upgrade HU-004, downgrade vacío, no downgrade real destructivo |
| Seguridad, privacidad y no divulgación | `RED-02/03/05`, `GREEN-03/05`, `REFACTOR` | respuestas/logs sanitizados, sin autoridad de body/evento |
| Alcance y compatibilidad HU-004/HU-006 | `RED-06`, `GREEN-05`, `TRIANGULATE-04` | regresión, estados representables, no UI/notifier/RBAC |

## Checklist final pre-apply

- [ ] Confirmar que `proposal.md`, `specs/tenant-subscription/spec.md`, `design.md` y este `tasks.md` son el conjunto vigente, y que la fase sigue siendo `tasks` con `nextRecommended: tasks` antes de iniciar apply. <!-- sdd-owner: implementation -->
- [ ] Confirmar que el forecast concreto permanece ≤ `400`, que no se requiere chain y que cualquier excedente activa la decisión explícita de `ask-on-risk`; no elevar el límite. <!-- sdd-owner: implementation -->
- [ ] Confirmar el root/submódulo/common-directory del runtime nativo y el mecanismo de accounting antes de cualquier actor `sdd-apply`; esta tarea no declara que native runtime accounting esté resuelto. <!-- sdd-owner: implementation -->
- [ ] Confirmar paths/export exactos HU-004 y head Alembic real; no crear `<next_revision>` hasta resolver `down_revision` y el delta de `EventoFacturacion`. <!-- sdd-owner: implementation -->
- [ ] Confirmar que no se editarán `docs/diagramas/Diagrama1.eapx`, UI, metadata raíz no relacionada, ramas, commits, pushes ni cleanup, y que no se creará `apply-progress` durante esta fase. <!-- sdd-owner: implementation -->
- [ ] Entregar el plan para aprobación interactiva del parent antes de `sdd-apply`; hasta esa aprobación, CP-004 sigue `not executed` y no se inicia implementación. <!-- sdd-owner: parent -->
