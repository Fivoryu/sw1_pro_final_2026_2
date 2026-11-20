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
  test('login wording reaches «Entrar a tu cuenta», not «Cerrar sesión»', () {
    for (final q in [
      '¿cómo inicio sesión?',
      'ingresar',
      'iniciar sesión',
      'cómo accedo a mi cuenta',
      'quiero entrar',
    ]) {
      final r = _assistant.answer(q, GuideScreen.catalog);
      expect(r.text, contains('Entrar a tu cuenta'), reason: q);
      expect(r.text, isNot(contains('«Cerrar sesión»')), reason: q);
    }
    final out = _assistant.answer('cerrar sesión', GuideScreen.catalog);
    expect(out.text, contains('«Cerrar sesión»'));
    expect(out.text, isNot(contains('Entrar a tu cuenta')));
  });

  test('payment and cost wording use synonyms', () {
    final pay = _assistant.answer('¿cómo pago?', GuideScreen.reservations);
    expect(pay.text, contains('Confirmar el depósito de prueba'));
    final cost = _assistant.answer('cuánto cuesta', GuideScreen.quote);
    expect(cost.text, contains('Calcular el costo total'));
  });

  test('light typos are tolerated for words of 5+ letters', () {
    final r = _assistant.answer('resevar', GuideScreen.catalog);
    expect(r.text, isNot(contains('no estoy seguro')));
    expect(r.text.toLowerCase(), contains('reserva'));
  });

  test('ties are not resolved by enum order (welcome tour)', () {
    final r = _assistant.answer('¿cómo reservo?', GuideScreen.catalog);
    expect(r.text, isNot(contains('Recorrido completo')));
    expect(r.text, contains('«Reservar un inmueble'));
  });

  test('a partial match with mostly unmatched words falls back honestly', () {
    final r = _assistant.answer(
      'reservar helicoptero submarino',
      GuideScreen.catalog,
    );
    expect(r.text, contains('no estoy seguro'));
  });

  test('action questions about starting a reservation pick the start flow', () {
    for (final q in [
      '¿cómo reservo?',
      'quiero reservar',
      'cómo hago una reserva',
    ]) {
      final r = _assistant.answer(q, GuideScreen.catalog);
      expect(r.text, contains('«Reservar un inmueble'), reason: q);
      expect(r.text, isNot(contains('«Seguir una reserva»')), reason: q);
    }
  });

  test('other action questions still resolve to their own steps', () {
    final cancel = _assistant.answer(
      'cómo cancelo una reserva',
      GuideScreen.catalog,
    );
    expect(cancel.text, contains('«Cancelar una solicitud»'));
    final quote = _assistant.answer('cómo cotizo', GuideScreen.catalog);
    expect(quote.text, contains('Calcular cotización'));
  });

  test('two-word questions need both words covered', () {
    final r = _assistant.answer('borrar reseña', GuideScreen.catalog);
    expect(r.text, contains('no estoy seguro'));
    expect(
      _assistant.answer('cerrar sesión', GuideScreen.catalog).text,
      contains('«Cerrar sesión»'),
    );
    expect(
      _assistant.answer('cómo reservo', GuideScreen.catalog).text,
      isNot(contains('no estoy seguro')),
    );
    expect(
      _assistant.answer('qué es escrow', GuideScreen.catalog).text,
      isNot(contains('no estoy seguro')),
    );
  });
}
