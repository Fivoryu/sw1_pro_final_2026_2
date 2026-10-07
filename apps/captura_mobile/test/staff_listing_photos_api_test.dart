import 'dart:convert';
import 'dart:typed_data';

import 'package:captura_mobile/data/services/staff_auth_failure.dart';
import 'package:captura_mobile/data/services/staff_listing_photos_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'https://api.example.test';
const _photos = '/api/v1/staff/agencies/agency-1/listings/listing-1/photos';
const _uploadUrl =
    'https://storage.example.test/bucket/agencies/agency-1/photo-1?X-Amz-Signature=abc';

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _photoBody({String id = 'photo-1'}) => {
  'photo_id': id,
  'content_type': 'image/jpeg',
  'size_bytes': 2048,
  'url': 'https://storage.example.test/bucket/$id?download=1',
  'created_at': '2026-10-06T12:00:00Z',
};

({StaffListingPhotosApi api, List<http.Request> requests}) _build(
  Future<http.Response> Function(http.Request request) handler,
) {
  final requests = <http.Request>[];
  return (
    api: StaffListingPhotosApi(
      baseUrl: '$_baseUrl/',
      client: MockClient((request) {
        requests.add(request);
        return handler(request);
      }),
    ),
    requests: requests,
  );
}

void main() {
  test('lists the confirmed photos of a listing', () async {
    final harness = _build(
      (_) async => _json({
        'photos': [_photoBody(), _photoBody(id: 'photo-2')],
      }, 200),
    );

    final photos = await harness.api.listPhotos(
      accessToken: 'access-token',
      agencyId: 'agency-1',
      listingId: 'listing-1',
    );

    final request = harness.requests.single;
    expect(request.method, 'GET');
    expect(request.url.path, _photos);
    expect(request.headers['Authorization'], 'Bearer access-token');
    expect(photos.map((photo) => photo.photoId), ['photo-1', 'photo-2']);
    expect(photos.first.url, contains('photo-1'));
    expect(photos.first.createdAt, DateTime.utc(2026, 10, 6, 12));
  });

  test('requests an upload link for one photo', () async {
    final harness = _build(
      (_) async => _json({
        'photo_id': 'photo-1',
        'upload_url': _uploadUrl,
        'upload_method': 'PUT',
        'upload_headers': {'Content-Type': 'image/png'},
        'expires_at': '2026-10-06T12:15:00Z',
      }, 201),
    );

    final grant = await harness.api.requestUpload(
      accessToken: 'access-token',
      agencyId: 'agency-1',
      listingId: 'listing-1',
      contentType: 'image/png',
      sizeBytes: 4096,
    );

    final request = harness.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, _photos);
    expect(jsonDecode(request.body), {
      'content_type': 'image/png',
      'size_bytes': 4096,
    });
    expect(grant.photoId, 'photo-1');
    expect(grant.uploadUrl, _uploadUrl);
    expect(grant.headers, {'Content-Type': 'image/png'});
    expect(grant.expiresAt, DateTime.utc(2026, 10, 6, 12, 15));
  });

  test('uploads the bytes to storage without the session token and reports '
      'progress', () async {
    final harness = _build((_) async => http.Response('', 200));
    final bytes = Uint8List.fromList(List.generate(200000, (i) => i % 251));
    final progress = <double>[];

    await harness.api.upload(
      grant: PhotoUploadGrant(
        photoId: 'photo-1',
        uploadUrl: _uploadUrl,
        headers: const {'Content-Type': 'image/jpeg'},
        expiresAt: DateTime.utc(2026, 10, 6, 12, 15),
      ),
      bytes: bytes,
      onProgress: progress.add,
    );

    final request = harness.requests.single;
    expect(request.method, 'PUT');
    expect(request.url.toString(), _uploadUrl);
    expect(request.headers['Content-Type'], 'image/jpeg');
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(request.bodyBytes, bytes);
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
  });

  test('reports a storage rejection as a failure with its status', () async {
    final harness = _build((_) async => http.Response('<Error/>', 403));

    await expectLater(
      harness.api.upload(
        grant: PhotoUploadGrant(
          photoId: 'photo-1',
          uploadUrl: _uploadUrl,
          headers: const {'Content-Type': 'image/jpeg'},
          expiresAt: DateTime.utc(2026, 10, 6, 12, 15),
        ),
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(
        isA<StaffAuthFailure>().having(
          (failure) => failure.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
  });

  test('confirms an uploaded photo', () async {
    final harness = _build((_) async => _json(_photoBody(), 200));

    final photo = await harness.api.confirm(
      accessToken: 'access-token',
      agencyId: 'agency-1',
      listingId: 'listing-1',
      photoId: 'photo 1',
    );

    final request = harness.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '$_photos/photo%201/confirm');
    expect(photo.photoId, 'photo-1');
  });

  test('deletes a photo', () async {
    final harness = _build((_) async => http.Response('', 204));

    await harness.api.delete(
      accessToken: 'access-token',
      agencyId: 'agency-1',
      listingId: 'listing-1',
      photoId: 'photo-1',
    );

    final request = harness.requests.single;
    expect(request.method, 'DELETE');
    expect(request.url.path, '$_photos/photo-1');
    expect(request.headers['Authorization'], 'Bearer access-token');
  });

  test('keeps the status and code of a rejected confirmation', () async {
    final harness = _build(
      (_) async => _json({
        'detail': 'Upload is not a valid photo of its type',
        'code': 'validation_error',
      }, 422),
    );

    await expectLater(
      harness.api.confirm(
        accessToken: 'access-token',
        agencyId: 'agency-1',
        listingId: 'listing-1',
        photoId: 'photo-1',
      ),
      throwsA(
        isA<StaffAuthFailure>()
            .having((failure) => failure.statusCode, 'statusCode', 422)
            .having((failure) => failure.code, 'code', kValidationError),
      ),
    );
  });

  test('reports a transport error as a network failure', () async {
    final harness = _build((_) async => throw http.ClientException('offline'));

    await expectLater(
      harness.api.listPhotos(
        accessToken: 'access-token',
        agencyId: 'agency-1',
        listingId: 'listing-1',
      ),
      throwsA(
        isA<StaffAuthFailure>().having(
          (failure) => failure.isNetworkFailure,
          'isNetworkFailure',
          isTrue,
        ),
      ),
    );
  });
}
