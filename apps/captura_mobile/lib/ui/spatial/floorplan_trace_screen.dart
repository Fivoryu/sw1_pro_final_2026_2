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

const _providerUnavailableMessage =
    'La interpretación automática no está disponible temporalmente. '
    'Podés reintentar o corregir el ambiente manualmente.';
const _modelLowConfidenceMessage =
    'No pudimos interpretar este plano con suficiente confianza. '
    'Podés corregir o trazar el ambiente manualmente.';
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
  final _wallLengths = <int, TextEditingController>{};
  final _height = TextEditingController();
  final _transform = TransformationController();
  final _reviewTransform = TransformationController();
  final List<FloorPoint> _points = [];
  LocalTraceSource? _source;
  int _imageWidth = 0;
  int _imageHeight = 0;
  int _referenceEdge = 0;
  int _selectedEdge = 0;
  int? _selectedVertex;
  bool _closed = false;
  bool _loading = false;
  bool _saved = false;
  FloorplanAnalysisResult? _analysis;
  List<InterpretedOpeningProposal> _openingProposals = const [];
  List<WallMeasurementCandidate> _candidates = const [];
  List<ReferenceMeasurement> _restoredMeasurements = const [];
  int _analysisGeneration = 0;
  _TraceMode _mode = _TraceMode.navigate;
  bool _showAmbiguous = false;

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

  List<FloorplanTraceOpening> get _traceOpenings => [
    for (final opening in _openingProposals)
      FloorplanTraceOpening(
        edgeIndex: opening.edgeIndex,
        type: switch (opening.type) {
          FloorplanOpeningCandidateType.door => FloorplanTraceOpeningType.door,
          FloorplanOpeningCandidateType.window =>
            FloorplanTraceOpeningType.window,
          FloorplanOpeningCandidateType.unknown =>
            FloorplanTraceOpeningType.unknown,
        },
        position: opening.position,
        normalizedWidth: opening.normalizedWidth,
        confidence: opening.confidence,
      ),
  ];

  List<InterpretedOpeningProposal> _interpretationOpenings(
    List<FloorplanTraceOpening> openings,
  ) => [
    for (final opening in openings)
      InterpretedOpeningProposal(
        edgeIndex: opening.edgeIndex,
        type: switch (opening.type) {
          FloorplanTraceOpeningType.door => FloorplanOpeningCandidateType.door,
          FloorplanTraceOpeningType.window =>
            FloorplanOpeningCandidateType.window,
          FloorplanTraceOpeningType.unknown =>
            FloorplanOpeningCandidateType.unknown,
        },
        position: opening.position,
        normalizedWidth: opening.normalizedWidth,
        confidence: opening.confidence,
      ),
  ];

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
    _height.text = room == null ? '' : room.height.value.toString();
    if (trace == null) return;
    final bytes = await widget.controller.floorplanSourceBytes(trace.sourceId);
    if (!mounted) return;
    if (bytes == null) {
      setState(() {});
      return;
    }
    setState(() {
      _source = LocalTraceSource(
        sourceId: trace.sourceId,
        contentType: trace.contentType,
        bytes: bytes,
      );
      _imageWidth = trace.imageWidth;
      _imageHeight = trace.imageHeight;
      _points.addAll(trace.vertices);
      _openingProposals = _interpretationOpenings(trace.openings);
      _referenceEdge = trace.referenceEdge ?? 0;
      // The calibration measurement is kept exactly as recorded: rounding it
      // to centimetres here would rescale an untouched retrace.
      if (_legacy && trace.referenceMeters != null) {
        _reference.text = trace.referenceMeters.toString();
      } else if (room != null) {
        _restoredMeasurements = room.references;
        for (final measurement in room.references) {
          if (measurement.provenance != WallMeasurementProvenance.user) {
            continue;
          }
          _wallLengths
              .putIfAbsent(measurement.edgeIndex, TextEditingController.new)
              .text = measurement.referenceMeters
              .toString();
        }
      }
      _closed = true;
      _mode = _TraceMode.trace;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _reference.dispose();
    for (final controller in _wallLengths.values) {
      controller.dispose();
    }
    _height.dispose();
    _transform.dispose();
    _reviewTransform.dispose();
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
        _source = next;
        _imageWidth = decoded.$1;
        _imageHeight = decoded.$2;
        _points
          ..clear()
          ..addAll(analysis.contour);
        _closed = analysis.hasCandidate;
        _analysis = analysis;
        _openingProposals = interpretedRoom?.openings ?? const [];
        _candidates = candidates;
        _mode = analysis.hasCandidate ? _TraceMode.trace : _TraceMode.navigate;
        _referenceEdge = 0;
        _reference.clear();
        for (final controller in _wallLengths.values) {
          controller.clear();
        }
        _selectedEdge = 0;
        _selectedVertex = null;
        _transform.value = Matrix4.identity();
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

  int? _near(FloorPoint point, Size size) {
    final scale = math.min(
      size.width / _imageWidth,
      size.height / _imageHeight,
    );
    final shownWidth = _imageWidth * scale;
    final shownHeight = _imageHeight * scale;
    return nearestTraceVertex(
      point: point,
      vertices: _points,
      renderedImageWidth: shownWidth,
      renderedImageHeight: shownHeight,
    );
  }

  int? _nearEdge(FloorPoint point, Size size) {
    final scale = math.min(
      size.width / _imageWidth,
      size.height / _imageHeight,
    );
    return nearestTraceEdge(
      point: point,
      vertices: _points,
      renderedImageWidth: _imageWidth * scale,
      renderedImageHeight: _imageHeight * scale,
    );
  }

  void _selectWall(TapDownDetails details, Size size) {
    if (!_closed || _points.isEmpty) return;
    final point = _point(details.localPosition, size);
    final edge = point == null ? null : _nearEdge(point, size);
    if (edge != null) setState(() => _selectedEdge = edge);
  }

  void _tap(TapDownDetails details, Size size) {
    if (_mode != _TraceMode.trace || _source == null) return;
    final point = _point(details.localPosition, size);
    if (point == null) return;
    setState(() {
      if (_closed) {
        _selectedVertex = _near(point, size);
      } else {
        _points.add(point);
        _candidates = const [];
      }
    });
  }

  void _dragStart(DragStartDetails details, Size size) {
    if (_mode != _TraceMode.trace || !_closed) return;
    final point = _point(details.localPosition, size);
    if (point != null) setState(() => _selectedVertex = _near(point, size));
  }

  void _dragUpdate(DragUpdateDetails details, Size size) {
    final selected = _selectedVertex;
    if (_mode != _TraceMode.trace || selected == null) return;
    final point = _point(details.localPosition, size);
    if (point != null) setState(() => _points[selected] = point);
  }

  CapturedRoom? get _metricRoom {
    final reference = parseMetres(_reference.text);
    final height = parseMetres(_height.text);
    if (!_closed || height == null || (_legacy && reference == null)) {
      return null;
    }
    try {
      if (_legacy) {
        return buildCalibratedFloorplanTraceRoom(
          id: widget.roomId ?? 'preview',
          name: _name.text.trim().isEmpty ? 'Ambiente' : _name.text,
          normalizedTrace: _points,
          imageWidth: _imageWidth,
          imageHeight: _imageHeight,
          referenceEdge: _referenceEdge,
          referenceMeters: reference!,
          height: height,
        );
      }
      var room = buildWallBasedFloorplanRoom(
        id: widget.roomId ?? 'preview',
        name: _name.text.trim().isEmpty ? 'Ambiente' : _name.text,
        normalizedTrace: _points,
        imageWidth: _imageWidth,
        imageHeight: _imageHeight,
        height: height,
      ).copyWith(references: _measurements);
      final fitted = fitConfirmedWallLengths(room);
      if (!fitted.isCoherent) return null;
      return room.copyWith(corners: fitted.corners);
    } on ArgumentError {
      return null;
    }
  }

  List<ReferenceMeasurement> get _userMeasurements => [
    for (var index = 0; index < _points.length; index++)
      if (parseMetres(_wallLengths[index]?.text ?? '') case final value?)
        ReferenceMeasurement(edgeIndex: index, referenceMeters: value),
  ];

  FloorplanMetricSolution get _metricSolution => solveFloorplanMetrics(
    semanticContour: [
      for (final point in _points)
        FloorPoint(point.x * _imageWidth, point.z * _imageHeight),
    ],
    existingMeasurements: _restoredMeasurements,
    userMeasurements: _userMeasurements,
    measurementCandidates: _candidates,
  );

  List<ReferenceMeasurement> get _measurements =>
      _legacy ? _userMeasurements : _metricSolution.measurements;

  String _measurementLabel(int edge, FloorplanMetricSolution solution) {
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

  Future<void> _save() async {
    final source = _source;
    final reference = parseMetres(_reference.text);
    final height = parseMetres(_height.text);
    if (source == null) return _show('Elegí una imagen para trazar.');
    if (_points.length < 3) return _show('Marcá al menos tres puntos.');
    if (!_closed) return _show('Cerrá el contorno antes de guardar.');
    if (_legacy && reference == null) {
      return _show('Ingresá una medida real válida.');
    }
    if (height == null) return _show('Ingresá una altura válida.');
    if (_metricRoom == null) {
      return _show('El contorno se cruza o no forma un ambiente válido.');
    }
    final message = await widget.controller.saveFloorplanTrace(
      roomId: widget.roomId,
      name: _name.text.trim(),
      sourceId: source.sourceId,
      contentType: source.contentType,
      imageWidth: _imageWidth,
      imageHeight: _imageHeight,
      normalizedTrace: _points,
      referenceEdge: _legacy ? _referenceEdge : null,
      referenceMeters: reference,
      measurements: _measurements,
      openings: _traceOpenings,
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
      : !_legacy && !_metricSolution.hasScale
      ? () => _show('Ingresá una medida real en la pared seleccionada.')
      : _save;

  String get _primaryActionLabel => !_legacy && !_metricSolution.hasScale
      ? 'Completar 1 dato pendiente'
      : 'Confirmar ambiente';

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
      'P${opening.edgeIndex + 1}',
      type,
      ...details,
      'falta ${missing.join(' y ')}',
    ].join(' · ');
  }

  Widget _persistentReviewPlan() => SafeArea(
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
                    Uint8List.fromList(_source!.bytes),
                    fit: BoxFit.contain,
                    cacheWidth: math.min(_imageWidth, 1200),
                  ),
                  CustomPaint(
                    painter: _NormalizedTracePainter(
                      points: _points,
                      imageWidth: _imageWidth.toDouble(),
                      imageHeight: _imageHeight.toDouble(),
                      closed: _closed,
                      selected: null,
                      selectedEdge: _closed ? _selectedEdge : null,
                      openings: _openingProposals,
                    ),
                  ),
                ],
              ),
            );
            return Column(
              children: [
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
                  child: ListView.separated(
                    key: const ValueKey('floorplan-wall-selector'),
                    scrollDirection: Axis.horizontal,
                    itemCount: _points.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 4),
                    itemBuilder: (context, index) => ChoiceChip(
                      key: ValueKey('wall-chip-$index'),
                      label: Text('P${index + 1}'),
                      selected: index == _selectedEdge,
                      onSelected: (_) => setState(() => _selectedEdge = index),
                    ),
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
        ),
        bottomNavigationBar: _source != null && _closed
            ? SizedBox(height: 288, child: _persistentReviewPlan())
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
                    '${_points.length} paredes · $_openingReviewCount aperturas por revisar',
                    key: const ValueKey('floorplan-result-summary'),
                  ),
                if (_openingProposals.any(
                  (opening) => !opening.hasGeometry,
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
                            if (!opening.hasGeometry)
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
                      _points.clear();
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
                      label: Text('Mover / zoom'),
                    ),
                    ButtonSegment(
                      value: _TraceMode.trace,
                      label: Text('Trazar'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) =>
                      setState(() => _mode = value.first),
                ),
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
                            Uint8List.fromList(_source!.bytes),
                            fit: BoxFit.contain,
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
                              openings: _openingProposals,
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
                                onTapDown: (details) =>
                                    _selectWall(details, size),
                                child: canvas,
                              )
                            : GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (details) => _tap(details, size),
                                onPanStart: (details) =>
                                    _dragStart(details, size),
                                onPanUpdate: (details) =>
                                    _dragUpdate(details, size),
                                child: canvas,
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
                      onPressed: _points.isEmpty || _closed
                          ? null
                          : () => setState(() => _points.removeLast()),
                      child: const Text('Deshacer'),
                    ),
                    TextButton(
                      key: const ValueKey('trace-remove'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _selectedVertex == null || _points.length <= 3
                          ? null
                          : () => setState(() {
                              _points.removeAt(_selectedVertex!);
                              _selectedVertex = null;
                              _referenceEdge = 0;
                              _candidates = const [];
                            }),
                      child: const Text('Quitar vértice'),
                    ),
                    TextButton(
                      key: const ValueKey('trace-reset'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => setState(() {
                        final detected = _analysis?.contour ?? const [];
                        _points
                          ..clear()
                          ..addAll(detected);
                        _closed = detected.length >= 3;
                        _selectedVertex = null;
                        _referenceEdge = 0;
                      }),
                      child: const Text('Reiniciar'),
                    ),
                    TextButton(
                      key: const ValueKey('trace-close'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _points.length < 3 || _closed
                          ? null
                          : () => setState(() => _closed = true),
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
                          ? '${_points.length} paredes · escala resuelta automáticamente'
                          : 'Reconstruimos el ambiente. Ingresá una medida real para establecer la escala.',
                      key: const ValueKey('floorplan-metric-summary'),
                    ),
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        key: const ValueKey('floorplan-wall-selector-scroll'),
                        scrollDirection: Axis.horizontal,
                        itemCount: _points.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 4),
                        itemBuilder: (context, index) => ChoiceChip(
                          key: ValueKey('wall-chip-scroll-$index'),
                          label: Text('P${index + 1}'),
                          selected: index == _selectedEdge,
                          onSelected: (_) =>
                              setState(() => _selectedEdge = index),
                        ),
                      ),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          key: const ValueKey('wall-previous'),
                          tooltip: 'Pared anterior',
                          onPressed: () => setState(
                            () => _selectedEdge =
                                (_selectedEdge - 1 + _points.length) %
                                _points.length,
                          ),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          'P${_selectedEdge + 1} de ${_points.length}',
                          key: const ValueKey('selected-wall-position'),
                        ),
                        IconButton(
                          key: const ValueKey('wall-next'),
                          tooltip: 'Pared siguiente',
                          onPressed: () => setState(
                            () => _selectedEdge =
                                (_selectedEdge + 1) % _points.length,
                          ),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    for (final index in [_selectedEdge]) ...[
                      for (final candidate in _candidates.where(
                        (value) =>
                            value.edgeIndex == index &&
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
                                  '${wallLabel(index)} · ${candidate.meters!.toStringAsFixed(2).replaceAll('.', ',')} m · detectado',
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
                                      onPressed: () => setState(() {
                                        _wallLengths
                                            .putIfAbsent(
                                              index,
                                              TextEditingController.new,
                                            )
                                            .text = candidate.meters!
                                            .toString();
                                        _candidates = [
                                          for (final value in _candidates)
                                            if (value.id != candidate.id) value,
                                        ];
                                      }),
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
                      TextField(
                        key: ValueKey('trace-wall-$index'),
                        controller: _wallLengths.putIfAbsent(
                          index,
                          TextEditingController.new,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'P${index + 1} · Longitud (m)',
                          helperText: _measurementLabel(index, _metricSolution),
                        ),
                      ),
                    ],
                  ],
                ],
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
                  Text('Altura: ${metres(metric.height.value)}'),
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
    required this.openings,
  });

  final List<FloorPoint> points;
  final double imageWidth;
  final double imageHeight;
  final bool closed;
  final int? selected;
  final int? selectedEdge;
  final List<InterpretedOpeningProposal> openings;

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
    final path = Path()..moveTo(map(points.first).dx, map(points.first).dy);
    for (final point in points.skip(1)) {
      path.lineTo(map(point).dx, map(point).dy);
    }
    if (closed) path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff16443c)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    if (closed &&
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
    if (closed && points.length >= 2) {
      for (final opening in openings) {
        if (!opening.hasGeometry ||
            opening.edgeIndex < 0 ||
            opening.edgeIndex >= points.length) {
          continue;
        }
        final position = opening.position!;
        final normalizedWidth = opening.normalizedWidth!;
        if (!position.isFinite || !normalizedWidth.isFinite) continue;
        final start = map(points[opening.edgeIndex]);
        final end = map(points[(opening.edgeIndex + 1) % points.length]);
        final startT = position - normalizedWidth / 2;
        final endT = position + normalizedWidth / 2;
        final openingStart = Offset.lerp(start, end, startT)!;
        final openingEnd = Offset.lerp(start, end, endT)!;
        final color = switch (opening.type) {
          FloorplanOpeningCandidateType.window => const Color(0xff1976a2),
          FloorplanOpeningCandidateType.door => const Color(0xffb85224),
          FloorplanOpeningCandidateType.unknown => const Color(0xff6b7280),
        };
        canvas.drawLine(
          openingStart,
          openingEnd,
          Paint()
            ..color = color
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
        final span = openingEnd - openingStart;
        final length = span.distance;
        if (opening.type == FloorplanOpeningCandidateType.window &&
            length > 0) {
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
        } else if (opening.type == FloorplanOpeningCandidateType.door &&
            length > 0) {
          // Generic review marker; it does not encode an inferred swing.
          final leaf = Offset(-span.dy / length, span.dx / length) *
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
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(
        map(points[i]),
        i == selected ? 7 : 5,
        Paint()..color = const Color(0xffc96b31),
      );
    }
    if (closed) {
      for (var i = 0; i < points.length; i++) {
        final start = map(points[i]);
        final end = map(points[(i + 1) % points.length]);
        final label = TextPainter(
          text: TextSpan(
            text: 'P${i + 1}',
            style: const TextStyle(
              color: Color(0xff16443c),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              backgroundColor: Color(0xddffffff),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final midpoint = Offset(
          (start.dx + end.dx) / 2,
          (start.dy + end.dy) / 2,
        );
        label.paint(
          canvas,
          midpoint - Offset(label.width / 2, label.height + 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NormalizedTracePainter oldDelegate) => true;
}
