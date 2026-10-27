import 'capture_models.dart';
import 'geometry.dart';
import 'validation.dart';

/// Creates an axis-aligned rectangular room from authoritative measurements.
///
/// The contour follows the domain's positive counter-clockwise x/z
/// convention. No scale reference or ARCore metric is needed because the
/// entered dimensions already define the real-world scale.
CapturedRoom buildManualRectangularRoom({
  required String id,
  required String name,
  required double length,
  required double width,
  required double height,
}) {
  if (id.trim().isEmpty) {
    throw ArgumentError.value(id, 'id', 'must not be empty');
  }
  if (name.trim().isEmpty) {
    throw ArgumentError.value(name, 'name', 'must not be empty');
  }
  if (!length.isFinite || !width.isFinite || !height.isFinite) {
    throw ArgumentError('Room dimensions must be finite');
  }
  if (height <= 0) {
    throw ArgumentError.value(height, 'height', 'must be greater than zero');
  }

  final corners = [
    const FloorPoint(0, 0),
    FloorPoint(length, 0),
    FloorPoint(length, width),
    FloorPoint(0, width),
  ];
  final blocking = validateContour(corners).where((issue) => issue.blocking);
  if (blocking.isNotEmpty) {
    throw ArgumentError('Invalid rectangular room: ${blocking.first.code}');
  }

  return CapturedRoom(
    id: id,
    name: name.trim(),
    corners: corners,
    height: RoomHeight(height, HeightSource.manual),
    openings: const [],
    boxes: const [],
    references: [
      ReferenceMeasurement(edgeIndex: 0, referenceMeters: length),
      ReferenceMeasurement(edgeIndex: 1, referenceMeters: width),
      ReferenceMeasurement(edgeIndex: 2, referenceMeters: length),
      ReferenceMeasurement(edgeIndex: 3, referenceMeters: width),
    ],
    measurementMode: RoomMeasurementMode.wallConstraints,
    acquisition: const RoomAcquisition(method: RoomAcquisitionMethod.manual),
  );
}
