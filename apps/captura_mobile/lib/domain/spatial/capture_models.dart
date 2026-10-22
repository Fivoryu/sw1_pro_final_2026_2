import 'dart:math' as math;

import 'geometry.dart';

/// Where a room height comes from. Only [ceilingPlane] and [wallPoint] are
/// observations; [assumed] is a placeholder that must never be shown as a
/// measurement.
enum HeightSource {
  ceilingPlane('ceiling_plane'),
  wallPoint('wall_point'),
  manual('manual'),
  assumed('assumed');

  const HeightSource(this.wire);

  final String wire;

  bool get isMeasured => this == ceilingPlane || this == wallPoint;

  static HeightSource fromWire(Object? wire) => values.firstWhere(
    (source) => source.wire == wire,
    orElse: () => throw FormatException('Unknown height source: $wire'),
  );
}

/// Floor-to-ceiling height of a room with its provenance.
class RoomHeight {
  const RoomHeight(this.value, this.source);

  factory RoomHeight.fromJson(Map<String, Object?> json) => RoomHeight(
    readDouble(json, 'value'),
    HeightSource.fromWire(json['source']),
  );

  /// Height used when nothing was measured; flagged as assumed.
  static const RoomHeight assumedDefault = RoomHeight(
    2.4,
    HeightSource.assumed,
  );

  final double value;
  final HeightSource source;

  bool get isMeasured => source.isMeasured;

  Map<String, Object?> toJson() => {'value': value, 'source': source.wire};

  @override
  bool operator ==(Object other) =>
      other is RoomHeight && other.value == value && other.source == source;

  @override
  int get hashCode => Object.hash(value, source);

  @override
  String toString() => 'RoomHeight($value, ${source.wire})';
}

enum OpeningType {
  door('door'),
  window('window');

  const OpeningType(this.wire);

  final String wire;

  static OpeningType fromWire(Object? wire) => values.firstWhere(
    (type) => type.wire == wire,
    orElse: () => throw FormatException('Unknown opening type: $wire'),
  );
}

/// A door or window on edge [edgeIndex] of a room contour (edge `i` goes from
/// corner `i` to corner `i + 1`). [position] (0..1) is the opening centre
/// along that edge, measured from its start corner.
class RoomOpening {
  const RoomOpening({
    required this.id,
    required this.edgeIndex,
    required this.position,
    required this.width,
    required this.height,
    required this.type,
    double? sillHeight,
  }) : _sillHeight = sillHeight;

  factory RoomOpening.fromJson(Map<String, Object?> json) => RoomOpening(
    id: json['id']! as String,
    edgeIndex: (json['edgeIndex']! as num).toInt(),
    position: readDouble(json, 'position'),
    width: readDouble(json, 'width'),
    height: readDouble(json, 'height'),
    type: OpeningType.fromWire(json['type']),
    sillHeight: readOptionalDouble(json, 'sillHeight'),
  );

  /// Default sill of a window, as in the scene contract.
  static const double defaultWindowSill = 0.9;

  final String id;
  final int edgeIndex;
  final double position;
  final double width;
  final double height;
  final OpeningType type;
  final double? _sillHeight;

  /// Sill height: 0 for doors, 0.9 m by default for windows.
  double get sillHeight =>
      _sillHeight ?? (type == OpeningType.window ? defaultWindowSill : 0);

  RoomOpening copyWith({
    int? edgeIndex,
    double? position,
    double? width,
    double? height,
    OpeningType? type,
    double? sillHeight,
  }) => RoomOpening(
    id: id,
    edgeIndex: edgeIndex ?? this.edgeIndex,
    position: position ?? this.position,
    width: width ?? this.width,
    height: height ?? this.height,
    type: type ?? this.type,
    sillHeight: sillHeight ?? _sillHeight,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'edgeIndex': edgeIndex,
    'position': position,
    'width': width,
    'height': height,
    'type': type.wire,
    'sillHeight': sillHeight,
  };
}

enum BoxSource {
  depth('depth'),
  manual('manual');

  const BoxSource(this.wire);

  final String wire;

  static BoxSource fromWire(Object? wire) => values.firstWhere(
    (source) => source.wire == wire,
    orElse: () => throw FormatException('Unknown box source: $wire'),
  );
}

/// An unlabelled occupancy volume, axis-aligned in the room-local frame.
///
/// It never carries a class, a price or an `extra_id`. A null [height] means
/// the height was not measured: the user must set it before the volume is
/// exported to the scene.
class OccupancyBox {
  const OccupancyBox({
    required this.id,
    required this.centerX,
    required this.centerZ,
    required this.width,
    required this.depth,
    required this.height,
    required this.source,
    this.confidence,
  });

  factory OccupancyBox.fromJson(Map<String, Object?> json) => OccupancyBox(
    id: json['id']! as String,
    centerX: readDouble(json, 'centerX'),
    centerZ: readDouble(json, 'centerZ'),
    width: readDouble(json, 'width'),
    depth: readDouble(json, 'depth'),
    height: readOptionalDouble(json, 'height'),
    source: BoxSource.fromWire(json['source']),
    confidence: readOptionalDouble(json, 'confidence'),
  );

  final String id;
  final double centerX;
  final double centerZ;

  /// Extent along the room-local x axis.
  final double width;

  /// Extent along the room-local z axis.
  final double depth;
  final double? height;
  final BoxSource source;
  final double? confidence;

  bool get needsHeight => height == null;

  /// A copy corrected by hand: the provenance becomes [BoxSource.manual] and
  /// the depth confidence no longer applies.
  OccupancyBox correctedManually({
    double? centerX,
    double? centerZ,
    double? width,
    double? depth,
    double? height,
  }) => OccupancyBox(
    id: id,
    centerX: centerX ?? this.centerX,
    centerZ: centerZ ?? this.centerZ,
    width: width ?? this.width,
    depth: depth ?? this.depth,
    height: height ?? this.height,
    source: BoxSource.manual,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'centerX': centerX,
    'centerZ': centerZ,
    'width': width,
    'depth': depth,
    'height': height,
    'source': source.wire,
    'confidence': confidence,
  };
}

/// Independent tape-measure length of one contour edge typed by the agent.
class ReferenceMeasurement {
  const ReferenceMeasurement({
    required this.edgeIndex,
    required this.referenceMeters,
  });

  factory ReferenceMeasurement.fromJson(Map<String, Object?> json) =>
      ReferenceMeasurement(
        edgeIndex: (json['edgeIndex']! as num).toInt(),
        referenceMeters: readDouble(json, 'referenceMeters'),
      );

  final int edgeIndex;
  final double referenceMeters;

  Map<String, Object?> toJson() => {
    'edgeIndex': edgeIndex,
    'referenceMeters': referenceMeters,
  };
}

/// Session metrics reported by the native capture.
class CaptureMetrics {
  const CaptureMetrics({
    required this.durationMs,
    required this.trackingLossCount,
    required this.depthSupported,
    required this.cornerHitDistances,
    required this.floorY,
  });

  factory CaptureMetrics.fromJson(Map<String, Object?> json) => CaptureMetrics(
    durationMs: (json['durationMs']! as num).toInt(),
    trackingLossCount: (json['trackingLossCount']! as num).toInt(),
    depthSupported: json['depthSupported']! as bool,
    cornerHitDistances: [
      for (final value in asJsonList(
        json['cornerHitDistances'],
        'cornerHitDistances',
      ))
        (value! as num).toDouble(),
    ],
    floorY: readDouble(json, 'floorY'),
  );

  final int durationMs;
  final int trackingLossCount;
  final bool depthSupported;
  final List<double> cornerHitDistances;
  final double floorY;

  Map<String, Object?> toJson() => {
    'durationMs': durationMs,
    'trackingLossCount': trackingLossCount,
    'depthSupported': depthSupported,
    'cornerHitDistances': cornerHitDistances,
    'floorY': floorY,
  };
}

/// Technology used to obtain a room's geometry.
///
/// Only the two ARCore methods are operational camera captures today. The
/// remaining values make provenance explicit without exposing unfinished UI.
enum RoomAcquisitionMethod {
  legacyArcore('legacy_arcore'),
  arcoreWalkthrough('arcore_walkthrough'),
  arcoreWalls('arcore_walls'),
  manual('manual'),
  floorplan('floorplan'),
  assistedCamera('assisted_camera');

  const RoomAcquisitionMethod(this.wire);

  final String wire;

  bool get usesArCore =>
      this == legacyArcore || this == arcoreWalkthrough || this == arcoreWalls;

  static RoomAcquisitionMethod fromWire(Object? wire) => values.firstWhere(
    (method) => method.wire == wire,
    orElse: () => throw FormatException('Unknown acquisition method: $wire'),
  );
}

/// Provenance of a room geometry and, only for ARCore captures, its native
/// session metrics. Manual geometry never fabricates AR tracking values.
class RoomAcquisition {
  const RoomAcquisition({required this.method, this.arMetrics})
    : assert(
        (method != RoomAcquisitionMethod.legacyArcore &&
                method != RoomAcquisitionMethod.arcoreWalkthrough &&
                method != RoomAcquisitionMethod.arcoreWalls) ||
            arMetrics != null,
        'ARCore acquisitions require capture metrics',
      ),
      assert(
        method == RoomAcquisitionMethod.legacyArcore ||
            method == RoomAcquisitionMethod.arcoreWalkthrough ||
            method == RoomAcquisitionMethod.arcoreWalls ||
            arMetrics == null,
        'Non-AR acquisitions cannot contain ARCore metrics',
      );

  factory RoomAcquisition.fromJson(Map<String, Object?> json) {
    final method = RoomAcquisitionMethod.fromWire(json['method']);
    final rawMetrics = json['arMetrics'];
    return RoomAcquisition(
      method: method,
      arMetrics: rawMetrics == null
          ? null
          : CaptureMetrics.fromJson(asJsonMap(rawMetrics, 'arMetrics')),
    );
  }

  final RoomAcquisitionMethod method;
  final CaptureMetrics? arMetrics;

  Map<String, Object?> toJson() => {
    'method': method.wire,
    if (arMetrics != null) 'arMetrics': arMetrics!.toJson(),
  };
}

/// Rigid transform of a room-local frame into the property frame:
/// `world = rotate(local, rotationDegrees) + (x, z)`, where a positive
/// rotation turns +x towards +z.
class RoomPlacement {
  const RoomPlacement({
    required this.x,
    required this.z,
    required this.rotationDegrees,
  });

  factory RoomPlacement.fromJson(Map<String, Object?> json) => RoomPlacement(
    x: readDouble(json, 'x'),
    z: readDouble(json, 'z'),
    rotationDegrees: readDouble(json, 'rotationDegrees'),
  );

  static const RoomPlacement identity = RoomPlacement(
    x: 0,
    z: 0,
    rotationDegrees: 0,
  );

  final double x;
  final double z;
  final double rotationDegrees;

  double get rotationRadians => rotationDegrees * math.pi / 180;

  /// Whether the rotation keeps local axes aligned with the property axes.
  bool get isAxisAligned {
    final remainder = rotationDegrees % 90;
    return remainder < 1e-6 || 90 - remainder < 1e-6;
  }

  FloorPoint apply(FloorPoint local) =>
      local.rotate(rotationRadians) + FloorPoint(x, z);

  Map<String, Object?> toJson() => {
    'x': x,
    'z': z,
    'rotationDegrees': rotationDegrees,
  };

  @override
  bool operator ==(Object other) =>
      other is RoomPlacement &&
      other.x == x &&
      other.z == z &&
      other.rotationDegrees == rotationDegrees;

  @override
  int get hashCode => Object.hash(x, z, rotationDegrees);

  @override
  String toString() => 'RoomPlacement($x, $z, $rotationDegrees°)';
}

/// One room geometry in its room-local frame. Its acquisition technology is
/// recorded separately in [acquisition]. The first corner is the origin, the
/// first edge lies on +x and corners run counter-clockwise (see [FloorPoint]
/// for the orientation convention). Corners trace the interior wall faces.
class CapturedRoom {
  const CapturedRoom({
    required this.id,
    required this.name,
    required this.corners,
    required this.height,
    required this.openings,
    required this.boxes,
    required this.references,
    required this.acquisition,
    this.placement = RoomPlacement.identity,
  });

  /// Normalizes a `captureRoom` channel result (`outcome: captured`) given in
  /// ARCore world metres. Throws a [FormatException] for any other outcome or
  /// a malformed payload.
  factory CapturedRoom.fromChannelResult({
    required String id,
    required String name,
    required Map<Object?, Object?> result,
  }) {
    final json = result.cast<String, Object?>();
    if (json['outcome'] != 'captured') {
      throw FormatException('Not a captured room: ${json['outcome']}');
    }
    final raw = [
      for (final corner in asJsonList(json['corners'], 'corners'))
        FloorPoint.fromJson(asJsonMap(corner, 'corners[]')),
    ];
    final ordered = signedArea(raw) < 0 && raw.length > 2
        ? [raw.first, ...raw.skip(1).toList().reversed]
        : raw;

    final origin = ordered.isEmpty ? const FloorPoint(0, 0) : ordered.first;
    final firstEdge = ordered.length > 1
        ? ordered[1] - origin
        : const FloorPoint(1, 0);
    final angle = firstEdge.length == 0
        ? 0.0
        : -math.atan2(firstEdge.z, firstEdge.x);
    FloorPoint toLocal(FloorPoint world) {
      final local = (world - origin).rotate(angle);
      return FloorPoint(roundTo(local.x, 6), roundTo(local.z, 6));
    }

    final rawHeight = json['height'];
    final height = rawHeight == null
        ? RoomHeight.assumedDefault
        : RoomHeight.fromJson(asJsonMap(rawHeight, 'height'));

    final rawBoxes = json['boxes'] == null
        ? const <Object?>[]
        : asJsonList(json['boxes'], 'boxes');
    final boxes = <OccupancyBox>[];
    for (var i = 0; i < rawBoxes.length; i++) {
      final box = asJsonMap(rawBoxes[i], 'boxes[$i]');
      final diagonal = [
        for (final corner in asJsonList(box['corners'], 'boxes[$i].corners'))
          toLocal(
            FloorPoint.fromJson(asJsonMap(corner, 'boxes[$i].corners[]')),
          ),
      ];
      if (diagonal.length != 2) {
        throw FormatException('boxes[$i] needs two diagonal corners');
      }
      final boxHeight = readOptionalDouble(box, 'height');
      final measuredByDepth =
          boxHeight != null && box['heightSource'] == 'depth';
      final minX = math.min(diagonal[0].x, diagonal[1].x);
      final maxX = math.max(diagonal[0].x, diagonal[1].x);
      final minZ = math.min(diagonal[0].z, diagonal[1].z);
      final maxZ = math.max(diagonal[0].z, diagonal[1].z);
      boxes.add(
        OccupancyBox(
          id: 'box-${i + 1}',
          centerX: roundTo((minX + maxX) / 2, 6),
          centerZ: roundTo((minZ + maxZ) / 2, 6),
          width: roundTo(maxX - minX, 6),
          depth: roundTo(maxZ - minZ, 6),
          height: boxHeight,
          source: measuredByDepth ? BoxSource.depth : BoxSource.manual,
          confidence: measuredByDepth
              ? readOptionalDouble(box, 'confidence')
              : null,
        ),
      );
    }

    return CapturedRoom(
      id: id,
      name: name,
      corners: [for (final corner in ordered) toLocal(corner)],
      height: height,
      openings: const [],
      boxes: boxes,
      references: const [],
      acquisition: RoomAcquisition(
        method:
            json['metrics'] is Map &&
                (json['metrics']! as Map)['method'] == 'walkthrough'
            ? RoomAcquisitionMethod.arcoreWalkthrough
            : RoomAcquisitionMethod.arcoreWalls,
        arMetrics: CaptureMetrics.fromJson(
          asJsonMap(json['metrics'], 'metrics'),
        ),
      ),
    );
  }

  factory CapturedRoom.fromJson(Map<String, Object?> json) => CapturedRoom(
    id: json['id']! as String,
    name: json['name']! as String,
    corners: [
      for (final corner in asJsonList(json['corners'], 'corners'))
        FloorPoint.fromJson(asJsonMap(corner, 'corners[]')),
    ],
    height: RoomHeight.fromJson(asJsonMap(json['height'], 'height')),
    openings: [
      for (final opening in asJsonList(json['openings'], 'openings'))
        RoomOpening.fromJson(asJsonMap(opening, 'openings[]')),
    ],
    boxes: [
      for (final box in asJsonList(json['boxes'], 'boxes'))
        OccupancyBox.fromJson(asJsonMap(box, 'boxes[]')),
    ],
    references: [
      for (final reference in asJsonList(json['references'], 'references'))
        ReferenceMeasurement.fromJson(asJsonMap(reference, 'references[]')),
    ],
    acquisition: json['acquisition'] == null
        // Drafts written before adaptive capture were exclusively ARCore
        // rooms. Their exact native mode was not persisted, so provenance
        // remains explicitly unknown within ARCore and is never manual.
        ? RoomAcquisition(
            method: RoomAcquisitionMethod.legacyArcore,
            arMetrics: CaptureMetrics.fromJson(
              asJsonMap(json['metrics'], 'metrics'),
            ),
          )
        : RoomAcquisition.fromJson(
            asJsonMap(json['acquisition'], 'acquisition'),
          ),
    placement: RoomPlacement.fromJson(
      asJsonMap(json['placement'], 'placement'),
    ),
  );

  final String id;
  final String name;
  final List<FloorPoint> corners;
  final RoomHeight height;
  final List<RoomOpening> openings;
  final List<OccupancyBox> boxes;
  final List<ReferenceMeasurement> references;
  final RoomAcquisition acquisition;

  /// Native metrics for an ARCore room, absent for technology-neutral rooms.
  CaptureMetrics? get metrics => acquisition.arMetrics;
  final RoomPlacement placement;

  /// Corners in the property frame after applying [placement].
  List<FloorPoint> worldCorners() => [
    for (final corner in corners) placement.apply(corner),
  ];

  CapturedRoom copyWith({
    String? name,
    List<FloorPoint>? corners,
    RoomHeight? height,
    List<RoomOpening>? openings,
    List<OccupancyBox>? boxes,
    List<ReferenceMeasurement>? references,
    RoomAcquisition? acquisition,
    RoomPlacement? placement,
  }) => CapturedRoom(
    id: id,
    name: name ?? this.name,
    corners: corners ?? this.corners,
    height: height ?? this.height,
    openings: openings ?? this.openings,
    boxes: boxes ?? this.boxes,
    references: references ?? this.references,
    acquisition: acquisition ?? this.acquisition,
    placement: placement ?? this.placement,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'corners': [for (final corner in corners) corner.toJson()],
    'height': height.toJson(),
    'openings': [for (final opening in openings) opening.toJson()],
    'boxes': [for (final box in boxes) box.toJson()],
    'references': [for (final reference in references) reference.toJson()],
    'acquisition': acquisition.toJson(),
    'placement': placement.toJson(),
  };
}

/// A door of [roomA] joined to a door of [roomB]; both become one opening.
class DoorConnection {
  const DoorConnection({
    required this.roomA,
    required this.openingA,
    required this.roomB,
    required this.openingB,
  });

  factory DoorConnection.fromJson(Map<String, Object?> json) => DoorConnection(
    roomA: json['roomA']! as String,
    openingA: json['openingA']! as String,
    roomB: json['roomB']! as String,
    openingB: json['openingB']! as String,
  );

  final String roomA;
  final String openingA;
  final String roomB;
  final String openingB;

  Map<String, Object?> toJson() => {
    'roomA': roomA,
    'openingA': openingA,
    'roomB': roomB,
    'openingB': openingB,
  };
}

/// Local spatial capture of a listing: rooms, how they connect and the wall
/// thickness used to build the scene. Persisted on the device as JSON.
class PropertyCapture {
  const PropertyCapture({
    required this.listingId,
    required this.rooms,
    required this.connections,
    required this.updatedAt,
    this.wallThickness = defaultWallThickness,
  });

  factory PropertyCapture.fromJson(Map<String, Object?> json) =>
      PropertyCapture(
        listingId: json['listingId']! as String,
        rooms: [
          for (final room in asJsonList(json['rooms'], 'rooms'))
            CapturedRoom.fromJson(asJsonMap(room, 'rooms[]')),
        ],
        connections: [
          for (final connection in asJsonList(
            json['connections'],
            'connections',
          ))
            DoorConnection.fromJson(asJsonMap(connection, 'connections[]')),
        ],
        wallThickness: readDouble(json, 'wallThickness'),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
      );

  static const double defaultWallThickness = 0.15;

  final String listingId;
  final List<CapturedRoom> rooms;
  final List<DoorConnection> connections;
  final double wallThickness;
  final DateTime updatedAt;

  PropertyCapture copyWith({
    List<CapturedRoom>? rooms,
    List<DoorConnection>? connections,
    double? wallThickness,
    DateTime? updatedAt,
  }) => PropertyCapture(
    listingId: listingId,
    rooms: rooms ?? this.rooms,
    connections: connections ?? this.connections,
    wallThickness: wallThickness ?? this.wallThickness,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'listingId': listingId,
    'rooms': [for (final room in rooms) room.toJson()],
    'connections': [for (final connection in connections) connection.toJson()],
    'wallThickness': wallThickness,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}
