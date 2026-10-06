# Plan maestro — fichas de ejecución y piloto F06.1

## Objetivo, problema y alcance autorizado

Reducir decisiones implícitas y redescubrimiento para personas o agentes que ejecuten el plan. El usuario autorizó el 2026-10-05 mantener el mapa maestro y agregar una ficha ejecutable piloto para F06.1, sin reescribir las fases completadas ni implementar el visor.

Superficies de esta actualización: `docs/plan-maestro-roomforge.md` y este registro. Conservar IDs, estados históricos, fuentes canónicas y decisiones pendientes. No modificar código de producto, infraestructura, OpenSpec ni Enterprise Architect.

## Restricciones y estrategia

- Documentación en español profesional y neutral; comandos e identificadores técnicos sin traducción.
- El alcance original no autorizaba commits, push, servicios, instalaciones ni operaciones remotas. El 2026-10-06 el usuario autorizó commit y push a `main` en el remoto `origin` de este repositorio; servicios, instalaciones y otros destinos siguen fuera de alcance.
- Rama existente: `docs/f05-plan-maestro-sync`; árbol inicialmente limpio.
- Estrategia de entrega: `ask-on-risk`; previsión de 120–220 líneas documentales añadidas/modificadas, sin archivos generados.
- TDD no aplicable: documentación pasiva sin comportamiento de producto. Verificación estructural y de enlaces, no evidencia ficticia de rendimiento.
- Espejo Engram: pendiente. Los intentos MCP anteriores fallaron por múltiples sesiones activas; no hay identidad de sesión autoritativa disponible.

## Tareas y criterios de aceptación

- [x] E1 — Añadir formato reutilizable de ficha y piloto F06.1 al plan. Ruta: delegada; lectura preparatoria y redacción no mecánica. La ficha contiene entradas, alcance permitido/prohibido, pasos ordenados, entregables, verificaciones observables y bloqueos localizados. Las decisiones aún abiertas no aparecen como acuerdos ni métricas medidas. Mantener F06 pendiente.
- [x] E2 — Verificar el documento y registrar resultados. Ruta: delegada para comprobaciones, más lectura puntual del padre. Comprobar diff/whitespace, enlaces locales nuevos, coherencia con F06 y ausencia de cambios fuera de las superficies autorizadas.

## Comprobaciones aplicables

- `git diff --check`.
- `git diff --stat -- docs/plan-maestro-roomforge.md` y `git status --short`.
- Resolver los enlaces locales añadidos en el diff y comprobar existencia de sus destinos; cualquier ruta futura se identifica como propuesta, no enlace a un archivo inexistente.
- Lectura estructural: preservar estados históricos, distinguir documentación de implementación y mantener localizados los bloqueos reales.
- No se ejecutan suites de backend/Flutter/panel ni pruebas en S23 FE: no se modifica ni implementa producto.

## Progreso y evidencia

2026-10-05: alcance confirmado, fase piloto seleccionada y registro creado antes de editar el plan maestro. E1 completada por el escritor: se añadió el contrato reutilizable de ficha y la ficha piloto F06.1 con fixture y protocolo propuestos; el WebView y los umbrales siguen sujetos a confirmación humana. La lectura de `apps/cliente_mobile/pubspec.yaml`, README y CI confirmó que el manifiesto actual no declara una dependencia WebView y que el README documenta `flutter test`, `flutter analyze` y `flutter build apk --debug`. `git diff --check` terminó con exit 0; emitió advertencias globales de conversión LF→CRLF. `git diff --stat -- docs/plan-maestro-roomforge.md` informó 44 inserciones; `git status --short` mostró el plan modificado y este registro sin seguimiento. No se agregaron enlaces Markdown locales; la bitácora de salida es una ruta propuesta sin enlace. F06 sigue pendiente. Sin suites, builds, teléfono, commits o push.

E2 completada: el padre leyó el diff completo, comprobó conservación de estados/cortes históricos y separación entre propuestas y resultados, y repitió `git diff --check` (exit 0, sin diagnósticos). Solo se modificó el plan y se creó este registro. La primera consulta de modo RDD falló por permisos; la consulta autorizada posterior confirmó modo `on` global, sin cambiarlo. La evaluación inicial fue no clasificable por el archivo nuevo; se obtuvo el inventario canónico y se repitió incluyendo explícitamente este registro. Resultado observado: `gentle-ai.review-assessment/v1`, riesgo `passive`, motivo `non_executable_only`, 2 rutas/81 líneas, `review_due: false` (`passive`). No se inició revisión, no hubo consentimiento ni aprobación inventada. Espejo Engram pendiente: el MCP rechazó la escritura por múltiples sesiones activas.

## Próximo paso

Publicar únicamente esta actualización documental mediante el commit y push a `main` autorizados el 2026-10-06. La implementación de F06.1 requiere autorización separada y cerrar solo las decisiones que la bloquean. El espejo Engram debe sincronizarse cuando exista una identidad de sesión autoritativa o un mecanismo independiente de guardado admitido por el proveedor.
