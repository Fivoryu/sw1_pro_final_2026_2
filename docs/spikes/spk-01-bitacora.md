# SPK-01 — Bitácora del benchmark de reconstrucción Meshroom

| Campo | Valor |
| --- | --- |
| Spike | SPK-01 — Benchmark de reconstrucción 3D (Meshroom/AliceVision) |
| Objetivo | Validar el pipeline 3D dentro de los límites del MVP y medir recursos y tamaños reales |
| Responsable | Equipo RoomForge (RTX 4050 como worker principal) |
| Estado | En ejecución |
| Fecha inicio | GAP-001: pendiente |
| Fecha cierre | GAP-002: pendiente |

## Entorno fijo (completar una vez por equipo)

| ítem | Valor registrado |
| --- | --- |
| Versión AliceVision/Meshroom | GAP-003 |
| CUDA / driver NVIDIA | GAP-004 |
| GPU | GAP-005 |
| RAM total disponible | GAP-006 |
| Disco libre | GAP-007 |
| Sistema operativo | GAP-008 |
| Grafo de nodos / configuración `meshroom_batch` | GAP-009 |

> Regla: todas las corridas usan exactamente esta configuración. Cualquier cambio se registra como otra corrida, no se reutiliza una anterior.

## Protocolo de captura (ambiente propio)

- Video guiado + fotos complementarias cubriendo paredes, esquinas y techo.
- Iluminación estable, sin contraluces.
- 15–40 fotos, resolución ≤ 12 MP.
- Evitar espejos, superficies transparentes y objetos en movimiento.

## Registro de corridas

Una fila por corrida. Fuente: salida real de `meshroom_batch` + herramientas de medición (task manager / nvidia-smi / hwmonitor).

| # | Fecha | Dataset | Imágenes | Resolución | Tiempo SfM | Tiempo DepthMap | Tiempo Meshing | Tiempo Texturing | Tiempo total | RAM pico (MB) | VRAM pico (MB) | Temp GPU máx (°C) | Resultado | Fallo (etapa y motivo) | GLB final (MB) | Texturas (MB) | Nube intermedia (MB) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 2 | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 3 | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |

> GAP = dato pendiente; no se completa hasta medirlo.

## Conclusiones que alimentan decisiones

| Decisión | Regla propuesta (completar al cerrar el spike) |
| --- | --- |
| Timeout técnico de jobs | GAP-010: tiempo total observado + margen |
| Concurrencia del worker | GAP-011: 1 corrida a la vez si RAM/VRAM satura |
| Cuota de reconstrucciones/mes | GAP-012: derivado de tiempo + capacidad semanal |
| Límite de almacenamiento | GAP-013: derivado de tamaños GLB/texturas/nubes (entrada a SPK-04) |
| RNF de rendimiento | GAP-014: ¿se cumple ≤ 30 min por ambiente? |
