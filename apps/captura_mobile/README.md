# Captura (Flutter)

App de captura del agente inmobiliario: acceso de personal y borradores de inmuebles (F04) contra la API, más pantallas de prototipo de fases futuras.

- Stack: Flutter 3.41.8 / Dart 3.11.5, Material 3.
- Superficie real: acceso de personal con contraseña y TOTP (F03), y «Mis inmuebles» (F04): lista por estado (borradores, rechazados, en revisión), ficha del inmueble con validación, guardar borrador y envío a revisión con confirmación.
- Prototipos de fases futuras (sin backend): ambientes/fotos, geometría y objetos, preparación de oferta y resumen de envío.
- Trazabilidad: `odd/tasks/f04-capture-drafts.md`, `odd/tasks/f03-capture-staff-origin.md`, `odd/tasks/f02-t4e-capture-prototype.md` y `docs/ux/f02-surface-map.md`.

## Alcance y límites

- El acceso abre una sesión de personal real; el token de acceso vive solo en memoria y el refresh se guarda en almacenamiento seguro.
- «Mis inmuebles» usa las rutas de personal de `docs/api/f04-publications-v1.md`: la agencia sale de la sesión y la autorización la decide el servidor. El agente ve todos los inmuebles de su agencia.
- La ficha valida lo mismo que la API (precio con hasta 16 enteros y 2 decimales y mayor que cero, ciudad y zona de 1 a 120 caracteres, conteos enteros). El precio se muestra en COP (decisión D-01 de `docs/api/catalog-reservations-v1.md`).
- Guardar un inmueble ya enviado o aprobado lo devuelve a borrador; un rechazado muestra el motivo de la última revisión.
- Fotografías (F04.2) no están implementadas: la cámara todavía no está disponible.
- Las pantallas de prototipo de fases futuras no están en el recorrido real; sus estados son simulados y no guardan ni envían nada.
- Runner Android generado con `flutter create --platforms=android --org com.example` (sin iOS). Solo la variante de depuración permite HTTP sin cifrar (`android/app/src/debug/AndroidManifest.xml`) para llegar a la API local; `pubspec.lock` no se versiona.

## Verificación

```bash
flutter test
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed lib test
```

Estos comandos requieren un checkout Flutter con las dependencias resueltas (`flutter pub get`); el repositorio no versiona `pubspec.lock`.

## Ejecutar en el emulador

Con el stack local levantado (`infra/README.md`) y un emulador Android iniciado:

```bash
flutter run
```

La app usa `http://10.0.2.2:8000` por defecto, que desde el emulador apunta a la API del equipo anfitrión; otro backend se indica con `--dart-define=ROOMFORGE_API_BASE_URL=https://host`.
