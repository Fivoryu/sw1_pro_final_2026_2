import 'package:flutter/foundation.dart';

import '../data/services/offline_listing_store.dart';
import '../data/services/staff_auth_api.dart';
import '../data/services/staff_credential_store.dart';

/// Lifecycle state of the staff session in the capture app.
enum StaffSessionStatus {
  /// The app is validating stored credentials.
  restoring,

  /// No session: the agent must send credentials.
  signedOut,

  /// Credentials were accepted; the TOTP proof is pending.
  awaitingCode,

  /// The agent has an authenticated session.
  signedIn,

  /// The API could not be reached, so stored credentials may still be valid.
  unavailable,

  /// No network at app start, but a session was already stored on this phone.
  /// Narrow capture-only mode: there is no access token and no authenticated
  /// API call; only the local listing list, recording and the upload queue.
  offline,
}

/// Owns the staff session: two-step login, restoration, denial, network
/// failures, and logout.
///
/// The access token lives only in memory, for authenticated API calls; only the
/// refresh cookie value and the CSRF token are persisted, because the API
/// refreshes through them.
class StaffSessionController extends ChangeNotifier {
  StaffSessionController({
    required StaffAuthApi api,
    required StaffCredentialStore credentialStore,
    OfflineListingStore? offlineStore,
    this.beforeSignOut,
  }) : _api = api,
       _credentialStore = credentialStore,
       _offlineStore = offlineStore;

  /// Runs while the access token is still valid, just before the session ends
  /// (for example to unregister the push token). Failures are ignored.
  final Future<void> Function()? beforeSignOut;

  final StaffAuthApi _api;
  final StaffCredentialStore _credentialStore;
  final OfflineListingStore? _offlineStore;

  StaffSessionStatus _status = StaffSessionStatus.restoring;
  StaffAccount? _account;
  String? _accessToken;
  StaffAccessChallenge? _challenge;
  String? _message;
  String? _offlineOwnerId;
  List<OfflineListing> _offlineListings = const [];

  StaffSessionStatus get status => _status;
  StaffAccount? get account => _account;

  /// Bearer token of the current session, held in memory only.
  String? get accessToken => _accessToken;

  /// User-facing notice for the last failure, if any.
  String? get message => _message;

  bool get isOffline => _status == StaffSessionStatus.offline;

  /// Account whose local data (upload queue, cached listings) may be used:
  /// the signed-in account, or the one of the stored session while offline.
  String? get ownerId => _account?.id ?? _offlineOwnerId;

  /// Listings this account downloaded before; only filled while offline.
  List<OfflineListing> get offlineListings => _offlineListings;

  /// Keeps [listings] (id and label only) for the offline mode of the signed-in
  /// account. Best effort: a failed write never breaks the online flow.
  Future<void> rememberListings(
    String bucket,
    List<OfflineListing> listings,
  ) async {
    final owner = _account?.id;
    final store = _offlineStore;
    if (owner == null || store == null) return;
    try {
      await store.write(owner, bucket, listings);
    } on Object {
      // The cache is a convenience.
    }
  }

  /// Validates stored credentials when the app starts.
  Future<void> restore() async {
    _status = StaffSessionStatus.restoring;
    _message = null;
    _offlineOwnerId = null;
    _offlineListings = const [];
    notifyListeners();

    final refreshCookie = await _credentialStore.readRefreshCookie();
    final csrfToken = await _credentialStore.readCsrfToken();
    if (refreshCookie == null || csrfToken == null) {
      await _wipeOfflineCache();
      _setSignedOut();
      return;
    }

    try {
      final grant = await _api.refresh(
        csrfToken: csrfToken,
        refreshCookie: refreshCookie,
      );
      await _acceptGrant(grant);
    } on StaffAuthFailure catch (failure) {
      if (failure.isNetworkFailure) {
        await _enterOfflineOrUnavailable(failure.detail);
      } else {
        await _discardSession(message: failure.detail);
      }
    }
  }

  /// A stored session (cookie, CSRF and owner) lets the app open in the
  /// capture-only offline mode; anything less keeps the plain "no connection"
  /// state. Nothing here is a login: the real refresh still has to succeed.
  Future<void> _enterOfflineOrUnavailable(String detail) async {
    final owner = await _credentialStore.readOwnerId();
    final store = _offlineStore;
    if (owner == null || store == null) {
      _status = StaffSessionStatus.unavailable;
      _message = detail;
      notifyListeners();
      return;
    }
    try {
      _offlineListings = await store.read(owner);
    } on Object {
      _offlineListings = const [];
    }
    _offlineOwnerId = owner;
    _account = null;
    _accessToken = null;
    _status = StaffSessionStatus.offline;
    _message = null;
    notifyListeners();
  }

  Future<void> _wipeOfflineCache() async {
    _offlineOwnerId = null;
    _offlineListings = const [];
    try {
      await _offlineStore?.clear();
    } on Object {
      // Nothing more to do; the cache is unreachable without the owner id.
    }
  }

  /// First step: exchanges credentials for a login challenge. When the server
  /// does not require TOTP the challenge is completed at once, so the session
  /// opens with the password alone.
  Future<void> startLogin({
    required String email,
    required String password,
  }) async {
    _message = null;
    try {
      final challenge = await _api.startLogin(email: email, password: password);
      if (!challenge.totpRequired) {
        _challenge = null;
        final grant = await _api.completeLogin(
          challengeToken: challenge.challengeToken,
        );
        await _acceptGrant(grant);
        return;
      }
      _challenge = challenge;
      _status = StaffSessionStatus.awaitingCode;
      notifyListeners();
    } on StaffAuthFailure catch (failure) {
      _challenge = null;
      _applyFailure(failure);
    }
  }

  /// Second step: proves the TOTP code and opens the session.
  Future<void> submitCode(String code) async {
    final challenge = _challenge;
    if (challenge == null) {
      _setSignedOut(message: 'Volvé a ingresar tus credenciales.');
      return;
    }

    _message = null;
    try {
      final grant = await _api.completeLogin(
        challengeToken: challenge.challengeToken,
        code: code,
      );
      _challenge = null;
      await _acceptGrant(grant);
    } on StaffAuthFailure catch (failure) {
      if (failure.isNetworkFailure) {
        _status = StaffSessionStatus.unavailable;
      }
      _message = failure.detail;
      notifyListeners();
    }
  }

  /// Revokes the session. A rejected session still signs out locally; a network
  /// failure keeps it so the agent can retry.
  Future<void> signOut() async {
    try {
      await beforeSignOut?.call();
    } catch (_) {
      // Signing out must never depend on an optional cleanup step.
    }
    final refreshCookie = await _credentialStore.readRefreshCookie();
    final csrfToken = await _credentialStore.readCsrfToken();

    if (refreshCookie != null && csrfToken != null) {
      try {
        await _api.logout(csrfToken: csrfToken, refreshCookie: refreshCookie);
      } on StaffAuthFailure catch (failure) {
        if (failure.isNetworkFailure) {
          _message = failure.detail;
          notifyListeners();
          return;
        }
      }
    }

    await _discardSession();
  }

  Future<void> _acceptGrant(StaffAccessGrant grant) async {
    final refreshCookie = grant.refreshCookie;
    if (refreshCookie != null) {
      await _credentialStore.save(
        refreshCookie: refreshCookie,
        csrfToken: grant.csrfToken,
      );
    } else {
      // Without the cookie the session cannot be refreshed later; keep the CSRF
      // token only for the logout call.
      await _credentialStore.saveCsrfToken(grant.csrfToken);
    }

    final previousOwner = await _credentialStore.readOwnerId();
    if (previousOwner != null && previousOwner != grant.account.id) {
      // Another account took over this phone: its cache never carries over.
      await _wipeOfflineCache();
    }
    await _credentialStore.saveOwnerId(grant.account.id);
    _offlineOwnerId = null;
    _offlineListings = const [];
    _account = grant.account;
    _accessToken = grant.accessToken;
    _status = StaffSessionStatus.signedIn;
    _message = null;
    notifyListeners();
  }

  void _applyFailure(StaffAuthFailure failure) {
    if (failure.isNetworkFailure) {
      _status = StaffSessionStatus.unavailable;
      _message = failure.detail;
      notifyListeners();
      return;
    }
    _setSignedOut(message: failure.detail);
  }

  Future<void> _discardSession({String? message}) async {
    await _credentialStore.clear();
    await _wipeOfflineCache();
    _account = null;
    _accessToken = null;
    _challenge = null;
    _status = StaffSessionStatus.signedOut;
    _message = message;
    notifyListeners();
  }

  void _setSignedOut({String? message}) {
    _account = null;
    _accessToken = null;
    _challenge = null;
    _status = StaffSessionStatus.signedOut;
    _message = message;
    notifyListeners();
  }
}
