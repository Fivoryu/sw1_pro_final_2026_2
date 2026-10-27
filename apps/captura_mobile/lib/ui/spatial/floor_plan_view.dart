import 'dart:math' as math;

import 'package:flutter/material.dart';

@visibleForTesting
bool acceptsWallLabel(Rect candidate, List<Rect> occupied) =>
    !occupied.any((other) => other.inflate(2).overlaps(candidate));

@visibleForTesting
({Offset? doorLeafEnd, Rect? doorArc, List<(Offset, Offset)> windowLines})
openingSymbolGeometry(Offset start, Offset end, {required bool isDoor}) {
  final vector = end - start;
  final length = vector.distance;
  if (length == 0) {
    return (doorLeafEnd: null, doorArc: null, windowLines: const []);
  }
  final normal = Offset(-vector.dy, vector.dx) / length;
  if (isDoor) {
    return (
      doorLeafEnd: start + normal * length,
      doorArc: Rect.fromCircle(center: start, radius: length),
      windowLines: const [],
    );
  }
  return (
    doorLeafEnd: null,
    doorArc: null,
    windowLines: [
      (start + normal * 3, end + normal * 3),
      (start - normal * 3, end - normal * 3),
      (start - normal * 5, start + normal * 5),
      (end - normal * 5, end + normal * 5),
    ],
  );
}

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
              backgroundColor: scheme.surfaceContainerLowest,
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
    required this.backgroundColor,
  });

  final Map<String, Object?> document;
  final Color wallColor;
  final Color doorColor;
  final Color windowColor;
  final Color boxColor;
  final Color backgroundColor;

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

    final rooms = (document['rooms'] as List? ?? const [])
        .cast<Map<Object?, Object?>>();
    final labelStyle = TextStyle(
      color: wallColor,
      fontSize: rooms.length > 1 ? 8 : 11,
      fontWeight: FontWeight.w600,
      backgroundColor: const Color(0xccffffff),
    );
    final occupiedLabels = <Rect>[];
    for (final room in rooms) {
      final wallIds = (room['wallIds'] as List? ?? const []).cast<Object?>();
      final roomPoints = <Offset>[];
      for (final id in wallIds) {
        final wall = byId[id];
        if (wall != null) roomPoints.add(map(_point(wall['start'])));
      }
      if (roomPoints.isEmpty) continue;
      final centroid =
          roomPoints.reduce((a, b) => a + b) / roomPoints.length.toDouble();
      for (var index = 0; index < wallIds.length; index++) {
        final wall = byId[wallIds[index]];
        if (wall == null) continue;
        final start = map(_point(wall['start']));
        final end = map(_point(wall['end']));
        final midpoint = Offset(
          (start.dx + end.dx) / 2,
          (start.dy + end.dy) / 2,
        );
        final painter = TextPainter(
          text: TextSpan(text: 'P${index + 1}', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final inward = centroid - midpoint;
        final distance = inward.distance;
        final offset = distance == 0
            ? const Offset(0, 10)
            : inward / distance * 11;
        final origin =
            midpoint + offset - Offset(painter.width / 2, painter.height / 2);
        final bounds = origin & painter.size;
        if (!acceptsWallLabel(bounds, occupiedLabels)) {
          continue;
        }
        occupiedLabels.add(bounds);
        painter.paint(canvas, origin);
      }
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
      final a = map(along(position - half));
      final b = map(along(position + half));
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = backgroundColor
          ..strokeWidth = math.max(5, thickness * scale + 4),
      );
      final vector = b - a;
      final vectorLength = vector.distance;
      if (vectorLength == 0) continue;
      final symbol = Paint()
        ..color = opening['type'] == 'door' ? doorColor : windowColor
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      final geometry = openingSymbolGeometry(
        a,
        b,
        isDoor: opening['type'] == 'door',
      );
      if (geometry.doorLeafEnd case final leaf?) {
        canvas.drawLine(a, leaf, symbol);
        canvas.drawArc(
          geometry.doorArc!,
          math.atan2(leaf.dy - a.dy, leaf.dx - a.dx),
          math.pi / 2,
          false,
          symbol,
        );
      } else {
        for (final line in geometry.windowLines) {
          canvas.drawLine(line.$1, line.$2, symbol);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PlanPainter old) => old.document != document;
}
