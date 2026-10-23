import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/services/photo_source.dart';
import '../../domain/spatial/spatial.dart';
import '../../domain/spatial_capture_controller.dart';
import 'spatial_format.dart';

enum _TraceMode { navigate, trace }

class FloorplanTraceScreen extends StatefulWidget {
  const FloorplanTraceScreen({
    super.key,
    required this.controller,
    this.roomId,
  });

  final SpatialCaptureController controller;
  final String? roomId;

  @override
  State<FloorplanTraceScreen> createState() => _FloorplanTraceScreenState();
}

class _FloorplanTraceScreenState extends State<FloorplanTraceScreen> {
  final _name = TextEditingController();
  final _reference = TextEditingController();
  final _height = TextEditingController();
  final _transform = TransformationController();
  final List<FloorPoint> _points = [];
  LocalTraceSource? _source;
  int _imageWidth = 0;
  int _imageHeight = 0;
  int _referenceEdge = 0;
  int? _selectedVertex;
  bool _closed = false;
  bool _loading = false;
  bool _saved = false;
  _TraceMode _mode = _TraceMode.navigate;

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
      _referenceEdge = trace.referenceEdge;
      // The calibration measurement is kept exactly as recorded: rounding it
      // to centimetres here would rescale an untouched retrace.
      _reference.text = trace.referenceMeters.toString();
      _closed = true;
      _mode = _TraceMode.trace;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _reference.dispose();
    _height.dispose();
    _transform.dispose();
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
    setState(() => _loading = true);
    try {
      final next = await widget.controller.pickFloorplanSource();
      if (next == null || !mounted) return;
      final dimensions = await _decodeDimensions(next.bytes);
      if (!mounted) return;
      if (dimensions == null) {
        await widget.controller.discardFloorplanSource(next.sourceId);
        _show('No se pudo abrir la imagen.');
        return;
      }
      final previous = _source;
      if (previous != null && widget.roomId == null) {
        await widget.controller.discardFloorplanSource(previous.sourceId);
      }
      setState(() {
        _source = next;
        _imageWidth = dimensions.$1;
        _imageHeight = dimensions.$2;
        _points.clear();
        _closed = false;
        _referenceEdge = 0;
        _reference.clear();
        _selectedVertex = null;
        _transform.value = Matrix4.identity();
      });
    } on UnsupportedPhotoFormat {
      _show('Usá una imagen JPEG, PNG o WEBP.');
    } on Object {
      _show('No se pudo abrir la imagen.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<(int, int)?> _decodeDimensions(List<int> bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      final result = (frame.image.width, frame.image.height);
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

  void _tap(TapDownDetails details, Size size) {
    if (_mode != _TraceMode.trace || _source == null) return;
    final point = _point(details.localPosition, size);
    if (point == null) return;
    setState(() {
      if (_closed) {
        _selectedVertex = _near(point, size);
      } else {
        _points.add(point);
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
    if (!_closed || reference == null || height == null) return null;
    try {
      return buildCalibratedFloorplanTraceRoom(
        id: widget.roomId ?? 'preview',
        name: _name.text.trim().isEmpty ? 'Ambiente' : _name.text,
        normalizedTrace: _points,
        imageWidth: _imageWidth,
        imageHeight: _imageHeight,
        referenceEdge: _referenceEdge,
        referenceMeters: reference,
        height: height,
      );
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _save() async {
    final source = _source;
    final reference = parseMetres(_reference.text);
    final height = parseMetres(_height.text);
    if (source == null) return _show('Elegí una imagen para trazar.');
    if (_points.length < 3) return _show('Marcá al menos tres puntos.');
    if (!_closed) return _show('Cerrá el contorno antes de guardar.');
    if (reference == null) return _show('Ingresá una medida real válida.');
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
      referenceEdge: _referenceEdge,
      referenceMeters: reference,
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
        body: SafeArea(
          child: ListView(
            key: const ValueKey('floorplan-trace-scroll'),
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'La imagen se usa como guía local para trazar. Solo se enviará la geometría resultante.',
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
                onPressed: _loading ? null : _pickSource,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  _source == null ? 'Elegir imagen' : 'Cambiar imagen',
                ),
              ),
              if (_source == null && widget.roomId != null) ...[
                const SizedBox(height: 8),
                const Text('La imagen original ya no está disponible.'),
              ],
              if (_source != null) ...[
                const SizedBox(height: 12),
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
                  'El trazado define la forma. La medida de referencia establece la escala. Revisá el resultado antes de guardar.',
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
                            ? canvas
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
                            }),
                      child: const Text('Quitar vértice'),
                    ),
                    TextButton(
                      key: const ValueKey('trace-reset'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => setState(() {
                        _points.clear();
                        _closed = false;
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
                  DropdownButtonFormField<int>(
                    key: const ValueKey('trace-reference-edge'),
                    initialValue: _referenceEdge,
                    decoration: const InputDecoration(
                      labelText: 'Lado de referencia',
                    ),
                    items: [
                      for (var i = 0; i < _points.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text('Lado ${i + 1}'),
                        ),
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
                      labelText: 'Medida real de este lado (m)',
                    ),
                  ),
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
                if (metric != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Vista previa métrica',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (var i = 0; i < metric.corners.length; i++)
                    Text(
                      'Lado ${i + 1}: ${metres(edgeLengths(metric.corners)[i])}',
                    ),
                  Text(
                    'Superficie estimada: ${squareMetres(polygonArea(metric.corners))}',
                  ),
                  Text('Altura: ${metres(metric.height.value)}'),
                  const Text('Plano o croquis trazado y calibrado'),
                ],
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('floorplan-trace-save'),
                onPressed: _loading ? null : _save,
                child: const Text('Guardar ambiente'),
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
  });

  final List<FloorPoint> points;
  final double imageWidth;
  final double imageHeight;
  final bool closed;
  final int? selected;

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
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(
        map(points[i]),
        i == selected ? 7 : 5,
        Paint()..color = const Color(0xffc96b31),
      );
    }
  }

  @override
  bool shouldRepaint(_NormalizedTracePainter oldDelegate) => true;
}
