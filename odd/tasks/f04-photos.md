# F04.2 — Fotografías y privacidad

## Objetivo

Asociar fotografías a cada inmueble con el patrón estándar de S3: el backend autoriza y firma, la app de captura sube directo al almacenamiento, el backend confirma y limpia el archivo, y el panel y la app cliente lo muestran mediante enlaces temporales. Sin binarios en PostgreSQL ni buckets públicos.

## Fuentes canónicas

Rige la regla del 2026-09-30 (`docs/plan-maestro-roomforge.md` §1.4.3).

- Plan F04.2: validar tipo/tamaño, permisos y claves de archivos; URLs temporales; separar pendiente/subido/confirmado y manejar subida fallida; imágenes asociadas al inmueble sin guardar binarios grandes en PostgreSQL. Aceptación: otra agencia no accede a originales privados; una subida incompleta no deja una publicación aparentemente terminada. El difuminado automático es función adicional, no promesa; política de borrado/retención pendiente.
- Plan F03.3: distinguir publicación pública de fotos originales/borradores privados.
- Plan, arquitectura: «S3 real y Floci local. Separar fotos/binarios de datos transaccionales; acceso autorizado, no buckets públicos generales»; «S3: fotografías y artefactos autorizados; acceso mediante mecanismos temporales/controlados».
- Redefinición: «las fotos forman parte del MVP»; deben respetar las decisiones de privacidad, con retención y sincronización pendientes; separar versiones de contenido visual y comerciales.

## Regla de alcance

El equipo trabaja solo en F04 (decisión del usuario, 2026-10-01). La pantalla de prototipo «Ambientes y fotos» de la app de captura pertenece a F07 y no se modifica.

## Decisiones tomadas (2026-10-04)

1. **Patrón:** subida directa a S3 con enlace firmado (`PUT`), confirmación en el backend y lectura con enlaces firmados (`GET`) de vida corta.
2. **Límites:** hasta 10 fotos por inmueble (confirmadas más pendientes vigentes), hasta 5 MB cada una, en JPEG, PNG o WebP.
3. **Reaprobación:** confirmar o borrar una foto de un inmueble en revisión o aprobado lo devuelve a borrador y lo retira del catálogo, igual que editar la ficha; queda en el historial como `edit`.
4. **Foto mínima:** no se puede enviar a revisión sin al menos una foto confirmada. Los inmuebles ya publicados sin foto siguen visibles.
5. **Privacidad:** al confirmar, el backend descarga el archivo, verifica que sea de verdad una imagen del tipo declarado y lo vuelve a guardar sin metadatos (EXIF, incluida la ubicación GPS), respetando la orientación.
6. **Versión comercial:** las fotos no cambian `offer_version` ni invalidan cotizaciones.
7. **Subidas incompletas:** solo las fotos confirmadas se muestran y cuentan para el envío; una foto pendiente vence a los 15 minutos.
8. **Dependencias nuevas aprobadas:** `boto3` y `Pillow` en el backend; `image_picker` en la app de captura.
9. **Columna `listing.photos`:** existe sin uso desde la migración `0007`; no se modifica.
10. **Firma local:** los enlaces se firman con una dirección pública de S3 (`http://127.0.0.1:4566` en local); el emulador la alcanza con `adb reverse tcp:4566 tcp:4566`. Se confirma en T0.

## Alcance permitido

- Registro: este archivo.
- Backend: `backend/pyproject.toml` (dependencias), `backend/app/core/config.py` (configuración de S3), `backend/app/main.py` (inyección del almacenamiento y registro de las rutas de fotos), módulo `backend/app/modules/catalog/` (modelos, servicio, rutas, esquemas, almacenamiento y el nuevo `photo_router.py`), nueva migración `backend/alembic/versions/0013_listing_photos.py`, pruebas en `backend/tests/` de F04, catálogo y migraciones.
- Infra: `infra/docker/compose.local.yml` y `infra/docker/local-env.example` (variables de S3 del servicio `api`), `infra/README.md`.
- App de captura: `pubspec.yaml`, `lib/data/`, `lib/domain/`, `lib/ui/listings/`, sus pruebas y `README.md`.
- Panel: `panel/staff-shell/src/application/staffListingsApi.ts`, `src/features/listings/`, sus pruebas y estilos.
- App cliente: `lib/data/`, `lib/domain/catalog_controller.dart`, `lib/ui/features/catalog/`, sus pruebas y `README.md`.
- Documentación: `docs/api/f04-publications-v1.md`, `docs/api/catalog-reservations-v1.md` (fotos en el detalle público), línea de avance de F04 en `docs/plan-maestro-roomforge.md`.

Fuera de superficie: identidad, agencias, reservas, contratos, prototipos de F07 de la app de captura, cuenta de cliente, `docs/diagramas/Diagrama1.eapx`, `openspec/`.

## Restricciones

- TDD estricto; Ruff y Pyright sin errores; suites de panel y apps en verde.
- Las pruebas automáticas usan un almacenamiento falso; S3 real (Floci) se verifica en T0 y T8.
- Claves de objeto decididas por el servidor (`agencies/{agency_id}/listings/{listing_id}/photos/{photo_id}`); nunca del cliente.
- Ningún enlace firmado, token ni credencial en logs.
- Sin datos personales en las fotos de prueba.
- Sin commit ni push sin autorización explícita del usuario.

## Tareas

- [x] **F04P-T0 — Prueba previa de Floci.** Bucket disponible, enlace firmado de subida y de lectura, y alcance desde el navegador y el emulador.
- [x] **F04P-T1 — Modelo y migración.** Tabla `listing_photo` (agencia, inmueble, clave, estado, tipo, tamaño, fechas) y migración `0013`.
- [x] **F04P-T2 — Almacenamiento.** Adaptador S3 (firmar subida y lectura, leer, escribir y borrar) con falso en memoria para pruebas; configuración y fallo controlado si S3 no está configurado.
- [x] **F04P-T3 — Rutas de personal.** Pedir subida, confirmar (validación y limpieza), listar y borrar, con límites, reaprobación, permisos y aislamiento entre agencias; envío a revisión con foto mínima.
- [x] **F04P-T4 — Exposición pública.** Fotos en el detalle público y portada en la lista, solo de inmuebles publicados; contrato actualizado.
- [x] **F04P-T5 — App de captura.** Sacar o elegir foto, subir con progreso, reintentar, ver y borrar en la ficha.
- [x] **F04P-T6 — Panel.** Ver las fotos al revisar un inmueble.
- [x] **F04P-T7 — App cliente.** Portada en la lista y galería en el detalle.
- [x] **F04P-T8 — Verificación.** Suites, PostgreSQL real, recorrido en el emulador y el panel, documentación y plan.

## Registro de ejecución

### 2026-10-04 — F04P-T0, prueba previa de Floci

- El stack local no tenía bucket (`list-buckets` vacío). Se ejecutó el script documentado `infra/docker/init-local-resources.ps1`, que creó `roomforge-local-assets` y la cola `roomforge-local-events` (solo crea lo que falta).
- Enlaces firmados SigV4 generados con `boto3` (estilo de ruta, firmados para `http://127.0.0.1:4566`) desde un contenedor descartable y usados desde el equipo anfitrión: `PUT` firmado `200` y `GET` firmado `200` con bytes idénticos. El patrón funciona contra Floci.
- **Hallazgo:** con la configuración del stack, Floci **no valida firmas**: también respondió `200` a un `GET` con la firma alterada, a un `GET` sin firma y a un `PUT` con otro `Content-Type`. En local, el almacenamiento no aplica control de acceso; cualquiera que conozca la clave del objeto puede leerlo.
- Floci tiene la opción `floci.auth.validate-signatures` (`FLOCI_AUTH_VALIDATE_SIGNATURES=true`). Probada en un Floci descartable aparte (puerto 4567, memoria): rechaza incluso los enlaces bien firmados con `SignatureDoesNotMatch`, también con `FLOCI_AUTH_PRESIGN_SECRET`, y la escritura con cabeceras se aceptó aun con un secreto incorrecto. No sirve para validar el patrón estándar; se descartó sin cambiar el stack.
- **Consecuencia para el diseño:** en local, la seguridad de las fotos depende del backend (quién recibe enlaces, claves con UUID no predecibles, validación y limpieza al confirmar). La validación de firma, vencimiento y `Content-Type` en el almacenamiento solo la aplica S3 real (F11); queda registrado como límite y no se presentará como verificado en local.
- Limpieza: objeto de prueba `t0/probe.png` borrado; el bucket quedó vacío; el Floci descartable se eliminó.
- Pendiente de T0: alcance del emulador con `adb reverse tcp:4566 tcp:4566` (no había emulador abierto); se comprueba en T5.

### 2026-10-04 — F04P-T1 a F04P-T4, backend

- **T1:** `test_listing_photo_migration_upgrades_and_downgrades_sqlite` (`tests/test_catalog_migration.py`) falló antes de existir la migración (RED) y pasó después: columnas, índice, restricciones de estado, tipo, tamaño (1 B a 5 MB), coherencia `status`/`confirmed_at`, clave única, clave foránea al inmueble y reversión. Modelo `ListingPhoto` con las mismas restricciones; la columna antigua `listing.photos` no se tocó.
- **T2:** `app/modules/catalog/photo_storage.py`: protocolo `PhotoStorage`, `S3PhotoStorage` (cliente interno para leer, escribir y borrar; firmante con la dirección pública, porque la firma SigV4 incluye el host), `InMemoryPhotoStorage` para pruebas y `create_photo_storage` (sin bucket configurado no hay almacenamiento). Configuración nueva: `S3_BUCKET_NAME`, `S3_PUBLIC_ENDPOINT_URL`, `AWS_DEFAULT_REGION`. Dependencias `boto3` y `Pillow` agregadas al `pyproject.toml`; imagen de pruebas reconstruida. Pruebas (6) en `tests/test_listing_photos.py`: RED por módulo inexistente; dos pasaron a GREEN después de definir credenciales ficticias en el entorno de la prueba, como las recibe la API en el stack.
- **T3:** `app/modules/catalog/photos.py` (servicio) y `app/modules/catalog/photo_router.py` (rutas), registradas en `create_app`, que acepta `photo_storage` inyectado. Rutas bajo `/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/photos`: pedir subida (`201`, enlace `PUT` firmado por 15 minutos, clave decidida por el servidor), confirmar (lee el objeto, exige el formato declarado, como máximo 40 megapíxeles y 5 MB; aplica la orientación y vuelve a codificar sin EXIF ni XMP; una subida inválida se borra con su fila y responde `422`; sin objeto `409`; ventana vencida `409`; confirmación repetida idempotente), listar confirmadas con enlaces de lectura de 10 minutos y borrar (`204`). Límite de 10 fotos contando confirmadas y pendientes vigentes; las pendientes vencidas se borran al pedir otra subida. Confirmar o borrar una foto confirmada devuelve el inmueble a borrador, lo retira del catálogo y registra `edit`, sin cambiar `offer_version`. El envío a revisión exige una foto confirmada (`409`). Mismos permisos que la ficha: otra agencia y `platform_admin` `403`; inmueble o foto ajenos `404` idéntico a inexistente; sin almacenamiento `503`. 40 pruebas nuevas: RED con 40 errores porque `create_app` no aceptaba el almacenamiento; GREEN después. La prueba de limpieza usa un JPEG con orientación 6 y coordenadas GPS en EXIF y comprueba que el resultado no tiene EXIF y quedó rotado.
- **Pruebas existentes ajustadas por la regla nueva:** dos pruebas de `test_f04_publications.py` y la de PostgreSQL envían inmuebles a revisión; ahora siembran una foto confirmada antes de enviar. Fallaron exactamente esas dos antes del ajuste.
- **T4:** el catálogo público agrega `cover_photo_url` (primera foto confirmada o `null`) en cada ítem y `photos` (`photo_id`, `url`) en el detalle, solo para inmuebles publicados y solo con fotos confirmadas; sin almacenamiento configurado, portada `null` y lista vacía. 2 pruebas nuevas (RED por `KeyError: 'cover_photo_url'`, luego GREEN). Tres pruebas de `test_catalog.py` que fijan la forma exacta del contrato público se actualizaron con los dos campos; la que verifica que la columna antigua `photos` no se expone sigue igual.
- **Verificación:** suite backend 555 aprobadas, 3 omitidas; Ruff y Pyright sin errores. `test_f04_publications_postgres.py` contra PostgreSQL 16 descartable: `1 passed`, la cadena de migraciones llega a `0013_listing_photos`.
- **Stack local:** `S3_PUBLIC_ENDPOINT_URL=http://127.0.0.1:4566` agregado a `compose.local.yml` y `local-env.example`; migración `0013` aplicada a la base local (`0012` → `0013`) desde la imagen de pruebas conectada a la red del stack; imagen `api` reconstruida y `healthy`, con las tres rutas de fotos en el OpenAPI.

### 2026-10-06 — Prueba manual del backend contra el stack local

- El usuario ejecutó un script de PowerShell (fuera del repositorio) como `agente@example.test`, con sesión TOTP real, sobre el inmueble «Oruro, Barrio Fátima»: enviar a revisión sin foto `409`; pedir subida `201`; `PUT` directo a Floci con el enlace firmado `200`; confirmar `200`; listar; enviar a revisión con foto `pending`. Historial resultante: `create`, `edit` (la foto), `submit`.
- Luego aprobó y publicó el inmueble desde el panel como `agencia@example.test` (`approve`; en la primera consulta faltaba `publish` y el catálogo no lo mostraba, comportamiento esperado). Ya publicado, `GET /api/v1/listings` devolvió `cover_photo_url` y el usuario abrió la foto en el navegador con ese enlace. Los tres inmuebles publicados antes de F04.2 siguen visibles con `cover_photo_url: null`.
- Objeto almacenado en Floci (`agencies/agencia-demo/listings/482f5a36…/photos/…`), leído con `boto3` y Pillow desde la imagen de pruebas: JPEG 1200×1600, 345 327 bytes, 0 entradas EXIF, 0 entradas GPS, sin XMP. No se comprobó si el archivo original tenía GPS; la eliminación de GPS está probada con un JPEG sintético en `test_confirm_validates_and_rewrites_the_photo_without_metadata`.

### 2026-10-06 — F04P-T5, app de captura

- Dependencia `image_picker ^1.2.4` agregada con `flutter pub add` (`pubspec.lock` sigue sin versionar).
- `lib/data/services/staff_listing_photos_api.dart` y `lib/data/models/listing_photo.dart`: listar, pedir subida, subir al enlace firmado con `StreamedRequest` (longitud declarada, progreso por bloques de 64 KB, sin cabecera `Authorization` hacia el almacenamiento), confirmar y borrar. `test/staff_listing_photos_api_test.dart` (8): RED por archivo inexistente, luego GREEN.
- `lib/data/services/photo_source.dart`: interfaz `PhotoSource`, `ImagePickerPhotoSource` (máximo 2560 px, calidad 85, sin pedir metadatos completos) y detección del formato por la firma de los bytes, no por la extensión. `test/photo_source_test.dart` (3): RED y GREEN.
- `lib/domain/listing_photos_controller.dart`: carga, subida con progreso, reintento reutilizando el enlace mientras es válido (o pidiendo otro si la API descartó la subida), descartar liberando el lugar reservado, borrar, límite de 10, rechazo local de formatos no admitidos y de más de 5 MB, y aviso al editor cuando la API devuelve el inmueble a borrador. `test/listing_photos_controller_test.dart` (12): RED y GREEN. `test/support/fake_listings_backend.dart` reproduce las rutas de fotos, el almacenamiento, el límite y la regla de foto mínima al enviar; `test/support/fake_photo_source.dart` reemplaza la cámara.
- `ListingDraftsController` recibe la API de fotos y el origen, y crea el controlador de fotos de cada inmueble guardado; un `409` por falta de foto se explica como «Agregá al menos una foto…».
- **Desvío de TDD registrado:** `lib/ui/listings/listing_photos_section.dart` (la sección visual) se escribió antes que sus pruebas. Para la integración en la ficha se volvió al orden correcto: las 6 pruebas nuevas o ajustadas de `test/listings_screens_test.dart` fallaron antes de integrar (RED) y pasaron después.
- Ficha (`listing_editor_screen.dart`): sección «Fotos (n de 10)» antes de los botones; sin guardar, «Guardá el borrador para agregar fotos»; envío deshabilitado sin foto o con una subida en curso, con aviso; confirmación antes de borrar y, si el inmueble está en revisión o aprobado, aviso de que vuelve a borrador; el estado mostrado pasa a «Borrador» tras el cambio.
- **Defecto encontrado y corregido:** si el almacenamiento fallaba mientras se escribía el cuerpo, el error de la petición quedaba sin escuchar y se reportaba como error no manejado en vez de mostrarse en la miniatura. Se observa ahora desde el inicio (`unawaited(sending.then(...))`). Lo detectó la prueba «retries a failed upload from its tile».
- **Ajuste de prueba por el entorno:** la subida transmite el cuerpo por un `Stream` que en las pruebas de widgets solo avanza con el bucle de eventos real; el ayudante `_settleUpload` usa `tester.runAsync`. No cambia el comportamiento de la app.
- Pruebas existentes ajustadas por la regla de foto mínima: el envío en `listing_drafts_controller_test.dart` y el flujo de la ficha siembran o agregan una foto; `widget_test.dart` pasa las dependencias nuevas a `CaptureApp`.
- **Verificación:** `flutter test` 106/106, `flutter analyze --no-pub` sin hallazgos, `dart format` sin cambios en los archivos de la tarea.
- **Emulador:** APK de depuración compilado (Gradle detenido después), instalado y `adb reverse tcp:4566 tcp:4566` configurado; con esto queda cerrado lo pendiente de T0 (el emulador alcanza Floci por `127.0.0.1:4566`). Recorrido del usuario como `agente@example.test`: nuevo inmueble «Cochabamba, Barrios Callejas», tres fotos subidas desde la app y confirmadas (619 275, 99 656 y 72 168 bytes, JPEG), envío a revisión y aprobación posterior en el panel. Resultado informado por el usuario: «funciona perfectamente». Logs de la API: 4 pedidos de subida `201` y 4 confirmaciones `200` en la ventana revisada (uno del script de PowerShell anterior). No hubo borrados en esa ventana: el borrado desde la app solo está cubierto por pruebas automáticas.
- `README.md` de la app: fotos, `adb reverse` y creación del bucket.

### 2026-10-06 — F04P-T6, panel

- `src/application/staffListingsApi.ts`: tipo `ListingPhoto` y `listListingPhotos` (`GET .../photos` con Bearer). `src/features/listings/AgencyReviewQueue.tsx`: sección «Fotos» en el detalle de revisión, antes del historial, con cuadrícula de imágenes (texto alternativo «Foto n de m · ciudad · zona»), enlace a tamaño completo en otra pestaña, nota de portada y estado vacío «Este inmueble no tiene fotos.». Las fotos se cargan aparte del detalle: si fallan, se muestra «No se pudieron cargar las fotos del inmueble.» y las acciones de revisión siguen disponibles. Estilos en `src/styles.css`.
- TDD: 5 pruebas nuevas (2 de la API, 3 del detalle) fallaron antes de implementar (RED: función inexistente y elementos ausentes) y pasaron después; las pruebas existentes simulan una lista de fotos vacía.
- Verificación en `node:22`: `vitest` 102/102; `npm run build` (`tsc --noEmit` y Vite) sin errores. Contenedor `panel` reconstruido y `healthy`.
- Prueba manual del usuario como `agencia@example.test`: el detalle de «Cochabamba, Barrios Callejas» muestra sus tres fotos y un inmueble antiguo muestra el estado vacío. Resultado informado: «funciona bien».
- Límite: los enlaces de lectura vencen a los 10 minutos; un detalle abierto más tiempo necesita reabrirse.

### 2026-10-07 — F04P-T7, app cliente

- `lib/data/models/catalog_models.dart`: `CatalogListing.coverPhotoUrl` (nulo sin fotos; un valor que no sea texto es un contrato roto) y `CatalogListingDetail.photos` (`CatalogPhoto`: `photoId`, `url`), en el orden de la API.
- `lib/ui/features/catalog/views/listing_photo.dart` (nuevo): `ListingPhoto` (imagen de red con texto alternativo; un enlace que no carga, por ejemplo vencido, cae al recuadro neutro) y `PhotoPlaceholder`. La tarjeta de la lista muestra la portada (160 px de alto) o el recuadro; el detalle abre con una galería deslizable (240 px) con «Foto n de m», o con «Este inmueble todavía no tiene fotos.».
- TDD: 6 pruebas nuevas (3 de la API, 3 de pantallas) fallaron antes de implementar (RED: compilación por campos inexistentes y elementos ausentes) y pasaron después. `test/support/fake_catalog_backend.dart` siembra fotos como la API.
- Ajustes durante GREEN: con la proporción 16:9 o 4:3 sobre 720 px de ancho las imágenes medían unos 400 px y empujaban el contenido fuera de lo que la lista construye, rompiendo tres pruebas existentes; se fijaron alturas de 160 y 240 px. La prueba del detalle ahora se desplaza hasta las secciones inferiores, que quedaron debajo de la galería. Dos pruebas nuevas buscaban `Image` en la clave del componente que la envuelve; se corrigieron para buscarla dentro.
- Verificación: `flutter test` 83/83, `flutter analyze --no-pub` sin hallazgos, formato limpio en los archivos de la tarea. APK de depuración compilado (Gradle detenido) e instalado en el emulador, con `adb reverse tcp:4566 tcp:4566` activo.
- Prueba manual del usuario en el emulador, sin iniciar sesión: portadas en la lista, recuadro neutro en los inmuebles sin fotos y galería en el detalle. Resultado informado: «funciona muy bien».

### 2026-10-07 — F04P-T8, cierre

- Verificación final sobre los commits `a8b8448`, `8594413`, `a1e6f32` y `596ee2d`:
  - backend: 555 aprobadas, 3 omitidas; Ruff y Pyright sin errores;
  - `test_f04_publications_postgres.py` contra PostgreSQL 16 descartable: `1 passed`, head `0013_listing_photos`;
  - app de captura: `flutter test` 106/106 y `flutter analyze` sin hallazgos;
  - app cliente: 83/83 y sin hallazgos;
  - panel: `vitest` 102/102 y `npm run build` sin errores.
- Contratos:
  - `docs/api/f04-publications-v1.md`: rutas de fotos, flujo, cuerpos y respuestas, reglas, fila de autorización con sus pruebas, errores `409`, `422` y `503`, y límites (Floci sin validación de firmas, sin política de retención).
  - `docs/api/catalog-reservations-v1.md`: `cover_photo_url` en lista y detalle y `photos` en el detalle, como nota fechada.
- Plan maestro: línea de avance de F04 con F04.2 implementada en la rama; el cuadro §1.4.1 se actualiza al integrar en `main`.
- Pendiente fuera de esta tarea:
  - política de retención y borrado de fotos (plan F04.2, sin decisión);
  - verificación del control de firmas en S3 real (F11);
  - CP-011 menciona «verificación del difuminado», que el plan declara función adicional y no promesa: se trata en el punto académico de F04.

### 2026-10-07 — Integración sobre `main` actualizado

- Mientras se hacía F04.2, `main` integró la primera parte de F04 (PR #12 y #13) y F05 con multi-moneda (PR #14 y #15). Los commits de fotos se aplicaron uno por uno en la rama nueva `feat/f04-listing-photos`, creada desde `origin/main` (`03d93ae`).
- **Migración renumerada:** `0013_listing_photos` pasó a ser `0018_listing_photos`, con `down_revision = "0017_exchange_rate_source"`, porque `main` ya ocupaba `0013` a `0017`. Las entradas anteriores de este registro conservan el nombre original.
- **Conflictos resueltos:**
  - backend: el error nuevo junto a `InvalidExtraReferenceError`; los imports del router; el detalle público con los extras de F05 (`_public_extra_item` con moneda) más `photos`; la prueba de migración agregada al final de las de F05;
  - backend falso de la app cliente: moneda y fotos;
  - contrato y plan: la fila de depósito de F05 más la fila de fotos, y un párrafo propio para F04.2 debajo de la línea reescrita por el PR #13.
- **Ajustes por la combinación:**
  - cinco pruebas nuevas de F05 enviaban inmuebles a revisión sin foto; ahora siembran una foto confirmada, igual que las de F04;
  - `StaffListing.reopenedAsDraft()` de la app de captura conserva el campo `currency` nuevo;
  - `apps/captura_mobile/pubspec.lock`, que ahora se versiona en `main`, incluye `image_picker`.
- **Verificación sobre la base combinada:**
  - backend: 657 aprobadas, 3 omitidas; Ruff y Pyright sin errores;
  - PostgreSQL 16 descartable: `1 passed`, head `0018_listing_photos`;
  - app de captura: 115/115, análisis y formato limpios;
  - app cliente: 89/89, análisis limpio;
  - panel: 123/123 y build.
- **Pendiente para el usuario, sin ejecutar:** la base local de desarrollo quedó en la revisión `0013_listing_photos` de la rama anterior. Deshacerla, que borra la tabla `listing_photo` y sus filas de prueba, quedó bloqueado por los permisos de la sesión; el usuario decide cuándo ejecutarlo antes de aplicar la cadena nueva.
