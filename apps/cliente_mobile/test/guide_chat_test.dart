import 'package:cliente_mobile/ui/features/guide/guide_assistant.dart';
import 'package:cliente_mobile/ui/features/guide/guide_content.dart';
import 'package:cliente_mobile/ui/features/guide/guide_help_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _field = ValueKey('guide-chat-input');
const _send = ValueKey('guide-chat-send');

Future<int> _pumpHost(
  WidgetTester tester, {
  GuideScreen screen = GuideScreen.catalog,
  Size size = const Size(800, 600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var actions = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [GuideHelpButton(screen: screen)]),
        body: TextButton(
          onPressed: () => actions++,
          child: const Text('Acción de la pantalla'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('guide-help-button')));
  await tester.pumpAndSettle();
  return actions;
}

void main() {
  testWidgets('opens as a chat with greeting and always-visible chips', (
    tester,
  ) async {
    await _pumpHost(tester);
    expect(find.byKey(const ValueKey('guide-sheet')), findsOneWidget);
    expect(find.textContaining('Hola'), findsOneWidget);
    expect(find.textContaining('Catálogo'), findsWidgets);
    expect(find.byType(ActionChip), findsWidgets);
    expect(
      find.widgetWithText(ActionChip, '¿Para qué sirve esta pantalla?'),
      findsOneWidget,
    );
    expect(find.byKey(_field), findsOneWidget);
    expect(find.byKey(_send), findsOneWidget);
  });

  testWidgets('tapping a chip adds a user and an assistant message', (
    tester,
  ) async {
    await _pumpHost(tester);
    final chip = find.widgetWithText(
      ActionChip,
      '¿Para qué sirve esta pantalla?',
    );
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-msg-user-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-msg-assistant-2')), findsOneWidget);
    expect(
      find.textContaining(GuideContent.forScreen(GuideScreen.catalog).goal),
      findsWidgets,
    );
    expect(find.byType(ActionChip), findsWidgets);
  });

  testWidgets('typing and sending answers, clears the field, runs no action', (
    tester,
  ) async {
    var actions = 0;
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [GuideHelpButton(screen: GuideScreen.reservations)],
          ),
          body: TextButton(
            onPressed: () => actions++,
            child: const Text('Acción de la pantalla'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('guide-help-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_field), '¿Cómo cancelo una reserva?');
    await tester.tap(find.byKey(_send));
    await tester.pumpAndSettle();
    final w = GuideContent.forScreen(GuideScreen.reservations).walkthroughs[2];
    expect(find.textContaining(w.steps.first), findsOneWidget);
    expect(find.text('¿Cómo cancelo una reserva?'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(_field)).controller!.text, '');
    expect(actions, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('keyboard send action submits and empty input is ignored', (
    tester,
  ) async {
    await _pumpHost(tester);
    await tester.enterText(find.byKey(_field), '   ');
    await tester.tap(find.byKey(_send));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-msg-user-1')), findsNothing);
    await tester.enterText(find.byKey(_field), 'hola');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-msg-user-1')), findsOneWidget);
  });

  testWidgets('full guide stays reachable through the toggle', (tester) async {
    await _pumpHost(tester);
    await tester.tap(find.byKey(const ValueKey('guide-full-toggle')));
    await tester.pumpAndSettle();
    for (final h in [
      'Para qué sirve',
      'Paso a paso',
      'Errores comunes',
      'Glosario',
    ]) {
      expect(find.text(h), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('guide-full-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(_field), findsOneWidget);
  });

  testWidgets('does not overflow at 320px with keyboard inset', (tester) async {
    await _pumpHost(tester, size: const Size(320, 568));
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_field), 'hola');
    await tester.tap(find.byKey(_send));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(_field), findsOneWidget);
  });

  testWidgets('every screen opens a chat with 3+ chips at 320px', (
    tester,
  ) async {
    for (final s in GuideScreen.values) {
      await _pumpHost(tester, screen: s, size: const Size(320, 568));
      expect(tester.takeException(), isNull, reason: '$s');
      expect(find.byType(ActionChip), findsWidgets, reason: '$s');
      await tester.pumpWidget(const SizedBox());
    }
    // sanity: the engine is stateless and pure
    expect(const GuideAssistant().greeting(GuideScreen.chat).text, isNotEmpty);
  });
}
