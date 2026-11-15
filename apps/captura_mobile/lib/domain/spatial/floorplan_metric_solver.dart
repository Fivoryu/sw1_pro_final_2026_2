import 'capture_models.dart';
import 'geometry.dart';
import 'wall_measurement_candidate.dart';

const double floorplanScaleTolerance = 0.12;

class FloorplanMetricSolution {
  const FloorplanMetricSolution({
    required this.measurements,
    required this.hasScale,
    required this.inconsistent,
  });

  final List<ReferenceMeasurement> measurements;
  final bool hasScale;
  final bool inconsistent;

  int get pendingCount => inconsistent ? 0 : 0;
}

/// Resolves semantic wall lengths from explicit user values and unambiguous
/// automatic measurement proposals. One reliable metric establishes scale for the final semantic
/// contour; raw raster fragments never participate.
FloorplanMetricSolution solveFloorplanMetrics({
  required List<FloorPoint> semanticContour,
  Iterable<ReferenceMeasurement> existingMeasurements = const [],
  Iterable<ReferenceMeasurement> userMeasurements = const [],
  Iterable<WallMeasurementCandidate> measurementCandidates = const [],
}) {
  if (semanticContour.length < 3) {
    return const FloorplanMetricSolution(
      measurements: [],
      hasScale: false,
      inconsistent: false,
    );
  }
  final imageLengths = edgeLengths(semanticContour);
  final explicit = <int, ReferenceMeasurement>{};
  for (final value in existingMeasurements) {
    if (value.edgeIndex >= 0 &&
        value.edgeIndex < imageLengths.length &&
        value.referenceMeters > 0 &&
        value.provenance != WallMeasurementProvenance.derivedScale &&
        value.provenance != WallMeasurementProvenance.derivedGeometry &&
        value.provenance != WallMeasurementProvenance.unresolved) {
      explicit[value.edgeIndex] = value;
    }
  }
  for (final value in userMeasurements) {
    if (value.edgeIndex >= 0 &&
        value.edgeIndex < imageLengths.length &&
        value.referenceMeters > 0) {
      explicit[value.edgeIndex] = ReferenceMeasurement(
        edgeIndex: value.edgeIndex,
        referenceMeters: value.referenceMeters,
        provenance: WallMeasurementProvenance.user,
      );
    }
  }
  for (final candidate in measurementCandidates) {
    final edge = candidate.edgeIndex;
    final meters = candidate.meters;
    if (edge == null ||
        meters == null ||
        edge < 0 ||
        edge >= imageLengths.length ||
        candidate.status != WallMeasurementCandidateStatus.proposed ||
        explicit.containsKey(edge)) {
      continue;
    }
    explicit[edge] = ReferenceMeasurement(
      edgeIndex: edge,
      referenceMeters: meters,
      provenance: WallMeasurementProvenance.aiDetected,
    );
  }
  if (explicit.isEmpty) {
    return const FloorplanMetricSolution(
      measurements: [],
      hasScale: false,
      inconsistent: false,
    );
  }
  final scales = [
    for (final value in explicit.values)
      value.referenceMeters / imageLengths[value.edgeIndex],
  ];
  final average = scales.reduce((a, b) => a + b) / scales.length;
  final inconsistent = scales.any(
    (scale) => (scale - average).abs() / average > floorplanScaleTolerance,
  );
  if (inconsistent) {
    return FloorplanMetricSolution(
      measurements: explicit.values.toList()..sort(_byEdge),
      hasScale: false,
      inconsistent: true,
    );
  }
  final resolved = <ReferenceMeasurement>[];
  for (var edge = 0; edge < imageLengths.length; edge++) {
    resolved.add(
      explicit[edge] ??
          ReferenceMeasurement(
            edgeIndex: edge,
            referenceMeters: imageLengths[edge] * average,
            provenance: WallMeasurementProvenance.derivedScale,
          ),
    );
  }
  return FloorplanMetricSolution(
    measurements: List.unmodifiable(resolved),
    hasScale: true,
    inconsistent: false,
  );
}

int _byEdge(ReferenceMeasurement a, ReferenceMeasurement b) =>
    a.edgeIndex.compareTo(b.edgeIndex);
