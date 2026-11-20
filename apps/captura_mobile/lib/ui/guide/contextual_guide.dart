import 'package:flutter/material.dart';

import 'guide_assistant.dart';
import 'guide_content.dart';

export 'guide_content.dart';

/// Steps of the primary walkthrough of [screen]. The guide only indicates
/// what to do; it never performs the action for the person.
List<String> guideSteps(GuideScreen screen) =>
    guideWalkthroughs(screen).first.steps;

/// Help button that opens a chat-style assistant for [screen].
///
/// The assistant only explains from static text: it holds no screen
/// controller and never navigates, calls an API or submits anything, so it
/// is safe in capture screens.
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

class _Message {
  const _Message(this.text, {required this.fromUser});

  final String text;
  final bool fromUser;
}

class _GuideSheet extends StatefulWidget {
  const _GuideSheet({required this.screen});

  final GuideScreen screen;

  @override
  State<_GuideSheet> createState() => _GuideSheetState();
}

class _GuideSheetState extends State<_GuideSheet> {
  late final GuideAssistant _assistant = GuideAssistant(widget.screen);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final List<_Message> _messages = [
    _Message(_assistant.greeting(), fromUser: false),
  ];
  late List<String> _suggestions = _assistant.initialSuggestions();
  bool _showFullGuide = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _ask(String question) {
    final text = question.trim();
    if (text.isEmpty) return;
    final reply = _assistant.answer(text);
    setState(() {
      _messages
        ..add(_Message(text, fromUser: true))
        ..add(_Message(reply.text, fromUser: false));
      _suggestions = reply.suggestions;
    });
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            key: const ValueKey('guide-sheet'),
            height: constraints.maxHeight * (inset > 0 ? 1 : 0.9),
            child: Semantics(
              label: 'Asistente de ayuda: ${guideTitle(widget.screen)}',
              container: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        guideTitle(widget.screen),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Wrap(
                      children: [
                        TextButton(
                          key: const ValueKey('guide-full-toggle'),
                          onPressed: () =>
                              setState(() => _showFullGuide = !_showFullGuide),
                          child: Text(
                            _showFullGuide
                                ? 'Volver al chat'
                                : 'Ver guía completa',
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Entendido'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: _showFullGuide
                          ? _FullGuide(screen: widget.screen)
                          : _chat(theme),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chat(ThemeData theme) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        Expanded(
          child: Semantics(
            label: 'Conversación con la guía',
            container: true,
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _messages.length; i++) _bubble(theme, i),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (constraints.maxHeight * 0.3).clamp(0.0, 112.0),
          ),
          child: SingleChildScrollView(
            key: const ValueKey('guide-suggestions'),
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final suggestion in _suggestions)
                    ActionChip(
                      key: ValueKey('guide-chip-$suggestion'),
                      label: Text(suggestion),
                      onPressed: () => _ask(suggestion),
                    ),
                ],
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('guide-input'),
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: _ask,
                decoration: const InputDecoration(
                  labelText: 'Escribí tu pregunta',
                  hintText: 'Por ejemplo: ¿cómo envío a revisión?',
                ),
              ),
            ),
            Semantics(
              label: 'Enviar pregunta',
              button: true,
              excludeSemantics: true,
              child: IconButton(
                key: const ValueKey('guide-send'),
                tooltip: 'Enviar pregunta',
                icon: const Icon(Icons.send),
                onPressed: () => _ask(_input.text),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _bubble(ThemeData theme, int i) {
    final message = _messages[i];
    final scheme = theme.colorScheme;
    return Align(
      alignment: message.fromUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        key: ValueKey(
          message.fromUser ? 'guide-user-$i' : 'guide-assistant-$i',
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        decoration: BoxDecoration(
          color: message.fromUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message.text, style: theme.textTheme.bodyMedium),
      ),
    );
  }
}

/// The complete structured guide: purpose, walkthroughs, mistakes, glossary.
class _FullGuide extends StatelessWidget {
  const _FullGuide({required this.screen});

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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        ],
      ),
    );
  }
}
