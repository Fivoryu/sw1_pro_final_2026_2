# Captura (Flutter)

Prototipo local de interfaz para la app de captura del agente inmobiliario.

- Stack: Flutter 3.41.8 / Dart 3.11.5, Material 3.
- Superficie implementada: paso de acceso (solo UI), estado vacío de borradores, datos básicos y operación, ambientes/fotos con permisos, conectividad, error/reintento y captura simulados, y corrección de geometría y objetos con formas ilustrativas.
- Estado: prototipo de UX en construcción; no hay backend, autenticación, cámara, almacenamiento ni sincronización.
- Trazabilidad: `odd/tasks/f02-t4e-capture-prototype.md` y `docs/ux/f02-surface-map.md`.

## Alcance y límites

- El acceso es una interacción de prototipo: no pide credenciales, no abre sesión y no valida identidad.
- La lista de borradores arranca vacía: no hay inmuebles, precios, monedas, fotos ni geometría de ejemplo.
- La acción `Nuevo inmueble` abre un asistente local de cinco pasos: datos básicos y operación, ambientes/fotos, corrección de geometría y objetos, preparación de oferta y resumen de envío. Los cinco pasos existen como pantallas de prototipo.
- Nada del flujo se guarda: el estado vive únicamente en memoria mientras la pantalla está abierta, y el acceso no pide credenciales.
- La captura de fotos, los permisos y la conectividad son estados simulados rotulados; las formas de geometría son ilustrativas y no provienen de fotos, medición ni reconstrucción.
- La preparación de oferta muestra solo la estructura conceptual aprobada (precio base, ajustes seleccionados y total con dos decimales) sin precio, moneda, impuestos, cargos, descuentos ni vigencia, y el envío a revisión exige confirmación explícita antes de un estado pendiente simulado.
- El prototipo no guarda, no sincroniza y no envía nada: no hay persistencia, carga ni notificación real.
- Runner Android generado con `flutter create --platforms=android --org com.example` (sin iOS). Solo la variante de depuración permite HTTP sin cifrar (`android/app/src/debug/AndroidManifest.xml`) para llegar a la API local; `pubspec.lock` no se versiona.

## Verificación

```bash
flutter test test/widget_test.dart
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed lib/main.dart test/widget_test.dart
```

Estos comandos requieren un checkout Flutter con las dependencias resueltas (`flutter pub get`); el repositorio no versiona `pubspec.lock`.

## Ejecutar en el emulador

Con el stack local levantado (`infra/README.md`) y un emulador Android iniciado:

```bash
flutter run
```

La app usa `http://10.0.2.2:8000` por defecto, que desde el emulador apunta a la API del equipo anfitrión; otro backend se indica con `--dart-define=ROOMFORGE_API_BASE_URL=https://host`.
