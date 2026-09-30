import 'dart:convert';

import 'package:captura_mobile/data/services/staff_credential_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory stand-in for the keychain-backed credential store.
class InMemoryStaffCredentialStore implements StaffCredentialStore {
  InMemoryStaffCredentialStore({this.refreshCookie, this.csrfToken});

  String? refreshCookie;
  String? csrfToken;

  @override
  Future<String?> readRefreshCookie() async =>
      (refreshCookie == null || refreshCookie!.isEmpty) ? null : refreshCookie;

  @override
  Future<String?> readCsrfToken() async => csrfToken;

  @override
  Future<void> save({
    required String refreshCookie,
    required String csrfToken,
  }) async {
    this.refreshCookie = refreshCookie;
    this.csrfToken = csrfToken;
  }

  @override
  Future<void> saveCsrfToken(String csrfToken) async {
    this.csrfToken = csrfToken;
  }

  @override
  Future<void> clear() async {
    refreshCookie = null;
    csrfToken = null;
  }
}

/// Programmable stand-in for `/api/v1/auth/*`.
class FakeStaffBackend {
  bool offline = false;
  bool loginRejected = false;
  bool codeRejected = false;
  bool refreshRejected = false;
  bool logoutRejected = false;
  bool exposeRefreshCookie = true;
  final List<String> calls = [];

  http.Client get client => MockClient(_handle);

  static http.Response _json(Object body, int status, {String? cookie}) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {
          'content-type': 'application/json',
          if (cookie != null)
            'set-cookie': 'roomforge_refresh=$cookie; HttpOnly; Path=/api/v1/auth',
        },
      );

  static http.Response _failure(int status, String code) => _json({
    'detail': 'Rejected by the API.',
    'code': code,
  }, status);

  static Map<String, Object?> _grantBody(String csrf) => {
    'access_token': 'access-token',
    'csrf_token': csrf,
    'user': {
      'id': 'staff-1',
      'email': 'agent@example.test',
      'role': 'agent',
      'tenant_id': 'agency-1',
    },
  };

  Future<http.Response> _handle(http.Request request) async {
    calls.add(request.url.path);
    if (offline) throw http.ClientException('offline');
    final cookie = exposeRefreshCookie ? 'refresh-cookie' : null;
    return switch (request.url.path) {
      '/api/v1/auth/login' => loginRejected
          ? _failure(401, 'unauthorized')
          : _json({'challenge_token': 'challenge-1'}, 200),
      '/api/v1/auth/login/totp' => codeRejected
          ? _failure(401, 'unauthorized')
          : _json(_grantBody('csrf-1'), 200, cookie: cookie),
      '/api/v1/auth/refresh' => refreshRejected
          ? _failure(401, 'unauthorized')
          : _json(_grantBody('csrf-2'), 200, cookie: 'rotated-cookie'),
      '/api/v1/auth/logout' => logoutRejected
          ? _failure(401, 'unauthorized')
          : http.Response('', 204),
      '/api/v1/auth/me' => _json({
        'user': {
          'id': 'staff-1',
          'email': 'agent@example.test',
          'role': 'agent',
          'tenant_id': 'agency-1',
        },
      }, 200),
      _ => http.Response('', 404),
    };
  }
}
