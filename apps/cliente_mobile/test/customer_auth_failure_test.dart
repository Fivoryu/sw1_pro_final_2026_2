import 'package:cliente_mobile/data/services/customer_auth_failure.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('falls back to the status when the body is not the envelope', () {
      final failure = failureFromResponse(
        statusCode: 502,
        body: '<html>gateway exploded</html>',
      );

      expect(failure.code, kDependencyUnavailable);
      expect(failure.detail, kSafeFailureDetails[kDependencyUnavailable]);
      expect(failure.detail, isNot(contains('gateway exploded')));
      expect(failure.statusCode, 502);
    });

    test('never exposes an envelope missing detail or code', () {
      final partial = failureFromResponse(
        statusCode: 500,
        body: '{"code":"unauthorized"}',
      );
      final wrongTypes = failureFromResponse(
        statusCode: 409,
        body: '{"detail":7,"code":false}',
      );

      expect(partial.code, kInternalError);
      expect(partial.detail, kSafeFailureDetails[kInternalError]);
      expect(wrongTypes.code, kConflict);
      expect(wrongTypes.detail, kSafeFailureDetails[kConflict]);
    });

    test('treats an empty body as a status-only failure', () {
      final failure = failureFromResponse(statusCode: 503, body: '');

      expect(failure.code, kDependencyUnavailable);
      expect(failure.detail, kSafeFailureDetails[kDependencyUnavailable]);
    });
  });

  group('local failures', () {
    test('network failures are retryable and carry no status', () {
      final failure = networkFailure();

      expect(failure.code, kNetworkError);
      expect(failure.isNetworkFailure, isTrue);
      expect(failure.statusCode, isNull);
      expect(failure.detail, kSafeFailureDetails[kNetworkError]);
    });

    test('malformed success bodies never leak content', () {
      final failure = malformedResponseFailure();

      expect(failure.code, kInternalError);
      expect(failure.detail, kSafeFailureDetails[kInternalError]);
      expect(failure.isNetworkFailure, isFalse);
    });
  });
}
