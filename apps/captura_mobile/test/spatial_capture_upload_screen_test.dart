import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_capture_api.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:captura_mobile/domain/spatial/capture_upload.dart';
import 'package:captura_mobile/domain/spatial/capture_upload_controller.dart';
import 'package:captura_mobile/domain/spatial_capture_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/ui/spatial/spatial_capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_ar_capture.dart';
import 'support/fake_capture_backend.dart';
import 'support/fake_scene_backend.dart';
import 'support/fake_staff_backend.dart';
import 'support/in_memory_capture_draft_store.dart';
import 'support/in_memory_upload_support.dart';

const _zipPath = '/files/capture_packages/cap-1.zip';

PendingCaptureUpload _upload({
  UploadStage stage = UploadStage.completed,
  RemoteCaptureStatus? remote = RemoteCaptureStatus.queued,
  String? reason,
  String? error,
}) => PendingCaptureUpload(
  captureId: 'cap-1',
  listingId: 'listing-1',
  zipPath: stage == UploadStage.completed ? null : _zipPath,
  sizeBytes: 4,
  keyframeCount: 8,
  createdAt: DateTime.utc(2026, 10, 21),
  stage: stage,
  remoteStatus: remote,
  failureReason: reason,
  lastError: error,
);

typedef _Built = ({
  SpatialCaptureController controller,
  FakeCaptureBackend backend,
  InMemoryPendingUploadStore pending,
});

Future<_Built> _build(
  WidgetTester tester, {
  PendingCaptureUpload? stored,
  FakeCaptureBackend? backend,
}) async {
  final captures = backend ?? FakeCaptureBackend();
  final pending = InMemoryPendingUploadStore();
  late SpatialCaptureController controller;
  await tester.runAsync(() async {
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
    if (stored != null) await pending.save('staff-1', stored);
    controller = SpatialCaptureController(
      listingId: 'listing-1',
      session: session,
      sceneApi: StaffSceneApi(
        baseUrl: 'https://api.example.test',
        client: FakeSceneBackend().client,
      ),
      store: InMemoryCaptureDraftStore(),
      ar: FakeArCapture(),
      uploads: CaptureUploadController(
        listingId: 'listing-1',
        session: session,
        api: StaffCaptureApi(
          baseUrl: 'https://api.example.test',
          client: captures.client,
        ),
        store: pending,
        files: FakePackageFiles({_zipPath: [1, 2, 3, 4]}),
      ),
    );
    await controller.load();
  });
  return (controller: controller, backend: captures, pending: pending);
}

Future<void> _pump(WidgetTester tester, SpatialCaptureController controller) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: SpatialCaptureScreen(controller: controller)),
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows no upload section when nothing was captured for reconstruction', (tester) async {
    final built = await _build(tester);
    await _pump(tester, built.controller);

    expect(find.byKey(const ValueKey('uploads-card')), findsNothing);
  });

  testWidgets('shows the queued state and refreshes it from the server', (tester) async {
    final backend = FakeCaptureBackend()
      ..captures['cap-1'] = (FakeCapture('cap-1', 4)..status = 'queued');
    final built = await _build(tester, stored: _upload(), backend: backend);
    await _pump(tester, built.controller);

    expect(find.byKey(const ValueKey('uploads-card')), findsOneWidget);
    expect(find.text('En la cola de reconstrucción'), findsOneWidget);

    backend.statusScript.add(('processing', null));
    await _tap(tester, find.byKey(const ValueKey('upload-refresh-button')));

    expect(find.text('Reconstruyendo el ambiente'), findsOneWidget);
  });

  testWidgets('shows the reconstruction result as a draft for the panel, not as 3D', (tester) async {
    final built = await _build(
      tester,
      stored: _upload(remote: RemoteCaptureStatus.completed),
    );
    await _pump(tester, built.controller);

    expect(find.text('Borrador listo'), findsOneWidget);
    expect(find.textContaining('panel'), findsOneWidget);
    expect(find.byKey(const ValueKey('upload-refresh-button')), findsNothing);
  });

  testWidgets('shows why a reconstruction failed and lets the agent remove it', (tester) async {
    final built = await _build(
      tester,
      stored: _upload(remote: RemoteCaptureStatus.failed, reason: 'Sin piso detectado'),
    );
    await _pump(tester, built.controller);

    expect(find.text('La reconstrucción falló'), findsOneWidget);
    expect(find.textContaining('Sin piso detectado'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('upload-dismiss-button')));

    expect(find.byKey(const ValueKey('uploads-card')), findsNothing);
    expect(await built.pending.list('staff-1'), isEmpty);
  });

  testWidgets('a package waiting on the phone can be retried', (tester) async {
    final backend = FakeCaptureBackend()..offline = true;
    final built = await _build(
      tester,
      stored: _upload(stage: UploadStage.local, remote: null),
      backend: backend,
    );
    await _pump(tester, built.controller);

    expect(find.text('Recorrido guardado en el teléfono'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('upload-retry-button')));
    expect(find.textContaining('Sin conexión'), findsOneWidget);

    backend.offline = false;
    await _tap(tester, find.byKey(const ValueKey('upload-retry-button')));

    expect(find.text('En la cola de reconstrucción'), findsOneWidget);
    expect(backend.captures, hasLength(1));
    expect(backend.registerCalls, 1);
  });
}
