import 'dart:math' as math;

import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/spatial_fixtures.dart';

/// World-frame door centre and edge direction of [openingId] in [room].
({FloorPoint center, FloorPoint direction}) _door(
  CapturedRoom room,
  String openingId,
) {
  final opening = room.openings.firstWhere((o) => o.id == openingId);
  final world = room.worldCorners();
  final start = world[opening.edgeIndex];
  final end = world[(opening.edgeIndex + 1) % world.length];
  final dx = end.x - start.x;
  final dz = end.z - start.z;
  final length = math.sqrt(dx * dx + dz * dz);
  return (
    center: FloorPoint(
      start.x + dx * opening.position,
      start.z + dz * opening.position,
    ),
    direction: FloorPoint(dx / length, dz / length),
  );
}

void main() {
  group('placementForConnection', () {
    test('places the moving room across the wall thickness, same rotation', () {
      final fixed = rectangleRoom(
        id: 'a',
        width: 4,
        depth: 3,
        openings: [door('da', 1)],
      );
      final moving = rectangleRoom(
        id: 'b',
        width: 3,
        depth: 3,
        openings: [door('db', 3)],
      );

      final placement = placementForConnection(
        fixed: fixed,
        fixedOpeningId: 'da',
        moving: moving,
        movingOpeningId: 'db',
        wallThickness: 0.15,
      );

      expect(placement.x, closeTo(4.15, 1e-9));
      expect(placement.z, closeTo(0, 1e-9));
      expect(placement.rotationDegrees, closeTo(0, 1e-9));
    });

    test('rotates the moving room so both door edges are anti-parallel', () {
      final fixed = rectangleRoom(
        id: 'a',
        width: 4,
        depth: 3,
        openings: [door('da', 1)],
        placement: const RoomPlacement(x: 10, z: 5, rotationDegrees: 30),
      );
      // Door on the moving room's first edge, off-centre.
      final moving = rectangleRoom(
        id: 'b',
        width: 3,
        depth: 2,
        openings: [door('db', 0, position: 0.3)],
      );

      final placement = placementForConnection(
        fixed: fixed,
        fixedOpeningId: 'da',
        moving: moving,
        movingOpeningId: 'db',
        wallThickness: 0.2,
      );
      final placed = moving.copyWith(placement: placement);

      final a = _door(fixed, 'da');
      final b = _door(placed, 'db');
      // Anti-parallel edges.
      expect(b.direction, closeToPoint(-a.direction.x, -a.direction.z, 1e-9));
      // Door centres aligned along the wall and separated by the thickness
      // along the fixed room's outward normal (dz, -dx).
      final outward = FloorPoint(a.direction.z, -a.direction.x);
      expect(
        b.center,
        closeToPoint(
          a.center.x + outward.x * 0.2,
          a.center.z + outward.z * 0.2,
          1e-6,
        ),
      );
      expect(placement.rotationDegrees, greaterThanOrEqualTo(0));
      expect(placement.rotationDegrees, lessThan(360));
    });

    test('unknown opening ids are rejected', () {
      final room = rectangleRoom(
        id: 'a',
        width: 4,
        depth: 3,
        openings: [door('da', 1)],
      );
      expect(
        () => placementForConnection(
          fixed: room,
          fixedOpeningId: 'missing',
          moving: room,
          movingOpeningId: 'da',
          wallThickness: 0.15,
        ),
        throwsArgumentError,
      );
    });
  });
}
