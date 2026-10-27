import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

CapturedRoom _room(
  List<FloorPoint> corners,
  List<double> lengths, {
  List<RoomOpening> openings = const [],
}) => CapturedRoom(
  id: 'room',
  name: 'Ambiente',
  corners: corners,
  height: const RoomHeight(2.6, HeightSource.manual),
  openings: openings,
  boxes: const [],
  references: [
    for (var index = 0; index < lengths.length; index++)
      ReferenceMeasurement(edgeIndex: index, referenceMeters: lengths[index]),
  ],
  acquisition: const RoomAcquisition(
    method: RoomAcquisitionMethod.manualSketch,
  ),
  measurementMode: RoomMeasurementMode.wallConstraints,
);

void main() {
  group('geometría autoritativa por paredes', () {
    test('cuatro paredes de 3.50 forman un cuadrado coherente', () {
      final result = fitConfirmedWallLengths(
        _room(
          const [
            FloorPoint(0, 0),
            FloorPoint(3.3, 0.1),
            FloorPoint(3.4, 3.6),
            FloorPoint(-0.1, 3.5),
          ],
          const [3.5, 3.5, 3.5, 3.5],
        ),
      );

      expect(result.isCoherent, isTrue);
      expect(edgeLengths(result.corners!), everyElement(closeTo(3.5, 1e-4)));
      expect(polygonArea(result.corners!), closeTo(12.25, 1e-3));
    });

    test('4 x 3 mantiene cierre, longitudes y área', () {
      final result = fitConfirmedWallLengths(
        _room(
          const [
            FloorPoint(0, 0),
            FloorPoint(4.1, 0),
            FloorPoint(4, 2.9),
            FloorPoint(0, 3),
          ],
          const [4, 3, 4, 3],
        ),
      );

      expect(result.isCoherent, isTrue);
      for (final (index, expected) in [4.0, 3.0, 4.0, 3.0].indexed) {
        expect(edgeLengths(result.corners!)[index], closeTo(expected, 1e-4));
      }
      expect(polygonArea(result.corners!), closeTo(12, 1e-3));
    });

    test('medidas incompatibles no se distorsionan silenciosamente', () {
      final result = fitConfirmedWallLengths(
        _room(
          const [
            FloorPoint(0, 0),
            FloorPoint(4, 0),
            FloorPoint(4, 3),
            FloorPoint(0, 3),
          ],
          const [10, 3, 2, 3],
        ),
      );

      expect(result.isCoherent, isFalse);
      expect(result.message, contains('no permiten cerrar'));
    });

    test('confirmar otra pared no sobrescribe la primera ni la abertura', () {
      final room = _room(
        const [
          FloorPoint(0, 0),
          FloorPoint(4, 0),
          FloorPoint(4, 3),
          FloorPoint(0, 3),
        ],
        const [4],
        openings: const [
          RoomOpening(
            id: 'door-1',
            edgeIndex: 2,
            position: 0.5,
            width: 0.8,
            height: 2,
            type: OpeningType.door,
          ),
        ],
      );
      final candidate = room.copyWith(
        references: [
          ...room.references,
          const ReferenceMeasurement(edgeIndex: 1, referenceMeters: 3.2),
        ],
      );
      final result = fitConfirmedWallLengths(candidate);

      expect(result.isCoherent, isTrue);
      expect(candidate.references[0].referenceMeters, 4);
      expect(candidate.references[1].referenceMeters, 3.2);
      expect(candidate.openings.single.edgeIndex, 2);
    });

    test('ambiente en L conserva seis asociaciones por índice', () {
      final room = buildManualLRoom(
        id: 'l',
        name: 'L',
        totalWidth: 5,
        totalDepth: 4,
        recessWidth: 2,
        recessDepth: 1.5,
        height: 2.6,
        recess: RecessCorner.upperRight,
      );
      final result = fitConfirmedWallLengths(room);

      expect(result.isCoherent, isTrue);
      expect(room.references, hasLength(6));
      expect(
        edgeLengths(result.corners!),
        orderedEquals(room.references.map((value) => value.referenceMeters)),
      );
      expect(
        [for (var i = 0; i < 6; i++) wallLabel(i)],
        ['Pared 1', 'Pared 2', 'Pared 3', 'Pared 4', 'Pared 5', 'Pared 6'],
      );
    });

    test('acepta un trapecio coherente sin ortogonalizar diagonales', () {
      const target = [
        FloorPoint(0, 0),
        FloorPoint(5, 0),
        FloorPoint(4, 3),
        FloorPoint(1, 3),
      ];
      final expected = edgeLengths(target);
      final result = fitConfirmedWallLengths(
        _room(const [
          FloorPoint(0, 0),
          FloorPoint(4.8, 0.1),
          FloorPoint(3.9, 2.8),
          FloorPoint(1.2, 3.1),
        ], expected),
      );

      expect(result.isCoherent, isTrue);
      for (final (index, length) in expected.indexed) {
        expect(edgeLengths(result.corners!)[index], closeTo(length, 1e-4));
      }
      expect(validateContour(result.corners!), isEmpty);
      expect(result.corners![2].x, isNot(closeTo(result.corners![1].x, 1e-3)));
    });

    test('acepta un pentágono no ortogonal coherente', () {
      const target = [
        FloorPoint(0, 0),
        FloorPoint(3, 0),
        FloorPoint(4.2, 2),
        FloorPoint(2, 3.5),
        FloorPoint(-0.5, 2),
      ];
      final expected = edgeLengths(target);
      final result = fitConfirmedWallLengths(
        _room(const [
          FloorPoint(0, 0),
          FloorPoint(2.8, 0.1),
          FloorPoint(4, 1.9),
          FloorPoint(2.1, 3.2),
          FloorPoint(-0.4, 1.8),
        ], expected),
      );

      expect(result.isCoherent, isTrue);
      for (final (index, length) in expected.indexed) {
        expect(edgeLengths(result.corners!)[index], closeTo(length, 1e-4));
      }
      expect(validateContour(result.corners!), isEmpty);
    });

    test('acepta un polígono cóncavo simple con diagonales', () {
      const source = [
        FloorPoint(0, 0),
        FloorPoint(4, 0.2),
        FloorPoint(3.2, 1.7),
        FloorPoint(4.1, 3.4),
        FloorPoint(0.2, 3),
        FloorPoint(1.3, 1.5),
      ];
      final expected = edgeLengths(source);
      final result = fitConfirmedWallLengths(_room(source, expected));

      expect(result.isCoherent, isTrue);
      expect(validateContour(result.corners!), isEmpty);
      for (final (index, length) in expected.indexed) {
        expect(edgeLengths(result.corners!)[index], closeTo(length, 1e-5));
      }
    });
  });
}
