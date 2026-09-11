## Remediación posterior a TRIANGULATE

### Corrección de calidad

- La evidencia fallida original de TRIANGULATE fue `sha256:120f88c9f7e5721c8f590a53dfbc4472cde1d26415acd0c3cc75a96f598712e4`.
- La remediación preservada agotó el intento por timeout con un delta de 277 líneas; después, un maintainer autorizó un presupuesto de corrección separado.
- La primera validación fresca registró pytest `77 passed, 3 warnings`, Pyright `0`, Ruff `49 errors` y Alembic bloqueado únicamente por ausencia de `DATABASE_URL`. Evidencia: `sha256:630474d378db8f7642f4d251ea20fdb4d644c04f9f295e4ceae5b0565a8c184f`.
- La corrección mecánica de Ruff terminó dentro del alcance autorizado de corrección de 400 líneas. La evidencia final registró pytest `77 passed, 3 warnings`, Ruff `0`, Pyright `0` y `git diff --check` PASS. Evidencia: `sha256:2549b9067a417eac8a1f6cf1e6959b1ce4b3dcb7f70c106827a9c4123e87202f`.

### Migración y regresión

- La validación fresca de base/migración confirmó Alembic `0005 (head)` y `upgrade head` con exit 0/no-op; pytest, Ruff, Pyright y `git diff --check` quedaron verdes. Esto no aporta evidencia conductual de PostgreSQL para CP-004. Evidencia: `sha256:8b82d1907c28898b70e7c04e4a01e8eeb2789eb2ed53f3333ac3a7d0ad501272`.
- La instancia local persistente de PostgreSQL quedó en `0005 (head)` por la comprobación de migración anterior; no se ejecutó downgrade.

### Intentos de base descartable

- Un intento autorizado por maintainer creó, migró y eliminó una base temporal, pero se detuvo antes de los escenarios por el orden de FKs del fixture. Evidencia: `sha256:c7631958d27a93490c8a227b955829376102bb50d3f08771195b804fe9e4827a`.
- Un reintento se detuvo antes de crear la base porque el actor no configuró `DATABASE_URL`. Evidencia: `sha256:d226f398515256a8680cf94a21b97c08be9f8e86383b7eb4db7eac9baa3904a8`.
- El intento final del parent se detuvo antes de ejecutar por un `SyntaxError` en un heredoc inline; no se creó ninguna base. Evidencia: `sha256:9b601baeb956c7d404b1d3b16bdac427fa8885a19f2981cfbe0cacdc52b8659a`.

### Estado actual

- `CP-004`, `CP-004.1`, `CP-004.2` y `CP-004.3` permanecen `not executed/unverified`. No se afirma evidencia de concurrencia, locks, replay, conflictos ni rollback en PostgreSQL.
- Los tests HTTP existentes con fakes/SQLite son evidencia separada y no sustituyen la ejecución conductual de PostgreSQL.
- El runtime nativo está bloqueado a la espera de una decisión del maintainer después del último work unit fallido de CP; no se fabrica un next token.
- No hubo commits, pushes ni operaciones de delivery.

### Presupuesto y accounting

- El forecast original de implementación fue de 400 líneas. Tras el timeout con delta de 277 líneas, la corrección mecánica de Ruff usó un presupuesto separado autorizado de 400 líneas.
- El accounting nativo reportó `239` líneas modificadas para ese work unit; el reporte de diff local del actor indicó `315` líneas de corrección. Son mediciones del mismo work unit con orígenes distintos, no un nuevo límite.
- El accounting acumulado de lifetime fue de `913` líneas modificadas a través de los work units del runtime. Este total no equivale al accounting nativo de `239` líneas ni al forecast original de 400.
- No ocurrieron cambios de código fuente durante los intentos de verificación.

### Filas pendientes

- `T-TRI-03` queda marcado porque se ejecutaron los checks de calidad y la comprobación de Alembic head; `T-TRI-01`, `T-TRI-02` y `T-TRI-04` permanecen sin marcar por falta de evidencia completa.
- `REFACTOR` no está completo.
- La ejecución de los escenarios conductuales de PostgreSQL de `CP-004` sigue pendiente en el corte documental anterior y queda actualizada en la sección siguiente.

## CP-004 — cierre de evidencia PostgreSQL y migración

- La evidencia parent `sha256:9d2b44780ac326b5f22982350474e5d9473e7ff1f3fc59e7754e3c348ac4783f` confirmó en PostgreSQL 16 disposable el bootstrap idempotente, la activación concurrente con un solo ganador y trial exacto de 336 horas, la conversión concurrente con un solo evento, replay/conflicto, rechazo de segunda key, rollback atómico y webhook HMAC mensual.
- La evidencia disposable de migración `sha256:eacf82d375fa76332ccc9eae6114c6326330f5d8ad0650ef78f59eb5fb926fcd` confirmó upgrade a `0005`, downgrade vacío a `0004`, re-upgrade a `0005` y bloqueo cerrado del downgrade con datos HU-005. La base temporal fue eliminada; no se degradó la base persistente.
- `CP-004` y `CP-004.1/.2/.3` quedan respaldados por evidencia separada fake/SQLite, PostgreSQL, migración y calidad. `T-REF-01` y `T-REF-02` permanecen pendientes; no se declara REFACTOR.
- La corrección nativa conserva `239` líneas, el lifetime acumulado `913` y el forecast original `400`; los harnesses no modificaron código fuente, no hubo commits/pushes/delivery y no quedaron procesos huérfanos.
