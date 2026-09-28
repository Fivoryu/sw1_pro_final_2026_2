# F02-T4d — Detalle de inmueble con muestra sintética

## Objetivo

Añadir a la app cliente un recorrido pequeño y navegable desde Explorar hasta el detalle de una propiedad de demostración. Es una muestra UX de F02.3, no un anuncio real ni una reserva funcional.

## Decisión del usuario

El usuario autorizó usar una muestra sintética, con rotulación visible y persistente. La selección no autoriza presentar datos inventados como reales ni definir condiciones comerciales.

## Alcance y límites

- Cambiar solo `apps/cliente_mobile/lib/main.dart` y `apps/cliente_mobile/test/widget_test.dart`; no agregar assets, dependencias, scaffolding generado ni `pubspec.lock`.
- Mostrar una sola muestra ficticia, claramente marcada en catálogo y detalle. Usar únicamente campos descriptivos mínimos para demostrar la pantalla.
- El detalle debe indicar que el recorrido 3D no está disponible y que la disponibilidad no fue consultada ni confirmada.
- No mostrar precio, moneda, impuestos, cargos, descuentos, validez de oferta, calendario ni estado real de disponibilidad.
- No conectar API, implementar filtros/consultas reales, reservas, pagos ni comportamiento de F03–F10. No modificar backend ni el prototipo de captura.
- Preservar las pestañas aprobadas Explorar/Reservas/Cuenta, estado de conexión y filtros existentes.

## Criterios de aceptación

1. Explorar presenta un único elemento sintético con una advertencia inequívoca de que no es una publicación real.
2. Activar el elemento abre un detalle con la misma advertencia, información descriptiva ficticia mínima y navegación de regreso accesible.
3. La pantalla aclara que no existe recorrido 3D disponible y que no se consultó ni confirmó disponibilidad; no ofrece una acción de reserva.
4. El recorrido funciona con viewport de 320 px y mantiene targets/semantics accesibles.
5. Pruebas Flutter, `flutter analyze`, formato Dart y `git diff --check` pasan; el work-unit completo queda bajo 400 líneas modificadas.
6. La verificación ocurre en un mirror temporal autorizado para evitar `pubspec.lock` en el worktree. No usar Docker/PostgreSQL ni servicios externos.

## TDD y validación

- Modo estricto: RED → GREEN → TRIANGULATE → REFACTOR. Agregar primero pruebas widget para rotulación, navegación/retorno, estados no consultados y viewport estrecho; observar RED antes de implementar.
- Runner desde el directorio de la app en el mirror temporal: `flutter test test/widget_test.dart --plain-name "<nombre de prueba>"`; suite: `flutter test test/widget_test.dart`.
- Checks complementarios: `flutter analyze` y `dart format --output=none --set-exit-if-changed lib/main.dart test/widget_test.dart`.
- Flutter 3.41.8 / Dart 3.11.5 fueron observados en verificaciones previas; reconfirmar el runtime utilizado al validar esta unidad.
- Runtime harness: Flutter widget tests en mirror temporal local; no requiere red ni servicios. No copiar lockfile al worktree.

## Work unit y cierre

Una unidad de trabajo: implementación + pruebas + este plan y actualización de estado en `odd/tasks/f02-t4-mobile-prototype.md` y el tracker F02, en un commit convencional local bajo 400 líneas. Tras la revisión nativa, registrar su lineage/resultado en esos documentos mediante un commit documental. No push ni PR.

## Estado

- Decisión sintética rotulada: autorizada.
- Implementación TDD: completada en `main.dart` y `widget_test.dart`. RED: tras corregir un error de compilación en el primer borrador de prueba, la prueba de navegación falló porque aún no existía la muestra. GREEN: las tres pruebas enfocadas pasaron. TRIANGULATE: la suite detectó un overflow de 28 px con texto ampliado; se simplificó el affordance y la suite final pasó.
- Mirror temporal autorizado por el usuario: `D:\tmp\f02-t4d-validation`; no se creó `pubspec.lock` en el worktree.
- Verificación independiente: Flutter 3.41.8 / Dart 3.11.5; `flutter test test/widget_test.dart` 11 PASS; `flutter analyze` sin issues; `dart format --output=none --set-exit-if-changed lib/main.dart test/widget_test.dart` PASS; `git diff --check` PASS.
- Diff final del work-unit: 245 líneas cambiadas (239 añadidas, 6 eliminadas) en cinco rutas; bajo 400. `git diff --cached --check` PASS.
- Commit del work-unit: `67a3052` (`feat(cliente-mobile): add synthetic property detail prototype`); no push ni PR.
- Revisión nativa exacta `c7cf98b3603d498275b38dce9d3421fa213e0905..67a3052517d1d76714a1e8373365aca07ee5b87c`: lineage `review-ee0459bbdc34f8a9`, cinco rutas, 245 líneas; aprobada y acknowledged. No se ofreció corrección y el cierre no expuso un resumen de hallazgos; no afirmar cero hallazgos.
- ASSESS devolvió riesgo `unassessable` por `schema-incompatible` sin diagnóstico sanitizado. Se aplicó la barra de verificación alta: el verifier independiente confirmó alcance/245 líneas y ejecutó 11 tests, analyze, formato y whitespace PASS sobre el mismo árbol candidato antes del commit; el worktree quedó limpio en el commit revisado.
- Registro de cierre: lineage y ASSESS anotados aquí y en ambos trackers; sin push ni PR.
