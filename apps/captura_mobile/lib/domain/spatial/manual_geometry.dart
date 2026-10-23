import 'dart:math' as math;

import 'capture_models.dart';
import 'geometry.dart';
import 'validation.dart';

enum RecessCorner { upperLeft, upperRight, lowerLeft, lowerRight }

CapturedRoom buildManualLRoom({
  required String id,
  required String name,
  required double totalWidth,
  required double totalDepth,
  required double recessWidth,
  required double recessDepth,
  required double height,
  required RecessCorner recess,
}) {
  _validateIdentity(id, name, height);
  final values = [totalWidth, totalDepth, recessWidth, recessDepth];
  if (values.any((value) => !value.isFinite || value <= 0) ||
      recessWidth >= totalWidth ||
      recessDepth >= totalDepth) {
    throw ArgumentError('Invalid L-shaped room dimensions');
  }
  final corners = switch (recess) {
    RecessCorner.upperRight => [
      const FloorPoint(0, 0),
      FloorPoint(totalWidth, 0),
      FloorPoint(totalWidth, totalDepth - recessDepth),
      FloorPoint(totalWidth - recessWidth, totalDepth - recessDepth),
      FloorPoint(totalWidth - recessWidth, totalDepth),
      FloorPoint(0, totalDepth),
    ],
    RecessCorner.upperLeft => [
      const FloorPoint(0, 0),
      FloorPoint(totalWidth, 0),
      FloorPoint(totalWidth, totalDepth),
      FloorPoint(recessWidth, totalDepth),
      FloorPoint(recessWidth, totalDepth - recessDepth),
      FloorPoint(0, totalDepth - recessDepth),
    ],
    RecessCorner.lowerRight => [
      const FloorPoint(0, 0),
      FloorPoint(totalWidth - recessWidth, 0),
      FloorPoint(totalWidth - recessWidth, recessDepth),
      FloorPoint(totalWidth, recessDepth),
      FloorPoint(totalWidth, totalDepth),
      FloorPoint(0, totalDepth),
    ],
    RecessCorner.lowerLeft => [
      FloorPoint(0, recessDepth),
      FloorPoint(recessWidth, recessDepth),
      FloorPoint(recessWidth, 0),
      FloorPoint(totalWidth, 0),
      FloorPoint(totalWidth, totalDepth),
      FloorPoint(0, totalDepth),
    ],
  };
  return _manualRoom(
    id: id,
    name: name,
    height: height,
    corners: corners,
    method: RoomAcquisitionMethod.manual,
  );
}

CapturedRoom buildCalibratedManualSketchRoom({
  required String id,
  required String name,
  required List<FloorPoint> sketch,
  required int referenceEdge,
  required double referenceMeters,
  required double height,
}) {
  _validateIdentity(id, name, height);
  if (!referenceMeters.isFinite || referenceMeters <= 0) {
    throw ArgumentError('Calibration measurement must be positive');
  }
  final raw = [...sketch];
  if (raw.length > 1 && raw.first.distanceTo(raw.last) < 1e-9) raw.removeLast();
  if (raw.length < 3 || referenceEdge < 0 || referenceEdge >= raw.length) {
    throw ArgumentError('Invalid sketch contour or reference edge');
  }
  final selectedLength = raw[referenceEdge].distanceTo(
    raw[(referenceEdge + 1) % raw.length],
  );
  if (!selectedLength.isFinite || selectedLength <= 1e-9) {
    throw ArgumentError('Calibration edge has zero length');
  }
  var ordered = signedArea(raw) < 0
      ? [raw.first, ...raw.skip(1).toList().reversed]
      : raw;
  final origin = ordered.first;
  final first = ordered[1] - origin;
  final rotation = -math.atan2(first.z, first.x);
  final scale = referenceMeters / selectedLength;
  ordered = [
    for (final point in ordered) (point - origin).rotate(rotation).scale(scale),
  ];
  return _manualRoom(
    id: id,
    name: name,
    height: height,
    corners: ordered,
    method: RoomAcquisitionMethod.manualSketch,
  );
}

CapturedRoom _manualRoom({
  required String id,
  required String name,
  required double height,
  required List<FloorPoint> corners,
  required RoomAcquisitionMethod method,
}) {
  final blocking = validateContour(corners).where((issue) => issue.blocking);
  if (blocking.isNotEmpty) {
    throw ArgumentError('Invalid manual room: ${blocking.first.code}');
  }
  return CapturedRoom(
    id: id,
    name: name.trim(),
    corners: corners,
    height: RoomHeight(height, HeightSource.manual),
    openings: const [],
    boxes: const [],
    references: const [],
    acquisition: RoomAcquisition(method: method),
  );
}

void _validateIdentity(String id, String name, double height) {
  if (id.trim().isEmpty || name.trim().isEmpty) {
    throw ArgumentError('Room id and name are required');
  }
  if (!height.isFinite || height <= 0) {
    throw ArgumentError('Room height must be positive');
  }
}
