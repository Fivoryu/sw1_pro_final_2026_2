# Patrón canónico — Diagrama de Comunicación UML en Enterprise Architect (vía MCP)

> Validado en sesión real: MCP Sparx Systems Japan 2.8.11 x86 (MCP3.exe) + Enterprise Architect 15.0.1514. Este patrón produce la misma forma que el ejemplo oficial "Communication Diagrams with Business Objects".

## Método preferido: clonar una referencia existente

Si el modelo ya contiene un diagrama de comunicación correcto (como el ejemplo importado), cloná el paquete con `enterprise-architect_clone_package` (recibe `{"packageID": <id>}` y clona al mismo padre): hereda el armado interno exacto (enlaces, mensajes, flechas, iconos de estereotipo).

```json
{ "packageID": 5 }
// → {"Cloned package infomation":{"packageID":12,...}}
```

Luego renombrar (sin tocar `type`):

- Paquete clonado: `create_or_update_package` con `packageID` y `name`.
- Diagrama clonado: `create_or_update_diagram` con `diagramID` y `name`.
- Elementos clonados: `create_or_update_elements` con `elementID` y `name`.
- Mensajes: `create_or_update_connectors` con `connectorID`, `name` ("1: Message A") y `direction: "FromSourceToTarget"` — sin `type` (mantiene `Collaboration`).
- Mover a otro paquete si hace falta: `owningPackageID` en el update de diagrama y de cada elemento.
- Abrir con `open_diagrams` y refrescar el navegador (F5) si el árbol no muestra el nodo.

## Método alternativo: crear desde cero

**1. Paquete** — bajo el root (nunca modelar en el root):

```json
{ "packageInfo": { "packageID": 0, "name": "Autenticacion", "owningPackageID": 1 } }
// → packageID: 4
```

**2. Diagrama**:

```json
{ "diagramInfo": { "diagramID": 0, "name": "Comunicacion - Inicio de Sesion", "type": "Communication", "owningPackageID": 4 } }
// → diagramID: 16
```

**3. Elementos** (objetos con estereotipos; el MCP convierte `boundary`/`control` a types `Boundary`/`Control` con estereotipo `EAUML::boundary`/`EAUML::control`; `entity` queda `Object` con `entity` — igual que el ejemplo oficial):

```json
{ "elementInfo": [
  { "elementID": 0, "name": "LoginUI", "type": "Object", "stereotypes": "boundary", "owningPackageID": 4 },
  { "elementID": 0, "name": "LoginController", "type": "Object", "stereotypes": "control", "owningPackageID": 4 },
  { "elementID": 0, "name": "Usuario", "type": "Object", "stereotypes": "entity", "owningPackageID": 4 }
] }
```

**4. Enlaces** (`Association`, sin nombre) y **mensajes** (`Collaboration`, numerados, con dirección):

```json
{ "connectorInfo": [
  { "connectorID": 0, "name": "", "type": "Association", "sourceEnd": { "relatedElementID": 66 }, "targetEnd": { "relatedElementID": 67 } },
  { "connectorID": 0, "name": "1: Message A", "type": "Collaboration", "direction": "FromSourceToTarget", "sourceEnd": { "relatedElementID": 66 }, "targetEnd": { "relatedElementID": 67 } },
  { "connectorID": 0, "name": "", "type": "Association", "sourceEnd": { "relatedElementID": 67 }, "targetEnd": { "relatedElementID": 68 } },
  { "connectorID": 0, "name": "2: Message B", "type": "Collaboration", "direction": "FromSourceToTarget", "sourceEnd": { "relatedElementID": 67 }, "targetEnd": { "relatedElementID": 68 } }
] }
```

Los mensajes van numerados SIEMPRE ("1: Message A", "2: Message B").

**5. Layout** (posiciones del ejemplo oficial, tamaño 50x60):

```json
{ "diagramID": 16, "elementPlacements": [
  { "elementID": 66, "x": 120, "y": 120, "width": 50, "height": 60 },
  { "elementID": 67, "x": 299, "y": 125, "width": 50, "height": 60 },
  { "elementID": 68, "x": 489, "y": 120, "width": 50, "height": 60 }
] }
```

`place_elements_on_diagram` recarga el diagrama automáticamente; para otros cambios usar `reload_diagrams`.

**6. Verificación y apertura**: `get_diagrams_information` (confirmar elementos, posiciones y conectores) y `open_diagrams`.

## Errores conocidos y workarounds

| Intento | Resultado | Correcto |
| --- | --- | --- |
| Mensaje con type `Communication` o `Message` | Forma visual distinta o `Message` rechazado ("invalid or wrong value(s)") | `Collaboration` |
| `create_or_update_messages` en diagrama Communication | "The target diagram type is not supported" | Solo funciona en diagrams Sequence |
| Update de conector pasando `type` | El tipo se reescribe (ej. `Communication` → `Dependency`) | Update solo con `name`/`direction`; nunca `type` |
| Crear diagrama/elemento bajo Root Package | "cannot be created directly under the Root packages" | Crear paquete primero |
| `get_diagram_image` | "Image reading is disabled" | Exportar PNG desde EA (Ctrl+Shift+I / Save as Image) |
| Múltiples instancias de EA abiertas | El add-in se conecta a una instancia que no es la esperada | Cerrar las demás; dejar una sola con el proyecto |
| Update de elemento pasando `type` | El type no cambia | Update solo con `name`/`owningPackageID` |

## Notas de modelo

- Los mensajes de la GUI de EA ("Configure Messages..." → añadir de A a B o de B a A) usan la colección interna `Connector.Messages`, que el MCP no expone; la aproximación equivalente vía API es el conector `Collaboration` numerado con `FromSourceToTarget`.
- `diagramID: 0` crea; un ID existente actualiza. Igual para `elementID`, `connectorID` y `packageID`.
- La numeración jerárquica (1.1, 1.2) se consigue incluyéndola en el nombre del mensaje.
