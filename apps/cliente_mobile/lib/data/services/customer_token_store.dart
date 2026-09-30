import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence boundary for the opaque customer refresh token.
///
/// The session logic depends on this interface so tests can substitute an
/// in-memory implementation without touching platform channels.
abstract interface class CustomerTokenStore {
  Future<String?> readRefreshToken();

  Future<void> writeRefreshToken(String token);

  Future<void> clearRefreshToken();
}

/// Keychain/Keystore-backed implementation used by the running app.
class SecureCustomerTokenStore implements CustomerTokenStore {
  SecureCustomerTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String refreshTokenKey = 'roomforge.customer.refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() => _storage.read(key: refreshTokenKey);

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: refreshTokenKey, value: token);

  @override
  Future<void> clearRefreshToken() => _storage.delete(key: refreshTokenKey);
}
