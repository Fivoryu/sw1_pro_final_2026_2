import 'geometry.dart';

class FloorplanTraceMetadata {
  const FloorplanTraceMetadata({
    required this.roomId,
    required this.sourceId,
    required this.contentType,
    required this.imageWidth,
    required this.imageHeight,
    required this.vertices,
    required this.referenceEdge,
    required this.referenceMeters,
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
        referenceEdge: (json['referenceEdge']! as num).toInt(),
        referenceMeters: (json['referenceMeters']! as num).toDouble(),
      );

  final String roomId;
  final String sourceId;
  final String contentType;
  final int imageWidth;
  final int imageHeight;
  final List<FloorPoint> vertices;
  final int referenceEdge;
  final double referenceMeters;

  Map<String, Object?> toJson() => {
    'roomId': roomId,
    'sourceId': sourceId,
    'contentType': contentType,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'vertices': [for (final point in vertices) point.toJson()],
    'referenceEdge': referenceEdge,
    'referenceMeters': referenceMeters,
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
