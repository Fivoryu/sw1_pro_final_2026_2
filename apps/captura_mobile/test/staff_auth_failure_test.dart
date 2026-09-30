import 'package:captura_mobile/data/services/staff_auth_failure.dart';
import 'package:flutter_test/flutter_test.dart';

const _cookieHeader =
    'roomforge_refresh=refresh-value; HttpOnly; Path=/api/v1/auth; SameSite=Lax';

void main() {
  group('codeForStatus', () {
    test('maps every documented status to the shared vocabulary', () {
      expect(codeForStatus(400), kValidationError);
      expect(codeForStatus(422), kValidationError);
      expect(codeForStatus(401), kUnauthorized);
      expect(codeForStatus(403), kForbidden);
      expect(codeForStatus(404), kNotFound);
      expect(codeForStatus(409), kConflict);
      expect(codeForStatus(502), kDependencyUnavailable);
      expect(codeForStatus(503), kDependencyUnavailable);
      expect(codeForStatus(504), kDependencyUnavailable);
      expect(codeForStatus(500), kInternalError);
      expect(codeForStatus(418), kInternalError);
    });
  });

  group('failureFromResponse', () {
    test('trusts the documented envelope', () {
      final failure = failureFromResponse(
        statusCode: 401,
        body: '{"detail":"Authentication failed.","code":"unauthorized"}',
      );

      expect(failure.code, kUnauthorized);
      expect(failure.detail, 'Authentication failed.');
      expect(failure.statusCode, 401);
      expect(failure.isNetworkFailure, isFalse);
    });

    test('falls back to the status and never leaks an unparsed body', () {
      final failure = failureFromResponse(
        statusCode: 502,
        body: '<html>gateway exploded</html>',
      );

      expect(failure.code, kDependencyUnavailable);
      expect(failure.detail, kSafeFailureDetails[kDependencyUnavailable]);
      expect(failure.detail, isNot(contains('gateway exploded')));
    });

    test('rejects an envelope missing detail or code', () {
      expect(
        failureFromResponse(statusCode: 500, body: '{"code":"unauthorized"}')
            .code,
        kInternalError,
      );
      expect(
        failureFromResponse(statusCode: 409, body: '{"detail":7,"code":false}')
            .code,
        kConflict,
      );
      expect(
        failureFromResponse(statusCode: 503, body: '').code,
        kDependencyUnavailable,
      );
    });
  });

  group('local failures', () {
    test('network failures are retryable and carry no status', () {
      final failure = networkFailure();

      expect(failure.code, kNetworkError);
      expect(failure.isNetworkFailure, isTrue);
      expect(failure.statusCode, isNull);
    });

    test('malformed success bodies never leak content', () {
      final failure = malformedResponseFailure();

      expect(failure.code, kInternalError);
      expect(failure.isNetworkFailure, isFalse);
    });
  });

  group('readRefreshCookie', () {
    test('extracts the opaque value from a multi-part set-cookie header', () {
      expect(
        readRefreshCookie(const {'set-cookie': _cookieHeader}),
        'refresh-value',
      );
    });

    test('returns null when the header is absent or holds another cookie', () {
      expect(readRefreshCookie(const {}), isNull);
      expect(readRefreshCookie(const {'set-cookie': 'other=1; Path=/'}), isNull);
      expect(
        readRefreshCookie(const {'set-cookie': 'roomforge_refresh=; Path=/'}),
        isNull,
      );
    });
  });
}
