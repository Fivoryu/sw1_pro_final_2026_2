import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:captura_mobile/data/services/ar_capture_channel.dart';
import 'package:captura_mobile/data/services/photo_source.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:captura_mobile/domain/spatial_capture_controller.dart';
import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/ui/spatial/floorplan_trace_screen.dart';
import 'package:captura_mobile/ui/spatial/room_editor_screen.dart';
import 'package:captura_mobile/ui/spatial/spatial_capture_screen.dart';
import 'package:captura_mobile/ui/theme/andean_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_ar_capture.dart';
import 'support/fake_scene_backend.dart';
import 'support/fake_staff_backend.dart';
import 'support/in_memory_capture_draft_store.dart';

typedef _Built = ({
  SpatialCaptureController controller,
  FakeSceneBackend backend,
  FakeArCapture ar,
  InMemoryCaptureDraftStore store,
});

class _FloorplanPhotoSource implements PhotoSource {
  _FloorplanPhotoSource(this.bytes);

  final Uint8List bytes;

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async =>
      PickedPhoto(bytes: bytes, contentType: 'image/png');
}

Future<Uint8List> _testPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 100, 80),
    Paint()..color = Colors.white,
  );
  final image = await recorder.endRecording().toImage(100, 80);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<_Built> _build(WidgetTester tester, {PhotoSource? traceSource}) async {
  final backend = FakeSceneBackend();
  final ar = FakeArCapture();
  final store = InMemoryCaptureDraftStore();
  final controller = await _newController(
    tester,
    backend: backend,
    ar: ar,
    store: store,
    traceSource: traceSource,
  );
  return (controller: controller, backend: backend, ar: ar, store: store);
}

Future<SpatialCaptureController> _newController(
  WidgetTester tester, {
  required FakeSceneBackend backend,
  required FakeArCapture ar,
  required InMemoryCaptureDraftStore store,
  PhotoSource? traceSource,
}) async {
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
    controller = SpatialCaptureController(
      listingId: 'listing-1',
      session: session,
      sceneApi: StaffSceneApi(
        baseUrl: 'https://api.example.test',
        client: backend.client,
      ),
      store: store,
      ar: ar,
      traceSource: traceSource,
    );
    await controller.load();
  });
  return controller;
}

Future<void> _pump(
  WidgetTester tester,
  SpatialCaptureController controller, {
  String? syncBlockedReason,
}) async {
  // A tall surface keeps every section of the lazy list built.
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: SpatialCaptureScreen(
        controller: controller,
        syncBlockedReason: syncBlockedReason,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _chooseAutomaticCapture(WidgetTester tester) => _tapAndSettle(
  tester,
  find.byKey(const ValueKey('automatic-capture-method')),
);

void main() {
  testWidgets('captures a room and shows its estimated dimensions', (
    tester,
  ) async {
    final built = await _build(tester);
    built.ar.results.add(rectangle(4, 3));
    await _pump(tester, built.controller);

    expect(find.text('Todavía no capturaste ambientes.'), findsOneWidget);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('capture-room-button')),
    );
    await _chooseAutomaticCapture(tester);
    await tester.enterText(
      find.byKey(const ValueKey('room-name-field')),
      'Estar',
    );
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('room-name-confirm')),
    );

    expect(find.text('Estar'), findsOneWidget);
    expect(find.text('Superficie estimada: 12,00 m²'), findsOneWidget);
    expect(find.text('Altura: 2,50 m (medida al techo)'), findsOneWidget);
    expect(find.bySemanticsLabel('Plano de la captura'), findsOneWidget);
    expect(find.text('Pendiente de enviar'), findsOneWidget);
  });

  testWidgets('creates a manual room without consulting ARCore', (
    tester,
  ) async {
    final built = await _build(tester);
    built.ar.available = ArAvailability.unsupported;
    await _pump(tester, built.controller);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('capture-room-button')),
    );
    expect(find.text('Captura automática'), findsOneWidget);
    expect(find.text('Medidas manuales'), findsOneWidget);
    expect(find.textContaining('importar'), findsNothing);
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('manual-capture-method')),
    );
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('manual-shape-rectangle')),
    );
    expect(find.text('Largo del ambiente (m)'), findsOneWidget);
    expect(find.text('Ancho del ambiente (m)'), findsOneWidget);
    expect(find.text('Altura del ambiente (m)'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('manual-room-name')),
      'Dormitorio',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-room-length')),
      '4,20',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-room-width')),
      '3,70',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manual-room-height')),
      '2,60',
    );
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('manual-room-confirm')),
    );

    expect(built.ar.availabilityChecks, 0);
    expect(find.text('Dormitorio'), findsOneWidget);
    expect(find.text('Superficie estimada: 15,54 m²'), findsOneWidget);
    expect(find.text('Medidas ingresadas manualmente'), findsOneWidget);
    expect(find.bySemanticsLabel('Plano de la captura'), findsOneWidget);

    final edit = find.byKey(const ValueKey('edit-room-room-1'));
    await tester.scrollUntilVisible(
      edit,
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('spatial-capture-screen')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Lados'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-opening-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('reference-field-0')), findsNothing);
  });

  testWidgets('creates an L room from the guided manual selector', (
    tester,
  ) async {
    final built = await _build(tester);
    built.ar.available = ArAvailability.unsupported;
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: SpatialCaptureScreen(controller: built.controller),
      ),
    );
    await tester.pumpAndSettle();
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('capture-room-button')),
    );
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('manual-capture-method')),
    );
    expect(find.text('Rectangular'), findsOneWidget);
    expect(find.text('En L'), findsOneWidget);
    expect(find.text('Irregular'), findsOneWidget);
    expect(find.textContaining('import'), findsNothing);
    await _tapAndSettle(tester, find.byKey(const ValueKey('manual-shape-l')));

    for (final entry in <ValueKey<String>, String>{
      const ValueKey('l-room-name'): 'Cocina en L',
      const ValueKey('l-total-width'): '5,00',
      const ValueKey('l-total-depth'): '4.00',
      const ValueKey('l-recess-width'): '2,00',
      const ValueKey('l-recess-depth'): '1,50',
      const ValueKey('l-room-height'): '2,60',
    }.entries) {
      await tester.enterText(find.byKey(entry.key), entry.value);
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('l-recess-corner')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('manual-contour-preview')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('l-recess-width')),
      '5,00',
    );
    await _tapAndSettle(tester, find.byKey(const ValueKey('l-room-confirm')));
    expect(find.textContaining('El recorte debe ser menor'), findsOneWidget);
    expect(built.controller.rooms, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('l-recess-width')),
      '2,00',
    );
    await _tapAndSettle(tester, find.byKey(const ValueKey('l-room-confirm')));

    final room = built.controller.rooms.single;
    expect(room.name, 'Cocina en L');
    expect(room.corners, hasLength(6));
    expect(polygonArea(room.corners), closeTo(17, 1e-9));
    expect(room.acquisition.method, RoomAcquisitionMethod.manual);
    expect(room.metrics, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'traces a local floorplan and keeps only metric geometry remote',
    (tester) async {
      final source = _FloorplanPhotoSource(
        await tester.runAsync(_testPng) ?? Uint8List(0),
      );
      final built = await _build(tester, traceSource: source);
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: andeanTheme(),
          home: SpatialCaptureScreen(controller: built.controller),
        ),
      );
      await tester.pumpAndSettle();
      await _tapAndSettle(
        tester,
        find.byKey(const ValueKey('capture-room-button')),
      );
      expect(find.text('Captura automática'), findsOneWidget);
      expect(find.text('Medidas manuales'), findsOneWidget);
      expect(find.text('Plano o croquis'), findsOneWidget);
      expect(find.textContaining('PDF'), findsNothing);
      await _tapAndSettle(
        tester,
        find.byKey(const ValueKey('floorplan-capture-method')),
      );
      expect(tester.takeException(), isNull);
      final pick = find.byKey(const ValueKey('floorplan-pick-source'));
      await tester.tap(pick);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mover / zoom'), findsOneWidget);
      expect(find.text('Trazar'), findsOneWidget);
      await tester.tap(find.text('Trazar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('floorplan-room-name')),
        'Dormitorio plano',
      );
      final canvas = find.byKey(const ValueKey('floorplan-trace-canvas'));
      await tester.ensureVisible(canvas);
      for (final point in const [
        Offset(50, 30),
        Offset(250, 30),
        Offset(250, 230),
        Offset(50, 230),
      ]) {
        await tester.tapAt(tester.getTopLeft(canvas) + point);
        await tester.pumpAndSettle();
      }
      final close = find.byKey(const ValueKey('trace-close'));
      await tester.scrollUntilVisible(
        close,
        150,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('floorplan-trace-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(close);
      await tester.pumpAndSettle();
      expect(close.hitTestable(), findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('trace-reference-metres')),
        '4,20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('trace-room-height')),
        '2.65',
      );
      await tester.pumpAndSettle();
      expect(find.text('Vista previa métrica'), findsOneWidget);
      final provenance = find.text('Plano o croquis trazado y calibrado');
      await tester.scrollUntilVisible(
        provenance,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('floorplan-trace-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(provenance, findsOneWidget);
      expect(tester.takeException(), isNull);
      final save = find.byKey(const ValueKey('floorplan-trace-save'));
      await tester.scrollUntilVisible(
        save,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('floorplan-trace-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();

      final room = built.controller.rooms.single;
      expect(room.name, 'Dormitorio plano');
      expect(room.acquisition.method, RoomAcquisitionMethod.floorplanTrace);
      expect(room.metrics, isNull);
      expect(edgeLengths(room.corners).first, closeTo(4.2, 1e-9));
      expect(find.text('Plano o croquis trazado y calibrado'), findsOneWidget);
      expect(find.byKey(const ValueKey('edit-trace-room-1')), findsOneWidget);
      expect(tester.takeException(), isNull);

      final editRoom = find.byKey(const ValueKey('edit-room-room-1'));
      await tester.drag(
        find.byKey(const ValueKey('spatial-capture-screen')),
        const Offset(0, -800),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(editRoom);
      await tester.pumpAndSettle();
      expect(editRoom.hitTestable(), findsOneWidget);
      await tester.tap(editRoom);
      await tester.pumpAndSettle();
      expect(find.byType(RoomEditorScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('add-opening-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(RoomEditorScreen))).pop();
      await tester.pumpAndSettle();

      final fresh = await _newController(
        tester,
        backend: built.backend,
        ar: built.ar,
        store: built.store,
      );
      expect(
        fresh.rooms.single.acquisition.method,
        RoomAcquisitionMethod.floorplanTrace,
      );
      expect(fresh.traceForRoom('room-1'), isNotNull);
      expect(fresh.preview!.document['version'], '2.0');
      expect(fresh.preview!.document.toString(), isNot(contains('source-')));

      final trace = fresh.traceForRoom('room-1')!;
      await fresh.discardFloorplanSource(trace.sourceId);
      await tester.pumpWidget(
        MaterialApp(
          theme: andeanTheme(),
          home: SpatialCaptureScreen(controller: fresh),
        ),
      );
      await tester.pumpAndSettle();
      final editTrace = find.byKey(const ValueKey('edit-trace-room-1'));
      await tester.ensureVisible(editTrace);
      await tester.tap(editTrace);
      await tester.pumpAndSettle();
      expect(
        find.text('La imagen original ya no está disponible.'),
        findsOneWidget,
      );
      expect(fresh.rooms.single.name, 'Dormitorio plano');
      expect(fresh.preview!.document['version'], '2.0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('move zoom and trace modes own mutually exclusive gestures', (
    tester,
  ) async {
    final source = _FloorplanPhotoSource(
      await tester.runAsync(_testPng) ?? Uint8List(0),
    );
    final built = await _build(tester, traceSource: source);
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: FloorplanTraceScreen(controller: built.controller),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('floorplan-pick-source')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final canvas = find.byKey(const ValueKey('floorplan-trace-canvas'));
    final canvasOrigin = tester.getTopLeft(canvas);
    final canvasSize = tester.getSize(canvas);
    await tester.tap(find.text('Trazar'));
    await tester.pump();
    await tester.tapAt(canvasOrigin + canvasSize.center(Offset.zero));
    await tester.pump();
    List<FloorPoint> paintedPoints() => List<FloorPoint>.of(
      (tester
                      .widget<CustomPaint>(
                        find.byKey(const ValueKey('floorplan-trace-paint')),
                      )
                      .painter
                  as dynamic)
              .points
          as List<FloorPoint>,
    );
    final originalPoints = paintedPoints();
    expect(originalPoints, hasLength(1));

    await tester.tap(find.text('Mover / zoom'));
    await tester.pump();
    final viewerFinder = find.byKey(
      const ValueKey('floorplan-interactive-viewer'),
    );
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    final transform = viewer.transformationController!;
    final center = tester.getCenter(viewerFinder);
    final first = await tester.startGesture(
      center + const Offset(-30, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(30, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(center + const Offset(-45, 0));
    await second.moveTo(center + const Offset(45, 0));
    await tester.pump();
    await first.moveTo(center + const Offset(-65, 0));
    await second.moveTo(center + const Offset(65, 0));
    await tester.pump();
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
    final beforePan = transform.value.clone();
    await first.moveTo(center + const Offset(-90, -20));
    await second.moveTo(center + const Offset(40, -20));
    await tester.pump();
    expect(transform.value.getTranslation(), isNot(beforePan.getTranslation()));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
    expect(
      paintedPoints(),
      originalPoints,
      reason: 'navegar no edita vértices',
    );

    final viewportTap = canvasSize.center(Offset.zero);
    final sceneTap = transform.toScene(viewportTap);
    final expected = normalizedTracePoint(
      sceneX: sceneTap.dx,
      sceneY: sceneTap.dy,
      viewportWidth: canvasSize.width,
      viewportHeight: canvasSize.height,
      imageWidth: 100,
      imageHeight: 80,
    );
    expect(expected, isNotNull);
    await tester.tap(find.text('Trazar'));
    await tester.pump();
    final preservedTransform = transform.value.clone();
    await tester.tapAt(canvasOrigin + viewportTap);
    await tester.pump();
    final afterTrace = paintedPoints();
    expect(afterTrace, hasLength(2));
    expect(afterTrace.first, originalPoints.first);
    expect(afterTrace.last.x, closeTo(expected!.x, 1e-9));
    expect(afterTrace.last.z, closeTo(expected.z, 1e-9));
    expect(transform.value.storage, preservedTransform.storage);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retracing a traced room keeps its exact height and provenance', (
    tester,
  ) async {
    final source = _FloorplanPhotoSource(
      await tester.runAsync(_testPng) ?? Uint8List(0),
    );
    final built = await _build(tester, traceSource: source);
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    late CapturedRoom room;
    await tester.runAsync(() async {
      final picked = await built.controller.pickFloorplanSource();
      await built.controller.saveFloorplanTrace(
        name: 'Dormitorio plano',
        sourceId: picked!.sourceId,
        contentType: picked.contentType,
        imageWidth: 100,
        imageHeight: 80,
        normalizedTrace: const [
          FloorPoint(0.1, 0.125),
          FloorPoint(0.5, 0.125),
          FloorPoint(0.5, 0.5),
          FloorPoint(0.1, 0.5),
        ],
        referenceEdge: 0,
        referenceMeters: 4.234,
        height: 2.655,
      );
      room = built.controller.rooms.single;
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => FloorplanTraceScreen(
                      controller: built.controller,
                      roomId: room.id,
                    ),
                  ),
                ),
                child: const Text('Editar trazado'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Editar trazado'));
    await tester.pumpAndSettle();

    final save = find.byKey(const ValueKey('floorplan-trace-save'));
    await tester.scrollUntilVisible(
      save,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('floorplan-trace-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    // The retrace starts from what the agent already recorded, without
    // rounding it to centimetres.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('trace-room-height')))
          .controller!
          .text,
      '2.655',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('trace-reference-metres')),
          )
          .controller!
          .text,
      '4.234',
    );

    await tester.tap(save);
    await tester.pumpAndSettle();

    final after = built.controller.rooms.single;
    expect(after.id, room.id);
    expect(after.name, 'Dormitorio plano');
    expect(after.height.value, 2.655);
    expect(after.openings, isEmpty);
    expect(after.acquisition.method, RoomAcquisitionMethod.floorplanTrace);
    expect(built.controller.traceForRoom(room.id)!.referenceMeters, 4.234);
    expect(tester.takeException(), isNull);
  });

  testWidgets('draws and calibrates an irregular room without ARCore', (
    tester,
  ) async {
    final built = await _build(tester);
    built.ar.available = ArAvailability.unsupported;
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: SpatialCaptureScreen(controller: built.controller),
      ),
    );
    await tester.pumpAndSettle();
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('capture-room-button')),
    );
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('manual-capture-method')),
    );
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('manual-shape-irregular')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('sketch-room-name')),
      'Estudio irregular',
    );
    final canvas = find.byKey(const ValueKey('sketch-canvas'));
    await tester.ensureVisible(canvas);
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(canvas);
    for (final offset in const [
      Offset(25, 25),
      Offset(190, 25),
      Offset(200, 85),
      Offset(110, 150),
      Offset(25, 110),
    ]) {
      await tester.tapAt(origin + offset);
      await tester.pump();
    }
    await tester.tapAt(origin + const Offset(70, 145));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sketch-undo')));
    await tester.pump();
    final close = find.byKey(const ValueKey('sketch-close'));
    await tester.ensureVisible(close);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sketch-reference-metres')),
      findsOneWidget,
    );
    await tester.ensureVisible(canvas);
    final closedOrigin = tester.getTopLeft(canvas);
    await tester.tapAt(closedOrigin + const Offset(25, 110));
    await tester.pump();
    final remove = find.byKey(const ValueKey('sketch-remove'));
    expect(tester.widget<TextButton>(remove).onPressed, isNotNull);
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('sketch-reference-metres')),
      '4,20',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sketch-room-height')),
      '2.70',
    );
    expect(find.byKey(const ValueKey('sketch-undo')), findsOneWidget);
    expect(find.byKey(const ValueKey('sketch-reset')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _tapAndSettle(tester, find.byKey(const ValueKey('sketch-confirm')));

    expect(built.controller.rooms, hasLength(1));
    final room = built.controller.rooms.single;
    expect(room.name, 'Estudio irregular');
    expect(room.corners, hasLength(4));
    expect(edgeLengths(room.corners).first, closeTo(4.2, 1e-9));
    expect(room.acquisition.method, RoomAcquisitionMethod.manualSketch);
    expect(room.metrics, isNull);
    expect(
      find.text('Croquis manual calibrado con una medida real'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final edit = find.byKey(const ValueKey('edit-room-room-1'));
    await tester.drag(
      find.byKey(const ValueKey('spatial-capture-screen')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(edit.hitTestable(), findsOneWidget);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.byType(RoomEditorScreen), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('room-editor-scroll')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.text('Puertas y ventanas'), findsOneWidget);
  });

  testWidgets('restores a persisted manual room in a fresh screen lifecycle', (
    tester,
  ) async {
    final backend = FakeSceneBackend();
    final ar = FakeArCapture()..available = ArAvailability.unsupported;
    final store = InMemoryCaptureDraftStore();
    final original = await _newController(
      tester,
      backend: backend,
      ar: ar,
      store: store,
    );
    await tester.runAsync(
      () => original.createManualRectangularRoom(
        name: 'Dormitorio prueba',
        length: 4.20,
        width: 3.70,
        height: 2.60,
      ),
    );
    original.dispose();

    final restored = await _newController(
      tester,
      backend: backend,
      ar: ar,
      store: store,
    );
    addTearDown(restored.dispose);
    final room = restored.rooms.single;
    expect(room.name, 'Dormitorio prueba');
    expect(room.acquisition.method, RoomAcquisitionMethod.manual);
    expect(room.acquisition.arMetrics, isNull);
    expect(
      edgeLengths(room.corners),
      orderedEquals([
        closeTo(4.20, 1e-9),
        closeTo(3.70, 1e-9),
        closeTo(4.20, 1e-9),
        closeTo(3.70, 1e-9),
      ]),
    );
    expect(polygonArea(room.corners), closeTo(15.54, 1e-9));
    expect(room.height, const RoomHeight(2.60, HeightSource.manual));
    expect(restored.syncState, CaptureSyncState.pending);
    expect(restored.preview, isNotNull);
    expect(restored.preview!.document['version'], '2.0');

    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: SpatialCaptureScreen(controller: restored)),
    );
    await tester.pump();

    for (final text in [
      'Captura espacial',
      'Pendiente de enviar',
      'Ambientes',
      'Dormitorio prueba',
      'Superficie estimada: 15,54 m²',
      'Altura: 2,60 m (ingresada a mano)',
      'Capturar ambiente',
    ]) {
      final finder = find.text(text);
      await tester.ensureVisible(finder);
      await tester.pump();
      expect(finder.hitTestable(), findsOneWidget);
    }

    await _tapAndSettle(tester, find.byKey(const ValueKey('edit-room-room-1')));
    expect(find.byType(RoomEditorScreen), findsOneWidget);
    expect(find.text('Lados'), findsOneWidget);
  });

  testWidgets('isolates scroll state and remains reachable after re-entry', (
    tester,
  ) async {
    final built = await _build(tester);
    await tester.runAsync(
      () => built.controller.createManualRectangularRoom(
        name: 'Dormitorio prueba',
        length: 4.20,
        width: 3.70,
        height: 2.60,
      ),
    );
    final inheritedScroll = ScrollController(initialScrollOffset: 1200);
    addTearDown(inheritedScroll.dispose);
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      PrimaryScrollController(
        controller: inheritedScroll,
        child: MaterialApp(
          home: SpatialCaptureScreen(controller: built.controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pendiente de enviar').hitTestable(), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('spatial-capture-screen')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.text('Capturar ambiente').hitTestable(), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: PrimaryScrollController(
          controller: inheritedScroll,
          child: SpatialCaptureScreen(controller: built.controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final roomName = find.text('Dormitorio prueba');
    await tester.scrollUntilVisible(
      roomName,
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('spatial-capture-screen')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
    expect(roomName.hitTestable(), findsOneWidget);
  });

  testWidgets('room editor owns its scroll state on a narrow phone', (
    tester,
  ) async {
    final built = await _build(tester);
    await tester.runAsync(
      () => built.controller.createManualRectangularRoom(
        name: 'Dormitorio prueba',
        length: 4.20,
        width: 3.70,
        height: 2.60,
      ),
    );
    expect(built.controller.rooms.single.acquisition.arMetrics, isNull);
    final inheritedScroll = ScrollController(initialScrollOffset: 1200);
    addTearDown(inheritedScroll.dispose);
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      PrimaryScrollController(
        controller: inheritedScroll,
        child: MaterialApp(
          home: SpatialCaptureScreen(controller: built.controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editButton = find.byKey(const ValueKey('edit-room-room-1'));
    await tester.scrollUntilVisible(
      editButton,
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('spatial-capture-screen')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(editButton.hitTestable(), findsOneWidget);
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    expect(find.byType(RoomEditorScreen), findsOneWidget);
    for (final text in [
      'Dormitorio prueba',
      'Altura',
      'Altura: 2,60 m (ingresada a mano)',
      'Lados',
      'Puertas y ventanas',
      'Agregar puerta o ventana',
    ]) {
      final finder = find.text(text);
      await tester.ensureVisible(finder);
      await tester.pump();
      expect(finder.hitTestable(), findsOneWidget);
    }
  });

  testWidgets('room editor lays out and saves height with the app theme', (
    tester,
  ) async {
    final built = await _build(tester);
    await tester.runAsync(
      () => built.controller.createManualRectangularRoom(
        name: 'Dormitorio prueba',
        length: 4.20,
        width: 3.70,
        height: 2.60,
      ),
    );
    final inheritedScroll = ScrollController(initialScrollOffset: 1200);
    addTearDown(inheritedScroll.dispose);
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: PrimaryScrollController(
          controller: inheritedScroll,
          child: RoomEditorScreen(
            controller: built.controller,
            roomId: 'room-1',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Dormitorio prueba').hitTestable(), findsOneWidget);
    expect(find.text('Altura').hitTestable(), findsOneWidget);
    expect(
      find.text('Altura: 2,60 m (ingresada a mano)').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Altura medida a mano (m)'), findsOneWidget);
    expect(find.text('Lados'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('room-height-field')),
      '2,65',
    );
    await tester.tap(find.byKey(const ValueKey('room-height-save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Altura: 2,65 m (ingresada a mano)'), findsOneWidget);
    expect(built.controller.rooms.single.height.value, 2.65);
    expect(built.controller.rooms.single.height.source, HeightSource.manual);

    final openings = find.text('Puertas y ventanas');
    await tester.ensureVisible(openings);
    await tester.pump();
    expect(openings.hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('add-opening-button')), findsOneWidget);

    final room = built.controller.rooms.single;
    await tester.runAsync(
      () => built.controller.updateRoom(
        room.copyWith(
          boxes: const [
            OccupancyBox(
              id: 'box-1',
              centerX: 1,
              centerZ: 1,
              width: 0.8,
              depth: 0.6,
              height: null,
              source: BoxSource.depth,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boxField = find.byKey(const ValueKey('box-height-field-box-1'));
    await tester.ensureVisible(boxField);
    await tester.enterText(boxField, '0,85');
    final boxSave = find.byKey(const ValueKey('box-height-save-box-1'));
    await tester.ensureVisible(boxSave);
    await tester.tap(boxSave);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(built.controller.rooms.single.boxes.single.height, 0.85);
  });

  testWidgets('reference action has finite constraints with the app theme', (
    tester,
  ) async {
    final built = await _build(tester);
    built.ar.results.add(rectangle(4.20, 3.70));
    await tester.runAsync(
      () => built.controller.captureRoom('Dormitorio prueba'),
    );
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: RoomEditorScreen(controller: built.controller, roomId: 'room-1'),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Lados y tolerancia'), findsOneWidget);

    final field = find.byKey(const ValueKey('reference-field-0'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '4,15');
    final save = find.byKey(const ValueKey('reference-save-0'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(built.controller.rooms.single.references.single.edgeIndex, 0);
    expect(
      built.controller.rooms.single.references.single.referenceMeters,
      4.15,
    );
  });

  testWidgets('opening position uses metres and preserves normalized domain', (
    tester,
  ) async {
    final built = await _build(tester);
    await tester.runAsync(
      () => built.controller.createManualRectangularRoom(
        name: 'Dormitorio prueba',
        length: 4.20,
        width: 3.70,
        height: 2.65,
      ),
    );
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: RoomEditorScreen(controller: built.controller, roomId: 'room-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final add = find.byKey(const ValueKey('add-opening-button'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final position = find.byKey(const ValueKey('opening-position-metres'));
    expect(tester.widget<TextField>(position).controller!.text, '2,10');
    await tester.enterText(position, '2.10');
    await tester.tap(find.byKey(const ValueKey('opening-confirm')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(built.controller.rooms.single.openings.single.position, 0.5);

    final openingTile = find.textContaining('Puerta 1');
    await tester.ensureVisible(openingTile);
    await tester.tap(openingTile);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(position).controller!.text, '2,10');
    await tester.enterText(position, '0,10');
    await tester.tap(find.byKey(const ValueKey('opening-confirm')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text(
        'La abertura se sale de la pared. Mové su posición hacia el centro.',
      ),
      findsOneWidget,
    );
    expect(built.controller.rooms.single.openings.single.position, 0.5);
  });

  testWidgets(
    'invalid stored opening stays visible and can be repaired explicitly',
    (tester) async {
      final built = await _build(tester);
      await tester.runAsync(() async {
        await built.controller.createManualRectangularRoom(
          name: 'Dormitorio prueba',
          length: 4.2,
          width: 3.7,
          height: 2.6,
        );
        final room = built.controller.rooms.single;
        await built.controller.updateRoom(
          room.copyWith(
            openings: const [
              RoomOpening(
                id: 'door-invalid',
                edgeIndex: 9,
                position: 0.5,
                width: 0.9,
                height: 2.1,
                type: OpeningType.door,
              ),
            ],
          ),
        );
      });
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: andeanTheme(),
          home: RoomEditorScreen(
            controller: built.controller,
            roomId: 'room-1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final warning = find.byKey(const ValueKey('invalid-openings-warning'));
      await tester.ensureVisible(warning);
      expect(warning, findsOneWidget);
      expect(built.controller.rooms.single.openings.single.edgeIndex, 9);

      final tile = find.textContaining('Puerta 1');
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'La pared guardada ya no existe. Seleccioná una pared válida.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('opening-confirm')));
      await tester.pump();
      expect(built.controller.rooms.single.openings.single.edgeIndex, 9);

      await tester.tap(find.byKey(const ValueKey('opening-edge')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Lado 1 (').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('opening-position-metres')),
        '2,10',
      );
      await tester.tap(find.byKey(const ValueKey('opening-confirm')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final repaired = built.controller.rooms.single.openings.single;
      expect(repaired.id, 'door-invalid');
      expect(repaired.edgeIndex, 0);
      expect(repaired.position, 0.5);
      expect(repaired.width, 0.9);
      expect(repaired.height, 2.1);
      expect(repaired.type, OpeningType.door);
    },
  );

  testWidgets('shows automatic capture unavailable on unsupported devices', (
    tester,
  ) async {
    final built = await _build(tester);
    built.ar.available = ArAvailability.unsupported;
    await _pump(tester, built.controller);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('capture-room-button')),
    );
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('automatic-capture-method')),
    );

    expect(built.ar.availabilityChecks, 1);
    expect(
      find.text('No disponible: este teléfono no admite ARCore.'),
      findsOneWidget,
    );
    expect(built.ar.names, isEmpty);
    expect(find.byKey(const ValueKey('manual-capture-method')), findsOneWidget);
  });

  testWidgets('sends the capture and reports it as synchronized', (
    tester,
  ) async {
    final built = await _build(tester);
    built.ar.results.add(rectangle(4, 3));
    await tester.runAsync(() => built.controller.captureRoom('Estar'));
    await _pump(tester, built.controller);

    await _tapAndSettle(tester, find.byKey(const ValueKey('sync-button')));

    expect(find.text('Escena sincronizada'), findsOneWidget);
    expect(built.backend.revision, 1);
  });

  testWidgets('offers to overwrite after a remote change', (tester) async {
    final built = await _build(tester);
    built.ar.results.add(rectangle(4, 3));
    built.backend.editRemotely({'version': '2.0'});
    await tester.runAsync(() => built.controller.captureRoom('Estar'));
    await _pump(tester, built.controller);

    await _tapAndSettle(tester, find.byKey(const ValueKey('sync-button')));

    expect(find.text('Conflicto con el servidor'), findsOneWidget);
    await _tapAndSettle(tester, find.byKey(const ValueKey('overwrite-button')));

    expect(find.text('Escena sincronizada'), findsOneWidget);
    expect(built.backend.revision, 2);
  });

  testWidgets('keeps sending disabled while the listing is under review', (
    tester,
  ) async {
    final built = await _build(tester);
    built.ar.results.add(rectangle(4, 3));
    await tester.runAsync(() => built.controller.captureRoom('Estar'));
    await _pump(
      tester,
      built.controller,
      syncBlockedReason: 'El inmueble está en revisión.',
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('sync-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('El inmueble está en revisión.'), findsOneWidget);
  });

  testWidgets('records a tape reference and shows the observed error', (
    tester,
  ) async {
    final built = await _build(tester);
    built.ar.results.add(rectangle(4, 3, height: null));
    await tester.runAsync(() => built.controller.captureRoom('Estar'));
    await _pump(tester, built.controller);

    await _tapAndSettle(tester, find.byKey(const ValueKey('edit-room-room-1')));

    expect(find.text('Altura: 2,40 m (supuesta, sin medir)'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('room-height-field')),
      '2,55',
    );
    await _tapAndSettle(tester, find.byKey(const ValueKey('room-height-save')));
    expect(find.text('Altura: 2,55 m (ingresada a mano)'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('reference-field-0')),
      '3,95',
    );
    await _tapAndSettle(tester, find.byKey(const ValueKey('reference-save-0')));

    expect(find.text('Error observado: +0,05 m (1,3 %)'), findsOneWidget);
  });

  testWidgets('a reference rescales the room and says so', (tester) async {
    final built = await _build(tester);
    built.ar.results.add(rectangle(4, 3));
    await tester.runAsync(() => built.controller.captureRoom('Estar'));
    await _pump(tester, built.controller);

    await _tapAndSettle(tester, find.byKey(const ValueKey('edit-room-room-1')));
    await tester.enterText(
      find.byKey(const ValueKey('reference-field-0')),
      '4,2',
    );
    await _tapAndSettle(tester, find.byKey(const ValueKey('reference-save-0')));

    expect(
      find.text('Escala corregida +5,0 % con 1 referencia.'),
      findsOneWidget,
    );
    expect(
      find.text('Lado 2: 3,00 m capturado → 3,15 m corregido'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Superficie estimada: 13,23 m²'), findsOneWidget);
    expect(find.text('Escala corregida con 1 referencia'), findsOneWidget);
  });

  testWidgets(
    'a walkthrough is the default capture and its proposal is announced',
    (tester) async {
      final built = await _build(tester);
      built.ar.results.add(walkthrough());
      await _pump(tester, built.controller);

      await _tapAndSettle(
        tester,
        find.byKey(const ValueKey('capture-room-button')),
      );
      await _chooseAutomaticCapture(tester);
      expect(find.text('Recorrido'), findsOneWidget);
      expect(find.textContaining('Recomendado.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('room-name-field')),
        'Estar',
      );
      await _tapAndSettle(
        tester,
        find.byKey(const ValueKey('room-name-confirm')),
      );

      expect(built.ar.modes, [CaptureMode.walkthrough]);
      expect(
        find.textContaining('Contorno propuesto con 4 paredes'),
        findsOneWidget,
      );
      expect(find.text('Estar'), findsOneWidget);
    },
  );

  testWidgets('the agent can fall back to marking walls', (tester) async {
    final built = await _build(tester);
    built.ar.results.add(rectangle(4, 3));
    await _pump(tester, built.controller);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('capture-room-button')),
    );
    await _chooseAutomaticCapture(tester);
    await tester.enterText(
      find.byKey(const ValueKey('room-name-field')),
      'Estar',
    );
    await tester.tap(find.text('Marcar paredes'));
    await tester.pumpAndSettle();
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('room-name-confirm')),
    );

    expect(built.ar.modes, [CaptureMode.walls]);
  });

  testWidgets('the new-room dialog fits on a phone with the keyboard open', (
    tester,
  ) async {
    final built = await _build(tester);
    await tester.pumpWidget(
      MaterialApp(home: SpatialCaptureScreen(controller: built.controller)),
    );
    // S23 FE in logical pixels, with the keyboard covering the lower part.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('capture-room-button')));
    await tester.pumpAndSettle();
    await _chooseAutomaticCapture(tester);
    await tester.showKeyboard(find.byKey(const ValueKey('room-name-field')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('room-name-confirm')), findsOneWidget);
  });

  testWidgets('opens the camera with a suggested name in one tap', (
    tester,
  ) async {
    final built = await _build(tester);
    built.ar.results.add(walkthrough());
    await _pump(tester, built.controller);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('capture-room-button')),
    );
    await _chooseAutomaticCapture(tester);
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('room-name-confirm')),
    );

    expect(built.ar.names, ['Ambiente 1']);
  });

  testWidgets('explains an empty name instead of ignoring the tap', (
    tester,
  ) async {
    final built = await _build(tester);
    await _pump(tester, built.controller);

    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('capture-room-button')),
    );
    await _chooseAutomaticCapture(tester);
    await tester.enterText(find.byKey(const ValueKey('room-name-field')), '  ');
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('room-name-confirm')),
    );

    expect(find.text('Escribí un nombre para el ambiente.'), findsOneWidget);
    expect(built.ar.names, isEmpty);
  });
}
