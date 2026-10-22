import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 4 × 3 room as the AR captured it, with optional tape references.
CapturedRoom _room({
  List<ReferenceMeasurement> references = const [],
  List<OccupancyBox> boxes = const [],
  RoomHeight height = const RoomHeight(2.5, HeightSource.ceilingPlane),
}) => CapturedRoom(
  id: 'room-1',
  name: 'Estar',
  corners: const [
    FloorPoint(0, 0),
    FloorPoint(4, 0),
    FloorPoint(4, 3),
    FloorPoint(0, 3),
  ],
  height: height,
  openings: const [],
  boxes: boxes,
  references: references,
  metrics: const CaptureMetrics(
    durationMs: 1000,
    trackingLossCount: 0,
    depthSupported: true,
    cornerHitDistances: [1, 1, 1, 1],
    floorY: -1.3,
  ),
);

void main() {
  group('scaleCorrection', () {
    test('is absent without references: nothing is corrected', () {
      expect(scaleCorrection(_room()), isNull);
    });

    test('one reference scales the room to match it', () {
      final correction = scaleCorrection(
        _room(
          references: const [
            ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.2),
          ],
        ),
      )!;

      expect(correction.applied, isTrue);
      expect(correction.factor, closeTo(1.05, 1e-9));
      expect(correction.referenceCount, 1);
    });

    test(
      'several references use the least-squares factor and keep residuals',
      () {
        final correction = scaleCorrection(
          _room(
            references: const [
              ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.2),
              ReferenceMeasurement(edgeIndex: 1, referenceMeters: 3.0),
            ],
          ),
        )!;

        // sum(r·c) / sum(c²) = (4.2·4 + 3·3) / (16 + 9) = 25.8 / 25.
        expect(correction.factor, closeTo(1.032, 1e-9));
        expect(correction.residuals[0], closeTo(4 * 1.032 - 4.2, 1e-9));
        expect(correction.residuals[1], closeTo(3 * 1.032 - 3.0, 1e-9));
      },
    );

    test(
      'refuses a reference that would change the room by more than 25 %',
      () {
        final correction = scaleCorrection(
          _room(
            references: const [
              ReferenceMeasurement(edgeIndex: 0, referenceMeters: 6),
            ],
          ),
        )!;

        expect(correction.applied, isFalse);
        expect(correction.message, contains('lado'));
      },
    );
  });

  group('correctedRoom', () {
    test(
      'scales the floor shape and the volumes footprint, not the height',
      () {
        final room = _room(
          references: const [
            ReferenceMeasurement(edgeIndex: 0, referenceMeters: 4.2),
          ],
          boxes: const [
            OccupancyBox(
              id: 'box-1',
              centerX: 1,
              centerZ: 1,
              width: 0.8,
              depth: 0.6,
              height: 0.75,
              source: BoxSource.depth,
              confidence: 0.8,
            ),
          ],
        );

        final corrected = correctedRoom(room);

        expect(edgeLengths(corrected.corners)[0], closeTo(4.2, 1e-9));
        expect(edgeLengths(corrected.corners)[1], closeTo(3.15, 1e-9));
        final box = corrected.boxes.single;
        expect(box.centerX, closeTo(1.05, 1e-9));
        expect(box.width, closeTo(0.84, 1e-9));
        expect(box.depth, closeTo(0.63, 1e-9));
        expect(box.height, 0.75);
        expect(box.source, BoxSource.depth);
        expect(corrected.height, room.height);
      },
    );

    test('leaves the room untouched when no correction applies', () {
      final room = _room();

      expect(identical(correctedRoom(room), room), isTrue);
    });
  });
}
