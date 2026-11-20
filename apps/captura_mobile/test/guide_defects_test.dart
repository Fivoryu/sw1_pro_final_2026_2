import 'package:captura_mobile/ui/guide/guide_assistant.dart';
import 'package:captura_mobile/ui/guide/guide_content.dart';
import 'package:flutter_test/flutter_test.dart';

GuideAnswer ask(GuideScreen screen, String question) =>
    GuideAssistant(screen).answer(question);

void expectHeader(GuideAnswer a, String title) {
  expect(a.text, startsWith('Para «$title»:\n1. '));
}

void expectFallback(GuideAnswer a) {
  expect(a.text, startsWith('Por ahora no estoy seguro'));
}

void main() {
  group('verb forms reach the same walkthrough', () {
    test('create: creo / creas / crear / crea', () {
      for (final q in [
        '¿cómo creo un inmueble?',
        'cómo creas un inmueble',
        'cómo crear un inmueble',
        'cómo crea un inmueble',
        'quiero crear un inmueble',
      ]) {
        expectHeader(
          ask(GuideScreen.listingsList, q),
          'Crear un inmueble nuevo',
        );
      }
    });

    test('create keeps working with the long form', () {
      expectHeader(
        ask(GuideScreen.listingsList, '¿cómo creo un inmueble nuevo?'),
        'Crear un inmueble nuevo',
      );
    });

    test('first person of other guide verbs', () {
      final cases = <(GuideScreen, String, String)>[
        (GuideScreen.listingEditor, 'cómo agrego fotos', 'Agregar fotos'),
        (
          GuideScreen.listingsList,
          'cómo envío un inmueble a revisión',
          'Enviar un inmueble a revisión',
        ),
        (
          GuideScreen.spatialCapture,
          'cómo mido un ambiente',
          'Medir un ambiente nuevo',
        ),
        (
          GuideScreen.reviews,
          'cómo respondo una reseña',
          'Responder una reseña',
        ),
        (GuideScreen.access, 'cómo cierro sesión', 'Cerrar sesión'),
      ];
      for (final (screen, q, title) in cases) {
        expectHeader(ask(screen, q), title);
      }
    });
  });

  group('subir', () {
    test('subo / subir + foto reaches Agregar fotos', () {
      for (final q in [
        'cómo subo una foto',
        'subir foto',
        'quiero subir fotos',
      ]) {
        final a = ask(GuideScreen.listingEditor, q);
        expectHeader(a, 'Agregar fotos');
        expect(a.text, isNot(contains('otra pantalla')));
      }
    });

    test('subir a revisión keeps the send-to-review flow', () {
      final a = ask(
        GuideScreen.listingsList,
        'cómo subo un inmueble a revisión',
      );
      expectHeader(a, 'Enviar un inmueble a revisión');
    });
  });

  group('borrar vs borrador', () {
    test('delete questions never return the Borrador definition', () {
      for (final q in [
        'cómo borro un inmueble',
        'quiero borrar un inmueble',
        'cómo elimino un inmueble',
      ]) {
        final a = ask(GuideScreen.listingsList, q);
        expect(a.text, isNot(startsWith('«Borrador»')));
        expectFallback(a);
      }
    });

    test('the Borrador definition still works', () {
      final a = ask(GuideScreen.listingsList, 'qué es un borrador');
      expect(a.text, startsWith('«Borrador»:'));
    });
  });

  group('definition lookups need every content word', () {
    test('half-matched definition falls back', () {
      expectFallback(
        ask(GuideScreen.listingsList, 'qué significa borrar reseña'),
      );
      expectFallback(ask(GuideScreen.listingsList, 'borrar reseña'));
    });

    test('plain definitions keep working', () {
      expect(
        ask(GuideScreen.spatialCapture, 'qué es un ambiente').text,
        startsWith('«Ambiente»:'),
      );
    });
  });

  group('regressions', () {
    test('access intents', () {
      expectHeader(
        ask(GuideScreen.access, 'no puedo entrar'),
        'Iniciar sesión',
      );
      expectHeader(
        ask(GuideScreen.access, 'cómo cierro sesión'),
        'Cerrar sesión',
      );
    });
    test('publish flow', () {
      final a = ask(GuideScreen.listingsList, 'cómo publico');
      expect(a.text, startsWith('Para «'));
    });
  });
}
