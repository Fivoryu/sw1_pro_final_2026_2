import 'package:cliente_mobile/ui/features/guide/guide_assistant.dart';
import 'package:cliente_mobile/ui/features/guide/guide_content.dart';
import 'package:flutter_test/flutter_test.dart';

const _assistant = GuideAssistant();

const _reserveStart =
    'Reservar un inmueble: sumar opcionales y elegir cómo reservar';

String _walkHeader(String name) => '«$name». Seguí estos pasos';

void _expectWalk(String q, GuideScreen screen, String name) {
  final r = _assistant.answer(q, screen);
  expect(r.text, contains(_walkHeader(name)), reason: '$screen «$q»');
}

void main() {
  test('«cómo pago» falls through to the next entry covering both words', () {
    _expectWalk('¿cómo pago?', GuideScreen.catalog, _reserveStart);
    _expectWalk(
      '¿cómo pago?',
      GuideScreen.reservations,
      'Confirmar el depósito de prueba',
    );
    expect(
      _assistant.answer('¿cómo pago?', GuideScreen.listingDetail).text,
      isNot(contains('no estoy seguro')),
    );
  });

  test('logout wording reaches «Cerrar sesión» from another screen', () {
    for (final q in [
      'cómo cierro sesión',
      'cierro mi sesión',
      'quiero salir de mi cuenta',
    ]) {
      _expectWalk(q, GuideScreen.catalog, 'Cerrar sesión');
    }
  });

  test('login wording is still not «Cerrar sesión»', () {
    for (final q in ['cómo entro a mi cuenta', 'iniciar sesión']) {
      final r = _assistant.answer(q, GuideScreen.catalog);
      expect(r.text, contains('Entrar a tu cuenta'), reason: q);
    }
  });

  test('«qué significa X» defines the glossary term', () {
    for (final q in ['¿qué significa wallet?', 'qué quiere decir wallet']) {
      expect(
        _assistant.answer(q, GuideScreen.catalog).text,
        startsWith('«Wallet»:'),
        reason: q,
      );
    }
    for (final q in ['qué significa escrow', 'qué significan escrow']) {
      expect(
        _assistant.answer(q, GuideScreen.catalog).text,
        startsWith('«Depósito en garantía»:'),
        reason: q,
      );
    }
  });

  test('viewing words reach «Seguir una reserva»', () {
    for (final q in [
      'mis reservas',
      'ver mi reserva',
      'estado de mi reserva',
    ]) {
      _expectWalk(q, GuideScreen.catalog, 'Seguir una reserva');
      _expectWalk(q, GuideScreen.reservations, 'Seguir una reserva');
    }
  });

  test('action words reach the start-a-reservation walkthrough', () {
    for (final q in ['¿cómo reservo?', 'quiero reservar', 'hago una reserva']) {
      _expectWalk(q, GuideScreen.reservations, _reserveStart);
      _expectWalk(q, GuideScreen.catalog, _reserveStart);
    }
  });

  test('reservation questions with other topics keep their own answer', () {
    _expectWalk(
      'cómo cancelo una reserva',
      GuideScreen.catalog,
      'Cancelar una solicitud',
    );
    _expectWalk(
      'cancelar mi reserva',
      GuideScreen.reservations,
      'Cancelar una solicitud',
    );
    expect(
      _assistant.answer('borrar reseña', GuideScreen.catalog).text,
      contains('no estoy seguro'),
    );
    expect(
      _assistant
          .answer('reservar helicoptero submarino', GuideScreen.reservations)
          .text,
      contains('no estoy seguro'),
    );
  });
}
