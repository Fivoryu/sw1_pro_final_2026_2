import 'package:cliente_mobile/data/models/chat_models.dart';
import 'package:cliente_mobile/data/services/catalog_api.dart';
import 'package:cliente_mobile/data/services/customer_auth_api.dart';
import 'package:cliente_mobile/domain/catalog_controller.dart';
import 'package:cliente_mobile/domain/customer_session_controller.dart';
import 'package:cliente_mobile/ui/features/catalog/views/listing_detail_screen.dart';
import 'package:cliente_mobile/ui/features/chat/chat_conversation_screen.dart';
import 'package:cliente_mobile/ui/features/chat/chat_conversations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_catalog_backend.dart';
import 'support/fake_chat_backend.dart';
import 'support/fake_customer_backend.dart';

Future<void> _pumpConversation(
  WidgetTester tester,
  FakeChatBackend backend, {
  bool readOnly = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChatConversationScreen(
        api: backend.api,
        conversation: ChatConversation.fromJson(
          FakeChatBackend.conversationJson(readOnly: readOnly),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

Future<void> _pumpDetail(
  WidgetTester tester,
  FakeChatBackend chat, {
  required bool signedIn,
}) async {
  final catalog = FakeCatalogBackend()..seed(id: 'listing-1');
  final catalogApi = CatalogApi(
    baseUrl: 'https://api.example.test',
    client: catalog.client,
  );
  final session = CustomerSessionController(
    api: CustomerAuthApi(
      baseUrl: 'https://api.example.test',
      client: FakeCustomerBackend().client,
    ),
    tokenStore: InMemoryCustomerTokenStore(signedIn ? 'stored' : null),
  );
  await tester.runAsync(session.restore);
  await tester.pumpWidget(
    MaterialApp(
      home: ListingDetailScreen(
        controller: CatalogController(api: catalogApi),
        listingId: 'listing-1',
        sessionController: session,
        chatApi: chat.api,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ListingDetailScreen chat button', () {
    testWidgets('opens the conversation when the customer is signed in', (
      tester,
    ) async {
      final chat = FakeChatBackend()..add('agency', 'Bienvenido');
      await _pumpDetail(tester, chat, signedIn: true);

      final button = find.byKey(const ValueKey('detail-open-chat'));
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('property-detail-content')),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('Andina Inmuebles'), findsWidgets);
      expect(find.text('Bienvenido'), findsOneWidget);
      expect(
        chat.requests.first,
        'POST /api/v1/customer/chat/listings/listing-1/conversation',
      );
      await _disposeScreen(tester);
    });

    testWidgets('asks to sign in without calling the API when signed out', (
      tester,
    ) async {
      final chat = FakeChatBackend();
      await _pumpDetail(tester, chat, signedIn: false);

      final button = find.byKey(const ValueKey('detail-open-chat'));
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('property-detail-content')),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat-message')), findsOneWidget);
      expect(find.textContaining('Iniciá sesión'), findsWidgets);
      expect(chat.requests, isEmpty);
    });

    testWidgets('shows a clear message when the agency blocked the customer', (
      tester,
    ) async {
      final chat = FakeChatBackend()..openBlocked = true;
      await _pumpDetail(tester, chat, signedIn: true);

      final button = find.byKey(const ValueKey('detail-open-chat'));
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('property-detail-content')),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(
        find.text('La inmobiliaria no está aceptando mensajes de tu cuenta.'),
        findsOneWidget,
      );
    });

    testWidgets('hides the button when no chat service is configured', (
      tester,
    ) async {
      final catalog = FakeCatalogBackend()..seed(id: 'listing-1');
      await tester.pumpWidget(
        MaterialApp(
          home: ListingDetailScreen(
            controller: CatalogController(
              api: CatalogApi(
                baseUrl: 'https://api.example.test',
                client: catalog.client,
              ),
            ),
            listingId: 'listing-1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('detail-open-chat')), findsNothing);
    });
  });

  group('ChatConversationScreen', () {
    testWidgets('renders customer and agency bubbles without agent identity', (
      tester,
    ) async {
      final backend = FakeChatBackend()
        ..add('customer', 'Hola')
        ..add('agency', 'Buenas tardes');
      await _pumpConversation(tester, backend);

      expect(find.text('Hola'), findsOneWidget);
      expect(find.text('Buenas tardes'), findsOneWidget);
      expect(find.text('Vos'), findsOneWidget);
      // AppBar title plus the agency bubble header.
      expect(find.text('Andina Inmuebles'), findsNWidgets(2));
      await _disposeScreen(tester);
    });

    testWidgets('sends a message and clears the input', (tester) async {
      final backend = FakeChatBackend();
      await _pumpConversation(tester, backend);

      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'Consulta',
      );
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Consulta'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text,
        isEmpty,
      );
      await _disposeScreen(tester);
    });

    testWidgets('keeps the typed text when sending fails on the network', (
      tester,
    ) async {
      final backend = FakeChatBackend();
      await _pumpConversation(tester, backend);
      backend.offline = true;

      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'No perder',
      );
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('chat-error')), findsOneWidget);
      expect(find.text('No perder'), findsOneWidget);
      await _disposeScreen(tester);
    });

    testWidgets('polls every 3 seconds and shows new messages', (tester) async {
      final backend = FakeChatBackend();
      await _pumpConversation(tester, backend);
      expect(find.text('Nuevo'), findsNothing);

      backend.add('agency', 'Nuevo');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('Nuevo'), findsOneWidget);
      await _disposeScreen(tester);
      final calls = backend.requests.length;
      await tester.pump(const Duration(seconds: 10));
      expect(backend.requests.length, calls);
    });

    testWidgets('read-only disables the input and shows the notice', (
      tester,
    ) async {
      final backend = FakeChatBackend()..readOnly = true;
      await _pumpConversation(tester, backend, readOnly: true);

      expect(find.byKey(const ValueKey('chat-read-only')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-input')), findsNothing);
      expect(find.byKey(const ValueKey('chat-send')), findsNothing);
      await _disposeScreen(tester);
    });

    testWidgets('a blocked customer sees a clear message', (tester) async {
      final backend = FakeChatBackend();
      await _pumpConversation(tester, backend);
      backend.blocked = true;

      await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Hola');
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('chat-read-only')), findsOneWidget);
      expect(
        find.text('La inmobiliaria no está aceptando mensajes de tu cuenta.'),
        findsWidgets,
      );
      await _disposeScreen(tester);
    });

    testWidgets('reports the conversation with a reason', (tester) async {
      final backend = FakeChatBackend();
      await _pumpConversation(tester, backend);

      await tester.tap(find.byKey(const ValueKey('chat-report')));
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('chat-report-submit'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('chat-report-reason')),
        'Trato indebido',
      );
      await tester.pump();
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(backend.reports, ['Trato indebido']);
      expect(find.text('Reporte enviado a la inmobiliaria.'), findsOneWidget);
      await _disposeScreen(tester);
    });
  });

  group('ChatConversationsScreen', () {
    testWidgets('lists conversations by agency name and opens one', (
      tester,
    ) async {
      final backend = FakeChatBackend()..add('agency', 'Hola cliente');
      await tester.pumpWidget(
        MaterialApp(home: ChatConversationsScreen(api: backend.api)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Andina Inmuebles'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('conversation-conv-1')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Hola cliente'), findsOneWidget);
      await _disposeScreen(tester);
    });

    testWidgets('shows a network error', (tester) async {
      final backend = FakeChatBackend()..offline = true;
      await tester.pumpWidget(
        MaterialApp(home: ChatConversationsScreen(api: backend.api)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('conversations-error')), findsOneWidget);
    });
  });
}
