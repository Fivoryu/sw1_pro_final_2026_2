/// Guided capture checklist (F14.2): which rooms to photograph, in which
/// order, what to check in each one and whether the session is complete.
///
/// It is plain data and rules, with no AR: F07 can reuse the same rooms and
/// checks for its spatial session (see `docs/guias/f14-captura-guiada.md`).
library;

/// Kind of room; the suggested capture order follows this declaration.
enum RoomKind { living, kitchen, bedroom, bathroom, extra }

/// A quality check the agent confirms for each room.
enum RoomCheck {
  lighting(
    'Luces encendidas y cortinas abiertas',
    'Encendé las luces y abrí cortinas antes de fotografiar.',
  ),
  coverage(
    'Foto tomada desde la entrada, mostrando al menos dos paredes',
    'Parate en la entrada del ambiente y encuadrá dos paredes o más.',
  ),
  privacy(
    'Sin personas ni objetos personales a la vista',
    'Retirá fotos familiares, documentos y personas del encuadre.',
  );

  const RoomCheck(this.label, this.hint);

  final String label;
  final String hint;
}

/// One room of the guided session.
class CaptureRoom {
  const CaptureRoom({
    required this.id,
    required this.kind,
    required this.label,
    this.checks = const {},
    this.photoIds = const [],
    this.skippedReason,
  });

  factory CaptureRoom.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Room must be an object');
    }
    final id = json['id'];
    final kind = json['kind'];
    final label = json['label'];
    final checks = json['checks'];
    final photoIds = json['photo_ids'];
    final skipped = json['skipped_reason'];
    if (id is! String ||
        kind is! String ||
        label is! String ||
        checks is! List<Object?> ||
        photoIds is! List<Object?> ||
        (skipped != null && skipped is! String)) {
      throw const FormatException('Room fields are invalid');
    }
    return CaptureRoom(
      id: id,
      kind: RoomKind.values.byName(kind),
      label: label,
      checks: {
        for (final check in checks) RoomCheck.values.byName(check! as String),
      },
      photoIds: [for (final photoId in photoIds) photoId! as String],
      skippedReason: skipped as String?,
    );
  }

  final String id;
  final RoomKind kind;
  final String label;

  /// Checks the agent confirmed.
  final Set<RoomCheck> checks;

  /// Confirmed listing photos taken for this room through the guide; only
  /// photos that passed the quality validation are ever added.
  final List<String> photoIds;

  /// Why the room does not apply to this listing, or null when it does.
  final String? skippedReason;

  bool get isSkipped => skippedReason != null;

  CaptureRoom copyWith({
    String? label,
    Set<RoomCheck>? checks,
    List<String>? photoIds,
    String? Function()? skippedReason,
  }) => CaptureRoom(
    id: id,
    kind: kind,
    label: label ?? this.label,
    checks: checks ?? this.checks,
    photoIds: photoIds ?? this.photoIds,
    skippedReason: skippedReason == null ? this.skippedReason : skippedReason(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'checks': [
      for (final check in RoomCheck.values)
        if (checks.contains(check)) check.name,
    ],
    'photo_ids': photoIds,
    'skipped_reason': skippedReason,
  };
}

/// Progress of one room against the listing's current photos.
enum RoomStatus { pending, inProgress, done, skipped }

/// The guided session of one listing.
class CaptureChecklist {
  const CaptureChecklist(this.rooms);

  factory CaptureChecklist.fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['version'] != 1) {
      throw const FormatException('Unknown checklist format');
    }
    final rooms = json['rooms'];
    if (rooms is! List<Object?>) {
      throw const FormatException('Rooms must be a list');
    }
    return CaptureChecklist([
      for (final room in rooms) CaptureRoom.fromJson(room),
    ]);
  }

  /// Rooms for a listing card: living and kitchen, then one bedroom and one
  /// bathroom per declared count. Rooms already in [previous] keep their
  /// state; extra rooms are kept; derived rooms beyond the counts are dropped.
  factory CaptureChecklist.derive({
    required int bedrooms,
    required int bathrooms,
    CaptureChecklist? previous,
  }) {
    final kept = {
      for (final room in previous?.rooms ?? const <CaptureRoom>[])
        room.id: room,
    };
    // A kept room keeps its state; its label follows the new counts.
    CaptureRoom room(String id, RoomKind kind, String label) =>
        kept[id]?.copyWith(label: label) ??
        CaptureRoom(id: id, kind: kind, label: label);
    return CaptureChecklist([
      room('living', RoomKind.living, 'Living'),
      room('kitchen', RoomKind.kitchen, 'Cocina'),
      for (var i = 1; i <= bedrooms; i++)
        room(
          'bedroom-$i',
          RoomKind.bedroom,
          bedrooms == 1 ? 'Dormitorio' : 'Dormitorio $i',
        ),
      for (var i = 1; i <= bathrooms; i++)
        room(
          'bathroom-$i',
          RoomKind.bathroom,
          bathrooms == 1 ? 'Baño' : 'Baño $i',
        ),
      for (final extra in previous?.rooms ?? const <CaptureRoom>[])
        if (extra.kind == RoomKind.extra) extra,
    ]);
  }

  /// Rooms in the suggested capture order.
  final List<CaptureRoom> rooms;

  Map<String, Object?> toJson() => {
    'version': 1,
    'rooms': [for (final room in rooms) room.toJson()],
  };

  CaptureChecklist replace(CaptureRoom updated) => CaptureChecklist([
    for (final room in rooms) room.id == updated.id ? updated : room,
  ]);

  /// Photos of [room] that still exist among the listing's [photoIds].
  static List<String> livePhotos(CaptureRoom room, Set<String> photoIds) => [
    for (final photoId in room.photoIds)
      if (photoIds.contains(photoId)) photoId,
  ];

  static RoomStatus statusOf(CaptureRoom room, Set<String> photoIds) {
    if (room.isSkipped) return RoomStatus.skipped;
    final hasPhoto = livePhotos(room, photoIds).isNotEmpty;
    final checked = room.checks.length == RoomCheck.values.length;
    if (hasPhoto && checked) return RoomStatus.done;
    if (hasPhoto || room.checks.isNotEmpty) return RoomStatus.inProgress;
    return RoomStatus.pending;
  }

  /// Rooms that are done or skipped, out of all rooms.
  ({int finished, int total}) progress(Set<String> photoIds) => (
    finished: rooms
        .where(
          (room) => switch (statusOf(room, photoIds)) {
            RoomStatus.done || RoomStatus.skipped => true,
            _ => false,
          },
        )
        .length,
    total: rooms.length,
  );

  /// Why the session cannot be sent to review yet; empty when it can.
  ///
  /// Every room that applies needs at least one photo that passed the
  /// quality validation and still exists, and every check confirmed. At
  /// least one room must apply.
  List<String> problems(Set<String> photoIds) {
    final problems = <String>[];
    if (rooms.every((room) => room.isSkipped)) {
      problems.add('Fotografiá al menos un ambiente.');
    }
    for (final room in rooms) {
      if (room.isSkipped) continue;
      if (livePhotos(room, photoIds).isEmpty) {
        problems.add(
          '${room.label}: falta una foto que pase la validación de calidad.',
        );
      }
      final missing = RoomCheck.values.where(
        (check) => !room.checks.contains(check),
      );
      if (missing.isNotEmpty) {
        problems.add(
          '${room.label}: falta confirmar «${missing.map((c) => c.label).join('», «')}».',
        );
      }
    }
    return problems;
  }
}
