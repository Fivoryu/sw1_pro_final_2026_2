import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../data/services/photo_source.dart';
import '../../data/services/local_floorplan_analyzer.dart';
import '../../data/services/staff_floorplan_interpretation_api.dart';
import '../../domain/spatial/spatial.dart';
import '../../domain/spatial_capture_controller.dart';
import 'spatial_format.dart';

enum _TraceMode { navigate, trace }

enum _TraceTool { select, vertex, wall, door, window, perimeter }

enum _TraceHitKind { vertex, opening, wall }

class _TraceHit {
  const _TraceHit(this.kind, this.index, this.distance);

  final _TraceHitKind kind;
  final int index;
  final double distance;
}

class _RoomOverlay {
  const _RoomOverlay(this.label, this.center);

  final String label;
  final FloorPoint center;
}

/// One undo/redo step. A closed contour is represented only by its single
/// authoritative [FloorplanVisualDraft]; open points exist only while the
/// contour is still being drawn.
class _TraceEditState {
  const _TraceEditState({this.openPoints = const [], this.draft});

  final List<FloorPoint> openPoints;
  final FloorplanVisualDraft? draft;
}

bool _sameTraceEditState(_TraceEditState left, _TraceEditState right) {
  if (left.openPoints.length != right.openPoints.length) return false;
  for (var index = 0; index < left.openPoints.length; index++) {
    if (left.openPoints[index] != right.openPoints[index]) return false;
  }
  final a = left.draft;
  final b = right.draft;
  if (a == null || b == null) return a == null && b == null;
  return a.hasSameContentAs(b);
}

const _providerUnavailableMessage =
    'La interpretación automática no está disponible temporalmente. '
    'Podés reintentar o corregir el ambiente manualmente.';
const _modelLowConfidenceMessage =
    'No pudimos interpretar este plano con suficiente confianza. '
    'Podés reintentar con otra imagen o trazar el ambiente manualmente.';
const _lowQualityProposalMessage =
    'La propuesta automática necesita demasiadas correcciones. '
    'Podés reintentar o corregir la geometría.';

class FloorplanTraceScreen extends StatefulWidget {
  const FloorplanTraceScreen({
    super.key,
    required this.controller,
    this.roomId,
    this.analyzer = const LocalFloorplanAnalyzer(),
  });

  final SpatialCaptureController controller;
  final String? roomId;
  final LocalFloorplanAnalyzer analyzer;

  @override
  State<FloorplanTraceScreen> createState() => _FloorplanTraceScreenState();
}

class _FloorplanTraceScreenState extends State<FloorplanTraceScreen> {
  final _name = TextEditingController();
  final _reference = TextEditingController();

  /// Text controllers are keyed by the stable wall identity, never by the
  /// display edge index. The latter changes after structural edits.
  final _wallLengths = <String, TextEditingController>{};
  final _wallHeights = <String, TextEditingController>{};
  // Opening input is transient UI state. Its stable key is the document's
  // opening ID, never the current list position or derived edge index.
  final _openingWidths = <String, TextEditingController>{};
  final _openingHeights = <String, TextEditingController>{};
  final _openingOffsets = <String, TextEditingController>{};
  final _openingSills = <String, TextEditingController>{};
  final _wallChipKeys = <String, GlobalKey>{};
  final _height = TextEditingController();
  final _transform = TransformationController();
  final _reviewTransform = TransformationController();
  final _wallSelectorController = ScrollController();
  final _toolStripController = ScrollController();
  String? _cachedSourceId;
  Uint8List? _cachedSourceBytes;

  /// Only used while the user is drawing an unfinished contour. Once closed,
  /// geometry is exclusively read from [_visualDraft].
  final List<FloorPoint> _openPoints = [];
  LocalTraceSource? _source;
  int _imageWidth = 0;
  int _imageHeight = 0;
  int _referenceEdge = 0;
  int _selectedEdge = 0;
  int? _selectedVertex;
  int? _selectedOpening;
  bool _closed = false;
  bool _loading = false;
  bool _saved = false;
  FloorplanAnalysisResult? _analysis;

  /// The single authoritative editable document once the contour is closed.
  /// Openings and measurement evidence are read from here, never duplicated.
  FloorplanVisualDraft? _visualDraft;
  _TraceEditState? _initialEditState;
  String? _selectedWallId;
  List<WallMeasurementCandidate> _candidates = const [];
  int _analysisGeneration = 0;
  _TraceMode _mode = _TraceMode.navigate;
  _TraceTool _tool = _TraceTool.select;
  final List<_TraceEditState> _undo = [];
  final List<_TraceEditState> _redo = [];
  FloorplanVisualDraft? _dragStartDraft;
  FloorPoint? _dragJunctionPoint;
  Set<String> _dragIncidentWallIds = const {};
  bool _openingDragValid = false;
  FloorPoint? _pendingWallStart;
  FloorPoint? _pendingWallPreview;
  String? _measurementEditWallId;
  String? _restorationProblem;
  bool _splitWallPending = false;
  bool _showAmbiguous = false;
  bool _editorToolsExpanded = false;
  bool _showWallLabels = true;
  bool _showRoomLabels = true;
  bool _showVertices = true;
  bool _showOpenings = true;
  bool _showOverlay = true;
  bool _showMiniMap = true;
  bool _cleanView = false;

  /// Wall chosen for each unassigned measurement, before the user confirms the
  /// association. Evidence recovery never happens implicitly.
  final _evidenceTargets = <String, int>{};

  String? get _documentRoomId {
    final capturedRoomId = widget.roomId;
    if (capturedRoomId == null) return _visualDraft?.rooms.firstOrNull?.id;
    return widget.controller.traceForRoom(capturedRoomId)?.visualRoomId ??
        capturedRoomId;
  }

  /// Single presentation ordering for every physical wall. Persistent wall
  /// IDs remain canonical; P numbers are derived exclusively from this list.
  List<VisualWallSegment> get _currentPhysicalWalls =>
      _visualDraft?.walls ?? const <VisualWallSegment>[];

  int? get _selectedPhysicalWallIndex {
    final wallId = _selectedWallId;
    if (wallId == null) return null;
    final index = _currentPhysicalWalls.indexWhere((wall) => wall.id == wallId);
    return index < 0 ? null : index;
  }

  String? _physicalWallIdAt(int index) =>
      index < 0 || index >= _currentPhysicalWalls.length
      ? null
      : _currentPhysicalWalls[index].id;

  void _selectPhysicalWall(String? wallId) {
    if (wallId == null ||
        !_currentPhysicalWalls.any((wall) => wall.id == wallId)) {
      return;
    }
    _selectedWallId = wallId;
    _selectedEdge = _edgeForWallId(wallId) ?? 0;
    _selectedVertex = null;
    _selectedOpening = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _wallChipKeys[wallId]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: .5,
          duration: const Duration(milliseconds: 180),
        );
      } else if (_wallSelectorController.hasClients) {
        final index = _selectedPhysicalWallIndex ?? 0;
        final target = (index * 52.0)
            .clamp(0.0, _wallSelectorController.position.maxScrollExtent)
            .toDouble();
        _wallSelectorController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _selectTraceTool(_TraceTool tool) {
    _tool = tool;
    _splitWallPending = false;
    _pendingWallStart = null;
    _pendingWallPreview = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_toolStripController.hasClients) return;
      const presentationOrder = [
        _TraceTool.select,
        _TraceTool.vertex,
        _TraceTool.wall,
        _TraceTool.door,
        _TraceTool.window,
        _TraceTool.perimeter,
      ];
      final index = presentationOrder.indexOf(tool);
      final target = (index * 104.0)
          .clamp(0.0, _toolStripController.position.maxScrollExtent)
          .toDouble();
      _toolStripController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  /// Rendering adapter for legacy widgets. It is never mutated directly.
  List<FloorPoint> get _points {
    if (!_closed) return List.unmodifiable(_openPoints);
    final roomId = _documentRoomId;
    final contour = roomId == null
        ? null
        : _visualDraft?.contourForRoom(roomId);
    return List.unmodifiable(contour ?? const <FloorPoint>[]);
  }

  List<VisualWallSegment> get _internalWalls {
    final draft = _visualDraft;
    final roomId = _documentRoomId;
    final perimeter = roomId == null
        ? const <String>[]
        : draft?.wallIdsForRoom(roomId) ?? const <String>[];
    if (draft == null) return const [];
    return List.unmodifiable([
      for (final wall in draft.walls)
        if (!perimeter.contains(wall.id)) wall,
    ]);
  }

  List<_RoomOverlay> get _roomOverlays {
    final draft = _visualDraft;
    if (draft == null || draft.rooms.length < 2) return const [];
    return [
      for (final (index, room) in draft.rooms.indexed)
        if (draft.contourForRoom(room.id) case final contour?)
          _RoomOverlay(
            'A${index + 1}',
            FloorPoint(
              contour.fold<double>(0, (sum, point) => sum + point.x) /
                  contour.length,
              contour.fold<double>(0, (sum, point) => sum + point.z) /
                  contour.length,
            ),
          ),
    ];
  }

  CapturedRoom? get _existingRoom => widget.roomId == null
      ? null
      : widget.controller.rooms
            .where((room) => room.id == widget.roomId)
            .firstOrNull;
  bool get _legacy =>
      _existingRoom?.measurementMode == RoomMeasurementMode.legacyUniform;
  int get _openingReviewCount => _openingProposals.isNotEmpty
      ? _openingProposals.length
      : _analysis?.openingCandidates.length ?? 0;

  /// Read-only projection of the document's persisted openings. Legacy widgets
  /// still paint and label edge indexes; the document keeps [VisualOpeningDraft.wallId].
  List<InterpretedOpeningProposal> get _openingProposals => [
    for (final opening
        in _visualDraft?.openings ?? const <VisualOpeningDraft>[])
      _proposalFor(opening),
  ];

  InterpretedOpeningProposal _proposalFor(VisualOpeningDraft opening) =>
      InterpretedOpeningProposal(
        edgeIndex: _edgeIndexForVisualOpening(opening),
        type: switch (opening.type) {
          VisualOpeningType.door => FloorplanOpeningCandidateType.door,
          VisualOpeningType.window => FloorplanOpeningCandidateType.window,
          VisualOpeningType.unknown => FloorplanOpeningCandidateType.unknown,
        },
        position: opening.position,
        normalizedWidth: opening.normalizedWidth,
        confidence: opening.confidence,
        manuallyPlaced: opening.manuallyPlaced,
      );

  VisualOpeningDraft _openingFor(
    InterpretedOpeningProposal opening, {
    required List<String> wallIds,
    required String fallbackId,
  }) => VisualOpeningDraft(
    id: fallbackId,
    type: switch (opening.type) {
      FloorplanOpeningCandidateType.door => VisualOpeningType.door,
      FloorplanOpeningCandidateType.window => VisualOpeningType.window,
      FloorplanOpeningCandidateType.unknown => VisualOpeningType.unknown,
    },
    wallId:
        opening.edgeIndex == null ||
            opening.edgeIndex! < 0 ||
            opening.edgeIndex! >= wallIds.length
        ? null
        : wallIds[opening.edgeIndex!],
    position: opening.position,
    normalizedWidth: opening.normalizedWidth,
    manuallyPlaced: opening.manuallyPlaced,
    confidence: opening.confidence,
  );

  /// Builds the closed document from the contour the user just finished.
  /// [openings] are provider proposals and stay unconfirmed ([VisualOpeningDraft.manuallyPlaced] false).
  FloorplanVisualDraft _draftFromOpenContour({
    List<InterpretedOpeningProposal> openings = const [],
  }) {
    final existing = _visualDraft;
    if (existing != null) return existing;
    final roomId = widget.roomId ?? 'trace:new';
    final wallIds = [
      for (var index = 0; index < _openPoints.length; index++)
        '$roomId:wall:$index',
    ];
    return FloorplanVisualDraft(
      walls: [
        for (var index = 0; index < _openPoints.length; index++)
          VisualWallSegment(
            id: wallIds[index],
            start: _openPoints[index],
            end: _openPoints[(index + 1) % _openPoints.length],
            roomIds: [roomId],
          ),
      ],
      rooms: [
        VisualRoomRegion(id: roomId, name: _name.text.trim(), wallIds: wallIds),
      ],
      openings: [
        for (final (index, opening) in openings.indexed)
          _openingFor(
            opening,
            wallIds: wallIds,
            fallbackId: '$roomId:opening:$index',
          ),
      ],
    );
  }

  int? _edgeIndexForVisualOpening(VisualOpeningDraft opening) {
    final wallId = opening.wallId;
    final draft = _visualDraft;
    final roomId = _documentRoomId;
    if (wallId == null || draft == null || roomId == null) return null;
    return draft.edgeIndexForWall(roomId, wallId);
  }

  String? _wallIdAt(int edgeIndex) {
    final draft = _visualDraft;
    final roomId = _documentRoomId;
    if (draft == null || roomId == null) return null;
    final wallIds = draft.wallIdsForRoom(roomId);
    return edgeIndex < 0 || edgeIndex >= wallIds.length
        ? null
        : wallIds[edgeIndex];
  }

  int? _edgeForWallId(String? wallId) {
    final draft = _visualDraft;
    final roomId = _documentRoomId;
    if (wallId == null || draft == null || roomId == null) return null;
    return draft.edgeIndexForWall(roomId, wallId);
  }

  void _applyVisualDraft(FloorplanVisualDraft draft) {
    final previousWalls = _currentPhysicalWalls;
    final previousIndex = _selectedWallId == null
        ? 0
        : previousWalls.indexWhere((wall) => wall.id == _selectedWallId);
    _visualDraft = draft;
    if (_selectedWallId == null ||
        !draft.walls.any((wall) => wall.id == _selectedWallId)) {
      if (draft.walls.isEmpty) {
        _selectedWallId = null;
      } else {
        final fallback = previousIndex < 0
            ? 0
            : previousIndex.clamp(0, draft.walls.length - 1).toInt();
        _selectedWallId = draft.walls[fallback].id;
      }
    }
    _selectedEdge = _edgeForWallId(_selectedWallId) ?? 0;
    _reconcileWallControllers();
  }

  List<FloorPoint> get _currentTrace =>
      _visualDraft?.contourForRoom(_roomIdForEdits) ?? _points;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final roomId = widget.roomId;
    if (roomId == null) {
      _name.text = 'Ambiente ${widget.controller.rooms.length + 1}';
      return;
    }
    final room = widget.controller.rooms
        .where((r) => r.id == roomId)
        .firstOrNull;
    final trace = widget.controller.traceForRoom(roomId);
    _name.text = room?.name ?? '';
    // Retracing keeps what the agent already recorded: the field is prefilled
    // with the exact stored value, not a rounded copy, so saving an untouched
    // retrace cannot silently re-quantize the height.
    _height.text = room?.height?.value.toString() ?? '';
    if (trace == null) return;
    final bytes = await widget.controller.floorplanSourceBytes(trace.sourceId);
    if (!mounted) return;
    if (bytes == null) {
      setState(() {});
      return;
    }
    // Legacy traces migrate deterministically; a stored document is restored
    // verbatim; a damaged document is reported and never rebuilt silently.
    final restoration = trace.restoreEditorDraft(
      references: _legacyReferences(room),
    );
    setState(() {
      _visualDraft = restoration.draft;
      _restorationProblem = restoration.problem;
      _source = LocalTraceSource(
        sourceId: trace.sourceId,
        contentType: trace.contentType,
        bytes: bytes,
      );
      _imageWidth = trace.imageWidth;
      _imageHeight = trace.imageHeight;
      _referenceEdge = trace.referenceEdge ?? 0;
      // The calibration measurement is kept exactly as recorded: rounding it
      // to centimetres here would rescale an untouched retrace.
      if (_legacy && trace.referenceMeters != null) {
        _reference.text = trace.referenceMeters.toString();
      }
      _closed = restoration.isReady;
      if (_closed) {
        _mode = _TraceMode.trace;
        _selectedWallId = restoration.draft?.walls.firstOrNull?.id;
        _selectedEdge = _edgeForWallId(_selectedWallId) ?? 0;
        _syncWallLengthControllers();
        _reconcileWallControllers();
        _initialEditState = _editState;
      } else {
        _openPoints.clear();
      }
    });
    if (restoration.problem != null) {
      _show(
        'No pudimos abrir el documento visual guardado. Volvé a trazar el '
        'ambiente para reemplazarlo.',
      );
    }
  }

  /// Canonical room references are migrated onto stable wall IDs only for
  /// traces that have no persisted document yet.
  List<LegacyMeasurementReference> _legacyReferences(CapturedRoom? room) => [
    for (final measurement
        in room?.references ?? const <ReferenceMeasurement>[])
      LegacyMeasurementReference(
        edgeIndex: measurement.edgeIndex,
        meters: measurement.referenceMeters,
        provenance: measurement.provenance.wire,
        requiresReview:
            measurement.provenance != WallMeasurementProvenance.user,
      ),
  ];

  /// Text fields are temporary input; the document stays the authority.
  void _reconcileWallControllers() {
    final draft = _visualDraft;
    if (draft == null) return;
    final activeWallIds = {for (final wall in draft.walls) wall.id};
    final knownWallIds = {..._wallLengths.keys, ..._wallHeights.keys};
    if (knownWallIds.length == activeWallIds.length &&
        knownWallIds.containsAll(activeWallIds)) {
      return;
    }
    for (final controllers in [_wallLengths, _wallHeights]) {
      for (final entry in controllers.entries.toList()) {
        if (!activeWallIds.contains(entry.key)) {
          entry.value.dispose();
          controllers.remove(entry.key);
        }
      }
    }
    _wallChipKeys.removeWhere((wallId, _) => !activeWallIds.contains(wallId));
    for (final wallId in activeWallIds) {
      _wallLengths.putIfAbsent(wallId, TextEditingController.new);
      _wallHeights.putIfAbsent(wallId, TextEditingController.new);
    }
    for (final evidence in draft.measurements) {
      final wallId = evidence.wallId;
      if (wallId == null || !activeWallIds.contains(wallId)) continue;
      final controller =
          evidence.dimension == VisualWallMeasurementDimension.height
          ? _wallHeights[wallId]
          : _wallLengths[wallId];
      if (controller != null && controller.text.isEmpty) {
        controller.text = evidence.meters.toString();
      }
    }
  }

  void _syncWallLengthControllers() {
    final draft = _visualDraft;
    if (draft == null) return;
    final activeWallIds = {for (final wall in draft.walls) wall.id};
    for (final entry in _wallLengths.entries.toList()) {
      if (!activeWallIds.contains(entry.key)) {
        entry.value.dispose();
        _wallLengths.remove(entry.key);
      } else {
        entry.value.clear();
      }
    }
    for (final entry in _wallHeights.entries.toList()) {
      if (!activeWallIds.contains(entry.key)) {
        entry.value.dispose();
        _wallHeights.remove(entry.key);
      } else {
        entry.value.clear();
      }
    }
    for (final evidence in draft.measurements) {
      final wallId = evidence.wallId;
      if (wallId == null ||
          evidence.dimension != VisualWallMeasurementDimension.length ||
          evidence.provenance != WallMeasurementProvenance.user.wire) {
        continue;
      }
      if (!activeWallIds.contains(wallId)) continue;
      _wallLengths.putIfAbsent(wallId, TextEditingController.new).text =
          evidence.meters.toString();
    }
    for (final evidence in draft.measurements) {
      if (evidence.dimension != VisualWallMeasurementDimension.height ||
          evidence.wallId == null ||
          !activeWallIds.contains(evidence.wallId))
        continue;
      _wallHeights
          .putIfAbsent(evidence.wallId!, TextEditingController.new)
          .text = evidence.meters
          .toString();
    }
    _syncOpeningControllers();
  }

  void _syncOpeningControllers() {
    final draft = _visualDraft;
    if (draft == null) return;
    final openings = {
      for (final opening in draft.openings) opening.id: opening,
    };
    void sync(
      Map<String, TextEditingController> controllers,
      double? Function(VisualOpeningDraft opening) valueOf,
    ) {
      for (final entry in controllers.entries.toList()) {
        if (!openings.containsKey(entry.key)) {
          entry.value.dispose();
          controllers.remove(entry.key);
        } else {
          entry.value.clear();
        }
      }
      for (final opening in openings.values) {
        final value = valueOf(opening);
        if (value != null) {
          controllers.putIfAbsent(opening.id, TextEditingController.new).text =
              value.toString();
        }
      }
    }

    sync(_openingWidths, (opening) => opening.widthM);
    sync(_openingHeights, (opening) => opening.heightM);
    sync(_openingOffsets, (opening) => opening.offsetFromWallStartM);
    sync(_openingSills, (opening) => opening.sillHeightM);
  }

  double? _estimatedOpeningWidth(VisualOpeningDraft opening) {
    final draft = _visualDraft;
    final wallId = opening.wallId;
    final normalizedWidth = opening.normalizedWidth;
    if (draft == null || wallId == null || normalizedWidth == null) return null;
    final length = draft.authoritativeWallLength(wallId)?.meters;
    return length == null ? null : length * normalizedWidth;
  }

  double? _estimatedOpeningOffset(VisualOpeningDraft opening) {
    final draft = _visualDraft;
    final wallId = opening.wallId;
    final position = opening.position;
    final normalizedWidth = opening.normalizedWidth;
    if (draft == null ||
        wallId == null ||
        position == null ||
        normalizedWidth == null) {
      return null;
    }
    final length = draft.authoritativeWallLength(wallId)?.meters;
    if (length == null) return null;
    return (length * (position - normalizedWidth / 2))
        .clamp(0.0, length)
        .toDouble();
  }

  String _openingHostLabel(VisualOpeningDraft opening) {
    final wallId = opening.wallId;
    if (wallId == null) return 'pared sin asignar';
    final index = _currentPhysicalWalls.indexWhere((wall) => wall.id == wallId);
    return index < 0 ? 'pared sin asignar' : 'P${index + 1}';
  }

  /// A picked image starts a new, isolated editing session. Persisted rooms
  /// are deliberately untouched here: they are only replaced by [_save] once
  /// the new document has passed validation and reached the controller.
  void _clearSourceSessionControllers() {
    for (final controllers in [
      _wallLengths,
      _wallHeights,
      _openingWidths,
      _openingHeights,
      _openingOffsets,
      _openingSills,
    ]) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      controllers.clear();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _reference.dispose();
    for (final controller in _wallLengths.values) {
      controller.dispose();
    }
    for (final controller in _wallHeights.values) {
      controller.dispose();
    }
    for (final controller in _openingWidths.values) {
      controller.dispose();
    }
    for (final controller in _openingHeights.values) {
      controller.dispose();
    }
    for (final controller in _openingOffsets.values) {
      controller.dispose();
    }
    for (final controller in _openingSills.values) {
      controller.dispose();
    }
    _height.dispose();
    _transform.dispose();
    _reviewTransform.dispose();
    _wallSelectorController.dispose();
    _toolStripController.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    if (_source != null && _points.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cambiar imagen'),
          content: const Text(
            'Cambiar la imagen eliminará el trazado actual. ¿Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cambiar'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    final generation = ++_analysisGeneration;
    setState(() => _loading = true);
    try {
      final next = await widget.controller.pickFloorplanSource();
      if (next == null || !mounted) return;
      final decoded = await _decode(next.bytes);
      if (!mounted || generation != _analysisGeneration) {
        await widget.controller.discardFloorplanSource(next.sourceId);
        return;
      }
      if (decoded == null) {
        await widget.controller.discardFloorplanSource(next.sourceId);
        _show('No se pudo abrir la imagen.');
        return;
      }
      final previous = _source;
      if (previous != null && widget.roomId == null) {
        await widget.controller.discardFloorplanSource(previous.sourceId);
      }
      final supportsInterpretation =
          widget.controller.supportsFloorplanInterpretation;
      FloorplanInterpretationResult? interpretation;
      var interpretationUnavailable = false;
      if (supportsInterpretation) {
        try {
          interpretation = await widget.controller.interpretFloorplan(
            imageBytes: next.bytes,
            contentType: next.contentType,
          );
          interpretationUnavailable = interpretation == null;
        } on Object catch (error, stackTrace) {
          // The image decoded correctly: a remote failure must preserve it and
          // must not silently fall back to classical local geometry.
          interpretationUnavailable = true;
          if (kDebugMode) {
            debugPrint('[RoomForge][FloorplanInterpretation] $error');
            debugPrintStack(stackTrace: stackTrace);
          }
        }
      }
      InterpretedRoomCandidate? interpretedRoom;
      if (interpretation != null && interpretation.rooms.length == 1) {
        interpretedRoom = interpretation.rooms.single;
      } else if (interpretation != null && interpretation.rooms.length > 1) {
        interpretedRoom = await _selectRoom(interpretation.rooms);
      }
      final FloorplanAnalysisResult analysis;
      if (interpretedRoom != null) {
        analysis = FloorplanAnalysisResult(
          status:
              interpretation!.status == FloorplanInterpretationStatus.success
              ? FloorplanAnalysisStatus.success
              : FloorplanAnalysisStatus.partial,
          contour: interpretedRoom.contour,
          openingCandidates: interpretedRoom.openings
              .map((opening) => opening.toCanonicalCandidate())
              .whereType<FloorplanOpeningCandidate>()
              .toList(growable: false),
          message: switch (interpretation.status) {
            FloorplanInterpretationStatus.success =>
              'Interpretación automática lista para revisión humana.',
            FloorplanInterpretationStatus.needsReview ||
            FloorplanInterpretationStatus.invalidInput =>
              _lowQualityProposalMessage,
            FloorplanInterpretationStatus.lowConfidence =>
              _modelLowConfidenceMessage,
            FloorplanInterpretationStatus.providerUnavailable =>
              _providerUnavailableMessage,
            FloorplanInterpretationStatus.partial =>
              'Interpretación parcial: revisá la geometría y las medidas.',
          },
          reason: FloorplanAnalysisReason.detected,
        );
      } else if (!supportsInterpretation) {
        // Compatibility/offline builds without the backend interpreter retain
        // the existing local analyzer. A configured provider failure never
        // silently substitutes its geometry.
        analysis = await widget.analyzer.analyze(
          rgba: decoded.$3,
          width: decoded.$1,
          height: decoded.$2,
        );
      } else {
        final unavailable =
            interpretationUnavailable ||
            interpretation?.status ==
                FloorplanInterpretationStatus.providerUnavailable;
        final message = unavailable
            ? _providerUnavailableMessage
            : switch (interpretation?.status) {
                FloorplanInterpretationStatus.lowConfidence =>
                  _modelLowConfidenceMessage,
                _ => _lowQualityProposalMessage,
              };
        analysis = FloorplanAnalysisResult(
          status: FloorplanAnalysisStatus.lowConfidence,
          message: message,
          reason: FloorplanAnalysisReason.insufficientStructuralSupport,
        );
      }
      if (kDebugMode) {
        final source = supportsInterpretation ? 'groq' : 'local_analyzer';
        final result = switch (analysis.status) {
          FloorplanAnalysisStatus.success => 'success',
          FloorplanAnalysisStatus.partial => 'partial',
          FloorplanAnalysisStatus.lowConfidence => 'low_confidence',
        };
        debugPrint(
          formatFloorplanImportDiagnostic(
            source: source,
            result: result,
            providerCandidates: interpretation?.rooms.length ?? 0,
            selectedRoom:
                interpretedRoom?.id ??
                (analysis.hasCandidate ? 'local_analyzer' : 'none'),
            selectedWalls: analysis.contour.length,
            selectedDimensions: interpretedRoom?.measurements.length ?? 0,
          ),
        );
      }
      if (!mounted || generation != _analysisGeneration) {
        await widget.controller.discardFloorplanSource(next.sourceId);
        return;
      }
      final candidates = interpretedRoom?.measurements ?? const [];
      setState(() {
        _undo.clear();
        _redo.clear();
        _measurementEditWallId = null;
        _initialEditState = null;
        _selectedWallId = null;
        _selectedVertex = null;
        _selectedOpening = null;
        _dragStartDraft = null;
        _splitWallPending = false;
        _evidenceTargets.clear();
        _clearSourceSessionControllers();
        _source = next;
        _imageWidth = decoded.$1;
        _imageHeight = decoded.$2;
        _openPoints
          ..clear()
          ..addAll(analysis.contour);
        _closed = analysis.hasCandidate;
        _visualDraft = null;
        _restorationProblem = null;
        _visualDraft = analysis.hasCandidate
            ? _draftFromOpenContour(
                openings: interpretedRoom?.openings ?? const [],
              )
            : null;
        _selectedWallId = _visualDraft?.walls.firstOrNull?.id;
        _initialEditState = _visualDraft == null
            ? null
            : _TraceEditState(draft: _visualDraft);
        _analysis = analysis;
        _candidates = candidates;
        _mode = analysis.hasCandidate ? _TraceMode.trace : _TraceMode.navigate;
        _referenceEdge = 0;
        _reference.clear();
        _selectedEdge = 0;
        _transform.value = Matrix4.identity();
        if (_visualDraft != null) {
          _syncWallLengthControllers();
          _reconcileWallControllers();
        }
      });
    } on UnsupportedPhotoFormat {
      _show('Usá una imagen JPEG, PNG o WEBP.');
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[RoomForge][FloorplanInterpretation] $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      _show('No se pudo abrir la imagen.');
    } finally {
      if (mounted && generation == _analysisGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<InterpretedRoomCandidate?> _selectRoom(
    List<InterpretedRoomCandidate> rooms,
  ) => showDialog<InterpretedRoomCandidate>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Elegí el ambiente'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Encontramos más de un ambiente posible. Seleccioná cuál querés revisar.',
          ),
          const SizedBox(height: 12),
          for (final (index, room) in rooms.indexed)
            ListTile(
              key: ValueKey('floorplan-room-candidate-$index'),
              title: Text(room.label ?? 'Ambiente ${index + 1}'),
              subtitle: Text('${room.contour.length} paredes'),
              onTap: () => Navigator.pop(context, room),
            ),
        ],
      ),
    ),
  );

  Future<(int, int, List<int>)?> _decode(List<int> bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) return null;
      final result = (
        frame.image.width,
        frame.image.height,
        data.buffer.asUint8List(),
      );
      frame.image.dispose();
      codec.dispose();
      return result;
    } on Object {
      return null;
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  FloorPoint? _point(Offset local, Size size) => normalizedTracePoint(
    sceneX: local.dx,
    sceneY: local.dy,
    viewportWidth: size.width,
    viewportHeight: size.height,
    imageWidth: _imageWidth.toDouble(),
    imageHeight: _imageHeight.toDouble(),
  );

  Uint8List _imageBytes(LocalTraceSource source) {
    if (_cachedSourceId != source.sourceId || _cachedSourceBytes == null) {
      _cachedSourceId = source.sourceId;
      _cachedSourceBytes = Uint8List.fromList(source.bytes);
    }
    return _cachedSourceBytes!;
  }

  _TraceHit? _nearestTraceTarget(FloorPoint point, Size size) {
    if (_points.isEmpty || _imageWidth <= 0 || _imageHeight <= 0) return null;
    final fitScale = math.min(
      size.width / _imageWidth,
      size.height / _imageHeight,
    );
    final shownWidth = _imageWidth * fitScale;
    final shownHeight = _imageHeight * fitScale;
    final viewerScale = _transform.value.getMaxScaleOnAxis();
    const strongVertexRadius = 20.0;
    const vertexTolerance = 30.0;
    const openingTolerance = 28.0;
    _TraceHit? best;
    _TraceHit? nearestVertex;

    void consider(_TraceHit candidate, double tolerance) {
      if (candidate.distance > tolerance) return;
      final current = best;
      if (current == null ||
          candidate.distance < current.distance - 0.001 ||
          ((candidate.distance - current.distance).abs() <= 0.001 &&
              candidate.kind.index < current.kind.index)) {
        best = candidate;
      }
    }

    for (final (index, vertex) in _points.indexed) {
      final dx = (point.x - vertex.x) * shownWidth * viewerScale;
      final dy = (point.z - vertex.z) * shownHeight * viewerScale;
      final candidate = _TraceHit(
        _TraceHitKind.vertex,
        index,
        math.sqrt(dx * dx + dy * dy),
      );
      final currentVertex = nearestVertex;
      if (currentVertex == null ||
          candidate.distance < currentVertex.distance) {
        nearestVertex = candidate;
      }
    }
    if (nearestVertex case final vertex?
        when vertex.distance <= strongVertexRadius) {
      return vertex;
    }
    if (nearestVertex case final vertex?) {
      consider(vertex, vertexTolerance);
    }
    for (final (index, opening)
        in (_visualDraft?.openings ?? const <VisualOpeningDraft>[]).indexed) {
      final wall = _visualDraft?.walls
          .where((value) => value.id == opening.wallId)
          .firstOrNull;
      final position = opening.position;
      final width = opening.normalizedWidth;
      if (wall == null || position == null || width == null) {
        continue;
      }
      final wallStart = wall.start;
      final wallEnd = wall.end;
      final edgeX = wallEnd.x - wallStart.x;
      final edgeZ = wallEnd.z - wallStart.z;
      final firstT = (position - width / 2).clamp(0.0, 1.0);
      final secondT = (position + width / 2).clamp(0.0, 1.0);
      final first = FloorPoint(
        wallStart.x + edgeX * firstT,
        wallStart.z + edgeZ * firstT,
      );
      final second = FloorPoint(
        wallStart.x + edgeX * secondT,
        wallStart.z + edgeZ * secondT,
      );
      final segmentX = (second.x - first.x) * shownWidth;
      final segmentY = (second.z - first.z) * shownHeight;
      final pointX = (point.x - first.x) * shownWidth;
      final pointY = (point.z - first.z) * shownHeight;
      final lengthSquared = segmentX * segmentX + segmentY * segmentY;
      final projection = lengthSquared <= 0
          ? 0.0
          : ((pointX * segmentX + pointY * segmentY) / lengthSquared).clamp(
              0.0,
              1.0,
            );
      final distanceX = pointX - segmentX * projection;
      final distanceY = pointY - segmentY * projection;
      consider(
        _TraceHit(
          _TraceHitKind.opening,
          index,
          math.sqrt(distanceX * distanceX + distanceY * distanceY) *
              viewerScale,
        ),
        openingTolerance,
      );
    }
    for (final (index, wall) in _currentPhysicalWalls.indexed) {
      final edge = wall.end - wall.start;
      final squared = edge.dot(edge);
      if (squared <= 0) continue;
      final projection = ((point - wall.start).dot(edge) / squared)
          .clamp(0.0, 1.0)
          .toDouble();
      final projected = wall.start + edge.scale(projection);
      final dx = (point.x - projected.x) * shownWidth * viewerScale;
      final dy = (point.z - projected.z) * shownHeight * viewerScale;
      consider(
        _TraceHit(_TraceHitKind.wall, index, math.sqrt(dx * dx + dy * dy)),
        26,
      );
    }
    if (best != null) return best;
    final legacyOpening = _nearOpening(point, size);
    return legacyOpening == null
        ? null
        : _TraceHit(_TraceHitKind.opening, legacyOpening, openingTolerance);
  }

  int? _nearOpening(FloorPoint point, Size size) {
    final scale = math.min(
      size.width / _imageWidth,
      size.height / _imageHeight,
    );
    final width = _imageWidth * scale;
    final height = _imageHeight * scale;
    var closest = 28.0;
    int? selected;
    for (final (index, opening) in _openingProposals.indexed) {
      final edge = opening.edgeIndex;
      if (!opening.hasGeometry ||
          edge == null ||
          edge < 0 ||
          edge >= _points.length)
        continue;
      final a = _points[edge];
      final b = _points[(edge + 1) % _points.length];
      final center = a + (b - a).scale(opening.position!);
      final dx = (point.x - center.x) * width;
      final dz = (point.z - center.z) * height;
      final distance = math.sqrt(dx * dx + dz * dz);
      if (distance < closest) {
        closest = distance;
        selected = index;
      }
    }
    return selected;
  }

  void _selectWall(TapDownDetails details, Size size) {
    if (!_closed || _currentPhysicalWalls.isEmpty) return;
    final point = _point(details.localPosition, size);
    final target = point == null ? null : _nearestWallProjection(point, size);
    if (target != null) {
      setState(() {
        _selectPhysicalWall(target.$1);
      });
    }
  }

  _TraceEditState get _editState =>
      _TraceEditState(openPoints: [..._openPoints], draft: _visualDraft);

  /// While one wall length is being typed, consecutive keystrokes coalesce into
  /// a single undo step so a confirmation is reversible but not noisy.
  void _rememberEdit(_TraceEditState before, {String? measurementWallId}) {
    if (measurementWallId != null &&
        _measurementEditWallId == measurementWallId) {
      _redo.clear();
      return;
    }
    _undo.add(before);
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
    _measurementEditWallId = measurementWallId;
  }

  void _restoreEdit(_TraceEditState state) {
    _measurementEditWallId = null;
    _openPoints
      ..clear()
      ..addAll(state.openPoints);
    final restoredDraft = state.draft;
    if (restoredDraft != null) {
      _applyVisualDraft(restoredDraft);
    } else {
      _visualDraft = null;
      _selectedWallId = null;
      _selectedEdge = 0;
    }
    _closed = state.draft != null;
    _selectedVertex = null;
    _selectedOpening = null;
    _syncWallLengthControllers();
  }

  void _undoEdit() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_editState);
      _restoreEdit(_undo.removeLast());
    });
  }

  void _redoEdit() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_editState);
      _restoreEdit(_redo.removeLast());
    });
  }

  String get _roomIdForEdits {
    final draft = _visualDraft;
    return _documentRoomId ?? draft?.rooms.singleOrNull?.id ?? 'trace:new';
  }

  void _showEditFailure(String? errorCode, {required String fallback}) {
    _show(switch (errorCode) {
      'pared_con_abertura' =>
        'No se puede unir una pared con aberturas asociadas.',
      'pared_con_medicion' =>
        'No se puede editar una pared con medidas asociadas.',
      'division_sobre_abertura' =>
        'La división atraviesa una abertura existente. Elegí un punto fuera '
            'de la puerta o ventana.',
      'abertura_no_representable' =>
        'No se puede quitar el vértice sin alterar una abertura existente.',
      'extremo_sin_conexion' =>
        'Los extremos de la pared deben tocar una pared o un vértice existente.',
      'interseccion_sin_vertice' =>
        'La pared cruza otra pared fuera de un punto de conexión.',
      'conexion_ambigua' =>
        'El punto coincide con varias paredes sin un vértice común.',
      'vertice_compartido' =>
        'El vértice conecta una pared interna y no puede disolverse sin desconectarla.',
      'vertice_existente' => 'Ese punto ya corresponde a un vértice existente.',
      'topologia_invalida' =>
        'La operación no produce ambientes cerrados válidos.',
      'pared_exterior' =>
        'Las paredes exteriores solo se modifican desde Contorno.',
      _ => fallback,
    });
  }

  void _splitSelectedWall(FloorPoint point) {
    final before = _editState;
    final draft = _visualDraft;
    final wallId = _selectedWallId ?? _wallIdAt(_selectedEdge);
    if (draft == null || wallId == null) return;
    // Geometric validity is delegated to the domain operation: a split away
    // from an existing opening is valid and remaps the opening onto the
    // resulting segment. Only cuts that intersect the opening interval are
    // rejected there.
    if (draft.hasMeasurementForWall(wallId)) {
      _show('No se puede dividir una pared con medidas asociadas.');
      return;
    }
    final next = FloorplanVisualDraftEditor.splitWall(
      draft: draft,
      roomId: _roomIdForEdits,
      wallId: wallId,
      point: point,
    );
    if (!next.isSuccess) {
      _showEditFailure(
        next.errorCode,
        fallback: 'Tocá un punto interior de la pared seleccionada.',
      );
      return;
    }
    setState(() {
      _rememberEdit(before);
      _applyVisualDraft(next.draft!);
      _selectedWallId = wallId;
      _selectedVertex = _selectedEdge + 1;
      _splitWallPending = false;
    });
  }

  void _mergeAtSelectedVertex() {
    final vertex = _selectedVertex;
    if (vertex == null) return;
    final draft = _visualDraft;
    final following = _wallIdAt(vertex);
    final previous = _wallIdAt((vertex - 1 + _points.length) % _points.length);
    if (draft == null || following == null || previous == null) return;
    if (draft.hasOpeningForWall(following) ||
        draft.hasOpeningForWall(previous)) {
      _show('No se puede unir paredes con aberturas asociadas.');
      return;
    }
    if (draft.hasMeasurementForWall(following) ||
        draft.hasMeasurementForWall(previous)) {
      _show('No se puede unir paredes con medidas asociadas.');
      return;
    }
    final hasPendingMeasurement = [
      previous,
      following,
    ].any((wallId) => (_wallLengths[wallId]?.text.trim().isNotEmpty ?? false));
    if (hasPendingMeasurement) {
      _show('Guardá o borrá la medida pendiente antes de unir las paredes.');
      return;
    }
    final next = FloorplanVisualDraftEditor.mergeWalls(
      draft: draft,
      roomId: _roomIdForEdits,
      firstWallId: previous,
      secondWallId: following,
    );
    if (!next.isSuccess) {
      _showEditFailure(
        next.errorCode,
        fallback: 'Solo podés unir paredes contiguas casi colineales.',
      );
      return;
    }
    final before = _editState;
    setState(() {
      _rememberEdit(before);
      _selectedWallId = previous;
      _applyVisualDraft(next.draft!);
      _selectedVertex = null;
    });
  }

  void _removeSelectedVertex() {
    final vertex = _selectedVertex;
    final draft = _visualDraft;
    if (vertex == null || draft == null || _points.length <= 3) return;
    final following = _wallIdAt(vertex);
    final previous = _wallIdAt((vertex - 1 + _points.length) % _points.length);
    if (following == null || previous == null) return;
    final hasPendingMeasurement = [
      previous,
      following,
    ].any((wallId) => (_wallLengths[wallId]?.text.trim().isNotEmpty ?? false));
    if (hasPendingMeasurement) {
      _show(
        'GuardÃ¡ o borrÃ¡ la medida pendiente antes de quitar el vÃ©rtice.',
      );
      return;
    }
    final next = FloorplanVisualDraftEditor.removeVertex(
      draft: draft,
      roomId: _roomIdForEdits,
      followingWallId: following,
    );
    if (!next.isSuccess) {
      _showEditFailure(
        next.errorCode,
        fallback: 'No se puede quitar este vÃ©rtice sin invalidar el plano.',
      );
      return;
    }
    final before = _editState;
    setState(() {
      _rememberEdit(before);
      _selectedWallId = previous;
      _applyVisualDraft(next.draft!);
      _selectedVertex = null;
      _syncOpeningControllers();
    });
  }

  bool get _canRemoveSelectedInternalWall {
    final draft = _visualDraft;
    final wallId = _selectedWallId;
    if (draft == null || wallId == null) return false;
    return draft.walls
        .where((wall) => wall.id == wallId)
        .any((wall) => wall.roomIds.length >= 2);
  }

  void _removeSelectedInternalWall() {
    final draft = _visualDraft;
    final wallId = _selectedWallId;
    if (draft == null || wallId == null) return;
    final next = FloorplanVisualDraftEditor.removeInternalWall(
      draft: draft,
      wallId: wallId,
    );
    if (!next.isSuccess) {
      _showEditFailure(
        next.errorCode,
        fallback: 'No se puede quitar esta pared.',
      );
      return;
    }
    final before = _editState;
    setState(() {
      _rememberEdit(before);
      _applyVisualDraft(next.draft!);
    });
  }

  String _nextOpeningId(FloorplanVisualDraft draft, int wallIndex) {
    final used = {for (final opening in draft.openings) opening.id};
    final roomId = draft.rooms.singleOrNull?.id ?? _roomIdForEdits;
    for (var generation = 1; ; generation++) {
      final candidate = '$roomId:opening:$wallIndex.$generation';
      if (!used.contains(candidate)) return candidate;
    }
  }

  (VisualWallSegment, FloorPoint, double)? _snapOpeningHost(
    FloorPoint point,
    Size size,
  ) {
    final draft = _visualDraft;
    if (draft == null || _imageWidth <= 0 || _imageHeight <= 0) return null;
    final scale = math.min(
      size.width / _imageWidth,
      size.height / _imageHeight,
    );
    final shownWidth = _imageWidth * scale;
    final shownHeight = _imageHeight * scale;
    const tolerance = 28.0;
    (VisualWallSegment, FloorPoint, double)? best;
    var bestDistance = tolerance;
    for (final wall in draft.walls) {
      final edge = wall.end - wall.start;
      final squared = edge.dot(edge);
      if (squared <= 0) continue;
      final position = ((point - wall.start).dot(edge) / squared)
          .clamp(0.0, 1.0)
          .toDouble();
      final projected = wall.start + edge.scale(position);
      final dx = (point.x - projected.x) * shownWidth;
      final dz = (point.z - projected.z) * shownHeight;
      final distance = math.sqrt(dx * dx + dz * dz);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = (wall, projected, position);
      }
    }
    return best;
  }

  (double, double)? _fitOpeningInterval({
    required FloorplanVisualDraft draft,
    required VisualWallSegment wall,
    required double requestedPosition,
    required double preferredWidth,
    String? excludedOpeningId,
    required bool allowShrink,
  }) {
    final wallLength = draft.authoritativeWallLength(wall.id)?.meters;
    final occupied = <(double, double)>[];
    for (final opening in draft.openings) {
      if (opening.id == excludedOpeningId || opening.wallId != wall.id) {
        continue;
      }
      final position = opening.position;
      final width =
          opening.normalizedWidth ??
          (wallLength != null && opening.widthM != null
              ? opening.widthM! / wallLength
              : null);
      if (position == null || width == null || width <= 0) continue;
      occupied.add((
        (position - width / 2).clamp(0.0, 1.0).toDouble(),
        (position + width / 2).clamp(0.0, 1.0).toDouble(),
      ));
    }
    occupied.sort((first, second) => first.$1.compareTo(second.$1));
    final requested = requestedPosition.clamp(0.0, 1.0).toDouble();
    var freeStart = 0.0;
    (double, double)? freeInterval;
    for (final interval in occupied) {
      if (requested > interval.$1 + 1e-9 && requested < interval.$2 - 1e-9) {
        return null;
      }
      if (requested >= freeStart - 1e-9 && requested <= interval.$1 + 1e-9) {
        freeInterval = (freeStart, interval.$1);
        break;
      }
      freeStart = math.max(freeStart, interval.$2).toDouble();
    }
    freeInterval ??= requested >= freeStart - 1e-9 ? (freeStart, 1.0) : null;
    if (freeInterval == null) return null;
    final available = freeInterval.$2 - freeInterval.$1;
    if (available <= 1e-6) return null;
    final width =
        (allowShrink ? math.min(preferredWidth, available) : preferredWidth)
            .toDouble();
    if (!width.isFinite || width <= 0 || width > available + 1e-9) {
      return null;
    }
    final half = width / 2;
    final position = requested
        .clamp(freeInterval.$1 + half, freeInterval.$2 - half)
        .toDouble();
    return (position, width);
  }

  VisualOpeningDraft? _openingMovedTo({
    required FloorplanVisualDraft draft,
    required VisualOpeningDraft opening,
    required VisualWallSegment wall,
    required double requestedPosition,
  }) {
    final wallLength = draft.authoritativeWallLength(wall.id)?.meters;
    final preferredWidth = wallLength != null && opening.widthM != null
        ? opening.widthM! / wallLength
        : opening.normalizedWidth ?? .2;
    final fitted = _fitOpeningInterval(
      draft: draft,
      wall: wall,
      requestedPosition: requestedPosition,
      preferredWidth: preferredWidth,
      excludedOpeningId: opening.id,
      allowShrink: false,
    );
    if (fitted == null) return null;
    final offset = wallLength == null || opening.widthM == null
        ? null
        : fitted.$1 * wallLength - opening.widthM! / 2;
    return VisualOpeningDraft(
      id: opening.id,
      type: opening.type,
      wallId: wall.id,
      position: fitted.$1,
      normalizedWidth: fitted.$2,
      manuallyPlaced: opening.manuallyPlaced,
      confidence: opening.confidence,
      widthM: opening.widthM,
      heightM: opening.heightM,
      offsetFromWallStartM: offset,
      sillHeightM: opening.sillHeightM,
    );
  }

  void _placeOpening(
    FloorPoint point,
    FloorplanOpeningCandidateType type,
    Size size,
  ) {
    final draft = _visualDraft;
    final host = _snapOpeningHost(point, size);
    final typeLabel = type == FloorplanOpeningCandidateType.window
        ? 'ventana'
        : 'puerta';
    if (draft == null || host == null) {
      if (kDebugMode) {
        debugPrint(
          '[RoomForge][OpeningPlacement] type=${type.name} '
          'result=rejected reason=no_wall_near_touch',
        );
      }
      _show('Tocá cerca de una pared para ubicar la $typeLabel.');
      return;
    }
    final wall = host.$1;
    final wallIndex = draft.walls.indexWhere((value) => value.id == wall.id);
    final fitted = _fitOpeningInterval(
      draft: draft,
      wall: wall,
      requestedPosition: host.$3,
      preferredWidth: .2,
      allowShrink: true,
    );
    if (fitted == null) {
      if (kDebugMode) {
        debugPrint(
          '[RoomForge][OpeningPlacement] type=${type.name} '
          'result=rejected reason=no_free_interval wallId=${wall.id}',
        );
      }
      _show('No hay espacio libre en esta parte de la pared.');
      return;
    }
    final candidate = draft.withOpening(
      VisualOpeningDraft(
        id: _nextOpeningId(draft, wallIndex),
        type: switch (type) {
          FloorplanOpeningCandidateType.door => VisualOpeningType.door,
          FloorplanOpeningCandidateType.window => VisualOpeningType.window,
          FloorplanOpeningCandidateType.unknown => VisualOpeningType.unknown,
        },
        wallId: wall.id,
        position: fitted.$1,
        normalizedWidth: fitted.$2,
        manuallyPlaced: true,
      ),
    );
    final errors = candidate.validate();
    if (errors.contains('opening_overlap') ||
        errors.contains('opening_interval_invalid')) {
      _show('No hay espacio libre en esta parte de la pared.');
      return;
    }
    final before = _editState;
    setState(() {
      _rememberEdit(before);
      _visualDraft = candidate;
      _selectPhysicalWall(wall.id);
      _selectedOpening = candidate.openings.length - 1;
      _syncOpeningControllers();
    });
    if (kDebugMode) {
      debugPrint(
        '[RoomForge][OpeningPlacement] type=${type.name} result=success '
        'wallId=${wall.id} position=${fitted.$1} width=${fitted.$2}',
      );
    }
  }

  FloorPoint? _snapWallPoint(FloorPoint point, Size size) {
    final draft = _visualDraft;
    if (draft == null) return null;
    final scale = math.min(
      size.width / _imageWidth,
      size.height / _imageHeight,
    );
    final shownWidth = _imageWidth * scale;
    final shownHeight = _imageHeight * scale;
    const tolerance = 24.0;
    const endpointGuard = 8.0;
    FloorPoint? best;
    var bestDistance = tolerance;
    double distance(FloorPoint candidate) {
      final dx = (point.x - candidate.x) * shownWidth;
      final dz = (point.z - candidate.z) * shownHeight;
      return math.sqrt(dx * dx + dz * dz);
    }

    for (final wall in draft.walls) {
      for (final endpoint in [wall.start, wall.end]) {
        final candidateDistance = distance(endpoint);
        if (candidateDistance < bestDistance) {
          bestDistance = candidateDistance;
          best = endpoint;
        }
      }
    }
    for (final wall in draft.walls) {
      final edge = wall.end - wall.start;
      final squared = edge.dot(edge);
      if (squared <= 0) continue;
      final t = ((point - wall.start).dot(edge) / squared).clamp(0.0, 1.0);
      final projected = wall.start + edge.scale(t);
      final projectedDx = edge.x * shownWidth;
      final projectedDz = edge.z * shownHeight;
      final renderedWallLength = math.sqrt(
        projectedDx * projectedDx + projectedDz * projectedDz,
      );
      final distanceFromStart = t * renderedWallLength;
      final distanceFromEnd = (1 - t) * renderedWallLength;
      if (distanceFromStart < endpointGuard ||
          distanceFromEnd < endpointGuard) {
        continue;
      }
      final candidateDistance = distance(projected);
      if (candidateDistance < bestDistance - 0.001) {
        bestDistance = candidateDistance;
        best = projected;
      }
    }
    return best;
  }

  (String, FloorPoint)? _nearestWallProjection(FloorPoint point, Size size) {
    final draft = _visualDraft;
    if (draft == null) return null;
    final scale = math.min(
      size.width / _imageWidth,
      size.height / _imageHeight,
    );
    final shownWidth = _imageWidth * scale;
    final shownHeight = _imageHeight * scale;
    const tolerance = 24.0;
    (String, FloorPoint)? best;
    var bestDistance = tolerance;
    for (final wall in draft.walls) {
      final edge = wall.end - wall.start;
      final squared = edge.dot(edge);
      if (squared <= 0) continue;
      final t = ((point - wall.start).dot(edge) / squared).clamp(0.0, 1.0);
      final projected = wall.start + edge.scale(t);
      final dx = (point.x - projected.x) * shownWidth;
      final dz = (point.z - projected.z) * shownHeight;
      final distance = math.sqrt(dx * dx + dz * dz);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = (wall.id, projected);
      }
    }
    return best;
  }

  void _createVertex(FloorPoint point, Size size) {
    final draft = _visualDraft;
    final target = _nearestWallProjection(point, size);
    if (draft == null || target == null) {
      _show('Tocá directamente la pared que querés subdividir.');
      return;
    }
    final next = FloorplanVisualDraftEditor.insertVertex(
      draft: draft,
      wallId: target.$1,
      point: target.$2,
    );
    if (!next.isSuccess) {
      _showEditFailure(
        next.errorCode,
        fallback: 'No se pudo crear un vértice válido en esa posición.',
      );
      return;
    }
    final before = _editState;
    setState(() {
      _rememberEdit(before);
      _applyVisualDraft(next.draft!);
      _selectTraceTool(_TraceTool.select);
    });
  }

  void _wallTap(FloorPoint point, Size size) {
    final snapped = _snapWallPoint(point, size);
    if (snapped == null) {
      _show('Tocá cerca de una pared o un vértice existente.');
      return;
    }
    final start = _pendingWallStart;
    if (start == null) {
      setState(() {
        _pendingWallStart = snapped;
        _pendingWallPreview = snapped;
      });
      return;
    }
    final draft = _visualDraft;
    if (draft == null) return;
    final next = FloorplanVisualDraftEditor.addInternalWall(
      draft: draft,
      roomId: _roomIdForEdits,
      start: start,
      end: snapped,
    );
    if (!next.isSuccess) {
      _showEditFailure(
        next.errorCode,
        fallback: 'La nueva pared produciría una geometría inválida.',
      );
      return;
    }
    final before = _editState;
    final previousWallIds = {for (final wall in draft.walls) wall.id};
    setState(() {
      _rememberEdit(before);
      _applyVisualDraft(next.draft!);
      final createdWalls = [
        for (final wall in next.draft!.walls)
          if (!previousWallIds.contains(wall.id)) wall,
      ];
      if (createdWalls.isNotEmpty) {
        _selectPhysicalWall(createdWalls.last.id);
      }
      _pendingWallStart = null;
      _pendingWallPreview = null;
      _selectTraceTool(_TraceTool.select);
    });
  }

  void _perimeterTap(FloorPoint point, Size size) {
    final snapped = _snapWallPoint(point, size) ?? point;
    final start = _pendingWallStart;
    if (start == null) {
      setState(() {
        _pendingWallStart = snapped;
        _pendingWallPreview = snapped;
      });
      return;
    }
    final draft = _visualDraft;
    final wallId = _selectedWallId ?? _wallIdAt(_selectedEdge);
    if (draft == null || wallId == null) return;
    final next = FloorplanVisualDraftEditor.addWallPath(
      draft: draft,
      roomId: _roomIdForEdits,
      wallId: wallId,
      start: start,
      end: snapped,
    );
    if (!next.isSuccess) {
      _showEditFailure(
        next.errorCode,
        fallback: 'La corrección produciría una geometría inválida.',
      );
      return;
    }
    final before = _editState;
    setState(() {
      _rememberEdit(before);
      _applyVisualDraft(next.draft!);
      _pendingWallStart = null;
      _pendingWallPreview = null;
      _selectTraceTool(_TraceTool.select);
    });
  }

  void _removeSelectedOpening() {
    final selected = _selectedOpening;
    final draft = _visualDraft;
    if (selected == null || draft == null) return;
    if (selected < 0 || selected >= draft.openings.length) return;
    final opening = draft.openings[selected];
    final before = _editState;
    setState(() {
      _rememberEdit(before);
      _visualDraft = draft.withoutOpening(opening.id);
      _selectedOpening = null;
      _syncOpeningControllers();
    });
  }

  VisualOpeningDraft? get _selectedVisualOpening {
    final index = _selectedOpening;
    final openings = _visualDraft?.openings;
    if (index == null ||
        openings == null ||
        index < 0 ||
        index >= openings.length) {
      return null;
    }
    return openings[index];
  }

  TextEditingController _openingWidthController(String openingId) =>
      _openingWidths.putIfAbsent(openingId, () {
        final opening = _visualDraft?.opening(openingId);
        return TextEditingController(text: opening?.widthM?.toString() ?? '');
      });

  TextEditingController _openingHeightController(String openingId) =>
      _openingHeights.putIfAbsent(openingId, TextEditingController.new);

  TextEditingController _openingOffsetController(String openingId) =>
      _openingOffsets.putIfAbsent(openingId, () {
        final opening = _visualDraft?.opening(openingId);
        return TextEditingController(
          text: opening?.offsetFromWallStartM?.toString() ?? '',
        );
      });

  TextEditingController _openingSillController(String openingId) =>
      _openingSills.putIfAbsent(openingId, TextEditingController.new);

  void _setOpeningWidth(String openingId, String text) =>
      _commitOpeningDimension(openingId, parseMetres(text), width: true);

  void _setOpeningHeight(String openingId, String text) =>
      _commitOpeningDimension(openingId, parseMetres(text), height: true);

  void _setOpeningOffset(String openingId, String text) =>
      _commitOpeningDimension(
        openingId,
        _parseNonNegativeMetres(text),
        offset: true,
      );

  void _setOpeningSill(String openingId, String text) =>
      _commitOpeningDimension(
        openingId,
        _parseNonNegativeMetres(text),
        sill: true,
      );

  double? _parseNonNegativeMetres(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    return value == null || !value.isFinite || value < 0 ? null : value;
  }

  void _commitOpeningDimension(
    String openingId,
    double? meters, {
    bool width = false,
    bool height = false,
    bool offset = false,
    bool sill = false,
  }) {
    final draft = _visualDraft;
    final opening = draft?.opening(openingId);
    final valid =
        meters != null &&
        meters.isFinite &&
        ((offset || sill) ? meters >= 0 : meters > 0);
    if (draft == null || opening == null || !valid) {
      if (meters != null) {
        _show(
          (offset || sill)
              ? 'La distancia debe ser un número válido mayor o igual a cero.'
              : 'Ingresá una medida positiva y válida.',
        );
      }
      return;
    }
    final updated = opening.copyWith(
      widthM: width ? meters : null,
      heightM: height ? meters : null,
      offsetFromWallStartM: offset ? meters : null,
      sillHeightM: sill ? meters : null,
    );
    final wallLength = opening.wallId == null
        ? null
        : draft.authoritativeWallLength(opening.wallId!)?.meters;
    final physicalOffset = wallLength != null && updated.widthM != null
        ? updated.offsetFromWallStartM ??
              (updated.position == null
                  ? null
                  : updated.position! * wallLength - updated.widthM! / 2)
        : null;
    if (wallLength != null &&
        updated.widthM != null &&
        physicalOffset != null &&
        (physicalOffset < -1e-9 ||
            physicalOffset + updated.widthM! > wallLength + 1e-9)) {
      _show('El ancho no cabe en esta posición de la pared.');
      return;
    }
    final projected =
        wallLength != null && updated.widthM != null && physicalOffset != null
        ? updated.copyWith(
            position: (physicalOffset + updated.widthM! / 2) / wallLength,
            normalizedWidth: updated.widthM! / wallLength,
            offsetFromWallStartM: physicalOffset
                .clamp(0.0, wallLength)
                .toDouble(),
          )
        : updated;
    final candidate = draft.withOpening(projected);
    final errors = candidate.validate();
    if (errors.contains('opening_exceeds_wall_length')) {
      _show('El ancho y la distancia exceden el largo de la pared.');
      return;
    }
    if (errors.contains('opening_exceeds_wall_height')) {
      _show('El alto de la abertura excede el alto de la pared.');
      return;
    }
    if (errors.contains('opening_physical_dimension_invalid')) {
      _show('Las dimensiones de la abertura no son válidas.');
      return;
    }
    if (errors.contains('opening_overlap')) {
      _show('Ese ancho se superpone con otra abertura de la pared.');
      return;
    }
    final before = _editState;
    setState(() {
      _rememberEdit(before, measurementWallId: 'opening:$openingId');
      _visualDraft = candidate;
    });
  }

  void _tap(TapDownDetails details, Size size) {
    if (_mode != _TraceMode.trace || _source == null) return;
    final point = _point(details.localPosition, size);
    if (point == null) return;
    if (_closed) {
      if (_splitWallPending) return _splitSelectedWall(point);
      if (_tool == _TraceTool.vertex) {
        final hit = _nearestTraceTarget(point, size);
        if (hit?.kind == _TraceHitKind.vertex) {
          return _selectEntityAt(point, size);
        }
        return _createVertex(point, size);
      }
      if (_tool == _TraceTool.perimeter) return _perimeterTap(point, size);
      if (_tool == _TraceTool.wall) return _wallTap(point, size);
      if (_tool == _TraceTool.door) {
        return _placeOpening(point, FloorplanOpeningCandidateType.door, size);
      }
      if (_tool == _TraceTool.window) {
        return _placeOpening(point, FloorplanOpeningCandidateType.window, size);
      }
      _selectEntityAt(point, size);
    } else {
      setState(() {
        _openPoints.add(point);
        _candidates = const [];
      });
    }
  }

  void _selectEntityAt(FloorPoint point, Size size) {
    final hit = _nearestTraceTarget(point, size);
    switch (hit) {
      case _TraceHit(kind: _TraceHitKind.opening, index: final openingIndex):
        final openings = _visualDraft?.openings;
        final opening = openings == null || openingIndex >= openings.length
            ? null
            : openings[openingIndex];
        final wallId = opening?.wallId;
        setState(() {
          if (wallId != null) _selectPhysicalWall(wallId);
          _selectedOpening = openingIndex;
          _selectedVertex = null;
        });
        return;
      case _TraceHit(kind: _TraceHitKind.vertex, index: final vertexIndex):
        setState(() {
          _selectedOpening = null;
          _selectedVertex = vertexIndex;
          _selectedWallId = null;
        });
        return;
      case _TraceHit(kind: _TraceHitKind.wall, index: final wallIndex):
        setState(() => _selectPhysicalWall(_physicalWallIdAt(wallIndex)));
        return;
      case null:
        setState(() {
          _selectedOpening = null;
          _selectedVertex = null;
        });
        return;
    }
  }

  void _dragDown(DragDownDetails details, Size size) {
    if (_mode != _TraceMode.trace || !_closed) return;
    if (_tool == _TraceTool.vertex ||
        _tool == _TraceTool.wall ||
        _tool == _TraceTool.perimeter) {
      return;
    }
    final point = _point(details.localPosition, size);
    if (point == null) return;
    final hit = _nearestTraceTarget(point, size);
    // Raw pointer events also reach this Listener while the enclosing form
    // wins a vertical scroll gesture. An opening must therefore have been
    // explicitly selected by a preceding tap before a drag can move it;
    // otherwise scrolling over its marker silently changes its position.
    // Vertices keep their direct press-and-drag interaction.
    final hitOpening = switch (hit) {
      _TraceHit(kind: _TraceHitKind.opening, index: final index) => index,
      _ => null,
    };
    final opening = hitOpening != null && _selectedOpening == hitOpening
        ? hitOpening
        : null;
    final vertex = switch (hit) {
      _TraceHit(kind: _TraceHitKind.vertex, index: final index) => index,
      _ => null,
    };
    if (opening == null && vertex == null) {
      _dragStartDraft = null;
      _dragJunctionPoint = null;
      _dragIncidentWallIds = const {};
      _openingDragValid = false;
      return;
    }
    final draft = _visualDraft;
    final junction = vertex == null ? null : _points[vertex];
    final incidentWallIds = draft == null || junction == null
        ? const <String>{}
        : {
            for (final wall in draft.walls)
              if (wall.start.distanceTo(junction) <= 1e-6 ||
                  wall.end.distanceTo(junction) <= 1e-6)
                wall.id,
          };
    setState(() {
      _selectedOpening = opening;
      _selectedVertex = vertex;
      _dragStartDraft = draft;
      _dragJunctionPoint = junction;
      _dragIncidentWallIds = incidentWallIds;
      _openingDragValid = opening != null;
    });
  }

  void _dragUpdate(DragUpdateDetails details, Size size) {
    if (_mode != _TraceMode.trace) return;
    final point = _point(details.localPosition, size);
    if (point == null) return;
    if ((_tool == _TraceTool.wall || _tool == _TraceTool.perimeter) &&
        _pendingWallStart != null) {
      setState(() {
        _pendingWallPreview = _tool == _TraceTool.wall
            ? _snapWallPoint(point, size)
            : _snapWallPoint(point, size) ?? point;
      });
      return;
    }
    if (_dragStartDraft == null) return;
    final selectedOpening = _selectedOpening;
    if (selectedOpening != null) {
      final original = _dragStartDraft;
      if (original == null ||
          selectedOpening < 0 ||
          selectedOpening >= original.openings.length) {
        return;
      }
      final host = _snapOpeningHost(point, size);
      if (host == null) {
        _openingDragValid = false;
        return;
      }
      final opening = original.openings[selectedOpening];
      final updated = _openingMovedTo(
        draft: original,
        opening: opening,
        wall: host.$1,
        requestedPosition: host.$3,
      );
      if (updated == null) {
        _openingDragValid = false;
        return;
      }
      final candidate = original.withOpening(updated);
      if (candidate.validate().any(
        (error) =>
            error == 'opening_interval_invalid' ||
            error == 'opening_exceeds_wall_length' ||
            error == 'opening_overlap',
      )) {
        _openingDragValid = false;
        return;
      }
      setState(() {
        _visualDraft = candidate;
        _selectedWallId = host.$1.id;
        _selectedEdge = _edgeForWallId(host.$1.id) ?? 0;
        _openingDragValid = true;
      });
      return;
    }
    final selected = _selectedVertex;
    if (selected == null) return;
    final original = _dragStartDraft;
    final junction = _dragJunctionPoint;
    if (original == null || junction == null || _dragIncidentWallIds.isEmpty) {
      return;
    }
    final next = FloorplanVisualDraftEditor.moveJunction(
      draft: original,
      originalPoint: junction,
      incidentWallIds: _dragIncidentWallIds,
      point: point,
      validateGeometry: false,
    );
    if (next.isSuccess) {
      setState(() {
        _applyVisualDraft(next.draft!);
      });
    } else {
      _showEditFailure(
        next.errorCode,
        fallback: 'El contorno se cruza o no forma un ambiente válido.',
      );
    }
  }

  void _dragEnd(DragEndDetails _) {
    final before = _dragStartDraft;
    final movedOpening =
        before != null &&
        _selectedOpening != null &&
        _dragJunctionPoint == null;
    final openingPlacementValid = _openingDragValid;
    _dragStartDraft = null;
    _dragJunctionPoint = null;
    _dragIncidentWallIds = const {};
    _openingDragValid = false;
    if (before == null) return;
    if (movedOpening) {
      final preview = _visualDraft;
      if (!openingPlacementValid || preview == null) {
        setState(() => _applyVisualDraft(before));
        _show('No hay espacio libre en esta parte de la pared.');
        return;
      }
      final original = _TraceEditState(draft: before);
      if (!_sameTraceEditState(original, _editState)) _rememberEdit(original);
      final selected = _selectedOpening;
      final wallId = selected == null || selected >= preview.openings.length
          ? null
          : preview.openings[selected].wallId;
      if (wallId != null) {
        setState(() {
          _selectPhysicalWall(wallId);
          _selectedOpening = selected;
        });
      }
      _syncOpeningControllers();
      return;
    }
    final preview = _visualDraft;
    final reconciled = preview == null
        ? null
        : FloorplanVisualDraftEditor.reconcileRoomRegions(draft: preview);
    if (reconciled == null || !reconciled.isSuccess) {
      setState(() => _applyVisualDraft(before));
      _show('El movimiento produciría una geometría inválida.');
      return;
    }
    setState(() => _applyVisualDraft(reconciled.draft!));
    final original = _TraceEditState(draft: before);
    if (!_sameTraceEditState(original, _editState)) _rememberEdit(original);
  }

  CapturedRoom? get _metricRoom {
    final reference = parseMetres(_reference.text);
    final height = parseMetres(_height.text);
    final draft = _visualDraft;
    final roomId = _roomIdForEdits;
    final trace = _currentTrace;
    final wallDimensions = draft == null
        ? const <CapturedWallDimension>[]
        : [
            for (final wallId in draft.wallIdsForRoom(roomId))
              if (draft.authoritativeWallLength(wallId) case final length?)
                if (draft.authoritativeWallHeight(wallId)
                    case final wallHeight?)
                  CapturedWallDimension(
                    wallId: wallId,
                    lengthM: length.meters,
                    heightM: wallHeight.meters,
                  ),
          ];
    final hasCompleteWallDimensions =
        draft != null &&
        wallDimensions.length == draft.wallIdsForRoom(roomId).length;
    if (!_closed ||
        (_legacy && (height == null || reference == null)) ||
        (!_legacy && !hasCompleteWallDimensions && height == null)) {
      return null;
    }
    try {
      if (_legacy) {
        return buildCalibratedFloorplanTraceRoom(
          id: widget.roomId ?? 'preview',
          name: _name.text.trim().isEmpty ? 'Ambiente' : _name.text,
          normalizedTrace: trace,
          imageWidth: _imageWidth,
          imageHeight: _imageHeight,
          referenceEdge: _referenceEdge,
          referenceMeters: reference!,
          height: height!,
        );
      }
      final room = buildWallBasedFloorplanRoom(
        id: widget.roomId ?? 'preview',
        name: _name.text.trim().isEmpty ? 'Ambiente' : _name.text,
        normalizedTrace: trace,
        imageWidth: _imageWidth,
        imageHeight: _imageHeight,
        height: hasCompleteWallDimensions ? null : height,
        wallDimensions: hasCompleteWallDimensions ? wallDimensions : const [],
      ).copyWith(references: _documentMeasurements);
      return room;
    } on ArgumentError {
      return null;
    }
  }

  /// Solver input derived from the document. Stable wall IDs are adapted to
  /// the edge-indexed solver API only here. Pending provider detections are
  /// excluded on purpose: they cannot influence authoritative scale until the
  /// user accepts them explicitly.
  List<ReferenceMeasurement> get _documentMeasurements {
    final draft = _visualDraft;
    final roomId = _documentRoomId;
    if (draft == null || roomId == null) return const [];
    return [
      for (final evidence in draft.authoritativeLengthMeasurements)
        if (draft.edgeIndexForWall(roomId, evidence.wallId!) case final edge?)
          ReferenceMeasurement(
            edgeIndex: edge,
            referenceMeters: evidence.meters,
            provenance: WallMeasurementProvenance.fromWire(evidence.provenance),
          ),
    ];
  }

  FloorplanMetricSolution get _metricSolution => solveFloorplanMetrics(
    semanticContour: [
      for (final point in _currentTrace)
        FloorPoint(point.x * _imageWidth, point.z * _imageHeight),
    ],
    existingMeasurements: _documentMeasurements,
    // Provider candidates remain review evidence until explicitly accepted.
    measurementCandidates: const [],
  );

  List<ReferenceMeasurement> get _measurements =>
      _legacy ? _documentMeasurements : _metricSolution.measurements;

  bool get _hasCompleteAuthoritativeMeasurements {
    final draft = _visualDraft;
    if (draft == null || draft.walls.isEmpty) return false;
    final authoritative = {
      for (final evidence in draft.authoritativeLengthMeasurements)
        evidence.wallId,
    };
    return draft.walls.every((wall) => authoritative.contains(wall.id));
  }

  String _measurementEvidenceId(String wallId) => '$wallId:measurement';

  TextEditingController? _wallLengthController(int edge) {
    final wallId = _physicalWallIdAt(edge);
    return wallId == null
        ? null
        : _wallLengths.putIfAbsent(wallId, TextEditingController.new);
  }

  TextEditingController? _wallHeightController(int edge) {
    final wallId = _physicalWallIdAt(edge);
    return wallId == null
        ? null
        : _wallHeights.putIfAbsent(wallId, TextEditingController.new);
  }

  void _setWallHeight(int edge, String text) {
    final draft = _visualDraft;
    final wallId = _physicalWallIdAt(edge);
    if (text.trim().isEmpty) {
      _clearWallDimension(edge, VisualWallMeasurementDimension.height);
      return;
    }
    final meters = parseMetres(text);
    if (draft == null || wallId == null || meters == null || meters <= 0)
      return;
    final next = draft.withMeasurement(
      VisualWallMeasurementEvidence(
        id: '$wallId:height',
        wallId: wallId,
        meters: meters,
        provenance: WallMeasurementProvenance.user.wire,
        dimension: VisualWallMeasurementDimension.height,
      ),
    );
    if (!_canApplyWallDimension(next)) return;
    final before = _editState;
    setState(() {
      _rememberEdit(before, measurementWallId: '$wallId:height');
      _visualDraft = next;
    });
  }

  bool _canApplyWallDimension(FloorplanVisualDraft candidate) {
    final errors = candidate.validate();
    if (errors.contains('opening_exceeds_wall_length')) {
      _show('El largo no puede dejar una abertura fuera de la pared.');
      return false;
    }
    if (errors.contains('opening_exceeds_wall_height')) {
      _show('El alto no puede ser menor que el alto de una abertura.');
      return false;
    }
    return errors.isEmpty;
  }

  void _clearWallDimension(int edge, VisualWallMeasurementDimension dimension) {
    final draft = _visualDraft;
    final wallId = _physicalWallIdAt(edge);
    if (draft == null || wallId == null) return;
    final matching = [
      for (final evidence in draft.measurements)
        if (evidence.wallId == wallId && evidence.dimension == dimension)
          evidence,
    ];
    if (matching.isEmpty) return;
    final before = _editState;
    setState(() {
      _rememberEdit(before, measurementWallId: '$wallId:${dimension.name}');
      _visualDraft = draft.copyWith(
        measurements: [
          for (final evidence in draft.measurements)
            if (!(evidence.wallId == wallId && evidence.dimension == dimension))
              evidence,
        ],
      );
      if (dimension == VisualWallMeasurementDimension.length) {
        _syncOpeningControllers();
      }
    });
  }

  String _metresLabel(double meters) =>
      '${meters.toStringAsFixed(2).replaceAll('.', ',')} m';

  String _evidenceProvenanceLabel(VisualWallMeasurementEvidence evidence) =>
      switch (WallMeasurementProvenance.fromWire(evidence.provenance)) {
        WallMeasurementProvenance.aiDetected => 'detectada',
        WallMeasurementProvenance.derivedScale ||
        WallMeasurementProvenance.derivedGeometry => 'calculada',
        WallMeasurementProvenance.user => 'confirmada',
        WallMeasurementProvenance.unresolved => 'pendiente',
      };

  /// Pending evidence attached to the wall currently open in the editor.
  List<VisualWallMeasurementEvidence> get _pendingWallMeasurements {
    final wallId = _selectedWallId;
    final draft = _visualDraft;
    if (draft == null || wallId == null) return const [];
    return [
      for (final evidence in draft.measurements)
        if (evidence.wallId == wallId && evidence.requiresReview) evidence,
    ];
  }

  /// Accepted provider evidence on the selected wall: it keeps its origin but
  /// is authoritative, so the user can see what resolved the scale.
  List<VisualWallMeasurementEvidence> get _acceptedProviderMeasurements {
    final wallId = _selectedWallId;
    final draft = _visualDraft;
    if (draft == null || wallId == null) return const [];
    return [
      for (final evidence in draft.measurements)
        if (evidence.wallId == wallId &&
            !evidence.requiresReview &&
            evidence.provenance != WallMeasurementProvenance.user.wire)
          evidence,
    ];
  }

  List<VisualWallMeasurementEvidence> get _unassignedMeasurements =>
      _visualDraft?.unassignedMeasurements ?? const [];

  /// Persists one user-entered wall length. Text fields stay temporary input;
  /// the document owns the evidence and the undo history owns the change. A
  /// typed value replaces only length evidence for that wall. Height and other
  /// evidence are independent document records.
  void _setWallLength(int edge, String text) {
    if (text.trim().isEmpty) {
      _clearWallDimension(edge, VisualWallMeasurementDimension.length);
      return;
    }
    if (!_commitWallLength(edge, parseMetres(text))) setState(() {});
  }

  /// Returns true when the document changed and the caller must not rebuild.
  bool _commitWallLength(int edge, double? meters) {
    final draft = _visualDraft;
    final wallId = _physicalWallIdAt(edge);
    if (draft == null || wallId == null) return false;
    final evidenceId = _measurementEvidenceId(wallId);
    final existing = draft.measurement(evidenceId);
    final valid = meters != null && meters.isFinite && meters > 0;
    if (!valid && existing == null) return false;
    if (valid &&
        existing != null &&
        existing.meters == meters &&
        !existing.requiresReview &&
        existing.provenance == WallMeasurementProvenance.user.wire) {
      return false;
    }
    FloorplanVisualDraft? replacement;
    if (valid) {
      var next = draft;
      for (final value in draft.measurements) {
        if (value.wallId == wallId &&
            value.dimension == VisualWallMeasurementDimension.length) {
          next = next.withoutMeasurement(value.id);
        }
      }
      replacement = next.withMeasurement(
        VisualWallMeasurementEvidence(
          id: evidenceId,
          wallId: wallId,
          meters: meters,
          provenance: WallMeasurementProvenance.user.wire,
        ),
      );
      if (!_canApplyWallDimension(replacement)) return false;
    }
    final before = _editState;
    setState(() {
      _rememberEdit(before, measurementWallId: '$wallId:length');
      if (!valid) {
        _visualDraft = draft.withoutMeasurement(evidenceId);
        _syncOpeningControllers();
        return;
      }
      _visualDraft = replacement!;
      _syncOpeningControllers();
    });
    return true;
  }

  /// Explicit acceptance of one provider measurement. Provenance is preserved
  /// and only the review status changes: the value becomes eligible for
  /// authoritative scale without pretending to be a user entry.
  void _confirmMeasurement(VisualWallMeasurementEvidence evidence) {
    final draft = _visualDraft;
    final current = draft?.measurement(evidence.id);
    if (draft == null || current == null || !current.requiresReview) return;
    final wallId = current.wallId;
    if (!current.meters.isFinite || current.meters <= 0) {
      _show('La medida detectada no contiene un valor físico válido.');
      return;
    }
    if (current.provenance != WallMeasurementProvenance.aiDetected.wire) {
      _show('Solo una medida detectada por IA puede confirmarse desde aquí.');
      return;
    }
    if (wallId == null || !draft.walls.any((wall) => wall.id == wallId)) {
      _show('Asociá la medida a una pared válida antes de confirmarla.');
      return;
    }
    final conflicts = draft.authoritativeMeasurements.any(
      (other) =>
          other.id != current.id &&
          other.wallId == wallId &&
          other.dimension == current.dimension,
    );
    if (conflicts) {
      _show('Ya existe una medida confirmada para esta dimensión de la pared.');
      return;
    }
    final candidate = draft.withMeasurement(
      current.copyWith(requiresReview: false),
    );
    if (candidate.validate().contains('measurement_authoritative_conflict')) {
      _show('La medida entra en conflicto con otra medida confirmada.');
      return;
    }
    final before = _editState;
    setState(() {
      _rememberEdit(
        before,
        measurementWallId: '$wallId:${current.dimension.name}',
      );
      _visualDraft = candidate;
    });
  }

  /// Explicit acceptance of a proposal shown for the selected wall. It is
  /// persisted as provider evidence, never as a manually entered value.
  bool _acceptCandidate(WallMeasurementCandidate candidate, int edge) {
    final draft = _visualDraft;
    final wallId = _physicalWallIdAt(edge);
    final meters = candidate.meters;
    if (draft == null || wallId == null || meters == null) return false;
    final existing = draft.wallLength(wallId);
    if (existing != null &&
        existing.provenance == WallMeasurementProvenance.user.wire &&
        !existing.requiresReview) {
      _show('La pared ya tiene una medida confirmada por la persona usuaria.');
      return false;
    }
    var next = draft;
    for (final value in draft.measurements) {
      if (value.wallId == wallId &&
          value.dimension == VisualWallMeasurementDimension.length) {
        next = next.withoutMeasurement(value.id);
      }
    }
    final replacement = next.withMeasurement(
      VisualWallMeasurementEvidence(
        id: _measurementEvidenceId(wallId),
        wallId: wallId,
        meters: meters,
        provenance: WallMeasurementProvenance.aiDetected.wire,
        lineageId: candidate.id,
      ),
    );
    if (!_canApplyWallDimension(replacement)) return false;
    final before = _editState;
    setState(() {
      _rememberEdit(before, measurementWallId: '$wallId:length');
      _visualDraft = replacement;
    });
    return true;
  }

  /// Recovers unassigned evidence. Identity, value, provenance, review status
  /// and extra metadata are preserved; a rejected target never mutates the
  /// document.
  bool _associateMeasurement(
    VisualWallMeasurementEvidence evidence,
    int? edge,
  ) {
    final draft = _visualDraft;
    final wallId = edge == null ? null : _physicalWallIdAt(edge);
    final targetWall = wallId == null
        ? null
        : draft?.walls.where((wall) => wall.id == wallId).firstOrNull;
    final roomId = targetWall?.roomIds.firstOrNull ?? _documentRoomId;
    if (draft == null || roomId == null || wallId == null) return false;
    final associated = draft.associateMeasurement(
      roomId: roomId,
      wallId: wallId,
      measurementId: evidence.id,
    );
    if (associated == null) return false;
    final before = _editState;
    setState(() {
      _rememberEdit(before, measurementWallId: wallId);
      _visualDraft = associated;
    });
    return true;
  }

  String _measurementLabel(int wallIndex, FloorplanMetricSolution solution) {
    final wallId = _physicalWallIdAt(wallIndex);
    final edge = _edgeForWallId(wallId);
    if (edge == null) return 'Estado: Pendiente';
    final measurement = solution.measurements
        .where((value) => value.edgeIndex == edge)
        .firstOrNull;
    if (measurement == null) return 'Estado: Pendiente';
    final source = switch (measurement.provenance) {
      WallMeasurementProvenance.aiDetected => 'detectada',
      WallMeasurementProvenance.derivedScale ||
      WallMeasurementProvenance.derivedGeometry => 'calculada',
      WallMeasurementProvenance.user => 'confirmada',
      WallMeasurementProvenance.unresolved => 'pendiente',
    };
    return '${measurement.referenceMeters.toStringAsFixed(2).replaceAll('.', ',')} m · $source';
  }

  bool _needsReview(WallMeasurementCandidate candidate) =>
      candidate.status != WallMeasurementCandidateStatus.ignored &&
      (candidate.status == WallMeasurementCandidateStatus.ambiguous ||
          candidate.status == WallMeasurementCandidateStatus.unresolved ||
          candidate.edgeIndex == null);

  String _candidateReviewLabel(WallMeasurementCandidate candidate) {
    final meters = candidate.meters;
    if (meters == null)
      return '${candidate.literalText} · unidad sin confirmar';
    return '${meters.toStringAsFixed(2).replaceAll('.', ',')} m · ambiguo / sin asignar';
  }

  String? _validationMessageFor(List<String> errors) {
    if (errors.isEmpty) return null;
    if (errors.any(
      (error) =>
          error.startsWith('wall_') ||
          error.startsWith('room_') ||
          error == 'version_unsupported',
    )) {
      return 'El contorno se cruza o no forma un ambiente válido.';
    }
    if (errors.any((error) => error.startsWith('measurement_'))) {
      return 'Las medidas ingresadas no son compatibles entre sí. Revisá las paredes resaltadas.';
    }
    if (errors.any((error) => error.startsWith('opening_'))) {
      return 'Revisá las puertas o ventanas: alguna queda fuera de su pared o se superpone.';
    }
    return 'No se pudo validar el plano. Revisá la geometría y sus medidas.';
  }

  void _logFinalValidationFailure(String reason) {
    if (!kDebugMode) return;
    debugPrint(
      '[RoomForge][FloorplanValidation] result=rejected reason=$reason '
      'roomId=${_documentRoomId ?? 'new'}',
    );
  }

  bool _hasBlockingMetricInconsistency(CapturedRoom room) {
    return hasContradictoryConfirmedWallLengths(room);
  }

  Future<void> _save() async {
    final source = _source;
    final reference = parseMetres(_reference.text);
    final height = parseMetres(_height.text);
    final draft = _visualDraft;
    if (source == null) return _show('Elegí una imagen para trazar.');
    if (_restorationProblem != null) {
      return _show(
        'El documento visual guardado no se pudo leer. Volvé a trazar el '
        'ambiente para reemplazarlo.',
      );
    }
    if (_points.length < 3) return _show('Marcá al menos tres puntos.');
    if (!_closed || draft == null) {
      return _show('Cerrá el contorno antes de guardar.');
    }
    if (_legacy && reference == null) {
      return _show('Ingresá una medida real válida.');
    }
    final wallIds = [for (final wall in draft.walls) wall.id];
    final hasCompleteWallDimensions = wallIds.every(
      (wallId) =>
          draft.authoritativeWallLength(wallId) != null &&
          draft.authoritativeWallHeight(wallId) != null,
    );
    if (_legacy && height == null) {
      return _show('Ingresá una altura válida.');
    }
    if (!_legacy && !hasCompleteWallDimensions && height == null) {
      return _show('Completá el largo y alto de cada pared.');
    }
    final documentErrors = draft.validate();
    if (_validationMessageFor(documentErrors) case final message?) {
      _logFinalValidationFailure(documentErrors.join(','));
      return _show(message);
    }
    final metricRoom = _metricRoom;
    if (metricRoom == null) {
      _logFinalValidationFailure('canonical_contour_invalid');
      return _show('El contorno se cruza o no forma un ambiente válido.');
    }
    if (_hasBlockingMetricInconsistency(metricRoom)) {
      _logFinalValidationFailure('measurement_constraints_inconsistent');
      return _show(
        'Las medidas ingresadas no son compatibles entre sí. Revisá las paredes resaltadas.',
      );
    }
    final message = await widget.controller.saveFloorplanTrace(
      roomId: widget.roomId,
      name: _name.text.trim(),
      sourceId: source.sourceId,
      contentType: source.contentType,
      imageWidth: _imageWidth,
      imageHeight: _imageHeight,
      normalizedTrace: _currentTrace,
      referenceEdge: _legacy ? _referenceEdge : null,
      referenceMeters: reference,
      // Compatibility hint for evidence still held as temporary analysis state
      // (provider candidates). The controller only imports what the document
      // does not already own; derived values are ignored.
      measurements: _measurements,
      visualDraft: draft,
      height: height,
    );
    if (!mounted) return;
    if (message != null) return _show(message);
    _saved = true;
    Navigator.pop(context);
  }

  Future<void> _cancel() async {
    final source = _source;
    final original = widget.roomId == null
        ? null
        : widget.controller.traceForRoom(widget.roomId!);
    if (!_saved && source != null && source.sourceId != original?.sourceId) {
      await widget.controller.discardFloorplanSource(source.sourceId);
    }
    if (mounted) Navigator.pop(context);
  }

  VoidCallback? get _primaryAction => _loading
      ? null
      : !_legacy &&
            !_hasCompleteAuthoritativeMeasurements &&
            !_metricSolution.hasScale
      ? () => _show('Ingresá una medida real en la pared seleccionada.')
      : _save;

  String get _primaryActionLabel =>
      !_legacy &&
          !_hasCompleteAuthoritativeMeasurements &&
          !_metricSolution.hasScale
      ? 'Completar 1 dato pendiente'
      : 'Confirmar ambiente';

  Future<void> _showVisualizationSettings() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => StatefulBuilder(
      builder: (context, setSheetState) {
        void update(VoidCallback change) {
          setState(change);
          setSheetState(() {});
        }

        Widget toggle(
          Key key,
          String label,
          bool value,
          ValueChanged<bool> onChanged,
        ) => SwitchListTile(
          key: key,
          dense: true,
          title: Text(label),
          value: value,
          onChanged: onChanged,
        );

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Visualización',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('floorplan-clean-view'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        fixedSize: null,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => update(() => _cleanView = !_cleanView),
                      child: Text(
                        _cleanView ? 'Mostrar trazos' : 'Vista limpia',
                      ),
                    ),
                  ],
                ),
              ),
              toggle(
                const ValueKey('visualization-wall-labels'),
                'Etiquetas de paredes',
                _showWallLabels,
                (value) => update(() => _showWallLabels = value),
              ),
              toggle(
                const ValueKey('visualization-rooms'),
                'Ambientes',
                _showRoomLabels,
                (value) => update(() => _showRoomLabels = value),
              ),
              toggle(
                const ValueKey('visualization-vertices'),
                'Vértices',
                _showVertices,
                (value) => update(() => _showVertices = value),
              ),
              toggle(
                const ValueKey('visualization-openings'),
                'Aberturas',
                _showOpenings,
                (value) => update(() => _showOpenings = value),
              ),
              toggle(
                const ValueKey('visualization-overlay'),
                'Trazos',
                _showOverlay,
                (value) => update(() => _showOverlay = value),
              ),
              toggle(
                const ValueKey('visualization-minimap'),
                'Mini mapa',
                _showMiniMap,
                (value) => update(() => _showMiniMap = value),
              ),
            ],
          ),
        );
      },
    ),
  );

  String _openingReviewLabel(InterpretedOpeningProposal opening) {
    final type = switch (opening.type) {
      FloorplanOpeningCandidateType.door => 'Puerta',
      FloorplanOpeningCandidateType.window => 'Ventana',
      FloorplanOpeningCandidateType.unknown => 'Abertura',
    };
    final details = <String>[
      if (opening.position != null)
        'posición ${(opening.position! * 100).toStringAsFixed(0)}%',
      if (opening.normalizedWidth != null)
        'ancho ${(opening.normalizedWidth! * 100).toStringAsFixed(0)}%',
    ];
    final missing = <String>[
      if (opening.position == null) 'posición',
      if (opening.normalizedWidth == null) 'ancho',
    ];
    return [
      if (opening.manuallyPlaced || opening.hasGeometry)
        opening.manuallyPlaced ? 'Manual' : 'IA',
      opening.edgeIndex == null
          ? 'Pared sin confirmar'
          : 'P${opening.edgeIndex! + 1}',
      type,
      ...details,
      if (missing.isNotEmpty) 'falta ${missing.join(' y ')}',
      if (!opening.manuallyPlaced && opening.hasGeometry) 'por confirmar',
    ].join(' · ');
  }

  Widget _persistentReviewPlan({required bool showPlan}) => SafeArea(
    top: false,
    child: Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, 176);
            final canvas = SizedBox.fromSize(
              size: size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    _imageBytes(_source!),
                    key: ValueKey('floorplan-source-${_source!.sourceId}'),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    cacheWidth: math.min(_imageWidth, 1200),
                    errorBuilder: (_, _, _) => const Center(
                      child: Text('No se pudo abrir la imagen.'),
                    ),
                  ),
                  CustomPaint(
                    painter: _NormalizedTracePainter(
                      points: _points,
                      imageWidth: _imageWidth.toDouble(),
                      imageHeight: _imageHeight.toDouble(),
                      closed: _closed,
                      selected: null,
                      selectedEdge: _closed ? _selectedEdge : null,
                      selectedWallId: _selectedWallId,
                      selectedOpening: _selectedOpening,
                      openings: _openingProposals,
                      visualOpenings: _visualDraft?.openings ?? const [],
                      walls: _visualDraft?.walls ?? const [],
                      internalWalls: _internalWalls,
                      rooms: _roomOverlays,
                      showWallLabels: _showWallLabels,
                      showRoomLabels: _showRoomLabels,
                      showVertices: _showVertices,
                      showOpenings: _showOpenings,
                      showOverlay: _showOverlay,
                      cleanView: _cleanView,
                    ),
                  ),
                ],
              ),
            );
            return Column(
              mainAxisSize: showPlan ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (showPlan)
                  Expanded(
                    child: InteractiveViewer(
                      key: const ValueKey('floorplan-persistent-review'),
                      transformationController: _reviewTransform,
                      minScale: 1,
                      maxScale: 5,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapDown: (details) => _selectWall(details, size),
                        child: canvas,
                      ),
                    ),
                  ),
                SizedBox(
                  height: 42,
                  child: ListView.builder(
                    key: const ValueKey('floorplan-wall-selector'),
                    controller: _wallSelectorController,
                    scrollDirection: Axis.horizontal,
                    itemCount: _currentPhysicalWalls.length,
                    itemBuilder: (context, index) {
                      final wall = _currentPhysicalWalls[index];
                      return KeyedSubtree(
                        key: ValueKey('wall-selector-entry-${wall.id}'),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: KeyedSubtree(
                            key: _wallChipKeys.putIfAbsent(
                              wall.id,
                              GlobalKey.new,
                            ),
                            child: ChoiceChip(
                              key: ValueKey('wall-chip-$index'),
                              label: Text('P${index + 1}'),
                              selected: wall.id == _selectedWallId,
                              onSelected: (_) =>
                                  setState(() => _selectPhysicalWall(wall.id)),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('floorplan-correct-geometry'),
                        onPressed: () =>
                            setState(() => _mode = _TraceMode.trace),
                        child: const Text('Corregir geometría'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('floorplan-trace-save'),
                        onPressed: _primaryAction,
                        child: Text(_primaryActionLabel),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final metric = _metricRoom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_cancel());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.roomId == null ? 'Plano o croquis' : 'Editar trazado',
          ),
          leading: IconButton(
            onPressed: _cancel,
            icon: const Icon(Icons.close),
          ),
          actions: [
            if (_source != null && _closed)
              IconButton(
                tooltip: 'Herramientas de edición',
                onPressed: () => setState(
                  () => _editorToolsExpanded = !_editorToolsExpanded,
                ),
                icon: const Icon(Icons.tune),
              ),
          ],
        ),
        bottomNavigationBar: _source != null && _closed
            ? _showMiniMap
                  ? SizedBox(
                      height: 288,
                      child: _persistentReviewPlan(showPlan: true),
                    )
                  : _persistentReviewPlan(showPlan: false)
            : null,
        body: SafeArea(
          child: ListView(
            key: const ValueKey('floorplan-trace-scroll'),
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'RoomForge interpretará la imagen y propondrá un ambiente para revisar. Solo se enviará la geometría confirmada.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('floorplan-room-name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nombre del ambiente',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('floorplan-pick-source'),
                onPressed: _pickSource,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  _source == null ? 'Elegir imagen' : 'Cambiar imagen',
                ),
              ),
              if (_loading) ...[
                const SizedBox(height: 8),
                const Text('Analizando plano...'),
              ],
              if (_source == null && widget.roomId != null) ...[
                const SizedBox(height: 8),
                const Text('La imagen original ya no está disponible.'),
              ],
              if (_source != null) ...[
                const SizedBox(height: 12),
                if (_analysis != null)
                  Text(
                    _analysis!.message,
                    key: const ValueKey('floorplan-analysis-status'),
                  ),
                if (_analysis?.hasCandidate == true)
                  Text(
                    '${_currentPhysicalWalls.length} paredes · $_openingReviewCount aperturas por revisar',
                    key: const ValueKey('floorplan-result-summary'),
                  ),
                if (_openingProposals.any(
                  (opening) =>
                      !opening.hasGeometry || opening.edgeIndex == null,
                )) ...[
                  const SizedBox(height: 8),
                  Card(
                    key: const ValueKey('floorplan-opening-review'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Aperturas detectadas que necesitan geometría',
                          ),
                          const SizedBox(height: 4),
                          for (final opening in _openingProposals)
                            if (!opening.hasGeometry ||
                                opening.edgeIndex == null)
                              Text(_openingReviewLabel(opening)),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_analysis?.status == FloorplanAnalysisStatus.lowConfidence)
                  OutlinedButton(
                    key: const ValueKey('floorplan-manual-fallback'),
                    onPressed: () => setState(() {
                      _openPoints.clear();
                      _visualDraft = null;
                      _closed = false;
                      _candidates = const [];
                      _mode = _TraceMode.trace;
                    }),
                    child: const Text('Trazar manualmente'),
                  ),
                if (_analysis?.hasCandidate == true && _candidates.isEmpty)
                  const Text(
                    'Detectamos el ambiente, pero no encontramos medidas confiables.',
                  ),
                if (_candidates.isNotEmpty)
                  const Text(
                    'Detectamos algunas medidas. Revisalas antes de confirmar.',
                  ),
                const SizedBox(height: 8),
                SegmentedButton<_TraceMode>(
                  key: const ValueKey('trace-mode'),
                  segments: const [
                    ButtonSegment(
                      value: _TraceMode.navigate,
                      label: Text(
                        'Mover / zoom',
                        key: ValueKey('trace-mode-navigate'),
                      ),
                    ),
                    ButtonSegment(
                      value: _TraceMode.trace,
                      label: Text('Trazar', key: ValueKey('trace-mode-edit')),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) =>
                      setState(() => _mode = value.first),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('floorplan-visualization'),
                    onPressed: _showVisualizationSettings,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Visualización'),
                  ),
                ),
                if (_closed &&
                    _mode == _TraceMode.trace &&
                    _editorToolsExpanded) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    label: 'Herramientas de edición del plano',
                    child: SingleChildScrollView(
                      key: const ValueKey('floorplan-editor-tools'),
                      controller: _toolStripController,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final tool in const [
                            _TraceTool.select,
                            _TraceTool.vertex,
                            _TraceTool.wall,
                            _TraceTool.door,
                            _TraceTool.window,
                            _TraceTool.perimeter,
                          ]) ...[
                            ChoiceChip(
                              key: ValueKey(switch (tool) {
                                _TraceTool.select => 'floorplan-tool-select',
                                _TraceTool.vertex => 'floorplan-tool-vertex',
                                _TraceTool.wall => 'floorplan-tool-wall',
                                _TraceTool.door => 'floorplan-tool-door',
                                _TraceTool.window => 'floorplan-tool-window',
                                _TraceTool.perimeter =>
                                  'floorplan-tool-contour',
                              }),
                              avatar: Icon(switch (tool) {
                                _TraceTool.select => Icons.near_me_outlined,
                                _TraceTool.vertex => Icons.control_point,
                                _TraceTool.wall => Icons.architecture_outlined,
                                _TraceTool.door =>
                                  Icons.door_front_door_outlined,
                                _TraceTool.window => Icons.window_outlined,
                                _TraceTool.perimeter => Icons.polyline,
                              }, size: 18),
                              label: Text(switch (tool) {
                                _TraceTool.select => 'Seleccionar',
                                _TraceTool.vertex => 'Vértice',
                                _TraceTool.wall => 'Pared',
                                _TraceTool.door => 'Puerta',
                                _TraceTool.window => 'Ventana',
                                _TraceTool.perimeter => 'Contorno',
                              }),
                              selected: _tool == tool,
                              onSelected: (_) =>
                                  setState(() => _selectTraceTool(tool)),
                            ),
                            if (tool != _TraceTool.perimeter)
                              const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(switch (_tool) {
                    _TraceTool.select =>
                      'Tocá una pared, vértice o propuesta para seleccionarla.',
                    _TraceTool.vertex =>
                      'Tocá una pared para insertar un vértice topológico.',
                    _TraceTool.perimeter =>
                      'Seleccioná una pared exterior y marcá el nuevo recorrido del contorno.',
                    _TraceTool.wall =>
                      'Tocá dos paredes o vértices para agregar una pared interna sin deformar el contorno.',
                    _TraceTool.door =>
                      'Tocá cerca de una pared para ubicar una puerta.',
                    _TraceTool.window =>
                      'Tocá cerca de una pared para ubicar una ventana.',
                  }),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Revisá el contorno propuesto. Las medidas detectadas no se consideran confirmadas hasta que las completes.',
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(constraints.maxWidth, 280);
                    final canvas = SizedBox.fromSize(
                      size: size,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            _imageBytes(_source!),
                            key: ValueKey(
                              'floorplan-source-${_source!.sourceId}',
                            ),
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            cacheWidth: math.min(_imageWidth, 1600),
                            errorBuilder: (_, _, _) => const Center(
                              child: Text('No se pudo abrir la imagen.'),
                            ),
                          ),
                          CustomPaint(
                            key: const ValueKey('floorplan-trace-paint'),
                            painter: _NormalizedTracePainter(
                              points: _points,
                              imageWidth: _imageWidth.toDouble(),
                              imageHeight: _imageHeight.toDouble(),
                              closed: _closed,
                              selected: _selectedVertex,
                              selectedEdge: _closed ? _selectedEdge : null,
                              selectedWallId: _selectedWallId,
                              selectedOpening: _selectedOpening,
                              openings: _openingProposals,
                              visualOpenings:
                                  _visualDraft?.openings ?? const [],
                              walls: _visualDraft?.walls ?? const [],
                              internalWalls: _internalWalls,
                              rooms: _roomOverlays,
                              showWallLabels: _showWallLabels,
                              showRoomLabels: _showRoomLabels,
                              showVertices: _showVertices,
                              showOpenings: _showOpenings,
                              showOverlay: _showOverlay,
                              cleanView: _cleanView,
                              pendingWallStart: _pendingWallStart,
                              pendingWallEnd: _pendingWallPreview,
                            ),
                          ),
                        ],
                      ),
                    );
                    return SizedBox(
                      key: const ValueKey('floorplan-trace-canvas'),
                      height: size.height,
                      child: InteractiveViewer(
                        key: const ValueKey('floorplan-interactive-viewer'),
                        transformationController: _transform,
                        panEnabled: _mode == _TraceMode.navigate,
                        scaleEnabled: _mode == _TraceMode.navigate,
                        minScale: 1,
                        maxScale: 5,
                        child: _mode == _TraceMode.navigate
                            ? GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTapUp: (details) {
                                  final point = _point(
                                    details.localPosition,
                                    size,
                                  );
                                  if (point != null) {
                                    _selectEntityAt(point, size);
                                  }
                                },
                                child: canvas,
                              )
                            : Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (event) => _dragDown(
                                  DragDownDetails(
                                    globalPosition: event.position,
                                    localPosition: event.localPosition,
                                  ),
                                  size,
                                ),
                                onPointerMove: (event) => _dragUpdate(
                                  DragUpdateDetails(
                                    globalPosition: event.position,
                                    localPosition: event.localPosition,
                                    delta: event.delta,
                                  ),
                                  size,
                                ),
                                onPointerUp: (_) => _dragEnd(DragEndDetails()),
                                onPointerCancel: (_) =>
                                    _dragEnd(DragEndDetails()),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (details) => _tap(details, size),
                                  child: canvas,
                                ),
                              ),
                      ),
                    );
                  },
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: const ValueKey('trace-undo'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _undo.isEmpty ? null : _undoEdit,
                      child: const Text('Deshacer'),
                    ),
                    if (_redo.isNotEmpty)
                      TextButton(
                        key: const ValueKey('trace-redo'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: _redoEdit,
                        child: const Text('Rehacer'),
                      ),
                    if (_closed && _tool == _TraceTool.perimeter)
                      TextButton(
                        key: const ValueKey('trace-split-wall'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: () => setState(() {
                          _pendingWallStart = null;
                          _pendingWallPreview = null;
                          _splitWallPending = true;
                        }),
                        child: Text(
                          _splitWallPending ? 'Tocá para dividir' : 'Dividir',
                        ),
                      ),
                    if (_closed &&
                        (_tool == _TraceTool.wall ||
                            _tool == _TraceTool.perimeter) &&
                        _pendingWallStart != null)
                      TextButton(
                        key: const ValueKey('trace-cancel-wall'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: _pendingWallStart == null
                            ? null
                            : () => setState(() {
                                _pendingWallStart = null;
                                _pendingWallPreview = null;
                              }),
                        child: const Text('Cancelar pared'),
                      ),
                    if (_closed && _selectedVertex != null)
                      TextButton(
                        key: const ValueKey('trace-merge-wall'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: canMergeTraceWalls(_points, _selectedVertex!)
                            ? _mergeAtSelectedVertex
                            : null,
                        child: const Text('Unir'),
                      ),
                    if (_closed &&
                        _selectedOpening != null &&
                        _selectedOpening! <
                            (_visualDraft?.openings.length ?? 0))
                      TextButton(
                        key: const ValueKey('trace-remove-opening'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: _removeSelectedOpening,
                        child: const Text('Quitar abertura'),
                      ),
                    if (_closed && _canRemoveSelectedInternalWall)
                      TextButton(
                        key: const ValueKey('trace-remove-wall'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: _removeSelectedInternalWall,
                        child: const Text('Quitar pared'),
                      ),
                    if (_closed && _selectedVertex != null)
                      TextButton(
                        key: const ValueKey('trace-remove'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: _points.length <= 3
                            ? null
                            : _removeSelectedVertex,
                        child: const Text('Quitar vértice'),
                      ),
                    TextButton(
                      key: const ValueKey('trace-reset'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _initialEditState == null
                          ? null
                          : () => setState(() {
                              final before = _editState;
                              _restoreEdit(_initialEditState!);
                              _selectedVertex = null;
                              _referenceEdge = 0;
                              _syncWallLengthControllers();
                              if (!_sameTraceEditState(before, _editState)) {
                                _rememberEdit(before);
                              }
                            }),
                      child: const Text('Reiniciar'),
                    ),
                    if (!_closed)
                      TextButton(
                        key: const ValueKey('trace-close'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: _points.length < 3
                            ? null
                            : () => setState(() {
                                final draft = _draftFromOpenContour();
                                _applyVisualDraft(draft);
                                _closed = true;
                                _initialEditState = _editState;
                              }),
                        child: const Text('Cerrar contorno'),
                      ),
                  ],
                ),
                Text(
                  '${_points.length} ${_points.length == 1 ? 'vértice' : 'vértices'} marcados',
                  key: const ValueKey('trace-vertex-count'),
                ),
                if (_closed) ...[
                  if (_legacy) ...[
                    DropdownButtonFormField<int>(
                      key: const ValueKey('trace-reference-edge'),
                      initialValue: _referenceEdge,
                      decoration: const InputDecoration(
                        labelText: 'Pared de referencia',
                      ),
                      items: [
                        for (var i = 0; i < _points.length; i++)
                          DropdownMenuItem(value: i, child: Text(wallLabel(i))),
                      ],
                      onChanged: (value) =>
                          setState(() => _referenceEdge = value ?? 0),
                    ),
                    TextField(
                      key: const ValueKey('trace-reference-metres'),
                      controller: _reference,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Largo real de esta pared (m)',
                      ),
                    ),
                  ] else ...[
                    Text(
                      _metricSolution.inconsistent
                          ? 'Las medidas detectadas no comparten una escala coherente. Revisalas.'
                          : _metricSolution.hasScale
                          ? '${_currentPhysicalWalls.length} paredes · escala resuelta automáticamente'
                          : 'Reconstruimos el ambiente. Ingresá una medida real para establecer la escala.',
                      key: const ValueKey('floorplan-metric-summary'),
                    ),
                    if (_candidates.any(_needsReview))
                      TextButton.icon(
                        key: const ValueKey('measurement-review-toggle'),
                        onPressed: () =>
                            setState(() => _showAmbiguous = !_showAmbiguous),
                        icon: Icon(
                          _showAmbiguous
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        label: Text(
                          '${_candidates.where(_needsReview).length} medidas por revisar',
                        ),
                      ),
                    if (_showAmbiguous && _candidates.any(_needsReview)) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Medidas detectadas por revisar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      for (final candidate in _candidates.where(_needsReview))
                        Card(
                          key: ValueKey(
                            'measurement-unassigned-${candidate.id}',
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_candidateReviewLabel(candidate)),
                                Text(
                                  'Evidencia detectada: ${candidate.literalText}',
                                ),
                                if (candidate.ambiguityReason != null)
                                  Text(candidate.ambiguityReason!),
                                TextButton(
                                  key: ValueKey(
                                    'measurement-ignore-${candidate.id}',
                                  ),
                                  onPressed: () => setState(() {
                                    _candidates = [
                                      for (final value in _candidates)
                                        value.id == candidate.id
                                            ? value.copyWith(
                                                status:
                                                    WallMeasurementCandidateStatus
                                                        .ignored,
                                              )
                                            : value,
                                    ];
                                  }),
                                  child: const Text('Ignorar'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    if (_unassignedMeasurements.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Medidas sin pared asignada',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      for (final evidence in _unassignedMeasurements)
                        Card(
                          key: ValueKey('evidence-unassigned-${evidence.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_metresLabel(evidence.meters)} · '
                                  '${_evidenceProvenanceLabel(evidence)} · '
                                  'sin pared',
                                ),
                                Row(
                                  children: [
                                    DropdownButton<int>(
                                      key: ValueKey(
                                        'evidence-wall-${evidence.id}',
                                      ),
                                      value: _evidenceTargets[evidence.id],
                                      hint: const Text('Elegí pared'),
                                      items: [
                                        for (
                                          var wallIndex = 0;
                                          wallIndex <
                                              _currentPhysicalWalls.length;
                                          wallIndex++
                                        )
                                          DropdownMenuItem(
                                            value: wallIndex,
                                            child: Text('P${wallIndex + 1}'),
                                          ),
                                      ],
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setState(
                                          () => _evidenceTargets[evidence.id] =
                                              value,
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      key: ValueKey(
                                        'evidence-assign-${evidence.id}',
                                      ),
                                      onPressed: () {
                                        if (!_associateMeasurement(
                                          evidence,
                                          _evidenceTargets[evidence.id],
                                        )) {
                                          _show(
                                            'Elegí una pared del ambiente que '
                                            'todavía no tenga esa dimensión.',
                                          );
                                        }
                                      },
                                      child: const Text('Asociar'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    if (_selectedVisualOpening == null)
                      if (_selectedPhysicalWallIndex case final index?) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              key: const ValueKey('wall-previous'),
                              tooltip: 'Pared anterior',
                              onPressed: _currentPhysicalWalls.length < 2
                                  ? null
                                  : () => setState(() {
                                      final previous =
                                          (index -
                                              1 +
                                              _currentPhysicalWalls.length) %
                                          _currentPhysicalWalls.length;
                                      _selectPhysicalWall(
                                        _physicalWallIdAt(previous),
                                      );
                                    }),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'P${index + 1}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  Text(
                                    'P${index + 1} de ${_currentPhysicalWalls.length}',
                                    key: const ValueKey(
                                      'selected-wall-position',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Text(
                                    'Pared seleccionada',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('wall-next'),
                              tooltip: 'Pared siguiente',
                              onPressed: _currentPhysicalWalls.length < 2
                                  ? null
                                  : () => setState(() {
                                      final next =
                                          (index + 1) %
                                          _currentPhysicalWalls.length;
                                      _selectPhysicalWall(
                                        _physicalWallIdAt(next),
                                      );
                                    }),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        for (final candidate in _candidates.where(
                          (value) =>
                              value.edgeIndex ==
                                  _edgeForWallId(_selectedWallId) &&
                              value.status ==
                                  WallMeasurementCandidateStatus.proposed &&
                              value.meters != null,
                        ))
                          Card(
                            key: ValueKey(
                              'measurement-candidate-${candidate.id}',
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'P${index + 1} · ${candidate.meters!.toStringAsFixed(2).replaceAll('.', ',')} m · detectado',
                                  ),
                                  Text(
                                    'Evidencia detectada: ${candidate.literalText}',
                                  ),
                                  Wrap(
                                    children: [
                                      TextButton(
                                        key: ValueKey(
                                          'measurement-confirm-${candidate.id}',
                                        ),
                                        onPressed: () {
                                          if (!_acceptCandidate(
                                            candidate,
                                            index,
                                          )) {
                                            return;
                                          }
                                          setState(() {
                                            _candidates = [
                                              for (final value in _candidates)
                                                if (value.id != candidate.id)
                                                  value,
                                            ];
                                          });
                                        },
                                        child: const Text('Confirmar'),
                                      ),
                                      TextButton(
                                        key: ValueKey(
                                          'measurement-ignore-${candidate.id}',
                                        ),
                                        onPressed: () => setState(() {
                                          _candidates = [
                                            for (final value in _candidates)
                                              value.id == candidate.id
                                                  ? value.copyWith(
                                                      status:
                                                          WallMeasurementCandidateStatus
                                                              .ignored,
                                                    )
                                                  : value,
                                          ];
                                        }),
                                        child: const Text('Ignorar'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        for (final evidence in _pendingWallMeasurements)
                          Card(
                            key: ValueKey('evidence-review-${evidence.id}'),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'P${index + 1} · '
                                    '${_metresLabel(evidence.meters)} · '
                                    '${_evidenceProvenanceLabel(evidence)} · '
                                    'pendiente de revisión',
                                  ),
                                  TextButton(
                                    key: ValueKey(
                                      'evidence-confirm-${evidence.id}',
                                    ),
                                    onPressed: () =>
                                        _confirmMeasurement(evidence),
                                    child: const Text('Confirmar medida'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        for (final evidence in _acceptedProviderMeasurements)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'P${index + 1} · '
                              '${_metresLabel(evidence.meters)} · '
                              '${_evidenceProvenanceLabel(evidence)} · confirmada',
                              key: ValueKey('evidence-accepted-${evidence.id}'),
                            ),
                          ),
                        TextField(
                          key: ValueKey('trace-wall-$index'),
                          controller: _wallLengthController(index),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (value) => _setWallLength(index, value),
                          decoration: InputDecoration(
                            labelText: 'Longitud (m)',
                            helperText: _measurementLabel(
                              index,
                              _metricSolution,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          key: ValueKey('trace-wall-height-$index'),
                          controller: _wallHeightController(index),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (value) => _setWallHeight(index, value),
                          decoration: InputDecoration(labelText: 'Alto (m)'),
                        ),
                      ],
                  ],
                ],
                if (_selectedVisualOpening case final opening?) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${switch (opening.type) {
                      VisualOpeningType.door => 'Puerta',
                      VisualOpeningType.window => 'Ventana',
                      VisualOpeningType.unknown => 'Abertura',
                    }} · ${_openingHostLabel(opening)}',
                    key: ValueKey('selected-opening-${opening.id}'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (_selectedPhysicalWallIndex case final wallIndex?)
                    Text(
                      'P${wallIndex + 1} de ${_currentPhysicalWalls.length}',
                      key: const ValueKey('selected-opening-wall-position'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (opening.widthM == null ||
                      opening.heightM == null ||
                      opening.offsetFromWallStartM == null ||
                      (opening.type == VisualOpeningType.window &&
                          opening.sillHeightM == null)) ...[
                    const SizedBox(height: 4),
                    Text(
                      opening.type == VisualOpeningType.window
                          ? 'Faltan medidas de esta ventana para completar su geometría física.'
                          : 'Faltan medidas de esta puerta para completar su geometría física.',
                      key: ValueKey('opening-measurement-status-${opening.id}'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    key: ValueKey('trace-opening-width-${opening.id}'),
                    controller: _openingWidthController(opening.id),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (value) => _setOpeningWidth(opening.id, value),
                    decoration: InputDecoration(
                      labelText: 'Ancho (m)',
                      helperText: opening.widthM != null
                          ? null
                          : switch (_estimatedOpeningWidth(opening)) {
                              final estimate? =>
                                '${_metresLabel(estimate)} · Estimado según ${_openingHostLabel(opening)}',
                              null => null,
                            },
                    ),
                  ),
                  if (opening.type == VisualOpeningType.window) ...[
                    const SizedBox(height: 8),
                    TextField(
                      key: ValueKey('trace-opening-sill-${opening.id}'),
                      controller: _openingSillController(opening.id),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (value) => _setOpeningSill(opening.id, value),
                      decoration: const InputDecoration(
                        labelText: 'Altura desde el suelo (m)',
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    key: ValueKey('trace-opening-height-${opening.id}'),
                    controller: _openingHeightController(opening.id),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (value) => _setOpeningHeight(opening.id, value),
                    decoration: const InputDecoration(labelText: 'Alto (m)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: ValueKey('trace-opening-offset-${opening.id}'),
                    controller: _openingOffsetController(opening.id),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (value) => _setOpeningOffset(opening.id, value),
                    decoration: InputDecoration(
                      labelText:
                          'Desde inicio de ${_openingHostLabel(opening)} (m)',
                      helperText: opening.offsetFromWallStartM != null
                          ? null
                          : switch (_estimatedOpeningOffset(opening)) {
                              final estimate? =>
                                '${_metresLabel(estimate)} · Estimado según ${_openingHostLabel(opening)}',
                              null => null,
                            },
                    ),
                  ),
                ],
                if (_legacy)
                  TextField(
                    key: const ValueKey('trace-room-height'),
                    controller: _height,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Altura del ambiente (m)',
                    ),
                  ),
                if (metric != null &&
                    (_legacy || _measurements.length == _points.length)) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Vista previa métrica',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (var i = 0; i < metric.corners.length; i++)
                    Text(
                      '${wallLabel(i)}: ${metres(edgeLengths(metric.corners)[i])}',
                    ),
                  Text(
                    'Superficie estimada: ${squareMetres(polygonArea(metric.corners))}',
                  ),
                  if (metric.height case final height?)
                    Text('Altura: ${metres(height.value)}')
                  else
                    const Text('Alturas independientes por pared'),
                  Text(
                    _legacy
                        ? 'Plano o croquis trazado y calibrado'
                        : 'Plano o croquis con medidas por pared',
                  ),
                ],
              ],
              const SizedBox(height: 16),
              if (!(_source != null && _closed) &&
                  _analysis?.hasCandidate == true)
                OutlinedButton(
                  key: const ValueKey('floorplan-correct-geometry'),
                  onPressed: () => setState(() => _mode = _TraceMode.trace),
                  child: const Text('Corregir geometría'),
                ),
              if (!(_source != null && _closed))
                FilledButton(
                  key: const ValueKey('floorplan-trace-save'),
                  onPressed: _primaryAction,
                  child: Text(_primaryActionLabel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NormalizedTracePainter extends CustomPainter {
  const _NormalizedTracePainter({
    required this.points,
    required this.imageWidth,
    required this.imageHeight,
    required this.closed,
    required this.selected,
    required this.selectedEdge,
    required this.selectedWallId,
    this.selectedOpening,
    required this.openings,
    required this.visualOpenings,
    required this.walls,
    required this.internalWalls,
    required this.rooms,
    required this.showWallLabels,
    required this.showRoomLabels,
    required this.showVertices,
    required this.showOpenings,
    required this.showOverlay,
    required this.cleanView,
    this.pendingWallStart,
    this.pendingWallEnd,
  });

  final List<FloorPoint> points;
  final double imageWidth;
  final double imageHeight;
  final bool closed;
  final int? selected;
  final int? selectedEdge;
  final String? selectedWallId;
  final int? selectedOpening;
  final List<InterpretedOpeningProposal> openings;
  final List<VisualOpeningDraft> visualOpenings;
  final List<VisualWallSegment> walls;
  final List<VisualWallSegment> internalWalls;
  final List<_RoomOverlay> rooms;
  final bool showWallLabels;
  final bool showRoomLabels;
  final bool showVertices;
  final bool showOpenings;
  final bool showOverlay;
  final bool cleanView;
  final FloorPoint? pendingWallStart;
  final FloorPoint? pendingWallEnd;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || imageWidth <= 0 || imageHeight <= 0) return;
    final scale = math.min(size.width / imageWidth, size.height / imageHeight);
    final shown = Size(imageWidth * scale, imageHeight * scale);
    final origin = Offset(
      (size.width - shown.width) / 2,
      (size.height - shown.height) / 2,
    );
    Offset map(FloorPoint point) => Offset(
      origin.dx + point.x * shown.width,
      origin.dy + point.z * shown.height,
    );
    for (final (index, wall) in walls.indexed) {
      final selected = wall.id == selectedWallId;
      if ((!showOverlay || cleanView) && !selected) continue;
      final start = map(wall.start);
      final end = map(wall.end);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = selected ? const Color(0xffc96b31) : const Color(0xff16443c)
          ..strokeWidth = selected ? 6 : 3
          ..strokeCap = StrokeCap.round,
      );
      if (!showWallLabels && !selected) continue;
      final span = end - start;
      final length = span.distance;
      final normal = length <= 0
          ? Offset.zero
          : Offset(-span.dy / length, span.dx / length) * 8;
      final midpoint = Offset.lerp(start, end, .5)! + normal;
      final label = TextPainter(
        text: TextSpan(
          text: 'P${index + 1}',
          style: TextStyle(
            color: selected ? const Color(0xff7a3517) : const Color(0xff16443c),
            fontSize: selected ? 12 : 10,
            fontWeight: FontWeight.w700,
            backgroundColor: const Color(0xeaffffff),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, midpoint - Offset(label.width / 2, label.height / 2));
    }
    if (showRoomLabels && !cleanView) {
      for (final room in rooms) {
        final label = TextPainter(
          text: TextSpan(
            text: room.label,
            style: const TextStyle(
              color: Color(0xff16443c),
              fontSize: 9,
              fontWeight: FontWeight.w500,
              backgroundColor: Color(0xaaffffff),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final center = map(room.center);
        label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
      }
    }
    if (pendingWallStart != null) {
      final previewStart = map(pendingWallStart!);
      canvas.drawCircle(
        previewStart,
        8,
        Paint()..color = const Color(0xff1976a2),
      );
      if (pendingWallEnd != null) {
        final previewEnd = map(pendingWallEnd!);
        canvas.drawLine(
          previewStart,
          previewEnd,
          Paint()
            ..color = const Color(0xff1976a2)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(
          previewEnd,
          8,
          Paint()
            ..color = const Color(0xff1976a2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }
    final path = Path()..moveTo(map(points.first).dx, map(points.first).dy);
    for (final point in points.skip(1)) {
      path.lineTo(map(point).dx, map(point).dy);
    }
    if (closed) path.close();
    if (walls.isEmpty) {
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xff16443c)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    if (walls.isEmpty &&
        closed &&
        points.isNotEmpty &&
        selectedEdge != null &&
        selectedEdge! >= 0 &&
        selectedEdge! < points.length) {
      final edge = selectedEdge!;
      canvas.drawLine(
        map(points[edge]),
        map(points[(edge + 1) % points.length]),
        Paint()
          ..color = const Color(0xffc96b31)
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }
    if (closed && walls.isNotEmpty) {
      for (final (openingIndex, opening) in visualOpenings.indexed) {
        final wall = walls
            .where((value) => value.id == opening.wallId)
            .firstOrNull;
        final selected = openingIndex == selectedOpening;
        if (!opening.hasVisualGeometry ||
            wall == null ||
            ((!showOpenings || cleanView) && !selected)) {
          continue;
        }
        final position = opening.position!;
        final normalizedWidth = opening.normalizedWidth!;
        if (!position.isFinite || !normalizedWidth.isFinite) continue;
        final start = map(wall.start);
        final end = map(wall.end);
        final startT = position - normalizedWidth / 2;
        final endT = position + normalizedWidth / 2;
        final openingStart = Offset.lerp(start, end, startT)!;
        final openingEnd = Offset.lerp(start, end, endT)!;
        final color = switch (opening.type) {
          VisualOpeningType.window => const Color(0xff1976a2),
          VisualOpeningType.door => const Color(0xffb85224),
          VisualOpeningType.unknown => const Color(0xff6b7280),
        };
        canvas.drawLine(
          openingStart,
          openingEnd,
          Paint()
            ..color = color
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
        if (selected) {
          final center = Offset.lerp(start, end, position)!;
          canvas.drawCircle(
            start,
            6,
            Paint()
              ..color = const Color(0xff7a3517)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
          canvas.drawCircle(
            center,
            12,
            Paint()
              ..color = color.withValues(alpha: 0.25)
              ..style = PaintingStyle.fill,
          );
          canvas.drawCircle(openingStart, 7, Paint()..color = color);
          canvas.drawCircle(openingEnd, 7, Paint()..color = color);
        }
        final span = openingEnd - openingStart;
        final length = span.distance;
        if (opening.type == VisualOpeningType.window && length > 0) {
          final parallelOffset = Offset(
            -span.dy / length * 4,
            span.dx / length * 4,
          );
          canvas.drawLine(
            openingStart + parallelOffset,
            openingEnd + parallelOffset,
            Paint()
              ..color = color
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round,
          );
        } else if (opening.type == VisualOpeningType.door && length > 0) {
          // Generic review marker; it does not encode an inferred swing.
          final leaf =
              Offset(-span.dy / length, span.dx / length) *
              math.min(length, 32);
          canvas.drawLine(
            openingStart,
            openingStart + leaf,
            Paint()
              ..color = color
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }
    final visibleVertices = walls.isEmpty
        ? points
        : {
            for (final wall in walls) wall.start,
            for (final wall in walls) wall.end,
          }.toList(growable: false);
    final selectedPoint = selected == null || selected! >= points.length
        ? null
        : points[selected!];
    for (final point in visibleVertices) {
      final isSelected = point == selectedPoint;
      if ((!showVertices || cleanView) && !isSelected) continue;
      canvas.drawCircle(
        map(point),
        isSelected ? 7 : 5,
        Paint()..color = const Color(0xffc96b31),
      );
    }
  }

  @override
  bool shouldRepaint(_NormalizedTracePainter oldDelegate) => true;
}
