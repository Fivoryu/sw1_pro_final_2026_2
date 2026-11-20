export interface GuideStep {
  title: string;
  detail: string;
}

export interface GuideWalkthrough {
  title: string;
  steps: GuideStep[];
}

export interface GuideMistake {
  problem: string;
  fix: string;
}

export interface GlossaryEntry {
  term: string;
  meaning: string;
}

export interface GuideTopic {
  heading: string;
  /** Who can see this screen. */
  audience: string;
  /** What the screen is for, in plain words. */
  purpose: string;
  /** Short list of what the person can do here. */
  canDo: string[];
  walkthroughs: GuideWalkthrough[];
  mistakes: GuideMistake[];
  /** Keys of GLOSSARY used by this screen. */
  glossary: GlossaryKey[];
}

/** Every term the guide uses, explained once for someone who has never seen the software. */
export const GLOSSARY = {
  inmueble: {
    term: "Inmueble",
    meaning: "Una casa, departamento u otra propiedad que la inmobiliaria quiere vender o alquilar.",
  },
  publicacion: {
    term: "Publicación",
    meaning: "El anuncio de un inmueble en el catálogo público. Un inmueble aprobado solo se ve para los clientes cuando se publica.",
  },
  catalogo: {
    term: "Catálogo público",
    meaning: "La lista de inmuebles publicados que los clientes ven en la aplicación para clientes.",
  },
  agencia: {
    term: "Agencia (inmobiliaria)",
    meaning: "La empresa que publica inmuebles. Cada persona del personal trabaja para una sola inmobiliaria.",
  },
  administrador_plataforma: {
    term: "Administrador de plataforma",
    meaning: "Persona del equipo de RoomForge que da de alta inmobiliarias, invita a sus administradores y atiende reportes.",
  },
  administrador_agencia: {
    term: "Administrador de inmobiliaria",
    meaning: "Persona que dirige una inmobiliaria: revisa y publica inmuebles, asigna agentes y atiende pagos y reseñas.",
  },
  agente: {
    term: "Agente",
    meaning: "Persona de la inmobiliaria que captura los inmuebles con el teléfono y conversa con los clientes.",
  },
  estado_revision: {
    term: "Estado de revisión",
    meaning: "La etapa en la que está un inmueble: en revisión (espera una decisión), aprobado, rechazado o publicado.",
  },
  borrador: {
    term: "Borrador",
    meaning: "Una versión de trabajo que todavía no es definitiva. Nada cambia para los clientes hasta que se guarda o se aprueba.",
  },
  captura: {
    term: "Captura",
    meaning: "Las fotos y videos que el agente toma de un inmueble con la aplicación del teléfono para reconstruirlo en 3D.",
  },
  escena3d: {
    term: "Escena 3D",
    meaning: "La versión del inmueble en tres dimensiones por la que el cliente puede recorrer: paredes, puertas, ventanas y objetos.",
  },
  plano2d: {
    term: "Plano 2D",
    meaning: "El dibujo del inmueble visto desde arriba, donde se mueven paredes, puertas, ventanas y objetos.",
  },
  mobiliario: {
    term: "Mobiliario",
    meaning: "Los muebles del inmueble, como sofás, camas o mesas. Pueden detectarse solos en las fotos o añadirse a mano.",
  },
  sugerencia_ia: {
    term: "Sugerencia automática",
    meaning: "Un mueble que el programa detectó solo en las fotos. Siempre requiere que una persona lo confirme o lo descarte.",
  },
  cotizacion: {
    term: "Cotización",
    meaning: "El precio que se le muestra a un cliente por un inmueble, en la moneda que elija.",
  },
  reserva: {
    term: "Reserva",
    meaning: "El apartado de un inmueble por parte de un cliente, que deja un depósito como garantía.",
  },
  escrow: {
    term: "Escrow (depósito en custodia)",
    meaning: "El dinero del depósito queda guardado de forma segura y solo se entrega cuando la reserva se acepta; si se rechaza, vuelve al cliente.",
  },
  stripe: {
    term: "Stripe Connect",
    meaning: "El servicio externo que recibe los pagos con tarjeta. La inmobiliaria debe configurarlo una vez para poder cobrar. Aquí funciona en modo de prueba.",
  },
  tipo_cambio: {
    term: "Tipo de cambio",
    meaning: "Cuántas unidades de una moneda equivalen a un dólar (USD). Sirve para convertir los precios entre bolivianos, dólares y USDT.",
  },
  usdt: {
    term: "USDT",
    meaning: "Una moneda digital que vale aproximadamente un dólar.",
  },
  verificacion_dos_pasos: {
    term: "Verificación en dos pasos",
    meaning: "Una segunda comprobación al entrar: además de la contraseña, escribes un código de seis dígitos que muestra la aplicación autenticadora de tu teléfono. Cambia cada pocos segundos.",
  },
  autenticadora: {
    term: "Aplicación autenticadora",
    meaning: "Una aplicación del teléfono (por ejemplo Google Authenticator) que genera los códigos de seis dígitos.",
  },
  codigo_recuperacion: {
    term: "Código de recuperación",
    meaning: "Un código de un solo uso, con forma RF-XXXX-XXXX, para entrar si pierdes el teléfono. Cada código funciona una vez.",
  },
  invitacion: {
    term: "Invitación",
    meaning: "Un correo con un enlace personal para activar una cuenta. El enlace vence y solo sirve para esa persona.",
  },
  bandeja: {
    term: "Bandeja",
    meaning: "Una lista de elementos pendientes de atender, como conversaciones o reportes.",
  },
  conversacion: {
    term: "Conversación",
    meaning: "El intercambio de mensajes entre un cliente y la inmobiliaria sobre un inmueble.",
  },
  reporte: {
    term: "Reporte",
    meaning: "Un aviso para que el administrador de plataforma revise un mensaje, cliente o reseña que parece inadecuado.",
  },
  bloqueo: {
    term: "Bloqueo de cliente",
    meaning: "Impide que ese cliente siga escribiendo a la inmobiliaria. Se puede deshacer con Desbloquear.",
  },
  resena: {
    term: "Reseña",
    meaning: "La opinión y calificación que un cliente deja sobre la inmobiliaria.",
  },
  notificacion: {
    term: "Notificación",
    meaning: "Un aviso corto dentro del panel, por ejemplo un mensaje nuevo o un cambio en una reserva.",
  },
  modo_prueba: {
    term: "Modo de prueba",
    meaning: "Los pagos y depósitos no mueven dinero real; sirven para practicar y comprobar el funcionamiento.",
  },
} satisfies Record<string, GlossaryEntry>;

export type GlossaryKey = keyof typeof GLOSSARY;

const REVIEW_STATE = "No cambies de pantalla con cambios sin guardar: perderás lo que hayas escrito.";

/** Deterministic, rule-based guide content keyed by screen. No external calls. */
export const GUIDE_TOPICS = {
  login: {
    heading: "Cómo entrar al panel",
    audience: "Todo el personal: administradores de plataforma, administradores de inmobiliaria y agentes.",
    purpose:
      "Esta pantalla sirve para entrar a tu espacio de trabajo de forma segura. Primero escribes tu correo y contraseña y después confirmas que eres tú con un código.",
    canDo: [
      "Escribir tu correo electrónico y tu contraseña.",
      "Mostrar u ocultar la contraseña con el botón del ojo para revisar que la escribiste bien.",
      "Confirmar tu identidad con el código de seis dígitos de tu aplicación autenticadora.",
      "Usar un código de recuperación si no tienes tu teléfono.",
    ],
    walkthroughs: [
      {
        title: "Entrar por primera vez en el día",
        steps: [
          { title: "Escribe tu correo", detail: "En el campo Correo electrónico escribe el correo con el que recibiste tu invitación." },
          { title: "Escribe tu contraseña", detail: "En el campo Contraseña escribe la que creaste al activar tu cuenta. Pulsa Mostrar contraseña si dudas." },
          { title: "Pulsa Continuar", detail: "El programa comprueba tus datos y te pide el segundo paso." },
          { title: "Escribe el código", detail: "Abre tu aplicación autenticadora, copia el código de seis dígitos de RoomForge en el campo Código de autenticación y pulsa Verificar acceso." },
        ],
      },
      {
        title: "Entrar si perdiste el teléfono",
        steps: [
          { title: "Llega al segundo paso", detail: "Escribe correo y contraseña y pulsa Continuar." },
          { title: "Elige el código de recuperación", detail: "Pulsa Usar un código de recuperación, debajo del campo del código." },
          { title: "Escribe un código guardado", detail: "Escribe uno de los códigos con forma RF-XXXX-XXXX que guardaste al activar tu cuenta y pulsa Verificar acceso. Ese código ya no volverá a servir." },
        ],
      },
    ],
    mistakes: [
      { problem: "Aparece «No pudimos validar tus credenciales».", fix: "Revisa el correo y la contraseña. Usa Mostrar contraseña para ver lo que escribiste y comprueba que no esté activada la tecla de mayúsculas." },
      { problem: "El código de autenticación no funciona.", fix: "Comprueba que la hora de tu teléfono sea la automática y escribe el código actual; el de hace un minuto ya venció." },
      { problem: "Se perdió el teléfono y no hay códigos de recuperación.", fix: "Pide ayuda al administrador de tu inmobiliaria o de la plataforma para volver a configurar tu acceso." },
    ],
    glossary: ["verificacion_dos_pasos", "autenticadora", "codigo_recuperacion"],
  },

  "invitation-acceptance": {
    heading: "Cómo activar tu cuenta con una invitación",
    audience: "Personas nuevas que recibieron un correo de invitación.",
    purpose:
      "Esta pantalla sirve para activar tu cuenta por primera vez. Eliges una contraseña, enlazas tu aplicación autenticadora y guardas tus códigos de recuperación.",
    canDo: [
      "Crear tu contraseña y confirmarla.",
      "Enlazar tu aplicación autenticadora con la clave o el código QR de configuración.",
      "Guardar tus códigos de recuperación.",
    ],
    walkthroughs: [
      {
        title: "Activar tu cuenta",
        steps: [
          { title: "Abre el enlace del correo", detail: "Usa el enlace de la invitación; no lo copies a mano ni lo compartas, es personal." },
          { title: "Crea tu contraseña", detail: "Escribe la Nueva contraseña y repítela en Confirmar contraseña. Deben ser iguales." },
          { title: "Enlaza tu aplicación autenticadora", detail: "En tu teléfono añade una cuenta nueva con la Clave de configuración que se muestra en pantalla." },
          { title: "Escribe el primer código", detail: "Copia el código de seis dígitos de la aplicación en Código de autenticación y pulsa el botón de verificar." },
          { title: "Guarda los códigos de recuperación", detail: "Anota los códigos que aparecen en un lugar seguro: no se volverán a mostrar. Luego pulsa Continuar." },
        ],
      },
    ],
    mistakes: [
      { problem: "Aparece «Invitación no válida».", fix: "El enlace venció, ya se usó o está incompleto. Pide al administrador que te envíe una invitación nueva." },
      { problem: "Aparece «Las contraseñas no coinciden».", fix: "Vuelve a escribir la contraseña en los dos campos con cuidado." },
      { problem: "No se verifica el código.", fix: "Revisa que la hora de tu teléfono sea la automática e inténtalo con el código más reciente." },
      { problem: "Cerraste la página sin guardar los códigos de recuperación.", fix: "No se pueden ver otra vez. Pide ayuda al administrador para reconfigurar tu acceso." },
    ],
    glossary: ["invitacion", "verificacion_dos_pasos", "autenticadora", "codigo_recuperacion"],
  },

  landing: {
    heading: "Cómo usar la página de inicio",
    audience: "Cualquier persona que visita RoomForge, sin necesidad de cuenta.",
    purpose:
      "Esta página presenta RoomForge: una plataforma para publicar inmuebles con recorridos 3D. Aquí conoces cómo funciona, para quién es y cuánto cuesta.",
    canDo: [
      "Leer cómo funciona RoomForge, para quién es y sus ventajas.",
      "Comparar los planes de precios, mensuales o anuales.",
      "Entrar al panel con el botón Entrar al panel (solo personal con cuenta).",
    ],
    walkthroughs: [
      {
        title: "Conocer la plataforma",
        steps: [
          { title: "Usa el menú de arriba", detail: "Los enlaces Cómo funciona, Para quién, Precios y Ventajas te llevan directo a cada parte de la página." },
          { title: "Lee los pasos", detail: "En Cómo funciona se explica el recorrido: el agente captura, se crea el recorrido 3D y el cliente explora y reserva." },
          { title: "Compara los planes", detail: "En Precios elige Mensual o Anual para ver el costo de cada plan." },
        ],
      },
      {
        title: "Entrar a trabajar",
        steps: [
          { title: "Pulsa Entrar al panel", detail: "Está arriba a la derecha y también en la parte principal." },
          { title: "Escribe tus datos", detail: "Te llevará a la pantalla de acceso, donde escribes correo, contraseña y código." },
          { title: "Si no tienes cuenta", detail: "Tu cuenta se crea con una invitación por correo; pídela al administrador de tu inmobiliaria." },
        ],
      },
    ],
    mistakes: [
      { problem: "Intento entrar y no tengo cuenta.", fix: "Las cuentas del personal se crean solo por invitación. Pide una al administrador de tu inmobiliaria." },
      { problem: "Busco inmuebles para comprar o alquilar aquí.", fix: "Los clientes ven los inmuebles en la aplicación para clientes, no en esta página." },
    ],
    glossary: ["agencia", "escena3d", "catalogo"],
  },

  "welcome-platform-admin": {
    heading: "Primeros pasos: administración de plataforma",
    audience: "Administradores de plataforma.",
    purpose:
      "Esta es tu pantalla de inicio. Desde aquí cuidas lo que es común a todas las inmobiliarias: los tipos de cambio, las invitaciones a administradores y los reportes de uso indebido.",
    canDo: [
      "Registrar los tipos de cambio para convertir monedas.",
      "Invitar al administrador de una inmobiliaria.",
      "Revisar los reportes de conversaciones y de reseñas.",
      "Cerrar tu sesión con el botón Cerrar sesión, arriba a la derecha.",
    ],
    walkthroughs: [
      {
        title: "Tu primer día",
        steps: [
          { title: "Revisa los tipos de cambio", detail: "En Tasas de cambio comprueba que el dólar y el boliviano tengan una tasa vigente. Si falta, regístrala." },
          { title: "Invita a una inmobiliaria", detail: "En Invitar administrador de inmobiliaria elige la inmobiliaria, escribe el correo de su administrador y pulsa Enviar invitación." },
          { title: "Atiende los reportes", detail: "Baja hasta Reportes de conversaciones y Reportes de reseñas y decide qué hacer con cada uno." },
          { title: "Pide ayuda cuando la necesites", detail: "Cada bloque tiene su propio botón Guía con los pasos concretos." },
        ],
      },
      {
        title: "Cerrar sesión",
        steps: [
          { title: "Busca el botón", detail: "Cerrar sesión está en la franja superior, arriba a la derecha." },
          { title: "Púlsalo", detail: "El botón cambia a «Cerrando sesión…» unos segundos." },
          { title: "Comprueba", detail: "Vuelves a la pantalla de acceso. Para entrar de nuevo necesitas tu correo, contraseña y código." },
        ],
      },
    ],
    mistakes: [
      { problem: "No veo las inmobiliarias ni los inmuebles.", fix: "Eso es normal: el administrador de plataforma no gestiona inmuebles. Los ve cada administrador de inmobiliaria." },
      { problem: "La sesión se cerró sola.", fix: "Por seguridad la sesión vence. Vuelve a entrar con tu correo, contraseña y código." },
    ],
    glossary: ["administrador_plataforma", "agencia", "tipo_cambio", "invitacion", "reporte"],
  },

  "welcome-agency-admin": {
    heading: "Primeros pasos: administración de inmobiliaria",
    audience: "Administradores de inmobiliaria.",
    purpose:
      "Esta es tu pantalla de inicio. Resume el estado de tus inmuebles, cotizaciones y reservas, y desde aquí decides qué se aprueba y se publica.",
    canDo: [
      "Mirar los números de tu inmobiliaria en el resumen.",
      "Revisar, aprobar, rechazar y publicar inmuebles.",
      "Configurar los pagos con tarjeta y decidir sobre reservas.",
      "Usar el menú lateral (a la izquierda; en pantallas angostas aparece arriba) para ir al Editor de escenas, al Chat o a las Reseñas.",
      "Ver tus notificaciones con la campana de la franja superior.",
    ],
    walkthroughs: [
      {
        title: "Tu primer día",
        steps: [
          { title: "Mira el resumen", detail: "Los recuadros Publicaciones, Cotizaciones y Estado de Reservas te dicen cuántos elementos hay en cada estado." },
          { title: "Revisa lo pendiente", detail: "En la Cola de revisión abre los inmuebles que esperan tu decisión y apruébalos o recházalos." },
          { title: "Publica los aprobados", detail: "Un inmueble aprobado todavía no se ve para los clientes: abre su detalle y pulsa Publicar." },
          { title: "Configura los pagos", detail: "En Tarjetas y reservas completa la configuración de pagos una sola vez para poder recibir depósitos." },
          { title: "Atiende a los clientes", detail: "Usa el Chat para responder conversaciones y las Reseñas para contestar opiniones." },
        ],
      },
      {
        title: "Cerrar sesión",
        steps: [
          { title: "Busca el botón", detail: "Cerrar sesión está en la franja superior, arriba a la derecha." },
          { title: "Púlsalo", detail: "El botón cambia a «Cerrando sesión…» unos segundos." },
          { title: "Comprueba", detail: "Vuelves a la pantalla de acceso. Para entrar de nuevo necesitas tu correo, contraseña y código." },
        ],
      },
    ],
    mistakes: [
      { problem: "Aprobé un inmueble pero los clientes no lo ven.", fix: "Aprobar no publica. Abre el inmueble y pulsa Publicar." },
      { problem: "No puedo aceptar reservas.", fix: "Primero hay que completar la configuración de Stripe Connect en Tarjetas y reservas." },
    ],
    glossary: ["administrador_agencia", "inmueble", "publicacion", "estado_revision", "reserva", "stripe"],
  },

  "welcome-agent": {
    heading: "Primeros pasos: área de agente",
    audience: "Agentes de una inmobiliaria.",
    purpose:
      "Esta es tu pantalla de inicio. Los inmuebles se capturan y se envían a revisión con la aplicación RoomForge Captura en el teléfono; aquí en el panel corriges la escena en 3D y atiendes a los clientes.",
    canDo: [
      "Abrir el Editor de escenas para ajustar el plano y el mobiliario de un inmueble.",
      "Atender conversaciones de clientes en el Chat.",
      "Ver y reportar reseñas en Reseñas.",
      "Ver tus notificaciones con la campana de la franja superior.",
    ],
    walkthroughs: [
      {
        title: "Tu primer día",
        steps: [
          { title: "Captura el inmueble en el teléfono", detail: "Abre la aplicación RoomForge Captura, crea el borrador del inmueble, toma las fotos y envíalo a revisión." },
          { title: "Ajusta la escena aquí", detail: "En el menú lateral (a la izquierda; en pantallas angostas aparece arriba) abre el Editor de escenas, elige el inmueble y corrige lo que haga falta." },
          { title: "Responde a los clientes", detail: "Abre el Chat y contesta las conversaciones asignadas a ti." },
        ],
      },
      {
        title: "Cerrar sesión",
        steps: [
          { title: "Busca el botón", detail: "Cerrar sesión está en la franja superior, arriba a la derecha." },
          { title: "Púlsalo", detail: "El botón cambia a «Cerrando sesión…» unos segundos." },
          { title: "Comprueba", detail: "Vuelves a la pantalla de acceso. Para entrar de nuevo necesitas tu correo, contraseña y código." },
        ],
      },
    ],
    mistakes: [
      { problem: "No encuentro dónde crear un inmueble.", fix: "Los inmuebles se crean en la aplicación RoomForge Captura del teléfono, no en este panel." },
      { problem: "No veo todos los inmuebles de la inmobiliaria.", fix: "Solo ves aquellos que el administrador te asignó." },
    ],
    glossary: ["agente", "inmueble", "captura", "escena3d", "conversacion"],
  },

  "agency-dashboard": {
    heading: "Cómo leer el resumen de tu inmobiliaria",
    audience: "Administradores de inmobiliaria.",
    purpose:
      "Esta pantalla muestra, en tres recuadros, cuántos inmuebles, cotizaciones y reservas tiene tu inmobiliaria en cada estado, para saber qué requiere tu atención.",
    canDo: [
      "Ver el total de inmuebles y cuántos están en revisión, aprobados, rechazados, en borrador o publicados.",
      "Ver las cotizaciones pendientes, aceptadas y rechazadas.",
      "Ver cuántas reservas hay en cada estado.",
      "Pulsar Reintentar si no se pudieron cargar los números.",
    ],
    walkthroughs: [
      {
        title: "Saber qué atender primero",
        steps: [
          { title: "Mira Publicaciones", detail: "Si hay inmuebles En revisión, esperan tu decisión: ve a la Cola de revisión, justo debajo." },
          { title: "Mira Aprobados sin publicar", detail: "Son inmuebles listos que los clientes todavía no ven. Ábrelos y pulsa Publicar." },
          { title: "Mira Estado de Reservas", detail: "Si hay reservas pendientes, ve a Tarjetas y reservas para aceptarlas o rechazarlas." },
        ],
      },
      {
        title: "Recuperarte de un fallo de carga",
        steps: [
          { title: "Lee el aviso", detail: "Si aparece «No se pudieron cargar las métricas», no se perdió nada." },
          { title: "Pulsa Reintentar", detail: "El botón vuelve a pedir los números." },
          { title: "Si sigue igual", detail: "Espera un momento y comprueba tu conexión a internet." },
        ],
      },
    ],
    mistakes: [
      { problem: "Aparece «Solo el administrador de la agencia puede ver estas métricas».", fix: "Tu cuenta no es de administrador de inmobiliaria. Pide el acceso a quien administra tu inmobiliaria." },
      { problem: "Los números parecen viejos.", fix: "El resumen se carga al abrir la pantalla; recarga la página para verlo actualizado." },
    ],
    glossary: ["publicacion", "estado_revision", "cotizacion", "reserva", "borrador"],
  },

  "agency-invitations": {
    heading: "Cómo invitar al administrador de una inmobiliaria",
    audience: "Administradores de plataforma.",
    purpose:
      "Esta pantalla sirve para que una persona nueva pueda administrar una inmobiliaria. Se le envía un correo con un enlace para activar su cuenta.",
    canDo: [
      "Elegir la inmobiliaria que tendrá un nuevo administrador.",
      "Escribir el correo de esa persona.",
      "Enviar la invitación.",
    ],
    walkthroughs: [
      {
        title: "Enviar una invitación",
        steps: [
          { title: "Elige la inmobiliaria", detail: "En la lista Inmobiliaria selecciona a cuál pertenecerá la persona." },
          { title: "Escribe el correo", detail: "En Correo del administrador escribe una dirección completa y correcta, por ejemplo nombre@empresa.com." },
          { title: "Pulsa Enviar invitación", detail: "Aparecerá un aviso verde cuando se haya enviado. En este entorno de pruebas el correo no sale a internet: queda en un buzón local de desarrollo." },
          { title: "Avisa a la persona", detail: "Dile que revise su correo y use el enlace antes de que venza." },
        ],
      },
    ],
    mistakes: [
      { problem: "La lista de inmobiliarias está vacía («No hay inmobiliarias disponibles»).", fix: "Primero debe existir al menos una inmobiliaria registrada. Recarga la página o pide que den de alta una inmobiliaria." },
      { problem: "Me equivoqué de correo.", fix: "Envía otra invitación al correo correcto; el enlace del correo equivocado no debe compartirse." },
      { problem: "Dice que mi sesión expiró.", fix: "Cierra sesión, vuelve a entrar y repite el envío." },
    ],
    glossary: ["administrador_agencia", "agencia", "invitacion", "administrador_plataforma"],
  },

  "listing-review-queue": {
    heading: "Cómo revisar un inmueble",
    audience: "Administradores de inmobiliaria.",
    purpose:
      "La cola de revisión lista los inmuebles que los agentes enviaron. Aquí decides cuáles se aprueban, se rechazan o se publican en el catálogo para los clientes.",
    canDo: [
      "Elegir la pestaña de estado (En revisión o Aprobados) para ver cada grupo de inmuebles.",
      "Pulsar Revisar en la fila de un inmueble para abrir su detalle.",
      "Decidir el destino del inmueble desde su detalle: aprobar, rechazar, publicar o retirar.",
    ],
    walkthroughs: [
      {
        title: "Abrir un inmueble para revisarlo",
        steps: [
          { title: "Elige la pestaña de estado", detail: "Usa las pestañas de arriba, por ejemplo En revisión para lo que espera una decisión." },
          { title: "Busca la fila", detail: "Cada fila muestra ciudad, zona y precio del inmueble." },
          { title: "Pulsa Revisar", detail: "Se abre el detalle del inmueble. Para volver a la lista usa Volver a la bandeja." },
        ],
      },
      {
        title: "Ver el mensaje cuando no hay inmuebles",
        steps: [
          { title: "Lee el aviso de la pestaña", detail: "Por ejemplo «No hay inmuebles esperando revisión». Significa que todo está al día." },
          { title: "Cambia de pestaña", detail: "Revisa Aprobados por si hay inmuebles aprobados que falta publicar." },
          { title: "Espera nuevos envíos", detail: "Cuando un agente envíe un inmueble aparecerá en En revisión." },
        ],
      },
    ],
    mistakes: [
      { problem: "No encuentro un inmueble que acabo de aprobar.", fix: "Cambió de pestaña: búscalo en Aprobados." },
      { problem: "Un inmueble nuevo no aparece.", fix: "El agente debe enviarlo a revisión desde la aplicación RoomForge Captura; hasta entonces es un borrador." },
    ],
    glossary: ["inmueble", "estado_revision", "publicacion", "catalogo", "agente"],
  },

  "listing-detail": {
    heading: "Cómo decidir sobre un inmueble",
    audience: "Administradores de inmobiliaria.",
    purpose:
      "El detalle muestra los datos, fotos, ubicación y recorrido 3D de un inmueble, el historial de decisiones y los botones para decidir qué pasa con él.",
    canDo: [
      "Revisar precio, ubicación, fotos y la escena 3D.",
      "Aprobar o rechazar un inmueble que está en revisión.",
      "Publicar un inmueble aprobado o retirarlo del catálogo.",
      "Guardar la ubicación en el mapa y asignar agentes.",
    ],
    walkthroughs: [
      {
        title: "Aprobar un inmueble",
        steps: [
          { title: "Comprueba los datos", detail: "Revisa el precio, la zona, las fotos y el recorrido 3D. Mira el historial para ver qué se hizo antes." },
          { title: "Pulsa Aprobar", detail: "Se pide una confirmación antes de cambiar nada." },
          { title: "Confirma", detail: "Pulsa el botón de confirmación. El inmueble queda aprobado pero todavía no se ve para los clientes." },
        ],
      },
      {
        title: "Rechazar un inmueble",
        steps: [
          { title: "Pulsa Rechazar", detail: "Se abre una confirmación." },
          { title: "Escribe el motivo", detail: "Explica con claridad qué debe corregir el agente; él lo verá." },
          { title: "Confirma", detail: "El agente deberá editar el inmueble y enviarlo de nuevo." },
        ],
      },
      {
        title: "Publicar o retirar del catálogo",
        steps: [
          { title: "Abre un inmueble aprobado", detail: "Solo se puede publicar lo que ya fue aprobado." },
          { title: "Pulsa Publicar", detail: "Se pide confirmación; al aceptar, los clientes lo ven en el catálogo público." },
          { title: "Para retirarlo", detail: "Pulsa Retirar del catálogo y confirma; los clientes dejarán de verlo." },
        ],
      },
      {
        title: "Guardar la ubicación y asignar agentes",
        steps: [
          { title: "Marca el punto en el mapa", detail: "Mueve el marcador o ajusta la ubicación donde está el inmueble." },
          { title: "Pulsa Guardar ubicación", detail: "Los clientes verán el inmueble en el lugar correcto." },
          { title: "Asigna agentes", detail: "En Agentes asignados marca a los agentes que atenderán el inmueble y pulsa Guardar asignación." },
        ],
      },
    ],
    mistakes: [
      { problem: "Quise rechazar sin escribir motivo.", fix: "Siempre explica el motivo: sin él el agente no sabrá qué corregir." },
      { problem: "Aprobé por error.", fix: "Mientras no lo publiques, los clientes no lo ven. Revisa el historial y decide el siguiente paso." },
      { problem: "No aparece la escena 3D.", fix: "Todavía no se guardó una escena para ese inmueble; el agente debe prepararla en el Editor de escenas." },
      { problem: "Los botones están desactivados.", fix: "El estado actual no permite esa acción; por ejemplo no se puede publicar lo que no está aprobado." },
    ],
    glossary: ["estado_revision", "publicacion", "catalogo", "escena3d", "agente", "inmueble"],
  },

  "scene-editor": {
    heading: "Cómo editar la escena 3D de un inmueble",
    audience: "Administradores de inmobiliaria y agentes.",
    purpose:
      "El editor de escenas permite corregir el plano del inmueble (paredes, puertas, ventanas y objetos), ver el resultado en 3D y guardar los cambios.",
    canDo: [
      "Elegir el inmueble cuya escena quieres ver.",
      "Arrastrar paredes, aberturas y objetos en el plano 2D.",
      "Mirar la vista tridimensional.",
      "Guardar la escena con el botón Guardar escena.",
      "Cargar borradores de capturas y confirmar el mobiliario.",
    ],
    walkthroughs: [
      {
        title: "Corregir y guardar una escena",
        steps: [
          { title: "Elige el inmueble", detail: "En la lista Inmueble selecciona el que quieres editar. Se carga su escena." },
          { title: "Mueve lo que haga falta", detail: "Arrastra los extremos de las paredes, las aberturas sobre su pared o los objetos en el Plano 2D." },
          { title: "Comprueba en 3D", detail: "Mira la Vista tridimensional para verificar que el resultado se ve bien." },
          { title: "Pulsa Guardar escena", detail: "Aparece «Cambios guardados correctamente». Sin este paso, nada queda guardado." },
        ],
      },
    ],
    mistakes: [
      { problem: "Cambié cosas y se perdieron al cambiar de inmueble.", fix: "Pulsa Guardar escena antes de elegir otro inmueble. " + REVIEW_STATE },
      { problem: "Aparece «Selecciona un inmueble para cargar su escena».", fix: "Aún no elegiste ninguno: usa la lista Inmueble." },
      { problem: "No se pudo guardar la escena.", fix: "Revisa tu conexión y pulsa Guardar escena otra vez. Si dice que tu sesión expiró, vuelve a entrar." },
    ],
    glossary: ["escena3d", "plano2d", "inmueble", "borrador", "mobiliario"],
  },

  "capture-drafts": {
    heading: "Cómo usar los borradores de capturas",
    audience: "Administradores de inmobiliaria y agentes.",
    purpose:
      "Muestra las reconstrucciones 3D automáticas hechas a partir de las fotos que subió el agente. Son borradores: no valen hasta que los cargues, los corrijas y guardes la escena.",
    canDo: [
      "Ver en qué etapa está cada captura: esperando la subida, en cola, procesando o completada.",
      "Actualizar la lista con el botón Actualizar.",
      "Cargar un borrador en el editor con Cargar borrador en el editor.",
    ],
    walkthroughs: [
      {
        title: "Aceptar un borrador de captura",
        steps: [
          { title: "Pulsa Actualizar", detail: "Revisa que la captura diga «Completada: el borrador está listo para revisar»." },
          { title: "Pulsa Cargar borrador en el editor", detail: "El borrador se carga en el plano; si había cambios sin guardar se te pedirá confirmar el reemplazo." },
          { title: "Corrige lo necesario", detail: "Ajusta paredes, puertas y objetos en el Plano 2D." },
          { title: "Pulsa Guardar escena", detail: "Solo entonces el borrador queda aceptado y los fotogramas temporales se eliminan." },
        ],
      },
    ],
    mistakes: [
      { problem: "La captura sigue en cola o procesando.", fix: "La reconstrucción tarda. Espera y pulsa Actualizar de vez en cuando." },
      { problem: "Aparece «Todavía no hay capturas subidas».", fix: "El agente debe subir la captura desde la aplicación RoomForge Captura." },
      { problem: "Cargué el borrador pero los clientes no lo ven.", fix: "Falta pulsar Guardar escena; mientras tanto es solo un borrador." },
    ],
    glossary: ["captura", "borrador", "escena3d", "plano2d"],
  },

  "furniture-review": {
    heading: "Cómo revisar el mobiliario de un inmueble",
    audience: "Administradores de inmobiliaria y agentes.",
    purpose:
      "El programa intenta detectar los muebles en las fotos. Aquí una persona confirma, corrige o descarta cada sugerencia, o añade muebles a mano, y confirma el inventario.",
    canDo: [
      "Ver las fotos con cajas que marcan los muebles sugeridos.",
      "Confirmar o descartar cada sugerencia.",
      "Añadir un mueble manualmente con su nombre, medidas, posición y precio.",
      "Confirmar todo con el botón Confirmar mobiliario.",
    ],
    walkthroughs: [
      {
        title: "Confirmar una sugerencia automática",
        steps: [
          { title: "Guarda antes la escena", detail: "Si hay cambios pendientes, pulsa Guardar escena: no se puede confirmar con cambios sin guardar." },
          { title: "Elige una sugerencia", detail: "Pulsa una caja o una fila de la lista para verla con sus medidas." },
          { title: "Completa los datos", detail: "Escribe el nombre y el precio por unidad; las medidas y la posición ya vienen cargadas desde la caja. Recuerda que el programa no mide ni fija precios: tú los confirmas." },
          { title: "Pulsa Confirmar mobiliario", detail: "Solo tu confirmación crea el inventario del inmueble." },
        ],
      },
      {
        title: "Añadir un mueble a mano",
        steps: [
          { title: "Abre Añadir mobiliario manualmente", detail: "Úsalo cuando el programa no detectó un mueble." },
          { title: "Rellena el formulario", detail: "Categoría, ancho, alto y fondo en centímetros, posición en metros y precio." },
          { title: "Pulsa Confirmar mobiliario", detail: "El alta queda en borrador para revisión." },
        ],
      },
    ],
    mistakes: [
      { problem: "Los botones están desactivados.", fix: "Hay cambios sin guardar en la escena o una operación en curso. Guarda la escena y espera." },
      { problem: "Aparece «No hay fotos confirmadas».", fix: "El alta manual sigue disponible; añade los muebles a mano." },
      { problem: "Confundí unidades.", fix: "Las medidas van en centímetros; la posición, en metros." },
      { problem: "Falló la operación.", fix: "Pulsa Actualizar revisión y vuelve a intentarlo." },
    ],
    glossary: ["mobiliario", "sugerencia_ia", "escena3d", "borrador"],
  },

  "exchange-rates": {
    heading: "Cómo administrar los tipos de cambio",
    audience: "Administradores de plataforma.",
    purpose:
      "Aquí se define cuántas unidades de cada moneda equivalen a un dólar. Con esos valores los precios se muestran a los clientes en bolivianos, dólares o USDT.",
    canDo: [
      "Ver la tasa vigente de cada moneda.",
      "Ver el historial de las tasas anteriores.",
      "Registrar una nueva tasa para una moneda.",
    ],
    walkthroughs: [
      {
        title: "Registrar una tasa nueva",
        steps: [
          { title: "Mira Tasas vigentes", detail: "Comprueba qué moneda está sin tasa («Sin tasa administrada»)." },
          { title: "Elige la Moneda", detail: "En el formulario Registrar nueva tasa selecciona Bolivianos (BOB) o Tether (USDT). El dólar es la referencia fija." },
          { title: "Escribe Unidades por USD", detail: "Escribe cuántas unidades de esa moneda valen un dólar, con hasta ocho decimales (por ejemplo 6.96)." },
          { title: "Pulsa Registrar tasa", detail: "Aparece «Tasa registrada» y el historial se actualiza." },
        ],
      },
      {
        title: "Consultar el historial",
        steps: [
          { title: "Baja a Historial de tasas", detail: "Cada línea es una tasa que estuvo vigente." },
          { title: "Revisa fecha y origen", detail: "Se ve cuándo se registró y de dónde viene el valor, por ejemplo BCB oficial." },
          { title: "Compara", detail: "Úsalo para detectar cambios o errores de digitación." },
        ],
      },
    ],
    mistakes: [
      { problem: "Aparece «Ingresa una tasa positiva con hasta ocho decimales».", fix: "Escribe un número mayor que cero con punto decimal y como máximo ocho decimales." },
      { problem: "Registré un valor equivocado.", fix: "Registra una tasa nueva con el valor correcto; la última registrada es la vigente." },
      { problem: "Confundí la dirección de la conversión.", fix: "Siempre se indica cuántas unidades de la moneda valen un dólar, no al revés." },
    ],
    glossary: ["tipo_cambio", "usdt", "administrador_plataforma"],
  },

  "card-payments": {
    heading: "Cómo gestionar pagos con tarjeta y reservas",
    audience: "Administradores de inmobiliaria.",
    purpose:
      "Aquí configuras la cuenta que recibe los pagos con tarjeta y decides si aceptas o rechazas las reservas cuyo depósito ya fue pagado. Funciona en modo de prueba.",
    canDo: [
      "Configurar la cuenta de pagos con Stripe Connect.",
      "Ver las reservas con tarjeta pendientes de decisión.",
      "Aceptar una reserva o rechazarla.",
      "Actualizar la lista.",
    ],
    walkthroughs: [
      {
        title: "Configurar la cuenta de pagos",
        steps: [
          { title: "Escribe el correo de contacto", detail: "En el campo de correo escribe uno válido de la inmobiliaria." },
          { title: "Pulsa Configurar Stripe Connect", detail: "Si ya empezaste antes, el botón dice Continuar configuración." },
          { title: "Completa los datos en Stripe", detail: "Sigue los pasos de la página de Stripe y vuelve aquí; al terminar aparece «Cuenta habilitada»." },
        ],
      },
      {
        title: "Decidir sobre una reserva",
        steps: [
          { title: "Revisa la reserva", detail: "Solo aparecen pagos ya confirmados que esperan tu decisión." },
          { title: "Para aceptar", detail: "Pulsa el botón de aceptar. El depósito de prueba se transfiere a la cuenta de la inmobiliaria." },
          { title: "Para rechazar", detail: "Pulsa el botón de rechazar. El depósito de prueba se devuelve al cliente." },
        ],
      },
    ],
    mistakes: [
      { problem: "El botón de aceptar está desactivado.", fix: "La cuenta de pagos todavía no está habilitada. Completa la configuración de Stripe Connect." },
      { problem: "No veo la reserva de un cliente.", fix: "Solo se listan reservas con pago confirmado y aún sin decisión. Pulsa Actualizar." },
      { problem: "Creo que se movió dinero real.", fix: "No: es modo de prueba; ningún dinero real se mueve." },
    ],
    glossary: ["stripe", "reserva", "escrow", "modo_prueba"],
  },

  "chat-inbox": {
    heading: "Cómo usar la bandeja de chat",
    audience: "Administradores de inmobiliaria y agentes.",
    purpose:
      "La bandeja reúne las conversaciones con clientes interesados en tus inmuebles. Desde aquí abres una conversación para leer y responder.",
    canDo: [
      "Ver todas las conversaciones y su estado: Sin atender, Atendida por ti o Solo lectura.",
      "Abrir una conversación para leerla y responder.",
      "Actualizar la bandeja con el botón de recargar.",
    ],
    walkthroughs: [
      {
        title: "Atender una conversación nueva",
        steps: [
          { title: "Busca las marcadas «Sin atender»", detail: "Son las que nadie contestó todavía." },
          { title: "Pulsa la conversación", detail: "Se abre con todos los mensajes." },
          { title: "Responde", detail: "Escribe en Mensaje y pulsa Enviar." },
        ],
      },
      {
        title: "Volver a la lista",
        steps: [
          { title: "Pulsa el botón de volver", detail: "Está arriba de la conversación." },
          { title: "Revisa la bandeja", detail: "Mira cuáles siguen Sin atender y cuáles ya atendiste." },
          { title: "Elige otra", detail: "Pulsa otra conversación para continuar." },
        ],
      },
      {
        title: "Desbloquear a un cliente (administradores de inmobiliaria)",
        steps: [
          { title: "Baja a Clientes bloqueados", detail: "Está al final de la bandeja de chat, debajo de Reportes de conversaciones; solo lo ves si eres administrador de inmobiliaria." },
          { title: "Pulsa Desbloquear", detail: "Junto al cliente que quieres liberar." },
          { title: "Comprueba", detail: "Desaparece de la lista y podrá escribir otra vez." },
        ],
      },
    ],
    mistakes: [
      { problem: "Aparece «Otro agente ya tomó esta conversación».", fix: "Otra persona la atendió primero y la bandeja se actualizó. Elige otra." },
      { problem: "No puedo escribir en una conversación.", fix: "Está en Solo lectura porque pertenece a otro agente." },
      { problem: "No hay conversaciones.", fix: "Aún no hay clientes escribiendo. Vuelve a revisar más tarde." },
    ],
    glossary: ["conversacion", "bandeja", "agente", "administrador_agencia", "bloqueo"],
  },

  "chat-conversation": {
    heading: "Cómo responder y moderar una conversación",
    audience: "Administradores de inmobiliaria y agentes (algunas acciones, solo administradores).",
    purpose:
      "Aquí lees los mensajes de un cliente y le respondes. También puedes reportar un mal uso, bloquear al cliente o reasignar la conversación a otro agente.",
    canDo: [
      "Leer los mensajes y escribir una respuesta.",
      "Reportar al cliente con un motivo (agentes y administradores).",
      "Bloquear al cliente (solo administradores de inmobiliaria).",
      "Reasignar la conversación a otro agente (solo administradores de inmobiliaria).",
    ],
    walkthroughs: [
      {
        title: "Responder a un cliente",
        steps: [
          { title: "Lee los mensajes", detail: "Los más recientes están al final de la lista Mensajes." },
          { title: "Escribe la respuesta", detail: "En el campo Mensaje escribe un texto claro y amable." },
          { title: "Pulsa Enviar", detail: "El mensaje llega al cliente." },
        ],
      },
      {
        title: "Reportar a un cliente",
        steps: [
          { title: "Ve a Moderación", detail: "Está debajo de los mensajes." },
          { title: "Escribe el Motivo del reporte", detail: "Cuenta qué pasó con datos concretos." },
          { title: "Pulsa Reportar cliente", detail: "El administrador de plataforma revisará el caso." },
        ],
      },
      {
        title: "Reasignar la conversación (administradores)",
        steps: [
          { title: "Elige a quién", detail: "En Reasignar a selecciona un agente o la opción automática." },
          { title: "Pulsa el botón de reasignar", detail: "Aparece «Conversación reasignada»." },
          { title: "Avisa al agente", detail: "La conversación aparecerá en su bandeja." },
        ],
      },
    ],
    mistakes: [
      { problem: "El botón Enviar está desactivado.", fix: "El mensaje está vacío o la conversación es de solo lectura." },
      { problem: "Bloqueé a un cliente por error.", fix: "Si eres administrador de inmobiliaria, ve a la bandeja de chat, baja a Clientes bloqueados y pulsa Desbloquear junto al cliente. Si eres agente, pídeselo al administrador de tu inmobiliaria." },
      { problem: "No veo la opción de bloquear ni de reasignar.", fix: "Esas acciones son solo para administradores de inmobiliaria." },
    ],
    glossary: ["conversacion", "reporte", "bloqueo", "agente", "administrador_agencia"],
  },

  "chat-reports": {
    heading: "Cómo atender reportes de conversaciones",
    audience: "Administradores de plataforma.",
    purpose:
      "Aquí llegan los reportes que el personal de las inmobiliarias hizo sobre clientes. Esta lista es para leerlos y decidir qué hacer; no tiene botones para actuar sobre los clientes.",
    canDo: [
      "Leer cada reporte: quién lo hizo, en qué inmueble y por qué.",
      "Ver los agentes involucrados.",
    ],
    walkthroughs: [
      {
        title: "Revisar un reporte",
        steps: [
          { title: "Lee el motivo", detail: "Cada reporte muestra la razón escrita por quien lo envió." },
          { title: "Valora la situación", detail: "Decide si el cliente actuó mal o fue un error." },
          { title: "Anota tu decisión", detail: "Aquí solo se leen los reportes; la inmobiliaria es quien decide sobre el cliente desde su propia bandeja de chat." },
        ],
      },
    ],
    mistakes: [
      { problem: "Busco cómo actuar sobre un cliente reportado.", fix: "Las acciones sobre clientes las hace el administrador de la inmobiliaria desde su bandeja de chat; esta lista solo muestra reportes." },
      { problem: "La lista aparece vacía.", fix: "«No hay reportes» significa que no hay nada pendiente." },
    ],
    glossary: ["reporte", "conversacion", "administrador_plataforma"],
  },

  notifications: {
    heading: "Cómo usar las notificaciones",
    audience: "Personal de inmobiliaria (administradores y agentes).",
    purpose:
      "La campana de arriba muestra avisos cortos de lo que necesita tu atención: mensajes nuevos, conversaciones asignadas y cambios en reservas.",
    canDo: [
      "Ver cuántos avisos tienes sin leer en el número de la campana.",
      "Abrir la lista de notificaciones.",
      "Pulsar un aviso de chat para ir a esa conversación.",
    ],
    walkthroughs: [
      {
        title: "Atender un aviso",
        steps: [
          { title: "Pulsa la campana", detail: "Se abre la Bandeja de notificaciones." },
          { title: "Lee el aviso", detail: "Por ejemplo «Nuevo mensaje en una conversación»." },
          { title: "Pulsa el aviso", detail: "Si es de chat, te lleva a la conversación." },
        ],
      },
      {
        title: "Cerrar la bandeja",
        steps: [
          { title: "Cierra la bandeja", detail: "Pulsa otra vez la campana (el botón Notificaciones)." },
          { title: "Marca todo como leído", detail: "Antes de cerrar puedes pulsar Marcar todo como leído para limpiar el número." },
          { title: "Sigue trabajando", detail: "Los avisos nuevos vuelven a sumar al número de la campana." },
          { title: "Vuelve cuando quieras", detail: "Tus avisos no se pierden." },
        ],
      },
    ],
    mistakes: [
      { problem: "Aparece «No hay notificaciones».", fix: "Todo está al día; no es un fallo." },
      { problem: "Esperaba un aviso y no está.", fix: "Recarga la página para pedirlos de nuevo." },
    ],
    glossary: ["notificacion", "conversacion", "reserva"],
  },

  "agency-reviews": {
    heading: "Cómo gestionar las reseñas",
    audience: "Administradores de inmobiliaria y agentes (responder, solo administradores).",
    purpose:
      "Aquí ves las opiniones y calificaciones que los clientes dejaron sobre tu inmobiliaria. Los administradores pueden responder y todos pueden reportar reseñas inadecuadas.",
    canDo: [
      "Leer las reseñas y sus calificaciones.",
      "Responder públicamente a una reseña (solo administradores).",
      "Reportar una reseña inadecuada con Reportar reseña.",
    ],
    walkthroughs: [
      {
        title: "Responder a una reseña",
        steps: [
          { title: "Lee la reseña", detail: "Entiende lo que el cliente cuenta antes de responder." },
          { title: "Pulsa Responder", detail: "Se abre un campo llamado Tu respuesta." },
          { title: "Escribe y envía", detail: "Escribe un texto respetuoso y pulsa el botón de enviar." },
        ],
      },
      {
        title: "Reportar una reseña",
        steps: [
          { title: "Pulsa Reportar reseña", detail: "Se abre un campo para el motivo." },
          { title: "Escribe el Motivo del reporte", detail: "Explica por qué es inadecuada, por ejemplo insultos o datos falsos." },
          { title: "Pulsa Enviar reporte", detail: "El administrador de plataforma decidirá si la oculta." },
        ],
      },
    ],
    mistakes: [
      { problem: "No encuentro el botón Responder.", fix: "Solo los administradores de inmobiliaria pueden responder." },
      { problem: "Reporté una reseña solo porque es negativa.", fix: "Reporta únicamente las que incumplen normas; una crítica negativa se contesta con una respuesta." },
      { problem: "Aparece «Todavía no hay reseñas».", fix: "Aún no hay opiniones de clientes." },
    ],
    glossary: ["resena", "reporte", "administrador_agencia"],
  },

  "review-reports": {
    heading: "Cómo resolver reportes de reseñas",
    audience: "Administradores de plataforma.",
    purpose:
      "Aquí decides qué hacer con las reseñas que una inmobiliaria reportó como inadecuadas: ocultarlas o descartar el reporte.",
    canDo: [
      "Leer el motivo y la fecha de cada reporte.",
      "Confirmar el reporte y ocultar la reseña.",
      "Descartar el reporte si la reseña es válida.",
    ],
    walkthroughs: [
      {
        title: "Resolver un reporte",
        steps: [
          { title: "Lee el Motivo del reporte", detail: "Entiende por qué la inmobiliaria la reportó." },
          { title: "Decide", detail: "Si incumple las normas, la reseña debe ocultarse; si solo es una crítica, debe quedar." },
          { title: "Pulsa el botón correspondiente", detail: "Confirmar y ocultar reseña, o Descartar reporte. El reporte desaparece de la lista." },
        ],
      },
    ],
    mistakes: [
      { problem: "Oculté una reseña válida.", fix: "Anota el caso y avisa al equipo; confirma siempre el motivo antes de decidir." },
      { problem: "Aparece «No hay reportes de reseñas pendientes».", fix: "No hay nada que resolver ahora." },
    ],
    glossary: ["resena", "reporte", "administrador_plataforma"],
  },

  "scene-viewer": {
    heading: "Cómo recorrer una escena en 3D",
    audience: "Personal con acceso al visor 3D.",
    purpose:
      "El visor muestra la escena 3D de un inmueble para recorrerla como lo haría un cliente. Sirve para mirar, no para cambiar nada.",
    canDo: [
      "Girar y acercar la vista con el ratón.",
      "Moverte por la escena con las teclas W, A, S y D.",
      "Revisar cómo se ve el inmueble.",
    ],
    walkthroughs: [
      {
        title: "Recorrer la escena",
        steps: [
          { title: "Haz clic en la escena", detail: "Así el visor recibe tus movimientos." },
          { title: "Muévete con W, A, S, D", detail: "W avanza, S retrocede, A va a la izquierda y D a la derecha." },
          { title: "Mira alrededor", detail: "Mantén pulsado el botón del ratón y arrástralo para girar la vista." },
        ],
      },
    ],
    mistakes: [
      { problem: "No me muevo con el teclado.", fix: "Haz clic primero dentro de la escena para que reciba las teclas." },
      { problem: "Quiero mover una pared desde aquí.", fix: "El visor no edita; usa el Editor de escenas." },
    ],
    glossary: ["escena3d", "inmueble"],
  },
} satisfies Record<string, GuideTopic>;

export type GuideScreenId = keyof typeof GUIDE_TOPICS;

export const GUIDE_SCREEN_IDS = Object.keys(GUIDE_TOPICS) as GuideScreenId[];
