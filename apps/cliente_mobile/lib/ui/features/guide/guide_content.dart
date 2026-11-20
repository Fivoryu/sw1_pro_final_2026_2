/// Screens of the client app that have contextual guidance.
enum GuideScreen { catalog, listingDetail }

/// Deterministic, rule-based guidance for one screen. It only describes what
/// the person can do; it never performs any action.
class GuideContent {
  const GuideContent({
    required this.title,
    required this.goal,
    required this.steps,
  });

  final String title;
  final String goal;
  final List<String> steps;

  static GuideContent forScreen(GuideScreen screen) => switch (screen) {
    GuideScreen.catalog => const GuideContent(
      title: 'Cómo buscar un inmueble',
      goal: 'Encontrá un inmueble que se ajuste a lo que necesitás.',
      steps: [
        'Elegí la moneda de visualización para ver los precios en la que prefieras.',
        'Tocá «Filtrar catálogo» para indicar tipo, precio o zona.',
        'Revisá las tarjetas de la lista: cada una resume el inmueble.',
        'Tocá una tarjeta para abrir su detalle.',
        'Si no ves resultados, usá «Quitar filtros» y probá de nuevo.',
      ],
    ),
    GuideScreen.listingDetail => const GuideContent(
      title: 'Cómo consultar un inmueble',
      goal: 'Conocé el inmueble antes de decidir.',
      steps: [
        'Mirá las fotos y la descripción para conocer el espacio.',
        'Revisá el precio y las condiciones de la operación.',
        'Si hay recorrido 3D, abrilo para ver el inmueble por dentro.',
        'Armá una cotización para conocer el costo total.',
        'Cuando estés seguro, podés solicitar la reserva desde esta pantalla.',
      ],
    ),
  };
}
