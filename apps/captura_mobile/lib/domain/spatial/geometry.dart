import 'dart:math' as math;

/// A point on the floor plane, in metres.
///
/// Spatial capture works on the ARCore x/z plane with y up. Orientation on
/// this plane is defined by the shoelace formula over (x, z): a polygon is
/// counter-clockwise when [signedArea] is positive. With that convention the
/// interior of a counter-clockwise polygon lies to the left of each edge, the
/// interior normal of an edge direction (dx, dz) is (-dz, dx) and the outward
/// normal is (dz, -dx).
class FloorPoint {
  const FloorPoint(this.x, this.z);

  factory FloorPoint.fromJson(Map<String, Object?> json) =>
      FloorPoint(readDouble(json, 'x'), readDouble(json, 'z'));

  final double x;
  final double z;

  FloorPoint operator +(FloorPoint other) =>
      FloorPoint(x + other.x, z + other.z);
  FloorPoint operator -(FloorPoint other) =>
      FloorPoint(x - other.x, z - other.z);
  FloorPoint scale(double factor) => FloorPoint(x * factor, z * factor);

  double dot(FloorPoint other) => x * other.x + z * other.z;

  /// z-component of the 2D cross product on the x/z plane.
  double cross(FloorPoint other) => x * other.z - z * other.x;

  double get length => math.sqrt(x * x + z * z);
  double distanceTo(FloorPoint other) => (this - other).length;

  /// Rotates this point around the origin by [radians] (positive turns +x
  /// towards +z).
  FloorPoint rotate(double radians) {
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return FloorPoint(x * cos - z * sin, x * sin + z * cos);
  }

  Map<String, Object?> toJson() => {'x': x, 'z': z};

  @override
  bool operator ==(Object other) =>
      other is FloorPoint && other.x == x && other.z == z;

  @override
  int get hashCode => Object.hash(x, z);

  @override
  String toString() => 'FloorPoint($x, $z)';
}

/// Shoelace signed area on the x/z plane; positive means counter-clockwise.
double signedArea(List<FloorPoint> polygon) {
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    sum += polygon[i].cross(polygon[(i + 1) % polygon.length]);
  }
  return sum / 2;
}

/// Unsigned area of [polygon] in square metres.
double polygonArea(List<FloorPoint> polygon) => signedArea(polygon).abs();

/// Length of each edge `i -> i + 1` (closing edge last), in metres.
List<double> edgeLengths(List<FloorPoint> polygon) => [
  for (var i = 0; i < polygon.length; i++)
    polygon[i].distanceTo(polygon[(i + 1) % polygon.length]),
];

/// Perimeter of the closed polygon, in metres.
double perimeter(List<FloorPoint> polygon) =>
    edgeLengths(polygon).fold(0.0, (sum, length) => sum + length);

/// Rounds [value] to [decimals] places, normalising `-0.0` to `0.0` so that
/// JSON output is stable.
double roundTo(double value, int decimals) {
  final factor = math.pow(10, decimals).toDouble();
  final rounded = (value * factor).round() / factor;
  return rounded == 0 ? 0.0 : rounded;
}

/// Whether segments `a-b` and `c-d` intersect, touching included.
bool segmentsIntersect(FloorPoint a, FloorPoint b, FloorPoint c, FloorPoint d) {
  const epsilon = 1e-12;
  int orientation(FloorPoint p, FloorPoint q, FloorPoint r) {
    final value = (q - p).cross(r - p);
    if (value.abs() < epsilon) return 0;
    return value > 0 ? 1 : -1;
  }

  bool onSegment(FloorPoint p, FloorPoint q, FloorPoint r) =>
      math.min(p.x, r.x) - epsilon <= q.x &&
      q.x <= math.max(p.x, r.x) + epsilon &&
      math.min(p.z, r.z) - epsilon <= q.z &&
      q.z <= math.max(p.z, r.z) + epsilon;

  final o1 = orientation(a, b, c);
  final o2 = orientation(a, b, d);
  final o3 = orientation(c, d, a);
  final o4 = orientation(c, d, b);
  if (o1 != o2 && o3 != o4) return true;
  if (o1 == 0 && onSegment(a, c, b)) return true;
  if (o2 == 0 && onSegment(a, d, b)) return true;
  if (o3 == 0 && onSegment(c, a, d)) return true;
  if (o4 == 0 && onSegment(c, b, d)) return true;
  return false;
}

/// Whether segments `a-b` and `c-d` cross at a single interior point of both.
bool segmentsCrossProperly(
  FloorPoint a,
  FloorPoint b,
  FloorPoint c,
  FloorPoint d,
) {
  const epsilon = 1e-9;
  final d1 = (b - a).cross(c - a);
  final d2 = (b - a).cross(d - a);
  final d3 = (d - c).cross(a - c);
  final d4 = (d - c).cross(b - c);
  return ((d1 > epsilon && d2 < -epsilon) || (d1 < -epsilon && d2 > epsilon)) &&
      ((d3 > epsilon && d4 < -epsilon) || (d3 < -epsilon && d4 > epsilon));
}

/// Even-odd point-in-polygon test (points on the boundary are unspecified).
bool pointInPolygon(FloorPoint point, List<FloorPoint> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final pi = polygon[i];
    final pj = polygon[j];
    if ((pi.z > point.z) != (pj.z > point.z) &&
        point.x < (pj.x - pi.x) * (point.z - pi.z) / (pj.z - pi.z) + pi.x) {
      inside = !inside;
    }
  }
  return inside;
}

/// Distance from [point] to segment `a-b`.
double distanceToSegment(FloorPoint point, FloorPoint a, FloorPoint b) {
  final ab = b - a;
  final lengthSquared = ab.dot(ab);
  if (lengthSquared == 0) return point.distanceTo(a);
  final t = ((point - a).dot(ab) / lengthSquared).clamp(0.0, 1.0);
  return point.distanceTo(a + ab.scale(t));
}

/// Reads a JSON number as a double, failing with a [FormatException].
double readDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('Expected a number at "$key"', json);
}

/// Reads an optional JSON number as a double.
double? readOptionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException('Expected a number or null at "$key"', json);
}

/// Casts a decoded JSON or platform-channel map to `Map<String, Object?>`.
Map<String, Object?> asJsonMap(Object? value, String key) {
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Expected an object at "$key"');
}

/// Casts a decoded JSON or platform-channel list.
List<Object?> asJsonList(Object? value, String key) {
  if (value is List) return value.cast<Object?>();
  throw FormatException('Expected a list at "$key"');
}
