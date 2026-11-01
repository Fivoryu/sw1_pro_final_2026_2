import 'dart:convert';

import 'package:captura_mobile/domain/spatial/floorplan_trace.dart';
import 'package:captura_mobile/domain/spatial/floorplan_visual_draft.dart';
import 'package:captura_mobile/domain/spatial/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FloorplanVisualDraft rectangle({
    List<VisualOpeningDraft> openings = const [],
  }) => FloorplanVisualDraft(
    walls: const [
      VisualWallSegment(
        id: 'a',
        start: FloorPoint(0, 0),
        end: FloorPoint(1, 0),
        roomIds: ['room'],
      ),
      VisualWallSegment(
        id: 'b',
        start: FloorPoint(1, 0),
        end: FloorPoint(1, 1),
        roomIds: ['room'],
      ),
      VisualWallSegment(
        id: 'c',
        start: FloorPoint(1, 1),
        end: FloorPoint(0, 1),
        roomIds: ['room'],
      ),
      VisualWallSegment(
        id: 'd',
        start: FloorPoint(0, 1),
        end: FloorPoint(0, 0),
        roomIds: ['room'],
      ),
    ],
    rooms: const [
      VisualRoomRegion(id: 'room', wallIds: ['a', 'b', 'c', 'd']),
    ],
    openings: openings,
  );

  test(
    'transactional move preserves wall IDs and rejects self intersection',
    () {
      final draft = rectangle();
      final moved = FloorplanVisualDraftEditor.moveVertex(
        draft: draft,
        roomId: 'room',
        wallId: 'a',
        endpoint: VisualWallEndpoint.end,
        point: const FloorPoint(0.8, 0.1),
      );

      expect(moved.isSuccess, isTrue);
      expect(moved.draft!.walls.map((wall) => wall.id), ['a', 'b', 'c', 'd']);
      expect(moved.draft!.validate(), isEmpty);

      final rejected = FloorplanVisualDraftEditor.moveVertex(
        draft: draft,
        roomId: 'room',
        wallId: 'a',
        endpoint: VisualWallEndpoint.end,
        point: const FloorPoint(0, 1),
      );
      expect(rejected.isSuccess, isFalse);
      expect(draft.contourForRoom('room'), const [
        FloorPoint(0, 0),
        FloorPoint(1, 0),
        FloorPoint(1, 1),
        FloorPoint(0, 1),
      ]);
    },
  );

  test('moving shared vertex preserves associated evidence and openings', () {
    final draft =
        rectangle(
          openings: const [
            VisualOpeningDraft(
              id: 'door-a',
              type: VisualOpeningType.door,
              wallId: 'a',
              position: .5,
              normalizedWidth: .2,
            ),
          ],
        ).copyWith(
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

    final moved = FloorplanVisualDraftEditor.moveVertex(
      draft: draft,
      roomId: 'room',
      wallId: 'a',
      endpoint: VisualWallEndpoint.end,
      point: const FloorPoint(.85, .15),
    );

    expect(moved.isSuccess, isTrue);
    expect(
      moved.draft!.walls.firstWhere((wall) => wall.id == 'a').end,
      const FloorPoint(.85, .15),
    );
    expect(
      moved.draft!.walls.firstWhere((wall) => wall.id == 'b').start,
      const FloorPoint(.85, .15),
    );
    expect(moved.draft!.measurements.single.id, 'length-a');
    expect(moved.draft!.measurements.single.requiresReview, isTrue);
    expect(moved.draft!.openings.single.wallId, 'a');
  });

  test(
    'manual wall path keeps perimeter connected and rejects zero length',
    () {
      final added = FloorplanVisualDraftEditor.addWallPath(
        draft: rectangle(),
        roomId: 'room',
        wallId: 'a',
        start: const FloorPoint(.3, 0),
        end: const FloorPoint(.7, .2),
      );

      expect(added.isSuccess, isTrue);
      expect(added.draft!.rooms.single.wallIds.length, 6);
      expect(added.draft!.walls.where((wall) => wall.manuallyEdited).length, 3);
      expect(added.draft!.validate(), isEmpty);

      final rejected = FloorplanVisualDraftEditor.addWallPath(
        draft: rectangle(),
        roomId: 'room',
        wallId: 'a',
        start: const FloorPoint(.4, .1),
        end: const FloorPoint(.4, .1),
      );
      expect(rejected.errorCode, 'pared_longitud_cero');
    },
  );

  test('manual wall path replaces an opening-evidence wall safely', () {
    final source = rectangle(
      openings: const [
        VisualOpeningDraft(
          id: 'door-a',
          type: VisualOpeningType.door,
          wallId: 'a',
          position: .5,
          normalizedWidth: .2,
          manuallyPlaced: true,
          confidence: .8,
          widthM: .9,
          heightM: 2,
          offsetFromWallStartM: 2,
        ),
      ],
    );

    // The replacement path is longer than the original wall, but the domain
    // reparameterizes the source wall onto it: the opening stays on the
    // segment that contains its whole interval.
    final added = FloorplanVisualDraftEditor.addWallPath(
      draft: source,
      roomId: 'room',
      wallId: 'a',
      start: const FloorPoint(.3, 0),
      end: const FloorPoint(.7, .2),
    );
    expect(added.isSuccess, isTrue);
    expect(added.draft!.rooms.single.wallIds, [
      'a',
      'a.split.1',
      'a.split.2',
      'b',
      'c',
      'd',
    ]);
    final opening = added.draft!.openings.single;
    expect(opening.id, 'door-a');
    expect(opening.wallId, 'a.split.1');
    expect(opening.position, closeTo(.5677026907899591, 1e-9));
    expect(opening.normalizedWidth, closeTo(.4954092336159584, 1e-9));
    expect(opening.offsetFromWallStartM, closeTo(.7813340709895575, 1e-9));
    expect(opening.widthM, .9);
    expect(opening.heightM, 2);
    expect(opening.manuallyPlaced, isTrue);
    expect(opening.confidence, .8);
    expect(added.draft!.validate(), isEmpty);

    // A path that only shrinks the start keeps the opening in the last
    // resulting segment.
    final tail = FloorplanVisualDraftEditor.addWallPath(
      draft: source,
      roomId: 'room',
      wallId: 'a',
      start: const FloorPoint(.1, 0),
      end: const FloorPoint(.2, 0),
    );
    expect(tail.isSuccess, isTrue);
    final tailOpening = tail.draft!.openings.single;
    expect(tailOpening.id, 'door-a');
    expect(tailOpening.wallId, 'a.split.2');
    expect(tailOpening.position, closeTo(.375, 1e-9));
    expect(tailOpening.normalizedWidth, closeTo(.25, 1e-9));
    expect(tailOpening.offsetFromWallStartM, closeTo(1.1, 1e-9));
    expect(tail.draft!.validate(), isEmpty);
  });

  test(
    'manual wall path rejects invalid geometry and intersects atomically',
    () {
      final source = rectangle(
        openings: const [
          VisualOpeningDraft(
            id: 'door-a',
            type: VisualOpeningType.door,
            wallId: 'a',
            position: .5,
            normalizedWidth: .2,
            widthM: .9,
            offsetFromWallStartM: 2,
          ),
        ],
      );

      // The drawn path reuses an existing perimeter segment.
      final duplicate = FloorplanVisualDraftEditor.addWallPath(
        draft: source,
        roomId: 'room',
        wallId: 'a',
        start: const FloorPoint(1, 0),
        end: const FloorPoint(1, 1),
      );
      expect(duplicate.isSuccess, isFalse);
      expect(duplicate.errorCode, 'pared_duplicada');

      // A path that intersects the physical opening interval cannot remap the
      // evidence and is rejected without touching the source document.
      final intersecting = FloorplanVisualDraftEditor.addWallPath(
        draft: source,
        roomId: 'room',
        wallId: 'a',
        start: const FloorPoint(.4, 0),
        end: const FloorPoint(.5, 0),
      );
      expect(intersecting.isSuccess, isFalse);
      expect(intersecting.errorCode, 'division_sobre_abertura');
      expect(source.openings.single.id, 'door-a');
      expect(source.openings.single.wallId, 'a');
      expect(source.openings.single.position, .5);
      expect(source.walls.map((wall) => wall.id), ['a', 'b', 'c', 'd']);
    },
  );

  test('overlapping openings on one wall are rejected by validation', () {
    final draft = rectangle(
      openings: const [
        VisualOpeningDraft(
          id: 'door-a',
          type: VisualOpeningType.door,
          wallId: 'a',
          position: .4,
          normalizedWidth: .3,
        ),
        VisualOpeningDraft(
          id: 'window-a',
          type: VisualOpeningType.window,
          wallId: 'a',
          position: .5,
          normalizedWidth: .2,
        ),
      ],
    );

    expect(draft.validate(), contains('opening_overlap'));
  });

  test(
    'split retains parent identity and rejects a cut through an opening',
    () {
      final split = FloorplanVisualDraftEditor.splitWall(
        draft: rectangle(),
        roomId: 'room',
        wallId: 'a',
        point: const FloorPoint(0.4, 0),
      );
      expect(split.isSuccess, isTrue);
      expect(split.draft!.rooms.single.wallIds, [
        'a',
        'a.split.1',
        'b',
        'c',
        'd',
      ]);
      expect(
        split.draft!.walls.firstWhere((wall) => wall.id == 'a').end,
        const FloorPoint(0.4, 0),
      );
      expect(split.draft!.validate(), isEmpty);

      final blocked = FloorplanVisualDraftEditor.splitWall(
        draft: rectangle(
          openings: const [
            VisualOpeningDraft(
              id: 'opening',
              type: VisualOpeningType.window,
              wallId: 'a',
              position: .5,
              normalizedWidth: .2,
            ),
          ],
        ),
        roomId: 'room',
        wallId: 'a',
        point: const FloorPoint(0.5, 0),
      );
      expect(blocked.isSuccess, isFalse);
      expect(blocked.errorCode, 'division_sobre_abertura');
    },
  );

  test(
    'split away from an opening keeps its identity on the right segment',
    () {
      final source = rectangle(
        openings: const [
          VisualOpeningDraft(
            id: 'door-a',
            type: VisualOpeningType.door,
            wallId: 'a',
            position: .5,
            normalizedWidth: .2,
            manuallyPlaced: true,
            confidence: .8,
            widthM: .9,
            heightM: 2,
            offsetFromWallStartM: 2,
          ),
        ],
      );

      // The opening interval is fully inside the first resulting segment, which
      // keeps the original wall ID.
      final first = FloorplanVisualDraftEditor.splitWall(
        draft: source,
        roomId: 'room',
        wallId: 'a',
        point: const FloorPoint(.75, 0),
      );
      expect(first.isSuccess, isTrue);
      final firstOpening = first.draft!.openings.single;
      expect(firstOpening.id, 'door-a');
      expect(firstOpening.wallId, 'a');
      expect(firstOpening.position, closeTo(.5 / .75, 1e-9));
      expect(firstOpening.normalizedWidth, closeTo(.2 / .75, 1e-9));
      expect(firstOpening.offsetFromWallStartM, 2);
      expect(firstOpening.widthM, .9);
      expect(firstOpening.heightM, 2);
      expect(firstOpening.manuallyPlaced, isTrue);
      expect(firstOpening.confidence, .8);
      expect(first.draft!.validate(), isEmpty);

      // The opening interval is fully inside the child segment, which becomes
      // its new wall and recalculates both normalized and physical offsets.
      final second = FloorplanVisualDraftEditor.splitWall(
        draft: source,
        roomId: 'room',
        wallId: 'a',
        point: const FloorPoint(.25, 0),
      );
      expect(second.isSuccess, isTrue);
      final secondOpening = second.draft!.openings.single;
      expect(secondOpening.id, 'door-a');
      expect(secondOpening.wallId, 'a.split.1');
      expect(secondOpening.position, closeTo((.5 - .25) / .75, 1e-9));
      expect(secondOpening.normalizedWidth, closeTo(.2 / .75, 1e-9));
      expect(secondOpening.offsetFromWallStartM, closeTo(.875, 1e-9));
      expect(secondOpening.widthM, .9);
      expect(secondOpening.manuallyPlaced, isTrue);
      expect(second.draft!.validate(), isEmpty);

      // Rejected intersections stay atomic: the source document is untouched.
      final rejected = FloorplanVisualDraftEditor.splitWall(
        draft: source,
        roomId: 'room',
        wallId: 'a',
        point: const FloorPoint(.5, 0),
      );
      expect(rejected.isSuccess, isFalse);
      expect(rejected.errorCode, 'division_sobre_abertura');
      expect(source.openings.single.id, 'door-a');
      expect(source.openings.single.wallId, 'a');
      expect(source.openings.single.position, .5);
      expect(source.walls.map((wall) => wall.id), ['a', 'b', 'c', 'd']);
    },
  );

  test('merge retires only the following wall and is atomic', () {
    const draft = FloorplanVisualDraft(
      walls: [
        VisualWallSegment(
          id: 'a',
          start: FloorPoint(0, 0),
          end: FloorPoint(.5, 0),
          roomIds: ['room'],
        ),
        VisualWallSegment(
          id: 'b',
          start: FloorPoint(.5, 0),
          end: FloorPoint(1, 0),
          roomIds: ['room'],
        ),
        VisualWallSegment(
          id: 'c',
          start: FloorPoint(1, 0),
          end: FloorPoint(0, 1),
          roomIds: ['room'],
        ),
        VisualWallSegment(
          id: 'd',
          start: FloorPoint(0, 1),
          end: FloorPoint(0, 0),
          roomIds: ['room'],
        ),
      ],
      rooms: [
        VisualRoomRegion(id: 'room', wallIds: ['a', 'b', 'c', 'd']),
      ],
    );
    final merged = FloorplanVisualDraftEditor.mergeWalls(
      draft: draft,
      roomId: 'room',
      firstWallId: 'b',
      secondWallId: 'a',
    );
    expect(merged.isSuccess, isTrue);
    expect(merged.draft!.rooms.single.wallIds, ['a', 'c', 'd']);
    expect(merged.draft!.walls.map((wall) => wall.id), ['a', 'c', 'd']);
    expect(
      merged.draft!.walls.singleWhere((wall) => wall.id == 'a').end,
      const FloorPoint(1, 0),
    );

    final rejected = FloorplanVisualDraftEditor.mergeWalls(
      draft: rectangle(),
      roomId: 'room',
      firstWallId: 'a',
      secondWallId: 'b',
    );
    expect(rejected.isSuccess, isFalse);
    expect(rectangle().walls.map((wall) => wall.id), ['a', 'b', 'c', 'd']);
  });

  test('validator rejects broken relationships and invalid geometry', () {
    final draft = FloorplanVisualDraft(
      walls: [
        VisualWallSegment(
          id: 'wall-a',
          start: FloorPoint(0, 0),
          end: FloorPoint(0, 0),
          roomIds: ['missing-room'],
        ),
      ],
      rooms: [
        VisualRoomRegion(id: 'room-a', wallIds: ['wall-a']),
      ],
      openings: [
        VisualOpeningDraft(
          id: 'opening-a',
          type: VisualOpeningType.door,
          wallId: 'missing-wall',
          position: 1.2,
        ),
      ],
    );

    expect(
      draft.validate(),
      containsAll([
        'wall_geometry_invalid',
        'room_wall_list_invalid',
        'wall_room_relation_invalid',
        'opening_wall_missing',
        'opening_geometry_invalid',
      ]),
    );
  });

  test(
    'visual draft persists stable wall, room and unassociated opening ids',
    () {
      const draft = FloorplanVisualDraft(
        walls: [
          VisualWallSegment(
            id: 'wall-a',
            start: FloorPoint(0, 0),
            end: FloorPoint(1, 0),
            roomIds: ['room-a'],
            manuallyEdited: true,
          ),
        ],
        rooms: [
          VisualRoomRegion(id: 'room-a', wallIds: ['wall-a']),
        ],
        openings: [
          VisualOpeningDraft(id: 'opening-a', type: VisualOpeningType.window),
        ],
      );

      final restored = FloorplanVisualDraft.fromJson(draft.toJson());

      expect(restored.walls.single.id, 'wall-a');
      expect(restored.walls.single.manuallyEdited, isTrue);
      expect(restored.rooms.single.wallIds, ['wall-a']);
      expect(restored.openings.single.wallId, isNull);
      expect(restored.openings.single.hasVisualGeometry, isFalse);
    },
  );

  test('legacy trace metadata remains readable without a visual draft', () {
    final metadata = FloorplanTraceMetadata.fromJson({
      'roomId': 'legacy',
      'sourceId': 'source',
      'contentType': 'image/png',
      'imageWidth': 100,
      'imageHeight': 100,
      'vertices': const [
        {'x': 0.0, 'z': 0.0},
        {'x': 1.0, 'z': 0.0},
        {'x': 0.0, 'z': 1.0},
      ],
      'openings': const [],
    });

    expect(metadata.visualDraft, isNull);
    expect(metadata.toJson().containsKey('visualDraft'), isFalse);
    final restored = metadata.restoreEditorDraft();
    expect(restored.isReady, isTrue);
    expect(restored.migratedFromLegacy, isTrue);
    final migrated = restored.draft!;
    expect(migrated.validate(), isEmpty);
    expect(migrated.contourForRoom('legacy'), metadata.vertices);
    expect(migrated.walls.map((wall) => wall.id), [
      'legacy:wall:0',
      'legacy:wall:1',
      'legacy:wall:2',
    ]);
  });

  test('opening identity and confidence survive serialization and edits', () {
    final draft = rectangle(
      openings: const [
        VisualOpeningDraft(
          id: 'opening-a',
          type: VisualOpeningType.window,
          wallId: 'b',
          position: .4,
          normalizedWidth: .2,
          confidence: .73,
        ),
      ],
    );
    final restored = FloorplanVisualDraft.fromJson(
      (jsonDecode(jsonEncode(draft.toJson())) as Map).cast<String, Object?>(),
    );
    expect(restored.validate(), isEmpty);
    expect(restored.openings.single.id, 'opening-a');
    expect(restored.openings.single.confidence, .73);

    final moved = restored.withOpening(
      restored.openings.single.copyWith(position: .6),
    );
    expect(moved.openings, hasLength(1));
    expect(moved.openings.single.id, 'opening-a');
    expect(moved.openings.single.wallId, 'b');
    expect(moved.openings.single.position, .6);
    expect(moved.openings.single.confidence, .73);
    expect(moved.withoutOpening('opening-a').openings, isEmpty);
  });

  test('physical door and window dimensions persist and validate by wall', () {
    final draft =
        rectangle(
              openings: const [
                VisualOpeningDraft(
                  id: 'window-a',
                  type: VisualOpeningType.window,
                  wallId: 'a',
                  position: .3,
                  normalizedWidth: .15,
                  widthM: 1.2,
                  heightM: 1.1,
                  offsetFromWallStartM: .4,
                ),
                VisualOpeningDraft(
                  id: 'door-b',
                  type: VisualOpeningType.door,
                  wallId: 'b',
                  position: .6,
                  normalizedWidth: .2,
                  widthM: .9,
                  heightM: 2,
                  offsetFromWallStartM: .3,
                ),
              ],
            )
            .withMeasurement(
              const VisualWallMeasurementEvidence(
                id: 'a:length',
                wallId: 'a',
                meters: 4,
              ),
            )
            .withMeasurement(
              const VisualWallMeasurementEvidence(
                id: 'a:height',
                wallId: 'a',
                meters: 2.4,
                dimension: VisualWallMeasurementDimension.height,
              ),
            )
            .withMeasurement(
              const VisualWallMeasurementEvidence(
                id: 'b:length',
                wallId: 'b',
                meters: 3,
              ),
            )
            .withMeasurement(
              const VisualWallMeasurementEvidence(
                id: 'b:height',
                wallId: 'b',
                meters: 2.8,
                dimension: VisualWallMeasurementDimension.height,
              ),
            );
    final restored = FloorplanVisualDraft.fromJson(
      (jsonDecode(jsonEncode(draft.toJson())) as Map).cast<String, Object?>(),
    );
    expect(restored.validate(), isEmpty);
    expect(restored.opening('window-a')!.widthM, 1.2);
    expect(restored.opening('window-a')!.heightM, 1.1);
    expect(restored.opening('window-a')!.offsetFromWallStartM, .4);
    expect(restored.opening('door-b')!.widthM, .9);
    expect(restored.opening('door-b')!.heightM, 2);
    expect(restored.opening('door-b')!.offsetFromWallStartM, .3);
    expect(restored.opening('window-a')!.position, .3);
    expect(restored.opening('window-a')!.normalizedWidth, .15);

    final tooWide = restored.withOpening(
      restored.opening('window-a')!.copyWith(widthM: 3.8),
    );
    expect(tooWide.validate(), contains('opening_exceeds_wall_length'));
    final tooHigh = restored.withOpening(
      restored.opening('door-b')!.copyWith(heightM: 3),
    );
    expect(tooHigh.validate(), contains('opening_exceeds_wall_height'));

    final legacy = FloorplanVisualDraft.fromJson({
      ...restored.toJson(),
      'version': 2,
      'openings': [
        {
          'id': 'legacy-window',
          'type': 'unknown',
          'wallId': 'a',
          'position': .3,
          'normalizedWidth': .15,
        },
      ],
    });
    expect(legacy.openings.single.type, VisualOpeningType.unknown);
    expect(legacy.openings.single.widthM, isNull);
    expect(legacy.openings.single.heightM, isNull);
    expect(legacy.openings.single.offsetFromWallStartM, isNull);
    expect(legacy.openings.single.position, .3);
    expect(legacy.openings.single.normalizedWidth, .15);
  });

  test('window sill height persists and cannot exceed its wall height', () {
    final draft = rectangle()
        .withMeasurement(
          const VisualWallMeasurementEvidence(
            id: 'a-height',
            wallId: 'a',
            meters: 2.4,
            dimension: VisualWallMeasurementDimension.height,
          ),
        )
        .withOpening(
          const VisualOpeningDraft(
            id: 'window-a',
            type: VisualOpeningType.window,
            wallId: 'a',
            widthM: 1,
            heightM: 1.2,
            offsetFromWallStartM: .5,
            sillHeightM: .8,
          ),
        );
    final restored = FloorplanVisualDraft.fromJson(draft.toJson());
    expect(restored.opening('window-a')!.sillHeightM, .8);
    expect(restored.validate(), isEmpty);

    final invalid = restored.withOpening(
      restored.opening('window-a')!.copyWith(sillHeightM: 1.3),
    );
    expect(invalid.validate(), contains('opening_exceeds_wall_height'));

    final legacy = FloorplanVisualDraft.fromJson({
      ...draft.toJson(),
      'openings': [
        {
          'id': 'legacy-window',
          'type': 'window',
          'wallId': 'a',
          'position': .5,
          'normalizedWidth': .2,
        },
      ],
    });
    expect(legacy.opening('legacy-window')!.sillHeightM, isNull);
  });

  test('measurement evidence serializes provenance and review status', () {
    final draft = rectangle().withMeasurement(
      const VisualWallMeasurementEvidence(
        id: 'measure-a',
        wallId: 'a',
        meters: 4.2,
        intervalStart: .1,
        intervalEnd: .4,
        provenance: 'ai_detected',
        requiresReview: true,
        lineageId: 'line-a',
      ),
    );
    expect(draft.validate(), isEmpty);
    final restored = FloorplanVisualDraft.fromJson(
      (jsonDecode(jsonEncode(draft.toJson())) as Map).cast<String, Object?>(),
    );
    final measurement = restored.measurements.single;
    expect(measurement.wallId, 'a');
    expect(measurement.meters, 4.2);
    expect(measurement.intervalStart, .1);
    expect(measurement.intervalEnd, .4);
    expect(measurement.provenance, 'ai_detected');
    expect(measurement.requiresReview, isTrue);
    expect(measurement.lineageId, 'line-a');
  });

  test('derived or unresolved evidence is never authoritative', () {
    final draft = rectangle()
        .withMeasurement(
          const VisualWallMeasurementEvidence(
            id: 'derived',
            wallId: 'a',
            meters: 4,
            provenance: 'derived_geometry',
          ),
        )
        .withMeasurement(
          const VisualWallMeasurementEvidence(
            id: 'unresolved',
            wallId: 'b',
            meters: 3,
            provenance: 'unresolved',
          ),
        )
        .withMeasurement(
          const VisualWallMeasurementEvidence(
            id: 'accepted-ai',
            wallId: 'c',
            meters: 4,
            provenance: 'ai_detected',
          ),
        );
    expect(draft.authoritativeMeasurements.map((value) => value.id), [
      'accepted-ai',
    ]);
  });

  test('validator rejects contradictory authoritative wall dimensions', () {
    final draft = rectangle()
        .withMeasurement(
          const VisualWallMeasurementEvidence(
            id: 'a-length-user',
            wallId: 'a',
            meters: 4,
          ),
        )
        .withMeasurement(
          const VisualWallMeasurementEvidence(
            id: 'a-length-ai',
            wallId: 'a',
            meters: 4.2,
            provenance: 'ai_detected',
          ),
        );
    expect(draft.validate(), contains('measurement_authoritative_conflict'));
  });

  test('validator rejects invalid measurement associations and values', () {
    const draft = FloorplanVisualDraft(
      walls: [
        VisualWallSegment(
          id: 'wall-a',
          start: FloorPoint(0, 0),
          end: FloorPoint(1, 0),
          roomIds: ['room-a'],
        ),
      ],
      rooms: [
        VisualRoomRegion(id: 'room-a', wallIds: ['wall-a']),
      ],
      measurements: [
        VisualWallMeasurementEvidence(
          id: 'measure-a',
          wallId: 'missing-wall',
          meters: 0,
        ),
        VisualWallMeasurementEvidence(
          id: 'measure-a',
          wallId: 'wall-a',
          meters: -1,
          intervalStart: .6,
          intervalEnd: .2,
        ),
        VisualWallMeasurementEvidence(
          id: 'measure-b',
          wallId: 'wall-a',
          meters: 3,
          intervalStart: .2,
        ),
      ],
    );

    expect(
      draft.validate(),
      containsAll([
        'measurement_id_invalid',
        'measurement_wall_missing',
        'measurement_invalid',
        'measurement_interval_invalid',
      ]),
    );
  });

  test('split and merge protect evidence while vertex move preserves it', () {
    final withMeasurement = rectangle().withMeasurement(
      const VisualWallMeasurementEvidence(
        id: 'measure-a',
        wallId: 'a',
        meters: 1,
        provenance: 'user',
      ),
    );
    final split = FloorplanVisualDraftEditor.splitWall(
      draft: withMeasurement,
      roomId: 'room',
      wallId: 'a',
      point: const FloorPoint(.5, 0),
    );
    expect(split.isSuccess, isFalse);
    expect(split.errorCode, 'pared_con_medicion');
    final merge = FloorplanVisualDraftEditor.mergeWalls(
      draft: withMeasurement,
      roomId: 'room',
      firstWallId: 'a',
      secondWallId: 'b',
    );
    expect(merge.isSuccess, isFalse);
    expect(merge.errorCode, 'pared_con_medicion');
    final moved = FloorplanVisualDraftEditor.moveVertex(
      draft: withMeasurement,
      roomId: 'room',
      wallId: 'b',
      endpoint: VisualWallEndpoint.start,
      point: const FloorPoint(1, .05),
    );
    expect(moved.isSuccess, isTrue);
    expect(moved.draft!.measurements.single.id, 'measure-a');
    expect(moved.draft!.measurements.single.wallId, 'a');
    // Structural rejections and the immutable move leave the source untouched.
    expect(withMeasurement.measurements, hasLength(1));
    expect(withMeasurement.walls, hasLength(4));
    expect(
      withMeasurement.hasSameContentAs(
        rectangle().withMeasurement(
          const VisualWallMeasurementEvidence(
            id: 'measure-a',
            wallId: 'a',
            meters: 1,
            provenance: 'user',
          ),
        ),
      ),
      isTrue,
    );

    final withOpening = rectangle(
      openings: const [
        VisualOpeningDraft(
          id: 'opening-a',
          type: VisualOpeningType.door,
          wallId: 'b',
          position: .5,
          normalizedWidth: .2,
        ),
      ],
    );
    final openingSplit = FloorplanVisualDraftEditor.splitWall(
      draft: withOpening,
      roomId: 'room',
      wallId: 'b',
      point: const FloorPoint(1, .5),
    );
    expect(openingSplit.isSuccess, isFalse);
    expect(openingSplit.errorCode, 'division_sobre_abertura');
    final openingMerge = FloorplanVisualDraftEditor.mergeWalls(
      draft: withOpening,
      roomId: 'room',
      firstWallId: 'a',
      secondWallId: 'b',
    );
    expect(openingMerge.isSuccess, isFalse);
    expect(openingMerge.errorCode, 'pared_con_abertura');
    final openingMove = FloorplanVisualDraftEditor.moveVertex(
      draft: withOpening,
      roomId: 'room',
      wallId: 'b',
      endpoint: VisualWallEndpoint.end,
      point: const FloorPoint(1, .95),
    );
    expect(openingMove.isSuccess, isTrue);
    expect(openingMove.draft!.openings.single.id, 'opening-a');
    expect(openingMove.draft!.openings.single.wallId, 'b');
    expect(withOpening.openings.single.wallId, 'b');
  });

  test('legacy migration is deterministic and maps references to walls', () {
    Map<String, Object?> legacyJson() => {
      'roomId': 'legacy',
      'sourceId': 'source',
      'contentType': 'image/png',
      'imageWidth': 100,
      'imageHeight': 80,
      'vertices': const [
        {'x': .1, 'z': .1},
        {'x': .8, 'z': .1},
        {'x': .8, 'z': .7},
        {'x': .1, 'z': .7},
      ],
      'openings': const [
        {
          'edgeIndex': 0,
          'type': 'door',
          'position': .5,
          'normalizedWidth': .2,
          'confidence': .4,
        },
      ],
    };

    const references = [
      LegacyMeasurementReference(edgeIndex: 1, meters: 3.5),
      LegacyMeasurementReference(
        edgeIndex: 9,
        meters: 2,
        provenance: 'unresolved',
        requiresReview: true,
      ),
    ];
    final first = FloorplanTraceMetadata.fromJson(
      legacyJson(),
    ).restoreEditorDraft(references: references);
    final second = FloorplanTraceMetadata.fromJson(
      legacyJson(),
    ).restoreEditorDraft(references: references);

    expect(first.isReady, isTrue);
    expect(first.migratedFromLegacy, isTrue);
    expect(first.draft!.toJson(), second.draft!.toJson());
    expect(first.draft!.validate(), isEmpty);
    expect(first.draft!.openings.single.id, 'legacy:opening:0');
    expect(first.draft!.openings.single.wallId, 'legacy:wall:0');
    expect(first.draft!.openings.single.confidence, .4);
    expect(first.draft!.openings.single.manuallyPlaced, isFalse);
    expect(
      first.draft!.measurement('legacy:measurement:0')!.wallId,
      'legacy:wall:1',
    );
    expect(first.draft!.measurement('legacy:measurement:0')!.meters, 3.5);
    expect(
      first.draft!.measurement('legacy:measurement:0')!.requiresReview,
      isFalse,
    );
    expect(first.draft!.measurement('legacy:measurement:1')!.wallId, isNull);
    expect(
      first.draft!.measurement('legacy:measurement:1')!.requiresReview,
      isTrue,
    );
  });

  test('stored drafts that cannot be trusted are reported, not rebuilt', () {
    Map<String, Object?> traceJson(Object draft) => {
      'roomId': 'room-a',
      'sourceId': 'source',
      'contentType': 'image/png',
      'imageWidth': 100,
      'imageHeight': 80,
      'vertices': const [
        {'x': .1, 'z': .1},
        {'x': .8, 'z': .1},
        {'x': .1, 'z': .7},
      ],
      'openings': const [],
      'visualDraft': draft,
    };

    final invalid = FloorplanTraceMetadata.fromJson(
      traceJson({
        'version': 2,
        'walls': [
          {
            'id': '',
            'start': {'x': 0.0, 'z': 0.0},
            'end': {'x': 0.0, 'z': 0.0},
          },
        ],
        'rooms': <Object?>[],
      }),
    );
    final invalidRestoration = invalid.restoreEditorDraft();
    expect(invalidRestoration.isReady, isFalse);
    expect(invalidRestoration.draft, isNull);
    expect(invalidRestoration.problem, startsWith('visual_draft_invalid'));

    final unsupported = FloorplanTraceMetadata.fromJson(
      traceJson({'version': 99, 'walls': <Object?>[], 'rooms': <Object?>[]}),
    );
    expect(
      unsupported.restoreEditorDraft().problem,
      'visual_draft_unsupported',
    );

    final unreadableJson = traceJson({'version': 2, 'walls': 'broken'});
    final unreadable = FloorplanTraceMetadata.fromJson(unreadableJson);
    expect(unreadable.draftProblem, 'visual_draft_unreadable');
    expect(unreadable.restoreEditorDraft().isReady, isFalse);
    // The original bytes are preserved so a save cannot destroy them.
    expect(unreadable.toJson()['visualDraft'], {
      'version': 2,
      'walls': 'broken',
    });
  });

  test('future documents keep unknown fields and are never downgraded', () {
    final futureDocument = <String, Object?>{
      'version': 4,
      'walls': <Object?>[],
      'rooms': <Object?>[],
      'openings': <Object?>[],
      'measurements': <Object?>[],
      // Written by a newer build: this build cannot interpret or rewrite it.
      'photogrammetry': {
        'anchors': [
          {'id': 'anchor-1', 'confidence': .9},
        ],
      },
      'calibration': {'method': 'lidar', 'scale': 1.25},
    };
    final metadata = FloorplanTraceMetadata.fromJson({
      'roomId': 'room-a',
      'sourceId': 'source',
      'contentType': 'image/png',
      'imageWidth': 100,
      'imageHeight': 80,
      'vertices': const [
        {'x': .1, 'z': .1},
        {'x': .8, 'z': .1},
        {'x': .1, 'z': .7},
      ],
      'openings': const [],
      'visualDraft': futureDocument,
    });

    expect(metadata.visualDraft, isNull);
    expect(metadata.draftProblem, 'visual_draft_unsupported');
    expect(metadata.preservedVisualDraft, same(futureDocument));
    final restoration = metadata.restoreEditorDraft();
    expect(restoration.isReady, isFalse);
    expect(restoration.problem, 'visual_draft_unsupported');
    // Saving the metadata must not drop the newer fields or downgrade it.
    final serialized =
        jsonDecode(jsonEncode(metadata.toJson())) as Map<String, Object?>;
    expect(serialized['visualDraft'], futureDocument);
  });

  test('structurally invalid documents are preserved instead of rebuilt', () {
    final invalidDocument = <String, Object?>{
      'version': 2,
      'walls': [
        {
          'id': 'a',
          'start': {'x': 0.0, 'z': 0.0},
          'end': {'x': 1.0, 'z': 0.0},
          'roomIds': ['room-a'],
        },
        {
          'id': 'b',
          'start': {'x': 1.0, 'z': 0.0},
          'end': {'x': 1.0, 'z': 1.0},
          'roomIds': ['room-a'],
        },
        {
          'id': 'c',
          'start': {'x': 1.0, 'z': 1.0},
          'end': {'x': 0.0, 'z': 0.0},
          'roomIds': ['room-a'],
        },
      ],
      'rooms': [
        {
          'id': 'room-a',
          'wallIds': ['a', 'b', 'c'],
        },
      ],
      'openings': <Object?>[],
      'measurements': [
        {
          'id': 'measure-1',
          'wallId': 'wall-that-does-not-exist',
          'meters': 3.2,
          'provenance': 'ai_detected',
          'requiresReview': true,
          'futureMetadata': {'source': 'provider'},
        },
      ],
    };
    final metadata = FloorplanTraceMetadata.fromJson({
      'roomId': 'room-a',
      'sourceId': 'source',
      'contentType': 'image/png',
      'imageWidth': 100,
      'imageHeight': 80,
      'vertices': const [
        {'x': .1, 'z': .1},
        {'x': .8, 'z': .1},
        {'x': .1, 'z': .7},
      ],
      'openings': const [],
      'visualDraft': invalidDocument,
    });

    expect(metadata.visualDraft, isNull);
    expect(
      metadata.draftProblem,
      'visual_draft_invalid:measurement_wall_missing',
    );
    expect(metadata.restoreEditorDraft().draft, isNull);
    expect(
      (jsonDecode(jsonEncode(metadata.toJson())) as Map)['visualDraft'],
      invalidDocument,
    );
  });

  test('only associated and accepted evidence is authoritative', () {
    final draft = rectangle()
        .withMeasurement(
          const VisualWallMeasurementEvidence(
            id: 'pending',
            wallId: 'a',
            meters: 4,
            provenance: 'ai_detected',
            requiresReview: true,
          ),
        )
        .withMeasurement(
          const VisualWallMeasurementEvidence(
            id: 'orphan',
            meters: 3,
            provenance: 'ai_detected',
            requiresReview: true,
          ),
        )
        .withMeasurement(
          const VisualWallMeasurementEvidence(
            id: 'accepted',
            wallId: 'b',
            meters: 2.5,
            provenance: 'ai_detected',
          ),
        );

    expect(draft.validate(), isEmpty);
    expect(draft.authoritativeMeasurements.map((value) => value.id), [
      'accepted',
    ]);
    expect(draft.unassignedMeasurements.map((value) => value.id), ['orphan']);
    expect(draft.measurement('pending')!.isAuthoritative, isFalse);
    expect(draft.measurement('accepted')!.isAuthoritative, isTrue);
    expect(draft.wallLength('a')!.id, 'pending');
    expect(draft.authoritativeWallLength('a'), isNull);
    expect(draft.authoritativeWallLength('b')!.id, 'accepted');

    final confirmed = draft.withMeasurement(
      draft.measurement('pending')!.copyWith(requiresReview: false),
    );
    expect(confirmed.authoritativeMeasurements.map((value) => value.id), [
      'pending',
      'accepted',
    ]);
    // Accepting evidence never rewrites where it came from.
    expect(confirmed.measurement('pending')!.provenance, 'ai_detected');
    expect(confirmed.authoritativeWallLength('a')!.id, 'pending');
  });

  test('derived and unresolved evidence never becomes authoritative', () {
    final draft = rectangle().copyWith(
      measurements: const [
        VisualWallMeasurementEvidence(
          id: 'derived',
          wallId: 'a',
          meters: 4,
          provenance: 'derived_geometry',
        ),
        VisualWallMeasurementEvidence(
          id: 'unresolved',
          wallId: 'b',
          meters: 3,
          provenance: 'unresolved',
        ),
      ],
    );

    expect(draft.wallLength('a')!.id, 'derived');
    expect(draft.wallLength('b')!.id, 'unresolved');
    expect(draft.authoritativeLengthMeasurements, isEmpty);
    expect(draft.authoritativeWallLength('a'), isNull);
    expect(draft.authoritativeWallLength('b'), isNull);
  });

  test('legacy window migration materializes historical sill default', () {
    final legacy = FloorplanVisualDraft.fromJson({
      ...rectangle().toJson(),
      'version': 2,
      'openings': [
        {
          'id': 'legacy-window',
          'type': 'window',
          'wallId': 'a',
          'position': .5,
          'normalizedWidth': .2,
        },
      ],
    });
    final modern = FloorplanVisualDraft.fromJson({
      ...rectangle().toJson(),
      'version': 3,
      'openings': [
        {
          'id': 'new-window',
          'type': 'window',
          'wallId': 'a',
          'position': .5,
          'normalizedWidth': .2,
        },
      ],
    });

    expect(legacy.opening('legacy-window')!.sillHeightM, .9);
    expect(
      legacy.toJson()['openings'],
      contains(containsPair('sillHeightM', .9)),
    );
    expect(modern.opening('new-window')!.sillHeightM, isNull);
  });

  test('unassigned evidence can be recovered without losing metadata', () {
    final draft = rectangle().withMeasurement(
      const VisualWallMeasurementEvidence(
        id: 'orphan',
        meters: 3.5,
        intervalStart: .2,
        intervalEnd: .5,
        provenance: 'ai_detected',
        requiresReview: true,
        lineageId: 'line-1',
      ),
    );

    final associated = draft.associateMeasurement(
      roomId: 'room',
      wallId: 'b',
      measurementId: 'orphan',
    );
    expect(associated, isNotNull);
    final evidence = associated!.measurement('orphan')!;
    expect(evidence.id, 'orphan');
    expect(evidence.wallId, 'b');
    expect(evidence.meters, 3.5);
    expect(evidence.intervalStart, .2);
    expect(evidence.intervalEnd, .5);
    expect(evidence.provenance, 'ai_detected');
    expect(evidence.lineageId, 'line-1');
    // Recovering evidence never confirms it implicitly.
    expect(evidence.requiresReview, isTrue);

    // Unknown walls, walls of another room and occupied walls are rejected
    // without mutating the document.
    expect(
      draft.associateMeasurement(
        roomId: 'room',
        wallId: 'missing',
        measurementId: 'orphan',
      ),
      isNull,
    );
    expect(
      draft.associateMeasurement(
        roomId: 'other-room',
        wallId: 'a',
        measurementId: 'orphan',
      ),
      isNull,
    );
    final occupied = draft.withMeasurement(
      const VisualWallMeasurementEvidence(
        id: 'existing',
        wallId: 'b',
        meters: 2,
      ),
    );
    expect(
      occupied.associateMeasurement(
        roomId: 'room',
        wallId: 'b',
        measurementId: 'orphan',
      ),
      isNull,
    );
    expect(draft.measurement('orphan')!.wallId, isNull);
    expect(draft.unassignedMeasurements, hasLength(1));
  });

  test('length and height evidence can coexist on the same wall', () {
    final draft = rectangle().copyWith(
      measurements: const [
        VisualWallMeasurementEvidence(id: 'length-b', wallId: 'b', meters: 3),
        VisualWallMeasurementEvidence(
          id: 'orphan-height',
          meters: 2.7,
          intervalStart: .1,
          intervalEnd: .9,
          provenance: 'ai_detected',
          requiresReview: true,
          lineageId: 'height-source',
          dimension: VisualWallMeasurementDimension.height,
        ),
      ],
    );

    final associated = draft.associateMeasurement(
      roomId: 'room',
      wallId: 'b',
      measurementId: 'orphan-height',
    );

    expect(associated, isNotNull);
    expect(associated!.wallLength('b')!.id, 'length-b');
    final height = associated.wallHeight('b')!;
    expect(height.id, 'orphan-height');
    expect(height.meters, 2.7);
    expect(height.provenance, 'ai_detected');
    expect(height.requiresReview, isTrue);
    expect(height.intervalStart, .1);
    expect(height.intervalEnd, .9);
    expect(height.lineageId, 'height-source');
  });

  test('same-dimension association is rejected without mutation', () {
    final draft = rectangle().copyWith(
      measurements: const [
        VisualWallMeasurementEvidence(
          id: 'height-b',
          wallId: 'b',
          meters: 2.6,
          dimension: VisualWallMeasurementDimension.height,
        ),
        VisualWallMeasurementEvidence(
          id: 'orphan-height',
          meters: 2.8,
          provenance: 'ai_detected',
          requiresReview: true,
          dimension: VisualWallMeasurementDimension.height,
        ),
      ],
    );
    final before = draft.toJson();

    final rejected = draft.associateMeasurement(
      roomId: 'room',
      wallId: 'b',
      measurementId: 'orphan-height',
    );

    expect(rejected, isNull);
    expect(draft.toJson(), before);
    expect(draft.measurement('height-b')!.wallId, 'b');
    expect(draft.measurement('orphan-height')!.wallId, isNull);
  });

  test('dangling evidence associations are reported and stay recoverable', () {
    final draft = rectangle().withMeasurement(
      const VisualWallMeasurementEvidence(
        id: 'dangling',
        wallId: 'removed-wall',
        meters: 2.75,
        provenance: 'ai_detected',
        requiresReview: true,
      ),
    );

    expect(draft.validate(), contains('measurement_wall_missing'));
    expect(draft.unassignedMeasurements.map((value) => value.id), ['dangling']);
    expect(
      draft
          .associateMeasurement(
            roomId: 'room',
            wallId: 'c',
            measurementId: 'dangling',
          )!
          .measurement('dangling')!
          .wallId,
      'c',
    );
  });

  test('V3 keeps independent wall length and height evidence', () {
    final draft = rectangle().copyWith(
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
    final restored = FloorplanVisualDraft.fromJson(draft.toJson());
    expect(restored.version, 3);
    expect(restored.wallLength('a')!.meters, 4);
    expect(restored.wallHeight('a')!.meters, 2.4);
    expect(restored.wallLength('b')!.meters, 3);
    expect(restored.wallHeight('b')!.meters, 2.8);
    expect(restored.authoritativeLengthMeasurements, hasLength(2));
    expect(restored.authoritativeHeightMeasurements, hasLength(2));

    final legacy = FloorplanVisualDraft.fromJson({
      ...draft.toJson(),
      'version': 2,
      'measurements': [
        {'id': 'legacy', 'wallId': 'a', 'meters': 4},
      ],
    });
    expect(
      legacy.measurements.single.dimension,
      VisualWallMeasurementDimension.length,
    );
  });

  test('removeVertex dissolves topological neighbors and retains first ID', () {
    const draft = FloorplanVisualDraft(
      walls: [
        VisualWallSegment(
          id: 'a',
          start: FloorPoint(0, 0),
          end: FloorPoint(.5, 0),
          roomIds: ['room'],
        ),
        VisualWallSegment(
          id: 'b',
          start: FloorPoint(.5, 0),
          end: FloorPoint(1, 0),
          roomIds: ['room'],
        ),
        VisualWallSegment(
          id: 'c',
          start: FloorPoint(1, 0),
          end: FloorPoint(1, 1),
          roomIds: ['room'],
        ),
        VisualWallSegment(
          id: 'd',
          start: FloorPoint(1, 1),
          end: FloorPoint(0, 1),
          roomIds: ['room'],
        ),
        VisualWallSegment(
          id: 'e',
          start: FloorPoint(0, 1),
          end: FloorPoint(0, 0),
          roomIds: ['room'],
        ),
      ],
      rooms: [
        VisualRoomRegion(id: 'room', wallIds: ['a', 'b', 'c', 'd', 'e']),
      ],
    );

    final result = FloorplanVisualDraftEditor.removeVertex(
      draft: draft,
      roomId: 'room',
      followingWallId: 'b',
    );

    expect(result.isSuccess, isTrue);
    expect(result.draft!.room('room')!.wallIds, ['a', 'c', 'd', 'e']);
    expect(result.draft!.walls.map((wall) => wall.id), ['a', 'c', 'd', 'e']);
    expect(result.draft!.walls.first.start, const FloorPoint(0, 0));
    expect(result.draft!.walls.first.end, const FloorPoint(1, 0));
    expect(result.draft!.validate(), isEmpty);
    expect(draft.room('room')!.wallIds, ['a', 'b', 'c', 'd', 'e']);
  });

  test('internal wall creates two ordered regions over one physical wall', () {
    final draft = rectangle();

    final result = FloorplanVisualDraftEditor.addInternalWall(
      draft: draft,
      roomId: 'room',
      start: const FloorPoint(0, 0),
      end: const FloorPoint(1, 1),
    );

    expect(result.isSuccess, isTrue);
    expect(result.draft!.rooms, hasLength(2));
    expect(result.draft!.walls, hasLength(5));
    final internal = result.draft!.walls.singleWhere(
      (wall) => wall.id == 'room.internal.1',
    );
    expect(internal.start, const FloorPoint(0, 0));
    expect(internal.end, const FloorPoint(1, 1));
    expect(internal.roomIds, hasLength(2));
    for (final room in result.draft!.rooms) {
      expect(room.wallIds, contains(internal.id));
      expect(result.draft!.contourForRoom(room.id), isNotNull);
    }
    expect(result.draft!.validate(), isEmpty);
  });

  test('internal wall inserts topology vertices at wall midpoints', () {
    final result = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle(),
      roomId: 'room',
      start: const FloorPoint(.5, 0),
      end: const FloorPoint(.5, 1),
    );

    expect(result.isSuccess, isTrue);
    final draft = result.draft!;
    expect(draft.rooms, hasLength(2));
    final internal = draft.walls.singleWhere(
      (wall) => wall.id == 'room.internal.1',
    );
    expect(internal.start, const FloorPoint(.5, 0));
    expect(internal.end, const FloorPoint(.5, 1));
    expect(internal.roomIds, hasLength(2));
    expect(
      draft.walls.map((wall) => wall.id),
      containsAll(['a', 'a.split.1', 'c', 'c.split.1']),
    );
    expect(draft.validate(), isEmpty);
  });

  test('explicit vertex tool splits perimeter and internal walls', () {
    final perimeter = FloorplanVisualDraftEditor.insertVertex(
      draft: rectangle(),
      wallId: 'a',
      point: const FloorPoint(.5, 0),
    );
    expect(perimeter.isSuccess, isTrue);
    expect(perimeter.draft!.room('room')!.wallIds, [
      'a',
      'a.split.1',
      'b',
      'c',
      'd',
    ]);

    final partitioned = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle(),
      roomId: 'room',
      start: const FloorPoint(.5, 0),
      end: const FloorPoint(.5, 1),
    ).draft!;
    final partition = partitioned.walls.singleWhere(
      (wall) => wall.id == 'room.internal.1',
    );
    final internal = FloorplanVisualDraftEditor.insertVertex(
      draft: partitioned,
      wallId: partition.id,
      point: const FloorPoint(.5, .5),
    );
    expect(internal.isSuccess, isTrue);
    expect(
      internal.draft!.walls.map((wall) => wall.id),
      containsAll(['room.internal.1', 'room.internal.1.split.1']),
    );
    expect(internal.draft!.rooms, hasLength(2));
    expect(internal.draft!.validate(), isEmpty);
  });

  test('partition reconstructs two rooms with one shared physical wall', () {
    final result = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle(),
      roomId: 'room',
      start: const FloorPoint(.5, 0),
      end: const FloorPoint(.5, 1),
    );

    expect(result.isSuccess, isTrue);
    final draft = result.draft!;
    expect(draft.rooms, hasLength(2));
    final shared = draft.walls.singleWhere(
      (wall) => wall.id == 'room.internal.1',
    );
    expect(shared.roomIds, hasLength(2));
    for (final room in draft.rooms) {
      expect(room.wallIds, contains(shared.id));
      expect(draft.contourForRoom(room.id), isNotNull);
    }
    expect(draft.validate(), isEmpty);

    final restored = FloorplanVisualDraft.fromJson(draft.toJson());
    expect(
      restored.rooms.map((room) => room.id),
      draft.rooms.map((room) => room.id),
    );
    expect(
      restored.walls.singleWhere((wall) => wall.id == shared.id).roomIds,
      shared.roomIds,
    );
    expect(restored.validate(), isEmpty);
  });

  test('second partition reconstructs three rooms and removal merges them', () {
    final first = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle(),
      roomId: 'room',
      start: const FloorPoint(.5, 0),
      end: const FloorPoint(.5, 1),
    ).draft!;
    final second = FloorplanVisualDraftEditor.addInternalWall(
      draft: first,
      roomId: 'room',
      start: const FloorPoint(0, .5),
      end: const FloorPoint(.5, .5),
    );

    expect(second.isSuccess, isTrue);
    final threeRooms = second.draft!;
    expect(threeRooms.rooms, hasLength(3));
    expect(threeRooms.validate(), isEmpty);
    for (final room in threeRooms.rooms) {
      final contour = threeRooms.contourForRoom(room.id);
      expect(contour, isNotNull);
      expect(polygonArea(contour!), greaterThan(0));
    }
    final horizontal = threeRooms.walls.singleWhere(
      (wall) => wall.id == 'room.internal.2',
    );
    expect(horizontal.roomIds, hasLength(2));

    final restored = FloorplanVisualDraft.fromJson(threeRooms.toJson());
    expect(
      restored.rooms.map((room) => room.id),
      threeRooms.rooms.map((room) => room.id),
    );
    expect(
      restored.rooms.map((room) => room.wallIds),
      threeRooms.rooms.map((room) => room.wallIds),
    );
    expect(restored.validate(), isEmpty);

    final removed = FloorplanVisualDraftEditor.removeInternalWall(
      draft: threeRooms,
      wallId: horizontal.id,
    );
    expect(removed.isSuccess, isTrue);
    expect(removed.draft!.rooms, hasLength(2));
    expect(
      removed.draft!.walls.any((wall) => wall.id == horizontal.id),
      isFalse,
    );
    expect(removed.draft!.validate(), isEmpty);
  });

  test('degree-three junction cannot be dissolved', () {
    final partitioned = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle(),
      roomId: 'room',
      start: const FloorPoint(.5, 0),
      end: const FloorPoint(.5, 1),
    ).draft!;
    final room = partitioned.rooms.firstWhere(
      (candidate) => candidate.wallIds.contains('a'),
    );
    final following = room.wallIds.firstWhere(
      (wallId) => wallId == 'a.split.1' || wallId == 'room.internal.1',
    );

    final result = FloorplanVisualDraftEditor.removeVertex(
      draft: partitioned,
      roomId: room.id,
      followingWallId: following,
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorCode, 'vertice_compartido');
    expect(partitioned.rooms, hasLength(2));
  });

  test('crossing partition creates one degree-four topology junction', () {
    final partitioned = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle(),
      roomId: 'room',
      start: const FloorPoint(.5, 0),
      end: const FloorPoint(.5, 1),
    ).draft!;
    final crossing = FloorplanVisualDraftEditor.addInternalWall(
      draft: partitioned,
      roomId: 'room',
      start: const FloorPoint(0, .5),
      end: const FloorPoint(1, .5),
    );

    expect(crossing.isSuccess, isTrue);
    final draft = crossing.draft!;
    expect(draft.rooms, hasLength(4));
    final incident = draft.walls.where(
      (wall) =>
          wall.start == const FloorPoint(.5, .5) ||
          wall.end == const FloorPoint(.5, .5),
    );
    expect(incident, hasLength(4));
    expect(draft.validate(), isEmpty);
  });

  test('crossing partition is atomic when it would cut an opening', () {
    final partitioned = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle(),
      roomId: 'room',
      start: const FloorPoint(.5, 0),
      end: const FloorPoint(.5, 1),
    ).draft!;
    final shared = partitioned.walls.singleWhere(
      (wall) => wall.roomIds.length == 2,
    );
    final protected = partitioned.withOpening(
      VisualOpeningDraft(
        id: 'window-on-partition',
        type: VisualOpeningType.window,
        wallId: shared.id,
        position: .5,
        normalizedWidth: .2,
        confidence: .9,
      ),
    );
    final before = protected.toJson();

    final crossing = FloorplanVisualDraftEditor.addInternalWall(
      draft: protected,
      roomId: 'room',
      start: const FloorPoint(0, .5),
      end: const FloorPoint(1, .5),
    );

    expect(crossing.isSuccess, isFalse);
    expect(crossing.errorCode, 'division_sobre_abertura');
    expect(protected.toJson(), before);
  });

  test('moving a degree-three junction changes only captured incident walls', () {
    final partitioned = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle(),
      roomId: 'room',
      start: const FloorPoint(.5, 0),
      end: const FloorPoint(.5, 1),
    ).draft!;
    const original = FloorPoint(.5, 0);
    const replacement = FloorPoint(.55, .1);
    final incidentIds = {
      for (final wall in partitioned.walls)
        if (wall.start == original || wall.end == original) wall.id,
    };
    final unrelated = {
      for (final wall in partitioned.walls)
        if (!incidentIds.contains(wall.id)) wall.id: wall.toJson(),
    };
    expect(incidentIds, hasLength(3));

    final moved = FloorplanVisualDraftEditor.moveJunction(
      draft: partitioned,
      originalPoint: original,
      incidentWallIds: incidentIds,
      point: replacement,
    );

    expect(moved.isSuccess, isTrue);
    final draft = moved.draft!;
    for (final wallId in incidentIds) {
      final wall = draft.walls.singleWhere((wall) => wall.id == wallId);
      expect(wall.start == replacement || wall.end == replacement, isTrue);
    }
    for (final entry in unrelated.entries) {
      expect(
        draft.walls.singleWhere((wall) => wall.id == entry.key).toJson(),
        entry.value,
      );
    }
    expect(draft.rooms, hasLength(2));
    expect(draft.validate(), isEmpty);
  });

  test('invalid junction move is rejected without mutating its source', () {
    final partitioned = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle(),
      roomId: 'room',
      start: const FloorPoint(.5, 0),
      end: const FloorPoint(.5, 1),
    ).draft!;
    const original = FloorPoint(.5, 0);
    final before = partitioned.toJson();
    final incidentIds = {
      for (final wall in partitioned.walls)
        if (wall.start == original || wall.end == original) wall.id,
    };

    final moved = FloorplanVisualDraftEditor.moveJunction(
      draft: partitioned,
      originalPoint: original,
      incidentWallIds: incidentIds,
      point: const FloorPoint(.5, 1),
    );

    expect(moved.isSuccess, isFalse);
    expect(partitioned.toJson(), before);
  });

  test('no-op room reconciliation preserves pentagon opening geometry', () {
    const points = [
      FloorPoint(.20, .20),
      FloorPoint(.70, .15),
      FloorPoint(.85, .50),
      FloorPoint(.60, .82),
      FloorPoint(.18, .70),
    ];
    const opening = VisualOpeningDraft(
      id: 'window-stable',
      type: VisualOpeningType.window,
      wallId: 'p0',
      position: .40,
      normalizedWidth: .20,
      confidence: .90,
      widthM: .80,
      heightM: 1.10,
      offsetFromWallStartM: .60,
      sillHeightM: .90,
    );
    final draft = FloorplanVisualDraft(
      walls: [
        VisualWallSegment(
          id: 'p0',
          start: points[0],
          end: points[1],
          roomIds: ['pentagon'],
        ),
        VisualWallSegment(
          id: 'p1',
          start: points[1],
          end: points[2],
          roomIds: ['pentagon'],
        ),
        VisualWallSegment(
          id: 'p2',
          start: points[2],
          end: points[3],
          roomIds: ['pentagon'],
        ),
        VisualWallSegment(
          id: 'p3',
          start: points[3],
          end: points[4],
          roomIds: ['pentagon'],
        ),
        VisualWallSegment(
          id: 'p4',
          start: points[4],
          end: points[0],
          roomIds: ['pentagon'],
        ),
      ],
      rooms: [
        VisualRoomRegion(
          id: 'pentagon',
          wallIds: ['p0', 'p1', 'p2', 'p3', 'p4'],
        ),
      ],
      openings: [opening],
    );

    final result = FloorplanVisualDraftEditor.reconcileRoomRegions(
      draft: draft,
    );

    expect(result.isSuccess, isTrue);
    final actual = result.draft!.opening(opening.id)!;
    expect(actual.toJson(), opening.toJson());
    final physicalWall = result.draft!.walls.singleWhere(
      (wall) => wall.id == 'p0',
    );
    expect(physicalWall.start, points[0]);
    expect(physicalWall.end, points[1]);
  });

  test('shared wall traversal never reverses physical opening geometry', () {
    final partitioned = FloorplanVisualDraftEditor.addInternalWall(
      draft: rectangle(),
      roomId: 'room',
      start: const FloorPoint(.5, 0),
      end: const FloorPoint(.5, 1),
    ).draft!;
    final shared = partitioned.walls.singleWhere(
      (wall) => wall.roomIds.length == 2,
    );
    const opening = VisualOpeningDraft(
      id: 'shared-window',
      type: VisualOpeningType.window,
      wallId: 'room.internal.1',
      position: .40,
      normalizedWidth: .20,
      confidence: .85,
    );
    final withOpening = partitioned.withOpening(opening);

    final result = FloorplanVisualDraftEditor.reconcileRoomRegions(
      draft: withOpening,
    );

    expect(result.isSuccess, isTrue);
    final reconciled = result.draft!;
    final physical = reconciled.walls.singleWhere(
      (wall) => wall.id == shared.id,
    );
    expect(physical.start, shared.start);
    expect(physical.end, shared.end);
    expect(reconciled.opening(opening.id)!.toJson(), opening.toJson());
    expect(reconciled.rooms, hasLength(2));
    for (final room in reconciled.rooms) {
      expect(room.wallIds, contains(shared.id));
      expect(reconciled.contourForRoom(room.id), isNotNull);
    }

    bool traverses(List<FloorPoint> contour, FloorPoint from, FloorPoint to) {
      for (var index = 0; index < contour.length; index++) {
        if (contour[index] == from &&
            contour[(index + 1) % contour.length] == to) {
          return true;
        }
      }
      return false;
    }

    final contours = [
      for (final room in reconciled.rooms) reconciled.contourForRoom(room.id)!,
    ];
    expect(
      contours.where((contour) => traverses(contour, shared.start, shared.end)),
      hasLength(1),
    );
    expect(
      contours.where((contour) => traverses(contour, shared.end, shared.start)),
      hasLength(1),
    );
  });
}
