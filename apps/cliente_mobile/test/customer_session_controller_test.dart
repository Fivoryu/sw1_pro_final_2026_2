import 'package:cliente_mobile/data/services/customer_auth_api.dart';
import 'package:cliente_mobile/domain/customer_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_customer_backend.dart';

const _baseUrl = 'https://api.example.test';

({CustomerSessionController controller, FakeCustomerBackend backend, InMemoryCustomerTokenStore store})
_build({String? storedToken}) {
  final backend = FakeCustomerBackend();
  final store = InMemoryCustomerTokenStore(storedToken);
  return (
    controller: CustomerSessionController(
      api: CustomerAuthApi(baseUrl: _baseUrl, client: backend.client),
      tokenStore: store,
    ),
    backend: backend,
    store: store,
  );
}

void main() {
  group('restore', () {
    test('signs out without calling the API when nothing is stored', () async {
      final harness = _build();

      await harness.controller.restore();

      expect(harness.controller.status, CustomerSessionStatus.signedOut);
      expect(harness.controller.identity, isNull);
      expect(harness.backend.calls, isEmpty);
    });

    test('validates the stored token and loads the identity', () async {
      final harness = _build(storedToken: 'stored-refresh');

      await harness.controller.restore();

      expect(harness.controller.status, CustomerSessionStatus.signedIn);
      expect(harness.controller.identity?.email, 'client@example.test');
      expect(harness.backend.calls, [
        '/api/v1/customer/auth/refresh',
        '/api/v1/customer/auth/me',
      ]);
      expect(harness.store.token, 'refresh-token-2');
    });

    test('discards the session when the stored token is rejected', () async {
      final harness = _build(storedToken: 'stored-refresh');
      harness.backend.refreshRejected = true;

      await harness.controller.restore();

      expect(harness.controller.status, CustomerSessionStatus.signedOut);
      expect(harness.controller.message, 'Rejected by the API.');
      expect(harness.store.token, isNull);
    });

    test('keeps the stored token when the API is unreachable', () async {
      final harness = _build(storedToken: 'stored-refresh');
      harness.backend.offline = true;

      await harness.controller.restore();

      expect(harness.controller.status, CustomerSessionStatus.unavailable);
      expect(harness.controller.message, isNotNull);
      expect(harness.store.token, 'stored-refresh');
    });
  });

  group('signIn', () {
    test('persists the refresh token and exposes the identity', () async {
      final harness = _build();

      await harness.controller.signIn(
        email: 'client@example.test',
        password: 'password123',
      );

      expect(harness.controller.status, CustomerSessionStatus.signedIn);
      expect(harness.controller.identity?.id, 'customer-1');
      expect(harness.store.token, 'refresh-token-1');
    });

    test('signs out with a message when the credentials are rejected', () async {
      final harness = _build();
      harness.backend.loginRejected = true;

      await harness.controller.signIn(
        email: 'client@example.test',
        password: 'wrong-password',
      );

      expect(harness.controller.status, CustomerSessionStatus.signedOut);
      expect(harness.controller.message, 'Rejected by the API.');
      expect(harness.store.token, isNull);
    });

    test('reports an unavailable session when the transport fails', () async {
      final harness = _build();
      harness.backend.offline = true;

      await harness.controller.signIn(
        email: 'client@example.test',
        password: 'password123',
      );

      expect(harness.controller.status, CustomerSessionStatus.unavailable);
      expect(harness.store.token, isNull);
    });
  });

  group('register', () {
    test('never signs in automatically after creating the account', () async {
      final harness = _build();

      final created = await harness.controller.register(
        email: 'client@example.test',
        password: 'password123',
      );

      expect(created, isTrue);
      expect(harness.controller.status, CustomerSessionStatus.signedOut);
      expect(harness.controller.identity, isNull);
      expect(harness.store.token, isNull);
      expect(harness.controller.message, contains('client@example.test'));
    });

    test('surfaces a conflicting account without creating a session', () async {
      final harness = _build();
      harness.backend.registerConflict = true;

      final created = await harness.controller.register(
        email: 'client@example.test',
        password: 'password123',
      );

      expect(created, isFalse);
      expect(harness.controller.message, 'Rejected by the API.');
      expect(harness.store.token, isNull);
    });
  });

  group('signOut', () {
    test('revokes the session and clears the stored token', () async {
      final harness = _build(storedToken: 'stored-refresh');
      await harness.controller.restore();

      await harness.controller.signOut();

      expect(harness.controller.status, CustomerSessionStatus.signedOut);
      expect(harness.store.token, isNull);
      expect(harness.backend.calls.last, '/api/v1/customer/auth/logout');
    });

    test('keeps the session so the customer can retry when offline', () async {
      final harness = _build(storedToken: 'stored-refresh');
      await harness.controller.restore();
      harness.backend.offline = true;

      await harness.controller.signOut();

      expect(harness.controller.status, CustomerSessionStatus.signedIn);
      expect(harness.controller.message, isNotNull);
      expect(harness.store.token, 'refresh-token-2');
    });

    test('still signs out locally when the token was already rejected', () async {
      final harness = _build(storedToken: 'stored-refresh');
      await harness.controller.restore();
      harness.backend.logoutRejected = true;

      await harness.controller.signOut();

      expect(harness.controller.status, CustomerSessionStatus.signedOut);
      expect(harness.store.token, isNull);
    });
  });
}
