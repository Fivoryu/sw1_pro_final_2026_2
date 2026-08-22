# SPK-03 — Inventario de GPUs y entorno del equipo

| Campo | Valor |
| --- | --- |
| Spike | SPK-03 — Inventario GPU/entorno |
| Objetivo | Conocer hardware exacto de los seis integrantes y validar compatibilidad con AliceVision/Meshroom |
| Responsable | Equipo RoomForge (cada integrante completa su fila) |
| Estado | En ejecución |
| Fecha inicio | GAP-020: pendiente |
| Fecha cierre | GAP-021: pendiente |

## Cómo obtener cada dato (Windows)

| Dato | Comando / lugar |
| --- | --- |
| GPU exacta, VRAM, driver | `dxdiag` (pestaña Pantalla) o Administrador de tareas → Rendimiento → GPU |
| Compute capability (CUDA) | Buscar el modelo en la tabla oficial de NVIDIA (<https://developer.nvidia.com/cuda-gpus>) |
| RAM total | `wmic memorychip get capacity` o Administrador de tareas |
| Disco libre | Explorador → Este equipo |
| Sistema operativo | `winver` |
| Versión driver | `nvidia-smi` (si hay GPU NVIDIA) |

> Si el equipo no tiene GPU NVIDIA, registrarlo igual: sirve para definir qué equipos solo desarrollan y cuáles pueden correr reconstrucción.

## Registro por integrante

| # | Integrante | Equipo (PC/laptop) | GPU exacta | VRAM (GB) | Compute capability | Driver/CUDA | RAM (GB) | Disco libre (GB) | SO | ¿Meshroom compatible? | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Buceta Pesoa Luis Fernando | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 2 | Calero Suyo Trevor Félix | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 3 | Cervantes Arancibia Roberto Carlos | PC RTX 4050 (worker principal) | RTX 4050 | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 4 | Ortiz Montero Luis Enrique | GAP | GTX 1050 o superior — modelo exacto pendiente | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 5 | Rebollo Condori Renato | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| 6 | Vedia Barrios Sebastian | GAP | GTX 1050 o superior — modelo exacto pendiente | GAP | GAP | GAP | GAP | GAP | GAP | GAP | GAP |
| R | Laptop de referencia (desarrollo) | Laptop | Intel integrada (Intel Core 5 120U, 7,8 GB compartidos) | 0 | N/A (sin CUDA) | N/A | 16 | GAP | GAP | No (solo desarrollo) | Útil para frontend/backend, no para reconstrucción |

## Conclusiones que alimentan decisiones

| Decisión | Regla propuesta (completar al cerrar el spike) |
| --- | --- |
| Perfil del worker | GAP-022: quién puede correr reconstrucción (RTX 4050 principal; GTX según resultado) |
| Plan B del pool GPU | GAP-023: si alguna GTX no es compatible, la RTX queda como única reconstrucción |
| Hardware mínimo para Meshroom | GAP-024: compute capability mínima verificada |
| Matriz de desarrollo | GAP-025: qué equipos sirven para frontend/backend/pruebas |
| Cruce con SPK-01 | GAP-026: comparar tiempos RTX vs GTX en Monstree cuando ambas corran |
