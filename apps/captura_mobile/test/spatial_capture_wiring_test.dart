import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_capture_api.dart';
import 'package:captura_mobile/data/services/staff_listing_photos_api.dart';
import 'package:captura_mobile/data/services/staff_listings_api.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:captura_mobile/domain/listing_drafts_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_ar_capture.dart';
import 'support/fake_listings_backend.dart';
import 'support/fake_photo_source.dart';
import 'support/fake_scene_backend.dart';
import 'support/fake_staff_backend.dart';
import 'support/in_memory_capture_draft_store.dart';
import 'support/in_memory_upload_support.dart';

const _baseUrl = 'https://api.example.test';

ListingDraftsController _controller({required bool uploads}) {
  final backend = FakeListingsBackend();
  return ListingDraftsController(
    api: StaffListingsApi(baseUrl: _baseUrl, client: backend.client),
    session: StaffSessionController(
      api: StaffAuthApi(baseUrl: _baseUrl, client: FakeStaffBackend().client),
      credentialStore: InMemoryStaffCredentialStore(),
    ),
    photosApi: StaffListingPhotosApi(baseUrl: _baseUrl, client: backend.client),
    photoSource: FakePhotoSource(),
    sceneApi: StaffSceneApi(
      baseUrl: _baseUrl,
      client: FakeSceneBackend().client,
    ),
    captureStore: InMemoryCaptureDraftStore(),
    arCapture: FakeArCapture(),
    captureApi: uploads ? StaffCaptureApi(baseUrl: _baseUrl) : null,
    uploadStore: uploads ? InMemoryPendingUploadStore() : null,
  );
}

void main() {
  test('spatial capture uploads its packages when the services exist', () {
    final spatial = _controller(uploads: true).spatialCaptureFor('listing-1');

    expect(spatial, isNotNull);
    expect(spatial!.uploads, isNotNull);
    expect(spatial.uploads!.listingId, 'listing-1');
  });

  test('spatial capture keeps working without the upload services', () {
    final spatial = _controller(uploads: false).spatialCaptureFor('listing-1');

    expect(spatial, isNotNull);
    expect(spatial!.uploads, isNull);
  });
}
