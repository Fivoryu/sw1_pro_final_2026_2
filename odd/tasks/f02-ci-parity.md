# F02-T5 — CI inicial y paridad local

## Objetivo

Añadir CI de pull request para las superficies F02 que ya tienen código ejecutable y pruebas, conservando comandos locales equivalentes y evitando secretos o servicios compartidos.

## Estado inicial

- Worktree: `D:/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final-f02-base-ux-automation-wt`.
- Rama: `feat/f02-base-ux-automation`; base de tarea `a5223a6`, worktree limpio y 14 commits ahead de `origin/main`.
- No existe `.github/workflows/` en la raíz.
- Backend: Python `>=3.11`; tests, Ruff y Pyright disponibles. Sin `ROOMFORGE_R6_DATABASE_URL`, la suite ordinaria usa fakes/SQLite y no necesita credenciales PostgreSQL.
- Panel: lockfile npm presente; `npm ci`, `npm run test` y `npm run build` disponibles.
- Cliente: Flutter SDK Dart constraint `^3.11.5`; `flutter test`, `flutter analyze` y build APK disponibles. No versionar `pubspec.lock` dentro de esta unidad.
- Captura móvil: no tiene manifest Flutter ni código ejecutable; excluir hasta que exista una superficie comprobable.

## Alcance y límites

- Añadir un workflow mínimo con jobs independientes: backend, panel y cliente móvil.
- Mantener alineación con comandos locales documentados; versiones: Python 3.11, Node 22 LTS y Flutter 3.41.8 (versión verificada localmente para Dart 3.11.5).
- Ejecutar en `pull_request`, `push` a `main` y `workflow_dispatch`; permisos mínimos `contents: read`.
- No usar secretos, `pull_request_target`, despliegues ni permisos de escritura. No configurar servicios compartidos.
- Excluir E2E del panel basado en Docker/PostgreSQL y cualquier migración/servicio PostgreSQL. Ese camino queda fuera de la CI inicial mientras PostgreSQL/Docker siga sujeto a autorización independiente.
- Documentar comandos locales, versiones y límites; actualizar el tracker F02 con hashes y evidencia.
- No tocar el checkout raíz, migraciones, aplicaciones fuera de las superficies ejecutables, branch protection, push ni PR.

## Tareas reconciliadas

- [x] Explorar workflows, manifests y runners en la worktree F02; no se creó ni reindexó CodeGraph.
- [x] Crear workflow seguro y jobs independientes backend/panel/cliente.
- [x] Documentar paridad local y actualizar el tracker F02 con evidencia preliminar; hash final pendiente del commit.
- [x] Ejecutar validación estática disponible y registrar evidencia.
- [x] Actualizar tracker/evidencia preliminar.
- [x] Commit convencional `8002648`; 171 líneas cambiadas en el work-unit commit, sin push ni PR.
- [x] Revisión nativa del rango exacto `a5223a6..8002648`: lineage `review-ccaef90d54cbf2cf` aprobada y acknowledged; cuatro lentes completadas, sin ruta de corrección.

## Criterios de aceptación

- Los comandos CI corresponden a los runners reales y manifiestos presentes.
- Los fallos se muestran por superficie y ninguno requiere secretos o DB compartida.
- No hay job para captura móvil sin manifest, ni E2E/Compose/PostgreSQL.
- PyYAML parsea el workflow completo y el diff total, incluidos los artefactos ODD, permanece <400 líneas. `actionlint` no está instalado; la semántica específica de GitHub Actions queda sin validar y se declara explícitamente.
- La guía local indica límites y los comandos equivalentes sin afirmar cobertura de E2E.
- El commit incluye workflow y documentación/evidencia. No push ni PR.

## Verificación

- PyYAML 6.0.3 parseó el YAML completo; sintaxis YAML válida. `actionlint`, `yamllint` y `yq` no están instalados, por lo que no se afirmó validación de semántica GitHub.
- Verificación staged final: 169 líneas añadidas + 2 eliminadas (171 líneas totales) en cuatro archivos, bajo el límite de 400.
- No se instalaron dependencias ni se ejecutaron tests de backend/panel/Flutter, Docker o PostgreSQL; la CI declarada los invocará solo al activarse y el job de DB/E2E se excluyó.

## Evidencia

- Workflow: `.github/workflows/ci.yml` (59 líneas), jobs separados backend/panel/cliente.
- Guía local: `docs/ci/f02-initial-ci.md` (52 líneas).
- Verificación: PyYAML 6.0.3 parse PASS; triggers, permisos, exclusiones y comandos comprobados contra manifests/docs. `actionlint` no está instalado, por lo que la semántica GitHub permanece sin validar. Diff staged final: 171 líneas.
- Commit: `8002648` (`ci(f02): add checks for active product surfaces`), 171 líneas cambiadas.
- Revisión nativa `review-ccaef90d54cbf2cf`: candidata exacta `8002648` sobre `a5223a645f0b1d63e8f54d49f846ecc7e50aaa48`; 4 rutas cambiadas y 171 líneas de diff. Se completaron las cuatro lentes; el cierre ofreció acknowledgement y no ofreció ruta de corrección. Resultado `approved` y `acknowledged`. El cierre no expuso un resumen de hallazgos, por lo que no se afirma que no los hubiera.
