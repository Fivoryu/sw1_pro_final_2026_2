import 'package:flutter/material.dart';

/// Screens that offer a contextual guide.
enum GuideScreen { listingsList, listingEditor }

/// Title of the guide shown for [screen].
String guideTitle(GuideScreen screen) => switch (screen) {
  GuideScreen.listingsList => 'Cómo preparar un borrador',
  GuideScreen.listingEditor => 'Cómo completar el borrador',
};

/// Deterministic, rule-based steps for [screen]. The guide only indicates
/// what to do; it never performs the action for the person.
List<String> guideSteps(GuideScreen screen) => switch (screen) {
  GuideScreen.listingsList => const [
    'Tocá «Nuevo inmueble» para empezar un borrador.',
    'Completá los datos y guardalos como borrador.',
    'Volvé a esta lista: tus borradores aparecen en la pestaña «Borradores».',
    'Cuando esté completo, abrilo y enviá el inmueble a revisión.',
  ],
  GuideScreen.listingEditor => const [
    'Elegí la moneda y cargá el precio base.',
    'Marcá la ubicación en el mapa y, si querés, agregá una descripción.',
    'Sumá las fotos del inmueble desde la cámara o la galería.',
    'Tocá «Guardar borrador» para conservar tus cambios.',
    'Cuando esté listo, tocá «Enviar a revisión».',
  ],
};

/// Help button that opens a bottom sheet with step-by-step guidance.
class ContextualGuideButton extends StatelessWidget {
  const ContextualGuideButton({super.key, required this.screen});

  final GuideScreen screen;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('guide-button'),
    tooltip: 'Asistente inteligente',
    icon: const Icon(Icons.help_outline),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GuideSheet(screen: screen),
    ),
  );
}

class _GuideSheet extends StatelessWidget {
  const _GuideSheet({required this.screen});

  final GuideScreen screen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = guideSteps(screen);
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('guide-sheet'),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(guideTitle(screen), style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(radius: 12, child: Text('${i + 1}')),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        steps[i],
                        key: ValueKey('guide-step-$i'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
