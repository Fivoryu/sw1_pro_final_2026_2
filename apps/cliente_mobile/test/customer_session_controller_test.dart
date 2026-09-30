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
