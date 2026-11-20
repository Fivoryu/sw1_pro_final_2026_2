/// Deterministic, rule-based guide content for the agent app. Everything here
/// is static Spanish text: no network, no model. The guide only indicates what
/// to do; it never performs a screen action.

/// Screens that offer a contextual guide.
enum GuideScreen {
  welcome,
  access,
  listingsList,
  listingEditor,
  spatialCapture,
  roomEditor,
  floorplanTrace,
  chatInbox,
  chatConversation,
  notifications,
  reviews,
}

/// A numbered walkthrough for one main action of a screen.
class GuideWalkthrough {
  const GuideWalkthrough(this.title, this.steps);

  final String title;
  final List<String> steps;
}

/// A common mistake and what to do about it.
class GuideMistake {
  const GuideMistake(this.problem, this.solution);

  final String problem;
  final String solution;
}

/// A domain term and its plain-words definition.
class GuideTerm {
  const GuideTerm(this.term, this.definition);

  final String term;
  final String definition;
}

/// Title of the guide shown for [screen].
String guideTitle(GuideScreen screen) => switch (screen) {
  GuideScreen.welcome => 'Primeros pasos',
  GuideScreen.access => 'Cómo entrar a RoomForge Captura',
  GuideScreen.listingsList => 'Cómo preparar un borrador',
  GuideScreen.listingEditor => 'Cómo completar el borrador',
  GuideScreen.spatialCapture => 'Cómo medir los ambientes',
  GuideScreen.roomEditor => 'Cómo corregir un ambiente',
  GuideScreen.floorplanTrace => 'Cómo trazar un ambiente desde un plano',
  GuideScreen.chatInbox => 'Cómo atender las conversaciones',
  GuideScreen.chatConversation => 'Cómo responder a un cliente',
  GuideScreen.notifications => 'Cómo leer tus avisos',
  GuideScreen.reviews => 'Cómo responder las reseñas',
};

/// What the screen is for, in plain words.
String guidePurpose(GuideScreen screen) => switch (screen) {
  GuideScreen.welcome =>
    'RoomForge Captura es la aplicación donde preparás los inmuebles de tu '
        'agencia: cargás sus datos, sacás fotos, medís cada ambiente y lo '
        'enviás a revisión para que los clientes puedan recorrerlo en 3D. '
        'Esta guía te explica el camino completo, de principio a fin.',
  GuideScreen.access =>
    'Acá demostrás quién sos. Se entra en dos pasos: primero con tu correo '
        'y tu contraseña, y después con un código de 6 dígitos que cambia '
        'cada pocos segundos. Cuando entrás, elegís adónde ir: tus '
        'inmuebles, las conversaciones o las reseñas.',
  GuideScreen.listingsList =>
    'Es tu lista de inmuebles. Ves los que ya cargaste y en qué estado '
        'está cada uno (borrador, en revisión o publicado). Desde acá '
        'empezás un inmueble nuevo o seguís trabajando en uno existente.',
  GuideScreen.listingEditor =>
    'Es la ficha del inmueble. Acá cargás la moneda, el precio, la '
        'ubicación, la descripción y las fotos, medís los ambientes y, '
        'cuando todo está listo, lo enviás a revisión.',
  GuideScreen.spatialCapture =>
    'Es el lugar donde medís el inmueble ambiente por ambiente. Podés '
        'recorrer con la cámara, dibujar el contorno a mano o trazarlo '
        'sobre un plano. Después enviás la escena 3D y seguís el estado '
        'de los recorridos que se están procesando.',
  GuideScreen.roomEditor =>
    'Es la ficha de un ambiente ya medido. Sirve para corregir la '
        'altura, ajustar el largo de una pared con una medida real, y '
        'agregar puertas y ventanas para que el ambiente quede fiel.',
  GuideScreen.floorplanTrace =>
    'Acá armás un ambiente a partir de una foto de un plano o croquis. '
        'RoomForge propone un contorno y vos lo revisás: solo se envía lo '
        'que confirmes. Sirve cuando no podés recorrer el lugar con la '
        'cámara.',
  GuideScreen.chatInbox =>
    'Es la lista de conversaciones con clientes interesados en tus '
        'inmuebles. Cada fila indica el inmueble y si la conversación '
        'está atrasada, solo de lectura o requiere a un administrador.',
  GuideScreen.chatConversation =>
    'Es el chat con un cliente. Leés lo que preguntó y respondés. Si el '
        'cliente se comporta mal, podés reportarlo a la agencia; y si '
        'sos administrador, podés reasignar la conversación.',
  GuideScreen.notifications =>
    'Muestra los avisos que RoomForge te manda: conversaciones nuevas '
        'asignadas, reservas y otros eventos. Los avisos sin leer se '
        'marcan para que no se te pase ninguno.',
  GuideScreen.reviews =>
    'Muestra lo que los clientes opinaron de los inmuebles y de la '
        'atención. Podés responder una vez a cada reseña y reportar las '
        'que sean falsas u ofensivas.',
};

/// Step-by-step walkthroughs, one per main action of the screen. The first
/// one is the primary action of the screen.
List<GuideWalkthrough> guideWalkthroughs(GuideScreen screen) =>
    switch (screen) {
      GuideScreen.welcome => const [
        GuideWalkthrough('Tu recorrido completo', [
          'Entrá con tu correo, tu contraseña y el código de 6 dígitos.',
          'Tocá «Continuar a mis inmuebles» para ver tu lista.',
          'Tocá «Nuevo inmueble» y completá moneda, precio y ubicación.',
          'Sumá las fotos del inmueble desde la cámara o la galería.',
          'Tocá «Medir ambientes» y medí cada habitación.',
          'Tocá «Guardar borrador» para conservar todo lo cargado.',
          'Cuando esté completo, tocá «Enviar a revisión».',
          'Esperá la respuesta de la agencia; mientras tanto, atendé las '
              'conversaciones y los avisos.',
        ]),
        GuideWalkthrough('Cómo pedir ayuda en cualquier pantalla', [
          'Buscá el ícono de interrogación en la barra de arriba.',
          'Tocalo: se abre una guía solo para esa pantalla.',
          'Leé la explicación y tocá «Entendido» para cerrarla.',
        ]),
      ],
      GuideScreen.access => const [
        GuideWalkthrough('Iniciar sesión', [
          'Escribí tu correo electrónico en el primer campo.',
          'Escribí tu contraseña; tocá el ojo si querés verla mientras '
              'escribís.',
          'Tocá «Continuar».',
          'Abrí tu aplicación de códigos y copiá el código de 6 dígitos.',
          'Escribilo en «Código de 6 dígitos» y tocá «Verificar código».',
        ]),
        GuideWalkthrough('Después de entrar', [
          'Verás tu correo y el mensaje «Sesión iniciada».',
          'Tocá «Continuar a mis inmuebles» para trabajar con tus '
              'inmuebles.',
          'Tocá «Conversaciones» o «Reseñas» si querés atender clientes.',
          'Al terminar, tocá «Cerrar sesión» para proteger tu cuenta.',
        ]),
      ],
      GuideScreen.listingsList => const [
        GuideWalkthrough('Crear un inmueble nuevo', [
          'Tocá «Nuevo inmueble».',
          'Completá los datos en la ficha y tocá «Guardar borrador».',
          'Volvé a esta lista: el inmueble aparece como borrador.',
          'Tocalo para seguir completándolo cuando quieras.',
        ]),
        GuideWalkthrough('Seguir trabajando en un inmueble', [
          'Buscá el inmueble en la lista.',
          'Tocalo para abrir su ficha.',
          'Cambiá lo que haga falta y tocá «Guardar borrador».',
        ]),
        GuideWalkthrough('Enviar un inmueble a revisión', [
          'Abrí el borrador desde la lista.',
          'Controlá que tenga precio, ubicación y fotos.',
          'Tocá «Enviar a revisión» y confirmá.',
          'Verás «Inmueble enviado a revisión» y cambia su estado.',
        ]),
      ],
      GuideScreen.listingEditor => const [
        GuideWalkthrough('Cargar moneda y precio', [
          'En «Moneda» elegí con qué moneda vas a cotizar.',
          'Escribí el precio en «Precio base»; el campo muestra la moneda '
              'elegida.',
          'Elegí si es venta o alquiler en «Operación».',
        ]),
        GuideWalkthrough('Marcar la ubicación', [
          'Escribí la ciudad y la zona o barrio.',
          'En el mapa, tocá el punto exacto donde está el inmueble.',
          'Si te equivocás, tocá «Quitar ubicación» y marcá de nuevo.',
          'La dirección exacta es opcional y queda privada.',
        ]),
        GuideWalkthrough('Agregar fotos', [
          'En la sección «Fotos», tocá «Agregar foto».',
          'Elegí «Cámara» para sacar una nueva o «Galería» para usar una '
              'guardada.',
          'Esperá que termine «Subiendo» antes de salir.',
          'Si falla una foto, tocá «Reintentar» o «Descartar».',
        ]),
        GuideWalkthrough('Medir los ambientes', [
          'Guardá el borrador primero.',
          'Tocá «Medir ambientes» en la sección de captura espacial.',
          'Seguí la guía de esa pantalla para medir cada habitación.',
        ]),
        GuideWalkthrough('Guardar y enviar a revisión', [
          'Tocá «Guardar borrador» para conservar tus cambios.',
          'Cuando todo esté completo, tocá «Enviar a revisión».',
          'Confirmá en el aviso: la agencia revisará el inmueble.',
        ]),
      ],
      GuideScreen.spatialCapture => const [
        GuideWalkthrough('Medir un ambiente nuevo', [
          'Tocá «Capturar ambiente».',
          'Elegí «Captura automática» (recorrer con la cámara), «Dibujar '
              'ambiente» (dibujarlo a mano) o «Plano o croquis».',
          'Escribí el nombre del ambiente, por ejemplo «Cocina».',
          'Seguí las indicaciones en pantalla y recorré despacio.',
          'Revisá el resultado en la tarjeta del ambiente.',
        ]),
        GuideWalkthrough('Dibujar un ambiente a mano', [
          'Tocá «Capturar ambiente» y elegí «Dibujar ambiente».',
          'Con «Dibujar / editar», tocá cada esquina de la habitación en '
              'orden.',
          'Tocá «Cerrar contorno» y escribí la altura.',
          'Tocá «Guardar ambiente».',
        ]),
        GuideWalkthrough('Conectar dos ambientes por una puerta', [
          'Necesitás al menos dos ambientes medidos.',
          'Tocá «Conectar ambientes por una puerta».',
          'Elegí los dos ambientes y la puerta que los une.',
          'Tocá «Conectar»; para deshacerlo usá «Quitar conexión».',
        ]),
        GuideWalkthrough('Enviar la escena 3D', [
          'Revisá que cada ambiente tenga sus paredes confirmadas.',
          'Mirá el estado arriba: «Pendiente de enviar».',
          'Tocá «Enviar escena» y esperá «Escena sincronizada».',
          'Si dice «No se pudo enviar», tocá «Reintentar envío».',
        ]),
        GuideWalkthrough('Seguir los recorridos subidos', [
          'En «Recorridos para reconstrucción» verás cada subida.',
          'Tocá «Actualizar estado» para ver si avanzó.',
          'Si quedó pendiente por falta de red, tocá «Reintentar subida».',
          'Cuando ya no haga falta, tocá «Quitar de la lista».',
        ]),
      ],
      GuideScreen.roomEditor => const [
        GuideWalkthrough('Corregir la altura', [
          'Buscá la sección «Altura».',
          'Medí la altura real del techo con un metro.',
          'Escribila en «Altura medida a mano (m)».',
          'Tocá «Guardar».',
        ]),
        GuideWalkthrough('Ajustar una pared con una medida real', [
          'Elegí la pared que podés medir con un metro.',
          'Escribí su largo en «Largo real de la pared (m)».',
          'Revisá cómo cambian las demás medidas del ambiente.',
        ]),
        GuideWalkthrough('Agregar una puerta o ventana', [
          'Tocá «Agregar puerta o ventana».',
          'Elegí «Puerta» o «Ventana».',
          'Elegí la «Pared» y la posición desde el inicio de la pared.',
          'Escribí el ancho y el alto en metros.',
          'Tocá «Guardar».',
        ]),
      ],
      GuideScreen.floorplanTrace => const [
        GuideWalkthrough('Trazar un ambiente desde un plano', [
          'Escribí el nombre del ambiente.',
          'Elegí la foto del plano desde la cámara o la galería.',
          'Esperá que RoomForge proponga un contorno.',
          'Revisá cada pared y confirmá su medida.',
          'Guardá el ambiente cuando todo esté confirmado.',
        ]),
        GuideWalkthrough('Corregir el contorno propuesto', [
          'Tocá «Herramientas de edición» (ícono de ajustes) arriba.',
          'Elegí «Dibujar / editar» y mové los vértices que estén mal.',
          'Usá «Deshacer» si te equivocás o «Reiniciar» para empezar de '
              'nuevo.',
        ]),
        GuideWalkthrough('Salir sin perder trabajo', [
          'Tocá la X de arriba a la izquierda.',
          'Si hay cambios sin guardar, la aplicación te pregunta qué hacer.',
          'Elegí si querés conservar o descartar lo trazado.',
        ]),
      ],
      GuideScreen.chatInbox => const [
        GuideWalkthrough('Abrir una conversación', [
          'Buscá la conversación en la lista.',
          'Fijate en las etiquetas: «Atrasada» pide atención primero.',
          'Tocala para leer los mensajes.',
        ]),
        GuideWalkthrough('Qué significan las etiquetas', [
          '«Atrasada»: el cliente espera respuesta hace tiempo.',
          '«Solo lectura»: podés leerla pero no responder.',
          '«Requiere administrador»: la decide alguien de la agencia.',
        ]),
        GuideWalkthrough('Si la lista no carga', [
          'Revisá tu conexión a internet.',
          'Tocá «Reintentar».',
          'Si sigue igual, volvé a entrar a la aplicación.',
        ]),
      ],
      GuideScreen.chatConversation => const [
        GuideWalkthrough('Responder a un cliente', [
          'Leé los mensajes del cliente de arriba hacia abajo.',
          'Escribí tu respuesta en «Escribí tu respuesta».',
          'Tocá «Enviar» (el avión de papel).',
        ]),
        GuideWalkthrough('Reportar a un cliente', [
          'Tocá la bandera de arriba («Reportar cliente»).',
          'Escribí el motivo con tus palabras.',
          'Confirmá; verás «Reporte enviado a la agencia».',
        ]),
        GuideWalkthrough('Reasignar la conversación (administradores)', [
          'Tocá «Reasignar» arriba (solo lo ven los administradores).',
          'Elegí a quién se la pasás, o «Automático».',
          'Confirmá; verás «Conversación reasignada».',
        ]),
      ],
      GuideScreen.notifications => const [
        GuideWalkthrough('Leer un aviso', [
          'Los avisos nuevos aparecen marcados como sin leer.',
          'Tocá un aviso para abrir lo que te comunica.',
          'El aviso queda como leído.',
        ]),
        GuideWalkthrough('Marcar todo como leído', [
          'Tocá «Marcar todo como leído» arriba a la derecha.',
          'El contador de avisos vuelve a cero.',
          'Si no hay avisos sin leer, el botón está apagado.',
        ]),
        GuideWalkthrough('Si no llegan avisos', [
          'Revisá tu conexión a internet.',
          'Cerrá esta pantalla y volvé a abrirla.',
          'Esperá unos segundos: los avisos se actualizan solos.',
        ]),
      ],
      GuideScreen.reviews => const [
        GuideWalkthrough('Responder una reseña', [
          'Buscá la reseña en la lista.',
          'Tocá «Responder».',
          'Escribí una respuesta amable y concreta.',
          'Confirmá: la respuesta se puede enviar una sola vez.',
        ]),
        GuideWalkthrough('Reportar una reseña', [
          'Tocá «Reportar» en la reseña que sea falsa u ofensiva.',
          'Escribí por qué la reportás.',
          'Confirmá; la reseña queda marcada como «Reportada».',
        ]),
        GuideWalkthrough('Entender el resumen', [
          'Arriba ves el promedio y la cantidad de reseñas.',
          '«Verificada» significa que el cliente realmente reservó.',
          'Con pocas reseñas el promedio todavía no es confiable.',
        ]),
      ],
    };

/// Common mistakes of the screen and what to do.
List<GuideMistake> guideMistakes(GuideScreen screen) => switch (screen) {
  GuideScreen.welcome => const [
    GuideMistake(
      'Enviás el inmueble sin fotos o sin ubicación.',
      'Antes de enviar a revisión, controlá que tenga precio, ubicación y '
          'fotos.',
    ),
    GuideMistake(
      'Te quedás sin conexión a mitad del trabajo.',
      'No pasa nada: lo medido queda guardado en el teléfono. Cuando '
          'vuelva la red, enviá de nuevo.',
    ),
    GuideMistake(
      'No sabés qué significa un término.',
      'Mirá el glosario de esta guía.',
    ),
  ],
  GuideScreen.access => const [
    GuideMistake(
      'El código de 6 dígitos no funciona.',
      'Cambia cada pocos segundos: esperá el siguiente código, escribilo '
          'completo y revisá que la hora del teléfono sea la correcta.',
    ),
    GuideMistake(
      'Dice que el correo o la contraseña no son correctos.',
      'Revisá mayúsculas y espacios. Tocá el ojo para ver lo que '
          'escribís.',
    ),
    GuideMistake(
      'No hay conexión.',
      'Conectate a una red con internet y tocá «Reintentar».',
    ),
  ],
  GuideScreen.listingsList => const [
    GuideMistake(
      'No encontrás un inmueble.',
      'Fijate en el estado de cada fila: puede estar en revisión o '
          'publicado.',
    ),
    GuideMistake(
      'La lista no carga.',
      'Revisá tu conexión y tocá «Reintentar».',
    ),
    GuideMistake(
      'Querés cambiar un inmueble que ya enviaste.',
      'Mientras está en revisión no se puede editar: esperá la respuesta '
          'de la agencia.',
    ),
  ],
  GuideScreen.listingEditor => const [
    GuideMistake(
      'Elegís la moneda equivocada.',
      'Cambiala en «Moneda» antes de guardar y revisá que el precio siga '
          'siendo el correcto.',
    ),
    GuideMistake(
      'Una foto queda en «Subiendo» para siempre.',
      'Probablemente se cortó la conexión. Tocá «Reintentar» o '
          '«Descartar» y volvé a sacarla.',
    ),
    GuideMistake(
      'Fotos oscuras o movidas.',
      'Sacalas con buena luz, con el teléfono quieto y sin dedos sobre '
          'la lente.',
    ),
    GuideMistake(
      'Salís sin guardar.',
      'Tocá «Guardar borrador» antes de volver para no perder lo '
          'escrito.',
    ),
  ],
  GuideScreen.spatialCapture => const [
    GuideMistake(
      'Poca luz en la habitación.',
      'Prendé todas las luces y abrí las cortinas antes de empezar a '
          'recorrer.',
    ),
    GuideMistake(
      'Te movés demasiado rápido.',
      'Caminá despacio y apuntá la cámara a las paredes y al piso. Si '
          'pierde el rastro, volvé al último lugar que reconoció.',
    ),
    GuideMistake(
      'Sin conexión al enviar.',
      'La escena queda como «Pendiente de enviar» en el teléfono. '
          'Cuando tengas red, tocá «Enviar escena» o «Reintentar envío».',
    ),
    GuideMistake(
      'Una subida quedó pendiente.',
      'No la borres. Tocá «Reintentar subida» con buena conexión; '
          'recién cuando termine usá «Quitar de la lista».',
    ),
    GuideMistake(
      'Dice «Conflicto con el servidor».',
      'Alguien envió otra escena. Si la tuya es la correcta, elegí '
          '«Reemplazar la escena del servidor»; si no, no envíes.',
    ),
  ],
  GuideScreen.roomEditor => const [
    GuideMistake(
      'Pusiste la medida en centímetros.',
      'Todas las medidas van en metros: 2,5 son dos metros y medio.',
    ),
    GuideMistake(
      'La puerta queda fuera de la pared.',
      'Revisá que la posición más el ancho no superen el largo de la '
          'pared elegida.',
    ),
    GuideMistake(
      'Corregiste una pared y cambió todo.',
      'Es normal: el ambiente se reajusta con la medida real. Revisá '
          'las demás paredes.',
    ),
  ],
  GuideScreen.floorplanTrace => const [
    GuideMistake(
      'El plano está torcido, borroso o cortado.',
      'Sacá otra foto de frente, con buena luz y con todo el plano a la '
          'vista.',
    ),
    GuideMistake(
      'El contorno propuesto no coincide.',
      'No lo confirmes: corregí los vértices con las herramientas de '
          'edición.',
    ),
    GuideMistake(
      'Sin conexión al interpretar el plano.',
      'Dibujá el contorno a mano o esperá a tener red y probá de nuevo.',
    ),
  ],
  GuideScreen.chatInbox => const [
    GuideMistake(
      'No ves conversaciones.',
      'Todavía no te asignaron ninguna. Se actualizan solas y también '
          'te llega un aviso.',
    ),
    GuideMistake(
      'Una conversación no te deja responder.',
      'Está en «Solo lectura». La atiende otra persona de la agencia.',
    ),
  ],
  GuideScreen.chatConversation => const [
    GuideMistake(
      'El mensaje no se envió.',
      'Revisá tu conexión y volvé a enviarlo cuando tengas red.',
    ),
    GuideMistake(
      'Reportaste a un cliente por error.',
      'Avisale a la agencia: el reporte llega a ellos y lo resuelven '
          'ellos.',
    ),
  ],
  GuideScreen.notifications => const [
    GuideMistake(
      'Un aviso no abre la conversación.',
      'Puede haber sido reasignada. Buscala en «Conversaciones».',
    ),
    GuideMistake(
      'Marcaste todo como leído sin mirar.',
      'Los avisos siguen en la lista: podés volver a leerlos.',
    ),
  ],
  GuideScreen.reviews => const [
    GuideMistake(
      'Querés responder otra vez.',
      'Cada reseña admite una sola respuesta. Pensala bien antes de '
          'confirmar.',
    ),
    GuideMistake(
      'Una reseña no te gusta pero es real.',
      'Solo reportá las falsas u ofensivas; las críticas se contestan '
          'con respeto.',
    ),
  ],
};

const _glossary = <String, GuideTerm>{
  'inmueble': GuideTerm(
    'Inmueble',
    'La casa, departamento u oficina que publicás.',
  ),
  'borrador': GuideTerm(
    'Borrador',
    'Un inmueble que todavía estás completando. Nadie más lo ve.',
  ),
  'revision': GuideTerm(
    'Revisión',
    'Cuando enviás el inmueble, la agencia controla que esté bien antes '
        'de publicarlo.',
  ),
  'moneda': GuideTerm(
    'Moneda',
    'La divisa del precio: bolivianos (BOB), dólares (USD) o USDT.',
  ),
  'captura': GuideTerm(
    'Captura espacial',
    'Medir el inmueble con el teléfono para armar su recorrido en 3D.',
  ),
  'ambiente': GuideTerm(
    'Ambiente',
    'Una habitación o espacio del inmueble, como la cocina o el living.',
  ),
  'escena': GuideTerm(
    'Escena 3D',
    'El conjunto de todos los ambientes medidos, listo para recorrerse.',
  ),
  'pendiente': GuideTerm(
    'Subida pendiente',
    'Información guardada en el teléfono que todavía no se envió, por '
        'ejemplo por falta de red.',
  ),
  'recorrido': GuideTerm(
    'Recorrido',
    'El video o las fotos que grabás caminando por el ambiente.',
  ),
  'abertura': GuideTerm('Abertura', 'Una puerta o una ventana de un ambiente.'),
  'plano': GuideTerm(
    'Plano o croquis',
    'El dibujo del inmueble visto desde arriba, con las paredes.',
  ),
  'sesion': GuideTerm(
    'Código de 6 dígitos',
    'Número temporal de tu aplicación de códigos que confirma que sos vos.',
  ),
  'conversacion': GuideTerm(
    'Conversación',
    'El chat con un cliente interesado en un inmueble.',
  ),
  'resena': GuideTerm(
    'Reseña',
    'La opinión y las estrellas que deja un cliente.',
  ),
};

List<GuideTerm> _terms(List<String> keys) => [
  for (final key in keys) _glossary[key]!,
];

/// Glossary terms relevant to [screen]. The welcome guide lists them all.
List<GuideTerm> guideGlossary(GuideScreen screen) => switch (screen) {
  GuideScreen.welcome => _glossary.values.toList(),
  GuideScreen.access => _terms(['sesion', 'inmueble']),
  GuideScreen.listingsList => _terms(['inmueble', 'borrador', 'revision']),
  GuideScreen.listingEditor => _terms([
    'moneda',
    'borrador',
    'captura',
    'revision',
    'pendiente',
  ]),
  GuideScreen.spatialCapture => _terms([
    'captura',
    'ambiente',
    'escena',
    'recorrido',
    'pendiente',
    'abertura',
  ]),
  GuideScreen.roomEditor => _terms(['ambiente', 'abertura', 'escena']),
  GuideScreen.floorplanTrace => _terms(['plano', 'ambiente', 'escena']),
  GuideScreen.chatInbox => _terms(['conversacion', 'inmueble']),
  GuideScreen.chatConversation => _terms(['conversacion']),
  GuideScreen.notifications => _terms(['conversacion', 'revision']),
  GuideScreen.reviews => _terms(['resena', 'inmueble']),
};
