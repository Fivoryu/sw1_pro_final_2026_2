import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('manual rectangular room', () {
    test(
      'creates authoritative counter-clockwise geometry without AR data',
      () {
        final room = buildManualRectangularRoom(
          id: 'room-1',
          name: 'Dormitorio',
          length: 4.20,
          width: 3.70,
          height: 2.60,
        );

        expect(room.corners, const [
          FloorPoint(0, 0),
          FloorPoint(4.2, 0),
          FloorPoint(4.2, 3.7),
          FloorPoint(0, 3.7),
        ]);
        expect(signedArea(room.corners), greaterThan(0));
        expect(polygonArea(room.corners), closeTo(15.54, 1e-9));
        expect(room.height, const RoomHeight(2.6, HeightSource.manual));
        expect(room.acquisition.method, RoomAcquisitionMethod.manual);
        expect(room.acquisition.arMetrics, isNull);
        expect(room.references, isEmpty);
      },
    );

    test('survives JSON persistence and reload', () {
      final original = buildManualRectangularRoom(
        id: 'room-1',
        name: 'Dormitorio',
        length: 4.2,
        width: 3.7,
        height: 2.6,
      );

      final restored = CapturedRoom.fromJson(original.toJson());

      expect(restored.corners, original.corners);
      expect(restored.height, original.height);
      expect(restored.acquisition.method, RoomAcquisitionMethod.manual);
      expect(restored.acquisition.arMetrics, isNull);
    });

    test('loads a legacy AR room without claiming manual provenance', () {
      final current = CapturedRoom.fromChannelResult(
        id: 'room-legacy',
        name: 'Estar',
        result: {
          'outcome': 'captured',
          'corners': [
            {'x': 0.0, 'z': 0.0},
            {'x': 4.0, 'z': 0.0},
            {'x': 4.0, 'z': 3.0},
            {'x': 0.0, 'z': 3.0},
          ],
          'height': {'value': 2.5, 'source': 'ceiling_plane'},
          'boxes': <Object?>[],
          'metrics': {
            'durationMs': 1000,
            'trackingLossCount': 0,
            'depthSupported': true,
            'cornerHitDistances': [1.0, 1.0, 1.0, 1.0],
            'floorY': -1.3,
          },
        },
      );
      final legacy = current.toJson()
        ..remove('acquisition')
        ..['metrics'] = current.acquisition.arMetrics!.toJson();

      final restored = CapturedRoom.fromJson(legacy);

      expect(restored.acquisition.method, RoomAcquisitionMethod.legacyArcore);
      expect(restored.acquisition.arMetrics, isNotNull);
    });

    test('builds a valid scene contract v2', () {
      final room = buildManualRectangularRoom(
        id: 'room-1',
        name: 'Dormitorio',
        length: 4.2,
        width: 3.7,
        height: 2.6,
      );
      final document = buildSceneDocument(
        PropertyCapture(
          listingId: 'listing-1',
          rooms: [room],
          connections: const [],
          updatedAt: DateTime.utc(2026, 10, 22),
        ),
      );

      expect(document['version'], '2.0');
      expect((document['rooms']! as List), hasLength(1));
      expect((document['walls']! as List), hasLength(4));
    });
  });
}
