import 'package:captura_mobile/data/services/ar_capture_channel.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_capture_api.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:captura_mobile/domain/spatial/capture_upload.dart';
import 'package:captura_mobile/domain/spatial/capture_upload_controller.dart';
import 'package:captura_mobile/domain/spatial_capture_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_ar_capture.dart';
import 'support/fake_capture_backend.dart';
import 'support/fake_scene_backend.dart';
import 'support/fake_staff_backend.dart';
import 'support/in_memory_capture_draft_store.dart';
import 'support/in_memory_upload_support.dart';

const _zipPath = '/files/capture_packages/cap-1.zip';

CapturePackageInfo _info({List<CapturePackageRoom>? rooms}) =>
    CapturePackageInfo(
      zipPath: _zipPath,
      captureId: 'cap-1',
      sizeBytes: 4,
      keyframeCount: 8,
      droppedKeyframes: 0,
      failedKeyframes: 0,
      rooms: rooms ?? const [CapturePackageRoom(id: 'room-1', name: 'Estar')],
    );

ArCaptured _withPackage(
  ArCaptured base, {
  CapturePackageInfo? package,
  String? problem,
}) =>
    ArCaptured(base.payload, capturePackage: package, packageProblem: problem);

typedef _Built = ({
  SpatialCaptureController controller,
  FakeArCapture ar,
  FakeCaptureBackend captures,
  FakeSceneBackend scenes,
  InMemoryPendingUploadStore pending,
  CaptureUploadController? uploads,
});

Future<_Built> _build({bool withUploads = true}) async {
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
  final ar = FakeArCapture();
  final captures = FakeCaptureBackend();
  final scenes = FakeSceneBackend();
  final pending = InMemoryPendingUploadStore();
  final uploads = withUploads
      ? CaptureUploadController(
          listingId: 'listing-1',
          session: session,
          api: StaffCaptureApi(
            baseUrl: 'https://api.example.test',
            client: captures.client,
          ),
          store: pending,
          files: FakePackageFiles({
            _zipPath: [1, 2, 3, 4],
          }),
        )
      : null;
  final controller = SpatialCaptureController(
    listingId: 'listing-1',
    session: session,
    sceneApi: StaffSceneApi(
      baseUrl: 'https://api.example.test',
      client: scenes.client,
    ),
    store: InMemoryCaptureDraftStore(),
    ar: ar,
    uploads: uploads,
  );
  await controller.load();
  return (
    controller: controller,
    ar: ar,
    captures: captures,
    scenes: scenes,
    pending: pending,
    uploads: uploads,
  );
}

void main() {
  test(
    'a walkthrough with a package adds the room and uploads the package',
    () async {
      final b = await _build();
      b.ar.results.add(_withPackage(walkthrough(), package: _info()));

      final notice = await b.controller.captureRoom(
        'Estar',
        mode: CaptureMode.walkthrough,
      );
      await b.uploads!.idle;

      expect(b.controller.rooms, hasLength(1));
      expect(notice, contains('Contorno propuesto'));
      expect(notice, contains('se sube'));
      expect(b.ar.listingIds, ['listing-1']);
      expect(b.captures.captures['cap-1']!.status, 'queued');
      expect(b.uploads!.items.single.upload.stage, UploadStage.completed);
    },
  );

  test('a package problem keeps the room and tells the agent', () async {
    final b = await _build();
    b.ar.results.add(
      _withPackage(
        walkthrough(),
        problem: 'No se guardaron cuadros del recorrido.',
      ),
    );

    final notice = await b.controller.captureRoom(
      'Estar',
      mode: CaptureMode.walkthrough,
    );

    expect(b.controller.rooms, hasLength(1));
    expect(notice, contains('No se guardaron cuadros del recorrido.'));
    expect(notice, contains('reconstrucción'));
    expect(b.captures.requests, isEmpty);
    expect(b.uploads!.items, isEmpty);
  });

  test(
    'several rooms in one session are flagged: the local contour is only a preview',
    () async {
      final b = await _build();
      b.ar.results.add(
        _withPackage(
          walkthrough(),
          package: _info(
            rooms: const [
              CapturePackageRoom(id: 'room-1', name: 'Estar'),
              CapturePackageRoom(id: 'room-2', name: 'Ambiente 2'),
            ],
          ),
        ),
      );

      final notice = await b.controller.captureRoom(
        'Estar',
        mode: CaptureMode.walkthrough,
      );

      expect(notice, contains('2 ambientes'));
      expect(notice, contains('vista previa'));
    },
  );

  test('walls mode never creates an upload', () async {
    final b = await _build();
    b.ar.results.add(rectangle(4, 3));

    await b.controller.captureRoom('Estar');
    await b.uploads!.idle;

    expect(b.controller.rooms, hasLength(1));
    expect(b.uploads!.items, isEmpty);
    expect(b.captures.requests, isEmpty);
  });

  test('without upload support a walkthrough behaves as before', () async {
    final b = await _build(withUploads: false);
    b.ar.results.add(_withPackage(walkthrough(), package: _info()));

    final notice = await b.controller.captureRoom(
      'Estar',
      mode: CaptureMode.walkthrough,
    );

    expect(b.controller.rooms, hasLength(1));
    expect(notice, isNot(contains('se sube')));
    expect(b.captures.requests, isEmpty);
  });

  test('upload progress notifies the capture controller listeners', () async {
    final b = await _build();
    var notifications = 0;
    b.controller.addListener(() => notifications++);
    b.ar.results.add(_withPackage(walkthrough(), package: _info()));

    await b.controller.captureRoom('Estar', mode: CaptureMode.walkthrough);
    final before = notifications;
    await b.uploads!.idle;

    expect(notifications, greaterThan(before));
  });

  test('load restores the pending uploads of the listing', () async {
    final b = await _build();
    await b.pending.save(
      'staff-1',
      PendingCaptureUpload(
        captureId: 'cap-9',
        listingId: 'listing-1',
        zipPath: _zipPath,
        sizeBytes: 4,
        keyframeCount: 3,
        createdAt: DateTime.utc(2026, 10, 21),
      ),
    );

    await b.controller.load();

    expect(b.uploads!.items.single.upload.captureId, 'cap-9');
  });
}
