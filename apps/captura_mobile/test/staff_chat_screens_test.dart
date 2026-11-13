import 'package:captura_mobile/data/services/staff_chat_api.dart';
import 'package:captura_mobile/domain/staff_chat_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/ui/chat/chat_conversation_screen.dart';
import 'package:captura_mobile/ui/chat/chat_inbox_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_backend.dart';

Future<({StaffChatApi api, StaffSessionController session})> _pumpInbox(
  WidgetTester tester,
  FakeChatBackend backend, {
  String role = 'agent',
}) async {
  late ({StaffChatApi api, StaffSessionController session}) chat;
  await tester.runAsync(
    () async => chat = await signedInChat(backend, role: role),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: ChatInboxScreen(
        controller: StaffInboxController(api: chat.api, session: chat.session),
        api: chat.api,
        session: chat.session,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return chat;
}

int _inboxRequests(FakeChatBackend backend) => backend.requests
    .where((r) => r.url.path == '/api/v1/staff/chat/conversations')
    .length;

void main() {
  testWidgets('the inbox shows status, badges and customer of each row', (
    tester,
  ) async {
    final backend = FakeChatBackend()
      ..conversations = [
        conversationJson('c1', email: 'ana@example.test'),
        conversationJson(
          'c2',
          email: 'beto@example.test',
          status: 'claimed',
          mine: true,
          readOnly: true,
          needsAdmin: true,
          overdue: true,
        ),
      ];
    await _pumpInbox(tester, backend);

    expect(find.text('ana@example.test'), findsOneWidget);
    expect(find.text('Sin responder'), findsOneWidget);
    expect(find.text('beto@example.test'), findsOneWidget);
    expect(find.text('Mía'), findsOneWidget);
    expect(find.text('Solo lectura'), findsOneWidget);
    expect(find.text('Requiere administrador'), findsOneWidget);
    expect(find.text('Atrasada'), findsOneWidget);
    expect(find.text('Inmueble listing-1'), findsNWidgets(2));
  });

  testWidgets('an empty inbox says so', (tester) async {
    await _pumpInbox(tester, FakeChatBackend());
    expect(find.byKey(const ValueKey('inbox-empty')), findsOneWidget);
  });

  testWidgets('the inbox polls every 15 seconds and stops on dispose', (
    tester,
  ) async {
    final backend = FakeChatBackend();
    await _pumpInbox(tester, backend);
    expect(_inboxRequests(backend), 1);

    await tester.pump(kInboxPollInterval);
    await tester.pumpAndSettle();
    expect(_inboxRequests(backend), 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(kInboxPollInterval * 2);
    expect(_inboxRequests(backend), 2);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    final backend = FakeChatBackend()..offline = true;
    await _pumpInbox(tester, backend);
    expect(find.byKey(const ValueKey('inbox-error')), findsOneWidget);

    backend.offline = false;
    await tester.tap(find.byKey(const ValueKey('inbox-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-empty')), findsOneWidget);
  });

  testWidgets('opening a conversation shows messages aligned by ownership', (
    tester,
  ) async {
    final backend = FakeChatBackend()
      ..conversations = [conversationJson('c1')]
      ..messages = [
        messageJson(1, body: 'Hola, ¿sigue disponible?'),
        messageJson(2, sender: 'agent', mine: true, body: 'Sí, claro'),
      ];
    await _pumpInbox(tester, backend);

    await tester.tap(find.byKey(const ValueKey('conversation-c1')));
    await tester.pumpAndSettle();

    expect(find.text('Hola, ¿sigue disponible?'), findsOneWidget);
    final theirs = tester.getTopLeft(find.byKey(const ValueKey('message-1')));
    final mine = tester.getTopRight(find.byKey(const ValueKey('message-2')));
    expect(mine.dx, greaterThan(theirs.dx + 100));
    // Agents never see authors, and have no admin actions.
    expect(find.byKey(const ValueKey('message-author-2')), findsNothing);
    expect(find.byKey(const ValueKey('reassign-action')), findsNothing);
  });

  testWidgets('sending appends the message and claims the conversation', (
    tester,
  ) async {
    final backend = FakeChatBackend()..conversations = [conversationJson('c1')];
    await _pumpInbox(tester, backend);
    await tester.tap(find.byKey(const ValueKey('conversation-c1')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('conversation-input')),
      'Buenas tardes',
    );
    await tester.tap(find.byKey(const ValueKey('conversation-send')));
    await tester.pumpAndSettle();

    expect(find.text('Buenas tardes'), findsOneWidget);
    expect(backend.sentBodies.single, {'body': 'Buenas tardes'});
  });

  testWidgets('conversation polling appends new messages every 3 seconds', (
    tester,
  ) async {
    final backend = FakeChatBackend()
      ..conversations = [conversationJson('c1')]
      ..messages = [messageJson(1, body: 'Primero')];
    await _pumpInbox(tester, backend);
    await tester.tap(find.byKey(const ValueKey('conversation-c1')));
    await tester.pumpAndSettle();

    backend.messages.add(messageJson(2, body: 'Segundo'));
    await tester.pump(kConversationPollInterval);
    await tester.pumpAndSettle();

    expect(find.text('Primero'), findsOneWidget);
    expect(find.text('Segundo'), findsOneWidget);
  });

  testWidgets('409 already taken returns to the inbox with a notice', (
    tester,
  ) async {
    final backend = FakeChatBackend()
      ..conversations = [conversationJson('c1')]
      ..sendConflictDetail = 'Conversation already taken';
    await _pumpInbox(tester, backend);
    await tester.tap(find.byKey(const ValueKey('conversation-c1')));
    await tester.pumpAndSettle();

    // The conversation vanishes from the inbox once another agent owns it.
    backend.conversations = [];
    await tester.enterText(
      find.byKey(const ValueKey('conversation-input')),
      'Hola',
    );
    await tester.tap(find.byKey(const ValueKey('conversation-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('conversation-input')), findsNothing);
    expect(find.text('Otro agente ya tomó esa conversación.'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-empty')), findsOneWidget);
  });

  testWidgets('a read-only conversation disables the input', (tester) async {
    final backend = FakeChatBackend()
      ..conversations = [conversationJson('c1', readOnly: true)]
      ..readOnly = true;
    await _pumpInbox(tester, backend);
    await tester.tap(find.byKey(const ValueKey('conversation-c1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('conversation-read-only')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('conversation-input')), findsNothing);
    expect(find.byKey(const ValueKey('conversation-send')), findsNothing);
  });

  testWidgets('409 read-only on send disables the input', (tester) async {
    final backend = FakeChatBackend()
      ..conversations = [conversationJson('c1')]
      ..sendConflictDetail = 'Conversation is read-only';
    await _pumpInbox(tester, backend);
    await tester.tap(find.byKey(const ValueKey('conversation-c1')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('conversation-input')),
      'Hola',
    );
    await tester.tap(find.byKey(const ValueKey('conversation-send')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('conversation-read-only')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('conversation-input')), findsNothing);
  });

  testWidgets('admin sees author emails and can reassign', (tester) async {
    final backend = FakeChatBackend()
      ..conversations = [conversationJson('c1', agentEmail: 'ag@example.test')]
      ..messages = [
        messageJson(
          1,
          sender: 'agent',
          body: 'Respuesta',
          authorEmail: 'ag@example.test',
        ),
      ];
    await _pumpInbox(tester, backend, role: 'agency_admin');
    await tester.tap(find.byKey(const ValueKey('conversation-c1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-author-1')), findsOneWidget);
    expect(find.text('ag@example.test'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reassign-action')));
    await tester.pumpAndSettle();
    expect(find.text('otro@example.test'), findsOneWidget);
    expect(find.text('baja@example.test'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('reassign-agent-9')));
    await tester.pumpAndSettle();

    expect(backend.sentBodies.last, {'agent_id': 'agent-9'});
    expect(find.text('Conversación reasignada.'), findsOneWidget);
  });

  testWidgets('automatic reassignment sends an empty body', (tester) async {
    final backend = FakeChatBackend()..conversations = [conversationJson('c1')];
    await _pumpInbox(tester, backend, role: 'agency_admin');
    await tester.tap(find.byKey(const ValueKey('conversation-c1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reassign-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reassign-auto')));
    await tester.pumpAndSettle();

    expect(backend.sentBodies.last, <String, Object?>{});
  });

  testWidgets('reporting a customer sends the reason', (tester) async {
    final backend = FakeChatBackend()..conversations = [conversationJson('c1')];
    await _pumpInbox(tester, backend);
    await tester.tap(find.byKey(const ValueKey('conversation-c1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('report-action')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('report-reason')), 'Spam');
    await tester.tap(find.byKey(const ValueKey('report-confirm')));
    await tester.pumpAndSettle();

    expect(backend.sentBodies.last, {'body': 'Spam'});
    expect(find.text('Reporte enviado a la agencia.'), findsOneWidget);
  });
}
