import 'dart:math' as math;

import 'guide_content.dart';

/// Reply of the guide assistant: Spanish [text] plus follow-up [suggestions].
class GuideAnswer {
  const GuideAnswer(this.text, this.suggestions);

  final String text;
  final List<String> suggestions;
}

/// Deterministic, offline question answering over the static guide content of
/// every screen. No network, no language model: it only matches words. It only
/// explains; it never performs a screen action.
class GuideAssistant {
  GuideAssistant(this.screen);

  final GuideScreen screen;

  static const _purposeChip = '¿Para qué sirve esta pantalla?';
  static const _errorsChip = '¿Qué errores son comunes?';
  static const _moreChip = '¿Qué más puedo hacer?';

  /// First message of the conversation.
  String greeting() {
    final titles = guideWalkthroughs(screen).map((w) => w.title).join(', ');
    return 'Hola, soy la guía de RoomForge. Estás en «${guideTitle(screen)}». '
        'Acá podés: $titles. Tocá una sugerencia o escribime tu pregunta.';
  }

  /// Context-aware chips shown when the chat opens.
  List<String> initialSuggestions() => [
    _purposeChip,
    for (final w in guideWalkthroughs(screen)) w.title,
    _errorsChip,
    for (final t in guideGlossary(screen).take(2)) '¿Qué es ${t.term}?',
    _moreChip,
  ];

  /// Answers [question] with the guide content; falls back honestly.
  GuideAnswer answer(String question) {
    final normalized = guideNormalize(question);
    final tokens = _tokens(normalized);
    final words = normalized.split(' ').where((w) => w.isNotEmpty).toList();

    if (words.isEmpty) return _fallback();
    if (_isGreeting(words)) {
      return GuideAnswer(
        'Hola, ¿en qué te ayudo? Estás en «${guideTitle(screen)}».',
        _initialChips(),
      );
    }
    if (words.contains('gracias') && words.length <= 5) {
      return GuideAnswer(
        'Con gusto. Si te surge otra duda, preguntame cuando quieras.',
        _initialChips(),
      );
    }
    if (_isLost(normalized, words)) return _lost();
    if (normalized.contains('para que sirve') ||
        normalized.contains('esta pantalla')) {
      return GuideAnswer(guidePurpose(screen), [
        ...guideWalkthroughs(screen).map((w) => w.title).take(3),
      ]);
    }
    if (normalized.contains('que mas') || normalized.contains('opciones')) {
      return _more();
    }
    if (words.any(_errorWords.contains) &&
        words.every((w) => _errorWords.contains(w) || _stopwords.contains(w))) {
      return _errors();
    }
    if (RegExp(r'^(que (es|son|significa)|significa)\b').hasMatch(normalized)) {
      final term = _best(tokens, termsOnly: true);
      if (term != null) return _reply(term, tokens);
    }
    final best = _best(tokens);
    return best == null ? _fallback() : _reply(best, tokens);
  }

  // ---- intents ----

  static const _errorWords = {
    'error',
    'errores',
    'comunes',
    'frecuentes',
    'problemas',
    'fallas',
  };

  bool _isGreeting(List<String> words) =>
      words.length <= 3 &&
      const {
        'hola',
        'buenas',
        'buenos',
        'buen',
        'hey',
        'saludos',
      }.contains(words.first);

  bool _isLost(String normalized, List<String> words) =>
      normalized.contains('perdi') ||
      normalized.contains('no se que hacer') ||
      normalized.contains('que hago') ||
      normalized.contains('no entiendo') ||
      const {'ayuda', 'ayudame', 'help', 'socorro'}.contains(words.first) &&
          words.length <= 3;

  GuideAnswer _lost() {
    final list = _numbered(guideWalkthroughs(screen).map((w) => w.title));
    return GuideAnswer(
      'No te preocupes, te ubico. Estás en «${guideTitle(screen)}». '
      '${guidePurpose(screen)}\n\nEn esta pantalla podés:\n$list\n\n'
      'Elegí una sugerencia o escribime qué querés lograr.',
      _initialChips(),
    );
  }

  GuideAnswer _more() => GuideAnswer(
    'En «${guideTitle(screen)}» podés:\n'
    '${_numbered(guideWalkthroughs(screen).map((w) => w.title))}\n\n'
    'Tocá uno para ver el paso a paso.',
    guideWalkthroughs(screen).map((w) => w.title).take(4).toList(),
  );

  GuideAnswer _errors() => GuideAnswer(
    'Errores comunes en esta pantalla:\n'
    '${[for (final m in guideMistakes(screen)) '• ${m.problem} Qué hacer: ${m.solution}'].join('\n')}',
    [
      _purposeChip,
      ...guideWalkthroughs(screen).map((w) => w.title),
    ].take(3).toList(),
  );

  GuideAnswer _fallback() => GuideAnswer(
    'Por ahora no estoy seguro de haber entendido tu pregunta, y prefiero no '
    'inventar. '
    'En esta pantalla puedo explicarte:\n'
    '${_numbered(guideWalkthroughs(screen).map((w) => w.title))}\n\n'
    'También podés preguntarme para qué sirve, qué errores son comunes o '
    'qué significa un término. Probá con una sugerencia.',
    _initialChips(),
  );

  List<String> _initialChips() => initialSuggestions().take(4).toList();

  static String _numbered(Iterable<String> items) =>
      [for (final (i, item) in items.indexed) '${i + 1}. $item'].join('\n');

  // ---- replies ----

  GuideAnswer _reply(_Entry entry, List<String> tokens) {
    final buffer = StringBuffer();
    final own = entry.screen == null || entry.screen == screen;
    if (!own) {
      final target = entry.screen!;
      buffer.writeln(
        'Eso se hace en otra pantalla: «${_screenName[target]}». '
        'Para llegar: ${_howToReach[target]}',
      );
      buffer.writeln();
    }
    buffer.write(entry.answer);
    return GuideAnswer(
      buffer.toString().trimRight(),
      _followUps(entry, tokens),
    );
  }

  List<String> _followUps(_Entry answered, List<String> tokens) {
    final chips = <String>[];
    void add(String chip) {
      if (chip != answered.chip && !chips.contains(chip)) chips.add(chip);
    }

    for (final e in _ranked(tokens).skip(1).take(6)) {
      add(e.chip);
    }
    for (final w in guideWalkthroughs(answered.screen ?? screen)) {
      add(w.title);
    }
    add(_moreChip);
    add(_purposeChip);
    return chips.take(math.min(3, chips.length)).toList();
  }

  // ---- matching ----

  _Entry? _best(List<String> tokens, {bool termsOnly = false}) {
    final ranked = _ranked(tokens, termsOnly: termsOnly);
    return ranked.isEmpty ? null : ranked.first;
  }

  List<_Entry> _ranked(List<String> tokens, {bool termsOnly = false}) {
    final stems = tokens.map(_stem).toSet();
    final scored = <(_Entry, double)>[];
    for (final e in _knowledge.entries) {
      if (termsOnly && e.kind != _Kind.term) continue;
      var score = 0.0;
      for (final s in stems) {
        final idf = _knowledge.idf(s);
        if (e.titleStems.contains(s)) {
          score += 3 * idf;
        } else if (!termsOnly && e.bodyStems.contains(s)) {
          score += idf;
        }
      }
      if (score < 2.0) continue;
      final isOwn =
          e.screen == screen ||
          (e.kind == _Kind.term &&
              guideGlossary(screen).any((t) => t.term == e.title));
      scored.add((e, isOwn ? score * 1.4 : score));
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : a.$1.order.compareTo(b.$1.order);
    });
    return [for (final s in scored) s.$1];
  }
}

/// Lowercases, strips accents and punctuation, and collapses spaces.
String guideNormalize(String text) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    buffer.write(i >= 0 ? to[i] : ch);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

const _stopwords = <String>{
  'a', 'al', 'algo', 'como', 'con', 'cual', 'de', 'del', 'desde', 'donde',
  'el', 'en', 'es', 'esta', 'este', 'esto', 'hacer', 'hago', 'la', 'las',
  'lo', 'los', 'me', 'mi', 'mis', 'muy', 'necesito', 'no', 'o', 'para',
  'pero', 'por', 'puedo', 'puede', 'podes', 'que', 'quiero', 'se', 'si',
  'sin', 'son', 'su', 'sus', 'te', 'tu', 'tus', 'un', 'una', 'uno', 'unos',
  'unas', 'y', 'ya', 'hay', 'mas', 'quisiera', 'queria', //
};

List<String> _tokens(String normalized) => [
  for (final w in normalized.split(' '))
    if (w.isNotEmpty && !_stopwords.contains(w)) w,
];

/// Light stemming: the first four letters absorb verb and plural endings.
String _stem(String word) => word.length > 4 ? word.substring(0, 4) : word;

Set<String> _stems(String text) => {
  for (final t in _tokens(guideNormalize(text))) _stem(t),
};

enum _Kind { purpose, walkthrough, mistake, term }

class _Entry {
  _Entry({
    required this.kind,
    required this.screen,
    required this.title,
    required String body,
    required this.answer,
    required this.chip,
    required this.order,
  }) : titleStems = _stems(title),
       bodyStems = _stems(body);

  final _Kind kind;
  final GuideScreen? screen;
  final String title;
  final String answer;
  final String chip;
  final int order;
  final Set<String> titleStems;
  final Set<String> bodyStems;
}

class _Knowledge {
  _Knowledge() {
    var order = 0;
    final seenTerms = <String>{};
    for (final screen in GuideScreen.values) {
      entries.add(
        _Entry(
          kind: _Kind.purpose,
          screen: screen,
          title: '',
          body: guidePurpose(screen),
          answer: guidePurpose(screen),
          chip: GuideAssistant._purposeChip,
          order: order++,
        ),
      );
      for (final w in guideWalkthroughs(screen)) {
        entries.add(
          _Entry(
            kind: _Kind.walkthrough,
            screen: screen,
            title: w.title,
            body: w.steps.join(' '),
            answer:
                'Para «${w.title}»:\n'
                '${GuideAssistant._numbered(w.steps)}',
            chip: w.title,
            order: order++,
          ),
        );
      }
      for (final m in guideMistakes(screen)) {
        entries.add(
          _Entry(
            kind: _Kind.mistake,
            screen: screen,
            title: m.problem,
            body: m.solution,
            answer:
                'Problema frecuente: ${m.problem}\nQué hacer: ${m.solution}',
            chip: GuideAssistant._errorsChip,
            order: order++,
          ),
        );
      }
      for (final t in guideGlossary(screen)) {
        if (!seenTerms.add(t.term)) continue;
        entries.add(
          _Entry(
            kind: _Kind.term,
            screen: null,
            title: t.term,
            body: t.definition,
            answer: '«${t.term}»: ${t.definition}',
            chip: '¿Qué es ${t.term}?',
            order: order++,
          ),
        );
      }
    }
    for (final e in entries) {
      for (final s in {...e.titleStems, ...e.bodyStems}) {
        _df[s] = (_df[s] ?? 0) + 1;
      }
    }
  }

  final entries = <_Entry>[];
  final _df = <String, int>{};

  double idf(String stem) =>
      math.log(1 + entries.length / (_df[stem] ?? entries.length));
}

final _knowledge = _Knowledge();

const _screenName = <GuideScreen, String>{
  GuideScreen.welcome: 'Inicio',
  GuideScreen.access: 'Acceso',
  GuideScreen.listingsList: 'Mis inmuebles',
  GuideScreen.listingEditor: 'Ficha del inmueble',
  GuideScreen.spatialCapture: 'Medición de ambientes',
  GuideScreen.roomEditor: 'Ficha de un ambiente',
  GuideScreen.floorplanTrace: 'Trazado desde un plano',
  GuideScreen.chatInbox: 'Conversaciones',
  GuideScreen.chatConversation: 'Conversación con un cliente',
  GuideScreen.notifications: 'Avisos',
  GuideScreen.reviews: 'Reseñas',
};

const _howToReach = <GuideScreen, String>{
  GuideScreen.welcome: 'es la pantalla que ves apenas entrás con tu cuenta.',
  GuideScreen.access:
      'es la primera pantalla al abrir la aplicación; si ya entraste, '
      'tocá «Cerrar sesión» en el inicio para volver a ella.',
  GuideScreen.listingsList: 'en el inicio, tocá «Continuar a mis inmuebles».',
  GuideScreen.listingEditor:
      'en «Mis inmuebles», tocá «Nuevo inmueble» o un borrador ya creado.',
  GuideScreen.spatialCapture:
      'en la ficha del inmueble, tocá «Medir ambientes».',
  GuideScreen.roomEditor:
      'en «Medición de ambientes», tocá un ambiente que ya esté medido.',
  GuideScreen.floorplanTrace:
      'en «Medición de ambientes», tocá «Capturar ambiente» y elegí '
      '«Plano o croquis».',
  GuideScreen.chatInbox: 'en el inicio, tocá «Conversaciones».',
  GuideScreen.chatConversation:
      'en «Conversaciones», tocá la conversación con el cliente.',
  GuideScreen.notifications: 'abrí los avisos desde el inicio.',
  GuideScreen.reviews: 'en el inicio, tocá «Reseñas».',
};
