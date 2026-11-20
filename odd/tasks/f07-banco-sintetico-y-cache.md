# F07 — Banco sintético con verdad conocida y caché por etapas

Objetivo: medir la exactitud del plano y de las aberturas sin esperar un piloto físico, y no repetir
las etapas caras al ajustar umbrales. Rama: `feat/f07-bench-cache` (desde `feat/f07-video-capture`).
Estrategia de entrega: `single-pr` (se mantiene la rama; no se abre PR). Runner: `pytest worker3d/tests`.

## Specs

- S1. "Dentro de esta rama podemos mejorar para medir sin necesidad de hacer el piloto?
  Pregunto sobre todo para no estar haciendo varios recalculos". Un banco sintético genera cuartos
  con geometría conocida solo por el banco, corre el pipeline real de `reconstruct_video` y reporta
  errores: razón largo/ancho de cada ambiente, razón de superficies entre ambientes, y por cada
  puerta o ventana su posición, ancho y alto relativos, más las perdidas y las inventadas.
- S2. El banco es determinista (semilla), admite ruido en los puntos de la nube y en los recuadros
  del detector, y permite sobreescribir umbrales (`--set modulo.CONSTANTE=valor`) para comparar
  configuraciones. Escribe una tabla y un JSON. Nada de lo que mide es una medida en metros.
- S3. Caché por etapas: el resultado de la reconstrucción dispersa (`SparseModel`) se guarda por
  huella del paquete y no se recalcula; con la caché llena no se llama al extractor ni al estimador.
  Sin caché el comportamiento es el de hoy (prueba dedicada). Un archivo de caché corrupto o con
  clases no permitidas se ignora y se recalcula; nunca se ejecuta código del archivo.
- S4. Caché de la salida cruda del modelo de puertas por contenido de la imagen: se guardan las
  probabilidades por prompt de cada recuadro, no la decisión, de modo que cambiar `MIN_SCORE`,
  `MIN_MARGIN` o `DUPLICATE_IOU` no vuelve a ejecutar el modelo.
- S5. Documentar en `worker3d/README.md` cómo correr el banco, la caché y sus límites.

- S6. Corrección pedida tras los hallazgos del banco ("Si corrigelo"): una abertura vista de forma oblicua se coloca igual de bien que de frente; el alto relativo no arrastra el sesgo de ~5 % y no se pierden puertas por la vista.

- S7. Corrección pedida ("siuu", tras ofrecer soldar los muros compartidos): dos ambientes que se tocan comparten una sola pared y una puerta compartida sale una sola vez, sin cambiar la salida del camino de esquema 1.

- S8. Pedido ("Podemos solucionar el ruido del telefono sin medir?" / "go misma rama"): el banco simula ruido de teléfono (puntos atípicos, temblor de poses) y el ajuste deja de romperse con él. No se pretende conocer el ruido real; se busca el margen en que el sistema aguanta.

- S9. Pedido ("siiiuuu" a la oferta de resolver el tope de ~10 % de puntos atípicos): el plano ya no se rompe con 15 % a 20 % de puntos sueltos, sin empeorar la nube limpia.

- S10. Pedido ("siiuu" a la última pasada de ruido: el temblor de cámara): reducir el error de posición de la abertura cuando las poses tiemblan, o decir con números que no se puede sin datos reales.

- S11. Pedido ("siiuuu" a cablear lo necesario para el piloto): el worker activa la caché y el reconocimiento de aberturas solo por entorno, apagados por defecto, sin cambiar la llamada actual al pipeline cuando no se piden.

Fuera de alcance: medir con imágenes reales (sigue requiriendo `torch` y el piloto), cablear el
detector de aberturas al worker de producción, cambiar umbrales.

## Tasks

- [x] T1 (S4) decisión desacoplada del modelo y caché de salida cruda en `openings.py` — inline (`test_openings_cache.py`, 7 pruebas)
- [x] T2 (S3) `stage_cache.py` y su uso en `reconstruct_video` para la reconstrucción dispersa — inline (`test_stage_cache.py` 12, `test_reconstruct_video_cache.py` 6)
- [x] T3 (S1, S2) `tests/bench_synthetic.py` y sus pruebas — inline (`test_bench_synthetic.py`, 13 pruebas)
- [x] T4 (S5) README
- [x] T10 (S11) cableado del piloto en `reconstruction_worker.py` por entorno — inline (`test_pilot_wiring.py`, 16 pruebas RED→GREEN)
- [x] T9 (S10) temblor de cámara: ponderar vistas probado y descartado (sin ganancia medible); más vistas por abertura es la palanca — inline
- [x] T8 (S9) descarte de puntos aislados antes de ajustar (`remove_stray_points`) — inline (5 pruebas RED→GREEN en `test_robust_fitting.py`)
- [x] T7 (S8) ruido de teléfono en el banco (puntos atípicos, temblor de poses) y endurecimiento del ajuste — inline (`test_robust_fitting.py` 8 pruebas, 2 en `test_bench_synthetic.py`)
- [x] T6 (S7) soldado de muros compartidos en `reconstruct._SceneBuilder` (`_snap_shared_walls`), activado por `reconstruct_video` — inline (`test_shared_walls.py`, 12 pruebas RED→GREEN)
- [x] T5 (S6) colocación por ajuste del cuadrilátero en `opening_placement.py` — inline (3 pruebas oblicuas RED→GREEN en `test_opening_placement.py`)

## Log

- L1 (usuario): "Dentro de esta rama podemos mejorar para medir sin necesidad de hacer el piloto?\nPregunto sobre todo para no estar haciendo varios recalculos" → "go" tras la propuesta de banco sintético + caché por etapas.
- L2: `reconstruction_worker.py` aún no pasa `opening_detector`; la caché de S4 queda lista para cuando se cablee.
- L3: no se hacen commits: la regla del repositorio exige autorización explícita del usuario.
- L4 (hallazgo del banco, semilla 1, 20 casos, sin ruido): 3 puertas perdidas (casos 9, 11, 14). La colocación devuelve `None` desde vistas oblicuas aunque la puerta esté entera en el cuadro. Hipótesis, no verificada: el recuadro del detector es un rectángulo alineado a los ejes y sus esquinas inferiores no son las de la puerta; con vista oblicua el rayo cae bajo el piso y se rechaza (`sill < -margen`).
- L5 (hallazgo): el alto relativo de la abertura sale ~5 % sobre la verdad (media 0.055, máx 0.07) en todos los casos. Misma hipótesis del recuadro; no hay causa confirmada.
- L6 (hallazgo): una puerta compartida sale duplicada (una por cada pared lateral) en 6 de 20 casos; es el límite ya conocido de muros sin soldar (L12 del ODD anterior), no una puerta inventada.
- L7: con ruido (`--point-noise 0.02 --pixel-noise 3 --score-noise 0.08`) los errores de proporción siguen bajo 0.5 %; con `--decoys` y `MIN_MARGIN=0.0` el banco acepta 16 clósets como puertas, con el margen por defecto 0 a 4 según el ruido de puntaje. Son cifras de un entorno simulado.
- L8: nada de lo anterior se corrigió: este ODD solo mide. Los hallazgos son candidatos para una siguiente tarea.
- L9 (usuario): "Pero te dije que lo hagas en la misma rama pe. Si corrigelo". El trabajo se movió a `feat/f07-openings-regularization` (la rama borrada `feat/f07-bench-cache` no tenía commits) y se corrigió L4/L5.
- L10 (causa, verificada con 3 pruebas RED): el recuadro del detector es la caja envolvente de un cuadrilátero y sus esquinas no son las de la abertura. `place_detection` ahora ajusta el rectángulo sobre el plano del muro (posición izquierda/derecha, base y tope) cuya proyección tiene esa caja: parte de los rayos por el centro de la caja y refina hasta 8 veces, porque la columna extrema la fija el vértice más a la izquierda y la fila extrema el más cercano (techo: la menor de las dos alturas; base: la mayor).
- L11 (antes → después, semilla 1, 20 casos, sin ruido): puertas perdidas 3 → 0; error de alto 0.055 (máx 0.070) → 0.0005 (máx 0.0019); de ancho 0.0145 → 0.0008; de posición 0.0033 → 0.0039. Las duplicadas suben de 6 a 11 porque ahora se colocan también las vistas oblicuas de la pared vecina (mismo límite de L6, no puertas nuevas).
- L12 (usuario): "siuu" a la oferta de soldar los muros compartidos.
- L13 (causa): el constructor ya soldaba vértices a menos de 3 cm, pero las caras interiores de dos ambientes vecinos salen de observaciones distintas y sus líneas de centro quedan a cualquier distancia (0 cm si la pared no tiene espesor en la nube, más si es gruesa). Antes solo se avisaba "misma pared capturada dos veces".
- L14 (diseño): `_snap_shared_walls` junta las líneas de centro de aristas antiparalelas (≤ 3°), a ≤ 0.3 de distancia y con solapamiento ≥ 30 % de la arista más corta, entre ambientes de la misma pieza; cada línea se mueve la mitad de la distancia (cada ambiente cede a lo sumo la mitad), una arista se empareja una sola vez (las más cercanas primero) y los extremos se deslizan por las aristas vecinas. Opt-in (`snap_shared_walls`), solo `reconstruct_video` lo activa (`SNAP_SHARED_WALLS`); el esquema 1 conserva su salida.
- L15 (el banco ahora usa espesor de pared real por caso, 0.08 a 0.3, y las puertas se ven sobre la cara de cada lado; la verdad se convierte con la escala propia de la escena). Semilla 1, 20 casos: sin soldar, 13 duplicadas y error de razón 0.0011 (máx 0.0041); soldando, 0 duplicadas y error de razón 0.0081 (máx 0.0235), posición 0.0081 (máx 0.0162), ancho 0.0018. El costo del soldado es que cada ambiente cede hasta la mitad de la diferencia entre el espesor real y los 0.15 que el constructor supone.
- L16 (usuario): "Podemos solucionar el ruido del telefono sin medir?" y luego "go misma rama".
- L17 (hallazgo 1, causa verificada con prueba RED): `horizontal_planes` solo evaluaba como centro de ventana los bins ocupados. Un techo denso con puntos sueltos a dos bins dejaba de ser máximo local de la ventana de 3 bins y su verdadero máximo caía en un bin vacío, que nunca se miraba: techo `None`, banda de paredes sin tope y 12 paredes fantasma. Ahora se evalúan todos los bins (el resultado no depende de dónde caen los bins).
- L18 (hallazgo 2, causa verificada con prueba RED): el control de altura plausible en metros (1.8 a 6.0) se aplicaba también en planos proporcionales. Un cuarto de 9 x 3 y 2.5 de alto, normalizado a un lado nominal de 5.0, mide 1.4 de alto y se reemplazaba por 2.4 "asumidos" sin escalar: la razón alto/largo salía mal. Ahora solo se aplica con escala métrica (`metric`). Es la parte de F5 que mordía a las alturas medidas.
- L19 (hallazgo 3, causa verificada con prueba RED): las paredes se extraen de la más fuerte a la más débil; con puntos atípicos sobraban líneas de 10 a 15 puntos que el contorno trataba como paredes. Ahora se corta cuando una línea tiene menos de `MIN_WALL_SUPPORT_REL` = 0.15 de los puntos de la más fuerte (supuesto, ajustable con el banco).
- L20 (antes → después, 10 casos, semilla 1): con 2 % de puntos atípicos el error de alto de la abertura pasa de 0.373 a 0.002 y con 5 % de 0.384 a 0.005; con 20 % las paredes fantasma ya no aparecen pero el rompimiento sigue (ver L21).
- L21 (límite medido, no resuelto): con 10 % de atípicos el error de razón es 0.015 (máx 0.033); con 15 % sube a 0.045 (máx 0.52) y con 20 % a 0.164 (máx 1.57). Causa: los atípicos que caen en la banda de tolerancia de una pared alargan su extensión (una pared de 5.4 sale de 9.6) y a esa densidad no se distinguen por huecos ni por conteo. Un cuarto del ruido real de un teléfono no se conoce: el margen medido es ~10 %.
- L22 (temblor de poses, medido, sin cambio de código): rotación de 4° y posición de 15 cm no pierden puertas ni cuartos; el error de posición de la abertura sube a 0.064 (4°) y 0.14 (15 cm) y el de ancho a 0.044 con 4°. El promedio entre vistas (`merge_views`) ya reparte parte del ruido; una puerta vista en pocas imágenes lo hereda casi entero.
- L23 (usuario): "siiiuuu".
- L24 (diagnóstico, corrige la hipótesis de L21): la extensión inflada de las paredes casi no importa (con 15 % las paredes salían de 9 a 27 de largo y 9 de 10 casos seguían bien). Lo que rompía era la votación de RANSAC: con muchos puntos sueltos, una línea que cruza el interior del cuarto reúne más puntos que una pared real corta y gana. La pared real del lado sur se perdía y el contorno usaba la línea falsa.
- L25 (solución): `remove_stray_points` descarta, antes de ajustar planos y paredes de cada ambiente, los puntos cuyos 4 vecinos más cercanos están en promedio a más de 2.5 veces la mediana de la nube (supuesto). Todo es relativo a la propia nube (celda de rejilla derivada de su superficie), así que vale en cualquier unidad; nubes de menos de 20 puntos no se tocan. Con 2 anillos de celdas da lo mismo que con 3 y es 4 veces más rápido (45 000 puntos: 5.9 s).
- L26 (antes → después, 10 casos, semilla 1, error de razón máx): 15 % de atípicos 0.521 → 0.027; 20 % 1.568 → 0.039; 30 % 0.053 (posición de la abertura 0.343); 40 % se rompe (1.239). La nube limpia no cambia (0.012). El margen medido sube de ~10 % a ~30 %.
- L27 (límite): los puntos sueltos a menos de ~0.5 de una superficie no se distinguen de su dispersión propia y se dejan al ajuste; el filtro asume que una nube real tiene densidad de superficie bastante pareja, y una nube muy irregular (zonas sin textura) podría perder puntos legítimos de las zonas ralas. Ambos son supuestos que solo el piloto confirma.
- L28 (usuario): "siiuu".
- L29 (probado y revertido): se pesó cada vista por (cos del ángulo con el muro / distancia)^2, que es el peso de varianza inversa si el error de cámara crece con la distancia y con lo oblicuo, y `merge_views` promedió con ese peso (4 pruebas unitarias en verde). En el banco, con todos los cuadros extraídos y 12 casos, el cambio no se distingue del ruido: posición media con rotación de 4° 0.021 → 0.020, con 15 cm 0.028 → 0.026, con ambos 0.039 → 0.040. Sin ganancia medible no se justifica la complejidad: se revirtió.
- L30 (lo que sí mueve el error, medido): más vistas. Con 6 cuadros extraídos y 15 cm de desvío la posición media es 0.045 (máx 0.140); con todos los cuadros (`--set reconstruct_video.EXTRACT_FPS=10`) 0.028 (máx 0.073). El promedio entre vistas reparte el ruido si es independiente entre cuadros. Con ambos ruidos juntos (3° y 10 cm) sobra 0.037 (máx 0.084) de posición y 0.090 de alto, y ahí ni más vistas ni ponderar cambian lo que se ve.
- L31 (límite honesto): el banco supone ruido independiente por cuadro y de magnitud pesimista (los ajustes de haces de SfM suelen dejar poses mucho más cerradas que 3° y 10 cm). El error de pose real es correlacionado entre cuadros vecinos (deriva) y promedia menos. Cuánto ruido y de qué tipo mete un teléfono se conoce solo con el piloto; `OPENING_MAX_FRAMES` (24) es el botón para pedir más vistas cuando se mida.
- L32 (usuario): "siiuuu".
- L33: `pilot_options` lee `ROOMFORGE_OPENING_DETECTION` (solo `owlv2`) y `ROOMFORGE_STAGE_CACHE_DIR`; el detector se construye cuando el pipeline lo pide, así que si falta `torch` el trabajo no falla: sale la advertencia ya existente. `openings.build_detector` rechaza con `ValueError` un modelo sin backend (Grounding DINO sigue fijado, no construido). Diferencial: sin variables, `reconstruct_video` recibe exactamente `detector_factory`, como antes (prueba).
- L34: pendiente solo del piloto: instalar `torch`/`transformers`/`pillow`, correr OWLv2 de verdad (nunca se ejecutó), medir velocidad por cuadro y exactitud, y ajustar umbrales.
