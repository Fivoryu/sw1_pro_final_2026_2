import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../domain/spatial/geometry.dart';

enum FloorplanAnalysisStatus { success, partial, lowConfidence }

enum FloorplanOpeningCandidateType { unknown, door, window }

class FloorplanOpeningCandidate {
  const FloorplanOpeningCandidate({
    required this.edgeIndex,
    required this.position,
    required this.normalizedWidth,
    this.type = FloorplanOpeningCandidateType.unknown,
  });

  final int edgeIndex;
  final double position;
  final double normalizedWidth;
  final FloorplanOpeningCandidateType type;
}

/// Local diagnostic only. It is never serialized into a capture or Scene v2.
enum FloorplanAnalysisReason {
  detected,
  recoveredStructuralGap,
  ambiguousInterior,
  noUsableInterior,
  invalidContour,
  excessiveSemanticComplexity,
  insufficientStructuralSupport,
}

class FloorplanAnalysisResult {
  const FloorplanAnalysisResult({
    required this.status,
    this.contour = const [],
    required this.message,
    this.reason = FloorplanAnalysisReason.detected,
    this.elapsedMs = 0,
    this.openingCandidates = const [],
  });

  final FloorplanAnalysisStatus status;
  final List<FloorPoint> contour;
  final String message;
  final FloorplanAnalysisReason reason;
  final int elapsedMs;
  final List<FloorplanOpeningCandidate> openingCandidates;
  bool get hasCandidate => contour.length >= 3;
}

String formatFloorplanAnalysisDiagnostic({
  required FloorplanAnalysisResult result,
  required int width,
  required int height,
}) =>
    '[RoomForge][FloorplanImport] source=local_analyzer '
    'result=${switch (result.status) {
      FloorplanAnalysisStatus.success => 'success',
      FloorplanAnalysisStatus.partial => 'partial',
      FloorplanAnalysisStatus.lowConfidence => 'low_confidence',
    }} '
    'reason=${result.reason.name} '
    'elapsedMs=${result.elapsedMs} '
    'image=${width}x$height '
    'contourVertices=${result.contour.length}';

String formatFloorplanImportDiagnostic({
  required String source,
  required String result,
  required int providerCandidates,
  required String selectedRoom,
  required int selectedWalls,
  required int selectedDimensions,
}) =>
    '[RoomForge][FloorplanImport] source=$source result=$result '
    'providerCandidates=$providerCandidates selectedRoom=$selectedRoom '
    'selectedWalls=$selectedWalls selectedDimensions=$selectedDimensions';

/// Extracts the usable interior boundary of one room entirely on-device.
/// Text and furniture normally form smaller regions and cannot enlarge it.
class LocalFloorplanAnalyzer {
  const LocalFloorplanAnalyzer();

  Future<FloorplanAnalysisResult> analyze({
    required List<int> rgba,
    required int width,
    required int height,
  }) => compute(_analyzeFloorplan, (rgba: rgba, width: width, height: height));

  FloorplanAnalysisResult analyzeRgba({
    required List<int> rgba,
    required int width,
    required int height,
  }) {
    final stopwatch = Stopwatch()..start();
    FloorplanAnalysisResult failed(FloorplanAnalysisReason reason) =>
        FloorplanAnalysisResult(
          status: FloorplanAnalysisStatus.lowConfidence,
          message:
              'No pudimos identificar el ambiente con suficiente confianza.',
          reason: reason,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
    if (width < 16 || height < 16 || rgba.length < width * height * 4) {
      return failed(FloorplanAnalysisReason.noUsableInterior);
    }
    final gray = List<int>.filled(width * height, 255);
    final histogram = List<int>.filled(256, 0);
    for (var index = 0; index < gray.length; index++) {
      final offset = index * 4;
      final value = rgba[offset + 3] < 100
          ? 255
          : ((rgba[offset] * 299 +
                        rgba[offset + 1] * 587 +
                        rgba[offset + 2] * 114) /
                    1000)
                .round();
      gray[index] = value;
      histogram[value]++;
    }
    final threshold = _otsu(histogram, gray.length).clamp(35, 220);
    var dark = [for (final value in gray) value <= threshold];
    dark = _dilate(_erode(dark, width, height), width, height);
    dark = _erode(_dilate(dark, width, height), width, height);
    final structuralMask = dark;
    final alreadyEnclosed = _lightComponents(dark, width, height).any(
      (component) =>
          !component.touchesBorder &&
          component.pixels.length >= width * height * 0.08,
    );
    var bridged = alreadyEnclosed
        ? (mask: dark, count: 0, rejectedForSupport: false)
        : _bridgeStructuralGaps(dark, width, height);
    if (!alreadyEnclosed && bridged.count == 0) {
      final envelope = _recoverDominantRectangularEnvelope(dark, width, height);
      if (envelope != null) {
        bridged = (
          mask: envelope,
          count: 1,
          rejectedForSupport: bridged.rejectedForSupport,
        );
      }
    }
    dark = bridged.mask;

    final components =
        _lightComponents(dark, width, height)
            .where((component) => !component.touchesBorder)
            .where(
              (component) => component.pixels.length >= width * height * 0.02,
            )
            .toList()
          ..sort((a, b) => b.pixels.length.compareTo(a.pixels.length));
    if (components.isEmpty) {
      return failed(
        bridged.rejectedForSupport
            ? FloorplanAnalysisReason.insufficientStructuralSupport
            : FloorplanAnalysisReason.noUsableInterior,
      );
    }
    if (components.length > 1 &&
        components[1].pixels.length >= components.first.pixels.length * 0.65) {
      return failed(FloorplanAnalysisReason.ambiguousInterior);
    }

    final shortestSide = width < height ? width : height;
    List<FloorPoint>? semanticContour(_Component component) {
      final raw = _traceBoundary(component, width, height);
      if (raw.length < 3) return null;
      var candidate = _simplifyClosed(raw, 2 / shortestSide);
      candidate = _removeShortEdges(candidate, 3 / shortestSide);
      return _validNormalizedContour(candidate) ? candidate : null;
    }

    var contour = semanticContour(components.first);
    var envelopeRecovered = false;
    if (contour == null || contour.length > 12) {
      // A raster contour with many turns is not automatically a semantic room.
      // Only replace it when four independently supported double wall bands
      // prove a rectangular architectural envelope. This prevents furniture,
      // dimensions and doorway notches from becoming semantic walls.
      final envelope = _recoverDominantRectangularEnvelope(
        structuralMask,
        width,
        height,
      );
      if (envelope != null) {
        final envelopeComponents =
            _lightComponents(envelope, width, height)
                .where((component) => !component.touchesBorder)
                .where(
                  (component) =>
                      component.pixels.length >= width * height * 0.02,
                )
                .toList()
              ..sort((a, b) => b.pixels.length.compareTo(a.pixels.length));
        if (envelopeComponents.isNotEmpty) {
          final recovered = semanticContour(envelopeComponents.first);
          if (recovered != null && recovered.length == 4) {
            contour = recovered;
            envelopeRecovered = true;
          }
        }
      }
    }
    if (contour == null) {
      return failed(FloorplanAnalysisReason.invalidContour);
    }
    if (contour.length > 12) {
      return failed(FloorplanAnalysisReason.excessiveSemanticComplexity);
    }
    if (signedArea(contour) < 0) contour = contour.reversed.toList();

    final support = components.first.pixels.length / (width * height);
    final recovered = bridged.count > 0 || envelopeRecovered;
    final status = !recovered && support >= 0.08
        ? FloorplanAnalysisStatus.success
        : FloorplanAnalysisStatus.partial;
    return FloorplanAnalysisResult(
      status: status,
      contour: List.unmodifiable(contour),
      message: status == FloorplanAnalysisStatus.success
          ? 'Detectamos un contorno. Revisalo y confirmá cada medida.'
          : 'Detectamos un contorno posible. Revisalo antes de continuar.',
      reason: !recovered
          ? FloorplanAnalysisReason.detected
          : FloorplanAnalysisReason.recoveredStructuralGap,
      elapsedMs: stopwatch.elapsedMilliseconds,
      openingCandidates: _detectOpeningCandidates(
        structuralMask,
        width,
        height,
        contour,
      ),
    );
  }
}

List<FloorplanOpeningCandidate> _detectOpeningCandidates(
  List<bool> mask,
  int width,
  int height,
  List<FloorPoint> contour,
) {
  final result = <FloorplanOpeningCandidate>[];
  bool darkNear(double x, double y) {
    final radius = math.max(1, (math.min(width, height) * 0.004).round());
    for (var oy = -radius; oy <= radius; oy++) {
      for (var ox = -radius; ox <= radius; ox++) {
        final px = x.round() + ox;
        final py = y.round() + oy;
        if (px >= 0 &&
            px < width &&
            py >= 0 &&
            py < height &&
            mask[py * width + px]) {
          return true;
        }
      }
    }
    return false;
  }

  for (var edge = 0; edge < contour.length; edge++) {
    final a = contour[edge];
    final b = contour[(edge + 1) % contour.length];
    final pixelLength = math.sqrt(
      math.pow((b.x - a.x) * width, 2) + math.pow((b.z - a.z) * height, 2),
    );
    final samples = pixelLength.round().clamp(20, 600);
    var runStart = -1;
    for (var sample = 0; sample <= samples; sample++) {
      final t = sample / samples;
      final supported = darkNear(
        (a.x + (b.x - a.x) * t) * width,
        (a.z + (b.z - a.z) * t) * height,
      );
      if (!supported && runStart < 0) runStart = sample;
      if ((supported || sample == samples) && runStart >= 0) {
        final runEnd = supported ? sample - 1 : sample;
        final normalizedWidth = (runEnd - runStart + 1) / samples;
        final position = (runStart + runEnd) / 2 / samples;
        // A structural opening is internal to a supported wall and materially
        // larger than raster noise, but not most of the wall.
        if (runStart > samples * 0.06 &&
            runEnd < samples * 0.94 &&
            normalizedWidth >= 0.06 &&
            normalizedWidth <= 0.48) {
          result.add(
            FloorplanOpeningCandidate(
              edgeIndex: edge,
              position: position,
              normalizedWidth: normalizedWidth,
            ),
          );
        }
        runStart = -1;
      }
    }
  }
  return List.unmodifiable(result);
}

/// Recovers only an axis-aligned structural envelope whose four sides are
/// independently evidenced. This complements local gap ratios for plans where
/// a large window splits one wall, without turning a U/open sketch into a room.
List<bool>? _recoverDominantRectangularEnvelope(
  List<bool> source,
  int width,
  int height,
) {
  final shortest = math.min(width, height);
  final nearRadius = math.max(1, (shortest * 0.006).round());

  bool darkNear(int x, int y) {
    for (var oy = -nearRadius; oy <= nearRadius; oy++) {
      for (var ox = -nearRadius; ox <= nearRadius; ox++) {
        final nx = x + ox;
        final ny = y + oy;
        if (nx >= 0 &&
            nx < width &&
            ny >= 0 &&
            ny < height &&
            source[ny * width + nx]) {
          return true;
        }
      }
    }
    return false;
  }

  int longestVerticalRun(int x) {
    var longest = 0;
    var current = 0;
    for (var y = 0; y < height; y++) {
      if (darkNear(x, y)) {
        current++;
        longest = math.max(longest, current);
      } else {
        current = 0;
      }
    }
    return longest;
  }

  List<(int, int)> bands(Iterable<int> values) {
    final sorted = values.toList()..sort();
    final result = <(int, int)>[];
    for (final value in sorted) {
      if (result.isEmpty || value > result.last.$2 + 1) {
        result.add((value, value));
      } else {
        result[result.length - 1] = (result.last.$1, value);
      }
    }
    return result;
  }

  final verticalBands = bands([
    for (var x = 1; x < width - 1; x++)
      if (longestVerticalRun(x) >= height * 0.38) x,
  ]).where((band) => band.$2 - band.$1 + 1 >= 2).toList();
  if (verticalBands.length < 2) return null;
  final parallelDistance = shortest * 0.06;

  bool hasParallelBand(
    List<(int, int)> candidates,
    int coordinate, {
    required bool greater,
  }) => candidates.any((band) {
    final center = (band.$1 + band.$2) / 2;
    final delta = greater ? center - coordinate : coordinate - center;
    return delta >= nearRadius * 2 && delta <= parallelDistance;
  });

  ({int left, int right, int top, int bottom, double score})? best;
  for (var leftIndex = 0; leftIndex < verticalBands.length - 1; leftIndex++) {
    for (
      var rightIndex = leftIndex + 1;
      rightIndex < verticalBands.length;
      rightIndex++
    ) {
      final left =
          (verticalBands[leftIndex].$1 + verticalBands[leftIndex].$2) ~/ 2;
      final right =
          (verticalBands[rightIndex].$1 + verticalBands[rightIndex].$2) ~/ 2;
      final span = right - left;
      if (span < width * 0.25) continue;
      if (!hasParallelBand(verticalBands, left, greater: true) ||
          !hasParallelBand(verticalBands, right, greater: false)) {
        continue;
      }

      int inwardSupport(int y, bool fromLeft) {
        var support = 0;
        final maximum = (span * 0.48).floor();
        for (var step = 0; step <= maximum; step++) {
          final x = fromLeft ? left + step : right - step;
          if (!darkNear(x, y)) break;
          support = step;
        }
        return support;
      }

      final horizontalRows = <int>[];
      for (var y = 1; y < height - 1; y++) {
        if (!darkNear(left, y) || !darkNear(right, y)) continue;
        final leftSupport = inwardSupport(y, true);
        final rightSupport = inwardSupport(y, false);
        if (leftSupport >= span * 0.08 && rightSupport >= span * 0.08) {
          horizontalRows.add(y);
        }
      }
      final horizontalBands = bands(
        horizontalRows,
      ).where((band) => band.$2 - band.$1 + 1 >= 2).toList();
      for (
        var topIndex = 0;
        topIndex < horizontalBands.length - 1;
        topIndex++
      ) {
        for (
          var bottomIndex = topIndex + 1;
          bottomIndex < horizontalBands.length;
          bottomIndex++
        ) {
          final top =
              (horizontalBands[topIndex].$1 + horizontalBands[topIndex].$2) ~/
              2;
          final bottom =
              (horizontalBands[bottomIndex].$1 +
                  horizontalBands[bottomIndex].$2) ~/
              2;
          if (bottom - top < height * 0.25) continue;
          if (!hasParallelBand(horizontalBands, top, greater: true) ||
              !hasParallelBand(horizontalBands, bottom, greater: false)) {
            continue;
          }
          final score = span * (bottom - top).toDouble();
          if (best == null || score > best.score) {
            best = (
              left: left,
              right: right,
              top: top,
              bottom: bottom,
              score: score,
            );
          }
        }
      }
    }
  }
  final envelope = best;
  if (envelope == null) return null;
  final result = [...source];
  final radius = math.max(1, nearRadius ~/ 2);
  _drawBridge(
    result,
    width,
    height,
    envelope.left,
    envelope.top,
    envelope.right,
    envelope.top,
    radius: radius,
  );
  _drawBridge(
    result,
    width,
    height,
    envelope.right,
    envelope.top,
    envelope.right,
    envelope.bottom,
    radius: radius,
  );
  _drawBridge(
    result,
    width,
    height,
    envelope.right,
    envelope.bottom,
    envelope.left,
    envelope.bottom,
    radius: radius,
  );
  _drawBridge(
    result,
    width,
    height,
    envelope.left,
    envelope.bottom,
    envelope.left,
    envelope.top,
    radius: radius,
  );
  return result;
}

/// Closes only bounded interruptions backed by collinear wall structure on
/// both sides. The global 45% image bound is only a safety ceiling: acceptance
/// is governed by the local evidence, requiring each missing span to be no
/// longer than 1.75 times the shorter continuous collinear fragment. This
/// admits a large architectural opening (about 43% of a well-supported wall)
/// while a mostly missing side still lacks enough local support. Every
/// candidate is measured against [source], never against bridges added during
/// this pass, so one hypothesis cannot create another.
({List<bool> mask, int count, bool rejectedForSupport}) _bridgeStructuralGaps(
  List<bool> source,
  int width,
  int height,
) {
  final shortest = math.min(width, height);
  final maximumGapPixels = math.max(4.0, shortest * 0.45);
  final minimumSupportPixels = math.max(5.0, shortest * 0.08);
  final maximumSupportPixels = math.max(minimumSupportPixels, shortest * 0.45);
  final result = [...source];
  var rejectedForSupport = false;
  final directions = <(double, double)>[];
  for (var index = 0; index < 180; index++) {
    final angle = index * math.pi / 180;
    directions.add((math.cos(angle), math.sin(angle)));
  }

  bool darkNear(int x, int y) {
    for (var oy = -1; oy <= 1; oy++) {
      for (var ox = -1; ox <= 1; ox++) {
        final nx = x + ox;
        final ny = y + oy;
        if (nx >= 0 &&
            nx < width &&
            ny >= 0 &&
            ny < height &&
            source[ny * width + nx]) {
          return true;
        }
      }
    }
    return false;
  }

  bool isDark(int x, int y) =>
      x >= 0 && x < width && y >= 0 && y < height && source[y * width + x];

  double supportLength(int x, int y, double dx, double dy) {
    final maximumSteps = maximumSupportPixels.floor();
    var continuousSteps = 0;
    for (var step = 1; step <= maximumSteps; step++) {
      if (!darkNear((x + dx * step).round(), (y + dy * step).round())) {
        break;
      }
      continuousSteps = step;
    }
    return continuousSteps.toDouble();
  }

  final candidates =
      <
        ({
          int x1,
          int y1,
          int x2,
          int y2,
          double gap,
          double ratio,
          double angle,
          int radius,
        })
      >[];
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      if (!source[y * width + x]) continue;
      for (final (dx, dy) in directions) {
        if (isDark((x + dx).round(), (y + dy).round())) continue;
        final supportBefore = supportLength(x, y, -dx, -dy);
        if (supportBefore < minimumSupportPixels) continue;
        final maximumGapSteps = maximumGapPixels.floor();
        for (var gap = 2; gap <= maximumGapSteps; gap++) {
          final endX = (x + dx * gap).round();
          final endY = (y + dy * gap).round();
          if (endX <= 0 ||
              endX >= width - 1 ||
              endY <= 0 ||
              endY >= height - 1) {
            break;
          }
          if (!isDark(endX, endY)) continue;
          final supportAfter = supportLength(endX, endY, dx, dy);
          final gapPixels = gap.toDouble();
          final localSupport = math.min(supportBefore, supportAfter);
          if (supportAfter < minimumSupportPixels ||
              gapPixels > localSupport * 1.75) {
            rejectedForSupport = true;
            break;
          }
          final profileA = _wallProfile(
            source,
            width,
            height,
            x,
            y,
            dx,
            dy,
            shortest,
          );
          final profileB = _wallProfile(
            source,
            width,
            height,
            endX,
            endY,
            dx,
            dy,
            shortest,
          );
          candidates.add((
            x1: profileA.centerX,
            y1: profileA.centerY,
            x2: profileB.centerX,
            y2: profileB.centerY,
            gap: gapPixels,
            ratio: gapPixels / localSupport,
            angle: math.atan2(dy, dx),
            radius: math.max(profileA.radius, profileB.radius),
          ));
          break;
        }
      }
    }
  }
  candidates.sort((a, b) {
    final ratio = a.ratio.compareTo(b.ratio);
    return ratio != 0 ? ratio : a.gap.compareTo(b.gap);
  });
  final selected =
      <
        ({
          int x1,
          int y1,
          int x2,
          int y2,
          double gap,
          double ratio,
          double angle,
          int radius,
        })
      >[];
  final sameGapDistance = shortest * 0.04;
  for (final candidate in candidates) {
    final midpointX = (candidate.x1 + candidate.x2) / 2;
    final midpointY = (candidate.y1 + candidate.y2) / 2;
    final duplicate = selected.any((other) {
      final dx = midpointX - (other.x1 + other.x2) / 2;
      final dy = midpointY - (other.y1 + other.y2) / 2;
      var angle = (candidate.angle - other.angle).abs() % math.pi;
      if (angle > math.pi / 2) angle = math.pi - angle;
      return math.sqrt(dx * dx + dy * dy) <= sameGapDistance &&
          angle <= math.pi / 12;
    });
    if (!duplicate) selected.add(candidate);
  }
  for (final bridge in selected) {
    _drawBridge(
      result,
      width,
      height,
      bridge.x1,
      bridge.y1,
      bridge.x2,
      bridge.y2,
      radius: bridge.radius,
    );
  }
  final bridges = selected.length;
  if (bridges == 0 ||
      !_lightComponents(result, width, height).any(
        (component) =>
            !component.touchesBorder &&
            component.pixels.length >= width * height * 0.02,
      )) {
    return (mask: source, count: 0, rejectedForSupport: rejectedForSupport);
  }
  return (mask: result, count: bridges, rejectedForSupport: rejectedForSupport);
}

void _drawBridge(
  List<bool> mask,
  int width,
  int height,
  int x1,
  int y1,
  int x2,
  int y2, {
  required int radius,
}) {
  final steps = math.max((x2 - x1).abs(), (y2 - y1).abs());
  for (var step = 0; step <= steps; step++) {
    final t = steps == 0 ? 0.0 : step / steps;
    final x = (x1 + (x2 - x1) * t).round();
    final y = (y1 + (y2 - y1) * t).round();
    for (var oy = -radius; oy <= radius; oy++) {
      for (var ox = -radius; ox <= radius; ox++) {
        final nx = x + ox;
        final ny = y + oy;
        if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
          mask[ny * width + nx] = true;
        }
      }
    }
  }
}

({int centerX, int centerY, int radius}) _wallProfile(
  List<bool> source,
  int width,
  int height,
  int x,
  int y,
  double dx,
  double dy,
  int shortest,
) {
  final maximum = math.max(2, (shortest * 0.04).round());
  final perpendicularX = -dy;
  final perpendicularY = dx;
  var negative = 0;
  var positive = 0;
  bool isDark(int px, int py) =>
      px >= 0 &&
      px < width &&
      py >= 0 &&
      py < height &&
      source[py * width + px];
  for (var distance = 1; distance <= maximum; distance++) {
    if (!isDark(
      (x - perpendicularX * distance).round(),
      (y - perpendicularY * distance).round(),
    )) {
      break;
    }
    negative = distance;
  }
  for (var distance = 1; distance <= maximum; distance++) {
    if (!isDark(
      (x + perpendicularX * distance).round(),
      (y + perpendicularY * distance).round(),
    )) {
      break;
    }
    positive = distance;
  }
  final shift = (positive - negative) / 2;
  return (
    centerX: (x + perpendicularX * shift).round(),
    centerY: (y + perpendicularY * shift).round(),
    radius: math.max(1, ((negative + positive + 1) / 2).ceil()),
  );
}

int _otsu(List<int> histogram, int total) {
  var sum = 0.0;
  for (var index = 0; index < histogram.length; index++) {
    sum += index * histogram[index];
  }
  var backgroundWeight = 0;
  var backgroundSum = 0.0;
  var bestVariance = -1.0;
  var best = 127;
  for (var value = 0; value < 256; value++) {
    backgroundWeight += histogram[value];
    if (backgroundWeight == 0) continue;
    final foregroundWeight = total - backgroundWeight;
    if (foregroundWeight == 0) break;
    backgroundSum += value * histogram[value];
    final difference =
        backgroundSum / backgroundWeight -
        (sum - backgroundSum) / foregroundWeight;
    final variance =
        backgroundWeight * foregroundWeight * difference * difference;
    if (variance > bestVariance) {
      bestVariance = variance;
      best = value;
    }
  }
  return best;
}

List<bool> _dilate(List<bool> source, int width, int height) {
  final result = List<bool>.filled(source.length, false);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      for (var dy = -1; dy <= 1 && !result[y * width + x]; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
            result[y * width + x] = source[ny * width + nx];
            if (result[y * width + x]) break;
          }
        }
      }
    }
  }
  return result;
}

List<bool> _erode(List<bool> source, int width, int height) {
  final result = List<bool>.filled(source.length, false);
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      var all = true;
      for (var dy = -1; dy <= 1 && all; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (!source[(y + dy) * width + x + dx]) {
            all = false;
            break;
          }
        }
      }
      result[y * width + x] = all;
    }
  }
  return result;
}

class _Component {
  _Component(this.pixels, this.touchesBorder);
  final List<int> pixels;
  final bool touchesBorder;
}

List<_Component> _lightComponents(List<bool> dark, int width, int height) {
  final visited = List<bool>.filled(dark.length, false);
  final result = <_Component>[];
  const directions = [(-1, 0), (1, 0), (0, -1), (0, 1)];
  for (var start = 0; start < dark.length; start++) {
    if (dark[start] || visited[start]) continue;
    final queue = Queue<int>()..add(start);
    final pixels = <int>[];
    var border = false;
    visited[start] = true;
    while (queue.isNotEmpty) {
      final index = queue.removeFirst();
      pixels.add(index);
      final x = index % width;
      final y = index ~/ width;
      border |= x == 0 || y == 0 || x == width - 1 || y == height - 1;
      for (final (dx, dy) in directions) {
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
        final next = ny * width + nx;
        if (!dark[next] && !visited[next]) {
          visited[next] = true;
          queue.add(next);
        }
      }
    }
    result.add(_Component(pixels, border));
  }
  return result;
}

List<FloorPoint> _traceBoundary(_Component component, int width, int height) {
  final inside = component.pixels.toSet();
  final next = <(int, int), (int, int)>{};
  bool has(int x, int y) =>
      x >= 0 &&
      x < width &&
      y >= 0 &&
      y < height &&
      inside.contains(y * width + x);
  void edge((int, int) a, (int, int) b) => next[a] = b;
  for (final index in component.pixels) {
    final x = index % width;
    final y = index ~/ width;
    if (!has(x, y - 1)) edge((x, y), (x + 1, y));
    if (!has(x + 1, y)) edge((x + 1, y), (x + 1, y + 1));
    if (!has(x, y + 1)) edge((x + 1, y + 1), (x, y + 1));
    if (!has(x - 1, y)) edge((x, y + 1), (x, y));
  }
  if (next.isEmpty) return const [];
  final start = next.keys.reduce(
    (a, b) => a.$2 < b.$2 || (a.$2 == b.$2 && a.$1 < b.$1) ? a : b,
  );
  final points = <FloorPoint>[];
  var current = start;
  do {
    points.add(FloorPoint(current.$1 / width, current.$2 / height));
    final following = next[current];
    if (following == null) return const [];
    current = following;
  } while (current != start && points.length <= next.length);
  return current == start ? points : const [];
}

List<FloorPoint> _simplifyClosed(List<FloorPoint> points, double epsilon) {
  if (points.length <= 3) return [...points];
  var first = 0;
  var second = 1;
  var greatest = -1.0;
  for (var index = 1; index < points.length; index++) {
    final distance = points.first.distanceTo(points[index]);
    if (distance > greatest) {
      greatest = distance;
      second = index;
    }
  }
  greatest = -1;
  for (var index = 0; index < points.length; index++) {
    final distance = points[second].distanceTo(points[index]);
    if (distance > greatest) {
      greatest = distance;
      first = index;
    }
  }
  if (first > second) (first, second) = (second, first);
  final forward = points.sublist(first, second + 1);
  final backward = [...points.sublist(second), ...points.sublist(0, first + 1)];
  final simplifiedForward = _simplifyOpen(forward, epsilon);
  final simplifiedBackward = _simplifyOpen(backward, epsilon);
  return [
    ...simplifiedForward.take(simplifiedForward.length - 1),
    ...simplifiedBackward.take(simplifiedBackward.length - 1),
  ];
}

List<FloorPoint> _simplifyOpen(List<FloorPoint> points, double epsilon) {
  if (points.length <= 2) return [...points];
  var farthest = -1;
  var maximumDistance = -1.0;
  for (var index = 1; index < points.length - 1; index++) {
    final distance = _lineDistance(points[index], points.first, points.last);
    if (distance > maximumDistance) {
      maximumDistance = distance;
      farthest = index;
    }
  }
  if (maximumDistance <= epsilon) return [points.first, points.last];
  final before = _simplifyOpen(points.sublist(0, farthest + 1), epsilon);
  final after = _simplifyOpen(points.sublist(farthest), epsilon);
  return [...before.take(before.length - 1), ...after];
}

double _lineDistance(FloorPoint point, FloorPoint start, FloorPoint end) {
  final delta = end - start;
  if (delta.length == 0) return point.distanceTo(start);
  return ((delta.z * point.x -
              delta.x * point.z +
              end.x * start.z -
              end.z * start.x)
          .abs()) /
      delta.length;
}

List<FloorPoint> _removeShortEdges(List<FloorPoint> points, double minimum) {
  final result = [...points];
  var changed = true;
  while (changed && result.length > 3) {
    changed = false;
    for (var index = 0; index < result.length; index++) {
      if (result[index].distanceTo(result[(index + 1) % result.length]) <
          minimum) {
        result.removeAt((index + 1) % result.length);
        changed = true;
        break;
      }
    }
  }
  return result;
}

bool _validNormalizedContour(List<FloorPoint> points) {
  if (points.length < 3 || signedArea(points).abs() < 0.002) return false;
  for (var index = 0; index < points.length; index++) {
    if (points[index].distanceTo(points[(index + 1) % points.length]) < 0.005) {
      return false;
    }
    for (var other = index + 1; other < points.length; other++) {
      if (other == index + 1 || (index == 0 && other == points.length - 1)) {
        continue;
      }
      if (_segmentsCross(
        points[index],
        points[(index + 1) % points.length],
        points[other],
        points[(other + 1) % points.length],
      )) {
        return false;
      }
    }
  }
  return true;
}

bool _segmentsCross(FloorPoint a, FloorPoint b, FloorPoint c, FloorPoint d) {
  double side(FloorPoint p, FloorPoint q, FloorPoint r) =>
      (q.x - p.x) * (r.z - p.z) - (q.z - p.z) * (r.x - p.x);
  final abC = side(a, b, c);
  final abD = side(a, b, d);
  final cdA = side(c, d, a);
  final cdB = side(c, d, b);
  return abC * abD < -1e-12 && cdA * cdB < -1e-12;
}

FloorplanAnalysisResult _analyzeFloorplan(
  ({List<int> rgba, int width, int height}) input,
) => const LocalFloorplanAnalyzer().analyzeRgba(
  rgba: input.rgba,
  width: input.width,
  height: input.height,
);
