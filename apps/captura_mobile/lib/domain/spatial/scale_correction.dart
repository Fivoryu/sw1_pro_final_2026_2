import 'capture_models.dart';
import 'validation.dart';

/// Hybrid capture (F07): the phone gives the room's shape, an independent
/// reference (tape or laser) gives its scale. A single factor is fitted to
/// the references and applied to the floor shape and the volumes' footprint.
/// Heights are measured separately and are not rescaled.
class ScaleCorrection {
  const ScaleCorrection({
    required this.factor,
    required this.referenceCount,
    required this.applied,
    required this.residuals,
    this.message,
  });

  /// Least-squares factor: sum(reference · captured) / sum(captured²).
  final double factor;
  final int referenceCount;

  /// False when the factor is implausible; the room is then left as captured.
  final bool applied;

  /// Per referenced edge: corrected length minus reference, in metres. With
  /// one reference it is zero by construction; with two or more it shows how
  /// consistent the capture is.
  final Map<int, double> residuals;

  /// Spanish notice when the correction was not applied.
  final String? message;
}

/// Largest change a reference may impose; beyond it the reference most likely
/// belongs to another edge, so it is reported instead of applied.
const double maxScaleChange = 0.25;

/// The correction implied by [room]'s references, or null without any.
ScaleCorrection? scaleCorrection(CapturedRoom room) {
  final records = toleranceRecords(room);
  if (records.isEmpty) return null;
  var numerator = 0.0;
  var denominator = 0.0;
  for (final record in records) {
    numerator += record.referenceMeters * record.capturedMeters;
    denominator += record.capturedMeters * record.capturedMeters;
  }
  if (denominator == 0) return null;
  final factor = numerator / denominator;
  final plausible =
      factor >= 1 / (1 + maxScaleChange) && factor <= 1 + maxScaleChange;
  return ScaleCorrection(
    factor: factor,
    referenceCount: records.length,
    applied: plausible,
    residuals: {
      for (final record in records)
        record.edgeIndex:
            record.capturedMeters * factor - record.referenceMeters,
    },
    message: plausible
        ? null
        : 'La medida de referencia cambia el ambiente más de un 25 %: revisá '
              'que corresponda al lado elegido.',
  );
}

/// [room] rescaled by its applied correction; the same instance otherwise.
CapturedRoom correctedRoom(CapturedRoom room) {
  final correction = scaleCorrection(room);
  if (correction == null || !correction.applied) return room;
  final factor = correction.factor;
  return room.copyWith(
    corners: [for (final corner in room.corners) corner.scale(factor)],
    boxes: [
      for (final box in room.boxes)
        OccupancyBox(
          id: box.id,
          centerX: box.centerX * factor,
          centerZ: box.centerZ * factor,
          width: box.width * factor,
          depth: box.depth * factor,
          height: box.height,
          source: box.source,
          confidence: box.confidence,
        ),
    ],
  );
}
