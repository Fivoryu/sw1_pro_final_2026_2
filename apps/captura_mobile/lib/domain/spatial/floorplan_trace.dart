import 'dart:math' as math;

import 'geometry.dart';

FloorPoint? normalizedTracePoint({
  required double sceneX,
  required double sceneY,
  required double viewportWidth,
  required double viewportHeight,
  required double imageWidth,
  required double imageHeight,
}) {
  if ([
    viewportWidth,
    viewportHeight,
    imageWidth,
    imageHeight,
  ].any((value) => !value.isFinite || value <= 0)) {
    return null;
  }
  final scale = (viewportWidth / imageWidth) < (viewportHeight / imageHeight)
      ? viewportWidth / imageWidth
      : viewportHeight / imageHeight;
  final shownWidth = imageWidth * scale;
  final shownHeight = imageHeight * scale;
  final left = (viewportWidth - shownWidth) / 2;
  final top = (viewportHeight - shownHeight) / 2;
  if (sceneX < left ||
      sceneY < top ||
      sceneX > left + shownWidth ||
      sceneY > top + shownHeight) {
    return null;
  }
  return FloorPoint((sceneX - left) / shownWidth, (sceneY - top) / shownHeight);
}

/// Finds a traced vertex using a circular tolerance in rendered image pixels.
int? nearestTraceVertex({
  required FloorPoint point,
  required List<FloorPoint> vertices,
  required double renderedImageWidth,
  required double renderedImageHeight,
  double tolerancePixels = 24,
}) {
  if (renderedImageWidth <= 0 || renderedImageHeight <= 0) return null;
  var best = tolerancePixels;
  int? selected;
  for (var i = 0; i < vertices.length; i++) {
    final dx = (vertices[i].x - point.x) * renderedImageWidth;
    final dz = (vertices[i].z - point.z) * renderedImageHeight;
    final distance = math.sqrt(dx * dx + dz * dz);
    if (distance < best) {
      best = distance;
      selected = i;
    }
  }
  return selected;
}

int? nearestTraceEdge({
  required FloorPoint point,
  required List<FloorPoint> vertices,
  required double renderedImageWidth,
  required double renderedImageHeight,
  double tolerancePixels = 28,
}) {
  if (vertices.length < 2) return null;
  var best = tolerancePixels;
  int? selected;
  final scaled = FloorPoint(
    point.x * renderedImageWidth,
    point.z * renderedImageHeight,
  );
  for (var index = 0; index < vertices.length; index++) {
    final start = FloorPoint(
      vertices[index].x * renderedImageWidth,
      vertices[index].z * renderedImageHeight,
    );
    final end = FloorPoint(
      vertices[(index + 1) % vertices.length].x * renderedImageWidth,
      vertices[(index + 1) % vertices.length].z * renderedImageHeight,
    );
    final delta = end - start;
    final squared = delta.x * delta.x + delta.z * delta.z;
    if (squared == 0) continue;
    final projection =
        (((scaled.x - start.x) * delta.x + (scaled.z - start.z) * delta.z) /
                squared)
            .clamp(0.0, 1.0);
    final distance = scaled.distanceTo(start + delta.scale(projection));
    if (distance < best) {
      best = distance;
      selected = index;
    }
  }
  return selected;
}

class FloorplanTraceMetadata {
  const FloorplanTraceMetadata({
    required this.roomId,
    required this.sourceId,
    required this.contentType,
    required this.imageWidth,
    required this.imageHeight,
    required this.vertices,
    this.referenceEdge,
    this.referenceMeters,
  });

  factory FloorplanTraceMetadata.fromJson(Map<String, Object?> json) =>
      FloorplanTraceMetadata(
        roomId: json['roomId']! as String,
        sourceId: json['sourceId']! as String,
        contentType: json['contentType']! as String,
        imageWidth: (json['imageWidth']! as num).toInt(),
        imageHeight: (json['imageHeight']! as num).toInt(),
        vertices: [
          for (final point in json['vertices']! as List)
            FloorPoint.fromJson((point as Map).cast<String, Object?>()),
        ],
        referenceEdge: (json['referenceEdge'] as num?)?.toInt(),
        referenceMeters: (json['referenceMeters'] as num?)?.toDouble(),
      );

  final String roomId;
  final String sourceId;
  final String contentType;
  final int imageWidth;
  final int imageHeight;
  final List<FloorPoint> vertices;
  final int? referenceEdge;
  final double? referenceMeters;

  Map<String, Object?> toJson() => {
    'roomId': roomId,
    'sourceId': sourceId,
    'contentType': contentType,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'vertices': [for (final point in vertices) point.toJson()],
    if (referenceEdge != null) 'referenceEdge': referenceEdge,
    if (referenceMeters != null) 'referenceMeters': referenceMeters,
  };
}

class LocalTraceSource {
  const LocalTraceSource({
    required this.sourceId,
    required this.contentType,
    required this.bytes,
  });

  final String sourceId;
  final String contentType;
  final List<int> bytes;
}
