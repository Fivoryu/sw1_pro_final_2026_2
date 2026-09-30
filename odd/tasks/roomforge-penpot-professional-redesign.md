# Rediseño visual profesional del mockup de RoomForge

## Objetivo
Elevar la calidad visual del mockup existente en Penpot para que se perciba como un producto inmobiliario diseñado a medida, no como una composición genérica generada automáticamente. Mantener el alcance funcional acordado y la identidad provisional, refinando su ejecución visual.

## Problema y motivación
El usuario considera que el resultado actual carece de profesionalidad y de iconografía. La revisión visual confirma patrones repetidos: titulares serif y cápsulas en casi todas las pantallas, tarjetas redondeadas para separar cada bloque, ilustraciones geométricas genéricas, controles sin iconos y datos de demo repetidos como copy de interfaz.

## Alcance autorizado
- Rediseñar las 4 páginas existentes del archivo Penpot: guía visual, cliente móvil, captura móvil y panel web.
- Conservar las 11 pantallas y sus recorridos de producto; cambiar composición, tipografía, iconografía, medios, jerarquía y componentes.
- Mantener crema/forest/clay como identidad provisional, reduciendo acentos decorativos y evitando modificar el alcance del MVP.
- Añadir una familia coherente de iconos vectoriales con etiquetas en navegación y acciones principales.
- Usar fotografía inmobiliaria de ejemplo solo como recurso visual, identificada como ilustrativa; conservar diagramas esquemáticos para geometría y recorrido.
- Mantener `Page 1` intacta. No editar archivos de código, submódulos, OpenSpec, binario EA, URL/token del MCP ni otros artefactos existentes.

## Restricciones de producto
- Captura y geometría de una planta, corregibles manualmente; no afirmar medición exacta ni automatización AR/IA.
- Las publicaciones requieren aprobación de la agencia antes de aparecer en el catálogo.
- Oferta: no inventar importes ni condiciones. Conservar la distinción entre venta y alquiler mensual si se muestra.
- Reserva: depósito de prueba con wallet externa, no pago total. Mantener estado pendiente y límite de 24 h sin cuenta regresiva ni supuesto sobre el inicio del plazo; el destino del depósito tras la aceptación permanece sin confirmar.
- Excluir suscripciones, acceso de siete días, monetización no acordada y estados no verificados.

## Dirección visual de rediseño
- Concepto: atlas editorial de arquitectura; composición y detalle como sello de marca, sin efectos decorativos ni una plantilla repetida.
- Tipografía: `Instrument Sans` para navegación, controles y datos; `Instrument Serif` solo para pocos encabezados editoriales y nombres de inmueble. Ambas están disponibles en Penpot. Escala 12/14/16/20/28/36 px, texto móvil legible.
- Paleta semántica contenida: papel `#F3F0E8`, superficie `#FCFBF8`, tinta `#24302A`, bosque `#183A32`, secundario `#617066`, línea `#D8D5CC`; arcilla `#B56E53` solo para un estado/acento funcional. Retirar colores decorativos redundantes.
- Ritmo: múltiplos de 4/8 px; radios 8/12/18 px, botones rectangulares moderados, cápsulas reservadas para filtros o estados breves; evitar una tarjeta por cada grupo.
- Iconografía propia vectorial de contorno, trazo uniforme de 1.7 px y terminal redondeado; tamaños 20 px en línea y 24 px en navegación/acción, con etiqueta visible.
- Foto inmobiliaria de ejemplo para catálogo/revisión, como recurso ilustrativo; visor y editor mantienen diagramas editables esquemáticos, sin sugerir precisión o automatización no confirmadas.

## Plan de trabajo
- [x] **RF-01 — Definir el sistema visual refinado.** Establecer jerarquía tipográfica, escala 4/8 px, radios, superficies, contraste y familia vectorial propia; actualizar la guía visual y los tokens. Ruta: inline con Penpot, tras la auditoría delegada. Evidencia: 10 tokens semánticos actualizados, 26 iconos SVG disponibles, dos fotos ilustrativas importadas y export del board `01 · RoomForge — sistema visual` revisado visualmente.
- [x] **RF-02 — Rediseñar el flujo del cliente.** Refinar catálogo, detalle, recorrido, oferta y reserva con jerarquías distintas, iconos coherentes y medios editoriales; conservar el alcance y sus límites. Ruta: inline en una página Penpot. Evidencia: exports individuales revisados para las cinco pantallas; fotos de muestra, navegación etiquetada, visor esquemático, precio sin importe inventado y reserva sin cuenta regresiva ni resultado del depósito supuesto.
- [x] **RF-03 — Rediseñar captura móvil.** Diferenciar visualmente la guía de captura y el editor técnico; mejorar los controles con iconos y mostrar de forma clara los límites de estimación/manualidad. Ruta: inline en una página Penpot. Evidencia: exports individuales revisados para las tres pantallas; contorno manual sobre foto ilustrativa, plano editable con herramientas vectoriales y envío con aprobación de agencia antes de publicación.
- [x] **RF-04 — Rediseñar el panel web.** Mejorar navegación, densidad de la cola y lectura de revisión/aprobación; retirar estadísticas/placeholders decorativos que no aporten a la tarea. Ruta: inline en una página Penpot. Evidencia: exports individuales revisados de alta de agencia, bandeja y revisión visual; cola sin cifras ficticias, decisión con fotografía ilustrativa y geometría esquemática.
- [x] **RF-05 — Verificar coherencia y cerrar.** Revisar exports de las 11 pantallas, guía de tokens, iconografía, estructura Penpot y límites de producto; conservar `Page 1` y comprobar que no se tocaron fuentes del repositorio. Ruta: read-only/QA inline, más auditoría de estado de repositorio delegada. Evidencia: 11 exports revisados, guía exportada, cinco páginas y boards confirmados; `Page 1` sigue vacía; diez colores semánticos y treinta iconos vectoriales disponibles.

## Criterios de aceptación
1. Las superficies se distinguen por objetivo y no repiten una misma plantilla de tarjetas y cápsulas.
2. Las navegaciones y acciones clave usan iconografía vectorial consistente, acompañada por texto donde corresponda.
3. El catálogo y la revisión usan fotografía de ejemplo con tratamiento uniforme; el recorrido y el editor siguen siendo esquemáticos y honestos sobre precisión.
4. La jerarquía tipográfica, el espaciado y los radios son consistentes; se reduce el uso de versales, badges y cajas decorativas.
5. Todas las afirmaciones y estados visuales permanecen dentro de los requisitos vigentes; ningún pendiente comercial se presenta como resuelto.
6. Se preserva `Page 1` y no se modifican archivos de código del repositorio.

## Verificación y decisiones de ejecución
- Ruta ODD; el usuario ya autorizó el mockup y ahora solicita una mejora de calidad visual. No se seleccionó SDD.
- Auditoría independiente `gentle-ai-explore` recibida: recomendó dirección de atlas editorial de arquitectura, fotografía real cuidada, diagramas editables, familias de iconos consistentes y reglas de alcance; confirmó que el depósito tras la aceptación, inicio exacto del plazo y varias condiciones comerciales siguen pendientes.
- No aplica TDD: no se modifica código ejecutable. Verificación visual mediante exports y lectura estructural del archivo Penpot.
- RDD permanece apagado; no se inicia revisión nativa para un archivo Penpot externo.
- Estado Git reportado en la sesión: rama `chore/roomforge-reset-01a0d0ec`, con cambios en submódulos `apps/cliente_mobile`, `backend`, `panel`, varios archivos de infraestructura/docs/OpenSpec y `odd/`. La auditoría final no puede atribuirlos sin un baseline; el trabajo de esta sesión modificó únicamente el lienzo Penpot y este task markdown. No se tocaron fuentes de código ni `docs/diagramas/Diagrama1.eapx`.
- No se ejecutaron tests porque no hubo cambios ejecutables. No se harán commits ni pushes; el usuario no los solicitó.

## Progreso y siguiente paso
- La auditoría visual detectó repetición de tarjetas/cápsulas, componentes text-only, ilustraciones genéricas y copy de demo repetido.
- **RF-01 completada:** actualizados 10 tokens semánticos; definida Instrument Sans/Serif y escala 4/8; creada una familia de 26 iconos vectoriales; importadas dos fotografías JPG y reconstruida/revisada la guía visual.
- **RF-02 completada:** rediseñadas y exportadas/revisadas las cinco pantallas cliente. Se incorporaron fotografía, distribución esquemática, controles vectoriales y jerarquías distintas; se mantuvieron importes sin definir, depósito de prueba y plazo de respuesta sin cuenta regresiva.
- **RF-03 completada:** rediseñadas y exportadas/revisadas las tres pantallas de captura. La guía usa foto ilustrativa con puntos manuales; el editor muestra geometría y herramientas editables; el envío deja explícita la aprobación previa a publicación.
- **RF-04 completada:** rediseñadas y exportadas/revisadas las tres pantallas web. Se diferenciaron los roles de plataforma y agencia; la cola omite conteos ficticios y la decisión conserva la aprobación previa a publicación.
- **RF-05 completada:** revisados los exports de las 11 pantallas y de la guía; confirmadas las cinco páginas, sus boards, los 10 colores semánticos y 30 rutas de iconos. `Page 1` sigue vacía. Se quitó un titular duplicado fuera del board de sistema visual. La auditoría del repositorio confirma un árbol ya sucio en varios módulos, pero no permite atribuir cambios sin baseline; no se editaron código ni EA.
- La copia de recuperación de Engram debe mantener el contenido completo de este archivo bajo `odd/roomforge-penpot-professional-redesign/tasks`.
