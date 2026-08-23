# Informe de verificación — `autenticacion`

## Estado

**VERIFY PASS — remediación confirmada.**

La verificación se ejecutó sobre la rama `feat/autenticacion/t4-endpoints`, commit `09b5a1a` (`fix(auth): remediate authentication verify blockers`). Los tres blockers de la verificación anterior quedaron resueltos:

1. **REQ-06:** `AuthenticationService.refresh` ya no hace `buscar_por_hash` antes de `rotar_por_hash`; la rotación SQLAlchemy mantiene `SELECT ... FOR UPDATE` y la transacción única, y copia el `usuario_global_id` bloqueado a la sesión reemplazo.
2. **REQ-10:** `create_app()` construye `PyJWTTokenService` sincrónicamente y falla cerrado sin `JWT_SECRET`; la aplicación por defecto registra la misma validación en su startup hook. No hay secreto operativo hardcodeado.
3. **REQ-12/TDD:** la suite incorpora los casos faltantes y `apply-progress.md` contiene una tabla reconciliada de evidencia TDD para T1–T5.

No quedan blockers críticos de implementación ni tareas de implementación sin completar. `REQ-05` permanece **NOT VERIFIED** únicamente por `GAP-092` (no se ejecutó PostgreSQL real); la verificación offline y los fakes sí fueron ejecutados según el alcance aprobado.

## Cobertura por requisito

| Requisito | Veredicto | Evidencia final |
| --- | --- | --- |
| REQ-01 — login `200/401/422` | **PASS** | `router.py:121-129`, `schemas.py` y `service.py:80-116` implementan el contrato, normalización, verificación uniforme, sesión inicial y payload público. `test_autenticacion.py` cubre login válido, validación, no enumeración y ausencia de sesión inválida. |
| REQ-02 — error genérico no enumerativo | **PASS** | `service.py:83-91` rechaza correo inexistente, password incorrecto y cuenta inactiva con el mismo error; `verify_password_uniform` conserva la verificación ficticia. `test_login_does_not_enumerate_missing_email_or_wrong_password` y `test_inactive_account_uses_same_generic_login_error` verifican `401` y `{"detail":"Correo o contraseña inválidos"}` idénticos. |
| REQ-03 — access HS256 + refresh opaco SHA-256 | **PASS** | `app/core/tokens.py:49-110` usa PyJWT HS256, claims `sub/sid/type/iat/exp`, TTL controlado por clock, `secrets.token_urlsafe` y SHA-256 hexadecimal. `test_tokens_core.py` verifica firma, claims, TTL, tipo, firma/expiración inválidos; `test_login_persists_exact_sha256_hash_without_plaintext` compara exactamente contra `hashlib.sha256(refresh.encode()).hexdigest()`. No hay logging del refresh en `app/`. |
| REQ-04 — modelo y migración `0002` | **PASS** | `models.py` y `0002_crear_sesion.py` coinciden en UUID PK, FK, `CHAR(64)`, timestamps, `revocado`, UNIQUE e índice. `alembic upgrade head --sql` mostró `CREATE TABLE sesion`, FK, UNIQUE e índice; `alembic downgrade 0002:0001 --sql` mostró únicamente `DROP INDEX` y `DROP TABLE sesion`, preservando `usuario_global`. La ejecución contra PostgreSQL real queda fuera por `GAP-092`. |
| REQ-05 — `SessionRepository` | **NOT VERIFIED — GAP-092 esperado** | El protocolo, adaptador SQLAlchemy (`SELECT ... FOR UPDATE`, validación, rotación, revocación y actividad) y fake están presentes. `test_session_repository.py` ejecuta 5 casos verdes, incluidos creación, rotación/reuso, concurrencia fake, actividad 29/31 minutos y revocación idempotente. No se afirma la ejecución del locking real contra PostgreSQL. |
| REQ-06 — refresh rotatorio | **PASS** | `service.py:118-156` calcula hashes y llama directamente a `rotar_por_hash`; no preconsulta. `repository.py:154-172` abre la transacción, bloquea la fila, valida, asigna `nueva_sesion.usuario_global_id = anterior.usuario_global_id`, revoca e inserta antes del commit. `test_refresh_uses_atomic_rotation_without_prior_hash_lookup` falla explícitamente si se invoca la búsqueda previa y pasó; la suite cubre rotación, reuso y nuevo par. Una reproducción complementaria con `SessionRepository` y sesiones SQLAlchemy separadas en SQLite in-memory rotó correctamente y preservó el usuario; PostgreSQL real sigue siendo `GAP-092`. |
| REQ-07 — logout `204` idempotente | **PASS** | `router.py:143-149` devuelve `204` sin cuerpo; `service.py:159-162` revoca por hash. `test_logout_is_idempotent_and_revokes_refresh` cubre logout válido, repetido, desconocido y reutilización rechazada. |
| REQ-08 — `/auth/me` protegido | **PASS** | `HTTPBearer(auto_error=False)` en `router.py:38-39` traduce ausencia/malformación a `401`, nunca `403`; `service.py:164-182` valida JWT, `sid`, `sub`, sesión e inactividad. Hay cobertura de ausencia y de token malformed, firma incorrecta, tipo incorrecto, sesión inexistente y usuario inconsistente; todos responden `401` genérico. La prueba complementaria de access expirado por HTTP también respondió `401` genérico. |
| REQ-09 — inactividad sliding de 30 minutos | **PASS** | `repository.py:321-325` aplica expiración por inactividad y revocación lazy; la validación actualiza `ultima_actividad`. Los tests cubren actividad a 29 minutos, rechazo a más de 30 minutos, refresh dentro de ventana y rechazo de `/me`/refresh inactivos. |
| REQ-10 — configuración y tokens en `app/core/` | **PASS** | `config.py` obtiene `JWT_SECRET`/TTLs desde entorno sin secreto operativo por defecto. `create_app()` construye `PyJWTTokenService(resolved_settings)` antes de devolver la app (`main.py:37-46`); `_create_default_app()` valida la configuración en startup (`main.py:49-62`). `test_create_app_fails_closed_without_jwt_secret` y `test_create_app_fails_closed_when_environment_lacks_jwt_secret` pasan. La prueba de startup del default app sin `JWT_SECRET` produjo `SecurityConfigurationError: JWT_SECRET must be configured`. `pyproject.toml` declara `PyJWT>=2.8,<3`. |
| REQ-11 — estructura S0-10 y DI | **PASS** | Existen `router.py`, `schemas.py`, `service.py`, `repository.py` y `models.py`; el router no contiene SQL; `main.py` registra el módulo bajo `/api/v1`; login reutiliza `UserRepository.buscar_por_correo` y Argon2id uniforme; los tests usan `dependency_overrides`; OpenAPI lista las cuatro rutas. |
| REQ-12 — TDD, TestClient, fakes y CP-002 | **PASS** | `test_autenticacion.py` contiene 16 casos y la suite completa pasa 33. Están presentes cuenta inactiva, hash SHA-256 exacto/no plaintext, refresh expirado, rotación atómica, variantes `/me` `401-not-403`, fail-closed de configuración y validación `422`. Los cinco pasos de CP-002 tienen cobertura reproducible; no se requiere PostgreSQL real. |

## Evidencia de pruebas y validación

Todos los comandos se ejecutaron desde `backend/` con el CLI del venv autorizado:

```text
/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -m pytest tests -q
```

Resultado:

```text
33 passed, 3 warnings in 2.50s
```

```text
/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -m ruff check app tests
```

Resultado:

```text
All checks passed!
```

```text
/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/pyright.exe app tests
```

Resultado:

```text
0 errors, 0 warnings, 0 informations
```

Verificación focalizada:

```text
/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -m pytest tests/test_autenticacion.py -q
```

Resultado: `16 passed, 3 warnings`.

Regresiones remediadas seleccionadas:

```text
/d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -m pytest tests/test_autenticacion.py -q -k "atomic_rotation or inactive_account or persists_exact_sha256 or expired_refresh or me_invalid_token_variants or create_app_fails_closed"
```

Resultado: `7 passed, 9 deselected, 3 warnings`.

Migración offline:

```text
DATABASE_URL='postgresql+psycopg://user:pass@localhost/db' /d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -m alembic upgrade head --sql
```

Resultado: SQL estático con `CREATE TABLE usuario_global`, `CREATE TABLE sesion`, FK a `usuario_global.id`, `uq_sesion_refresh_token_hash` e `ix_sesion_usuario_global_revocado`; sin conexión a PostgreSQL.

```text
DATABASE_URL='postgresql+psycopg://user:pass@localhost/db' /d/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final/.venv/Scripts/python.exe -m alembic downgrade 0002:0001 --sql
```

Resultado: SQL estático con `DROP INDEX ix_sesion_usuario_global_revocado` y `DROP TABLE sesion`; `usuario_global` no se elimina.

Las tres advertencias de pytest son preexistentes/deprecaciones de Starlette/httpx y FastAPI `on_event`; no alteran el resultado. El ruido de LSP no se tomó como evidencia; Pyright CLI es la autoridad.

## TDD estricto

Strict TDD está activo. `apply-progress.md` contiene la tabla reconciliada **TDD Cycle Evidence — strict mode** con filas T1–T5 y columnas Safety Net, RED, GREEN, TRIANGULATE y REFACTOR.

| Unidad | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR | Estado |
| --- | --- | --- | --- | --- | --- | --- |
| T1 — núcleo de tokens | N/A, archivo unitario nuevo | Colección falló antes de PyJWT (`ModuleNotFoundError: jwt`) | 4 pasaron | Firma, claims/TTL, rechazos, refresh opaco/hash | Ruff limpio | **PASS** |
| T2 — modelo/migración | N/A, tarea estructural | Checks de aceptación de migración/modelo escritos | Alembic offline y Ruff pasaron | Alcance, modelo y migración coinciden | Checks estáticos limpios | **PASS** |
| T3 — repositorio | Baseline acumulado pasó | Colección falló antes de `FakeSessionRepository` | 5 pasaron | Crear/rotar/reusar, concurrencia, actividad y revocación | Ruff/Pyright limpios | **PASS** |
| T4 — endpoints/composición | Baseline conocido de 26 pasaron | Regresiones de rotación atómica y fail-closed fueron RED antes de la remediación | Suite auth focalizada: 16 pasaron | Cuenta inactiva, refresh expirado y matriz `/me` inválida | Ruff/Pyright limpios | **PASS** |
| T5 — contrato | Baseline conocido de 26 pasaron | Casos REQ-12 y regresiones startup/atomicidad escritos antes de corregir | Suite completa: 33 pasaron | SHA-256 exacto, no plaintext, errores genéricos y `401-not-403` | Ruff limpio; Pyright 0 | **PASS** |

Cross-reference de archivos: existen y fueron ejecutados `backend/tests/test_tokens_core.py`, `backend/tests/test_session_repository.py` y `backend/tests/test_autenticacion.py`. No se detectaron tautologías críticas, loops fantasma, aserciones únicamente de tipos, smoke tests vacíos ni aserciones CSS irrelevantes.

### Assertion quality

- **WARNING:** `test_autenticacion.py:105` mantiene `assert user.id`, una comprobación de truthiness de bajo valor frente a las aserciones HTTP y de identidad que siguen a continuación.
- **WARNING:** `test_session_repository.py:47` comprueba que el literal fijo `"refresh-token"` no aparezca en hashes; no demuestra por sí sola la relación con un refresh real. La cobertura contractual fuerte está en `test_autenticacion.py:108-118`, que compara exactamente el SHA-256.
- **WARNING:** `test_tokens_core.py:90-92` verifica forma hexadecimal, longitud y diferencia, pero no la igualdad exacta con SHA-256; la igualdad exacta sí está cubierta en la suite API.

Estas observaciones no son blockers: las afirmaciones críticas de hash, exposición y comportamiento HTTP tienen aserciones directas en la suite remediada.

## Cobertura de CP-002

| Paso | Cobertura | Evidencia |
| --- | --- | --- |
| 1. Login válido | **PASS** | `test_login_returns_public_token_pair` + `test_login_persists_exact_sha256_hash_without_plaintext`. |
| 2. Credenciales inválidas/no enumeración | **PASS** | `test_login_does_not_enumerate_missing_email_or_wrong_password` + cuenta inactiva con mismo `401/detail`. |
| 3. Actividad dentro de ventana/rotación | **PASS** | refresh a los 20 minutos y `/me` a los 29 minutos; actividad actualizada y par nuevo válido. |
| 4. Más de 30 minutos sin actividad | **PASS** | `/me` y refresh responden `401` genérico y la sesión queda revocada; refresh expirado también se rechaza. |
| 5. Logout/reutilización | **PASS** | logout `204` idempotente, fila revocada y refresh posterior `401`. |

La documentación de CP-002 continúa correctamente como `not executed`; esta evidencia corresponde a pruebas automatizadas unitarias/API con fakes, no a una ejecución de caja negra documentada.

## Estado estructurado y `actionContext`

Estado nativo consumido antes de verificar:

```yaml
schemaName: gentle-ai.sdd-status
changeName: autenticacion
artifactStore: openspec
sessionArtifactStore: hybrid
planningHome: repo-local/openspec
artifacts: proposal=done, specs=done, design=done, tasks=done, applyProgress=done, verifyReport=done
taskProgress: total=7, completed=5, pending=2
applyState: ready
dependencies.verify: blocked
nextRecommended: apply
actionContext.mode: repo-local
workspaceRoot: D:\Universidad\Proyectos\2doSemestre2026\sw1\proyecto_final
allowedEditRoots:
  - D:\Universidad\Proyectos\2doSemestre2026\sw1\proyecto_final
```

Hallazgos de status:

- La selección `autenticacion` es explícita y no ambigua.
- La autoridad nativa identificó `openspec` porque existe `openspec/`; los artefactos requeridos también fueron confirmados en Engram.
- Las 5 tareas de implementación T1–T5 están `[x]`. Las 2 filas pendientes son acciones explícitamente `sdd-owner: parent`, no trabajo de implementación.
- `actionContext.mode=repo-local` y la raíz autorizada coincide con el workspace; no hubo problema de autoridad de edición.
- El estado nativo mantiene `dependencies.verify=blocked`/`nextRecommended=apply` porque las acciones parent-owned de review/delivery siguen pendientes. Esta re-ejecución fue solicitada explícitamente para refrescar la evidencia contra `09b5a1a`; no se modificó `tasks.md` ni se autoejecutaron acciones parent-owned.

## Tareas y completitud

No quedan líneas unchecked de implementación (`sdd-owner: implementation`). Permanecen exactamente estas acciones parent-owned, que no bloquean la completitud de implementación pero sí deben reconciliarse antes del cierre final de delivery/archive:

```text
- [ ] Start or reuse bounded review del slice implementado (contraste con spec REQ-01..REQ-12 y design: criterios de terminado de T1..T5, ausencia de refresh/password/hashes en respuestas y logs, cobertura CP-002 y REQ-12, resolución del vínculo access↔`sesion` vía `sid`). <!-- sdd-owner: parent -->
- [ ] Gate de entrega chain (`auto-chain` → `stacked-to-main`): verificar por T que el diff ≤ ~400 líneas (dividiendo internamente una T si cruza el umbral), validar `pytest -q` verde por PR, correr los gates de entrega por PR (pre-commit/pre-pr) y crear en secuencia las ramas `feat/autenticacion/tN-<slug>` y sus PRs a `main` (5 PRs según el split del forecast; documentar cada PR en el apply-progress). <!-- sdd-owner: parent -->
```

## Review workload / límite de PR

- Forecast: `~1450–1650` líneas; riesgo de presupuesto de 400 líneas **High**; chained PRs **Yes**.
- Estrategia registrada: `auto-chain`, chain `stacked-to-main`; no se usó `size:exception`.
- El trabajo se mantuvo en el slice backend T1–T5 y en la remediación de los tres blockers. No se observó scope creep funcional.
- Referencias de commits: `5d2a94d` (T1), `fc71daf` (T2), `e6a6ecd` (T3), `2df56f2` (T4), `e6c3b4b` (documentación), `23d0674` (apply-progress reconciliado), `09b5a1a` (remediación).
- No se crearon ramas nuevas, PRs, pushes ni gates parent-owned durante esta fase.
- La modificación `docs/diagramas/Diagrama1.eapx` permanece preexistente, fuera de scope e ignorada según la instrucción. El único archivo generado por esta fase es este `verify-report.md`.

## Observaciones y blockers exactos

- **Blockers críticos:** ninguno.
- **GAP-092:** no se ejecutó PostgreSQL real; `REQ-05` queda `NOT VERIFIED` como excepción esperada y explícita. La migración se verificó únicamente con Alembic offline `--sql`.
- **Warnings no bloqueantes:** tres warnings de assertion quality y tres warnings/deprecaciones del runner.
- La exploración estructural usó `codegraph status`/`codegraph explore` después de confirmar `.codegraph/`; el proxy MCP de CodeGraph no estaba inicializado, por lo que se utilizó el CLI upstream de solo lectura. No se hicieron ediciones de código durante la verificación.

## Referencias de worker/commit

- Worker de implementación/remediación: apply corrective rerun de `autenticacion`, rama `feat/autenticacion/t4-endpoints`.
- Commit verificado: `09b5a1aec442a0ba4e2f8e767968071634b13f19`.
- Apply evidence: `openspec/changes/autenticacion/apply-progress.md` y observation Engram `sdd/autenticacion/apply-progress`.
- Spec/tareas/diseño: `openspec/changes/autenticacion/{spec.md,design.md,tasks.md}` y topics Engram correspondientes.

## Conclusión

**VERIFY PASS.** La implementación y la evidencia TDD cumplen REQ-01..REQ-12 dentro del alcance aprobado; `REQ-05` queda explícitamente `NOT VERIFIED` por el gap de PostgreSQL real, sin blocker adicional. Próximo paso recomendado: reconciliar las acciones parent-owned de bounded review y delivery chain, luego continuar con **sync/archive**.
