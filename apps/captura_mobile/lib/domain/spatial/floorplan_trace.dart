import 'dart:math' as math;

import 'geometry.dart';
import 'floorplan_visual_draft.dart';

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

enum FloorplanTraceOpeningType {
  unknown,
  door,
  window;

  String get wire => name;

  static FloorplanTraceOpeningType fromWire(Object? value) => switch (value) {
    'door' => FloorplanTraceOpeningType.door,
    'window' => FloorplanTraceOpeningType.window,
    _ => FloorplanTraceOpeningType.unknown,
  };
}

/// A door/window proposal detected from a 2D floor plan, not a canonical
/// RoomOpening.
class FloorplanTraceOpening {
  const FloorplanTraceOpening({
    this.edgeIndex,
    required this.type,
    this.position,
    this.normalizedWidth,
    this.confidence,
    this.manuallyPlaced = false,
  });

  factory FloorplanTraceOpening.fromJson(Map<String, Object?> json) =>
      FloorplanTraceOpening(
        edgeIndex: (json['edgeIndex'] as num?)?.toInt(),
        type: FloorplanTraceOpeningType.fromWire(json['type']),
        position: (json['position'] as num?)?.toDouble(),
        normalizedWidth: (json['normalizedWidth'] as num?)?.toDouble(),
        confidence: (json['confidence'] as num?)?.toDouble(),
        manuallyPlaced: json['manuallyPlaced'] == true,
      );

  final int? edgeIndex;
  final FloorplanTraceOpeningType type;
  final double? position;
  final double? normalizedWidth;
  final double? confidence;
  final bool manuallyPlaced;

  bool get hasGeometry => position != null && normalizedWidth != null;

  Map<String, Object?> toJson() => {
    'edgeIndex': edgeIndex,
    'type': type.wire,
    if (position != null) 'position': position,
    if (normalizedWidth != null) 'normalizedWidth': normalizedWidth,
    if (confidence != null) 'confidence': confidence,
    if (manuallyPlaced) 'manuallyPlaced': true,
  };
}

/// Boundary adapter used only by deterministic legacy migration. The canonical
/// room keeps owning its references; migration maps them onto stable wall IDs
/// instead of persisting raw edge indexes inside the visual document.
class LegacyMeasurementReference {
  const LegacyMeasurementReference({
    required this.edgeIndex,
    required this.meters,
    this.provenance = 'user',
    this.requiresReview = false,
  });

  final int edgeIndex;
  final double meters;
  final String provenance;
  final bool requiresReview;
}

/// Result of opening the persisted editor document.
///
/// A legacy trace is migrated deterministically. A stored document is restored
/// verbatim. A stored document that cannot be interpreted is reported instead
/// of being replaced by an automatically reconstructed alternative.
class FloorplanTraceDraftRestoration {
  const FloorplanTraceDraftRestoration._({
    this.draft,
    this.problem,
    this.migratedFromLegacy = false,
  });

  const FloorplanTraceDraftRestoration.ready(FloorplanVisualDraft draft)
    : this._(draft: draft);

  const FloorplanTraceDraftRestoration.migrated(FloorplanVisualDraft draft)
    : this._(draft: draft, migratedFromLegacy: true);

  const FloorplanTraceDraftRestoration.failed(String problem)
    : this._(problem: problem);

  final FloorplanVisualDraft? draft;

  /// Recovery code: `visual_draft_unreadable`, `visual_draft_unsupported` or
  /// `visual_draft_invalid`.
  final String? problem;
  final bool migratedFromLegacy;

  bool get isReady => draft != null;
}

class FloorplanTraceMetadata {
  const FloorplanTraceMetadata({
    required this.roomId,
    this.visualRoomId,
    this.documentOwnerRoomId,
    required this.sourceId,
    required this.contentType,
    required this.imageWidth,
    required this.imageHeight,
    required this.vertices,
    this.referenceEdge,
    this.referenceMeters,
    this.openings = const [],
    this.visualDraft,
    this.preservedVisualDraft,
    this.draftProblem,
  });

  factory FloorplanTraceMetadata.fromJson(Map<String, Object?> json) {
    final rawDraft = json['visualDraft'];
    Object? preserved;
    FloorplanVisualDraft? draft;
    String? problem;
    if (rawDraft != null) {
      if (rawDraft is Map) {
        final decoded = rawDraft.cast<String, Object?>();
        try {
          final parsed = FloorplanVisualDraft.fromJson(decoded);
          // A document this build cannot fully interpret must never be
          // re-serialized from a partial model: unknown fields, nested data and
          // newer versions would be silently lost.
          if (parsed.version < 1 ||
              parsed.version > FloorplanVisualDraft.currentVersion) {
            preserved = rawDraft;
            problem = 'visual_draft_unsupported';
          } else {
            final errors = parsed.validate();
            if (errors.isEmpty) {
              draft = parsed;
            } else {
              preserved = rawDraft;
              problem = 'visual_draft_invalid:${errors.first}';
            }
          }
        } on Object {
          // Keep the exact persisted value so a later save cannot quietly
          // replace the damaged document with a reconstructed one.
          preserved = rawDraft;
          problem = 'visual_draft_unreadable';
        }
      } else {
        preserved = rawDraft;
        problem = 'visual_draft_unreadable';
      }
    }
    return FloorplanTraceMetadata(
      roomId: json['roomId']! as String,
      visualRoomId: json['visualRoomId'] as String?,
      documentOwnerRoomId: json['documentOwnerRoomId'] as String?,
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
      openings: [
        for (final opening in (json['openings'] as List? ?? const []))
          FloorplanTraceOpening.fromJson(
            (opening as Map).cast<String, Object?>(),
          ),
      ],
      visualDraft: draft,
      preservedVisualDraft: preserved,
      draftProblem: problem,
    );
  }

  final String roomId;

  /// Stable room-region identity inside the canonical visual document.
  final String? visualRoomId;

  /// Captured-room projection that persists the shared canonical document.
  /// Secondary projections refer to it instead of serializing another copy.
  final String? documentOwnerRoomId;
  final String sourceId;
  final String contentType;
  final int imageWidth;
  final int imageHeight;
  final List<FloorPoint> vertices;
  final int? referenceEdge;
  final double? referenceMeters;
  final List<FloorplanTraceOpening> openings;

  /// Optional visual-editor document. It is the single authority for editable
  /// walls, rooms, openings and measurement evidence once present.
  final FloorplanVisualDraft? visualDraft;

  /// Verbatim persisted document when it could not be decoded, is structurally
  /// invalid or was written by an unsupported version. It is written back
  /// unchanged so a save cannot destroy the only copy.
  final Object? preservedVisualDraft;

  /// Recoverable restoration problem for [visualDraft], if any.
  final String? draftProblem;

  /// Edge indexes and [referenceEdge] below are legacy compatibility
  /// projections: they are derived from the document when it exists.
  Map<String, Object?> toJson() => {
    'roomId': roomId,
    if (visualRoomId != null) 'visualRoomId': visualRoomId,
    if (documentOwnerRoomId != null) 'documentOwnerRoomId': documentOwnerRoomId,
    'sourceId': sourceId,
    'contentType': contentType,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'vertices': [for (final point in vertices) point.toJson()],
    if (referenceEdge != null) 'referenceEdge': referenceEdge,
    if (referenceMeters != null) 'referenceMeters': referenceMeters,
    'openings': [for (final opening in openings) opening.toJson()],
    if (visualDraft != null)
      'visualDraft': visualDraft!.toJson()
    else if (preservedVisualDraft != null)
      'visualDraft': preservedVisualDraft,
  };

  FloorplanTraceMetadata withResolvedVisualDraft(
    FloorplanVisualDraft document,
  ) => FloorplanTraceMetadata(
    roomId: roomId,
    visualRoomId: visualRoomId,
    documentOwnerRoomId: documentOwnerRoomId,
    sourceId: sourceId,
    contentType: contentType,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    vertices: vertices,
    referenceEdge: referenceEdge,
    referenceMeters: referenceMeters,
    openings: openings,
    visualDraft: document,
    draftProblem: draftProblem,
  );

  /// Restores the authoritative editor document.
  ///
  /// Case 1: no stored document — deterministic migration from the persisted
  /// vertices, openings and the supplied legacy measurement references.
  /// Case 2: a valid stored document is restored verbatim, without merging any
  /// legacy projection into it.
  /// Case 3: a stored document that is invalid, unsupported or unreadable is
  /// reported; it is never rebuilt silently.
  FloorplanTraceDraftRestoration restoreEditorDraft({
    List<LegacyMeasurementReference> references = const [],
  }) {
    final stored = visualDraft;
    if (stored != null) {
      if (stored.version < 1 ||
          stored.version > FloorplanVisualDraft.currentVersion) {
        return const FloorplanTraceDraftRestoration.failed(
          'visual_draft_unsupported',
        );
      }
      final errors = stored.validate();
      if (errors.isEmpty) return FloorplanTraceDraftRestoration.ready(stored);
      return FloorplanTraceDraftRestoration.failed(
        'visual_draft_invalid:${errors.first}',
      );
    }
    if (draftProblem != null) {
      return FloorplanTraceDraftRestoration.failed(draftProblem!);
    }
    return FloorplanTraceDraftRestoration.migrated(
      _migrateLegacyDraft(references),
    );
  }

  /// Deterministic legacy migration. IDs derive only from the persisted room,
  /// traversal order and reference position, so reopening a legacy trace never
  /// creates a different identity graph.
  FloorplanVisualDraft _migrateLegacyDraft(
    List<LegacyMeasurementReference> references,
  ) {
    final wallIds = [
      for (var index = 0; index < vertices.length; index++)
        '$roomId:wall:$index',
    ];
    return FloorplanVisualDraft(
      walls: [
        for (var index = 0; index < vertices.length; index++)
          VisualWallSegment(
            id: wallIds[index],
            start: vertices[index],
            end: vertices[(index + 1) % vertices.length],
            roomIds: [roomId],
          ),
      ],
      rooms: [VisualRoomRegion(id: roomId, wallIds: wallIds)],
      openings: [
        for (final (index, opening) in openings.indexed)
          VisualOpeningDraft(
            id: '$roomId:opening:$index',
            type: switch (opening.type) {
              FloorplanTraceOpeningType.door => VisualOpeningType.door,
              FloorplanTraceOpeningType.window => VisualOpeningType.window,
              FloorplanTraceOpeningType.unknown => VisualOpeningType.unknown,
            },
            wallId:
                opening.edgeIndex == null ||
                    opening.edgeIndex! < 0 ||
                    opening.edgeIndex! >= wallIds.length
                ? null
                : wallIds[opening.edgeIndex!],
            position: opening.position,
            normalizedWidth: opening.normalizedWidth,
            manuallyPlaced: opening.manuallyPlaced,
            confidence: opening.confidence,
          ),
      ],
      measurements: [
        for (final (index, reference) in references.indexed)
          if (reference.meters.isFinite && reference.meters > 0)
            VisualWallMeasurementEvidence(
              id: '$roomId:measurement:$index',
              wallId:
                  reference.edgeIndex >= 0 &&
                      reference.edgeIndex < wallIds.length
                  ? wallIds[reference.edgeIndex]
                  : null,
              meters: reference.meters,
              provenance: reference.provenance,
              requiresReview:
                  reference.requiresReview ||
                  reference.edgeIndex < 0 ||
                  reference.edgeIndex >= wallIds.length,
            ),
      ],
    );
  }

  /// Compatibility accessor for callers that only need the document.
  FloorplanVisualDraft? editorDraft({
    List<LegacyMeasurementReference> references = const [],
  }) => restoreEditorDraft(references: references).draft;
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
