# Guía práctica — UML 2.5 para diagramas en Enterprise Architect

> Referencia de trabajo para crear diagramas UML 2.5 correctos mediante el MCP de Enterprise Architect. Fuentes: OMG UML 2.5.1 (<https://www.omg.org/spec/UML/2.5.1/PDF>) y uml-diagrams.org.

## 1. Taxonomía oficial (14 diagramas)

UML 2.5 define dos familias:

| Familia | Diagramas |
| --- | --- |
| **Estructura** (estática) | Clase, Objeto, Paquete, Estructura compuesta, Componente, Despliegue, Perfil |
| **Comportamiento** (dinámica) | Casos de uso, Actividad, Máquina de estados, Interacción (Secuencia, Comunicación, Timing, Interaction Overview) |

Nota: la especificación no prohíbe mezclar tipos de diagrama; las herramientas (EA) sí restringen elementos por tipo de diagrama.

## 2. Diagramas estructurales — propósito y elementos

| Diagrama | Propósito | Elementos principales | Relaciones |
| --- | --- | --- | --- |
| **Clase** | Estructura del sistema como clases e interfaces, sus atributos, operaciones y relaciones | Clase, Interfaz, Atributo, Operación, Restricción, Enum | Asociación, Agregación, Composición, Generalización, Dependencia, Realización |
| **Objeto** | Instancias (snapshot) | InstanceSpecification/Object, Slot, Link | Link (instancia de asociación) |
| **Paquete** | Organización de modelos | Paquete, PackageableElement | Dependencia, Import, Merge |
| **Estructura compuesta** | Estructura interna de un clasificador, colaboraciones | Part, Port, Connector, Collaboration | Conector interno, Dependencia |
| **Componente** | Desarrollo basado en componentes / SOA | Componente, Interfaz, Provided/Required Interface, Port, Artifact | Realización de componente, Uso, Dependencia, Asamblea |
| **Despliegue** | Distribución física de artefactos en nodos | Nodo, Dispositivo, Ambiente de ejecución, Artefacto, DeploymentSpec | Deployment (artifact→node), Manifestación, Ruta de comunicación |
| **Perfil** | Extensiones (estereotipos, tagged values) | Profile, Metaclass, Stereotype, Extension | Extensión, Aplicación de perfil, Referencia |

## 3. Diagramas de comportamiento — propósito y elementos

| Diagrama | Propósito | Elementos principales | Relaciones |
| --- | --- | --- | --- |
| **Casos de uso** | Acciones que el sistema realiza con actores externos, con valor observable | Actor, UseCase, Subject, Boundary | Asociación (actor→CU), Include, Extend, Generalización |
| **Actividad** | Secuencia y condiciones de flujos de control y de objeto | Activity, Action, Partition (swimlane), Initial/Final, Decision, Merge, Fork, Join, Object node (pin) | Control edge, Object edge |
| **Máquina de estados** | Comportamiento discreto por transiciones de estado | Estado, Estado inicial/final, Pseudostate (choice, junction, entry/exit), Transition, Trigger, Guard, Effect | Transición |
| **Secuencia** | Intercambio de mensajes entre lifelines ordenado en el tiempo | Lifeline, ExecutionSpecification, Message (sync, async, reply, create, delete), CombinedFragment (alt, opt, loop, break, par), InteractionUse, Gate, State/Time invariant | Mensajes entre lifelines |
| **Comunicación** | Interacción con foco en la estructura de enlaces y numeración de mensajes | Lifeline/Object, Link, Message (numeración) | Enlace |
| **Timing** | Cambios de estado de los objetos a lo largo del tiempo | Lifeline, State condition, Event, Time/Duration constraint | — |
| **Interaction Overview** | Vista de control de interacciones (variante de actividad) | Initial/Final, Decision, InteractionUse, Interaction | Control edge |

## 4. Reglas de diseño que EA/MCP debe respetar

1. **Jeraquía de paquete**: nunca crear diagramas ni elementos directamente bajo un Root Package; crear un paquete y modelar dentro de él.
2. **Tipos de diagrama**: usar el tipo exacto de EA (`Class`, `Use Case`, `Sequence`, `Activity`, `Statechart`, `Component`, `Deployment`, `Object`, `Composite`, `Package`, `Profile`, `Timing`, `Interaction Overview`, `Communication`).
3. **Tipos de elemento**: `Class`, `Interface`, `Actor`, `UseCase`, `Component`, `Artifact`, `Node`, `Package`, `Object` (lifeline en secuencia), `Action`, `State`, `Activity` según el diagrama.
4. **Conectores**: la asociación en casos de uso se modela con conector `UseCase` (no `Association`); `Include`/`Extend` se modelan como conector `UseCase` con estereotipo `<<include>>`/`<<extend>>`.
5. **Composición vs agregación**: composición = parte con ciclo de vida dependiente (rombo relleno); agregación = compartición débil (rombo vacío); asociación simple sin rombo.
6. **Dirección**: `FromSourceToTarget` para asociaciones dirigidas y mensajes; `BothDirection` solo cuando la navegación es bidireccional.
7. **Multiplicidad**: declarar `0..1`, `1..*`, `*` en los extremos de la asociación; el conector de EA soporta `multiplicity` en sourceEnd/targetEnd.
8. **Secuencia**: los mensajes requieren lifelines (elementos `Object` o clasificadores) colocados en el diagrama; usar `create_or_update_messages` con `order`, `isReturnMessage`, `isAsynchronousMessage`.
9. **Combinación de fragmentos**: para lógica, usar CombinedFragment (alt/opt/loop/par); no dibujar decisiones como flechas sueltas.
10. **Redes**: después de crear conectores/mensajes, recargar el diagrama (`reload_diagrams`) salvo tras `place_elements_on_diagram` que ya recarga.
11. **Naming**: clases con PascalCase, operaciones/atributos en camelCase, mensajes como verbos (`solicitarPedido()`), casos de uso como frases nominales («Realizar Pedido»).

## 5. Mapeo a herramientas MCP de EA (validate) ✔

Validado en la instalación local (MCP 2.8.11 x86, EA 15.0.1514):

- `create_or_update_diagram` requiere `owningPackageID` de un paquete (no root) y `type` (p. ej. `Class`, `Use Case`, `Sequence`).
- `create_or_update_elements` acepta `type: Class|Actor|UseCase|Object`, `stereotypes`, `description`, `taggedValues`.
- `create_or_update_connectors` (`type: Association`, `UseCase`, `Realization`, `Aggregation`, `Composition`, `Dependency`, `Generalization`, `Interface`).
- `place_elements_on_diagram` (x, y, width, height) — recarga el diagrama automáticamente.
- `create_or_update_messages` para mensajes de secuencia (source/targetElementID, order, sync/async/return).
- `get_diagram_image` está deshabilitado en la instalación actual («Image reading is disabled»); exportar PNG desde EA (Ctrl+Shift+I) o guardar como imagen.
