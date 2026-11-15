import 'dart:math' as math;

import 'package:captura_mobile/data/services/local_floorplan_analyzer.dart';
import 'package:captura_mobile/domain/spatial/spatial.dart';
import 'package:flutter_test/flutter_test.dart';

class _Raster {
  _Raster([this.width = 120, this.height = 100])
    : rgba = List<int>.filled(width * height * 4, 255);
  final int width;
  final int height;
  final List<int> rgba;

  int get wallRadius => math.max(1, (math.min(width, height) / 300).round());

  (int, int) scaled((double, double) point) =>
      ((point.$1 * (width - 1)).round(), (point.$2 * (height - 1)).round());

  void black(int x, int y, {int radius = 1}) {
    _paint(x, y, radius: radius, value: 0);
  }

  void white(int x, int y, {int radius = 1}) {
    _paint(x, y, radius: radius, value: 255);
  }

  void _paint(int x, int y, {required int radius, required int value}) {
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px < 0 || px >= width || py < 0 || py >= height) continue;
        final offset = (py * width + px) * 4;
        rgba[offset] = rgba[offset + 1] = rgba[offset + 2] = value;
      }
    }
  }

  void line((int, int) a, (int, int) b, {int radius = 1}) {
    final steps = math.max((b.$1 - a.$1).abs(), (b.$2 - a.$2).abs());
    for (var step = 0; step <= steps; step++) {
      final t = steps == 0 ? 0.0 : step / steps;
      black(
        (a.$1 + (b.$1 - a.$1) * t).round(),
        (a.$2 + (b.$2 - a.$2) * t).round(),
        radius: radius,
      );
    }
  }

  void polygon(List<(int, int)> points, {int radius = 1}) {
    for (var index = 0; index < points.length; index++) {
      line(points[index], points[(index + 1) % points.length], radius: radius);
    }
  }

  void normalizedLine((double, double) a, (double, double) b) {
    line(scaled(a), scaled(b), radius: wallRadius);
  }

  void normalizedPolygon(List<(double, double)> points) {
    for (var index = 0; index < points.length; index++) {
      normalizedLine(points[index], points[(index + 1) % points.length]);
    }
  }

  void normalizedGap(
    (double, double) a,
    (double, double) b, {
    required double from,
    required double to,
  }) {
    final start = (a.$1 + (b.$1 - a.$1) * from, a.$2 + (b.$2 - a.$2) * from);
    final end = (a.$1 + (b.$1 - a.$1) * to, a.$2 + (b.$2 - a.$2) * to);
    final pa = scaled(start);
    final pb = scaled(end);
    final steps = math.max((pb.$1 - pa.$1).abs(), (pb.$2 - pa.$2).abs());
    for (var step = 0; step <= steps; step++) {
      final t = steps == 0 ? 0.0 : step / steps;
      white(
        (pa.$1 + (pb.$1 - pa.$1) * t).round(),
        (pa.$2 + (pb.$2 - pa.$2) * t).round(),
        radius: wallRadius + 1,
      );
    }
  }
}

FloorplanAnalysisResult _analyze(_Raster fixture) =>
    const LocalFloorplanAnalyzer().analyzeRgba(
      rgba: fixture.rgba,
      width: fixture.width,
      height: fixture.height,
    );

const _resolutions = [(120, 100), (480, 400), (1080, 900)];

bool _isSimple(List<FloorPoint> contour) {
  double side(FloorPoint a, FloorPoint b, FloorPoint c) =>
      (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x);
  for (var edge = 0; edge < contour.length; edge++) {
    final a = contour[edge];
    final b = contour[(edge + 1) % contour.length];
    for (var other = edge + 1; other < contour.length; other++) {
      if (other == edge + 1 || (edge == 0 && other == contour.length - 1)) {
        continue;
      }
      final c = contour[other];
      final d = contour[(other + 1) % contour.length];
      if (side(a, b, c) * side(a, b, d) < 0 &&
          side(c, d, a) * side(c, d, b) < 0) {
        return false;
      }
    }
  }
  return true;
}

void main() {
  test('formats privacy-safe typed runtime diagnostics', () {
    for (final entry in const [
      (FloorplanAnalysisStatus.success, FloorplanAnalysisReason.detected, 4),
      (
        FloorplanAnalysisStatus.partial,
        FloorplanAnalysisReason.recoveredStructuralGap,
        4,
      ),
      (
        FloorplanAnalysisStatus.lowConfidence,
        FloorplanAnalysisReason.insufficientStructuralSupport,
        0,
      ),
    ]) {
      final diagnostic = formatFloorplanAnalysisDiagnostic(
        result: FloorplanAnalysisResult(
          status: entry.$1,
          reason: entry.$2,
          elapsedMs: 84,
          contour: List.filled(entry.$3, const FloorPoint(0, 0)),
          message: 'local',
        ),
        width: 495,
        height: 619,
      );
      expect(
        diagnostic,
        contains(
          'result=${switch (entry.$1) {
            FloorplanAnalysisStatus.success => 'success',
            FloorplanAnalysisStatus.partial => 'partial',
            FloorplanAnalysisStatus.lowConfidence => 'low_confidence',
          }}',
        ),
      );
      expect(diagnostic, contains('source=local_analyzer'));
      expect(diagnostic, isNot(contains('[FloorplanAnalyzer]')));
      expect(diagnostic, contains('reason=${entry.$2.name}'));
      expect(diagnostic, contains('elapsedMs=84'));
      expect(diagnostic, contains('image=495x619'));
      expect(diagnostic, contains('contourVertices=${entry.$3}'));
      expect(diagnostic, isNot(contains('sourceId')));
    }
  });

  test('attributes provider diagnostics to Groq, not the local analyzer', () {
    final diagnostic = formatFloorplanImportDiagnostic(
      source: 'groq',
      result: 'success',
      providerCandidates: 3,
      selectedRoom: 'room-b',
      selectedWalls: 6,
      selectedDimensions: 6,
    );

    expect(
      diagnostic,
      '[RoomForge][FloorplanImport] source=groq result=success '
      'providerCandidates=3 selectedRoom=room-b '
      'selectedWalls=6 selectedDimensions=6',
    );
    expect(diagnostic, isNot(contains('[FloorplanAnalyzer]')));
  });

  test('B1 extracts a clean rectangular interior', () {
    final fixture = _Raster()
      ..polygon([(15, 12), (100, 12), (100, 85), (15, 85)]);
    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.success);
    expect(result.reason, FloorplanAnalysisReason.detected);
    expect(result.elapsedMs, greaterThanOrEqualTo(0));
    expect(result.contour, hasLength(4));
  });

  test('B2 preserves an L room with six logical walls', () {
    final fixture = _Raster()
      ..polygon([(12, 10), (105, 10), (105, 48), (65, 48), (65, 88), (12, 88)]);
    final result = _analyze(fixture);
    expect(result.hasCandidate, isTrue);
    expect(result.contour, hasLength(6));
  });

  test('B3 preserves a diagonal trapezoid', () {
    final fixture = _Raster()
      ..polygon([(20, 15), (98, 15), (108, 82), (10, 82)]);
    final result = _analyze(fixture);
    expect(result.hasCandidate, isTrue);
    expect(result.contour, hasLength(4));
    expect(
      result.contour.any(
        (point) =>
            point.x != result.contour.first.x &&
            point.z != result.contour.first.z,
      ),
      isTrue,
    );
  });

  test('B4 external dimensions do not expand the room', () {
    final fixture = _Raster()
      ..polygon([(20, 20), (95, 20), (95, 80), (20, 80)])
      ..line((10, 8), (105, 8))
      ..line((10, 5), (10, 11))
      ..line((105, 5), (105, 11));
    final result = _analyze(fixture);
    expect(result.contour, hasLength(4));
    expect(
      result.contour.map((point) => point.z).reduce(math.min),
      greaterThan(0.1),
    );
  });

  test('B5 furniture-like internal shapes do not replace the room', () {
    final fixture = _Raster()
      ..polygon([(12, 10), (108, 10), (108, 90), (12, 90)])
      ..polygon([(40, 35), (65, 35), (65, 55), (40, 55)]);
    final result = _analyze(fixture);
    expect(result.contour, hasLength(4));
    expect(polygonArea(result.contour), greaterThan(0.5));
  });

  test('B6 double-line walls produce one interior contour', () {
    final fixture = _Raster()
      ..polygon([(10, 8), (110, 8), (110, 92), (10, 92)])
      ..polygon([(15, 13), (105, 13), (105, 87), (15, 87)]);
    final result = _analyze(fixture);
    expect(result.contour, hasLength(4));
  });

  test('B7 isolated noise is ignored', () {
    final fixture = _Raster()
      ..polygon([(15, 12), (100, 12), (100, 85), (15, 85)]);
    for (var index = 0; index < 80; index++) {
      fixture.black(
        (index * 37) % fixture.width,
        (index * 53) % fixture.height,
        radius: 0,
      );
    }
    expect(_analyze(fixture).contour, hasLength(4));
  });

  test('B8 a dominant structural component wins over a small component', () {
    final fixture = _Raster()
      ..polygon([(8, 8), (90, 8), (90, 90), (8, 90)])
      ..polygon([(98, 15), (115, 15), (115, 32), (98, 32)]);
    final result = _analyze(fixture);
    expect(result.hasCandidate, isTrue);
    expect(polygonArea(result.contour), greaterThan(0.4));
  });

  test('B9 equally plausible rooms are low confidence', () {
    final fixture = _Raster()
      ..polygon([(5, 10), (55, 10), (55, 88), (5, 88)])
      ..polygon([(64, 10), (114, 10), (114, 88), (64, 88)]);
    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.lowConfidence);
    expect(result.contour, isEmpty);
  });

  test('B10 an open sketch never fabricates a rectangle', () {
    final fixture = _Raster()
      ..line((15, 15), (100, 15))
      ..line((100, 15), (100, 80))
      ..line((100, 80), (30, 80));
    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.lowConfidence);
    expect(result.contour, isEmpty);
  });

  test('B11 recovers a rectangle through one door-sized gap', () {
    final fixture = _Raster()
      ..polygon([(15, 12), (100, 12), (100, 85), (15, 85)])
      ..white(58, 85, radius: 3);
    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.partial);
    expect(result.reason, FloorplanAnalysisReason.recoveredStructuralGap);
    expect(result.contour, hasLength(4));
  });

  test('B12 recovers an L room through one doorway gap', () {
    final fixture = _Raster()
      ..polygon([(12, 10), (105, 10), (105, 48), (65, 48), (65, 88), (12, 88)])
      ..white(38, 88, radius: 3);
    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.partial);
    expect(result.contour, hasLength(6));
  });

  test('B13 recovers a small gap on a diagonal trapezoid wall', () {
    final fixture = _Raster()
      ..polygon([(20, 15), (98, 15), (108, 82), (10, 82)])
      ..white(103, 49, radius: 3);
    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.partial);
    expect(result.contour, hasLength(4));
    final diagonal = result.contour.any((point) {
      final next = result
          .contour[(result.contour.indexOf(point) + 1) % result.contour.length];
      return (next.x - point.x).abs() > 0.02 && (next.z - point.z).abs() > 0.2;
    });
    expect(diagonal, isTrue);
  });

  test('B14 recovers two strongly supported small gaps', () {
    final fixture = _Raster()
      ..polygon([(15, 12), (100, 12), (100, 85), (15, 85)])
      ..white(58, 12, radius: 3)
      ..white(58, 85, radius: 3);
    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.partial);
    expect(result.contour, hasLength(4));
  });

  test('B15 does not bridge a large missing wall segment', () {
    final fixture = _Raster()
      ..polygon([(15, 12), (100, 12), (100, 85), (15, 85)]);
    for (var x = 32; x <= 83; x++) {
      fixture.white(x, 85, radius: 2);
    }
    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.lowConfidence);
    expect(result.contour, isEmpty);
  });

  test('B16 U-shaped open sketch remains low confidence', () {
    final fixture = _Raster()
      ..line((15, 15), (100, 15))
      ..line((15, 15), (15, 82))
      ..line((100, 15), (100, 82));
    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.lowConfidence);
    expect(
      result.reason,
      anyOf(
        FloorplanAnalysisReason.noUsableInterior,
        FloorplanAnalysisReason.insufficientStructuralSupport,
      ),
    );
    expect(result.contour, isEmpty);
  });

  test('B17 unrelated facing lines do not create a room', () {
    final fixture = _Raster()
      ..line((12, 30), (48, 30))
      ..line((56, 30), (105, 30));
    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.lowConfidence);
    expect(result.contour, isEmpty);
  });

  test('B18 doorway recovery ignores internal furniture', () {
    final fixture = _Raster()
      ..polygon([(12, 10), (108, 10), (108, 90), (12, 90)])
      ..white(60, 90, radius: 3)
      ..polygon([(40, 35), (65, 35), (65, 55), (40, 55)]);
    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.partial);
    expect(result.contour, hasLength(4));
    expect(polygonArea(result.contour), greaterThan(0.5));
  });

  test('physical topology recovers double walls with window and door gaps', () {
    const outer = [(0.10, 0.14), (0.90, 0.14), (0.90, 0.86), (0.10, 0.86)];
    const inner = [(0.13, 0.17), (0.87, 0.17), (0.87, 0.83), (0.13, 0.83)];
    final fixture = _Raster(495, 619)
      ..normalizedPolygon(outer)
      ..normalizedPolygon(inner)
      ..normalizedGap(outer[0], outer[1], from: 0.285, to: 0.715)
      ..normalizedGap(inner[0], inner[1], from: 0.285, to: 0.715)
      ..normalizedGap(outer[2], outer[3], from: 0.37, to: 0.63)
      ..normalizedGap(inner[2], inner[3], from: 0.37, to: 0.63)
      // Thin external dimensions and extensions.
      ..normalizedLine((0.08, 0.07), (0.92, 0.07))
      ..normalizedLine((0.08, 0.05), (0.08, 0.19))
      ..normalizedLine((0.92, 0.05), (0.92, 0.19))
      // Furniture and annotation-like strokes inside the room.
      ..normalizedPolygon([
        (0.34, 0.38),
        (0.65, 0.38),
        (0.65, 0.62),
        (0.34, 0.62),
      ])
      ..normalizedLine((0.28, 0.72), (0.72, 0.72));

    final result = _analyze(fixture);
    expect(result.status, FloorplanAnalysisStatus.partial);
    expect(result.reason, FloorplanAnalysisReason.recoveredStructuralGap);
    expect(result.contour, hasLength(4));
    expect(result.contour, isNotEmpty);
    expect(_isSimple(result.contour), isTrue);
    expect(polygonArea(result.contour), greaterThan(0.4));
    expect(result.openingCandidates, isNotEmpty);
    expect(
      result.openingCandidates.every(
        (value) => value.type == FloorplanOpeningCandidateType.unknown,
      ),
      isTrue,
    );
  });

  test('quality gate rejects a raster zig-zag as semantic room walls', () {
    final fixture = _Raster(240, 200)
      ..polygon([
        (20, 20),
        (55, 20),
        (55, 28),
        (80, 28),
        (80, 20),
        (115, 20),
        (115, 28),
        (140, 28),
        (140, 20),
        (215, 20),
        (215, 180),
        (180, 180),
        (180, 172),
        (150, 172),
        (150, 180),
        (115, 180),
        (115, 172),
        (85, 172),
        (85, 180),
        (20, 180),
      ]);

    final result = _analyze(fixture);

    expect(result.status, FloorplanAnalysisStatus.lowConfidence);
    expect(result.reason, FloorplanAnalysisReason.excessiveSemanticComplexity);
    expect(result.contour, isEmpty);
  });

  test('FP-05 preserves a structurally supported irregular pentagon', () {
    final fixture = _Raster(240, 200)
      ..polygon([(25, 25), (170, 25), (220, 95), (150, 175), (25, 150)]);

    final result = _analyze(fixture);

    expect(result.status, isNot(FloorplanAnalysisStatus.lowConfidence));
    expect(result.contour, hasLength(5));
    expect(_isSimple(result.contour), isTrue);
  });

  group('multi-resolution proportional gap recovery', () {
    for (final (width, height) in _resolutions) {
      final label = '${width}x$height';

      test('R1 rectangle with realistic door gap at $label', () {
        const points = [(0.12, 0.12), (0.88, 0.12), (0.88, 0.86), (0.12, 0.86)];
        final fixture = _Raster(width, height)
          ..normalizedPolygon(points)
          ..normalizedGap(points[2], points[3], from: 0.4, to: 0.6);
        final result = _analyze(fixture);
        expect(result.status, FloorplanAnalysisStatus.partial);
        expect(result.contour, hasLength(4));
        expect(_isSimple(result.contour), isTrue);
      });

      test('R2 L room with realistic opening at $label', () {
        const points = [
          (0.1, 0.1),
          (0.9, 0.1),
          (0.9, 0.5),
          (0.56, 0.5),
          (0.56, 0.88),
          (0.1, 0.88),
        ];
        final fixture = _Raster(width, height)
          ..normalizedPolygon(points)
          ..normalizedGap(points[4], points[5], from: 0.42, to: 0.58);
        final result = _analyze(fixture);
        expect(result.status, FloorplanAnalysisStatus.partial);
        expect(result.contour, hasLength(6));
      });

      test('R3 trapezoid preserves diagonal opening at $label', () {
        const points = [(0.18, 0.14), (0.82, 0.14), (0.91, 0.84), (0.18, 0.84)];
        final fixture = _Raster(width, height)
          ..normalizedPolygon(points)
          ..normalizedGap(points[1], points[2], from: 0.42, to: 0.58);
        final result = _analyze(fixture);
        expect(result.status, FloorplanAnalysisStatus.partial);
        expect(result.contour, hasLength(4));
        expect(
          result.contour.any((point) {
            final next =
                result.contour[(result.contour.indexOf(point) + 1) %
                    result.contour.length];
            return (next.x - point.x).abs() > 0.025 &&
                (next.z - point.z).abs() > 0.3;
          }),
          isTrue,
        );
      });

      test('R4 two proportional openings at $label', () {
        const points = [(0.12, 0.12), (0.88, 0.12), (0.88, 0.86), (0.12, 0.86)];
        final fixture = _Raster(width, height)
          ..normalizedPolygon(points)
          ..normalizedGap(points[0], points[1], from: 0.4, to: 0.6)
          ..normalizedGap(points[2], points[3], from: 0.4, to: 0.6);
        final result = _analyze(fixture);
        expect(result.status, FloorplanAnalysisStatus.partial);
        expect(result.contour, hasLength(4));
      });

      test('R5 proportional open U stays low confidence at $label', () {
        final fixture = _Raster(width, height)
          ..normalizedLine((0.12, 0.12), (0.88, 0.12))
          ..normalizedLine((0.12, 0.12), (0.12, 0.86))
          ..normalizedLine((0.88, 0.12), (0.88, 0.86));
        final result = _analyze(fixture);
        expect(result.status, FloorplanAnalysisStatus.lowConfidence);
        expect(result.contour, isEmpty);
      });

      test('R6 large missing wall remains open at $label', () {
        const points = [(0.12, 0.12), (0.88, 0.12), (0.88, 0.86), (0.12, 0.86)];
        final fixture = _Raster(width, height)
          ..normalizedPolygon(points)
          ..normalizedGap(points[2], points[3], from: 0.24, to: 0.76);
        final result = _analyze(fixture);
        expect(result.status, FloorplanAnalysisStatus.lowConfidence);
        expect(result.contour, isEmpty);
      });

      test('R7 unrelated facing lines stay low confidence at $label', () {
        final fixture = _Raster(width, height)
          ..normalizedLine((0.1, 0.4), (0.42, 0.4))
          ..normalizedLine((0.58, 0.4), (0.9, 0.4));
        final result = _analyze(fixture);
        expect(result.status, FloorplanAnalysisStatus.lowConfidence);
        expect(result.contour, isEmpty);
      });

      test('R8 gap plus furniture keeps room dominant at $label', () {
        const room = [(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.1, 0.9)];
        final fixture = _Raster(width, height)
          ..normalizedPolygon(room)
          ..normalizedGap(room[2], room[3], from: 0.4, to: 0.6)
          ..normalizedPolygon([
            (0.35, 0.35),
            (0.58, 0.35),
            (0.58, 0.56),
            (0.35, 0.56),
          ]);
        final result = _analyze(fixture);
        expect(result.status, FloorplanAnalysisStatus.partial);
        expect(result.contour, hasLength(4));
        expect(polygonArea(result.contour), greaterThan(0.5));
      });

      test('REAL-1 two architectural openings remain one room at $label', () {
        const room = [(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.1, 0.9)];
        final fixture = _Raster(width, height)
          ..normalizedPolygon(room)
          ..normalizedGap(room[0], room[1], from: 0.285, to: 0.715)
          ..normalizedGap(room[2], room[3], from: 0.37, to: 0.63)
          ..normalizedPolygon([
            (0.35, 0.35),
            (0.58, 0.35),
            (0.58, 0.56),
            (0.35, 0.56),
          ]);
        final result = _analyze(fixture);
        expect(result.status, FloorplanAnalysisStatus.partial);
        expect(result.contour, hasLength(4));
        expect(_isSimple(result.contour), isTrue);
      });

      test('REAL-5 an unsupported missing side remains rejected at $label', () {
        const room = [(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.1, 0.9)];
        final fixture = _Raster(width, height)
          ..normalizedPolygon(room)
          ..normalizedGap(room[2], room[3], from: 0.2, to: 0.8);
        final result = _analyze(fixture);
        expect(result.status, FloorplanAnalysisStatus.lowConfidence);
        expect(result.contour, isEmpty);
        expect(
          result.reason,
          anyOf(
            FloorplanAnalysisReason.noUsableInterior,
            FloorplanAnalysisReason.insufficientStructuralSupport,
          ),
        );
      });
    }
  });
}
