# Guía estructural del CAPITULO 2 — Modelo Grupo#12

## Propósito y alcance

Esta guía describe la estructura que deben reproducir los módulos de **Sprint 1**, **Sprint 2** y **Sprint 3** sin cambiar el orden conceptual del modelo Grupo#12. La unidad repetida es el sprint completo con sus ocho secciones:

1. Sprint Planning
2. Proceso/patrón de desarrollo por Historia de Usuario
3. Daily Scrum
4. Sprint Review
5. Sprint Retrospective
6. Burndown y BurnUp
7. Gráfica de esfuerzo y datos de esfuerzo
8. Scrum Taskboard

**Regla de diagramas del proyecto:** se referencia únicamente el **tipo** de diagrama y su ubicación. No se embeben imágenes ni se inventa un tipo cuando el modelo no lo especifica.

## Evidencia consultada

| Fuente | Alcance verificado |
| --- | --- |
| `docs/modelo_doc/extracto-capitulo2-p151-373.txt` | CAPITULO 2 completo: Sprint 1, Sprint 2 y Sprint 3; páginas impresas 151–373. |
| `docs/modelo_doc/extracto-sprints-p85-150.txt` | Contexto de Sprint 0: §8.1–§8.5, límites entre la planificación general y CAPITULO 2. |
| `Documento Final - Grupo#12 - estandar de cod.pdf` | Verificación de celdas y encabezados con `pdfplumber`, especialmente páginas 152–205, 223–290, 310–373. |

### Cómo leer las marcas

- **Verificado:** aparece directamente en el extracto o fue confirmado en la tabla del PDF.
- **Derivado:** conclusión mecánica de la repetición de la estructura.
- **GAP:** el extracto no permite completar el dato; no debe inventarse.

### Gaps del modelo que deben conservarse como advertencia

- **GAP-CH2-001:** en las secciones 1, 3, 4 y 5 no se encontró un tipo de diagrama explícito. No agregar UML por analogía.
- **GAP-CH2-002:** las gráficas de Burndown y BurnUp de §6 aparecen como artefactos gráficos, pero sus series, ejes y valores no son recuperables del texto extraído.
- **GAP-CH2-003:** §7 se titula también “Gráfica de esfuerzo”, pero la extracción solo permite verificar la tabla de esfuerzo; no permite determinar un tipo adicional de gráfica.
- **GAP-CH2-004:** §8 contiene el rótulo “Scrum Taskboard” y una captura/artefacto visual, pero no se recuperan sus columnas ni sus filas mediante extracción textual.
- **GAP-CH2-005:** Sprint 3 agrega “Diagrama de arquitectura general” en `2.1.1.3`, pero el modelo no especifica un tipo UML normalizado. Mantener el rótulo literal y no mapearlo a Deployment, Package o Component sin evidencia.
- **GAP-CH2-006:** el reporte de pruebas de Sprint 3 informa 6 historias/casos, mientras el plan enumera CP-31 a CP-38 (8 casos). Conservar la discrepancia y resolverla antes de cerrar el módulo.
- **GAP-CH2-007:** el reporte de pruebas de Sprint 3 dice “Estado general del Sprint 1”; es una inconsistencia literal del modelo, no debe corregirse silenciosamente al copiar evidencia.

---

# 1. Sprint Planning

## 1.1. Estructura narrativa común

Cada sprint comienza con el título `1. Sprint Planning` y conserva esta secuencia:

1. **1.1. Objetivos del Sprint**
   - **1.1.1. Objetivo general del Sprint N:** un párrafo que define el incremento funcional del sprint.
   - **1.1.2. Objetivos específicos:** lista de acciones/funcionalidades que deben implementarse.
2. **1.2. Equipo Scrum:** tabla de integrantes y roles.
3. **1.3. Historias de Usuario:** una ficha narrativa por HU seleccionada.
4. **1.4. Contexto del sistema:** párrafo sobre el alcance del sistema en ese sprint.
5. **1.5. Sprint Backlog:** objetivo del sprint, duración, fechas y tabla de tareas.

El modelo usa dos escalas distintas: las fichas de HU expresan `Estimación: N PHU`, mientras el Sprint Backlog expresa `N HRS`. No sustituir una por otra.

## 1.2. Formatos de tabla y ficha

### Equipo Scrum

Tabla exacta:

```text
INTEGRANTE | ROL SCRUM
```

Una fila por persona. Los roles observados son `Product Owner`, `Scrum Master` y `Developer`.

### Historia de Usuario

No hay una tabla canónica con encabezado; el modelo usa una ficha repetida con este orden:

```text
HU-XX  Título de la historia
Descripción: Como <rol>, quiero <capacidad>, para <valor>.
Prioridad: Alta/Media/Baja    Estimación: N PHU
Criterios de Aceptación
- criterio observable
- criterio observable
...
Desarrollador a cargo: <integrante>
Prototipo
```

El bloque `Prototipo` aparece como rótulo al final de la ficha. No es un tipo de diagrama y no habilita a embebar imágenes en los módulos.

### Sprint Backlog

Antes de la tabla aparecen estos datos:

```text
SPRINT BACKLOG
Objetivo: <párrafo>
Sprint: N                 Tiempo programado: 3 semanas
Fecha inicio: <dd/mm/aaaa>       Fecha finalización: <dd/mm/aaaa>
```

Tabla exacta de tareas:

```text
ID | TAREA | ESTIMACIÓN | RESPONSABLE | ESTADO | PLATAFORMA
```

Muestra de Sprint 1 verificada:

```text
PB-01 | Login escritorio | 3 HRS | Nelson Chumacero Miranda | Hecho | Desktop
```

Las celdas de tareas extensas, nombres y plataformas pueden estar combinadas en varias líneas en el PDF; al modularizar, conservar una fila por PB y no perder el vínculo entre tarea, responsable, estado y plataforma.

## 1.3. Variaciones verificadas por sprint

| Sprint | Contenido específico observado |
| --- | --- |
| **Sprint 1** | 10 HU: HU-01 a HU-07, HU-24, HU-26 y HU-31. Fechas: 18/04/2026–09/05/2026. Estado del backlog: `Hecho`. Después de la tabla aparece una explicación narrativa de la dependencia funcional entre autenticación, administración y jornada. |
| **Sprint 2** | 17 elementos/HU de monitoreo, navegación, inactividad, consultas y productividad. Fechas: 10/05/2026–31/05/2026. Estado del backlog: `Hecho`. La tabla mantiene las seis columnas; no se encontró en el extracto un párrafo posterior equivalente al de Sprint 1. |
| **Sprint 3** | 19 elementos de supervisión avanzada, reportes, alertas, evidencias, comunicación, ubicación y cámara. Fechas: 01/06/2026–22/06/2026. Estado del backlog: `Pendiente` en la tabla de planificación. La tabla mantiene las seis columnas y varias plataformas combinadas (`Desktop`, `Web`, `Backend`). |

## 1.4. Diagramas en Sprint Planning

**GAP-CH2-001:** el extracto no identifica un tipo de diagrama dentro de §1 de ninguno de los tres sprints. No insertar Gantt aquí por confusión con Sprint 0 §8.1: el **Gantt** pertenece a la planificación general de Sprint 0, no a la sección 1 repetida de CAPITULO 2.

---

# 2. Proceso/patrón de desarrollo por Historia de Usuario

El título exacto es `2. Proceso/Patrón de desarrollo por Historia de Usuario`. La estructura interna que debe conservarse es:

```text
2. Proceso/Patrón de desarrollo por Historia de Usuario
  2.1. Diseño
    2.1.1. Diseño de la Arquitectura
      2.1.1.1. Diagrama de Despliegue
      2.1.1.2. Diagrama de Paquetes
      [solo Sprint 3] 2.1.1.3. Diagrama de arquitectura general
    2.1.2. Diseño de Datos
      2.1.2.1. Diseño Conceptual
      2.1.2.2. Diseño Lógico
      2.1.2.3. Diseño Físico
    2.1.3. Diseño de la Lógica de Negocio
      2.1.3.1. Diagrama de Comunicación
      2.1.3.2. Diagrama de Secuencia
    2.1.4. Implementación
      2.1.4.1. Diagrama de Componentes
    2.1.5. Pruebas
      2.1.5.1. Plan de pruebas
      2.1.5.2. Casos de prueba funcionales de caja negra
      2.1.5.3. Reporte de prueba
```

### Regla de alcance

Aunque el título dice “por Historia de Usuario”, el modelo no presenta una ficha separada de arquitectura, datos, lógica e implementación para cada HU. Presenta artefactos agrupados por sprint y luego casos de prueba por HU. No crear repeticiones artificiales que el modelo no tiene.

## 2.1.1. Diseño de la Arquitectura

### Contenido

- `2.1.1.1. Diagrama de Despliegue`: referencia el tipo **Deployment**.
- `2.1.1.2. Diagrama de Paquetes`: referencia el tipo **Package**.
- Sprint 3 agrega `2.1.1.3. Diagrama de arquitectura general`; conservar el nombre, pero aplicar **GAP-CH2-005** porque el tipo no está normalizado en el modelo.

No se encontró una tabla textual asociada a estos diagramas.

### Tipos por sprint

| Sprint | Tipos y ubicación |
| --- | --- |
| Sprint 1 | **Deployment** en `2.1.1.1`; **Package** en `2.1.1.2`. |
| Sprint 2 | **Deployment** en `2.1.1.1`; **Package** en `2.1.1.2`. |
| Sprint 3 | **Deployment** en `2.1.1.1`; **Package** en `2.1.1.2`; rótulo literal `2.1.1.3 Diagrama de arquitectura general` (**GAP-CH2-005**). |

## 2.1.2. Diseño de Datos

### 2.1.2.1. Diseño Conceptual

El modelo reserva esta subsección para el diseño conceptual del dominio. El extracto textual no expone una tabla de atributos completa ni un encabezado tabular inequívoco; por eso no se debe completar con entidades inventadas.

**Tipo de referencia permitido:** **ERD conceptual**. Si el módulo no tiene las entidades verificadas, usar un GAP.

### 2.1.2.2. Diseño Lógico

El modelo representa cada entidad como una tabla visual de tres niveles:

```text
<Entidad>                         [nombre de entidad]
PK | FK | FK ...                  [marcadores de claves]
<atributo 1> | <atributo 2> | ...  [columnas/campos]
```

No es una tabla de registros; es una representación relacional del esquema. Las columnas cambian por entidad y sprint. Ejemplos verificados de Sprint 1:

```text
Empresa
PK
IdEmpresa | NombreEmpresa | Slug | Estado | FechaCreacion

Rol
PK
IdRol | Codigo | NombreRol | Descripcion | Estado | FechaCreacion

Usuario
PK | FK | FK | FK
IdUsuario | IdEmpresa | IdRol | IdUsuarioCreador | Nombres | Apellidos |
Username | Email | PasswordHash | Estado | UltimoLogin | FechaCreacion |
FechaActualizacion

ConfiguracionJornadaDetalle
PK | FK
IdDetalle | IdConfiguracionJornada | DiaSemana | EsLaborable | HoraInicio | HoraFin
```

Entidades base observadas:

- **Sprint 1:** Empresa, Rol, Usuario, Sesion, ConfiguracionJornada, ConfiguracionJornadaDetalle, UsuarioJornada, BitacoraAdministrativa y Notificacion.
- **Sprint 2:** conserva las entidades base y agrega, entre otras, RegistroJornadaEvento, UsuarioPreferencia, AplicacionDetectada, UsoAplicacion, EstadoTrabajador, RegistroJornada, EventoAgente, PeriodoInactividad, ResumenProductividad, ClasificacionProductividad, DominioProductividad y VisitaNavegacion.
- **Sprint 3:** conserva el dominio operativo y agrega EventoSospechoso, ReglaAlerta, EstadoAlerta, Alerta, ConsentimientoMonitoreo, CapturaPeriodica, EvidenciaCaptura, Reporte/ReporteDetalle, ConversacionChat, MensajeChat, UbicacionReferencial, IndicadorGeneral y DashboardWidget.

**Tipo de referencia permitido:** **ERD lógico**.

### 2.1.2.3. Diseño Físico

El modelo no usa una tabla Markdown para esta subsección: usa bloques de SQL/DDL. El patrón es:

```sql
-- =========================
-- N. <NOMBRE DEL BLOQUE>
-- =========================
CREATE TABLE <tabla> (...);
```

El bloque puede incluir `PRIMARY KEY`, `FOREIGN KEY`, `UNIQUE`, `CHECK`, índices y, en Sprint 2, datos base con `INSERT`. Sprint 3 comienza además con extensión/esquema SQL (`CREATE EXTENSION`, `CREATE SCHEMA`, `SET search_path`) y usa nombres físicos diferentes en parte del esquema. No convertir el SQL en una tabla de campos resumida si se busca replicar el formato del modelo.

**Tipo de referencia permitido:** **ERD físico** solo si existe evidencia del diagrama. El texto verificado demuestra el **esquema físico SQL**, no una imagen adicional; no afirmar un diagrama físico separado sin fuente.

## 2.1.3. Diseño de la Lógica de Negocio

### 2.1.3.1. Diagrama de Comunicación

Referencia únicamente el tipo **Communication** y conserva los rótulos funcionales que acompañan cada artefacto:

| Sprint | Rótulos observados |
| --- | --- |
| Sprint 1 | PB01 Gestión de usuario; PB05 Registro de actividad de jornada; PB26 Notificaciones; PB31 Administración de jornada. |
| Sprint 2 | Monitoreo de aplicaciones; Consulta de aplicaciones. |
| Sprint 3 | CU32 Gestión de alertas y reglas de alerta; CU34 Comunicación operativa, chat y ubicación referencial. |

### 2.1.3.2. Diagrama de Secuencia

Referencia únicamente el tipo **Sequence** y conserva los rótulos observados:

| Sprint | Rótulos observados |
| --- | --- |
| Sprint 1 | PB01 Gestión de usuario; PB05 Registro de actividad de jornada; PB26 Notificaciones; PB31 Administración de jornada. |
| Sprint 2 | PB-11 Intercepción URL; PB-13 Detección de inactividad. |
| Sprint 3 | CU26 Detección de eventos sospechosos; CU27 Captura de evidencia por cámara ante evento sospechoso; CU29 Visualización de galería de evidencias; CU30 Indicadores generales y dashboard operativo; CU33 Generación y exportación de reportes. |

No se encontró una tabla textual para Comunicación o Secuencia.

## 2.1.4. Implementación

### 2.1.4.1. Diagrama de Componentes

Referencia el tipo **Component** en los tres sprints. El modelo no expone una tabla de componentes ni un inventario textual equivalente en el extracto.

## 2.1.5. Pruebas

### 2.1.5.1. Plan de pruebas

El texto narrativo indica que el plan relaciona cada prueba con PB, HU, funcionalidad, plataforma, responsable y resultado esperado/obtenido. La tabla exacta es:

```text
ID Prueba | PB | HU | Funcionalidad evaluada | Plataforma | Responsable | Estado
```

Muestras verificadas:

```text
CP-01 | PB-01 | HU-01 | Login en aplicación de escritorio | Desktop / Backend | ... | Satisfactorio
CP-02 | PB-02 | HU-02 | Login en panel administrativo web | Web / Backend | ... | Satisfactorio
```

Variantes observadas:

- Sprint 1: `CP-01` a `CP-10`, 10 casos.
- Sprint 2: `CP-01` a `CP-17`, 17 casos; el contador se reinicia localmente.
- Sprint 3: `CP-31` a `CP-38` en el plan; el reporte final declara 6 casos (**GAP-CH2-006**).

### 2.1.5.2. Casos de prueba funcionales de caja negra

Cada caso mantiene primero una tabla de metadatos:

```text
CAMPO | DESCRIPCIÓN
```

Filas observadas:

```text
Caso de prueba | CP-XX
Product Backlog relacionado | PB-XX <nombre>
Descripción | <objetivo observable>
Precondiciones | <estado, datos, permisos y servicios requeridos>
```

Después aparece la tabla de pasos:

```text
PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO
```

El patrón del caso es:

1. `Prueba de Historia de Usuario HU-XX: <nombre>`.
2. Metadatos con `CAMPO | DESCRIPCIÓN`.
3. Pasos numerados, incluyendo entradas válidas, inválidas, permisos, filtros o límites cuando correspondan.
4. `Responsable: <integrante>`.
5. `Resultado de la prueba: Satisfactorio` u otro estado observado.
6. `Adjunto` cuando el modelo lo incluye; no completar el adjunto si no existe evidencia.

Las acciones y los resultados esperados son observables desde Desktop, Web, Backend o DB según la HU. No reemplazar la tabla de pasos por una descripción general.

### 2.1.5.3. Reporte de prueba

El reporte comienza con un párrafo narrativo sobre la ejecución de pruebas de caja negra y termina con observaciones y una conclusión. Su tabla exacta es:

```text
RESULTADO GENERAL | VALOR
```

Filas del modelo:

```text
Total de historias de usuario probadas | N
Total de casos de prueba ejecutados | N
Casos satisfactorios | N
Casos fallidos | N
Porcentaje de cumplimiento | 100%
Estado general del Sprint N | Aprobado
```

Variantes y advertencias:

- Sprint 1: 10 historias, 10 casos, 10 satisfactorios, 0 fallidos, 100 %, Aprobado.
- Sprint 2: 17 historias, 17 casos, 17 satisfactorios, 0 fallidos, 100 %, Aprobado.
- Sprint 3: la tabla declara 6 historias y 6 casos, aunque el plan enumera 8 casos (**GAP-CH2-006**); además aparece “Estado general del Sprint 1” (**GAP-CH2-007**).
- La conclusión enumera las funcionalidades verificadas y el incremento que habilita para el sprint siguiente.

---

# 3. Daily Scrum

## 3.1. Patrón narrativo

Cada sprint contiene bloques por semana:

```text
3. Daily Scrum
SEMANA N
<fecha inicial> a <fecha final>
```

Dentro de cada semana aparece un bloque por integrante. La información se organiza por día y responde siempre tres preguntas:

- `¿Qué hiciste?`
- `¿Qué harás?`
- `¿Qué obstáculos encontraste en el camino?`

Las respuestas son narrativas y reflejan avance, próximo trabajo y bloqueos. No sustituir este registro por una lista de tareas sin fechas.

## 3.2. Tabla

El formato de tabla observado es:

```text
Pregunta | <Integrante> | Sábado | Domingo | Lunes | Martes | Miércoles | Jueves | Viernes
```

La ubicación de los días varía según la semana del documento. En Sprint 3 también se observa el orden `Lunes | Martes | Miércoles | Jueves | Viernes | Sábado | Domingo`. Mantener la fecha y el orden realmente usado; no inventar días sin actividad.

No se encontró un tipo de diagrama en esta sección: **GAP-CH2-001**.

---

# 4. Sprint Review

## 4.1. Estructura narrativa

El modelo abre con `SPRINT REVIEW` y organiza la revisión en este orden:

1. Objetivo de la revisión.
2. Participantes.
3. Presentación del incremento.
4. Tareas completadas.

### Tabla de objetivo

```text
Objetivo de la revisión | <párrafo de objetivo>
```

### Participantes

```text
Nombre | Rol
```

### Presentación del incremento

```text
FUNCIÓN PRESENTADA | RETROALIMENTACIÓN
```

La retroalimentación expresa validaciones, recomendaciones y observaciones del Product Owner/equipo.

### Tareas completadas

```text
Tarea | Estado
```

Los estados observados son `Terminada`. En Sprint 3 las filas corresponden a PB-27 a PB-46, con los PB reservados por el modelo.

No se encontró un tipo de diagrama en esta sección: **GAP-CH2-001**.

---

# 5. Sprint Retrospective

## 5.1. Estructura narrativa

El modelo abre con `SPRINT RETROSPECTIVE` y conserva:

1. `Fecha: <fecha>`.
2. `Objetivos de la retrospectiva: <párrafo>`.
3. Participantes.
4. `Temas Para Tratar: <párrafo>`.
5. Discusión en tres columnas.

### Participantes

```text
Nombres | Rol
```

### Discusión

```text
¿Que hicimos bien? | ¿Qué debemos dejar de hacer? | ¿Qué podemos mejorar?
```

La discusión debe contener observaciones del sprint, prácticas a abandonar y acciones de mejora. No completar responsables o acciones que no estén evidenciados.

No se encontró un tipo de diagrama en esta sección: **GAP-CH2-001**.

---

# 6. Burndown y BurnUp

## 6.1. Subestructura

La sección conserva exactamente:

```text
6. Burndown y BurnUp
  6.1. Grafica Burndown
  6.2. Grafica BurnUp
```

## 6.2. Tipos de diagrama

- `6.1. Grafica Burndown`: **Burndown chart**.
- `6.2. Grafica BurnUp`: **BurnUp chart**.

El extracto textual muestra el lugar de cada artefacto, pero no sus datos. Aplicar **GAP-CH2-002**: no inventar puntos, fechas, ejes ni valores. No sustituir estas gráficas por Gantt; el **Gantt** pertenece a Sprint 0 §8.1.

---

# 7. Gráfica de esfuerzo y datos de esfuerzo

## 7.1. Tabla exacta

El modelo presenta el título `7. Grafica de esfuerzo y Datos de esfuerzo` y una tabla con estos encabezados:

```text
CÓDIGO | TAREA | PREVISTO DE HORAS | REAL DE HORAS
```

Cada fila vincula un PB con la tarea y separa horas previstas de horas reales. Muestras verificadas:

```text
PB-01 | Login escritorio | 17 hrs | 18 hrs
PB-08 | Capturar proceso activo del sistema | 5 hrs | 6 hrs
PB-27 | Detectar evento sospechoso según reglas de inactividad y aplicación no laboral | 8 hrs | 9 hrs
```

La última fila conserva el formato de resumen:

```text
Total | Esfuerzo total del Sprint N | <previsto> | <real>
```

Totales verificados en el PDF:

| Sprint | Previsto | Real |
| --- | ---: | ---: |
| Sprint 1 | 114 hrs | 119 hrs |
| Sprint 2 | 79 hrs | 85 hrs |
| Sprint 3 | 103 hrs | 111 hrs |

## 7.2. Diagramas

El título menciona una “Gráfica de esfuerzo”, pero el tipo y sus series no se pueden verificar en la extracción. Aplicar **GAP-CH2-003**; como mínimo, conservar la tabla con sus cuatro columnas y los totales previstos/reales.

---

# 8. Scrum Taskboard

La sección conserva únicamente el título:

```text
8. Scrum Taskboard
```

El modelo coloca un snapshot/artefacto visual de Taskboard después de §8. No se recuperan mediante el extracto textual las columnas, tarjetas, estados ni fecha de captura. Referenciar solo el tipo **Taskboard** y aplicar **GAP-CH2-004** si el contenido no está disponible. No inventar el estado de PB ni reemplazarlo con la tabla del Sprint Backlog.

---

# Matriz rápida de tipos de diagrama por sprint

| Sección y ubicación | Sprint 1 | Sprint 2 | Sprint 3 |
| --- | --- | --- | --- |
| `2.1.1.1` | Deployment | Deployment | Deployment |
| `2.1.1.2` | Package | Package | Package |
| `2.1.1.3` | No aparece | No aparece | Rótulo “arquitectura general”; tipo no especificado (**GAP-CH2-005**) |
| `2.1.2.1` | ERD conceptual | ERD conceptual | ERD conceptual |
| `2.1.2.2` | ERD lógico | ERD lógico | ERD lógico |
| `2.1.2.3` | Esquema físico SQL; no afirmar diagrama adicional | Esquema físico SQL; no afirmar diagrama adicional | Esquema físico SQL; no afirmar diagrama adicional |
| `2.1.3.1` | Communication | Communication | Communication |
| `2.1.3.2` | Sequence | Sequence | Sequence |
| `2.1.4.1` | Component | Component | Component |
| `6.1` | Burndown chart | Burndown chart | Burndown chart |
| `6.2` | BurnUp chart | BurnUp chart | BurnUp chart |
| `8` | Taskboard | Taskboard | Taskboard |

En `1`, `3`, `4`, `5` y `7` no se encontró un tipo adicional verificable (**GAP-CH2-001** y **GAP-CH2-003**).

---

# Checklist de conformidad para los ocho módulos de cada sprint

## Orden y encabezados

- [ ] El módulo conserva las ocho secciones en el orden 1–8 del CAPITULO 2.
- [ ] Sprint Planning contiene `1.1` a `1.5` en ese orden.
- [ ] El proceso por HU conserva literalmente `2.1.1` Arquitectura, `2.1.2` Datos, `2.1.3` Lógica de Negocio, `2.1.4` Implementación y `2.1.5` Pruebas.
- [ ] Sprint 3 incluye `2.1.1.3 Diagrama de arquitectura general` como variación documentada; Sprint 1 y Sprint 2 no lo agregan.

## Sprint Planning

- [ ] Existe la tabla `INTEGRANTE | ROL SCRUM`.
- [ ] Cada HU tiene título, descripción Como/Quiero/Para, prioridad, estimación en PHU, criterios de aceptación, desarrollador y rótulo de prototipo cuando corresponda.
- [ ] Existe el bloque `SPRINT BACKLOG` con objetivo, sprint, tiempo programado y fechas.
- [ ] La tabla de backlog usa exactamente `ID | TAREA | ESTIMACIÓN | RESPONSABLE | ESTADO | PLATAFORMA`.
- [ ] La estimación de backlog en HRS no se confunde con la estimación de HU en PHU.
- [ ] Las filas conservan un PB, su tarea, responsable, estado y plataforma.
- [ ] No se inserta Gantt en §1; el Gantt pertenece al Sprint 0 §8.1.

## Proceso/patrón por HU

- [ ] `2.1.1.1` referencia Deployment y `2.1.1.2` referencia Package.
- [ ] `2.1.2.1` se identifica como ERD conceptual, sin inventar entidades ausentes.
- [ ] `2.1.2.2` conserva la representación por entidad con marcadores PK/FK y atributos.
- [ ] `2.1.2.3` conserva el patrón SQL/DDL, constraints, índices y seeds solo cuando estén evidenciados.
- [ ] `2.1.3.1` referencia Communication y conserva PB/CU de la fuente.
- [ ] `2.1.3.2` referencia Sequence y conserva PB/CU de la fuente.
- [ ] `2.1.4.1` referencia Component.
- [ ] No se presenta una repetición artificial de arquitectura/datos por cada HU si la fuente entrega un artefacto agrupado por sprint.
- [ ] El plan usa `ID Prueba | PB | HU | Funcionalidad evaluada | Plataforma | Responsable | Estado`.
- [ ] Cada caso de caja negra usa las tablas `CAMPO | DESCRIPCIÓN` y `PASO | ACCIÓN | RESULTADO ESPERADO | ESTADO`.
- [ ] Cada caso incluye precondiciones, pasos, responsable y resultado observado; los adjuntos inexistentes permanecen como GAP.
- [ ] El reporte usa `RESULTADO GENERAL | VALOR` y no declara aprobado sin evidencia.
- [ ] Se revisa la discrepancia de Sprint 3: 8 casos en el plan frente a 6 en el reporte.

## Ceremonias y seguimiento

- [ ] Daily Scrum conserva semana, rango de fechas, un bloque por integrante y las tres preguntas.
- [ ] Las columnas de días reflejan el rango real y no se rellenan con actividad inventada.
- [ ] Sprint Review conserva objetivo, participantes (`Nombre | Rol`), presentación (`FUNCIÓN PRESENTADA | RETROALIMENTACIÓN`) y tareas (`Tarea | Estado`).
- [ ] Sprint Retrospective conserva fecha, objetivo, participantes (`Nombres | Rol`), tema y discusión de tres columnas.
- [ ] Burndown y BurnUp se referencian por tipo en `6.1` y `6.2`; no se inventan puntos ni se embeben imágenes.
- [ ] Esfuerzo usa `CÓDIGO | TAREA | PREVISTO DE HORAS | REAL DE HORAS`.
- [ ] Esfuerzo conserva la fila `Total | Esfuerzo total del Sprint N | previsto | real`.
- [ ] Taskboard se referencia por tipo y no se reemplaza por el Sprint Backlog.

## Trazabilidad y evidencia

- [ ] PB, HU y CP mantienen los identificadores de la fuente o se marca el mapeo como GAP.
- [ ] Los estados `Hecho`, `Pendiente`, `Terminada`, `Satisfactorio` y `Aprobado` no se mezclan sin una equivalencia explícita.
- [ ] Las cifras de horas, fechas, participantes, resultados y porcentajes tienen fuente.
- [ ] Todo elemento no recuperable del extracto queda marcado como GAP y no se completa por inferencia.
- [ ] No se embeben imágenes: los diagramas se nombran solo por tipo y ubicación.
- [ ] La guía no mezcla el formato de Sprint 0 §8 (`PB | HISTORIA DE USUARIO | PRIORIDAD | RESULTADO ESPERADO`) con el Sprint Backlog de CAPITULO 2 (`ID | TAREA | ESTIMACIÓN | RESPONSABLE | ESTADO | PLATAFORMA`).

---

# Hallazgos para S1-01 y S1-02 actuales

## S1-01 — Sprint Planning

El documento actual ya tiene objetivo, alcance, estimación, capacidad, dependencias, DoD y riesgos, pero para reproducir la estructura del modelo todavía debe contemplar explícitamente:

- la tabla `INTEGRANTE | ROL SCRUM` de `1.2`;
- las fichas de `1.3 Historias de Usuario` con criterios de aceptación y `Desarrollador a cargo`;
- el párrafo independiente de `1.4 Contexto del sistema`;
- el bloque `1.5 Sprint Backlog` con fechas y la tabla exacta `ID | TAREA | ESTIMACIÓN | RESPONSABLE | ESTADO | PLATAFORMA`;
- la separación visible entre estimación HU en PHU y backlog en HRS.

La tabla actual `PB | HISTORIA DE USUARIO | PRIORIDAD | RESULTADO ESPERADO` corresponde al formato de Sprint 0 §8.3, no sustituye la tabla de tareas de CAPITULO 2. La estimación con valor esperado y la capacidad son contenido adicional del proyecto: pueden permanecer, pero no deben ocultar las estructuras del modelo.

## S1-02 — Proceso por HU

El documento actual cubre solo el inicio del **Diseño de Datos** y deja pendientes varios bloques que el modelo sí incluye:

- `2.1.1.1` Deployment y `2.1.1.2` Package;
- `2.1.3.1` Communication y `2.1.3.2` Sequence;
- `2.1.4.1` Component;
- `2.1.5.1` plan de pruebas, `2.1.5.2` casos de caja negra y `2.1.5.3` reporte;
- el diseño físico SQL y la correspondencia completa entre PB, HU y CP.

Además, el documento actual llama `Class` al diseño conceptual. El encabezado literal del modelo es `2.1.2.1 Diseño Conceptual`; si se usa `ERD conceptual`, debe presentarse como tipo de referencia del proyecto y no como una afirmación de que el PDF rotula el artefacto como `Class`.

## No desviarse del modelo

- No agregar Gantt en los módulos S1–S3 de CAPITULO 2.
- No convertir cada rótulo de diagrama en una imagen embebida.
- No inventar datos de Burndown, BurnUp, Taskboard, adjuntos o capturas.
- No ocultar las inconsistencias del reporte de pruebas de Sprint 3: deben permanecer como GAP hasta su decisión.
