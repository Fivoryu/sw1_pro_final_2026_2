import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Top-down plan of a contract v2 scene document: walls, openings and
/// occupancy volumes, scaled to fit. It draws what the capture will send.
class FloorPlanView extends StatelessWidget {
  const FloorPlanView({super.key, required this.document});

  final Map<String, Object?> document;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Plano de la captura',
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: CustomPaint(
            painter: _PlanPainter(
              document,
              wallColor: scheme.onSurface,
              doorColor: scheme.primary,
              windowColor: scheme.tertiary,
              boxColor: scheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Point = ({double x, double z});

class _PlanPainter extends CustomPainter {
  _PlanPainter(
    this.document, {
    required this.wallColor,
    required this.doorColor,
    required this.windowColor,
    required this.boxColor,
  });

  final Map<String, Object?> document;
  final Color wallColor;
  final Color doorColor;
  final Color windowColor;
  final Color boxColor;

  static _Point _point(Object? json) {
    final map = json! as Map;
    return (x: (map['x']! as num).toDouble(), z: (map['z']! as num).toDouble());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final walls = (document['walls'] as List? ?? const [])
        .cast<Map<Object?, Object?>>();
    if (walls.isEmpty) return;
    final points = [
      for (final wall in walls) ...[_point(wall['start']), _point(wall['end'])],
    ];
    final minX = points.map((p) => p.x).reduce(math.min);
    final maxX = points.map((p) => p.x).reduce(math.max);
    final minZ = points.map((p) => p.z).reduce(math.min);
    final maxZ = points.map((p) => p.z).reduce(math.max);
    const margin = 16.0;
    final scale = math.min(
      (size.width - 2 * margin) / math.max(maxX - minX, 0.5),
      (size.height - 2 * margin) / math.max(maxZ - minZ, 0.5),
    );
    Offset map(_Point p) =>
        Offset(margin + (p.x - minX) * scale, margin + (p.z - minZ) * scale);

    final boxPaint = Paint()
      ..color = boxColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    for (final object
        in (document['objects'] as List? ?? const [])
            .cast<Map<Object?, Object?>>()) {
      final position = object['position']! as Map;
      final dimensions = object['dimensions']! as Map;
      final width = (dimensions['width']! as num).toDouble();
      final depth = (dimensions['depth']! as num).toDouble();
      final centre = map((
        x: (position['x']! as num).toDouble(),
        z: (position['z']! as num).toDouble(),
      ));
      canvas.drawRect(
        Rect.fromCenter(
          center: centre,
          width: width * scale,
          height: depth * scale,
        ),
        boxPaint,
      );
    }

    final byId = {for (final wall in walls) wall['id']: wall};
    for (final wall in walls) {
      final thickness = (wall['thickness'] as num? ?? 0.15).toDouble();
      canvas.drawLine(
        map(_point(wall['start'])),
        map(_point(wall['end'])),
        Paint()
          ..color = wallColor
          ..strokeWidth = math.max(2, thickness * scale)
          ..strokeCap = StrokeCap.square,
      );
    }

    for (final opening
        in (document['openings'] as List? ?? const [])
            .cast<Map<Object?, Object?>>()) {
      final wall = byId[opening['wallId']];
      if (wall == null) continue;
      final start = _point(wall['start']);
      final end = _point(wall['end']);
      final length = math.sqrt(
        math.pow(end.x - start.x, 2) + math.pow(end.z - start.z, 2),
      );
      if (length == 0) continue;
      final position = (opening['position']! as num).toDouble();
      final half = (opening['width']! as num).toDouble() / 2 / length;
      _Point along(double t) => (
        x: start.x + (end.x - start.x) * t,
        z: start.z + (end.z - start.z) * t,
      );
      final thickness = (wall['thickness'] as num? ?? 0.15).toDouble();
      canvas.drawLine(
        map(along(position - half)),
        map(along(position + half)),
        Paint()
          ..color = opening['type'] == 'door' ? doorColor : windowColor
          ..strokeWidth = math.max(3, thickness * scale + 2),
      );
    }
  }

  @override
  bool shouldRepaint(_PlanPainter old) => old.document != document;
}
