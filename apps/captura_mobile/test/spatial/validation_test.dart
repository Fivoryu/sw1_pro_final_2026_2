import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/spatial_fixtures.dart';

List<FloorPoint> _points(List<List<double>> raw) => [
  for (final p in raw) FloorPoint(p[0], p[1]),
];

void main() {
  group('validateContour', () {
    test('a 4 x 3 room is valid and reports estimated dimensions', () {
      final corners = _points([
        [0, 0],
        [4, 0],
        [4, 3],
        [0, 3],
      ]);
      expect(validateContour(corners), isEmpty);
      expect(edgeLengths(corners), [4, 3, 4, 3]);
      expect(perimeter(corners), 14);
      expect(polygonArea(corners), 12);
    });

    test('fewer than 3 corners', () {
      final issues = validateContour(
        _points([
          [0, 0],
          [4, 0],
        ]),
      );
      expect(issues.map((issue) => issue.code), [
        ContourIssueCode.tooFewCorners,
      ]);
      expect(issues.single.blocking, isTrue);
    });

    test('edge shorter than 0.3 m', () {
      final issues = validateContour(
        _points([
          [0, 0],
          [4, 0],
          [4, 3],
          [3.8, 3],
          [0, 3],
        ]),
      );
      final short = issues.where(
        (issue) => issue.code == ContourIssueCode.edgeTooShort,
      );
      expect(short.map((issue) => issue.edgeIndex), [2]);
    });

    test('self-intersection between non-adjacent edges', () {
      final issues = validateContour(
        _points([
          [0, 0],
          [4, 3],
          [4, 0],
          [0, 3],
        ]),
      );
      final crossing = issues
          .where((issue) => issue.code == ContourIssueCode.selfIntersection)
          .toList();
      expect(crossing, hasLength(1));
      expect(crossing.single.edgeIndex, 0);
      expect(crossing.single.otherEdgeIndex, 2);
    });

    test('area under 1 m2', () {
      final issues = validateContour(
        _points([
          [0, 0],
          [0.9, 0],
          [0.9, 0.9],
          [0, 0.9],
        ]),
      );
      expect(issues.map((issue) => issue.code), [
        ContourIssueCode.areaTooSmall,
      ]);
    });

    test('near-collinear redundant corner is reported as non-blocking', () {
      final issues = validateContour(
        _points([
          [0, 0],
          [2, 0.01],
          [4, 0],
          [4, 3],
          [0, 3],
        ]),
      );
      expect(issues.map((issue) => issue.code), [
        ContourIssueCode.redundantCorner,
      ]);
      expect(issues.single.cornerIndex, 1);
      expect(issues.single.blocking, isFalse);
    });

    test('every issue has a Spanish user-facing message', () {
      const samples = [
        ContourIssue(ContourIssueCode.tooFewCorners),
        ContourIssue(ContourIssueCode.edgeTooShort, edgeIndex: 1),
        ContourIssue(
          ContourIssueCode.selfIntersection,
          edgeIndex: 0,
          otherEdgeIndex: 2,
        ),
        ContourIssue(ContourIssueCode.areaTooSmall),
        ContourIssue(ContourIssueCode.redundantCorner, cornerIndex: 1),
      ];
      expect(samples.map(contourIssueMessage).toList(), [
        'Marcá al menos 3 esquinas para cerrar el ambiente.',
        'La pared 2 mide menos de 30 cm. Revisá las esquinas marcadas.',
        'Las paredes 1 y 3 se cruzan. Marcá las esquinas en orden alrededor '
            'del ambiente.',
        'El ambiente mide menos de 1 m². Revisá las esquinas marcadas.',
        'La esquina 2 está casi alineada con sus vecinas; podés quitarla.',
      ]);
    });
  });

  group('toleranceRecords', () {
    test('observed error is the captured length minus the reference', () {
      final room = rectangleRoom(id: 'r', width: 4, depth: 3).copyWith(
        references: const [
          ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.05),
          ReferenceMeasurement(edgeIndex: 1, referenceMeters: 2.95),
        ],
      );
      final records = toleranceRecords(room);
      expect(records, hasLength(2));
      expect(records[0].edgeIndex, 0);
      expect(records[0].capturedMeters, 4);
      expect(records[0].referenceMeters, 4.05);
      expect(records[0].absoluteError, closeTo(-0.05, 1e-9));
      expect(records[0].relativeErrorPercent, closeTo(-1.2345679, 1e-6));
      expect(records[1].absoluteError, closeTo(0.05, 1e-9));
    });

    test('without references there is no accuracy record', () {
      expect(
        toleranceRecords(rectangleRoom(id: 'r', width: 4, depth: 3)),
        isEmpty,
      );
    });
  });

  group('validateOpening', () {
    final room = rectangleRoom(
      id: 'r',
      width: 4,
      depth: 3,
      height: const RoomHeight(2.4, HeightSource.ceilingPlane),
    );

    RoomOpening opening({
      int edgeIndex = 1,
      double position = 0.5,
      double width = 0.9,
      double height = 2.1,
      OpeningType type = OpeningType.door,
      double? sillHeight,
    }) => RoomOpening(
      id: 'o',
      edgeIndex: edgeIndex,
      position: position,
      width: width,
      height: height,
      type: type,
      sillHeight: sillHeight,
    );

    List<OpeningIssueCode> codes(RoomOpening value) =>
        validateOpening(room, value).map((issue) => issue.code).toList();

    test('a centred door fits', () {
      expect(codes(opening()), isEmpty);
    });

    test('width must leave margins on the edge', () {
      expect(
        codes(opening(width: 2.95)),
        contains(OpeningIssueCode.widthExceedsEdge),
      );
    });

    test('position must keep the opening inside the edge', () {
      expect(codes(opening(position: 0.1)), [OpeningIssueCode.outsideEdge]);
    });

    test('height cannot exceed the room height', () {
      expect(codes(opening(height: 2.5)), [OpeningIssueCode.tallerThanRoom]);
    });

    test('window sill plus height cannot exceed the room height', () {
      expect(
        codes(opening(type: OpeningType.window, height: 1.6, sillHeight: 0.9)),
        [OpeningIssueCode.windowAboveCeiling],
      );
    });

    test('edge index must exist', () {
      expect(codes(opening(edgeIndex: 4)), [
        OpeningIssueCode.edgeIndexOutOfRange,
      ]);
    });

    test('issues have Spanish messages', () {
      for (final code in OpeningIssueCode.values) {
        expect(openingIssueMessage(OpeningIssue(code)), isNotEmpty);
      }
      expect(
        openingIssueMessage(
          const OpeningIssue(OpeningIssueCode.tallerThanRoom),
        ),
        'La abertura es más alta que el ambiente. Revisá su altura.',
      );
    });
  });
}
