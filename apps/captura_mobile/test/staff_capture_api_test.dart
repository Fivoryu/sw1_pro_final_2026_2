import 'dart:convert';

import 'package:captura_mobile/data/services/staff_auth_failure.dart';
import 'package:captura_mobile/data/services/staff_capture_api.dart';
import 'package:captura_mobile/domain/spatial/capture_upload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_capture_backend.dart';

StaffCaptureApi _api(FakeCaptureBackend backend) => StaffCaptureApi(
  baseUrl: 'https://api.example.test/',
  client: backend.client,
);

Stream<List<int>> _bytes(List<int> data) => Stream.value(data);

void main() {
  group('register', () {
    test('posts the capture id and size to the listing route', () async {
      final backend = FakeCaptureBackend();

      final registration = await _api(backend).register(
        accessToken: 'tok',
        agencyId: 'agency 1',
        listingId: 'listing-1',
        captureId: 'cap-1',
        sizeBytes: 1234,
      );

      final request = backend.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/api/v1/staff/agencies/agency%201/listings/listing-1/captures',
      );
      expect(request.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(request.body), {
        'captureId': 'cap-1',
        'sizeBytes': 1234,
      });
      expect(registration.captureId, 'cap-1');
      expect(registration.status, RemoteCaptureStatus.awaitingUpload);
      expect(
        registration.uploadUrl,
        'https://storage.example.test/upload/cap-1?sig=1',
      );
      expect(registration.expiresAt, DateTime.utc(2026, 10, 21, 13));
    });

    test('repeating a registration returns the same capture', () async {
      final backend = FakeCaptureBackend();
      final api = _api(backend);
      Future<CaptureRegistration> register() => api.register(
        accessToken: 'tok',
        agencyId: 'a',
        listingId: 'l',
        captureId: 'cap-1',
        sizeBytes: 10,
      );

      final first = await register();
      final second = await register();

      expect(second.captureId, first.captureId);
      expect(backend.captures, hasLength(1));
    });

    test('maps a rejection to the staff failure vocabulary', () async {
      final backend = FakeCaptureBackend()..rejectRegistration = true;

      expect(
        _api(backend).register(
          accessToken: 'tok',
          agencyId: 'a',
          listingId: 'l',
          captureId: 'cap-1',
          sizeBytes: 10,
        ),
        throwsA(
          isA<StaffAuthFailure>()
              .having((f) => f.code, 'code', kValidationError)
              .having((f) => f.statusCode, 'status', 422),
        ),
      );
    });

    test('reports a lost connection as a network failure', () async {
      final backend = FakeCaptureBackend()..offline = true;

      expect(
        _api(backend).register(
          accessToken: 'tok',
          agencyId: 'a',
          listingId: 'l',
          captureId: 'cap-1',
          sizeBytes: 10,
        ),
        throwsA(
          isA<StaffAuthFailure>().having(
            (f) => f.isNetworkFailure,
            'net',
            true,
          ),
        ),
      );
    });

    test('rejects a registration without an upload URL', () async {
      final api = StaffCaptureApi(
        baseUrl: 'https://api.example.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'captureId': 'cap-1', 'status': 'awaiting_upload'}),
            201,
          ),
        ),
      );

      expect(
        api.register(
          accessToken: 't',
          agencyId: 'a',
          listingId: 'l',
          captureId: 'cap-1',
          sizeBytes: 1,
        ),
        throwsA(isA<StaffAuthFailure>()),
      );
    });

    test('rejects an unknown status instead of guessing', () async {
      final api = StaffCaptureApi(
        baseUrl: 'https://api.example.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'captureId': 'cap-1',
              'status': 'weird',
              'uploadUrl': 'https://x.test/u',
              'expiresAt': '2026-10-21T13:00:00Z',
            }),
            201,
          ),
        ),
      );

      expect(
        api.register(
          accessToken: 't',
          agencyId: 'a',
          listingId: 'l',
          captureId: 'cap-1',
          sizeBytes: 1,
        ),
        throwsA(isA<StaffAuthFailure>()),
      );
    });
  });

  group('upload', () {
    test(
      'PUTs the ZIP bytes to the signed URL without the staff token',
      () async {
        final backend = FakeCaptureBackend();
        backend.captures['cap-1'] = FakeCapture('cap-1', 4);
        final progress = <int>[];

        await _api(backend).upload(
          uploadUrl: 'https://storage.example.test/upload/cap-1?sig=1',
          body: Stream.fromIterable([
            [1, 2],
            [3, 4],
          ]),
          length: 4,
          onProgress: progress.add,
        );

        final request = backend.requests.single;
        expect(request.method, 'PUT');
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(request.headers['Content-Type'], 'application/zip');
        expect(backend.captures['cap-1']!.uploaded, [1, 2, 3, 4]);
        expect(progress, [2, 4]);
      },
    );

    test('resolves a relative upload URL against the API', () async {
      final backend = FakeCaptureBackend();
      final requests = <http.BaseRequest>[];
      final api = StaffCaptureApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('', 200);
        }),
      );

      await api.upload(
        uploadUrl: '/api/v1/uploads/cap-1?sig=9',
        body: _bytes([1]),
        length: 1,
      );

      expect(
        requests.single.url.toString(),
        'https://api.example.test/api/v1/uploads/cap-1?sig=9',
      );
      expect(backend.requests, isEmpty);
    });

    test('an expired signature is a distinct failure', () async {
      final backend = FakeCaptureBackend()..expirePuts = 1;

      expect(
        _api(backend).upload(
          uploadUrl: 'https://storage.example.test/upload/cap-1',
          body: _bytes([1]),
          length: 1,
        ),
        throwsA(isA<UploadUrlExpired>()),
      );
    });

    test('a lost connection is a network failure', () async {
      final backend = FakeCaptureBackend()..failPuts = 1;

      expect(
        _api(backend).upload(
          uploadUrl: 'https://storage.example.test/upload/cap-1',
          body: _bytes([1]),
          length: 1,
        ),
        throwsA(
          isA<StaffAuthFailure>().having(
            (f) => f.isNetworkFailure,
            'net',
            true,
          ),
        ),
      );
    });

    test('a storage error becomes a retryable failure', () async {
      final api = StaffCaptureApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((_) async => http.Response('boom', 500)),
      );

      expect(
        api.upload(
          uploadUrl: 'https://storage.example.test/u',
          body: _bytes([1]),
          length: 1,
        ),
        throwsA(
          isA<StaffAuthFailure>().having((f) => f.code, 'code', kInternalError),
        ),
      );
    });
  });

  group('complete and status', () {
    test('complete is idempotent and reports the queue state', () async {
      final backend = FakeCaptureBackend();
      final api = _api(backend);
      await api.register(
        accessToken: 't',
        agencyId: 'a',
        listingId: 'l',
        captureId: 'cap-1',
        sizeBytes: 1,
      );

      final first = await api.complete(
        accessToken: 't',
        agencyId: 'a',
        listingId: 'l',
        captureId: 'cap-1',
      );
      final second = await api.complete(
        accessToken: 't',
        agencyId: 'a',
        listingId: 'l',
        captureId: 'cap-1',
      );

      expect(first, RemoteCaptureStatus.queued);
      expect(second, RemoteCaptureStatus.queued);
      expect(
        backend.requests.last.url.path,
        '/api/v1/staff/agencies/a/listings/l/captures/cap-1/complete',
      );
    });

    test('status returns the failure reason and warnings', () async {
      final backend = FakeCaptureBackend();
      final api = _api(backend);
      await api.register(
        accessToken: 't',
        agencyId: 'a',
        listingId: 'l',
        captureId: 'cap-1',
        sizeBytes: 1,
      );
      backend.statusScript.add(('failed', 'Sin piso detectado'));

      final report = await api.status(
        accessToken: 't',
        agencyId: 'a',
        listingId: 'l',
        captureId: 'cap-1',
      );

      expect(report.status, RemoteCaptureStatus.failed);
      expect(report.failureReason, 'Sin piso detectado');
      expect(report.warnings, isEmpty);
    });

    test('status of an unknown capture is a not-found failure', () async {
      expect(
        _api(FakeCaptureBackend()).status(
          accessToken: 't',
          agencyId: 'a',
          listingId: 'l',
          captureId: 'nope',
        ),
        throwsA(
          isA<StaffAuthFailure>().having((f) => f.code, 'code', kNotFound),
        ),
      );
    });

    test('status with a body that is not the contract is malformed', () async {
      final api = StaffCaptureApi(
        baseUrl: 'https://api.example.test',
        client: MockClient((_) async => http.Response('[]', 200)),
      );

      expect(
        api.status(
          accessToken: 't',
          agencyId: 'a',
          listingId: 'l',
          captureId: 'c',
        ),
        throwsA(isA<StaffAuthFailure>()),
      );
    });
  });
}
