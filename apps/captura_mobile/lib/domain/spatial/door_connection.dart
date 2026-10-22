import 'dart:math' as math;

import 'capture_models.dart';
import 'geometry.dart';

/// Placement of [moving] that joins its door [movingOpeningId] to the door
/// [fixedOpeningId] of [fixed] (which keeps its own placement):
///
/// * the moving door edge becomes anti-parallel to the fixed door edge;
/// * both door centres line up along the wall;
/// * the interior faces are [wallThickness] apart, so the wall centrelines of
///   both rooms coincide and the scene builder welds them into one wall.
///
/// Throws an [ArgumentError] when an opening id is unknown or its edge is
/// degenerate.
RoomPlacement placementForConnection({
  required CapturedRoom fixed,
  required String fixedOpeningId,
  required CapturedRoom moving,
  required String movingOpeningId,
  required double wallThickness,
}) {
  final fixedDoor = _doorFrame(fixed.worldCorners(), fixed, fixedOpeningId);
  final movingDoor = _doorFrame(moving.corners, moving, movingOpeningId);

  final target = fixedDoor.direction.scale(-1);
  final radians =
      math.atan2(target.z, target.x) -
      math.atan2(movingDoor.direction.z, movingDoor.direction.x);
  var degrees = roundTo((radians * 180 / math.pi) % 360, 6);
  if (degrees >= 360) degrees -= 360;

  final outward = FloorPoint(fixedDoor.direction.z, -fixedDoor.direction.x);
  final targetCenter = fixedDoor.center + outward.scale(wallThickness);
  final rotatedCenter = movingDoor.center.rotate(degrees * math.pi / 180);
  final translation = targetCenter - rotatedCenter;
  return RoomPlacement(
    x: roundTo(translation.x, 6),
    z: roundTo(translation.z, 6),
    rotationDegrees: degrees,
  );
}

({FloorPoint center, FloorPoint direction}) _doorFrame(
  List<FloorPoint> corners,
  CapturedRoom room,
  String openingId,
) {
  final opening = room.openings.where((o) => o.id == openingId).firstOrNull;
  if (opening == null) {
    throw ArgumentError.value(openingId, 'openingId', 'Unknown opening');
  }
  if (opening.edgeIndex < 0 || opening.edgeIndex >= corners.length) {
    throw ArgumentError.value(openingId, 'openingId', 'Edge out of range');
  }
  final start = corners[opening.edgeIndex];
  final edge = corners[(opening.edgeIndex + 1) % corners.length] - start;
  if (edge.length == 0) {
    throw ArgumentError.value(openingId, 'openingId', 'Degenerate edge');
  }
  return (
    center: start + edge.scale(opening.position),
    direction: edge.scale(1 / edge.length),
  );
}
