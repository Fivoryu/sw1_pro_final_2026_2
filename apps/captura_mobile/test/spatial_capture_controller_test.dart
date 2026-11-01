import 'dart:convert';
import 'dart:io';

import 'package:captura_mobile/data/services/ar_capture_channel.dart';
import 'package:captura_mobile/data/services/capture_draft_store.dart';
import 'package:captura_mobile/data/services/photo_source.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:captura_mobile/domain/spatial_capture_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_ar_capture.dart';
import 'support/fake_scene_backend.dart';
import 'support/fake_staff_backend.dart';
import 'support/fake_photo_source.dart';
import 'support/in_memory_capture_draft_store.dart';

const FloorplanVisualDraft _threeRoomVisualDraft = FloorplanVisualDraft(
  walls: [
    VisualWallSegment(
      id: 'top-a',
      start: FloorPoint(.1, .2),
      end: FloorPoint(.366666, .2),
      roomIds: ['A1'],
    ),
    VisualWallSegment(
      id: 'partition-ab',
      start: FloorPoint(.366666, .2),
      end: FloorPoint(.366666, .8),
      roomIds: ['A1', 'A2'],
    ),
    VisualWallSegment(
      id: 'bottom-a',
      start: FloorPoint(.366666, .8),
      end: FloorPoint(.1, .8),
      roomIds: ['A1'],
    ),
    VisualWallSegment(
      id: 'left-a',
      start: FloorPoint(.1, .8),
      end: FloorPoint(.1, .2),
      roomIds: ['A1'],
    ),
    VisualWallSegment(
      id: 'top-b',
      start: FloorPoint(.366666, .2),
      end: FloorPoint(.633333, .2),
      roomIds: ['A2'],
    ),
    VisualWallSegment(
      id: 'partition-bc',
      start: FloorPoint(.633333, .2),
      end: FloorPoint(.633333, .8),
      roomIds: ['A2', 'A3'],
    ),
    VisualWallSegment(
      id: 'bottom-b',
      start: FloorPoint(.633333, .8),
      end: FloorPoint(.366666, .8),
      roomIds: ['A2'],
    ),
    VisualWallSegment(
      id: 'top-c',
      start: FloorPoint(.633333, .2),
      end: FloorPoint(.9, .2),
      roomIds: ['A3'],
    ),
    VisualWallSegment(
      id: 'right-c',
      start: FloorPoint(.9, .2),
      end: FloorPoint(.9, .8),
      roomIds: ['A3'],
    ),
    VisualWallSegment(
      id: 'bottom-c',
      start: FloorPoint(.9, .8),
      end: FloorPoint(.633333, .8),
      roomIds: ['A3'],
    ),
  ],
  rooms: [
    VisualRoomRegion(
      id: 'A1',
      name: 'Ambiente 1',
      wallIds: ['top-a', 'partition-ab', 'bottom-a', 'left-a'],
    ),
    VisualRoomRegion(
      id: 'A2',
      name: 'Ambiente 2',
      wallIds: ['top-b', 'partition-bc', 'bottom-b', 'partition-ab'],
    ),
    VisualRoomRegion(
      id: 'A3',
      name: 'Ambiente 3',
      wallIds: ['top-c', 'right-c', 'bottom-c', 'partition-bc'],
    ),
  ],
  openings: [
    VisualOpeningDraft(
      id: 'door-a2',
      type: VisualOpeningType.door,
      wallId: 'top-b',
      position: .5,
      normalizedWidth: .4,
      manuallyPlaced: true,
      widthM: .8,
      heightM: 2.1,
      offsetFromWallStartM: .6,
    ),
  ],
  measurements: [
    VisualWallMeasurementEvidence(
      id: 'top-b:length',
      wallId: 'top-b',
      meters: 2,
      provenance: 'user',
    ),
  ],
);

typedef Harness = ({
  SpatialCaptureController controller,
  FakeSceneBackend backend,
  FakeArCapture ar,
  CaptureDraftStore store,
  Directory root,
});

/// [CaptureDraftStore] that can fail writes, so tests can check what survives
/// an interrupted persistence.
class _FailingWriteStore implements CaptureDraftStore {
  _FailingWriteStore(this._inner);

  final CaptureDraftStore _inner;
  bool failWrites = false;

  @override
  Future<Map<String, Object?>?> read(String ownerId, String listingId) =>
      _inner.read(ownerId, listingId);

  @override
  Future<void> write(
    String ownerId,
    String listingId,
    Map<String, Object?> draft,
  ) async {
    if (failWrites) throw const FileSystemException('disk full');
    await _inner.write(ownerId, listingId, draft);
  }

  @override
  Future<void> delete(String ownerId, String listingId) =>
      _inner.delete(ownerId, listingId);

  @override
  Future<List<String>> listingIds(String ownerId) => _inner.listingIds(ownerId);

  @override
  Future<int> sizeBytes(String ownerId) => _inner.sizeBytes(ownerId);

  @override
  Future<String> saveTraceSource(
    String ownerId,
    String listingId,
    List<int> bytes,
    String contentType,
  ) => _inner.saveTraceSource(ownerId, listingId, bytes, contentType);

  @override
  Future<List<int>?> readTraceSource(
    String ownerId,
    String listingId,
    String sourceId,
  ) => _inner.readTraceSource(ownerId, listingId, sourceId);

  @override
  Future<void> deleteTraceSource(
    String ownerId,
    String listingId,
    String sourceId,
  ) => _inner.deleteTraceSource(ownerId, listingId, sourceId);

  @override
  Future<void> deleteTraceSources(String ownerId, String listingId) =>
      _inner.deleteTraceSources(ownerId, listingId);
}

Future<StaffSessionController> signedIn() async {
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

Future<Harness> build({
  FakeSceneBackend? backend,
  Directory? root,
  FakeArCapture? ar,
  PhotoSource? traceSource,
  CaptureDraftStore? store,
  http.Client? sceneClient,
}) async {
  final dir = root ?? await Directory.systemTemp.createTemp('spatial-');
  final scenes = backend ?? FakeSceneBackend();
  final capture = ar ?? FakeArCapture();
  final drafts = store ?? FileCaptureDraftStore(root: () async => dir);
  final controller = SpatialCaptureController(
    listingId: 'listing-1',
    session: await signedIn(),
    sceneApi: StaffSceneApi(
      baseUrl: 'https://api.example.test',
      client: sceneClient ?? scenes.client,
    ),
    store: drafts,
    ar: capture,
    traceSource: traceSource,
    now: () => DateTime.utc(2026, 10, 21, 12),
  );
  await controller.load();
  return (
    controller: controller,
    backend: scenes,
    ar: capture,
    store: drafts,
    root: dir,
  );
}

void main() {
  final roots = <Directory>[];

  Future<Harness> harness({
    FakeSceneBackend? backend,
    Directory? root,
    FakeArCapture? ar,
    PhotoSource? traceSource,
    CaptureDraftStore? store,
    http.Client? sceneClient,
  }) async {
    final built = await build(
      backend: backend,
      root: root,
      ar: ar,
      traceSource: traceSource,
      store: store,
      sceneClient: sceneClient,
    );
    roots.add(built.root);
    return built;
  }

  tearDown(() async {
    for (final root in roots) {
      if (await root.exists()) await root.delete(recursive: true);
    }
    roots.clear();
  });

  group('capture', () {
    test('adds a normalized room and keeps it across a restart', () async {
      final h = await harness();
      h.ar.results.add(rectangle(4, 3));

      final message = await h.controller.captureRoom('Estar');

      expect(message, isNull);
      expect(h.ar.names, ['Estar']);
      final room = h.controller.rooms.single;
      expect(room.name, 'Estar');
      expect(room.corners.first, const FloorPoint(0, 0));
      expect(room.height!.source, HeightSource.ceilingPlane);
      expect(h.controller.syncState, CaptureSyncState.pending);

      final reopened = await harness(root: h.root, backend: h.backend);
      expect(reopened.controller.rooms.single.corners, room.corners);
      expect(reopened.controller.syncState, CaptureSyncState.pending);
    });

    test(
      'accepts a wall-lines capture with one hit distance per point',
      () async {
        final h = await harness();
        h.ar.results.add(
          const ArCaptured({
            'outcome': 'captured',
            'corners': [
              {'x': 0.0, 'z': 0.0},
              {'x': 4.0, 'z': 0.0},
              {'x': 4.0, 'z': 3.0},
              {'x': 0.0, 'z': 3.0},
            ],
            'height': null,
            'boxes': <Object?>[],
            'metrics': {
              'durationMs': 30000,
              'trackingLossCount': 0,
              'depthSupported': true,
              'cornerHitDistances': [1.1, 1.2, 1.0, 1.3, 1.4, 1.2, 1.1, 1.0],
              'floorY': -1.3,
              'method': 'wall_lines',
            },
          }),
        );

        expect(await h.controller.captureRoom('Estar'), isNull);
        expect(h.controller.rooms.single.corners, hasLength(4));
      },
    );

    test(
      'a walkthrough becomes a proposed room the agent can review',
      () async {
        final h = await harness();
        h.ar.results.add(walkthrough());

        final message = await h.controller.captureRoom(
          'Estar',
          mode: CaptureMode.walkthrough,
        );

        expect(h.ar.modes, [CaptureMode.walkthrough]);
        expect(
          message,
          contains('Contorno propuesto con 4 paredes detectadas'),
        );
        final room = h.controller.rooms.single;
        expect(room.corners, hasLength(4));
        expect(polygonArea(room.corners), closeTo(12, 0.05));
        expect(
          room.acquisition.method,
          RoomAcquisitionMethod.arcoreWalkthrough,
        );
        expect(room.acquisition.arMetrics, isNotNull);
      },
    );

    test('a walkthrough with a missing wall flags the inferred side', () async {
      final h = await harness();
      h.ar.results.add(walkthrough(walls: 3));

      final message = await h.controller.captureRoom(
        'Estar',
        mode: CaptureMode.walkthrough,
      );

      expect(message, contains('1 lado inferido'));
      expect(h.controller.rooms.single.corners, hasLength(4));
    });

    test(
      'a walkthrough with too few walls adds nothing and explains why',
      () async {
        final h = await harness();
        h.ar.results.add(walkthrough(walls: 2));

        final message = await h.controller.captureRoom(
          'Estar',
          mode: CaptureMode.walkthrough,
        );

        expect(message, contains('Marcar paredes'));
        expect(h.controller.rooms, isEmpty);
      },
    );

    test('marks a room without measured height as assumed', () async {
      final h = await harness();
      h.ar.results.add(rectangle(4, 3, height: null));

      await h.controller.captureRoom('Estar');

      expect(h.controller.rooms.single.height!.source, HeightSource.assumed);
      expect(
        h.controller.preview!.warnings.map((w) => w.code),
        contains(SceneWarningCode.assumedHeight),
      );
    });

    test('leaves the draft untouched when the agent cancels', () async {
      final h = await harness();
      h.ar.results.add(const ArCaptureCancelled());

      expect(await h.controller.captureRoom('Estar'), isNull);
      expect(h.controller.rooms, isEmpty);
    });

    test('explains a failed capture without adding a room', () async {
      final h = await harness();
      h.ar.results.add(
        ArCaptureFailed(
          'camera_permission_denied',
          MethodChannelArCapture.messageFor('camera_permission_denied'),
        ),
      );

      final message = await h.controller.captureRoom('Estar');

      expect(message, contains('permiso de cámara'));
      expect(h.controller.rooms, isEmpty);
    });

    test('rejects a malformed native payload without adding a room', () async {
      final h = await harness();
      h.ar.results.add(
        const ArCaptured({
          'outcome': 'captured',
          'corners': [
            {'x': 0.0, 'z': 0.0},
          ],
          'metrics': {'durationMs': 1000},
        }),
      );

      expect(await h.controller.captureRoom('Estar'), contains('incompleta'));
      expect(h.controller.rooms, isEmpty);
    });

    test('does not open the camera on an unsupported phone', () async {
      final h = await harness();
      h.ar.available = ArAvailability.unsupported;

      final message = await h.controller.captureRoom('Estar');

      expect(message, contains('ARCore'));
      expect(h.ar.names, isEmpty);
    });

    test(
      'creates and persists a manual room without checking ARCore',
      () async {
        final h = await harness();
        h.ar.available = ArAvailability.unsupported;

        final message = await h.controller.createManualRectangularRoom(
          name: 'Dormitorio',
          length: 4.2,
          width: 3.7,
          height: 2.6,
        );

        expect(message, isNull);
        expect(h.ar.availabilityChecks, 0);
        expect(h.ar.names, isEmpty);
        final room = h.controller.rooms.single;
        expect(room.acquisition.method, RoomAcquisitionMethod.manual);
        expect(room.acquisition.arMetrics, isNull);
        expect(polygonArea(room.corners), closeTo(15.54, 1e-9));

        final reopened = await harness(root: h.root, backend: h.backend);
        expect(
          reopened.controller.rooms.single.acquisition.method,
          RoomAcquisitionMethod.manual,
        );
        expect(reopened.controller.preview!.document['version'], '2.0');
      },
    );

    test(
      'persists L and calibrated sketch rooms across fresh controllers',
      () async {
        final h = await harness();
        h.ar.available = ArAvailability.unsupported;
        expect(
          await h.controller.createManualLRoom(
            name: 'Cocina en L',
            totalWidth: 5,
            totalDepth: 4,
            recessWidth: 2,
            recessDepth: 1.5,
            height: 2.6,
            recess: RecessCorner.upperRight,
          ),
          isNull,
        );
        expect(
          await h.controller.createCalibratedManualSketchRoom(
            name: 'Estudio irregular',
            sketch: const [
              FloorPoint(10, 10),
              FloorPoint(210, 10),
              FloorPoint(240, 120),
              FloorPoint(120, 210),
              FloorPoint(10, 140),
            ],
            referenceEdge: 0,
            referenceMeters: 4,
            height: 2.7,
          ),
          isNull,
        );

        final reopened = await harness(root: h.root, backend: h.backend);
        final rooms = reopened.controller.rooms;
        expect(rooms, hasLength(2));
        expect(rooms.first.corners, hasLength(6));
        expect(polygonArea(rooms.first.corners), closeTo(17, 1e-9));
        expect(rooms.first.acquisition.method, RoomAcquisitionMethod.manual);
        expect(
          rooms.last.acquisition.method,
          RoomAcquisitionMethod.manualSketch,
        );
        expect(edgeLengths(rooms.last.corners).first, closeTo(4, 1e-9));
        expect(rooms.every((room) => room.metrics == null), isTrue);
        expect(reopened.controller.preview!.document['version'], '2.0');
        expect(h.ar.availabilityChecks, 0);
        expect(h.ar.names, isEmpty);
      },
    );

    test('new wall sketch starts pending and confirms independently', () async {
      final h = await harness();
      const sketch = [
        FloorPoint(0, 0),
        FloorPoint(4, 0),
        FloorPoint(4, 3),
        FloorPoint(0, 3),
      ];

      expect(
        await h.controller.createWallBasedManualSketchRoom(
          name: 'Croquis por paredes',
          sketch: sketch,
          height: 2.6,
        ),
        isNull,
      );
      final pending = h.controller.rooms.single;
      expect(pending.measurementMode, RoomMeasurementMode.wallConstraints);
      expect(pending.references, isEmpty);

      await h.controller.updateRoom(
        pending.copyWith(
          references: const [
            ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.1),
          ],
        ),
      );
      final partial = h.controller.rooms.single;
      expect(partial.references, hasLength(1));
      expect(partial.references.single.edgeIndex, 0);
      expect(hasCompleteWallMeasurements(partial), isFalse);
    });

    test(
      'persists floorplan opening proposals across controller restart',
      () async {
        final source = FakePhotoSource();
        final h = await harness(traceSource: source);
        final picked = await h.controller.pickFloorplanSource();

        expect(picked, isNotNull);
        expect(
          await h.controller.saveFloorplanTrace(
            name: 'Dormitorio plano',
            sourceId: picked!.sourceId,
            contentType: picked.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: const [
              FloorPoint(0.1, 0.2),
              FloorPoint(0.5, 0.2),
              FloorPoint(0.5, 0.6),
              FloorPoint(0.1, 0.6),
            ],
            openings: const [
              FloorplanTraceOpening(
                edgeIndex: 0,
                type: FloorplanTraceOpeningType.window,
                position: 0.40,
                normalizedWidth: 0.20,
                confidence: 0.90,
              ),
              FloorplanTraceOpening(
                edgeIndex: 1,
                type: FloorplanTraceOpeningType.window,
                position: 0.55,
                normalizedWidth: 0.18,
                confidence: 0.88,
              ),
              FloorplanTraceOpening(
                edgeIndex: 2,
                type: FloorplanTraceOpeningType.door,
                position: 0.50,
                normalizedWidth: 0.22,
                confidence: 0.95,
              ),
            ],
            height: 2.65,
          ),
          isNull,
        );

        final room = h.controller.rooms.single;
        final trace = h.controller.traceForRoom(room.id);
        expect(trace, isNotNull);
        expect(trace!.openings, hasLength(3));
        expect(room.openings, isEmpty);

        final reopened = await harness(root: h.root, backend: h.backend);
        final reopenedRoom = reopened.controller.rooms.single;
        final reopenedTrace = reopened.controller.traceForRoom(reopenedRoom.id);
        expect(reopenedTrace, isNotNull);
        expect(reopenedTrace!.openings, hasLength(3));
        expect(
          reopenedTrace.openings.where(
            (opening) => opening.type == FloorplanTraceOpeningType.window,
          ),
          hasLength(2),
        );
        expect(
          reopenedTrace.openings.where(
            (opening) => opening.type == FloorplanTraceOpeningType.door,
          ),
          hasLength(1),
        );

        final firstWindow = reopenedTrace.openings.firstWhere(
          (opening) =>
              opening.type == FloorplanTraceOpeningType.window &&
              opening.edgeIndex == 0,
        );
        expect(firstWindow.position, 0.40);
        expect(firstWindow.normalizedWidth, 0.20);
        expect(firstWindow.confidence, 0.90);

        final door = reopenedTrace.openings.singleWhere(
          (opening) => opening.type == FloorplanTraceOpeningType.door,
        );
        expect(door.edgeIndex, 2);
        expect(door.position, 0.50);
        expect(door.normalizedWidth, 0.22);
        expect(door.confidence, 0.95);
        expect(reopenedRoom.openings, isEmpty);
        expect(reopened.controller.preview!.document['openings'], isEmpty);
      },
    );

    test(
      'persists the visual draft identity graph across controller restart',
      () async {
        final source = FakePhotoSource();
        final h = await harness(traceSource: source);
        final picked = await h.controller.pickFloorplanSource();
        expect(picked, isNotNull);
        const draft = FloorplanVisualDraft(
          walls: [
            VisualWallSegment(
              id: 'a',
              start: FloorPoint(.1, .2),
              end: FloorPoint(.5, .2),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'b',
              start: FloorPoint(.5, .2),
              end: FloorPoint(.5, .6),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'c',
              start: FloorPoint(.5, .6),
              end: FloorPoint(.1, .6),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'd',
              start: FloorPoint(.1, .6),
              end: FloorPoint(.1, .2),
              roomIds: ['temporary'],
            ),
          ],
          rooms: [
            VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd']),
          ],
        );

        expect(
          await h.controller.saveFloorplanTrace(
            name: 'Documento visual',
            sourceId: picked!.sourceId,
            contentType: picked.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: draft.contourForRoom('temporary')!,
            visualDraft: draft,
            height: 2.65,
          ),
          isNull,
        );

        final saved = h.controller.traceForRoom(h.controller.rooms.single.id)!;
        final savedDraft = saved.visualDraft!;
        expect(savedDraft.validate(), isEmpty);
        expect(savedDraft.walls.map((wall) => wall.id), ['a', 'b', 'c', 'd']);
        expect(savedDraft.rooms.single.id, h.controller.rooms.single.id);

        final reopened = await harness(root: h.root, backend: h.backend);
        final restored = reopened.controller.traceForRoom(
          reopened.controller.rooms.single.id,
        )!;
        expect(restored.visualDraft, isNotNull);
        expect(restored.visualDraft!.validate(), isEmpty);
        expect(
          restored.visualDraft!.walls.map((wall) => wall.id),
          savedDraft.walls.map((wall) => wall.id),
        );
        expect(
          restored.visualDraft!.rooms.single.wallIds,
          savedDraft.rooms.single.wallIds,
        );
        expect(
          restored.vertices,
          savedDraft.contourForRoom(savedDraft.rooms.single.id),
        );
      },
    );

    test(
      'persists multi-room topology and shared walls across controller restart',
      () async {
        final source = FakePhotoSource();
        final h = await harness(traceSource: source);
        final picked = await h.controller.pickFloorplanSource();
        expect(picked, isNotNull);
        const base = FloorplanVisualDraft(
          walls: [
            VisualWallSegment(
              id: 'a',
              start: FloorPoint(.1, .2),
              end: FloorPoint(.9, .2),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'b',
              start: FloorPoint(.9, .2),
              end: FloorPoint(.9, .8),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'c',
              start: FloorPoint(.9, .8),
              end: FloorPoint(.1, .8),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'd',
              start: FloorPoint(.1, .8),
              end: FloorPoint(.1, .2),
              roomIds: ['temporary'],
            ),
          ],
          rooms: [
            VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd']),
          ],
        );
        final partitioned = FloorplanVisualDraftEditor.addInternalWall(
          draft: base,
          roomId: 'temporary',
          start: const FloorPoint(.5, .2),
          end: const FloorPoint(.5, .8),
        );
        expect(partitioned.isSuccess, isTrue);
        final draft = partitioned.draft!;
        final displayWallOrder = draft.walls
            .map((wall) => wall.id)
            .toList(growable: false);
        final sharedId = draft.walls
            .singleWhere((wall) => wall.roomIds.length == 2)
            .id;

        expect(
          await h.controller.saveFloorplanTrace(
            name: 'Casa con ambientes',
            sourceId: picked!.sourceId,
            contentType: picked.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: draft.contourForRoom('temporary')!,
            visualDraft: draft,
            height: 2.65,
          ),
          isNull,
        );

        expect(h.controller.rooms, hasLength(2));
        final firstProjectionIds = {
          for (final room in h.controller.rooms) room.id,
        };
        final firstVisualRoomIds = {
          for (final room in h.controller.rooms)
            h.controller.traceForRoom(room.id)!.visualRoomId!,
        };
        expect(firstVisualRoomIds, draft.rooms.map((room) => room.id).toSet());

        final raw = (await h.store.read(h.controller.ownerId!, 'listing-1'))!;
        final rawTraces = (raw['traces']! as List).cast<Map>();
        expect(
          rawTraces.where((trace) => trace['visualDraft'] != null),
          hasLength(1),
          reason: 'El documento canónico debe persistirse una sola vez.',
        );

        final reopened = await harness(root: h.root, backend: h.backend);
        expect(reopened.controller.rooms, hasLength(2));
        expect({
          for (final room in reopened.controller.rooms) room.id,
        }, firstProjectionIds);
        final restored = reopened.controller
            .traceForRoom(reopened.controller.rooms.first.id)!
            .visualDraft!;
        for (final room in reopened.controller.rooms) {
          final trace = reopened.controller.traceForRoom(room.id)!;
          expect(trace.visualDraft, isNotNull);
          expect(trace.visualDraft!.toJson(), restored.toJson());
        }
        expect(restored.rooms, hasLength(2));
        expect(
          restored.walls.map((wall) => wall.id),
          displayWallOrder,
          reason: 'La numeración visual P conserva el orden físico persistido.',
        );
        expect(
          restored.walls.where((wall) => wall.id == sharedId),
          hasLength(1),
        );
        expect(
          restored.walls.singleWhere((wall) => wall.id == sharedId).roomIds,
          hasLength(2),
        );
        for (final room in restored.rooms) {
          expect(room.wallIds, contains(sharedId));
          expect(restored.contourForRoom(room.id), isNotNull);
        }
        expect(restored.validate(), isEmpty);
      },
    );

    test(
      'projects three visual rooms once, preserves preview topology and stable ids',
      () async {
        final source = FakePhotoSource();
        final h = await harness(traceSource: source);
        final picked = await h.controller.pickFloorplanSource();

        expect(_threeRoomVisualDraft.validate(), isEmpty);
        expect(
          await h.controller.saveFloorplanTrace(
            name: 'Plano de tres ambientes',
            sourceId: picked!.sourceId,
            contentType: picked.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: _threeRoomVisualDraft.contourForRoom('A1')!,
            visualDraft: _threeRoomVisualDraft,
            height: 2.65,
          ),
          isNull,
        );

        expect(h.controller.rooms, hasLength(3));
        final firstIds = [for (final room in h.controller.rooms) room.id];
        expect(
          {
            for (final room in h.controller.rooms)
              h.controller.traceForRoom(room.id)!.visualRoomId!,
          },
          {'A1', 'A2', 'A3'},
        );

        final raw = (await h.store.read(h.controller.ownerId!, 'listing-1'))!;
        final traces = (raw['traces']! as List).cast<Map>();
        expect(
          traces.where((trace) => trace['visualDraft'] != null),
          hasLength(1),
        );

        final preview = h.controller.preview!;
        final sceneRooms = (preview.document['rooms']! as List).cast<Map>();
        expect(sceneRooms, hasLength(3));
        final sceneWalls = {
          for (final value in (preview.document['walls']! as List).cast<Map>())
            value['id']! as String: value,
        };
        double roomCenterX(Map room) {
          final points = <double>[];
          for (final wallId in (room['wallIds']! as List).cast<String>()) {
            final wall = sceneWalls[wallId]!;
            points.add(((wall['start']! as Map)['x']! as num).toDouble());
            points.add(((wall['end']! as Map)['x']! as num).toDouble());
          }
          return points.reduce((a, b) => a + b) / points.length;
        }

        final centers = [for (final room in sceneRooms) roomCenterX(room)];
        expect(centers.toSet(), hasLength(3));
        expect(
          centers.reduce((a, b) => a < b ? a : b),
          lessThan(centers.reduce((a, b) => a > b ? a : b)),
        );
        final second = h.controller.rooms[1];
        final secondTrace = h.controller.traceForRoom(second.id)!;
        expect(
          await h.controller.saveFloorplanTrace(
            roomId: second.id,
            name: second.name,
            sourceId: secondTrace.sourceId,
            contentType: secondTrace.contentType,
            imageWidth: secondTrace.imageWidth,
            imageHeight: secondTrace.imageHeight,
            normalizedTrace: secondTrace.vertices,
            visualDraft: secondTrace.visualDraft,
            height: second.height?.value ?? 2.65,
          ),
          isNull,
        );
        expect(h.controller.rooms, hasLength(3));
        expect([for (final room in h.controller.rooms) room.id], firstIds);

        final reopened = await harness(root: h.root, backend: h.backend);
        expect(reopened.controller.rooms, hasLength(3));
        expect([
          for (final room in reopened.controller.rooms) room.id,
        ], firstIds);
        for (final room in reopened.controller.rooms) {
          expect(
            reopened.controller.traceForRoom(room.id)!.visualDraft!.rooms,
            hasLength(3),
          );
        }
      },
    );

    test(
      'multiroom resave preserves external connection until its room disappears',
      () async {
        final source = FakePhotoSource();
        final h = await harness(traceSource: source);
        final picked = await h.controller.pickFloorplanSource();
        expect(
          await h.controller.saveFloorplanTrace(
            name: 'Plano de tres ambientes',
            sourceId: picked!.sourceId,
            contentType: picked.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: _threeRoomVisualDraft.contourForRoom('A1')!,
            visualDraft: _threeRoomVisualDraft,
            height: 2.65,
          ),
          isNull,
        );

        final middle = h.controller.rooms.singleWhere(
          (room) => h.controller.traceForRoom(room.id)!.visualRoomId == 'A2',
        );
        expect(
          middle.openings.map((opening) => opening.id),
          contains('door-a2'),
        );

        await h.controller.createManualRectangularRoom(
          name: 'Exterior',
          length: 3,
          width: 3,
          height: 2.65,
        );
        final external = h.controller.rooms.last;
        await h.controller.updateRoom(
          external.copyWith(
            openings: const [
              RoomOpening(
                id: 'door-external',
                edgeIndex: 0,
                position: .5,
                width: .8,
                height: 2.1,
                type: OpeningType.door,
              ),
            ],
          ),
        );
        expect(
          await h.controller.connect(
            roomA: middle.id,
            openingA: 'door-a2',
            roomB: external.id,
            openingB: 'door-external',
          ),
          isNull,
        );
        expect(h.controller.connections, hasLength(1));

        final trace = h.controller.traceForRoom(middle.id)!;
        expect(
          await h.controller.saveFloorplanTrace(
            roomId: middle.id,
            name: middle.name,
            sourceId: trace.sourceId,
            contentType: trace.contentType,
            imageWidth: trace.imageWidth,
            imageHeight: trace.imageHeight,
            normalizedTrace: trace.vertices,
            visualDraft: trace.visualDraft,
            height: middle.height?.value ?? 2.65,
          ),
          isNull,
        );
        expect(h.controller.connections, hasLength(1));
        expect(h.controller.connections.single.roomA, middle.id);
        expect(h.controller.connections.single.roomB, external.id);

        await h.controller.removeRoom(middle.id);
        expect(h.controller.rooms, hasLength(3));
        expect(h.controller.connections, isEmpty);
      },
    );

    test(
      'deleting canonical owner transfers the shared document without orphan traces',
      () async {
        final source = FakePhotoSource();
        final h = await harness(traceSource: source);
        final picked = await h.controller.pickFloorplanSource();
        expect(
          await h.controller.saveFloorplanTrace(
            name: 'Plano de tres ambientes',
            sourceId: picked!.sourceId,
            contentType: picked.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: _threeRoomVisualDraft.contourForRoom('A1')!,
            visualDraft: _threeRoomVisualDraft,
            height: 2.65,
          ),
          isNull,
        );

        final before = (await h.store.read(
          h.controller.ownerId!,
          'listing-1',
        ))!;
        final beforeTraces = (before['traces']! as List).cast<Map>();
        final ownerRaw = beforeTraces.singleWhere(
          (trace) => trace['visualDraft'] != null,
        );
        final ownerRoomId = ownerRaw['roomId']! as String;
        final sourceId = ownerRaw['sourceId']! as String;

        await h.controller.removeRoom(ownerRoomId);

        expect(h.controller.rooms, hasLength(2));
        for (final room in h.controller.rooms) {
          final trace = h.controller.traceForRoom(room.id)!;
          expect(trace.visualDraft, isNotNull);
          expect(trace.visualDraft!.rooms, hasLength(2));
        }
        expect(
          await h.controller.floorplanSourceBytes(sourceId),
          isNotNull,
          reason:
              'La imagen sigue referenciada por las proyecciones restantes.',
        );

        final after = (await h.store.read(h.controller.ownerId!, 'listing-1'))!;
        final afterTraces = (after['traces']! as List).cast<Map>();
        expect(
          afterTraces.where((trace) => trace['visualDraft'] != null),
          hasLength(1),
        );
        final survivingIds = {
          for (final trace in afterTraces) trace['roomId']! as String,
        };
        for (final trace in afterTraces) {
          final owner = trace['documentOwnerRoomId'] as String?;
          if (owner != null) expect(survivingIds, contains(owner));
        }
      },
    );

    test(
      'V3 wall dimensions survive complete controller reconstruction',
      () async {
        const draft = FloorplanVisualDraft(
          walls: [
            VisualWallSegment(
              id: 'a',
              start: FloorPoint(.1, .2),
              end: FloorPoint(.5, .2),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'b',
              start: FloorPoint(.5, .2),
              end: FloorPoint(.5, .575),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'c',
              start: FloorPoint(.5, .575),
              end: FloorPoint(.1, .575),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'd',
              start: FloorPoint(.1, .575),
              end: FloorPoint(.1, .2),
              roomIds: ['temporary'],
            ),
          ],
          rooms: [
            VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd']),
          ],
          openings: [
            VisualOpeningDraft(
              id: 'window-a',
              type: VisualOpeningType.window,
              wallId: 'a',
              position: .3,
              normalizedWidth: .15,
              widthM: 1.2,
              heightM: 1.1,
              offsetFromWallStartM: .4,
              sillHeightM: .8,
            ),
            VisualOpeningDraft(
              id: 'door-b',
              type: VisualOpeningType.door,
              wallId: 'b',
              position: .5,
              normalizedWidth: .2,
              widthM: .9,
              heightM: 2,
              offsetFromWallStartM: .3,
            ),
          ],
          measurements: [
            VisualWallMeasurementEvidence(
              id: 'a:length',
              wallId: 'a',
              meters: 4,
              provenance: 'user',
            ),
            VisualWallMeasurementEvidence(
              id: 'a:height',
              wallId: 'a',
              meters: 2.4,
              provenance: 'user',
              dimension: VisualWallMeasurementDimension.height,
            ),
            VisualWallMeasurementEvidence(
              id: 'b:length',
              wallId: 'b',
              meters: 3,
              provenance: 'user',
            ),
            VisualWallMeasurementEvidence(
              id: 'b:height',
              wallId: 'b',
              meters: 2.8,
              provenance: 'user',
              dimension: VisualWallMeasurementDimension.height,
            ),
            VisualWallMeasurementEvidence(
              id: 'c:length',
              wallId: 'c',
              meters: 4,
              provenance: 'user',
            ),
            VisualWallMeasurementEvidence(
              id: 'c:height',
              wallId: 'c',
              meters: 2.5,
              provenance: 'user',
              dimension: VisualWallMeasurementDimension.height,
            ),
            VisualWallMeasurementEvidence(
              id: 'd:length',
              wallId: 'd',
              meters: 3,
              provenance: 'user',
            ),
            VisualWallMeasurementEvidence(
              id: 'd:height',
              wallId: 'd',
              meters: 2.6,
              provenance: 'user',
              dimension: VisualWallMeasurementDimension.height,
            ),
          ],
        );
        final store = InMemoryCaptureDraftStore();
        final first = await harness(
          store: store,
          traceSource: FakePhotoSource(),
        );
        final source = await first.controller.pickFloorplanSource();
        expect(source, isNotNull);
        expect(
          await first.controller.saveFloorplanTrace(
            name: 'Dimensiones V3',
            sourceId: source!.sourceId,
            contentType: source.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: draft.contourForRoom('temporary')!,
            visualDraft: draft,
          ),
          isNull,
        );
        final firstRoomId = first.controller.rooms.single.id;
        first.controller.dispose();

        final second = await harness(store: store);
        final secondRoom = second.controller.rooms.single;
        final restored = second.controller
            .traceForRoom(secondRoom.id)!
            .visualDraft!;
        expect(secondRoom.id, firstRoomId);
        expect(secondRoom.height, isNull);
        expect(secondRoom.wallDimensions, hasLength(4));
        expect(secondRoom.wallDimensions[0].wallId, 'a');
        expect(secondRoom.wallDimensions[0].lengthM, 4);
        expect(secondRoom.wallDimensions[0].heightM, 2.4);
        expect(secondRoom.openings.map((opening) => opening.id), [
          'window-a',
          'door-b',
        ]);
        expect(secondRoom.openings[0].wallId, 'a');
        expect(secondRoom.openings[0].explicitSillHeight, .8);
        expect(secondRoom.openings[1].wallId, 'b');
        expect(secondRoom.openings[1].sillHeight, 0);
        final scene = buildSceneDocument(second.controller.capture);
        final sceneWalls = (scene['walls']! as List)
            .cast<Map<String, Object?>>();
        expect(sceneWalls.map((wall) => wall['height']), [2.4, 2.8, 2.5, 2.6]);
        final sceneOpenings = (scene['openings']! as List)
            .cast<Map<String, Object?>>();
        expect(
          sceneOpenings.firstWhere((opening) => opening['id'] == 'window-a'),
          allOf(containsPair('wallId', 'a'), containsPair('sillHeight', .8)),
        );
        expect(restored.rooms.single.wallIds, ['a', 'b', 'c', 'd']);
        expect(restored.wallLength('a')!.meters, 4);
        expect(restored.wallHeight('a')!.meters, 2.4);
        expect(restored.wallLength('b')!.meters, 3);
        expect(restored.wallHeight('b')!.meters, 2.8);
        expect(
          restored.wallHeight('a')!.dimension,
          VisualWallMeasurementDimension.height,
        );
        expect(
          restored.wallHeight('b')!.dimension,
          VisualWallMeasurementDimension.height,
        );
        expect(restored.wallHeight('a')!.provenance, 'user');
        expect(restored.wallHeight('a')!.requiresReview, isFalse);
        expect(restored.wallHeight('b')!.provenance, 'user');
        expect(restored.wallHeight('b')!.requiresReview, isFalse);
        expect(restored.measurements, hasLength(8));
        expect(
          restored.measurements.map((value) => value.id).toSet(),
          hasLength(8),
        );
        expect(restored.openings, hasLength(2));
        expect(restored.opening('window-a')!.wallId, 'a');
        expect(restored.opening('window-a')!.widthM, 1.2);
        expect(restored.opening('window-a')!.heightM, 1.1);
        expect(restored.opening('window-a')!.offsetFromWallStartM, .4);
        expect(restored.opening('window-a')!.sillHeightM, .8);
        expect(restored.opening('door-b')!.wallId, 'b');
        expect(restored.opening('door-b')!.widthM, .9);
        expect(restored.opening('door-b')!.heightM, 2);
        expect(restored.opening('door-b')!.offsetFromWallStartM, .3);

        final updated = restored.withMeasurement(
          restored.wallHeight('b')!.copyWith(meters: 2.9),
        );
        final trace = second.controller.traceForRoom(secondRoom.id)!;
        expect(
          await second.controller.saveFloorplanTrace(
            roomId: secondRoom.id,
            name: secondRoom.name,
            sourceId: trace.sourceId,
            contentType: trace.contentType,
            imageWidth: trace.imageWidth,
            imageHeight: trace.imageHeight,
            normalizedTrace: trace.vertices,
            visualDraft: updated,
          ),
          isNull,
        );
        second.controller.dispose();

        final third = await harness(store: store);
        final finalRoom = third.controller.rooms.single;
        final finalDraft = third.controller
            .traceForRoom(finalRoom.id)!
            .visualDraft!;
        expect(finalDraft.rooms.single.wallIds, ['a', 'b', 'c', 'd']);
        expect(finalDraft.wallLength('a')!.meters, 4);
        expect(finalDraft.wallHeight('a')!.meters, 2.4);
        expect(finalDraft.wallLength('b')!.meters, 3);
        expect(finalDraft.wallHeight('b')!.meters, 2.9);
        expect(
          finalDraft.wallHeight('b')!.dimension,
          VisualWallMeasurementDimension.height,
        );
        expect(finalDraft.wallHeight('b')!.provenance, 'user');
        expect(finalDraft.wallHeight('b')!.requiresReview, isFalse);
        expect(finalRoom.height, isNull);
        expect(finalRoom.wallDimensions, hasLength(4));
        expect(finalRoom.wallDimensions[1].heightM, 2.9);
        expect(finalDraft.measurements, hasLength(8));
        expect(
          finalDraft.measurements.map((value) => value.id).toSet(),
          hasLength(8),
        );
        expect(finalDraft.openings, hasLength(2));
        expect(finalDraft.opening('window-a')!.wallId, 'a');
        expect(finalDraft.opening('window-a')!.widthM, 1.2);
        expect(finalDraft.opening('door-b')!.wallId, 'b');
        expect(finalDraft.opening('door-b')!.heightM, 2);
      },
    );

    test(
      'pending evidence stays visual and only confirmation reaches canonical dimensions',
      () async {
        const walls = [
          VisualWallSegment(
            id: 'a',
            start: FloorPoint(.1, .2),
            end: FloorPoint(.5, .2),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'b',
            start: FloorPoint(.5, .2),
            end: FloorPoint(.5, .6),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'c',
            start: FloorPoint(.5, .6),
            end: FloorPoint(.1, .6),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'd',
            start: FloorPoint(.1, .6),
            end: FloorPoint(.1, .2),
            roomIds: ['temporary'],
          ),
        ];
        final pending = FloorplanVisualDraft(
          walls: walls,
          rooms: const [
            VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd']),
          ],
          measurements: [
            for (final wall in walls) ...[
              VisualWallMeasurementEvidence(
                id: '${wall.id}:length',
                wallId: wall.id,
                meters: 4,
                provenance: 'ai_detected',
                requiresReview: true,
              ),
              VisualWallMeasurementEvidence(
                id: '${wall.id}:height',
                wallId: wall.id,
                meters: 2.4,
                provenance: 'ai_detected',
                requiresReview: true,
                dimension: VisualWallMeasurementDimension.height,
              ),
            ],
          ],
        );
        final h = await harness(traceSource: FakePhotoSource());
        final source = await h.controller.pickFloorplanSource();

        expect(
          await h.controller.saveFloorplanTrace(
            name: 'Pendiente',
            sourceId: source!.sourceId,
            contentType: source.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: pending.contourForRoom('temporary')!,
            visualDraft: pending,
            height: 2.6,
          ),
          isNull,
        );
        final pendingRoom = h.controller.rooms.single;
        expect(pendingRoom.wallDimensions, isEmpty);
        expect(pendingRoom.height!.value, 2.6);
        final roomId = pendingRoom.id;
        final pendingTrace = h.controller.traceForRoom(roomId)!;
        expect(
          pendingTrace.visualDraft!.measurements.every(
            (measurement) => measurement.requiresReview,
          ),
          isTrue,
        );

        final confirmed = pending.copyWith(
          measurements: [
            for (final measurement in pending.measurements)
              measurement.copyWith(requiresReview: false),
          ],
        );
        expect(
          await h.controller.saveFloorplanTrace(
            roomId: roomId,
            name: 'Confirmado',
            sourceId: pendingTrace.sourceId,
            contentType: pendingTrace.contentType,
            imageWidth: pendingTrace.imageWidth,
            imageHeight: pendingTrace.imageHeight,
            normalizedTrace: confirmed.contourForRoom('temporary')!,
            visualDraft: confirmed,
          ),
          isNull,
        );
        final confirmedRoom = h.controller.rooms.single;
        expect(confirmedRoom.height, isNull);
        expect(confirmedRoom.wallDimensions, hasLength(4));
        expect(
          confirmedRoom.wallDimensions.map((wall) => wall.lengthM),
          everyElement(4),
        );
        expect(
          h.controller
              .traceForRoom(roomId)!
              .visualDraft!
              .measurements
              .every((measurement) => !measurement.requiresReview),
          isTrue,
        );
      },
    );

    test(
      'derives compatibility projections from the visual document',
      () async {
        final source = FakePhotoSource();
        final h = await harness(traceSource: source);
        final picked = await h.controller.pickFloorplanSource();
        const draft = FloorplanVisualDraft(
          walls: [
            VisualWallSegment(
              id: 'a',
              start: FloorPoint(.1, .2),
              end: FloorPoint(.5, .2),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'b',
              start: FloorPoint(.5, .2),
              end: FloorPoint(.5, .6),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'c',
              start: FloorPoint(.5, .6),
              end: FloorPoint(.1, .6),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'd',
              start: FloorPoint(.1, .6),
              end: FloorPoint(.1, .2),
              roomIds: ['temporary'],
            ),
          ],
          rooms: [
            VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd']),
          ],
        );

        expect(
          await h.controller.saveFloorplanTrace(
            name: 'Documento visual',
            sourceId: picked!.sourceId,
            contentType: picked.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: draft.contourForRoom('temporary')!,
            visualDraft: draft,
            measurements: const [
              ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.2),
            ],
            openings: const [
              FloorplanTraceOpening(
                edgeIndex: 2,
                type: FloorplanTraceOpeningType.window,
                position: .5,
                normalizedWidth: .2,
                confidence: .8,
              ),
            ],
            height: 2.6,
          ),
          isNull,
        );

        final room = h.controller.rooms.single;
        final trace = h.controller.traceForRoom(room.id)!;
        final document = trace.visualDraft!;
        expect(document.validate(), isEmpty);
        expect(document.measurements, hasLength(1));
        expect(document.measurements.single.wallId, 'a');
        expect(document.measurements.single.provenance, 'user');
        expect(document.openings.single.wallId, 'c');
        expect(trace.vertices, document.contourForRoom(room.id));
        expect(trace.openings.single.edgeIndex, 2);
        expect(trace.openings.single.confidence, .8);
        expect(room.references, hasLength(4));
        expect(room.references.first.referenceMeters, 4.2);
        expect(
          room.references.first.provenance,
          WallMeasurementProvenance.user,
        );
        expect(
          room.references[1].provenance,
          anyOf(
            WallMeasurementProvenance.derivedScale,
            WallMeasurementProvenance.derivedGeometry,
          ),
        );
      },
    );

    test('save, reopen and save is idempotent', () async {
      final source = FakePhotoSource();
      final h = await harness(traceSource: source);
      final picked = await h.controller.pickFloorplanSource();
      const draft = FloorplanVisualDraft(
        walls: [
          VisualWallSegment(
            id: 'a',
            start: FloorPoint(.1, .2),
            end: FloorPoint(.5, .2),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'b',
            start: FloorPoint(.5, .2),
            end: FloorPoint(.5, .6),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'c',
            start: FloorPoint(.5, .6),
            end: FloorPoint(.1, .6),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'd',
            start: FloorPoint(.1, .6),
            end: FloorPoint(.1, .2),
            roomIds: ['temporary'],
          ),
        ],
        rooms: [
          VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd']),
        ],
      );
      expect(
        await h.controller.saveFloorplanTrace(
          name: 'Documento visual',
          sourceId: picked!.sourceId,
          contentType: picked.contentType,
          imageWidth: 1000,
          imageHeight: 800,
          normalizedTrace: draft.contourForRoom('temporary')!,
          visualDraft: draft,
          measurements: const [
            ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.2),
          ],
          openings: const [
            FloorplanTraceOpening(
              edgeIndex: 2,
              type: FloorplanTraceOpeningType.window,
              position: .5,
              normalizedWidth: .2,
              confidence: .8,
            ),
          ],
          height: 2.6,
        ),
        isNull,
      );
      final storedJson = h.controller
          .traceForRoom(h.controller.rooms.single.id)!
          .toJson();
      final storedReferences = h.controller.rooms.single.references
          .map((measurement) => measurement.referenceMeters)
          .toList();

      final reopened = await harness(
        root: h.root,
        backend: h.backend,
        store: h.store,
      );
      final room = reopened.controller.rooms.single;
      final trace = reopened.controller.traceForRoom(room.id)!;
      expect(trace.visualDraft, isNotNull);
      expect(
        await reopened.controller.saveFloorplanTrace(
          roomId: room.id,
          name: room.name,
          sourceId: trace.sourceId,
          contentType: trace.contentType,
          imageWidth: trace.imageWidth,
          imageHeight: trace.imageHeight,
          normalizedTrace: trace.vertices,
          visualDraft: trace.visualDraft,
          height: room.height!.value,
        ),
        isNull,
      );

      final resaved = reopened.controller.traceForRoom(room.id)!;
      expect(resaved.toJson(), storedJson);
      expect(
        reopened.controller.rooms.single.references
            .map((measurement) => measurement.referenceMeters)
            .toList(),
        storedReferences,
      );
    });

    test('repeated saves never duplicate document evidence', () async {
      final source = FakePhotoSource();
      final h = await harness(traceSource: source);
      final picked = await h.controller.pickFloorplanSource();
      const draft = FloorplanVisualDraft(
        walls: [
          VisualWallSegment(
            id: 'a',
            start: FloorPoint(.1, .2),
            end: FloorPoint(.5, .2),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'b',
            start: FloorPoint(.5, .2),
            end: FloorPoint(.5, .6),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'c',
            start: FloorPoint(.5, .6),
            end: FloorPoint(.1, .6),
            roomIds: ['temporary'],
          ),
          VisualWallSegment(
            id: 'd',
            start: FloorPoint(.1, .6),
            end: FloorPoint(.1, .2),
            roomIds: ['temporary'],
          ),
        ],
        rooms: [
          VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd']),
        ],
      );
      Future<String?> save({String? roomId}) => h.controller.saveFloorplanTrace(
        roomId: roomId,
        name: 'Documento visual',
        sourceId: picked!.sourceId,
        contentType: picked.contentType,
        imageWidth: 1000,
        imageHeight: 800,
        normalizedTrace: draft.contourForRoom('temporary')!,
        visualDraft: draft,
        measurements: const [
          ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.2),
        ],
        openings: const [
          FloorplanTraceOpening(
            edgeIndex: 2,
            type: FloorplanTraceOpeningType.window,
            position: .5,
            normalizedWidth: .2,
            confidence: .8,
          ),
        ],
        height: 2.6,
      );

      expect(await save(), isNull);
      expect(await save(roomId: h.controller.rooms.single.id), isNull);

      final room = h.controller.rooms.single;
      final trace = h.controller.traceForRoom(room.id)!;
      expect(trace.visualDraft!.measurements, hasLength(1));
      expect(trace.visualDraft!.openings, hasLength(1));
      expect(trace.openings, hasLength(1));
      expect(room.references, hasLength(4));
    });

    test(
      'a damaged stored document is preserved and never overwritten',
      () async {
        final source = FakePhotoSource();
        final h = await harness(traceSource: source);
        final picked = await h.controller.pickFloorplanSource();
        const draft = FloorplanVisualDraft(
          walls: [
            VisualWallSegment(
              id: 'a',
              start: FloorPoint(.1, .2),
              end: FloorPoint(.5, .2),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'b',
              start: FloorPoint(.5, .2),
              end: FloorPoint(.5, .6),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'c',
              start: FloorPoint(.5, .6),
              end: FloorPoint(.1, .6),
              roomIds: ['temporary'],
            ),
            VisualWallSegment(
              id: 'd',
              start: FloorPoint(.1, .6),
              end: FloorPoint(.1, .2),
              roomIds: ['temporary'],
            ),
          ],
          rooms: [
            VisualRoomRegion(id: 'temporary', wallIds: ['a', 'b', 'c', 'd']),
          ],
        );
        expect(
          await h.controller.saveFloorplanTrace(
            name: 'Documento visual',
            sourceId: picked!.sourceId,
            contentType: picked.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: draft.contourForRoom('temporary')!,
            visualDraft: draft,
            height: 2.6,
          ),
          isNull,
        );

        // Simulate a persisted document written by a broken build.
        final ownerId = h.controller.ownerId!;
        final raw = (await h.store.read(ownerId, 'listing-1'))!;
        final traces = (raw['traces']! as List).cast<Map<String, Object?>>();
        traces.single['visualDraft'] = {'version': 2, 'walls': 'broken'};
        await h.store.write(ownerId, 'listing-1', raw);

        final damaged = await harness(
          root: h.root,
          backend: h.backend,
          store: h.store,
        );
        final room = damaged.controller.rooms.single;
        final trace = damaged.controller.traceForRoom(room.id)!;
        expect(trace.draftProblem, 'visual_draft_unreadable');
        expect(trace.restoreEditorDraft().isReady, isFalse);

        expect(
          await damaged.controller.saveFloorplanTrace(
            roomId: room.id,
            name: room.name,
            sourceId: trace.sourceId,
            contentType: trace.contentType,
            imageWidth: trace.imageWidth,
            imageHeight: trace.imageHeight,
            normalizedTrace: trace.vertices,
            height: 2.6,
          ),
          contains('no se pudo leer'),
        );
        final untouched = (await h.store.read(ownerId, 'listing-1'))!;
        final untouchedTrace = (untouched['traces']! as List).single as Map;
        expect(untouchedTrace['visualDraft'], {
          'version': 2,
          'walls': 'broken',
        });

        // An explicit human reconstruction is the only way to replace it.
        expect(
          await damaged.controller.saveFloorplanTrace(
            roomId: room.id,
            name: room.name,
            sourceId: trace.sourceId,
            contentType: trace.contentType,
            imageWidth: trace.imageWidth,
            imageHeight: trace.imageHeight,
            normalizedTrace: draft.contourForRoom('temporary')!,
            visualDraft: draft,
            height: 2.6,
          ),
          isNull,
        );
        expect(
          damaged.controller.traceForRoom(room.id)!.visualDraft,
          isNotNull,
        );
      },
    );

    test('persists a local-only floorplan trace across restart', () async {
      final source = FakePhotoSource();
      final h = await harness(traceSource: source);
      final picked = await h.controller.pickFloorplanSource();
      expect(picked, isNotNull);
      expect(
        await h.controller.saveFloorplanTrace(
          name: 'Dormitorio plano',
          sourceId: picked!.sourceId,
          contentType: picked.contentType,
          imageWidth: 1000,
          imageHeight: 800,
          normalizedTrace: const [
            FloorPoint(0.1, 0.2),
            FloorPoint(0.5, 0.2),
            FloorPoint(0.5, 0.6),
            FloorPoint(0.1, 0.6),
          ],
          height: 2.65,
        ),
        isNull,
      );

      final reopened = await harness(root: h.root, backend: h.backend);
      final room = reopened.controller.rooms.single;
      final trace = reopened.controller.traceForRoom(room.id)!;
      expect(room.acquisition.method, RoomAcquisitionMethod.floorplanTrace);
      expect(room.metrics, isNull);
      expect(trace.vertices.first, const FloorPoint(0.1, 0.2));
      expect(trace.referenceMeters, isNull);
      expect(room.references, isEmpty);
      expect(room.measurementMode, RoomMeasurementMode.wallConstraints);
      expect(
        await reopened.controller.floorplanSourceBytes(trace.sourceId),
        isNotNull,
      );
      expect(reopened.controller.preview!.document['version'], '2.0');
      expect(
        reopened.controller.preview!.document.toString(),
        isNot(contains(trace.sourceId)),
      );
      expect(h.ar.availabilityChecks, 0);
      expect(h.ar.names, isEmpty);

      await reopened.controller.updateRoom(
        room.copyWith(
          openings: const [
            RoomOpening(
              id: 'door-plan',
              edgeIndex: 0,
              position: 0.5,
              width: 0.9,
              height: 2.1,
              type: OpeningType.door,
            ),
          ],
        ),
      );
      expect(
        await reopened.controller.saveFloorplanTrace(
          roomId: room.id,
          name: room.name,
          sourceId: trace.sourceId,
          contentType: trace.contentType,
          imageWidth: trace.imageWidth,
          imageHeight: trace.imageHeight,
          normalizedTrace: const [
            FloorPoint(0.1, 0.2),
            FloorPoint(0.5, 0.2),
            FloorPoint(0.55, 0.6),
            FloorPoint(0.1, 0.6),
          ],
          height: 2.65,
        ),
        contains('datos espaciales vinculados'),
      );
      expect(reopened.controller.rooms.single.id, room.id);
      expect(reopened.controller.rooms.single.openings.single.id, 'door-plan');

      await reopened.controller.discardFloorplanSource(trace.sourceId);
      final missing = await harness(root: h.root, backend: h.backend);
      expect(missing.controller.rooms.single.id, room.id);
      expect(missing.controller.preview!.document['version'], '2.0');
      expect(
        await missing.controller.floorplanSourceBytes(trace.sourceId),
        isNull,
      );

      await missing.controller.removeRoom(room.id);
      expect(
        await missing.controller.floorplanSourceBytes(trace.sourceId),
        isNull,
      );
    });
  });

  group('floorplan source lifecycle', () {
    const plan = [
      FloorPoint(0.1, 0.125),
      FloorPoint(0.5, 0.125),
      FloorPoint(0.5, 0.5),
      FloorPoint(0.1, 0.5),
    ];

    Future<(_FailingWriteStore, Harness)> harnessWithFailingWrites() async {
      final root = await Directory.systemTemp.createTemp('spatial-');
      final drafts = _FailingWriteStore(
        FileCaptureDraftStore(root: () async => root),
      );
      final h = await harness(
        root: root,
        traceSource: FakePhotoSource(),
        store: drafts,
      );
      return (drafts, h);
    }

    test(
      'keeps the source image when a room delete is not persisted',
      () async {
        final (drafts, h) = await harnessWithFailingWrites();
        final picked = await h.controller.pickFloorplanSource();
        expect(
          await h.controller.saveFloorplanTrace(
            name: 'Dormitorio plano',
            sourceId: picked!.sourceId,
            contentType: picked.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: plan,
            referenceEdge: 0,
            referenceMeters: 4,
            height: 2.5,
          ),
          isNull,
        );
        final room = h.controller.rooms.single;
        final trace = h.controller.traceForRoom(room.id)!;

        drafts.failWrites = true;
        await expectLater(
          h.controller.removeRoom(room.id),
          throwsA(isA<FileSystemException>()),
        );

        // Nothing was persisted, so the room, its trace and its image survive.
        expect(h.controller.rooms.single.id, room.id);
        expect(h.controller.traceForRoom(room.id)?.sourceId, trace.sourceId);
        expect(
          await h.controller.floorplanSourceBytes(trace.sourceId),
          isNotNull,
        );
        final afterFailure = await harness(root: h.root, backend: h.backend);
        expect(afterFailure.controller.rooms.single.id, room.id);
        expect(
          afterFailure.controller.traceForRoom(room.id)?.sourceId,
          trace.sourceId,
        );
        expect(
          await afterFailure.controller.floorplanSourceBytes(trace.sourceId),
          isNotNull,
        );

        drafts.failWrites = false;
        await h.controller.removeRoom(room.id);

        expect(h.controller.rooms, isEmpty);
        expect(h.controller.traceForRoom(room.id), isNull);
        expect(await h.controller.floorplanSourceBytes(trace.sourceId), isNull);
        final afterSuccess = await harness(root: h.root, backend: h.backend);
        expect(afterSuccess.controller.rooms, isEmpty);
        expect(afterSuccess.controller.traceForRoom(room.id), isNull);
        expect(
          await afterSuccess.controller.floorplanSourceBytes(trace.sourceId),
          isNull,
        );
      },
    );

    test('keeps the previous source when a retrace is not persisted', () async {
      final (drafts, h) = await harnessWithFailingWrites();
      final first = await h.controller.pickFloorplanSource();
      expect(
        await h.controller.saveFloorplanTrace(
          name: 'Dormitorio plano',
          sourceId: first!.sourceId,
          contentType: first.contentType,
          imageWidth: 1000,
          imageHeight: 800,
          normalizedTrace: plan,
          referenceEdge: 0,
          referenceMeters: 4,
          height: 2.5,
        ),
        isNull,
      );
      final room = h.controller.rooms.single;
      final original = h.controller.traceForRoom(room.id)!;
      final originalCorners = room.corners;
      final second = await h.controller.pickFloorplanSource();
      expect(second, isNotNull);
      expect(second!.sourceId, isNot(original.sourceId));

      drafts.failWrites = true;
      await expectLater(
        h.controller.saveFloorplanTrace(
          roomId: room.id,
          name: 'Dormitorio plano',
          sourceId: second.sourceId,
          contentType: second.contentType,
          imageWidth: 1000,
          imageHeight: 800,
          normalizedTrace: const [
            FloorPoint(0.1, 0.125),
            FloorPoint(0.7, 0.125),
            FloorPoint(0.7, 0.5),
            FloorPoint(0.1, 0.5),
          ],
          referenceEdge: 0,
          referenceMeters: 5,
          height: 2.8,
        ),
        throwsA(isA<FileSystemException>()),
      );

      // The failed retrace leaves the previous room and image in place.
      expect(h.controller.traceForRoom(room.id)?.sourceId, original.sourceId);
      expect(h.controller.rooms.single.corners, originalCorners);
      expect(h.controller.rooms.single.height!.value, 2.5);
      expect(
        await h.controller.floorplanSourceBytes(original.sourceId),
        isNotNull,
      );
      final afterFailure = await harness(root: h.root, backend: h.backend);
      expect(
        afterFailure.controller.traceForRoom(room.id)?.sourceId,
        original.sourceId,
      );
      expect(
        await afterFailure.controller.floorplanSourceBytes(original.sourceId),
        isNotNull,
      );

      drafts.failWrites = false;
      expect(
        await h.controller.saveFloorplanTrace(
          roomId: room.id,
          name: 'Dormitorio plano',
          sourceId: second.sourceId,
          contentType: second.contentType,
          imageWidth: 1000,
          imageHeight: 800,
          normalizedTrace: const [
            FloorPoint(0.1, 0.125),
            FloorPoint(0.7, 0.125),
            FloorPoint(0.7, 0.5),
            FloorPoint(0.1, 0.5),
          ],
          referenceEdge: 0,
          referenceMeters: 5,
          height: 2.8,
        ),
        isNull,
      );

      // Only now is the replaced image dropped.
      expect(h.controller.traceForRoom(room.id)?.sourceId, second.sourceId);
      expect(
        await h.controller.floorplanSourceBytes(original.sourceId),
        isNull,
      );
      expect(
        await h.controller.floorplanSourceBytes(second.sourceId),
        isNotNull,
      );
      final afterSuccess = await harness(root: h.root, backend: h.backend);
      expect(
        afterSuccess.controller.traceForRoom(room.id)?.sourceId,
        second.sourceId,
      );
      expect(
        await afterSuccess.controller.floorplanSourceBytes(original.sourceId),
        isNull,
      );
    });
  });

  group('floorplan retrace', () {
    const plan = [
      FloorPoint(0.1, 0.125),
      FloorPoint(0.5, 0.125),
      FloorPoint(0.5, 0.5),
      FloorPoint(0.1, 0.5),
    ];
    const retraced = [
      FloorPoint(0.1, 0.125),
      FloorPoint(0.55, 0.125),
      FloorPoint(0.55, 0.5),
      FloorPoint(0.1, 0.5),
    ];

    Future<Harness> traced({PhotoSource? source}) async {
      final h = await harness(traceSource: source ?? FakePhotoSource());
      final picked = await h.controller.pickFloorplanSource();
      expect(
        await h.controller.saveFloorplanTrace(
          name: 'Dormitorio plano',
          sourceId: picked!.sourceId,
          contentType: picked.contentType,
          imageWidth: 1000,
          imageHeight: 800,
          normalizedTrace: plan,
          referenceEdge: 0,
          referenceMeters: 4,
          height: 2.655,
        ),
        isNull,
      );
      return h;
    }

    test(
      'retrace without dependent data keeps identity, name, exact height and provenance',
      () async {
        final h = await traced();
        final room = h.controller.rooms.single;

        final second = await h.controller.pickFloorplanSource();
        expect(
          await h.controller.saveFloorplanTrace(
            roomId: room.id,
            name: 'Dormitorio plano',
            sourceId: second!.sourceId,
            contentType: second.contentType,
            imageWidth: 1000,
            imageHeight: 800,
            normalizedTrace: retraced,
            referenceEdge: 0,
            referenceMeters: 4,
            height: 2.655,
          ),
          isNull,
        );

        final after = h.controller.rooms.single;
        expect(after.id, room.id);
        expect(after.name, 'Dormitorio plano');
        expect(after.height!.value, 2.655);
        expect(after.openings, isEmpty);
        expect(after.boxes, isEmpty);
        expect(after.acquisition.method, RoomAcquisitionMethod.floorplanTrace);
        expect(h.controller.traceForRoom(room.id)!.sourceId, second.sourceId);

        final reopened = await harness(root: h.root, backend: h.backend);
        final restored = reopened.controller.rooms.single;
        expect(restored.id, room.id);
        expect(restored.height!.value, 2.655);
        expect(restored.openings, isEmpty);
        expect(restored.boxes, isEmpty);
        expect(
          restored.acquisition.method,
          RoomAcquisitionMethod.floorplanTrace,
        );
      },
    );

    test(
      'retrace with an opening is blocked without changing room or trace',
      () async {
        final h = await traced();
        final room = h.controller.rooms.single;
        await h.controller.updateRoom(
          room.copyWith(
            openings: const [
              RoomOpening(
                id: 'door-plan',
                edgeIndex: 3,
                position: 0.5,
                width: 0.9,
                height: 2.1,
                type: OpeningType.door,
              ),
            ],
          ),
        );

        final second = await h.controller.pickFloorplanSource();
        final message = await h.controller.saveFloorplanTrace(
          roomId: room.id,
          name: 'Dormitorio plano',
          sourceId: second!.sourceId,
          contentType: second.contentType,
          imageWidth: 1000,
          imageHeight: 800,
          // A triangle: edge 3 of the previous contour no longer exists.
          normalizedTrace: const [
            FloorPoint(0.1, 0.125),
            FloorPoint(0.6, 0.125),
            FloorPoint(0.6, 0.6),
          ],
          referenceEdge: 0,
          referenceMeters: 4,
          height: 2.655,
        );

        expect(message, contains('datos espaciales vinculados'));
        final after = h.controller.rooms.single;
        expect(after.corners, room.corners);
        expect(after.openings, hasLength(1));
        expect(after.openings.single.id, 'door-plan');
        expect(after.openings.single.edgeIndex, 3, reason: 'not relocated');
        expect(after.openings.single.position, 0.5);
        expect(after.openings.single.width, 0.9);
        expect(after.openings.single.height, 2.1);

        expect(
          h.controller.traceForRoom(room.id)!.sourceId,
          isNot(second.sourceId),
        );
      },
    );

    test('retrace with a box or non-identity placement is blocked', () async {
      for (final dependent in <CapturedRoom Function(CapturedRoom)>[
        (room) => room.copyWith(
          boxes: const [
            OccupancyBox(
              id: 'box-plan',
              centerX: 1,
              centerZ: 1,
              width: 0.6,
              depth: 0.5,
              height: null,
              source: BoxSource.manual,
            ),
          ],
        ),
        (room) => room.copyWith(
          placement: const RoomPlacement(x: 1, z: 0, rotationDegrees: 0),
        ),
      ]) {
        final h = await traced();
        final before = dependent(h.controller.rooms.single);
        await h.controller.updateRoom(before);
        final trace = h.controller.traceForRoom(before.id)!;
        final message = await h.controller.saveFloorplanTrace(
          roomId: before.id,
          name: before.name,
          sourceId: trace.sourceId,
          contentType: trace.contentType,
          imageWidth: trace.imageWidth,
          imageHeight: trace.imageHeight,
          normalizedTrace: retraced,
          referenceEdge: 0,
          referenceMeters: 4,
          height: before.height!.value,
        );
        expect(message, contains('datos espaciales vinculados'));
        expect(h.controller.rooms.single.toJson(), before.toJson());
        expect(h.controller.traceForRoom(before.id)!.toJson(), trace.toJson());
      }
    });

    test('RoomEditor updates keep each acquisition method', () async {
      final h = await harness(traceSource: FakePhotoSource());
      await h.controller.createManualRectangularRoom(
        name: 'Manual',
        length: 4,
        width: 3,
        height: 2.6,
      );
      expect(
        await h.controller.createCalibratedManualSketchRoom(
          name: 'Croquis',
          sketch: const [
            FloorPoint(0, 0),
            FloorPoint(4, 0),
            FloorPoint(4, 3),
            FloorPoint(0, 3),
          ],
          referenceEdge: 0,
          referenceMeters: 4,
          height: 2.6,
        ),
        isNull,
      );
      final picked = await h.controller.pickFloorplanSource();
      expect(
        await h.controller.saveFloorplanTrace(
          name: 'Plano',
          sourceId: picked!.sourceId,
          contentType: picked.contentType,
          imageWidth: 1000,
          imageHeight: 800,
          normalizedTrace: plan,
          referenceEdge: 0,
          referenceMeters: 4,
          height: 2.6,
        ),
        isNull,
      );
      const expected = [
        RoomAcquisitionMethod.manual,
        RoomAcquisitionMethod.manualSketch,
        RoomAcquisitionMethod.floorplanTrace,
      ];
      expect([
        for (final room in h.controller.rooms) room.acquisition.method,
      ], expected);

      // What RoomEditor does when the agent saves a height or an opening.
      for (final room in h.controller.rooms) {
        await h.controller.updateRoom(
          room.copyWith(height: const RoomHeight(2.55, HeightSource.manual)),
        );
      }

      expect([
        for (final room in h.controller.rooms) room.acquisition.method,
      ], expected);

      // The reserved legacy value stays available and distinct.
      expect(RoomAcquisitionMethod.floorplan.wire, 'floorplan');
      expect(
        RoomAcquisitionMethod.fromWire('floorplan'),
        RoomAcquisitionMethod.floorplan,
      );

      final reopened = await harness(root: h.root, backend: h.backend);
      expect([
        for (final room in reopened.controller.rooms) room.acquisition.method,
      ], expected);
      expect(reopened.controller.rooms.first.height!.value, 2.55);
    });
  });

  group('editing', () {
    test('a manual height replaces the assumed one and is persisted', () async {
      final h = await harness();
      h.ar.results.add(rectangle(4, 3, height: null));
      await h.controller.captureRoom('Estar');
      final room = h.controller.rooms.single;

      await h.controller.updateRoom(
        room.copyWith(height: const RoomHeight(2.55, HeightSource.manual)),
      );

      final reopened = await harness(root: h.root, backend: h.backend);
      expect(
        reopened.controller.rooms.single.height,
        const RoomHeight(2.55, HeightSource.manual),
      );
    });

    test('preserves the physically verified manual room and door', () async {
      final h = await harness();
      await h.controller.createManualRectangularRoom(
        name: 'Dormitorio prueba',
        length: 4.2,
        width: 3.7,
        height: 2.65,
      );
      final room = h.controller.rooms.single;
      await h.controller.updateRoom(
        room.copyWith(
          openings: const [
            RoomOpening(
              id: 'door-1',
              edgeIndex: 0,
              position: 0.5,
              width: 0.9,
              height: 2.1,
              type: OpeningType.door,
            ),
          ],
        ),
      );

      final reopened = await harness(root: h.root, backend: h.backend);
      final restored = reopened.controller.rooms.single;
      expect(restored.name, 'Dormitorio prueba');
      expect(restored.height, const RoomHeight(2.65, HeightSource.manual));
      expect(restored.acquisition.method, RoomAcquisitionMethod.manual);
      expect(restored.metrics, isNull);
      expect(restored.openings.single.width, 0.9);
      expect(restored.openings.single.height, 2.1);
      expect(restored.openings.single.position, 0.5);
      expect(reopened.controller.preview, isNotNull);
      expect(reopened.controller.preview!.document['version'], '2.0');
    });

    test('connecting two rooms by their doors shares one wall', () async {
      final h = await harness();
      h.ar.results
        ..add(rectangle(4, 3))
        ..add(rectangle(3, 3));
      await h.controller.captureRoom('Estar');
      await h.controller.captureRoom('Dormitorio');
      final [living, bedroom] = h.controller.rooms;
      await h.controller.updateRoom(
        living.copyWith(
          openings: [
            const RoomOpening(
              id: 'd-a',
              edgeIndex: 1,
              position: 0.5,
              width: 0.9,
              height: 2.1,
              type: OpeningType.door,
            ),
          ],
        ),
      );
      await h.controller.updateRoom(
        bedroom.copyWith(
          openings: [
            const RoomOpening(
              id: 'd-b',
              edgeIndex: 3,
              position: 0.5,
              width: 0.9,
              height: 2.1,
              type: OpeningType.door,
            ),
          ],
        ),
      );

      final message = await h.controller.connect(
        roomA: living.id,
        openingA: 'd-a',
        roomB: bedroom.id,
        openingB: 'd-b',
      );

      expect(message, isNull);
      final document = h.controller.preview!.document;
      expect((document['walls']! as List).length, 7);
      expect((document['openings']! as List).length, 1);
      expect(
        h.controller.preview!.warnings.map((w) => w.code),
        isNot(contains(SceneWarningCode.roomNotConnected)),
      );
    });
  });

  group('scale correction', () {
    double wallLength(Map<String, Object?> wall) {
      final start = wall['start']! as Map;
      final end = wall['end']! as Map;
      final dx = (end['x']! as num) - (start['x']! as num);
      final dz = (end['z']! as num) - (start['z']! as num);
      return (dx * dx + dz * dz).toDouble();
    }

    test('the scene uses the room rescaled by a tape reference', () async {
      final h = await harness();
      h.ar.results.add(rectangle(4, 3));
      await h.controller.captureRoom('Estar');
      final room = h.controller.rooms.single;

      await h.controller.updateRoom(
        room.copyWith(
          references: const [
            ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.2),
          ],
        ),
      );

      final walls = (h.controller.preview!.document['walls']! as List)
          .cast<Map<String, Object?>>();
      // Interior 4.2 m plus half a 0.15 m wall at each end.
      expect(wallLength(walls.first), closeTo(4.35 * 4.35, 1e-6));
      expect(h.controller.rooms.single.corners, room.corners);
    });

    test('rooms joined by a door stay joined after rescaling one', () async {
      final h = await harness();
      h.ar.results
        ..add(rectangle(4, 3))
        ..add(rectangle(3, 3));
      await h.controller.captureRoom('Estar');
      await h.controller.captureRoom('Dormitorio');
      final [living, bedroom] = h.controller.rooms;
      await h.controller.updateRoom(
        living.copyWith(
          openings: const [
            RoomOpening(
              id: 'd-a',
              edgeIndex: 1,
              position: 0.5,
              width: 0.9,
              height: 2.1,
              type: OpeningType.door,
            ),
          ],
        ),
      );
      await h.controller.updateRoom(
        bedroom.copyWith(
          openings: const [
            RoomOpening(
              id: 'd-b',
              edgeIndex: 3,
              position: 0.5,
              width: 0.9,
              height: 2.1,
              type: OpeningType.door,
            ),
          ],
        ),
      );
      await h.controller.connect(
        roomA: living.id,
        openingA: 'd-a',
        roomB: bedroom.id,
        openingB: 'd-b',
      );

      await h.controller.updateRoom(
        h.controller.rooms.first.copyWith(
          references: const [
            ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.2),
          ],
        ),
      );

      final document = h.controller.preview!.document;
      expect((document['openings']! as List).length, 1);
      expect(
        h.controller.preview!.warnings.map((w) => w.code),
        isNot(contains(SceneWarningCode.roomsOverlap)),
      );
    });
  });

  group('sync', () {
    test('blocks incomplete wall drafts but preserves local work', () async {
      final h = await harness();
      await h.controller.createWallBasedManualSketchRoom(
        name: 'Croquis',
        sketch: const [
          FloorPoint(0, 0),
          FloorPoint(4, 0),
          FloorPoint(4, 3),
          FloorPoint(0, 3),
        ],
        height: 2.6,
        measurements: const [
          ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4),
        ],
      );

      await h.controller.sync();

      expect(h.controller.syncState, CaptureSyncState.pending);
      expect(h.controller.message, contains('faltan medidas'));
      expect(h.backend.requests.where((r) => r.method == 'PUT'), isEmpty);
      expect(await h.store.read(h.controller.ownerId!, 'listing-1'), isNotNull);
      expect(h.controller.rooms.single.references, hasLength(1));
    });

    test('shortening a wall keeps its door and blocks invalid sync', () async {
      final h = await harness();
      await h.controller.createManualRectangularRoom(
        name: 'Estar',
        length: 4,
        width: 3,
        height: 2.6,
      );
      final room = h.controller.rooms.single.copyWith(
        references: const [
          ReferenceMeasurement(edgeIndex: 0, referenceMeters: 2),
          ReferenceMeasurement(edgeIndex: 1, referenceMeters: 3),
          ReferenceMeasurement(edgeIndex: 2, referenceMeters: 2),
          ReferenceMeasurement(edgeIndex: 3, referenceMeters: 3),
        ],
        openings: const [
          RoomOpening(
            id: 'wide-door',
            edgeIndex: 0,
            position: 0.5,
            width: 1.95,
            height: 2.1,
            type: OpeningType.door,
          ),
        ],
      );
      final fitted = fitConfirmedWallLengths(room);
      expect(fitted.isCoherent, isTrue);
      expect(edgeLengths(fitted.corners!).first, closeTo(2, 1e-6));
      await h.controller.updateRoom(room.copyWith(corners: fitted.corners));
      expect(
        validateOpening(
          h.controller.rooms.single,
          h.controller.rooms.single.openings.single,
        ),
        isNotEmpty,
      );

      await h.controller.sync();

      final after = h.controller.rooms.single;
      expect(after.openings.single.id, 'wide-door');
      expect(after.openings.single.edgeIndex, 0);
      expect(after.openings.single.width, 1.95);
      expect(h.controller.syncState, CaptureSyncState.pending);
      expect(
        h.backend.requests.where((request) => request.method == 'PUT'),
        isEmpty,
      );
      expect(h.controller.message, isNotNull);
    });

    test(
      'overwrite also blocks a wall draft that becomes incomplete',
      () async {
        final h = await harness();
        await h.controller.createManualRectangularRoom(
          name: 'Estar',
          length: 4,
          width: 3,
          height: 2.6,
        );
        await h.controller.sync();
        h.backend.editRemotely({
          ...h.backend.document!,
          'objects': <Object?>[],
        });
        final mutableReferences = [...h.controller.rooms.single.references];
        await h.controller.updateRoom(
          h.controller.rooms.single.copyWith(
            name: 'Cambio local',
            references: mutableReferences,
          ),
        );
        await h.controller.sync();
        expect(h.controller.syncState, CaptureSyncState.conflict);
        final putsBefore = h.backend.requests
            .where((request) => request.method == 'PUT')
            .length;
        mutableReferences.removeLast();

        await h.controller.overwriteRemote();

        expect(h.controller.syncState, CaptureSyncState.conflict);
        expect(h.controller.message, contains('faltan medidas'));
        expect(
          h.backend.requests.where((request) => request.method == 'PUT').length,
          putsBefore,
        );
      },
    );

    test('422 scene validation never exposes raw backend detail', () async {
      final h = await harness(
        sceneClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'extra_forbidden',
              'detail': 'walls[0].lengthM Extra inputs are not permitted',
            }),
            422,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await h.controller.createManualRectangularRoom(
        name: 'Estar',
        length: 4,
        width: 3,
        height: 2.6,
      );

      await h.controller.sync();

      expect(h.controller.syncState, CaptureSyncState.failed);
      expect(
        h.controller.message,
        'No se pudo enviar la escena. Revisá los ambientes e intentá nuevamente.',
      );
      expect(h.controller.message, isNot(contains('lengthM')));
      expect(h.controller.message, isNot(contains('Extra inputs')));
    });

    test('floorplan trace sends only canonical Scene v2 geometry', () async {
      final h = await harness(traceSource: FakePhotoSource());
      final source = await h.controller.pickFloorplanSource();
      await h.controller.saveFloorplanTrace(
        name: 'Plano local',
        sourceId: source!.sourceId,
        contentType: source.contentType,
        imageWidth: 1000,
        imageHeight: 800,
        normalizedTrace: const [
          FloorPoint(0.1, 0.125),
          FloorPoint(0.5, 0.125),
          FloorPoint(0.5, 0.5),
          FloorPoint(0.1, 0.5),
        ],
        referenceEdge: 0,
        referenceMeters: 4,
        height: 2.6,
      );
      final room = h.controller.rooms.single;
      final lengths = edgeLengths(room.corners);
      await h.controller.updateRoom(
        room.copyWith(
          references: [
            for (var index = 0; index < lengths.length; index++)
              ReferenceMeasurement(
                edgeIndex: index,
                referenceMeters: lengths[index],
              ),
          ],
        ),
      );
      await h.controller.sync();

      final payload = jsonEncode(h.backend.document);
      expect(h.backend.requests.where((r) => r.method == 'PUT'), hasLength(1));
      expect(h.backend.document!['version'], '2.0');
      expect(payload, contains('Plano local'));
      for (final localDetail in [
        source.sourceId,
        'sourceId',
        'contentType',
        'imageWidth',
        'imageHeight',
        'referenceMeters',
        'normalizedTrace',
        '_traces',
        'FloorplanTraceMetadata',
        'measurementMode',
        'legacyUniform',
        'wallConstraints',
        'ocr',
        'ocrText',
        'detectedText',
        'measurementCandidate',
        'candidateStatus',
        'confidence',
        'imagePath',
        'imageBytes',
        'base64',
      ]) {
        expect(payload, isNot(contains(localDetail)));
      }
    });

    test('creates the scene once and then updates its own revision', () async {
      final h = await harness();
      h.ar.results.add(rectangle(4, 3));
      await h.controller.captureRoom('Estar');

      await h.controller.sync();

      expect(h.controller.syncState, CaptureSyncState.synced);
      expect(h.backend.revision, 1);
      expect(h.backend.requests.last.headers['If-None-Match'], '*');

      await h.controller.updateRoom(
        h.controller.rooms.single.copyWith(name: 'Living'),
      );
      expect(h.controller.syncState, CaptureSyncState.pending);
      await h.controller.sync();

      expect(h.controller.syncState, CaptureSyncState.synced);
      expect(h.backend.revision, 2);
      expect(h.backend.requests.last.headers['If-Match'], '"1"');
      expect(
        (h.backend.document!['rooms']! as List).single,
        containsPair('name', 'Living'),
      );
    });

    test('keeps the draft offline and retries without duplicating', () async {
      final h = await harness();
      h.ar.results.add(rectangle(4, 3));
      await h.controller.captureRoom('Estar');
      h.backend.offline = true;

      await h.controller.sync();

      expect(h.controller.syncState, CaptureSyncState.failed);
      expect(h.controller.message, isNotNull);
      final reopened = await harness(root: h.root, backend: h.backend);
      expect(reopened.controller.rooms, hasLength(1));
      expect(reopened.controller.syncState, CaptureSyncState.pending);

      h.backend.offline = false;
      await reopened.controller.sync();
      await reopened.controller.sync();

      expect(reopened.controller.syncState, CaptureSyncState.synced);
      expect(h.backend.revision, 1);
    });

    test('stops on a remote edit and lets the agent overwrite it', () async {
      final h = await harness();
      h.ar.results.add(rectangle(4, 3));
      await h.controller.captureRoom('Estar');
      await h.controller.sync();
      h.backend.editRemotely({...h.backend.document!, 'objects': <Object?>[]});
      await h.controller.updateRoom(
        h.controller.rooms.single.copyWith(name: 'Living'),
      );

      await h.controller.sync();

      expect(h.controller.syncState, CaptureSyncState.conflict);
      expect(h.backend.revision, 2);

      await h.controller.overwriteRemote();

      expect(h.controller.syncState, CaptureSyncState.synced);
      expect(h.backend.revision, 3);
      expect(h.backend.requests.last.headers['If-Match'], '"2"');
    });

    test('refuses to send a contour that crosses itself', () async {
      final h = await harness();
      h.ar.results.add(
        const ArCaptured({
          'outcome': 'captured',
          'corners': [
            {'x': 0.0, 'z': 0.0},
            {'x': 4.0, 'z': 3.0},
            {'x': 4.0, 'z': 0.0},
            {'x': 0.0, 'z': 3.0},
          ],
          'height': null,
          'boxes': <Object?>[],
          'metrics': {
            'durationMs': 1000,
            'trackingLossCount': 0,
            'depthSupported': false,
            'cornerHitDistances': [1.0, 1.0, 1.0, 1.0],
            'floorY': -1.3,
          },
        }),
      );
      await h.controller.captureRoom('Estar');

      await h.controller.sync();

      expect(h.controller.syncState, CaptureSyncState.pending);
      expect(h.controller.message, contains('Estar'));
      expect(h.backend.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    test('sync and conflict overwrite never send blocking openings', () async {
      final h = await harness();
      await h.controller.createManualRectangularRoom(
        name: 'Estar',
        length: 4,
        width: 3,
        height: 2.6,
      );
      final room = h.controller.rooms.single;
      await h.controller.updateRoom(
        room.copyWith(
          openings: const [
            RoomOpening(
              id: 'invalid-door',
              edgeIndex: 99,
              position: 0.5,
              width: 0.9,
              height: 2.1,
              type: OpeningType.door,
            ),
          ],
        ),
      );
      await h.controller.sync();
      expect(h.backend.requests.where((r) => r.method == 'PUT'), isEmpty);

      // Establish a conflict using a valid room, then make the local draft
      // invalid before the explicit overwrite action.
      await h.controller.updateRoom(room);
      await h.controller.sync();
      h.backend.editRemotely({...h.backend.document!, 'objects': <Object?>[]});
      final mutableOpenings = <RoomOpening>[];
      await h.controller.updateRoom(
        room.copyWith(name: 'Cambio local', openings: mutableOpenings),
      );
      await h.controller.sync();
      expect(h.controller.syncState, CaptureSyncState.conflict);
      final putsBefore = h.backend.requests
          .where((r) => r.method == 'PUT')
          .length;
      mutableOpenings.add(
        const RoomOpening(
          id: 'invalid-door',
          edgeIndex: 99,
          position: 0.5,
          width: 0.9,
          height: 2.1,
          type: OpeningType.door,
        ),
      );
      await h.controller.overwriteRemote();
      expect(h.controller.syncState, CaptureSyncState.conflict);
      expect(
        h.backend.requests.where((r) => r.method == 'PUT').length,
        putsBefore,
      );
    });
  });

  group('local data', () {
    test('only a synced draft can be cleared from the phone', () async {
      final h = await harness();
      h.ar.results.add(rectangle(4, 3));
      await h.controller.captureRoom('Estar');

      expect(await h.controller.clearLocal(), isFalse);
      expect(await h.store.read(h.controller.ownerId!, 'listing-1'), isNotNull);

      await h.controller.sync();
      expect(await h.controller.storageBytes(), greaterThan(0));
      expect(await h.controller.clearLocal(), isTrue);

      expect(await h.store.read(h.controller.ownerId!, 'listing-1'), isNull);
      expect(h.controller.rooms, isEmpty);
    });
  });
}
