/// Screens of the client app that have contextual guidance.
enum GuideScreen {
  welcome,
  catalog,
  filters,
  listingDetail,
  viewer,
  quote,
  reviews,
  reservations,
  account,
  chats,
  chat,
  notifications,
}

/// One main action of a screen, explained as numbered steps.
class GuideWalkthrough {
  const GuideWalkthrough({required this.name, required this.steps});

  final String name;
  final List<String> steps;
}

/// One domain term and its plain-language definition.
class GuideTerm {
  const GuideTerm(this.term, this.definition);

  final String term;
  final String definition;
}

/// Deterministic, rule-based guidance for one screen. It only describes what
/// the person can do; it never performs any action.
class GuideContent {
  const GuideContent({
    required this.title,
    required this.goal,
    required this.walkthroughs,
    required this.mistakes,
  });

  /// Short title of the guide.
  final String title;

  /// What the screen is for, in plain words ("Para qué sirve").
  final String goal;

  /// One numbered walkthrough per main action of the screen.
  final List<GuideWalkthrough> walkthroughs;

  /// Common mistakes and what to do about them.
  final List<String> mistakes;

  /// Steps of the first (primary) walkthrough.
  List<String> get steps => walkthroughs.first.steps;

  /// Every domain term used by the app, explained for newcomers.
  static const List<GuideTerm> glossary = [
    GuideTerm(
      'Inmueble',
      'Una casa, un departamento u otro espacio que una inmobiliaria publica para vender o alquilar.',
    ),
    GuideTerm(
      'Inmobiliaria',
      'La empresa que publica el inmueble y atiende tus consultas. También se la llama agencia.',
    ),
    GuideTerm(
      'Catálogo',
      'La lista de todos los inmuebles publicados, donde podés buscar y comparar.',
    ),
    GuideTerm('Operación', 'Si el inmueble está en venta o en alquiler.'),
    GuideTerm(
      'Moneda de visualización',
      'La moneda en la que preferís ver los precios en pantalla (por ejemplo BOB, USD o USDT). Solo cambia cómo se muestran; no cambia lo que se cobra.',
    ),
    GuideTerm(
      'Opcionales',
      'Extras que se pueden sumar al inmueble, como una cochera o un mueble. Tienen su propio precio.',
    ),
    GuideTerm(
      'Cotización',
      'El cálculo del costo total de un inmueble con los opcionales que elijas, en la moneda que indiques. Es un presupuesto; todavía no es una compra.',
    ),
    GuideTerm(
      'Reserva',
      'La solicitud para apartar un inmueble. Tiene estados, como pendiente o confirmada, que ves en la pestaña Reservas.',
    ),
    GuideTerm(
      'Depósito en garantía',
      'Un monto que queda guardado de forma segura hasta que la reserva se resuelva. También se lo llama escrow. Si la reserva se cancela o vence, podés pedir que te lo devuelvan.',
    ),
    GuideTerm(
      'Token de prueba',
      'Dinero ficticio que se usa solo para practicar. En esta app los pagos son de prueba: no se cobra dinero real.',
    ),
    GuideTerm(
      'Wallet',
      'Una billetera digital que guarda tus tokens. Vincularla a tu cuenta permite usarla para el depósito de prueba.',
    ),
    GuideTerm(
      'Recorrido 3D',
      'Un paseo virtual por dentro del inmueble, que podés mover con el dedo como si estuvieras ahí.',
    ),
    GuideTerm(
      'Objeto de la escena',
      'Un mueble o elemento marcado dentro del recorrido 3D. Al tocarlo ves información sobre él.',
    ),
    GuideTerm(
      'Reseña',
      'Una calificación y un comentario de otra persona sobre un inmueble o sobre la atención de la inmobiliaria.',
    ),
    GuideTerm(
      'Reseña verificada',
      'Una reseña escrita por alguien que realmente tuvo una reserva con esa inmobiliaria.',
    ),
    GuideTerm(
      'Sesión',
      'El período en que tu cuenta está abierta en el teléfono. Al cerrar sesión, la app deja de reconocerte hasta que vuelvas a entrar.',
    ),
    GuideTerm(
      'Notificación',
      'Un aviso dentro de la app, por ejemplo cuando tu reserva cambia de estado o te escribe una inmobiliaria.',
    ),
  ];

  static GuideContent forScreen(GuideScreen screen) => switch (screen) {
    GuideScreen.welcome => const GuideContent(
      title: 'Primeros pasos en RoomForge',
      goal:
          'RoomForge te permite buscar inmuebles, recorrerlos en 3D, calcular su costo, reservarlos con dinero de prueba y hablar con la inmobiliaria. Esta guía te muestra el camino completo.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Recorrido completo, de la búsqueda a la reserva',
          steps: [
            'Abrí la pestaña Catálogo, que es la primera, y mirá los inmuebles publicados.',
            'Tocá «Filtrar catálogo» para indicar qué buscás: tipo, precio o zona.',
            'Tocá una tarjeta para abrir el detalle del inmueble y mirá sus fotos.',
            'Si hay recorrido 3D, tocá «Recorrer en 3D» para verlo por dentro.',
            'En el detalle del inmueble, tocá «Calcular cotización» para ver el costo total con los opcionales que quieras.',
            'Creá tu cuenta en la pestaña Cuenta, o entrá si ya tenés una.',
            'Volvé al detalle y solicitá la reserva. Seguila después en la pestaña Reservas.',
          ],
        ),
        GuideWalkthrough(
          name: 'Cómo moverte por la app',
          steps: [
            'Usá las pestañas de abajo para cambiar entre Catálogo, Reservas y Cuenta.',
            'Tocá el ícono de interrogación de cada pantalla para ver su ayuda.',
            'Tocá la campana de arriba para ver tus notificaciones cuando hayas entrado.',
          ],
        ),
      ],
      mistakes: [
        'Si no podés reservar o ver tus reservas, probablemente no entraste a tu cuenta: abrí la pestaña Cuenta e iniciá sesión.',
        'Si el catálogo aparece vacío, puede que tengas filtros activos: usá «Quitar filtros».',
        'Los pagos son de prueba: no necesitás dinero real ni vas a perderlo.',
      ],
    ),
    GuideScreen.catalog => const GuideContent(
      title: 'Cómo buscar un inmueble',
      goal:
          'Es la pantalla principal: muestra los inmuebles publicados para que encuentres el que se ajuste a lo que necesitás.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Buscar un inmueble',
          steps: [
            'Elegí la moneda de visualización para ver los precios en la que prefieras.',
            'Tocá «Filtrar catálogo» para indicar tipo, precio o zona.',
            'Revisá las tarjetas de la lista: cada una resume el inmueble.',
            'Tocá una tarjeta para abrir su detalle.',
            'Si no ves resultados, usá «Quitar filtros» y probá de nuevo.',
          ],
        ),
        GuideWalkthrough(
          name: 'Cambiar la moneda de los precios',
          steps: [
            'Buscá el campo «Moneda de visualización» arriba de la lista.',
            'Tocalo y elegí BOB, USD o USDT.',
            'Los precios de todas las tarjetas se actualizan solos.',
          ],
        ),
        GuideWalkthrough(
          name: 'Ver la ayuda de primeros pasos',
          steps: [
            'Tocá el botón «Primeros pasos» de esta pantalla.',
            'Leé el recorrido completo de la app, de la búsqueda a la reserva.',
            'Cuando termines, tocá «Ver guía completa» y después «Entendido», o deslizá la ayuda hacia abajo para cerrarla.',
          ],
        ),
      ],
      mistakes: [
        'La lista aparece vacía: tenés filtros muy estrictos. Tocá «Quitar filtros» o ampliá el rango de precio.',
        'Los precios cambiaron de número: cambiaste la moneda de visualización. Los valores son equivalentes, no hubo un aumento.',
        'La ciudad y la zona se buscan por nombre completo: escribí «Santa Cruz» y no una parte del nombre.',
      ],
    ),
    GuideScreen.filters => const GuideContent(
      title: 'Cómo usar los filtros',
      goal:
          'Te deja acotar el catálogo para ver solo los inmuebles que te interesan.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Filtrar por tipo, operación y precio',
          steps: [
            'Elegí la operación: Venta, Alquiler o Cualquiera.',
            'Completá los campos que quieras, por ejemplo ciudad o rango de precio.',
            'Tocá «Aplicar filtros» para ver los resultados.',
          ],
        ),
        GuideWalkthrough(
          name: 'Buscar cerca de un punto',
          steps: [
            'En «Cerca de un punto», tocá «Usar mi ubicación» o «Elegir en el mapa».',
            'Si usás el mapa, tocá el lugar que te interesa.',
            'Ajustá el radio con la barra para elegir qué tan lejos buscar.',
            'Tocá «Aplicar filtros». Tu ubicación solo se usa para esta búsqueda.',
          ],
        ),
        GuideWalkthrough(
          name: 'Empezar de nuevo',
          steps: [
            'Tocá «Limpiar campos» para vaciar lo que escribiste.',
            'Si habías elegido una zona, tocá «Quitar zona».',
            'Tocá «Aplicar filtros» para volver a ver todo.',
          ],
        ),
      ],
      mistakes: [
        'No aparece ningún inmueble: combinaste demasiados filtros. Limpiá los campos y probá con menos.',
        'No te encuentra la ubicación: revisá que el permiso de ubicación esté activo, o elegí el punto en el mapa.',
        'Escribiste solo parte del nombre de una ciudad: se busca por nombre completo.',
      ],
    ),
    GuideScreen.listingDetail => const GuideContent(
      title: 'Cómo consultar un inmueble',
      goal:
          'Muestra todo sobre un inmueble: fotos, precio, opcionales, recorrido 3D, reseñas y formas de contactar a la inmobiliaria.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Conocer el inmueble',
          steps: [
            'Mirá las fotos y la descripción para conocer el espacio.',
            'Revisá el precio base y las condiciones de la operación.',
            'Si hay recorrido 3D, abrilo para ver el inmueble por dentro.',
            'Tocá «Calcular cotización» para conocer el costo total con los opcionales que hayas marcado.',
            'Cuando estés seguro, podés solicitar la reserva desde esta pantalla.',
          ],
        ),
        GuideWalkthrough(
          name: 'Sumar opcionales y reservar',
          steps: [
            'En «Opcionales», marcá los extras que quieras sumar.',
            'Elegí la moneda de la reserva en el desplegable (BOB, USD o USDT).',
            'Tocá el botón de reservar. Si no entraste a tu cuenta, la app te lo va a pedir.',
            'Confirmá los datos y elegí cómo pagar con dinero de prueba: tarjeta de prueba o wallet de prueba.',
            'Tocá «Ver mi reserva» para seguir su estado.',
          ],
        ),
        GuideWalkthrough(
          name: 'Hablar con la inmobiliaria',
          steps: [
            'Entrá a tu cuenta si todavía no lo hiciste.',
            'Tocá «Chatear con la inmobiliaria».',
            'Escribí tu consulta en la pantalla de la conversación y enviala.',
          ],
        ),
        GuideWalkthrough(
          name: 'Leer y dejar reseñas',
          steps: [
            'Bajá hasta «Calificaciones» para leer lo que opinan otras personas.',
            'Tocá «Ver todas las reseñas de la inmobiliaria» para ver más.',
            'Si ya tuviste una reserva, completá tu calificación y guardala.',
          ],
        ),
      ],
      mistakes: [
        'No ves el botón de reserva o te pide iniciar sesión: entrá primero en la pestaña Cuenta.',
        'El precio no coincide con otra pantalla: puede estar en otra moneda de visualización.',
        'La disponibilidad aparece como no confirmada: es solo informativa. La inmobiliaria la confirma después de tu reserva.',
        'No hay recorrido 3D: no todos los inmuebles lo tienen. Mirá las fotos o consultá por chat.',
      ],
    ),
    GuideScreen.viewer => const GuideContent(
      title: 'Cómo recorrer el inmueble en 3D',
      goal:
          'Te deja caminar virtualmente por dentro del inmueble para conocer sus ambientes antes de visitarlo.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Moverte por el recorrido',
          steps: [
            'Esperá a que termine de cargar el recorrido.',
            'Arrastrá con un dedo para mirar alrededor.',
            'Usá dos dedos para acercar o alejar la vista.',
          ],
        ),
        GuideWalkthrough(
          name: 'Ver información de un objeto',
          steps: [
            'Buscá un objeto marcado dentro del recorrido, como un mueble.',
            'Tocalo para abrir su ficha con la información.',
            'Si querés avanzar, tocá «Cotizar este inmueble» desde esa ficha.',
          ],
        ),
      ],
      mistakes: [
        'Aparece «Recorrido 3D no disponible»: ese inmueble todavía no tiene recorrido. Volvé y mirá las fotos.',
        'Dice «El visor 3D no respondió»: revisá tu conexión y tocá «Reintentar».',
        'La vista se ve oscura o lenta: cerrá otras aplicaciones y volvé a abrir el recorrido.',
      ],
    ),
    GuideScreen.quote => const GuideContent(
      title: 'Cómo armar una cotización',
      goal:
          'Calcula cuánto cuesta el inmueble con los opcionales que elijas, en la moneda que prefieras. Es un presupuesto: no compromete ninguna compra.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Calcular el costo total',
          steps: [
            'Revisá el precio base del inmueble, arriba.',
            'En «Opcionales», marcá los extras que quieras sumar.',
            'En «Moneda de la cotización», elegí BOB, USD o USDT.',
            'Tocá «Cotizar» y esperá el resultado.',
            'Leé el desglose: precio base, opcionales y total.',
          ],
        ),
        GuideWalkthrough(
          name: 'Entender el resultado',
          steps: [
            'Fijate en el número de cotización: identifica tu cálculo.',
            'Mirá la vigencia de precios: indica con qué versión de la oferta se calculó.',
            'Si cambiás opcionales o moneda, tocá «Cotizar» otra vez para actualizar.',
          ],
        ),
      ],
      mistakes: [
        'El total no cambió después de marcar un opcional: tenés que tocar «Cotizar» de nuevo.',
        'No hay opcionales para elegir: ese inmueble no publicó ninguno.',
        'Falló el cálculo: revisá tu conexión y volvé a tocar «Cotizar».',
      ],
    ),
    GuideScreen.reviews => const GuideContent(
      title: 'Cómo ver las reseñas de una inmobiliaria',
      goal:
          'Reúne las calificaciones y comentarios de otras personas para que sepas cómo atiende la inmobiliaria.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Leer las reseñas',
          steps: [
            'Mirá la calificación promedio de la inmobiliaria, de 1 a 5.',
            'Bajá por la lista para leer cada comentario.',
            'Fijate en la marca «Verificada»: indica que la persona realmente reservó.',
          ],
        ),
        GuideWalkthrough(
          name: 'Dejar tu calificación',
          steps: [
            'Entrá a tu cuenta si todavía no lo hiciste.',
            'En el detalle del inmueble que reservaste, tocá «Calificar»: se abre la ventana «Tu calificación».',
            'Elegí cuántas estrellas das al inmueble y a la atención de la inmobiliaria.',
            'Escribí un comentario si querés (es opcional) y tocá «Guardar».',
          ],
        ),
      ],
      mistakes: [
        'No podés calificar: solo pueden hacerlo quienes tuvieron una reserva con esa inmobiliaria.',
        'No aparecen reseñas: el inmueble o la inmobiliaria todavía no recibió calificaciones.',
        'El comentario es demasiado largo: acortalo antes de guardar.',
      ],
    ),
    GuideScreen.reservations => const GuideContent(
      title: 'Cómo seguir tus reservas',
      goal:
          'Muestra tus reservas y en qué estado está cada una, y te deja cancelarlas o pedir la devolución del depósito cuando corresponda.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Seguir una reserva',
          steps: [
            'Entrá a tu cuenta: sin sesión no se ven las reservas.',
            'Abrí la pestaña Reservas.',
            'Buscá la tarjeta de tu reserva y mirá su estado.',
            'Deslizá hacia abajo para actualizar la lista.',
          ],
        ),
        GuideWalkthrough(
          name: 'Confirmar el depósito de prueba',
          steps: [
            'Abrí la reserva que está esperando el depósito.',
            'Tocá el botón del depósito y revisá el monto en «Confirmar depósito de prueba».',
            'Tocá «Continuar» para confirmar, o «Volver» para dejarlo para después.',
          ],
        ),
        GuideWalkthrough(
          name: 'Cancelar una solicitud',
          steps: [
            'Abrí la reserva que querés cancelar.',
            'Tocá «Cancelar solicitud».',
            'Leé el aviso y tocá «Confirmar cancelación», o «Volver» si te arrepentís.',
          ],
        ),
        GuideWalkthrough(
          name: 'Pedir un reembolso por vencimiento',
          steps: [
            'Abrí la reserva que venció sin resolverse.',
            'Tocá «Solicitar reembolso por vencimiento».',
            'Confirmá con «Solicitar reembolso» para recuperar tu depósito de prueba.',
          ],
        ),
      ],
      mistakes: [
        'Dice «Iniciá sesión para consultar tus reservas»: entrá primero en la pestaña Cuenta.',
        'No aparece la reserva que hiciste: deslizá hacia abajo para actualizar.',
        'Cancelaste por error: la cancelación no se puede deshacer; hacé una reserva nueva desde el detalle del inmueble.',
        'Los botones de cancelar o reembolso no aparecen: solo están disponibles en ciertos estados de la reserva.',
      ],
    ),
    GuideScreen.account => const GuideContent(
      title: 'Cómo usar tu cuenta',
      goal:
          'Acá creás tu cuenta, entrás a ella, cerrás sesión y vinculás tu wallet de prueba para pagar los depósitos.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Crear tu cuenta',
          steps: [
            'Tocá el texto «No tengo cuenta: registrarme», que está debajo del botón, para pasar a «Crear cuenta».',
            'Escribí tu correo electrónico en el primer campo.',
            'Escribí una contraseña de al menos 8 caracteres en el segundo campo.',
            'Tocá «Crear cuenta». Si todo está bien, quedás dentro automáticamente.',
          ],
        ),
        GuideWalkthrough(
          name: 'Entrar a tu cuenta',
          steps: [
            'Escribí el correo con el que te registraste.',
            'Escribí tu contraseña (tiene que tener al menos 8 caracteres).',
            'Tocá «Entrar». Si todavía no tenés cuenta, tocá antes «No tengo cuenta: registrarme»; para volver, «Ya tengo cuenta: iniciar sesión».',
          ],
        ),
        GuideWalkthrough(
          name: 'Vincular tu wallet de prueba',
          steps: [
            'Entrá a tu cuenta y buscá la sección de wallet.',
            'Tocá el botón de conectar y elegí tu wallet en la ventana que se abre.',
            'Aprobá la firma en tu wallet: sirve para comprobar que la wallet es tuya y no cuesta dinero.',
            'Esperá el aviso «Wallet verificada y vinculada a tu cuenta».',
          ],
        ),
        GuideWalkthrough(
          name: 'Cerrar sesión',
          steps: [
            'Entrá a la pestaña Cuenta.',
            'Tocá «Cerrar sesión».',
            'La app deja de reconocerte hasta que vuelvas a entrar.',
          ],
        ),
      ],
      mistakes: [
        'Te pide un correo: es obligatorio. Ingresá tu correo electrónico completo.',
        'Dice «La contraseña necesita al menos 8 caracteres»: escribí una contraseña más larga, de 8 caracteres o más.',
        'No podés entrar: revisá que el correo y la contraseña estén bien escritos, sin espacios de más.',
        'Dice que no pudo restaurar la sesión: tocá «Reintentar».',
        'Aparece «Conectá una wallet EVM para continuar»: primero conectá tu wallet y después vinculala.',
      ],
    ),
    GuideScreen.chats => const GuideContent(
      title: 'Cómo ver tus conversaciones',
      goal:
          'Lista tus conversaciones con las inmobiliarias para que retomes cualquiera de ellas.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Abrir una conversación',
          steps: [
            'Buscá en la lista el nombre de la inmobiliaria.',
            'Mirá el último mensaje para recordar de qué hablaban.',
            'Tocá la conversación para abrirla.',
          ],
        ),
        GuideWalkthrough(
          name: 'Actualizar la lista',
          steps: [
            'Tocá el ícono de actualizar, arriba a la derecha.',
            'Esperá unos segundos a que se carguen los mensajes nuevos.',
            'Revisá si aparece una conversación nueva.',
          ],
        ),
      ],
      mistakes: [
        'La lista está vacía: todavía no escribiste a ninguna inmobiliaria. Hacelo desde el detalle de un inmueble.',
        'Aparece un error de conexión: revisá tu internet y actualizá la lista.',
      ],
    ),
    GuideScreen.chat => const GuideContent(
      title: 'Cómo conversar con la inmobiliaria',
      goal:
          'Te permite escribirle a la inmobiliaria para hacer preguntas sobre un inmueble o una reserva.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Enviar un mensaje',
          steps: [
            'Tocá el campo «Escribí un mensaje», abajo.',
            'Escribí tu consulta con el mayor detalle posible.',
            'Tocá el botón de enviar y esperá a que aparezca en la conversación.',
          ],
        ),
        GuideWalkthrough(
          name: 'Reportar una conversación',
          steps: [
            'Tocá la banderita de arriba a la derecha.',
            'Escribí el «Motivo» por el que querés reportar.',
            'Tocá «Enviar reporte», o «Volver» si cambiaste de idea.',
          ],
        ),
      ],
      mistakes: [
        'No llega la respuesta: la inmobiliaria puede tardar. Volvé más tarde o mirá tus notificaciones.',
        'El mensaje no se envía: revisá tu conexión y probá de nuevo.',
        'Reportaste por error: contanos en el motivo qué pasó; el reporte no borra la conversación.',
      ],
    ),
    GuideScreen.notifications => const GuideContent(
      title: 'Cómo leer tus notificaciones',
      goal:
          'Reúne los avisos de la app, como cambios en tus reservas o mensajes de las inmobiliarias.',
      walkthroughs: [
        GuideWalkthrough(
          name: 'Leer un aviso',
          steps: [
            'Mirá la lista: los avisos sin leer se distinguen de los leídos.',
            'Tocá un aviso para abrirlo.',
            'La app te lleva a la reserva o a la conversación relacionada.',
          ],
        ),
        GuideWalkthrough(
          name: 'Marcar todo como leído',
          steps: [
            'Tocá «Marcar todo como leído», arriba a la derecha.',
            'El número de la campana vuelve a cero.',
            'Los avisos siguen en la lista para que los consultes.',
          ],
        ),
      ],
      mistakes: [
        'El botón «Marcar todo como leído» está apagado: no tenés avisos sin leer.',
        'No ves la campana: solo aparece cuando entraste a tu cuenta.',
        'Un aviso no te lleva a ningún lado: puede referirse a algo que ya no está disponible.',
      ],
    ),
  };
}
