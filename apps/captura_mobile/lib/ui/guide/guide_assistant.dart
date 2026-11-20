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
  ///
  /// Social and orientation intents fire only when the question holds no
  /// meaningful word beyond the intent words, so "hola, cómo entro" or "qué
  /// hago con una foto oscura" are answered with the specific content.
  GuideAnswer answer(String question) {
    final normalized = guideNormalize(question);
    final words = normalized.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return _fallback();

    final meaningful = [
      for (final w in words)
        if (!_stopwords.contains(w)) w,
    ];
    if (meaningful.isNotEmpty && meaningful.every(_greetingWords.contains)) {
      return GuideAnswer(
        'Hola, ¿en qué te ayudo? Estás en «${guideTitle(screen)}».',
        _initialChips(),
      );
    }
    if (meaningful.isNotEmpty && meaningful.every(_thanksWords.contains)) {
      return GuideAnswer(
        'Con gusto. Si te surge otra duda, preguntame cuando quieras.',
        _initialChips(),
      );
    }
    // A greeting or thanks prefix followed by a real question is dropped.
    final content = [
      for (final w in meaningful)
        if (!_greetingWords.contains(w) && !_thanksWords.contains(w)) w,
    ];
    bool only(Set<String> intentWords) => content.every(intentWords.contains);

    final lost =
        _lostPhrase.hasMatch(normalized) && only(_lostWords) ||
        content.isNotEmpty &&
            _helpWords.contains(content.first) &&
            only({..._lostWords, ..._helpWords});
    if (lost) return _lost();
    if (_purposePhrase.hasMatch(normalized) && only(_purposeWords)) {
      return GuideAnswer(guidePurpose(screen), [
        ...guideWalkthroughs(screen).map((w) => w.title).take(3),
      ]);
    }
    if (_morePhrase.hasMatch(normalized) && only(_moreWords)) return _more();
    if (content.any(_errorWords.contains) && only(_errorWords)) {
      return _errors();
    }

    final query = [
      for (final w in _fuzzy(content))
        if (!_intentWords.contains(w)) _canon(w),
    ];
    if (query.isEmpty) return _fallback();

    if (_definePhrase.hasMatch(normalized)) {
      final term = _best(query, termsOnly: true);
      if (term != null) return _reply(term, query);
    }
    final best = _best(query);
    return best == null ? _fallback() : _reply(best, query);
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
  static const _greetingWords = {
    'hola',
    'buenas',
    'buenos',
    'buen',
    'hey',
    'saludos',
    'dia',
    'dias',
    'tardes',
    'noches',
  };
  static const _thanksWords = {
    'gracias',
    'muchas',
    'mil',
    'genial',
    'perfecto',
    'excelente',
  };
  static const _helpWords = {'ayuda', 'ayudame', 'help', 'socorro'};
  static const _lostWords = {
    'perdi',
    'perdido',
    'perdida',
    'entiendo',
    'nada',
    'ayuda',
    'ayudame',
    'help',
    'socorro',
  };
  static const _purposeWords = {'sirve', 'pantalla', 'aqui', 'aca', 'ahi'};
  static const _moreWords = {'opciones', 'otra', 'otras', 'cosas', 'ademas'};
  static final _intentWords = {
    'significa',
    ..._lostWords,
    ..._purposeWords,
    ..._errorWords,
    ..._moreWords,
  };
  static final _lostPhrase = RegExp(
    r'\b(perdi|perdido|perdida|no se que hacer|que hago|no entiendo)\b',
  );
  static final _purposePhrase = RegExp(r'\b(para que sirve|esta pantalla)\b');
  static final _morePhrase = RegExp(r'\b(que mas|opciones)\b');
  static final _definePhrase = RegExp(
    r'\b(que (es|son|significa)|significa|para que sirve)\b',
  );

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

  GuideAnswer _reply(_Entry entry, _Query query) {
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
    return GuideAnswer(buffer.toString().trimRight(), _followUps(entry, query));
  }

  List<String> _followUps(_Entry answered, _Query query) {
    final chips = <String>[];
    void add(String chip) {
      if (chip != answered.chip && !chips.contains(chip)) chips.add(chip);
    }

    for (final e in _ranked(query).skip(1).take(6)) {
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

  _Entry? _best(_Query query, {bool termsOnly = false}) {
    final ranked = _ranked(query, termsOnly: termsOnly);
    return ranked.isEmpty ? null : ranked.first;
  }

  List<_Entry> _ranked(_Query query, {bool termsOnly = false}) {
    final stems = {for (final w in query) ...w};
    final scored = <(_Entry, double, bool, int)>[];
    for (final e in _knowledge.entries) {
      if (termsOnly && e.kind != _Kind.term) continue;
      var score = 0.0;
      var titleHits = 0;
      for (final s in stems) {
        final idf = _knowledge.idf(s);
        if (e.titleStems.contains(s)) {
          score += 3 * idf;
          titleHits++;
        } else if (!termsOnly && e.bodyStems.contains(s)) {
          score += idf;
        }
      }
      if (score < 2.0) continue;
      // The matched words must cover at least half of the question.
      final matchedWords = query
          .where(
            (w) => w.any(
              (s) =>
                  e.titleStems.contains(s) ||
                  (!termsOnly && e.bodyStems.contains(s)),
            ),
          )
          .length;
      if (termsOnly) {
        // A definition lookup needs every non-generic word to hit the term.
        final missed = [
          for (final w in query)
            if (!w.any(e.titleStems.contains)) w,
        ];
        // A missed word is tolerated only when it names an action of this
        // screen ("para qué sirve medir ambientes"), never a foreign topic.
        final own = {
          for (final o in _knowledge.entries)
            if (o.screen == screen) ...o.titleStems,
        };
        if (missed.any(
          (w) => !w.every((s) => _genericStems.contains(s) || own.contains(s)),
        )) {
          continue;
        }
      } else if (query.length == 2) {
        // Both words must match; a generic domain word may be skipped only
        // when the other one matches.
        final unmatched = [
          for (final w in query)
            if (!w.any(
              (s) =>
                  e.titleStems.contains(s) ||
                  (!termsOnly && e.bodyStems.contains(s)),
            ))
              w,
        ];
        if (unmatched.any((w) => !w.every(_genericStems.contains))) continue;
      } else if (query.length >= 2 && matchedWords * 2 < query.length) {
        continue;
      }
      if (e.titleStems.isNotEmpty) {
        score *= 1 + 0.5 * titleHits / e.titleStems.length;
      }
      final isOwn =
          e.screen == screen ||
          (e.kind == _Kind.term &&
              guideGlossary(screen).any((t) => t.term == e.title));
      scored.add((
        e,
        isOwn ? score * 1.4 : score,
        e.screen == screen,
        titleHits,
      ));
    }
    // Ties: the current screen first, then relevance, then content order.
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      if (a.$3 != b.$3) return a.$3 ? -1 : 1;
      final byHits = b.$4.compareTo(a.$4);
      return byHits != 0 ? byHits : a.$1.order.compareTo(b.$1.order);
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

/// The canonical stems of every word of a question: one list per word.
typedef _Query = List<List<String>>;

/// Light stemming: the first four letters absorb verb and plural endings. The
/// "cont" family (contraseña, contorno, controlá, continuar) needs six letters
/// to stay apart.
String _stem(String word) {
  if (word.length <= 4) return word;
  if (word.startsWith('cont')) {
    return word.substring(0, math.min(6, word.length));
  }
  return word.substring(0, 4);
}

/// Synonym groups: every word of a group stands for the listed stems.
const _synonymGroups = <(List<String>, List<String>)>[
  (
    [
      'entrar', 'entro', 'entras', 'entra', 'entran', 'entrando', 'ingresar',
      'ingreso', 'ingresas', 'ingresa', 'ingresando', 'acceder', 'acceso',
      'accedo', 'accedes', 'accede', 'loguear', 'logueo', 'loguearme',
      'loguearse', 'logear', 'logeo', 'login', 'iniciar', 'inicia', 'sesion',
      'sesiones', //
    ],
    ['login'],
  ),
  (
    [
      'publicar', 'publico', 'publica', 'publicas', 'publicando', 'publicado',
      'publicarlo', 'publicacion', //
    ],
    ['envi', 'revi'],
  ),
  // "subir" is both "upload a photo" and "submit for review".
  (['subir', 'subo', 'sube', 'subes', 'subirlo'], ['envi', 'agre']),
  (
    ['crear', 'creo', 'creas', 'crea', 'creando', 'creamos', 'creado'],
    ['crea'],
  ),
  (
    [
      'borrar', 'borro', 'borras', 'borra', 'borrando', 'eliminar', 'elimino',
      'eliminas', 'elimina', 'eliminando', //
    ],
    ['elim'],
  ),
  (['abrir', 'abro', 'abres', 'abre', 'abriendo'], ['abri']),
  (['tocar', 'toco', 'tocas', 'toca', 'tocando'], ['toca']),
  (['leer', 'leo', 'lees', 'lee', 'leyendo'], ['leer']),
  (['pedir', 'pido', 'pides', 'pide'], ['pedi']),
  (['ver', 'veo', 'ves', 'viendo'], ['ver']),
  (
    [
      'habitacion', 'habitaciones', 'cuarto', 'cuartos', 'pieza', 'piezas',
      'dormitorio', 'dormitorios', //
    ],
    ['ambi'],
  ),
  (['mido', 'mides', 'mide', 'midiendo', 'midan'], ['medi']),
  (
    [
      'cerrar', 'cierro', 'cierra', 'cierras', 'cierre', 'cerrando', 'cerrarla',
      'cerrado', //
    ],
    ['cerr'],
  ),
  (['incorrecta', 'incorrecto', 'incorrectas', 'incorrectos'], ['corr']),
  (['imagen', 'imagenes'], ['foto']),
  (['totp', 'verificacion', 'autenticador', 'autenticacion'], ['codi']),
  (['clave', 'claves', 'password', 'pass', 'pwd'], ['contra']),
  (['salgo', 'salgas', 'salimos'], ['sali']),
];

final _synonyms = <String, List<String>>{
  for (final (words, stems) in _synonymGroups)
    for (final w in words) w: stems,
};

/// Canonical stems of [word]: its synonym concept, or its light stem.
List<String> _canon(String word) => _synonyms[word] ?? [_stem(word)];

Set<String> _stems(String text) => {
  for (final t in _tokens(guideNormalize(text))) ..._canon(t),
};

/// Generic domain stems that may be left unmatched in a two-word question.
const _genericStems = <String>{'inmu', 'pant'};

/// 0 when equal, 1 when [a] and [b] differ by one edit, else 2.
int _editDistanceUpTo1(String a, String b) {
  if ((a.length - b.length).abs() > 1) return 2;
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  if (i == a.length && i == b.length) return 0;
  final restA = a.substring(i);
  final restB = b.substring(i);
  if (restA.length == restB.length) {
    return restA.substring(1) == restB.substring(1) ? 1 : 2;
  }
  return restA.length > restB.length
      ? (restA.substring(1) == restB ? 1 : 2)
      : (restB.substring(1) == restA ? 1 : 2);
}

/// Corrects typos: a word of five or more letters that is unknown becomes the
/// known word at edit distance one, if any (alphabetical order on ties).
List<String> _fuzzy(List<String> words) => [
  for (final w in words)
    if (w.length < 5 || _knowledge.known.contains(w))
      w
    else
      _knowledge.vocabulary.firstWhere(
        (v) => _editDistanceUpTo1(w, v) == 1,
        orElse: () => w,
      ),
];

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
       bodyStems = _stems(body),
       rawBody = body;

  final _Kind kind;
  final GuideScreen? screen;
  final String title;
  final String answer;
  final String chip;
  final int order;
  final Set<String> titleStems;
  final Set<String> bodyStems;
  final String rawBody;
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
    final words = <String>{};
    for (final e in entries) {
      for (final s in {...e.titleStems, ...e.bodyStems}) {
        _df[s] = (_df[s] ?? 0) + 1;
      }
      for (final t in _tokens(guideNormalize('${e.title} ${e.rawBody}'))) {
        if (t.length >= 5) words.add(t);
      }
    }
    words.addAll(_synonyms.keys.where((k) => k.length >= 5));
    known = words;
    vocabulary = words.toList()..sort();
  }

  final entries = <_Entry>[];
  final _df = <String, int>{};

  /// Every word of five or more letters of the guide, and the synonym words.
  late final Set<String> known;
  late final List<String> vocabulary;

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
