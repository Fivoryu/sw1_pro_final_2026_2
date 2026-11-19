import 'package:captura_mobile/data/services/offline_listing_store.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_capture_api.dart';
import 'package:captura_mobile/data/services/staff_listing_photos_api.dart';
import 'package:captura_mobile/data/services/staff_listings_api.dart';
import 'package:captura_mobile/domain/listing_drafts_controller.dart';
import 'package:captura_mobile/domain/spatial/capture_upload.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/domain/video_capture_controller.dart';
import 'package:captura_mobile/main.dart';
import 'package:captura_mobile/ui/listings/offline_capture_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_capture_backend.dart';
import 'support/fake_listings_backend.dart';
import 'support/fake_photo_source.dart';
import 'support/fake_staff_backend.dart';
import 'support/fake_video_capture.dart';
import 'support/in_memory_offline_listing_store.dart';
import 'support/in_memory_upload_support.dart';

const _baseUrl = 'https://api.example.test';
const _zipPath = '/files/capture_packages/cap-video-1.zip';

/// One "phone": shared disk (credentials, caches, queue, files) and one
/// network switch, with a fresh session/controllers per app start.
class _Phone {
  final staff = FakeStaffBackend();
  final listings = FakeListingsBackend();
  final capture = FakeCaptureBackend();
  final credentials = InMemoryStaffCredentialStore(
    refreshCookie: 'refresh-cookie',
    csrfToken: 'csrf-1',
    ownerId: 'staff-1',
  );
  final cache = InMemoryOfflineListingStore();
  final queue = InMemoryPendingUploadStore();
  final files = FakePackageFiles({
    _zipPath: [1, 2, 3, 4],
  });

  set online(bool value) {
    staff.offline = !value;
    capture.offline = !value;
  }

  StaffSessionController session() => StaffSessionController(
    api: StaffAuthApi(baseUrl: _baseUrl, client: staff.client),
    credentialStore: credentials,
    offlineStore: cache,
  );

  ListingDraftsController drafts(StaffSessionController session) =>
      ListingDraftsController(
        api: StaffListingsApi(baseUrl: _baseUrl, client: listings.client),
        session: session,
        photosApi: StaffListingPhotosApi(
          baseUrl: _baseUrl,
          client: listings.client,
        ),
        photoSource: FakePhotoSource(),
        captureApi: StaffCaptureApi(baseUrl: _baseUrl, client: capture.client),
        uploadStore: queue,
        packageFiles: files,
      );
}

/// Queue whose `list` call number [failOn] (1-based) throws.
class _FlakyQueue extends InMemoryPendingUploadStore {
  _FlakyQueue(this.failOn);

  final int failOn;
  int calls = 0;

  @override
  Future<List<PendingCaptureUpload>> list(String ownerId) {
    calls++;
    if (calls == failOn) throw StateError('disk failure');
    return super.list(ownerId);
  }
}

void main() {
  test('a failing listing does not stop the resume of the others', () async {
    final phone = _Phone();
    final queue = _FlakyQueue(2);
    for (final id in ['a', 'b']) {
      await queue.save(
        'staff-1',
        PendingCaptureUpload(
          captureId: 'cap-$id',
          listingId: 'listing-$id',
          zipPath: _zipPath,
          sizeBytes: 4,
          keyframeCount: 1,
          createdAt: DateTime.utc(2026, 11, 16),
        ),
      );
    }
    final session = phone.session();
    await session.restore();
    final drafts = ListingDraftsController(
      api: StaffListingsApi(baseUrl: _baseUrl, client: phone.listings.client),
      session: session,
      photosApi: StaffListingPhotosApi(
        baseUrl: _baseUrl,
        client: phone.listings.client,
      ),
      photoSource: FakePhotoSource(),
      captureApi: StaffCaptureApi(
        baseUrl: _baseUrl,
        client: phone.capture.client,
      ),
      uploadStore: queue,
      packageFiles: phone.files,
    );

    await drafts.resumePendingUploads();

    // First listing's load threw (list call 2); the second still ran.
    expect(phone.capture.registerCalls, 1);
  });

  test('an online listing fetch caches id and label for the account', () async {
    final phone = _Phone();
    phone.listings.seed(id: 'listing-1');
    final session = phone.session();
    await session.restore();

    await phone.drafts(session).load();

    final cached = await phone.cache.read('staff-1');
    expect(cached.single.listingId, 'listing-1');
    expect(cached.single.label, 'Medellín · El Poblado');
    // Only id and label are kept: nothing else about the listing.
    expect(cached.single.toJson().keys, ['listing_id', 'label']);
  });

  test('record offline, then upload after the session is renewed', () async {
    final phone = _Phone();
    phone.listings.seed(id: 'listing-1');
    var session = phone.session();
    await session.restore();
    await phone.drafts(session).load();

    // Cold start without network.
    phone.listings.requests.clear();
    phone.online = false;
    session = phone.session();
    await session.restore();
    final drafts = phone.drafts(session);
    expect(session.status, StaffSessionStatus.offline);
    expect(session.offlineListings.single.listingId, 'listing-1');

    final uploads = drafts.uploadsFor('listing-1')!;
    await uploads.load();
    final video = FakeVideoCapture()..results.add(videoCaptured(sizeBytes: 4));
    final recording = VideoCaptureController(
      listingId: 'listing-1',
      capture: video,
      uploads: uploads,
    );
    await recording.start();
    await uploads.idle;

    // Queued on the phone, nothing sent, no authenticated call made.
    expect(recording.status, VideoCaptureStatus.sent);
    expect((await drafts.pendingUploads()).single.captureId, 'cap-video-1');
    expect(phone.capture.requests, isEmpty);
    expect(phone.listings.requests, isEmpty);
    expect(uploads.message, contains('Modo sin conexión'));
    await drafts.resumePendingUploads();
    expect(phone.capture.requests, isEmpty);

    // The network returns: real refresh first, then the queue goes out.
    phone.online = true;
    await session.restore();
    expect(session.status, StaffSessionStatus.signedIn);
    await drafts.resumePendingUploads();

    expect(phone.capture.registerCalls, 1);
    expect(phone.capture.putCalls, 1);
    expect(phone.capture.completeCalls, 1);
    final stored = (await phone.queue.list('staff-1')).single;
    expect(stored.stage, UploadStage.completed);
    expect(phone.files.deleted, [_zipPath]);
  });

  test('a rejected refresh keeps the queued package on the phone', () async {
    final phone = _Phone();
    phone.listings.seed(id: 'listing-1');
    var session = phone.session();
    await session.restore();
    await phone.drafts(session).load();
    phone.online = false;
    session = phone.session();
    await session.restore();
    final uploads = phone.drafts(session).uploadsFor('listing-1')!;
    await uploads.load();
    await VideoCaptureController(
      listingId: 'listing-1',
      capture: FakeVideoCapture()..results.add(videoCaptured(sizeBytes: 4)),
      uploads: uploads,
    ).start();

    phone.online = true;
    phone.staff.refreshRejected = true;
    await session.restore();

    expect(session.status, StaffSessionStatus.signedOut);
    expect(phone.credentials.refreshCookie, isNull);
    expect(phone.cache.data, isEmpty);
    expect((await phone.queue.list('staff-1')), hasLength(1));
    expect(phone.files.files, contains(_zipPath));
    expect(phone.capture.requests, isEmpty);
  });

  test('resumePendingUploads does nothing without an access token', () async {
    final phone = _Phone();
    final session = phone.session();
    await phone.queue.save(
      'staff-1',
      PendingCaptureUpload(
        captureId: 'cap-1',
        listingId: 'listing-1',
        zipPath: _zipPath,
        sizeBytes: 4,
        keyframeCount: 1,
        createdAt: DateTime.utc(2026, 11, 16),
      ),
    );
    phone.online = false;
    await session.restore();

    await phone.drafts(session).resumePendingUploads();

    expect(phone.capture.requests, isEmpty);
  });

  testWidgets('the offline screen shows only local data and no sign-out', (
    tester,
  ) async {
    final phone = _Phone();
    await phone.cache.write('staff-1', 'draft', [
      const OfflineListing(listingId: 'listing-1', label: 'La Paz · Sopocachi'),
    ]);
    phone.online = false;
    final session = phone.session();
    await tester.runAsync(session.restore);
    final video = FakeVideoCapture();
    await tester.pumpWidget(
      CaptureApp(
        controller: session,
        listingsApi: StaffListingsApi(
          baseUrl: _baseUrl,
          client: phone.listings.client,
        ),
        photosApi: StaffListingPhotosApi(
          baseUrl: _baseUrl,
          client: phone.listings.client,
        ),
        photoSource: FakePhotoSource(),
        captureApi: StaffCaptureApi(
          baseUrl: _baseUrl,
          client: phone.capture.client,
        ),
        uploadStore: phone.queue,
        videoCapture: video,
      ),
    );
    await tester.pump();

    expect(find.text(OfflineCaptureView.notice), findsOneWidget);
    expect(find.text('La Paz · Sopocachi'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('offline-record-listing-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('offline-retry')), findsOneWidget);
    // Nothing that needs the server, and no way to look signed in.
    expect(find.byKey(const ValueKey('access-logout')), findsNothing);
    expect(find.byKey(const ValueKey('access-continue-button')), findsNothing);
    expect(find.byKey(const ValueKey('access-chat-button')), findsNothing);
    expect(find.byKey(const ValueKey('access-reviews-button')), findsNothing);
    expect(find.byKey(const ValueKey('access-email-field')), findsNothing);
    expect(phone.listings.requests, isEmpty);
    expect(phone.capture.requests, isEmpty);

    await tester.tap(find.byKey(const ValueKey('offline-record-listing-1')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('start-video-button')), findsOneWidget);
  });
}
