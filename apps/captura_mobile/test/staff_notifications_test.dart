import 'dart:convert';

import 'package:captura_mobile/data/models/staff_notification.dart';
import 'package:captura_mobile/data/services/staff_notifications_api.dart';
import 'package:captura_mobile/domain/staff_notifications_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/ui/notifications/staff_notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_chat_backend.dart';

/// Stand-in for `/api/v1/staff/notifications`.
class _FakeNotificationsBackend {
  final List<Map<String, Object?>> items = [];
  final List<http.Request> requests = [];
  bool offline = false;
  int status = 200;

  void add(
    String id,
    String kind, {
    String? conversationId,
    String? reservationId,
    String? detail,
    bool read = false,
  }) => items.add({
    'id': id,
    'kind': kind,
    'conversation_id': conversationId,
    'reservation_id': reservationId,
    'detail': detail,
    'created_at': '2026-11-13T10:00:00Z',
    'read': read,
  });

  StaffNotificationsApi get api => StaffNotificationsApi(
    baseUrl: chatBaseUrl,
    client: MockClient(_handle),
  );

  http.Response _json(Object body, int code) => http.Response(
    jsonEncode(body),
    code,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('offline');
    if (status != 200) return _json({'detail': 'no', 'code': 'forbidden'}, status);
    const root = '/api/v1/staff/notifications';
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

Future<StaffNotificationsController> _controller(
  WidgetTester? tester,
  _FakeNotificationsBackend backend, {
  String role = 'agent',
}) async {
  late ({StaffSessionController session, dynamic api}) chat;
  Future<void> build() async {
    final signed = await signedInChat(FakeChatBackend(), role: role);
    chat = (session: signed.session, api: signed.api);
  }

  if (tester != null) {
    await tester.runAsync(build);
  } else {
    await build();
  }
  final controller = StaffNotificationsController(
    api: backend.api,
    session: chat.session,
    pollInterval: const Duration(milliseconds: 20),
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Waits (real time) until [condition] holds, instead of a fixed sleep.
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('staff notification model', () {
    test('maps every kind and falls back to other', () {
      Map<String, Object?> json(String kind) => {
        'id': 'n',
        'kind': kind,
        'conversation_id': null,
        'reservation_id': null,
        'detail': null,
        'created_at': '2026-11-13T10:00:00Z',
        'read': false,
      };
      expect(
        [
          'chat_message',
          'chat_assigned',
          'chat_needs_admin',
          'chat_overdue',
          'reservation_status',
          'novel',
        ].map((k) => StaffNotification.fromJson(json(k)).kind),
        [
          StaffNotificationKind.chatMessage,
          StaffNotificationKind.chatAssigned,
          StaffNotificationKind.chatNeedsAdmin,
          StaffNotificationKind.chatOverdue,
          StaffNotificationKind.reservationStatus,
          StaffNotificationKind.other,
        ],
      );
    });

    test('rejects malformed data', () {
      expect(() => StaffNotification.fromJson({'id': 1}), throwsFormatException);
      expect(
        () => StaffNotificationInbox.fromJson({'unread': 'x', 'items': []}),
        throwsFormatException,
      );
    });
  });

  group('StaffNotificationsController', () {
    test('start loads the inbox and polling picks up new notices', () async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_message', conversationId: 'c1');
      final controller = await _controller(null, backend);

      await controller.start();
      expect(controller.unread, 1);

      backend.add('n2', 'chat_assigned', conversationId: 'c2');
      await _until(() => controller.unread == 2);
      expect(controller.unread, 2);
    });

    test('requests carry the staff bearer token', () async {
      final backend = _FakeNotificationsBackend();
      final controller = await _controller(null, backend);

      await controller.start();

      expect(backend.requests.first.headers['Authorization'], startsWith('Bearer '));
    });

    test('markRead and markAllRead update the counter', () async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_message', conversationId: 'c1')
        ..add('n2', 'chat_overdue', conversationId: 'c1');
      final controller = await _controller(null, backend, role: 'agency_admin');
      await controller.start();

      await controller.markRead(controller.items.first);
      expect(controller.unread, 1);

      await controller.markAllRead();
      expect(controller.unread, 0);
      expect(
        backend.requests.map((r) => r.url.path),
        contains('/api/v1/staff/notifications/read-all'),
      );
    });

    test('sync starts for an agent and stops when the session ends', () async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_message', conversationId: 'c1');
      final controller = await _controller(null, backend);
      expect(controller.available, isTrue);

      controller.sync();
      await _until(() => controller.unread == 1);
      expect(controller.unread, 1);

      controller.stop();
      // A request already in flight may still land; nothing new starts after it.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final seen = backend.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.unread, 0);
      expect(backend.requests.length, seen);
    });

    test('a platform admin has no inbox', () async {
      final backend = _FakeNotificationsBackend();
      final controller = await _controller(null, backend, role: 'platform_admin');

      expect(controller.available, isFalse);
      controller.sync();

      expect(backend.requests, isEmpty);
    });

    test('a failed first load shows a Spanish message', () async {
      final backend = _FakeNotificationsBackend()..status = 403;
      final controller = await _controller(null, backend);

      await controller.start();

      expect(controller.message, 'Tu cuenta no tiene permisos para esta conversación.');
    });

    test('an offline poll keeps the last inbox without an error', () async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_message', conversationId: 'c1');
      final controller = await _controller(null, backend);
      await controller.start();

      backend.offline = true;
      final polls = backend.requests.length;
      await _until(() => backend.requests.length > polls + 1);

      expect(controller.unread, 1);
      expect(controller.message, isNull);
    });
  });

  group('wording', () {
    StaffNotification notice(StaffNotificationKind kind, [String? detail]) =>
        StaffNotification(
          id: 'n',
          kind: kind,
          conversationId: null,
          reservationId: null,
          detail: detail,
          createdAt: DateTime(2026),
          read: false,
        );

    test('every kind has distinct Spanish text', () {
      final titles = {
        for (final k in StaffNotificationKind.values)
          if (k != StaffNotificationKind.reservationStatus)
            staffNotificationTitle(notice(k)),
      };
      expect(titles, hasLength(StaffNotificationKind.values.length - 1));
      expect(
        staffNotificationTitle(
          notice(StaffNotificationKind.reservationStatus, 'accepted'),
        ),
        'Una reserva fue aceptada',
      );
    });
  });

  group('StaffNotificationsScreen', () {
    /// Pumps with real-time gaps until [finder] matches (or gives up).
    Future<void> settleUntil(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    testWidgets('lists notices and opens the conversation on tap', (tester) async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_assigned', conversationId: 'c1');
      final chat = FakeChatBackend()
        ..conversations = [conversationJson('c1', email: 'ana@example.test')]
        ..messages = [messageJson(1, body: 'Hola, consulta')];
      late ({StaffSessionController session, dynamic api}) signed;
      await tester.runAsync(() async {
        final s = await signedInChat(chat);
        signed = (session: s.session, api: s.api);
      });
      final withToken = StaffNotificationsController(
        api: backend.api,
        session: signed.session,
        pollInterval: const Duration(hours: 1),
      );
      addTearDown(withToken.dispose);
      await tester.runAsync(withToken.refresh);

      await tester.pumpWidget(
        MaterialApp(
          home: StaffNotificationsScreen(
            controller: withToken,
            chatApi: signed.api,
            session: signed.session,
          ),
        ),
      );
      await settleUntil(tester, find.text('Te asignaron una conversación'));
      expect(find.text('Te asignaron una conversación'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await settleUntil(tester, find.text('Hola, consulta'));

      expect(withToken.unread, 0);
      expect(find.text('Hola, consulta'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the bell shows the unread count', (tester) async {
      final backend = _FakeNotificationsBackend()
        ..add('n1', 'chat_message', conversationId: 'c1')
        ..add('n2', 'chat_message', conversationId: 'c1');
      final controller = await _controller(tester, backend);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                StaffNotificationsBell(controller: controller, onPressed: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(controller.start);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      controller.stop();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows the empty state', (tester) async {
      final backend = _FakeNotificationsBackend();
      final controller = await _controller(tester, backend);
      await tester.runAsync(controller.refresh);
      final chat = FakeChatBackend();
      late ({StaffSessionController session, dynamic api}) signed;
      await tester.runAsync(() async {
        final s = await signedInChat(chat);
        signed = (session: s.session, api: s.api);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: StaffNotificationsScreen(
            controller: controller,
            chatApi: signed.api,
            session: signed.session,
          ),
        ),
      );
      await settleUntil(tester, find.byKey(const ValueKey('notifications-empty')));

      expect(find.byKey(const ValueKey('notifications-empty')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
