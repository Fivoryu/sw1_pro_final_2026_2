import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_staff_backend.dart';

const _baseUrl = 'https://api.example.test';

({StaffSessionController controller, FakeStaffBackend backend, InMemoryStaffCredentialStore store})
_build({String? cookie, String? csrf}) {
  final backend = FakeStaffBackend();
  final store = InMemoryStaffCredentialStore(
    refreshCookie: cookie,
    csrfToken: csrf,
  );
  return (
    controller: StaffSessionController(
      api: StaffAuthApi(baseUrl: _baseUrl, client: backend.client),
      credentialStore: store,
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

      expect(harness.controller.status, StaffSessionStatus.signedOut);
      expect(harness.backend.calls, isEmpty);
    });

    test('validates stored credentials and rotates them', () async {
      final harness = _build(cookie: 'refresh-cookie', csrf: 'csrf-1');

      await harness.controller.restore();

      expect(harness.controller.status, StaffSessionStatus.signedIn);
      expect(harness.controller.account?.email, 'agent@example.test');
      expect(harness.store.refreshCookie, 'rotated-cookie');
      expect(harness.store.csrfToken, 'csrf-2');
    });

    test('discards stored credentials when the API rejects them', () async {
      final harness = _build(cookie: 'stale-cookie', csrf: 'csrf-1');
      harness.backend.refreshRejected = true;

      await harness.controller.restore();

      expect(harness.controller.status, StaffSessionStatus.signedOut);
      expect(harness.controller.message, 'Rejected by the API.');
      expect(harness.store.refreshCookie, isNull);
      expect(harness.store.csrfToken, isNull);
    });

    test('keeps stored credentials when the API is unreachable', () async {
      final harness = _build(cookie: 'refresh-cookie', csrf: 'csrf-1');
      harness.backend.offline = true;

      await harness.controller.restore();

      expect(harness.controller.status, StaffSessionStatus.unavailable);
      expect(harness.store.refreshCookie, 'refresh-cookie');
      expect(harness.store.csrfToken, 'csrf-1');
    });
  });

  group('signOut', () {
    test('revokes the session and clears the stored credentials', () async {
      final harness = _build(cookie: 'refresh-cookie', csrf: 'csrf-1');
      await harness.controller.restore();

      await harness.controller.signOut();

      expect(harness.controller.status, StaffSessionStatus.signedOut);
      expect(harness.store.refreshCookie, isNull);
      expect(harness.backend.calls.last, '/api/v1/auth/logout');
    });

    test('keeps the session when the API is unreachable', () async {
      final harness = _build(cookie: 'refresh-cookie', csrf: 'csrf-2');
      await harness.controller.restore();
      harness.backend.offline = true;

      await harness.controller.signOut();

      expect(harness.controller.status, StaffSessionStatus.signedIn);
      expect(harness.controller.message, isNotNull);
      expect(harness.store.refreshCookie, 'rotated-cookie');
    });
  });
}
