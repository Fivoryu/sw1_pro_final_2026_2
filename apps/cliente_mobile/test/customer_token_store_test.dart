import 'package:cliente_mobile/data/services/customer_token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('SecureCustomerTokenStore', () {
    test('returns null before any session is stored', () async {
      final store = SecureCustomerTokenStore();

      expect(await store.readRefreshToken(), isNull);
    });

    test('persists and reads back the refresh token', () async {
      final store = SecureCustomerTokenStore();

      await store.writeRefreshToken('refresh-token');

      expect(await store.readRefreshToken(), 'refresh-token');
      expect(
        await FlutterSecureStorage().read(
          key: SecureCustomerTokenStore.refreshTokenKey,
        ),
        'refresh-token',
      );
    });

    test('replaces a previous token instead of accumulating values', () async {
      final store = SecureCustomerTokenStore();

      await store.writeRefreshToken('first');
      await store.writeRefreshToken('second');

      expect(await store.readRefreshToken(), 'second');
    });

    test('clears the stored token on logout', () async {
      final store = SecureCustomerTokenStore();
      await store.writeRefreshToken('refresh-token');

      await store.clearRefreshToken();

      expect(await store.readRefreshToken(), isNull);
      expect(
        await FlutterSecureStorage().containsKey(
          key: SecureCustomerTokenStore.refreshTokenKey,
        ),
        isFalse,
      );
    });
  });
}
