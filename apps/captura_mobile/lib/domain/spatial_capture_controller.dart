import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/services/ar_capture_channel.dart';
import '../data/services/capture_draft_store.dart';
import '../data/services/photo_source.dart';
import '../data/services/staff_auth_failure.dart';
import '../data/services/staff_scene_api.dart';
import '../data/services/staff_floorplan_interpretation_api.dart';
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
    PhotoSource? traceSource,
    FloorplanInterpretationApi? floorplanInterpreter,
    this.uploads,
    DateTime Function()? now,
  }) : _session = session,
       _sceneApi = sceneApi,
       _store = store,
       _ar = ar,
       _traceSource = traceSource,
       _floorplanInterpreter = floorplanInterpreter,
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
  final PhotoSource? _traceSource;
  final FloorplanInterpretationApi? _floorplanInterpreter;
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
  final Map<String, FloorplanTraceMetadata> _traces = {};

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
  bool get supportsFloorplanInterpretation => _floorplanInterpreter != null;
  FloorplanTraceMetadata? traceForRoom(String roomId) {
    final trace = _traces[roomId];
    if (trace == null || trace.visualDraft != null) return trace;
    final ownerId = trace.documentOwnerRoomId;
    final document = ownerId == null ? null : _traces[ownerId]?.visualDraft;
    return document == null ? trace : trace.withResolvedVisualDraft(document);
  }

  /// Checks ARCore only when the agent explicitly chooses automatic capture.
  Future<ArAvailability> arAvailability() => _ar.availability();

  Future<FloorplanInterpretationResult?> interpretFloorplan({
    required List<int> imageBytes,
    required String contentType,
  }) async {
    final api = _floorplanInterpreter;
    final credentials = _credentials();
    if (api == null || credentials == null) return null;
    return api.interpret(
      accessToken: credentials.token,
      agencyId: credentials.agencyId,
      listingId: listingId,
      imageBytes: imageBytes,
      contentType: contentType,
    );
  }

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
        final traces = stored['traces'];
        if (traces is List) {
          for (final value in traces) {
            try {
              final trace = FloorplanTraceMetadata.fromJson(
                (value as Map).cast<String, Object?>(),
              );
              _traces[trace.roomId] = trace;
            } on Object {
              // A damaged local tracing aid must not invalidate metric rooms.
            }
          }
        }
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

  Future<String?> createManualLRoom({
    required String name,
    required double totalWidth,
    required double totalDepth,
    required double recessWidth,
    required double recessDepth,
    required double height,
    required RecessCorner recess,
  }) async {
    if (ownerId == null) return _noSessionMessage;
    try {
      final room = buildManualLRoom(
        id: _newRoomId(),
        name: name,
        totalWidth: totalWidth,
        totalDepth: totalDepth,
        recessWidth: recessWidth,
        recessDepth: recessDepth,
        height: height,
        recess: recess,
      );
      await _change(_capture.copyWith(rooms: [..._capture.rooms, room]));
      return null;
    } on ArgumentError {
      return 'Revisá las medidas y el recorte del ambiente en L.';
    }
  }

  Future<String?> createCalibratedManualSketchRoom({
    required String name,
    required List<FloorPoint> sketch,
    required int referenceEdge,
    required double referenceMeters,
    required double height,
  }) async {
    if (ownerId == null) return _noSessionMessage;
    try {
      final room = buildCalibratedManualSketchRoom(
        id: _newRoomId(),
        name: name,
        sketch: sketch,
        referenceEdge: referenceEdge,
        referenceMeters: referenceMeters,
        height: height,
      );
      await _change(_capture.copyWith(rooms: [..._capture.rooms, room]));
      return null;
    } on ArgumentError {
      return 'Revisá el contorno y la medida real usada para calibrarlo.';
    }
  }

  Future<String?> createWallBasedManualSketchRoom({
    required String name,
    required List<FloorPoint> sketch,
    required double height,
    List<ReferenceMeasurement> measurements = const [],
  }) async {
    if (ownerId == null) return _noSessionMessage;
    try {
      var room = buildWallBasedManualSketchRoom(
        id: _newRoomId(),
        name: name,
        sketch: sketch,
        height: height,
      );
      room = room.copyWith(references: measurements);
      final fitted = fitConfirmedWallLengths(room);
      if (!fitted.isCoherent) return fitted.message;
      room = room.copyWith(corners: fitted.corners);
      await _change(_capture.copyWith(rooms: [..._capture.rooms, room]));
      return null;
    } on ArgumentError {
      return 'Revisá el contorno y la altura del ambiente.';
    }
  }

  Future<LocalTraceSource?> pickFloorplanSource() async {
    final owner = ownerId;
    final picker = _traceSource;
    if (owner == null || picker == null) return null;
    final picked = await picker.pick(PhotoOrigin.gallery);
    if (picked == null) return null;
    if (!const {
      'image/jpeg',
      'image/png',
      'image/webp',
    }.contains(picked.contentType)) {
      throw const UnsupportedPhotoFormat();
    }
    final sourceId = await _store.saveTraceSource(
      owner,
      listingId,
      picked.bytes,
      picked.contentType,
    );
    return LocalTraceSource(
      sourceId: sourceId,
      contentType: picked.contentType,
      bytes: picked.bytes,
    );
  }

  Future<void> discardFloorplanSource(String sourceId) async {
    final owner = ownerId;
    if (owner != null) {
      await _store.deleteTraceSource(owner, listingId, sourceId);
    }
  }

  Future<List<int>?> floorplanSourceBytes(String sourceId) async {
    final owner = ownerId;
    return owner == null
        ? null
        : _store.readTraceSource(owner, listingId, sourceId);
  }

  Future<String?> saveFloorplanTrace({
    String? roomId,
    required String name,
    required String sourceId,
    required String contentType,
    required int imageWidth,
    required int imageHeight,
    required List<FloorPoint> normalizedTrace,
    int? referenceEdge,
    double? referenceMeters,
    List<ReferenceMeasurement> measurements = const [],
    List<FloorplanTraceOpening> openings = const [],
    FloorplanVisualDraft? visualDraft,
    double? height,
  }) async {
    if (ownerId == null) return _noSessionMessage;
    if (await floorplanSourceBytes(sourceId) == null) {
      return 'La imagen original ya no está disponible.';
    }
    final previous = roomId == null ? null : _room(roomId);
    final previousTrace = roomId == null ? null : _traces[roomId];
    final geometryChanged =
        previousTrace == null ||
        previousTrace.vertices.length != normalizedTrace.length ||
        Iterable<int>.generate(normalizedTrace.length).any(
          (index) =>
              previousTrace.vertices[index].distanceTo(normalizedTrace[index]) >
              1e-9,
        );
    if (previous != null &&
        geometryChanged &&
        (previous.openings.isNotEmpty ||
            previous.boxes.isNotEmpty ||
            (previous.references.isNotEmpty &&
                previousTrace != null &&
                previousTrace.vertices.length != normalizedTrace.length) ||
            previous.placement != RoomPlacement.identity)) {
      return 'Este ambiente contiene datos espaciales vinculados a la '
          'geometría actual. Corregí o eliminá esos elementos antes de volver '
          'a trazar el ambiente.';
    }
    final id = previous?.id ?? _newRoomId();
    try {
      final legacy =
          previous?.measurementMode == RoomMeasurementMode.legacyUniform;
      if (visualDraft != null && visualDraft.rooms.length > 1) {
        return _saveMultiroomFloorplan(
          editedRoomId: roomId,
          fallbackRoomId: id,
          fallbackName: name,
          sourceId: sourceId,
          contentType: contentType,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          document: visualDraft,
          height: height,
        );
      }
      if (previousTrace?.draftProblem != null && visualDraft == null) {
        return 'El documento visual guardado no se pudo leer. Volvé a '
            'trazar el ambiente para reemplazarlo.';
      }
      // The visual document is the authority whenever the caller supplies it.
      // Legacy parameters are only imported for evidence the document does not
      // already own, so neither collection can compete with the other.
      var document = visualDraft?.rekeySingleRoom(id);
      if (document != null) {
        document = _importLegacyEvidence(
          document,
          roomId: id,
          measurements: measurements,
          openings: openings,
        );
        if (document.validate().isNotEmpty) {
          return 'El documento visual contiene relaciones o geometría inválidas.';
        }
      }
      final editorTrace = document?.contourForRoom(id);
      if (document != null && editorTrace == null) {
        return 'No pudimos derivar el perímetro del documento visual.';
      }
      final traceForRoom = editorTrace ?? normalizedTrace;
      final projectedWallDimensions = document == null
          ? const <CapturedWallDimension>[]
          : [
              for (final wallId in document.wallIdsForRoom(id))
                if (document.authoritativeWallLength(wallId) case final length?)
                  if (document.authoritativeWallHeight(wallId)
                      case final wallHeight?)
                    CapturedWallDimension(
                      wallId: wallId,
                      lengthM: length.meters,
                      heightM: wallHeight.meters,
                    ),
            ];
      final hasCompleteWallDimensions =
          document != null &&
          projectedWallDimensions.length == document.wallIdsForRoom(id).length;
      if (legacy && height == null) {
        return 'La captura heredada requiere una altura general válida.';
      }
      if (!legacy && !hasCompleteWallDimensions && height == null) {
        return 'Completá el largo y alto de cada pared antes de continuar.';
      }
      final traceOpenings = document == null
          ? openings
          : _openingsFromDocument(document, id);
      var room = legacy
          ? buildCalibratedFloorplanTraceRoom(
              id: id,
              name: name,
              normalizedTrace: traceForRoom,
              imageWidth: imageWidth,
              imageHeight: imageHeight,
              referenceEdge: referenceEdge ?? previousTrace!.referenceEdge!,
              referenceMeters:
                  referenceMeters ?? previousTrace!.referenceMeters!,
              height: height!,
            )
          : buildWallBasedFloorplanRoom(
              id: id,
              name: name,
              normalizedTrace: traceForRoom,
              imageWidth: imageWidth,
              imageHeight: imageHeight,
              height: hasCompleteWallDimensions ? null : height,
              wallDimensions: hasCompleteWallDimensions
                  ? projectedWallDimensions
                  : const [],
            );
      if (!legacy) {
        // Compatibility projection: the canonical room keeps receiving one
        // reference per edge, but they are derived from the document.
        room = room.copyWith(
          wallDimensions: hasCompleteWallDimensions
              ? projectedWallDimensions
              : const [],
          clearHeight: hasCompleteWallDimensions,
          references: document == null
              ? measurements
              : _measurementsFromDocument(
                  document,
                  roomId: id,
                  contour: traceForRoom,
                  imageWidth: imageWidth,
                  imageHeight: imageHeight,
                ),
        );
        if (document != null) {
          final canonicalOpenings = <RoomOpening>[];
          for (final opening in document.openings) {
            final wallId = opening.wallId;
            final length = wallId == null
                ? null
                : document.authoritativeWallLength(wallId);
            final width = opening.widthM;
            final openingHeight = opening.heightM;
            final offset = opening.offsetFromWallStartM;
            final edge = wallId == null
                ? null
                : document.edgeIndexForWall(id, wallId);
            if (length == null ||
                width == null ||
                openingHeight == null ||
                offset == null ||
                edge == null ||
                opening.type == VisualOpeningType.unknown ||
                (opening.type == VisualOpeningType.window &&
                    opening.sillHeightM == null)) {
              continue;
            }
            canonicalOpenings.add(
              RoomOpening(
                id: opening.id,
                edgeIndex: edge,
                wallId: wallId,
                offsetFromWallStartM: offset,
                position: (offset + width / 2) / length.meters,
                width: width,
                height: openingHeight,
                type: opening.type == VisualOpeningType.door
                    ? OpeningType.door
                    : OpeningType.window,
                sillHeight: opening.type == VisualOpeningType.door
                    ? 0
                    : opening.sillHeightM,
              ),
            );
          }
          room = room.copyWith(openings: canonicalOpenings);
        }
        if (hasContradictoryConfirmedWallLengths(room)) {
          return 'Las medidas ingresadas no permiten cerrar el ambiente. Revisá las paredes marcadas.';
        }
      }
      final replacedSourceId = _traces[id]?.sourceId;
      await _change(
        _capture.copyWith(
          rooms: previous == null
              ? [..._capture.rooms, room]
              : [
                  for (final current in _capture.rooms)
                    current.id == id ? room : current,
                ],
        ),
        traces: {
          ..._traces,
          id: FloorplanTraceMetadata(
            roomId: id,
            sourceId: sourceId,
            contentType: contentType,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            vertices: [...traceForRoom],
            referenceEdge: referenceEdge,
            referenceMeters: referenceMeters,
            openings: [...traceOpenings],
            visualDraft: document,
          ),
        },
      );
      // The previous image outlives the replacement until the new state is
      // safely on disk, and it is only dropped when nothing references it.
      if (replacedSourceId != null &&
          replacedSourceId != sourceId &&
          !_referencesSource(replacedSourceId)) {
        await discardFloorplanSource(replacedSourceId);
      }
      return null;
    } on ArgumentError {
      return 'Revisá el trazado, la medida real y la altura del ambiente.';
    }
  }

  String _documentOwnerOf(FloorplanTraceMetadata trace) =>
      trace.documentOwnerRoomId ?? trace.roomId;

  double _floorplanDocumentScale(
    FloorplanVisualDraft document,
    int imageWidth,
    int imageHeight,
  ) {
    var longest = 0.0;
    for (final wall in document.walls) {
      final start = FloorPoint(
        wall.start.x * imageWidth,
        wall.start.z * imageHeight,
      );
      final end = FloorPoint(wall.end.x * imageWidth, wall.end.z * imageHeight);
      longest = math.max(longest, start.distanceTo(end));
    }
    if (!longest.isFinite || longest <= 1e-9) {
      throw ArgumentError('Invalid floorplan document scale');
    }
    // Shape-prior previews intentionally remain approximate. A single scale
    // for the whole document preserves relative room placement without
    // promoting image geometry to authoritative metric evidence.
    return 4 / longest;
  }

  ({List<FloorPoint> corners, RoomPlacement placement})
  _floorplanProjectionFrame({
    required List<FloorPoint> contour,
    required int imageWidth,
    required int imageHeight,
    required double scale,
  }) {
    final raw = [
      for (final point in contour)
        FloorPoint(point.x * imageWidth, point.z * imageHeight),
    ];
    if (raw.length < 3) throw ArgumentError('Invalid floorplan room contour');
    final ordered = signedArea(raw) < 0
        ? [raw.first, ...raw.skip(1).toList().reversed]
        : raw;
    final origin = ordered.first;
    final first = ordered[1] - origin;
    if (first.length <= 1e-9) {
      throw ArgumentError('Invalid floorplan room first edge');
    }
    final angle = math.atan2(first.z, first.x);
    final local = [
      for (final point in ordered) (point - origin).rotate(-angle).scale(scale),
    ];
    return (
      corners: local,
      placement: RoomPlacement(
        x: origin.x * scale,
        z: origin.z * scale,
        rotationDegrees: angle * 180 / math.pi,
      ),
    );
  }

  FloorplanVisualDraft _withoutVisualRoom(
    FloorplanVisualDraft document,
    String visualRoomId,
  ) {
    final rooms = [
      for (final room in document.rooms)
        if (room.id != visualRoomId) room,
    ];
    final roomIds = {for (final room in rooms) room.id};
    final walls = <VisualWallSegment>[];
    final keptWallIds = <String>{};
    for (final wall in document.walls) {
      final memberships = [
        for (final roomId in wall.roomIds)
          if (roomIds.contains(roomId)) roomId,
      ];
      if (memberships.isEmpty) continue;
      walls.add(
        VisualWallSegment(
          id: wall.id,
          start: wall.start,
          end: wall.end,
          roomIds: memberships,
          manuallyEdited: wall.manuallyEdited,
        ),
      );
      keptWallIds.add(wall.id);
    }
    return document.copyWith(
      walls: walls,
      rooms: rooms,
      openings: [
        for (final opening in document.openings)
          if (opening.wallId == null || keptWallIds.contains(opening.wallId))
            opening,
      ],
      measurements: [
        for (final measurement in document.measurements)
          if (measurement.wallId == null ||
              keptWallIds.contains(measurement.wallId))
            measurement,
      ],
    );
  }

  Future<String?> _saveMultiroomFloorplan({
    required String? editedRoomId,
    required String fallbackRoomId,
    required String fallbackName,
    required String sourceId,
    required String contentType,
    required int imageWidth,
    required int imageHeight,
    required FloorplanVisualDraft document,
    required double? height,
  }) async {
    final errors = document.validate();
    if (errors.isNotEmpty) {
      return 'El documento visual contiene relaciones o geometrÃ­a invÃ¡lidas.';
    }

    final editedTrace = editedRoomId == null ? null : _traces[editedRoomId];
    final ownerId = editedTrace == null
        ? fallbackRoomId
        : _documentOwnerOf(editedTrace);
    final groupTraces = <FloorplanTraceMetadata>[
      for (final trace in _traces.values)
        if (_documentOwnerOf(trace) == ownerId) trace,
    ];
    final existingByRegion = {
      for (final trace in groupTraces)
        if (trace.visualRoomId != null) trace.visualRoomId!: trace,
    };
    final usedRoomIds = {for (final room in _capture.rooms) room.id};
    for (final trace in groupTraces) {
      usedRoomIds.remove(trace.roomId);
    }

    String allocateRoomId() {
      var index = _capture.rooms.length + 1;
      while (usedRoomIds.contains('room-$index')) index++;
      final value = 'room-$index';
      usedRoomIds.add(value);
      return value;
    }

    final projectionIds = <String, String>{};
    for (final (index, region) in document.rooms.indexed) {
      final existing = existingByRegion[region.id]?.roomId;
      final projectionId =
          existing ??
          (index == 0 && !usedRoomIds.contains(ownerId)
              ? ownerId
              : allocateRoomId());
      projectionIds[region.id] = projectionId;
      usedRoomIds.add(projectionId);
    }

    final resultingProjectionIds = projectionIds.values.toSet();
    final canonicalOwnerId = resultingProjectionIds.contains(ownerId)
        ? ownerId
        : resultingProjectionIds.first;
    final documentScale = _floorplanDocumentScale(
      document,
      imageWidth,
      imageHeight,
    );

    final projectedRooms = <CapturedRoom>[];
    final projectedTraces = <String, FloorplanTraceMetadata>{};
    for (final (index, region) in document.rooms.indexed) {
      final projectionId = projectionIds[region.id]!;
      final contour = document.contourForRoom(region.id);
      if (contour == null) {
        return 'No pudimos derivar el perÃ­metro de uno de los ambientes.';
      }
      final wallIds = document.wallIdsForRoom(region.id);
      final wallDimensions = <CapturedWallDimension>[
        for (final wallId in wallIds)
          if (document.authoritativeWallLength(wallId) case final length?)
            if (document.authoritativeWallHeight(wallId) case final wallHeight?)
              CapturedWallDimension(
                wallId: wallId,
                lengthM: length.meters,
                heightM: wallHeight.meters,
              ),
      ];
      final complete = wallDimensions.length == wallIds.length;
      if (!complete && height == null) {
        return 'CompletÃ¡ el largo y alto de cada pared antes de continuar.';
      }
      final previousRoom = _room(projectionId);
      final regionName = region.name?.trim();
      final roomName = regionName != null && regionName.isNotEmpty
          ? regionName
          : previousRoom?.name ??
                (index == 0 && fallbackName.trim().isNotEmpty
                    ? fallbackName.trim()
                    : 'Ambiente ${index + 1}');
      final frame = _floorplanProjectionFrame(
        contour: contour,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        scale: documentScale,
      );
      final preservedPlacement =
          previousRoom != null &&
              previousRoom.placement != RoomPlacement.identity
          ? previousRoom.placement
          : frame.placement;
      var room =
          buildWallBasedFloorplanRoom(
            id: projectionId,
            name: roomName,
            normalizedTrace: contour,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            height: complete ? null : height,
            wallDimensions: complete ? wallDimensions : const [],
          ).copyWith(
            corners: frame.corners,
            references: _measurementsFromDocument(
              document,
              roomId: region.id,
              contour: contour,
              imageWidth: imageWidth,
              imageHeight: imageHeight,
            ),
            placement: preservedPlacement,
            boxes: previousRoom?.boxes,
          );
      room = room.copyWith(
        openings: _canonicalOpeningsForRoom(document, region.id),
      );
      if (hasContradictoryConfirmedWallLengths(room)) {
        return 'Las medidas ingresadas no permiten cerrar el ambiente. RevisÃ¡ las paredes marcadas.';
      }
      projectedRooms.add(room);
      projectedTraces[projectionId] = FloorplanTraceMetadata(
        roomId: projectionId,
        visualRoomId: region.id,
        documentOwnerRoomId: canonicalOwnerId,
        sourceId: sourceId,
        contentType: contentType,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        vertices: contour,
        openings: _openingsFromDocument(document, region.id),
        visualDraft: projectionId == canonicalOwnerId ? document : null,
      );
    }

    final previousSourceIds = {for (final trace in groupTraces) trace.sourceId};
    final groupRoomIds = {for (final trace in groupTraces) trace.roomId};
    final removedProjectionIds = groupRoomIds.difference(
      resultingProjectionIds,
    );
    await _change(
      _capture.copyWith(
        rooms: [
          for (final room in _capture.rooms)
            if (!groupRoomIds.contains(room.id)) room,
          ...projectedRooms,
        ],
        connections: [
          for (final connection in _capture.connections)
            if (!removedProjectionIds.contains(connection.roomA) &&
                !removedProjectionIds.contains(connection.roomB))
              connection,
        ],
      ),
      traces: {
        for (final entry in _traces.entries)
          if (!groupRoomIds.contains(entry.key)) entry.key: entry.value,
        ...projectedTraces,
      },
    );
    debugPrint(
      '[RoomForge][MultiroomConfirm] canonicalRooms=${document.rooms.length} '
      'physicalWalls=${document.walls.length} openings=${document.openings.length} '
      'projectedRooms=${projectedRooms.length} owner=$canonicalOwnerId',
    );
    for (final previousSourceId in previousSourceIds) {
      if (previousSourceId != sourceId &&
          !_referencesSource(previousSourceId)) {
        await discardFloorplanSource(previousSourceId);
      }
    }
    return null;
  }

  List<RoomOpening> _canonicalOpeningsForRoom(
    FloorplanVisualDraft document,
    String visualRoomId,
  ) {
    final wallIds = document.wallIdsForRoom(visualRoomId).toSet();
    return [
      for (final opening in document.openings)
        if (opening.wallId case final wallId? when wallIds.contains(wallId))
          if (document.authoritativeWallLength(wallId) case final length?)
            if (opening.widthM case final width?)
              if (opening.heightM case final openingHeight?)
                if (opening.offsetFromWallStartM case final offset?)
                  if (document.edgeIndexForWall(visualRoomId, wallId)
                      case final edge?)
                    if (opening.type != VisualOpeningType.unknown &&
                        (opening.type != VisualOpeningType.window ||
                            opening.sillHeightM != null))
                      RoomOpening(
                        id: opening.id,
                        edgeIndex: edge,
                        wallId: wallId,
                        offsetFromWallStartM: offset,
                        position: (offset + width / 2) / length.meters,
                        width: width,
                        height: openingHeight,
                        type: opening.type == VisualOpeningType.door
                            ? OpeningType.door
                            : OpeningType.window,
                        sillHeight: opening.type == VisualOpeningType.door
                            ? 0
                            : opening.sillHeightM,
                      ),
    ];
  }

  /// Imports legacy parameters only where the document owns no evidence yet.
  /// Derived measurements stay derived and are never persisted as evidence.
  FloorplanVisualDraft _importLegacyEvidence(
    FloorplanVisualDraft document, {
    required String roomId,
    required List<ReferenceMeasurement> measurements,
    required List<FloorplanTraceOpening> openings,
  }) {
    final wallIds = document.wallIdsForRoom(roomId);
    var imported = document;
    if (imported.openings.isEmpty) {
      for (final (index, opening) in openings.indexed) {
        final edge = opening.edgeIndex;
        imported = imported.withOpening(
          VisualOpeningDraft(
            id: '$roomId:opening:$index',
            type: switch (opening.type) {
              FloorplanTraceOpeningType.door => VisualOpeningType.door,
              FloorplanTraceOpeningType.window => VisualOpeningType.window,
              FloorplanTraceOpeningType.unknown => VisualOpeningType.unknown,
            },
            wallId: edge == null || edge < 0 || edge >= wallIds.length
                ? null
                : wallIds[edge],
            position: opening.position,
            normalizedWidth: opening.normalizedWidth,
            manuallyPlaced: opening.manuallyPlaced,
            confidence: opening.confidence,
          ),
        );
      }
    }
    for (final (index, measurement) in measurements.indexed) {
      if (measurement.provenance == WallMeasurementProvenance.derivedScale ||
          measurement.provenance == WallMeasurementProvenance.derivedGeometry ||
          !measurement.referenceMeters.isFinite ||
          measurement.referenceMeters <= 0) {
        continue;
      }
      final edge = measurement.edgeIndex;
      final wallId = edge >= 0 && edge < wallIds.length ? wallIds[edge] : null;
      if (wallId != null && imported.hasMeasurementForWall(wallId)) continue;
      imported = imported.withMeasurement(
        VisualWallMeasurementEvidence(
          id: '$roomId:measurement:$index',
          wallId: wallId,
          meters: measurement.referenceMeters,
          provenance: measurement.provenance.wire,
          requiresReview:
              wallId == null ||
              measurement.provenance != WallMeasurementProvenance.user,
        ),
      );
    }
    return imported;
  }

  /// Compatibility projection: persisted openings remain keyed by [wallId],
  /// the legacy edge index is derived from the room traversal.
  List<FloorplanTraceOpening> _openingsFromDocument(
    FloorplanVisualDraft document,
    String roomId,
  ) => [
    for (final opening in document.openings)
      FloorplanTraceOpening(
        edgeIndex: opening.wallId == null
            ? null
            : document.edgeIndexForWall(roomId, opening.wallId!),
        type: switch (opening.type) {
          VisualOpeningType.door => FloorplanTraceOpeningType.door,
          VisualOpeningType.window => FloorplanTraceOpeningType.window,
          VisualOpeningType.unknown => FloorplanTraceOpeningType.unknown,
        },
        position: opening.position,
        normalizedWidth: opening.normalizedWidth,
        confidence: opening.confidence,
        manuallyPlaced: opening.manuallyPlaced,
      ),
  ];

  /// Compatibility projection: adapts the document's stable wall IDs to the
  /// edge-indexed solver API. Only evidence the user explicitly accepted is
  /// eligible to establish authoritative scale; pending provider detections
  /// stay in the document as reviewable evidence. Derived values only live in
  /// this projection.
  List<ReferenceMeasurement> _measurementsFromDocument(
    FloorplanVisualDraft document, {
    required String roomId,
    required List<FloorPoint> contour,
    required int imageWidth,
    required int imageHeight,
  }) {
    final evidence = <ReferenceMeasurement>[
      // Heights are physical evidence for a wall, but never horizontal
      // references. The legacy metric solver only accepts wall lengths.
      for (final measurement in document.authoritativeLengthMeasurements)
        if (document.edgeIndexForWall(roomId, measurement.wallId!)
            case final edge?)
          ReferenceMeasurement(
            edgeIndex: edge,
            referenceMeters: measurement.meters,
            provenance: WallMeasurementProvenance.fromWire(
              measurement.provenance,
            ),
          ),
    ];
    return solveFloorplanMetrics(
      semanticContour: [
        for (final point in contour)
          FloorPoint(point.x * imageWidth, point.z * imageHeight),
      ],
      existingMeasurements: evidence,
    ).measurements;
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

  Future<void> removeRoom(String roomId) async {
    final trace = _traces[roomId];
    final resolved = traceForRoom(roomId);
    final visualRoomId = trace?.visualRoomId;
    final document = resolved?.visualDraft;

    // A floorplan room card is a projection of one canonical room region.
    // Removing one card therefore removes only that region from the shared
    // visual document, then reconciles every surviving projection atomically.
    if (trace != null &&
        visualRoomId != null &&
        document != null &&
        document.rooms.length > 1) {
      final nextDocument = _withoutVisualRoom(document, visualRoomId);
      FloorplanTraceMetadata? survivorTrace;
      for (final candidate in _traces.values) {
        final candidateRoomId = candidate.visualRoomId;
        if (_documentOwnerOf(candidate) == _documentOwnerOf(trace) &&
            candidateRoomId != null &&
            candidateRoomId != visualRoomId &&
            nextDocument.room(candidateRoomId) != null) {
          survivorTrace = candidate;
          break;
        }
      }
      final survivor = survivorTrace;
      if (survivor != null) {
        final survivorRoom = _room(survivor.roomId);
        final message = await _saveMultiroomFloorplan(
          editedRoomId: survivor.roomId,
          fallbackRoomId: survivor.roomId,
          fallbackName: survivorRoom?.name ?? 'Ambiente',
          sourceId: survivor.sourceId,
          contentType: survivor.contentType,
          imageWidth: survivor.imageWidth,
          imageHeight: survivor.imageHeight,
          document: nextDocument,
          height: survivorRoom?.height?.value,
        );
        if (message != null) _fail(message);
        return;
      }
    }

    await _change(
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
      traces: {
        for (final entry in _traces.entries)
          if (entry.key != roomId) entry.key: entry.value,
      },
    );
    // The image is only removed once the room is gone for good, and only if no
    // other local trace still points at it.
    if (trace != null && !_referencesSource(trace.sourceId)) {
      await discardFloorplanSource(trace.sourceId);
    }
  }

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
      if (const {
            RoomAcquisitionMethod.manual,
            RoomAcquisitionMethod.manualSketch,
            RoomAcquisitionMethod.floorplanTrace,
          }.contains(room.acquisition.method) &&
          room.measurementMode == RoomMeasurementMode.wallConstraints &&
          hasContradictoryConfirmedWallLengths(room))
        '${room.name}: Las medidas ingresadas no permiten cerrar el ambiente. Revisá las paredes marcadas.',
      if (!hasCompleteWallMeasurements(room))
        '${room.name}: faltan medidas por confirmar en una o más paredes.',
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
    final problems = blockingProblems();
    if (problems.isNotEmpty) {
      _message = 'Corregí antes de enviar: ${problems.first}';
      _notify();
      return;
    }
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
      final uploadDocument = sceneUploadDocument(_preview!.document);
      debugPrint(
        '[RoomForge][SceneUpload] rooms=${(uploadDocument['rooms']! as List).length} '
        'walls=${(uploadDocument['walls']! as List).length} '
        'openings=${(uploadDocument['openings']! as List).length}',
      );
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
      debugPrint(
        '[RoomForge][SceneUpload] result=rejected status=${failure.statusCode} '
        'code=${failure.code}',
      );
      _syncState = CaptureSyncState.failed;
      final validationFailure =
          failure.statusCode == 400 ||
          failure.statusCode == 422 ||
          const {'scene_invalid', kValidationError}.contains(failure.code);
      _message = failure.isNetworkFailure
          ? 'Sin conexión. Tu captura quedó guardada en el teléfono; '
                'reintentá cuando tengas red.'
          : validationFailure
          ? 'No se pudo enviar la escena. Revisá los ambientes e intentá nuevamente.'
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
    _traces.clear();
    _syncState = CaptureSyncState.empty;
    _rebuild();
    _notify();
    return true;
  }

  Future<int> storageBytes() async {
    final owner = ownerId;
    return owner == null ? 0 : _store.sizeBytes(owner);
  }

  /// Applies [next] plus, optionally, the local tracing aids, and only keeps
  /// them in memory when they were persisted. A storage failure leaves the
  /// previous rooms, traces and sync state exactly as they were.
  Future<void> _change(
    PropertyCapture next, {
    Map<String, FloorplanTraceMetadata>? traces,
  }) async {
    final previousCapture = _capture;
    final previousTraces = Map<String, FloorplanTraceMetadata>.of(_traces);
    final previousSyncState = _syncState;
    final previousMessage = _message;
    final nextTraces = traces == null
        ? null
        : Map<String, FloorplanTraceMetadata>.of(traces);
    _capture = next.copyWith(updatedAt: _now());
    if (nextTraces != null) {
      _traces
        ..clear()
        ..addAll(nextTraces);
    }
    _syncState = _capture.rooms.isEmpty && _baseEtag == null
        ? CaptureSyncState.empty
        : CaptureSyncState.pending;
    _message = null;
    _rebuild();
    try {
      await _persist();
    } on Object {
      _capture = previousCapture;
      _traces
        ..clear()
        ..addAll(previousTraces);
      _syncState = previousSyncState;
      _message = previousMessage;
      _rebuild();
      rethrow;
    }
    _notify();
  }

  /// Whether any local tracing aid still points at [sourceId].
  bool _referencesSource(String sourceId) =>
      _traces.values.any((trace) => trace.sourceId == sourceId);

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
      'traces': [for (final trace in _traces.values) trace.toJson()],
    });
  }

  ({String token, String agencyId})? _credentials() {
    final token = _session.accessToken;
    final agencyId = _session.account?.tenantId;
    if (token == null || agencyId == null) return null;
    return (token: token, agencyId: agencyId);
  }
}
