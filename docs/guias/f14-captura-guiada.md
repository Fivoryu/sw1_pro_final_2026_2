# F14.2 — Captura guiada con checklist

La app de captura guía al agente ambiente por ambiente antes de enviar un inmueble a revisión: le dice qué fotografiar y en qué orden, le pide confirmar una lista por ambiente y revisa la calidad de cada foto en el teléfono antes de subirla. No usa ARCore ni modelos de IA. El flujo de revisión del panel (F04.3) no cambia: la guía solo decide cuándo se habilita «Enviar a revisión» en la app de captura.

Código: `apps/captura_mobile/lib/domain/guided_capture/` (reglas), `lib/domain/guided_capture_controller.dart`, `lib/data/services/guided_capture_store.dart` y `lib/ui/guided_capture/`. Pruebas: `apps/captura_mobile/test/guided_capture_test.dart`.

## Ambientes y orden

Al abrir un borrador guardado, la guía arma los ambientes a partir de la ficha, en este orden sugerido:

1. Living.
2. Cocina.
3. Un dormitorio por cada dormitorio de la ficha («Dormitorio» si hay uno, «Dormitorio 1», «Dormitorio 2»… si hay más).
4. Un baño por cada baño de la ficha, con la misma regla de nombres.
5. Los ambientes que agregó el agente (por ejemplo, Balcón o Patio), al final.

Si la ficha cambia sus cantidades, los ambientes se recalculan: los que siguen existiendo conservan su lista y sus fotos, los que sobran se quitan y los agregados por el agente se conservan. Un ambiente derivado de la ficha no se borra: se marca «No aplica» con un motivo obligatorio (por ejemplo, un monoambiente sin cocina separada). Un ambiente agregado sí se puede quitar.

## Lista por ambiente

Cada ambiente que aplica pide confirmar tres puntos:

| Punto | Indicación al agente |
| --- | --- |
| Luces encendidas y cortinas abiertas | Encendé las luces y abrí cortinas antes de fotografiar. |
| Foto tomada desde la entrada, mostrando al menos dos paredes | Parate en la entrada del ambiente y encuadrá dos paredes o más. |
| Sin personas ni objetos personales a la vista | Retirá fotos familiares, documentos y personas del encuadre. |

La confirmación es del agente: la app no puede comprobar estos puntos por sí sola.

## Validación de calidad de cada foto

Cada foto que se toma desde la guía se analiza en el teléfono **antes** de subirla. Si no pasa, no se sube y el ambiente muestra el motivo. Son heurísticas locales sobre los píxeles, con umbrales elegidos a mano y **no calibrados** con un conjunto de fotos reales de inmuebles:

| Regla | Medida | Falla cuando | Motivo mostrado |
| --- | --- | --- | --- |
| Tamaño | Lado menor de la foto original | menos de 720 px | «La foto es muy chica (ancho×alto px)…» |
| Luz | Luma media (BT.601, 0–255) | menos de 50 | «La foto está muy oscura…» |
| Sobreexposición | Luma media | más de 220 | «La foto está sobreexpuesta…» |
| Nitidez | Varianza del laplaciano de 4 vecinos, sobre la foto reducida a 640 px en su lado mayor | menos de 25 | «La foto está movida o desenfocada…» |

La decodificación usa los códecs de la plataforma (`dart:ui`). Si el teléfono no puede decodificar la foto (por ejemplo, algunas HEIC/HEIF), la foto no se acepta y se le pide al agente usar la cámara o una foto JPG o PNG. Reducir la foto para medir la nitidez hace que un desenfoque leve no se detecte: la regla apunta a fotos claramente movidas.

## Cuándo se puede enviar a revisión

«Enviar a revisión» se habilita solo cuando, además de las condiciones de F04 (borrador guardado y al menos una foto), la guía está completa:

- cada ambiente que aplica tiene al menos una foto que pasó la validación **y que todavía existe** en el inmueble (si se borra la foto, el ambiente vuelve a quedar pendiente);
- cada ambiente que aplica tiene confirmados los tres puntos de la lista;
- al menos un ambiente aplica.

Mientras falte algo, el editor muestra el primer motivo y la pantalla de la guía los lista todos.

## Dónde se guarda

Qué foto pertenece a qué ambiente, la lista confirmada y los motivos de «No aplica» se guardan **solo en el teléfono**, en `guided_captures/<cuenta>/<inmueble>.json` dentro del directorio de soporte de la app, separados por cuenta del personal. La API y el panel no conocen los ambientes. Consecuencia: si el agente cambia de teléfono o borra los datos de la app, tiene que volver a recorrer la guía (las fotos ya subidas siguen en el inmueble, pero no cuentan para ningún ambiente hasta que se tome una foto nueva desde la guía).

Las pruebas y las compilaciones sin almacenamiento local no activan la guía: sin `GuidedCaptureStore`, el editor se comporta como antes de F14.2.

## Reutilización por F07

La guía es independiente del AR. F07 puede reutilizarla así:

- **Mismos ambientes.** `CaptureChecklist.derive` produce la lista y el orden de ambientes de un inmueble; la sesión espacial de F07 puede recorrer esa misma lista en lugar de pedir los ambientes de nuevo, usando el `id` estable de cada ambiente (`living`, `kitchen`, `bedroom-N`, `bathroom-N`, `extra-…`).
- **Mismos puntos.** `RoomCheck` es una lista declarativa: F07 puede agregar sus propios puntos (por ejemplo, «recorrido completo del perímetro») sin cambiar la lógica de progreso ni de validación.
- **Misma regla de envío.** `CaptureChecklist.problems` ya combina foto válida y lista confirmada; F07 puede sumar la condición de escena capturada como un problema más del ambiente.
- **Mismas heurísticas.** `assessPhoto` y `measureLuma` sirven para los cuadros clave del paquete de captura de F07, con las mismas advertencias de calibración.

## Límites

- Las heurísticas no están calibradas con fotos reales; pueden rechazar un ambiente oscuro a propósito o aceptar una foto mal encuadrada. Ajustar los umbrales requiere fotos reales de prueba.
- Los tres puntos de la lista son confirmaciones del agente, no comprobaciones automáticas.
- La asociación foto → ambiente no se sincroniza entre teléfonos.
- No se probó todavía en un dispositivo físico: queda pendiente recorrer la guía con la cámara real y confirmar que el análisis de una foto de 12 MP es fluido en un teléfono de gama media.
