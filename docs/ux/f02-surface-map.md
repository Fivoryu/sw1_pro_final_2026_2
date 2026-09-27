# F02.3 — Mapa de pantallas y navegación

> **Estado:** el usuario aprobó el mapa para avanzar al detalle visual y los prototipos. Define estados de interfaz; no implementa APIs ni operaciones de negocio.

## Decisiones de alcance

- Producto y roles: [`redefinicion-roomforge.md`](../redefinicion-roomforge.md), §§2–4; alcance F02: [`plan-maestro-roomforge.md`](../plan-maestro-roomforge.md), F02.3.
- El usuario aprobó esta distribución: **el agente prepara y edita el borrador completo en la app Android de captura**; el panel web concentra administración de plataforma/agencia y revisión/publicación; el cliente explora y reserva desde su app móvil.
- El alcance es **F02 únicamente**: mapa, navegación y prototipos. No incluye la implementación funcional de las capacidades de F03–F10.
- Las únicas superficies son panel web administrativo, app Android de captura y app móvil de cliente. La experiencia de cliente no se duplica en el panel.
- El onboarding pagado y las suscripciones de agencias no forman parte del MVP.

## Mapa de recorridos

| Superficie / actor | Recorrido propuesto | Límites del prototipo |
|---|---|---|
| **Panel web — administrador de plataforma** | Acceso staff → agencias → crear agencia y asignar/invitar administrador → confirmación. | Sin checkout, precios de planes ni suscripciones. |
| **Panel web — administrador de agencia** | Inicio → equipo/agentes → cola de borradores → revisar detalle → aprobar o rechazar con contexto → resultado. | Los controles de aprobación requieren contexto y confirmación; no ejecutan cambios reales en F02. |
| **Panel web — agente** | Acceso staff → indicación para continuar el borrador en la app de captura. | No crear ni editar borradores desde web, según la distribución elegida por el usuario. |
| **App Android — agente** | Acceso → borradores → nuevo inmueble → datos básicos y operación → ambientes/fotos → corregir geometría y objetos → preparar oferta → revisar resumen → enviar a revisión. | Geometría y objetos se muestran como editables/corregibles, no como medición automática exacta. En F02, guardar/enviar son interacciones de prototipo. |
| **App cliente — cliente** | Acceso → catálogo y filtros → detalle del inmueble → recorrido/disponibilidad → solicitar acceso cuando corresponda → seleccionar oferta/opciones → revisar desglose → conexión con wallet externa → confirmar intención de reserva → estado pendiente. | Sin consulta real al backend, visor funcional, firma de wallet, depósito ni transacción blockchain. Si no hay recorrido, mostrarlo honestamente como no disponible. |

### Navegación por superficie

- **Panel web:** navegación lateral adaptable por rol; separar administración de plataforma de administración de agencia. Mantener la ubicación actual y ofrecer retorno predecible desde revisión.
- **Captura Android:** inicio con borradores y acción principal “Nuevo inmueble”; creación como flujo por pasos, con volver sin perder el contexto visible. Acciones de cámara y edición disponibles mediante controles explícitos, no solo gestos.
- **Cliente móvil:** navegación principal para explorar, reservas y cuenta; el detalle, la selección y la confirmación forman un recorrido lineal con retorno al anuncio y filtros preservados.

## Estados compartidos del prototipo

| Estado | Presentación y acción disponible |
|---|---|
| Carga | Indicador con contexto; deshabilitar temporalmente la acción enviada y evitar doble envío. |
| Vacío | Explicar por qué la lista está vacía y ofrecer una siguiente acción válida. |
| Error | Mensaje junto al contenido afectado, recuperación/reintento explícitos; no mostrar detalles internos. |
| Sin conexión | Aviso persistente y estado de borrador/acción no sincronizada. El prototipo no promete sincronización ni persistencia local hasta que ese contrato se implemente. |
| Permiso requerido/denegado | Explicar el permiso necesario (por ejemplo, cámara) y ofrecer volver a intentarlo o continuar sin esa capacidad cuando sea posible. |
| Sin autorización | Explicar el límite de acceso sin revelar datos privados; nunca confiar solo en ocultar controles. |
| Confirmación | Mostrar objeto, consecuencia y acción elegida antes de enviar a revisión, aprobar/rechazar o confirmar una reserva. |
| Éxito/pendiente | Confirmar la acción y el estado resultante; no presentar una operación simulada como persistida o firmada. |

## Contratos de estado por recorrido

- **Borradores del agente:** mostrar estado conceptual del borrador y de su envío. Los nombres de estado de API/DB y la persistencia offline no se fijan en F02.
- **Revisión de agencia:** distinguir carga, cola vacía, error, borrador en revisión, aprobación/rechazo por confirmar y resultado del prototipo. No exponer borradores al catálogo cliente.
- **Catálogo cliente:** filtrar únicamente por ciudad/zona, venta/alquiler, precio base, habitaciones y baños. Incluir carga, sin resultados, error y sin conexión; no agregar filtros sin aprobación.
- **Acceso temporal:** el usuario autorizó prototipar solicitud y aprobación con siete días de vigencia. En F02 se muestran estados informativos; la autorización efectiva pertenece a una fase posterior.
- **Oferta/selección:** representar precio base más ajustes seleccionados, con dos decimales, como regla aprobada por el usuario para fases posteriores. La moneda, impuestos, descuentos, cargos y vigencia de cotización siguen pendientes; no mostrar una moneda inventada.
- **Reserva:** representar conexión de wallet externa y un estado pendiente simulado. No mostrar una reserva como confirmada ni indicar que se movieron tokens.

## Accesibilidad y acciones seguras

- Web adaptable; navegación por teclado y foco visible; encabezados y etiquetas explícitos; contraste accesible y significado no transmitido solo por color.
- Controles móviles táctiles legibles, con objetivos de al menos 48 dp y separación suficiente; texto escalable y rutas de volver/cancelar.
- Errores próximos al campo afectado, estados de carga/error anunciables y opción de recuperación. Las acciones irreversibles siempre muestran contexto y confirmación.

## Límites que se mantienen pendientes

- La moneda, los impuestos, los descuentos, los cargos obligatorios y la vigencia de cotización no se fijan en este mapa.
- La persistencia/sincronización offline exacta no se promete en un prototipo.
- Las capacidades funcionales de fases posteriores y las integraciones reales quedan fuera de F02.