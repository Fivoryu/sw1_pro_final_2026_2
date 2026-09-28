# F02-T6 — Verificación integrada

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
