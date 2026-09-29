# F02-T6 — Verificación integrada

## Snapshot actual — `e7d18f9682058dff8749aeb22ce1dea2d0126796`

**Fecha:** 2026-09-28 (reejecución). Este bloque es el estado vigente; el informe anterior se conserva sin reescribir como snapshot histórico al final del archivo.

**Árbol verificado:** `feat/f02-base-ux-automation` en `e7d18f9682058dff8749aeb22ce1dea2d0126796`. El worktree estuvo limpio antes y después de las corridas (sin cambios sin confirmar, sin archivos sin seguimiento).

**Resultado:** reejecutada como verificación local con limitaciones declaradas; no se publicó y no autoriza publicación.

### Alcance y seguridad

Se verificaron los runners locales de backend, panel, app cliente y **app de captura** (esta última ya ejecutable, antes ausente). No se cambió código ni configuración para verificar. Para aislar PostgreSQL, el proceso de `pytest` eliminó `ROOMFORGE_R6_DATABASE_URL`, fijó `DATABASE_URL=sqlite+pysqlite:///:memory:`, deshabilitó bytecode y la caché de pytest. No se ejecutaron PostgreSQL, Alembic, migraciones, Docker, Compose, Playwright E2E ni builds APK, y no se hizo push ni PR. La base, el volumen y el contenedor pausados del diagnóstico T3b siguen preservados.

### Resultados

| Área | Estado | Evidencia |
|---|---|---|
| Backend — suite | **PASS** | Python 3.12.13, pytest 9.1.1, entorno virtual existente. `python -m pytest tests -q -p no:cacheprovider`: **135 passed, 2 skipped, 4 warnings**. Los 2 skips son los tests R6/PostgreSQL de `test_staff_identity_migration.py` y `test_staff_identity_postgres.py`; no hubo conexión a PostgreSQL. |
| Backend — lint | **PASS** | Ruff 0.16.4: `ruff check --no-cache app tests` → `All checks passed!`. |
| Backend — tipos | **PASS** | Pyright 1.1.411: `pyright app tests` → **0 errors, 0 warnings, 0 informations**. El ejecutable avisó de una versión más nueva (1.1.414); no se instaló. |
| Panel — tests | **PASS** | Node v22.23.0, Vitest 3.2.7: `npm run test` → **52 tests en 6 archivos**. No se ejecutó `npm ci`. |
| Panel — build | **PASS** | `npm run build` con Vite 6.4.3 y TypeScript: build correcto (35 módulos, `dist/index.html` + `assets/`). El `dist/` generado no se limpió. |
| Cliente Flutter | **PASS** | SHA-256 comparados entre el worktree y el mirror autorizado: `lib/main.dart` `3132384798…4146`, `test/widget_test.dart` `7be9d75e…0a57`. Flutter 3.41.8 / Dart 3.11.5: **11 tests PASS**, `flutter analyze --no-pub` sin issues, `dart format --output=none --set-exit-if-changed` sin cambios. |
| Captura Flutter | **PASS** | SHA-256: `lib/main.dart` `59d9624e…fd26c`, `test/widget_test.dart` `65c0738f…8ffe`. Flutter 3.41.8 / Dart 3.11.5: **15 tests PASS**, `flutter analyze --no-pub` sin issues, `dart format --output=none --set-exit-if-changed` sin cambios. Antes de la corrida se guardaron hashes y `baseline.tar` del mirror; después se restauró y el `diff` de hashes quedó vacío (restauración byte-idéntica), con `build/` preservado. |
| Lockfiles y scaffolding | **PASS** | No existe `pubspec.lock` rastreado (`git ls-files` = 0) ni presente en `apps/`; `apps/captura_mobile` sigue sin `android/`, `ios/` ni `.dart_tool`. El único directorio `ios/` de `apps/` pertenece a la app cliente y es preexistente. |
| PostgreSQL / T3b | **BLOCKED / EXCLUIDO** | La instrucción vigente prohíbe el retest PostgreSQL y toda acción de Docker/Alembic. Los 2 tests R6 se omitieron de forma explícita mediante el entorno saneado. |
| Playwright E2E | **SKIP** | `npm run test:e2e` levanta servicios y Docker/PostgreSQL; queda excluido por el límite de T3b. |
| GitHub Actions | **PASS parcial / BLOCKED** | PyYAML 6.0.3 parseó `.github/workflows/ci.yml` completo: 4 jobs (`backend`, `panel`, `customer-flutter`, `capture-flutter`), permiso `contents: read` y `flutter-version: 3.41.8` en ambos jobs Flutter. `actionlint` no está instalado, así que la semántica de GitHub sigue sin validar, y **el workflow no se ejecutó en GitHub Actions**: los cuatro comandos del job de captura se corrieron solo localmente en el mirror. |
| Presupuesto de commits | **PASS** | En el rango local `origin/main..e7d18f9` (sin fetch) hay **32 commits**; ninguno alcanza 400 líneas cambiadas. El máximo es `a6d899c` con 395; le siguen `c1c4b99` (392) y `5d0cc8a` (393). La última unidad, `e7d18f9`, sumó 44. |
| Estado Git | **PASS** | Tras los runners el worktree seguía limpio en `e7d18f9`; sin push ni PR. |

### Unidades añadidas desde el snapshot histórico

| Commit | + | − | Total |
|---|---:|---:|---:|
| `a6d899c` | 390 | 5 | 395 |
| `2251e2d` | 11 | 9 | 20 |
| `c1c4b99` | 355 | 37 | 392 |
| `23f4b03` | 11 | 5 | 16 |
| `fedeccc` | 259 | 15 | 274 |
| `e495575` | 273 | 22 | 295 |
| `e7d18f9` | 37 | 7 | 44 |

Ninguna excede el límite de 400 líneas.

### Advertencias de pytest

Se observaron cuatro warnings, sin tests fallidos: dos avisos deprecados de Starlette/`httpx` sobre `testclient` y sobre `cookies=` por petición, y dos `SAWarning` por reflexión omitida del índice basado en expresión `uq_staff_invitation_pending_normalized_email`.

### Límites que se mantienen

- La revisión nativa de las unidades de captura quedó cerrada: **T4f** `review-bfee92cef5c28da1` y, tras reofrecerse cada slot, **T4g-1** `review-140dcc79298cbf8a`, **T4g-2** `review-ff2b2911e2e55ea7` y **T4h** `review-dc87edad58b003c8` (tier alto, cuatro lentes), cada una sobre su commit exacto contra su padre y no sobre la rama acumulada; todas **aprobadas y acknowledged** con autoridad quemada y solo hallazgos informativos (`R3-001`, `R2-stale-status`). El commit de evidencia `b3b56d5` es solo documental y no tuvo revisión nativa propia, como corresponde a un cambio pasivo de documentación. La verificación de este informe es técnica y local y no sustituye la decisión de publicación.
- No se verificó runtime Android, emulador, cámara, AR, red ni persistencia reales; el prototipo de captura declara todas las simulaciones como tales.
- No se validó cobertura numérica ni semántica de GitHub Actions, y el workflow sigue sin ejecutarse en GitHub.
- Esta verificación no autoriza publicación: no hubo push, PR ni despliegue.

## Snapshot histórico — `e7452c5a426f9aa6f4928ce1c1663aeb36a6acf6`

**Fecha:** 2026-09-28

**Árbol verificado:** `feat/f02-base-ux-automation` en `e7452c5a426f9aa6f4928ce1c1663aeb36a6acf6` (HEAD esperado antes de registrar este informe).

**Resultado:** completada con limitaciones declaradas; no se publicó.

## Alcance y seguridad

Se verificaron los runners locales de backend, panel y app cliente. No se cambió código ni configuración. Antes y después de las pruebas, el worktree F02 estuvo limpio y en el mismo HEAD. No se instalaron dependencias ni se modificaron bases de datos.

Para aislar PostgreSQL, el proceso de `pytest` eliminó `ROOMFORGE_R6_DATABASE_URL`, fijó `DATABASE_URL=sqlite+pysqlite:///:memory:` y deshabilitó bytecode. Así, los tests R6 que requieren una base PostgreSQL quedaron omitidos. No se ejecutaron PostgreSQL, Alembic, migraciones, Docker, Compose, Playwright E2E, APK build, push ni PR. Se preservaron la base, el volumen y el contenedor pausados del diagnóstico T3b.

## Resultados

| Área | Estado | Evidencia |
|---|---|---|
| Backend — suite | **PASS** | Python 3.12.13, entorno virtual existente. `python -m pytest tests -q`: 132 passed, 2 skipped, 4 warnings. Los skips corresponden a los tests R6/PostgreSQL de `test_staff_identity_migration.py` y `test_staff_identity_postgres.py`; no se conectaron a PostgreSQL. |
| Backend — lint | **PASS** | Ruff 0.16.4: `ruff check --no-cache app tests` — `All checks passed!`. |
| Backend — tipos | **PASS** | `pyright app tests` — 0 errors, warnings o informations. El ejecutable reportó actualización disponible; no se instaló. |
| Panel — tests | **PASS** | Node v22.23.0; `npm run test`: Vitest 3.2.7, 52 tests en 6 archivos. No se ejecutó `npm ci`. |
| Panel — build | **PASS** | `npm run build`: TypeScript y Vite 6.4.3 terminaron correctamente. Se generó `panel/staff-shell/dist/`; no se limpió. |
| Cliente Flutter | **PASS** | Se compararon SHA-256 de `lib/main.dart`, `test/widget_test.dart`, `pubspec.yaml` y `analysis_options.yaml` entre el worktree y el mirror autorizado `D:\tmp\f02-t4d-validation`; los cuatro coincidieron. Flutter 3.41.8 / Dart 3.11.5: 11 tests PASS, `flutter analyze --no-pub` sin issues y `dart format --output=none --set-exit-if-changed ...` sin cambios. |
| Lockfile Flutter | **PASS** | `apps/cliente_mobile/pubspec.lock` no existe en el worktree; no se creó. El mirror conserva su lockfile local. |
| App de captura Android | **SKIP** | `apps/captura_mobile` no tiene `pubspec.yaml` ni directorio `test/`; no hay runner ejecutable. |
| PostgreSQL/T3b | **BLOCKED / EXCLUIDO** | La instrucción vigente prohíbe el retest PostgreSQL y cualquier acción de Docker/Alembic. Los dos tests R6 se omitieron de forma explícita mediante el entorno saneado. El diagnóstico T3b permanece pausado. |
| Playwright E2E | **SKIP** | `npm run test:e2e` levanta servicios y Docker/PostgreSQL; queda excluido por el límite de T3b. |
| GitHub Actions | **PASS parcial / BLOCKED** | PyYAML 6.0.3 pudo parsear `.github/workflows/ci.yml`. `actionlint` no está disponible; el parseo no valida semántica de GitHub Actions. No hubo ejecución en GitHub ni publicación. |
| Presupuesto y estado Git | **PASS** | En el rango local `origin/main..e7452c5` (sin fetch) hay 21 commits; todos suman menos de 400 líneas, máximo 395 (`eeda6e7`). Los conteos del tracker concuerdan. Tras los runners, el worktree estaba limpio en `e7452c5`; sin push/PR. |

### Advertencias de pytest

Se observaron cuatro warnings, sin tests fallidos:

- Una advertencia deprecada de Starlette sobre el uso de `httpx` con `starlette.testclient` y la recomendación de instalar `httpx2`.
- Una advertencia deprecada sobre pasar `cookies=...` por petición en lugar de configurarlas en la instancia del cliente.
- Dos `SAWarning` por reflexión omitida del índice basado en expresión `uq_staff_invitation_pending_normalized_email`.

### Presupuesto de commits local

Conteo por suma de adiciones y eliminaciones en el rango local `origin/main..e7452c5`; no se consultó el remoto:

| Commit | + | − | Total |
|---|---:|---:|---:|
| `a156a53` | 115 | 0 | 115 |
| `66dc6fd` | 5 | 5 | 10 |
| `5d0cc8a` | 376 | 17 | 393 |
| `8dd7057` | 5 | 5 | 10 |
| `eeda6e7` | 361 | 34 | 395 |
| `447c8ec` | 269 | 7 | 276 |
| `82abcee` | 5 | 5 | 10 |
| `0952252` | 76 | 2 | 78 |
| `c38ac84` | 5 | 5 | 10 |
| `c7849b3` | 19 | 15 | 34 |
| `b154888` | 129 | 0 | 129 |
| `49a853d` | 279 | 73 | 352 |
| `ce5028e` | 253 | 83 | 336 |
| `a5223a6` | 49 | 4 | 53 |
| `8002648` | 169 | 2 | 171 |
| `3fcc5c3` | 4 | 4 | 8 |
| `a7a8572` | 169 | 12 | 181 |
| `3a30a52` | 6 | 5 | 11 |
| `c7cf98b` | 4 | 2 | 6 |
| `67a3052` | 239 | 6 | 245 |
| `e7452c5` | 9 | 8 | 17 |

Ningún commit del rango auditado excede el límite de 400 líneas. El máximo, `eeda6e7`, suma 395.

## Notas operativas

Dos intentos auxiliares iniciales fallaron antes de ejecutar verificaciones: uno usó una ruta de mirror incorrecta y otro tuvo un error de quoting (`SyntaxError`) al preparar la lectura YAML. Ambos se corrigieron; no cambiaron archivos ni alteraron los resultados finales. No se consultó ni imprimió ninguna URL de base de datos o secreto.

## Cierre

F02-T6 queda completada como verificación local con las limitaciones anteriores explícitas. El proyecto F02 **no** se declara terminado: F02-T4 continúa en curso hasta que exista un prototipo verificable de captura Android; T3b permanece pausada hasta nueva autorización PostgreSQL. La verificación integrada no autoriza publicación.

## Publicación (2026-09-29)

- **PR #6** mergeado a `main` el **2026-09-29T16:01:13Z** como `98ce894b97356e5c1808f8f9be0814495ad30697`. `origin/main` ya contiene todos los commits de F02 verificados en este informe.
- **Primera ejecución real de GitHub Actions** del workflow de F02 (run `36594625038`, evento `push` a `main`): **captura ✅, cliente ✅, panel ✅** y backend ❌ **solo** en `pyright app tests` (pytest y ruff en verde también en CI). Los 15 errores de pyright y los dos revision ids de 35 caracteres eran defectos heredados de la línea catálogo/reservas, y se corrigieron en el PR de seguimiento: `odd/tasks/main-inherited-ci-defects.md`.
- **Límites que siguen vigentes:** PostgreSQL/E2E no se ejecutaron (autorización T3b), el runtime Android/cámara real no se verifica por diseño, y el merge no recibió aprobación nativa propia: la autoridad quemada corresponde a las unidades de trabajo revisadas.
