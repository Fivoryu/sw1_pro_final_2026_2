# F14.3 — Favoritos y búsquedas guardadas

**Objetivo:** el cliente guarda inmuebles favoritos y búsquedas del catálogo para volver a ellos. **Plan:** `docs/plan-maestro-roomforge.md` F14.3. **Issue:** #38.
**Rama:** `feat/f14-favoritos` desde `main` actualizado (`ca9fc4e`). **Entrega:** `ask-on-risk`.
**Ejecutores de pruebas:** `backend` con `<raiz>/.venv/Scripts/python.exe -m pytest`, Ruff y Pyright; app cliente con `flutter test` y `flutter analyze`.

## Specs

El alcance y los criterios de aceptación vienen de la issue #38. **[Propuesta]** = decisión del asistente donde la issue no la fijaba; confirmar ante cualquier duda.

- **S1 — Favoritos.** Favorito por inmueble (marcar, desmarcar y listar) que se guarda en el servidor por cliente.
  - Aceptación: el cliente guarda, lista y elimina favoritos que persisten entre sesiones; un cliente no ve los favoritos de otro.
  - **[Propuesta]** Solo un inmueble aprobado y publicado se puede marcar. Si después deja de estar publicado, el favorito se conserva como «ya no está publicado», sin datos del inmueble, y se puede quitar. Hay un máximo de 100 favoritos por cliente.
- **S2 — Búsquedas guardadas.** Los filtros actuales del catálogo se guardan con un nombre y se pueden volver a aplicar.
  - Aceptación: el cliente guarda, lista y elimina búsquedas que persisten entre sesiones; un cliente no ve las búsquedas de otro.
  - **[Propuesta]** El nombre es único por cliente, sin distinguir mayúsculas, y hay un máximo de 20 búsquedas.
- **S3 — Privacidad de la ubicación. [Propuesta]** Una búsqueda guardada no incluye el punto ni el radio de la búsqueda por zona, porque F14.5 (S4) establece que la ubicación del cliente no se guarda. La app avisa que la zona no se guarda, y el servidor rechaza esas claves.
- **S4 — Catálogo sin cambios.** El catálogo no cambia de comportamiento para quien no usa la función: sin sesión no aparecen corazones ni botones de búsquedas, y `GET /api/v1/listings` responde lo mismo con o sin sesión.
- **S5 — Estados honestos.** Carga, vacío y error coherentes con el resto de la app.
- **Fuera de alcance (issue):** avisos o alertas push de búsquedas y compartir favoritos entre usuarios.

## Tasks

Estado: ☐ pendiente. Ruta por defecto: en línea.

| ID | Tarea | Specs | Ruta | Estado | Commit / evidencia |
| --- | --- | --- | --- | --- | --- |
| T1 | Backend: modelos y migración `0035` (un solo head), rutas de favoritos y búsquedas con aislamiento por sesión de cliente, límites y validación de filtros. | S1, S2, S3, S4 | en línea | ☑ | Módulo `favorites`, migración `0035_customer_favorites`, 14 pruebas en `tests/test_favorites.py` (aislamiento, idempotencia, inmueble no publicado, límites, filtros inválidos, ubicación nunca guardada y catálogo sin cambios). Sin commit todavía. |
| T2 | App cliente: corazón en la tarjeta del catálogo y en el detalle, pantalla «Mis favoritos», guardar búsqueda y hoja «Mis búsquedas». | S1–S5 | en línea | ☑ | `CustomerFavoritesApi`, `CustomerFavoritesController` (carga al iniciar sesión y se borra al cerrarla) y vistas en `lib/ui/features/favorites/`. 14 pruebas en `test/customer_favorites_test.dart`. Sin commit todavía. |
| T3 | Cierre: contrato de API, registro y filas del plan maestro. | — | en línea | ☑ | `docs/api/f14-favorites.md` y F14.3 en el plan maestro. |
| T4 | Verificar la migración `0035` contra un PostgreSQL desechable y probar el flujo en un dispositivo. | — | en línea | ☐ | Pendiente: Docker no estaba disponible en la máquina usada (2026-11-18); las pruebas de API corren sobre SQLite. |

**Riesgo previsto:** T1 nombra el ítem 1 (migración) y el ítem 2 (aislamiento entre clientes).

**Estado verificado (2026-11-18, `main` en `ca9fc4e`):** no había favoritos ni búsquedas guardadas en `backend/app/modules/` ni en `apps/cliente_mobile/lib/`.

## Log

- **L1 (2026-11-18, usuario):** eligió la issue #38 como siguiente unidad de trabajo.
- **L2 (2026-11-18):** al revisar el catálogo se encontró que F14.5 (S4) no guarda la ubicación del cliente; por eso S3 deja la zona fuera de las búsquedas guardadas.
- **L3 (2026-11-18):** decisiones del asistente, a confirmar: límites de 100 favoritos y 20 búsquedas; favorito de inmueble despublicado conservado sin datos; `PUT` y `DELETE` de favoritos idempotentes con 204; los corazones y los botones de búsquedas solo aparecen con sesión iniciada; la lista de favoritos se abre desde un ícono en la barra superior, junto a la campana de avisos.
- **L4 (2026-11-18):** T1–T3 hechas en `feat/f14-favoritos`, sin commit. Verificación: backend 1128 verdes y 16 omitidas (incluye las 14 nuevas), Ruff y Pyright limpios; app cliente 243 pruebas verdes y `flutter analyze` limpio. Pendiente T4: PostgreSQL real y flujo en dispositivo.
