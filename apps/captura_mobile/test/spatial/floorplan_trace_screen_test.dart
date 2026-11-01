import 'dart:math' as math;
import 'dart:typed_data';

import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:captura_mobile/ui/spatial/floorplan_trace_screen.dart';
import 'package:captura_mobile/ui/theme/andean_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/floorplan_trace_screen_test_support.dart';

void main() {
  Future<(FloorplanTraceHarness, String)> seedDraft(
    WidgetTester tester, {
    required FloorplanVisualDraft draft,
    List<FloorplanTraceOpening> openings = const [],
    List<ReferenceMeasurement> measurements = const [],
  }) async {
    final bytes = await tester.runAsync(floorplanTraceTestPng);
    final harness = await buildFloorplanTraceHarness(
      tester,
      traceSource: FloorplanTracePhotoSource(bytes!),
    );
    final source = await harness.controller.pickFloorplanSource();
    expect(source, isNotNull);
    expect(
      await harness.controller.saveFloorplanTrace(
        name: 'Prueba visual',
        sourceId: source!.sourceId,
        contentType: source.contentType,
        imageWidth: 100,
        imageHeight: 80,
        normalizedTrace: draft.contourForRoom('temporary')!,
        visualDraft: draft,
        openings: openings,
        measurements: measurements,
        height: 2.6,
      ),
      isNull,
    );
    // A visual draft may project several canonical rooms. Select the region
    // being edited instead of assuming that only one room was created.
    expect(harness.controller.rooms, hasLength(draft.rooms.length));
    if (draft.rooms.length == 1) {
      return (harness, harness.controller.rooms.single.id);
    }
    final visualRoomId = draft.room('temporary')?.id ?? draft.rooms.first.id;
    final projected = harness.controller.rooms.singleWhere(
      (room) =>
          harness.controller.traceForRoom(room.id)?.visualRoomId == visualRoomId,
    );
    return (harness, projected.id);
  }

  void sizeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpEditor(
    WidgetTester tester,
    FloorplanTraceHarness harness,
    String roomId, {
    required bool pushed,
  }) async {
    final screen = FloorplanTraceScreen(
      controller: harness.controller,
      roomId: roomId,
    );
    if (!pushed) {
      await tester.pumpWidget(MaterialApp(theme: andeanTheme(), home: screen));
    } else {
      await tester.pumpWidget(
        MaterialApp(
          theme: andeanTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  key: const ValueKey('open-floorplan-editor'),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => screen)),
                  child: const Text('Abrir editor'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-floorplan-editor')));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Herramientas de edición'));
    await tester.pumpAndSettle();
  }

  Future<(FloorplanTraceHarness, String)> openDraft(
    WidgetTester tester, {
    required FloorplanVisualDraft draft,
    List<FloorplanTraceOpening> openings = const [],
    List<ReferenceMeasurement> measurements = const [],
  }) async {
    final seeded = await seedDraft(
      tester,
      draft: draft,
      openings: openings,
      measurements: measurements,
    );
    sizeView(tester);
    await pumpEditor(tester, seeded.$1, seeded.$2, pushed: false);
    return seeded;
  }

  Future<(FloorplanTraceHarness, String)> openPushedDraft(
    WidgetTester tester, {
    required FloorplanVisualDraft draft,
    List<FloorplanTraceOpening> openings = const [],
    List<ReferenceMeasurement> measurements = const [],
  }) async {
    final seeded = await seedDraft(
      tester,
      draft: draft,
      openings: openings,
      measurements: measurements,
    );
    sizeView(tester);
    await pumpEditor(tester, seeded.$1, seeded.$2, pushed: true);
    return seeded;
  }

  Future<void> tapModelPoint(WidgetTester tester, double x, double z) async {
    final canvas = find.byKey(const ValueKey('floorplan-trace-canvas'));
    await tester.ensureVisible(canvas);
    await tester.pumpAndSettle();
    final rect = tester.getRect(canvas);
    final shownWidth = rect.height * 100 / 80;
    final left = rect.left + (rect.width - shownWidth) / 2;
    await tester.tapAt(
      Offset(left + x * shownWidth, rect.top + z * rect.height),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dragModelPoint(
    WidgetTester tester, {
    required double fromX,
    required double fromZ,
    required double toX,
    required double toZ,
  }) async {
    final canvas = find.byKey(const ValueKey('floorplan-trace-canvas'));
    await tester.ensureVisible(canvas);
    await tester.pumpAndSettle();
    final rect = tester.getRect(canvas);
    final shownWidth = rect.height * 100 / 80;
    final left = rect.left + (rect.width - shownWidth) / 2;
    Offset point(double x, double z) =>
        Offset(left + x * shownWidth, rect.top + z * rect.height);
    final start = point(fromX, fromZ);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(3, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(point(toX, toZ));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> chooseWallTool(WidgetTester tester) async {
    final control = find.byKey(const ValueKey('floorplan-tool-wall'));
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  Future<void> choosePerimeterTool(WidgetTester tester) async {
    final control = find.byKey(const ValueKey('floorplan-tool-contour'));
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  Future<void> chooseVertexTool(WidgetTester tester) async {
    final control = find.byKey(const ValueKey('floorplan-tool-vertex'));
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  List<VisualWallSegment> paintedInternalWalls(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('floorplan-trace-paint')),
    );
    final painter = paint.painter as dynamic;
    return List<VisualWallSegment>.from(
      painter.internalWalls as List<VisualWallSegment>,
    );
  }

  List<VisualWallSegment> paintedWalls(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('floorplan-trace-paint')),
    );
    final painter = paint.painter as dynamic;
    return List<VisualWallSegment>.from(
      painter.walls as List<VisualWallSegment>,
    );
  }

  List<VisualOpeningDraft> paintedOpenings(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('floorplan-trace-paint')),
    );
    final painter = paint.painter as dynamic;
    return List<VisualOpeningDraft>.from(
      painter.visualOpenings as List<VisualOpeningDraft>,
    );
  }

  String? paintedSelectedWallId(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('floorplan-trace-paint')),
    );
    final painter = paint.painter as dynamic;
    return painter.selectedWallId as String?;
  }

  int? paintedSelectedVertex(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('floorplan-trace-paint')),
    );
    final painter = paint.painter as dynamic;
    return painter.selected as int?;
  }

  FloorplanVisualDraft polygonDraft(int wallCount) {
    final points = [
      for (var index = 0; index < wallCount; index++)
        FloorPoint(
          .5 + .32 * math.cos(-math.pi / 2 + index * 2 * math.pi / wallCount),
          .5 + .32 * math.sin(-math.pi / 2 + index * 2 * math.pi / wallCount),
        ),
    ];
    final wallIds = [for (var index = 0; index < wallCount; index++) 'w$index'];
    return FloorplanVisualDraft(
      walls: [
        for (var index = 0; index < wallCount; index++)
          VisualWallSegment(
            id: wallIds[index],
            start: points[index],
            end: points[(index + 1) % wallCount],
            roomIds: const ['temporary'],
          ),
      ],
      rooms: [VisualRoomRegion(id: 'temporary', wallIds: wallIds)],
    );
  }

  List<FloorPoint> paintedPerimeter(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('floorplan-trace-paint')),
    );
    final painter = paint.painter as dynamic;
    return List<FloorPoint>.from(painter.points as List<FloorPoint>);
  }

  int paintedRoomCount(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('floorplan-trace-paint')),
    );
    final painter = paint.painter as dynamic;
    return (painter.rooms as List<Object?>).length;
  }

  Future<void> tapControl(WidgetTester tester, Key key) async {
    final control = find.byKey(key);
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  const rectangle = FloorplanVisualDraft(
    walls: [
      VisualWallSegment(
        id: 'a',
        start: FloorPoint(.2, .2),
        end: FloorPoint(.8, .2),
        roomIds: ['temporary'],
      ),
      VisualWallSegment(
        id: 'b',
        start: FloorPoint(.8, .2),
        end: FloorPoint(.8, .8),
        roomIds: ['temporary'],
      ),
      VisualWallSegment(
        id: 'c',
        start: FloorPoint(.8, .8),
        end: FloorPoint(.2, .8),
        roomIds: ['temporary'],
      ),
      VisualWallSegment(
        id: 'd',
        start: FloorPoint(.2, .8),
        end: FloorPoint(.2, .2),
        roomIds: ['temporary'],
      ),
    ],
    rooms: [
      VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd']),
    ],
  );

  // Its 60 x 45 pixel perimeter is deliberately proportional to the 4 x 3
  // authoritative lengths used by the persistence regression below.
  const metricRectangle = FloorplanVisualDraft(
    walls: [
      VisualWallSegment(
        id: 'a',
        start: FloorPoint(.2, .2),
        end: FloorPoint(.8, .2),
        roomIds: ['temporary'],
      ),
      VisualWallSegment(
        id: 'b',
        start: FloorPoint(.8, .2),
        end: FloorPoint(.8, .7625),
        roomIds: ['temporary'],
      ),
      VisualWallSegment(
        id: 'c',
        start: FloorPoint(.8, .7625),
        end: FloorPoint(.2, .7625),
        roomIds: ['temporary'],
      ),
      VisualWallSegment(
        id: 'd',
        start: FloorPoint(.2, .7625),
        end: FloorPoint(.2, .2),
        roomIds: ['temporary'],
      ),
    ],
    rooms: [
      VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd']),
    ],
  );

  testWidgets(
    'split, undo and redo use the real trace controls and stable IDs',
    (tester) async {
      await openDraft(tester, draft: rectangle);
      await choosePerimeterTool(tester);
      await tapModelPoint(tester, .5, .2);
      await tapControl(tester, const ValueKey('trace-split-wall'));
      expect(find.text('Tocá para dividir'), findsOneWidget);
      await tapModelPoint(tester, .5, .2);
      expect(find.textContaining('punto interior'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('trace-undo')))
            .onPressed,
        isNotNull,
      );

      await tapControl(tester, const ValueKey('trace-undo'));
      await tapControl(tester, const ValueKey('trace-redo'));
      expect(find.byKey(const ValueKey('wall-chip-4')), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('wall-chip-0')))
            .selected,
        isTrue,
      );
    },
  );

  testWidgets('vertex tool splits a wall and undo restores the topology', (
    tester,
  ) async {
    await openDraft(tester, draft: rectangle);
    await chooseVertexTool(tester);
    await tapModelPoint(tester, .5, .2);

    expect(find.byKey(const ValueKey('wall-chip-4')), findsOneWidget);
    expect(paintedPerimeter(tester), contains(const FloorPoint(.5, .2)));
    await tapControl(tester, const ValueKey('trace-undo'));
    expect(find.byKey(const ValueKey('wall-chip-4')), findsNothing);
    expect(paintedPerimeter(tester), isNot(contains(const FloorPoint(.5, .2))));
  });

  testWidgets('evidence-associated shared vertex can be dragged and undone', (
    tester,
  ) async {
    final draft = rectangle.copyWith(
      openings: const [
        VisualOpeningDraft(
          id: 'door-a',
          type: VisualOpeningType.door,
          wallId: 'a',
          position: .5,
          normalizedWidth: .2,
        ),
      ],
      measurements: const [
        VisualWallMeasurementEvidence(
          id: 'length-a',
          wallId: 'a',
          meters: 4,
          provenance: 'ai_detected',
          requiresReview: true,
        ),
      ],
    );
    await openDraft(tester, draft: draft);

    await dragModelPoint(tester, fromX: .8, fromZ: .2, toX: .72, toZ: .28);
    expect(find.textContaining('evidencia asociada'), findsNothing);
    await tapControl(tester, const ValueKey('trace-undo'));
    await tapControl(tester, const ValueKey('trace-redo'));
    expect(find.byKey(const ValueKey('trace-undo')), findsOneWidget);
  });

  testWidgets('wall tool creates two regions joined by one partition', (
    tester,
  ) async {
    await openDraft(tester, draft: rectangle);
    await chooseWallTool(tester);

    await tapModelPoint(tester, .2, .2);
    expect(find.byKey(const ValueKey('trace-cancel-wall')), findsOneWidget);
    await tapModelPoint(tester, .8, .7625);
    expect(paintedRoomCount(tester), 2);
    final physicalWallIds = paintedWalls(
      tester,
    ).map((wall) => wall.id).toList(growable: false);
    expect(physicalWallIds.toSet(), hasLength(physicalWallIds.length));
    expect([
      ...paintedPerimeter(tester),
      for (final wall in paintedInternalWalls(tester)) ...[
        wall.start,
        wall.end,
      ],
    ], contains(const FloorPoint(.8, .7625)));

    await tapControl(tester, const ValueKey('trace-undo'));
    expect(paintedInternalWalls(tester), isEmpty);
    expect(paintedRoomCount(tester), 0);
    await tapControl(tester, const ValueKey('trace-redo'));
    expect(paintedRoomCount(tester), 2);
    expect(
      paintedWalls(tester).map((wall) => wall.id),
      physicalWallIds,
      reason: 'La numeraciÃ³n P sigue el orden estable de paredes fÃ­sicas.',
    );
    expect([
      ...paintedPerimeter(tester),
      for (final wall in paintedInternalWalls(tester)) ...[
        wall.start,
        wall.end,
      ],
    ], contains(const FloorPoint(.8, .7625)));
  });

  testWidgets('crossing wall creates one junction and undoes atomically', (
    tester,
  ) async {
    await openDraft(tester, draft: rectangle);
    await chooseWallTool(tester);
    await tapModelPoint(tester, .5, .2);
    await tapModelPoint(tester, .5, .8);
    final afterFirstWall = paintedWalls(
      tester,
    ).map((wall) => wall.id).toList(growable: false);
    expect(paintedRoomCount(tester), 2);

    await chooseWallTool(tester);
    // Both touches are slightly outside the visible perimeter and must snap
    // to the closest valid wall projection within the mobile tolerance.
    await tapModelPoint(tester, .18, .5);
    await tapModelPoint(tester, .82, .5);
    expect(paintedRoomCount(tester), 4);
    expect(
      paintedWalls(tester).where(
        (wall) =>
            wall.start == const FloorPoint(.5, .5) ||
            wall.end == const FloorPoint(.5, .5),
      ),
      hasLength(4),
    );

    await tapControl(tester, const ValueKey('trace-undo'));
    expect(paintedRoomCount(tester), 2);
    expect(
      paintedWalls(tester).map((wall) => wall.id),
      afterFirstWall,
      reason: 'Una sola desacciÃ³n revierte toda la pared cruzada.',
    );
  });

  testWidgets('dragging a degree-three junction moves only incident walls', (
    tester,
  ) async {
    final partitioned = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle,
      roomId: 'temporary',
      start: const FloorPoint(.5, .2),
      end: const FloorPoint(.5, .8),
    ).draft!;
    await openDraft(tester, draft: partitioned);
    const original = FloorPoint(.5, .2);
    const replacement = FloorPoint(.55, .3);
    final before = paintedWalls(tester);
    final incidentIds = {
      for (final wall in before)
        if (wall.start == original || wall.end == original) wall.id,
    };
    final unrelated = {
      for (final wall in before)
        if (!incidentIds.contains(wall.id)) wall.id: wall.toJson(),
    };
    expect(incidentIds, hasLength(3));

    await dragModelPoint(
      tester,
      fromX: original.x,
      fromZ: original.z,
      toX: replacement.x,
      toZ: replacement.z,
    );

    final after = paintedWalls(tester);
    for (final wallId in incidentIds) {
      final wall = after.singleWhere((wall) => wall.id == wallId);
      expect(wall.start == replacement || wall.end == replacement, isTrue);
    }
    for (final entry in unrelated.entries) {
      expect(
        after.singleWhere((wall) => wall.id == entry.key).toJson(),
        entry.value,
      );
    }
    expect(paintedRoomCount(tester), 2);
  });

  testWidgets('merge control keeps the traversal-surviving ID', (tester) async {
    const draft = FloorplanVisualDraft(
      walls: [
        VisualWallSegment(
          id: 'a',
          start: FloorPoint(.2, .2),
          end: FloorPoint(.5, .2),
          roomIds: ['temporary'],
        ),
        VisualWallSegment(
          id: 'b',
          start: FloorPoint(.5, .2),
          end: FloorPoint(.8, .2),
          roomIds: ['temporary'],
        ),
        VisualWallSegment(
          id: 'c',
          start: FloorPoint(.8, .2),
          end: FloorPoint(.8, .8),
          roomIds: ['temporary'],
        ),
        VisualWallSegment(
          id: 'd',
          start: FloorPoint(.8, .8),
          end: FloorPoint(.2, .8),
          roomIds: ['temporary'],
        ),
        VisualWallSegment(
          id: 'e',
          start: FloorPoint(.2, .8),
          end: FloorPoint(.2, .2),
          roomIds: ['temporary'],
        ),
      ],
      rooms: [
        VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd', 'e']),
      ],
    );
    await openDraft(tester, draft: draft);
    await tapModelPoint(tester, .5, .2);
    await tapControl(tester, const ValueKey('trace-merge-wall'));
    expect(find.byKey(const ValueKey('wall-chip-4')), findsNothing);
    expect(find.byKey(const ValueKey('wall-chip-3')), findsOneWidget);
  });

  testWidgets('remove vertex dissolves its topological neighbors and undoes', (
    tester,
  ) async {
    const draft = FloorplanVisualDraft(
      walls: [
        VisualWallSegment(
          id: 'a',
          start: FloorPoint(.2, .2),
          end: FloorPoint(.5, .2),
          roomIds: ['temporary'],
        ),
        VisualWallSegment(
          id: 'b',
          start: FloorPoint(.5, .2),
          end: FloorPoint(.8, .2),
          roomIds: ['temporary'],
        ),
        VisualWallSegment(
          id: 'c',
          start: FloorPoint(.8, .2),
          end: FloorPoint(.8, .8),
          roomIds: ['temporary'],
        ),
        VisualWallSegment(
          id: 'd',
          start: FloorPoint(.8, .8),
          end: FloorPoint(.2, .8),
          roomIds: ['temporary'],
        ),
        VisualWallSegment(
          id: 'e',
          start: FloorPoint(.2, .8),
          end: FloorPoint(.2, .2),
          roomIds: ['temporary'],
        ),
      ],
      rooms: [
        VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd', 'e']),
      ],
    );
    await openDraft(tester, draft: draft);
    await tapModelPoint(tester, .5, .2);
    await tapControl(tester, const ValueKey('trace-remove'));

    expect(paintedPerimeter(tester), const [
      FloorPoint(.2, .2),
      FloorPoint(.8, .2),
      FloorPoint(.8, .8),
      FloorPoint(.2, .8),
    ]);
    expect(find.byKey(const ValueKey('wall-chip-4')), findsNothing);

    await tapControl(tester, const ValueKey('trace-undo'));
    expect(paintedPerimeter(tester), hasLength(5));
    expect(paintedPerimeter(tester)[1], const FloorPoint(.5, .2));
  });

  testWidgets(
    'pending measurement text blocks merge without losing either value',
    (tester) async {
      const draft = FloorplanVisualDraft(
        walls: [
          VisualWallSegment(
            id: 'a',
            start: FloorPoint(.2, .2),
            end: FloorPoint(.5, .2),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'b',
            start: FloorPoint(.5, .2),
            end: FloorPoint(.8, .2),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'c',
            start: FloorPoint(.8, .2),
            end: FloorPoint(.8, .8),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'd',
            start: FloorPoint(.8, .8),
            end: FloorPoint(.2, .8),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'e',
            start: FloorPoint(.2, .8),
            end: FloorPoint(.2, .2),
            roomIds: ['temporary'],
          ),
        ],
        rooms: [
          VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd', 'e']),
        ],
      );
      await openDraft(tester, draft: draft);
      await tapControl(tester, const ValueKey('wall-chip-0'));
      tester
              .widget<TextField>(find.byKey(const ValueKey('trace-wall-0')))
              .controller!
              .text =
          '4.1';
      await tapControl(tester, const ValueKey('wall-chip-1'));
      tester
              .widget<TextField>(find.byKey(const ValueKey('trace-wall-1')))
              .controller!
              .text =
          '3.2';
      await tapModelPoint(tester, .5, .2);
      await tapControl(tester, const ValueKey('trace-merge-wall'));
      expect(find.byKey(const ValueKey('wall-chip-4')), findsOneWidget);
      await tapControl(tester, const ValueKey('wall-chip-0'));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('trace-wall-0')))
            .controller!
            .text,
        '4.1',
      );
      await tapControl(tester, const ValueKey('wall-chip-1'));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('trace-wall-1')))
            .controller!
            .text,
        '3.2',
      );
    },
  );

  testWidgets('opening evidence alone rejects a split through the opening', (
    tester,
  ) async {
    final (harness, roomId) = await openDraft(
      tester,
      draft: rectangle,
      openings: const [
        FloorplanTraceOpening(
          edgeIndex: 0,
          type: FloorplanTraceOpeningType.window,
          position: .5,
          normalizedWidth: .2,
        ),
      ],
    );
    await choosePerimeterTool(tester);
    await tapModelPoint(tester, .5, .2);
    await tapControl(tester, const ValueKey('trace-split-wall'));
    await tapModelPoint(tester, .5, .2);
    expect(find.textContaining('atraviesa una abertura'), findsOneWidget);
    expect(find.textContaining('medidas asociadas'), findsNothing);
    expect(find.byKey(const ValueKey('wall-chip-4')), findsNothing);
    final stored = harness.controller.traceForRoom(roomId)!;
    expect(stored.openings, hasLength(1));
    expect(stored.visualDraft!.openings.single.position, .5);
    expect(stored.visualDraft!.measurements, isEmpty);
  });

  testWidgets('split away from an opening keeps evidence and undo history', (
    tester,
  ) async {
    final (harness, roomId) = await openDraft(
      tester,
      draft: rectangle,
      openings: const [
        FloorplanTraceOpening(
          edgeIndex: 0,
          type: FloorplanTraceOpeningType.window,
          position: .2,
          normalizedWidth: .1,
          manuallyPlaced: true,
          confidence: .9,
        ),
      ],
    );
    final originalOpeningId = harness.controller
        .traceForRoom(roomId)!
        .visualDraft!
        .openings
        .single
        .id;

    await choosePerimeterTool(tester);
    await tapModelPoint(tester, .5, .2);
    await tapControl(tester, const ValueKey('trace-split-wall'));
    await tapModelPoint(tester, .7, .2);
    expect(find.textContaining('atraviesa una abertura'), findsNothing);
    expect(find.byKey(const ValueKey('wall-chip-4')), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('trace-undo')))
          .onPressed,
      isNotNull,
    );

    await tapControl(tester, const ValueKey('trace-undo'));
    expect(find.byKey(const ValueKey('wall-chip-4')), findsNothing);
    await tapControl(tester, const ValueKey('trace-redo'));
    expect(find.byKey(const ValueKey('wall-chip-4')), findsOneWidget);

    // The remapped opening is still selectable on the surviving segment with
    // its original identity.
    await tapControl(tester, const ValueKey('floorplan-tool-select'));
    await tapModelPoint(tester, .32, .2);
    expect(find.byKey(const ValueKey('trace-remove-opening')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('selected-opening-$originalOpeningId')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('floorplan-trace-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.byKey(ValueKey('selected-opening-$originalOpeningId')),
      findsOneWidget,
    );
  });

  testWidgets('measurement evidence alone rejects the split from the UI', (
    tester,
  ) async {
    final (harness, roomId) = await openDraft(
      tester,
      draft: rectangle,
      measurements: const [
        ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4),
      ],
    );
    await choosePerimeterTool(tester);
    await tapModelPoint(tester, .5, .2);
    await tapControl(tester, const ValueKey('trace-split-wall'));
    await tapModelPoint(tester, .5, .2);
    expect(find.textContaining('medidas asociadas'), findsOneWidget);
    expect(find.textContaining('aberturas asociadas'), findsNothing);
    expect(find.byKey(const ValueKey('wall-chip-4')), findsNothing);
    final stored = harness.controller.traceForRoom(roomId)!;
    expect(stored.openings, isEmpty);
    expect(stored.visualDraft!.measurements, hasLength(1));
  });

  testWidgets('placed openings are persisted through the document', (
    tester,
  ) async {
    final (harness, roomId) = await openPushedDraft(
      tester,
      draft: rectangle,
      measurements: const [
        ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4),
      ],
    );
    await tapModelPoint(tester, .5, .2);
    await tapControl(tester, const ValueKey('floorplan-tool-door'));
    await tapModelPoint(tester, .5, .2);
    await tapControl(tester, const ValueKey('floorplan-trace-save'));

    final saved = harness.controller.traceForRoom(roomId)!;
    expect(saved.openings, hasLength(1));
    expect(saved.openings.single.type, FloorplanTraceOpeningType.door);
    expect(saved.openings.single.edgeIndex, 0);
    expect(saved.openings.single.manuallyPlaced, isTrue);
    final document = saved.visualDraft!;
    expect(document.openings, hasLength(1));
    expect(document.openings.single.wallId, isNotNull);
    expect(document.openings.single.manuallyPlaced, isTrue);

    // Reopening restores the same opening from the document, and removing it
    // is also persisted through the document.
    await tapControl(tester, const ValueKey('open-floorplan-editor'));
    await tapModelPoint(tester, .5, .2);
    expect(find.byKey(const ValueKey('trace-remove-opening')), findsOneWidget);
    await tapControl(tester, const ValueKey('trace-remove-opening'));
    await tapControl(tester, const ValueKey('floorplan-trace-save'));

    final afterRemoval = harness.controller.traceForRoom(roomId)!;
    expect(afterRemoval.openings, isEmpty);
    expect(afterRemoval.visualDraft!.openings, isEmpty);
  });

  testWidgets('door tool snaps to closest walls and stays active', (
    tester,
  ) async {
    await openDraft(tester, draft: rectangle);
    await tapControl(tester, const ValueKey('wall-chip-2'));
    await tapControl(tester, const ValueKey('floorplan-tool-door'));

    // Roughly 13 px below the top wall: no wall preselection or exact hit.
    await tapModelPoint(tester, .5, .247);
    expect(paintedOpenings(tester), hasLength(1));
    final firstOpening = paintedOpenings(tester).single;
    expect(firstOpening.wallId, 'a');
    expect(
      find.byKey(ValueKey('selected-opening-${firstOpening.id}')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('floorplan-tool-door')))
          .selected,
      isTrue,
    );

    // The same active tool can place another door near another physical wall.
    await tapModelPoint(tester, .77, .55);
    final openings = paintedOpenings(tester);
    expect(openings, hasLength(2));
    expect(openings.last.wallId, 'b');
    expect(find.text('P2 de 4'), findsOneWidget);
  });

  testWidgets(
    'adaptive opening width uses free interval and rejects occupied tap',
    (tester) async {
      final draft = rectangle.copyWith(
        openings: const [
          VisualOpeningDraft(
            id: 'existing-door',
            type: VisualOpeningType.door,
            wallId: 'a',
            position: .7,
            normalizedWidth: .4,
            manuallyPlaced: true,
          ),
        ],
      );
      await openDraft(tester, draft: draft);
      await tapControl(tester, const ValueKey('floorplan-tool-window'));

      await tapModelPoint(tester, .79, .2);
      final openings = paintedOpenings(tester);
      expect(openings, hasLength(2));
      expect(openings.last.type, VisualOpeningType.window);
      expect(openings.last.wallId, 'a');
      expect(openings.last.normalizedWidth, closeTo(.1, 1e-6));
      expect(openings.last.position, closeTo(.95, 1e-6));

      await tapModelPoint(tester, .62, .2);
      expect(paintedOpenings(tester), hasLength(2));
      expect(
        find.text('No hay espacio libre en esta parte de la pared.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('window can be placed once on a shared manual partition', (
    tester,
  ) async {
    final partitioned = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle,
      roomId: 'temporary',
      start: const FloorPoint(.2, .5),
      end: const FloorPoint(.8, .5),
    ).draft!;
    final sharedWall = partitioned.walls.singleWhere(
      (wall) => wall.roomIds.length == 2,
    );
    await openDraft(tester, draft: partitioned);
    await tapControl(tester, const ValueKey('floorplan-tool-window'));
    await tapModelPoint(tester, .5, .5);

    final opening = paintedOpenings(tester).single;
    expect(opening.type, VisualOpeningType.window);
    expect(opening.wallId, sharedWall.id);
    expect(opening.manuallyPlaced, isTrue);
    expect(
      paintedOpenings(tester).where((value) => value.id == opening.id),
      hasLength(1),
    );
  });

  testWidgets('selected opening can move to another physical wall', (
    tester,
  ) async {
    final draft = rectangle.copyWith(
      openings: const [
        VisualOpeningDraft(
          id: 'manual-door',
          type: VisualOpeningType.door,
          wallId: 'a',
          position: .5,
          normalizedWidth: .2,
          manuallyPlaced: true,
        ),
      ],
    );
    await openDraft(tester, draft: draft);
    await tapModelPoint(tester, .5, .2);
    await dragModelPoint(tester, fromX: .5, fromZ: .2, toX: .8, toZ: .5);

    final moved = paintedOpenings(tester).single;
    expect(moved.id, 'manual-door');
    expect(moved.wallId, 'b');
    expect(moved.position, closeTo(.5, 1e-6));
    final destinationIndex = paintedWalls(
      tester,
    ).indexWhere((wall) => wall.id == moved.wallId);
    expect(destinationIndex, greaterThanOrEqualTo(0));
    expect(
      find.byKey(const ValueKey('selected-opening-wall-position')),
      findsOneWidget,
    );
    expect(
      find.text('P${destinationIndex + 1} de ${paintedWalls(tester).length}'),
      findsOneWidget,
    );

    await tapControl(tester, const ValueKey('trace-undo'));
    expect(paintedOpenings(tester).single.wallId, 'a');
    await tapControl(tester, const ValueKey('trace-redo'));
    expect(paintedOpenings(tester).single.wallId, 'b');
  });

  testWidgets('drag over an unselected opening does not move it', (
    tester,
  ) async {
    final draft = rectangle.copyWith(
      openings: const [
        VisualOpeningDraft(
          id: 'unselected-door',
          type: VisualOpeningType.door,
          wallId: 'a',
          position: .5,
          normalizedWidth: .2,
          manuallyPlaced: true,
        ),
      ],
    );
    await openDraft(tester, draft: draft);

    await dragModelPoint(tester, fromX: .5, fromZ: .2, toX: .5, toZ: .5);

    final opening = paintedOpenings(tester).single;
    expect(opening.wallId, 'a');
    expect(opening.position, .5);
  });

  testWidgets('opening fields expose estimates without confirming them', (
    tester,
  ) async {
    final draft = metricRectangle.copyWith(
      openings: const [
        VisualOpeningDraft(
          id: 'estimated-door',
          type: VisualOpeningType.door,
          wallId: 'a',
          position: .5,
          normalizedWidth: .2,
          manuallyPlaced: true,
        ),
      ],
      measurements: const [
        VisualWallMeasurementEvidence(id: 'a:length', wallId: 'a', meters: 4),
      ],
    );
    await openDraft(tester, draft: draft);
    await tapModelPoint(tester, .5, .2);

    final width = tester.widget<TextField>(
      find.byKey(const ValueKey('trace-opening-width-estimated-door')),
    );
    final offset = tester.widget<TextField>(
      find.byKey(const ValueKey('trace-opening-offset-estimated-door')),
    );
    expect(width.controller!.text, isEmpty);
    expect(offset.controller!.text, isEmpty);
    expect(find.text('0,80 m · Estimado según P1'), findsOneWidget);
    expect(find.text('1,60 m · Estimado según P1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('opening-measurement-status-estimated-door')),
      findsOneWidget,
    );
    expect(paintedOpenings(tester).single.widthM, isNull);
    expect(paintedOpenings(tester).single.offsetFromWallStartM, isNull);
  });

  testWidgets('visualization toggles hide mini map without losing selector', (
    tester,
  ) async {
    await openDraft(tester, draft: rectangle);
    expect(
      find.byKey(const ValueKey('floorplan-persistent-review')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('floorplan-wall-selector')),
      findsOneWidget,
    );

    await tapControl(tester, const ValueKey('floorplan-visualization'));
    final cleanView = find.byKey(const ValueKey('floorplan-clean-view'));
    expect(cleanView, findsOneWidget);
    expect(
      tester.getSize(cleanView).width,
      lessThan(tester.getSize(find.byType(BottomSheet)).width),
    );
    await tapControl(tester, const ValueKey('visualization-minimap'));
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('floorplan-persistent-review')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('floorplan-wall-selector')),
      findsOneWidget,
    );
    await tapControl(tester, const ValueKey('wall-chip-1'));
    expect(paintedSelectedWallId(tester), 'b');
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigate tap selects a wall without mutating geometry', (
    tester,
  ) async {
    await openDraft(tester, draft: rectangle);
    final before = [
      for (final wall in paintedWalls(tester)) (wall.id, wall.start, wall.end),
    ];

    await tester.ensureVisible(find.text('Mover / zoom'));
    await tester.tap(find.text('Mover / zoom'));
    await tester.pumpAndSettle();
    await tapModelPoint(tester, .8, .5);

    expect(paintedSelectedWallId(tester), 'b');
    expect([
      for (final wall in paintedWalls(tester)) (wall.id, wall.start, wall.end),
    ], before);
  });

  testWidgets('direct vertex capture wins over an incident wall', (
    tester,
  ) async {
    await openDraft(tester, draft: rectangle);

    await tapModelPoint(tester, .2, .2);
    expect(paintedSelectedVertex(tester), 0);
    expect(paintedSelectedWallId(tester), isNull);

    // Ten screen pixels along the wall remain inside the direct-capture zone.
    await tapModelPoint(tester, .2 + 10 / 350, .2);
    expect(paintedSelectedVertex(tester), 0);
    expect(paintedSelectedWallId(tester), isNull);

    // Outside that zone, the geometrically closer wall remains selectable.
    await tapModelPoint(tester, .2 + 24 / 350, .2);
    expect(paintedSelectedVertex(tester), isNull);
    expect(paintedSelectedWallId(tester), 'a');
  });

  testWidgets(
    'junction vertex selection is canonical in navigate and vertex tools',
    (tester) async {
      final partitioned = FloorplanVisualDraftEditor.addInternalWall(
        draft: rectangle,
        roomId: 'temporary',
        start: const FloorPoint(.2, .5),
        end: const FloorPoint(.8, .5),
      ).draft!;
      await openDraft(tester, draft: partitioned);
      final originalWalls = paintedWalls(tester);

      await tapControl(tester, const ValueKey('trace-mode-navigate'));
      await tapModelPoint(tester, .2, .5);
      expect(paintedSelectedVertex(tester), isNotNull);
      expect(paintedSelectedWallId(tester), isNull);
      expect(paintedWalls(tester), originalWalls);

      await tapControl(tester, const ValueKey('trace-mode-edit'));
      await tapControl(tester, const ValueKey('floorplan-tool-vertex'));
      await tapModelPoint(tester, .2, .5);
      expect(paintedSelectedVertex(tester), isNotNull);
      expect(paintedSelectedWallId(tester), isNull);
      expect(paintedWalls(tester), originalWalls);
    },
  );

  testWidgets('opening remains selectable outside strong vertex capture zone', (
    tester,
  ) async {
    final draft = rectangle.copyWith(
      openings: const [
        VisualOpeningDraft(
          id: 'near-corner-door',
          type: VisualOpeningType.door,
          wallId: 'a',
          position: 1 / 6,
          normalizedWidth: .08,
        ),
      ],
    );
    await openDraft(tester, draft: draft);

    await tapModelPoint(tester, .3, .2);
    expect(
      find.byKey(const ValueKey('selected-opening-near-corner-door')),
      findsOneWidget,
    );
    expect(paintedSelectedVertex(tester), isNull);
    expect(paintedSelectedWallId(tester), 'a');
  });

  testWidgets('inconsistent wall lengths report measurement error', (
    tester,
  ) async {
    await openDraft(tester, draft: rectangle);
    for (final (index, value) in ['10', '1', '1', '1'].indexed) {
      await tapControl(tester, ValueKey('wall-chip-$index'));
      await tester.enterText(find.byKey(ValueKey('trace-wall-$index')), value);
      await tester.pump();
    }

    await tapControl(tester, const ValueKey('floorplan-trace-save'));
    expect(
      find.textContaining('Las medidas ingresadas no son compatibles'),
      findsOneWidget,
    );
    expect(
      find.text('El contorno se cruza o no forma un ambiente válido.'),
      findsNothing,
    );
  });

  testWidgets('undo and redo restore the complete document state', (
    tester,
  ) async {
    await openDraft(
      tester,
      draft: rectangle,
      measurements: const [
        ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4),
      ],
    );
    await tapModelPoint(tester, .5, .2);
    await tapControl(tester, const ValueKey('floorplan-tool-door'));
    await tapModelPoint(tester, .5, .2);
    expect(find.byKey(const ValueKey('trace-remove-opening')), findsOneWidget);

    await tapControl(tester, const ValueKey('trace-undo'));
    expect(find.byKey(const ValueKey('trace-remove-opening')), findsNothing);

    await tapControl(tester, const ValueKey('trace-redo'));
    await tapControl(tester, const ValueKey('floorplan-tool-select'));
    await tapModelPoint(tester, .5, .2);
    expect(find.byKey(const ValueKey('trace-remove-opening')), findsOneWidget);
  });

  testWidgets('original image persists across review, editing and reopen', (
    tester,
  ) async {
    final (harness, roomId) = await openPushedDraft(
      tester,
      draft: rectangle,
      measurements: const [
        ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4),
      ],
    );
    final sourceId = harness.controller.traceForRoom(roomId)!.sourceId;
    final imageKey = ValueKey('floorplan-source-$sourceId');

    Uint8List? bytesOf(ImageProvider<Object> provider) {
      final decoded = provider is ResizeImage
          ? provider.imageProvider
          : provider;
      return decoded is MemoryImage ? decoded.bytes : null;
    }

    Future<List<Image>> imagesOnCanvas() async {
      await tester.ensureVisible(
        find.byKey(const ValueKey('floorplan-trace-canvas')),
      );
      await tester.pumpAndSettle();
      return tester.widgetList<Image>(find.byKey(imageKey)).toList();
    }

    void expectSharedImage(List<Image> images) {
      expect(images, hasLength(2));
      expect(images.every((image) => image.gaplessPlayback), isTrue);
      final bytes = [for (final image in images) bytesOf(image.image)];
      expect(bytes.every((value) => value != null), isTrue);
      expect(identical(bytes.first, bytes.last), isTrue);
    }

    final opened = await imagesOnCanvas();
    expectSharedImage(opened);

    // Switching between review and editing views keeps the same cached bytes.
    await tester.ensureVisible(find.text('Mover / zoom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mover / zoom'));
    await tester.pumpAndSettle();
    final reviewView = await imagesOnCanvas();
    expectSharedImage(reviewView);
    expect(
      identical(bytesOf(reviewView.first.image), bytesOf(opened.first.image)),
      isTrue,
    );

    await tester.ensureVisible(find.text('Trazar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trazar'));
    await tester.pumpAndSettle();
    final afterModeChange = await imagesOnCanvas();
    expectSharedImage(afterModeChange);
    expect(
      identical(
        bytesOf(afterModeChange.first.image),
        bytesOf(opened.first.image),
      ),
      isTrue,
    );

    // Selecting another wall and dragging a vertex never remount the source.
    await tapControl(tester, const ValueKey('wall-chip-1'));
    final afterSelection = await imagesOnCanvas();
    expectSharedImage(afterSelection);
    expect(
      identical(
        bytesOf(afterSelection.first.image),
        bytesOf(opened.first.image),
      ),
      isTrue,
    );

    await dragModelPoint(tester, fromX: .2, fromZ: .2, toX: .24, toZ: .24);
    expectSharedImage(await imagesOnCanvas());

    await tapControl(tester, const ValueKey('trace-undo'));
    await tapControl(tester, const ValueKey('trace-redo'));
    expectSharedImage(await imagesOnCanvas());

    // Back to the persisted baseline so the image assertion does not depend on
    // the geometry persistence path.
    await tapControl(tester, const ValueKey('trace-undo'));
    await tapControl(tester, const ValueKey('floorplan-trace-save'));
    await tapControl(tester, const ValueKey('open-floorplan-editor'));
    expectSharedImage(await imagesOnCanvas());
  });

  testWidgets('confirmed wall lengths live in the document', (tester) async {
    final (harness, roomId) = await openPushedDraft(tester, draft: rectangle);
    await tapModelPoint(tester, .5, .2);
    await tester.enterText(find.byKey(const ValueKey('trace-wall-0')), '4.2');
    await tester.pumpAndSettle();
    expect(find.textContaining('m · confirmada'), findsOneWidget);

    await tapControl(tester, const ValueKey('floorplan-trace-save'));
    final saved = harness.controller.traceForRoom(roomId)!;
    final evidence = saved.visualDraft!.measurements.single;
    expect(evidence.wallId, isNotNull);
    expect(evidence.meters, 4.2);
    expect(evidence.provenance, 'user');
    expect(harness.controller.rooms.single.references, hasLength(4));

    // The value survives reopening without duplicating evidence.
    await tapControl(tester, const ValueKey('open-floorplan-editor'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('trace-wall-0')))
          .controller!
          .text,
      '4.2',
    );
    expect(find.textContaining('m · confirmada'), findsOneWidget);
    expect(
      harness.controller.traceForRoom(roomId)!.visualDraft!.measurements,
      hasLength(1),
    );
  });

  testWidgets(
    'reset after reopening restores the persisted document baseline',
    (tester) async {
      final (harness, roomId) = await openPushedDraft(
        tester,
        draft: rectangle,
        measurements: const [
          ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4),
        ],
      );
      await tapModelPoint(tester, .5, .2);
      await tapControl(tester, const ValueKey('floorplan-tool-door'));
      await tapModelPoint(tester, .5, .2);
      await tapControl(tester, const ValueKey('floorplan-trace-save'));

      final persisted = harness.controller.traceForRoom(roomId)!.visualDraft!;
      final persistedWallIds = persisted.rooms.single.wallIds;
      final persistedOpeningId = persisted.openings.single.id;
      final persistedMeasurementId = persisted.measurements.single.id;

      await tapControl(tester, const ValueKey('open-floorplan-editor'));
      await tapModelPoint(tester, .5, .2);
      await tapControl(tester, const ValueKey('trace-remove-opening'));
      expect(find.byKey(const ValueKey('trace-remove-opening')), findsNothing);

      await tapControl(tester, const ValueKey('trace-reset'));
      await tapModelPoint(tester, .5, .2);
      expect(
        find.byKey(const ValueKey('trace-remove-opening')),
        findsOneWidget,
      );

      await tapControl(tester, const ValueKey('trace-undo'));
      expect(find.byKey(const ValueKey('trace-remove-opening')), findsNothing);
      await tapControl(tester, const ValueKey('trace-redo'));
      await tapModelPoint(tester, .5, .2);
      expect(
        find.byKey(const ValueKey('trace-remove-opening')),
        findsOneWidget,
      );

      await tapControl(tester, const ValueKey('floorplan-trace-save'));
      final restored = harness.controller.traceForRoom(roomId)!.visualDraft!;
      expect(restored.rooms.single.wallIds, persistedWallIds);
      expect(restored.openings.single.id, persistedOpeningId);
      expect(restored.measurements.single.id, persistedMeasurementId);
    },
  );

  testWidgets(
    'wall measurement fields keep their wall identity through split undo redo',
    (tester) async {
      await openDraft(tester, draft: rectangle);
      await tapModelPoint(tester, .5, .2);
      await tester.enterText(find.byKey(const ValueKey('trace-wall-0')), '4.1');
      await tapControl(tester, const ValueKey('wall-chip-1'));
      await tester.enterText(find.byKey(const ValueKey('trace-wall-1')), '3.2');
      await tester.pumpAndSettle();

      await choosePerimeterTool(tester);
      await tapModelPoint(tester, .8, .5);
      await tapControl(tester, const ValueKey('trace-split-wall'));
      await tapModelPoint(tester, .8, .5);
      await tapControl(tester, const ValueKey('trace-undo'));
      await tapControl(tester, const ValueKey('trace-redo'));

      await tapControl(tester, const ValueKey('wall-chip-0'));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('trace-wall-0')))
            .controller!
            .text,
        '4.1',
      );
      await tapControl(tester, const ValueKey('wall-chip-1'));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('trace-wall-1')))
            .controller!
            .text,
        '3.2',
      );
    },
  );

  testWidgets(
    'pending AI measurement cannot confirm until explicitly reviewed',
    (tester) async {
      final (harness, roomId) = await openPushedDraft(
        tester,
        draft: rectangle.copyWith(
          measurements: const [
            VisualWallMeasurementEvidence(
              id: 'ai-a',
              wallId: 'a',
              meters: 4,
              provenance: 'ai_detected',
              requiresReview: true,
            ),
          ],
        ),
      );

      await tapControl(tester, const ValueKey('floorplan-trace-save'));
      expect(
        harness.controller
            .traceForRoom(roomId)!
            .visualDraft!
            .measurements
            .single
            .requiresReview,
        isTrue,
      );

      await tapControl(tester, const ValueKey('evidence-confirm-ai-a'));
      expect(find.byKey(const ValueKey('evidence-confirm-ai-a')), findsNothing);
      await tapControl(tester, const ValueKey('trace-undo'));
      expect(
        find.byKey(const ValueKey('evidence-confirm-ai-a')),
        findsOneWidget,
      );
      await tapControl(tester, const ValueKey('trace-redo'));
      expect(find.byKey(const ValueKey('evidence-confirm-ai-a')), findsNothing);
      await tapControl(tester, const ValueKey('floorplan-trace-save'));
      final confirmed = harness.controller
          .traceForRoom(roomId)!
          .visualDraft!
          .measurements
          .single;
      expect(confirmed.provenance, 'ai_detected');
      expect(confirmed.requiresReview, isFalse);
    },
  );

  testWidgets(
    'conflicting AI measurement confirmation is rejected atomically',
    (tester) async {
      final draft = rectangle.copyWith(
        measurements: const [
          VisualWallMeasurementEvidence(id: 'user-a', wallId: 'a', meters: 4),
          VisualWallMeasurementEvidence(
            id: 'ai-a',
            wallId: 'a',
            meters: 4.2,
            provenance: 'ai_detected',
            requiresReview: true,
          ),
        ],
      );
      final (harness, roomId) = await openDraft(tester, draft: draft);

      await tapControl(tester, const ValueKey('evidence-confirm-ai-a'));

      expect(
        find.textContaining('Ya existe una medida confirmada'),
        findsOneWidget,
      );
      final persisted = harness.controller.traceForRoom(roomId)!.visualDraft!;
      expect(persisted.measurement('user-a')!.isAuthoritative, isTrue);
      expect(persisted.measurement('ai-a')!.requiresReview, isTrue);
      expect(persisted.measurement('ai-a')!.provenance, 'ai_detected');
    },
  );

  testWidgets(
    'dragging physical openings updates offset and normalized geometry',
    (tester) async {
      final draft = metricRectangle.copyWith(
        openings: const [
          VisualOpeningDraft(
            id: 'window-a',
            type: VisualOpeningType.window,
            wallId: 'a',
            position: .25,
            normalizedWidth: .3,
            widthM: 1.2,
            heightM: 1.1,
            offsetFromWallStartM: .4,
            sillHeightM: .8,
          ),
          VisualOpeningDraft(
            id: 'door-b',
            type: VisualOpeningType.door,
            wallId: 'b',
            position: .25,
            normalizedWidth: .3,
            widthM: .9,
            heightM: 2,
            offsetFromWallStartM: .3,
          ),
        ],
        measurements: const [
          VisualWallMeasurementEvidence(id: 'a:length', wallId: 'a', meters: 4),
          VisualWallMeasurementEvidence(
            id: 'a:height',
            wallId: 'a',
            meters: 2.4,
            dimension: VisualWallMeasurementDimension.height,
          ),
          VisualWallMeasurementEvidence(id: 'b:length', wallId: 'b', meters: 3),
          VisualWallMeasurementEvidence(
            id: 'b:height',
            wallId: 'b',
            meters: 2.8,
            dimension: VisualWallMeasurementDimension.height,
          ),
        ],
      );
      final (harness, roomId) = await openDraft(tester, draft: draft);

      await tapModelPoint(tester, .35, .2);
      expect(
        find.byKey(const ValueKey('selected-opening-window-a')),
        findsOneWidget,
      );
      await dragModelPoint(tester, fromX: .35, fromZ: .2, toX: .5, toZ: .2);
      await tapModelPoint(tester, .8, .340625);
      expect(
        find.byKey(const ValueKey('selected-opening-door-b')),
        findsOneWidget,
      );
      await dragModelPoint(
        tester,
        fromX: .8,
        fromZ: .340625,
        toX: .8,
        toZ: .48125,
      );
      await tapControl(tester, const ValueKey('floorplan-trace-save'));

      final saved = harness.controller.traceForRoom(roomId)!.visualDraft!;
      final window = saved.opening('window-a')!;
      final door = saved.opening('door-b')!;
      expect(window.position, closeTo(.5, 1e-6));
      expect(window.normalizedWidth, closeTo(.3, 1e-6));
      expect(window.offsetFromWallStartM, closeTo(1.4, 1e-6));
      expect(door.position, closeTo(.5, 1e-6));
      expect(door.normalizedWidth, closeTo(.3, 1e-6));
      expect(door.offsetFromWallStartM, closeTo(1.05, 1e-6));
      expect(saved.validate(), isEmpty);
    },
  );

  testWidgets(
    'door and window physical dimensions stay independent through undo and reopen',
    (tester) async {
      final draft = metricRectangle.copyWith(
        openings: const [
          VisualOpeningDraft(
            id: 'window-a',
            type: VisualOpeningType.window,
            wallId: 'a',
            position: .3,
            normalizedWidth: .15,
          ),
          VisualOpeningDraft(
            id: 'door-b',
            type: VisualOpeningType.door,
            wallId: 'b',
            position: .5,
            normalizedWidth: .2,
          ),
        ],
        measurements: const [
          VisualWallMeasurementEvidence(id: 'a:length', wallId: 'a', meters: 4),
          VisualWallMeasurementEvidence(
            id: 'a:height',
            wallId: 'a',
            meters: 2.4,
            dimension: VisualWallMeasurementDimension.height,
          ),
          VisualWallMeasurementEvidence(id: 'b:length', wallId: 'b', meters: 3),
          VisualWallMeasurementEvidence(
            id: 'b:height',
            wallId: 'b',
            meters: 2.8,
            dimension: VisualWallMeasurementDimension.height,
          ),
          VisualWallMeasurementEvidence(id: 'c:length', wallId: 'c', meters: 4),
          VisualWallMeasurementEvidence(id: 'd:length', wallId: 'd', meters: 3),
        ],
      );
      final (harness, roomId) = await openPushedDraft(tester, draft: draft);

      await tapModelPoint(tester, .38, .2);
      expect(
        find.byKey(const ValueKey('selected-opening-window-a')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('trace-opening-width-window-a')),
        '1.2',
      );
      await tester.drag(
        find.byKey(const ValueKey('floorplan-trace-scroll')),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      final windowHeight = find.byKey(
        const ValueKey('trace-opening-height-window-a'),
      );
      await tester.ensureVisible(windowHeight);
      await tester.pumpAndSettle();
      await tester.enterText(windowHeight, '1.1');
      await tester.drag(
        find.byKey(const ValueKey('floorplan-trace-scroll')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      final windowOffset = find.byKey(
        const ValueKey('trace-opening-offset-window-a'),
      );
      await tester.ensureVisible(windowOffset);
      await tester.enterText(windowOffset, '0');

      await tapModelPoint(tester, .8, .48125);
      expect(
        find.byKey(const ValueKey('selected-opening-door-b')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('trace-opening-width-door-b')),
        '.9',
      );
      await tester.enterText(
        find.byKey(const ValueKey('trace-opening-height-door-b')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('trace-opening-offset-door-b')),
        '.3',
      );
      await tapControl(tester, const ValueKey('trace-undo'));
      await tapControl(tester, const ValueKey('trace-redo'));
      await tapModelPoint(tester, .8, .35);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-opening-width-door-b')),
            )
            .controller!
            .text,
        '0.9',
      );

      await tapModelPoint(tester, .29, .2);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-opening-height-window-a')),
            )
            .controller!
            .text,
        '1.1',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-opening-offset-window-a')),
            )
            .controller!
            .text,
        '0.0',
      );

      await tapControl(tester, const ValueKey('floorplan-trace-save'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      final saved = harness.controller.traceForRoom(roomId)!.visualDraft!;
      expect(saved.opening('window-a')!.wallId, 'a');
      expect(saved.opening('window-a')!.widthM, 1.2);
      expect(saved.opening('window-a')!.heightM, 1.1);
      expect(saved.opening('window-a')!.offsetFromWallStartM, 0);
      expect(saved.opening('door-b')!.wallId, 'b');
      expect(saved.opening('door-b')!.widthM, .9);
      expect(saved.opening('door-b')!.heightM, 2);
      expect(saved.opening('door-b')!.offsetFromWallStartM, .3);
      expect(saved.openings, hasLength(2));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpEditor(tester, harness, roomId, pushed: false);
      await tapModelPoint(tester, .8, .35);
      await tester.drag(
        find.byKey(const ValueKey('floorplan-trace-scroll')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-opening-offset-door-b')),
            )
            .controller!
            .text,
        '0.3',
      );
      await tapModelPoint(tester, .29, .2);
      await tester.drag(
        find.byKey(const ValueKey('floorplan-trace-scroll')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-opening-width-window-a')),
            )
            .controller!
            .text,
        '1.2',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-opening-offset-window-a')),
            )
            .controller!
            .text,
        '0.0',
      );
    },
  );

  testWidgets(
    'wall heights stay independent through selection undo redo and reopen',
    (tester) async {
      final (harness, roomId) = await openPushedDraft(
        tester,
        draft: metricRectangle,
      );
      await tapControl(tester, const ValueKey('wall-chip-0'));
      await tester.enterText(find.byKey(const ValueKey('trace-wall-0')), '4');
      await tester.enterText(
        find.byKey(const ValueKey('trace-wall-height-0')),
        '2.4',
      );
      await tapControl(tester, const ValueKey('wall-chip-1'));
      await tester.enterText(find.byKey(const ValueKey('trace-wall-1')), '3');
      await tester.enterText(
        find.byKey(const ValueKey('trace-wall-height-1')),
        '2.8',
      );
      // Complete the horizontal metric evidence so the actual Save action is
      // enabled. The two selected walls remain the subject of this height
      // regression; these measurements only satisfy the existing workflow.
      await tapControl(tester, const ValueKey('wall-chip-2'));
      await tester.enterText(find.byKey(const ValueKey('trace-wall-2')), '4');
      await tapControl(tester, const ValueKey('wall-chip-3'));
      await tester.enterText(find.byKey(const ValueKey('trace-wall-3')), '3');
      await tapControl(tester, const ValueKey('wall-chip-0'));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-wall-height-0')),
            )
            .controller!
            .text,
        '2.4',
      );
      await tapControl(tester, const ValueKey('trace-undo'));
      await tapControl(tester, const ValueKey('trace-redo'));
      await tapControl(tester, const ValueKey('wall-chip-1'));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-wall-height-1')),
            )
            .controller!
            .text,
        '2.8',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('floorplan-trace-save')),
            )
            .onPressed,
        isNotNull,
      );
      await tapControl(tester, const ValueKey('floorplan-trace-save'));
      // Saving writes through the draft store. Let the pending zero-delay
      // futures complete, then use the popped route as the observable signal
      // that the save transaction has finished.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('open-floorplan-editor')),
        findsOneWidget,
      );
      final firstSaved = harness.controller.traceForRoom(roomId)!.visualDraft!;
      expect(firstSaved.wallLength('a')!.meters, 4);
      expect(firstSaved.wallHeight('a')!.meters, 2.4);
      expect(firstSaved.wallLength('b')!.meters, 3);
      expect(firstSaved.wallHeight('b')!.meters, 2.8);
      final wallIds = firstSaved.rooms.single.wallIds;
      expect(firstSaved.measurements, hasLength(6));

      // Reuse the same fresh-editor lifecycle as the other trace tests. The
      // screen restores its image source asynchronously, so a direct rebuild
      // must go through [pumpEditor] before inspecting field controllers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpEditor(tester, harness, roomId, pushed: false);
      await tapControl(tester, const ValueKey('wall-chip-0'));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-wall-height-0')),
            )
            .controller!
            .text,
        '2.4',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('trace-wall-0')))
            .controller!
            .text,
        '4.0',
      );
      await tapControl(tester, const ValueKey('wall-chip-1'));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-wall-height-1')),
            )
            .controller!
            .text,
        '2.8',
      );
      expect(
        harness.controller
            .traceForRoom(roomId)!
            .visualDraft!
            .wallHeight('a')!
            .meters,
        2.4,
      );
      expect(
        harness.controller
            .traceForRoom(roomId)!
            .visualDraft!
            .rooms
            .single
            .wallIds,
        wallIds,
      );

      await tester.enterText(
        find.byKey(const ValueKey('trace-wall-height-1')),
        '2.9',
      );
      await tapControl(tester, const ValueKey('floorplan-trace-save'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-floorplan-editor')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpEditor(tester, harness, roomId, pushed: false);
      await tapControl(tester, const ValueKey('wall-chip-0'));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-wall-height-0')),
            )
            .controller!
            .text,
        '2.4',
      );
      await tapControl(tester, const ValueKey('wall-chip-1'));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('trace-wall-height-1')),
            )
            .controller!
            .text,
        '2.9',
      );
      final secondSaved = harness.controller.traceForRoom(roomId)!.visualDraft!;
      expect(secondSaved.rooms.single.wallIds, wallIds);
      expect(secondSaved.measurements, hasLength(6));
      expect(secondSaved.wallHeight('a')!.meters, 2.4);
      expect(secondSaved.wallHeight('b')!.meters, 2.9);
    },
  );

  testWidgets('length and height have independent document history', (
    tester,
  ) async {
    await openDraft(tester, draft: metricRectangle);
    await tapControl(tester, const ValueKey('wall-chip-0'));
    await tester.enterText(find.byKey(const ValueKey('trace-wall-0')), '4');
    await tester.enterText(
      find.byKey(const ValueKey('trace-wall-height-0')),
      '2.4',
    );
    await tester.enterText(find.byKey(const ValueKey('trace-wall-0')), '4.1');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('trace-wall-height-0')))
          .controller!
          .text,
      '2.4',
    );

    await tapControl(tester, const ValueKey('trace-undo'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('trace-wall-0')))
          .controller!
          .text,
      '4.0',
    );
    await tapControl(tester, const ValueKey('trace-undo'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('trace-wall-height-0')))
          .controller!
          .text,
      '',
    );
    await tapControl(tester, const ValueKey('trace-redo'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('trace-wall-height-0')))
          .controller!
          .text,
      '2.4',
    );
  });

  testWidgets('all current physical walls share one selector and P mapping', (
    tester,
  ) async {
    final draft = polygonDraft(13);
    await openDraft(tester, draft: draft);

    final selector = find.byKey(const ValueKey('floorplan-wall-selector'));
    expect(selector, findsOneWidget);
    final delegate =
        tester.widget<ListView>(selector).childrenDelegate
            as SliverChildBuilderDelegate;
    expect(delegate.childCount, 13);
    expect(paintedWalls(tester), hasLength(13));
    expect(
      find.byKey(const ValueKey('wall-selector-entry-w0')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('wall-chip-10')),
      200,
      scrollable: find.descendant(
        of: selector,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('wall-chip-10')));
    await tester.pumpAndSettle();
    expect(find.text('P11 de 13'), findsOneWidget);
    expect(paintedSelectedWallId(tester), 'w10');

    final wall = draft.walls[10];
    await tapModelPoint(
      tester,
      (wall.start.x + wall.end.x) / 2,
      (wall.start.z + wall.end.z) / 2,
    );
    expect(find.text('P11 de 13'), findsOneWidget);
    expect(paintedSelectedWallId(tester), 'w10');
  });

  testWidgets('selected wall header stays usable at 328 logical pixels', (
    tester,
  ) async {
    await openDraft(tester, draft: polygonDraft(13));
    tester.view.physicalSize = const Size(328, 1400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();

    final toolbar = find.byKey(const ValueKey('floorplan-editor-tools'));
    expect(toolbar, findsOneWidget);
    expect(
      tester.widget<SingleChildScrollView>(toolbar).scrollDirection,
      Axis.horizontal,
    );
    for (final key in const [
      'floorplan-tool-select',
      'floorplan-tool-vertex',
      'floorplan-tool-wall',
      'floorplan-tool-door',
      'floorplan-tool-window',
      'floorplan-tool-contour',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }

    await tapControl(tester, const ValueKey('floorplan-tool-contour'));
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('floorplan-tool-contour')),
          )
          .selected,
      isTrue,
    );
    await tapControl(tester, const ValueKey('floorplan-tool-wall'));
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('floorplan-tool-wall')))
          .selected,
      isTrue,
    );
    await tapControl(tester, const ValueKey('floorplan-tool-vertex'));
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('floorplan-tool-vertex')),
          )
          .selected,
      isTrue,
    );

    await tapControl(tester, const ValueKey('wall-next'));
    expect(find.text('P2 de 13'), findsOneWidget);
    await tapControl(tester, const ValueKey('wall-previous'));
    expect(find.text('P1 de 13'), findsOneWidget);
    expect(find.byKey(const ValueKey('wall-next')), findsOneWidget);
    expect(find.byKey(const ValueKey('wall-previous')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wall selector supports 26 physical walls without overflow', (
    tester,
  ) async {
    await openDraft(tester, draft: polygonDraft(26));

    final selector = find.byKey(const ValueKey('floorplan-wall-selector'));
    expect(selector, findsOneWidget);
    expect(tester.widget<ListView>(selector).scrollDirection, Axis.horizontal);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('wall-chip-25')),
      240,
      scrollable: find.descendant(
        of: selector,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('wall-chip-25')));
    await tester.pumpAndSettle();
    expect(find.text('P26 de 26'), findsOneWidget);
    expect(paintedSelectedWallId(tester), 'w25');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'topology mutation updates count and keeps measurement by wallId',
    (tester) async {
      final draft = polygonDraft(5);
      await openDraft(tester, draft: draft);
      await tapControl(tester, const ValueKey('wall-chip-2'));
      await tester.enterText(
        find.byKey(const ValueKey('trace-wall-2')),
        '3.25',
      );

      await chooseVertexTool(tester);
      final splitWall = draft.walls.first;
      await tapModelPoint(
        tester,
        (splitWall.start.x + splitWall.end.x) / 2,
        (splitWall.start.z + splitWall.end.z) / 2,
      );

      expect(find.byKey(const ValueKey('wall-chip-5')), findsOneWidget);
      expect(find.textContaining('de 6'), findsOneWidget);
      expect(paintedSelectedWallId(tester), 'w2');
      final currentIndex = paintedWalls(
        tester,
      ).indexWhere((wall) => wall.id == 'w2');
      expect(currentIndex, greaterThanOrEqualTo(0));
      expect(
        tester
            .widget<TextField>(find.byKey(ValueKey('trace-wall-$currentIndex')))
            .controller!
            .text,
        '3.25',
      );

      await tapControl(tester, const ValueKey('trace-undo'));
      expect(find.byKey(const ValueKey('wall-chip-5')), findsNothing);
      expect(paintedSelectedWallId(tester), 'w2');
      await tapControl(tester, const ValueKey('trace-redo'));
      expect(find.byKey(const ValueKey('wall-chip-5')), findsOneWidget);
      expect(paintedSelectedWallId(tester), 'w2');
    },
  );

  testWidgets('shared wall is listed once and deletion selects a neighbor', (
    tester,
  ) async {
    final partitioned = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle,
      roomId: 'temporary',
      start: const FloorPoint(.2, .5),
      end: const FloorPoint(.8, .5),
    ).draft!;
    await openDraft(tester, draft: partitioned);

    final sharedWalls = partitioned.walls
        .where((wall) => wall.roomIds.length == 2)
        .toList();
    expect(sharedWalls, hasLength(1));
    expect(
      paintedWalls(tester).where((wall) => wall.id == sharedWalls.single.id),
      hasLength(1),
    );

    final sharedIndex = partitioned.walls.indexWhere(
      (wall) => wall.id == sharedWalls.single.id,
    );
    final selector = find.byKey(const ValueKey('floorplan-wall-selector'));
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('wall-chip-$sharedIndex')),
      160,
      scrollable: find.descendant(
        of: selector,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(ValueKey('wall-chip-$sharedIndex')));
    await tester.pumpAndSettle();
    await tapControl(tester, const ValueKey('trace-remove-wall'));

    expect(paintedSelectedWallId(tester), isNot(sharedWalls.single.id));
    expect(paintedSelectedWallId(tester), isNotNull);
    await tapControl(tester, const ValueKey('trace-undo'));
    expect(
      paintedWalls(tester).where((wall) => wall.id == sharedWalls.single.id),
      hasLength(1),
    );
    await tapControl(tester, const ValueKey('trace-redo'));
    expect(
      paintedWalls(tester).where((wall) => wall.id == sharedWalls.single.id),
      isEmpty,
    );
  });
}
