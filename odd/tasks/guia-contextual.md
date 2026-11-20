# Guía contextual de RoomForge
Trabajo local en `feat/guia-contextual`; se verifica cada superficie por separado.

## Specs
S1. «Quiero en un worktree que hagamos el asistennte inteligente para que guie al usuario para apredner a usar la app correctamente».
S2. «Guía por pantalla (recomendada)». La indicación corresponde a la pantalla y a la acción que la persona quiere aprender; no ejecuta la acción.
S3. «Que dicha guia inteligente sea para la parte web, cliente y agente».
S4. «Quiero que dichos guias sean los mas completos posibles capaz de guiar a un usuario que cono conece para nada del softwae». Cada superficie cubre todas sus pantallas principales y cada acción principal, con lenguaje para quien nunca usó el software.
S5. «dicha guia inteligente debe ser en español». Todo el contenido de la guía visible al usuario está en español.
S6. «más o menos que se asemeje a un chatbot donde el usuario pueda escribir o que le de sugenerencias, de tal forma que el usuario no se pierde en el sistema». La guía es una conversación: la persona escribe una pregunta o toca una sugerencia y recibe la respuesta de la guía de la pantalla actual; siempre hay sugerencias visibles. Supuesto: respuestas por reglas sobre el contenido de la guía, sin modelo de lenguaje ni red.

## Tasks
T1 · S1–S3 · Panel web: guiar la revisión de un inmueble · delegada · hecha, sin commit (RED/GREEN: 2 tests de guía; 65 tests listings+App; tsc 0).
T2 · S1–S3 · App cliente: guiar la búsqueda y consulta de un inmueble · delegada · hecha, sin commit (RED/GREEN: 3 tests de guía; 38 tests catálogo; analyze limpio).
T3 · S1–S3 · App agente: guiar la preparación de un borrador de captura · delegada · hecha, sin commit (RED/GREEN: 4 tests de guía; 45 tests; analyze: 1 warning previo en spatial_capture_controller.dart:463).
T4 · S4–S5 · Panel web: guía completa de todas las pantallas · delegada (paralela) · hecha (22 guías; 221 tests features+App y tsc 0 según el agente; 90 tests guide/listings/auth verificados por el parent).
T5 · S4–S5 · App cliente: guía completa de todas las pantallas · delegada (paralela) · hecha (12 guías; parent verificó analyze y tests; arregló botón en estados sin sesión de reservas).
T6 · S4–S5 · App agente: guía completa de todas las pantallas · delegada (paralela) · hecha (11 guías incl. acceso y bienvenida vía main.dart; 51+20 tests verificados; conocido: spatial_capture_screen_test 'traces a local floorplan' falla también sin el cambio).
T7 · S6 · Panel web: interfaz de chat de la guía · delegada · hecha (62 tests guide; parent: 86 tests + tsc 0).
T8 · S6 · App cliente: interfaz de chat de la guía · delegada · hecha (18 tests nuevos; parent: 64 tests + analyze limpio).
T9 · S6 · App agente: interfaz de chat de la guía · delegada · hecha (18 tests nuevos; parent: 76 tests; analyze: solo warning previo spatial_capture_controller.dart:463).

## Log
L1. Quiero en un worktree que hagamos el asistennte inteligente para que guie al usuario para apredner a usar la app correctamente
L2. Para todos
L3. Que dicha guia inteligente sea para la parte web, cliente y agente
L4. 2026-11-19: implementación paralela T1–T3 (tres escritores, superficies disjuntas). Límites: suite completa del panel y de Flutter no corrida; RED del panel obtenido tras escribir la implementación.
L5. 2026-11-20: Quiero que dichos guias sean los mas completos posibles capaz de guiar a un usuario que cono conece para nada del softwae, dicha guia inteligente debe ser en español
L6. 2026-11-20: más o menos que se asemeje a un chatbot donde el usuario pueda escribir o que le de sugenerencias, de tal forma que el usuario no se pierde en el sistema
L7. 2026-11-20: chat implementado con motor por reglas (sin LLM, offline). Límites: 'cómo llegar' a otra pantalla escrito a mano y no contrastado con la navegación real; con teclado abierto a 320x480 el área del chat queda mínima; sin prueba en dispositivo ni lector de pantalla.
