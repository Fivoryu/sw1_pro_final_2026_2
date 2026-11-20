import 'dart:async';
import 'dart:convert';

import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/device_push_registrar.dart';
import 'package:captura_mobile/data/services/push_messaging.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_staff_backend.dart';

class _FakeMessaging implements PushMessaging {
  bool permission = true;
  String? token = 'fcm-token-1';
  int permissionRequests = 0;
  final refreshes = StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<String?> obtainToken() async => token;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;
}

class _Request {
  _Request(this.path, this.authorization, this.body);

  final String path;
  final String? authorization;
  final Map<String, Object?> body;
}

({DevicePushRegistrar registrar, _FakeMessaging messaging, List<_Request> sent})
_build({int status = 204}) {
  final sent = <_Request>[];
  final client = MockClient((request) async {
    sent.add(
      _Request(
        request.url.path,
        request.headers['Authorization'],
        jsonDecode(request.body) as Map<String, Object?>,
      ),
    );
    return http.Response('', status);
  });
  final messaging = _FakeMessaging();
  final registrar = DevicePushRegistrar(
    baseUrl: 'https://api.example.test/',
    accessTokenProvider: () async => 'access-1',
    messaging: messaging,
    client: client,
  );
  return (registrar: registrar, messaging: messaging, sent: sent);
}

class _Session extends ChangeNotifier {
  bool signedIn = false;

  void change({required bool signedIn}) {
    this.signedIn = signedIn;
    notifyListeners();
  }
}

void main() {
  test('registers the FCM token of the signed-in agency staff', () async {
    final harness = _build();

    await harness.registrar.register();

    expect(harness.sent, hasLength(1));
    final request = harness.sent.single;
    expect(request.path, '/api/v1/staff/devices');
    expect(request.authorization, 'Bearer access-1');
    expect(request.body, {'token': 'fcm-token-1', 'platform': 'android'});
    expect(harness.registrar.registeredToken, 'fcm-token-1');
  });

  test('does nothing when notification permission is denied', () async {
    final harness = _build();
    harness.messaging.permission = false;

    await harness.registrar.register();

    expect(harness.sent, isEmpty);
    expect(harness.registrar.registeredToken, isNull);
  });

  test('does nothing when FCM has no token', () async {
    final harness = _build();
    harness.messaging.token = null;

    await harness.registrar.register();

    expect(harness.sent, isEmpty);
  });

  test('registers only once while a token is already registered', () async {
    final harness = _build();

    await harness.registrar.register();
    await harness.registrar.register();

    expect(harness.sent, hasLength(1));
    expect(harness.messaging.permissionRequests, 1);
  });

  test('swallows a failing backend and tries again later', () async {
    final harness = _build(status: 500);

    await harness.registrar.register();

    expect(harness.registrar.registeredToken, isNull);
    await harness.registrar.register();
    expect(harness.sent, hasLength(2));
  });

  test('attach registers when the session becomes signed in', () async {
    final harness = _build();
    final session = _Session();
    harness.registrar.attach(session, isSignedIn: () => session.signedIn);

    session.change(signedIn: false);
    await Future<void>.delayed(Duration.zero);
    expect(harness.sent, isEmpty);

    session.change(signedIn: true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(harness.sent, hasLength(1));
  });

  test('sends a rotated token to the backend', () async {
    final harness = _build();
    await harness.registrar.register();

    harness.messaging.refreshes.add('fcm-token-2');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(harness.sent.last.body['token'], 'fcm-token-2');
    expect(harness.registrar.registeredToken, 'fcm-token-2');
    harness.registrar.dispose();
  });

  test('unregister removes the token and ignores backend errors', () async {
    final harness = _build();
    await harness.registrar.register();

    await harness.registrar.unregister();

    expect(harness.sent.last.path, '/api/v1/staff/devices/remove');
    expect(harness.sent.last.body, {'token': 'fcm-token-1'});
    expect(harness.registrar.registeredToken, isNull);

    final callsBefore = harness.sent.length;
    await harness.registrar.unregister();
    expect(harness.sent, hasLength(callsBefore));
  });

  test('signOut runs beforeSignOut first and survives its failure', () async {
    final backend = FakeStaffBackend();
    final store = InMemoryStaffCredentialStore(
      refreshCookie: 'refresh-cookie',
      csrfToken: 'csrf-1',
    );
    final callsAtHook = <String>[];
    final controller = StaffSessionController(
      api: StaffAuthApi(
        baseUrl: 'https://api.example.test',
        client: backend.client,
      ),
      credentialStore: store,
      beforeSignOut: () async {
        callsAtHook.addAll(backend.calls);
        throw StateError('cleanup failed');
      },
    );
    await controller.restore();

    await controller.signOut();

    expect(callsAtHook, isNot(contains('/api/v1/auth/logout')));
    expect(backend.calls.last, '/api/v1/auth/logout');
    expect(controller.status, StaffSessionStatus.signedOut);
    expect(store.refreshCookie, isNull);
  });
}
