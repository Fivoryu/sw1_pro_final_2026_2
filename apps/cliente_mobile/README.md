# Aplicación cliente (Flutter)

## Estado actual

- **Explorar (F04.4):** catálogo público real sobre `GET /api/v1/listings` y `GET /api/v1/listings/{listing_id}` (`docs/api/catalog-reservations-v1.md`). Muestra solo inmuebles aprobados y publicados, sin iniciar sesión, con filtros de ciudad, zona, operación, rango de precio base, dormitorios y baños mínimos, paginación con «Cargar más» y estados de carga, vacío, error y sin conexión. El detalle muestra precio base con su periodicidad (alquiler por mes, venta de pago único), dormitorios, baños y opcionales con su precio.
- **Recorrido 3D (F06.4/F06.5):** el detalle abre `ListingViewerScreen`, que monta en una WebView el visor local vendoreado, sin CDN ni URLs remotas. Los controles táctiles usan un joystick en la mitad izquierda para moverse y arrastre en la mitad derecha para mirar; el recorrido aplica colisiones y permite atravesar las aberturas de puerta. Muestra carga, error con reintento y «Recorrido 3D no disponible» si el inmueble no tiene escena o no es público, sin simular una escena vacía. El hotspot abre la ficha del objeto y, al confirmar, la pantalla de cotización; `objects[].id` debe ser el `extra_id` de un extra publicado del inmueble.
- **Cuenta:** registro, inicio y cierre de sesión de cliente sobre `/api/v1/customer/auth/*`; el refresh se guarda en almacenamiento seguro.
- **Reservas:** sigue siendo un prototipo rotulado, sin datos conectados.
- Trazabilidad: `odd/tasks/f04-client-catalog.md`, `odd/tasks/cliente-catalog.md` y `odd/tasks/f06-customer-walkthrough.md`.

### Límites

- Ciudad y zona se filtran por nombre completo (sin distinguir mayúsculas), como la API.
- Los importes se muestran en COP según la decisión D-01 y se manejan como texto decimal, nunca como `double`.
- No incluye captura espacial (F07), realidad aumentada (AR), detección de mobiliario con IA (F08) ni recorrido panorámico (F14.1). El visor no ofrece flujos de reserva ni wallet. Las mediciones en Samsung Galaxy S23 FE siguen pendientes; por tanto, no se afirman resultados de rendimiento.
- La app usa `http://10.0.2.2:8000` por defecto, que desde el emulador Android apunta a la API del equipo anfitrión; otro backend se indica con `--dart-define=ROOMFORGE_API_BASE_URL=https://host`.

## Plataformas y verificaciones

Se requiere Flutter con Dart SDK `^3.11.5`. El proyecto incluye runners nativos
para Android e iOS. Sus identificadores actuales (`com.example.cliente_mobile`
y `com.example.clienteMobile`) son valores de ejemplo y deben definirse antes de
una distribución.

Comandos principales (desde `apps/cliente_mobile/`):

```bash
flutter pub get
flutter test
node --test   # geometría del recorrido (colisiones, aberturas, límites)
flutter analyze
flutter build apk --debug
```

| Verificación | Resultado en este corte |
| --- | --- |
| `flutter test` | Correcto: 132 pruebas. |
| `node --test` | Correcto: 14 pruebas (geometría del recorrido). |
| `flutter analyze` | Correcto: sin problemas reportados. |
| `flutter build apk --debug` | Correcto: APK de depuración generado. |
| Build de iOS | No ejecutado: el entorno Windows no dispone de Xcode. |

El README original de los recursos de lanzamiento iOS se conservó.
