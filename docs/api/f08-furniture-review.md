# F08.5 — Contrato de revisión humana de mobiliario
Estado: contrato de esta unidad, sobre escena F06 v2 e inventario F05. ODD: `odd/tasks/f08-human-confirmation.md`; issue #26.

## Invariantes
- La inferencia solo produce sugerencias 2D. Etiqueta y puntuación no son identidad física, probabilidad calibrada, medidas ni precio.
- Solo un editor autenticado de la agencia (`agent` o `agency_admin`) decide. Un ID ajeno bajo la agencia propia responde como inexistente.
- Cada sugerencia se identifica por `job_id` + `detection_index` (índice de base cero en el resultado inmutable). La revisión final se inserta una sola vez y nunca se modifica.
- La confirmación crea un extra con las reglas existentes de F05 y coloca una caja en una escena v2 ya guardada. `SceneObject.id = ListingExtra.id`. No se agregan campos a F06.
- La persona aporta nombre, precio en moneda del inmueble, dimensiones enteras en centímetros y posición en metros. Dimensiones de la caja = centímetros / 100; no se infieren desde píxeles.
- Un repetido entre fotos se resuelve explícitamente vinculándolo a un extra existente del mismo inmueble: no se crea otro extra ni se incrementan cantidad/precio.
- Rechazar no cambia inventario, escena ni oferta. La misma detección no vuelve a pendiente; otro trabajo de inferencia es otra sugerencia.
- Alta de extra y caja, edición del inmueble y revisión se confirman en una transacción. Como la autoría F05, añadir mobiliario deja el inmueble en borrador y sin publicar; requiere el flujo normal de revisión.
- El inventario manual usa el mismo formulario y operación, sin necesitar detecciones.

## Endpoints
Prefijo: `/api/v1/staff/agencies/{agency_id}/listings/{listing_id}`.

### GET /furniture-review
Devuelve `listing` (respuesta staff existente con extras, moneda y `offer_version`), `suggestions[]` y `history[]`.
Cada sugerencia incluye `job_id`, `detection_index`, `photo_id`, `model_id`, `label`, `score`, `box`, `status` (`pending|confirmed|rejected|expired`) y `extra_id`.
El historial conserva actor, fecha, decisión, resultado original y extra confirmado. GET no inserta ni modifica filas.
Solo aparecen resultados de trabajos completados. Los estados de ejecución siguen en `GET /detections`; la solicitud de inferencia sigue en `POST /photos/{photo_id}/detections`.

### POST /furniture-review
Campos comunes: `request_id` (UUID de idempotencia), `expected_offer_version` (entero positivo).
Modo manual: `action: "manual"`, `item`.
Modo sugerencia: `action: "confirmed"|"rejected"`, `job_id`, `detection_index`.
Confirmar requiere exactamente uno de `item` (nuevo extra) o `existing_extra_id` (repetido ya inventariado).
Rechazar no admite item ni vínculo.
`item`: `name`, `price` (decimal exacto, máximo dos decimales), `width_cm`, `height_cm`, `depth_cm`, `position: {x,y,z}`; opcionales `category`, `room`, `quantity` (por defecto 1).
El servidor asigna procedencia y vínculo visual; no acepta que el cliente los fabrique. Nueva caja de tipo `box`, color neutro.
Respuesta: la misma vista actualizada de GET.

## Cambios, caducidad e idempotencia
- Se serializan decisiones por el bloqueo del inmueble; en SQLite se reserva escritura antes de leer. La tabla impide dos decisiones para el mismo par trabajo/índice.
- Se exige la versión actual de la oferta. Si otra edición/confirmación cambió la oferta: `409`, sin revisión ni cambios parciales; recargar y volver a confirmar conscientemente.
- Editar o despublicar no convierte sugerencias en inventario ni borra decisiones; las pendientes permanecen revisables por personal sobre la oferta actual. Una foto de origen eliminada/no confirmada o un resultado no disponible vuelve la sugerencia pendiente `expired`; no se puede confirmar.
- La repetición de una operación idéntica devuelve el estado vigente sin modificar filas ni versiones. Reutilizar la clave o la detección con otra decisión/contenido responde `409`. El hash ignora clave y versión, pero no contenido.
- Falta de escena válida para un alta con caja: `409`. Guardar primero una escena real/confirmada; nunca crear una escena sintética desde esta operación.
- Entrada inválida: `422`; sesión ausente `401`; rol/agencia indebida `403`; inmueble/trabajo/extra ajeno `404`.
- La revisión histórica sobrevive a la eliminación de una foto. No se modifica el resultado del detector.

## Interfaz y verificaciones
La revisión vive junto al editor del panel: fotos y trabajos con estados reales, sugerencias con clase/puntuación/caja y procedencia, descarte, alta o vínculo a existente, formulario manual e historial. Una escena con cambios locales debe guardarse antes de revisar para no sobrescribir una caja recién añadida.
Pruebas públicas: confirmación y cotización, rechazo permanente, repetidos, alta manual, conflictos sin efectos, caducidad, aislamiento por agencia, idempotencia y preservación de las rutas anteriores. Migración aditiva posterior al head real, sin reescribir migraciones integradas.

## Comprobaciones reproducibles

Desde `backend/`, con el intérprete del monorepo:
- `python -m pytest tests/test_furniture_review.py -q`: reglas de la API y preservación de inventario/escena ante rechazos.
- `python -m pytest tests/test_furniture_review_postgres.py -q`: migración completa y decisiones concurrentes. Requiere `ROOMFORGE_F08_DATABASE_URL` apuntando a una base **vacía**, PostgreSQL local, puerto explícito y nombre con prefijo `roomforge_f08_`; nunca usar la base de desarrollo. Sin esa variable se omite explícitamente.
- `python -m ruff check app tests` y `pyright --pythonpath <intérprete-real> app tests`.

Desde `panel/staff-shell/`:
- `npm test` y `npm run build`.
- `node e2e/furniture-review.e2e.test.mjs`: Chromium real con React/Vite y fixtures HTTP interceptadas. Verifica formulario manual, vínculo de repetidos, descarte, bloqueo por escena con cambios y ancho 390 px. **No** acredita persistencia ni integración de login/backend; las pruebas HTTP/PostgreSQL cubren esas reglas de servidor. Necesita el navegador de Playwright disponible. Crea y elimina solo su propia entrada temporal de prueba.

El vínculo a un extra existente exige que ya tenga una caja con ese mismo ID en la escena: no se inventa su geometría. El formulario manual permite dar de alta inventario nuevo; no sustituye la edición general de extras de F05.

F08.6 no se activa: no hay ajuste fino ni experimento nuevo de modelos en esta unidad.
