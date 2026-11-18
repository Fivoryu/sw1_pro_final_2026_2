import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_capture_api.dart';
import 'package:captura_mobile/data/services/video_capture_channel.dart';
import 'package:captura_mobile/domain/spatial/capture_upload.dart';
import 'package:captura_mobile/domain/spatial/capture_upload_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/domain/video_capture_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_capture_backend.dart';
import 'support/fake_staff_backend.dart';
import 'support/fake_video_capture.dart';
import 'support/in_memory_upload_support.dart';

const _zipPath = '/files/capture_packages/cap-video-1.zip';

Future<
  ({
    VideoCaptureController controller,
    FakeVideoCapture capture,
    FakeCaptureBackend backend,
    CaptureUploadController uploads,
  })
>
_build() async {
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
  final backend = FakeCaptureBackend();
  final uploads = CaptureUploadController(
    listingId: 'listing-1',
    session: session,
    api: StaffCaptureApi(
      baseUrl: 'https://api.example.test',
      client: backend.client,
    ),
    store: InMemoryPendingUploadStore(),
    files: FakePackageFiles({_zipPath: List<int>.generate(100, (i) => i)}),
  );
  await uploads.load();
  final capture = FakeVideoCapture();
  final controller = VideoCaptureController(
    listingId: 'listing-1',
    capture: capture,
    uploads: uploads,
  );
  return (
    controller: controller,
    capture: capture,
    backend: backend,
    uploads: uploads,
  );
}

void main() {
  test('a recording goes through the existing upload queue', () async {
    final h = await _build();
    h.capture.results.add(videoCaptured());

    await h.controller.start();
    await h.uploads.idle;

    expect(h.capture.listingIds, ['listing-1']);
    expect(h.controller.status, VideoCaptureStatus.sent);
    expect(h.controller.warning, isNull);
    expect(h.uploads.items.single.upload.captureId, 'cap-video-1');
    expect(h.uploads.items.single.upload.stage, UploadStage.completed);
    expect(h.backend.captures.containsKey("cap-video-1"), isTrue);
  });

  test('skipping the reference warns that the model has no scale', () async {
    final h = await _build();
    h.capture.results.add(videoCaptured(hasReference: false));

    await h.controller.start();
    await h.uploads.idle;

    expect(h.controller.status, VideoCaptureStatus.sent);
    expect(h.controller.warning, contains('plano será proporcional'));
  });

  test('a package above 150 MiB is refused and never queued', () async {
    final h = await _build();
    h.capture.results.add(videoCaptured(sizeBytes: maxCapturePackageBytes + 1));

    await h.controller.start();

    expect(h.controller.status, VideoCaptureStatus.failed);
    expect(h.controller.message, contains('150 MB'));
    expect(h.uploads.items, isEmpty);
  });

  test('the five minute cut is reported to the agent', () async {
    final h = await _build();
    h.capture.results.add(videoCaptured(reachedTimeLimit: true));

    await h.controller.start();
    await h.uploads.idle;

    expect(h.controller.message, contains('5 minutos'));
  });

  test('cancel and failure leave the queue untouched', () async {
    final h = await _build();
    h.capture.results.add(const VideoCaptureCancelled());
    await h.controller.start();
    expect(h.controller.status, VideoCaptureStatus.idle);

    h.capture.results.add(const VideoCaptureFailed('x', 'Falló la cámara.'));
    await h.controller.start();
    expect(h.controller.status, VideoCaptureStatus.failed);
    expect(h.controller.message, 'Falló la cámara.');
    expect(h.uploads.items, isEmpty);
  });

  test('a second start while recording is ignored', () async {
    final h = await _build();
    h.capture.results.add(videoCaptured());

    final first = h.controller.start();
    final second = h.controller.start();
    await Future.wait([first, second]);

    expect(h.capture.listingIds, hasLength(1));
  });

  test('a blank listing id never reaches the native recorder', () async {
    final h = await _build();
    final controller = VideoCaptureController(
      listingId: ' ',
      capture: h.capture,
      uploads: h.uploads,
    );

    await controller.start();

    expect(controller.status, VideoCaptureStatus.failed);
    expect(h.capture.listingIds, isEmpty);
  });
}
