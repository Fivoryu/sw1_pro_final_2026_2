# Tipos de diagrama según el modelo Grupo#12

> Referencia: qué **tipo de diagrama** corresponde en cada sección, según el documento modelo (páginas impresas 12–150 para PAPS/Sprint 0 y 151–373 para el CAPITULO 2). Los diagramas se referencian por **tipo** (y nombre cuando aplica); no se embeben imágenes.

## CAPITULO 1 — Sprint 0

| Sección del modelo | Módulo de RoomForge | Tipo de diagrama |
| --- | --- | --- |
| 8.1. Duración de los Sprints | S0-08 — Planificación | **Gantt** (diagrama de Gantt general de los Sprints) |
| 7.2. Paquetes y casos de uso | S0-07 — Casos de uso | **Use Case** (diagrama de casos de uso) |
| 11.1. Modelo de contexto | S0-11 — Modelos iniciales | **Diagrama de contexto** (actores externos y componentes) |
| 11.2. Modelo de casos de uso | S0-11 — Modelos iniciales | **Use Case** |
| 11.3. Modelo de datos | S0-11 — Modelos iniciales | **Class / ERD** (modelo de datos conceptual) |
| 11.4. Modelo de arquitectura | S0-11 — Modelos iniciales | **Package / Component** (arquitectura general) |
| 11.5. Modelo de interfaces principales | S0-11 — Modelos iniciales | Esquema de interfaces (sin UML definido en el modelo) |

## CAPITULO 2 — Proceso por HU (cada Sprint: módulo 02-proceso-por-hu)

| Subsección del modelo | Tipo de diagrama |
| --- | --- |
| 2.1.1.1. Diseño de la Arquitectura — Diagrama de Despliegue | **Deployment** |
| 2.1.1.2. Diseño de la Arquitectura — Diagrama de Paquetes | **Package** |
| 2.1.2.1. Diseño de Datos — Conceptual | **ERD conceptual** |
| 2.1.2.2. Diseño de Datos — Lógico | **Modelo lógico (relacional)** |
| 2.1.2.3. Diseño de Datos — Físico | **Esquema físico (tablas)** |
| 2.1.3.1. Lógica de Negocio — Diagrama de Comunicación | **Communication** |
| 2.1.3.2. Lógica de Negocio — Diagrama de Secuencia | **Sequence** |
| 2.1.4.1. Implementación — Diagrama de Componentes | **Component** |
| 2.1.5. Pruebas | Tablas de casos de prueba de caja negra (sin diagrama) |

## Otras secciones de cada Sprint

| Sección | Tipo |
| --- | --- |
| 6. Burndown y BurnUp (6.1 / 6.2) | **Gráfica Burndown** / **Gráfica BurnUp** |
| 8. Scrum Taskboard | Tabla/snapshot del taskboard (sin UML) |

> Nota: el modelo no asigna diagramas UML a las secciones 3 (equipo), 4 (requerimientos), 5 (funciones), 9 (infraestructura) ni 10 (patrón) del Sprint 0 — usan texto y tablas. Los estados de dominio se expresan en los diagramas de Comunicación/Secuencia del CAPITULO 2, no como Statechart separados en el Sprint 0.
