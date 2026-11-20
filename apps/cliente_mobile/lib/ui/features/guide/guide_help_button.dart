import 'package:flutter/material.dart';

import 'guide_content.dart';

/// Help button that opens a bottom sheet with guidance for [screen]. It only
/// shows information and has no effect on the screen.
class GuideHelpButton extends StatelessWidget {
  const GuideHelpButton({super.key, required this.screen, this.label});

  final GuideScreen screen;

  /// When set, uses a compass icon whose tooltip starts with this label.
  final String? label;

  void _open(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GuideSheet(content: GuideContent.forScreen(screen)),
  );

  @override
  Widget build(BuildContext context) {
    final title = GuideContent.forScreen(screen).title;
    final text = label;
    if (text != null) {
      return IconButton(
        key: ValueKey('guide-welcome-button-${screen.name}'),
        tooltip: '$text: $title',
        icon: const Icon(Icons.explore_outlined),
        onPressed: () => _open(context),
      );
    }
    return IconButton(
      key: const ValueKey('guide-help-button'),
      tooltip: 'Ayuda: $title',
      icon: const Icon(Icons.help_outline),
      onPressed: () => _open(context),
    );
  }
}

class GuideSheet extends StatelessWidget {
  const GuideSheet({super.key, required this.content});

  final GuideContent content;

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );

  Widget _step(int number, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      label: 'Paso $number: $text',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 12, child: Text('$number')),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('guide-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(content.title, style: text.titleLarge),
            ),
            _heading(context, 'Para qué sirve'),
            Text(content.goal, style: text.bodyMedium),
            _heading(context, 'Paso a paso'),
            for (final walkthrough in content.walkthroughs) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(walkthrough.name, style: text.titleSmall),
              ),
              for (var i = 0; i < walkthrough.steps.length; i++)
                _step(i + 1, walkthrough.steps[i]),
            ],
            _heading(context, 'Errores comunes'),
            for (final mistake in content.mistakes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(mistake)),
                  ],
                ),
              ),
            _heading(context, 'Glosario'),
            for (final term in GuideContent.glossary)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${term.term}: ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: term.definition),
                    ],
                  ),
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
