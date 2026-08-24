# Apply progress — `prueba-hu001`

## Estado actual

- **Resultado:** `completed` para las tareas de implementación T1–T8.
- **Cambio:** `prueba-hu001`
- **Fase:** `sdd-apply`
- **Fecha de ejecución:** 2026-08-23/24 (hora local del entorno)
- **Backend activo solicitado:** hybrid; el status nativo identifica `artifactStore: openspec` porque existe `openspec/`; el progreso también se persistió en Engram.
- **Siguiente acción:** `parent-lifecycle` — bounded review y gate de entrega son acciones `sdd-owner: parent` y quedan diferidas.

## Continuidad con el intento previo

El primer intento quedó bloqueado antes de implementar porque el status nativo reportaba `design: missing`. Ese estado se conserva como historial, no como resultado vigente. En este intento `design.md` existe, el status fue refrescado y `applyState: ready`; no se perdió trabajo de implementación anterior porque T1–T8 estaban pendientes.

## Status estructurado consumido

```yaml
schemaName: gentle-ai.sdd-status
changeName: prueba-hu001
artifactStore: openspec
changeRoot: openspec/changes/prueba-hu001
artifacts:
  proposal: done
  specs: done
  design: done
  tasks: done
  applyProgress: done
  verifyReport: missing
taskProgress:
  total: 10
  completed: 8
  pending: 2
applyState: ready
dependencies:
  proposal: all_done
  specs: all_done
  design: all_done
  tasks: all_done
  apply: ready
  verify: blocked
actionContext:
  mode: repo-local
  workspaceRoot: D:\Universidad\Proyectos\2doSemestre2026\sw1\proyecto_final
  allowedEditRoots:
    - D:\Universidad\Proyectos\2doSemestre2026\sw1\proyecto_final
  warnings: []
nextRecommended: apply
```

La revisión de workload fue satisfecha antes de aplicar: `Decision needed before apply: No`, `Chained PRs recommended: No`, `Chain strategy: pending`, `400-line budget risk: Low`. Delivery boundary: single PR aditivo cuando el parent lo autorice; no se hizo commit, push ni PR.

## Tareas completadas y persistencia

- **T1 `[x]`:** se creó `infra/docker/compose.postgres.yml` con `postgres:16-alpine`, proyecto `roomforge`, healthcheck, restart y volumen explícito `roomforge_pgdata`.
  - El chequeo previo encontró `5433` ocupado por PostgreSQL del host (PID 6624). Se aplicó el fallback autorizado a `5434` y se dejó reflejado en compose, configuración local y evidencia.
  - `roomforge-postgres-1` quedó `Up ... (healthy)` y `pg_isready` respondió `accepting connections`.
- **T2 `[x]`:** se creó `backend/.env` local con URL efectiva en `localhost:5434`, secreto JWT de desarrollo y `APP_ENV=development`; `.gitignore` ya cubría `.env` y `.env.*`. `git check-ignore backend/.env` respondió `backend/.env`; no aparece en status/diff.
- **T3 `[x]`:** desde `backend/`, Alembic ejecutó `0001` y `0002`; `current` fue `0002 (head)`; las tablas públicas incluyeron `alembic_version`, `sesion` y `usuario_global`; la segunda ejecución de `upgrade head` fue idempotente.
- **T4 `[x]`:** uvicorn + httpx contra PostgreSQL real produjo los cuatro outcomes: P1 `201`, P2 duplicado con mayúsculas `409` y mensaje exacto, P3 correo inválido `422`, P4 contraseña corta `422`. Ambos cuerpos `422` no contienen `password`. Baseline previo del correo controlado: `0`.
- **T5 `[x]`:** SQL confirmó exactamente una fila, correo `prueba@ejemplo.inv` en minúsculas, `estado=activo`, `correo_verificado=f`, hash `$argon2id$` y ausencia de fila para el correo del caso de contraseña corta; el conteo final siguió en `1`.
- **T6 `[x]`:** se creó `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt` con entorno, infraestructura, migraciones, requests/responses y SQL. Auditoría efectiva: plaintext `0`, valor local sensible `0`, marcador de secreto `0`, `$argon2id$` `2` coincidencias.
- **T7 `[x]`:** se actualizó únicamente el alcance documental solicitado en `docs/scrum/sprint-1/02-proceso-por-hu.md`: CP-001 `executed`, cuatro pasos `executed`, adjunto real, reporte parcial `1/1/1/0/≈7,7 %/en ejecución`, CP-002..CP-013 pendientes y GAP-092 parcial por `0001`/`0002` reales con 12 tablas pendientes.
- **T8 `[x]`:** la suite terminó en `33 passed, 0 failed` sin cambios de este apply en `backend/app` ni `backend/tests`.

Los checkboxes T1–T8 se actualizaron en `openspec/changes/prueba-hu001/tasks.md` inmediatamente después de completar el trabajo y el espejo Engram `sdd/prueba-hu001/tasks` también fue actualizado. Las dos filas parent permanecen byte-equivalentes y `[ ]`.

## Evidencia de comandos y decisiones

### Compose y conexión

```text
Docker Engine 29.6.2
postgres (PostgreSQL) 16.14
roomforge-postgres-1  postgres:16-alpine  Up ... (healthy)  0.0.0.0:5434->5432/tcp
/var/run/postgresql:5432 - accepting connections
```

La configuración verificada desde `backend/` se reportó redactada como:

```text
postgresql+psycopg://roomforge:[REDACTED]@localhost:5434/roomforge
```

### Alembic y SQL

```text
Running upgrade  -> 0001, Create the global user table.
Running upgrade 0001 -> 0002, Create the session table.
0002 (head)
public tables: alembic_version, sesion, usuario_global
alembic_version: 0002
second upgrade head: no new migrations
```

La SQL posterior observó:

```text
baseline before HTTP: 0
final count for prueba@ejemplo.inv: 1
correo: prueba@ejemplo.inv
estado: activo; correo_verificado: f
argon2id_rows: 1
corta@ejemplo.inv rows: 0
```

El hash Argon2id completo está en el transcripto, conforme a la política de evidencia de la spec; no se registró el valor plaintext.

### HTTP real

```text
P1 201 {"id":"...","correo":"prueba@ejemplo.inv","estado":"activo","correo_verificado":false,"creado_en":"..."}
P2 409 {"detail":"Ya existe una cuenta con este correo"}
P3 422 ... sin password
P4 422 ... sin password
```

Los cuerpos crudos completos y los requests con password redactado están en `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt`.

### No-regresión

La primera corrida con `backend/.env` presente obtuvo `32 passed, 1 failed`: el test preexistente `test_create_app_fails_closed_when_environment_lacks_jwt_secret` no podía observar la ausencia del secreto porque Pydantic cargaba el `.env` local. Sin modificar código ni tests, se apartó temporalmente el `.env`, se ejecutó nuevamente desde `backend/` y se restauró inmediatamente después:

```text
33 passed, 3 warnings in 1.90s
```

La advertencia operacional queda registrada para verify: la suite existente exige que el archivo local no esté presente durante ese test específico.

## Archivos cambiados por este apply

- `infra/docker/compose.postgres.yml` — nuevo.
- `backend/.env` — local, ignorado; no forma parte del diff.
- `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt` — nuevo.
- `docs/scrum/sprint-1/02-proceso-por-hu.md` — cambios acotados a CP-001, narrativa de CP pendientes, reporte parcial y GAP-092.
- `openspec/changes/prueba-hu001/tasks.md` — checkboxes de implementación T1–T8.
- `openspec/changes/prueba-hu001/apply-progress.md` — este registro acumulativo.

No se modificaron `backend/app`, `backend/tests`, `.gitignore` ni `docs/diagramas/Diagrama1.eapx`. El working tree ya contenía cambios previos de PB-002, entre ellos `backend/tests/test_autenticacion.py`, `docs/diagramas/Diagrama1.eapx` y otros documentos de Sprint 1; se conservaron sin mezclarlos ni revertirlos.

## TDD Cycle Evidence

Strict TDD fue declarado activo en el contexto de esta fase. Estas tareas son operativas, de configuración, evidencia y documentación; NREQ-05 prohíbe modificar producción y tests, por lo que no se escribió un RED test artificial ni código GREEN. La suite existente se usó como safety net y la corrida final quedó verde tras aislar temporalmente el `.env` para respetar el escenario del test de configuración.

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T1 | N/A | Configuración estructural | N/A — archivo nuevo | N/A — sin producción/test nuevo | N/A | N/A — estructura sin lógica | N/A |
| T2 | N/A | Configuración local | N/A — archivo ignorado | N/A — restricción de entorno | N/A | N/A | N/A |
| T3 | N/A | Migración operacional | N/A — backend sin cambios | N/A — ejecución existente | N/A | N/A — comando idempotente | N/A |
| T4 | N/A | Integración HTTP/PG real | Suite existente: 32+1 inicial; final 33/33 | N/A — no se agregó endpoint | Evidencia real: 201/409/422/422 | Cuatro outcomes observados | N/A |
| T5 | N/A | Verificación SQL | Evidencia T4/T3 | N/A — no se agregó lógica | SQL real: 1 fila y Argon2id | Conteos/campos/hash | N/A |
| T6 | N/A | Evidencia documental | N/A — archivo nuevo | N/A | N/A — redacción auditada | N/A | N/A |
| T7 | N/A | Documento pasivo | N/A — cambio acotado | N/A | N/A — no producción | N/A | N/A |
| T8 | `backend/tests` existente | Suite completa | ✅ 33 passed tras apartar/restaurar `.env` | N/A — no se escribieron tests | ✅ 33 passed | ✅ escenarios existentes | N/A |

No se agregaron tests ni producción, en cumplimiento del alcance y NREQ-05.

## Riesgos y desviaciones

- **Puerto:** desviación controlada de 5433 a 5434 porque 5433 estaba ocupado; quedó reflejada en compose, `.env` y transcripto.
- **Suite con `.env`:** ejecutar pytest con el `.env` local presente produce un fallo preexistente del test de configuración; la corrida final verde se realizó apartando/restaurando el archivo, sin cambios de código/tests.
- **Volumen:** una primera subida provisional con el mapeo 5433 creó el volumen prefijado `roomforge_roomforge_pgdata`; se dejó preservado porque el flujo normal prohíbe `down -v`. El contenedor final usa el volumen requerido `roomforge_pgdata`.
- **Working tree:** hay cambios previos fuera de este slice. El diff global muestra `backend/tests/test_autenticacion.py` modificado antes de apply; este actor no lo editó. No se tocó el `.eapx`.
- **Parent lifecycle:** no se inició review, no se creó/validó receipt y no se ejecutó ningún gate de entrega, conforme a la frontera de ownership.

## Tareas restantes

Implementation: ninguna. Permanecen exactamente estas acciones parent, sin marcar:

- [ ] Start or reuse bounded review del slice implementado: contraste con spec REQ-01..08 — criterios de terminado de T1..T8, transcripto sin secretos (R6), ausencia de cambios en `backend/app`/`backend/tests` (REQ-08) y diff documental acotado (REQ-07 CA6/CA7). <!-- sdd-owner: parent -->
- [ ] Gate de entrega: consultar al usuario el momento del único commit aditivo (rama `feat/pruebas/cp001-postgres`, sin push; NREQ-07) antes de cualquier operación git; resolver `chain strategy: pending` solo si el usuario cambia el delivery strategy a una cadena. <!-- sdd-owner: parent -->

## Persistencia

- OpenSpec tasks actualizado y re-leído: T1–T8 visibles como `- [x]`; las dos filas parent siguen `- [ ]`.
- OpenSpec apply progress: `openspec/changes/prueba-hu001/apply-progress.md`.
- Engram apply progress: se actualizará en el topic `sdd/prueba-hu001/apply-progress`, fusionando el bloqueo histórico con este resultado real.
- No hubo commit, push, PR ni cambios en `docs/diagramas/Diagrama1.eapx`.
