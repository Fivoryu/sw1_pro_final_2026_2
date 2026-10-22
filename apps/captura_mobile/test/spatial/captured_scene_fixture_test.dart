import 'dart:convert';
import 'dart:io';

import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/spatial_fixtures.dart';

const _fixturePath = '../../docs/api/f07-captured-scene-fixture.json';

Map<String, Object?> _metrics() => {
  'durationMs': 45000,
  'trackingLossCount': 0,
  'depthSupported': true,
  'cornerHitDistances': [1.4, 2.2, 2.6, 1.8],
  'floorY': -1.35,
};

/// Canonical two-room capture: a 4 m x 3 m living room captured with its
/// first wall along world +z, and a 3 m x 3 m bedroom captured in another
/// session at an arbitrary world pose, joined by a 0.9 m door.
PropertyCapture canonicalCapture() {
  final living = CapturedRoom.fromChannelResult(
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
      ],
      'metrics': _metrics(),
    },
  );
  final bedroom = CapturedRoom.fromChannelResult(
    id: 'bedroom',
    name: 'Dormitorio',
    result: {
      'outcome': 'captured',
      // 3 m x 3 m square rotated 30 degrees in its own session.
      'corners': [
        {'x': 5.0, 'z': 5.0},
        {'x': 7.598076211353316, 'z': 6.5},
        {'x': 6.098076211353316, 'z': 9.098076211353316},
        {'x': 3.5, 'z': 7.598076211353316},
      ],
      'height': null,
      'boxes': <Object?>[],
      'metrics': _metrics(),
    },
  );

  final livingWithOpenings = living.copyWith(
    openings: const [
      RoomOpening(
        id: 'living-door',
        edgeIndex: 1,
        position: 0.5,
        width: 0.9,
        height: 2.1,
        type: OpeningType.door,
      ),
      RoomOpening(
        id: 'living-window',
        edgeIndex: 2,
        position: 0.5,
        width: 1.2,
        height: 1,
        type: OpeningType.window,
      ),
    ],
  );
  final bedroomWithDoor = bedroom.copyWith(
    openings: const [
      RoomOpening(
        id: 'bedroom-door',
        edgeIndex: 3,
        position: 0.5,
        width: 0.9,
        height: 2.1,
        type: OpeningType.door,
      ),
    ],
  );
  final placement = placementForConnection(
    fixed: livingWithOpenings,
    fixedOpeningId: 'living-door',
    moving: bedroomWithDoor,
    movingOpeningId: 'bedroom-door',
    wallThickness: 0.15,
  );

  return PropertyCapture(
    listingId: 'listing-f07',
    rooms: [
      livingWithOpenings,
      bedroomWithDoor.copyWith(placement: placement),
    ],
    connections: const [
      DoorConnection(
        roomA: 'living',
        openingA: 'living-door',
        roomB: 'bedroom',
        openingB: 'bedroom-door',
      ),
    ],
    updatedAt: DateTime.utc(2026, 10, 21, 12),
  );
}

void main() {
  test('the canonical two-room capture matches the shared fixture', () {
    final result = buildScene(canonicalCapture());

    final fixture =
        jsonDecode(File(_fixturePath).readAsStringSync())
            as Map<String, Object?>;
    expect(result.document, fixture);
    expectEveryRoomCloses(result.document);
    expect(result.warnings.map((warning) => warning.code), [
      SceneWarningCode.assumedHeight,
    ]);
  });

  test('the fixture file is the pretty-printed document', () {
    final document = buildSceneDocument(canonicalCapture());
    final pretty = '${const JsonEncoder.withIndent('  ').convert(document)}\n';
    final stored = File(
      _fixturePath,
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(stored, pretty);
  });
}
