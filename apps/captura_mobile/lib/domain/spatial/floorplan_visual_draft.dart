import 'dart:math' as math;

import 'geometry.dart';

/// Versioned, acquisition-only plan editor document. It deliberately does not
/// feed [CapturedRoom] or Scene v2 until a later explicit confirmation flow.
class FloorplanVisualDraft {
  const FloorplanVisualDraft({
    this.version = currentVersion,
    this.walls = const [],
    this.rooms = const [],
    this.openings = const [],
    this.measurements = const [],
  });

  /// Highest document version this build can interpret. A document written by
  /// a newer build must never be rebuilt or overwritten silently.
  static const int currentVersion = 3;

  factory FloorplanVisualDraft.fromJson(Map<String, Object?> json) {
    final version = (json['version'] as num?)?.toInt() ?? 1;
    return FloorplanVisualDraft(
      version: version,
      walls: [
        for (final wall in json['walls'] as List? ?? const [])
          VisualWallSegment.fromJson((wall as Map).cast<String, Object?>()),
      ],
      rooms: [
        for (final room in json['rooms'] as List? ?? const [])
          VisualRoomRegion.fromJson((room as Map).cast<String, Object?>()),
      ],
      openings: [
        for (final opening in json['openings'] as List? ?? const [])
          VisualOpeningDraft.fromJson(
            (opening as Map).cast<String, Object?>(),
            legacyDocument: version < 3,
          ),
      ],
      measurements: [
        for (final measurement in json['measurements'] as List? ?? const [])
          VisualWallMeasurementEvidence.fromJson(
            (measurement as Map).cast<String, Object?>(),
          ),
      ],
    );
  }

  final int version;
  final List<VisualWallSegment> walls;
  final List<VisualRoomRegion> rooms;
  final List<VisualOpeningDraft> openings;
  final List<VisualWallMeasurementEvidence> measurements;

  Map<String, Object?> toJson() => {
    'version': version,
    'walls': [for (final wall in walls) wall.toJson()],
    'rooms': [for (final room in rooms) room.toJson()],
    'openings': [for (final opening in openings) opening.toJson()],
    'measurements': [
      for (final measurement in measurements) measurement.toJson(),
    ],
  };

  FloorplanVisualDraft copyWith({
    List<VisualWallSegment>? walls,
    List<VisualRoomRegion>? rooms,
    List<VisualOpeningDraft>? openings,
    List<VisualWallMeasurementEvidence>? measurements,
  }) => FloorplanVisualDraft(
    version: version,
    walls: walls ?? this.walls,
    rooms: rooms ?? this.rooms,
    openings: openings ?? this.openings,
    measurements: measurements ?? this.measurements,
  );

  /// Returns human-readable integrity errors. The document is intentionally
  /// independent from the canonical capture model, but it must still be a
  /// coherent editable plan before it can be saved as trace metadata.
  List<String> validate() {
    final errors = <String>[];
    final wallById = <String, VisualWallSegment>{};
    final roomById = <String, VisualRoomRegion>{};
    final openingIds = <String>{};
    final measurementIds = <String>{};

    if (version < 1 || version > currentVersion) {
      errors.add('version_unsupported');
    }

    for (final wall in walls) {
      if (wall.id.trim().isEmpty || wallById.containsKey(wall.id)) {
        errors.add('wall_id_invalid');
      } else {
        wallById[wall.id] = wall;
      }
      if (!wall.isUsable) errors.add('wall_geometry_invalid');
      if (!wall.start.x.isFinite ||
          !wall.start.z.isFinite ||
          !wall.end.x.isFinite ||
          !wall.end.z.isFinite) {
        errors.add('wall_coordinate_invalid');
      }
      if (!_isNormalizedPoint(wall.start) || !_isNormalizedPoint(wall.end)) {
        errors.add('wall_coordinate_out_of_range');
      }
      if (wall.roomIds.length > 2 ||
          wall.roomIds.toSet().length != wall.roomIds.length) {
        errors.add('wall_room_relation_invalid');
      }
    }
    for (var firstIndex = 0; firstIndex < walls.length; firstIndex++) {
      for (
        var secondIndex = firstIndex + 1;
        secondIndex < walls.length;
        secondIndex++
      ) {
        final first = walls[firstIndex];
        final second = walls[secondIndex];
        if (_samePhysicalWall(first, second)) {
          errors.add('wall_duplicate');
        } else if (_wallsCrossWithoutTopology(first, second)) {
          errors.add('wall_intersection_without_vertex');
        }
      }
    }
    for (final room in rooms) {
      if (room.id.trim().isEmpty || roomById.containsKey(room.id)) {
        errors.add('room_id_invalid');
      } else {
        roomById[room.id] = room;
      }
      if (room.wallIds.length < 3 ||
          room.wallIds.toSet().length != room.wallIds.length) {
        errors.add('room_wall_list_invalid');
        continue;
      }
      final ordered = <VisualWallSegment>[];
      for (final id in room.wallIds) {
        final wall = wallById[id];
        if (wall == null) {
          errors.add('room_wall_missing');
        } else {
          ordered.add(wall);
          if (!wall.roomIds.contains(room.id)) {
            errors.add('room_wall_relation_invalid');
          }
        }
      }
      final oriented = ordered.length == room.wallIds.length
          ? _orientRoomWalls(ordered)
          : null;
      if (oriented == null || !_isClosedSimplePerimeter(oriented)) {
        errors.add('room_perimeter_invalid');
      }
    }
    for (final wall in walls) {
      for (final roomId in wall.roomIds) {
        final room = roomById[roomId];
        if (room == null || !room.wallIds.contains(wall.id)) {
          errors.add('wall_room_relation_invalid');
        }
      }
    }
    for (final opening in openings) {
      if (opening.id.trim().isEmpty || !openingIds.add(opening.id)) {
        errors.add('opening_id_invalid');
      }
      final wallId = opening.wallId;
      if (wallId != null && !wallById.containsKey(wallId)) {
        errors.add('opening_wall_missing');
      }
      if (!_normalizedOrNull(opening.position) ||
          !_normalizedOrNull(opening.normalizedWidth)) {
        errors.add('opening_geometry_invalid');
      }
      final position = opening.position;
      final width = opening.normalizedWidth;
      if ((width != null && (width <= 0 || width > 1)) ||
          (position != null &&
              width != null &&
              (position - width / 2 < 0 || position + width / 2 > 1))) {
        errors.add('opening_interval_invalid');
      }
      final widthM = opening.widthM;
      final heightM = opening.heightM;
      final offsetM = opening.offsetFromWallStartM;
      final sillM = opening.sillHeightM;
      if ((widthM != null && (!widthM.isFinite || widthM <= 0)) ||
          (heightM != null && (!heightM.isFinite || heightM <= 0)) ||
          (offsetM != null && (!offsetM.isFinite || offsetM < 0)) ||
          (sillM != null && (!sillM.isFinite || sillM < 0))) {
        errors.add('opening_physical_dimension_invalid');
      }
      if (wallId != null) {
        final length = authoritativeWallLength(wallId)?.meters;
        final height = authoritativeWallHeight(wallId)?.meters;
        if (length != null &&
            widthM != null &&
            offsetM != null &&
            offsetM + widthM > length + 1e-9) {
          errors.add('opening_exceeds_wall_length');
        }
        final verticalStart = opening.type == VisualOpeningType.door
            ? 0.0
            : sillM ?? 0.0;
        if (height != null &&
            heightM != null &&
            verticalStart + heightM > height + 1e-9) {
          errors.add('opening_exceeds_wall_height');
        }
      }
    }
    for (var firstIndex = 0; firstIndex < openings.length; firstIndex++) {
      final first = openings[firstIndex];
      if (first.wallId == null) continue;
      for (
        var secondIndex = firstIndex + 1;
        secondIndex < openings.length;
        secondIndex++
      ) {
        final second = openings[secondIndex];
        if (second.wallId != first.wallId) continue;
        final firstPosition = first.position;
        final firstWidth = first.normalizedWidth;
        final secondPosition = second.position;
        final secondWidth = second.normalizedWidth;
        if (firstPosition != null &&
            firstWidth != null &&
            secondPosition != null &&
            secondWidth != null &&
            _intervalsOverlap(
              firstPosition - firstWidth / 2,
              firstPosition + firstWidth / 2,
              secondPosition - secondWidth / 2,
              secondPosition + secondWidth / 2,
            )) {
          errors.add('opening_overlap');
          continue;
        }
        final firstOffset = first.offsetFromWallStartM;
        final firstWidthM = first.widthM;
        final secondOffset = second.offsetFromWallStartM;
        final secondWidthM = second.widthM;
        if (firstOffset != null &&
            firstWidthM != null &&
            secondOffset != null &&
            secondWidthM != null &&
            _intervalsOverlap(
              firstOffset,
              firstOffset + firstWidthM,
              secondOffset,
              secondOffset + secondWidthM,
            )) {
          errors.add('opening_overlap');
        }
      }
    }
    final authoritativeDimensions = <String>{};
    for (final measurement in measurements) {
      if (measurement.id.trim().isEmpty ||
          !measurementIds.add(measurement.id)) {
        errors.add('measurement_id_invalid');
      }
      if (measurement.wallId != null &&
          !wallById.containsKey(measurement.wallId)) {
        errors.add('measurement_wall_missing');
      }
      if (!measurement.meters.isFinite || measurement.meters <= 0) {
        errors.add('measurement_invalid');
      }
      if (measurement.isAuthoritative && measurement.wallId != null) {
        final key = '${measurement.wallId}:${measurement.dimension.name}';
        if (!authoritativeDimensions.add(key)) {
          errors.add('measurement_authoritative_conflict');
        }
      }
      final intervalStart = measurement.intervalStart;
      final intervalEnd = measurement.intervalEnd;
      if ((intervalStart == null) != (intervalEnd == null) ||
          !_normalizedOrNull(intervalStart) ||
          !_normalizedOrNull(intervalEnd) ||
          (intervalStart != null &&
              intervalEnd != null &&
              intervalStart >= intervalEnd)) {
        errors.add('measurement_interval_invalid');
      }
    }
    return errors;
  }

  VisualRoomRegion? room(String roomId) {
    for (final candidate in rooms) {
      if (candidate.id == roomId) return candidate;
    }
    return null;
  }

  List<FloorPoint>? contourForRoom(String roomId) {
    final room = this.room(roomId);
    if (room == null) return null;
    final byId = {for (final wall in walls) wall.id: wall};
    final ordered = [for (final id in room.wallIds) byId[id]];
    if (ordered.any((wall) => wall == null)) return null;
    final oriented = _orientRoomWalls(ordered.cast<VisualWallSegment>());
    if (oriented == null) return null;
    return [for (final wall in oriented) wall.start];
  }

  /// Stable wall identifiers in room traversal order. Edge indexes required by
  /// the existing solver and by compatibility projections are derived from this
  /// list; they are never stored in the document.
  List<String> wallIdsForRoom(String roomId) =>
      room(roomId)?.wallIds ?? const [];

  int? edgeIndexForWall(String roomId, String wallId) {
    final index = wallIdsForRoom(roomId).indexOf(wallId);
    return index < 0 ? null : index;
  }

  bool hasOpeningForWall(String wallId) =>
      openings.any((opening) => opening.wallId == wallId);

  bool hasMeasurementForWall(String wallId) =>
      measurements.any((measurement) => measurement.wallId == wallId);

  /// Walls with persisted evidence may not be merged or reinforced until the
  /// evidence is remapped on purpose. Splitting remaps openings per segment and
  /// still rejects any wall that owns confirmed measurements.
  bool hasProtectedEvidence(String wallId) =>
      hasOpeningForWall(wallId) || hasMeasurementForWall(wallId);

  VisualOpeningDraft? opening(String openingId) {
    for (final candidate in openings) {
      if (candidate.id == openingId) return candidate;
    }
    return null;
  }

  VisualWallMeasurementEvidence? measurement(String measurementId) {
    for (final candidate in measurements) {
      if (candidate.id == measurementId) return candidate;
    }
    return null;
  }

  /// Evidence that may establish authoritative scale: it is associated with a
  /// wall and it is not waiting for explicit user review. Pending provider
  /// detections stay persisted in [measurements] but never resolve geometry on
  /// their own.
  List<VisualWallMeasurementEvidence> get authoritativeMeasurements => [
    for (final measurement in measurements)
      if (measurement.isAuthoritative) measurement,
  ];

  List<VisualWallMeasurementEvidence> get authoritativeLengthMeasurements => [
    for (final measurement in authoritativeMeasurements)
      if (measurement.dimension == VisualWallMeasurementDimension.length)
        measurement,
  ];

  List<VisualWallMeasurementEvidence> get authoritativeHeightMeasurements => [
    for (final measurement in authoritativeMeasurements)
      if (measurement.dimension == VisualWallMeasurementDimension.height)
        measurement,
  ];

  VisualWallMeasurementEvidence? wallLength(String wallId) => measurements
      .where(
        (value) =>
            value.wallId == wallId &&
            value.dimension == VisualWallMeasurementDimension.length,
      )
      .firstOrNull;

  VisualWallMeasurementEvidence? wallHeight(String wallId) => measurements
      .where(
        (value) =>
            value.wallId == wallId &&
            value.dimension == VisualWallMeasurementDimension.height,
      )
      .firstOrNull;

  /// Accepted physical length for canonical projection and geometry. The
  /// observed accessors above deliberately keep pending evidence visible to
  /// the editor, while these accessors exclude pending, derived and unresolved
  /// records from physical output.
  VisualWallMeasurementEvidence? authoritativeWallLength(String wallId) =>
      authoritativeLengthMeasurements
          .where((value) => value.wallId == wallId)
          .firstOrNull;

  VisualWallMeasurementEvidence? authoritativeWallHeight(String wallId) =>
      authoritativeHeightMeasurements
          .where((value) => value.wallId == wallId)
          .firstOrNull;

  /// Evidence that cannot be resolved to a wall of this document because it
  /// has no association or because the referenced wall does not exist. It is
  /// kept verbatim so the user can recover it instead of losing it.
  List<VisualWallMeasurementEvidence> get unassignedMeasurements {
    final known = {for (final wall in walls) wall.id};
    return [
      for (final measurement in measurements)
        if (measurement.wallId == null || !known.contains(measurement.wallId))
          measurement,
    ];
  }

  /// Re-associates persisted evidence without touching its identity, value,
  /// provenance, review status or extra metadata. Returns null when the target
  /// wall does not belong to [roomId] or when that wall already holds another
  /// measurement of the same dimension, so a rejected recovery never mutates
  /// the document.
  FloorplanVisualDraft? associateMeasurement({
    required String roomId,
    required String wallId,
    required String measurementId,
  }) {
    final targetRoom = room(roomId);
    final evidence = measurement(measurementId);
    if (targetRoom == null || evidence == null) return null;
    if (!targetRoom.wallIds.contains(wallId)) return null;
    if (!walls.any((wall) => wall.id == wallId)) return null;
    if (measurements.any(
      (current) =>
          current.id != measurementId &&
          current.wallId == wallId &&
          current.dimension == evidence.dimension,
    )) {
      return null;
    }
    return withMeasurement(evidence.copyWith(wallId: wallId));
  }

  /// Insert-or-replace by stable ID: saving the same document twice never
  /// duplicates its evidence.
  FloorplanVisualDraft withOpening(VisualOpeningDraft opening) {
    final next = <VisualOpeningDraft>[];
    var replaced = false;
    for (final current in openings) {
      if (current.id == opening.id) {
        next.add(opening);
        replaced = true;
      } else {
        next.add(current);
      }
    }
    return copyWith(openings: replaced ? next : [...openings, opening]);
  }

  FloorplanVisualDraft withoutOpening(String openingId) => copyWith(
    openings: [
      for (final opening in openings)
        if (opening.id != openingId) opening,
    ],
  );

  FloorplanVisualDraft withMeasurement(
    VisualWallMeasurementEvidence measurement,
  ) {
    final next = <VisualWallMeasurementEvidence>[];
    var replaced = false;
    for (final current in measurements) {
      if (current.id == measurement.id) {
        next.add(measurement);
        replaced = true;
      } else {
        next.add(current);
      }
    }
    return copyWith(
      measurements: replaced ? next : [...measurements, measurement],
    );
  }

  FloorplanVisualDraft withoutMeasurement(String measurementId) => copyWith(
    measurements: [
      for (final measurement in measurements)
        if (measurement.id != measurementId) measurement,
    ],
  );

  /// Structural equality used by undo/redo. Presentation state is deliberately
  /// excluded, while IDs, associations and provenance are all compared.
  bool hasSameContentAs(FloorplanVisualDraft other) {
    if (version != other.version) return false;
    if (!_sameList(
      walls,
      other.walls,
      (a, b) =>
          a.id == b.id &&
          a.start == b.start &&
          a.end == b.end &&
          _sameList(a.roomIds, b.roomIds, (x, y) => x == y) &&
          a.manuallyEdited == b.manuallyEdited,
    )) {
      return false;
    }
    if (!_sameList(
      rooms,
      other.rooms,
      (a, b) =>
          a.id == b.id &&
          a.name == b.name &&
          _sameList(a.wallIds, b.wallIds, (x, y) => x == y),
    )) {
      return false;
    }
    if (!_sameList(
      openings,
      other.openings,
      (a, b) =>
          a.id == b.id &&
          a.type == b.type &&
          a.wallId == b.wallId &&
          a.position == b.position &&
          a.normalizedWidth == b.normalizedWidth &&
          a.manuallyPlaced == b.manuallyPlaced &&
          a.confidence == b.confidence &&
          a.widthM == b.widthM &&
          a.heightM == b.heightM &&
          a.offsetFromWallStartM == b.offsetFromWallStartM &&
          a.sillHeightM == b.sillHeightM,
    )) {
      return false;
    }
    return _sameList(
      measurements,
      other.measurements,
      (a, b) =>
          a.id == b.id &&
          a.wallId == b.wallId &&
          a.meters == b.meters &&
          a.intervalStart == b.intervalStart &&
          a.intervalEnd == b.intervalEnd &&
          a.provenance == b.provenance &&
          a.requiresReview == b.requiresReview &&
          a.lineageId == b.lineageId,
    );
  }

  /// A newly created trace has no canonical capture id yet. Rekey the primary
  /// region atomically at persistence time; additional detected regions and
  /// all physical wall/opening IDs remain stable.
  FloorplanVisualDraft rekeySingleRoom(String roomId) {
    if (rooms.isEmpty || rooms.any((room) => room.id == roomId)) return this;
    final previousId = rooms.first.id;
    return copyWith(
      rooms: [
        for (final room in rooms)
          room.id == previousId
              ? VisualRoomRegion(
                  id: roomId,
                  name: room.name,
                  wallIds: room.wallIds,
                )
              : room,
      ],
      walls: [
        for (final wall in walls)
          VisualWallSegment(
            id: wall.id,
            start: wall.start,
            end: wall.end,
            roomIds: [
              for (final current in wall.roomIds)
                current == previousId ? roomId : current,
            ],
            manuallyEdited: wall.manuallyEdited,
          ),
      ],
      measurements: measurements,
    );
  }
}

/// Stable endpoint selector used by the editor. It is deliberately not an
/// index in a contour: wall IDs remain valid when other walls are reordered.
enum VisualWallEndpoint { start, end }

class VisualDraftEditResult {
  const VisualDraftEditResult._({this.draft, this.errorCode});

  const VisualDraftEditResult.success(FloorplanVisualDraft draft)
    : this._(draft: draft);

  const VisualDraftEditResult.failure(String errorCode)
    : this._(errorCode: errorCode);

  final FloorplanVisualDraft? draft;
  final String? errorCode;

  bool get isSuccess => draft != null;
}

/// Transactional geometry operations for the acquisition-only visual draft.
///
/// A split retains the original wall ID for the segment from its old start to
/// the split point and creates a deterministic child ID for the second
/// segment. Openings are remapped onto the resulting segment that contains
/// their full interval; a cut that intersects an opening is rejected. Confirmed
/// measurements are never remapped, so any wall owning them refuses the
/// operation. A merge retains the wall that comes first in room traversal and
/// retires the following ID.
class FloorplanVisualDraftEditor {
  const FloorplanVisualDraftEditor._();

  static const _epsilon = 1e-6;
  static const _minimumSegmentLength = 1e-4;

  /// Rebuilds room-face ownership without changing physical wall orientation
  /// or opening-relative geometry. This is an idempotent topology boundary
  /// used when the wall graph itself has not been structurally edited.
  static VisualDraftEditResult reconcileRoomRegions({
    required FloorplanVisualDraft draft,
  }) {
    final reconciled = _reconcileRoomRegions(draft, draft.rooms);
    return reconciled == null
        ? const VisualDraftEditResult.failure('topologia_invalida')
        : _commit(reconciled);
  }

  static VisualDraftEditResult moveVertex({
    required FloorplanVisualDraft draft,
    required String roomId,
    required String wallId,
    required VisualWallEndpoint endpoint,
    required FloorPoint point,
    bool validateGeometry = true,
  }) {
    final room = draft.room(roomId);
    final wall = _wall(draft, wallId);
    if (room == null || wall == null || !room.wallIds.contains(wallId)) {
      return const VisualDraftEditResult.failure('pared_no_encontrada');
    }
    if (!_isNormalized(point)) {
      return const VisualDraftEditResult.failure('coordenada_invalida');
    }
    final original = endpoint == VisualWallEndpoint.start
        ? wall.start
        : wall.end;
    final walls = [
      for (final candidate in draft.walls)
        _replaceMatchingEndpoint(candidate, original, point),
    ];
    final candidate = draft.copyWith(walls: walls);
    return validateGeometry
        ? _commit(candidate)
        : VisualDraftEditResult.success(candidate);
  }

  /// Moves one already-resolved logical junction. The incident wall set is
  /// captured by the gesture at pointer-down and is never rediscovered from
  /// the moving coordinate, so unrelated endpoints cannot be reconnected by
  /// proximity while the preview is changing.
  static VisualDraftEditResult moveJunction({
    required FloorplanVisualDraft draft,
    required FloorPoint originalPoint,
    required Set<String> incidentWallIds,
    required FloorPoint point,
    bool validateGeometry = true,
  }) {
    if (!_isNormalized(point) || incidentWallIds.isEmpty) {
      return const VisualDraftEditResult.failure('coordenada_invalida');
    }
    final actualIncident = {
      for (final wall in draft.walls)
        if (wall.start.distanceTo(originalPoint) <= _epsilon ||
            wall.end.distanceTo(originalPoint) <= _epsilon)
          wall.id,
    };
    if (actualIncident.length != incidentWallIds.length ||
        !actualIncident.containsAll(incidentWallIds)) {
      return const VisualDraftEditResult.failure('vertice_desactualizado');
    }
    final walls = [
      for (final wall in draft.walls)
        incidentWallIds.contains(wall.id)
            ? _replaceMatchingEndpoint(wall, originalPoint, point)
            : wall,
    ];
    final candidate = draft.copyWith(walls: walls);
    return validateGeometry
        ? reconcileRoomRegions(draft: candidate)
        : VisualDraftEditResult.success(candidate);
  }

  /// Replaces one perimeter segment with a user-drawn path while retaining
  /// the original wall identity for the first resulting segment. This keeps
  /// the room closed and allows arbitrary horizontal, vertical or diagonal
  /// corrections without creating floating walls.
  static VisualDraftEditResult addWallPath({
    required FloorplanVisualDraft draft,
    required String roomId,
    required String wallId,
    required FloorPoint start,
    required FloorPoint end,
  }) {
    final room = draft.room(roomId);
    final wall = _wall(draft, wallId);
    if (room == null || wall == null || !room.wallIds.contains(wallId)) {
      return const VisualDraftEditResult.failure('pared_no_encontrada');
    }
    if (!_isNormalized(start) || !_isNormalized(end)) {
      return const VisualDraftEditResult.failure('coordenada_invalida');
    }
    if (start.distanceTo(end) < _minimumSegmentLength) {
      return const VisualDraftEditResult.failure('pared_longitud_cero');
    }
    if (draft.hasMeasurementForWall(wallId)) {
      return const VisualDraftEditResult.failure('pared_con_medicion');
    }

    final points = <FloorPoint>[wall.start, start, end, wall.end];
    final compact = <FloorPoint>[];
    for (final point in points) {
      if (compact.isEmpty ||
          compact.last.distanceTo(point) >= _minimumSegmentLength) {
        compact.add(point);
      }
    }
    if (compact.length < 2) {
      return const VisualDraftEditResult.failure('pared_longitud_cero');
    }
    final ids = <String>[wall.id];
    for (var index = 1; index < compact.length - 1; index++) {
      ids.add(_childWallId(draft, wallId, reserved: ids));
    }
    final replacements = <VisualWallSegment>[
      for (var index = 0; index < compact.length - 1; index++)
        VisualWallSegment(
          id: ids[index],
          start: compact[index],
          end: compact[index + 1],
          roomIds: wall.roomIds,
          manuallyEdited: true,
        ),
    ];
    final remappedOpenings = _remapOpeningsAcrossSegments(
      draft,
      wallId,
      replacements,
    );
    if (remappedOpenings == null) {
      return const VisualDraftEditResult.failure('division_sobre_abertura');
    }
    for (final replacement in replacements) {
      for (final existing in draft.walls) {
        if (existing.id == wallId) continue;
        if (_sameSegment(replacement, existing)) {
          return const VisualDraftEditResult.failure('pared_duplicada');
        }
      }
    }
    final walls = <VisualWallSegment>[
      for (final current in draft.walls)
        if (current.id == wallId) ...replacements else current,
    ];
    final rooms = [
      for (final current in draft.rooms)
        current.id == roomId
            ? VisualRoomRegion(
                id: current.id,
                name: current.name,
                wallIds: [
                  for (final id in current.wallIds)
                    if (id == wallId) ...ids else id,
                ],
              )
            : current,
    ];
    final candidate = draft.copyWith(
      walls: walls,
      rooms: rooms,
      openings: remappedOpenings,
    );
    final reconciled = _reconcileRoomRegions(candidate, draft.rooms);
    return reconciled == null
        ? const VisualDraftEditResult.failure('topologia_invalida')
        : _commit(reconciled);
  }

  static VisualDraftEditResult splitWall({
    required FloorplanVisualDraft draft,
    required String roomId,
    required String wallId,
    required FloorPoint point,
  }) {
    final room = draft.room(roomId);
    final wall = _wall(draft, wallId);
    if (room == null || wall == null || !room.wallIds.contains(wallId)) {
      return const VisualDraftEditResult.failure('pared_no_encontrada');
    }
    if (draft.hasMeasurementForWall(wallId)) {
      return const VisualDraftEditResult.failure('pared_con_medicion');
    }
    final split = _project(point, wall.start, wall.end);
    if (split.distanceTo(point) > _epsilon ||
        split.distanceTo(wall.start) < _minimumSegmentLength ||
        split.distanceTo(wall.end) < _minimumSegmentLength) {
      return const VisualDraftEditResult.failure('division_invalida');
    }
    final newId = _childWallId(draft, wallId);
    final first = VisualWallSegment(
      id: wall.id,
      start: wall.start,
      end: split,
      roomIds: wall.roomIds,
      manuallyEdited: true,
    );
    final second = VisualWallSegment(
      id: newId,
      start: split,
      end: wall.end,
      roomIds: wall.roomIds,
      manuallyEdited: true,
    );
    final remappedOpenings = _remapOpeningsAcrossSegments(draft, wallId, [
      first,
      second,
    ]);
    if (remappedOpenings == null) {
      return const VisualDraftEditResult.failure('division_sobre_abertura');
    }
    final walls = <VisualWallSegment>[
      for (final candidate in draft.walls) ...[
        if (candidate.id == wallId) first else candidate,
        if (candidate.id == wallId) second,
      ],
    ];
    final rooms = [
      for (final candidate in draft.rooms)
        candidate.id == roomId
            ? VisualRoomRegion(
                id: candidate.id,
                name: candidate.name,
                wallIds: [
                  for (final id in candidate.wallIds) ...[
                    id,
                    if (id == wallId) newId,
                  ],
                ],
              )
            : candidate,
    ];
    final candidate = draft.copyWith(
      walls: walls,
      rooms: rooms,
      openings: remappedOpenings,
    );
    final reconciled = _reconcileRoomRegions(candidate, draft.rooms);
    return reconciled == null
        ? const VisualDraftEditResult.failure('topologia_invalida')
        : _commit(reconciled);
  }

  static VisualDraftEditResult mergeWalls({
    required FloorplanVisualDraft draft,
    required String roomId,
    required String firstWallId,
    required String secondWallId,
  }) {
    final room = draft.room(roomId);
    if (room == null || firstWallId == secondWallId) {
      return const VisualDraftEditResult.failure('paredes_no_adyacentes');
    }
    final firstIndex = room.wallIds.indexOf(firstWallId);
    final secondIndex = room.wallIds.indexOf(secondWallId);
    if (firstIndex < 0 || secondIndex < 0) {
      return const VisualDraftEditResult.failure('pared_no_encontrada');
    }
    final count = room.wallIds.length;
    final orderedFirstId = (firstIndex + 1) % count == secondIndex
        ? firstWallId
        : (secondIndex + 1) % count == firstIndex
        ? secondWallId
        : null;
    if (orderedFirstId == null) {
      return const VisualDraftEditResult.failure('paredes_no_adyacentes');
    }
    final orderedSecondId = orderedFirstId == firstWallId
        ? secondWallId
        : firstWallId;
    final first = _wall(draft, orderedFirstId)!;
    final second = _wall(draft, orderedSecondId)!;
    final protection = _evidenceProtection(draft, {first.id, second.id});
    if (protection != null) return VisualDraftEditResult.failure(protection);
    if (first.end.distanceTo(second.start) > _epsilon ||
        !_collinear(first.start, first.end, second.end)) {
      return const VisualDraftEditResult.failure('fusion_invalida');
    }
    final merged = VisualWallSegment(
      id: first.id,
      start: first.start,
      end: second.end,
      roomIds: first.roomIds,
      manuallyEdited: true,
    );
    final walls = [
      for (final wall in draft.walls)
        if (wall.id == first.id) merged else if (wall.id != second.id) wall,
    ];
    final rooms = [
      for (final candidate in draft.rooms)
        candidate.id == roomId
            ? VisualRoomRegion(
                id: candidate.id,
                name: candidate.name,
                wallIds: [
                  for (final id in candidate.wallIds)
                    if (id != second.id) id,
                ],
              )
            : candidate,
    ];
    final candidate = draft.copyWith(walls: walls, rooms: rooms);
    final reconciled = _reconcileRoomRegions(candidate, draft.rooms);
    return reconciled == null
        ? const VisualDraftEditResult.failure('topologia_invalida')
        : _commit(reconciled);
  }

  static VisualDraftEditResult removeVertex({
    required FloorplanVisualDraft draft,
    required String roomId,
    required String followingWallId,
  }) {
    final room = draft.room(roomId);
    if (room == null)
      return const VisualDraftEditResult.failure('pared_no_encontrada');
    final index = room.wallIds.indexOf(followingWallId);
    if (index < 0)
      return const VisualDraftEditResult.failure('pared_no_encontrada');
    final roomWalls = [for (final id in room.wallIds) _wall(draft, id)!];
    final oriented = _orientRoomWalls(roomWalls);
    if (oriented == null) {
      return const VisualDraftEditResult.failure('topologia_invalida');
    }
    final previousIndex =
        (index - 1 + room.wallIds.length) % room.wallIds.length;
    final first = roomWalls[previousIndex];
    final second = roomWalls[index];
    final orientedFirst = oriented[previousIndex];
    final orientedSecond = oriented[index];
    if (draft.hasMeasurementForWall(first.id) ||
        draft.hasMeasurementForWall(second.id)) {
      return const VisualDraftEditResult.failure('pared_con_medicion');
    }
    if (orientedFirst.end.distanceTo(orientedSecond.start) > _epsilon) {
      return const VisualDraftEditResult.failure('paredes_no_adyacentes');
    }
    final selectedVertex = orientedFirst.end;
    final hasAdditionalConnection = draft.walls.any(
      (wall) =>
          wall.id != first.id &&
          wall.id != second.id &&
          (wall.start.distanceTo(selectedVertex) <= _epsilon ||
              wall.end.distanceTo(selectedVertex) <= _epsilon),
    );
    if (hasAdditionalConnection) {
      return const VisualDraftEditResult.failure('vertice_compartido');
    }
    final merged = VisualWallSegment(
      id: first.id,
      start: orientedFirst.start,
      end: orientedSecond.end,
      roomIds: first.roomIds,
      manuallyEdited: true,
    );
    if (!merged.isUsable) {
      return const VisualDraftEditResult.failure('pared_longitud_cero');
    }
    for (final wall in draft.walls) {
      if (wall.id != first.id &&
          wall.id != second.id &&
          _sameSegment(merged, wall)) {
        return const VisualDraftEditResult.failure('pared_duplicada');
      }
    }
    final hasAffectedOpenings =
        draft.hasOpeningForWall(first.id) || draft.hasOpeningForWall(second.id);
    final keepsPhysicalDirections =
        orientedFirst.start.distanceTo(first.start) <= _epsilon &&
        orientedSecond.start.distanceTo(second.start) <= _epsilon;
    final remappedOpenings = hasAffectedOpenings && !keepsPhysicalDirections
        ? null
        : _remapOpeningsForMergedWalls(draft, first, second, merged);
    if (remappedOpenings == null) {
      return const VisualDraftEditResult.failure('abertura_no_representable');
    }
    final walls = [
      for (final wall in draft.walls)
        if (wall.id == first.id) merged else if (wall.id != second.id) wall,
    ];
    final rooms = [
      for (final candidate in draft.rooms)
        candidate.id == roomId
            ? VisualRoomRegion(
                id: candidate.id,
                name: candidate.name,
                wallIds: [
                  for (final id in candidate.wallIds)
                    if (id != second.id) id,
                ],
              )
            : candidate,
    ];
    final candidate = draft.copyWith(
      walls: walls,
      rooms: rooms,
      openings: remappedOpenings,
    );
    final reconciled = _reconcileRoomRegions(candidate, draft.rooms);
    return reconciled == null
        ? const VisualDraftEditResult.failure('topologia_invalida')
        : _commit(reconciled);
  }

  /// Adds a physical partition without deforming the exterior geometry.
  /// Endpoints must attach to an existing topology vertex or to the interior
  /// of an existing wall. Interior attachment splits that wall transactionally
  /// and the bounded room regions are then reconstructed from the wall graph.
  static VisualDraftEditResult addInternalWall({
    required FloorplanVisualDraft draft,
    required String roomId,
    required FloorPoint start,
    required FloorPoint end,
  }) {
    if (draft.room(roomId) == null) {
      return const VisualDraftEditResult.failure('ambiente_no_encontrado');
    }
    if (!_isNormalized(start) || !_isNormalized(end)) {
      return const VisualDraftEditResult.failure('coordenada_invalida');
    }
    final first = _attachEndpoint(draft, start);
    if (first.errorCode != null) {
      return VisualDraftEditResult.failure(first.errorCode!);
    }
    final second = _attachEndpoint(first.draft!, end);
    if (second.errorCode != null) {
      return VisualDraftEditResult.failure(second.errorCode!);
    }
    final attachedStart = first.point!;
    final attachedEnd = second.point!;
    var candidate = second.draft!;
    if (attachedStart.distanceTo(attachedEnd) < _minimumSegmentLength) {
      return const VisualDraftEditResult.failure('pared_longitud_cero');
    }
    final intersections = <(double, FloorPoint)>[];
    final total = attachedStart.distanceTo(attachedEnd);
    void addIntersection(FloorPoint point) {
      if (intersections.any(
        (entry) => entry.$2.distanceTo(point) <= _epsilon,
      )) {
        return;
      }
      intersections.add((attachedStart.distanceTo(point) / total, point));
    }

    for (final existing in candidate.walls) {
      final intersection = _properIntersectionPoint(
        attachedStart,
        attachedEnd,
        existing.start,
        existing.end,
      );
      if (intersection != null) {
        addIntersection(intersection);
        continue;
      }
      for (final endpoint in [existing.start, existing.end]) {
        final projected = _project(endpoint, attachedStart, attachedEnd);
        if (projected.distanceTo(endpoint) <= _epsilon &&
            endpoint.distanceTo(attachedStart) >= _minimumSegmentLength &&
            endpoint.distanceTo(attachedEnd) >= _minimumSegmentLength) {
          addIntersection(endpoint);
        }
      }
    }
    intersections.sort((first, second) => first.$1.compareTo(second.$1));
    final junctions = <FloorPoint>[attachedStart];
    for (final (_, intersection) in intersections) {
      final attached = _attachEndpoint(candidate, intersection);
      if (attached.errorCode != null) {
        return VisualDraftEditResult.failure(attached.errorCode!);
      }
      candidate = attached.draft!;
      if (junctions.last.distanceTo(attached.point!) >= _minimumSegmentLength) {
        junctions.add(attached.point!);
      }
    }
    if (junctions.last.distanceTo(attachedEnd) >= _minimumSegmentLength) {
      junctions.add(attachedEnd);
    }
    if (junctions.length < 2) {
      return const VisualDraftEditResult.failure('pared_longitud_cero');
    }
    final baseId = _internalWallId(candidate, roomId);
    final ids = <String>[baseId];
    for (var index = 1; index < junctions.length - 1; index++) {
      ids.add(_childWallId(candidate, baseId, reserved: ids));
    }
    final newWalls = [
      for (var index = 0; index < junctions.length - 1; index++)
        VisualWallSegment(
          id: ids[index],
          start: junctions[index],
          end: junctions[index + 1],
          manuallyEdited: true,
        ),
    ];
    for (final wall in newWalls) {
      for (final existing in candidate.walls) {
        if (_sameSegment(wall, existing)) {
          return const VisualDraftEditResult.failure('pared_duplicada');
        }
        if (_crossesAwayFromSharedEndpoint(wall, existing)) {
          return const VisualDraftEditResult.failure(
            'interseccion_sin_vertice',
          );
        }
      }
    }
    final withWall = candidate.copyWith(
      walls: [...candidate.walls, ...newWalls],
    );
    final reconciled = _reconcileRoomRegions(withWall, draft.rooms);
    return reconciled == null
        ? const VisualDraftEditResult.failure('topologia_invalida')
        : _commit(reconciled);
  }

  static VisualDraftEditResult insertVertex({
    required FloorplanVisualDraft draft,
    required String wallId,
    required FloorPoint point,
  }) {
    final wall = _wall(draft, wallId);
    if (wall == null) {
      return const VisualDraftEditResult.failure('pared_no_encontrada');
    }
    final projected = _project(point, wall.start, wall.end);
    if (projected.distanceTo(point) > _epsilon) {
      return const VisualDraftEditResult.failure('division_invalida');
    }
    if (projected.distanceTo(wall.start) < _minimumSegmentLength ||
        projected.distanceTo(wall.end) < _minimumSegmentLength) {
      return const VisualDraftEditResult.failure('vertice_existente');
    }
    final attached = _attachEndpoint(draft, projected);
    if (attached.errorCode != null) {
      return VisualDraftEditResult.failure(attached.errorCode!);
    }
    final reconciled = _reconcileRoomRegions(attached.draft!, draft.rooms);
    return reconciled == null
        ? const VisualDraftEditResult.failure('topologia_invalida')
        : _commit(reconciled);
  }

  static VisualDraftEditResult removeInternalWall({
    required FloorplanVisualDraft draft,
    required String wallId,
  }) {
    final wall = _wall(draft, wallId);
    if (wall == null) {
      return const VisualDraftEditResult.failure('pared_no_encontrada');
    }
    if (wall.roomIds.length < 2) {
      return const VisualDraftEditResult.failure('pared_exterior');
    }
    if (draft.hasOpeningForWall(wallId)) {
      return const VisualDraftEditResult.failure('pared_con_abertura');
    }
    if (draft.hasMeasurementForWall(wallId)) {
      return const VisualDraftEditResult.failure('pared_con_medicion');
    }
    final candidate = draft.copyWith(
      walls: [
        for (final current in draft.walls)
          if (current.id != wallId) current,
      ],
    );
    final reconciled = _reconcileRoomRegions(candidate, draft.rooms);
    return reconciled == null
        ? const VisualDraftEditResult.failure('topologia_invalida')
        : _commit(reconciled);
  }

  static List<VisualOpeningDraft>? _remapOpeningsForMergedWalls(
    FloorplanVisualDraft draft,
    VisualWallSegment first,
    VisualWallSegment second,
    VisualWallSegment merged,
  ) {
    final affected = draft.openings
        .where(
          (opening) =>
              opening.wallId == first.id || opening.wallId == second.id,
        )
        .toList(growable: false);
    if (affected.isEmpty) return draft.openings;
    if (!_strictlyCollinear(first.start, first.end, second.end)) return null;

    final firstLength = first.start.distanceTo(first.end);
    final secondLength = second.start.distanceTo(second.end);
    final totalLength = firstLength + secondLength;
    if (totalLength <= _epsilon ||
        merged.start.distanceTo(merged.end) <= _epsilon) {
      return null;
    }

    double? physicalScale;
    for (final opening in affected) {
      final widthM = opening.widthM;
      final normalizedWidth = opening.normalizedWidth;
      if (opening.offsetFromWallStartM == null) continue;
      if (widthM == null ||
          normalizedWidth == null ||
          widthM <= 0 ||
          normalizedWidth <= 0) {
        return null;
      }
      final sourceLength = opening.wallId == first.id
          ? firstLength
          : secondLength;
      final inferred = widthM / (normalizedWidth * sourceLength);
      if (!inferred.isFinite || inferred <= 0) return null;
      if (physicalScale != null &&
          (physicalScale - inferred).abs() >
              math.max(physicalScale, inferred) * 0.01) {
        return null;
      }
      physicalScale ??= inferred;
    }

    final replacements = <String, VisualOpeningDraft>{};
    for (final opening in affected) {
      final position = opening.position;
      final width = opening.normalizedWidth;
      if (position == null || width == null || width <= 0) return null;
      final onSecond = opening.wallId == second.id;
      final sourceLength = onSecond ? secondLength : firstLength;
      final startDistance = onSecond ? firstLength : 0.0;
      double? offset = opening.offsetFromWallStartM;
      if (onSecond && offset != null) {
        if (physicalScale == null) return null;
        offset += firstLength * physicalScale;
      }
      replacements[opening.id] = opening.copyWith(
        wallId: first.id,
        position: (startDistance + position * sourceLength) / totalLength,
        normalizedWidth: width * sourceLength / totalLength,
        offsetFromWallStartM: offset,
      );
    }
    return [
      for (final opening in draft.openings) replacements[opening.id] ?? opening,
    ];
  }

  static _EndpointAttachment _attachEndpoint(
    FloorplanVisualDraft draft,
    FloorPoint requested,
  ) {
    VisualWallSegment? closestWall;
    FloorPoint? projected;
    var closestDistance = double.infinity;
    var ambiguous = false;
    for (final wall in draft.walls) {
      for (final endpoint in [wall.start, wall.end]) {
        final distance = requested.distanceTo(endpoint);
        if (distance <= _epsilon) {
          return _EndpointAttachment.success(draft, endpoint);
        }
      }
      final candidate = _project(requested, wall.start, wall.end);
      final distance = requested.distanceTo(candidate);
      if (distance <= _epsilon &&
          closestWall != null &&
          (distance - closestDistance).abs() <= _epsilon) {
        ambiguous = true;
      } else if (distance <= _epsilon && distance < closestDistance) {
        closestWall = wall;
        projected = candidate;
        closestDistance = distance;
        ambiguous = false;
      }
    }
    if (ambiguous) {
      return const _EndpointAttachment.failure('conexion_ambigua');
    }
    if (closestWall == null || projected == null) {
      return const _EndpointAttachment.failure('extremo_sin_conexion');
    }
    if (projected.distanceTo(closestWall.start) < _minimumSegmentLength ||
        projected.distanceTo(closestWall.end) < _minimumSegmentLength) {
      return const _EndpointAttachment.failure('division_invalida');
    }
    if (draft.hasMeasurementForWall(closestWall.id)) {
      return const _EndpointAttachment.failure('pared_con_medicion');
    }

    final childId = _childWallId(draft, closestWall.id);
    final first = VisualWallSegment(
      id: closestWall.id,
      start: closestWall.start,
      end: projected,
      roomIds: closestWall.roomIds,
      manuallyEdited: true,
    );
    final second = VisualWallSegment(
      id: childId,
      start: projected,
      end: closestWall.end,
      roomIds: closestWall.roomIds,
      manuallyEdited: true,
    );
    final openings = _remapOpeningsAcrossSegments(draft, closestWall.id, [
      first,
      second,
    ]);
    if (openings == null) {
      return const _EndpointAttachment.failure('division_sobre_abertura');
    }
    final walls = <VisualWallSegment>[
      for (final wall in draft.walls)
        if (wall.id == closestWall.id) ...[first, second] else wall,
    ];
    final rooms = [
      for (final room in draft.rooms)
        room.wallIds.contains(closestWall.id)
            ? VisualRoomRegion(
                id: room.id,
                name: room.name,
                wallIds: [
                  for (final wallId in room.wallIds) ...[
                    wallId,
                    if (wallId == closestWall.id) childId,
                  ],
                ],
              )
            : room,
    ];
    final candidate = draft.copyWith(
      walls: walls,
      rooms: rooms,
      openings: openings,
    );
    return _EndpointAttachment.success(candidate, projected);
  }

  static bool _crossesAwayFromSharedEndpoint(
    VisualWallSegment candidate,
    VisualWallSegment existing,
  ) {
    if (!segmentsIntersect(
      candidate.start,
      candidate.end,
      existing.start,
      existing.end,
    )) {
      return false;
    }
    final sharesStart =
        candidate.start.distanceTo(existing.start) <= _epsilon ||
        candidate.start.distanceTo(existing.end) <= _epsilon;
    final sharesEnd =
        candidate.end.distanceTo(existing.start) <= _epsilon ||
        candidate.end.distanceTo(existing.end) <= _epsilon;
    if (!sharesStart && !sharesEnd) return true;
    return _pointOnSegmentInterior(candidate.start, existing) ||
        _pointOnSegmentInterior(candidate.end, existing) ||
        _pointOnSegmentInterior(existing.start, candidate) ||
        _pointOnSegmentInterior(existing.end, candidate);
  }

  static bool _pointOnSegmentInterior(
    FloorPoint point,
    VisualWallSegment wall,
  ) {
    final projected = _project(point, wall.start, wall.end);
    return point.distanceTo(projected) <= _epsilon &&
        point.distanceTo(wall.start) > _epsilon &&
        point.distanceTo(wall.end) > _epsilon;
  }

  static List<VisualOpeningDraft>? _remapOpeningsAcrossSegments(
    FloorplanVisualDraft draft,
    String sourceWallId,
    List<VisualWallSegment> segments,
  ) {
    final sourceOpenings = draft.openings
        .where((opening) => opening.wallId == sourceWallId)
        .toList(growable: false);
    if (sourceOpenings.isEmpty) return draft.openings;

    final lengths = [
      for (final segment in segments) segment.start.distanceTo(segment.end),
    ];
    final totalLength = lengths.fold<double>(0, (sum, value) => sum + value);
    if (!totalLength.isFinite || totalLength <= _epsilon) return null;

    final remapped = <String, VisualOpeningDraft>{};
    const tolerance = 1e-7;
    for (final opening in sourceOpenings) {
      final position = opening.position;
      final normalizedWidth = opening.normalizedWidth;
      if (position == null ||
          normalizedWidth == null ||
          !position.isFinite ||
          !normalizedWidth.isFinite ||
          normalizedWidth <= 0) {
        return null;
      }
      final openingStart = position - normalizedWidth / 2;
      final openingEnd = position + normalizedWidth / 2;
      if (openingStart < -tolerance || openingEnd > 1 + tolerance) {
        return null;
      }

      var cumulative = 0.0;
      VisualWallSegment? target;
      double? targetStart;
      double? targetFraction;
      for (var index = 0; index < segments.length; index++) {
        final fraction = lengths[index] / totalLength;
        final segmentEnd = cumulative + fraction;
        final contained =
            openingStart >= cumulative - tolerance &&
            openingEnd <= segmentEnd + tolerance;
        if (contained) {
          target = segments[index];
          targetStart = cumulative;
          targetFraction = fraction;
          break;
        }
        cumulative = segmentEnd;
      }
      if (target == null ||
          targetStart == null ||
          targetFraction == null ||
          targetFraction <= _epsilon) {
        return null;
      }

      double? physicalOffset = opening.offsetFromWallStartM;
      if (physicalOffset != null) {
        final widthM = opening.widthM;
        if (widthM == null || widthM <= 0) return null;
        final physicalWallLength = widthM / normalizedWidth;
        if (!physicalWallLength.isFinite || physicalWallLength <= 0) {
          return null;
        }
        physicalOffset -= targetStart * physicalWallLength;
        if (physicalOffset < -tolerance) return null;
        if (physicalOffset < 0) physicalOffset = 0;
      }

      remapped[opening.id] = opening.copyWith(
        wallId: target.id,
        position: (position - targetStart) / targetFraction,
        normalizedWidth: normalizedWidth / targetFraction,
        offsetFromWallStartM: physicalOffset,
      );
    }

    return [
      for (final opening in draft.openings) remapped[opening.id] ?? opening,
    ];
  }

  static FloorplanVisualDraft? _reconcileRoomRegions(
    FloorplanVisualDraft draft,
    List<VisualRoomRegion> previousRooms,
  ) {
    for (var firstIndex = 0; firstIndex < draft.walls.length; firstIndex++) {
      final first = draft.walls[firstIndex];
      for (
        var secondIndex = firstIndex + 1;
        secondIndex < draft.walls.length;
        secondIndex++
      ) {
        final second = draft.walls[secondIndex];
        if (_sameSegment(first, second) ||
            _crossesAwayFromSharedEndpoint(first, second)) {
          return null;
        }
      }
    }
    final directed = <_DirectedVisualWall>[
      for (final wall in draft.walls) ...[
        _DirectedVisualWall(wall, false),
        _DirectedVisualWall(wall, true),
      ],
    ];
    final outgoing = <String, List<_DirectedVisualWall>>{};
    for (final edge in directed) {
      outgoing.putIfAbsent(_vertexKey(edge.start), () => []).add(edge);
    }
    for (final edges in outgoing.values) {
      edges.sort((a, b) => a.angle.compareTo(b.angle));
    }

    final visited = <String>{};
    final faces = <_VisualFace>[];
    for (final seed in directed) {
      if (visited.contains(seed.key)) continue;
      final wallIds = <String>[];
      final points = <FloorPoint>[];
      var current = seed;
      var closed = false;
      for (var step = 0; step <= directed.length; step++) {
        if (!visited.add(current.key)) {
          closed = current.key == seed.key;
          break;
        }
        wallIds.add(current.wall.id);
        points.add(current.start);
        final choices = outgoing[_vertexKey(current.end)];
        if (choices == null || choices.isEmpty) break;
        final reverseIndex = choices.indexWhere(
          (candidate) =>
              candidate.wall.id == current.wall.id &&
              candidate.reversed != current.reversed,
        );
        if (reverseIndex < 0) break;
        current = choices[(reverseIndex - 1 + choices.length) % choices.length];
        if (current.key == seed.key) {
          closed = true;
          break;
        }
      }
      if (!closed ||
          wallIds.length < 3 ||
          wallIds.toSet().length != wallIds.length ||
          signedArea(points) <= _epsilon) {
        continue;
      }
      faces.add(_VisualFace(wallIds, points));
    }
    if (faces.isEmpty) return null;
    final usedWalls = {for (final face in faces) ...face.wallIds};
    if (usedWalls.length != draft.walls.length) return null;

    final assigned = <int, VisualRoomRegion>{};
    final availableFaces = {
      for (var index = 0; index < faces.length; index++) index,
    };
    for (final room in previousRooms) {
      var bestIndex = -1;
      var bestScore = 0;
      for (final index in availableFaces) {
        final score = faces[index].wallIds
            .toSet()
            .intersection(room.wallIds.toSet())
            .length;
        if (score > bestScore) {
          bestScore = score;
          bestIndex = index;
        }
      }
      if (bestIndex >= 0 && bestScore > 0) {
        assigned[bestIndex] = VisualRoomRegion(
          id: room.id,
          name: room.name,
          wallIds: faces[bestIndex].wallIds,
        );
        availableFaces.remove(bestIndex);
      }
    }
    final usedRoomIds = {for (final room in assigned.values) room.id};
    final baseId = previousRooms.firstOrNull?.id ?? 'room';
    for (final index in availableFaces) {
      final id = _nextRoomId(baseId, usedRoomIds);
      usedRoomIds.add(id);
      assigned[index] = VisualRoomRegion(
        id: id,
        name: 'Ambiente ${assigned.length + 1}',
        wallIds: faces[index].wallIds,
      );
    }
    final rooms = [
      for (var index = 0; index < faces.length; index++) assigned[index]!,
    ];
    final roomIdsByWall = <String, List<String>>{};
    for (final room in rooms) {
      for (final wallId in room.wallIds) {
        roomIdsByWall.putIfAbsent(wallId, () => []).add(room.id);
      }
    }
    final walls = [
      for (final wall in draft.walls)
        VisualWallSegment(
          id: wall.id,
          start: wall.start,
          end: wall.end,
          roomIds: roomIdsByWall[wall.id] ?? const [],
          manuallyEdited: wall.manuallyEdited,
        ),
    ];
    final reconciled = draft.copyWith(walls: walls, rooms: rooms);
    return reconciled.validate().isEmpty ? reconciled : null;
  }

  static String _nextRoomId(String baseId, Set<String> used) {
    for (var generation = 1; ; generation++) {
      final candidate = '$baseId.region.$generation';
      if (!used.contains(candidate)) return candidate;
    }
  }

  static VisualDraftEditResult _commit(FloorplanVisualDraft candidate) {
    final errors = candidate.validate();
    return errors.isEmpty
        ? VisualDraftEditResult.success(candidate)
        : VisualDraftEditResult.failure('geometria_invalida');
  }

  /// Conservative protection for operations that cannot remap evidence: merge
  /// refuses walls with openings, and any operation refuses walls with confirmed
  /// measurements. Splitting delegates opening remapping to
  /// [_remapOpeningsAcrossSegments] instead of this blanket rejection.
  static String? _evidenceProtection(
    FloorplanVisualDraft draft,
    Iterable<String> wallIds,
  ) {
    for (final wallId in wallIds) {
      if (draft.hasOpeningForWall(wallId)) return 'pared_con_abertura';
    }
    for (final wallId in wallIds) {
      if (draft.hasMeasurementForWall(wallId)) return 'pared_con_medicion';
    }
    return null;
  }

  static VisualWallSegment? _wall(FloorplanVisualDraft draft, String id) {
    for (final wall in draft.walls) {
      if (wall.id == id) return wall;
    }
    return null;
  }

  static VisualWallSegment _replaceMatchingEndpoint(
    VisualWallSegment wall,
    FloorPoint original,
    FloorPoint replacement,
  ) => VisualWallSegment(
    id: wall.id,
    start: wall.start.distanceTo(original) <= _epsilon
        ? replacement
        : wall.start,
    end: wall.end.distanceTo(original) <= _epsilon ? replacement : wall.end,
    roomIds: wall.roomIds,
    manuallyEdited: true,
  );

  static bool _isNormalized(FloorPoint point) =>
      point.x.isFinite &&
      point.z.isFinite &&
      point.x >= 0 &&
      point.x <= 1 &&
      point.z >= 0 &&
      point.z <= 1;

  static FloorPoint _project(
    FloorPoint point,
    FloorPoint start,
    FloorPoint end,
  ) {
    final edge = end - start;
    final lengthSquared = edge.dot(edge);
    if (lengthSquared <= 0) return start;
    final t = ((point - start).dot(edge) / lengthSquared).clamp(0.0, 1.0);
    return start + edge.scale(t);
  }

  static FloorPoint? _properIntersectionPoint(
    FloorPoint firstStart,
    FloorPoint firstEnd,
    FloorPoint secondStart,
    FloorPoint secondEnd,
  ) {
    final firstDirection = firstEnd - firstStart;
    final secondDirection = secondEnd - secondStart;
    final denominator = firstDirection.cross(secondDirection);
    if (denominator.abs() <= _epsilon) return null;
    final delta = secondStart - firstStart;
    final firstT = delta.cross(secondDirection) / denominator;
    final secondT = delta.cross(firstDirection) / denominator;
    if (firstT <= _epsilon ||
        firstT >= 1 - _epsilon ||
        secondT <= _epsilon ||
        secondT >= 1 - _epsilon) {
      return null;
    }
    return firstStart + firstDirection.scale(firstT);
  }

  static bool _collinear(FloorPoint start, FloorPoint middle, FloorPoint end) {
    final a = middle - start;
    final b = end - middle;
    final product = a.length * b.length;
    return product > _epsilon &&
        (a.cross(b).abs() / product) <= math.sin(8 * math.pi / 180) &&
        a.dot(b) > 0;
  }

  static bool _strictlyCollinear(
    FloorPoint start,
    FloorPoint middle,
    FloorPoint end,
  ) {
    final a = middle - start;
    final b = end - middle;
    final product = a.length * b.length;
    return product > _epsilon &&
        a.cross(b).abs() / product <= _epsilon &&
        a.dot(b) > 0;
  }

  static bool _sameSegment(VisualWallSegment first, VisualWallSegment second) =>
      (first.start.distanceTo(second.start) <= _epsilon &&
          first.end.distanceTo(second.end) <= _epsilon) ||
      (first.start.distanceTo(second.end) <= _epsilon &&
          first.end.distanceTo(second.start) <= _epsilon);

  static String _childWallId(
    FloorplanVisualDraft draft,
    String parentId, {
    Iterable<String> reserved = const [],
  }) {
    final ids = {for (final wall in draft.walls) wall.id, ...reserved};
    for (var generation = 1; ; generation++) {
      final candidate = '$parentId.split.$generation';
      if (!ids.contains(candidate)) return candidate;
    }
  }

  static String _internalWallId(FloorplanVisualDraft draft, String roomId) {
    final ids = {for (final wall in draft.walls) wall.id};
    for (var generation = 1; ; generation++) {
      final candidate = '$roomId.internal.$generation';
      if (!ids.contains(candidate)) return candidate;
    }
  }
}

class _EndpointAttachment {
  const _EndpointAttachment._({this.draft, this.point, this.errorCode});

  const _EndpointAttachment.success(
    FloorplanVisualDraft value,
    FloorPoint resolved,
  ) : this._(draft: value, point: resolved);

  const _EndpointAttachment.failure(String code) : this._(errorCode: code);

  final FloorplanVisualDraft? draft;
  final FloorPoint? point;
  final String? errorCode;
}

class _DirectedVisualWall {
  const _DirectedVisualWall(this.wall, this.reversed);

  final VisualWallSegment wall;
  final bool reversed;

  FloorPoint get start => reversed ? wall.end : wall.start;
  FloorPoint get end => reversed ? wall.start : wall.end;
  double get angle => math.atan2(end.z - start.z, end.x - start.x);
  String get key => '${wall.id}:${reversed ? 1 : 0}';
}

class _VisualFace {
  const _VisualFace(this.wallIds, this.points);

  final List<String> wallIds;
  final List<FloorPoint> points;
}

String _vertexKey(FloorPoint point) =>
    '${(point.x * 1000000).round()}:${(point.z * 1000000).round()}';

bool _sameList<T>(List<T> a, List<T> b, bool Function(T a, T b) same) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (!same(a[index], b[index])) return false;
  }
  return true;
}

bool _normalizedOrNull(double? value) =>
    value == null || (value.isFinite && value >= 0 && value <= 1);

bool _intervalsOverlap(
  double firstStart,
  double firstEnd,
  double secondStart,
  double secondEnd,
) => math.max(firstStart, secondStart) < math.min(firstEnd, secondEnd) - 1e-9;

bool _isNormalizedPoint(FloorPoint point) =>
    point.x.isFinite &&
    point.z.isFinite &&
    point.x >= 0 &&
    point.x <= 1 &&
    point.z >= 0 &&
    point.z <= 1;

bool _samePhysicalWall(VisualWallSegment first, VisualWallSegment second) =>
    (first.start.distanceTo(second.start) <= 1e-6 &&
        first.end.distanceTo(second.end) <= 1e-6) ||
    (first.start.distanceTo(second.end) <= 1e-6 &&
        first.end.distanceTo(second.start) <= 1e-6);

bool _wallsCrossWithoutTopology(
  VisualWallSegment first,
  VisualWallSegment second,
) {
  if (!segmentsIntersect(first.start, first.end, second.start, second.end)) {
    return false;
  }
  final sharedEndpoint =
      first.start.distanceTo(second.start) <= 1e-6 ||
      first.start.distanceTo(second.end) <= 1e-6 ||
      first.end.distanceTo(second.start) <= 1e-6 ||
      first.end.distanceTo(second.end) <= 1e-6;
  if (!sharedEndpoint) return true;
  return _pointOnWallInterior(first.start, second) ||
      _pointOnWallInterior(first.end, second) ||
      _pointOnWallInterior(second.start, first) ||
      _pointOnWallInterior(second.end, first);
}

bool _pointOnWallInterior(FloorPoint point, VisualWallSegment wall) {
  final edge = wall.end - wall.start;
  final lengthSquared = edge.dot(edge);
  if (lengthSquared <= 0) return false;
  final t = (point - wall.start).dot(edge) / lengthSquared;
  if (t <= 1e-6 || t >= 1 - 1e-6) return false;
  final projected = wall.start + edge.scale(t);
  return point.distanceTo(projected) <= 1e-6;
}

List<VisualWallSegment>? _orientRoomWalls(List<VisualWallSegment> walls) {
  if (walls.isEmpty) return null;
  for (final reverseFirst in [false, true]) {
    final oriented = <VisualWallSegment>[
      _orientedWall(walls.first, reverseFirst),
    ];
    var valid = true;
    for (final wall in walls.skip(1)) {
      final previousEnd = oriented.last.end;
      if (previousEnd.distanceTo(wall.start) <= 1e-6) {
        oriented.add(wall);
      } else if (previousEnd.distanceTo(wall.end) <= 1e-6) {
        oriented.add(_orientedWall(wall, true));
      } else {
        valid = false;
        break;
      }
    }
    if (valid && oriented.last.end.distanceTo(oriented.first.start) <= 1e-6) {
      return oriented;
    }
  }
  return null;
}

VisualWallSegment _orientedWall(VisualWallSegment wall, bool reversed) =>
    reversed
    ? VisualWallSegment(
        id: wall.id,
        start: wall.end,
        end: wall.start,
        roomIds: wall.roomIds,
        manuallyEdited: wall.manuallyEdited,
      )
    : wall;

bool _isClosedSimplePerimeter(List<VisualWallSegment> walls) {
  const tolerance = 1e-6;
  for (var index = 0; index < walls.length; index++) {
    if (walls[index].end.distanceTo(walls[(index + 1) % walls.length].start) >
        tolerance) {
      return false;
    }
  }
  final points = [for (final wall in walls) wall.start];
  if (polygonArea(points) <= tolerance) return false;
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    for (var j = i + 1; j < points.length; j++) {
      if (j == i ||
          (j + 1) % points.length == i ||
          (i + 1) % points.length == j) {
        continue;
      }
      if (segmentsIntersect(a, b, points[j], points[(j + 1) % points.length])) {
        return false;
      }
    }
  }
  return true;
}

class VisualWallSegment {
  const VisualWallSegment({
    required this.id,
    required this.start,
    required this.end,
    this.roomIds = const [],
    this.manuallyEdited = false,
  });

  factory VisualWallSegment.fromJson(Map<String, Object?> json) =>
      VisualWallSegment(
        id: json['id']! as String,
        start: FloorPoint.fromJson(
          (json['start']! as Map).cast<String, Object?>(),
        ),
        end: FloorPoint.fromJson((json['end']! as Map).cast<String, Object?>()),
        roomIds: [
          for (final id in json['roomIds'] as List? ?? const []) id as String,
        ],
        manuallyEdited: json['manuallyEdited'] == true,
      );

  final String id;
  final FloorPoint start;
  final FloorPoint end;
  final List<String> roomIds;
  final bool manuallyEdited;

  bool get isUsable => start.distanceTo(end) > 1e-6;

  Map<String, Object?> toJson() => {
    'id': id,
    'start': start.toJson(),
    'end': end.toJson(),
    'roomIds': roomIds,
    if (manuallyEdited) 'manuallyEdited': true,
  };
}

class VisualRoomRegion {
  const VisualRoomRegion({required this.id, required this.wallIds, this.name});

  factory VisualRoomRegion.fromJson(Map<String, Object?> json) =>
      VisualRoomRegion(
        id: json['id']! as String,
        name: json['name'] as String?,
        wallIds: [for (final id in json['wallIds'] as List) id as String],
      );

  final String id;
  final String? name;
  final List<String> wallIds;

  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'wallIds': wallIds,
  };
}

enum VisualOpeningType { unknown, door, window }

/// Acquisition-only measurement evidence. A null [wallId] deliberately means
/// the legacy evidence survived migration but requires human association.
class VisualWallMeasurementEvidence {
  const VisualWallMeasurementEvidence({
    required this.id,
    required this.meters,
    this.wallId,
    this.intervalStart,
    this.intervalEnd,
    this.provenance = 'user',
    this.requiresReview = false,
    this.lineageId,
    this.dimension = VisualWallMeasurementDimension.length,
  });

  factory VisualWallMeasurementEvidence.fromJson(Map<String, Object?> json) =>
      VisualWallMeasurementEvidence(
        id: json['id']! as String,
        meters: (json['meters']! as num).toDouble(),
        wallId: json['wallId'] as String?,
        intervalStart: (json['intervalStart'] as num?)?.toDouble(),
        intervalEnd: (json['intervalEnd'] as num?)?.toDouble(),
        provenance: json['provenance'] as String? ?? 'user',
        requiresReview: json['requiresReview'] == true,
        lineageId: json['lineageId'] as String?,
        dimension: VisualWallMeasurementDimension.values.firstWhere(
          (value) => value.name == json['dimension'],
          orElse: () => VisualWallMeasurementDimension.length,
        ),
      );

  final String id;
  final String? wallId;
  final double meters;
  final double? intervalStart;
  final double? intervalEnd;
  final String provenance;
  final bool requiresReview;
  final String? lineageId;
  final VisualWallMeasurementDimension dimension;

  /// Authoritative evidence must be wall-bound and explicitly accepted by the
  /// user. Provider detections keep [requiresReview] until that happens, even
  /// after the room itself is confirmed.
  bool get isAuthoritative =>
      wallId != null &&
      !requiresReview &&
      (provenance == 'user' || provenance == 'ai_detected');

  VisualWallMeasurementEvidence copyWith({
    String? wallId,
    bool clearWallId = false,
    double? meters,
    String? provenance,
    bool? requiresReview,
    VisualWallMeasurementDimension? dimension,
  }) => VisualWallMeasurementEvidence(
    id: id,
    wallId: clearWallId ? null : wallId ?? this.wallId,
    meters: meters ?? this.meters,
    intervalStart: intervalStart,
    intervalEnd: intervalEnd,
    provenance: provenance ?? this.provenance,
    requiresReview: requiresReview ?? this.requiresReview,
    lineageId: lineageId,
    dimension: dimension ?? this.dimension,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'wallId': wallId,
    'meters': meters,
    if (intervalStart != null) 'intervalStart': intervalStart,
    if (intervalEnd != null) 'intervalEnd': intervalEnd,
    if (provenance != 'user') 'provenance': provenance,
    if (requiresReview) 'requiresReview': true,
    if (lineageId != null) 'lineageId': lineageId,
    if (dimension != VisualWallMeasurementDimension.length)
      'dimension': dimension.name,
  };
}

enum VisualWallMeasurementDimension { length, height }

/// Acquisition-only opening. [manuallyPlaced] is false for provider
/// detections: they stay reviewable and are never silently confirmed, and
/// [confidence] is preserved verbatim when converting representations.
class VisualOpeningDraft {
  const VisualOpeningDraft({
    required this.id,
    required this.type,
    this.wallId,
    this.position,
    this.normalizedWidth,
    this.manuallyPlaced = false,
    this.confidence,
    this.widthM,
    this.heightM,
    this.offsetFromWallStartM,
    this.sillHeightM,
  });

  factory VisualOpeningDraft.fromJson(
    Map<String, Object?> json, {
    bool legacyDocument = false,
  }) => VisualOpeningDraft(
    id: json['id']! as String,
    type: VisualOpeningType.values.firstWhere(
      (type) => type.name == json['type'],
      orElse: () => VisualOpeningType.unknown,
    ),
    wallId: json['wallId'] as String?,
    position: (json['position'] as num?)?.toDouble(),
    normalizedWidth: (json['normalizedWidth'] as num?)?.toDouble(),
    manuallyPlaced: json['manuallyPlaced'] == true,
    confidence: (json['confidence'] as num?)?.toDouble(),
    widthM: (json['widthM'] as num?)?.toDouble(),
    heightM: (json['heightM'] as num?)?.toDouble(),
    offsetFromWallStartM: (json['offsetFromWallStartM'] as num?)?.toDouble(),
    sillHeightM:
        (json['sillHeightM'] as num?)?.toDouble() ??
        (legacyDocument && json['type'] == VisualOpeningType.window.name
            ? 0.9
            : null),
  );

  final String id;
  final VisualOpeningType type;
  final String? wallId;
  final double? position;
  final double? normalizedWidth;
  final bool manuallyPlaced;
  final double? confidence;
  final double? widthM;
  final double? heightM;
  final double? offsetFromWallStartM;
  final double? sillHeightM;

  bool get hasVisualGeometry =>
      wallId != null && position != null && normalizedWidth != null;

  VisualOpeningDraft copyWith({
    String? wallId,
    double? position,
    double? normalizedWidth,
    bool? manuallyPlaced,
    double? confidence,
    double? widthM,
    double? heightM,
    double? offsetFromWallStartM,
    double? sillHeightM,
  }) => VisualOpeningDraft(
    id: id,
    type: type,
    wallId: wallId ?? this.wallId,
    position: position ?? this.position,
    normalizedWidth: normalizedWidth ?? this.normalizedWidth,
    manuallyPlaced: manuallyPlaced ?? this.manuallyPlaced,
    confidence: confidence ?? this.confidence,
    widthM: widthM ?? this.widthM,
    heightM: heightM ?? this.heightM,
    offsetFromWallStartM: offsetFromWallStartM ?? this.offsetFromWallStartM,
    sillHeightM: sillHeightM ?? this.sillHeightM,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'wallId': wallId,
    if (position != null) 'position': position,
    if (normalizedWidth != null) 'normalizedWidth': normalizedWidth,
    if (manuallyPlaced) 'manuallyPlaced': true,
    if (confidence != null) 'confidence': confidence,
    if (widthM != null) 'widthM': widthM,
    if (heightM != null) 'heightM': heightM,
    if (offsetFromWallStartM != null)
      'offsetFromWallStartM': offsetFromWallStartM,
    if (sillHeightM != null) 'sillHeightM': sillHeightM,
  };
}
