import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chains the walls of [roomId] the way the panel's `roomPolygon` does:
/// consecutive walls must share an endpoint with EXACT coordinate equality,
/// reversed walls are tolerated, and the chain must return to its start.
///
/// Returns the polygon (without the repeated closing vertex) or null when the
/// room does not close.
List<({num x, num z})>? chainRoom(
  Map<String, Object?> document,
  String roomId,
) {
  final rooms = (document['rooms']! as List).cast<Map<String, Object?>>();
  final room = rooms.firstWhere((candidate) => candidate['id'] == roomId);
  final wallIds = (room['wallIds']! as List).cast<String>();
  if (wallIds.length < 3 || wallIds.toSet().length != wallIds.length) {
    return null;
  }
  final walls = {
    for (final wall
        in (document['walls']! as List).cast<Map<String, Object?>>())
      wall['id']! as String: wall,
  };
  ({num x, num z}) point(Object? raw) {
    final map = raw! as Map<String, Object?>;
    return (x: map['x']! as num, z: map['z']! as num);
  }

  final chain = wallIds.map((id) => walls[id]).toList();
  if (chain.any((wall) => wall == null)) return null;
  for (final reverseFirst in [false, true]) {
    final first = chain.first!;
    final start = point(reverseFirst ? first['end'] : first['start']);
    var current = point(reverseFirst ? first['start'] : first['end']);
    final polygon = [start, current];
    var valid = true;
    for (final wall in chain.skip(1)) {
      final wallStart = point(wall!['start']);
      final wallEnd = point(wall['end']);
      if (wallStart == current) {
        current = wallEnd;
      } else if (wallEnd == current) {
        current = wallStart;
      } else {
        valid = false;
        break;
      }
      polygon.add(current);
    }
    if (valid && current == start) {
      polygon.removeLast();
      return polygon;
    }
  }
  return null;
}

/// Asserts that every room of [document] closes with exact endpoint equality.
void expectEveryRoomCloses(Map<String, Object?> document) {
  for (final room
      in (document['rooms']! as List).cast<Map<String, Object?>>()) {
    expect(
      chainRoom(document, room['id']! as String),
      isNotNull,
      reason: 'room ${room['id']} must close',
    );
  }
}

Matcher closeToPoint(double x, double z, [double tolerance = 1e-6]) =>
    isA<FloorPoint>()
        .having((point) => point.x, 'x', closeTo(x, tolerance))
        .having((point) => point.z, 'z', closeTo(z, tolerance));

const CaptureMetrics sampleMetrics = CaptureMetrics(
  durationMs: 42000,
  trackingLossCount: 1,
  depthSupported: true,
  cornerHitDistances: [1.2, 1.5, 2.1, 1.9],
  floorY: -1.31,
);

/// A rectangular room already in its room-local frame.
CapturedRoom rectangleRoom({
  required String id,
  required double width,
  required double depth,
  RoomHeight height = const RoomHeight(2.5, HeightSource.ceilingPlane),
  List<RoomOpening> openings = const [],
  List<OccupancyBox> boxes = const [],
  RoomPlacement placement = RoomPlacement.identity,
  String? name,
}) => CapturedRoom(
  id: id,
  name: name ?? id,
  corners: [
    const FloorPoint(0, 0),
    FloorPoint(width, 0),
    FloorPoint(width, depth),
    FloorPoint(0, depth),
  ],
  height: height,
  openings: openings,
  boxes: boxes,
  references: const [],
  metrics: sampleMetrics,
  placement: placement,
);

RoomOpening door(String id, int edgeIndex, {double position = 0.5}) =>
    RoomOpening(
      id: id,
      edgeIndex: edgeIndex,
      position: position,
      width: 0.9,
      height: 2.1,
      type: OpeningType.door,
    );

/// Builds a two-room capture where [moving] is placed through the door
/// connection on [fixed]'s east wall (edge 1) and [moving]'s west wall (edge 3).
PropertyCapture connectedPair(CapturedRoom fixed, CapturedRoom moving) {
  const thickness = 0.15;
  final placement = placementForConnection(
    fixed: fixed,
    fixedOpeningId: fixed.openings.first.id,
    moving: moving,
    movingOpeningId: moving.openings.first.id,
    wallThickness: thickness,
  );
  return PropertyCapture(
    listingId: 'listing-1',
    rooms: [
      fixed,
      moving.copyWith(placement: placement),
    ],
    connections: [
      DoorConnection(
        roomA: fixed.id,
        openingA: fixed.openings.first.id,
        roomB: moving.id,
        openingB: moving.openings.first.id,
      ),
    ],
    wallThickness: thickness,
    updatedAt: DateTime.utc(2026, 10, 21, 12),
  );
}
