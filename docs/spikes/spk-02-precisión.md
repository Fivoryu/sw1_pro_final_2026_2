# SPK-02 — Bitácora de precisión geométrica

| Campo | Valor |
| --- | --- |
| Spike | SPK-02 — Precisión geométrica de la reconstrucción |
| Objetivo | Medir exactitud (error vs. valor real) y precisión (repetibilidad) de las medidas obtenidas del modelo 3D |
| Responsable | Equipo RoomForge |
| Estado | En ejecución |
| Fecha inicio | GAP-030: pendiente |
| Fecha cierre | GAP-031: pendiente |

## Terminología (obligatoria)

| Término | Definición usada |
| --- | --- |
| **Exactitud** | Qué tan cerca del valor real está la medida del modelo (error absoluto en cm). |
| **Precisión / repetibilidad** | Qué tan parecidas son medidas repetidas del mismo objeto en corridas distintas. |
| **Medida calibrada** | El modelo fue escalado con una referencia métrica externa (cinta o láser). |
| **Medida estimada** | El modelo conserva escala sin referencia: sirve para proporciones, no para dimensiones absolutas. |

## Ground truth (referencia real)

- 4–6 distancias por ambiente, cubriendo **orientaciones ortogonales**:
  - largo de pared, alto de pared, ancho de puerta, ancho de ventana, profundidad del ambiente.
- Medir con cinta métrica/láser; registrar la **incertidumbre estimada** de la medición (por lo general ±0,5–1 cm).
- Registrar fecha, ambiente y quién midió.

## Procedimiento de escala (evita la trampa de autovalidación)

1. Reconstruir con SPK-01 (misma versión y grafo).
2. Elegir **una distancia de escala** (idealmente la más larga) y, si es posible, **una segunda ortogonal** para detectar escala no uniforme.
3. Aplicar el factor de escala calculado = distancia_real / distancia_en_modelo.
4. **Validar SOLO con las distancias restantes** (nunca la usada para escalar).
5. Reportar también el modelo **sin escalar** como control (debe mostrar error relativo ~constante).

## Métricas por dimensión de validación

| Métrica | Fórmula |
| --- | --- |
| Error absoluto | distancia_real − distancia_modelo (cm) |
| Error relativo | error_absoluto / distancia_real × 100 (%) |
| Error medio | promedio del error absoluto de todas las dimensiones |
| Error máximo | peor dimensión |
| Desviación (repetibilidad) | diferencia entre corridas de la misma dimensión (cm) |

## Registro de mediciones

| # | Fecha | Ambiente | Dimensión | Distancia real (cm) | Incertidumbre cinta (±cm) | ¿Escala? (Sí/No) | Distancia modelo (cm) | Error absoluto (cm) | Error relativo (%) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 2 | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 3 | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 4 | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 5 | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 6 | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |

## Registro de repetibilidad (2ª corrida)

| # | Ambiente | Dimensión | Corrida 1 (cm) | Corrida 2 (cm) | Diferencia (cm) |
| --- | --- | --- | --- | --- | --- |
| 1 | GAP | GAP | GAP | GAP | GAP |
| 2 | GAP | GAP | GAP | GAP | GAP |

## Conclusiones que alimentan decisiones

| Decisión | Regla propuesta (completar al cerrar el spike) |
| --- | --- |
| Tolerancia numérica de exactitud (RNF) | GAP-032: error relativo observado (validado, sin escala propia) + margen |
| Criterio calibrado vs. estimado en UI | GAP-033: si error ≤ tolerancia tras escala → `calibrada`; si no → `estimada` |
| Umbral de confianza para ocultar medidas | GAP-034: error máximo tolerable antes de ocultar la medida |
| Registro de incertidumbre | GAP-035: incluir incertidumbre de cinta en el cálculo y reportarla en la ficha |
| Uso de ARCore/ARKit como escala opcional | GAP-036: probar solo si hay dispositivo compatible; no reemplaza la cinta |

> Regla: no se declara ninguna tolerancia ni métrica "casi exacta" sin los datos de esta bitácora. Una medida sin referencia métrica externa siempre se reporta como `estimada`.
