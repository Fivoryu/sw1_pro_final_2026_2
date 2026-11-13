import 'package:cliente_mobile/data/models/chat_models.dart';
import 'package:cliente_mobile/data/services/customer_auth_failure.dart';
import 'package:cliente_mobile/domain/customer_chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_backend.dart';

Future<CustomerChatController> _started(
  FakeChatBackend backend, {
  bool readOnly = false,
}) async {
  final controller = CustomerChatController(
    api: backend.api,
    conversation: ChatConversation.fromJson(
      FakeChatBackend.conversationJson(readOnly: readOnly),
    ),
    pollInterval: const Duration(milliseconds: 20),
  );
  await controller.start();
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group('chat models', () {
    test('parses a message and rejects an agent sender', () {
      final message = ChatMessage.fromJson({
        'id': 3,
        'sender': 'agency',
        'body': 'Hola',
        'created_at': '2026-11-01T10:00:00Z',
      });
      expect(message.sender, ChatSender.agency);
      expect(
        () => ChatMessage.fromJson({
          'id': 3,
          'sender': 'agent',
          'body': 'x',
          'created_at': '2026-11-01T10:00:00Z',
        }),
        throwsFormatException,
      );
    });

    test('throws FormatException on malformed data', () {
      expect(() => ChatMessage.fromJson({'id': '1'}), throwsFormatException);
      expect(() => ChatConversation.fromJson(null), throwsFormatException);
      expect(
        () => ChatMessagePage.fromJson({'messages': 'x', 'read_only': false}),
        throwsFormatException,
      );
      expect(
        () => ChatConversation.fromJson({
          ...FakeChatBackend.conversationJson(),
          'read_only': 'no',
        }),
        throwsFormatException,
      );
    });

    test('parses a conversation with an agency name and no agent data', () {
      final conversation = ChatConversation.fromJson(
        FakeChatBackend.conversationJson(readOnly: true),
      );
      expect(conversation.agencyName, 'Andina Inmuebles');
      expect(conversation.readOnly, isTrue);
      expect(conversation.lastMessageAt, isNull);
    });
  });

  group('CustomerChatApi', () {
    test('opens a conversation and maps malformed bodies to a failure', () async {
      final backend = FakeChatBackend();
      final conversation = await backend.api.openConversation('listing-1');
      expect(conversation.id, 'conv-1');
      expect(
        backend.requests.single,
        'POST /api/v1/customer/chat/listings/listing-1/conversation',
      );
      expect(
        () => backend.api.listMessages('missing'),
        throwsA(isA<CustomerAuthFailure>()),
      );
    });

    test('maps a transport error to a network failure', () async {
      final backend = FakeChatBackend()..offline = true;
      await expectLater(
        backend.api.listConversations(),
        throwsA(
          isA<CustomerAuthFailure>().having(
            (f) => f.isNetworkFailure,
            'isNetworkFailure',
            true,
          ),
        ),
      );
    });
  });

  group('CustomerChatController', () {
    test('loads the history on start', () async {
      final backend = FakeChatBackend()
        ..add('customer', 'Hola')
        ..add('agency', 'Buenas');
      final controller = await _started(backend);
      expect(controller.messages.map((m) => m.body), ['Hola', 'Buenas']);
      expect(controller.messages.last.sender, ChatSender.agency);
    });

    test('polling asks only for messages after the last id and appends them',
        () async {
      final backend = FakeChatBackend()..add('customer', 'Hola');
      final controller = await _started(backend);
      backend.add('agency', 'Respuesta');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.messages.map((m) => m.id), [1, 2]);
      expect(
        backend.requests.where((r) => r.contains('after=1')),
        isNotEmpty,
      );
      expect(
        backend.requests.where((r) => r.contains('after=0')).length,
        1,
      );
    });

    test('send appends the message once even when polling returns it', () async {
      final backend = FakeChatBackend();
      final controller = await _started(backend);
      expect(await controller.send('  Hola  '), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.messages.map((m) => m.body), ['Hola']);
    });

    test('a network error on send keeps the failure and returns false',
        () async {
      final backend = FakeChatBackend();
      final controller = await _started(backend);
      backend.offline = true;
      expect(await controller.send('Hola'), isFalse);
      expect(controller.message, kSafeFailureDetails[kNetworkError]);
      expect(controller.messages, isEmpty);
      backend.offline = false;
      expect(await controller.send('Hola'), isTrue);
    });

    test('read-only conversations cannot send', () async {
      final backend = FakeChatBackend()..readOnly = true;
      final controller = await _started(backend, readOnly: true);
      expect(controller.readOnly, isTrue);
      expect(await controller.send('Hola'), isFalse);
      expect(backend.requests.where((r) => r.startsWith('POST')), isEmpty);
    });

    test('a 409 on send flips to read-only', () async {
      final backend = FakeChatBackend();
      final controller = await _started(backend);
      backend.readOnly = true;
      expect(await controller.send('Hola'), isFalse);
      expect(controller.readOnly, isTrue);
    });

    test('a 403 on send marks the customer as blocked', () async {
      final backend = FakeChatBackend();
      final controller = await _started(backend);
      backend.blocked = true;
      expect(await controller.send('Hola'), isFalse);
      expect(controller.blocked, isTrue);
      expect(controller.canSend, isFalse);
      expect(controller.message, contains('no está aceptando mensajes'));
    });

    test('report posts the trimmed reason', () async {
      final backend = FakeChatBackend();
      final controller = await _started(backend);
      expect(await controller.report('  Insultos  '), isTrue);
      expect(backend.reports, ['Insultos']);
      expect(await controller.report('   '), isFalse);
    });

    test('dispose cancels the polling timer', () async {
      final backend = FakeChatBackend();
      final controller = CustomerChatController(
        api: backend.api,
        conversation: ChatConversation.fromJson(
          FakeChatBackend.conversationJson(),
        ),
        pollInterval: const Duration(milliseconds: 20),
      );
      await controller.start();
      controller.dispose();
      final before = backend.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(backend.requests.length, before);
    });
  });

  group('CustomerConversationsController', () {
    test('loads the conversations', () async {
      final controller = CustomerConversationsController(
        api: FakeChatBackend().api,
      );
      await controller.load();
      expect(controller.conversations.single.agencyName, 'Andina Inmuebles');
      expect(controller.message, isNull);
    });

    test('reports a failure message', () async {
      final controller = CustomerConversationsController(
        api: (FakeChatBackend()..offline = true).api,
      );
      await controller.load();
      expect(controller.conversations, isEmpty);
      expect(controller.message, kSafeFailureDetails[kNetworkError]);
    });
  });
}
