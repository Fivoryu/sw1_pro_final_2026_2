import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'guide_assistant.dart';
import 'guide_content.dart';

/// Help button that opens a chat-style assistant for [screen]. It only
/// explains and has no effect on the screen.
class GuideHelpButton extends StatelessWidget {
  const GuideHelpButton({super.key, required this.screen, this.label});

  final GuideScreen screen;

  /// When set, uses a compass icon whose tooltip starts with this label.
  final String? label;

  void _open(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GuideSheet(screen: screen),
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

class _Message {
  const _Message({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

/// Chat-style assistant sheet. Answers come from [GuideAssistant]; nothing the
/// person writes or taps here triggers an action of the screen.
class GuideSheet extends StatefulWidget {
  const GuideSheet({super.key, required this.screen});

  final GuideScreen screen;

  @override
  State<GuideSheet> createState() => _GuideSheetState();
}

class _GuideSheetState extends State<GuideSheet> {
  static const _assistant = GuideAssistant();

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];
  late List<String> _suggestions;
  bool _full = false;

  @override
  void initState() {
    super.initState();
    final hello = _assistant.greeting(widget.screen);
    _messages.add(_Message(fromUser: false, text: hello.text));
    _suggestions = hello.suggestions;
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _ask(String raw) {
    final question = raw.trim();
    if (question.isEmpty) return;
    final reply = _assistant.answer(question, widget.screen);
    setState(() {
      _messages
        ..add(_Message(fromUser: true, text: question))
        ..add(_Message(fromUser: false, text: reply.text));
      _suggestions = reply.suggestions;
    });
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Widget _bubble(BuildContext context, int index) {
    final m = _messages[index];
    final scheme = Theme.of(context).colorScheme;
    final isLast = index == _messages.length - 1;
    final who = m.fromUser ? 'user' : 'assistant';
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        liveRegion: !m.fromUser && isLast,
        label: m.fromUser ? 'Vos: ${m.text}' : 'Guía: ${m.text}',
        excludeSemantics: true,
        child: Container(
          key: ValueKey('guide-msg-$who-$index'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.85,
          ),
          decoration: BoxDecoration(
            color: m.fromUser
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(m.text),
        ),
      ),
    );
  }

  Widget _chat(BuildContext context, bool keyboardOpen) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            itemCount: _messages.length,
            itemBuilder: _bubble,
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: keyboardOpen ? 48 : 96),
          child: SingleChildScrollView(
            key: const ValueKey('guide-suggestions'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final s in _suggestions)
                  ActionChip(label: Text(s), onPressed: () => _ask(s)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('guide-chat-input'),
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [LengthLimitingTextInputFormatter(200)],
                  onSubmitted: _ask,
                  decoration: const InputDecoration(
                    hintText: 'Escribí tu pregunta',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('guide-chat-send'),
                tooltip: 'Enviar pregunta',
                icon: const Icon(Icons.send),
                onPressed: () => _ask(_input.text),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom;
    final available = media.size.height * 0.85 - inset;
    final height = available < 240 ? 240.0 : available;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: SizedBox(
          key: const ValueKey('guide-sheet'),
          height: height,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Asistente de RoomForge',
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('guide-full-toggle'),
                      onPressed: () => setState(() => _full = !_full),
                      child: Text(
                        _full ? 'Volver al chat' : 'Ver guía completa',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _full
                    ? GuideFullView(
                        content: GuideContent.forScreen(widget.screen),
                      )
                    : _chat(context, inset > 0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Structured guide: purpose, steps, common mistakes and glossary.
class GuideFullView extends StatelessWidget {
  const GuideFullView({super.key, required this.content});

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
        key: const ValueKey('guide-full'),
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
