import 'dart:math' as math;

import 'geometry.dart';

/// Small, trace-only perimeter editing primitives. They preserve contour order
/// and never create canonical room geometry by themselves.
bool isSimpleTraceContour(List<FloorPoint> points) {
  if (points.length < 3 || polygonArea(points) <= 1e-9) return false;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    if (a.distanceTo(b) <= 1e-6) return false;
    for (var j = i + 1; j < points.length; j++) {
      if (j == i ||
          (j + 1) % points.length == i ||
          (i + 1) % points.length == j) {
        continue;
      }
      if (segmentsIntersect(a, b, points[j], points[(j + 1) % points.length])) {
        return false;
      }
    }
  }
  return true;
}

List<FloorPoint>? moveTraceVertex(
  List<FloorPoint> points,
  int vertex,
  FloorPoint replacement,
) {
  if (vertex < 0 || vertex >= points.length) return null;
  final next = [...points]..[vertex] = replacement;
  return isSimpleTraceContour(next) ? next : null;
}

List<FloorPoint>? splitTraceWall(
  List<FloorPoint> points,
  int edgeIndex,
  FloorPoint point,
) {
  if (edgeIndex < 0 || edgeIndex >= points.length) return null;
  final a = points[edgeIndex];
  final b = points[(edgeIndex + 1) % points.length];
  if (distanceToSegment(point, a, b) > 1e-4 ||
      point.distanceTo(a) <= 1e-5 ||
      point.distanceTo(b) <= 1e-5) {
    return null;
  }
  final next = [...points]..insert(edgeIndex + 1, point);
  return isSimpleTraceContour(next) ? next : null;
}

/// The two walls around [vertex] can merge only as a near-straight line.
bool canMergeTraceWalls(List<FloorPoint> points, int vertex) {
  if (points.length <= 3 || vertex < 0 || vertex >= points.length) return false;
  final previous = points[(vertex - 1 + points.length) % points.length];
  final current = points[vertex];
  final following = points[(vertex + 1) % points.length];
  final first = current - previous;
  final second = following - current;
  final lengths = first.length * second.length;
  if (lengths <= 1e-9) return false;
  // About 8 degrees: intentionally conservative around real corners.
  return (first.cross(second).abs() / lengths) <= math.sin(8 * math.pi / 180) &&
      first.dot(second) > 0;
}

List<FloorPoint>? mergeTraceWalls(List<FloorPoint> points, int vertex) {
  if (!canMergeTraceWalls(points, vertex)) return null;
  final next = [...points]..removeAt(vertex);
  return isSimpleTraceContour(next) ? next : null;
}

double projectTracePosition(
  FloorPoint point,
  FloorPoint start,
  FloorPoint end,
) {
  final edge = end - start;
  final squared = edge.dot(edge);
  if (squared <= 1e-12) return 0.5;
  return ((point - start).dot(edge) / squared).clamp(0.0, 1.0);
}
