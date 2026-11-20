import 'package:flutter/material.dart';

import 'guide_content.dart';

/// Help button that opens a bottom sheet with step-by-step guidance for
/// [screen]. It only shows information and has no effect on the screen.
class GuideHelpButton extends StatelessWidget {
  const GuideHelpButton({super.key, required this.screen});

  final GuideScreen screen;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('guide-help-button'),
    tooltip: 'Ayuda: ${GuideContent.forScreen(screen).title}',
    icon: const Icon(Icons.help_outline),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => GuideSheet(content: GuideContent.forScreen(screen)),
    ),
  );
}

class GuideSheet extends StatelessWidget {
  const GuideSheet({super.key, required this.content});

  final GuideContent content;

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
            Text(content.title, style: text.titleLarge),
            const SizedBox(height: 4),
            Text(content.goal, style: text.bodyMedium),
            const SizedBox(height: 16),
            for (var i = 0; i < content.steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(radius: 12, child: Text('${i + 1}')),
                    const SizedBox(width: 12),
                    Expanded(child: Text(content.steps[i])),
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
