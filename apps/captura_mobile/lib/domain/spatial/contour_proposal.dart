import 'dart:math' as math;

import 'geometry.dart';
import 'validation.dart';

/// A vertical ARCore plane projected onto the floor (world metres).
class ObservedWall {
  const ObservedWall({
    required this.start,
    required this.end,
    required this.area,
    required this.minY,
    required this.maxY,
  });

  factory ObservedWall.fromJson(Map<String, Object?> json) => ObservedWall(
    start: FloorPoint.fromJson(asJsonMap(json['start'], 'start')),
    end: FloorPoint.fromJson(asJsonMap(json['end'], 'end')),
    area: readDouble(json, 'area'),
    minY: readDouble(json, 'minY'),
    maxY: readDouble(json, 'maxY'),
  );

  final FloorPoint start;
  final FloorPoint end;
  final double area;
  final double minY;
  final double maxY;
}

/// What a walkthrough recorded (channel `observations`, mode `walkthrough`).
class WalkthroughObservations {
  const WalkthroughObservations({
    required this.floorY,
    required this.walls,
    required this.floors,
    required this.trajectory,
  });

  factory WalkthroughObservations.fromJson(Map<String, Object?> json) {
    List<FloorPoint> points(Object? raw, String name) => [
      for (final item in asJsonList(raw, name))
        FloorPoint.fromJson(asJsonMap(item, '$name[]')),
    ];
    return WalkthroughObservations(
      floorY: readDouble(json, 'floorY'),
      walls: [
        for (final wall in asJsonList(json['walls'], 'walls'))
          ObservedWall.fromJson(asJsonMap(wall, 'walls[]')),
      ],
      floors: [
        for (final floor in asJsonList(json['floors'], 'floors'))
          points(floor, 'floors[]'),
      ],
      trajectory: points(json['trajectory'], 'trajectory'),
    );
  }

  final double floorY;
  final List<ObservedWall> walls;
  final List<List<FloorPoint>> floors;
  final List<FloorPoint> trajectory;
}

/// Result of proposing a room contour from a walkthrough.
sealed class ContourProposal {
  const ContourProposal();
}

/// Corners in world metres (the same frame as a marked capture), ready to be
/// normalized like any other capture.
class ProposedContour extends ContourProposal {
  const ProposedContour({
    required this.corners,
    required this.observedWalls,
    required this.inferredEdges,
  });

  final List<FloorPoint> corners;

  /// Wall lines backed by detected planes, after merging fragments.
  final int observedWalls;

  /// Sides closed without any detected wall: their position is a guess the
  /// agent must check (reference measure or panel editor).
  final int inferredEdges;
}

/// The walkthrough cannot produce a contour; [message] is Spanish.
class ProposalFailed extends ContourProposal {
  const ProposalFailed(this.message);

  final String message;
}

const double _minWallLength = 0.3;
const double _snapTolerance = 12 * math.pi / 180;
const double _sameDirection = 3 * math.pi / 180;
const double _sameLineOffset = 0.15;
const double _minCornerAngle = 15 * math.pi / 180;
const double _maxCornerDistance = 20;

/// One merged wall line: direction angle in [0, π), signed offset along the
/// normal, and the observed extent along the direction.
class _Line {
  _Line(this.angle, this.offset, this.tMin, this.tMax, this.weight);

  final double angle;
  double offset;
  double tMin;
  double tMax;
  double weight;

  FloorPoint get direction => FloorPoint(math.cos(angle), math.sin(angle));
  FloorPoint get normal => FloorPoint(-math.sin(angle), math.cos(angle));
  double get length => tMax - tMin;

  FloorPoint at(double t) => direction.scale(t) + normal.scale(offset);
  FloorPoint get middle => at((tMin + tMax) / 2);
  FloorPoint project(FloorPoint p) => at(direction.dot(p));
}

double _normalizeAngle(double angle) {
  var a = angle % math.pi;
  if (a < 0) a += math.pi;
  return a;
}

double _angleGap(double a, double b) {
  final d = (a - b).abs() % math.pi;
  return math.min(d, math.pi - d);
}

/// Proposes the room contour of a walkthrough. Rooms are assumed to have
/// mostly square corners: observations within 12° of the dominant axes are
/// straightened, others are kept as observed.
ContourProposal proposeContour(WalkthroughObservations observations) {
  final walls = [
    for (final wall in observations.walls)
      if (wall.start.distanceTo(wall.end) >= _minWallLength) wall,
  ];
  if (walls.length < 3) return _tooFewWalls(walls.length);

  // Dominant axis: length-weighted circular mean of 4θ (period of 90°).
  var sumSin = 0.0;
  var sumCos = 0.0;
  for (final wall in walls) {
    final d = wall.end - wall.start;
    final theta = math.atan2(d.z, d.x);
    sumSin += d.length * math.sin(4 * theta);
    sumCos += d.length * math.cos(4 * theta);
  }
  final axis = math.atan2(sumSin, sumCos) / 4;

  final lines = <_Line>[];
  for (final wall in walls) {
    final d = wall.end - wall.start;
    var theta = math.atan2(d.z, d.x);
    final quarter = math.pi / 2;
    var diff = (theta - axis) % quarter;
    if (diff >= quarter / 2) diff -= quarter;
    if (diff < -quarter / 2) diff += quarter;
    if (diff.abs() <= _snapTolerance) theta -= diff;
    final angle = _normalizeAngle(theta);
    final line = _Line(angle, 0, 0, 0, d.length);
    final middle = (wall.start + wall.end).scale(0.5);
    line.offset = line.normal.dot(middle);
    final t1 = line.direction.dot(wall.start);
    final t2 = line.direction.dot(wall.end);
    line
      ..tMin = math.min(t1, t2)
      ..tMax = math.max(t1, t2);
    lines.add(line);
  }

  final merged = _merge(lines);
  final centre = _centre(observations, merged);
  final boundary = _dropInnerFaces(merged, centre);
  if (boundary.length < 3) return _tooFewWalls(boundary.length);

  double polar(_Line line) {
    final m = line.middle - centre;
    return math.atan2(m.z, m.x);
  }

  boundary.sort((a, b) => polar(a).compareTo(polar(b)));

  final corners = <FloorPoint>[];
  var inferred = 0;
  for (var i = 0; i < boundary.length; i++) {
    final a = boundary[i];
    final b = boundary[(i + 1) % boundary.length];
    if (_angleGap(a.angle, b.angle) >= _minCornerAngle) {
      final corner = _intersect(a, b);
      if (corner.distanceTo(centre) > _maxCornerDistance) {
        return const ProposalFailed(
          'Dos paredes detectadas se cruzan demasiado lejos del ambiente. '
          'Repetí el recorrido o usá el modo Marcar paredes.',
        );
      }
      corners.add(corner);
    } else {
      // Parallel neighbours: the wall between them was not detected. Close
      // the gap where the observations reach furthest towards it.
      var gap = polar(b) - polar(a);
      if (gap <= 0) gap += 2 * math.pi;
      final bisector = polar(a) + gap / 2;
      final towards = FloorPoint(math.cos(bisector), math.sin(bisector));
      final candidates = [
        a.at(a.tMin),
        a.at(a.tMax),
        b.at(b.tMin),
        b.at(b.tMax),
      ];
      candidates.sort(
        (p, q) =>
            (q - centre).dot(towards).compareTo((p - centre).dot(towards)),
      );
      final reach = candidates.first;
      corners
        ..add(a.project(reach))
        ..add(b.project(reach));
      inferred++;
    }
  }

  if (validateContour(corners).any((issue) => issue.blocking)) {
    return const ProposalFailed(
      'Las paredes detectadas no forman un contorno válido. Repetí el '
      'recorrido o usá el modo Marcar paredes.',
    );
  }
  return ProposedContour(
    corners: corners,
    observedWalls: boundary.length,
    inferredEdges: inferred,
  );
}

ProposalFailed _tooFewWalls(int count) => ProposalFailed(
  'Detectamos $count ${count == 1 ? 'pared' : 'paredes'}; hacen falta al '
  'menos 3. Recorré las que faltan apuntando a su base, o usá el modo '
  'Marcar paredes.',
);

/// Joins fragments of the same wall (ARCore often splits one wall into
/// several planes) into one line weighted by observed length.
List<_Line> _merge(List<_Line> lines) {
  final result = <_Line>[];
  for (final line in lines) {
    _Line? target;
    for (final candidate in result) {
      if (_angleGap(candidate.angle, line.angle) > _sameDirection) continue;
      // Express the line in the candidate's frame (directions may be opposite).
      final sign = candidate.direction.dot(line.direction) >= 0 ? 1.0 : -1.0;
      if ((candidate.offset - sign * line.offset).abs() <= _sameLineOffset) {
        target = candidate;
        break;
      }
    }
    if (target == null) {
      result.add(line);
      continue;
    }
    final sign = target.direction.dot(line.direction) >= 0 ? 1.0 : -1.0;
    final t1 = sign * line.tMin;
    final t2 = sign * line.tMax;
    final total = target.weight + line.weight;
    target
      ..offset =
          (target.offset * target.weight + sign * line.offset * line.weight) /
          total
      ..tMin = math.min(target.tMin, math.min(t1, t2))
      ..tMax = math.max(target.tMax, math.max(t1, t2))
      ..weight = total;
  }
  return result;
}

/// Room centre: floor polygons and the walked path describe the interior.
FloorPoint _centre(WalkthroughObservations observations, List<_Line> lines) {
  final points = [
    for (final floor in observations.floors) ...floor,
    ...observations.trajectory,
  ];
  if (points.isEmpty) {
    points.addAll([for (final line in lines) line.middle]);
  }
  var sum = const FloorPoint(0, 0);
  for (final point in points) {
    sum = sum + point;
  }
  return sum.scale(1 / points.length);
}

/// A vertical surface in front of a parallel wall on the same side of the
/// room (a wardrobe, a shelf) is not the room boundary: keep the outer one.
List<_Line> _dropInnerFaces(List<_Line> lines, FloorPoint centre) {
  final dropped = <_Line>{};
  for (final a in lines) {
    for (final b in lines) {
      if (identical(a, b) || dropped.contains(a) || dropped.contains(b)) {
        continue;
      }
      if (_angleGap(a.angle, b.angle) > _sameDirection) continue;
      final sign = a.direction.dot(b.direction) >= 0 ? 1.0 : -1.0;
      final aSide = a.offset - a.normal.dot(centre);
      final bSide = sign * b.offset - a.normal.dot(centre);
      if (aSide.sign != bSide.sign) continue;
      final bMin = math.min(sign * b.tMin, sign * b.tMax);
      final bMax = math.max(sign * b.tMin, sign * b.tMax);
      final overlap = math.min(a.tMax, bMax) - math.max(a.tMin, bMin);
      if (overlap <= 0.5 * math.min(a.length, b.length)) continue;
      dropped.add(aSide.abs() < bSide.abs() ? a : b);
    }
  }
  return [
    for (final line in lines)
      if (!dropped.contains(line)) line,
  ];
}

FloorPoint _intersect(_Line a, _Line b) {
  // Solve n_a·p = o_a and n_b·p = o_b.
  final na = a.normal;
  final nb = b.normal;
  final det = na.x * nb.z - na.z * nb.x;
  return FloorPoint(
    (a.offset * nb.z - na.z * b.offset) / det,
    (na.x * b.offset - a.offset * nb.x) / det,
  );
}
