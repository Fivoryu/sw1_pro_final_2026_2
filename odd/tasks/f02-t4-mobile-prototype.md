# F02-T4 — Prototipos accesibles: cliente móvil

## Objetivo

Construir incrementalmente la app móvil del cliente para F02.3, sin APIs ni comportamiento de negocio de F03–F10. T4a incorpora el shell Flutter aprobado; T4b añade catálogo/filtros y T4c accesibilidad/responsive. Para T4d el usuario autorizó una muestra sintética claramente rotulada; no se presentará como publicación real ni se inventarán condiciones comerciales.

## Alcance autorizado de esta unidad

- **T4a:** importar exactamente las 129 líneas acordadas del commit `64c59c0` en `apps/cliente_mobile/lib/main.dart`, `test/widget_test.dart`, `pubspec.yaml` y `analysis_options.yaml`.
- **T4b/T4c:** evolucionar únicamente `apps/cliente_mobile/lib/main.dart` y `apps/cliente_mobile/test/widget_test.dart` para el shell de catálogo y accesibilidad.
- Excluir scaffolding Android/iOS generado, íconos/assets, README, `pubspec.lock` y los commits posteriores de API/identidad. Las pruebas corren en mirror temporal autorizado para mantener el lockfile fuera del worktree.
- No editar el documento principal F02 ni los archivos de migraciones salvo las actualizaciones de estado autorizadas. El usuario autorizó los commits por unidad; no hacer push ni abrir PR.

## Tareas

- [x] **T4a — Starter Flutter con TDD.** RED con `main.dart` ausente; GREEN: 2 widget tests y `flutter analyze` PASS en mirror temporal. 129 líneas exactas de los cuatro archivos autorizados; commit `b154888`.
- [x] **T4b — Catálogo y filtros cliente.** Navegación aprobada (Explorar/Reservas/Cuenta), estado vacío honesto y cinco filtros locales, sin datos ficticios ni API. Verificación independiente: 352 líneas modificadas (bajo el límite de 400), 5 widget tests PASS y `flutter analyze` sin issues. Commit `49a853d`. El forecast de 240–340 quedó corto; T4c añadió comprobaciones de accesibilidad y viewport por pestaña.
- [x] **T4c — Accesibilidad y adaptación móvil.** Añadidas pruebas de semantics/objetivos táctiles, tres pestañas en 320 px y filtro con texto ampliado/teclado. `dart format` aplicado solo a los dos Dart files. Verificación independiente: 8 tests PASS, analyze limpio, formato estable y whitespace limpio. Snapshot T4c: 336 líneas modificadas vs T4b, bajo el límite de 400; commit `ce5028e`.

- [ ] **T4d — Detalle y recorrido/disponibilidad.** **AUTORIZADO; IMPLEMENTACIÓN EN CURSO:** el usuario eligió una muestra sintética claramente rotulada como no real. El detalle indica que no hay recorrido 3D ni disponibilidad consultada/confirmada. No incluir precio, moneda, términos comerciales ni reserva; no conectar APIs. Pruebas Flutter/analyze pasan en mirror, commit y review pendientes. Plan y alcance: `odd/tasks/f02-t4d-property-detail.md`.

## Criterios de aceptación T4b

- La navegación principal mantiene `Explorar`, `Reservas` y `Cuenta`; las vistas no implementadas se identifican como prototipo, no como datos reales.
- El catálogo muestra un estado vacío explícito, sin anuncios ficticios ni valores de precio/moneda.
- El selector de filtros contiene únicamente ciudad/zona, operación venta/alquiler, precio base, habitaciones y baños. Los controles son etiquetados y accesibles; sus cambios solo actualizan estado local del prototipo.
- Tests de widget cubren navegación, visibilidad del estado vacío, apertura de filtros, las cinco categorías autorizadas y viewport estrecho.
- El forecast de T4b fue 240–340 líneas; medición independiente final: 352, aún bajo el límite de 400.
- Si un slice futuro proyecta más de 400 líneas modificadas, detenerse y volver a acordar slices.

## Criterios de aceptación T4c

- Ejecutar guías de semantics para controles etiquetados y objetivos táctiles Android de 48 dp.
- Probar las tres pestañas y el filtro con viewport de 320 px, texto ampliado y teclado.
- `dart format --output=none --set-exit-if-changed`, 8 widget tests y `flutter analyze` pasan en mirror temporal.

## Restricciones y verificación

- Mantener identidad de cliente existente fuera de esta unidad; no tocar backend/API ni contratos.
- No inventar precio final, moneda, impuestos ni validez de oferta.
- Ejecutar pruebas y análisis Flutter en mirror temporal fuera del worktree para no crear `pubspec.lock` en el repositorio.
- Mantener T3b de PostgreSQL en modo diagnóstico de solo lectura; no cambiar migraciones, repetir tests ni usar Docker/PostgreSQL.
- El usuario autorizó commits por unidad; el consentimiento no incluye push ni PR.

**Estado:** T4a, T4b y T4c cerradas, verificadas y comprometidas: `b154888` (129 líneas), `49a853d` (352 líneas) y `ce5028e` (336 líneas). T3b diagnóstico-only quedó documentado en `c7849b3`; DB R6 y volumen preservados. Flutter 3.41.8/Dart 3.11.5; T4c tuvo 8 widget tests y `flutter analyze` PASS. T4d usa el mirror temporal autorizado `D:\tmp\f02-t4d-validation`: suite 11 tests PASS, analyze PASS, formato estable; el work-unit y la revisión siguen pendientes. No hay `pubspec.lock` en el worktree. Revisión T4a–T4c `review-e64f5f3ca1291648` aprobada y reconocida; R3-001 es WARNING informativo, sin corrección. No hubo push ni PR. Captura Android y panel web siguen pendientes.
