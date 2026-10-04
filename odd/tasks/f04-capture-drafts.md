# F04 — App de captura: borradores del agente

## Objetivo

Reemplazar los prototipos de F04 de la app de captura (`apps/captura_mobile`) por el recorrido real del agente contra la API: ver sus inmuebles (borradores, rechazados con motivo y en revisión), crear y editar la ficha del inmueble (F04.1) y enviarla a revisión (F04.3). La bandeja del panel ya recibe lo que el agente envía.

## Fuentes canónicas

Rige la regla del 2026-09-30 (`docs/plan-maestro-roomforge.md` §1.4.3).

- Redefinición: el agente prepara borradores; el administrador de agencia aprueba o rechaza; el borrador no aparece en el catálogo hasta la aprobación.
- Plan F04.1: ficha del inmueble con propietario inmobiliario y validación de entradas, sin inventar precisión geográfica. Plan F04.3: borrador por agente, envío a revisión, reapertura tras cambios.
- Mapa UX aprobado (`docs/ux/f02-surface-map.md`): el agente prepara y edita el borrador en la app Android de captura; inicio con borradores y acción principal «Nuevo inmueble»; volver sin perder contexto; estados de carga, vacío, error, sin conexión y confirmación antes de enviar a revisión; objetivos táctiles de 48 dp.
- Contrato: `docs/api/f04-publications-v1.md` (alta, edición, envío, listado, consulta e historial).

## Regla de alcance (decisión del usuario, 2026-10-01)

El equipo trabaja solo en F04. Se corrigen fases anteriores cuando F04 lo necesita; no se construye nada de fases futuras salvo que sea estrictamente necesario.

## Estado de partida (rama `feat/f04-listings-completion`, `a415a65`)

| Superficie | Estado |
|---|---|
| Acceso de personal en la app | Real y verificado en emulador contra la API (`odd/tasks/f03-capture-staff-origin.md`); el controlador conserva el token de acceso en memoria |
| Pantalla «Borradores» | Prototipo de F02 con lista siempre vacía |
| Paso 1 «Datos básicos y operación» | Prototipo de F02 sin campos («todavía no está implementada») |
| Pasos 2–4 (ambientes y fotos, geometría, oferta) | Prototipos de F02 de fases futuras (F04.2 diferida, F05, F06, F07) |
| Paso 5 «Revisar resumen» | Prototipo de envío simulado, enlazado desde el paso 4 |

## Decisiones tomadas (2026-10-01)

1. **Recorrido real:** acceso → mis inmuebles → nuevo/editar → guardar borrador → enviar a revisión con confirmación.
2. **Prototipos de F04 reemplazados:** se eliminan `DraftsScreen` y `BasicOperationScreen` de `lib/main.dart`; nada más depende de ellas.
3. **Prototipos de fases futuras intactos:** `RoomsPhotosScreen`, `GeometryObjectsScreen`, `OfferPreparationScreen` y `ReviewSummaryScreen` no se modifican; quedan fuera del recorrido real. `ReviewSummaryScreen` se conserva porque `OfferPreparationScreen` (F05) la enlaza. Sus pruebas solo cambian el punto de entrada (abren el paso 2 directamente).
4. **Organización:** cliente HTTP en `lib/data/services/`, modelos en `lib/data/models/`, estado en `lib/domain/`, pantallas de F04 en `lib/ui/listings/` para no compartir archivos con el futuro trabajo de captura (F07).
5. **Errores:** se reutiliza el vocabulario compartido de `staff_auth_failure.dart` (`failureFromResponse`, `networkFailure`), sin modificarlo.
6. **Visibilidad:** el agente ve todos los inmuebles de su agencia, coherente con la API.

## Alcance permitido

- Nuevos: `lib/data/models/staff_listing.dart`, `lib/data/services/staff_listings_api.dart`, `lib/domain/listing_drafts_controller.dart`, `lib/ui/listings/*.dart`, `test/staff_listings_api_test.dart`, `test/listing_drafts_controller_test.dart`, `test/listings_screens_test.dart`, `test/support/fake_listings_backend.dart`.
- `lib/main.dart`: destino del botón tras el acceso, inyección del cliente de inmuebles, aviso de acceso y eliminación de `DraftsScreen` y `BasicOperationScreen`.
- `test/widget_test.dart`: pruebas del acceso y punto de entrada de las pruebas de los prototipos.
- `README.md` de la app; este registro; línea de avance de F04 en `docs/plan-maestro-roomforge.md`.

Fuera de superficie: backend, panel, app cliente, las cuatro pantallas de prototipo de fases futuras, `staff_auth_api.dart`, `staff_auth_failure.dart`, `staff_session_controller.dart`, `android/`.

## Restricciones

- TDD estricto con `flutter test`; además `flutter analyze` y `dart format`.
- El token de acceso se toma del controlador de sesión; nunca se persiste.
- La agencia sale de la sesión (`tenant_id`); la autorización real sigue en el servidor.
- Sin commit ni push sin autorización explícita del usuario.

## Tareas

- [x] **F04A-T1 — Modelos y cliente HTTP.** Listado por estado, consulta, alta, edición, envío e historial con Bearer y errores del vocabulario compartido.
- [x] **F04A-T2 — Controlador de borradores.** Carga por pestaña, guardar (alta o edición), enviar a revisión y motivo del último rechazo.
- [x] **F04A-T3 — Pantallas.** Lista con pestañas, estados de carga/vacío/error, formulario con validación equivalente a la API, motivo de rechazo y confirmación de envío.
- [x] **F04A-T4 — Integración.** El acceso lleva a la lista real; se retiran los prototipos de F04; las pruebas de los prototipos futuros cambian solo su entrada.
- [x] **F04A-T5 — Verificación.** Suite, análisis y formato; recorrido real en el emulador con una cuenta de agente: crear, editar, enviar y verlo en la bandeja del panel.

## Registro de ejecución

### 2026-10-01 — F04A-T1 a F04A-T4

- **T1:** `test/staff_listings_api_test.dart` (9 pruebas) se escribió antes del cliente y falló por la ausencia de `staff_listings_api.dart` (RED). El cliente decodifica el cuerpo como UTF-8 de forma explícita porque la API responde `application/json` sin `charset`; la prueba reproduce ese caso con «Medellín».
- **T2:** `test/listing_drafts_controller_test.dart` (11 pruebas, con `test/support/fake_listings_backend.dart`) falló antes de existir el controlador (RED) y pasó después (GREEN).
- **T3:** `test/listings_screens_test.dart` (10 pruebas) falló antes de existir las pantallas (RED). Durante GREEN, la prueba de validación reveló un defecto real: el formulario dentro de un `ListView` perezoso no construía los campos fuera de pantalla y `validate()` no los alcanzaba. El editor pasó a `SingleChildScrollView` + `Column` para que la validación cubra todos los campos. Ajustes solo de prueba: quitar el foco antes de desplazar y esperar a que se cierre el `SnackBar` antes de tocar «Enviar a revisión».
- **T4:** `lib/main.dart` lleva del acceso a «Mis inmuebles» y se eliminaron `DraftsScreen` y `BasicOperationScreen`. En `test/widget_test.dart` se retiraron las pruebas de esos dos prototipos, se añadió «continues from access to the agent listings» y las pruebas de los prototipos futuros abren directamente el paso 2. La prueba de 320 px ahora aplica el texto a 1,5× a los pasos de prototipo (antes solo al acceso); falló porque el ayudante `tapScreenEndAction` desplazaba una distancia fija y se corrigió para desplazar hasta encontrar la acción. Las cuatro pantallas de prototipo no cambiaron.
- **Verificación:** `flutter test` → `00:08 +77: All tests passed!`; `flutter analyze --no-pub` → `No issues found!`; `dart format --output=none --set-exit-if-changed lib test` → sin cambios.


### 2026-10-02 — F04A-T5

- APK de depuración compilado (`flutter build apk --debug`) e instalado en el emulador `ShareGrams_Test`; el daemon de Gradle se detuvo después para liberar memoria.
- Cuenta de agente `agente@example.test` invitada con `POST /api/v1/agencies/agent-invitations` desde la sesión de `agencia@example.test` (el panel todavía no tiene pantalla para invitar agentes); el enlace salió del buzón local de desarrollo y el usuario lo aceptó en el panel.
- Recorrido manual del usuario en el emulador: acceso como agente → «Mis inmuebles» → nuevo inmueble → guardar borrador → editar → enviar a revisión con confirmación; el inmueble aparece en la bandeja del panel de `agencia@example.test`. Resultado informado por el usuario: «funciona bien el flujo».
- Incidencia de entorno, sin cambio de código: el emulador arranca desde una instantánea anterior a la instalación y volvía a mostrar el APK viejo (con el prototipo «Datos básicos y operación»); se resolvió reinstalando el APK con `adb install -r`.
- Límite: el rechazo visto desde la app (motivo en «Rechazados») solo está cubierto por pruebas automáticas; no se recorrió a mano.

### Pendiente registrado (2026-10-02)

- El usuario pidió mostrar los precios en dólares. La moneda está fijada como COP en la decisión D-01 (`docs/api/catalog-reservations-v1.md`), en el contrato del catálogo, en el depósito (`deposit_amount_cop`) y en reservas. Por decisión del usuario se mantiene COP y el cambio queda para revisión del equipo junto con D-01; un cambio solo visual en F04 dejaría pantallas contradictorias.
