# F04 — App cliente: catálogo real

## Objetivo

Reemplazar el catálogo sintético de la app cliente (`apps/cliente_mobile`) por el catálogo público real de F04.4: búsqueda con filtros y paginación sobre `GET /api/v1/listings` y detalle sobre `GET /api/v1/listings/{listing_id}`, con estados honestos de carga, vacío, error y sin conexión.

## Fuentes canónicas

Rige la regla del 2026-09-30 (`docs/plan-maestro-roomforge.md` §1.4.3).

- Plan F04.4: filtros ciudad/zona, venta/alquiler, precio base, habitaciones y baños; paginación y estados vacíos. El detalle aclara precio base y periodicidad, opcionales y estado de disponibilidad. Aceptación: resultados coherentes con filtros y autorización; alquiler visible por mes, venta sin recargo mensual accidental; sin modelo, estado honesto y no escena ajena.
- Redefinición: el catálogo muestra solo publicaciones aprobadas; el precio base no incluye muebles opcionales; venta con extras de pago único y alquiler con base y extras mensuales.
- Contrato: `docs/api/catalog-reservations-v1.md` (búsqueda y detalle público). Moneda COP por la decisión D-01.
- Mapa UX aprobado (`docs/ux/f02-surface-map.md`) y el shell existente de la app cliente.

## Regla de alcance (decisión del usuario, 2026-10-01)

El equipo trabaja solo en F04. Cotización (F05), visor 3D (F06), reservas y wallet (F09/F10) y fotografías (F04.2, diferida) quedan fuera.

## Relación con `odd/tasks/cliente-catalog.md`

CC-07 de ese registro («Cliente Flutter por capas») abarca catálogo, cotización y wallet. Este registro cubre solo la parte de F04 (listado, filtros y detalle); cotización y wallet siguen abiertas en CC-07.

## Estado de partida (rama `feat/f04-listings-completion`, `0555c8d`)

| Superficie | Estado |
|---|---|
| API pública de catálogo | Implementada en `main`: solo inmuebles aprobados y publicados, filtros, cursor opaco y detalle con dormitorios, baños y extras |
| Cuenta de cliente en la app | Real (registro, login, sesión y cuenta) |
| Pestaña «Explorar» | Prototipo: una tarjeta sintética rotulada, hoja de filtros local sin API y detalle ficticio |
| README de la app | Desactualizado: afirma que no hay autenticación |

## Decisiones tomadas (2026-10-02)

1. **Catálogo público:** se navega sin iniciar sesión, igual que la API; la cuenta queda para cotizar y reservar en fases futuras.
2. **Disponibilidad:** la API pública no la expone (depende de reservas, F09). El detalle muestra «Disponibilidad no consultada» y se registra como límite; no se agrega al backend.
3. **Registro propio:** este archivo, con una referencia en CC-07.
4. **Opcionales:** el detalle lista los extras con su precio y aclara que el precio base no los incluye; no se eligen ni se calcula un total (cotización, F05).
5. **Organización:** modelos en `lib/data/models/`, cliente HTTP en `lib/data/services/`, estado en `lib/domain/`, pantallas en `lib/ui/features/catalog/views/`, igual que la cuenta de cliente.
6. **Errores:** se reutiliza el vocabulario de `customer_auth_failure.dart` sin modificarlo; los textos al usuario se eligen en la app, porque el detalle del servidor viene en inglés.

## Alcance permitido

- Nuevos: `lib/data/models/catalog_models.dart`, `lib/data/services/catalog_api.dart`, `lib/domain/catalog_controller.dart`, `lib/ui/features/catalog/views/*.dart`, `test/catalog_api_test.dart`, `test/catalog_controller_test.dart`, `test/catalog_screens_test.dart`, `test/support/fake_catalog_backend.dart`.
- `lib/main.dart`: inyección del cliente de catálogo y reemplazo de la pestaña «Explorar», del detalle y de la hoja de filtros sintéticos.
- `test/widget_test.dart`: pruebas del shell que hoy verifican el catálogo sintético.
- `README.md` de la app; este registro; una línea en CC-07 de `odd/tasks/cliente-catalog.md`; línea de avance de F04 en `docs/plan-maestro-roomforge.md`.

- `android/app/src/debug/AndroidManifest.xml`: ampliación aprobada por el usuario el 2026-10-02 (ver registro).

Fuera de superficie: backend, panel, app de captura, cuenta de cliente (`customer_*`), pestaña «Reservas», el resto de `android/` e `ios/`.

## Restricciones

- TDD estricto con `flutter test`; además `flutter analyze` y `dart format`.
- Dinero como texto decimal del servidor; nunca `double`.
- Cuerpo decodificado como UTF-8 explícito: la API responde `application/json` sin `charset`.
- Sin datos ficticios presentados como catálogo real.
- Sin commit ni push sin autorización explícita del usuario.

## Tareas

- [x] **F04C-T1 — Modelos y cliente HTTP.** Búsqueda con filtros, cursor y límite; detalle; errores del vocabulario compartido.
- [x] **F04C-T2 — Controlador del catálogo.** Filtros activos, primera página, «cargar más», estados de carga/vacío/error y detalle.
- [x] **F04C-T3 — Pantallas.** Lista con tarjetas reales, hoja de filtros con validación equivalente a la API, detalle con precio y periodicidad, opcionales, recorrido 3D y disponibilidad honestos.
- [x] **F04C-T4 — Integración.** «Explorar» usa el catálogo real; se retiran el listado, el detalle y la hoja sintéticos; las pruebas del shell se actualizan.
- [x] **F04C-T5 — Verificación.** Suite, análisis y formato; recorrido en el emulador con inmuebles publicados desde el panel.

## Registro de ejecución

### 2026-10-02 — F04C-T1 a F04C-T4

- **T1:** `test/catalog_api_test.dart` (7 pruebas) falló antes de existir `catalog_models.dart` y `catalog_api.dart` (RED) y pasó después (GREEN). El cliente no envía credenciales, decodifica UTF-8 explícito y rechaza respuestas que no cumplen el contrato (por ejemplo una operación desconocida).
- **T2:** `test/catalog_controller_test.dart` (9 pruebas, con `test/support/fake_catalog_backend.dart`) falló antes de existir el controlador (RED) y pasó después (GREEN). Un fallo al cargar más conserva lo ya cargado.
- **T3:** `test/catalog_screens_test.dart` (12 pruebas) falló antes de existir las pantallas (RED). En GREEN, la prueba de 320 px con texto a 1,5× falló porque el ayudante cerraba la hoja de filtros tocando una esquina que la hoja cubre a ese tamaño; se corrigió solo la prueba (cierra la hoja con el navegador).
- **T4:** `lib/main.dart` usa `CatalogScreen` en «Explorar» y se eliminaron el listado, el detalle y la hoja de filtros sintéticos. `test/widget_test.dart` reemplazó las pruebas del catálogo sintético por las del catálogo real y adaptó etiquetas y claves de los filtros; las pruebas de pestañas, cuenta, reservas, 320 px y accesibilidad se conservan.
- **Formato:** `dart format lib test` reformateó también 7 archivos de la cuenta de cliente que ya no cumplían el formato; se revirtieron por estar fuera de superficie. `dart format --set-exit-if-changed` sobre los archivos de esta tarea no reporta cambios.
- **Verificación:** `flutter test` → `00:09 +77: All tests passed!`; `flutter analyze --no-pub` → `No issues found!`.

### 2026-10-02 — Corrección de fase anterior: HTTP local en depuración

- La app cliente no podía llegar a la API local desde el emulador: su manifiesto de depuración no permitía tráfico sin cifrar y Android 9+ lo bloquea por defecto, así que el login de cliente (F03) y el catálogo fallarían como «sin conexión». Con aprobación del usuario se agregó `<application android:usesCleartextTraffic="true"/>` solo en `android/app/src/debug/AndroidManifest.xml`, igual que la app de captura (`a415a65`). La versión de lanzamiento sigue rechazando HTTP.


### 2026-10-02 — F04C-T5

- APK de depuración de la app cliente compilado con el manifiesto corregido, instalado en el emulador y Gradle detenido después.
- La API local devolvió un inmueble aprobado y publicado desde el panel (`GET /api/v1/listings` → 1 ítem).
- Recorrido manual del usuario en el emulador sin iniciar sesión: lista, detalle y filtros del catálogo. Resultado informado por el usuario: «ya funciona la parte de catálogo».
- Límite: la paginación («Cargar más», más de 20 publicados) solo está cubierta por pruebas automáticas.

### Pendiente registrado (2026-10-02)

- Filtros de ciudad y zona: hoy son texto libre con coincidencia exacta del nombre (sin distinguir mayúsculas), como la API (`strip().casefold()`). El usuario lo revisará con el equipo para decidir si se mantiene o se cambia (por ejemplo, coincidencia parcial o lista de valores); un cambio afectaría el contrato y el backend, no solo la app.
