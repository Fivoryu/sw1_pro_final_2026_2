import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:captura_mobile/data/services/ar_capture_channel.dart';
import 'package:captura_mobile/data/services/local_floorplan_analyzer.dart';
import 'package:captura_mobile/data/services/photo_source.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:captura_mobile/data/services/staff_floorplan_interpretation_api.dart';
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

class _FixedFloorplanAnalyzer extends LocalFloorplanAnalyzer {
  const _FixedFloorplanAnalyzer({
    this.contour = const [
      FloorPoint(0.2, 0.2),
      FloorPoint(0.8, 0.2),
      FloorPoint(0.8, 0.8),
      FloorPoint(0.2, 0.8),
    ],
  });

  final List<FloorPoint> contour;

  @override
  Future<FloorplanAnalysisResult> analyze({
    required List<int> rgba,
    required int width,
    required int height,
  }) async => FloorplanAnalysisResult(
    status: FloorplanAnalysisStatus.success,
    message: 'Detectamos un contorno. Revisalo y confirmá cada medida.',
    contour: contour,
  );
}

class _SequencedFloorplanAnalyzer extends LocalFloorplanAnalyzer {
  final first = Completer<FloorplanAnalysisResult>();
  var calls = 0;

  @override
  Future<FloorplanAnalysisResult> analyze({
    required List<int> rgba,
    required int width,
    required int height,
  }) {
    calls++;
    if (calls == 1) return first.future;
    return Future.value(
      const FloorplanAnalysisResult(
        status: FloorplanAnalysisStatus.success,
        message: 'Resultado de la segunda imagen',
        contour: [
          FloorPoint(0.2, 0.2),
          FloorPoint(0.8, 0.2),
          FloorPoint(0.8, 0.8),
          FloorPoint(0.2, 0.8),
        ],
      ),
    );
  }
}

class _CountingFloorplanAnalyzer extends LocalFloorplanAnalyzer {
  var calls = 0;

  @override
  Future<FloorplanAnalysisResult> analyze({
    required List<int> rgba,
    required int width,
    required int height,
  }) async {
    calls++;
    return const FloorplanAnalysisResult(
      status: FloorplanAnalysisStatus.success,
      message: 'Resultado local no esperado',
      contour: [
        FloorPoint(0.2, 0.2),
        FloorPoint(0.8, 0.2),
        FloorPoint(0.8, 0.8),
        FloorPoint(0.2, 0.8),
      ],
    );
  }
}

class _FailingFloorplanInterpretationApi implements FloorplanInterpretationApi {
  @override
  Future<FloorplanInterpretationResult> interpret({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required List<int> imageBytes,
    required String contentType,
  }) async => throw StateError('provider offline');
}

class _ProposedFloorplanInterpretationApi
    implements FloorplanInterpretationApi {
  @override
  Future<FloorplanInterpretationResult> interpret({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required List<int> imageBytes,
    required String contentType,
  }) async => const FloorplanInterpretationResult(
    status: FloorplanInterpretationStatus.success,
    rooms: [
      InterpretedRoomCandidate(
        id: 'groq-room',
        contour: [
          FloorPoint(0.2, 0.2),
          FloorPoint(0.8, 0.2),
          FloorPoint(0.8, 0.8),
          FloorPoint(0.2, 0.8),
        ],
        measurements: [
          WallMeasurementCandidate(
            id: 'groq-0',
            literalText: '4.00 m',
            meters: 4,
            edgeIndex: 0,
            explicitUnit: true,
            status: WallMeasurementCandidateStatus.proposed,
          ),
        ],
        openings: [],
      ),
    ],
  );
}

class _ConflictFloorplanInterpretationApi
    implements FloorplanInterpretationApi {
  @override
  Future<FloorplanInterpretationResult> interpret({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required List<int> imageBytes,
    required String contentType,
  }) async => const FloorplanInterpretationResult(
    status: FloorplanInterpretationStatus.partial,
    rooms: [
      InterpretedRoomCandidate(
        id: 'ai-room',
        contour: [
          FloorPoint(0.2, 0.2),
          FloorPoint(0.8, 0.2),
          FloorPoint(0.8, 0.8),
          FloorPoint(0.2, 0.8),
        ],
        measurements: [
          WallMeasurementCandidate(
            id: 'ai-0',
            literalText: '419',
            meters: null,
            rawValue: 419,
            edgeIndex: 0,
            explicitUnit: false,
            ambiguityReason:
                'La IA leyó una medida sin una unidad métrica confirmada; solo es evidencia textual.',
            status: WallMeasurementCandidateStatus.unresolved,
          ),
        ],
        openings: [],
      ),
    ],
    informationStillNeeded: ['Confirmar la medida visible.'],
  );
}

class _ResultFloorplanInterpretationApi implements FloorplanInterpretationApi {
  const _ResultFloorplanInterpretationApi(this.result);

  final FloorplanInterpretationResult result;

  @override
  Future<FloorplanInterpretationResult> interpret({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required List<int> imageBytes,
    required String contentType,
  }) async => result;
}

class _SequencedFloorplanInterpretationApi
    implements FloorplanInterpretationApi {
  _SequencedFloorplanInterpretationApi(this.results);

  final List<FloorplanInterpretationResult> results;
  var _next = 0;

  @override
  Future<FloorplanInterpretationResult> interpret({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required List<int> imageBytes,
    required String contentType,
  }) async => results[_next++];
}

class _IncompleteOpeningFloorplanInterpretationApi
    implements FloorplanInterpretationApi {
  @override
  Future<FloorplanInterpretationResult> interpret({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required List<int> imageBytes,
    required String contentType,
  }) async => const FloorplanInterpretationResult(
    status: FloorplanInterpretationStatus.partial,
    rooms: [
      InterpretedRoomCandidate(
        id: 'ai-room',
        contour: [
          FloorPoint(0.2, 0.2),
          FloorPoint(0.8, 0.2),
          FloorPoint(0.8, 0.8),
          FloorPoint(0.2, 0.8),
        ],
        measurements: [],
        openings: [
          InterpretedOpeningProposal(
            edgeIndex: 1,
            type: FloorplanOpeningCandidateType.door,
          ),
        ],
      ),
    ],
  );
}

class _PentagonOpeningsFloorplanInterpretationApi
    implements FloorplanInterpretationApi {
  @override
  Future<FloorplanInterpretationResult> interpret({
    required String accessToken,
    required String agencyId,
    required String listingId,
    required List<int> imageBytes,
    required String contentType,
  }) async => const FloorplanInterpretationResult(
    status: FloorplanInterpretationStatus.success,
    rooms: [
      InterpretedRoomCandidate(
        id: 'pentagon-room',
        contour: [
          FloorPoint(0.20, 0.20),
          FloorPoint(0.70, 0.15),
          FloorPoint(0.85, 0.50),
          FloorPoint(0.60, 0.82),
          FloorPoint(0.18, 0.70),
        ],
        measurements: [
          WallMeasurementCandidate(
            id: 'pentagon-edge-0',
            literalText: '3.50 m',
            meters: 3.50,
            edgeIndex: 0,
            explicitUnit: true,
            status: WallMeasurementCandidateStatus.proposed,
          ),
        ],
        openings: [
          InterpretedOpeningProposal(
            edgeIndex: 0,
            type: FloorplanOpeningCandidateType.window,
            position: 0.40,
            normalizedWidth: 0.20,
            confidence: 0.90,
          ),
          InterpretedOpeningProposal(
            edgeIndex: 1,
            type: FloorplanOpeningCandidateType.window,
            position: 0.55,
            normalizedWidth: 0.18,
            confidence: 0.88,
          ),
          InterpretedOpeningProposal(
            edgeIndex: 3,
            type: FloorplanOpeningCandidateType.door,
            position: 0.50,
            normalizedWidth: 0.22,
            confidence: 0.95,
          ),
        ],
      ),
    ],
  );
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

Future<void> _pumpRemoteFloorplan(
  WidgetTester tester,
  FloorplanInterpretationApi interpreter,
) async {
  final source = _FloorplanPhotoSource(
    await tester.runAsync(_testPng) ?? Uint8List(0),
  );
  final analyzer = _CountingFloorplanAnalyzer();
  final built = await _build(
    tester,
    traceSource: source,
    floorplanInterpreter: interpreter,
  );
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: andeanTheme(),
      home: FloorplanTraceScreen(
        controller: built.controller,
        analyzer: analyzer,
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('floorplan-pick-source')));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

Future<_Built> _build(
  WidgetTester tester, {
  PhotoSource? traceSource,
  FloorplanInterpretationApi? floorplanInterpreter,
}) async {
  final backend = FakeSceneBackend();
  final ar = FakeArCapture();
  final store = InMemoryCaptureDraftStore();
  final controller = await _newController(
    tester,
    backend: backend,
    ar: ar,
    store: store,
    traceSource: traceSource,
    floorplanInterpreter: floorplanInterpreter,
  );
  return (controller: controller, backend: backend, ar: ar, store: store);
}

Future<SpatialCaptureController> _newController(
  WidgetTester tester, {
  required FakeSceneBackend backend,
  required FakeArCapture ar,
  required InMemoryCaptureDraftStore store,
  PhotoSource? traceSource,
  FloorplanInterpretationApi? floorplanInterpreter,
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
      floorplanInterpreter: floorplanInterpreter,
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
    expect(find.text('Dibujar ambiente'), findsOneWidget);
    expect(find.textContaining('imagen'), findsOneWidget);
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('manual-capture-method')),
    );
    await _tapAndSettle(
      tester,
      find.byKey(const ValueKey('manual-shape-rectangle')),
    );
    expect(find.text('Largo del ambiente (m)'), findsNothing);
    expect(find.text('Ancho del ambiente (m)'), findsNothing);
    expect(find.text('Altura del ambiente (m)'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('sketch-room-name')),
      'Dormitorio',
    );
    for (final entry in const ['4,20', '3,70', '4,20', '3,70'].indexed) {
      await tester.enterText(
        find.byKey(ValueKey('sketch-wall-${entry.$1}')),
        entry.$2,
      );
    }
    await tester.enterText(
      find.byKey(const ValueKey('sketch-room-height')),
      '2,60',
    );
    await tester.pump();
    expect(
      find.bySemanticsLabel('Geometría resuelta y ajustada de 4 paredes'),
      findsOneWidget,
    );
    await _tapAndSettle(tester, find.byKey(const ValueKey('sketch-confirm')));

    expect(built.ar.availabilityChecks, 0);
    expect(find.text('Dormitorio'), findsOneWidget);
    expect(find.text('Superficie estimada: 15,54 m²'), findsOneWidget);
    expect(find.text('Croquis manual con medidas por pared'), findsOneWidget);
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
    expect(find.text('Paredes'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-opening-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('reference-field-0')), findsOneWidget);
  });

  testWidgets('manual templates stay stable until every wall is measured', (
    tester,
  ) async {
    final built = await _build(tester);
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await _pump(tester, built.controller);

    Future<void> openTemplate(String key) async {
      await _tapAndSettle(
        tester,
        find.byKey(const ValueKey('capture-room-button')),
      );
      await _tapAndSettle(
        tester,
        find.byKey(const ValueKey('manual-capture-method')),
      );
      await _tapAndSettle(tester, find.byKey(ValueKey(key)));
    }

    await openTemplate('manual-shape-rectangle');
    expect(
      find.bySemanticsLabel('Plantilla estable de 4 paredes'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('sketch-wall-0')), '3,50');
    await tester.pump();
    expect(
      find.bySemanticsLabel('Plantilla estable de 4 paredes'),
      findsOneWidget,
    );
    expect(find.text('Estado: Confirmada'), findsOneWidget);
    expect(find.text('Estado: Pendiente'), findsNWidgets(3));
    await tester.enterText(find.byKey(const ValueKey('sketch-wall-1')), '3,00');
    await tester.pump();
    expect(
      find.bySemanticsLabel('Plantilla estable de 4 paredes'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await openTemplate('manual-shape-l');
    await tester.enterText(find.byKey(const ValueKey('sketch-wall-0')), '4,00');
    await tester.pump();
    expect(
      find.bySemanticsLabel('Plantilla estable de 6 paredes'),
      findsOneWidget,
    );
    expect(find.text('Estado: Confirmada'), findsOneWidget);
    expect(find.text('Estado: Pendiente'), findsNWidgets(5));
    expect(tester.takeException(), isNull);
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
    expect(find.text('Plantilla rectangular'), findsOneWidget);
    expect(find.text('Plantilla en L'), findsOneWidget);
    expect(find.text('Dibujo libre'), findsOneWidget);
    expect(find.textContaining('import'), findsNothing);
    await _tapAndSettle(tester, find.byKey(const ValueKey('manual-shape-l')));

    await tester.enterText(
      find.byKey(const ValueKey('sketch-room-name')),
      'Cocina en L',
    );
    expect(find.byKey(const ValueKey('sketch-wall-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('sketch-wall-5')), findsOneWidget);
    const confirmed = [
      '4,000000',
      '1,333333',
      '1,619048',
      '1,333333',
      '2,380952',
      '2,666667',
    ];
    for (final entry in confirmed.indexed) {
      await tester.enterText(
        find.byKey(ValueKey('sketch-wall-${entry.$1}')),
        entry.$2,
      );
    }
    await tester.enterText(
      find.byKey(const ValueKey('sketch-room-height')),
      '2,60',
    );
    await tester.pump();
    expect(
      find.bySemanticsLabel('Geometría resuelta y ajustada de 6 paredes'),
      findsOneWidget,
    );
    expect(find.textContaining('recorte'), findsNothing);
    expect(tester.takeException(), isNull);
    await _tapAndSettle(tester, find.byKey(const ValueKey('sketch-confirm')));

    final room = built.controller.rooms.single;
    expect(room.name, 'Cocina en L');
    expect(room.corners, hasLength(6));
    expect(
      room.references.map((value) => value.edgeIndex).toSet(),
      hasLength(6),
    );
    expect(room.measurementMode, RoomMeasurementMode.wallConstraints);
    expect(fitConfirmedWallLengths(room).isCoherent, isTrue);
    expect(validateContour(room.corners), isEmpty);
    expect(polygonArea(room.corners), greaterThan(0));
    expect(room.acquisition.method, RoomAcquisitionMethod.manualSketch);
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
      expect(find.text('Dibujar ambiente'), findsOneWidget);
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
      for (var index = 0; index < 4; index++) {
        await tester.tap(find.byKey(ValueKey('wall-chip-$index')));
        await tester.pump();
        final field = find.byKey(ValueKey('trace-wall-$index'));
        await tester.scrollUntilVisible(
          field,
          150,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('floorplan-trace-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.enterText(field, '4,20');
      }
      expect(find.text('Pared de referencia'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('trace-room-height')),
        '2.65',
      );
      await tester.pumpAndSettle();
      expect(find.text('Vista previa métrica'), findsOneWidget);
      final provenance = find.text('Plano o croquis con medidas por pared');
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
      expect(
        find.text('Plano o croquis con medidas por pared'),
        findsOneWidget,
      );
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
      final addOpening = find.byKey(const ValueKey('add-opening-button'));
      await tester.scrollUntilVisible(
        addOpening,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('room-editor-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(addOpening, findsOneWidget);
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

  testWidgets('Groq proposal seeds scale without local analyzer', (
    tester,
  ) async {
    final source = _FloorplanPhotoSource(
      await tester.runAsync(_testPng) ?? Uint8List(0),
    );
    final analyzer = _CountingFloorplanAnalyzer();
    final built = await _build(
      tester,
      traceSource: source,
      floorplanInterpreter: _ProposedFloorplanInterpretationApi(),
    );
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: FloorplanTraceScreen(
          controller: built.controller,
          analyzer: analyzer,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('floorplan-pick-source')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('floorplan-trace-scroll')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(built.controller.rooms, isEmpty);

    // An unambiguous Groq metric seeds the scale without becoming a
    // user-authored value. The room is still only persisted on confirmation.
    expect(built.controller.rooms, isEmpty);
    final height = find.byKey(const ValueKey('trace-room-height'));
    await tester.scrollUntilVisible(
      height,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('floorplan-trace-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(height, '2,60');
    final save = find.byKey(const ValueKey('floorplan-trace-save'));
    expect(save.hitTestable(), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(built.controller.rooms.single.references, hasLength(4));
    expect(
      built.controller.rooms.single.references.first.provenance,
      WallMeasurementProvenance.aiDetected,
    );
    expect(analyzer.calls, 0);
    await built.controller.sync();
    expect(built.controller.syncState, CaptureSyncState.synced);
    final scenePayload = jsonEncode(built.backend.document);
    for (final acquisitionOnlyValue in [
      'groq',
      'ocr',
      source.bytes.toString(),
      'sourceId',
      'imagePath',
      'imageBytes',
      'base64',
      'providerResponse',
      'debugPayload',
      'literalText',
      'candidateStatus',
    ]) {
      expect(scenePayload, isNot(contains(acquisitionOnlyValue)));
    }

    final room = built.controller.rooms.single;
    expect(
      scenePayload,
      isNot(contains(built.controller.traceForRoom(room.id)!.sourceId)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: FloorplanTraceScreen(
          controller: built.controller,
          roomId: room.id,
          analyzer: analyzer,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final finalSave = find.byKey(const ValueKey('floorplan-trace-save'));
    expect(finalSave.hitTestable(), findsOneWidget);
    await tester.tap(finalSave);
    await tester.pumpAndSettle();
    expect(built.controller.rooms.single.references, hasLength(4));
    await built.controller.sync();
    expect(built.controller.syncState, CaptureSyncState.synced);
    expect(built.backend.document.toString(), isNot(contains('ocr')));
    expect(tester.takeException(), isNull);
  });

  for (final wallCount in [12, 26])
    testWidgets('$wallCount-wall review keeps one editor and visible plan', (
      tester,
    ) async {
      final source = _FloorplanPhotoSource(
        await tester.runAsync(_testPng) ?? Uint8List(0),
      );
      final built = await _build(tester, traceSource: source);
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final contour = [
        for (var index = 0; index < wallCount; index++)
          FloorPoint(
            0.5 + 0.32 * math.cos(index * 2 * math.pi / wallCount),
            0.5 + 0.32 * math.sin(index * 2 * math.pi / wallCount),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: andeanTheme(),
          home: FloorplanTraceScreen(
            controller: built.controller,
            analyzer: _FixedFloorplanAnalyzer(contour: contour),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('floorplan-pick-source')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('floorplan-persistent-review')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('floorplan-wall-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('floorplan-correct-geometry')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('floorplan-trace-save')).hitTestable(),
        findsOneWidget,
      );
      if (wallCount == 12) {
        await tester.showKeyboard(
          find.byKey(const ValueKey('floorplan-room-name')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('floorplan-trace-save')).hitTestable(),
          findsOneWidget,
        );
      }
      expect(find.byType(TextField).evaluate().length, lessThanOrEqualTo(3));
      expect(tester.takeException(), isNull);
    });

  testWidgets('replacing a floorplan clears a stale selected edge', (
    tester,
  ) async {
    final contour22 = [
      for (var index = 0; index < 22; index++)
        FloorPoint(
          0.5 + 0.35 * math.cos(index * 2 * math.pi / 22),
          0.5 + 0.35 * math.sin(index * 2 * math.pi / 22),
        ),
    ];
    final interpreter = _SequencedFloorplanInterpretationApi([
      FloorplanInterpretationResult(
        status: FloorplanInterpretationStatus.success,
        rooms: [
          InterpretedRoomCandidate(
            id: 'many-walls',
            contour: contour22,
            measurements: const [],
            openings: const [],
          ),
        ],
      ),
      const FloorplanInterpretationResult(
        status: FloorplanInterpretationStatus.success,
        rooms: [
          InterpretedRoomCandidate(
            id: 'five-walls',
            contour: [
              FloorPoint(0.20, 0.20),
              FloorPoint(0.70, 0.15),
              FloorPoint(0.85, 0.50),
              FloorPoint(0.60, 0.82),
              FloorPoint(0.18, 0.70),
            ],
            measurements: [],
            openings: [],
          ),
        ],
      ),
    ]);
    final source = _FloorplanPhotoSource(
      await tester.runAsync(_testPng) ?? Uint8List(0),
    );
    final analyzer = _CountingFloorplanAnalyzer();
    final built = await _build(
      tester,
      traceSource: source,
      floorplanInterpreter: interpreter,
    );
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: FloorplanTraceScreen(
          controller: built.controller,
          analyzer: analyzer,
        ),
      ),
    );

    final pick = find.byKey(const ValueKey('floorplan-pick-source'));
    await tester.tap(pick);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('22 paredes'), findsWidgets);

    final wallSelector = find.byKey(
      const ValueKey('floorplan-wall-selector'),
    );
    final edge21 = find.byKey(const ValueKey('wall-chip-21'));
    await tester.scrollUntilVisible(
      edge21,
      120,
      scrollable: find
          .descendant(of: wallSelector, matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(edge21);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(edge21).selected, isTrue);

    await tester.ensureVisible(pick);
    await tester.tap(pick);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final confirm = find.descendant(
      of: dialog,
      matching: find.byType(FilledButton),
    );
    expect(confirm, findsOneWidget);
    await tester.tap(
      confirm,
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('5 paredes'), findsWidgets);
    for (final edge in [0, 1, 2, 3, 4]) {
      expect(find.byKey(ValueKey('wall-chip-$edge')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('wall-chip-21')), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('wall-chip-0')),
          )
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale analysis cannot replace a newer floorplan image', (
    tester,
  ) async {
    final bytes = await tester.runAsync(_testPng) ?? Uint8List(0);
    final built = await _build(
      tester,
      traceSource: _FloorplanPhotoSource(bytes),
    );
    final analyzer = _SequencedFloorplanAnalyzer();
    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: FloorplanTraceScreen(
          controller: built.controller,
          analyzer: analyzer,
        ),
      ),
    );
    final pick = find.byKey(const ValueKey('floorplan-pick-source'));
    await tester.tap(pick);
    for (var attempt = 0; attempt < 20 && analyzer.calls == 0; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(analyzer.calls, 1);
    await tester.pump();
    await tester.tap(pick);
    for (var attempt = 0; attempt < 20 && analyzer.calls < 2; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(analyzer.calls, 2);
    await tester.pumpAndSettle();
    expect(find.text('Resultado de la segunda imagen'), findsOneWidget);

    analyzer.first.complete(
      const FloorplanAnalysisResult(
        status: FloorplanAnalysisStatus.success,
        message: 'Resultado obsoleto',
        contour: [
          FloorPoint(0.1, 0.1),
          FloorPoint(0.9, 0.1),
          FloorPoint(0.9, 0.9),
          FloorPoint(0.1, 0.9),
        ],
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resultado de la segunda imagen'), findsOneWidget);
    expect(find.text('Resultado obsoleto'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a remote interpretation failure keeps the image and manual path',
    (tester) async {
      final source = _FloorplanPhotoSource(
        await tester.runAsync(_testPng) ?? Uint8List(0),
      );
      final analyzer = _CountingFloorplanAnalyzer();
      final built = await _build(
        tester,
        traceSource: source,
        floorplanInterpreter: _FailingFloorplanInterpretationApi(),
      );
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: andeanTheme(),
          home: FloorplanTraceScreen(
            controller: built.controller,
            analyzer: analyzer,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('floorplan-pick-source')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'La interpretación automática no está disponible temporalmente. '
          'Podés reintentar o corregir el ambiente manualmente.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('floorplan-trace-paint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('floorplan-manual-fallback')),
        findsOneWidget,
      );
      expect(find.text('No se pudo abrir la imagen.'), findsNothing);
      expect(analyzer.calls, 0);

      await tester.tap(find.byKey(const ValueKey('floorplan-manual-fallback')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('provider unavailable result uses temporary message', (
    tester,
  ) async {
    await _pumpRemoteFloorplan(
      tester,
      const _ResultFloorplanInterpretationApi(
        FloorplanInterpretationResult(
          status: FloorplanInterpretationStatus.providerUnavailable,
        ),
      ),
    );

    expect(
      find.text(
        'La interpretación automática no está disponible temporalmente. '
        'Podés reintentar o corregir el ambiente manualmente.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('floorplan-manual-fallback')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('model low confidence uses confidence message', (tester) async {
    await _pumpRemoteFloorplan(
      tester,
      const _ResultFloorplanInterpretationApi(
        FloorplanInterpretationResult(
          status: FloorplanInterpretationStatus.lowConfidence,
        ),
      ),
    );

    expect(
      find.text(
        'No pudimos interpretar este plano con suficiente confianza. '
        'Podés corregir o trazar el ambiente manualmente.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('floorplan-manual-fallback')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('low-quality review proposal uses correction message', (
    tester,
  ) async {
    await _pumpRemoteFloorplan(
      tester,
      const _ResultFloorplanInterpretationApi(
        FloorplanInterpretationResult(
          status: FloorplanInterpretationStatus.needsReview,
          rooms: [
            InterpretedRoomCandidate(
              id: 'review-room',
              contour: [
                FloorPoint(0.2, 0.2),
                FloorPoint(0.8, 0.2),
                FloorPoint(0.8, 0.8),
                FloorPoint(0.2, 0.8),
              ],
              measurements: [],
              openings: [],
            ),
          ],
        ),
      ),
    );

    expect(
      find.text(
        'La propuesta automática necesita demasiadas correcciones. '
        'Podés reintentar o corregir la geometría.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('floorplan-result-summary')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid provider response uses correction message', (
    tester,
  ) async {
    await _pumpRemoteFloorplan(
      tester,
      const _ResultFloorplanInterpretationApi(
        FloorplanInterpretationResult(
          status: FloorplanInterpretationStatus.needsReview,
        ),
      ),
    );

    expect(
      find.text(
        'La propuesta automática necesita demasiadas correcciones. '
        'Podés reintentar o corregir la geometría.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('floorplan-manual-fallback')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid AI proposal uses normal review message', (tester) async {
    await _pumpRemoteFloorplan(tester, _ProposedFloorplanInterpretationApi());

    expect(
      find.text('Interpretación automática lista para revisión humana.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('floorplan-manual-fallback')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unresolved Groq evidence stays review-only', (tester) async {
    final source = _FloorplanPhotoSource(
      await tester.runAsync(_testPng) ?? Uint8List(0),
    );
    final analyzer = _CountingFloorplanAnalyzer();
    final built = await _build(
      tester,
      traceSource: source,
      floorplanInterpreter: _ConflictFloorplanInterpretationApi(),
    );
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: FloorplanTraceScreen(
          controller: built.controller,
          analyzer: analyzer,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('floorplan-pick-source')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('floorplan-trace-scroll')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('measurement-review-toggle'));
    expect(toggle.hitTestable(), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('floorplan-trace-scroll')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('measurement-unassigned-ai-0')),
      findsOneWidget,
    );
    expect(find.textContaining('419'), findsWidgets);
    expect(find.textContaining('410'), findsNothing);
    expect(find.textContaining('unidad sin confirmar'), findsOneWidget);
    expect(
      find.textContaining('escala resuelta automáticamente'),
      findsNothing,
    );
    expect(analyzer.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an incomplete AI opening stays reviewable without fabricated geometry',
    (tester) async {
      final source = _FloorplanPhotoSource(
        await tester.runAsync(_testPng) ?? Uint8List(0),
      );
      final analyzer = _CountingFloorplanAnalyzer();
      final built = await _build(
        tester,
        traceSource: source,
        floorplanInterpreter: _IncompleteOpeningFloorplanInterpretationApi(),
      );
      tester.view.physicalSize = const Size(720, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: andeanTheme(),
          home: FloorplanTraceScreen(
            controller: built.controller,
            analyzer: analyzer,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('floorplan-pick-source')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('floorplan-opening-review')),
        findsOneWidget,
      );
      expect(
        find.text('Aperturas detectadas que necesitan geometría'),
        findsOneWidget,
      );
      expect(find.text('P2 · Puerta · falta posición y ancho'), findsOneWidget);
      expect(find.textContaining('posición 50%'), findsNothing);
      expect(find.textContaining('ancho 15%'), findsNothing);
      expect(find.text('4 paredes · 1 aperturas por revisar'), findsOneWidget);
      expect(analyzer.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'incomplete AI opening stays reviewable but is not drawable geometry',
    (tester) async {
      final source = _FloorplanPhotoSource(
        await tester.runAsync(_testPng) ?? Uint8List(0),
      );
      final analyzer = _CountingFloorplanAnalyzer();
      final built = await _build(
        tester,
        traceSource: source,
        floorplanInterpreter: _IncompleteOpeningFloorplanInterpretationApi(),
      );
      tester.view.physicalSize = const Size(720, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: andeanTheme(),
          home: FloorplanTraceScreen(
            controller: built.controller,
            analyzer: analyzer,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('floorplan-pick-source')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('floorplan-opening-review')),
        findsOneWidget,
      );
      expect(find.text('P2 · Puerta · falta posición y ancho'), findsOneWidget);

      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('floorplan-trace-paint')),
      );
      final painter = paint.painter as dynamic;
      final openings = painter.openings as List<InterpretedOpeningProposal>;
      expect(openings, hasLength(1));

      final opening = openings.single;
      expect(opening.hasGeometry, isFalse);
      expect(opening.position, isNull);
      expect(opening.normalizedWidth, isNull);
      expect(opening.position, isNot(0.5));
      expect(opening.normalizedWidth, isNot(0.15));
      expect(built.controller.rooms, isEmpty);
    },
  );

  testWidgets('complete AI openings reach the floorplan review canvas', (
    tester,
  ) async {
    final source = _FloorplanPhotoSource(
      await tester.runAsync(_testPng) ?? Uint8List(0),
    );
    final analyzer = _CountingFloorplanAnalyzer();
    final built = await _build(
      tester,
      traceSource: source,
      floorplanInterpreter: _PentagonOpeningsFloorplanInterpretationApi(),
    );
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: FloorplanTraceScreen(
          controller: built.controller,
          analyzer: analyzer,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('floorplan-pick-source')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('5 paredes · 3 aperturas por revisar'), findsOneWidget);

    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('floorplan-trace-paint')),
    );
    final painter = paint.painter as dynamic;
    final openings = painter.openings as List<InterpretedOpeningProposal>;
    expect(openings, hasLength(3));
    expect(
      openings.where(
        (opening) => opening.type == FloorplanOpeningCandidateType.window,
      ),
      hasLength(2),
    );
    expect(
      openings.where(
        (opening) => opening.type == FloorplanOpeningCandidateType.door,
      ),
      hasLength(1),
    );

    final firstWindow = openings.firstWhere(
      (opening) =>
          opening.type == FloorplanOpeningCandidateType.window &&
          opening.edgeIndex == 0,
    );
    expect(firstWindow.position, 0.40);
    expect(firstWindow.normalizedWidth, 0.20);

    final door = openings.singleWhere(
      (opening) => opening.type == FloorplanOpeningCandidateType.door,
    );
    expect(door.edgeIndex, 3);
    expect(door.position, 0.50);
    expect(door.normalizedWidth, 0.22);
    expect(built.controller.rooms, isEmpty);
  });

  testWidgets('complete AI openings survive floorplan confirmation', (
    tester,
  ) async {
    final source = _FloorplanPhotoSource(
      await tester.runAsync(_testPng) ?? Uint8List(0),
    );
    final analyzer = _CountingFloorplanAnalyzer();
    final built = await _build(
      tester,
      traceSource: source,
      floorplanInterpreter: _PentagonOpeningsFloorplanInterpretationApi(),
    );

    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: FloorplanTraceScreen(
          controller: built.controller,
          analyzer: analyzer,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('floorplan-pick-source')));

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('5 paredes'), findsWidgets);

    final height = find.byKey(const ValueKey('trace-room-height'));
    await tester.scrollUntilVisible(
      height,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('floorplan-trace-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    await tester.enterText(height, '2,60');

    final save = find.byKey(const ValueKey('floorplan-trace-save'));
    expect(save.hitTestable(), findsOneWidget);

    await tester.tap(save);
    await tester.pumpAndSettle();

    final room = built.controller.rooms.single;

    expect(room.corners, hasLength(5));

    expect(
      room.openings,
      isEmpty,
      reason:
          'Las aperturas detectadas desde un plano 2D no deben convertirse '
          'todavía en RoomOpening sin completar los datos canónicos necesarios.',
    );

    final trace = built.controller.traceForRoom(room.id);
    expect(trace, isNotNull);

    expect(
      trace!.openings,
      hasLength(3),
      reason:
          'Las aperturas 2D detectadas por IA deben sobrevivir a la '
          'confirmación dentro de FloorplanTraceMetadata.',
    );

    expect(
      trace.openings.where(
        (opening) => opening.type == FloorplanTraceOpeningType.window,
      ),
      hasLength(2),
    );

    expect(
      trace.openings.where(
        (opening) => opening.type == FloorplanTraceOpeningType.door,
      ),
      hasLength(1),
    );

    final firstWindow = trace.openings.firstWhere(
      (opening) => opening.type == FloorplanTraceOpeningType.window,
    );
    expect(firstWindow.position, 0.40);
    expect(firstWindow.normalizedWidth, 0.20);

    final door = trace.openings.firstWhere(
      (opening) => opening.type == FloorplanTraceOpeningType.door,
    );
    expect(door.edgeIndex, 3);
    expect(door.position, 0.50);
    expect(door.normalizedWidth, 0.22);

    expect(analyzer.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('persisted AI openings survive floorplan reopen and resave', (
    tester,
  ) async {
    final source = _FloorplanPhotoSource(
      await tester.runAsync(_testPng) ?? Uint8List(0),
    );
    final analyzer = _CountingFloorplanAnalyzer();
    final built = await _build(
      tester,
      traceSource: source,
      floorplanInterpreter: _PentagonOpeningsFloorplanInterpretationApi(),
    );
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: FloorplanTraceScreen(
          controller: built.controller,
          analyzer: analyzer,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('floorplan-pick-source')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('5 paredes'), findsWidgets);
    final height = find.byKey(const ValueKey('trace-room-height'));
    await tester.scrollUntilVisible(
      height,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('floorplan-trace-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(height, '2,60');
    final save = find.byKey(const ValueKey('floorplan-trace-save'));
    expect(save.hitTestable(), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final room = built.controller.rooms.single;
    final initialTrace = built.controller.traceForRoom(room.id);
    expect(initialTrace, isNotNull);
    expect(initialTrace!.openings, hasLength(3));
    expect(room.openings, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        theme: andeanTheme(),
        home: FloorplanTraceScreen(
          controller: built.controller,
          roomId: room.id,
          analyzer: analyzer,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    final resave = find.byKey(const ValueKey('floorplan-trace-save'));
    await tester.scrollUntilVisible(
      resave,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('floorplan-trace-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(resave.hitTestable(), findsOneWidget);
    await tester.tap(resave);
    await tester.pumpAndSettle();

    final resavedTrace = built.controller.traceForRoom(room.id);
    expect(resavedTrace, isNotNull);
    expect(resavedTrace!.openings, hasLength(3));
    expect(
      resavedTrace.openings.where(
        (opening) => opening.type == FloorplanTraceOpeningType.window,
      ),
      hasLength(2),
    );
    expect(
      resavedTrace.openings.where(
        (opening) => opening.type == FloorplanTraceOpeningType.door,
      ),
      hasLength(1),
    );

    final firstWindow = resavedTrace.openings.firstWhere(
      (opening) =>
          opening.type == FloorplanTraceOpeningType.window &&
          opening.edgeIndex == 0,
    );
    expect(firstWindow.position, 0.40);
    expect(firstWindow.normalizedWidth, 0.20);

    final door = resavedTrace.openings.firstWhere(
      (opening) => opening.type == FloorplanTraceOpeningType.door,
    );
    expect(door.edgeIndex, 3);
    expect(door.position, 0.50);
    expect(door.normalizedWidth, 0.22);
    expect(built.controller.rooms.single.openings, isEmpty);
    expect(analyzer.calls, 0);
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
        measurements: const [
          ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.234),
          ReferenceMeasurement(edgeIndex: 1, referenceMeters: 3.25),
          ReferenceMeasurement(edgeIndex: 2, referenceMeters: 4.234),
          ReferenceMeasurement(edgeIndex: 3, referenceMeters: 3.25),
        ],
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
    expect(save.hitTestable(), findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final after = built.controller.rooms.single;
    expect(after.id, room.id);
    expect(after.name, 'Dormitorio plano');
    expect(after.height.value, 2.655);
    expect(after.openings, isEmpty);
    expect(after.acquisition.method, RoomAcquisitionMethod.floorplanTrace);
    expect(after.references.first.referenceMeters, 4.234);
    expect(built.controller.traceForRoom(room.id)!.referenceMeters, isNull);
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
    await tester.tap(find.text('Mover / zoom'));
    await tester.pump();
    final viewerFinder = find.byKey(
      const ValueKey('sketch-interactive-viewer'),
    );
    final viewer = tester.widget<InteractiveViewer>(viewerFinder);
    final transform = viewer.transformationController!;
    final center = tester.getCenter(viewerFinder);
    final first = await tester.startGesture(
      center + const Offset(-25, 0),
      pointer: 21,
    );
    final second = await tester.startGesture(
      center + const Offset(25, 0),
      pointer: 22,
    );
    await tester.pump();
    await first.moveTo(center + const Offset(-40, 0));
    await second.moveTo(center + const Offset(40, 0));
    await tester.pump();
    await first.moveTo(center + const Offset(-60, 0));
    await second.moveTo(center + const Offset(60, 0));
    await tester.pump();
    await first.up();
    await second.up();
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('sketch-undo')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Dibujar / editar'));
    await tester.pump();
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
    final undo = find.byKey(const ValueKey('sketch-undo'));
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pump();
    final close = find.byKey(const ValueKey('sketch-close'));
    await tester.ensureVisible(close);
    await tester.pumpAndSettle();
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text('Pared de referencia'), findsNothing);
    expect(find.byKey(const ValueKey('sketch-wall-0')), findsOneWidget);
    await tester.ensureVisible(canvas);
    final closedOrigin = tester.getTopLeft(canvas);
    await tester.tapAt(closedOrigin + const Offset(25, 110));
    await tester.pump();
    final remove = find.byKey(const ValueKey('sketch-remove'));
    expect(tester.widget<TextButton>(remove).onPressed, isNotNull);
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('sketch-wall-0')), '4,20');
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
    expect(find.text('Croquis manual con medidas por pared'), findsOneWidget);
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
    expect(find.text('Paredes'), findsOneWidget);
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
      'Paredes',
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
    expect(find.text('Paredes'), findsOneWidget);

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
    await tester.scrollUntilVisible(
      openings,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('room-editor-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
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
    expect(find.text('Paredes y tolerancia'), findsOneWidget);

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
        length: 4.00,
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
    await tester.scrollUntilVisible(
      add,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('room-editor-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(add);
    await tester.pumpAndSettle();
    final position = find.byKey(const ValueKey('opening-position-metres'));
    expect(tester.widget<TextField>(position).controller!.text, '2,00');
    final gesture = find.byKey(const ValueKey('opening-position-gesture'));
    final rect = tester.getRect(gesture);
    await tester.tapAt(Offset(rect.left + rect.width * 0.70, rect.center.dy));
    await tester.pump();
    expect(tester.widget<TextField>(position).controller!.text, '2,80');
    expect(find.text('Posición desde el inicio: 2,80 m'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('opening-confirm')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      built.controller.rooms.single.openings.single.position,
      closeTo(0.7, 0.01),
    );

    final openingTile = find.textContaining('Puerta 1');
    await tester.ensureVisible(openingTile);
    await tester.tap(openingTile);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(position).controller!.text, '2,80');
    await tester.enterText(position, '1,20');
    await tester.pump();
    expect(find.text('Posición desde el inicio: 1,20 m'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('opening-confirm')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      built.controller.rooms.single.openings.single.position,
      closeTo(0.3, 1e-9),
    );
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
      await tester.scrollUntilVisible(
        warning,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('room-editor-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(warning, findsOneWidget);
      expect(built.controller.rooms.single.openings.single.edgeIndex, 9);

      final tile = find.textContaining('Puerta 1');
      await tester.scrollUntilVisible(
        tile,
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('room-editor-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
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
      await tester.tap(find.textContaining('Pared 1 (').last);
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
      find.text('Pared 2: 3,00 m capturado → 3,15 m corregido'),
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
