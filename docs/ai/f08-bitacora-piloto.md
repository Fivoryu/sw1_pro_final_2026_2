# F08.2 — Bitácora del piloto de detección de mobiliario

- **Rama:** `feat/f08-furniture-ai-pilot` · **Base:** `origin/main` `452fcd7` · **Fecha:** 2026-10-14
- **Estado:** preparación **completa**; experimento **pendiente** por falta de fotos autorizadas.
- **Regla de la bitácora:** lo no observado se escribe **no medido**. Nada de esta bitácora se presenta como ejecutado sin su comando y su salida.

## 1. Preparación (completa)

### 1.1 Versiones resueltas, no estimadas

Resueltas el 2026-10-14 contra el índice oficial de PyTorch y el índice de PyPI:

| Paquete | Versión fijada | Wheel verificada | Fuente |
|---|---|---|---|
| `torch` | `2.14.1+cpu` | `torch-2.14.1+cpu-cp312-cp312-manylinux_2_28_x86_64.whl` | `download.pytorch.org/whl/cpu` |
| `torchvision` | `0.29.1+cpu` | `torchvision-0.29.1+cpu-cp312-cp312-manylinux_2_28_x86_64.whl` | `download.pytorch.org/whl/cpu` |

- `torchvision` 0.29.1 declara `torch>=2.14.0`; 2.14.1 es la última estable del par. La pareja se validó contra el índice, no de memoria.
- `requires_python` de torchvision 0.29.1 es `!=3.14.1,>=3.10`: Python 3.12 es compatible.
- El pin usa la etiqueta local `+cpu`, que existe **únicamente** en el índice de PyTorch: no hay ambigüedad entre índices. El resto de las dependencias (Pillow y compañía) se resuelve desde PyPI, que es el índice por defecto.

### 1.2 Efecto declarado antes de instalar

Descarga de varios cientos de MB y aumento del tamaño de la imagen. Sólo CPU: no se declara GPU porque no se midió ninguna.

### 1.3 Superficie creada

| Ruta | Rol |
|---|---|
| `infra/docker/compose.inference.yml` | Overlay aditivo; no toca `compose.local.yml` |
| `infra/docker/inference/Dockerfile` | Imagen `python:3.12-slim`, sólo CPU |
| `infra/docker/inference/requirements.txt` | Par de versiones fijado |
| `worker3d/detect.py` | CLI de inferencia |
| `worker3d/fetch_cc0_pilot_set.py` | Descargador del conjunto CC0 y su manifiesto |
| `worker3d/tests/test_detect_contract.py` | Pruebas del contrato |
| `.gitignore` | Excluye fotos, pesos y resultados del piloto |

### 1.4 Contrato del CLI y su verificación (RED real observado, luego GREEN)

Comando: `.venv/Scripts/python.exe -m pytest worker3d/tests -q` desde el worktree.

**Primer RED observado**

```
worker3d\tests\test_detect_contract.py:22: in <module>
    import detect
E   ModuleNotFoundError: No module named 'detect'
!!!!!!!!!!!!!!!!!!! Interrupted: 1 error during collection !!!!!!!!!!!!!!!!!!!!
1 error in 1.22s
```

**Segundo RED observado (defecto real del diseño)**

```
worker3d\detect.py:19: in <module>
    import resource
E   ModuleNotFoundError: No module named 'resource'
```

`resource` es sólo POSIX y estaba importado a nivel de módulo, así que el CLI ni siquiera se podía importar en un host Windows. Corregido con un import perezoso dentro de `peak_rss_mb()`, que ya devuelve `None` cuando el valor no es observable. La lección se registra porque el defecto existía de verdad y lo detectó la prueba, no una casualidad.

**GREEN**

```
........                                                                 [100%]
8 passed in 1.58s
```

**Qué queda fijado por las 8 pruebas**

1. El módulo se importa y `--help` funciona con `torch` **ausente** del intérprete.
2. El registro tiene exactamente las claves esperadas y `model` y `detections` las suyas.
3. La palabra `probability` no aparece en la salida serializada: se llama `score`.
4. `not_measured` es una lista explícita y los valores no observables viajan como `null`.
5. Directorio de imágenes inexistente: código de salida 2, mensaje con la ruta, **sin archivo de salida**.
6. Directorio sin imágenes: código 3, mensaje explícito, **sin archivo de salida**.
7. Umbral fuera de rango o no numérico (`1.5`, `-0.1`, `dos`): código 2, **sin archivo de salida**.

La entrada rechazada no deja datos escritos: las validaciones ocurren antes de abrir el archivo de salida.

### 1.5 Aislamiento del entorno

- El entorno virtual de la raíz **no** recibió `torch` ni `torchvision`: sigue siendo el árbitro de `pytest`, `ruff` y `pyright` del backend.
- `compose.local.yml` queda intacto; el overlay es aditivo, así que la evidencia verificada de F01 no se invalida.

### 1.6 Conjunto de imágenes: CC0 de fuente pública

Decisión del dueño del producto (2026-10-14): el conjunto autorizado sale de fotos **CC0** de fuente pública, no de fotos propias.

- **Fuente final:** API de Wikimedia Commons (`https://commons.wikimedia.org/w/api.php`), restringida con `incategory:"CC-Zero"` y verificada **por archivo** leyendo `extmetadata`: licencia, términos de uso, autor, página de procedencia y URL de licencia.
- **Descargador reproducible:** `worker3d/fetch_cc0_pilot_set.py`. Las imágenes van a `worker3d/pilot/input/`, que está **excluido de git**: el repositorio conserva la procedencia y la licencia, no los bytes de terceros.
- **Manifiesto de procedencia:** `docs/ai/f08-conjunto-cc0.json`, generado por el mismo script, con `source_api` apuntando a Commons. Es la evidencia de R3.

**El pivote de fuente, registrado en lugar de borrado.** El primer intento se hizo contra la API de Openverse (`https://api.openverse.org/v1/images/`, `license=cc0`) y falló dos veces por causas distintas:

1. Con `page_size=24` respondía **401 en lugar de 400**:

```
page_size=20 -> 200
page_size=21 -> 401
{"detail":"page_size may not exceed 20 for anonymous requests"}
```

Se corrigió el tope a 20 por consulta.

2. Con el tope corregido, Openverse empezó a responder con un **desafío de Cloudflare** al cliente HTTP de Python: el cuerpo era HTML de `challenge-platform`, no JSON. La validación de bytes del descargador lo rechazó correctamente —no se guardó ninguna imagen falsa— pero tampoco se descargó ninguna.

**Decisión tomada:** se cambió la fuente a Wikimedia Commons, que responde de forma estable, y el script se reescribió contra ella. Los dos hallazgos se registran porque son reales y le sirven a quien lo reintente.

**Corrección de una inconsistencia que encontró el verificador independiente.** Una versión anterior de esta sección atribuía el conjunto a **Openverse**, mientras el script de la rama ya consultaba **Commons**. El manifiesto y el código coincidían entre sí; la prosa no coincidía con ninguno de los dos. Queda corregida acá, y es el hallazgo de severidad media del informe de verificación: la evidencia era sólida, su relato no.

### 1.7 Método de revisión manual (R4)

La separación entre aciertos, falsos positivos y omisiones exige mirada humana. El método es: el mismo servicio de inferencia genera planchas de contacto con las cajas detectadas dibujadas encima de cada imagen, y sobre esas planchas se registra el juicio por imagen. La plancha **es** evidencia de la revisión; el juicio se guarda junto a los registros del detector.

## 2. Experimento

### 2.1 Estado

**Ejecutado.** El conjunto autorizado proviene de fotos CC0 (ver §1.6), así que R3 tiene su origen y su permiso registrados, y la corrida se hizo sobre las 24 imágenes.

Dos defectos propios aparecieron **usando** la herramienta, y los dos se corrigieron con prueba primero:

1. **Etiquetas que no son objetos.** El modelo tiene 91 salidas, no 80: `__background__` y diez `N/A`. Una sugerencia podía llegar al producto con la etiqueta `N/A`. RED observado: `AttributeError: module 'detect' has no attribute 'build_detections'`.
2. **Coordenadas de las cajas.** Las cajas se dibujaban con coordenadas de mosaico pero sobre la página completa, así que todas las detecciones de una página se apilaban encima del primer mosaico. La plancha mostraba cajas sobre `pilot-01`, que tiene cero detecciones. Lo detectó la lectura visual de la plancha, no una prueba unitaria. Se corrigió de forma estructural —cada mosaico dibuja en su propio espacio— y se agregó la prueba de celdas disjuntas (`cell_origin`), que primero falló con `AttributeError`.

### 2.2 Comandos (exactos, desde la raíz del repositorio)

```bash
docker compose -f infra/docker/compose.local.yml -f infra/docker/compose.inference.yml \
  run -T --rm inference --list-classes

docker compose -f infra/docker/compose.local.yml -f infra/docker/compose.inference.yml \
  run -T --rm inference --images /work/pilot/input --out /work/pilot/out/detections.jsonl
```

### 2.3 Qué se mide y qué queda no medido

- **Se mide:** latencia por imagen (`latency_ms`) y memoria residente pico del proceso (`peak_rss_mb`, vía `ru_maxrss` en Linux).
- **No medido:** memoria de GPU, utilización de GPU y estado térmico. Viajan declarados en `not_measured` porque ninguna herramienta disponible en este entorno los expone. No se estiman.

### 2.4 Resultados de la corrida (24 imágenes, umbral 0.5)

| Métrica | Valor observado |
|---|---|
| Imágenes procesadas | 24 |
| Detecciones emitidas | 30 |
| Latencia media / pico | **230.5 ms** / **592.1 ms** |
| Memoria residente pico | **541.05 MB** |
| Imágenes sin ninguna detección | 8 |
| Etiquetas emitidas | `chair` 11, `couch` 5, `tv` 4, `potted plant` 3, `bed` 2, `dining table` 2, `car` 1, `bus` 1, `laptop` 1 |

Estas cifras son **mediciones propias**, en este equipo, con el digest de imagen registrado en §3. No son un benchmark ajeno, y el tamaño de los pesos no se presenta como consumo: lo que se reporta es la latencia y la memoria observadas al ejecutar.

### 2.5 Revisión manual (R4)

Registro completo por imagen en `docs/ai/f08-revision-manual.json`. Resumen:

| Resultado | Cantidad |
|---|---|
| Imágenes del conjunto | 24 |
| No aplica (2 exteriores, 1 detalle de pared, 3 láminas del MET… en total 5) | 5 |
| No concluyente (pilot-03) | 1 |
| **Imágenes con veredicto** | **18** |
| Detecciones | 30 |
| **Aciertos** | **25** |
| **Falsos positivos** | **5** |
| Aciertos discutibles (taburete→`chair`, mesa baja→`dining table`) | 3 de los 25 |
| Imágenes con omisiones notables | 8 de las 18 |

**Corrección de conteo.** Una versión anterior decía «19 imágenes evaluables» de forma inconsistente con su propio desglose: 24 − 5 no aplicables − 1 no concluyente = **18 con veredicto**. Lo detectó el verificador independiente. Las 30 detecciones y los 25/5 se cuentan sobre el conjunto completo y no cambian.

Los cinco falsos positivos: `chair` sobre un sofá (pilot-02), `bed` sobre el mismo sofá (pilot-07), `chair` sobre el mismo sofá (pilot-14), `chair` sobre una chaise longue (pilot-22) y `bus` sobre un edificio (pilot-05).

Las omisiones notables: el televisor de tubo de pilot-02, los asientos bajos de pilot-04, el televisor de pilot-11, los asientos y el televisor de pared de pilot-12, la segunda pantalla de pilot-15, **todos** los asientos de pilot-16, las otras sillas de pilot-20 y la cama con dosel de pilot-23.

**Advertencia sobre el revisor.** La revisión la hizo el agente sobre las planchas, no una persona. Es una lectura visual asistida y **no sustituye la validación humana**: las planchas se regeneran con `worker3d/review_sheet.py` justamente para que alguien las confirme o las corrija. Se declara para no presentar una revisión asistida como revisión humana.

### 2.6 Qué dicen estos datos, sin adornos

1. El detector **acierta de forma consistente** sobre mobiliario grande, bien iluminado y de perfil claro: sofás, camas, sillas y televisores.
2. Falla de dos maneras: **confunde clases** entre muebles parecidos y **omite objetos evidentes** en escenas cargadas o de clases que COCO no tiene.
3. Por lo tanto, la confirmación humana de F08.5 **no es una formalidad**: es la condición que vuelve usable la función.
4. El resultado respalda una IA que **sugiere**, no una IA que inventaría. Cualquier promesa de inventario automático queda contradicha por estos datos.

### 2.7 Correcciones posteriores a la verificación independiente

La verificación independiente (`gentle-ai-verify`, 2026-10-14) dictaminó **R1–R8 satisfechos**, no encontró ninguna violación de honestidad y devolvió **nueve hallazgos**, todos causados por esta unidad: uno de severidad media y ocho menores o informativos. Se corrigieron así:

| # | Hallazgo | Corrección |
|---|---|---|
| 1 (media) | Esta bitácora atribuía el conjunto a **Openverse** mientras el script commiteado consulta **Commons** | §1.6 reescrita: registra el pivote, el 401 del tope de página, el desafío de Cloudflare y la fuente final |
| 2 | Sin hardware ni condiciones de medición (R5) | `docs/ai/f08-mediciones-entorno.txt`, con las salidas crudas |
| 3 | Mediciones publicadas sin salida archivable | el mismo archivo, con los comandos y sus salidas |
| 4 | «19 imágenes evaluables» contra un desglose que daba 18 | **18 con veredicto** en la bitácora, el JSON de revisión, el README y el plan maestro |
| 5 | `.gitignore` fuera de la superficie declarada en R7 | agregado a la aceptación de R7 en `spec.md` |
| 6 | Conjunto incompleto salía con código 0 | `EXIT_SHORTFALL = 4` y `--allow-partial`, con prueba |
| 7 | Una imagen ilegible abortaba la corrida entera | omisión por imagen con aviso y resumen, con prueba |
| 8 | JSONL malformado daba traza; código 5 frente al 4 del detector | código 2 con mensaje claro y códigos alineados, con prueba |
| 9 (info) | El build instala desde `requirements.txt`, no desde el lock | **no se cambió**, ver §4 |

Los cinco defectos de código se corrigieron con **RED observado primero**: `AttributeError` en tres casos y una aserción de alineación de códigos en el cuarto. Las pruebas pasaron de 31 a **35**.

**El hallazgo 7 verificado de punta a punta, en el contenedor real.** Sonda con una imagen buena y un archivo corrupto:

```
1 imágenes procesadas; registros en /work/pilot/probe/detections.jsonl
EXIT_PROBE=0
  omitida: no se pudo leer como imagen: corrupta.jpg
1 imágenes omitidas por no poder leerse: corrupta.jpg
```

Se escribió **un** registro (el de la imagen buena) y el archivo corrupto quedó declarado en `stderr`. Antes, ese mismo caso habría descartado todo.

**El refactor, comprobado equivalente.** Se repitió el piloto completo con el código corregido: **24 imágenes, 30 detecciones**, y las etiquetas, puntuaciones y cajas coinciden exactamente con la tabla registrada antes del refactor (`pilot-06`: `tv 0.9951`, `laptop 0.9865`, `potted plant 0.8564`, `couch 0.7816`; `pilot-22`: `chair 0.8833`, `chair 0.8808`; `pilot-24`: `bed 0.9507`). Cambió sólo la latencia, que es lo esperable. Sin esta comprobación, haber tocado el bucle de inferencia habría dejado la evidencia sin respaldo.

## 3. Categorías reales del modelo (evidencia de F08.1)

Salida completa del modelo, ya descargado, dentro del servicio de inferencia: `docs/ai/f08-clases-modelo.json`. Es la salida cruda, no un resumen.

| Resultado | Valor observado |
|---|---|
| `weights_id` | `SSDLite320_MobileNet_V3_Large_Weights.COCO_V1` |
| `package` / `version` | `torchvision` / `0.29.1+cpu` |
| Cantidad de categorías | **91** |
| Mobiliario presente | `chair`, `couch`, `bed`, `dining table`, `tv`, `refrigerator` (las seis del plan) |
| Mobiliario ausente | ninguna |
| `door`, `window`, `desk` | **ausentes**: `expected_absent_found` está vacío |

**Hallazgo que el plan no anticipa.** El plan dice «COCO incluye sillas, sofás, camas, mesas de comedor, TV y refrigeradores», y eso se cumple. Lo que no dice es que el modelo tiene **91 salidas y no 80**: el índice 0 es `__background__` y hay diez ranuras `N/A` en los identificadores de categoría que COCO nunca definió. Una sugerencia podía llegar al producto con la etiqueta `N/A`, que no es un objeto.

Consecuencia aplicada: el CLI descarta `__background__` y `N/A` antes de emitir una detección, con prueba propia que primero falló (`AttributeError: module 'detect' has no attribute 'build_detections'`) y después pasó.

**Identidad del artefacto construido.** Imagen `roomforge-local-dev-inference`, digest `sha256:100a36e164ad99057ad456c04bd8ca774ddb360685774d50a03addc08650cb4d`. Es el artefacto que produjo toda la evidencia de esta bitácora.

## 4. Límites

1. Un piloto con 20–40 fotos mide **viabilidad**, no calidad estadística. No se reporta precisión ni recall.
2. Las puntuaciones del modelo no son probabilidades calibradas y así se registran.
3. Ningún benchmark ajeno se presenta como consumo propio, y el tamaño de los pesos no es consumo medido.
4. El conjunto CC0 es de dominio público pero **no es el dominio del producto**: son fotos de ambientes de fuente pública, no inmuebles bolivianos reales capturados por la agencia. El piloto mide si un detector COCO sin ajuste sirve como base; la calidad sobre fotos reales del flujo de negocio queda **sin medir**.
5. El código del modelo es BSD-3-Clause, pero **los pesos no tienen licencia declarada aparte**: la documentación de torchvision delega la verificación en quien los usa.
6. **El build no usa el lock** (hallazgo informativo de la verificación independiente, no corregido a propósito). `requirements.txt` fija las dependencias directas y el build re-resuelve las transitivas; `requirements.lock.txt` documenta el árbol que efectivamente quedó instalado y el digest identifica el artefacto. Cambiar el build para instalar desde el lock daría una reconstrucción exacta, pero **produciría otro digest e invalidaría toda la evidencia medida** sobre esta imagen. Queda declarado como límite en lugar de silenciado: quien quiera reproducibilidad bit a bit debe cambiar el build y **volver a correr el piloto**.
7. **Sin control de carga.** Las mediciones son de una máquina en uso normal; ver `docs/ai/f08-mediciones-entorno.txt` §2. Las latencias son indicativas, no un benchmark.
8. Los archivos escritos por el contenedor quedan propiedad de `root` en el directorio montado. En Linux hay que borrarlos desde el contenedor. Me pasó durante esta unidad: un `cp` de respaldo falló por eso y una sonda no llegó a ejecutarse hasta que se escribió en un directorio propio.
9. Sin la corrida del detector, R3–R5 quedarían pendientes. La corrida existe; lo que sigue sin existir es la validación humana de las planchas.
