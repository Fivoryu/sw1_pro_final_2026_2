import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy room keeps global height and edge-index opening', () {
    const legacy = CapturedRoom(
      id: 'legacy',
      name: 'Legacy',
      corners: [
        FloorPoint(0, 0),
        FloorPoint(4, 0),
        FloorPoint(4, 3),
        FloorPoint(0, 3),
      ],
      height: RoomHeight(2.5, HeightSource.manual),
      openings: [
        RoomOpening(
          id: 'legacy-window',
          edgeIndex: 0,
          position: .5,
          width: 1,
          height: 1,
          type: OpeningType.window,
        ),
      ],
      boxes: [],
      references: [],
      acquisition: RoomAcquisition(method: RoomAcquisitionMethod.manual),
    );

    final json = legacy.toJson();
    final restored = CapturedRoom.fromJson(json);
    expect(restored.height, legacy.height);
    expect(restored.wallDimensions, isEmpty);
    expect(restored.openings.single.edgeIndex, 0);
    expect(restored.openings.single.wallId, isNull);
    expect(restored.openings.single.explicitSillHeight, .9);
    expect((json['openings']! as List).single, isNot(contains('sillHeight')));
    expect(
      (restored.toJson()['openings']! as List).single,
      containsPair('sillHeight', .9),
    );
  });

  test('wall-based room round-trip needs no global height', () {
    const room = CapturedRoom(
      id: 'f07',
      name: 'F07',
      corners: [
        FloorPoint(0, 0),
        FloorPoint(4, 0),
        FloorPoint(4, 3),
        FloorPoint(0, 3),
      ],
      openings: [
        RoomOpening(
          id: 'window-a',
          wallId: 'a',
          width: 1.2,
          height: 1.1,
          offsetFromWallStartM: .4,
          sillHeight: .8,
          type: OpeningType.window,
        ),
      ],
      boxes: [],
      references: [],
      acquisition: RoomAcquisition(
        method: RoomAcquisitionMethod.floorplanTrace,
      ),
      wallDimensions: [
        CapturedWallDimension(wallId: 'a', lengthM: 4, heightM: 2.4),
        CapturedWallDimension(wallId: 'b', lengthM: 3, heightM: 2.8),
        CapturedWallDimension(wallId: 'c', lengthM: 4, heightM: 2.5),
        CapturedWallDimension(wallId: 'd', lengthM: 3, heightM: 2.6),
      ],
      measurementMode: RoomMeasurementMode.wallConstraints,
    );

    final json = room.toJson();
    expect(json, isNot(contains('height')));
    final restored = CapturedRoom.fromJson(json);
    expect(restored.height, isNull);
    expect(restored.wallDimensions.map((wall) => wall.wallId), [
      'a',
      'b',
      'c',
      'd',
    ]);
    expect(restored.wallDimensions[1].heightM, 2.8);
    expect(restored.openings.single.id, 'window-a');
    expect(restored.openings.single.wallId, 'a');
    expect(restored.openings.single.offsetFromWallStartM, .4);
    expect(restored.openings.single.explicitSillHeight, .8);
  });

  test('invalid and duplicate wall dimensions are rejected from JSON', () {
    final base = <String, Object?>{
      'id': 'f07',
      'name': 'F07',
      'corners': [
        {'x': 0.0, 'z': 0.0},
        {'x': 4.0, 'z': 0.0},
        {'x': 4.0, 'z': 3.0},
      ],
      'openings': <Object?>[],
      'boxes': <Object?>[],
      'references': <Object?>[],
      'acquisition': const RoomAcquisition(
        method: RoomAcquisitionMethod.floorplanTrace,
      ).toJson(),
      'measurementMode': 'wall_constraints',
      'placement': RoomPlacement.identity.toJson(),
    };
    expect(
      () => CapturedRoom.fromJson({
        ...base,
        'wallDimensions': [
          {'wallId': 'a', 'lengthM': 4.0, 'heightM': 2.4},
          {'wallId': 'a', 'lengthM': 3.0, 'heightM': 2.8},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => CapturedRoom.fromJson({
        ...base,
        'wallDimensions': [
          {'wallId': 'a', 'lengthM': 0.0, 'heightM': 2.4},
        ],
      }),
      throwsFormatException,
    );
  });
}
