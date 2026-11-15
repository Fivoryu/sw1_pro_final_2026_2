import 'package:captura_mobile/data/models/staff_chat.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/domain/staff_chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_backend.dart';

void main() {
  group('models', () {
    test('parse a conversation and keep admin-only fields optional', () {
      final agent = StaffConversation.fromJson(conversationJson('c1'));
      expect(agent.customerEmail, 'cliente@example.test');
      expect(agent.status, ConversationStatus.unclaimed);
      expect(agent.agentEmail, isNull);
      final admin = StaffConversation.fromJson(
        conversationJson('c1', agentEmail: 'ag@example.test'),
      );
      expect(admin.agentEmail, 'ag@example.test');
    });

    test('a null last_message_at is accepted', () {
      final parsed = StaffConversation.fromJson(
        conversationJson('c1', lastMessageAt: null),
      );
      expect(parsed.lastMessageAt, isNull);
    });

    test('malformed conversations and messages throw FormatException', () {
      expect(
        () =>
            StaffConversation.fromJson({...conversationJson('c1'), 'mine': 1}),
        throwsFormatException,
      );
      expect(
        () => StaffConversation.fromJson({
          ...conversationJson('c1'),
          'status': 'closed',
        }),
        throwsFormatException,
      );
      expect(
        () => StaffChatMessage.fromJson({...messageJson(1), 'id': '1'}),
        throwsFormatException,
      );
      expect(
        () => StaffChatMessage.fromJson({...messageJson(1), 'sender': 'bot'}),
        throwsFormatException,
      );
      expect(
        () => StaffChatMessage.fromJson({
          ...messageJson(1),
          'created_at': 'ayer',
        }),
        throwsFormatException,
      );
      expect(
        () => StaffMessagePage.fromJson({'messages': 'x', 'read_only': false}),
        throwsFormatException,
      );
      expect(
        () => parseConversationList({'conversations': 3}),
        throwsFormatException,
      );
    });

    test('message author_email is parsed only when present', () {
      expect(StaffChatMessage.fromJson(messageJson(1)).authorEmail, isNull);
      expect(
        StaffChatMessage.fromJson(
          messageJson(1, authorEmail: 'ag@example.test'),
        ).authorEmail,
        'ag@example.test',
      );
    });
  });

  group('inbox', () {
    test('loads the conversations with the bearer token', () async {
      final backend = FakeChatBackend()
        ..conversations = [conversationJson('c1'), conversationJson('c2')];
      final chat = await signedInChat(backend);
      final inbox = StaffInboxController(api: chat.api, session: chat.session);

      await inbox.load();

      expect(inbox.state, ChatLoadState.ready);
      expect(inbox.conversations.map((c) => c.id), ['c1', 'c2']);
      expect(
        backend.requests.last.headers['Authorization'],
        'Bearer access-token',
      );
    });

    test('a failed first load reports a failure state', () async {
      final backend = FakeChatBackend()..offline = true;
      final chat = await signedInChat(backend);
      final inbox = StaffInboxController(api: chat.api, session: chat.session);

      await inbox.load();

      expect(inbox.state, ChatLoadState.failed);
      expect(inbox.message, isNotNull);
    });

    test('a failed refresh keeps the previous list', () async {
      final backend = FakeChatBackend()
        ..conversations = [conversationJson('c1')];
      final chat = await signedInChat(backend);
      final inbox = StaffInboxController(api: chat.api, session: chat.session);
      await inbox.load();

      backend.offline = true;
      await inbox.refresh();

      expect(inbox.state, ChatLoadState.ready);
      expect(inbox.conversations, hasLength(1));
      expect(inbox.message, isNotNull);
    });
  });

  group('conversation', () {
    Future<StaffConversationController> open(
      FakeChatBackend backend, {
      String role = 'agent',
      Map<String, Object?>? json,
    }) async {
      final chat = await signedInChat(backend, role: role);
      return StaffConversationController(
        api: chat.api,
        session: chat.session,
        conversation: StaffConversation.fromJson(
          json ?? conversationJson('c1'),
        ),
      );
    }

    test('load fetches the history and read-only flag', () async {
      final backend = FakeChatBackend()
        ..messages = [messageJson(1), messageJson(2, body: 'Precio?')]
        ..readOnly = true;
      final controller = await open(backend);

      await controller.load();

      expect(controller.messages.map((m) => m.id), [1, 2]);
      expect(controller.readOnly, isTrue);
    });

    test('send to an unclaimed conversation claims it', () async {
      final backend = FakeChatBackend()..messages = [messageJson(1)];
      final controller = await open(backend);
      await controller.load();

      final sent = await controller.send('  Buenas  ');

      expect(sent, isTrue);
      expect(backend.sentBodies.single, {'body': 'Buenas'});
      expect(controller.messages.last.body, 'Buenas');
      expect(controller.messages.last.mine, isTrue);
      expect(controller.conversation.status, ConversationStatus.claimed);
      expect(controller.conversation.mine, isTrue);
    });

    test('an empty message is not sent', () async {
      final backend = FakeChatBackend();
      final controller = await open(backend);
      await controller.load();

      expect(await controller.send('   '), isFalse);
      expect(backend.sentBodies, isEmpty);
    });

    test('409 already taken flags the conversation as taken', () async {
      final backend = FakeChatBackend()
        ..sendConflictDetail = 'Conversation already taken';
      final controller = await open(backend);
      await controller.load();

      expect(await controller.send('Hola'), isFalse);

      expect(controller.taken, isTrue);
      expect(controller.readOnly, isFalse);
      expect(controller.message, 'Otro agente ya tomó esta conversación.');
    });

    test('409 read-only disables sending', () async {
      final backend = FakeChatBackend()
        ..sendConflictDetail = 'Conversation is read-only';
      final controller = await open(backend);
      await controller.load();

      expect(await controller.send('Hola'), isFalse);

      expect(controller.readOnly, isTrue);
      expect(controller.taken, isFalse);
      backend.sendConflictDetail = null;
      expect(await controller.send('otra'), isFalse);
      expect(backend.sentBodies, isEmpty);
    });

    test('poll appends only messages newer than the last id', () async {
      final backend = FakeChatBackend()
        ..messages = [messageJson(1), messageJson(2)];
      final controller = await open(backend);
      await controller.load();

      backend.messages.add(messageJson(3, body: 'Nuevo'));
      await controller.poll();
      await controller.poll();

      expect(controller.messages.map((m) => m.id), [1, 2, 3]);
      expect(backend.requests.last.url.queryParameters['after'], '3');
    });

    test('poll does not duplicate a message already added by send', () async {
      final backend = FakeChatBackend()..messages = [messageJson(1)];
      final controller = await open(backend);
      await controller.load();
      await controller.send('Respuesta propia');

      await controller.poll();

      expect(
        controller.messages.where((m) => m.body == 'Respuesta propia'),
        hasLength(1),
      );
    });

    test('poll picks up the read-only flag turning on', () async {
      final backend = FakeChatBackend();
      final controller = await open(backend);
      await controller.load();

      backend.readOnly = true;
      await controller.poll();

      expect(controller.readOnly, isTrue);
    });

    test('poll 404 marks the conversation unavailable', () async {
      final backend = FakeChatBackend();
      final controller = await open(backend);
      await controller.load();

      backend.messagesNotFound = true;
      await controller.poll();

      expect(controller.unavailable, isTrue);
    });

    test('a poll network failure is silent', () async {
      final backend = FakeChatBackend()..messages = [messageJson(1)];
      final controller = await open(backend);
      await controller.load();

      backend.offline = true;
      await controller.poll();

      expect(controller.unavailable, isFalse);
      expect(controller.message, isNull);
      expect(controller.messages, hasLength(1));
    });

    test(
      'admin lists active agents and reassigns, automatic or manual',
      () async {
        final backend = FakeChatBackend();
        final controller = await open(backend, role: 'agency_admin');
        await controller.load();
        await controller.loadAgents();

        expect(controller.isAdmin, isTrue);
        expect(controller.agents.map((a) => a.id), ['agent-9']);

        expect(await controller.reassign(), isTrue);
        expect(await controller.reassign(agentId: 'agent-9'), isTrue);
        expect(backend.sentBodies, [
          <String, Object?>{},
          {'agent_id': 'agent-9'},
        ]);
        expect(controller.conversation.agentEmail, 'otro@example.test');
      },
    );

    test('an agent cannot reassign', () async {
      final backend = FakeChatBackend();
      final controller = await open(backend);

      expect(await controller.reassign(), isFalse);
      expect(backend.sentBodies, isEmpty);
    });

    test('report sends the reason', () async {
      final backend = FakeChatBackend();
      final controller = await open(backend);

      expect(await controller.reportCustomer(' Insultos '), isTrue);
      expect(backend.sentBodies.single, {'body': 'Insultos'});
      expect(await controller.reportCustomer(' '), isFalse);
    });
  });

  test('canUseStaffChat accepts only agents and agency admins', () {
    StaffAccount account(String role) => StaffAccount(
      id: 'u',
      email: 'u@example.test',
      role: role,
      tenantId: 'a',
    );
    expect(canUseStaffChat(account('agent')), isTrue);
    expect(canUseStaffChat(account('agency_admin')), isTrue);
    expect(canUseStaffChat(account('platform_admin')), isFalse);
    expect(canUseStaffChat(null), isFalse);
  });

  test('chatFailureMessage tells taken from read-only conflicts', () {
    const taken = StaffAuthFailure(
      code: kConflict,
      detail: 'Conversation already taken',
      statusCode: 409,
    );
    const readOnly = StaffAuthFailure(
      code: kConflict,
      detail: 'Conversation is read-only',
      statusCode: 409,
    );
    expect(chatFailureMessage(taken), contains('ya tomó'));
    expect(chatFailureMessage(readOnly), contains('solo lectura'));
  });
}
