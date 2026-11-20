import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'push_messaging.dart';

/// Keeps this device's FCM token registered with the backend while agency staff
/// is signed in (`/api/v1/staff/devices`).
///
/// Everything here is best effort: a denied permission, a missing Firebase
/// setup, or a network error never affects the session or the UI.
class DevicePushRegistrar {
  DevicePushRegistrar({
    required String baseUrl,
    required Future<String> Function() accessTokenProvider,
    required PushMessaging messaging,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _accessTokenProvider = accessTokenProvider,
       _messaging = messaging,
       _client = client ?? http.Client();

  static const String _path = '/api/v1/staff/devices';

  final String _baseUrl;
  final Future<String> Function() _accessTokenProvider;
  final PushMessaging _messaging;
  final http.Client _client;
  final Duration timeout;

  String? _registeredToken;
  bool _registering = false;
  StreamSubscription<String>? _refreshes;

  /// The token currently registered with the backend, if any.
  String? get registeredToken => _registeredToken;

  /// Registers the device whenever [session] reports signed-in staff.
  void attach(Listenable session, {required bool Function() isSignedIn}) {
    session.addListener(() {
      if (isSignedIn()) register();
    });
  }

  /// Asks for permission, reads the token and registers it. Safe to call
  /// repeatedly: it does nothing while a token is already registered.
  Future<void> register() async {
    if (_registering || _registeredToken != null) return;
    _registering = true;
    try {
      if (!await _messaging.requestPermission()) return;
      final token = await _messaging.obtainToken();
      if (token == null || token.isEmpty) return;
      await _post(_path, {'token': token, 'platform': 'android'});
      _registeredToken = token;
      _refreshes ??= _messaging.tokenRefreshes.listen(_onRefresh);
    } catch (_) {
      // Push is optional; the next sign-in or restore tries again.
    } finally {
      _registering = false;
    }
  }

  /// Removes this device from the signed-in staff member. Call it before the
  /// session ends, while the access token is still valid.
  Future<void> unregister() async {
    final token = _registeredToken;
    if (token == null) return;
    _registeredToken = null;
    try {
      await _post('$_path/remove', {'token': token});
    } catch (_) {
      // The backend drops tokens FCM reports as gone, so a missed call heals.
    }
  }

  Future<void> _onRefresh(String token) async {
    if (_registeredToken == null) return;
    try {
      await _post(_path, {'token': token, 'platform': 'android'});
      _registeredToken = token;
    } catch (_) {
      // Keep the previous registration; the next sign-in registers the new token.
    }
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    final accessToken = await _accessTokenProvider();
    final response = await _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Device registration failed',
        response.request?.url,
      );
    }
  }

  void dispose() {
    _refreshes?.cancel();
    _refreshes = null;
  }
}
