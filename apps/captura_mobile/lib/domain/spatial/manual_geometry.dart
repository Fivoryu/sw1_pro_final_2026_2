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
    authoritativeLengths: true,
  );
}

CapturedRoom buildCalibratedManualSketchRoom({
  required String id,
  required String name,
  required List<FloorPoint> sketch,
  required int referenceEdge,
  required double referenceMeters,
  required double height,
}) => _buildCalibratedRoom(
  id: id,
  name: name,
  sketch: sketch,
  referenceEdge: referenceEdge,
  referenceMeters: referenceMeters,
  height: height,
  method: RoomAcquisitionMethod.manualSketch,
);

/// New PR4 wall-based sketch. Drawing coordinates are only a shape prior; no
/// metric wall is inferred or confirmed until the agent enters it explicitly.
CapturedRoom buildWallBasedManualSketchRoom({
  required String id,
  required String name,
  required List<FloorPoint> sketch,
  required double height,
}) => _buildShapePriorRoom(
  id: id,
  name: name,
  shape: sketch,
  height: height,
  method: RoomAcquisitionMethod.manualSketch,
);

/// Calibrates a floorplan trace stored as normalized image coordinates.
///
/// Normalized coordinates are independent per axis, so they are first mapped
/// back to source-image pixels with the real image size. Only then is a single
/// uniform metric scale applied, which keeps the aspect ratio of non-square
/// source images.
CapturedRoom buildCalibratedFloorplanTraceRoom({
  required String id,
  required String name,
  required List<FloorPoint> normalizedTrace,
  required int imageWidth,
  required int imageHeight,
  required int referenceEdge,
  required double referenceMeters,
  required double height,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) {
    throw ArgumentError('Trace source image size must be positive');
  }
  return _buildCalibratedRoom(
    id: id,
    name: name,
    sketch: [
      for (final point in normalizedTrace)
        FloorPoint(point.x * imageWidth, point.z * imageHeight),
    ],
    referenceEdge: referenceEdge,
    referenceMeters: referenceMeters,
    height: height,
    method: RoomAcquisitionMethod.floorplanTrace,
  );
}

/// New PR4 floorplan candidate. Image coordinates define topology and relative
/// shape only. All metric walls begin pending.
CapturedRoom buildWallBasedFloorplanRoom({
  required String id,
  required String name,
  required List<FloorPoint> normalizedTrace,
  required int imageWidth,
  required int imageHeight,
  required double height,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) {
    throw ArgumentError('Trace source image size must be positive');
  }
  return _buildShapePriorRoom(
    id: id,
    name: name,
    shape: [
      for (final point in normalizedTrace)
        FloorPoint(point.x * imageWidth, point.z * imageHeight),
    ],
    height: height,
    method: RoomAcquisitionMethod.floorplanTrace,
  );
}

CapturedRoom _buildShapePriorRoom({
  required String id,
  required String name,
  required List<FloorPoint> shape,
  required double height,
  required RoomAcquisitionMethod method,
}) {
  _validateIdentity(id, name, height);
  final raw = [...shape];
  if (raw.length > 1 && raw.first.distanceTo(raw.last) < 1e-9) raw.removeLast();
  if (raw.length < 3) throw ArgumentError('Invalid shape prior');
  var ordered = signedArea(raw) < 0
      ? [raw.first, ...raw.skip(1).toList().reversed]
      : raw;
  final origin = ordered.first;
  final first = ordered[1] - origin;
  final rotation = -math.atan2(first.z, first.x);
  ordered = [for (final point in ordered) (point - origin).rotate(rotation)];
  final lengths = edgeLengths(ordered);
  final longest = lengths.reduce(math.max);
  if (!longest.isFinite || longest <= 1e-9) {
    throw ArgumentError('Invalid shape prior');
  }
  ordered = [for (final point in ordered) point.scale(4 / longest)];
  return _manualRoom(
    id: id,
    name: name,
    height: height,
    corners: ordered,
    method: method,
    measurementMode: RoomMeasurementMode.wallConstraints,
  );
}

CapturedRoom _buildCalibratedRoom({
  required String id,
  required String name,
  required List<FloorPoint> sketch,
  required int referenceEdge,
  required double referenceMeters,
  required double height,
  required RoomAcquisitionMethod method,
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
    method: method,
    initialReference: ReferenceMeasurement(
      edgeIndex: referenceEdge,
      referenceMeters: referenceMeters,
    ),
    measurementMode: RoomMeasurementMode.legacyUniform,
  );
}

CapturedRoom _manualRoom({
  required String id,
  required String name,
  required double height,
  required List<FloorPoint> corners,
  required RoomAcquisitionMethod method,
  bool authoritativeLengths = false,
  ReferenceMeasurement? initialReference,
  RoomMeasurementMode measurementMode = RoomMeasurementMode.legacyUniform,
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
    references: authoritativeLengths
        ? [
            for (var index = 0; index < corners.length; index++)
              ReferenceMeasurement(
                edgeIndex: index,
                referenceMeters: edgeLengths(corners)[index],
              ),
          ]
        : [if (initialReference != null) initialReference],
    measurementMode: authoritativeLengths
        ? RoomMeasurementMode.wallConstraints
        : measurementMode,
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
