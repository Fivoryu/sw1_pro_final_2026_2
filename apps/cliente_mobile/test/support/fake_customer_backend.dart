import 'dart:convert';

import 'package:cliente_mobile/data/services/customer_token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory stand-in for the keychain-backed store.
class InMemoryCustomerTokenStore implements CustomerTokenStore {
  InMemoryCustomerTokenStore([this.token]);

  String? token;
  int writes = 0;

  @override
  Future<String?> readRefreshToken() async => token;

  @override
  Future<void> writeRefreshToken(String value) async {
    token = value;
    writes += 1;
  }

  @override
  Future<void> clearRefreshToken() async => token = null;
}

/// Programmable stand-in for `/api/v1/customer/auth/*`.
class FakeCustomerBackend {
  FakeCustomerBackend({this.refreshToken = 'refresh-token'});

  String refreshToken;
  String email = 'client@example.test';
  bool offline = false;
  bool loginRejected = false;
  bool registerConflict = false;
  bool refreshRejected = false;
  bool logoutRejected = false;
  final List<String> calls = [];

  http.Client get client => MockClient(_handle);

  static http.Response _json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: const {'content-type': 'application/json'},
  );

  static http.Response _failure(int status, String code) => _json({
    'detail': 'Rejected by the API.',
    'code': code,
  }, status);

  Future<http.Response> _handle(http.Request request) async {
    calls.add(request.url.path);
    if (offline) throw http.ClientException('offline');
    return switch (request.url.path) {
      '/api/v1/customer/auth/register' => registerConflict
          ? _failure(409, 'conflict')
          : _json({'id': 'customer-1', 'email': email}, 201),
      '/api/v1/customer/auth/login' => loginRejected
          ? _failure(401, 'unauthorized')
          : _json(_tokens('access-token', 'refresh-token-1'), 200),
      '/api/v1/customer/auth/refresh' => refreshRejected
          ? _failure(401, 'unauthorized')
          : _json(_tokens('access-token-2', 'refresh-token-2'), 200),
      '/api/v1/customer/auth/logout' => logoutRejected
          ? _failure(401, 'unauthorized')
          : http.Response('', 204),
      '/api/v1/customer/auth/me' => _json({
        'id': 'customer-1',
        'email': email,
      }, 200),
      _ => http.Response('', 404),
    };
  }

  static Map<String, Object?> _tokens(String access, String refresh) => {
    'access_token': access,
    'refresh_token': refresh,
    'token_type': 'Bearer',
    'access_expires_in': 900,
  };
}
