# F14.5 — Búsqueda de inmuebles por zona

**Objetivo:** el cliente encuentra inmuebles cercanos a su ubicación o dentro de un radio alrededor de un punto que elige. **Plan:** `docs/plan-maestro-roomforge.md` F14.5. **Issue:** #76.
**Rama:** `feat/f14-zone-search` desde `main` actualizado. **Entrega:** `ask-on-risk`.
**Ejecutores de pruebas:** `backend` con `<raiz>/.venv/Scripts/python.exe -m pytest`, Ruff y Pyright; apps con `flutter test` y `flutter analyze`; `panel` con `vitest`.

## Specs

Las citas entre comillas son texto literal del dueño del repositorio. **[Propuesta]** = planteada por el asistente en la sesión de diseño y no objetada por el usuario; confirmar ante cualquier duda.

- **S1 — Búsqueda por cercanía o por punto y radio.** «En si el cliente ve todos los inmuebles de las agencias, la idea es que vea por zonas que esten cerca de su ubicación o que pueda seleccionar una ubicación y poner un rango de km y visualizar los inmuebles que estan en dicha zona.»
  - Aceptación: con un punto y un radio, el catálogo público devuelve solo los inmuebles publicados dentro de ese radio; sin esos parámetros el catálogo se comporta igual que hoy.
- **S2 — Coordenadas del inmueble.** El agente marca el punto en un mapa al crear o editar el inmueble. Los inmuebles publicados sin coordenadas no aparecen en la búsqueda por zona y siguen apareciendo en el catálogo general. El catálogo público expone la ubicación del inmueble. Cambiar la ubicación de un inmueble publicado lo retira de publicación y lo devuelve a revisión, como una edición normal.
- **S3 — Sin permiso de ubicación. [Propuesta]** El cliente elige un punto en el mapa o una ciudad.
- **S4 — Privacidad. [Propuesta]** La ubicación del cliente viaja solo como parámetro de la consulta y no se guarda.
- **S5 — Distancia y radio.** Distancia en línea recta; radio de 1 a 50 km, 5 km por defecto.
- **S6 — Mapa.** Datos y servidor público de OpenStreetMap para el proyecto académico, sin clave de pago. El proveedor debe ser configurable y se debe mostrar un error si el mapa no carga. Respetar la licencia y las condiciones de uso de la librería y del servidor de teselas.

## Tasks

Estado: ☐ pendiente. Ruta por defecto: en línea.

| ID | Tarea | Specs | Ruta | Estado | Commit / evidencia |
| --- | --- | --- | --- | --- | --- |
| T1 | Backend: coordenadas opcionales en el inmueble (migración Alembic, un solo head, GAP-093), validación de rangos y exposición en borrador, revisión y catálogo. | S2 | delegada | ☑ | `81fd0cf`; 1009 tests aprobados, 16 omitidos; Ruff y Pyright sin errores; migración 0028 aplicada y revertida en SQLite aislado. |
| T2 | Backend: filtro por punto y radio en el catálogo público, con orden por distancia y pruebas de borde (radio mínimo y máximo, inmueble sin coordenadas, parámetros incompletos). | S1, S4, S5 | en línea | ☑ | Commit `feat(catalog): add zone radius search`; 1032 tests + 3 nuevas aprobadas, Ruff y Pyright sin errores; plan PostgreSQL con ambos índices (L12). |
| T3 | App de captura y panel: marcar y corregir el punto del inmueble en un mapa. | S2, S6 | en línea | ☑ | Sin commit aún. App captura: 605 tests aprobados; panel: 207 aprobados y `tsc` sin errores; backend: 1047 aprobados, Ruff y Pyright sin errores (ver L16). |
| T4 | App cliente: permiso de ubicación, selector de punto y radio, y resultados por zona con estados vacío, carga y error. | S1, S3, S5, S6 | en línea | ☑ | Sin commit aún. 172 tests aprobados (13 nuevos), `flutter analyze` sin errores; revisión independiente sin bloqueantes (L17). |
| T5 | Cierre: documentación, contrato de API y filas del plan maestro. | — | en línea | ☑ | Sin commit aún. Contrato de API (`docs/api/catalog-reservations-v1.md`, `docs/api/f04-publications-v1.md`) y estado de F14.5 en el plan maestro (L18). |

**Riesgo previsto:** T1 puede nombrar el ítem 1 (migración) y T3/T4 el ítem 5 (dependencia nueva de mapas).

**Estado verificado (2026-11-12, `main` en `9981b49`, búsqueda por palabras clave, no auditoría):** `backend/app/modules/catalog/models.py` no tiene latitud ni longitud; no se encontró ninguna librería de mapas en `apps/*/pubspec.yaml` ni en el `package.json` del panel. No se ejecutó ninguna suite.

## Log

- **L1 (2026-11-12, usuario):** «En si el cliente ve todos los inmuebles de las agencias, la idea es que vea por zonas que esten cerca de su ubicación o que pueda seleccionar una ubicación y poner un rango de km y visualizar los inmuebles que estan en dicha zona.»
- **L2 (2026-11-12):** el asistente propuso S2–S6 para cubrir huecos; el usuario no los objetó ni los confirmó de forma expresa. A la pregunta de agregar las funcionalidades al plan y crear los documentos respondió «5. Si». Siguiente paso: T1.
- **L3 (usuario):** «Vamos papu» en respuesta a la propuesta de que el agente marque el punto y que los inmuebles sin coordenadas aparezcan en el catálogo general, pero no en búsquedas por radio.
- **L4 (usuario):** «QUe exponga la ubicacion del inmueble» en respuesta a si el catálogo público expone la ubicación exacta.
- **L5:** T1 en `81fd0cf`. Verificación independiente sin hallazgos; 1009 tests aprobados y 16 omitidos, Ruff y Pyright sin errores. Migración 0028 aplicada y revertida en SQLite en memoria preservando una fila; la cadena completa en SQLite falla en la migración anterior 0002. PostgreSQL real no verificado.
- **L6 (usuario):** «si» en respuesta a la confirmación de distancia en línea recta, radio de 1 a 50 km y 5 km por defecto.
- **L7:** T2 implementada sin commit; 1027 tests aprobados, 16 omitidos, Ruff y Pyright sin errores. La revisión independiente detectó que la consulta geográfica aún puede examinar todo el catálogo en la base aunque el resultado tenga LIMIT.
- **L8 (usuario):** «Dale» para una continuación acotada con prefiltro indexado y verificación en PostgreSQL aislado si estuviera disponible.
- **L9:** se implementaron prefiltro e índices; 1032 tests aprobados, 16 omitidos, Ruff y Pyright sin errores. Los dos verificadores independientes fallaron por error de red; el plan real de PostgreSQL y la corrección del prefiltro siguen sin verificar. T2 no está terminada.
- **L11 (2026-11-12):** reverificado en línea: 1032 tests aprobados, 16 omitidos; Ruff y Pyright sin errores; un solo head Alembic (`0029_listing_coordinate_indexes`). Siguen pendientes: revisión independiente (fallaron por red) y plan real de PostgreSQL de la consulta de la aplicación. Sin commit (AGENTS.md exige autorización explícita).
- **L12 (2026-11-12):** revisión independiente sin bloqueantes; advisorios: el cursor no liga centro/radio, el borde exacto del radio depende del flotante, faltan pruebas de cursor/modo sin coordenadas y de radio por defecto. PostgreSQL 16 descartable: `alembic upgrade head` hasta `0029` OK; la consulta real de la aplicación (200 000 filas sintéticas, radio 5 km) usó BitmapAnd sobre `ix_listing_latitude` e `ix_listing_longitude`, 0,4 ms. Esa corrida devolvió 0 filas por datos aleatorios, así que no prueba la corrección del resultado en PostgreSQL.
- **L13:** se agregaron 3 pruebas (radio por defecto de 5 km, exclusión de no publicados/no aprobados, cursor de modo distinto → 400); `test_f14_zone_search.py`: 26 aprobadas, Ruff y Pyright sin errores. Suite completa no reejecutada tras este cambio (solo se añadieron pruebas).
- **L10:** PostgreSQL 16 descartable con 200 000 filas sintéticas usó ambos índices en una consulta análoga (BitmapAnd); no es la consulta real de la aplicación y no reemplaza su plan ni la revisión independiente.
- **L14 (usuario):** «si» a usar datos de OpenStreetMap y verificar condiciones y costos; «Dale» a usar el servidor público para el proyecto académico, con proveedor configurable y error visible si no carga. El servicio es de mejor esfuerzo y no garantiza disponibilidad.
- **L15 (usuario):** «si» a que cambiar la ubicación retire el inmueble publicado y lo mande a revisión, igual que una edición normal. El panel requiere una operación acotada que no sobrescriba campos ajenos editados simultáneamente.
- **L16:** T3 en dos unidades paralelas. Captura: modelo, solicitud, `MapTileConfig` configurable, `location_picker.dart` con error y reintento, permiso INTERNET en el manifiesto principal; `flutter analyze` con 1 advertencia previa en `spatial_capture_controller.dart:463` (archivo no tocado). Backend: `PATCH /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/location` solo coordenadas, vuelve el inmueble a borrador. Panel: mapa Leaflet con corrección y confirmación. Reverificado en línea: 38 tests backend, 51 tests panel, 41 tests de captura. Pendientes: user-agent `com.example.captura_mobile` provisional, sin indicador de carga de teselas, e2e y `npm run build` del panel no ejecutados, sin revisión independiente.
- **L17:** T4 en línea en `apps/cliente_mobile`: filtros con punto/radio (1–50 km, 5 por defecto), `DeviceLocation` con `geolocator`, mapa OSM configurable con error y reintento, permisos Android/iOS. Revisión independiente (ítem 5, dependencia nueva) sin bloqueantes; licencias BSD-3/MIT/Apache-2.0; la posición no se persiste. Corregido el advisorio de `device_location.dart` (ahora captura también `Error`). Pendientes: S3 «ciudad» cubierto solo por el filtro de nombre existente (sin geocodificación), user-agent provisional `com.example.cliente_mobile`, flujo de permisos no probado en dispositivo, y registros de acceso del servidor con coordenadas en la URL (para T5).
- **L18:** T4 en `a2b25e4`. T5: documentados los parámetros `latitude`/`longitude`/`radius_km`, el cursor por distancia y la ruta `PATCH .../location` (roles: `agency_admin` y `agent` de la agencia, igual que la edición); estado de F14.5 en la sección del plan maestro. No se cambió la fila de §1.4.1 ni la de §1.4.5: la fase sigue sin PR ni issue cerrada.
