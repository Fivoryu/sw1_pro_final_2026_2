import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/spatial_fixtures.dart';

List<Map<String, Object?>> _list(Map<String, Object?> document, String key) =>
    (document[key]! as List).cast<Map<String, Object?>>();

Map<String, Object?> _wall(Map<String, Object?> document, String id) =>
    _list(document, 'walls').firstWhere((wall) => wall['id'] == id);

List<String> _roomWalls(Map<String, Object?> document, String roomId) =>
    (_list(
              document,
              'rooms',
            ).firstWhere((room) => room['id'] == roomId)['wallIds']!
            as List)
        .cast<String>();

Set<String> _endpointPairs(Map<String, Object?> document) => {
  for (final wall in _list(document, 'walls'))
    ([
      '${(wall['start']! as Map)['x']},${(wall['start']! as Map)['z']}',
      '${(wall['end']! as Map)['x']},${(wall['end']! as Map)['z']}',
    ]..sort()).join('|'),
};

Set<SceneWarningCode> _codes(SceneBuildResult result) =>
    result.warnings.map((warning) => warning.code).toSet();

PropertyCapture _single(CapturedRoom room) => PropertyCapture(
  listingId: 'listing-1',
  rooms: [room],
  connections: const [],
  updatedAt: DateTime.utc(2026, 10, 21),
);

void main() {
  test(
    'a single room becomes four centreline walls offset by half thickness',
    () {
      final document = buildSceneDocument(
        _single(rectangleRoom(id: 'living', name: 'Estar', width: 4, depth: 3)),
      );

      expect(document['version'], '2.0');
      expect(document['unit'], 'meters');
      final walls = _list(document, 'walls');
      expect(walls.map((wall) => wall['id']), [
        'wall-1',
        'wall-2',
        'wall-3',
        'wall-4',
      ]);
      expect(walls.first, {
        'id': 'wall-1',
        'start': {'x': -0.075, 'z': -0.075},
        'end': {'x': 4.075, 'z': -0.075},
        'height': 2.5,
        'thickness': 0.15,
        'heightSource': 'ceiling_plane',
      });
      expect(_list(document, 'rooms').single, {
        'id': 'room-living',
        'name': 'Estar',
        'wallIds': ['wall-1', 'wall-2', 'wall-3', 'wall-4'],
      });
      expectEveryRoomCloses(document);
    },
  );

  test('two rooms joined by a door share one wall and one door', () {
    final capture = connectedPair(
      rectangleRoom(id: 'a', width: 4, depth: 3, openings: [door('da', 1)]),
      rectangleRoom(
        id: 'b',
        width: 3,
        depth: 3,
        height: RoomHeight.assumedDefault,
        openings: [door('db', 3)],
      ),
    );
    final result = buildScene(capture);
    final document = result.document;

    expect(_list(document, 'walls'), hasLength(7));
    expect(_endpointPairs(document), hasLength(7));
    final shared = _roomWalls(document, 'room-a')[1];
    expect(_roomWalls(document, 'room-b'), contains(shared));
    // Height of the shared wall is the max of both rooms, with its source.
    expect(_wall(document, shared)['height'], 2.5);
    expect(_wall(document, shared)['heightSource'], 'ceiling_plane');

    final openings = _list(document, 'openings');
    expect(openings, [
      {
        'id': 'door-1',
        'wallId': shared,
        'position': 0.5,
        'width': 0.9,
        'height': 2.1,
        'type': 'door',
      },
    ]);
    expectEveryRoomCloses(document);
    expect(_codes(result), {SceneWarningCode.assumedHeight});
  });

  test('a T-junction splits the longer wall so both rooms close', () {
    final capture = connectedPair(
      rectangleRoom(id: 'a', width: 4, depth: 3, openings: [door('da', 1)]),
      rectangleRoom(id: 'b', width: 2, depth: 2, openings: [door('db', 3)]),
    );
    final result = buildScene(capture);
    final document = result.document;

    expect(_roomWalls(document, 'room-a'), hasLength(6));
    expect(_roomWalls(document, 'room-b'), hasLength(4));
    expect(_list(document, 'walls'), hasLength(9));
    expect(_endpointPairs(document), hasLength(9));
    final middle = _roomWalls(document, 'room-a')[2];
    expect(_roomWalls(document, 'room-b'), contains(middle));
    expect(
      _wall(document, middle),
      containsPair('start', {'x': 4.075, 'z': 0.425}),
    );
    expect(
      _wall(document, middle),
      containsPair('end', {'x': 4.075, 'z': 2.575}),
    );
    final opening = _list(document, 'openings').single;
    expect(opening['wallId'], middle);
    expect(opening['position'], 0.5);
    expectEveryRoomCloses(document);
    expect(result.warnings, isEmpty);
  });

  test('vertices within 3 cm weld to one canonical coordinate', () {
    final a = rectangleRoom(id: 'a', width: 4, depth: 3);
    final b = rectangleRoom(
      id: 'b',
      width: 3,
      depth: 3,
      placement: const RoomPlacement(x: 4.17, z: 0.01, rotationDegrees: 0),
    );
    final result = buildScene(
      PropertyCapture(
        listingId: 'listing-1',
        rooms: [a, b],
        connections: const [],
        updatedAt: DateTime.utc(2026, 10, 21),
      ),
    );
    final document = result.document;

    expect(_list(document, 'walls'), hasLength(7));
    expect(
      _roomWalls(document, 'room-b'),
      contains(_roomWalls(document, 'room-a')[1]),
    );
    expectEveryRoomCloses(document);
    expect(_codes(result), {SceneWarningCode.roomNotConnected});
  });

  test('near-parallel walls closer than 30 cm are flagged, not merged', () {
    final a = rectangleRoom(id: 'a', width: 4, depth: 3);
    final b = rectangleRoom(
      id: 'b',
      width: 3,
      depth: 3,
      placement: const RoomPlacement(x: 4.35, z: 0, rotationDegrees: 0),
    );
    final result = buildScene(
      PropertyCapture(
        listingId: 'listing-1',
        rooms: [a, b],
        connections: const [],
        updatedAt: DateTime.utc(2026, 10, 21),
      ),
    );

    expect(_list(result.document, 'walls'), hasLength(8));
    expect(_codes(result), contains(SceneWarningCode.possibleDuplicateWall));
    expectEveryRoomCloses(result.document);
  });

  test('overlapping rooms are flagged', () {
    final result = buildScene(
      PropertyCapture(
        listingId: 'listing-1',
        rooms: [
          rectangleRoom(id: 'a', width: 4, depth: 3),
          rectangleRoom(
            id: 'b',
            width: 3,
            depth: 3,
            placement: const RoomPlacement(x: 2, z: 1, rotationDegrees: 0),
          ),
        ],
        connections: const [],
        updatedAt: DateTime.utc(2026, 10, 21),
      ),
    );
    expect(_codes(result), contains(SceneWarningCode.roomsOverlap));
  });

  group('occupancy objects', () {
    const measured = OccupancyBox(
      id: 'box-1',
      centerX: 1,
      centerZ: 1,
      width: 0.8,
      depth: 0.6,
      height: 0.75,
      source: BoxSource.depth,
      confidence: 0.8,
    );
    const manual = OccupancyBox(
      id: 'box-2',
      centerX: 3,
      centerZ: 2,
      width: 0.5,
      depth: 0.5,
      height: 1,
      source: BoxSource.manual,
    );
    const missingHeight = OccupancyBox(
      id: 'box-3',
      centerX: 2,
      centerZ: 2,
      width: 0.5,
      depth: 0.5,
      height: null,
      source: BoxSource.manual,
    );

    test('become unlabelled occupancy volumes, base centre in world frame', () {
      final result = buildScene(
        _single(
          rectangleRoom(
            id: 'a',
            width: 4,
            depth: 3,
            boxes: const [measured, manual, missingHeight],
            placement: const RoomPlacement(x: 10, z: 20, rotationDegrees: 90),
          ),
        ),
      );
      final objects = _list(result.document, 'objects');

      expect(objects, [
        {
          'id': 'box-1',
          'type': 'occupancy',
          'position': {'x': 9.0, 'y': 0.0, 'z': 21.0},
          'dimensions': {'width': 0.6, 'height': 0.75, 'depth': 0.8},
          'color': '#9e9e9e',
          'source': 'depth',
          'confidence': 0.8,
        },
        {
          'id': 'box-2',
          'type': 'occupancy',
          'position': {'x': 8.0, 'y': 0.0, 'z': 23.0},
          'dimensions': {'width': 0.5, 'height': 1.0, 'depth': 0.5},
          'color': '#9e9e9e',
          'source': 'manual',
        },
      ]);
      for (final object in objects) {
        expect(object.keys, isNot(contains('extra_id')));
        expect(object.keys, isNot(contains('price')));
        expect(object.keys, isNot(contains('label')));
      }
      expect(_codes(result), {SceneWarningCode.boxMissingHeight});
    });

    test('rotation off the 90 degree grid is approximated and warned', () {
      final result = buildScene(
        _single(
          rectangleRoom(
            id: 'a',
            width: 4,
            depth: 3,
            boxes: const [measured],
            placement: const RoomPlacement(x: 0, z: 0, rotationDegrees: 30),
          ),
        ),
      );
      expect(_codes(result), {SceneWarningCode.boxRotationApproximated});
      expect(_list(result.document, 'objects'), hasLength(1));
    });
  });

  test('every warning has a Spanish message', () {
    final result = buildScene(
      PropertyCapture(
        listingId: 'listing-1',
        rooms: [
          rectangleRoom(
            id: 'a',
            width: 4,
            depth: 3,
            height: RoomHeight.assumedDefault,
          ),
          rectangleRoom(
            id: 'b',
            name: 'Dormitorio',
            width: 3,
            depth: 3,
            placement: const RoomPlacement(x: 20, z: 0, rotationDegrees: 0),
          ),
        ],
        connections: const [],
        updatedAt: DateTime.utc(2026, 10, 21),
      ),
    );
    final messages = {for (final w in result.warnings) w.code: w.message};
    expect(
      messages[SceneWarningCode.assumedHeight],
      'La altura de «a» es supuesta (2.40 m), no medida. Ajustala si conocés '
      'el valor real.',
    );
    expect(
      messages[SceneWarningCode.roomNotConnected],
      '«Dormitorio» no está conectado con el resto de los ambientes. Conectalo '
      'mediante una puerta.',
    );
  });
}
