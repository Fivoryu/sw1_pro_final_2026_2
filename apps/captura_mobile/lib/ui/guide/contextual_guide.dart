import 'package:flutter/material.dart';

import 'guide_content.dart';

export 'guide_content.dart';

/// Steps of the primary walkthrough of [screen]. The guide only indicates
/// what to do; it never performs the action for the person.
List<String> guideSteps(GuideScreen screen) =>
    guideWalkthroughs(screen).first.steps;

/// Help button that opens a bottom sheet with the guide of [screen].
///
/// It only reads static text: it holds no controller and touches no screen
/// state, so it is safe in capture screens.
class ContextualGuideButton extends StatelessWidget {
  const ContextualGuideButton({super.key, required this.screen});

  final GuideScreen screen;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('guide-button'),
    tooltip: 'Asistente inteligente: ayuda de esta pantalla',
    icon: const Icon(Icons.help_outline),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GuideSheet(screen: screen),
    ),
  );
}

class _GuideSheet extends StatelessWidget {
  const _GuideSheet({required this.screen});

  final GuideScreen screen;

  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(text, style: theme.textTheme.titleMedium),
    ),
  );

  Widget _step(ThemeData theme, Key key, int number, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(radius: 12, child: Text('$number')),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, key: key, style: theme.textTheme.bodyMedium),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final walkthroughs = guideWalkthroughs(screen);
    return SafeArea(
      child: Semantics(
        label: 'Guía de ayuda: ${guideTitle(screen)}',
        child: SingleChildScrollView(
          key: const ValueKey('guide-sheet'),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  guideTitle(screen),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              _heading(theme, 'Para qué sirve'),
              Text(guidePurpose(screen), style: theme.textTheme.bodyMedium),
              _heading(theme, 'Paso a paso'),
              for (var w = 0; w < walkthroughs.length; w++) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    walkthroughs[w].title,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                for (var i = 0; i < walkthroughs[w].steps.length; i++)
                  _step(
                    theme,
                    ValueKey(w == 0 ? 'guide-step-$i' : 'guide-step-$w-$i'),
                    i + 1,
                    walkthroughs[w].steps[i],
                  ),
              ],
              _heading(theme, 'Errores comunes'),
              for (final mistake in guideMistakes(screen))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mistake.problem,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Qué hacer: ${mistake.solution}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              _heading(theme, 'Glosario'),
              for (final term in guideGlossary(screen))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${term.term}: ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: term.definition),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium,
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
      ),
    );
  }
}
