# Documentar la redefinición de RoomForge

## Objetivo y autorización
Consolidar la conversación de definición en documentación española verificable. El usuario autorizó documentar y preguntó si se puede implementar; no se inició código de producto en esta tarea.

## Alcance y restricciones
Creado `docs/redefinicion-roomforge.md`, conservando `docs/propuesta-roomforge-original.md` y documentación histórica. Separados acuerdos, propuestas y pendientes. No modificar submódulos, OpenSpec ni binario EA. Sin commits/push autorizados. Cambios previos en backend, panel, app cliente, infra y OpenSpec preservados.

## Ruta y controles
Preparación y escritura delegadas a gentle-ai-worker; revisión estructural del padre y verificación independiente gentle-ai-verify. Corrección final mecánica de periodicidad mensual por el padre. RDD desactivado. TDD no aplica a documentación; no se ejecutaron suites de producto. Documento de aproximadamente 330 líneas. Estrategia ask-on-risk; sin commits ni PR.

## Tareas
- [x] D1 (delegada): redactar documento integral con requisitos, arquitectura explicada, IA preentrenada, calidad, límites y ruta de implementación.
- [x] D2 (padre + verificador independiente): revisar documento, referencias y límites de autorización; corrección de alquiler mensual verificada. Resultado documental PASS, no validación de producto.

## Evidencia
Git status inicial: cambios existentes en submódulos, borrado previo de compose.postgres.yml y archivos OpenSpec; rama chore/roomforge-reset-01a0d0ec. No atribuir esos cambios a esta tarea. Informe previo de exploración no verificó código de producto; no asumir pérdida ni reutilización disponible.

El padre leyó el documento integral; el escritor corrigió distinción entre datos privados y catálogo público, depósito posterior a aceptación pendiente, fotografías MVP/video opcional, pipeline IA y puertas transitables. Verificador confirmó tres referencias locales existentes. ASSESS no pudo clasificar por archivos sin seguimiento del árbol ambiente; se siguió su plan conservador con verificador independiente, sin iniciar RDD.

Primera revisión independiente detectó periodicidad del precio base del alquiler insuficientemente explícita. El padre corrigió precio base mensual, suma de recargos mensuales y eliminó periodicidad de pendientes. Segunda revisión PASS y lectura final del padre confirmaron la corrección.

Comprobación del verificador: `git -c core.autocrlf=false diff --no-index --check -- /dev/null docs/redefinicion-roomforge.md`: exit 1, sin salida ni diagnósticos de whitespace; se conserva el resultado observado sin atribuir exit 0. El diff normal inicial no cubría archivos nuevos. URLs externas no se revalidaron en la revisión final. No se ejecutaron pruebas AR, IA, visor, blockchain o AWS.

## Próximo paso
Documentación terminada. Respuesta: sí se puede iniciar implementación incremental, comenzando por validar ARCore, visor móvil, detector y wallet; no se afirma factibilidad integral en un mes. Acordar decisiones pendientes y seguir el flujo SDD del proyecto para cambios sustanciales de producto. No se ha iniciado esa implementación.
