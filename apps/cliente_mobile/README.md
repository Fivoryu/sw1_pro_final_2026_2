# Cliente mobile (Flutter)

Aplicación cliente para autenticación y gestión de sesión. El catálogo,
recorridos 3D y reservas todavía no forman parte de esta entrega.

## Estado implementado

- Registro contra `POST /api/v1/auth/register`.
- Inicio de sesión contra `POST /api/v1/auth/login`.
- Restauración de sesión mediante `GET /api/v1/auth/me`.
- Rotación de tokens una sola vez ante una respuesta `401`, persistida solo
  después de confirmar la sesión con `/auth/me`.
- Cierre de sesión contra `POST /api/v1/auth/logout`, con limpieza local aun si
  la solicitud falla.
- Credenciales persistidas mediante `flutter_secure_storage`, detrás de una
  abstracción testeable sin plugins nativos.
- Navegación declarativa con `go_router` y formularios accesibles y adaptables.

## Configuración y ejecución

Requiere Flutter con Dart SDK `^3.11.5`.

```bash
flutter pub get
flutter test
flutter analyze
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

`API_BASE_URL` debe ser la URL base que ya incluye `/api/v1`. El valor
predeterminado es `http://10.0.2.2:8000/api/v1`, que permite acceder al host
desde un emulador Android. En un dispositivo físico o en otra plataforma,
reemplazalo por la dirección accesible del backend, por ejemplo:

```bash
flutter run --dart-define=API_BASE_URL=http://<host-accesible>:8000/api/v1
```

### Red local en desarrollo y producción

Los builds `debug` y `profile` permiten el backend HTTP local documentado: en
Android la excepción `usesCleartextTraffic` vive únicamente en los manifests
de esas variantes, y en iOS se permite solo `NSAllowsLocalNetworking`. El
permiso de Internet está declarado en el manifest principal para todas las
variantes.

Los builds de producción deben usar un backend HTTPS; configurá, por ejemplo:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

No habilites cleartext globalmente ni uses una URL HTTP en producción.

No se guardan secretos en el repositorio ni en los comandos documentados. Los
tokens se reciben en tiempo de ejecución y se almacenan únicamente en el
almacenamiento seguro del dispositivo.
