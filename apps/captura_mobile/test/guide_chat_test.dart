import 'package:captura_mobile/ui/guide/contextual_guide.dart';
import 'package:captura_mobile/ui/guide/guide_assistant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  GuideScreen screen = GuideScreen.listingsList,
  VoidCallback? onAction,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [ContextualGuideButton(screen: screen)]),
        body: FilledButton(
          key: const ValueKey('screen-action'),
          onPressed: onAction ?? () {},
          child: const Text('Acción'),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('guide-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens as a chat with greeting and suggestion chips', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester);

    expect(find.byKey(const ValueKey('guide-sheet')), findsOneWidget);
    final greeting = GuideAssistant(GuideScreen.listingsList).greeting();
    expect(find.text(greeting), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-send')), findsOneWidget);
    expect(find.text('¿Para qué sirve esta pantalla?'), findsOneWidget);
    expect(find.text('Crear un inmueble nuevo'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('guide-input')),
    );
    expect(field.textInputAction, TextInputAction.send);
  });

  testWidgets('tapping a chip adds a user and an assistant message', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester);

    await tester.tap(find.text('Crear un inmueble nuevo').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guide-user-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-assistant-2')), findsOneWidget);
    final reply = GuideAssistant(
      GuideScreen.listingsList,
    ).answer('Crear un inmueble nuevo').text;
    expect(find.text(reply), findsOneWidget);
    // Suggestions stay visible after the answer.
    expect(find.byType(ActionChip), findsWidgets);
  });

  testWidgets('typing and sending asks, then clears the field', (tester) async {
    await _pump(tester);
    await _open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('guide-input')),
      'cómo agrego fotos',
    );
    await tester.tap(find.byKey(const ValueKey('guide-send')));
    await tester.pumpAndSettle();

    expect(find.text('cómo agrego fotos'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('guide-input')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const ValueKey('guide-assistant-2')), findsOneWidget);

    // Keyboard action also sends; blank input sends nothing.
    await tester.enterText(find.byKey(const ValueKey('guide-input')), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-user-3')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('guide-input')), 'hola');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-user-3')), findsOneWidget);
  });

  testWidgets('the chat never runs a screen action', (tester) async {
    var runs = 0;
    await _pump(tester, onAction: () => runs++);
    await _open(tester);
    await tester.tap(find.text('Crear un inmueble nuevo').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('guide-input')),
      'enviar a revisión',
    );
    await tester.tap(find.byKey(const ValueKey('guide-send')));
    await tester.pumpAndSettle();
    expect(runs, 0);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('full guide toggle shows the structured guide and back', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester);

    await tester.tap(find.byKey(const ValueKey('guide-full-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Para qué sirve'), findsOneWidget);
    expect(find.text('Paso a paso'), findsOneWidget);
    expect(find.text('Errores comunes'), findsOneWidget);
    expect(find.text('Glosario'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-input')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('guide-full-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-input')), findsOneWidget);
  });

  for (final size in [const Size(320, 480), const Size(320, 640)]) {
    testWidgets('no overflow at ${size.width}x${size.height}, with keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, screen: GuideScreen.welcome);
      await _open(tester);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Tu recorrido completo').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('guide-input')), findsOneWidget);
    });
  }

  testWidgets('chat elements have Spanish semantics labels', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await _open(tester);
    expect(find.bySemanticsLabel(RegExp('Enviar pregunta')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Conversación con la guía')),
      findsWidgets,
    );
    handle.dispose();
  });
}
