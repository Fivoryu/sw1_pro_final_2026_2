import 'dart:math' as math;

import 'capture_models.dart';
import 'geometry.dart';

/// Vertices closer than this (metres) become one canonical vertex, and a
/// vertex this close to the interior of a wall splits it.
const double weldTolerance = 0.03;

/// Neutral colour of occupancy volumes: no class, no price.
const String occupancyColor = '#9e9e9e';

const double _duplicateWallAngleDegrees = 3;
const double _duplicateWallDistance = 0.3;
const double _duplicateWallOverlap = 0.2;

enum SceneWarningCode {
  assumedHeight,
  boxMissingHeight,
  boxRotationApproximated,
  openingExceedsWall,
  possibleDuplicateWall,
  roomsOverlap,
  roomNotConnected,
}

/// Something the agent should review before trusting the generated scene.
class SceneWarning {
  const SceneWarning(this.code, this.message);

  final SceneWarningCode code;

  /// User-facing Spanish message.
  final String message;

  @override
  String toString() => 'SceneWarning($code, $message)';
}

class SceneBuildResult {
  const SceneBuildResult({required this.document, required this.warnings});

  /// Scene contract v2 document (`docs/api/f06-scene-contract.md`).
  final Map<String, Object?> document;
  final List<SceneWarning> warnings;
}

/// Contract v2 document for [capture]; see [buildScene] for the warnings.
Map<String, Object?> buildSceneDocument(PropertyCapture capture) =>
    buildScene(capture).document;

/// Builds the scene contract v2 document of [capture].
///
/// Each captured contour is the interior face of its walls: the wall
/// centrelines are the contour offset outwards by `wallThickness / 2` (miter
/// joints), placed in the property frame and rounded to millimetres. Vertices
/// are then welded, walls are split at vertices lying on them (T-junctions)
/// and walls with the same endpoints are emitted once, so every room's
/// `wallIds` chain with exact coordinate equality.
SceneBuildResult buildScene(PropertyCapture capture) {
  final builder = _SceneBuilder(capture);
  return SceneBuildResult(
    document: builder.build(),
    warnings: builder.warnings,
  );
}

class _WallRecord {
  _WallRecord(this.id, this.start, this.end, this.height);

  final String id;
  final int start;
  final int end;
  RoomHeight height;
}

/// Sub-wall of one room edge, in the direction of that room's contour.
typedef _EdgePiece = ({int wall, int from, int to});

class _SceneBuilder {
  _SceneBuilder(this.capture);

  final PropertyCapture capture;
  final List<SceneWarning> warnings = [];

  final List<FloorPoint> _vertices = [];
  final List<_WallRecord> _walls = [];
  final Map<String, int> _wallByEndpoints = {};

  /// `_edges[room][edge]` lists the pieces that make up that contour edge.
  final List<List<List<_EdgePiece>>> _edges = [];

  double get _halfThickness => capture.wallThickness / 2;

  Map<String, Object?> build() {
    final rooms = capture.rooms;
    final vertexIndexes = [
      for (final room in rooms) [for (final v in _centerline(room)) _weld(v)],
    ];

    final roomDocuments = <Map<String, Object?>>[];
    for (var r = 0; r < rooms.length; r++) {
      final indexes = vertexIndexes[r];
      final pieces = <List<_EdgePiece>>[];
      final wallIds = <String>[];
      for (var i = 0; i < indexes.length; i++) {
        final chain = _splitEdge(indexes[i], indexes[(i + 1) % indexes.length]);
        final edgePieces = <_EdgePiece>[];
        for (var k = 0; k + 1 < chain.length; k++) {
          final wall = _wallFor(chain[k], chain[k + 1], rooms[r].height);
          edgePieces.add((wall: wall, from: chain[k], to: chain[k + 1]));
          final id = _walls[wall].id;
          if (wallIds.isEmpty || wallIds.last != id) wallIds.add(id);
        }
        pieces.add(edgePieces);
      }
      if (wallIds.length > 1 && wallIds.first == wallIds.last) {
        wallIds.removeLast();
      }
      _edges.add(pieces);
      roomDocuments.add({
        'id': 'room-${rooms[r].id}',
        'name': rooms[r].name,
        'wallIds': wallIds,
      });
    }

    final document = <String, Object?>{
      'version': '2.0',
      'unit': 'meters',
      'walls': [for (final wall in _walls) _wallJson(wall)],
      'openings': _openings(),
      'rooms': roomDocuments,
      'objects': _objects(),
    };
    _heightWarnings();
    _duplicateWallWarnings();
    _overlapWarnings();
    _connectivityWarnings();
    return document;
  }

  /// Interior contour offset outwards by half the thickness, in the property
  /// frame, rounded to millimetres.
  List<FloorPoint> _centerline(CapturedRoom room) {
    final interior = room.worldCorners();
    final count = interior.length;
    final result = <FloorPoint>[];
    for (var i = 0; i < count; i++) {
      final previous = interior[(i - 1 + count) % count];
      final corner = interior[i];
      final next = interior[(i + 1) % count];
      final d1 = _unit(corner - previous);
      final d2 = _unit(next - corner);
      final n1 = FloorPoint(d1.z, -d1.x).scale(_halfThickness);
      final n2 = FloorPoint(d2.z, -d2.x).scale(_halfThickness);
      final denominator = d1.cross(d2);
      FloorPoint point;
      if (denominator.abs() < 1e-9) {
        point = corner + n2;
      } else {
        final a1 = corner + n1;
        final a2 = corner + n2;
        point = a1 + d1.scale((a2 - a1).cross(d2) / denominator);
      }
      result.add(FloorPoint(roundTo(point.x, 3), roundTo(point.z, 3)));
    }
    return result;
  }

  int _weld(FloorPoint point) {
    for (var i = 0; i < _vertices.length; i++) {
      if (_vertices[i].distanceTo(point) <= weldTolerance + 1e-9) return i;
    }
    _vertices.add(point);
    return _vertices.length - 1;
  }

  /// Vertex chain from [a] to [b] including every canonical vertex that lies
  /// within [weldTolerance] of the segment interior.
  List<int> _splitEdge(int a, int b) {
    if (a == b) return [a];
    final start = _vertices[a];
    final segment = _vertices[b] - start;
    final length = segment.length;
    final inner = <({int index, double t})>[];
    for (var k = 0; k < _vertices.length; k++) {
      if (k == a || k == b) continue;
      final relative = _vertices[k] - start;
      final along = relative.dot(segment) / length;
      if (along <= 1e-6 || along >= length - 1e-6) continue;
      final offset = relative.cross(segment).abs() / length;
      if (offset <= weldTolerance + 1e-9) {
        inner.add((index: k, t: along));
      }
    }
    inner.sort((left, right) => left.t.compareTo(right.t));
    return [a, for (final point in inner) point.index, b];
  }

  int _wallFor(int a, int b, RoomHeight height) {
    final key = a < b ? '$a:$b' : '$b:$a';
    final existing = _wallByEndpoints[key];
    if (existing != null) {
      if (height.value > _walls[existing].height.value) {
        _walls[existing].height = height;
      }
      return existing;
    }
    _walls.add(_WallRecord('wall-${_walls.length + 1}', a, b, height));
    return _wallByEndpoints[key] = _walls.length - 1;
  }

  Map<String, Object?> _wallJson(_WallRecord wall) => {
    'id': wall.id,
    'start': _vertices[wall.start].toJson(),
    'end': _vertices[wall.end].toJson(),
    'height': roundTo(wall.height.value, 3),
    'thickness': roundTo(capture.wallThickness, 3),
    'heightSource': wall.height.source.wire,
  };

  List<Map<String, Object?>> _openings() {
    final skipped = {
      for (final connection in capture.connections)
        '${connection.roomB}\u0000${connection.openingB}',
    };
    final result = <Map<String, Object?>>[];
    var doors = 0;
    var windows = 0;
    for (var r = 0; r < capture.rooms.length; r++) {
      final room = capture.rooms[r];
      final interior = room.worldCorners();
      for (final opening in room.openings) {
        if (skipped.contains('${room.id}\u0000${opening.id}')) continue;
        if (opening.edgeIndex < 0 || opening.edgeIndex >= interior.length) {
          continue;
        }
        final start = interior[opening.edgeIndex];
        final edge =
            interior[(opening.edgeIndex + 1) % interior.length] - start;
        if (edge.length == 0) continue;
        final direction = _unit(edge);
        final center =
            start +
            edge.scale(opening.position) +
            FloorPoint(direction.z, -direction.x).scale(_halfThickness);

        _EdgePiece? best;
        var bestT = 0.0;
        var bestDistance = double.infinity;
        for (final piece in _edges[r][opening.edgeIndex]) {
          final wall = _walls[piece.wall];
          final wallStart = _vertices[wall.start];
          final wallVector = _vertices[wall.end] - wallStart;
          final t =
              ((center - wallStart).dot(wallVector) /
                      wallVector.dot(wallVector))
                  .clamp(0.0, 1.0);
          final distance = center.distanceTo(wallStart + wallVector.scale(t));
          if (distance < bestDistance) {
            best = piece;
            bestT = t;
            bestDistance = distance;
          }
        }
        if (best == null) continue;
        final wall = _walls[best.wall];
        final wallLength = _vertices[wall.start].distanceTo(
          _vertices[wall.end],
        );
        final position = roundTo(bestT, 6);
        final half = opening.width / 2 / wallLength;
        if (position - half < -1e-9 || position + half > 1 + 1e-9) {
          warnings.add(
            SceneWarning(
              SceneWarningCode.openingExceedsWall,
              'Una abertura de «${room.name}» se sale del tramo de pared '
              '${wall.id}. Revisá su posición y su ancho.',
            ),
          );
        }
        final isWindow = opening.type == OpeningType.window;
        result.add({
          'id': isWindow ? 'window-${++windows}' : 'door-${++doors}',
          'wallId': wall.id,
          'position': position,
          'width': roundTo(opening.width, 3),
          'height': roundTo(opening.height, 3),
          'type': opening.type.wire,
          if (isWindow) 'sillHeight': roundTo(opening.sillHeight, 3),
        });
      }
    }
    return result;
  }

  List<Map<String, Object?>> _objects() {
    final result = <Map<String, Object?>>[];
    for (final room in capture.rooms) {
      if (room.boxes.isNotEmpty && !room.placement.isAxisAligned) {
        warnings.add(
          SceneWarning(
            SceneWarningCode.boxRotationApproximated,
            'Los volúmenes de «${room.name}» se aproximaron con su caja '
            'alineada a los ejes porque el ambiente está girado. Revisá sus '
            'medidas.',
          ),
        );
      }
      for (final box in room.boxes) {
        final height = box.height;
        if (height == null) {
          warnings.add(
            SceneWarning(
              SceneWarningCode.boxMissingHeight,
              'Un volumen de «${room.name}» no tiene altura medida y no se '
              'incluyó en la escena. Ingresá su altura.',
            ),
          );
          continue;
        }
        final halfWidth = box.width / 2;
        final halfDepth = box.depth / 2;
        final footprint = [
          for (final (dx, dz) in [
            (-halfWidth, -halfDepth),
            (halfWidth, -halfDepth),
            (halfWidth, halfDepth),
            (-halfWidth, halfDepth),
          ])
            room.placement.apply(
              FloorPoint(box.centerX + dx, box.centerZ + dz),
            ),
        ];
        final xs = footprint.map((p) => p.x);
        final zs = footprint.map((p) => p.z);
        final minX = xs.reduce(math.min);
        final maxX = xs.reduce(math.max);
        final minZ = zs.reduce(math.min);
        final maxZ = zs.reduce(math.max);
        result.add({
          'id': 'box-${result.length + 1}',
          'type': 'occupancy',
          'position': {
            'x': roundTo((minX + maxX) / 2, 3),
            'y': 0.0,
            'z': roundTo((minZ + maxZ) / 2, 3),
          },
          'dimensions': {
            'width': roundTo(maxX - minX, 3),
            'height': roundTo(height, 3),
            'depth': roundTo(maxZ - minZ, 3),
          },
          'color': occupancyColor,
          'source': box.source.wire,
          if (box.confidence != null) 'confidence': box.confidence,
        });
      }
    }
    return result;
  }

  void _heightWarnings() {
    for (final room in capture.rooms) {
      if (room.height.source == HeightSource.assumed) {
        warnings.add(
          SceneWarning(
            SceneWarningCode.assumedHeight,
            'La altura de «${room.name}» es supuesta '
            '(${room.height.value.toStringAsFixed(2)} m), no medida. Ajustala '
            'si conocés el valor real.',
          ),
        );
      }
    }
  }

  void _duplicateWallWarnings() {
    final maxSin = math.sin(_duplicateWallAngleDegrees * math.pi / 180);
    for (var i = 0; i < _walls.length; i++) {
      final aStart = _vertices[_walls[i].start];
      final aVector = _vertices[_walls[i].end] - aStart;
      final aLength = aVector.length;
      final aDirection = aVector.scale(1 / aLength);
      for (var j = i + 1; j < _walls.length; j++) {
        final bStart = _vertices[_walls[j].start];
        final bEnd = _vertices[_walls[j].end];
        final bDirection = _unit(bEnd - bStart);
        if (aDirection.cross(bDirection).abs() > maxSin) continue;
        final t0 = (bStart - aStart).dot(aDirection);
        final t1 = (bEnd - aStart).dot(aDirection);
        final overlap =
            math.min(aLength, math.max(t0, t1)) -
            math.max(0.0, math.min(t0, t1));
        if (overlap <= _duplicateWallOverlap) continue;
        final distance =
            ((bStart - aStart).cross(aDirection).abs() +
                (bEnd - aStart).cross(aDirection).abs()) /
            2;
        if (distance >= _duplicateWallDistance) continue;
        warnings.add(
          SceneWarning(
            SceneWarningCode.possibleDuplicateWall,
            'Las paredes ${_walls[i].id} y ${_walls[j].id} son casi paralelas '
            'y están a menos de 30 cm: puede ser la misma pared capturada dos '
            'veces. Revisá la conexión de los ambientes.',
          ),
        );
      }
    }
  }

  void _overlapWarnings() {
    final rooms = capture.rooms;
    final polygons = [for (final room in rooms) room.worldCorners()];
    for (var i = 0; i < rooms.length; i++) {
      for (var j = i + 1; j < rooms.length; j++) {
        if (_polygonsOverlap(polygons[i], polygons[j])) {
          warnings.add(
            SceneWarning(
              SceneWarningCode.roomsOverlap,
              '«${rooms[i].name}» y «${rooms[j].name}» se superponen. Revisá '
              'cómo están ubicados.',
            ),
          );
        }
      }
    }
  }

  void _connectivityWarnings() {
    final rooms = capture.rooms;
    if (rooms.length < 2) return;
    final reached = {rooms.first.id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final connection in capture.connections) {
        final hasA = reached.contains(connection.roomA);
        final hasB = reached.contains(connection.roomB);
        if (hasA != hasB) {
          reached
            ..add(connection.roomA)
            ..add(connection.roomB);
          changed = true;
        }
      }
    }
    for (final room in rooms.skip(1)) {
      if (!reached.contains(room.id)) {
        warnings.add(
          SceneWarning(
            SceneWarningCode.roomNotConnected,
            '«${room.name}» no está conectado con el resto de los ambientes. '
            'Conectalo mediante una puerta.',
          ),
        );
      }
    }
  }
}

FloorPoint _unit(FloorPoint vector) {
  final length = vector.length;
  return length == 0 ? const FloorPoint(0, 0) : vector.scale(1 / length);
}

bool _polygonsOverlap(List<FloorPoint> a, List<FloorPoint> b) {
  if (a.length < 3 || b.length < 3) return false;
  for (var i = 0; i < a.length; i++) {
    for (var j = 0; j < b.length; j++) {
      if (segmentsCrossProperly(
        a[i],
        a[(i + 1) % a.length],
        b[j],
        b[(j + 1) % b.length],
      )) {
        return true;
      }
    }
  }
  FloorPoint centroid(List<FloorPoint> polygon) => polygon
      .fold(const FloorPoint(0, 0), (sum, point) => sum + point)
      .scale(1 / polygon.length);
  return a.any((point) => pointInPolygon(point, b)) ||
      b.any((point) => pointInPolygon(point, a)) ||
      pointInPolygon(centroid(a), b) ||
      pointInPolygon(centroid(b), a);
}
