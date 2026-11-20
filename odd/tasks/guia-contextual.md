# Guía contextual de RoomForge
Trabajo local en `feat/guia-contextual`; se verifica cada superficie por separado.

## Specs
S1. «Quiero en un worktree que hagamos el asistennte inteligente para que guie al usuario para apredner a usar la app correctamente».
S2. «Guía por pantalla (recomendada)». La indicación corresponde a la pantalla y a la acción que la persona quiere aprender; no ejecuta la acción.
S3. «Que dicha guia inteligente sea para la parte web, cliente y agente».

## Tasks
T1 · S1–S3 · Panel web: guiar la revisión de un inmueble · delegada · hecha, sin commit (RED/GREEN: 2 tests de guía; 65 tests listings+App; tsc 0).
T2 · S1–S3 · App cliente: guiar la búsqueda y consulta de un inmueble · delegada · hecha, sin commit (RED/GREEN: 3 tests de guía; 38 tests catálogo; analyze limpio).
T3 · S1–S3 · App agente: guiar la preparación de un borrador de captura · delegada · hecha, sin commit (RED/GREEN: 4 tests de guía; 45 tests; analyze: 1 warning previo en spatial_capture_controller.dart:463).

## Log
L1. Quiero en un worktree que hagamos el asistennte inteligente para que guie al usuario para apredner a usar la app correctamente
L2. Para todos
L3. Que dicha guia inteligente sea para la parte web, cliente y agente
L4. 2026-11-19: implementación paralela T1–T3 (tres escritores, superficies disjuntas). Límites: suite completa del panel y de Flutter no corrida; RED del panel obtenido tras escribir la implementación.
