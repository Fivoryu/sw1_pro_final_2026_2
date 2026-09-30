import 'package:flutter/foundation.dart';

import '../data/models/customer_models.dart';
import '../data/services/customer_auth_api.dart';
import '../data/services/customer_token_store.dart';

/// Lifecycle state of the customer session.
enum CustomerSessionStatus {
  /// The app is reading the stored token and validating it.
  restoring,

  /// No usable session: the UI must offer login or registration.
  signedOut,

  /// The customer has a valid session and identity.
  signedIn,

  /// The API could not be reached, so a stored session may still be valid.
  unavailable,
}

/// Owns the customer session lifecycle: restoration, login, registration,
/// denial, network failures, and logout.
///
/// The opaque refresh token is the only persisted value; access tokens are
/// requested per call and never stored.
class CustomerSessionController extends ChangeNotifier {
  CustomerSessionController({
    required CustomerAuthApi api,
    required CustomerTokenStore tokenStore,
  }) : _api = api,
       _tokenStore = tokenStore;

  final CustomerAuthApi _api;
  final CustomerTokenStore _tokenStore;

  CustomerSessionStatus _status = CustomerSessionStatus.restoring;
  CustomerIdentity? _identity;
  String? _message;

  CustomerSessionStatus get status => _status;
  CustomerIdentity? get identity => _identity;

  /// User-facing notice for the last failure or confirmation, if any.
  String? get message => _message;

  /// Restores a stored session when the app starts.
  ///
  /// A rejected token signs the customer out; an unreachable API keeps the
  /// stored token so the caller can retry without losing the session.
  Future<void> restore() async {
    _status = CustomerSessionStatus.restoring;
    _message = null;
    notifyListeners();

    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) {
      _setSignedOut();
      return;
    }
    try {
      final tokens = await _api.refresh(refreshToken: refreshToken);
      await _tokenStore.writeRefreshToken(tokens.refreshToken);
      await _loadIdentity(tokens.accessToken);
    } on CustomerAuthFailure catch (failure) {
      if (failure.isNetworkFailure) {
        _status = CustomerSessionStatus.unavailable;
        _message = failure.detail;
        notifyListeners();
      } else {
        await _discardSession(message: failure.detail);
      }
    }
  }

  /// Revokes the session. A rejected token still signs out locally; a network
  /// failure keeps the session so the customer can retry.
  Future<void> signOut() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _api.logout(refreshToken: refreshToken);
      } on CustomerAuthFailure catch (failure) {
        if (failure.isNetworkFailure) {
          _message = failure.detail;
          notifyListeners();
          return;
        }
      }
    }
    await _tokenStore.clearRefreshToken();
    _setSignedOut();
  }

  Future<void> _loadIdentity(String accessToken) async {
    try {
      _identity = await _api.fetchIdentity(accessToken: accessToken);
      _status = CustomerSessionStatus.signedIn;
      _message = null;
      notifyListeners();
    } on CustomerAuthFailure catch (failure) {
      await _discardSession(message: failure.detail);
    }
  }

  Future<void> _discardSession({String? message}) async {
    await _tokenStore.clearRefreshToken();
    _setSignedOut(message: message);
  }

  void _setSignedOut({String? message}) {
    _status = CustomerSessionStatus.signedOut;
    _identity = null;
    _message = message;
    notifyListeners();
  }
}
