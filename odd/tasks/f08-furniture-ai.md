# F08 — IA preentrenada para mobiliario: piloto de inferencia (F08.1–F08.3)

Este documento es la especificación que leen los subagentes: leer hasta `## Log`.
Fase F08 del `docs/plan-maestro-roomforge.md`. Rama `feat/f08-furniture-ai-pilot`, worktree `proyecto_final-f08-ai-wt`, base `origin/main` `452fcd7`. Registro SDD en `openspec/changes/f08-ia-mobiliario/`.

## Specs

S1. Excepción de arranque anticipado (§1.5 regla 5): «Excepciones de arranque anticipado ya declaradas en el plan, y solo esas: F06 puede empezar con escenas sintéticas antes de F07; **F08 puede empezar con el piloto de inferencia antes de F05/F06**; F11 admite un smoke temprano después de F02.»

S2. Rama y worktree (§1.5 regla 8): «Una rama y un worktree por fase, nombrados `feat/<fase>-<tema>` (por ejemplo `feat/f05-furniture-inventory`), partiendo de `main` actualizado. La rama se rebasa sobre `main` y se integra por fast-forward; no se hace merge entre ramas de features. Al cerrar, la rama se borra una vez contenida.»

S3. Contrato primero (§1.5 regla 6): «Cuando dos fases comparten una interfaz, esa interfaz se congela y se documenta antes de que cada rama implemente, así ninguna espera a la otra. Interfaces conocidas: contrato de escena (F06 ↔ F07), **sugerencias de IA (F08 ↔ F05/F06)**, oferta versionada (F04/F05 ↔ F09) y estado de publicación (F04 ↔ F10).»

S4. F08.1 (§F08.1): «evaluar SSDLite/MobileNetV3 y alternativa YOLO pequeña. Revisar código, pesos y términos de datos. COCO incluye sillas, sofás, camas, mesas de comedor, TV y refrigeradores; no inferir puertas/ventanas o cualquier escritorio.» Aceptación: «dependencia reproducible y permitida para la modalidad elegida; no comprar licencia ni contratar servicios sin autorización.»

S5. F08.2 (§F08.2): «descargar pesos una vez, ejecutar imágenes con runtime local y obtener clases/cajas/puntuaciones. No descargar todo COCO ni pedir miles de fotos propias. 20–40 fotos autorizadas pueden servir como piloto exploratorio con revisión manual, no garantía estadística.» Aceptación: «separar aciertos, falsos positivos y omisiones; puntuación no se vende como probabilidad calibrada. Dataset de evaluación no se reutiliza como prueba imparcial si se ajustó con él.»

S6. F08.3 (§F08.3): «comparar teléfono offline contra worker en PC/AWS. Servidor simplifica actualización pero requiere sincronizar; móvil evita red pero compite con AR y aumenta integración.» Salida: «decisión de ejecución; PyTorch inicial u ONNX tras validar operadores y resultados.» Aceptación: «conversión conserva comportamiento aceptable medido; ni benchmark ajeno ni tamaño de pesos se presenta como consumo total propio.»

S7. Fuera de alcance de esta unidad: F08.4, F08.5 y F08.6. F08.5 exige «mostrar sugerencias, descartar/confirmar... colocar formas en escena» sobre F05/F06, y F06 no tiene implementación integrada. Se reevalúa cuando el contrato de escena esté congelado (S3).

S8. Flujo SDD obligatorio (§5.4): «Antes de código sustancial, resolver requisitos y seguir el flujo SDD del proyecto mediante sus herramientas autorizadas: propuesta, especificación, diseño, tareas, aplicación, verificación y archivo. No crear resultados de fases no ejecutadas.»

S9. Evidencia (AGENTS.md regla dura 4): «No silenciar GAPs ni inventar evidencia (documentación académica verificable).» Un campo no observado se registra como **no medido**, nunca como estimación.

S10. Commits (AGENTS.md regla dura 1): «No commitear/pushear sin autorización explícita del humano.» Los commits de unidad de trabajo quedan pendientes de autorización. Consecuencia declarada: sin commit, el candidato de revisión nativa no existe como unidad revisable (el `assess` nativo devolvió `unassessable` por archivos sin seguimiento).

## Tasks

- **F08T-T1 — F08.1 ficha de candidato** (S4). Salida `docs/ai/f08-ficha-candidato.md`. Commit: `09dbb6d`.
- **F08T-T2 — F08.2 servicio de inferencia + piloto** (S5, S6). Superficie `infra/docker/`, `worker3d/`, `docs/ai/`. Commits: `79ba71b` servicio, `88ca47f` CLI del detector, `71d7ac8` descargador CC0, `71bf6bf` planchas de revisión, `09dbb6d` evidencia.
- **F08T-T3 — F08.3 decisión de ubicación y empaquetado** (S6). Salida `docs/ai/f08-decision-empaquetado.md`. Commit: `09dbb6d`.
- **F08T-T4 — verificación y trazabilidad** (S1–S7). Plan maestro §1.4.1/§F08, `worker3d/README.md`, registro en este documento. Commits: `af931be` artefactos SDD y registro ODD, `675e66a` plan maestro y README del worker.

## Log

L1 (usuario, verbatim): «Podemos hacer en un worktree la fase 8?»

L2 (usuario, verbatim): alcance — «Hay una rama feat/f06-modelo-editable no se si tiene todo F06. Pero podemospartir de ahí. Sino hagamos todo la fase 8 de 1 a 3»; runtime — «Servicio en infra/docker».

L3 (verificación del orquestador, 2026-10-14): estado real medido, no supuesto.

- `origin/main` = `452fcd7`. La rama local `main` está en `03d93ae`, siete commits atrás: «main actualizado» (S2) significa `origin/main`.
- El worktree principal está en `feat/f04-photo-policy` con un único archivo sin seguimiento ajeno a esta fase (`odd/tasks/f04-photo-policy.md`).
- `origin/feat/f06-modelo-editable` = `43f629e`, nueve commits sobre `03d93ae` y **sin integrar**, siete commits detrás de `origin/main`. Aporta `docs/api/f06-scene-contract.md` (borrador), el visor `panel/staff-shell/src/features/editor3d/SceneViewer.tsx` con three.js, navegación libre y colisiones, y una propuesta de `webview_flutter 4.8.0`. **No** aporta F06.3 (editor de correcciones) ni F06.5.
- El contrato de escena de esa rama declara `objects[]` con `{id, type, position, dimensions, color}`: no tiene campos de sugerencia de IA (confianza, foto de origen, estado de revisión). El contrato «sugerencias de IA (F08 ↔ F05/F06)» de S3 sigue **sin definir**.
- `.venv` raíz: Python 3.12.13, sin `torch` ni `ultralytics`. `worker3d/` contiene únicamente `README.md`.

L4 (decisión del orquestador, 2026-10-14): no se basa F08 en `origin/feat/f06-modelo-editable`. Motivo: viola S2 (rama por fase desde `main` actualizado) y arrastraría una base siete commits atrasada, sin beneficio, porque F08.1–F08.3 no comparten ningún archivo con F06. La rama F06 queda pendiente de disposición propia (integrar o rebasar) por ser dependencia de F08.5.

L5 (candidato seleccionado, 2026-10-14): SSDLite320 + MobileNetV3-Large (`COCO_V1`) de torchvision. La alternativa YOLO pequeña de Ultralytics queda **descartada por licencia AGPL-3.0**, no por calidad técnica. Detalle y citas en `docs/ai/f08-ficha-candidato.md`.

L6 (evidencia operativa, 2026-10-14): el worktree se creó con el git de WSL, así que los punteros internos quedaron como rutas `/mnt/d/...`. **El git de Windows, que es el del host, no las resuelve**: `git worktree list` lo marcaba «prunable» y cualquier operación dentro fallaba con `fatal: not a git repository: (NULL)`. Efecto medido: la delegación al verificador independiente fue rechazada dos veces.
Corrección aplicada, con punteros **relativos** para que ambos gits los resuelvan:

- `<worktree>/.git` → `gitdir: ../proyecto_final/.git/worktrees/proyecto_final-f08-ai-wt`
- `.git/worktrees/<nombre>/gitdir` → `../../../../proyecto_final-f08-ai-wt/.git` (cuatro niveles: desde `worktrees/<nombre>/` hacen falta cuatro `..` para llegar a `sw1/`; con tres queda un nivel corto y WSL resuelve una ruta inexistente)

Verificado tras la corrección: ambos gits listan el worktree **sin** «prunable», coinciden en HEAD (`452fcd7`) y devuelven el mismo `git status`. Respaldo de los punteros originales en `proyecto_final-f08-ai-wt/../f08-worktree-pointers.bak`.

Lección para el repo: **un worktree creado desde WSL no lo ve el host de Windows**, y en este proyecto el trabajo se hace desde los dos lados. Conviene crear los worktrees con el git de Windows o corregir los punteros a relativos, y no usar `git worktree repair` sin verificar, porque escribe rutas absolutas del git que lo invoca.

L7 (verificación y correcciones, 2026-10-14): la verificación independiente dictaminó **R1–R8 satisfechos** y ninguna violación de honestidad, y devolvió **nueve hallazgos, todos causados por esta unidad**. Se corrigieron ocho, con RED observado primero en los de código, y las pruebas pasaron de 31 a **35**:

1. **(media)** la bitácora atribuía el conjunto a Openverse mientras el script consulta Commons → §1.6 reescrita con el pivote registrado;
2. sin hardware ni condiciones de medición (R5) → `docs/ai/f08-mediciones-entorno.txt`;
3. mediciones publicadas sin salida archivable → el mismo archivo;
4. «19 imágenes evaluables» contra un desglose que daba 18 → **18 con veredicto** en los cuatro documentos;
5. `.gitignore` fuera de la superficie de R7 → agregado a la aceptación;
6. conjunto incompleto salía con código 0 → `EXIT_SHORTFALL = 4` y `--allow-partial`;
7. una imagen ilegible abortaba la corrida entera → omisión por imagen, verificada de punta a punta en el contenedor (sonda con archivo corrupto: código 0, un registro, aviso en `stderr`);
8. JSONL malformado daba traza y el código de runtime difería del detector (5 frente a 4) → código 2 con mensaje claro y códigos alineados.

El noveno (el build instala desde `requirements.txt` y no desde el lock) **se deja declarado como límite, no corregido**: instalar desde el lock daría otro digest de imagen e invalidaría toda la evidencia medida. Quien lo cambie tiene que volver a correr el piloto.

Se comprobó además que el refactor del bucle de inferencia es **equivalente**: repetir el piloto completo devolvió 24 imágenes y 30 detecciones con la misma tabla de etiquetas, puntuaciones y cajas; sólo cambió la latencia.

L8 (usuario, verbatim, 2026-10-14): «AUtorizo los commits.
No hay otra opción o si o si es mejor usar torchvision?»

L9 (commits de unidad de trabajo, 2026-10-14, rama `feat/f08-furniture-ai-pilot`, sin push):

```
79ba71b feat(infra): add CPU-only inference service overlay for F08
88ca47f feat(worker3d): add furniture detection CLI with contract tests
71d7ac8 feat(worker3d): add CC0 pilot set fetcher with license guard
71bf6bf feat(worker3d): add manual review sheet builder
09dbb6d docs(f08): record candidate model sheet and pilot evidence
af931be docs(f08): add SDD artifacts and ODD task record
675e66a docs(plan): mark the F08 inference pilot as partial
```

Siete unidades, cada una con sus pruebas o su documentación adentro, en inglés y con conventional commits según AGENTS.md. **Sin push**: publicar es una decisión del dueño del repositorio.
