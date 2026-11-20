# Guía contextual de RoomForge
Trabajo local en `feat/guia-contextual`; se verifica cada superficie por separado.

## Specs
S1. «Quiero en un worktree que hagamos el asistennte inteligente para que guie al usuario para apredner a usar la app correctamente».
S2. «Guía por pantalla (recomendada)». La indicación corresponde a la pantalla y a la acción que la persona quiere aprender; no ejecuta la acción.
S3. «Que dicha guia inteligente sea para la parte web, cliente y agente».
S4. «Quiero que dichos guias sean los mas completos posibles capaz de guiar a un usuario que cono conece para nada del softwae». Cada superficie cubre todas sus pantallas principales y cada acción principal, con lenguaje para quien nunca usó el software.
S5. «dicha guia inteligente debe ser en español». Todo el contenido de la guía visible al usuario está en español.

## Tasks
T1 · S1–S3 · Panel web: guiar la revisión de un inmueble · delegada · hecha, sin commit (RED/GREEN: 2 tests de guía; 65 tests listings+App; tsc 0).
T2 · S1–S3 · App cliente: guiar la búsqueda y consulta de un inmueble · delegada · hecha, sin commit (RED/GREEN: 3 tests de guía; 38 tests catálogo; analyze limpio).
T3 · S1–S3 · App agente: guiar la preparación de un borrador de captura · delegada · hecha, sin commit (RED/GREEN: 4 tests de guía; 45 tests; analyze: 1 warning previo en spatial_capture_controller.dart:463).
T4 · S4–S5 · Panel web: guía completa de todas las pantallas · delegada (paralela) · pendiente.
T5 · S4–S5 · App cliente: guía completa de todas las pantallas · delegada (paralela) · pendiente.
T6 · S4–S5 · App agente: guía completa de todas las pantallas · delegada (paralela) · pendiente.

## Log
L1. Quiero en un worktree que hagamos el asistennte inteligente para que guie al usuario para apredner a usar la app correctamente
L2. Para todos
L3. Que dicha guia inteligente sea para la parte web, cliente y agente
L4. 2026-11-19: implementación paralela T1–T3 (tres escritores, superficies disjuntas). Límites: suite completa del panel y de Flutter no corrida; RED del panel obtenido tras escribir la implementación.
L5. 2026-11-20: Quiero que dichos guias sean los mas completos posibles capaz de guiar a un usuario que cono conece para nada del softwae, dicha guia inteligente debe ser en español
