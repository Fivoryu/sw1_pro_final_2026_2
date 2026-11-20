import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_capture_api.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:captura_mobile/domain/spatial/capture_upload_controller.dart';
import 'package:captura_mobile/domain/spatial_capture_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/domain/video_capture_controller.dart';
import 'package:captura_mobile/ui/spatial/spatial_capture_screen.dart';
import 'package:captura_mobile/ui/spatial/video_capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_ar_capture.dart';
import 'support/fake_capture_backend.dart';
import 'support/fake_scene_backend.dart';
import 'support/fake_staff_backend.dart';
import 'support/fake_video_capture.dart';
import 'support/in_memory_capture_draft_store.dart';
import 'support/in_memory_upload_support.dart';

const _zipPath = '/files/capture_packages/cap-video-1.zip';

Future<StaffSessionController> _session() async {
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
  return session;
}

CaptureUploadController _uploads(StaffSessionController session) =>
    CaptureUploadController(
      listingId: 'listing-1',
      session: session,
      api: StaffCaptureApi(
        baseUrl: 'https://api.example.test',
        client: FakeCaptureBackend().client,
      ),
      store: InMemoryPendingUploadStore(),
      files: FakePackageFiles({
        _zipPath: [1, 2, 3, 4],
      }),
    );

SpatialCaptureController _spatial(
  StaffSessionController session, {
  CaptureUploadController? uploads,
}) => SpatialCaptureController(
  listingId: 'listing-1',
  session: session,
  sceneApi: StaffSceneApi(
    baseUrl: 'https://api.example.test',
    client: FakeSceneBackend().client,
  ),
  store: InMemoryCaptureDraftStore(),
  ar: FakeArCapture(),
  uploads: uploads,
);

void main() {
  testWidgets('the screen warns about a missing reference after recording', (
    tester,
  ) async {
    final session = await tester.runAsync(_session);
    final capture = FakeVideoCapture()
      ..results.add(videoCaptured(hasReference: false));
    final controller = VideoCaptureController(
      listingId: 'listing-1',
      capture: capture,
      uploads: _uploads(session!),
    );
    // Tall enough that the whole list is built, now that it has one more card.
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: VideoCaptureScreen(controller: controller)),
    );

    expect(find.byKey(const ValueKey('video-reference-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('video-warning')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('start-video-button')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(capture.listingIds, ['listing-1']);
    expect(find.byKey(const ValueKey('video-message')), findsOneWidget);
    expect(find.byKey(const ValueKey('video-warning')), findsOneWidget);
    expect(find.textContaining('plano será proporcional'), findsWidgets);
  });

  testWidgets('the intro says the app detects the reference and no longer asks '
      'to mark two ends', (tester) async {
    final session = await tester.runAsync(_session);
    final controller = VideoCaptureController(
      listingId: 'listing-1',
      capture: FakeVideoCapture(),
      uploads: _uploads(session!),
    );
    await tester.pumpWidget(
      MaterialApp(home: VideoCaptureScreen(controller: controller)),
    );

    expect(find.textContaining('detecta el objeto'), findsOneWidget);
    expect(find.textContaining('confirmás o ajustás'), findsOneWidget);
    expect(find.textContaining('a mano'), findsOneWidget);
    expect(find.textContaining('vertical u horizontal'), findsOneWidget);
    expect(find.textContaining('marcá sus dos extremos'), findsNothing);
  });

  testWidgets('the screen explains the live guidance shown while recording', (
    tester,
  ) async {
    final session = await tester.runAsync(_session);
    final controller = VideoCaptureController(
      listingId: 'listing-1',
      capture: FakeVideoCapture(),
      uploads: _uploads(session!),
    );
    await tester.pumpWidget(
      MaterialApp(home: VideoCaptureScreen(controller: controller)),
    );

    final hint = find.byKey(const ValueKey('video-guidance-hint'));
    expect(hint, findsOneWidget);
    expect(find.textContaining('poca luz'), findsOneWidget);
    expect(find.textContaining('cerrar el recorrido'), findsOneWidget);
    // T7a behavior still holds: the reference hint and start button remain.
    expect(find.byKey(const ValueKey('video-reference-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('start-video-button')), findsOneWidget);
  });

  testWidgets('the spatial screen offers the video walkthrough beside the '
      'manual capture', (tester) async {
    final session = (await tester.runAsync(_session))!;
    final controller = _spatial(session, uploads: _uploads(session));
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SpatialCaptureScreen(
          controller: controller,
          videoCapture: FakeVideoCapture(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('capture-room-button')), findsOneWidget);
    final button = find.byKey(const ValueKey('record-video-button'));
    expect(button, findsOneWidget);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('start-video-button')), findsOneWidget);
  });

  testWidgets('without the upload queue there is no video walkthrough', (
    tester,
  ) async {
    final session = (await tester.runAsync(_session))!;
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: SpatialCaptureScreen(controller: _spatial(session))),
    );

    expect(find.byKey(const ValueKey('capture-room-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('record-video-button')), findsNothing);
  });
}
