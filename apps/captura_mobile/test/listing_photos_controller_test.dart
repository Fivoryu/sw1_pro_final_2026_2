import 'dart:typed_data';

import 'package:captura_mobile/data/services/photo_source.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_listing_photos_api.dart';
import 'package:captura_mobile/domain/listing_photos_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_listings_backend.dart';
import 'support/fake_photo_source.dart';
import 'support/fake_staff_backend.dart';

typedef _Harness = ({
  ListingPhotosController controller,
  FakeListingsBackend backend,
  FakePhotoSource source,
  List<String> changes,
});

Future<_Harness> _build({String status = 'draft'}) async {
  final session = StaffSessionController(
    api: StaffAuthApi(
      baseUrl: 'https://api.example.test',
      client: FakeStaffBackend().client,
    ),
    credentialStore: InMemoryStaffCredentialStore(),
  );
  await session.restore();
  await session.startLogin(email: 'agent@example.test', password: 'x');
  await session.submitCode('123456');
  final backend = FakeListingsBackend()..seed(id: 'listing-1', status: status);
  final source = FakePhotoSource();
  final changes = <String>[];
  final controller = ListingPhotosController(
    api: StaffListingPhotosApi(
      baseUrl: 'https://api.example.test',
      client: backend.client,
    ),
    session: session,
    source: source,
    listingId: 'listing-1',
    onListingChanged: () => changes.add('changed'),
  );
  return (
    controller: controller,
    backend: backend,
    source: source,
    changes: changes,
  );
}

void main() {
  group('load', () {
    test('loads the confirmed photos of the listing', () async {
      final harness = await _build();
      harness.backend
        ..seedPhoto('listing-1', photoId: 'photo-a')
        ..seedPhoto('listing-1', photoId: 'photo-b');

      await harness.controller.load();

      expect(harness.controller.loadState, PhotosLoadState.ready);
      expect(harness.controller.photos.map((photo) => photo.photoId), [
        'photo-a',
        'photo-b',
      ]);
      expect(harness.controller.count, 2);
      expect(harness.controller.canAdd, isTrue);
    });

    test('reports a failed load', () async {
      final harness = await _build();
      harness.backend.offline = true;

      await harness.controller.load();

      expect(harness.controller.loadState, PhotosLoadState.failed);
      expect(harness.controller.message, contains('conexión'));
      expect(harness.controller.canAdd, isFalse);
    });
  });

  group('add', () {
    test('uploads, confirms and lists a photo from the camera', () async {
      final harness = await _build();
      await harness.controller.load();
      harness.source.next = FakePhotoSource.jpeg();

      await harness.controller.add(PhotoOrigin.camera);

      expect(harness.source.origins, [PhotoOrigin.camera]);
      expect(harness.controller.uploads, isEmpty);
      expect(harness.controller.photos, hasLength(1));
      final photoId = harness.controller.photos.single.photoId;
      expect(harness.backend.storage[photoId], FakePhotoSource.jpeg().bytes);
      expect(harness.changes, ['changed']);
      final upload = harness.backend.requests.singleWhere(
        (request) => request.url.host == FakeListingsBackend.storageHost,
      );
      expect(upload.headers.containsKey('Authorization'), isFalse);
      expect(upload.headers['Content-Type'], 'image/jpeg');
    });

    test('does nothing when the agent cancels the picker', () async {
      final harness = await _build();
      await harness.controller.load();
      harness.source.next = null;

      await harness.controller.add(PhotoOrigin.gallery);

      expect(harness.controller.photos, isEmpty);
      expect(harness.controller.uploads, isEmpty);
      expect(harness.controller.message, isNull);
    });

    test('rejects an unsupported format before uploading', () async {
      final harness = await _build();
      await harness.controller.load();
      harness.source.error = const UnsupportedPhotoFormat();

      await harness.controller.add(PhotoOrigin.gallery);

      expect(harness.controller.message, contains('JPG, PNG o WebP'));
      expect(harness.controller.uploads, isEmpty);
      expect(
        harness.backend.requests.where((r) => r.method == 'POST'),
        isEmpty,
      );
    });

    test('rejects a photo above 5 MB before uploading', () async {
      final harness = await _build();
      await harness.controller.load();
      harness.source.next = PickedPhoto(
        bytes: Uint8List(5 * 1024 * 1024 + 1)..setAll(0, [0xFF, 0xD8, 0xFF]),
        contentType: 'image/jpeg',
      );

      await harness.controller.add(PhotoOrigin.gallery);

      expect(harness.controller.message, contains('5 MB'));
      expect(harness.controller.uploads, isEmpty);
    });

    test('keeps a failed upload to retry it with the same link', () async {
      final harness = await _build();
      await harness.controller.load();
      harness.backend.storageOffline = true;
      harness.source.next = FakePhotoSource.jpeg();

      await harness.controller.add(PhotoOrigin.camera);

      final failed = harness.controller.uploads.single;
      expect(failed.state, PhotoUploadState.failed);
      expect(failed.message, contains('conexión'));
      expect(harness.controller.photos, isEmpty);
      expect(harness.changes, isEmpty);

      harness.backend.storageOffline = false;
      await harness.controller.retry(failed);

      expect(harness.controller.uploads, isEmpty);
      expect(harness.controller.photos, hasLength(1));
      final grants = harness.backend.requests.where(
        (r) => r.method == 'POST' && r.url.path.endsWith('/photos'),
      );
      expect(grants, hasLength(1));
    });

    test(
      'asks for a new link after the API discards an invalid upload',
      () async {
        final harness = await _build();
        await harness.controller.load();
        harness.backend.failNextConfirmWithStatus = 422;
        harness.source.next = FakePhotoSource.jpeg();

        await harness.controller.add(PhotoOrigin.gallery);

        final failed = harness.controller.uploads.single;
        expect(failed.message, contains('no es una foto válida'));

        await harness.controller.retry(failed);

        expect(harness.controller.photos, hasLength(1));
        final grants = harness.backend.requests.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/photos'),
        );
        expect(grants, hasLength(2));
      },
    );

    test('discarding a failed upload frees its reserved slot', () async {
      final harness = await _build();
      await harness.controller.load();
      harness.backend.storageOffline = true;
      harness.source.next = FakePhotoSource.jpeg();
      await harness.controller.add(PhotoOrigin.camera);

      await harness.controller.discard(harness.controller.uploads.single);

      expect(harness.controller.uploads, isEmpty);
      expect(harness.backend.photos['listing-1'], isEmpty);
    });

    test('explains the ten photo limit', () async {
      final harness = await _build();
      for (var i = 0; i < 10; i++) {
        harness.backend.seedPhoto('listing-1');
      }
      await harness.controller.load();

      expect(harness.controller.canAdd, isFalse);
    });
  });

  group('delete', () {
    test('deletes a confirmed photo and reports the listing change', () async {
      final harness = await _build(status: 'approved');
      harness.backend.seedPhoto('listing-1', photoId: 'photo-a');
      await harness.controller.load();

      final deleted = await harness.controller.delete('photo-a');

      expect(deleted, isTrue);
      expect(harness.controller.photos, isEmpty);
      expect(harness.backend.storage.containsKey('photo-a'), isFalse);
      expect(
        harness.backend.listings['listing-1']!['approval_status'],
        'draft',
      );
      expect(harness.changes, ['changed']);
    });

    test('keeps the photo and explains a failed deletion', () async {
      final harness = await _build();
      harness.backend.seedPhoto('listing-1', photoId: 'photo-a');
      await harness.controller.load();
      harness.backend.offline = true;

      final deleted = await harness.controller.delete('photo-a');

      expect(deleted, isFalse);
      expect(harness.controller.photos, hasLength(1));
      expect(harness.controller.message, contains('conexión'));
    });
  });
}
