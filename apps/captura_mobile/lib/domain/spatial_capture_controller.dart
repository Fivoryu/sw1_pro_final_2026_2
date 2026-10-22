import 'package:flutter/foundation.dart';

import '../data/services/ar_capture_channel.dart';
import '../data/services/capture_draft_store.dart';
import '../data/services/staff_auth_failure.dart';
import '../data/services/staff_scene_api.dart';
import 'spatial/capture_upload_controller.dart';
import 'spatial/spatial.dart';
import 'staff_session_controller.dart';

/// Where the local capture stands against the server scene.
enum CaptureSyncState {
  /// Nothing captured yet.
  empty,

  /// Local changes not on the server yet.
  pending,
  syncing,
  synced,

  /// The server scene changed since the capture started; nothing was sent.
  conflict,

  /// The last attempt failed (network, rejection); the draft is intact.
  failed,
}

/// Owns the spatial capture of one listing in the capture app (F07).
///
/// Every change is written to the device first, so a capture survives app
/// restarts and lost connectivity. Sending is a conditional replace of the
/// listing scene: the capture remembers the server revision it is based on
/// and never overwrites a scene edited elsewhere without the agent's choice.
class SpatialCaptureController extends ChangeNotifier {
  SpatialCaptureController({
    required this.listingId,
    required StaffSessionController session,
    required StaffSceneApi sceneApi,
    required CaptureDraftStore store,
    required ArCapture ar,
    this.uploads,
    DateTime Function()? now,
  }) : _session = session,
       _sceneApi = sceneApi,
       _store = store,
       _ar = ar,
       _now = now ?? DateTime.now {
    uploads?.addListener(_notify);
  }

  static const String _noSessionMessage =
      'Tu cuenta no tiene una sesión activa. Volvé a ingresar.';

  final String listingId;

  /// Sends walkthrough capture packages for server-side reconstruction
  /// (F07.7); null when this build has no upload support. This controller
  /// owns it and disposes it.
  final CaptureUploadController? uploads;
  final StaffSessionController _session;
  final StaffSceneApi _sceneApi;
  final CaptureDraftStore _store;
  final ArCapture _ar;
  final DateTime Function() _now;

  late PropertyCapture _capture = PropertyCapture(
    listingId: listingId,
    rooms: const [],
    connections: const [],
    updatedAt: _now(),
  );
  CaptureSyncState _syncState = CaptureSyncState.empty;
  String? _baseEtag;
  String? _conflictEtag;
  DateTime? _lastSyncedAt;
  String? _message;
  bool _busy = false;
  bool _disposed = false;
  SceneBuildResult? _preview;

  List<CapturedRoom> get rooms => _capture.rooms;
  List<DoorConnection> get connections => _capture.connections;
  PropertyCapture get capture => _capture;
  CaptureSyncState get syncState => _syncState;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get message => _message;
  bool get busy => _busy;

  /// Scene document and warnings for the current rooms; null without rooms.
  SceneBuildResult? get preview => _preview;

  String? get ownerId => _session.account?.id;

  /// Checks ARCore only when the agent explicitly chooses automatic capture.
  Future<ArAvailability> arAvailability() => _ar.availability();

  @override
  void dispose() {
    _disposed = true;
    uploads?.removeListener(_notify);
    uploads?.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final owner = ownerId;
    if (owner == null) {
      _message = _noSessionMessage;
      _notify();
      return;
    }
    await uploads?.load();
    final stored = await _store.read(owner, listingId);
    if (stored != null) {
      try {
        _capture = PropertyCapture.fromJson(
          (stored['capture']! as Map).cast<String, Object?>(),
        );
        final sync = (stored['sync'] as Map?)?.cast<String, Object?>() ?? {};
        _baseEtag = sync['baseEtag'] as String?;
        final synced = sync['lastSyncedAt'];
        _lastSyncedAt = synced is String ? DateTime.tryParse(synced) : null;
        // A send interrupted by closing the app is simply pending again.
        _syncState = switch (sync['state']) {
          'synced' => CaptureSyncState.synced,
          'conflict' => CaptureSyncState.conflict,
          _ => CaptureSyncState.pending,
        };
        _conflictEtag = sync['conflictEtag'] as String?;
      } on Object {
        _message =
            'No pudimos leer la captura guardada en el teléfono. '
            'Podés empezar una nueva.';
      }
    }
    if (_capture.rooms.isEmpty && _syncState != CaptureSyncState.conflict) {
      _syncState = CaptureSyncState.empty;
    }
    _rebuild();
    _notify();
  }

  /// Opens the native capture. Returns a message for the agent: why no room
  /// was added, or, for a walkthrough, what the proposal is based on.
  Future<String?> captureRoom(
    String name, {
    CaptureMode mode = CaptureMode.walls,
  }) async {
    if (ownerId == null) return _noSessionMessage;
    final availability = await _ar.availability();
    if (availability == ArAvailability.unsupported) {
      return MethodChannelArCapture.messageFor('arcore_unavailable');
    }
    final result = await _ar.captureRoom(
      name,
      mode: mode,
      listingId: listingId,
    );
    switch (result) {
      case ArCaptureCancelled():
        return null;
      case ArCaptureFailed(:final message):
        return message;
      case ArCaptured(
        :final payload,
        :final capturePackage,
        :final packageProblem,
      ):
        var capture = payload;
        String? notice;
        final metrics = payload['metrics'];
        if (metrics is Map && metrics['method'] == 'walkthrough') {
          final ContourProposal proposal;
          try {
            proposal = proposeContour(
              WalkthroughObservations.fromJson(
                (payload['observations']! as Map).cast<String, Object?>(),
              ),
            );
          } on Object {
            return 'La captura llegó incompleta. Intentá de nuevo.';
          }
          switch (proposal) {
            case ProposalFailed(:final message):
              return message;
            case ProposedContour(
              :final corners,
              :final observedWalls,
              :final inferredEdges,
            ):
              capture = {
                ...payload,
                'corners': [for (final corner in corners) corner.toJson()],
              };
              notice =
                  'Contorno propuesto con $observedWalls paredes detectadas'
                  '${inferredEdges == 0 ? '' : ' y $inferredEdges ${inferredEdges == 1 ? 'lado inferido' : 'lados inferidos'} (sin pared observada)'}'
                  '. Revisalo y corregí la escala con una medida de referencia.';
          }
        }
        final CapturedRoom room;
        try {
          room = CapturedRoom.fromChannelResult(
            id: _newRoomId(),
            name: name,
            result: capture,
          );
        } on Object {
          // FormatException or TypeError: a malformed native payload.
          return 'La captura llegó incompleta. Intentá de nuevo.';
        }
        await _change(_capture.copyWith(rooms: [..._capture.rooms, room]));
        final reconstruction = await _handlePackage(
          capturePackage,
          packageProblem,
        );
        if (reconstruction == null) return notice;
        return notice == null ? reconstruction : '$notice $reconstruction';
    }
  }

  /// Adds a room whose real dimensions were measured and entered by hand.
  /// This path is deliberately independent from ARCore and reconstruction.
  Future<String?> createManualRectangularRoom({
    required String name,
    required double length,
    required double width,
    required double height,
  }) async {
    if (ownerId == null) return _noSessionMessage;
    final CapturedRoom room;
    try {
      room = buildManualRectangularRoom(
        id: _newRoomId(),
        name: name,
        length: length,
        width: width,
        height: height,
      );
    } on ArgumentError {
      return 'RevisÃ¡ las medidas: el ambiente debe tener al menos 1 mÂ², '
          'paredes de 30 cm o mÃ¡s y una altura mayor que cero.';
    }
    await _change(_capture.copyWith(rooms: [..._capture.rooms, room]));
    return null;
  }

  /// Hands the capture package to the upload queue and says what happens
  /// next, or why there is no package. Null when there is nothing to say.
  Future<String?> _handlePackage(
    CapturePackageInfo? package,
    String? problem,
  ) async {
    if (problem != null) {
      return 'No pudimos preparar el recorrido para la reconstrucción '
          'en el servidor ($problem) El contorno propuesto sigue disponible.';
    }
    final queue = uploads;
    if (package == null || queue == null) return null;
    await queue.enqueue(package);
    final rooms = package.rooms.length;
    final preview = rooms > 1
        ? ' Recorriste $rooms ambientes: el contorno de arriba es solo una '
              'vista previa, porque la reconstrucción los separa en el servidor.'
        : '';
    return 'El recorrido se sube para reconstruir el ambiente; seguí el '
        'estado más abajo.$preview';
  }

  String _newRoomId() {
    var index = _capture.rooms.length + 1;
    final used = {for (final room in _capture.rooms) room.id};
    while (used.contains('room-$index')) {
      index++;
    }
    return 'room-$index';
  }

  Future<void> updateRoom(CapturedRoom room) => _change(
    _capture.copyWith(
      rooms: [
        for (final current in _capture.rooms)
          current.id == room.id ? room : current,
      ],
    ),
  );

  Future<void> removeRoom(String roomId) => _change(
    _capture.copyWith(
      rooms: [
        for (final room in _capture.rooms)
          if (room.id != roomId) room,
      ],
      connections: [
        for (final connection in _capture.connections)
          if (connection.roomA != roomId && connection.roomB != roomId)
            connection,
      ],
    ),
  );

  /// Places room B so its door meets room A's door and records the link.
  Future<String?> connect({
    required String roomA,
    required String openingA,
    required String roomB,
    required String openingB,
  }) async {
    if (roomA == roomB) return 'Elegí dos ambientes distintos.';
    final fixed = _room(roomA);
    final moving = _room(roomB);
    if (fixed == null || moving == null) return 'El ambiente ya no existe.';
    final RoomPlacement placement;
    try {
      placement = placementForConnection(
        fixed: fixed,
        fixedOpeningId: openingA,
        moving: moving,
        movingOpeningId: openingB,
        wallThickness: _capture.wallThickness,
      );
    } on ArgumentError {
      return 'Elegí una puerta de cada ambiente.';
    }
    await _change(
      _capture.copyWith(
        rooms: [
          for (final room in _capture.rooms)
            room.id == roomB ? room.copyWith(placement: placement) : room,
        ],
        connections: [
          for (final connection in _capture.connections)
            if (connection.roomB != roomB) connection,
          DoorConnection(
            roomA: roomA,
            openingA: openingA,
            roomB: roomB,
            openingB: openingB,
          ),
        ],
      ),
    );
    return null;
  }

  Future<void> disconnect(DoorConnection connection) => _change(
    _capture.copyWith(
      connections: [
        for (final current in _capture.connections)
          if (current != connection) current,
      ],
    ),
  );

  CapturedRoom? _room(String id) {
    for (final room in _capture.rooms) {
      if (room.id == id) return room;
    }
    return null;
  }

  /// Problems that block sending, phrased for the agent; empty when sendable.
  List<String> blockingProblems() => [
    for (final room in _capture.rooms) ...[
      for (final issue in validateContour(room.corners))
        if (issue.blocking) '${room.name}: ${contourIssueMessage(issue)}',
      for (final opening in room.openings)
        for (final issue in validateOpening(room, opening))
          '${room.name}: ${openingIssueMessage(issue)}',
    ],
  ];

  /// Sends the capture as the listing scene over the remembered revision.
  Future<void> sync() async {
    if (_busy || _capture.rooms.isEmpty) return;
    if (_syncState == CaptureSyncState.synced) return;
    final problems = blockingProblems();
    if (problems.isNotEmpty) {
      _message = 'Corregí antes de enviar: ${problems.first}';
      _notify();
      return;
    }
    await _send(_baseEtag);
  }

  /// After a conflict, replaces the server scene with this capture.
  Future<void> overwriteRemote() async {
    if (_busy || _syncState != CaptureSyncState.conflict) return;
    var base = _conflictEtag;
    if (base == null) {
      final credentials = _credentials();
      if (credentials == null) return _fail(_noSessionMessage);
      try {
        final remote = await _sceneApi.fetch(
          accessToken: credentials.token,
          agencyId: credentials.agencyId,
          listingId: listingId,
        );
        base = remote is RemoteScene ? remote.etag : null;
      } on StaffAuthFailure catch (failure) {
        return _fail(failure.detail);
      }
    }
    await _send(base);
  }

  Future<void> _send(String? baseEtag) async {
    final credentials = _credentials();
    if (credentials == null) return _fail(_noSessionMessage);
    _busy = true;
    _syncState = CaptureSyncState.syncing;
    _message = null;
    _notify();
    try {
      final result = await _sceneApi.save(
        accessToken: credentials.token,
        agencyId: credentials.agencyId,
        listingId: listingId,
        document: _preview!.document,
        baseEtag: baseEtag,
      );
      switch (result) {
        case SceneSaved(:final etag):
          _baseEtag = etag;
          _conflictEtag = null;
          _lastSyncedAt = _now();
          _syncState = CaptureSyncState.synced;
        case SceneConflict(:final currentEtag):
          _conflictEtag = currentEtag;
          _syncState = CaptureSyncState.conflict;
          _message =
              'La escena de este inmueble cambió en el servidor (por ejemplo, '
              'desde el panel). Tu captura sigue guardada en el teléfono.';
      }
    } on StaffAuthFailure catch (failure) {
      _syncState = CaptureSyncState.failed;
      _message = failure.isNetworkFailure
          ? 'Sin conexión. Tu captura quedó guardada en el teléfono; '
                'reintentá cuando tengas red.'
          : failure.detail;
    } finally {
      _busy = false;
    }
    await _persist();
    _notify();
  }

  void _fail(String message) {
    _message = message;
    _notify();
  }

  /// Removes the local copy, only once the server confirmed it.
  Future<bool> clearLocal() async {
    final owner = ownerId;
    if (owner == null || _syncState != CaptureSyncState.synced) return false;
    await _store.delete(owner, listingId);
    _capture = _capture.copyWith(rooms: const [], connections: const []);
    _syncState = CaptureSyncState.empty;
    _rebuild();
    _notify();
    return true;
  }

  Future<int> storageBytes() async {
    final owner = ownerId;
    return owner == null ? 0 : _store.sizeBytes(owner);
  }

  Future<void> _change(PropertyCapture next) async {
    _capture = next.copyWith(updatedAt: _now());
    _syncState = _capture.rooms.isEmpty && _baseEtag == null
        ? CaptureSyncState.empty
        : CaptureSyncState.pending;
    _message = null;
    _rebuild();
    await _persist();
    _notify();
  }

  void _rebuild() {
    _preview = _capture.rooms.isEmpty ? null : buildScene(_sceneCapture());
  }

  /// What is sent: each room rescaled by its references (the captured
  /// geometry stays as observed), with door connections re-placed on the
  /// rescaled rooms so joined rooms stay joined.
  PropertyCapture _sceneCapture() {
    final rooms = {
      for (final room in _capture.rooms) room.id: correctedRoom(room),
    };
    for (final connection in _capture.connections) {
      final fixed = rooms[connection.roomA];
      final moving = rooms[connection.roomB];
      if (fixed == null || moving == null) continue;
      try {
        rooms[moving.id] = moving.copyWith(
          placement: placementForConnection(
            fixed: fixed,
            fixedOpeningId: connection.openingA,
            moving: moving,
            movingOpeningId: connection.openingB,
            wallThickness: _capture.wallThickness,
          ),
        );
      } on ArgumentError {
        // A door removed after connecting: the room keeps its last placement.
      }
    }
    return _capture.copyWith(
      rooms: [for (final room in _capture.rooms) rooms[room.id]!],
    );
  }

  Future<void> _persist() async {
    final owner = ownerId;
    if (owner == null) return;
    await _store.write(owner, listingId, {
      'capture': _capture.toJson(),
      'sync': {
        'state': switch (_syncState) {
          CaptureSyncState.synced => 'synced',
          CaptureSyncState.conflict => 'conflict',
          _ => 'pending',
        },
        'baseEtag': _baseEtag,
        'conflictEtag': _conflictEtag,
        'lastSyncedAt': _lastSyncedAt?.toIso8601String(),
      },
    });
  }

  ({String token, String agencyId})? _credentials() {
    final token = _session.accessToken;
    final agencyId = _session.account?.tenantId;
    if (token == null || agencyId == null) return null;
    return (token: token, agencyId: agencyId);
  }
}
