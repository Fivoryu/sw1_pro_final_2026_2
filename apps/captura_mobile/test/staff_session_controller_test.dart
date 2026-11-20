import 'package:captura_mobile/data/services/offline_listing_store.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_staff_backend.dart';
import 'support/in_memory_offline_listing_store.dart';

const _baseUrl = 'https://api.example.test';

({
  StaffSessionController controller,
  FakeStaffBackend backend,
  InMemoryStaffCredentialStore store,
  InMemoryOfflineListingStore? cache,
})
_build({String? cookie, String? csrf, String? owner, bool withCache = false}) {
  final backend = FakeStaffBackend();
  final store = InMemoryStaffCredentialStore(
    refreshCookie: cookie,
    csrfToken: csrf,
    ownerId: owner,
  );
  final cache = withCache ? InMemoryOfflineListingStore() : null;
  return (
    controller: StaffSessionController(
      api: StaffAuthApi(baseUrl: _baseUrl, client: backend.client),
      credentialStore: store,
      offlineStore: cache,
    ),
    backend: backend,
    store: store,
    cache: cache,
  );
}

const _listing = OfflineListing(listingId: 'listing-1', label: 'La Paz');

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

  group('offline mode (S10)', () {
    test('enters offline with a stored session and no network', () async {
      final harness = _build(
        cookie: 'refresh-cookie',
        csrf: 'csrf-1',
        owner: 'staff-1',
        withCache: true,
      );
      await harness.cache!.write('staff-1', 'draft', [_listing]);
      harness.backend.offline = true;

      await harness.controller.restore();

      expect(harness.controller.status, StaffSessionStatus.offline);
      expect(harness.controller.offlineListings, [
        isA<OfflineListing>().having((l) => l.listingId, 'id', 'listing-1'),
      ]);
      expect(harness.controller.ownerId, 'staff-1');
      // Not authenticated for any API call.
      expect(harness.controller.accessToken, isNull);
      expect(harness.controller.account, isNull);
      expect(harness.store.refreshCookie, 'refresh-cookie');
    });

    test('does not enter offline without a stored session', () async {
      final harness = _build(owner: 'staff-1', withCache: true);
      await harness.cache!.write('staff-1', 'draft', [_listing]);
      harness.backend.offline = true;

      await harness.controller.restore();

      expect(harness.controller.status, StaffSessionStatus.signedOut);
      expect(harness.controller.offlineListings, isEmpty);
    });

    test('does not enter offline when the owner is unknown', () async {
      final harness = _build(
        cookie: 'refresh-cookie',
        csrf: 'csrf-1',
        withCache: true,
      );
      harness.backend.offline = true;

      await harness.controller.restore();

      expect(harness.controller.status, StaffSessionStatus.unavailable);
    });

    test('makes no API call while offline entry is decided', () async {
      final harness = _build(
        cookie: 'refresh-cookie',
        csrf: 'csrf-1',
        owner: 'staff-1',
        withCache: true,
      );
      harness.backend.offline = true;

      await harness.controller.restore();

      expect(harness.backend.calls, ['/api/v1/auth/refresh']);
    });

    test('a rejected session is discarded and the cache wiped', () async {
      final harness = _build(
        cookie: 'stale-cookie',
        csrf: 'csrf-1',
        owner: 'staff-1',
        withCache: true,
      );
      await harness.cache!.write('staff-1', 'draft', [_listing]);
      harness.backend.refreshRejected = true;

      await harness.controller.restore();

      expect(harness.controller.status, StaffSessionStatus.signedOut);
      expect(harness.store.refreshCookie, isNull);
      expect(harness.store.ownerId, isNull);
      expect(harness.cache!.data, isEmpty);
    });

    test('the real refresh runs when the network returns', () async {
      final harness = _build(
        cookie: 'refresh-cookie',
        csrf: 'csrf-1',
        owner: 'staff-1',
        withCache: true,
      );
      harness.backend.offline = true;
      await harness.controller.restore();
      harness.backend.offline = false;

      await harness.controller.restore();

      expect(harness.controller.status, StaffSessionStatus.signedIn);
      expect(harness.controller.accessToken, 'access-token');
      expect(harness.controller.ownerId, 'staff-1');
      expect(harness.store.ownerId, 'staff-1');
    });

    test('sign-out wipes the stored session, owner and cache', () async {
      final harness = _build(
        cookie: 'refresh-cookie',
        csrf: 'csrf-1',
        withCache: true,
      );
      await harness.controller.restore();
      await harness.controller.rememberListings('draft', [_listing]);
      expect(harness.cache!.data['staff-1'], isNotNull);

      await harness.controller.signOut();

      expect(harness.store.refreshCookie, isNull);
      expect(harness.store.ownerId, isNull);
      expect(harness.cache!.data, isEmpty);
    });

    test('the cache is kept per account', () async {
      final harness = _build(
        cookie: 'refresh-cookie',
        csrf: 'csrf-1',
        owner: 'staff-2',
        withCache: true,
      );
      await harness.cache!.write('staff-1', 'draft', [_listing]);
      harness.backend.offline = true;

      await harness.controller.restore();

      expect(harness.controller.status, StaffSessionStatus.offline);
      expect(harness.controller.offlineListings, isEmpty);
    });

    test('a different account signing in wipes the previous cache', () async {
      final harness = _build(
        cookie: 'refresh-cookie',
        csrf: 'csrf-1',
        owner: 'staff-9',
        withCache: true,
      );
      await harness.cache!.write('staff-9', 'draft', [_listing]);

      await harness.controller.restore();

      expect(harness.cache!.data, isEmpty);
      expect(harness.store.ownerId, 'staff-1');
    });

    test('remembers listings only for the signed-in account', () async {
      final harness = _build(withCache: true);

      await harness.controller.rememberListings('draft', [_listing]);

      expect(harness.cache!.data, isEmpty);
    });
  });

  group('two-step login', () {
    test('asks for the TOTP code after valid credentials', () async {
      final harness = _build();

      await harness.controller.startLogin(
        email: 'agent@example.test',
        password: 'password123',
      );

      expect(harness.controller.status, StaffSessionStatus.awaitingCode);
      expect(harness.backend.calls, ['/api/v1/auth/login']);
    });

    test(
      'signs out with a message when the credentials are rejected',
      () async {
        final harness = _build();
        harness.backend.loginRejected = true;

        await harness.controller.startLogin(
          email: 'agent@example.test',
          password: 'wrong-password',
        );

        expect(harness.controller.status, StaffSessionStatus.signedOut);
        expect(harness.controller.message, 'Rejected by the API.');
      },
    );

    test(
      'opens the session with a valid code and stores the credentials',
      () async {
        final harness = _build();
        await harness.controller.startLogin(
          email: 'agent@example.test',
          password: 'password123',
        );

        await harness.controller.submitCode('123456');

        expect(harness.controller.status, StaffSessionStatus.signedIn);
        expect(harness.store.refreshCookie, 'refresh-cookie');
        expect(harness.store.csrfToken, 'csrf-1');
      },
    );

    test('keeps the challenge available when the code is rejected', () async {
      final harness = _build();
      await harness.controller.startLogin(
        email: 'agent@example.test',
        password: 'password123',
      );
      harness.backend.codeRejected = true;

      await harness.controller.submitCode('000000');

      expect(harness.controller.status, StaffSessionStatus.awaitingCode);
      expect(harness.controller.message, 'Rejected by the API.');
      expect(harness.store.refreshCookie, isNull);

      harness.backend.codeRejected = false;
      await harness.controller.submitCode('123456');
      expect(harness.controller.status, StaffSessionStatus.signedIn);
    });

    test('signs in even when the API exposed no refresh cookie', () async {
      final harness = _build();
      harness.backend.exposeRefreshCookie = false;
      await harness.controller.startLogin(
        email: 'agent@example.test',
        password: 'password123',
      );

      await harness.controller.submitCode('123456');

      expect(harness.controller.status, StaffSessionStatus.signedIn);
      expect(harness.store.refreshCookie, isNull);
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

  group('access token', () {
    test('keeps the access token in memory after the TOTP login', () async {
      final harness = _build();
      expect(harness.controller.accessToken, isNull);
      await harness.controller.startLogin(
        email: 'agent@example.test',
        password: 'password123',
      );
      expect(harness.controller.accessToken, isNull);

      await harness.controller.submitCode('123456');

      expect(harness.controller.accessToken, 'access-token');
      expect(harness.store.refreshCookie, isNot('access-token'));
      expect(harness.store.csrfToken, isNot('access-token'));
    });

    test('takes the rotated access token when restoring a session', () async {
      final harness = _build(cookie: 'refresh-cookie', csrf: 'csrf-1');

      await harness.controller.restore();

      expect(harness.controller.accessToken, 'access-token');
    });

    test('forgets the access token when the API rejects the session', () async {
      final harness = _build(cookie: 'refresh-cookie', csrf: 'csrf-1');
      await harness.controller.restore();
      harness.backend.refreshRejected = true;

      await harness.controller.restore();

      expect(harness.controller.status, StaffSessionStatus.signedOut);
      expect(harness.controller.accessToken, isNull);
    });

    test('forgets the access token on logout', () async {
      final harness = _build(cookie: 'refresh-cookie', csrf: 'csrf-1');
      await harness.controller.restore();

      await harness.controller.signOut();

      expect(harness.controller.accessToken, isNull);
    });
  });
  group('login without TOTP', () {
    test('opens the session with the password alone', () async {
      final harness = _build();
      harness.backend.totpRequired = false;

      await harness.controller.startLogin(
        email: 'agent@example.test',
        password: 'secret',
      );

      expect(harness.controller.status, StaffSessionStatus.signedIn);
      expect(harness.backend.calls, contains('/api/v1/auth/login/totp'));
      expect(harness.backend.lastCompletionBody, {
        'challenge_token': 'challenge-1',
      });
    });

    test('still asks for the code when the server requires TOTP', () async {
      final harness = _build();

      await harness.controller.startLogin(
        email: 'agent@example.test',
        password: 'secret',
      );

      expect(harness.controller.status, StaffSessionStatus.awaitingCode);
      expect(harness.backend.calls, isNot(contains('/api/v1/auth/login/totp')));

      await harness.controller.submitCode('123456');

      expect(harness.controller.status, StaffSessionStatus.signedIn);
      expect(harness.backend.lastCompletionBody, {
        'challenge_token': 'challenge-1',
        'code': '123456',
      });
    });
  });
}
