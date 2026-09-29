# Aplicación cliente (Flutter)

## Estado de este snapshot

Este checkout contiene únicamente el shell inicial de RoomForge: una pantalla
Material que informa que el catálogo está pendiente de integración. No muestra
publicaciones ficticias ni consulta una API.

La autenticación, la gestión de sesión, la persistencia de credenciales y la
integración del catálogo **no están implementadas en este snapshot**. El README
anterior describía capacidades de código que no existe en este checkout; esas
afirmaciones no deben tomarse como comportamiento disponible o verificado.
Tampoco hay un contrato canónico de catálogo configurado en esta app.

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
| `flutter test` | Correcto: 2 pruebas. |
| `flutter analyze` | Correcto: sin problemas reportados. |
| `flutter build apk --debug` | Correcto: APK de depuración generado. |
| Build de iOS | No ejecutado: el entorno Windows no dispone de Xcode. |

El build Android no implica que las funciones de autenticación o catálogo estén
implementadas. El README original de los recursos de lanzamiento iOS se conservó.
