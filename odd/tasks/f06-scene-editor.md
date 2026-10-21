# F06.3 — Editor de plano 2D ↔ escena 3D paramétrica (issue #21)

Header: dotar al panel de un editor de correcciones con lienzo 2D sincronizado bidireccionalmente
con el visor 3D existente, y persistencia de la escena editada por inmueble sobre el contrato JSON
ya definido en `docs/api/f06-scene-contract.md`.

## Specs

- S1: Issue #21 verbatim — "Dotar al panel de un editor de correcciones (F06.3): plano 2D editable
  sincronizado con la escena 3D paramétrica ya integrada, con persistencia por inmueble."
- S2: Alcance ✅ — "Lienzo 2D del plano (paredes y objetos) con edición directa", "Sincronización
  bidireccional 2D ↔ 3D sobre el contrato JSON existente", "Persistencia de la escena editada
  asociada al inmueble (decidir ubicación del dato y documentar en el contrato de API antes de
  implementar)". ❌ — captura AR (F07), IA (F08), 360° (F14.1), versión móvil.
- S3: Criterios — "Editar una pared en 2D se refleja en el 3D y persiste tras recargar", "La escena
  guardada carga exactamente lo editado (sin estados silenciosos)", "Suites y build del panel en
  verde; sin migraciones huérfanas en la cadena".
- S4: Regla del espejo — rama `feat/f06-…` → PR `Closes #21` → merge → fila §1.4.1 + tabla espejo.

## Decisiones de diseño (tarea 1 de la issue: modelo editable y ruta de API)

1. **Ubicación del dato:** tabla nueva `listing_scene` (migración `0022_listing_scene`), no una
   columna en `listings`: mantiene la fila caliente del inmueble liviana y separa el ciclo de vida
   de la escena (se crea al primer guardado, no con el inmueble). Columnas: `listing_id`
   (String(36), PK, FK → la tabla existente `listing.id`, singular según el esquema vigente,
   ON DELETE CASCADE), `scene` (JSONB, documento completo del contrato v1), `updated_at`,
   `updated_by` (String(36), actor del staff, nullable).
2. **Modelo editable (diffs sobre el contrato):** el servidor almacena y valida el **documento
   completo** del contrato v1 (`version`, `unit`, `rooms[]`, `objects[]`) con Pydantic
   `extra="forbid"`; el cliente edita y envía el documento entero (el diff es interno del estado
   del panel, no del transporte). Esto garantiza S3.2: lo guardado es exactamente lo validado.
3. **Ruta de API** (bajo el mismo guard de listing staff de F04):
   - `GET /api/v1/staff/agencies/{agency_id}/listings/{listing_id}/scene` → `200` con el documento,
     o `404 {code: "scene_not_defined"}` si nunca se guardó (el panel cae a la escena sintética
     por defecto y lo muestra honesto).
   - `PUT .../scene` con el documento completo → valida esquema (`422 scene_invalid` con detalle),
     `404 listing_not_found`, `403` cross-agency (mismo guard que la edición de inmueble); guarda y
     devuelve `200` con lo almacenado.
   - Autorización: miembros de la agencia (admin o agente), igual que la edición de inmuebles.
4. **Panel:** refactor de `SceneViewer` para aceptar la escena como prop (hoy renderiza un fixture
   `roomData` incrustado); único origen de verdad = estado React del documento de escena; el lienzo
   2D (SVG: contornos como polígonos, objetos como rects con selección y arrastre) y el visor 3D
   leen el mismo estado. Selector de inmueble vía `application/staffListingsApi.ts` existente.
5. **Pruebas:** backend pytest (guard, validación, round-trip, 404 inicial) y panel vitest
   (sincronización 2D→3D, edición y persistencia con fetch simulado).

## Tasks

- T1 (S2, decisión 1-3): backend — migración `0022`, modelos, esquemas Pydantic del contrato,
  rutas GET/PUT con guard F04, pruebas pytest, y actualización de `docs/api/f06-scene-contract.md`
  (sección de persistencia).
- T2 (S2, decisión 4): panel — tipos del contrato, refactor `SceneViewer` a prop, `SceneEditor`
  con lienzo 2D SVG, selector de inmueble, GET/PUT por `staffListingsApi`, pruebas vitest.
- T3 (S3): verificación — suite backend + ruff + pyright, panel `npm test` + build, CI verde.
- T4 (S4): PR `Closes #21` y tras el merge, fila §1.4.1 + tabla espejo.

## Log

- L1 (2026-10-16): "Hagarra la siguiente issue de F06" — pedido verbatim; se toma #21 (editor
  2D↔3D, primera de la fase).
- L2 (2026-10-16): Exploración — contrato de escena ya definido (`docs/api/f06-scene-contract.md`,
  rooms/contours/openings/objects); `SceneViewer.tsx` (247 líneas) renderiza un fixture incrustado,
  no consume el contrato dinámicamente; panel con vitest y `application/staffListingsApi.ts`
  existente; backend sin campos de escena, última migración `0021_merge_photos_detection`.
