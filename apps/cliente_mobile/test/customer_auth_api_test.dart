import 'dart:convert';

import 'package:cliente_mobile/data/services/customer_auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'https://api.example.test';

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

void main() {
  group('CustomerAuthApi', () {
    test('register posts credentials and returns the created identity', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _json(const {'id': 'customer-1', 'email': 'client@example.test'}, 201);
      });
      final api = CustomerAuthApi(baseUrl: _baseUrl, client: client);

      final identity = await api.register(
        email: 'client@example.test',
        password: 'password123',
      );

      expect(captured.method, 'POST');
      expect(captured.url.toString(), '$_baseUrl/api/v1/customer/auth/register');
      expect(
        jsonDecode(captured.body),
        {'email': 'client@example.test', 'password': 'password123'},
      );
      expect(identity.id, 'customer-1');
      expect(identity.email, 'client@example.test');
    });

    test('login returns the rotated token pair with its access lifetime', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _json(const {
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'token_type': 'Bearer',
          'access_expires_in': 900,
        }, 200);
      });
      final api = CustomerAuthApi(baseUrl: _baseUrl, client: client);

      final tokens = await api.login(
        email: 'client@example.test',
        password: 'password123',
      );

      expect(captured.url.path, '/api/v1/customer/auth/login');
      expect(tokens.accessToken, 'access-token');
      expect(tokens.refreshToken, 'refresh-token');
      expect(tokens.accessExpiresIn, const Duration(minutes: 15));
    });

    test('refresh sends the opaque refresh token in the body', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _json(const {
          'access_token': 'access-token-2',
          'refresh_token': 'refresh-token-2',
          'token_type': 'Bearer',
          'access_expires_in': 900,
        }, 200);
      });
      final api = CustomerAuthApi(baseUrl: _baseUrl, client: client);

      final tokens = await api.refresh(refreshToken: 'refresh-token');

      expect(captured.url.path, '/api/v1/customer/auth/refresh');
      expect(jsonDecode(captured.body), {'refresh_token': 'refresh-token'});
      expect(tokens.refreshToken, 'refresh-token-2');
    });

    test('logout tolerates the empty 204 response', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });
      final api = CustomerAuthApi(baseUrl: _baseUrl, client: client);

      await api.logout(refreshToken: 'refresh-token');

      expect(captured.url.path, '/api/v1/customer/auth/logout');
      expect(captured.headers['Authorization'], isNull);
    });

    test('fetchIdentity sends the bearer access token', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _json(const {'id': 'customer-1', 'email': 'client@example.test'}, 200);
      });
      final api = CustomerAuthApi(baseUrl: _baseUrl, client: client);

      final identity = await api.fetchIdentity(accessToken: 'access-token');

      expect(captured.url.path, '/api/v1/customer/auth/me');
      expect(captured.headers['Authorization'], 'Bearer access-token');
      expect(identity.email, 'client@example.test');
    });

    test('maps the shared error envelope for every rejected call', () async {
      Future<CustomerAuthFailure> failureFor(
        Future<void> Function(CustomerAuthApi api) call,
        int status,
        String code,
      ) async {
        final client = MockClient(
          (_) async => _json({'detail': 'Rejected by the API.', 'code': code}, status),
        );
        final api = CustomerAuthApi(baseUrl: _baseUrl, client: client);
        try {
          await call(api);
        } on CustomerAuthFailure catch (failure) {
          return failure;
        }
        fail('expected a CustomerAuthFailure for status $status');
      }

      final unauthorized = await failureFor(
        (api) => api.login(email: 'client@example.test', password: 'password123'),
        401,
        'unauthorized',
      );
      final conflict = await failureFor(
        (api) => api.register(email: 'client@example.test', password: 'password123'),
        409,
        'conflict',
      );
      final validation = await failureFor(
        (api) => api.refresh(refreshToken: 'refresh-token'),
        422,
        'validation_error',
      );

      expect(unauthorized.statusCode, 401);
      expect(unauthorized.code, 'unauthorized');
      expect(unauthorized.detail, 'Rejected by the API.');
      expect(unauthorized.isNetworkFailure, isFalse);
      expect(conflict.code, 'conflict');
      expect(validation.code, 'validation_error');
    });

    test('reports a network failure when the transport throws', () async {
      final client = MockClient((_) async => throw http.ClientException('offline'));
      final api = CustomerAuthApi(baseUrl: _baseUrl, client: client);

      await expectLater(
        api.login(email: 'client@example.test', password: 'password123'),
        throwsA(
          isA<CustomerAuthFailure>()
              .having((failure) => failure.isNetworkFailure, 'isNetworkFailure', isTrue)
              .having((failure) => failure.code, 'code', 'network_error'),
        ),
      );
    });

    test('does not leak a malformed body when the response is not the envelope', () async {
      final client = MockClient(
        (_) async => http.Response('<html>gateway exploded</html>', 502),
      );
      final api = CustomerAuthApi(baseUrl: _baseUrl, client: client);

      await expectLater(
        api.login(email: 'client@example.test', password: 'password123'),
        throwsA(
          isA<CustomerAuthFailure>()
              .having((failure) => failure.statusCode, 'statusCode', 502)
              .having((failure) => failure.code, 'code', 'dependency_unavailable')
              .having(
                (failure) => failure.detail,
                'detail',
                isNot(contains('gateway exploded')),
              ),
        ),
      );
    });
  });
}
