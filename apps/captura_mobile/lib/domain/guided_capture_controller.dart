import 'package:flutter/foundation.dart';

import '../data/services/guided_capture_store.dart';
import '../data/services/photo_source.dart';
import 'guided_capture/capture_checklist.dart';
import 'guided_capture/photo_quality.dart';
import 'listing_photos_controller.dart';
import 'staff_session_controller.dart';

/// Loading state of a listing's guided capture.
enum GuidedCaptureLoadState { loading, ready, failed }

/// Owns the guided capture of one listing (F14.2).
///
/// The rooms come from the listing card and the agent's additions; each
/// photo taken for a room is checked locally before it is uploaded, and only
/// photos that pass are assigned to the room. The checklist is stored on the
/// phone, per staff account and listing.
class GuidedCaptureController extends ChangeNotifier {
  GuidedCaptureController({
    required this.listingId,
    required StaffSessionController session,
    required GuidedCaptureStore store,
    required ListingPhotosController photos,
    PhotoAnalyzer analyzer = analyzePhotoBytes,
    this.rules = const PhotoQualityRules(),
    DateTime Function()? now,
  }) : _session = session,
       _store = store,
       _photos = photos,
       _analyzer = analyzer,
       _now = now ?? DateTime.now {
    _photos.addListener(_notify);
  }

  static const String _noSessionMessage =
      'Tu cuenta no tiene una sesión activa. Volvé a ingresar.';

  final String listingId;
  final StaffSessionController _session;
  final GuidedCaptureStore _store;
  final ListingPhotosController _photos;
  final PhotoAnalyzer _analyzer;
  final PhotoQualityRules rules;
  final DateTime Function() _now;

  GuidedCaptureLoadState _state = GuidedCaptureLoadState.loading;
  CaptureChecklist _checklist = const CaptureChecklist([]);
  final Map<String, String> _roomMessages = {};
  String? _busyRoom;
  String? _message;
  bool _disposed = false;

  GuidedCaptureLoadState get state => _state;
  CaptureChecklist get checklist => _checklist;
  ListingPhotosController get photos => _photos;

  /// Room whose photo is being checked or uploaded, if any.
  String? get busyRoom => _busyRoom;

  /// Notice of the last failure outside one room.
  String? get message => _message;

  /// Why the last photo for [roomId] was not accepted, if it was not.
  String? roomMessage(String roomId) => _roomMessages[roomId];

  Set<String> get _photoIds => {
    for (final photo in _photos.photos) photo.photoId,
  };

  RoomStatus statusOf(CaptureRoom room) =>
      CaptureChecklist.statusOf(room, _photoIds);

  List<String> photosOf(CaptureRoom room) =>
      CaptureChecklist.livePhotos(room, _photoIds);

  ({int finished, int total}) get progress => _checklist.progress(_photoIds);

  /// Why the listing cannot be sent to review yet; empty when it can.
  List<String> get problems {
    if (_state != GuidedCaptureLoadState.ready) {
      return const ['Completá la captura guiada antes de enviar a revisión.'];
    }
    return _checklist.problems(_photoIds);
  }

  bool get isComplete => problems.isEmpty;

  /// Reads the stored checklist and aligns its rooms with the listing card.
  Future<void> load({required int bedrooms, required int bathrooms}) async {
    _state = GuidedCaptureLoadState.loading;
    _message = null;
    _notify();
    final owner = _session.account?.id;
    if (owner == null) {
      _state = GuidedCaptureLoadState.failed;
      _message = _noSessionMessage;
      _notify();
      return;
    }
    CaptureChecklist? stored;
    try {
      final json = await _store.read(owner, listingId);
      stored = json == null ? null : CaptureChecklist.fromJson(json);
    } on FormatException {
      stored = null; // An unreadable checklist starts over.
    } on ArgumentError {
      stored = null;
    } on TypeError {
      stored = null;
    } on Exception {
      _state = GuidedCaptureLoadState.failed;
      _message = 'No pudimos leer la captura guiada guardada en el teléfono.';
      _notify();
      return;
    }
    _checklist = CaptureChecklist.derive(
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      previous: stored,
    );
    _state = GuidedCaptureLoadState.ready;
    _notify();
    await _save();
  }

  /// Re-derives the rooms after the listing card changed its counts.
  Future<void> updateCounts({
    required int bedrooms,
    required int bathrooms,
  }) async {
    if (_state != GuidedCaptureLoadState.ready) return;
    _checklist = CaptureChecklist.derive(
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      previous: _checklist,
    );
    _notify();
    await _save();
  }

  Future<void> toggleCheck(CaptureRoom room, RoomCheck check) async {
    final current = _room(room.id);
    if (current == null) return;
    final checks = {...current.checks};
    if (!checks.remove(check)) checks.add(check);
    await _update(current.copyWith(checks: checks));
  }

  /// Marks [room] as not applying to this listing, with [reason].
  Future<void> skip(CaptureRoom room, String reason) async {
    final current = _room(room.id);
    final trimmed = reason.trim();
    if (current == null || trimmed.isEmpty) return;
    await _update(current.copyWith(skippedReason: () => trimmed));
  }

  Future<void> unskip(CaptureRoom room) async {
    final current = _room(room.id);
    if (current == null) return;
    await _update(current.copyWith(skippedReason: () => null));
  }

  /// Adds a room the card does not derive, such as a balcony or a patio.
  Future<void> addExtraRoom(String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty || _state != GuidedCaptureLoadState.ready) return;
    final room = CaptureRoom(
      id: 'extra-${_now().microsecondsSinceEpoch}',
      kind: RoomKind.extra,
      label: trimmed,
    );
    _checklist = CaptureChecklist([..._checklist.rooms, room]);
    _notify();
    await _save();
  }

  /// Removes an added room; derived rooms can only be skipped.
  Future<void> removeExtraRoom(CaptureRoom room) async {
    if (room.kind != RoomKind.extra) return;
    _checklist = CaptureChecklist([
      for (final item in _checklist.rooms)
        if (item.id != room.id) item,
    ]);
    _roomMessages.remove(room.id);
    _notify();
    await _save();
  }

  /// Takes a photo for [room], checks its quality and uploads it only when
  /// it passes. Returns true when the photo was added to the room.
  Future<bool> capture(CaptureRoom room, PhotoOrigin origin) async {
    if (_busyRoom != null || _room(room.id) == null) return false;
    _busyRoom = room.id;
    _roomMessages.remove(room.id);
    _notify();
    try {
      final picked = await _photos.pick(origin);
      if (picked == null) {
        final failure = _photos.message;
        if (failure != null) _roomMessages[room.id] = failure;
        return false;
      }
      final PhotoMeasurements measured;
      try {
        measured = await _analyzer(picked.bytes);
      } on PhotoAnalysisFailure {
        _roomMessages[room.id] =
            'No pudimos analizar la calidad de esta foto en el teléfono. '
            'Probá con la cámara o con una foto JPG o PNG.';
        return false;
      }
      final reasons = assessPhoto(measured, rules);
      if (reasons.isNotEmpty) {
        _roomMessages[room.id] = reasons.join('\n');
        return false;
      }
      final photo = await _photos.upload(picked);
      if (photo == null) {
        _roomMessages[room.id] =
            'La foto pasó la validación pero no se pudo subir. Reintentá.';
        return false;
      }
      final current = _room(room.id);
      if (current == null) return false;
      await _update(
        current.copyWith(photoIds: [...current.photoIds, photo.photoId]),
      );
      return true;
    } finally {
      _busyRoom = null;
      _notify();
    }
  }

  CaptureRoom? _room(String id) {
    for (final room in _checklist.rooms) {
      if (room.id == id) return room;
    }
    return null;
  }

  Future<void> _update(CaptureRoom room) async {
    _checklist = _checklist.replace(room);
    _notify();
    await _save();
  }

  Future<void> _save() async {
    final owner = _session.account?.id;
    if (owner == null) return;
    try {
      await _store.write(owner, listingId, _checklist.toJson());
      if (_message != null) {
        _message = null;
        _notify();
      }
    } on Exception {
      _message = 'No pudimos guardar la captura guiada en el teléfono.';
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _photos.removeListener(_notify);
    super.dispose();
  }
}
