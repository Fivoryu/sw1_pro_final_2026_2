import 'package:cliente_mobile/ui/features/guide/guide_content.dart';
import 'package:cliente_mobile/ui/features/guide/guide_help_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openChat(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: GuideHelpButton(screen: GuideScreen.catalog)),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('guide-help-button')));
  await tester.pumpAndSettle();
}

Future<void> ask(WidgetTester tester, String question) async {
  await tester.enterText(
    find.byKey(const ValueKey('guide-chat-input')),
    question,
  );
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pumpAndSettle();
}

void main() {
  for (final (choice, expected) in [
    ('Iniciar una reserva', 'tarjeta del inmueble'),
    ('Consultar mis reservas', 'pestaña «Reservas»'),
  ]) {
    testWidgets('reserva asks before choosing: $choice', (tester) async {
      await openChat(tester);
      await ask(tester, 'reserva');
      expect(
        find.text('¿Querés iniciar una o consultar una que ya hiciste?'),
        findsOneWidget,
      );
      final chip = find.widgetWithText(ActionChip, choice);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.textContaining(expected), findsOneWidget);
      expect(
        find.text('Llevame'),
        findsNothing,
      ); // No navigator supplied by this host.
    });
  }

  testWidgets('payment follows the reservation only in this conversation', (
    tester,
  ) async {
    await openChat(tester);
    await ask(tester, '¿Cómo reservo este inmueble?');
    expect(find.textContaining('«Explorar»'), findsOneWidget);
    await ask(tester, '¿y cómo pago?');
    expect(find.textContaining('BOB o USD'), findsOneWidget);
    expect(find.textContaining('wallet vinculada'), findsOneWidget);
    expect(find.textContaining('sin elegir un medio'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await openChat(tester);
    await ask(tester, '¿y cómo pago?');
    expect(find.textContaining('sin elegir un medio'), findsNothing);
    expect(find.textContaining('Seguí estos pasos'), findsOneWidget);
  });
}
