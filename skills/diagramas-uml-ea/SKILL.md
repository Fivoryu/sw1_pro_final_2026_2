---
name: diagramas-uml-ea
description: "Trigger: diagrama de comunicación, crear diagrama UML, diagrama en Enterprise Architect, EA, MCP enterprise-architect. Crea diagramas UML en Enterprise Architect vía MCP usando el patrón validado (comunicación con business objects)."
license: Apache-2.0
metadata:
  author: "gentleman-programming"
  version: "1.0"
---

# diagramas-uml-ea

## Activation Contract

Activá esta skill cuando el usuario pida crear o reproducir un diagrama UML (comunicación, clases, casos de uso, secuencia, actividad, estados, componentes) en Enterprise Architect a través del MCP `enterprise-architect`.

## Hard Rules

- Si existe un diagrama de referencia en el modelo, cloná su paquete con `enterprise-architect_clone_package` y renombrá: heredás el armado exacto (enlaces, flechas y estilos). Es el método preferido.
- Nunca crees diagramas ni elementos directamente bajo un Root Package: primero un paquete bajo el root.
- En diagramas de comunicación: enlaces con conector `Association` y mensajes con `Collaboration`; los mensajes SIEMPRE numerados ("1: Message A") y con `direction: FromSourceToTarget` para que se dibuje la flecha.
- No uses `Communication` ni `Message` como tipo de mensaje en comunicación; quedan mal o son rechazados. `create_or_update_messages` solo funciona en diagramas Sequence.
- Al actualizar conectores o elementos, no pases `type`: el MCP lo ignora o reescribe el tipo (ej. Communication → Dependency).
- Verificá siempre con `enterprise-architect_get_diagrams_information` antes de reportar éxito; no inventes elementos, conectores ni posiciones.

## Decision Gates

| Situación | Decisión |
| --- | --- |
| Hay diagrama de referencia en el modelo | `clone_package` del paquete que lo contiene + rename de elementos y diagrama |
| Diagrama de comunicación sin referencia | Paquete → diagrama `Communication` → objetos boundary/control/entity → enlaces `Association` → mensajes `Collaboration` numerados |
| Otro tipo de diagrama UML | Usar su tipo exacto: `Class`, `Use Case`, `Sequence`, `Activity`, `Statechart`, `Component`, `Deployment` |
| Necesitas actualizar algo existente | Solo `name`, `direction` u `owningPackageID`; nunca `type` |

## Execution Steps

1. Conectá el MCP (`mcp connect enterprise-architect`) y confirmá que EA está abierto con el proyecto correcto (idealmente una sola instancia).
2. Explorá paquetes y diagramas (`get_packages_information`) en busca de una referencia. Si existe, cloná el paquete y renombrá.
3. Si no hay referencia: creá un paquete bajo el root y un diagrama nuevo (`diagramID: 0`) con `owningPackageID` del paquete.
4. Creá los elementos con su tipo exacto y estereotipos (`boundary`/`control`/`entity` para comunicación).
5. Creá enlaces `Association` y mensajes `Collaboration` (numerados, con dirección).
6. Colocá los elementos (`place_elements_on_diagram` con x/y/width/height); recargá diagramas tras crear conectores si no fue automático.
7. Verificá (`get_diagrams_information`) y abrí el diagrama (`open_diagrams`).

## Output Contract

Devolvé: nombre e ID del paquete y diagrama, elementos y conectores creados, resultado de la verificación, y cualquier limitación encontrada. No afirmes lo que no pudiste verificar.

## References

- [Patrón y errores conocidos del diagrama de comunicación](references/patron-diagrama-comunicacion.md)
