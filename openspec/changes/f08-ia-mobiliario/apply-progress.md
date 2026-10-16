# Apply / Verify — Detector de mobiliario preentrenado (F08.1–F08.3)

- **Rama:** `feat/f08-furniture-ai-pilot` · **Base:** `origin/main` `452fcd7` · **Fecha:** 2026-10-14
- **Estado del cambio:** aplicado y verificado en la rama. **No integrado y no archivado.**
- **Commits:** ninguno. AGENTS.md regla dura 1 prohíbe commitear sin autorización explícita; los commits de unidad de trabajo quedan pendientes de esa autorización.

## Fases SDD

| Fase | Estado | Artefacto |
|---|---|---|
| explore | ✅ | `explore.md` |
| proposal | ✅ | `proposal.md` |
| spec | ✅ | `spec.md` (R1–R8) |
| design | ✅ | `design.md` |
| tasks | ✅ | `tasks.md` (F08T-T1..T4) |
| apply | ✅ | este documento + la superficie de §Superficie |
| verify | ✅ | verificación por requisito abajo |
| archive | ⬜ | **No corresponde todavía**: el cambio no está integrado en `main` |

## Superficie modificada (R7 verificado)

```
 M .gitignore
?? docs/ai/
?? infra/docker/compose.inference.yml
?? infra/docker/inference/
?? odd/tasks/f08-furniture-ai.md
?? openspec/changes/f08-ia-mobiliario/
?? worker3d/detect.py
?? worker3d/fetch_cc0_pilot_set.py
?? worker3d/review_sheet.py
?? worker3d/tests/
 M docs/plan-maestro-roomforge.md
 M worker3d/README.md
```

Nada fuera de `infra/docker`, `worker3d`, `docs/ai`, `.gitignore`, `docs/plan-maestro-roomforge.md`, `openspec` y `odd`. **No se tocó**: backend de producto, panel, apps móviles, `contracts/`, migraciones ni `docs/diagramas/Diagrama1.eapx`. En el worktree principal existe un archivo sin seguimiento ajeno a esta fase (`odd/tasks/f04-photo-policy.md`) que no se modificó.

`worker3d/pilot/` está **excluido** por `.gitignore` (fotos de terceros, pesos, planchas y sondas): el repositorio conserva la procedencia en `docs/ai/f08-conjunto-cc0.json`, no los bytes.

## Verificación por requisito

| Requisito | Veredicto | Evidencia |
|---|---|---|
| R1 ficha de candidato con licencia verificable | ✅ | `docs/ai/f08-ficha-candidato.md`, con citas de torchvision, Ultralytics y COCO; ninguna licencia no declarada se presenta como permiso; YOLO descartado por licencia |
| R2 dependencia reproducible | ✅ | `requirements.txt` con versiones fijadas contra el índice real, `requirements.lock.txt` con el árbol instalado, digest `sha256:100a36e1…cb4d`; overlay aditivo |
| R3 piloto sobre fotos autorizadas | ✅ con límite | 24 fotos CC0 con licencia verificada por archivo en `docs/ai/f08-conjunto-cc0.json`; el conjunto es de fuente pública, **no** inmuebles reales |
| R4 separación honesta de resultados | ✅ | `docs/ai/f08-revision-manual.json`: 25 aciertos, 5 falsos positivos, omisiones en 8 imágenes, clasificadas por imagen y por detección |
| R5 medición propia o declaración de no medido | ✅ | 230.5 ms de media / 592.1 ms de pico, 541 MB de RSS; memoria de GPU, uso de GPU y estado térmico declarados `no medido` en cada registro |
| R6 decisión de ubicación y empaquetado | ✅ | `docs/ai/f08-decision-empaquetado.md`: worker en servidor con PyTorch; ONNX **no evaluado** con su condición de desbloqueo nombrada; móvil **no medido**, no condenado |
| R7 límite de alcance declarado | ✅ | la lista de superficie de arriba; el plan maestro marca F08 como parcial y no como completa |
| R8 trazabilidad actualizada | ✅ | `docs/plan-maestro-roomforge.md` §1.4.1 y §F08 y `worker3d/README.md`, con el avance marcado **sin integrar** |

## Pruebas

| Comando | Resultado |
|---|---|
| `.venv/Scripts/python.exe -m pytest worker3d/tests -q` | **31 aprobadas** |

Tres RED observados de verdad durante la unidad, no declarados de memoria:

1. `ModuleNotFoundError: No module named 'detect'` — antes de implementar el CLI.
2. `ModuleNotFoundError: No module named 'resource'` — defecto real: un import POSIX a nivel de módulo impedía importar el CLI en Windows. Corregido con import perezoso.
3. `AttributeError: module 'review_sheet' has no attribute 'cell_origin'` y `AttributeError: module 'fetch_cc0_pilot_set'…` en su momento — antes de cada corrección.

**Un defecto no lo atrapó una prueba unitaria:** las cajas se dibujaban en coordenadas de mosaico sobre la página completa, apilando todas las detecciones de una página en el primer mosaico. Lo detectó la lectura visual de la plancha producida. Se corrigió de forma estructural (cada mosaico dibuja en su propio espacio) y se agregó la prueba de celdas disjuntas. Se registra porque el modo de descubrimiento importa: la prueba cubre la aritmética del diseño, no el espacio de coordenadas.

**Por qué no hay RED/GREEN de producto:** la unidad no cambia comportamiento de producto ni extiende una suite existente. Los 31 tests son de contrato de herramientas. Las afirmaciones sobre calidad del detector se sostienen en la corrida y la revisión manual, no en una métrica.

## Verificación independiente y ronda de correcciones (2026-10-14)

Un verificador ajeno a la escritura (`gentle-ai-verify`) dictaminó **R1–R8 satisfechos** y no encontró violaciones de honestidad, pero devolvió **nueve hallazgos**, todos causados por esta unidad. Estado de cada uno:

| # | Severidad | Hallazgo | Estado |
|---|---|---|---|
| 1 | media | La bitácora atribuía el conjunto a Openverse mientras el script consulta Commons | **Corregido**: §1.6 reescrita con el pivote registrado |
| 2 | baja-media | Sin hardware ni condiciones de medición (R5) | **Corregido**: `docs/ai/f08-mediciones-entorno.txt` |
| 3 | baja | Mediciones publicadas sin salida archivable | **Corregido**: el mismo archivo |
| 4 | baja | «19 imágenes evaluables» contra un desglose que daba 18 | **Corregido**: 18 con veredicto en los cuatro documentos |
| 5 | baja | `.gitignore` fuera de la superficie declarada en R7 | **Corregido**: agregado a la aceptación de R7 |
| 6 | baja | Conjunto incompleto salía con código 0 | **Corregido**: `EXIT_SHORTFALL` y `--allow-partial`, con prueba |
| 7 | baja | Una imagen ilegible abortaba la corrida entera | **Corregido**: omisión por imagen; verificado en el contenedor |
| 8 | baja | JSONL malformado daba traza; códigos de runtime dispares (5 vs 4) | **Corregido**: código 2 y códigos alineados, con prueba |
| 9 | info | El build instala desde `requirements.txt`, no desde el lock | **Declarado como límite**: cambiarlo daría otro digest e invalidaría la evidencia medida |

Los cinco defectos de código se corrigieron con **RED observado primero**. Las pruebas pasaron de 31 a **35**.

**Sonda de corrupción, ejecutada en el contenedor real** (una imagen buena y un archivo corrupto): código de salida 0, **un** registro escrito y el archivo ilegible declarado en `stderr`. Antes, ese caso descartaba las 24 imágenes.

**Equivalencia del refactor, comprobada:** repetir el piloto completo devolvió 24 imágenes y 30 detecciones con la misma tabla de etiquetas, puntuaciones y cajas. Sólo cambió la latencia.

**Defecto propio encontrado al cerrar:** las reglas de `.gitignore` cubrían `worker3d/pilot/input/` y `out/` pero no el directorio `probe/` que agregó la sonda, así que `worker3d/pilot/` aparecía sin ignorar. Corregido ampliando la regla a `worker3d/pilot/` completo.

## Qué NO está verificado

- Precisión, recall o exactitud del detector: **no se calculan**. 24 imágenes no sostienen una métrica.
- Comportamiento sobre inmuebles reales del flujo de negocio: **no medido**.
- ONNX y ejecución en teléfono: **no evaluados**.
- Suite del backend: **no ejecutada**, porque ningún archivo del backend fue tocado. Sería un chequeo sin relación con el cambio.
- La revisión humana de las planchas: **pendiente de una persona**.
