# F02-T4e — Prototipo UX de captura Android

## Estado

**EN PROGRESO.** El plan y su espejo Engram se crearon antes del código. El usuario autorizó completar F02-T4 antes de F03 y extender el workflow/guía local de CI para ejecutar esta superficie. T4e está cerrado como el primer work-unit de captura: commit `a6d899c` (`feat(capture): add access and drafts prototype`), seis archivos, `390` inserciones + `5` eliminaciones = `395` líneas modificadas (<400). El slice de app es UI-only: `Access → empty drafts → local not-built Nuevo inmueble placeholder`. T4f, T4g, T4h y T6 siguen pendientes. Cada work-unit tendrá commit local propio, menos de 400 líneas modificadas y pruebas TDD. Sin push ni PR.

**Evidencia T4e:** Strict TDD observado con RED conductual mediante stub compilable y GREEN final. Los 6 widget tests, `flutter analyze --no-pub` y Dart format pasaron en el worker y en la verificación independiente, con Flutter 3.41.8 / Dart 3.11.5 y resolución offline solo SDK en el único mirror existente autorizado. Las fuentes, manifiestos, lockfile y `.dart_tool` del cliente en el mirror fueron restaurados y verificados por hash; se preservaron el `build/` existente y el snapshot del worker. El pre-commit ASSESS fue `unassessable` por archivos sin seguimiento; el verificador independiente de barra alta pasó.

La revisión nativa `review-023f7c902198a590` quedó acotada exactamente al commit de seis archivos contra el padre `cfb8679e422b649b49b05d9ba16f1e2e4802963f`, tier medio; fue aprobada y acknowledged. No se expuso resumen de hallazgos. No se verificaron autenticación real, API, propiedades/precios, cámara/AR, persistencia, emulador Android ni runtime de cámara.

## Objetivo

Crear el prototipo Flutter de la app Android de captura del agente conforme al flujo autorizado de F02, con navegación local y estados UX verificables. No implementar funciones de las fases F03–F10.

## Autoridad y alcance

- Fuentes de producto: `docs/redefinicion-roomforge.md`, `docs/plan-maestro-roomforge.md` y mapa aprobado `docs/ux/f02-surface-map.md`.
- Flujo aprobado: **Acceso → borradores → nuevo inmueble → datos básicos y operación → ambientes/fotos → corregir geometría y objetos → preparar oferta → revisar resumen → enviar a revisión**.
- Acceso, guardado y envío son solo interacciones de prototipo. Mostrar estados sin afirmar autenticación, persistencia o envío reales.
- La lista inicial de borradores estará vacía; no crear datos inmobiliarios ficticios ni reutilizar el ejemplo sintético del cliente como un borrador real.
- Fotos, permiso y geometría se simulan en UI: controles explícitos, plantilla/formas identificadas como ilustrativas y nunca como captura, medición o reconstrucción real. No usar cámara, ARCore, video, Meshroom, 3D engine ni plugins nativos.
- Oferta: mostrar únicamente el paso/estructura conceptual aprobada; no inventar precio, moneda, impuestos, cargos, descuentos ni vigencia. No incluir datos comerciales de ejemplo.
- Mostrar estado conceptual offline/error/permiso/reintento/confirmación sin prometer persistencia local, sincronización, identidad/API ni operación durable.
- Corregir el README de captura para retirar el enlace a un repositorio externo y las capacidades no aprobadas de video/difuminado; describir con precisión el prototipo local y sus límites.
- Extender `.github/workflows/ci.yml` y `docs/ci/f02-initial-ci.md` para ejecutar tests y análisis Flutter de captura. No desplegar, usar secretos, PostgreSQL/Docker ni afirmar una ejecución de GitHub Actions.

## No objetivos

- No modificar backend, contratos, panel, app cliente, migraciones, infraestructura ni las fuentes de producto.
- No integrar login real, cámara/AR, almacenamiento, carga de medios, API, sincronización offline, editor/visor 3D, inventario o precios.
- No generar directorios Android/iOS, APK, assets ni versionar `pubspec.lock`; no añadir dependencias de terceros. Para verificar, se permite `flutter pub get --offline` solo en el mirror existente y únicamente para resolver los paquetes SDK `flutter`/`flutter_test`; restaurar su lockfile y `.dart_tool` originales.
- No modificar F03–F10 ni empezar su implementación.

## Superficies autorizadas

## Allowed edit surfaces

- `apps/captura_mobile/lib/**`
- `apps/captura_mobile/test/**`
- `apps/captura_mobile/pubspec.yaml`
- `apps/captura_mobile/analysis_options.yaml`
- `apps/captura_mobile/README.md`
- `.github/workflows/ci.yml`
- `docs/ci/f02-initial-ci.md`
- `odd/tasks/f02-t4e-capture-prototype.md`
- `odd/tasks/f02-t4-mobile-prototype.md`
- `odd/tasks/f02-base-ux-automation.md`
- `odd/tasks/f02-t6-integrated-verification.md`

## Plan por work-units

1. **T4e — Esqueleto, acceso visual y borradores.** **CERRADA.** Commit `a6d899c` (`feat(capture): add access and drafts prototype`), seis archivos, `390` inserciones + `5` eliminaciones = `395` líneas modificadas (<400). Slice UI-only: `Access → empty drafts → local not-built Nuevo inmueble placeholder`. RED conductual con stub compilable y GREEN final; 6 widget tests, `flutter analyze --no-pub` y Dart format PASS en worker y verificación independiente con Flutter 3.41.8 / Dart 3.11.5, resolución offline solo SDK en el mirror autorizado. Fuentes, manifiestos, lockfile y `.dart_tool` restaurados y hash-checkeados; `build/` existente y snapshot del worker preservados. ASSESS pre-commit `unassessable` por archivos sin seguimiento; verificador independiente de barra alta PASS. Revisión `review-023f7c902198a590`, exactamente sobre el commit de seis archivos contra `cfb8679e422b649b49b05d9ba16f1e2e4802963f`, tier medio: aprobada y acknowledged, sin resumen de hallazgos expuesto. Sin autenticación real, API, propiedades/precios, cámara/AR, persistencia, emulador Android ni runtime de cámara.
2. **T4f — Flujo de captura y permisos simulados.** Añadir pasos genéricos de datos/operación, ambientes/fotos con acciones de cámara explícitamente simuladas, estados de permiso requerido/denegado, offline/error/reintento, y retorno sin perder contexto. No definir campos de F04 ni guardar archivos. RED→GREEN→TRIANGULATE→REFACTOR; <400 líneas. Commit y evidencia pendientes.
3. **T4g — Corrección conceptual y revisión simulada.** Añadir formas/objetos editables de demostración con procedencia honesta, paso conceptual de oferta sin valores comerciales, resumen, confirmación y resultado de envío simulado; cubrir accesibilidad, tamaño de pantalla y escala de texto. <400 líneas. Commit y evidencia pendientes.
4. **T4h — CI, guía y tracker.** Añadir job Flutter para `apps/captura_mobile` usando Flutter 3.41.8; ejecutar `flutter pub get`, `flutter test`, `flutter analyze` y formato. Actualizar guía CI, tracker y registro T4. No ejecutar GitHub Actions. <400 líneas. Commit documental/CI pendiente.
5. **T6 — Verificación integrada F02.** Repetir los checks locales necesarios tras añadir captura/CI, registrar skips/limitaciones honestamente y actualizar `odd/tasks/f02-t6-integrated-verification.md`. No usar DB/Docker/Alembic ni publicar. Commit de evidencia pendiente.

## Verificación y entorno

- Strict TDD por work-unit: prueba RED antes del cambio, GREEN y triangulación; no declarar como RED un simple error de compilación sin evidencia.
- Flutter 3.41.8 / Dart 3.11.5. Reutilizar únicamente el mirror ya autorizado `D:\tmp\f02-t4d-validation`; no crear otro mirror. Preservar/restaurar sus archivos de `cliente_mobile` después de cada uso.
- En el mirror autorizado, ejecutar `flutter pub get --offline` (solo SDK) y luego `flutter test test/widget_test.dart`, `flutter analyze --no-pub` y `dart format --output=none --set-exit-if-changed` sobre los Dart files. Restaurar lockfile/`.dart_tool` originales y verificar hashes de `cliente_mobile` antes de aceptar el resultado.
- Revisar `git diff --check`, sumar additions+deletions para cada commit (<400) y confirmar que no exista `pubspec.lock` ni scaffolding generado en el worktree.
- El job de CI solo tendrá parseo/lectura local en esta tarea; no se reportará validación semántica por GitHub sin ejecutar Actions.
- El runtime Android/cámara real no se ejecuta ni se afirma; la UI debe identificar todas las simulaciones.

## Rollback

Revertir cada commit de work-unit por separado: T4e elimina el shell/manifiesto/readme de captura; T4f y T4g eliminan solo sus pasos UX y pruebas; T4h revierte el job/guía CI; T6 revierte únicamente evidencia. Ningún rollback toca la app cliente, la base R6, el contenedor o su volumen.
