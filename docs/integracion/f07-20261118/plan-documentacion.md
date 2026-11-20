# Fuentes y plan documental de la integración

**Objeto:** documentar una integración local revisable, en español profesional, sin alterar el estado académico del plan maestro ni atribuir evidencia física a pruebas sintéticas. Se aplica la skill [documentacion-software](../../../skills/documentacion-software/SKILL.md).

## Fuentes y precedencia

| Fuente | Uso |
|---|---|
| [Plan maestro](../../plan-maestro-roomforge.md), §1.4.1, §1.4.4 y F07 | Alcance de las superficies y dependencias F06/F08; no se cambia su estado. |
| [Redefinición](../../redefinicion-roomforge.md) | Reglas de producto; no se añaden requisitos comerciales. |
| [Issue #63](https://github.com/Fivoryu/sw1_pro_final_2026_2/issues/63) | Leída completa mediante GitHub: video/sensores, referencia, revisión y límites. No se cierra ni se amplía su alcance. |
| Misión del usuario del 18/11/2026 | Autoriza integrar en el worktree nuevo, conservar ambos aportes y producir este informe; prohíbe cambios en el original y operaciones de entrega Git. |
| `F07_INTEGRACION_TREVOR_LOCAL_20261118.md` del original | Dictamen de riesgos y comparación previa; leído sin modificar ni importar como artefacto raíz. |
| Diff local y archivos nuevos del original; commits `95a730e..46b092a` | Evidencia de los cambios comparados, distinta de los resultados de prueba. |
| [Contratos F06](../../api/f06-scene-contract.md) y [F07](../../api/f07-capture-package.md) | Modalidad, unidades, compatibilidad y aceptación. |
| Logs y resultados de esta ejecución | Única fuente de los resultados declarados como ejecutados aquí. La evidencia histórica queda en el original. |

## Módulos y trazabilidad

| Módulo | Propósito y comprobación |
|---|---|
| [Informe](README.md) | F07/#63, F06 y F08 → contratos → resolución semántica → límites. |
| [Verificación](verificacion.md) | Integración y regresión → comandos, resultados, fallos corregidos y pendientes físicos. |
| [Archivos del PR](archivos-pr.md) | Delta exacto contra `46b092a`, archivos nuevos y rutas heredadas de Trevor; excluye evidencia privada. |
| [OpenSpec existente](../../../openspec/changes/f07-integrity-hardening/tasks.md) | Se preservan los cuatro artefactos locales existentes; se agrega el registro verificable de integración, sin inventar autorizaciones de fases ni memoria remota. |

El registro original de auditorías F07-01..33/R01..R12 y sus logs continúa en la fuente de solo lectura. Las referencias a `odd/tasks/f07-audit-hardening.md` y `f07-residual-hardening.md` de los artefactos importados describen esa fuente histórica, no evidencia nueva ni archivos incluidos en este PR.

## Validación documental

- Se distinguen cambios de código, pruebas ejecutadas, evidencia histórica y aceptación pendiente.
- No se inventan CP, PB/HU, responsables ni resultados físicos; se conserva GAP-065 y no se cierran otros GAP académicos.
- El informe no crea diagramas, no modifica el binario EA ni reemplaza el índice de los documentos académicos.
- Los enlaces entre módulos y hacia contratos/código deben resolver; el manifiesto se genera al finalizar las modificaciones.
- Engram y dispatcher SDD no están disponibles en esta sesión. No se afirma haber persistido allí ni archivado el cambio.
