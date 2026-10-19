# f00 — Decisiones de alcance: realismo métrico, ocupación sin etiqueta y precio aditivo con paquete amoblado

Decisión de alcance del 2026-10-19 registrada por el usuario sobre el plan maestro y la redefinición.
No crea código de producto; actualiza F05, F07, F08, §4.3 y §6.2 del plan maestro y una fila de la redefinición.

## Specs

- **S1** — Verbatim del usuario (L1): «Yo quiero que el generador 2D y 3D se vean casi reales… Con real me refiero al tema del tamaño, altura, etc. Los shapes no tienen que ser reales.» y «sino solo captura la luz, profundidad, altura del entorno».
- **S2** — Selección del usuario (pregunta 1): **«Escala real + cajas de ocupación sin etiqueta»** — muebles ocupan espacio y colisionan, sin nombre; etiqueta y precio quedan manuales (F05.1 + F06.3); requiere spike de Depth API (no medido).
- **S3** — Respuesta del usuario (pregunta 2, verbatim): «POdriamos incorporarlo al momento de la agencia a la hora de seleccionar los objetos que van a estar incorporados y donde el usuario decida sin manetenerlo o no a la hora de la compra final, rebajando el precio del inmueble. Ya que el blockchain se encargará del tema de contratos». La porción «rebajando el precio» se resuelve como **D3**: la aritmética vigente es aditiva (`total = base + Σ(precio × cantidad)`, restricción `price >= 0`) y el usuario eligió el paquete amoblado en la pregunta de modelado de precio, sin descuentos.
- **S4** — Selección del usuario (pregunta 3): **«Aditivo + paquete amoblado de la agencia»** — el paquete es colección nombrada de `extra_id` existentes, sin precio propio; su precio es la suma de sus extras.
- **S5** — Selección del usuario: **«Actualizar el plan maestro directo»** (sin proposal SDD).
- **S6** — Verbatim del usuario: «Recuerda no usar sdd, sino odd» — nada de `openspec/changes/` para esta unidad; registro aquí y ediciones directas.
- **S7** — Consecuencia de D2: la blockchain (escrow F09) custodia el monto congelado de la `QuoteSnapshot` (F05.4); no calcula precios ni lee inventario.
- **S8** — D1 no reabre el ACORDADO de la redefinición («No se incluye… reconstrucción fotorrealista»): lo confirma. Los volúmenes sin etiqueta caen en el estado honesto ya previsto por el contrato de escena («Este objeto es parte del recorrido; no tiene precio publicado.»).

## Tasks

| ID | Specs | Route | Commit |
|---|---|---|---|
| T1 | S2, S8 | Nueva subfase F07.6 (ocupación sin etiqueta, gate = spike Depth API en S23 FE) + fila F07 de §1.4.1 | docs |
| T2 | S3, S4, S7 | F05: decisión aditivo + paquete amoblado; F08: asistente de sugerencias; §4.3 contrato de sugerencias; §6.2 riesgo de profundidad; fila F08 de §1.4.1 | docs |
| T3 | S8 | Redefinición: fila Meshroom PENDIENTE → DECIDIDO | docs |
| T4 | S1–S8 | Relectura de coherencia del diff | — |

## Log

- **L1** (verbatim): «Actualmente la idea de este proyecto es el generador 3d, pero lo que planteabamos es que reconozca sillas, mesas, muebles, televisores, etc. Yo quiero que el generador 2D y 3D se vean casi reales, donde al hacer el recorrido. Se estará escaneando a tiempo real el piso y el software será capaz de replicar, no tan igual ni que este en 4k, un poco parecido a cubicasa donde no reconoce lo que es mesa, television, etc. Sino solo captura la luz, profundidad, altura del entorno. Con real me refiero al tema del tamaño, altura, etc. Los shapes no tienen que ser reales. Que te vez esa idea?»
- **L2**: usuario seleccionó «Escala real + cajas de ocupación sin etiqueta» (S2), respondió el papel de F08 con el texto de S3, eligió «Aditivo + paquete amoblado de la agencia» (S4) y «Actualizar el plan maestro directo» (S5).
- **L3**: usuario corrigió el flujo de trabajo: «Recuerda no usar sdd, sino odd» (S6).
- **L4**: verificación de código que ancla D3: `backend/app/modules/catalog/service.py` calcula `total = base + Σ(extra.price × quantity)`; `CheckConstraint("price >= 0")` en `listing_extra`; `is_optional` no existe; el escrow no calcula montos.
