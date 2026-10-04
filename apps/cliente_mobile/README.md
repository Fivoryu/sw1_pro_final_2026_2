# Aplicación cliente (Flutter)

## Estado actual

- **Explorar (F04.4):** catálogo público real sobre `GET /api/v1/listings` y `GET /api/v1/listings/{listing_id}` (`docs/api/catalog-reservations-v1.md`). Muestra solo inmuebles aprobados y publicados, sin iniciar sesión, con filtros de ciudad, zona, operación, rango de precio base, dormitorios y baños mínimos, paginación con «Cargar más» y estados de carga, vacío, error y sin conexión. El detalle muestra precio base con su periodicidad (alquiler por mes, venta de pago único), dormitorios, baños y opcionales con su precio.
- **Cuenta:** registro, inicio y cierre de sesión de cliente sobre `/api/v1/customer/auth/*`; el refresh se guarda en almacenamiento seguro.
- **Reservas:** sigue siendo un prototipo rotulado, sin datos conectados.
- Trazabilidad: `odd/tasks/f04-client-catalog.md` y `odd/tasks/cliente-catalog.md`.

### Límites

- Ciudad y zona se filtran por nombre completo (sin distinguir mayúsculas), como la API.
- Los importes se muestran en COP según la decisión D-01 y se manejan como texto decimal, nunca como `double`.
- No hay cotización (F05), recorrido 3D (F06), reservas ni wallet (F09/F10) ni fotos (F04.2): el detalle lo dice en lugar de mostrar datos ajenos. La disponibilidad no se consulta porque la API pública no la expone.
- La app usa `http://10.0.2.2:8000` por defecto, que desde el emulador Android apunta a la API del equipo anfitrión; otro backend se indica con `--dart-define=ROOMFORGE_API_BASE_URL=https://host`.

## Plataformas y verificaciones

Se requiere Flutter con Dart SDK `^3.11.5`. El proyecto incluye runners nativos
para Android e iOS. Sus identificadores actuales (`com.example.cliente_mobile`
y `com.example.clienteMobile`) son valores de ejemplo y deben definirse antes de
una distribución.

Comandos principales:

```bash
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
```

| Verificación | Resultado en este corte |
| --- | --- |
| `flutter test` | Correcto: 77 pruebas. |
| `flutter analyze` | Correcto: sin problemas reportados. |
| `flutter build apk --debug` | Correcto: APK de depuración generado. |
| Build de iOS | No ejecutado: el entorno Windows no dispone de Xcode. |

El README original de los recursos de lanzamiento iOS se conservó.
