# F06 — Contrato de escena v2: muros como fuente de verdad

Adaptación de los conceptos validados de openPlan3D (MIT) al contrato de escena de RoomForge.
Decisiones del operador: «Adapta esos cambios plis. Del 1 los muros serían la fuente de verdad
y las habitaciones las complementarían» — se adopta el modelo de muros (v2) y los conceptos
baratos: validación con rutas e integridad referencial, reset en blur, y (registro) picking con
tolerancia. La corrida en S23 FE continúa después, con el build v2.

## Specs

- **S1** (modelo): «los muros serían la fuente de verdad y las habitaciones las complementarían» —
  `version: "2.0"` con `walls[]` (segmento start/end en metros, height, thickness), `openings[]`
  top-level paramétricas (`wallId`, `position` 0..1 a lo largo del muro, width, height, type
  door|window, sillHeight para ventanas) y `rooms[]` como complemento (`id`, `name?`,
  `wallIds[]` que forman un ciclo, sin contornos guardados). `objects[]` no cambia.
- **S2** (validación): estilo `projectValidation` de openPlan3D — errores con ruta
  (`openings[0].wallId must refer to an existing wall`), integridad referencial (toda `wallId`
  existe), ids duplicados rechazados por colección, `position` en [0,1], longitudes > 0.
  El sobre sigue siendo `422 scene_invalid`.
- **S3** (lecturas honestas): un documento almacenado que ya no valida contra el contrato vigente
  se lee como `404 scene_not_defined` (staff y público): el cliente muestra su estado honesto y el
  staff debe re-guardar. Nunca se inventa una escena.
- **S4** (visor): colisiones desde muros, no desde contornos: segmentos con sus tramos de abertura
  restados; el margen de cámara respeta el espesor (`CAMERA_RADIUS + thickness/2`, concepto
  «distancia al borde pintado»). `validateScene` v2 valida muros/aberturas/objetos y es tolerante
  con `rooms` (metadato complementario). Spawn: centro del bbox de muros.
- **S5** (caminata): reset de input al perder foco (`blur`/`visibilitychange`) y clamp de delta
  ya existente; un frame retrasado no teletransporta y una app en segundo plano no sigue caminando.
- **S6** (panel): `DEFAULT_SCENE_DOCUMENT` = fixture v2 (pin vitest); el editor carga, edita y
  guarda v2: mover extremos de muro con snap, mover aberturas a lo largo del muro, mover objetos;
  las habitaciones se muestran como polígonos derivados de la cadena de `wallIds`.
- **S7** (fixture): `docs/api/f06-scene-fixture.json` pasa a v2 (misma habitación 4×3×2.4, misma
  puerta al centro, mismos tres cubos) y sigue siendo el documento canónico consumido verbatim
  por pytest, vitest, dart test y el E2E.
- **S8** (semilla y E2E): `backend/scripts/seed_local_walkthrough.py` y el E2E F10 generan
  documentos v2; el E2E conserva PUT staff → GET público → cotización con el `object.id`.
- **S9** (app cliente): el gate de versión acepta `2.0`/`meters`; el parser sigue sin retipar
  números; los tests de dart usan la fixture v2.
- **S10** (alcance excluido): sin herramientas de dibujo de muros nuevos más allá del mínimo
  necesario del editor, sin detección automática de habitaciones (queda para F07 con
  multi-ambiente), sin muros curvos, sin CSG, sin IFC.
- **S11** (historia): v1 queda documentada como superada en el contrato; el contrato no promete
  retrocompatibilidad de lectura de documentos v1 guardados (S3 define el comportamiento).
- **S12** (commits): una unidad por commit con tests; el working tree ya tenía pendiente el slice
  del visor (inappwebview): se mantiene separado lógicamente; el commit lo decide el operador.

## Tasks

- **T1** (S1, S7): contrato v2 + fixture canónica. Commit: `(pendiente)`
- **T2** (S2, S3, S8): backend — esquemas v2, validación referencial, rutas, seed v2, E2E F10 v2,
  tests RED→GREEN. Commit: `(pendiente)`
- **T3** (S4, S5): visor — `geometry.mjs` desde muros, `viewer.js` render v2 + reset en blur,
  `node --test` v2. Commit: `(pendiente)`
- **T4** (S6): panel — `DEFAULT_SCENE_DOCUMENT` v2 y editor de muros con tests vitest. Commit: `(pendiente)`
- **T5** (S9): app cliente — gate `2.0`, fixture y parser tests. Commit: `(pendiente)`
- **T6**: gates completos (pytest, ruff, pyright, vitest+build, flutter test/analyze/build,
  node --test, E2E PostgreSQL). Commit: `(pendiente)`
- **T7**: corrida en S23 FE con el build v2 y registro de mediciones (S6/S7/S8 del issue #22).

## Log

- **L1** (2026-10-19): «Adapta esos cambios plis. Del 1 los muros serían la fuente de verdad y las
  habitaciones las complementarían» — decisión del operador después de la evaluación de openPlan3D
  (MIT): se adopta el modelo de muros paramétricos con habitaciones derivadas/complementarias, y
  los conceptos baratos (validación con rutas e integridad referencial, reset en blur). Unidades
  en metros (contrato propio), no centímetros (openPlan3D): solo se adoptan conceptos, no su modelo.
- **L2** (2026-10-18, contexto previo): la corrida en S23 FE pausada por el operador queda
  registrada en `odd/tasks/f06-customer-walkthrough.md` L6; el visor con origen virtual
  `https://appassets.local/` ya renderiza; el guard de entrega única está corregido con test.
  Este cambio de contrato se hace encima de ese working tree.
- **L3** (2026-10-19, ejecución de T1–T6): contrato v2 + fixture congelados primero (T1); tres
  trabajadores en paralelo con superficies disjuntas más la app cliente inline, todos con RED
  observado antes del cambio. Backend: RED 18 failed / 10 passed → GREEN 29 passed (escena + F10),
  validación con ruta (`openings[0].wallId`…), ids duplicados, `scene_not_defined` honesto para
  documentos que ya no validan (S3), seed v2 con las dos habitaciones compartiendo el tabique y
  E2E F10 v2 `1 passed` contra `roomforge_f10_v2_runner` recreada. Visor: RED (`roomPolygon` no
  existía) → 17 tests `node --test`, colisión con `radio + thickness/2`, ventana sin hueco a nivel
  de piso, reset en blur/visibilidad. Panel: RED 9 failed / 3 passed → 142 vitest + `npm run build`
  limpio; editor de muros con extremos arrastrables (snap 0.1 m y a extremos), aberturas movibles
  a lo largo del muro, habitaciones derivadas de la cadena de `wallIds`. App cliente: fixture test
  v2, parser sin retipar números, 139 flutter tests + analyze limpio. Suite backend completa sin
  F10: 771 passed / 5 skipped. ruff y pyright limpios. Sin CRLF en los 27 archivos tocados
  (1878 inserciones / 605 eliminaciones). Límites declarados: el editor no agrega ni borra muros
  (no había estructura de herramientas; edición de extremos/aberturas/objetos sí); sin detección
  automática de habitaciones (F07); sin muros curvos ni CSG; la lectura de documentos v1 guardados
  degrada a `scene_not_defined` (S3). Pendiente: commits (decisión del operador, S12) y corrida en
  S23 FE con build v2 (T7).

