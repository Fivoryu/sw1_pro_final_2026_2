---
name: documentacion-software
description: "Trigger: documentación de Ingeniería de Software, README, requisitos, historias de usuario, casos de uso, sprints y trazabilidad. Genera documentación modular, consistente y verificable a partir de evidencia del repositorio."
license: Apache-2.0
metadata:
  author: "gentleman-programming"
  version: "1.0"
---

# documentacion-software

## Activation Contract

Activá esta skill cuando el proyecto necesite generar, ordenar o completar documentación de Ingeniería de Software: contexto, requisitos, backlog, HU, CU, diseño, sprints o cierre. Inspeccioná primero el repositorio y sus convenciones; en este proyecto, redactá en español.

## Hard Rules

- Si existe un documento modelo o un índice de referencia, ese índice gobierna el orden conceptual. No lo reemplaces por agrupaciones genéricas, aunque la documentación se divida en más archivos.
- Generá módulos enlazados, nunca un único documento monolítico ni secciones vacías; conservá nomenclatura, IDs estables y enlaces relativos.
- Usá evidencia real del repositorio. Separá hechos, inferencias, propuestas y gaps; no inventes métricas, resultados, fechas, roles ni artefactos.
- Mantené trazabilidad verificable entre problema, objetivos, requisitos, HU/CU, sprints, diseño, implementación, pruebas y cierre.

## Decision Gates

| Situación | Decisión |
| --- | --- |
| Existe modelo o índice | Reproducí exactamente su orden y sus niveles; solo modularizá la ubicación de los archivos. |
| Falta evidencia | Marcá `GAP-###` y proponé una acción, sin completar el dato. |
| Ya existe estructura | Extendela sin romper enlaces ni IDs. |
| No existe estructura | Aplicá el árbol modular de la referencia. |

## Execution Steps

1. Completá `assets/plan-documentacion-template.md` con fuentes, idioma, módulos, IDs, evidencias, gaps y validación.
2. Construí los módulos en este orden del modelo: `PAPS` (capítulos 1–10: Introducción; Descripción del problema; Métricas —ActivityWach, Kimai y Worklenz, con descripción, capturas/prototipos, MOT y MOF—; Definiciones para la estimación; Métodos de estimación; Análisis de riesgos; Planificación del tiempo; Recursos; Organización interna; Seguimiento/control); `PROCESO DE DESARROLLO SCRUM`; `CAPITULO 1 – REQUERIMIENTOS (Sprint 0)` con sus 13 apartados; `CAPITULO 2 - PROCESO DE DESARROLLO DE SOFTWARE` con `Sprint 1`, `Sprint 2` y `Sprint 3`; y al final `BIBLIOGRAFIA` y `ANEXOS`.
3. Para cada Sprint repetí las ocho secciones del índice: Sprint Planning, proceso/patrón por HU, Daily Scrum, Sprint Review, Sprint Retrospective, Burndown/BurnUp, esfuerzo y Scrum Taskboard. Dentro del proceso por HU conservá Diseño (arquitectura, datos y lógica de negocio), Implementación y Pruebas.
4. Registrá requisitos, HU, CU, diseño, implementación y pruebas de caja negra con IDs trazables; enlazá cada afirmación con su fuente o gap.
5. Auditá orden, enlaces, referencias locales, duplicación, estados, cobertura de la matriz y evidencia antes de entregar.

## Tablas canónicas del modelo (formato Grupo#12)

Verificado contra el PDF oficial con extracción pdfplumber (págs. 1–150). Usar exactamente estas columnas y estilos:

| Artefacto | Formato de tabla | Observaciones |
| --- | --- | --- |
| Requisitos funcionales (4.3) | `CÓDIGO \| MÓDULO \| REQUERIMIENTO \| PRIORIDAD` | Requerimiento en oración completa ("El sistema debe…"); prioridad Alta/Media/Baja |
| Requisitos no funcionales (4.4) | `CÓDIGO \| CATEGORÍA \| REQUERIMIENTO` | Categorías: Rendimiento, Seguridad, Compatibilidad, Privacidad… |
| Reglas de negocio (4.5) | Lista numerada: título + descripción (`1. Unicidad de jornada: …`) | No tabla |
| Funciones (5.x) | `FUNCIÓN \| DESCRIPCIÓN \| BACKLOG` por superficie | Backlog con PB-XX (puede agrupar varios: `PB-33, PB-34`) |
| Product Backlog (6.1) | Bloque cabecera (PRODUCT BACKLOG / PROYECTO / PRODUCT OWNER / VERSIÓN / FECHA) + `PB \| HISTORIA DE USUARIO \| DESCRIPCIÓN \| PRIORIDAD` | Una fila por PB |
| Historias de usuario (6.2) | `ID \| ROL \| HISTORIA DE USUARIO \| PRIORIDAD \| SPRINT \| PLATAFORMA` | Historia en frase completa "Como X quiero Y para Z"; plataforma Desktop/Web/Backend o las del proyecto |
| Casos de uso (7) | Lista `ID \| CASO DE USO` + `ACTOR \| DESCRIPCIÓN` + `PAQUETE FUNCIONAL \| CASOS DE USO RELACIONADOS \| DESCRIPCIÓN` | Los flujos detallados van al CAPITULO 2 por sprint |
| Duración de sprints (8.1) | `NRO. \| SPRINT \| FECHA DE INICIO \| FECHA DE FINALIZACIÓN \| DURACIÓN \| PROPÓSITO PRINCIPAL` + diagrama Gantt | |
| Criterios de división (8.2) | `CRITERIO \| APLICACIÓN EN EL PROYECTO` | Seis criterios: Dependencia funcional, Prioridad de negocio, Complejidad técnica, Equilibrio de carga, Valor incremental, Trazabilidad |
| Sprint individual (8.3-8.5) | Título `8.x. Sprint N — <nombre>`; `**Objetivo**: …` (párrafo); `PB \| HISTORIA DE USUARIO \| PRIORIDAD \| RESULTADO ESPERADO` (una fila por PB, nombre de la historia — no IDs de HU); `**Entregable principal del Sprint N**: …` | |
| Diseño por HU (CAPITULO 2) | 2.1.1 Arquitectura (Despliegue + Paquetes); 2.1.2 Datos (Conceptual/Lógico/Físico); 2.1.3 Lógica de Negocio (Comunicación + Secuencia); 2.1.4 Implementación (Componentes); 2.1.5 Pruebas (plan + casos de caja negra + reporte) | |

Regla de prioridad: usar **Alta/Media/Baja** del modelo (mapear Must → Alta, Should → Media).

## CAPITULO 2 — formatos verificados por sprint (referencia: `docs/modelo_doc/guia-capitulo2-modelo.md`)

| Pieza | Formato |
| --- | --- |
| Equipo Scrum (§1) | `INTEGRANTE \| ROL SCRUM` (una fila por persona) |
| Ficha de HU (§1) | `HU-XX Título`; `Descripción: Como <rol>, quiero <capacidad>, para <valor>.`; `Prioridad: Alta/Media/Baja — Estimación: N PHU`; `Criterios de Aceptación` (lista observable); `Desarrollador a cargo`; rótulo `Prototipo` (no habilita imágenes) |
| Sprint Backlog (§1) | Encabezado `SPRINT BACKLOG / Objetivo / Sprint: N — Tiempo programado: 3 semanas / Fecha inicio+finalización` + tabla `ID \| TAREA \| ESTIMACIÓN \| RESPONSABLE \| ESTADO \| PLATAFORMA` (ej.: `PB-01 \| Login escritorio \| 3 HRS \| Nelson Chumacero Miranda \| Hecho \| Desktop`) |
| Plan de pruebas (2.1.5.1) | `ID Prueba \| PB \| HU \| Funcionalidad evaluada \| Plataforma \| Responsable \| Estado` (casos `CP-XX`; el contador se reinicia en cada sprint; **no** usar numeración global) |
| Caso de caja negra (2.1.5.2) | Metadatos `CAMPO \| DESCRIPCIÓN` (Caso de prueba / PB relacionado / Descripción / Precondiciones) + pasos `PASO \| ACCIÓN \| RESULTADO ESPERADO \| ESTADO` + `Responsable: <integrante>` + `Resultado de la prueba: Satisfactorio` + `Adjunto` solo con evidencia |
| Reporte de prueba (2.1.5.3) | `RESULTADO GENERAL \| VALOR`: Total HU probadas / Total casos ejecutados / Satisfactorios / Fallidos / % cumplimiento / Estado general del Sprint N |

### Gaps del modelo a conservar como advertencia (GAP-CH2-00x)

- §1/§3/§4/§5 del CAPITULO 2 **no tienen diagramas**: no agregar UML por analogía; el **Gantt** pertenece al Sprint 0 §8.1, no al §1 de cada sprint (GAP-CH2-001).
- Burndown/BurnUp (§6): artefactos gráficos; series y ejes no recuperables del modelo (GAP-CH2-002).
- §7 se titula también "Gráfica de esfuerzo": solo la tabla de esfuerzo es verificable (GAP-CH2-003).
- §8 Taskboard: snapshot visual, columnas no recuperables del texto (GAP-CH2-004).
- En el modelo, el Sprint 3 agrega "2.1.1.3 Diagrama de arquitectura general" sin tipo UML definido: conservar el rótulo literal, no mapearlo a Deployment/Package/Component (GAP-CH2-005).
- Sprint 3 del modelo planifica CP-31..CP-38 y el reporte declara 6 casos: registrar la discrepancia, no copiarla (GAP-CH2-006).
- En el modelo "Estado general del Sprint 1" aparece por error en el reporte del Sprint 3: no corregirlo silenciosamente al copiar evidencia (GAP-CH2-007).

## Diagramas: solo tipo, nunca imagen embebida

- Los diagramas se referencian por **tipo** (y nombre cuando aplique); **no se embeben imágenes**.
- Tipos por sección del modelo: Sprint 0 → **Gantt** (8.1), **Use Case** (7.2), Modelos iniciales (11) → **Contexto · Use Case · Class/ERD · Package/Component · Interfaces**. CAPITULO 2 por sprint → **Deployment · Package · ERD (conceptual/lógico/físico) · Communication · Sequence · Component** + **Gráfica Burndown / Gráfica BurnUp** y **Taskboard**.
- El modelo **no usa Statechart en el Sprint 0**: los estados de dominio se expresan en los diagramas de Comunicación/Secuencia del CAPITULO 2. Las secciones 3/4/5/9/10 del Sprint 0 no llevan diagramas UML (texto y tablas).

## Lectura del modelo cuando no hay visión

- `pdftotext -f A -l B -layout -enc UTF-8 modelo.pdf out.txt` para texto; `pdfplumber` (Python) para extraer las **tablas con sus celdas reales** (`page.extract_tables()`), incluidas las celdas combinadas.
- No afirmes contenido del modelo sin verificación; los números de página impresos pueden diferir de los físicos (usar el TOC).

## Output Contract

Entregá los módulos generados o actualizados, el mapa de fuentes, la matriz de trazabilidad, el registro de evidencia y los gaps abiertos. Indicá qué se verificó y qué permanece pendiente; no presentes contenido no respaldado como hecho.

## References

- [Estándar modular y patrones](references/estandar-documentacion.md)
- [Plantilla de planificación](assets/plan-documentacion-template.md)
