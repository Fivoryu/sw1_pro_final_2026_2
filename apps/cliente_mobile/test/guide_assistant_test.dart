import 'package:cliente_mobile/ui/features/guide/guide_assistant.dart';
import 'package:cliente_mobile/ui/features/guide/guide_content.dart';
import 'package:flutter_test/flutter_test.dart';

const _assistant = GuideAssistant();

GuideWalkthrough _walk(GuideScreen s, int i) =>
    GuideContent.forScreen(s).walkthroughs[i];

void main() {
  test('every screen offers at least 3 initial suggestions', () {
    for (final s in GuideScreen.values) {
      final chips = _assistant.initialSuggestions(s);
      expect(chips.length, greaterThanOrEqualTo(3), reason: '$s');
      expect(chips, contains('¿Para qué sirve esta pantalla?'));
      for (final w in GuideContent.forScreen(s).walkthroughs) {
        expect(chips, contains(w.name), reason: '$s ${w.name}');
      }
    }
  });

  test('greeting is Spanish, names the screen and has chips', () {
    final r = _assistant.greeting(GuideScreen.catalog);
    expect(r.text, contains('Hola'));
    expect(r.text, contains('Catálogo'));
    expect(r.suggestions, isNotEmpty);
  });

  test('every suggestion chip of every screen is answered with steps', () {
    for (final s in GuideScreen.values) {
      for (final chip in _assistant.initialSuggestions(s)) {
        final r = _assistant.answer(chip, s);
        expect(r.text.trim(), isNotEmpty, reason: '$s $chip');
        expect(r.text, isNot(contains('no estoy seguro')), reason: '$s $chip');
        expect(r.suggestions.length, inInclusiveRange(2, 4), reason: '$chip');
      }
    }
  });

  test('typical question on the current screen returns its walkthrough', () {
    final r = _assistant.answer(
      '¿Cómo cancelo una reserva?',
      GuideScreen.reservations,
    );
    final w = _walk(GuideScreen.reservations, 2);
    expect(w.name, contains('Cancelar'));
    expect(r.text, contains(w.steps.first));
    expect(r.text, contains('1.'));
    expect(r.suggestions.length, inInclusiveRange(2, 4));
  });

  test('accents, case and punctuation do not matter', () {
    final a = _assistant.answer(
      'COMO FILTRO POR PRECIO???',
      GuideScreen.catalog,
    );
    final b = _assistant.answer('cómo filtro por precio', GuideScreen.catalog);
    expect(a.text, b.text);
    expect(a.text, contains(_walk(GuideScreen.filters, 0).steps.first));
  });

  test('glossary question defines the term', () {
    final r = _assistant.answer('¿Qué es una cotización?', GuideScreen.catalog);
    final def = GuideContent.glossary
        .firstWhere((t) => t.term == 'Cotización')
        .definition;
    expect(r.text, contains(def));
    final r2 = _assistant.answer('que es el escrow', GuideScreen.catalog);
    expect(r2.text, contains('Depósito en garantía'));
  });

  test('question about another screen says where it lives and how to get', () {
    final r = _assistant.answer(
      'quiero vincular mi wallet',
      GuideScreen.catalog,
    );
    expect(r.text, contains('Cuenta'));
    expect(r.text, contains(_walk(GuideScreen.account, 2).steps.first));
    expect(r.text.toLowerCase(), contains('pantalla'));
  });

  test('lost intent summarises the screen and lists chips', () {
    for (final q in [
      'me perdí',
      'ayuda',
      'no sé qué hacer',
      '¿Qué más puedo hacer?',
    ]) {
      final r = _assistant.answer(q, GuideScreen.quote);
      expect(
        r.text,
        contains(GuideContent.forScreen(GuideScreen.quote).goal),
        reason: q,
      );
      expect(r.suggestions.length, inInclusiveRange(2, 4), reason: q);
    }
  });

  test('purpose and mistakes intents', () {
    final p = _assistant.answer(
      '¿Para qué sirve esta pantalla?',
      GuideScreen.chats,
    );
    expect(p.text, contains(GuideContent.forScreen(GuideScreen.chats).goal));
    final m = _assistant.answer('¿Qué errores son comunes?', GuideScreen.chats);
    for (final e in GuideContent.forScreen(GuideScreen.chats).mistakes) {
      expect(m.text, contains(e));
    }
  });

  test('greeting and thanks intents', () {
    expect(
      _assistant.answer('hola', GuideScreen.catalog).text,
      contains('Hola'),
    );
    final t = _assistant.answer('muchas gracias', GuideScreen.catalog);
    expect(t.text.toLowerCase(), contains('de nada'));
    expect(t.suggestions, isNotEmpty);
  });

  test('nonsense falls back with chips and topics, inventing nothing', () {
    final r = _assistant.answer('asdkjh qwpoei zzxx', GuideScreen.catalog);
    expect(r.text, contains('no estoy seguro'));
    expect(r.suggestions.length, inInclusiveRange(2, 4));
    expect(r.text, contains(_walk(GuideScreen.catalog, 0).name));
    final empty = _assistant.answer('   ', GuideScreen.catalog);
    expect(empty.text, contains('no estoy seguro'));
  });
}
