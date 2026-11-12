# F14.5 — Guía de prueba en dispositivo: búsqueda por zona

Esta guía cubre lo que las pruebas automatizadas no pueden ejercer: el permiso de ubicación del sistema operativo y la carga real de las teselas de OpenStreetMap. Las pruebas de `apps/cliente_mobile/test/zone_search_test.dart` usan un servicio de ubicación falso y un proveedor de teselas sin red.

**Estado:** ☐ sin ejecutar en un dispositivo físico o emulador Android/iOS. Al 2026-11-12 el entorno de desarrollo solo tenía Windows y navegadores disponibles. Registrar el resultado en la issue #76 al ejecutarla; no marcar la fase como cerrada sin esa evidencia.

## Preparación

1. Backend local con al menos dos inmuebles publicados con coordenadas, uno a menos de 5 km y otro a más de 10 km del punto de prueba, y uno publicado sin coordenadas.
2. App cliente instalada en un dispositivo con la ubicación del sistema encendida.
3. Opcional: construir con otro proveedor de teselas, por ejemplo `flutter run --dart-define=MAP_TILE_URL=<plantilla> --dart-define=MAP_USER_AGENT=<identificador>`. Sin esas variables se usa el servidor público de OpenStreetMap con el identificador `roomforge-cliente-sw1-g12`.

## Casos

| # | Situación | Pasos | Resultado esperado |
|---|---|---|---|
| 1 | Permiso concedido | Filtrar catálogo → «Usar mi ubicación» → conceder «Mientras se usa la app» → «Aplicar filtros». | Aparece el radio de 5 km y la etiqueta «Zona». El catálogo muestra solo el inmueble cercano. |
| 2 | Solo ubicación aproximada (Android 12+) | Repetir el caso 1 concediendo «Aproximada». | Funciona igual. |
| 3 | Permiso denegado una vez | «Usar mi ubicación» → denegar. | Mensaje «No diste permiso de ubicación…» y se abre el mapa. Volver a tocar el botón vuelve a pedir el permiso. |
| 4 | Permiso bloqueado | Denegar con «No volver a preguntar», o bloquearlo en Ajustes. | Mensaje que indica habilitarlo en Ajustes o elegir un punto en el mapa. |
| 5 | Ubicación del sistema apagada | Apagar la ubicación y tocar el botón. | Mensaje «La ubicación del teléfono está apagada…» y se abre el mapa. |
| 6 | Sin permiso, punto a mano | En cualquiera de los casos 3 a 5, tocar el mapa y aplicar. | El catálogo se filtra por el punto elegido; el círculo muestra el radio. |
| 7 | Radio | Mover el control entre 1 y 50 km y aplicar. | La lista cambia según el radio; el inmueble a más de 10 km aparece al ampliar a 15 km o más. |
| 8 | Inmueble sin coordenadas | Con zona activa. | No aparece. Al quitar la zona, vuelve a aparecer en el catálogo general. |
| 9 | Mapa sin red | Activar modo avión, abrir el mapa. | Tarjeta de error «No se pudo cargar el mapa…» con «Reintentar». Con la red de vuelta, «Reintentar» carga las teselas. |
| 10 | Privacidad | Cerrar y volver a abrir la app. | La zona no se conserva. Revisar que el registro de acceso del backend muestre `latitude=[redacted]` y `longitude=[redacted]`. |

## App de captura y panel

| # | Situación | Pasos | Resultado esperado |
|---|---|---|---|
| 11 | Marcar punto al crear | Editor de inmueble → tocar el mapa → guardar. | El inmueble guardado conserva latitud y longitud; «Quitar ubicación» las borra. |
| 12 | Corregir en el panel | Panel → detalle del inmueble publicado → mover el marcador → «Guardar ubicación». | Pide confirmación; al guardar, el inmueble vuelve a borrador y sale del catálogo público hasta ser aprobado de nuevo. |
