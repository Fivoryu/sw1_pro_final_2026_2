import 'capture_models.dart';
import 'geometry.dart';

/// Shortest wall the contour accepts, in metres.
const double minEdgeLength = 0.3;

/// Smallest room area the contour accepts, in square metres.
const double minRoomArea = 1.0;

/// A corner closer than this to the segment joining its neighbours adds no
/// shape information.
const double redundantCornerTolerance = 0.03;

/// Free space kept at each end of an edge around an opening, in metres.
const double openingEdgeMargin = 0.05;

enum ContourIssueCode {
  tooFewCorners,
  edgeTooShort,
  selfIntersection,
  areaTooSmall,
  redundantCorner,
}

/// A problem with a room contour. Every issue but [ContourIssueCode.redundantCorner]
/// blocks closing the room.
class ContourIssue {
  const ContourIssue(
    this.code, {
    this.edgeIndex,
    this.otherEdgeIndex,
    this.cornerIndex,
  });

  final ContourIssueCode code;
  final int? edgeIndex;
  final int? otherEdgeIndex;
  final int? cornerIndex;

  bool get blocking => code != ContourIssueCode.redundantCorner;

  @override
  String toString() =>
      'ContourIssue($code, edge: $edgeIndex, '
      'other: $otherEdgeIndex, corner: $cornerIndex)';
}

/// Validates a closed contour (edge `i` joins corner `i` and `i + 1`).
List<ContourIssue> validateContour(List<FloorPoint> corners) {
  if (corners.length < 3) {
    return const [ContourIssue(ContourIssueCode.tooFewCorners)];
  }
  final issues = <ContourIssue>[];
  final count = corners.length;
  final lengths = edgeLengths(corners);
  for (var i = 0; i < count; i++) {
    if (lengths[i] < minEdgeLength) {
      issues.add(ContourIssue(ContourIssueCode.edgeTooShort, edgeIndex: i));
    }
  }
  for (var i = 0; i < count; i++) {
    for (var j = i + 2; j < count; j++) {
      if (i == 0 && j == count - 1) continue; // adjacent through the closure
      if (segmentsIntersect(
        corners[i],
        corners[(i + 1) % count],
        corners[j],
        corners[(j + 1) % count],
      )) {
        issues.add(
          ContourIssue(
            ContourIssueCode.selfIntersection,
            edgeIndex: i,
            otherEdgeIndex: j,
          ),
        );
      }
    }
  }
  if (polygonArea(corners) < minRoomArea) {
    issues.add(const ContourIssue(ContourIssueCode.areaTooSmall));
  }
  for (var i = 0; i < count; i++) {
    final previous = corners[(i - 1 + count) % count];
    final next = corners[(i + 1) % count];
    if (distanceToSegment(corners[i], previous, next) <
        redundantCornerTolerance) {
      issues.add(
        ContourIssue(ContourIssueCode.redundantCorner, cornerIndex: i),
      );
    }
  }
  return issues;
}

/// User-facing Spanish message for [issue]. Indexes are shown 1-based.
String contourIssueMessage(ContourIssue issue) => switch (issue.code) {
  ContourIssueCode.tooFewCorners =>
    'Marcá al menos 3 esquinas para cerrar el ambiente.',
  ContourIssueCode.edgeTooShort =>
    'La pared ${(issue.edgeIndex ?? 0) + 1} mide menos de 30 cm. Revisá las '
        'esquinas marcadas.',
  ContourIssueCode.selfIntersection =>
    'Las paredes ${(issue.edgeIndex ?? 0) + 1} y '
        '${(issue.otherEdgeIndex ?? 0) + 1} se cruzan. Marcá las esquinas en '
        'orden alrededor del ambiente.',
  ContourIssueCode.areaTooSmall =>
    'El ambiente mide menos de 1 m². Revisá las esquinas marcadas.',
  ContourIssueCode.redundantCorner =>
    'La esquina ${(issue.cornerIndex ?? 0) + 1} está casi alineada con sus '
        'vecinas; podés quitarla.',
};

enum OpeningIssueCode {
  edgeIndexOutOfRange,
  nonPositiveSize,
  widthExceedsEdge,
  outsideEdge,
  tallerThanRoom,
  windowAboveCeiling,
}

class OpeningIssue {
  const OpeningIssue(this.code);

  final OpeningIssueCode code;

  @override
  String toString() => 'OpeningIssue($code)';
}

/// Validates [opening] against the contour and height of [room].
List<OpeningIssue> validateOpening(CapturedRoom room, RoomOpening opening) {
  final count = room.corners.length;
  if (opening.edgeIndex < 0 || opening.edgeIndex >= count || count < 2) {
    return const [OpeningIssue(OpeningIssueCode.edgeIndexOutOfRange)];
  }
  if (opening.width <= 0 || opening.height <= 0 || opening.sillHeight < 0) {
    return const [OpeningIssue(OpeningIssueCode.nonPositiveSize)];
  }
  final issues = <OpeningIssue>[];
  final edge = room.corners[opening.edgeIndex].distanceTo(
    room.corners[(opening.edgeIndex + 1) % count],
  );
  if (opening.width > edge - 2 * openingEdgeMargin) {
    issues.add(const OpeningIssue(OpeningIssueCode.widthExceedsEdge));
  }
  final center = opening.position * edge;
  final half = opening.width / 2;
  if (opening.position < 0 ||
      opening.position > 1 ||
      center - half < openingEdgeMargin - 1e-9 ||
      center + half > edge - openingEdgeMargin + 1e-9) {
    issues.add(const OpeningIssue(OpeningIssueCode.outsideEdge));
  }
  if (opening.height > room.height.value) {
    issues.add(const OpeningIssue(OpeningIssueCode.tallerThanRoom));
  }
  if (opening.type == OpeningType.window &&
      opening.height <= room.height.value &&
      opening.sillHeight + opening.height > room.height.value) {
    issues.add(const OpeningIssue(OpeningIssueCode.windowAboveCeiling));
  }
  return issues;
}

/// User-facing Spanish message for [issue].
String openingIssueMessage(OpeningIssue issue) => switch (issue.code) {
  OpeningIssueCode.edgeIndexOutOfRange =>
    'La pared elegida no existe en el ambiente. Elegí otra pared.',
  OpeningIssueCode.nonPositiveSize =>
    'El ancho y la altura de la abertura deben ser mayores que cero.',
  OpeningIssueCode.widthExceedsEdge =>
    'La abertura es más ancha que la pared. Revisá su ancho.',
  OpeningIssueCode.outsideEdge =>
    'La abertura se sale de la pared. Mové su posición hacia el centro.',
  OpeningIssueCode.tallerThanRoom =>
    'La abertura es más alta que el ambiente. Revisá su altura.',
  OpeningIssueCode.windowAboveCeiling =>
    'La ventana, sumando su antepecho, supera la altura del ambiente. Revisá '
        'el antepecho o la altura.',
};

/// Observed error of one captured edge against an independent reference.
class ToleranceRecord {
  const ToleranceRecord({
    required this.edgeIndex,
    required this.capturedMeters,
    required this.referenceMeters,
  });

  final int edgeIndex;
  final double capturedMeters;
  final double referenceMeters;

  /// Captured length minus reference, in metres (negative: captured short).
  double get absoluteError => capturedMeters - referenceMeters;

  /// [absoluteError] as a percentage of the reference.
  double get relativeErrorPercent => absoluteError / referenceMeters * 100;
}

/// One record per reference typed by the agent. References to a missing edge
/// or with a non-positive length are skipped. An empty list means accuracy is
/// unknown: never claim accuracy without references.
List<ToleranceRecord> toleranceRecords(CapturedRoom room) {
  final lengths = edgeLengths(room.corners);
  return [
    for (final reference in room.references)
      if (reference.edgeIndex >= 0 &&
          reference.edgeIndex < lengths.length &&
          reference.referenceMeters > 0)
        ToleranceRecord(
          edgeIndex: reference.edgeIndex,
          capturedMeters: lengths[reference.edgeIndex],
          referenceMeters: reference.referenceMeters,
        ),
  ];
}
