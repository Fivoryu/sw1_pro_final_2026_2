import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rectangle = [
    FloorPoint(0, 0),
    FloorPoint(400, 0),
    FloorPoint(400, 300),
    FloorPoint(0, 300),
  ];

  test(
    'one proposed dimension establishes scale and derives remaining walls',
    () {
      final result = solveFloorplanMetrics(
        semanticContour: rectangle,
        measurementCandidates: [_candidate(edge: 0, meters: 4)],
      );

      expect(result.hasScale, isTrue);
      expect(result.inconsistent, isFalse);
      expect(
        result.measurements.map((value) => value.referenceMeters),
        orderedEquals([4, 3, 4, 3]),
      );
      expect(
        result.measurements.first.provenance,
        WallMeasurementProvenance.aiDetected,
      );
      expect(
        result.measurements[1].provenance,
        WallMeasurementProvenance.derivedScale,
      );
    },
  );

  test('one user reference derives all walls without overwriting the user', () {
    final result = solveFloorplanMetrics(
      semanticContour: rectangle,
      userMeasurements: const [
        ReferenceMeasurement(edgeIndex: 1, referenceMeters: 3),
      ],
    );

    expect(result.hasScale, isTrue);
    expect(result.measurements.map((value) => value.referenceMeters), [
      4,
      3,
      4,
      3,
    ]);
    expect(result.measurements[1].provenance, WallMeasurementProvenance.user);
  });

  test('inconsistent explicit scales are flagged and never averaged', () {
    final result = solveFloorplanMetrics(
      semanticContour: rectangle,
      measurementCandidates: [
        _candidate(edge: 0, meters: 4),
        _candidate(edge: 1, meters: 5),
      ],
    );

    expect(result.hasScale, isFalse);
    expect(result.inconsistent, isTrue);
    expect(result.measurements, hasLength(2));
  });

  test('ambiguous automatic evidence does not establish scale', () {
    final result = solveFloorplanMetrics(
      semanticContour: rectangle,
      measurementCandidates: [
        _candidate(
          edge: 0,
          meters: 4,
          status: WallMeasurementCandidateStatus.ambiguous,
        ),
      ],
    );

    expect(result.hasScale, isFalse);
    expect(result.measurements, isEmpty);
  });

  test('a provider conflict metric is never used for scale', () {
    final result = solveFloorplanMetrics(
      semanticContour: rectangle,
      measurementCandidates: [
        _candidate(
          edge: 0,
          meters: 4.10,
          status: WallMeasurementCandidateStatus.ambiguous,
        ),
      ],
    );

    expect(result.hasScale, isFalse);
    expect(result.inconsistent, isFalse);
    expect(result.measurements, isEmpty);
  });

  test('unresolved metric evidence is never used for scale', () {
    final result = solveFloorplanMetrics(
      semanticContour: rectangle,
      measurementCandidates: [
        _candidate(
          edge: 0,
          meters: 4.10,
          status: WallMeasurementCandidateStatus.unresolved,
        ),
      ],
    );

    expect(result.hasScale, isFalse);
    expect(result.inconsistent, isFalse);
    expect(result.measurements, isEmpty);
  });

  test('an unknown-unit reading cannot establish scale', () {
    final result = solveFloorplanMetrics(
      semanticContour: rectangle,
      measurementCandidates: [
        _candidate(
          edge: 0,
          meters: null,
          rawValue: 419,
          status: WallMeasurementCandidateStatus.unresolved,
        ),
      ],
    );

    expect(result.hasScale, isFalse);
    expect(result.measurements, isEmpty);
  });

  test('one reference scales a six-wall orthogonal L consistently', () {
    const l = [
      FloorPoint(0, 0),
      FloorPoint(600, 0),
      FloorPoint(600, 300),
      FloorPoint(400, 300),
      FloorPoint(400, 500),
      FloorPoint(0, 500),
    ];
    final result = solveFloorplanMetrics(
      semanticContour: l,
      userMeasurements: const [
        ReferenceMeasurement(edgeIndex: 0, referenceMeters: 6),
      ],
    );

    expect(result.hasScale, isTrue);
    expect(
      result.measurements.map((value) => value.referenceMeters),
      orderedEquals([6, 3, 2, 2, 4, 5]),
    );
  });

  test(
    'measurement provenance survives local JSON and legacy defaults user',
    () {
      const detected = ReferenceMeasurement(
        edgeIndex: 2,
        referenceMeters: 3.5,
        provenance: WallMeasurementProvenance.aiDetected,
      );
      final restored = ReferenceMeasurement.fromJson(detected.toJson());
      final legacy = ReferenceMeasurement.fromJson(const {
        'edgeIndex': 0,
        'referenceMeters': 4.0,
      });

      expect(restored.provenance, WallMeasurementProvenance.aiDetected);
      expect(
        ReferenceMeasurement.fromJson(const {
          'edgeIndex': 1,
          'referenceMeters': 3.0,
          'provenance': 'ocr',
        }).provenance,
        WallMeasurementProvenance.aiDetected,
      );
      expect(legacy.provenance, WallMeasurementProvenance.user);
    },
  );

  test('semantic wall hit testing uses a phone-friendly tolerance', () {
    final selected = nearestTraceEdge(
      point: const FloorPoint(0.51, 0.04),
      vertices: const [
        FloorPoint(0.1, 0.1),
        FloorPoint(0.9, 0.1),
        FloorPoint(0.9, 0.9),
        FloorPoint(0.1, 0.9),
      ],
      renderedImageWidth: 320,
      renderedImageHeight: 240,
    );

    expect(selected, 0);
  });
}

WallMeasurementCandidate _candidate({
  required int edge,
  required double? meters,
  double? rawValue,
  WallMeasurementCandidateStatus status =
      WallMeasurementCandidateStatus.proposed,
}) => WallMeasurementCandidate(
  id: 'candidate-$edge',
  literalText: meters == null ? '${rawValue ?? 0}' : '$meters m',
  meters: meters,
  rawValue: rawValue,
  edgeIndex: edge,
  explicitUnit: meters != null,
  status: status,
);
