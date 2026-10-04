# F04 — Panel: bandeja de revisión y publicación del administrador de agencia

## Objetivo

Reemplazar el prototipo «Cola de revisión» del panel (`panel/staff-shell`) por la bandeja real del administrador de agencia, conectada a la API de F04: revisar los inmuebles enviados por agentes, aprobarlos o rechazarlos con motivo y publicar o retirar los aprobados. Mostrar al agente el aviso del mapa UX para continuar en la app de captura.

## Fuentes canónicas

Rige la regla del 2026-09-30 (`docs/plan-maestro-roomforge.md` §1.4.3): solo `docs/redefinicion-roomforge.md` y `docs/plan-maestro-roomforge.md` son fuente de requisitos.

- Redefinición: el administrador de agencia aprueba o rechaza las publicaciones preparadas por agentes; el borrador no aparece en el catálogo hasta la aprobación.
- Plan F04.3: aprobación/rechazo con motivo, publicación y retiro, historial mínimo; el agente no salta la aprobación.
- Plan F02.3 y mapa UX aprobado (`docs/ux/f02-surface-map.md`): recorrido del administrador de agencia «cola de borradores → revisar detalle → aprobar o rechazar con contexto → resultado»; el agente en el panel solo recibe la indicación de continuar en la app de captura; estados de carga, vacío, error, sin autorización, confirmación y éxito; acciones irreversibles con contexto y confirmación; foco visible, teclado y diseño adaptable.
- Contrato: `docs/api/f04-publications-v1.md` (rutas de listado, consulta, transiciones e historial).

## Estado de partida (rama `feat/f04-listings-completion`, `858d473`)

| Superficie | Estado |
|---|---|
| API de listado, consulta, transiciones e historial de personal | Implementada, probada y verificada a mano en el stack local |
| Panel, vista `agency_admin` | Prototipo de F02 con cola vacía fija «No se muestran solicitudes en este prototipo» |
| Panel, vista `agent` | Texto genérico «El espacio protegido está listo.» |
| Panel, patrón de código | `src/application/` (llamadas HTTP y sesión), `src/features/<área>/` (pantallas con pruebas Vitest + Testing Library); sin librería de rutas |

## Decisiones tomadas (2026-10-01)

1. **Alcance:** bandeja con dos pestañas, «En revisión» (`status=pending`) y «Aprobados» (`status=approved`), detalle con historial, y acciones aprobar, rechazar con motivo obligatorio, publicar y retirar, todas con confirmación.
2. **Agente:** el panel le muestra el aviso de continuar en la app de captura, en lugar del texto genérico.
3. **Sin dependencias nuevas:** sin librería de rutas ni de componentes; la navegación entre bandeja y detalle es estado del componente.
4. **Precios:** se muestran los importes que devuelve el servidor con la etiqueta `COP`, sin recalcularlos en el cliente.

## Alcance permitido

- `panel/staff-shell/src/application/staffListingsApi.ts` y `staffListingsApi.test.ts` (nuevos).
- `panel/staff-shell/src/features/listings/AgencyReviewQueue.tsx` y `AgencyReviewQueue.test.tsx` (nuevos).
- `panel/staff-shell/src/features/auth/ProtectedStaffShell.tsx` y `ProtectedStaffShell.test.tsx`.
- `panel/staff-shell/src/App.test.tsx` (solo expectativas de la vista por rol).
- `panel/staff-shell/src/styles.css`.
- Este registro y la línea de avance de F04 en `docs/plan-maestro-roomforge.md`.

Fuera de superficie: backend, apps Flutter, `panel/staff-shell/e2e/`, manifiestos y lockfile del panel, `docs/capturas/`, `contracts/`, `worker3d/`, `docs/diagramas/Diagrama1.eapx`, `openspec/`.

## Restricciones

- TDD estricto con `npm test` (Vitest), más `npm run build` (`tsc --noEmit` + Vite).
- El token de acceso permanece en memoria, como en el resto del panel; no se escribe en `localStorage` ni en `sessionStorage`.
- La agencia se toma de la sesión (`tenant_id`); la autorización real sigue siendo del servidor.
- Sin commit ni push sin autorización explícita del usuario.

## Tareas

- [x] **F04P-T1 — Cliente HTTP de inmuebles de personal.** Listado, detalle, historial y transiciones con Bearer y errores tipados por estado HTTP.
- [x] **F04P-T2 — Bandeja de revisión.** Pestañas, carga, vacío, error con reintento y lista de inmuebles.
- [x] **F04P-T3 — Detalle y acciones.** Detalle con historial; aprobar, rechazar con motivo, publicar y retirar con confirmación; resultado y conflicto `409`.
- [x] **F04P-T4 — Integración en el shell.** La bandeja reemplaza el prototipo para `agency_admin`; aviso de app de captura para `agent`.
- [x] **F04P-T5 — Verificación.** `npm test`, `npm run build`, revisión manual en el stack local con datos de prueba.

## Registro de ejecución

### F04P-T1 — Cliente HTTP (2026-10-01)

- Nuevo `src/application/staffListingsApi.ts`: `listAgencyListings` (`status` + `limit=50`), `getAgencyListing`, `listListingTransitions` y `transitionListing` (cuerpo `{observation}` o `{}`), todos con `Authorization: Bearer`, el identificador de agencia codificado con `encodeURIComponent` y `StaffListingsApiError` con el estado HTTP; un fallo de red se propaga como `TypeError`. `base_price` se conserva como cadena decimal; se comprobó en el contenedor `api` que el servidor lo serializa así (`"350000000.00"`).
- TDD: `staffListingsApi.test.ts` observó RED (módulo inexistente al transformar) y GREEN 11/11.

### F04P-T2/T3 — Bandeja, detalle y acciones (2026-10-01)

- Nuevo `src/features/listings/AgencyReviewQueue.tsx`: pestañas «En revisión» y «Aprobados»; carga, vacío, error con «Reintentar» y sesión rechazada (`401`); lista con operación, ciudad/zona, precio (`por mes` en alquiler), dormitorios/baños y visibilidad en catálogo; detalle con dirección exacta, descripción e historial (acción, rol, fecha y observación); acciones según estado (pendiente → aprobar/rechazar; aprobado → publicar o retirar), cada una con un grupo de confirmación que explica la consecuencia; rechazo con motivo obligatorio enviado sin espacios; aviso de resultado y recarga de la lista; conflicto `409` con aviso y recarga del detalle. `formatCop` agrupa la cadena decimal sin pasar por punto flotante. El token rotado por el shell se lee desde una referencia para no recargar la bandeja en cada renovación.
- `AgencyReviewQueue.test.tsx`: 16 pruebas GREEN. **Límite de proceso:** el componente se escribió antes de ejecutar estas pruebas, así que el RED no se observó en orden; se reconstruyó después ejecutando la misma suite en una copia sin el componente (`Failed to resolve import "./AgencyReviewQueue"`). Se registra como RED reconstruido, no como TDD estricto.

### F04P-T4 — Integración en el shell (2026-10-01)

- `ProtectedStaffShell.tsx`: `agency_admin` con `tenant_id` ve `AgencyReviewQueue`; `agent` ve el aviso de continuar en la app RoomForge Captura; `platform_admin` conserva la vista inicial. Se retiró el prototipo «PROTOTIPO · SIN CONEXIÓN».
- Pruebas: `ProtectedStaffShell.test.tsx` y `App.test.tsx` simulan `listAgencyListings`; se reemplazó la prueba del prototipo por la bandeja real y la del agente por el aviso. RED observado: 3 fallidas (agente en ambos archivos y bandeja real) y 94 aprobadas; luego GREEN.
- `styles.css`: estilos de pestañas, lista, detalle, historial, confirmación y botones con los tokens existentes, foco visible y objetivos táctiles de al menos 2,75 rem.

### F04P-T5 — Verificación (2026-10-01)

- Contenedor desechable `node:22` con el panel copiado sin `node_modules`: `npm test` 8 archivos, 97/97; `npm run build` (`tsc --noEmit` + Vite) sin errores.
- Imagen `panel` del stack local reconstruida y `healthy`; `http://127.0.0.1:5173/` responde `200`.
- Revisión manual en el navegador por el usuario con `agencia@example.test` (`agency_admin` de `agencia-demo`) sobre los datos de prueba locales, contrastada con los logs de acceso del contenedor `api` (peticiones desde el proxy del panel) y con `listing_transition` en el PostgreSQL local: la bandeja cargó las pestañas (`GET ...listings?status=pending&limit=50` y `status=approved`), el detalle y el historial (`GET .../listings/{id}` y `.../transitions`), y se ejecutaron `approve` → `publish` → `unpublish`, todas `200`; el historial quedó `submit` → `approve` → `publish` → `unpublish` con rol `agency_admin`, y el catálogo público se consultó entre acciones.
- **No ejecutado a mano:** el rechazo. Solo había un inmueble pendiente y se aprobó; el rechazo con motivo obligatorio queda cubierto por `AgencyReviewQueue.test.tsx` y por las pruebas backend de F04, no por la revisión manual.
