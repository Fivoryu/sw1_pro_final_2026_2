import 'dart:convert';

import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('floorplan trace geometry', () {
    test('calibrates normalized image coordinates into metric Scene v2', () {
      final room = buildCalibratedFloorplanTraceRoom(
        id: 'room-plan',
        name: 'Dormitorio plano',
        normalizedTrace: const [
          FloorPoint(0.1, 0.2),
          FloorPoint(0.5, 0.2),
          FloorPoint(0.5, 0.6),
          FloorPoint(0.1, 0.6),
        ],
        imageWidth: 1000,
        imageHeight: 800,
        referenceEdge: 0,
        referenceMeters: 4.2,
        height: 2.65,
      );

      expect(edgeLengths(room.corners).first, closeTo(4.2, 1e-9));
      expect(signedArea(room.corners), greaterThan(0));
      expect(room.height, const RoomHeight(2.65, HeightSource.manual));
      expect(room.acquisition.method, RoomAcquisitionMethod.floorplanTrace);
      expect(room.metrics, isNull);
      final scene = buildScene(
        PropertyCapture(
          listingId: 'listing-1',
          rooms: [room],
          connections: const [],
          updatedAt: DateTime.utc(2026),
        ),
      ).document;
      expect(scene['version'], '2.0');
      expect(jsonEncode(scene), isNot(contains('source')));
      expect(jsonEncode(scene), isNot(contains('floorplan')));
    });

    test(
      'calibrates 1000x800 traces in source pixels, not normalized space',
      () {
        const imageWidth = 1000;
        const imageHeight = 800;
        const pixels = [
          FloorPoint(100, 100),
          FloorPoint(500, 100),
          FloorPoint(500, 400),
          FloorPoint(100, 400),
        ];
        final trace = [
          for (final point in pixels)
            FloorPoint(point.x / imageWidth, point.z / imageHeight),
        ];
        CapturedRoom calibrate(int referenceEdge, double referenceMeters) =>
            buildCalibratedFloorplanTraceRoom(
              id: 'plan',
              name: 'Rectangulo',
              normalizedTrace: trace,
              imageWidth: imageWidth,
              imageHeight: imageHeight,
              referenceEdge: referenceEdge,
              referenceMeters: referenceMeters,
              height: 2.5,
            );

        final horizontal = calibrate(0, 4);
        final lengths = edgeLengths(horizontal.corners);
        expect(lengths[0], closeTo(4, 1e-9));
        expect(lengths[1], closeTo(3, 1e-9));
        expect(lengths[2], closeTo(4, 1e-9));
        expect(lengths[3], closeTo(3, 1e-9));
        expect(polygonArea(horizontal.corners), closeTo(12, 1e-9));
        expect(perimeter(horizontal.corners), closeTo(14, 1e-9));

        final vertical = calibrate(1, 3);
        expect(vertical.corners, hasLength(horizontal.corners.length));
        for (var i = 0; i < horizontal.corners.length; i++) {
          expect(
            vertical.corners[i].x,
            closeTo(horizontal.corners[i].x, 1e-9),
            reason: 'vertical calibration must match horizontal at vertex $i',
          );
          expect(
            vertical.corners[i].z,
            closeTo(horizontal.corners[i].z, 1e-9),
            reason: 'vertical calibration must match horizontal at vertex $i',
          );
        }
        expect(polygonArea(vertical.corners), closeTo(12, 1e-9));
        expect(perimeter(vertical.corners), closeTo(14, 1e-9));
      },
    );

    test('keeps pixel proportions of an irregular non-square trace', () {
      const imageWidth = 1000;
      const imageHeight = 800;
      const pixels = [
        FloorPoint(100, 100),
        FloorPoint(500, 100),
        FloorPoint(500, 400),
        FloorPoint(300, 400),
        FloorPoint(300, 600),
        FloorPoint(100, 600),
      ];
      final trace = [
        for (final point in pixels)
          FloorPoint(point.x / imageWidth, point.z / imageHeight),
      ];
      final before = edgeLengths(pixels);
      final room = buildCalibratedFloorplanTraceRoom(
        id: 'r',
        name: 'Irregular',
        normalizedTrace: trace,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        referenceEdge: 0,
        referenceMeters: 4,
        height: 2.5,
      );
      final after = edgeLengths(room.corners);
      expect(after.first, closeTo(4, 1e-9));
      for (var i = 1; i < before.length; i++) {
        expect(
          after[i] / after.first,
          closeTo(before[i] / before.first, 1e-9),
          reason: 'edge $i must keep its source-image proportion',
        );
      }
      expect(polygonArea(room.corners), closeTo(16, 1e-9));
      expect(perimeter(room.corners), closeTo(18, 1e-9));
    });

    test('normalizes contain coordinates independently from viewport size', () {
      final small = normalizedTracePoint(
        sceneX: 180,
        sceneY: 400,
        viewportWidth: 360,
        viewportHeight: 800,
        imageWidth: 1000,
        imageHeight: 800,
      );
      final large = normalizedTracePoint(
        sceneX: 360,
        sceneY: 400,
        viewportWidth: 720,
        viewportHeight: 800,
        imageWidth: 1000,
        imageHeight: 800,
      );
      expect(small, const FloorPoint(0.5, 0.5));
      expect(large, const FloorPoint(0.5, 0.5));
    });

    test('rejects taps in letterboxing and invalid contours', () {
      expect(
        normalizedTracePoint(
          sceneX: 10,
          sceneY: 10,
          viewportWidth: 360,
          viewportHeight: 800,
          imageWidth: 1000,
          imageHeight: 800,
        ),
        isNull,
      );
      expect(
        () => buildCalibratedFloorplanTraceRoom(
          id: 'r',
          name: 'x',
          normalizedTrace: const [
            FloorPoint(0, 0),
            FloorPoint(1, 1),
            FloorPoint(0, 1),
            FloorPoint(1, 0),
          ],
          imageWidth: 1000,
          imageHeight: 800,
          referenceEdge: 0,
          referenceMeters: 4,
          height: 2.5,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildCalibratedFloorplanTraceRoom(
          id: 'r',
          name: 'x',
          normalizedTrace: const [
            FloorPoint(0, 0),
            FloorPoint(0, 0),
            FloorPoint(1, 1),
          ],
          imageWidth: 1000,
          imageHeight: 800,
          referenceEdge: 0,
          referenceMeters: 4,
          height: 2.5,
        ),
        throwsArgumentError,
      );
    });

    test('vertex hit tolerance is circular in non-square rendered pixels', () {
      const vertices = [FloorPoint(0.5, 0.5)];
      expect(
        nearestTraceVertex(
          point: const FloorPoint(0.52, 0.5),
          vertices: vertices,
          renderedImageWidth: 1000,
          renderedImageHeight: 200,
        ),
        0,
      );
      expect(
        nearestTraceVertex(
          point: const FloorPoint(0.5, 0.6),
          vertices: vertices,
          renderedImageWidth: 1000,
          renderedImageHeight: 200,
        ),
        0,
      );
      expect(
        nearestTraceVertex(
          point: const FloorPoint(0.53, 0.5),
          vertices: vertices,
          renderedImageWidth: 1000,
          renderedImageHeight: 200,
        ),
        isNull,
      );
    });
  });
}
