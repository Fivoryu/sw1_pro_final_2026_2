import 'dart:convert';

import 'package:cliente_mobile/data/models/notification_models.dart';
import 'package:cliente_mobile/data/services/customer_notifications_api.dart';
import 'package:cliente_mobile/domain/customer_notifications_controller.dart';
import 'package:cliente_mobile/ui/features/notifications/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_chat_backend.dart';

/// Stand-in for `/api/v1/customer/notifications`.
class _FakeNotificationsBackend {
  final List<Map<String, Object?>> items = [];
  final List<String> requests = [];
  bool offline = false;

  Map<String, Object?> add(
    String id,
    String kind, {
    String? conversationId,
    String? reservationId,
    String? detail,
    bool read = false,
  }) {
    final item = {
      'id': id,
      'kind': kind,
      'conversation_id': conversationId,
      'reservation_id': reservationId,
      'detail': detail,
      'created_at': '2026-11-01T10:00:00Z',
      'read': read,
    };
    items.add(item);
    return item;
  }

  CustomerNotificationsApi get api => CustomerNotificationsApi(
    baseUrl: 'https://api.example.test',
    accessTokenProvider: () async => 'token',
    client: MockClient(_handle),
  );

  http.Response _json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: const {'content-type': 'application/json'},
  );

  Future<http.Response> _handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    if (offline) throw http.ClientException('offline');
    const root = '/api/v1/customer/notifications';
    final path = request.url.path;
    if (path == root && request.method == 'GET') {
      return _json({
        'unread': items.where((i) => i['read'] == false).length,
        'items': items,
      }, 200);
    }
    if (path == '$root/read-all') {
      for (final item in items) {
        item['read'] = true;
      }
      return http.Response('', 204);
    }
    final single = RegExp('^$root/([^/]+)/read\$').firstMatch(path);
    if (single != null) {
      items.firstWhere((i) => i['id'] == single.group(1))['read'] = true;
      return http.Response('', 204);
    }
    return http.Response('', 404);
  }
}

CustomerNotificationsController _controller(_FakeNotificationsBackend b) {
  final controller = CustomerNotificationsController(
    api: b.api,
    pollInterval: const Duration(milliseconds: 20),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group('notification models', () {
    test('parses a notice and maps unknown kinds to other', () {
      final notice = AppNotification.fromJson({
        'id': 'n1',
        'kind': 'something_new',
        'conversation_id': null,
        'reservation_id': null,
        'detail': null,
        'created_at': '2026-11-01T10:00:00Z',
        'read': false,
      });
      expect(notice.kind, NotificationKind.other);
      expect(notice.asRead().read, isTrue);
    });

    test('rejects malformed data', () {
      expect(() => AppNotification.fromJson({'id': 1}), throwsFormatException);
      expect(
        () => NotificationInbox.fromJson({'unread': 'x', 'items': []}),
        throwsFormatException,
      );
    });
  });

  group('CustomerNotificationsController', () {
    test('start loads the inbox and the unread counter', () async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_message', conversationId: 'conv-1')
        ..add('n2', 'reservation_status', reservationId: 'r1', detail: 'accepted');
      final controller = _controller(backend);

      await controller.start();

      expect(controller.unread, 2);
      expect(controller.items.map((i) => i.id), ['n1', 'n2']);
    });

    test('polling picks up a new notice', () async {
      final backend = _FakeNotificationsBackend();
      final controller = _controller(backend);
      await controller.start();
      expect(controller.unread, 0);

      backend.add('n1', 'chat_message', conversationId: 'conv-1');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(controller.unread, 1);
    });

    test('markRead and markAllRead update the counter', () async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_message', conversationId: 'conv-1')
        ..add('n2', 'chat_message', conversationId: 'conv-1');
      final controller = _controller(backend);
      await controller.start();

      await controller.markRead(controller.items.first);
      expect(controller.unread, 1);
      expect(controller.items.first.read, isTrue);

      await controller.markAllRead();
      expect(controller.unread, 0);
      expect(backend.requests, contains('POST /api/v1/customer/notifications/read-all'));
    });

    test('stop clears the counter and ends polling', () async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_message', conversationId: 'conv-1');
      final controller = _controller(backend);
      await controller.start();

      controller.stop();
      final requestsAtStop = backend.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(controller.unread, 0);
      expect(controller.items, isEmpty);
      expect(backend.requests.length, requestsAtStop);
    });

    test('an offline poll keeps the last inbox and shows no error', () async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_message', conversationId: 'conv-1');
      final controller = _controller(backend);
      await controller.start();

      backend.offline = true;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(controller.unread, 1);
      expect(controller.message, isNull);
    });

    test('an offline first load reports a safe message', () async {
      final backend = _FakeNotificationsBackend()..offline = true;
      final controller = _controller(backend);

      await controller.start();

      expect(controller.message, isNotNull);
    });
  });

  group('notification wording', () {
    AppNotification notice(NotificationKind kind, [String? detail]) =>
        AppNotification(
          id: 'n',
          kind: kind,
          conversationId: null,
          reservationId: null,
          detail: detail,
          createdAt: DateTime(2026),
          read: false,
        );

    test('a chat notice names the agency, never an agent', () {
      expect(
        notificationTitle(notice(NotificationKind.chatMessage)),
        'Nuevo mensaje de la inmobiliaria',
      );
    });

    test('each reservation status has its own text', () {
      final titles = {
        for (final s in ['accepted', 'rejected', 'cancelled', 'expired'])
          notificationTitle(notice(NotificationKind.reservationStatus, s)),
      };
      expect(titles, hasLength(4));
    });
  });

  group('NotificationsScreen', () {
    Future<void> pump(
      WidgetTester tester,
      CustomerNotificationsController controller, {
      FakeChatBackend? chat,
      VoidCallback? onOpenReservations,
    }) async {
      await tester.runAsync(controller.refresh);
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            controller: controller,
            chatApi: chat?.api,
            onOpenReservations: onOpenReservations,
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('shows the empty state', (tester) async {
      final controller = _controller(_FakeNotificationsBackend());
      await pump(tester, controller);

      expect(find.byKey(const ValueKey('notifications-empty')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping a reservation notice marks it read and opens reservations', (
      tester,
    ) async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'reservation_status', reservationId: 'r1', detail: 'accepted');
      final controller = _controller(backend);
      var opened = 0;
      await pump(tester, controller, onOpenReservations: () => opened++);
      expect(find.text('Tu reserva fue aceptada'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await settle(tester);

      expect(opened, 1);
      expect(controller.unread, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping a chat notice opens the conversation', (tester) async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_message', conversationId: 'conv-1');
      final chat = FakeChatBackend()..add('agency', 'Hola, ¿seguís interesado?');
      final controller = _controller(backend);
      await pump(tester, controller, chat: chat);

      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await settle(tester);

      expect(find.text('Hola, ¿seguís interesado?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('mark all read clears the badge', (tester) async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_message', conversationId: 'conv-1')
        ..add('n2', 'chat_message', conversationId: 'conv-1');
      final controller = _controller(backend);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                NotificationsBell(controller: controller, onPressed: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(controller.start);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      await tester.runAsync(controller.markAllRead);
      await tester.pump();

      expect(find.text('2'), findsNothing);
      controller.stop();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
