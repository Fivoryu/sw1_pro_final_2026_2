import 'package:cliente_mobile/data/services/customer_auth_api.dart';
import 'package:cliente_mobile/domain/customer_session_controller.dart';
import 'package:cliente_mobile/ui/features/auth/views/customer_account_screen.dart';
import 'package:cliente_mobile/ui/features/chat/chat_conversations_screen.dart';
import 'package:cliente_mobile/ui/features/guide/guide_content.dart';
import 'package:cliente_mobile/ui/features/reservations/customer_reservations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_backend.dart';
import 'support/fake_customer_backend.dart';

const _help = ValueKey('guide-help-button');

CustomerSessionController _session() => CustomerSessionController(
  api: CustomerAuthApi(
    baseUrl: 'https://api.example.test',
    client: FakeCustomerBackend().client,
  ),
  tokenStore: InMemoryCustomerTokenStore(null),
);

Future<void> _openGuide(WidgetTester tester) async {
  await tester.tap(find.byKey(_help));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.byKey(const ValueKey('guide-sheet')), findsOneWidget);
  // The sheet now opens as a chat; the structured guide is one tap away.
  await tester.tap(find.byKey(const ValueKey('guide-full-toggle')));
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('Para qué sirve'), findsOneWidget);
  expect(find.text('Paso a paso'), findsOneWidget);
  expect(find.text('Errores comunes'), findsOneWidget);
  expect(find.text('Glosario'), findsOneWidget);
}

void main() {
  testWidgets('account guide opens and does not submit the form', (
    tester,
  ) async {
    final controller = _session();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CustomerAccountScreen(controller: controller)),
      ),
    );
    await tester.pump();
    await _openGuide(tester);
    expect(controller.message, isNull);
    expect(find.byKey(const ValueKey('account-message')), findsNothing);
  });

  testWidgets('reservations guide opens', (tester) async {
    final session = _session();
    await session.restore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerReservationsScreen(
            controller: null,
            sessionController: session,
          ),
        ),
      ),
    );
    await tester.pump();
    await _openGuide(tester);
  });

  testWidgets('chat list guide opens without opening a conversation', (
    tester,
  ) async {
    final backend = FakeChatBackend()..add('agency', 'Hola cliente');
    await tester.pumpWidget(
      MaterialApp(home: ChatConversationsScreen(api: backend.api)),
    );
    await tester.pump();
    await tester.pump();
    await _openGuide(tester);
    expect(find.text('Hola cliente'), findsNothing);
    expect(
      find.text(GuideContent.forScreen(GuideScreen.chats).goal),
      findsOneWidget,
    );
  });
}
