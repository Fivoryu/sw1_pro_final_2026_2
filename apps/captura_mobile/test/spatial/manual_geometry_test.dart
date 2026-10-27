import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('manual L room', () {
    for (final recess in RecessCorner.values) {
      test('builds a valid six-corner ${recess.name} room', () {
        final room = buildManualLRoom(
          id: 'room-l',
          name: 'Cocina en L',
          totalWidth: 5,
          totalDepth: 4,
          recessWidth: 2,
          recessDepth: 1.5,
          height: 2.6,
          recess: recess,
        );

        expect(room.corners, hasLength(6));
        expect(signedArea(room.corners), greaterThan(0));
        expect(polygonArea(room.corners), closeTo(17, 1e-9));
        expect(validateContour(room.corners).where((i) => i.blocking), isEmpty);
        expect(room.height, const RoomHeight(2.6, HeightSource.manual));
        expect(room.acquisition.method, RoomAcquisitionMethod.manual);
        expect(room.metrics, isNull);
        expect(buildScene(roomCapture(room)).document['version'], '2.0');
      });
    }

    test('rejects invalid recesses and short resulting edges', () {
      CapturedRoom build({double rw = 2, double rd = 1.5}) => buildManualLRoom(
        id: 'room-l',
        name: 'L',
        totalWidth: 5,
        totalDepth: 4,
        recessWidth: rw,
        recessDepth: rd,
        height: 2.6,
        recess: RecessCorner.upperRight,
      );

      expect(() => build(rw: 5), throwsArgumentError);
      expect(() => build(rd: 4), throwsArgumentError);
      expect(() => build(rw: 0), throwsArgumentError);
      expect(() => build(rd: -1), throwsArgumentError);
      expect(() => build(rw: 4.8), throwsArgumentError);
    });
  });

  group('calibrated manual sketch', () {
    final sketch = const [
      FloorPoint(20, 20),
      FloorPoint(220, 20),
      FloorPoint(260, 130),
      FloorPoint(130, 220),
      FloorPoint(20, 150),
    ];

    test('calibrates pixels into metres with honest provenance', () {
      final room = buildCalibratedManualSketchRoom(
        id: 'room-sketch',
        name: 'Estudio irregular',
        sketch: sketch,
        referenceEdge: 0,
        referenceMeters: 4,
        height: 2.7,
      );

      expect(room.corners, hasLength(5));
      expect(room.corners.first, const FloorPoint(0, 0));
      expect(edgeLengths(room.corners).first, closeTo(4, 1e-9));
      expect(room.corners[1].x, closeTo(4, 1e-9));
      expect(signedArea(room.corners), greaterThan(0));
      expect(validateContour(room.corners).where((i) => i.blocking), isEmpty);
      expect(room.acquisition.method, RoomAcquisitionMethod.manualSketch);
      expect(room.metrics, isNull);
      expect(room.height, const RoomHeight(2.7, HeightSource.manual));
      expect(buildScene(roomCapture(room)).document['version'], '2.0');
    });

    test('removes a duplicate closing point', () {
      final room = buildCalibratedManualSketchRoom(
        id: 'room-sketch',
        name: 'Estudio',
        sketch: [...sketch, sketch.first],
        referenceEdge: 0,
        referenceMeters: 4,
        height: 2.7,
      );
      expect(room.corners, hasLength(5));
      expect(room.corners.first, isNot(room.corners.last));
    });

    test('rejects incomplete, crossed, zero-edge and invalid calibration', () {
      expect(
        () => buildCalibratedManualSketchRoom(
          id: 'x',
          name: 'x',
          sketch: sketch.take(2).toList(),
          referenceEdge: 0,
          referenceMeters: 4,
          height: 2.7,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildCalibratedManualSketchRoom(
          id: 'x',
          name: 'x',
          sketch: const [
            FloorPoint(0, 0),
            FloorPoint(2, 2),
            FloorPoint(0, 2),
            FloorPoint(2, 0),
          ],
          referenceEdge: 0,
          referenceMeters: 4,
          height: 2.7,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildCalibratedManualSketchRoom(
          id: 'x',
          name: 'x',
          sketch: const [FloorPoint(0, 0), FloorPoint(0, 0), FloorPoint(1, 1)],
          referenceEdge: 0,
          referenceMeters: 4,
          height: 2.7,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildCalibratedManualSketchRoom(
          id: 'x',
          name: 'x',
          sketch: sketch,
          referenceEdge: 0,
          referenceMeters: 0,
          height: 2.7,
        ),
        throwsArgumentError,
      );
    });
  });
}

PropertyCapture roomCapture(CapturedRoom room) => PropertyCapture(
  listingId: 'listing-1',
  rooms: [room],
  connections: const [],
  updatedAt: DateTime.utc(2026),
);
