# Captura (Flutter)

Prototipo local de interfaz para la app de captura del agente inmobiliario.

- Stack: Flutter 3.41.8 / Dart 3.11.5, Material 3.
- Superficie implementada: paso de acceso (solo UI) y estado vacío de borradores con la acción `Nuevo inmueble`.
- Estado: prototipo de UX en construcción; no hay backend, autenticación, cámara, almacenamiento ni sincronización.
- Trazabilidad: `odd/tasks/f02-t4e-capture-prototype.md` y `docs/ux/f02-surface-map.md`.

## Alcance y límites

- El acceso es una interacción de prototipo: no pide credenciales, no abre sesión y no valida identidad.
- La lista de borradores arranca vacía: no hay inmuebles, precios, monedas, fotos ni geometría de ejemplo.
- La acción `Nuevo inmueble` solo muestra un aviso local; el asistente de creación todavía no está construido.
- Los pasos de captura, permisos simulados, corrección de geometría y envío corresponden a unidades posteriores y no están implementados.
- Sin directorios Android/iOS generados, sin plugins nativos, sin dependencias externas y sin `pubspec.lock` versionado.

## Verificación

```bash
flutter test test/widget_test.dart
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed lib/main.dart test/widget_test.dart
```

Estos comandos requieren un checkout Flutter con las dependencias resueltas (`flutter pub get`); el repositorio no versiona `pubspec.lock`.
