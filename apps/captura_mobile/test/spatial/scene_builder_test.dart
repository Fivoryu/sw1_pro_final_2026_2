import 'dart:convert';

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
    'wall-based F07 scene preserves independent walls and physical openings',
    () {
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
            id: 'door-a',
            wallId: 'wall-a',
            width: .9,
            height: 2.1,
            offsetFromWallStartM: .5,
            type: OpeningType.door,
            sillHeight: 0,
          ),
          RoomOpening(
            id: 'window-b',
            wallId: 'wall-b',
            width: 1.2,
            height: 1.1,
            offsetFromWallStartM: .4,
            type: OpeningType.window,
            sillHeight: .8,
          ),
        ],
        boxes: [],
        references: [],
        acquisition: RoomAcquisition(
          method: RoomAcquisitionMethod.floorplanTrace,
        ),
        wallDimensions: [
          CapturedWallDimension(wallId: 'wall-a', lengthM: 4, heightM: 2.4),
          CapturedWallDimension(wallId: 'wall-b', lengthM: 3, heightM: 2.8),
          CapturedWallDimension(wallId: 'wall-c', lengthM: 4, heightM: 2.5),
          CapturedWallDimension(wallId: 'wall-d', lengthM: 3, heightM: 2.6),
        ],
        measurementMode: RoomMeasurementMode.wallConstraints,
      );

      final document = buildSceneDocument(_single(room));
      final walls = _list(document, 'walls');
      expect(walls.map((wall) => wall['id']), [
        'wall-a',
        'wall-b',
        'wall-c',
        'wall-d',
      ]);
      expect(walls.map((wall) => wall['height']), [2.4, 2.8, 2.5, 2.6]);
      expect(walls.map((wall) => wall['lengthM']), [4.0, 3.0, 4.0, 3.0]);

      final openings = _list(document, 'openings');
      expect(openings, hasLength(2));
      expect(
        openings.firstWhere((opening) => opening['id'] == 'door-a'),
        allOf(
          containsPair('wallId', 'wall-a'),
          containsPair('sourceWallId', 'wall-a'),
          containsPair('offsetFromWallStartM', .5),
          containsPair('width', .9),
          containsPair('height', 2.1),
          containsPair('type', 'door'),
        ),
      );
      expect(
        openings.firstWhere((opening) => opening['id'] == 'window-b'),
        allOf(
          containsPair('wallId', 'wall-b'),
          containsPair('sourceWallId', 'wall-b'),
          containsPair('offsetFromWallStartM', .4),
          containsPair('width', 1.2),
          containsPair('height', 1.1),
          containsPair('sillHeight', .8),
          containsPair('type', 'window'),
        ),
      );

      final roundTrip =
          jsonDecode(jsonEncode(document)) as Map<String, Object?>;
      expect(roundTrip, document);
    },
  );


  test('canonical opening shared by room projections is emitted only once', () {
    const opening = RoomOpening(
      id: 'shared-door',
      wallId: 'shared-wall',
      width: .9,
      height: 2.1,
      offsetFromWallStartM: .5,
      type: OpeningType.door,
      sillHeight: 0,
    );
    const dimensions = [
      CapturedWallDimension(
        wallId: 'shared-wall',
        lengthM: 4,
        heightM: 2.6,
      ),
      CapturedWallDimension(wallId: 'wall-b', lengthM: 3, heightM: 2.6),
      CapturedWallDimension(wallId: 'wall-c', lengthM: 4, heightM: 2.6),
      CapturedWallDimension(wallId: 'wall-d', lengthM: 3, heightM: 2.6),
    ];
    const corners = [
      FloorPoint(0, 0),
      FloorPoint(4, 0),
      FloorPoint(4, 3),
      FloorPoint(0, 3),
    ];
    const first = CapturedRoom(
      id: 'a',
      name: 'A',
      corners: corners,
      openings: [opening],
      boxes: [],
      references: [],
      acquisition: RoomAcquisition(method: RoomAcquisitionMethod.floorplanTrace),
      wallDimensions: dimensions,
      measurementMode: RoomMeasurementMode.wallConstraints,
    );
    const second = CapturedRoom(
      id: 'b',
      name: 'B',
      corners: corners,
      openings: [opening],
      boxes: [],
      references: [],
      acquisition: RoomAcquisition(method: RoomAcquisitionMethod.floorplanTrace),
      wallDimensions: dimensions,
      measurementMode: RoomMeasurementMode.wallConstraints,
    );
    final capture = PropertyCapture(
      listingId: 'listing-1',
      rooms: const [first, second],
      connections: const [],
      updatedAt: DateTime.utc(2026, 10, 21),
    );

    final document = buildSceneDocument(capture);

    final openings = _list(document, 'openings');
    expect(openings, hasLength(1));
    expect(openings.single['id'], 'shared-door');
  });

  test('legacy window default is materialized before scene generation', () {
    const historical = CapturedRoom(
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
          width: 1.2,
          height: 1.1,
          type: OpeningType.window,
        ),
      ],
      boxes: [],
      references: [],
      acquisition: RoomAcquisition(method: RoomAcquisitionMethod.manual),
    );

    final restored = CapturedRoom.fromJson(historical.toJson());
    expect(restored.openings.single.explicitSillHeight, .9);
    final result = buildScene(_single(restored));
    final opening = _list(result.document, 'openings').single;
    expect(opening['id'], 'window-1');
    expect(opening['sillHeight'], .9);
    expect(_codes(result), isNot(contains(SceneWarningCode.openingIncomplete)));
  });

  test('new wall-based window without sill stays incomplete', () {
    const room = CapturedRoom(
      id: 'new',
      name: 'New',
      corners: [
        FloorPoint(0, 0),
        FloorPoint(4, 0),
        FloorPoint(4, 3),
        FloorPoint(0, 3),
      ],
      openings: [
        RoomOpening(
          id: 'new-window',
          wallId: 'a',
          offsetFromWallStartM: .5,
          width: 1.2,
          height: 1.1,
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
        CapturedWallDimension(wallId: 'b', lengthM: 3, heightM: 2.4),
        CapturedWallDimension(wallId: 'c', lengthM: 4, heightM: 2.4),
        CapturedWallDimension(wallId: 'd', lengthM: 3, heightM: 2.4),
      ],
      measurementMode: RoomMeasurementMode.wallConstraints,
    );

    final result = buildScene(_single(room));
    expect(_codes(result), contains(SceneWarningCode.openingIncomplete));
    expect(_list(result.document, 'openings'), isEmpty);
  });

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
    // The joined wall has two different physical height values. The scene
    // keeps its first height, but the conflict must be reported for review.
    expect(_codes(result), {
      SceneWarningCode.assumedHeight,
      SceneWarningCode.wallDimensionConflict,
    });
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
