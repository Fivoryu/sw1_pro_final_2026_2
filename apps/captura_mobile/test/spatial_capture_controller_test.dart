import 'dart:io';

import 'package:captura_mobile/data/services/ar_capture_channel.dart';
import 'package:captura_mobile/data/services/capture_draft_store.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:captura_mobile/domain/spatial_capture_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_ar_capture.dart';
import 'support/fake_scene_backend.dart';
import 'support/fake_staff_backend.dart';

typedef Harness = ({
  SpatialCaptureController controller,
  FakeSceneBackend backend,
  FakeArCapture ar,
  CaptureDraftStore store,
  Directory root,
});

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
}) async {
  final dir = root ?? await Directory.systemTemp.createTemp('spatial-');
  final scenes = backend ?? FakeSceneBackend();
  final capture = ar ?? FakeArCapture();
  final store = FileCaptureDraftStore(root: () async => dir);
  final controller = SpatialCaptureController(
    listingId: 'listing-1',
    session: await signedIn(),
    sceneApi: StaffSceneApi(
      baseUrl: 'https://api.example.test',
      client: scenes.client,
    ),
    store: store,
    ar: capture,
    now: () => DateTime.utc(2026, 10, 21, 12),
  );
  await controller.load();
  return (
    controller: controller,
    backend: scenes,
    ar: capture,
    store: store,
    root: dir,
  );
}

void main() {
  final roots = <Directory>[];

  Future<Harness> harness({
    FakeSceneBackend? backend,
    Directory? root,
    FakeArCapture? ar,
  }) async {
    final built = await build(backend: backend, root: root, ar: ar);
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
