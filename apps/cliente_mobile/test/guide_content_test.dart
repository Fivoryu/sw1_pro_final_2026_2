import 'package:cliente_mobile/ui/features/guide/guide_assistant.dart';
import 'package:cliente_mobile/ui/features/guide/guide_content.dart';
import 'package:flutter_test/flutter_test.dart';

const _englishWords = [
  'click',
  'button',
  'login',
  'log in',
  'sign in',
  'sign up',
  'password',
  'submit',
  'cancel',
  'settings',
  'loading',
  'please',
  'next',
  'back',
  'search',
  'filter',
  'filters',
  'tap',
  'select',
  'the',
  'and',
  'your',
];

List<String> _allText(GuideContent c) => [
  c.title,
  c.goal,
  for (final w in c.walkthroughs) ...[w.name, ...w.steps],
  ...c.mistakes,
];

void main() {
  test('every screen has purpose, walkthroughs of 3+ steps and mistakes', () {
    for (final screen in GuideScreen.values) {
      final c = GuideContent.forScreen(screen);
      expect(c.title.trim(), isNotEmpty, reason: '$screen title');
      expect(c.goal.trim(), isNotEmpty, reason: '$screen goal');
      expect(c.walkthroughs, isNotEmpty, reason: '$screen walkthroughs');
      for (final w in c.walkthroughs) {
        expect(w.name.trim(), isNotEmpty, reason: '$screen walkthrough name');
        expect(
          w.steps.length,
          greaterThanOrEqualTo(3),
          reason: '$screen ${w.name}',
        );
      }
      expect(c.mistakes, isNotEmpty, reason: '$screen mistakes');
    }
  });

  test('covers the main screens of the client app', () {
    expect(
      GuideScreen.values.map((s) => s.name),
      containsAll([
        'welcome',
        'catalog',
        'filters',
        'listingDetail',
        'viewer',
        'quote',
        'reviews',
        'reservations',
        'account',
        'chats',
        'chat',
        'notifications',
      ]),
    );
  });

  test('glossary defines the domain terms', () {
    final terms = GuideContent.glossary
        .map((t) => t.term.toLowerCase())
        .toList();
    for (final needed in [
      'inmueble',
      'cotización',
      'moneda de visualización',
      'reserva',
      'depósito en garantía',
      'token de prueba',
      'recorrido 3d',
      'wallet',
    ]) {
      expect(terms.any((t) => t.contains(needed)), isTrue, reason: needed);
    }
    for (final t in GuideContent.glossary) {
      expect(t.definition.trim(), isNotEmpty, reason: t.term);
    }
  });

  test('guide text is Spanish (no English UI words)', () {
    final texts = <String>[
      for (final s in GuideScreen.values)
        ..._allText(GuideContent.forScreen(s)),
      for (final t in GuideContent.glossary) ...[t.term, t.definition],
    ];
    for (final text in texts) {
      final lower = ' ${text.toLowerCase()} ';
      for (final word in _englishWords) {
        expect(
          RegExp('\b$word\b').hasMatch(lower),
          isFalse,
          reason: '"$text" contains "$word"',
        );
      }
    }
  });
  test('quote guidance matches the real labels of the flow', () {
    final detail = _allText(
      GuideContent.forScreen(GuideScreen.listingDetail),
    ).join('\n');
    final welcome = _allText(
      GuideContent.forScreen(GuideScreen.welcome),
    ).join('\n');
    expect(detail, contains('Calcular cotización'));
    expect(welcome, contains('Calcular cotización'));
    expect(welcome, isNot(contains('Tocá «Cotizar» ')));
    final reach = GuideAssistant.reachFor(GuideScreen.quote);
    expect(reach, contains('Cotizar este inmueble'));
    expect(reach, isNot(contains('«Cotizar»')));
  });

  test('«Tu calificación» is never presented as a button', () {
    for (final s in GuideScreen.values) {
      final text = _allText(GuideContent.forScreen(s)).join('\n');
      expect(text, isNot(contains('Abrí «Tu calificación»')), reason: '$s');
    }
    final reviews = _allText(
      GuideContent.forScreen(GuideScreen.reviews),
    ).join('\n');
    expect(reviews, contains('«Calificar»'));
  });

  test('account guide states the 8-character password and real toggle', () {
    final text = _allText(GuideContent.forScreen(GuideScreen.account));
    final all = text.join('\n');
    expect(all, contains('8 caracteres'));
    expect(all, contains('No tengo cuenta: registrarme'));
    expect(
      GuideContent.forScreen(GuideScreen.account).mistakes.join(' '),
      contains('8 caracteres'),
    );
  });

  test('catalog help does not promise an «Entendido» that chat lacks', () {
    final w = GuideContent.forScreen(GuideScreen.catalog).walkthroughs[2];
    expect(w.steps.last, contains('Ver guía completa'));
  });
}
