import 'dart:convert';

import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'https://api.example.test';
const _cookieHeader =
    'roomforge_refresh=refresh-value; HttpOnly; Path=/api/v1/auth; SameSite=Lax';

http.Response _json(Object body, int status, {Map<String, String>? headers}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {
        'content-type': 'application/json',
        ...?headers,
      },
    );

Map<String, Object?> _loginBody() => const {
  'access_token': 'access-token',
  'csrf_token': 'csrf-token',
  'user': {
    'id': 'staff-1',
    'email': 'agent@example.test',
    'role': 'agent',
    'tenant_id': 'agency-1',
  },
};

void main() {
  group('StaffAuthApi two-step login', () {
    test('starts the login with credentials and returns a challenge', () async {
      late http.Request captured;
      final api = StaffAuthApi(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          captured = request;
          return _json(const {'challenge_token': 'challenge-1'}, 200);
        }),
      );

      final challenge = await api.startLogin(
        email: 'agent@example.test',
        password: 'password123',
      );

      expect(captured.url.path, '/api/v1/auth/login');
      expect(jsonDecode(captured.body), {
        'email': 'agent@example.test',
        'password': 'password123',
      });
      expect(challenge.challengeToken, 'challenge-1');
    });

    test('completes the login and captures the refresh cookie', () async {
      late http.Request captured;
      final api = StaffAuthApi(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          captured = request;
          return _json(
            _loginBody(),
            200,
            headers: {'set-cookie': _cookieHeader},
          );
        }),
      );

      final grant = await api.completeLogin(
        challengeToken: 'challenge-1',
        code: '123456',
      );

      expect(captured.url.path, '/api/v1/auth/login/totp');
      expect(jsonDecode(captured.body), {
        'challenge_token': 'challenge-1',
        'code': '123456',
      });
      expect(grant.accessToken, 'access-token');
      expect(grant.csrfToken, 'csrf-token');
      expect(grant.account.email, 'agent@example.test');
      expect(grant.account.role, 'agent');
      expect(grant.account.tenantId, 'agency-1');
      expect(grant.refreshCookie, 'refresh-value');
    });

    test('keeps a valid session when the response exposed no cookie', () async {
      final api = StaffAuthApi(
        baseUrl: _baseUrl,
        client: MockClient((_) async => _json(_loginBody(), 200)),
      );

      final grant = await api.completeLogin(
        challengeToken: 'challenge-1',
        code: '123456',
      );

      expect(grant.accessToken, 'access-token');
      expect(grant.refreshCookie, isNull);
    });

    test('reports a rejected proof through the shared envelope', () async {
      final api = StaffAuthApi(
        baseUrl: _baseUrl,
        client: MockClient(
          (_) async => _json(
            {'detail': 'The proof was rejected.', 'code': 'unauthorized'},
            401,
          ),
        ),
      );

      await expectLater(
        api.completeLogin(challengeToken: 'challenge-1', code: '000000'),
        throwsA(
          isA<StaffAuthFailure>()
              .having((failure) => failure.statusCode, 'statusCode', 401)
              .having((failure) => failure.code, 'code', kUnauthorized)
              .having(
                (failure) => failure.detail,
                'detail',
                'The proof was rejected.',
              ),
        ),
      );
    });
  });

}
