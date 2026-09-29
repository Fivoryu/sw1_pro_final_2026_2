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

- [x] **T4d — Detalle y recorrido/disponibilidad.** Muestra sintética claramente rotulada, detalle señala recorrido 3D no disponible y disponibilidad no consultada/confirmada; sin precio, moneda, términos comerciales, reserva ni API. Commit `67a3052` (245 líneas); 11 widget tests, analyze y formato PASS en mirror. Revisión nativa `review-ee0459bbdc34f8a9` aprobada/acknowledged; sin resumen de hallazgos y sin ruta de corrección. ASSESS falló con `schema-incompatible`/riesgo `unassessable`; verificación independiente completada con la barra alta. Plan: `odd/tasks/f02-t4d-property-detail.md`; queda el commit documental de cierre.

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

**Estado:** T4a, T4b, T4c y T4d cerradas como work-units verificados/comprometidos: `b154888` (129 líneas), `49a853d` (352), `ce5028e` (336) y `67a3052` (245). T3b diagnóstico-only quedó documentado en `c7849b3`; DB R6 y volumen preservados. Flutter 3.41.8/Dart 3.11.5; T4d tuvo 11 widget tests, `flutter analyze`, formato y whitespace PASS en el mirror autorizado `D:\tmp\f02-t4d-validation`. Revisión T4a–T4c `review-e64f5f3ca1291648` aprobada/acknowledged; R3-001 es WARNING informativo. Revisión T4d `review-ee0459bbdc34f8a9` aprobada/acknowledged; ASSESS quedó `unassessable` por incompatibilidad de esquema, mitigado con verificación independiente. El cierre documental T4d ya está registrado en `e7452c5`. El panel web ya está completo. La captura Android tiene el shell T4e comprometido en `a6d899c` (seis archivos, `+390/-5 = 395` líneas; `Access → empty drafts → local not-built Nuevo inmueble placeholder`) y el flujo T4f comprometido en `c1c4b99d19be31d3e49a39b9e9590e822446fed4` (`feat(capture): add simulated capture flow and photo states`, dos archivos, `+355/-37 = 392` líneas; pasos de datos/operación y ambientes/fotos con permiso, conectividad, error/reintento y captura de foto simulados y rotulados). T4f contó con verificación independiente de barra alta: 9 widget tests, `flutter analyze --no-pub`, Dart format y whitespace PASS con Flutter 3.41.8 / Dart 3.11.5 en el mirror autorizado, con restauración byte-idéntica del mirror. ASSESS quedó `unassessable` (`schema-incompatible`) y la revisión nativa `review-bfee92cef5c28da1` del rango exacto `2251e2d..c1c4b99` no pudo completarse por `operation_timeout` del proveedor (`retry_safe: false`, sin mutación): T4f **no** está revisado nativamente. Quedan T4g/T4h/T6 y dos hallazgos del verificador (README desactualizado y prueba de ausencia de credenciales demasiado laxa) para T4g. T4g se dividió en dos unidades al medir `+489/-8 = 497` líneas: **T4g-1** (corrección de geometría y objetos con formas ilustrativas, continuación desde ambientes/fotos) quedó cerrada con `246` líneas en app y pruebas más el README corregido —13 widget tests, `flutter analyze --no-pub`, Dart format y whitespace PASS, mirror restaurado byte-idéntico— y **T4g-2** (oferta conceptual, resumen, confirmación y envío simulado) sigue pendiente. No hay `pubspec.lock` en el worktree. No hubo push ni PR.
