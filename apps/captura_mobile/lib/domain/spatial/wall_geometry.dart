import 'capture_models.dart';
import 'geometry.dart';
import 'validation.dart';

String wallLabel(int edgeIndex) => 'Pared ${edgeIndex + 1}';

const double wallConstraintTolerance = 1e-4;

class WallGeometryResult {
  const WallGeometryResult._({this.corners, this.message});
  const WallGeometryResult.coherent(List<FloorPoint> value)
    : this._(corners: value);
  const WallGeometryResult.inconsistent(String value) : this._(message: value);

  final List<FloorPoint>? corners;
  final String? message;
  bool get isCoherent => corners != null;
}

const _inconsistent = WallGeometryResult.inconsistent(
  'Las medidas ingresadas no permiten cerrar el ambiente. Revisá las paredes marcadas.',
);

/// Reconciles a simple polygon with independent confirmed wall lengths.
///
/// The original vertices seed this small position-based solver, preserving the
/// approximate shape without forcing arbitrary walls onto orthogonal axes.
/// Confirmed lengths are hard constraints, unconfirmed edges remain free,
/// vertex zero removes translation drift, and wall ordering never changes.
WallGeometryResult fitConfirmedWallLengths(CapturedRoom room) {
  if (room.measurementMode != RoomMeasurementMode.wallConstraints ||
      room.references.isEmpty) {
    return WallGeometryResult.coherent(room.corners);
  }
  final count = room.corners.length;
  if (count < 3) return _inconsistent;
  final confirmed = <int, double>{};
  for (final reference in room.references) {
    if (reference.edgeIndex < 0 ||
        reference.edgeIndex >= count ||
        !reference.referenceMeters.isFinite ||
        reference.referenceMeters < minEdgeLength) {
      return _inconsistent;
    }
    confirmed[reference.edgeIndex] = reference.referenceMeters;
  }

  if (confirmed.length == count) {
    final lengths = confirmed.values.toList();
    final longest = lengths.reduce((a, b) => a > b ? a : b);
    final total = lengths.fold<double>(0, (sum, value) => sum + value);
    if (longest >= total - longest - wallConstraintTolerance) {
      return _inconsistent;
    }
  }

  final orthogonal = _orthogonalDirections(room.corners);
  if (orthogonal != null) {
    return _fitOrthogonal(room, confirmed, orthogonal);
  }

  final points = [...room.corners];
  final anchor = points.first;
  for (var iteration = 0; iteration < 4000; iteration++) {
    final entries = iteration.isEven
        ? confirmed.entries
        : confirmed.entries.toList().reversed;
    for (final entry in entries) {
      final startIndex = entry.key;
      final endIndex = (startIndex + 1) % count;
      final start = points[startIndex];
      final end = points[endIndex];
      final delta = end - start;
      final distance = delta.length;
      if (!distance.isFinite || distance <= 1e-12) return _inconsistent;
      final correction = delta.scale((distance - entry.value) / distance);
      if (startIndex == 0) {
        points[endIndex] = end - correction;
      } else if (endIndex == 0) {
        points[startIndex] = start + correction;
      } else {
        points[startIndex] = start + correction.scale(0.5);
        points[endIndex] = end - correction.scale(0.5);
      }
    }
    points[0] = anchor;
    if (_maximumError(points, confirmed) <= wallConstraintTolerance) break;
  }

  if (_maximumError(points, confirmed) > wallConstraintTolerance ||
      validateContour(points).any((issue) => issue.blocking) ||
      signedArea(points) <= 0) {
    return _inconsistent;
  }
  return WallGeometryResult.coherent(List.unmodifiable(points));
}

List<FloorPoint>? _orthogonalDirections(List<FloorPoint> source) {
  final directions = <FloorPoint>[];
  for (var index = 0; index < source.length; index++) {
    final delta = source[(index + 1) % source.length] - source[index];
    final minor = delta.x.abs() < delta.z.abs() ? delta.x.abs() : delta.z.abs();
    final major = delta.x.abs() > delta.z.abs() ? delta.x.abs() : delta.z.abs();
    if (major <= 1e-9 || minor / major > 0.2) return null;
    directions.add(
      delta.x.abs() >= delta.z.abs()
          ? FloorPoint(delta.x >= 0 ? 1 : -1, 0)
          : FloorPoint(0, delta.z >= 0 ? 1 : -1),
    );
  }
  return directions;
}

WallGeometryResult _fitOrthogonal(
  CapturedRoom room,
  Map<int, double> confirmed,
  List<FloorPoint> directions,
) {
  final lengths = edgeLengths(room.corners);
  for (final entry in confirmed.entries) {
    lengths[entry.key] = entry.value;
  }

  for (final axisX in [true, false]) {
    var signedTotal = 0.0;
    final adjustable = <int>[];
    for (var index = 0; index < lengths.length; index++) {
      final direction = directions[index];
      final component = axisX ? direction.x : direction.z;
      if (component == 0) continue;
      signedTotal += component * lengths[index];
      if (!confirmed.containsKey(index)) adjustable.add(index);
    }
    if (signedTotal.abs() <= wallConstraintTolerance) continue;
    if (adjustable.isEmpty) return _inconsistent;

    final share = signedTotal / adjustable.length;
    for (final index in adjustable) {
      final component = axisX ? directions[index].x : directions[index].z;
      lengths[index] -= share / component;
      if (lengths[index] < minEdgeLength) return _inconsistent;
    }
  }

  final points = <FloorPoint>[room.corners.first];
  for (var index = 0; index < room.corners.length - 1; index++) {
    points.add(points.last + directions[index].scale(lengths[index]));
  }
  if (_maximumError(points, confirmed) > wallConstraintTolerance ||
      validateContour(points).any((issue) => issue.blocking) ||
      signedArea(points) <= 0) {
    return _inconsistent;
  }
  return WallGeometryResult.coherent(List.unmodifiable(points));
}

double _maximumError(List<FloorPoint> points, Map<int, double> confirmed) {
  var maximum = 0.0;
  for (final entry in confirmed.entries) {
    final actual = points[entry.key].distanceTo(
      points[(entry.key + 1) % points.length],
    );
    final error = (actual - entry.value).abs();
    if (error > maximum) maximum = error;
  }
  return maximum;
}

bool hasCompleteWallMeasurements(CapturedRoom room) =>
    room.measurementMode != RoomMeasurementMode.wallConstraints ||
    ({for (final value in room.references) value.edgeIndex}.length ==
        room.corners.length);

double openingPositionMetres(CapturedRoom room, RoomOpening opening) =>
    opening.position * edgeLengths(room.corners)[opening.edgeIndex];

double normalizedOpeningPosition({
  required double wallLength,
  required double openingWidth,
  required double positionMetres,
}) {
  if (wallLength <= 0 || openingWidth <= 0 || openingWidth > wallLength) {
    return 0.5;
  }
  final half = openingWidth / 2;
  return positionMetres.clamp(half, wallLength - half) / wallLength;
}
