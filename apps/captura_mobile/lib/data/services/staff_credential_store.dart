import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence boundary for the staff session credentials.
///
/// The staff API is browser-shaped: the refresh token lives in an HttpOnly
/// cookie and refresh/logout also need the CSRF token. A mobile client has no
/// cookie jar, so both values are held here behind one interface.
abstract interface class StaffCredentialStore {
  Future<String?> readRefreshCookie();

  Future<String?> readCsrfToken();

  Future<void> save({required String refreshCookie, required String csrfToken});

  Future<void> saveCsrfToken(String csrfToken);

  /// Id of the account the stored session belongs to. It is not a secret; it
  /// only selects whose local data the offline mode may show.
  Future<String?> readOwnerId();

  Future<void> saveOwnerId(String ownerId);

  Future<void> clear();
}

/// Keychain/Keystore-backed implementation used by the running app.
class SecureStaffCredentialStore implements StaffCredentialStore {
  SecureStaffCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String refreshCookieKey = 'roomforge.staff.refresh_cookie';
  static const String csrfTokenKey = 'roomforge.staff.csrf_token';
  static const String ownerIdKey = 'roomforge.staff.owner_id';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshCookie() async {
    final value = await _storage.read(key: refreshCookieKey);
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<String?> readCsrfToken() => _storage.read(key: csrfTokenKey);

  @override
  Future<void> save({
    required String refreshCookie,
    required String csrfToken,
  }) async {
    await _storage.write(key: refreshCookieKey, value: refreshCookie);
    await _storage.write(key: csrfTokenKey, value: csrfToken);
  }

  @override
  Future<void> saveCsrfToken(String csrfToken) =>
      _storage.write(key: csrfTokenKey, value: csrfToken);

  @override
  Future<String?> readOwnerId() async {
    final value = await _storage.read(key: ownerIdKey);
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<void> saveOwnerId(String ownerId) =>
      _storage.write(key: ownerIdKey, value: ownerId);

  @override
  Future<void> clear() async {
    await _storage.delete(key: refreshCookieKey);
    await _storage.delete(key: csrfTokenKey);
    await _storage.delete(key: ownerIdKey);
  }
}
