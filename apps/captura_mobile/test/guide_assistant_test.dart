import 'package:captura_mobile/ui/guide/guide_assistant.dart';
import 'package:captura_mobile/ui/guide/guide_content.dart';
import 'package:flutter_test/flutter_test.dart';

GuideAnswer ask(GuideScreen screen, String question) =>
    GuideAssistant(screen).answer(question);

void expectWalkthrough(GuideAnswer a, GuideScreen screen, String title) {
  final w = guideWalkthroughs(screen).firstWhere((w) => w.title == title);
  // The reply is exactly this walkthrough, never a sibling with similar words.
  expect(a.text, contains('Para «${w.title}»:\n1. '));
  for (var i = 0; i < w.steps.length; i++) {
    expect(a.text, contains('${i + 1}. ${w.steps[i]}'));
  }
}

void main() {
  group('GuideAssistant answers', () {
    test('typical questions map to the expected walkthrough', () {
      final cases = <(GuideScreen, String, String)>[
        (
          GuideScreen.listingsList,
          '¿Cómo creo un inmueble nuevo?',
          'Crear un inmueble nuevo',
        ),
        (
          GuideScreen.spatialCapture,
          'cómo envío la escena 3D',
          'Enviar la escena 3D',
        ),
        (GuideScreen.access, 'no puedo iniciar sesión', 'Iniciar sesión'),
        (
          GuideScreen.reviews,
          'cómo respondo una reseña',
          'Responder una reseña',
        ),
        (GuideScreen.listingEditor, 'quiero agregar fotos', 'Agregar fotos'),
        (
          GuideScreen.roomEditor,
          'como corrijo la altura',
          'Corregir la altura',
        ),
      ];
      for (final (screen, question, title) in cases) {
        expectWalkthrough(ask(screen, question), screen, title);
      }
    });

    test('accents, case and punctuation do not change the answer', () {
      final a = ask(GuideScreen.spatialCapture, 'COMO MEDIR UN AMBIENTE???');
      final b = ask(GuideScreen.spatialCapture, 'cómo medir un ambiente');
      expect(a.text, b.text);
      expectWalkthrough(
        a,
        GuideScreen.spatialCapture,
        'Medir un ambiente nuevo',
      );
    });

    test('every walkthrough title answers with its own steps', () {
      for (final screen in GuideScreen.values) {
        for (final w in guideWalkthroughs(screen)) {
          expectWalkthrough(ask(screen, w.title), screen, w.title);
        }
      }
    });

    test('glossary questions return the definition', () {
      final a = ask(GuideScreen.listingsList, '¿qué es un borrador?');
      expect(a.text, contains('Un inmueble que todavía estás completando'));
      final b = ask(GuideScreen.spatialCapture, 'que significa escena');
      expect(b.text, contains('El conjunto de todos los ambientes medidos'));
    });

    test('a question about another screen says where it lives', () {
      final a = ask(GuideScreen.listingsList, 'cómo trazo un plano');
      expect(a.text, contains('pantalla'));
      expect(a.text, contains('Trazado desde un plano'));
      expect(a.text, contains('Para llegar'));
      expectWalkthrough(
        a,
        GuideScreen.floorplanTrace,
        'Trazar un ambiente desde un plano',
      );
    });

    test('nonsense falls back honestly with suggestions and topics', () {
      final a = ask(GuideScreen.listingsList, 'asdfgh qwerty zzz');
      expect(a.text, contains('no estoy seguro'));
      expect(a.text, contains('Crear un inmueble nuevo'));
      expect(a.suggestions.length, greaterThanOrEqualTo(3));
      expect(ask(GuideScreen.listingsList, '   ').text, contains('no estoy'));
    });

    test('greeting, thanks, lost and purpose intents', () {
      for (final screen in GuideScreen.values) {
        final assistant = GuideAssistant(screen);
        expect(assistant.answer('hola').text, contains('Hola'));
        expect(assistant.answer('muchas gracias').text, contains('Con gusto'));
        final lost = assistant.answer('me perdí, no sé qué hacer');
        expect(lost.text, contains(guideTitle(screen)));
        expect(lost.suggestions.length, greaterThanOrEqualTo(3));
        expect(
          assistant.answer('¿Para qué sirve esta pantalla?').text,
          contains(guidePurpose(screen)),
        );
        final more = assistant.answer('¿Qué más puedo hacer?');
        for (final w in guideWalkthroughs(screen)) {
          expect(more.text, contains(w.title));
        }
        final errors = assistant.answer('¿Qué errores son comunes?');
        for (final m in guideMistakes(screen)) {
          expect(errors.text, contains(m.problem));
        }
      }
    });

    test('answers carry 2 to 4 follow-up chips and are deterministic', () {
      for (final screen in GuideScreen.values) {
        final assistant = GuideAssistant(screen);
        for (final w in guideWalkthroughs(screen)) {
          final a = assistant.answer(w.title);
          expect(a.suggestions.length, inInclusiveRange(2, 4));
          expect(a.suggestions.toSet().length, a.suggestions.length);
          expect(assistant.answer(w.title).text, a.text);
        }
      }
    });
  });

  group('GuideAssistant intents do not hijack real questions (J4)', () {
    test('a greeting followed by a question answers the question', () {
      expectWalkthrough(
        ask(GuideScreen.access, 'hola como entro'),
        GuideScreen.access,
        'Iniciar sesión',
      );
      expectWalkthrough(
        ask(GuideScreen.listingsList, 'gracias, cómo publico un inmueble'),
        GuideScreen.listingsList,
        'Enviar un inmueble a revisión',
      );
      expect(ask(GuideScreen.access, 'hola').text, contains('en qué te ayudo'));
    });

    test('lost phrases with a real topic reach the specific answer', () {
      final dark = ask(
        GuideScreen.listingEditor,
        'qué hago con una foto oscura',
      );
      expect(dark.text, contains('Fotos oscuras o movidas'));
      final code = ask(GuideScreen.access, 'perdí el código');
      expect(code.text, isNot(contains('te ubico')));
      expect(code.text, contains('Número temporal'));
      final term = ask(
        GuideScreen.spatialCapture,
        'no entiendo qué es un ambiente',
      );
      expect(term.text, contains('Una habitación o espacio'));
    });

    test('purpose and more phrases with a topic are not hijacked', () {
      final purpose = ask(
        GuideScreen.spatialCapture,
        '¿para qué sirve medir ambientes?',
      );
      expect(purpose.text, isNot(guidePurpose(GuideScreen.spatialCapture)));
      expect(purpose.text, contains('Una habitación o espacio'));
      expectWalkthrough(
        ask(GuideScreen.floorplanTrace, 'cómo salgo de esta pantalla'),
        GuideScreen.floorplanTrace,
        'Salir sin perder trabajo',
      );
    });
  });

  group('GuideAssistant synonyms and typos (J5)', () {
    test('login synonyms resolve to Iniciar sesión', () {
      for (final q in [
        'no puedo entrar',
        'cómo entro',
        'ingreso',
        'quiero acceder',
        'logueo',
      ]) {
        expectWalkthrough(
          ask(GuideScreen.access, q),
          GuideScreen.access,
          'Iniciar sesión',
        );
      }
      expectWalkthrough(
        ask(GuideScreen.access, 'qué veo después de entrar'),
        GuideScreen.access,
        'Después de entrar',
      );
    });

    test('publishing resolves to the review flow and names who publishes', () {
      for (final q in [
        'cómo publico un inmueble',
        'pubicar',
        'subir un inmueble',
      ]) {
        final a = ask(GuideScreen.listingsList, q);
        expectWalkthrough(
          a,
          GuideScreen.listingsList,
          'Enviar un inmueble a revisión',
        );
        expect(a.text, contains('administrador'));
      }
    });

    test('typos, room and measure synonyms', () {
      expect(
        ask(GuideScreen.access, 'contraceña incorrecta').text,
        contains('correo o la contraseña'),
      );
      expectWalkthrough(
        ask(GuideScreen.spatialCapture, 'cómo mido una habitación'),
        GuideScreen.spatialCapture,
        'Medir un ambiente nuevo',
      );
    });

    test('password does not collide with contour or control', () {
      final a = ask(GuideScreen.floorplanTrace, 'cómo controlo la contraseña');
      expect(a.text, isNot(contains('Para «Corregir el contorno')));
      expect(a.text, isNot(contains('Problema frecuente: El contorno')));
    });
  });

  group('GuideAssistant logout and coverage (R2)', () {
    test('logout questions reach Cerrar sesión, not the login steps', () {
      for (final q in [
        'cómo cierro sesión',
        'cierro mi sesión',
        'quiero salir de mi cuenta',
        'cerrar sesión',
      ]) {
        final a = ask(GuideScreen.access, q);
        expectWalkthrough(a, GuideScreen.access, 'Cerrar sesión');
        expect(a.text, isNot(contains('Para «Iniciar sesión»')), reason: q);
      }
      final other = ask(GuideScreen.listingsList, 'cómo cierro sesión');
      expect(other.text, contains('Para «Cerrar sesión»:\n1. '));
    });

    test('login questions still reach Iniciar sesión', () {
      for (final q in ['no puedo entrar', 'iniciar sesión', 'sesión']) {
        expectWalkthrough(
          ask(GuideScreen.access, q),
          GuideScreen.access,
          'Iniciar sesión',
        );
      }
    });

    test('two meaningful words must both match', () {
      final a = ask(GuideScreen.reviews, 'borrar reseña');
      expect(a.text, contains('no estoy seguro'));
      expect(
        ask(GuideScreen.listingsList, 'cómo publico').text,
        contains('Para «Enviar un inmueble a revisión»:\n1. '),
      );
      expect(
        ask(GuideScreen.spatialCapture, 'qué es un ambiente').text,
        contains('Una habitación o espacio'),
      );
    });
  });

  group('GuideAssistant partial matches (J8)', () {
    test('a single weak word out of many falls back honestly', () {
      final a = ask(
        GuideScreen.listingsList,
        'cómo emito una factura electrónica del inmueble',
      );
      expect(a.text, contains('no estoy seguro'));
    });
  });

  group('GuideAssistant opening', () {
    test('greets in Spanish naming the screen and its purpose', () {
      for (final screen in GuideScreen.values) {
        final greeting = GuideAssistant(screen).greeting();
        expect(greeting, contains('Hola'));
        expect(greeting, contains(guideTitle(screen)));
      }
    });

    test('every screen has at least 3 context-aware initial chips', () {
      for (final screen in GuideScreen.values) {
        final chips = GuideAssistant(screen).initialSuggestions();
        expect(chips.length, greaterThanOrEqualTo(3));
        expect(chips, contains('¿Para qué sirve esta pantalla?'));
        expect(chips, contains('¿Qué errores son comunes?'));
        expect(chips, contains('¿Qué más puedo hacer?'));
        for (final w in guideWalkthroughs(screen)) {
          expect(chips, contains(w.title));
        }
      }
    });
  });
}
