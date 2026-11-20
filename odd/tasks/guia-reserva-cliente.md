# Piloto de guía de reservas — app cliente
Rama `feat/guia-reserva-cliente`, base `main` en `f1947e9`. Solo ODD. Verificación: `flutter test`, `flutter analyze` y prueba de uso separada.
Commits y PR autorizados; no se solicita merge. Estrategia `single-pr`: una sola revisión hacia `main`, con commits separados para conversación y navegación. No se extiende a captura o panel antes de probar el piloto.

## Specs
S1. Piloto aceptado: «¿Cómo reservo este inmueble?». Guiar desde la pantalla actual con el nombre del control real; ofrecer «Llevame» solo para un destino válido. «El chat puede navegar; reservar, pagar o confirmar siempre queda en tus manos.»
S2. Cuando la consulta sea «reserva», preguntar «¿Querés iniciar una o consultar una que ya hiciste?» y permitir ambas opciones. Tras preguntar cómo reservar, «¿y cómo pago?» se refiere a esa reserva. Contexto solo durante la conversación, sin LLM.
S3. Consigna: «Llegá hasta el paso previo a confirmar una reserva usando la guía». Verificar si se encuentra el botón y si la respuesta se puede leer con el teclado abierto. Preparar el recorrido para una persona nueva con celular y lector de pantalla; no presentar las pruebas automáticas como evidencia de esa sesión.
S4. «SIn sdd, estamos con odd». Registro y ejecución únicamente con ODD.
S5. «Dale pr, puedes commitear sin problemas».

## Tasks
T1 · S1–S2,S4 · Orientación conversacional y aclaración con pruebas RED/GREEN · inline (una conducta con pruebas, T2 depende del contrato) · verificada: 3 RED y 51 pruebas de guía GREEN · commit `0f66cbb` (conversación y paso actual); 52 pruebas sobre ese commit aislado.
T2 · S1–S3 · Conectar navegación válida, comprobar recorrido, teclado y semántica; documentar la prueba en dispositivo · verificada en Flutter y en copia independiente (riesgo 3: pestañas compartidas) · commit `b0ebed1` (destinos, recorrido y guion).
T3 · S3 · Ejecutar la prueba de uso real con una persona nueva, registrar lo observado · bloqueada: falta una persona nueva con un teléfono y TalkBack o VoiceOver · sin commit.
T4 · S5 · Agrupar en commits verificables y publicar el piloto para revisión · realizada: [PR #104](https://github.com/Fivoryu/sw1_pro_final_2026_2/pull/104), con cierre de la [issue #103](https://github.com/Fivoryu/sw1_pro_final_2026_2/issues/103) al integrar.

## Log
L1. Puedes hacerlo?
L2. SIn sdd, estamos con odd
L3. La propuesta aceptada se limita al piloto de reservas en cliente. Base: PR #102 y `odd/tasks/guia-contextual.md`. Worktree independiente para preservar la rama activa. La línea base pasó: `flutter test --no-pub --reporter expanded test/guide_*_test.dart` (48 pruebas). El borrador OpenSpec propio quedó fuera del repositorio, sin eliminar archivos.
L4. La aclaración, las dos opciones y la pregunta de pago fallaron antes del cambio (3 RED, código 1); después pasaron las 51 pruebas de guía (código 0). La conversación se reinicia al cerrar la hoja. El punto de detención seguro es «Elegí cómo reservar»: elegir un medio ya puede crear la solicitud. `flutter devices` no detectó un celular.
L5. Cuatro pruebas de recorrido fallaron antes de la integración. El tema real exponía `BoxConstraints forces an infinite width` al abrir la guía: un TextButton heredaba el ancho infinito dentro de Row. Se acotó ese botón sin tocar el tema. Después pasaron las cuatro, incluida la navegación con teclado a 320×480 y la hoja de medios con 0 creaciones de reserva/pago. Suite cliente: 299 aprobadas (avisos «Invalid image data» sin fallos). Diferencial: 120 respuestas y sugerencias no afectadas idénticas a `f1947e9`, con el mismo stdout, stderr y código 0. Guion manual: `apps/cliente_mobile/docs/prueba-guia-reservas.md`.
L6. `flutter analyze --no-pub` finalizó sin diagnósticos. La evaluación nativa inicial aún no pudo medir el candidato con archivos nuevos sin declarar; la verificación independiente funcional se lanzó sobre el worktree. Sin commit ni publicación.
L7. Verificación independiente en copia aislada del candidato: dependencias offline y 19 pruebas de conversación, navegación y shell, código 0. S1 y S2 aprobadas; S3 acreditada solo en condiciones automatizadas, T3 pendiente. S4: sin cambios de OpenSpec. La suite completa del padre también incluyó notificaciones. La revisión nativa no emitió dictamen: `assessment-unavailable` al evaluar los archivos nuevos de la rama aun con selección explícita (sin candidato ni ejecuciones de revisores).
L8. Dale pr, puedes commitear sin problemas
L9. «Un solo PR (menos recomendado por tamaño)» y «Crear una issue específica del piloto». Corte de producto: `f1947e9..0f66cbb` y `0f66cbb..b0ebed1`; ambas unidades resultaron `under_budget` en la evaluación nativa de commits. El PR reúne ambas en un solo diff por decisión del responsable.
L10. GitHub confirmó el PR #104 abierto desde `feat/guia-reserva-cliente` hacia `main`, con `Closes #103`. El rango de producto mide 672 líneas cambiadas y la evaluación del conjunto no requirió revisión nativa adicional. Publicar el PR no acredita un merge ni la prueba en dispositivo de T3.
