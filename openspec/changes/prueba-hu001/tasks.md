# Tareas — Ejecución real de CP-001 contra PostgreSQL (HU-001)

- **Cambio:** `prueba-hu001` · **PB:** PB-001 · **HU:** HU-001 · **CP:** CP-001 · **Slice:** integración backend + PostgreSQL real + evidencia documental Sprint 1
- **Fuentes:** [spec.md](./spec.md) (REQ-01..08, NREQ-01..09) · [proposal.md](./proposal.md) · skill `documentacion-software` (formatos §2.1.5.1/§2.1.5.2/§2.1.5.3, GAP-CH2)
- **Design:** NO existe `sdd-design` para este cambio (decisión del orquestador: sin decisiones de arquitectura nuevas); las decisiones de ejecución —split de CP-001 en 4 pasos y reporte §2.1.5.3 parcial honesto— vienen de la propuesta.
- **Modo:** un solo actor de implementación; orden estricto T1→T2→T3→T4→T5→T6→T7→T8 (no paralelizable: cada tarea consume el resultado de la anterior).
- **Modo TDD:** no aplica RED→GREEN — el cambio NO escribe código ni tests (NREQ-05); la suite existente (33 tests, conteo verificado en `backend/tests`) es el guardián de no-regresión y debe quedar en verde sin modificaciones (REQ-08).

## Reglas de apply (usuario)

- NO ejecutar `git commit` / `git push` hasta aviso explícito del usuario (entrega `single-pr`: un único commit aditivo en rama `feat/pruebas/cp001-postgres`, sin push; NREQ-07).
- NO modificar `backend/app` ni `backend/tests` (REQ-08 / NREQ-05); el cambio es aditivo (infraestructura, configuración local, evidencia y documentación).
- Ejecutar Alembic y la API SOLO desde `backend/` (cwd correcto: `Settings` y Alembic leen `.env` relativo a `backend/`; ejecutar desde otro directorio produce falsas fallas — R3).
- No usar `docker compose down -v` en el flujo normal: destruye el volumen `roomforge_pgdata` y exige decisión explícita (NREQ-09).
- Evidencia SIN contraseñas (plaintext), `JWT_SECRET` ni credenciales completas de conexión; el hash `$argon2id$` completo SÍ puede mostrarse (política de evidencia de la spec).
- No se agregan migraciones nuevas: se ejecuta la cadena existente `0001_crear_usuario_global` → `0002_crear_sesion` (head `0002`; NREQ-04).
- Trazabilidad canónica documental: CP-001 = PB-001/HU-001 (la solicitud mencionó PB-002; NO se corrige el documento canónico).

## Review Workload Forecast

| Field | Value |
| ------- | ------- |
| Estimated changed lines | ~250–380 (compose ~45; `.env` 3; ejecución/salidas sin archivos de código; optional script de prueba ~80; transcripto ~120–180; doc Sprint 1 ~40–60) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | single PR aditivo (T1..T8 en un único commit; el usuario decide cuándo commitear) |
| Delivery strategy | single-pr |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

> Nota de forecast: no hay código backend ni tests nuevos; el grueso del volumen son evidencia (transcripto, documento de texto pasivo) y un compose mínimo. Total muy por debajo del presupuesto de 400 líneas, por lo que NO se recomienda chain de PRs. `chain strategy: pending` significa sencillamente que no hay cadena que planificar; la decisión de commit queda en el gate de entrega (acción de parent).

---

## T1 — Compose mínimo de PostgreSQL (`infra/docker/compose.postgres.yml`)

- [x] T1 Crear el directorio `infra/docker/` y `infra/docker/compose.postgres.yml` con: top-level `name: roomforge` (project name → contenedor `roomforge-postgres-1`), servicio `postgres` con `image: postgres:16-alpine`, `ports: "5434:5432"` (fallback autorizado porque 5433 estaba ocupado), entorno `POSTGRES_DB=roomforge`, `POSTGRES_USER=roomforge`, `POSTGRES_PASSWORD=valor-dev-local` (valor dev-local, no secreto), volumen nombrado `roomforge_pgdata:/var/lib/postgresql/data`, healthcheck `pg_isready -U roomforge -d roomforge` (interval 5s, timeout 5s, retries 10, start_period 5s) y `restart: unless-stopped`. Verificar ANTES del `up` que el puerto host `5433` está libre (`netstat -ano | findstr :5433` o equivalente); si está ocupado, usar `5434` y dejar el puerto real reflejado en `DATABASE_URL` (T2), en la evidencia y en esta tarea (R1). Ejecutar `docker compose -f infra/docker/compose.postgres.yml up -d` y confirmar estado. <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-01):** `docker compose -f infra/docker/compose.postgres.yml ps` muestra `roomforge-postgres-1` `running (healthy)`; `docker volume ls` incluye `roomforge_pgdata`; `docker exec roomforge-postgres-1 pg_isready -U roomforge -d roomforge` responde "accepting connections"; el archivo declara imagen `postgres:16-alpine`, mapeo `5434:5432` (fallback documentado por ocupación de 5433), volumen nombrado y healthcheck `pg_isready`. `docker compose down` (sin `-v`) preserva el volumen.
  - **Archivos objetivo:** `infra/docker/compose.postgres.yml` (nuevo).
  - **Dependencias:** ninguna (primera tarea).
  - **Estimación:** S (~1 h).

## T2 — Configuración local `backend/.env` gitignored

- [x] T2 Crear `backend/.env` (local, NO versionado) con exactamente: `DATABASE_URL=postgresql+psycopg://roomforge:valor-dev-local@localhost:5434/roomforge` (el puerto DEBE coincidir con el usado en T1), `JWT_SECRET=valor-dev-local` y `APP_ENV=development`. Verificar que `.gitignore` cubre `.env` y `.env.*` (HOY ya lo cubre, bloque `# Env` con `!.env.example`; si el estado cambió, agregar la entrada) y confirmarlo con `git check-ignore backend/.env`. NO exponer el password en el transcripto; solo verificar que la carga de configuración funciona. <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-02):** `git check-ignore backend/.env` responde el path (ignorado); `git status` NO muestra `backend/.env`; desde `backend/` con el venv, `python -c "from app.core.config import get_settings; print(get_settings().database_url)"` imprime el URL real `postgresql+psycopg://...@localhost:5434/roomforge` (sin secretos en la salida guardada); la API de T4 resuelve configuración desde este archivo y `create_app()` no falla por falta de `JWT_SECRET`.
  - **Archivos objetivo:** `backend/.env` (nuevo, ignorado) · `.gitignore` (solo si el estado actual dejara de cubrir `.env`).
  - **Dependencias:** T1.
  - **Estimación:** S (~0.5 h).

## T3 — Migraciones Alembic reales (`alembic upgrade head`)

- [x] T3 Desde `backend/` con el venv del proyecto, ejecutar `python -m alembic upgrade head` (aplica la cadena existente `0001` → `0002`; NO se crean migraciones nuevas) y capturar la salida completa. Luego `python -m alembic current` → debe reportar `0002 (head)`. Verificar tablas contra PostgreSQL real: `docker exec roomforge-postgres-1 psql -U roomforge -d roomforge -c "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;"` → contiene `usuario_global`, `sesion` y `alembic_version`; y `docker exec roomforge-postgres-1 psql -U roomforge -d roomforge -c "SELECT version_num FROM alembic_version;"` → `0002`. Re-ejecutar `python -m alembic upgrade head` y confirmar idempotencia (sin nuevas operaciones). Todas las salidas se guardan para T6. <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-03):** `upgrade head` finaliza sin error con salida capturada; `current` = `0002`; existen `usuario_global`, `sesion` y `alembic_version`; `alembic_version` contiene exactamente `0002`; la re-ejecución es idempotente.
  - **Archivos objetivo:** ninguno (solo ejecución + salidas capturadas para el transcripto).
  - **Dependencias:** T1, T2.
  - **Estimación:** S (~1 h).

## T4 — Ejecución real de los cuatro outcomes de CP-001 (API + PostgreSQL)

- [x] T4 Arrancar la API real contra PostgreSQL y ejecutar los cuatro outcomes de CP-001. Vía preferida (spec): desde `backend/` con el venv, `python -m uvicorn app.main:app --port 8000` y solicitudes HTTP reales con `httpx`/curl contra `http://localhost:8000/api/v1/auth/registro`. Alternativa aceptable solo si uvicorn+httpx resulta inviable: script Python con TestClient SIN `dependency_overrides` (cadena real `get_db` contra el `.env`). Casos: (a) registro válido con correo controlado `prueba@ejemplo.inv` y password de 8+ caracteres → `201` con `id` UUID, `correo` normalizado, `estado: "activo"`, `correo_verificado: false` y `creado_en`, SIN `hash_password` ni password; (b) mismo correo y variante `Prueba@Ejemplo.INV` → `409` con el mensaje EXACTO `Ya existe una cuenta con este correo`; (c) correo inválido `no-es-correo` → `422`; (d) password de 7 caracteres → `422`. Verificar que los cuerpos `422` NO contienen la cadena `password` (sanitización esperada). Controlar el estado inicial (R4): baseline del correo de prueba en 0 filas ANTES de ejecutar (conteo SQL previo). Guardar requests (password redactado), status y cuerpos crudos para T6. <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-04):** 201 con los campos públicos esperados; 409 (incluida la variante con mayúsculas) con el mensaje exacto y sin incremento de filas; 422 en correo inválido y en password corta sin creación de filas; cuerpos 422 sin la cadena `password`; baseline identificado pre-ejecución.
  - **Archivos objetivo:** ninguno en el repositorio (script opcional temporal fuera de `backend/app` y `backend/tests`, o consumido desde `python -c`; no se versiona).
  - **Dependencias:** T3.
  - **Estimación:** M (~2–3 h).

## T5 — Verificación SQL en PostgreSQL

- [x] T5 Ejecutar las consultas SQL directas vía `docker exec roomforge-postgres-1 psql -U roomforge -d roomforge -c "..."` y capturar las salidas: (1) baseline: `SELECT count(*) FROM usuario_global WHERE correo = 'prueba@ejemplo.inv';` → `0`; (2) post-ejecución: count → exactamente `1`; (3) `SELECT correo FROM usuario_global WHERE correo = 'prueba@ejemplo.inv';` → en minúsculas; (4) `SELECT estado, correo_verificado FROM usuario_global WHERE correo = 'prueba@ejemplo.inv';` → `activo`, `false`; (5) `SELECT hash_password FROM usuario_global WHERE correo = 'prueba@ejemplo.inv';` → prefijo `$argon2id$` y valor ≠ plaintext; (6) conteo final tras los intentos 409/422 → sigue en `1`. El hash Argon2id completo SÍ se captura como evidencia (no es secreto reutilizable). <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-05):** 1 sola fila; correo minúsculas; `estado='activo'`; `correo_verificado=false`; hash con prefijo `$argon2id$`; el conteo no cambió tras duplicados/validaciones; salidas capturadas para T6.
  - **Archivos objetivo:** ninguno (solo salidas SQL capturadas).
  - **Dependencias:** T4.
  - **Estimación:** S (~0.75 h).

## T6 — Evidencia transcripta (`docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt`)

- [x] T6 Crear el directorio `docs/scrum/sprint-1/evidencia/` y el archivo `cp001-registro-transcripto.txt` con secciones que permitan reconstruir la ejecución sin ambigüedad: (1) entorno (fecha, Docker/PG versión, puerto usado, cwd `backend/`); (2) migraciones: salida de `upgrade head`, `current` y consulta de tablas/`alembic_version`; (3) requests/responses de los cuatro outcomes con URL, status y cuerpo completos y password redactado; (4) consultas SQL con salidas (incluido el hash `$argon2id$` completo). Redacción estricta: sin password plaintext, sin `JWT_SECRET`, sin credenciales completas de conexión. Auditoría final con `grep`: el password de prueba NO aparece (0 aciertos), `JWT_SECRET` NO aparece (0 aciertos), `$argon2id$` aparece al menos una vez (≥1 acierto). <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-06):** archivo en la ruta acordada con las cuatro secciones; greps de auditoría documentados (0 passwords, 0 `JWT_SECRET`, ≥1 `$argon2id$`); reconstrucción posible paso a paso.
  - **Archivos objetivo:** `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt` (nuevo).
  - **Dependencias:** T3, T4, T5.
  - **Estimación:** S (~1 h).

## T7 — Actualización del documento Sprint 1 (`02-proceso-por-hu.md`)

- [x] T7 Actualizar `docs/scrum/sprint-1/02-proceso-por-hu.md` SOLO en estos puntos: (1) **§2.1.5.1**: fila CP-001 → `executed`, conservando `PB-001`, `HU-001`, plataforma `App cliente / Backend` con aclaración de que esta ejecución cubre la superficie backend y `GAP-073`; ajustar la frase intro de §2.1.5.1 ("Los casos no fueron ejecutados... (GAP-087)") para reflejar que CP-001 ya tiene evidencia y que CP-002..CP-013 siguen pendientes; (2) **§2.1.5.2 caso CP-001**: cuatro pasos con `executed` y resultados por outcome (P1 registro válido → 201, P2 duplicado → 409, P3 correo inválido → 422, P4 contraseña corta → 422), nota explícita de que P3 y P4 desdoblan el paso 3 original conservando la numeración del modelo, `Responsable: GAP-073`, `Resultado de la prueba: Satisfactorio` y `Adjunto: evidencia/cp001-registro-transcripto.txt` (ruta relativa al archivo); ajustar la frase intro de §2.1.5.2 solo si queda obsoleta ("todos permanecen `not executed` (GAP-087)" → CP-002..CP-013); (3) **§2.1.5.3 reporte**: llenado parcial honesto — total HU probadas `1`, casos ejecutados `1`, satisfactorios `1`, fallidos `0`, cumplimiento `≈7,7 %`, estado general del Sprint 1 `en ejecución`, con nota explícita de que CP-002..CP-013 siguen pendientes y SIN declarar aprobación global del sprint; (4) **intro de §2.1** (línea 5): "Las pruebas CP-001..CP-013 no se declaran ejecutadas (GAP-087)" → "CP-002..CP-013" (CP-001 ya no es una prueba sin ejecutar); (5) **§2.1.2.3 y §2.1.4**: menciones de GAP-092 → cobertura parcial con evidencia (migraciones `0001` y `0002` ejecutadas contra PostgreSQL real; quedan 12 tablas/migraciones del Sprint 1 pendientes). NO tocar CP-002..CP-013 (filas y casos intactos), ni el `.eapx`, ni otras secciones. <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-07):** fila CP-001 `executed` con PB-001/HU-001/plataforma aclarada/GAP-073; CP-002..CP-013 `not executed` sin cambios en §2.1.5.1 y §2.1.5.2; caso CP-001 con 4 pasos `executed`, nota de desdoblamiento, `Satisfactorio` y Adjunto con la ruta del transcripto; reporte §2.1.5.3 con 1/1/1/0/≈7,7 %/`en ejecución` y nota de pendientes; frase intro (§2.1) con "CP-002..CP-013"; §2.1.2.3 y §2.1.4 con GAP-092 parcial (0001+0002 ejecutadas, 12 pendientes). Homologar con `git diff` acotado a estos puntos.
  - **Archivos objetivo:** `docs/scrum/sprint-1/02-proceso-por-hu.md`.
  - **Dependencias:** T6 (el Adjunto debe apuntar a evidencia real existente).
  - **Estimación:** M (~1.5 h).

## T8 — No-regresión y verificación del alcance aditivo

- [x] T8 Desde `backend/` con el venv del proyecto, ejecutar `.venv/Scripts/python.exe -m pytest tests -q` (o `python -m pytest tests -q`) → suite completa en verde (33 tests actuales, 0 failed) SIN ninguna modificación de `backend/app` ni `backend/tests`. Listar el alcance del cambio con `git status` y `git diff --name-status` para confirmar: solo `infra/docker/compose.postgres.yml` (nuevo), `docs/scrum/sprint-1/evidencia/cp001-registro-transcripto.txt` (nuevo), `docs/scrum/sprint-1/02-proceso-por-hu.md` (modificado), `.env` local (ignorado, ausente del diff); cero diferencias en código backend y en tests. Guardar la salida de pytest como evidencia. <!-- sdd-owner: implementation -->
  - **Criterio de terminado (REQ-08):** pytest 33 passed / 0 failed; suite corre sin servicios externos (los fakes no dependen de PostgreSQL); `git diff --name-status` sin paths bajo `backend/app` ni `backend/tests` y sin `backend/.env`.
  - **Archivos objetivo:** ninguno (solo verificación).
  - **Dependencias:** T1..T7 (suite completa).
  - **Estimación:** S (~0.5 h).

---

## Acciones de orquestador (post-apply; NO las ejecuta el actor de implementación)

- [ ] Start or reuse bounded review del slice implementado: contraste con spec REQ-01..08 — criterios de terminado de T1..T8, transcripto sin secretos (R6), ausencia de cambios en `backend/app`/`backend/tests` (REQ-08) y diff documental acotado (REQ-07 CA6/CA7). <!-- sdd-owner: parent -->
- [ ] Gate de entrega: consultar al usuario el momento del único commit aditivo (rama `feat/pruebas/cp001-postgres`, sin push; NREQ-07) antes de cualquier operación git; resolver `chain strategy: pending` solo si el usuario cambia el delivery strategy a una cadena. <!-- sdd-owner: parent -->

## Trazabilidad rápida

| Tarea | REQ | Fuente principal |
| ------- | ----- | ------------------ |
| T1 Compose PostgreSQL | REQ-01 | proposal objetivo 1; PB-048 (parcial); R1/R5 |
| T2 `.env` gitignored | REQ-02 | proposal objetivo 2; S0-10; R3/R6 |
| T3 Migraciones Alembic | REQ-03 | proposal objetivo 3, regla 8; GAP-092 (parcial) |
| T4 Cuatro outcomes CP-001 | REQ-04 | proposal objetivo 4, reglas 1–4/7; HU-001 CA1–CA3; R4 |
| T5 Verificación SQL | REQ-05 | proposal objetivo 5, reglas 2/5/6; HU-001 CA2/CA4 |
| T6 Transcripto | REQ-06 | proposal objetivo 6; R6; skill documentacion-software (evidencia real) |
| T7 Documento Sprint 1 | REQ-07 | proposal objetivo 7, decisiones 1–2; skill §2.1.5.1/§2.1.5.2/§2.1.5.3; GAP-087/092 |
| T8 No-regresión | REQ-08 | proposal alcance excluido, criterio de éxito 1; R2 |
