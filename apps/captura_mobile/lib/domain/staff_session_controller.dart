import 'package:flutter/foundation.dart';

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
  }) : _api = api,
       _credentialStore = credentialStore;

  final StaffAuthApi _api;
  final StaffCredentialStore _credentialStore;

  StaffSessionStatus _status = StaffSessionStatus.restoring;
  StaffAccount? _account;
  String? _accessToken;
  StaffAccessChallenge? _challenge;
  String? _message;

  StaffSessionStatus get status => _status;
  StaffAccount? get account => _account;

  /// Bearer token of the current session, held in memory only.
  String? get accessToken => _accessToken;

  /// User-facing notice for the last failure, if any.
  String? get message => _message;

  /// Validates stored credentials when the app starts.
  Future<void> restore() async {
    _status = StaffSessionStatus.restoring;
    _message = null;
    notifyListeners();

    final refreshCookie = await _credentialStore.readRefreshCookie();
    final csrfToken = await _credentialStore.readCsrfToken();
    if (refreshCookie == null || csrfToken == null) {
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
        _status = StaffSessionStatus.unavailable;
        _message = failure.detail;
        notifyListeners();
      } else {
        await _discardSession(message: failure.detail);
      }
    }
  }

  /// First step: exchanges credentials for a TOTP challenge.
  Future<void> startLogin({
    required String email,
    required String password,
  }) async {
    _message = null;
    try {
      _challenge = await _api.startLogin(email: email, password: password);
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
