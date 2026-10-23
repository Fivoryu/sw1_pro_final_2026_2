import 'package:captura_mobile/data/services/ar_capture_channel.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:captura_mobile/domain/spatial_capture_controller.dart';
import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
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
});

Future<_Built> _build(WidgetTester tester) async {
  final backend = FakeSceneBackend();
  final ar = FakeArCapture();
  final store = InMemoryCaptureDraftStore();
  final controller = await _newController(
    tester,
    backend: backend,
    ar: ar,
    store: store,
  );
  return (controller: controller, backend: backend, ar: ar);
}

Future<SpatialCaptureController> _newController(
  WidgetTester tester, {
  required FakeSceneBackend backend,
  required FakeArCapture ar,
  required InMemoryCaptureDraftStore store,
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

    await _tapAndSettle(tester, find.byKey(const ValueKey('edit-room-room-1')));
    expect(find.text('Lados'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-opening-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('reference-field-0')), findsNothing);
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
