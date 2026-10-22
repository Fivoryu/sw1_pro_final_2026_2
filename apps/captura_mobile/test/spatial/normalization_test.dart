import 'dart:convert';

import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/spatial_fixtures.dart';

Map<String, Object?> _metrics() => {
  'durationMs': 30000,
  'trackingLossCount': 0,
  'depthSupported': true,
  'cornerHitDistances': [1.0, 1.5, 2.0, 2.5],
  'floorY': -1.2,
};

void main() {
  group('CapturedRoom.fromChannelResult', () {
    test('moves the first corner to the origin and the first edge onto +x', () {
      // A 4 m x 3 m room captured with its first edge along world +z.
      final room = CapturedRoom.fromChannelResult(
        id: 'living',
        name: 'Estar',
        result: {
          'outcome': 'captured',
          'corners': [
            {'x': 1.0, 'z': 1.0},
            {'x': 1.0, 'z': 5.0},
            {'x': -2.0, 'z': 5.0},
            {'x': -2.0, 'z': 1.0},
          ],
          'height': {'value': 2.5, 'source': 'ceiling_plane'},
          'boxes': <Object?>[],
          'metrics': _metrics(),
        },
      );

      expect(room.corners, [
        closeToPoint(0, 0),
        closeToPoint(4, 0),
        closeToPoint(4, 3),
        closeToPoint(0, 3),
      ]);
      expect(signedArea(room.corners), greaterThan(0));
      expect(room.height, const RoomHeight(2.5, HeightSource.ceilingPlane));
      expect(room.placement, RoomPlacement.identity);
      expect(room.metrics!.trackingLossCount, 0);
      expect(room.metrics!.cornerHitDistances, [1.0, 1.5, 2.0, 2.5]);
      expect(room.acquisition.method, RoomAcquisitionMethod.arcoreWalls);
    });

    test('reorders a clockwise capture counter-clockwise keeping corner 0', () {
      final room = CapturedRoom.fromChannelResult(
        id: 'r',
        name: 'R',
        result: {
          'outcome': 'captured',
          // Clockwise on the x/z plane (negative shoelace area).
          'corners': [
            {'x': 0.0, 'z': 0.0},
            {'x': 0.0, 'z': 3.0},
            {'x': 4.0, 'z': 3.0},
            {'x': 4.0, 'z': 0.0},
          ],
          'height': null,
          'boxes': <Object?>[],
          'metrics': _metrics(),
        },
      );

      expect(signedArea(room.corners), closeTo(12, 1e-6));
      expect(room.corners, [
        closeToPoint(0, 0),
        closeToPoint(4, 0),
        closeToPoint(4, 3),
        closeToPoint(0, 3),
      ]);
    });

    test('missing ceiling height becomes an assumed 2.4 m, never measured', () {
      final room = CapturedRoom.fromChannelResult(
        id: 'r',
        name: 'R',
        result: {
          'outcome': 'captured',
          'corners': [
            {'x': 0.0, 'z': 0.0},
            {'x': 3.0, 'z': 0.0},
            {'x': 3.0, 'z': 3.0},
          ],
          'height': null,
          'boxes': <Object?>[],
          'metrics': _metrics(),
        },
      );

      expect(room.height.value, 2.4);
      expect(room.height.source, HeightSource.assumed);
      expect(room.height.isMeasured, isFalse);
    });

    test('boxes move into the room-local frame as axis-aligned volumes', () {
      final room = CapturedRoom.fromChannelResult(
        id: 'living',
        name: 'Estar',
        result: {
          'outcome': 'captured',
          'corners': [
            {'x': 1.0, 'z': 1.0},
            {'x': 1.0, 'z': 5.0},
            {'x': -2.0, 'z': 5.0},
            {'x': -2.0, 'z': 1.0},
          ],
          'height': {'value': 2.5, 'source': 'wall_point'},
          'boxes': [
            {
              'corners': [
                {'x': 0.3, 'z': 1.6},
                {'x': -0.3, 'z': 2.4},
              ],
              'height': 0.75,
              'heightSource': 'depth',
              'confidence': 0.8,
            },
            {
              'corners': [
                {'x': 0.0, 'z': 3.0},
                {'x': -1.0, 'z': 4.0},
              ],
              'height': null,
              'heightSource': null,
              'confidence': null,
            },
            {
              'corners': [
                {'x': 0.0, 'z': 3.0},
                {'x': -1.0, 'z': 4.0},
              ],
              'height': 1.1,
              'heightSource': null,
              'confidence': null,
            },
          ],
          'metrics': _metrics(),
        },
      );

      final measured = room.boxes[0];
      expect(measured.centerX, closeTo(1, 1e-6));
      expect(measured.centerZ, closeTo(1, 1e-6));
      expect(measured.width, closeTo(0.8, 1e-6));
      expect(measured.depth, closeTo(0.6, 1e-6));
      expect(measured.height, 0.75);
      expect(measured.source, BoxSource.depth);
      expect(measured.confidence, 0.8);
      expect(measured.needsHeight, isFalse);

      final unmeasured = room.boxes[1];
      expect(unmeasured.height, isNull);
      expect(unmeasured.needsHeight, isTrue);
      expect(unmeasured.source, BoxSource.manual);
      expect(unmeasured.confidence, isNull);

      final noDepth = room.boxes[2];
      expect(noDepth.height, 1.1);
      expect(noDepth.source, BoxSource.manual);
    });

    test('rejects results that are not a capture', () {
      expect(
        () => CapturedRoom.fromChannelResult(
          id: 'r',
          name: 'R',
          result: {'outcome': 'cancelled'},
        ),
        throwsFormatException,
      );
    });

    test('a manual correction of a box drops the depth provenance', () {
      const box = OccupancyBox(
        id: 'box-1',
        centerX: 1,
        centerZ: 1,
        width: 1,
        depth: 1,
        height: null,
        source: BoxSource.manual,
      );
      final corrected = box.correctedManually(height: 0.9);
      expect(corrected.height, 0.9);
      expect(corrected.source, BoxSource.manual);
      expect(corrected.needsHeight, isFalse);
    });
  });

  test('PropertyCapture survives a JSON round trip without loss', () {
    final capture = PropertyCapture(
      listingId: 'listing-1',
      rooms: [
        rectangleRoom(
          id: 'living',
          width: 4.123456,
          depth: 3,
          openings: [
            door('d1', 1, position: 0.25),
            const RoomOpening(
              id: 'w1',
              edgeIndex: 2,
              position: 0.5,
              width: 1.2,
              height: 1,
              type: OpeningType.window,
              sillHeight: 0.85,
            ),
          ],
          boxes: const [
            OccupancyBox(
              id: 'box-1',
              centerX: 1,
              centerZ: 1.5,
              width: 0.8,
              depth: 0.6,
              height: 0.75,
              source: BoxSource.depth,
              confidence: 0.66,
            ),
            OccupancyBox(
              id: 'box-2',
              centerX: 2,
              centerZ: 2,
              width: 0.5,
              depth: 0.5,
              height: null,
              source: BoxSource.manual,
            ),
          ],
          placement: const RoomPlacement(x: 1.5, z: -2, rotationDegrees: 90),
        ).copyWith(
          references: const [
            ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.1),
          ],
        ),
      ],
      connections: const [
        DoorConnection(
          roomA: 'living',
          openingA: 'd1',
          roomB: 'b',
          openingB: 'd2',
        ),
      ],
      wallThickness: 0.12,
      updatedAt: DateTime.utc(2026, 10, 21, 9, 30),
    );

    final encoded = jsonEncode(capture.toJson());
    final decoded = PropertyCapture.fromJson(
      jsonDecode(encoded) as Map<String, Object?>,
    );

    expect(jsonEncode(decoded.toJson()), encoded);
    expect(decoded.rooms.single.boxes[1].height, isNull);
    expect(decoded.rooms.single.openings[1].sillHeight, 0.85);
    expect(decoded.updatedAt, DateTime.utc(2026, 10, 21, 9, 30));
  });

  test('HeightSource uses the documented wire names', () {
    expect(HeightSource.values.map((source) => source.wire), [
      'ceiling_plane',
      'wall_point',
      'manual',
      'assumed',
    ]);
  });
}
