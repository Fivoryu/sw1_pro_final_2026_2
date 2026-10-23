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

import 'support/fake_ar_capture.dart';
import 'support/fake_scene_backend.dart';
import 'support/fake_staff_backend.dart';
import 'support/fake_photo_source.dart';

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
      client: scenes.client,
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
  }) async {
    final built = await build(
      backend: backend,
      root: root,
      ar: ar,
      traceSource: traceSource,
      store: store,
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
      expect(room.height.source, HeightSource.ceilingPlane);
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

      expect(h.controller.rooms.single.height.source, HeightSource.assumed);
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
          referenceEdge: 0,
          referenceMeters: 4.2,
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
      expect(trace.referenceMeters, 4.2);
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
          referenceEdge: 0,
          referenceMeters: 4.2,
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
      expect(h.controller.rooms.single.height.value, 2.5);
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
        expect(after.height.value, 2.655);
        expect(after.openings, isEmpty);
        expect(after.boxes, isEmpty);
        expect(after.acquisition.method, RoomAcquisitionMethod.floorplanTrace);
        expect(h.controller.traceForRoom(room.id)!.sourceId, second.sourceId);

        final reopened = await harness(root: h.root, backend: h.backend);
        final restored = reopened.controller.rooms.single;
        expect(restored.id, room.id);
        expect(restored.height.value, 2.655);
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
          height: before.height.value,
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
      expect(reopened.controller.rooms.first.height.value, 2.55);
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
