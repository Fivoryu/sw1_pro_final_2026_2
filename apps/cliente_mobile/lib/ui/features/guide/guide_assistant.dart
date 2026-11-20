import 'dart:math' as math;

import 'guide_content.dart';

/// Answer of the guide assistant: Spanish text plus follow-up suggestions.
class GuideReply {
  const GuideReply(this.text, this.suggestions);

  final String text;
  final List<String> suggestions;
}

/// Pure, deterministic, offline answer engine built only on [GuideContent].
/// It explains; it never performs any action of the app.
class GuideAssistant {
  const GuideAssistant();

  static const purposeChip = '¿Para qué sirve esta pantalla?';
  static const mistakesChip = '¿Qué errores son comunes?';
  static const moreChip = '¿Qué más puedo hacer?';

  static const Map<GuideScreen, String> _labels = {
    GuideScreen.welcome: 'Primeros pasos',
    GuideScreen.catalog: 'Catálogo',
    GuideScreen.filters: 'Filtros del catálogo',
    GuideScreen.listingDetail: 'Detalle del inmueble',
    GuideScreen.viewer: 'Recorrido 3D',
    GuideScreen.quote: 'Cotización',
    GuideScreen.reviews: 'Reseñas',
    GuideScreen.reservations: 'Reservas',
    GuideScreen.account: 'Cuenta',
    GuideScreen.chats: 'Conversaciones',
    GuideScreen.chat: 'Conversación',
    GuideScreen.notifications: 'Notificaciones',
  };

  static const Map<GuideScreen, String> _reach = {
    GuideScreen.welcome:
        'tocá el ícono de brújula que aparece arriba en el Catálogo',
    GuideScreen.catalog: 'tocá la pestaña Catálogo, la primera de abajo',
    GuideScreen.filters: 'en el Catálogo, tocá «Filtrar catálogo»',
    GuideScreen.listingDetail: 'en el Catálogo, tocá la tarjeta de un inmueble',
    GuideScreen.viewer:
        'abrí un inmueble desde el Catálogo y tocá «Recorrer en 3D»',
    GuideScreen.quote:
        'abrí un inmueble desde el Catálogo, tocá «Recorrer en 3D», tocá un '
        'objeto marcado del recorrido y elegí «Cotizar este inmueble» '
        '(en el detalle del inmueble, «Calcular cotización» hace el cálculo '
        'sin salir de esa pantalla)',
    GuideScreen.reviews:
        'abrí un inmueble desde el Catálogo y buscá su sección de reseñas',
    GuideScreen.reservations: 'tocá la pestaña Reservas, abajo',
    GuideScreen.account: 'tocá la pestaña Cuenta, abajo',
    GuideScreen.chats: 'entrá a la pestaña Reservas y abrí tus conversaciones',
    GuideScreen.chat: 'abrí una conversación desde la lista de conversaciones',
    GuideScreen.notifications:
        'tocá la campana de arriba, una vez que hayas entrado a tu cuenta',
  };

  /// How to reach [screen] from elsewhere, in plain words.
  static String reachFor(GuideScreen screen) => _reach[screen]!;

  /// Common novice wording mapped to the words the guide uses.
  static const Map<String, List<String>> _tokenSynonyms = {
    'pago': ['pagar', 'deposito'],
    'pagos': ['pagar', 'deposito'],
    'pagando': ['pagar', 'deposito'],
    'pague': ['pagar', 'deposito'],
    'abonar': ['pagar', 'deposito'],
    'depositar': ['deposito'],
    'cuesta': ['costo'],
    'cuestan': ['costo'],
    'cuanto': ['costo'],
    'cuantos': ['costo'],
    'apartar': ['reservar'],
    'separar': ['reservar'],
    'mostrar': [],
    'mostrame': [],
    'muestra': [],
    'muestrame': [],
    'clave': ['contrasena'],
    'contrasenia': ['contrasena'],
    'password': ['contrasena'],
  };

  static const _loginWords = {
    'iniciar',
    'inicio',
    'inicias',
    'inicia',
    'ingresar',
    'ingreso',
    'ingresas',
    'ingresa',
    'entrar',
    'entro',
    'entras',
    'acceder',
    'accedo',
    'accedes',
    'acceso',
    'loguear',
    'loguearme',
    'logear',
    'logearme',
    'login',
  };
  static const _logoutWords = {
    'cerrar',
    'cierro',
    'cierras',
    'salir',
    'salgo',
    'sales',
    'logout',
    'desloguear',
    'deslogear',
  };

  /// Extra words people use for a glossary term.
  static const Map<String, String> _synonyms = {
    'Inmobiliaria': 'agencia empresa',
    'Depósito en garantía': 'escrow garantia deposito',
    'Wallet': 'billetera monedero',
    'Cotización': 'presupuesto costo',
    'Reserva': 'apartar',
    'Token de prueba': 'ficticio',
    'Recorrido 3D': 'tour virtual',
    'Reseña': 'opinion calificacion',
    'Notificación': 'aviso',
    'Sesión': 'logout',
  };

  static const _stopwords = {
    'de',
    'del',
    'la',
    'las',
    'el',
    'los',
    'un',
    'una',
    'unos',
    'unas',
    'y',
    'o',
    'a',
    'al',
    'en',
    'por',
    'para',
    'con',
    'sin',
    'que',
    'es',
    'son',
    'se',
    'mi',
    'tu',
    'su',
    'me',
    'te',
    'lo',
    'le',
    'como',
    'cual',
    'cuales',
    'donde',
    'cuando',
    'quiero',
    'puedo',
    'puede',
    'hacer',
    'hago',
    'esta',
    'este',
    'esto',
    'esa',
    'ese',
    'estoy',
    'hay',
    'mas',
    'muy',
    'ya',
    'si',
    'no',
    'pantalla',
    'app',
    'aca',
    'aqui',
    'sobre',
    'quisiera',
    'necesito',
    'saber',
    'dime',
    'decime',
    'explicame',
    'ver',
    'puedes',
    'podes',
  };

  static const _greetingWords = {
    'hola',
    'buenas',
    'buenos',
    'buen',
    'dias',
    'tardes',
    'noches',
    'hey',
    'saludos',
  };
  static const _thanksWords = {
    'gracias',
    'muchas',
    'genial',
    'perfecto',
    'excelente',
    'vale',
    'listo',
  };
  static const _lostWords = {
    'perdi',
    'perdido',
    'perdida',
    'ayuda',
    'ayudame',
    'ayudar',
    'entiendo',
    'empiezo',
    'empezar',
  };
  static const _purposeWords = {'sirve', 'sirven', 'trata'};
  static const _mistakeWords = {
    'error',
    'errores',
    'problema',
    'problemas',
    'falla',
    'fallas',
    'fallo',
    'comun',
    'comunes',
    'funciona',
    'mal',
  };

  /// Domain words too generic to require a match (stems).
  static const _genericWords = {'inmue'};

  static final RegExp _lostPhrase = RegExp(
    r'perd|ayuda|no se que hacer|no entiendo|que mas puedo|que puedo hacer|'
    r'que hago|por donde empiezo',
  );
  static final RegExp _purposePhrase = RegExp(
    r'para que sirve|que es esta|donde estoy|de que se trata',
  );
  static final RegExp _definePhrase = RegExp(
    r'que es |que son |que significa|significa |que quiere decir|definicion',
  );

  /// Lowercases, removes accents and punctuation and collapses spaces.
  static String normalize(String text) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    final b = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final c = String.fromCharCode(rune);
      final i = from.indexOf(c);
      if (i >= 0) {
        b.write(to[i]);
      } else if (RegExp(r'[a-z0-9]').hasMatch(c)) {
        b.write(c);
      } else {
        b.write(' ');
      }
    }
    return b.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _stem(String token) {
    var t = token;
    if (t.length > 3 && t.endsWith('s')) t = t.substring(0, t.length - 1);
    return t.length > 5 ? t.substring(0, 5) : t;
  }

  static List<String> _tokens(String normalized) =>
      normalized.isEmpty ? const [] : normalized.split(' ');

  /// Stems of the words that carry meaning (no stopwords).
  static Set<String> _stems(
    String normalized, [
    Set<String> extraDrop = const {},
  ]) => {
    for (final t in _tokens(normalized))
      if (!_stopwords.contains(t) && !extraDrop.contains(t)) _stem(t),
  };

  /// Rewrites novice wording into the words the guide uses. «Iniciar sesión»
  /// and friends mean logging in, which is different from «Cerrar sesión».
  static String _expand(String normalized) {
    final tokens = _tokens(normalized);
    final login =
        tokens.any(_loginWords.contains) && !tokens.any(_logoutWords.contains);
    final out = <String>[];
    for (final t in tokens) {
      if (login && (t == 'sesion' || _loginWords.contains(t))) continue;
      out.addAll(_tokenSynonyms[t] ?? [t]);
    }
    if (login) out.addAll(const ['entrar', 'cuenta']);
    return out.join(' ');
  }

  static bool _withinOneEdit(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0;
    var j = 0;
    var edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length > b.length) {
        i++;
      } else if (a.length < b.length) {
        j++;
      } else {
        i++;
        j++;
      }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }

  /// Replaces unknown stems of words with 5+ letters by the most common known
  /// stem that is one edit away (light typo tolerance).
  static Set<String> _fuzzy(String normalized, Set<String> stems) {
    final out = <String>{};
    final longStems = <String>{
      for (final t in _tokens(normalized))
        if (t.length >= 5 && !_stopwords.contains(t)) _stem(t),
    };
    for (final s in stems) {
      if (_df.containsKey(s) || !longStems.contains(s) || s.length < 4) {
        out.add(s);
        continue;
      }
      final near = [
        for (final k in _df.keys)
          if (_withinOneEdit(s, k)) k,
      ];
      if (near.isEmpty) {
        out.add(s);
      } else {
        // The most common known stem is the likeliest intended word.
        near.sort((x, y) {
          final c = _df[y]!.compareTo(_df[x]!);
          return c != 0 ? c : x.compareTo(y);
        });
        out.add(near.first);
      }
    }
    return out;
  }

  static final List<_Entry> _entries = _buildEntries();

  static final Map<String, int> _df = () {
    final df = <String, int>{};
    for (final e in _entries) {
      for (final t in {...e.name, ...e.body}) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
    return df;
  }();

  static List<_Entry> _buildEntries() {
    final list = <_Entry>[];
    for (final screen in GuideScreen.values) {
      final c = GuideContent.forScreen(screen);
      list.add(
        _Entry(
          kind: _Kind.purpose,
          screen: screen,
          title: c.title,
          name: _stems(normalize(c.title)),
          body: _stems(normalize(c.goal)),
        ),
      );
      for (final w in c.walkthroughs) {
        list.add(
          _Entry(
            kind: _Kind.walkthrough,
            screen: screen,
            title: w.name,
            name: _stems(normalize(w.name)),
            body: _stems(normalize(w.steps.join(' '))),
            walkthrough: w,
          ),
        );
      }
      for (final m in c.mistakes) {
        list.add(
          _Entry(
            kind: _Kind.mistake,
            screen: screen,
            title: m,
            name: const {},
            body: _stems(normalize(m)),
            text: m,
          ),
        );
      }
    }
    for (final t in GuideContent.glossary) {
      list.add(
        _Entry(
          kind: _Kind.term,
          screen: null,
          title: t.term,
          name: _stems(normalize('${t.term} ${_synonyms[t.term] ?? ''}')),
          body: _stems(normalize(t.definition)),
          term: t,
        ),
      );
    }
    return list;
  }

  /// Display name of [screen] for the person.
  static String screenLabel(GuideScreen screen) => _labels[screen]!;

  static String _numbered(List<String> steps) => [
    for (var i = 0; i < steps.length; i++) '${i + 1}. ${steps[i]}',
  ].join('\n');

  /// Initial, context-aware suggestions for [screen].
  List<String> initialSuggestions(GuideScreen screen) {
    final c = GuideContent.forScreen(screen);
    final screenText = <String>{
      ..._stems(normalize(c.title)),
      ..._stems(normalize(c.goal)),
      ..._stems(
        normalize(
          c.walkthroughs.map((w) => '${w.name} ${w.steps.join(' ')}').join(' '),
        ),
      ),
      ..._stems(normalize(c.mistakes.join(' '))),
    };
    final terms = <String>[
      for (final t in GuideContent.glossary)
        if (_stems(normalize(t.term)).every(screenText.contains))
          '¿Qué es ${t.term}?',
    ].take(2);
    return [
      purposeChip,
      for (final w in c.walkthroughs) w.name,
      mistakesChip,
      ...terms,
      moreChip,
    ];
  }

  List<String> _followUps(GuideScreen screen, {Set<String> asked = const {}}) {
    final c = GuideContent.forScreen(screen);
    final candidates = [
      for (final w in c.walkthroughs) w.name,
      mistakesChip,
      purposeChip,
      moreChip,
    ];
    final out = <String>[];
    for (final s in candidates) {
      if (!asked.contains(s) && out.length < 4) out.add(s);
    }
    for (final s in candidates) {
      if (out.length < 2 && !out.contains(s)) out.add(s);
    }
    return out;
  }

  GuideReply greeting(GuideScreen screen) {
    final c = GuideContent.forScreen(screen);
    return GuideReply(
      '¡Hola! Soy la guía de RoomForge. Ahora estás en «${screenLabel(screen)}». '
      '${c.goal}\n\nPodés escribirme una pregunta o tocar una sugerencia. '
      'Yo solo te explico cómo se hace: no hago nada por vos en la pantalla.',
      initialSuggestions(screen),
    );
  }

  GuideReply _purpose(GuideScreen screen) {
    final c = GuideContent.forScreen(screen);
    return GuideReply(
      'En «${screenLabel(screen)}»: ${c.goal}',
      _followUps(screen, asked: {purposeChip}),
    );
  }

  GuideReply _lost(GuideScreen screen) {
    final c = GuideContent.forScreen(screen);
    final topics = c.walkthroughs.map((w) => '• ${w.name}').join('\n');
    return GuideReply(
      'Tranquilo, te ayudo. Estás en «${screenLabel(screen)}». ${c.goal}\n\n'
      'Acá podés aprender a:\n$topics\n\n'
      'Tocá una sugerencia o escribime qué querés hacer.',
      _followUps(screen, asked: {moreChip}),
    );
  }

  GuideReply _mistakes(GuideScreen screen) {
    final c = GuideContent.forScreen(screen);
    return GuideReply(
      'Errores comunes en «${screenLabel(screen)}»:\n'
      '${c.mistakes.map((m) => '• $m').join('\n')}',
      _followUps(screen, asked: {mistakesChip}),
    );
  }

  GuideReply _fallback(GuideScreen screen) {
    final c = GuideContent.forScreen(screen);
    final topics = c.walkthroughs.map((w) => '• ${w.name}').join('\n');
    return GuideReply(
      'Perdoná, no estoy seguro de haber entendido tu pregunta. '
      'En «${screenLabel(screen)}» puedo explicarte:\n$topics\n\n'
      'Probá con otras palabras o tocá una sugerencia.',
      _followUps(screen),
    );
  }

  String _where(GuideScreen current, GuideScreen? other) {
    if (other == null || other == current) return '';
    return 'Eso se hace en otra pantalla: «${screenLabel(other)}». '
        'Para llegar: ${_reach[other]}.\n\n';
  }

  GuideReply _fromEntry(_Entry e, GuideScreen current) {
    final screen = e.screen;
    final where = _where(current, screen);
    switch (e.kind) {
      case _Kind.walkthrough:
        final w = e.walkthrough!;
        return GuideReply(
          '$where«${w.name}». Seguí estos pasos:\n${_numbered(w.steps)}',
          _followUps(
            screen!,
            asked: {w.name},
          ).where((s) => s != w.name).toList(),
        );
      case _Kind.purpose:
        return GuideReply(
          '$where«${screenLabel(screen!)}»: ${GuideContent.forScreen(screen).goal}',
          _followUps(screen, asked: {purposeChip}),
        );
      case _Kind.mistake:
        return GuideReply(
          '$where${e.text}',
          _followUps(screen!, asked: {mistakesChip}),
        );
      case _Kind.term:
        return GuideReply(
          '«${e.term!.term}»: ${e.term!.definition}',
          _followUps(current),
        );
    }
  }

  double _score(_Entry e, Set<String> q, GuideScreen current) {
    var s = 0.0;
    final n = _entries.length;
    for (final t in q) {
      final idf = math.log(1 + n / (_df[t] ?? n));
      if (e.name.contains(t)) {
        s += 3 * idf;
      } else if (e.body.contains(t)) {
        s += idf;
      }
    }
    if (e.screen == current) s *= 1.4;
    if (s > 0) {
      // Tie-breakers: actionable walkthroughs, then walkthroughs that start
      // with the action asked («reservo» → «Reservar…», not «Seguir una
      // reserva»), then more specific names.
      if (e.kind == _Kind.walkthrough) {
        s += 0.02;
        if (e.name.isNotEmpty && q.contains(e.name.first)) s += 0.05;
      }
      if (e.name.isNotEmpty) {
        s += 0.005 * e.name.where(q.contains).length / e.name.length;
      }
    }
    return s;
  }

  /// Meaningful query words found in the entry (name or body).
  int _matched(_Entry e, Set<String> q) =>
      q.where((t) => e.name.contains(t) || e.body.contains(t)).length;

  _Entry? _best(Set<String> q, GuideScreen current, {_Kind? only}) {
    _Entry? best;
    var top = 0.0;
    for (final e in _entries) {
      if (only != null && e.kind != only) continue;
      final s = _score(e, q, current);
      if (s > top) {
        top = s;
        best = e;
      }
    }
    if (best == null || top < 3.0) return null;
    // Honest fallback when most meaningful words are not covered.
    if (q.length == 2) {
      // Both words must be covered; only a generic domain word may be skipped.
      final missing = q.where(
        (t) => !best!.name.contains(t) && !best.body.contains(t),
      );
      if (missing.any((t) => !_genericWords.contains(t))) return null;
    } else if (q.length > 2 && _matched(best, q) * 2 < q.length) {
      return null;
    }
    return best;
  }

  /// Answers [question] asked while the person is on [screen].
  GuideReply answer(String question, GuideScreen screen) {
    final norm = normalize(question);
    if (norm.isEmpty) return _fallback(screen);
    final tokens = _tokens(norm);

    // 1. A suggestion that is exactly a walkthrough name.
    for (final e in _entries) {
      if (e.kind == _Kind.walkthrough && normalize(e.title) == norm) {
        return _fromEntry(e, screen);
      }
    }

    // 2. Social intents.
    final meaningful = tokens.where((t) => !_stopwords.contains(t)).toList();
    if (meaningful.isNotEmpty && meaningful.every(_greetingWords.contains)) {
      return GuideReply(
        '¡Hola! Estás en «${screenLabel(screen)}». ¿Qué querés aprender a hacer acá?',
        _followUps(screen),
      );
    }
    if (meaningful.isNotEmpty && meaningful.every(_thanksWords.contains)) {
      return GuideReply(
        '¡De nada! Si algo no te queda claro, preguntame de nuevo.',
        _followUps(screen),
      );
    }

    bool only(Set<String> intentWords) =>
        meaningful.every(intentWords.contains);

    // 3. Orientation intents (only when nothing else is being asked).
    if (_lostPhrase.hasMatch(norm) &&
        (meaningful.isEmpty || only(_lostWords))) {
      return _lost(screen);
    }
    if (_purposePhrase.hasMatch(norm) &&
        (meaningful.isEmpty || only(_purposeWords))) {
      return _purpose(screen);
    }
    if (meaningful.any(_mistakeWords.contains) && only(_mistakeWords)) {
      return _mistakes(screen);
    }

    final expanded = _expand(norm);
    final q = _fuzzy(
      expanded,
      _stems(expanded, {
        ..._lostWords,
        ..._purposeWords,
        ..._mistakeWords,
        ..._greetingWords,
      }),
    );
    if (q.isEmpty) return _fallback(screen);

    // 4. Glossary questions: "qué es X".
    if (_definePhrase.hasMatch('$norm ')) {
      final term = _best(q, screen, only: _Kind.term);
      if (term != null) return _fromEntry(term, screen);
    }

    // 5. General scoring over the guide of every screen.
    final best = _best(q, screen);
    return best == null ? _fallback(screen) : _fromEntry(best, screen);
  }
}

enum _Kind { purpose, walkthrough, mistake, term }

class _Entry {
  const _Entry({
    required this.kind,
    required this.screen,
    required this.title,
    required this.name,
    required this.body,
    this.walkthrough,
    this.term,
    this.text,
  });

  final _Kind kind;
  final GuideScreen? screen;
  final String title;
  final Set<String> name;
  final Set<String> body;
  final GuideWalkthrough? walkthrough;
  final GuideTerm? term;
  final String? text;
}
