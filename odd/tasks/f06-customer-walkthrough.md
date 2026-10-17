# F06.4/F06.5 — Recorrido en primera persona en la app cliente (issue #22)

Último issue abierto de la fase F06. El cliente recorre el inmueble en primera persona
desde la app cliente (WebView) y el hotspot comercial lleva del objeto a la cotización.

## Specs

- **S1**: «Webview que monta el visor con la escena del inmueble publicado.»
- **S2**: «Controles táctiles de navegación libre (sustituir WASD por joystick/touch-look) con las mismas colisiones.»
- **S3**: «Hotspot comercial (F06.5) que lleve del objeto en la escena a la cotización existente de F05.» Decisión del operador (L2): se construye una pantalla mínima de cotización en la app que llama al `POST /quotes` público existente y muestra el snapshot.
- **S4**: «Estados honestos: inmueble sin escena muestra el estado actual del catálogo, nunca una escena vacía fingida.»
- **S5**: «`flutter test` / `flutter analyze` / build Android verdes; registro en `odd/tasks/`.»
- **S6** (aceptación): «Un inmueble publicado con escena se recorre en primera persona en el dispositivo físico.» (S23 FE, corrida junto al operador.)
- **S7** (aceptación): «El hotspot lleva a la cotización del objeto sin salir del flujo del cliente.»
- **S8** (aceptación): «Sin escena: estado honesto visible. Riesgo "visor móvil lento" (§6.2) medido, no supuesto.»
- **S9** (F06.5, plan): «Cargar únicamente contenido controlado; limitar puente WebView y evitar exponer tokens a páginas arbitrarias.» El visor viaja como asset local vendoreado (sin CDN); el puente expone solo mensajes de escena/selección, nunca tokens.
- **S10** (alcance excluido): «❌ Captura (F07), IA (F08), reserva/pago dentro del visor, tour de panorámicas (F14.1).»
- **S11** (espejo): «esta issue no amplía el plan; requisito nuevo → actualizar primero plan maestro/redefinición. Flujo: rama `feat/f06-…` → PR con `Closes #N` → merge → actualizar fila §1.4.1 y tabla espejo.»
- **S12** (backend): la app necesita la escena del inmueble publicado vía API pública; se agrega `GET` público de escena solo para inmuebles publicados (staff ya tiene `GET/PUT` desde F06.3).

## Tasks

- **T1** (S12) backend: endpoint público `GET` de escena para inmuebles publicados + tests RED→GREEN. Commit: `2899fd2`
- **T2** (S2, S9) app móvil: asset del visor (Three.js vendoreado, HTML/JS local) con navegación en primera persona, colisiones, aberturas transitables y límites. Commit: `(ver T3 commit, se integra junto)`
- **T3** (S1, S4, S9) app móvil: pantalla WebView con carga de la escena desde la API, puente acotado y estados honestos (carga, error con reintento, sin escena). Commit: `55cd45c`
- **T4** (S3, S7) app móvil: hotspot → ficha del objeto → pantalla mínima de cotización (`POST /quotes`) con cliente API y tests. Commit: `bcac802`
- **T5** (S5, S11) verificación y docs: `flutter test/analyze/build apk`, `pytest`, `ruff`, `pyright`; docs del contrato de escena (ruta pública) y bitácora. Commit: `(pendiente)`
- **T6** (S6, S8) corrida en S23 FE con el operador: carga, fluidez, error/recuperación; registro de mediciones reales en la bitácora.

## Log

- **L1**: «Hagamos el último issue de la fase 6» — pedido original del operador. Identificado: issue #22 (F06.4/F06.5), única issue abierta de la fase 6; la #21 cerró con PR #47.
- **L2**: Decisiones del operador (pregunta de alcance): (1) hotspot con **pantalla mínima de cotización** construida en la app (S3); (2) **medición en S23 FE hoy juntos** durante esta sesión (T6).
- **L3**: Verificación de T5 (2026-10-16): backend `pytest` 756 passed / 6 skipped, `ruff` limpio, `pyright` 0 errores; app `flutter test` 131 passed, `flutter analyze` sin problemas, `flutter build apk --debug` compila. Nota de entorno: el wrapper `pyright` se autoactualizó y dejó de resolver la venv (falsos `reportMissingImports` de `eth_account`/`pillow_heif`, paquetes instalados); con `--pythonpath ../.venv/Scripts/python.exe` reporta 0 errores. Contrato actualizado con la ruta pública `GET /api/v1/listings/{listing_id}/scene` (`docs/api/f06-scene-contract.md`, sección "Lectura pública (F06.4)").
