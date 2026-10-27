import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/services/ar_capture_channel.dart';
import '../../domain/spatial/capture_upload_controller.dart';
import '../../domain/spatial/spatial.dart';
import '../../domain/spatial_capture_controller.dart';
import 'capture_upload_format.dart';
import 'floor_plan_view.dart';
import 'floorplan_trace_screen.dart';
import 'room_editor_screen.dart';
import 'spatial_format.dart';

/// Minimum 48 dp touch target for primary actions.
const _actionMinSize = Size.fromHeight(48);

/// Spatial capture of one listing (F07): rooms measured with ARCore, their
/// connections, the plan that will be sent and its synchronization state.
class SpatialCaptureScreen extends StatefulWidget {
  const SpatialCaptureScreen({
    super.key,
    required this.controller,
    this.syncBlockedReason,
  });

  final SpatialCaptureController controller;

  /// Why the capture cannot be sent now (for example, a listing under review);
  /// capturing and editing on the phone stay available.
  final String? syncBlockedReason;

  @override
  State<SpatialCaptureScreen> createState() => _SpatialCaptureScreenState();
}

class _SpatialCaptureScreenState extends State<SpatialCaptureScreen> {
  final ScrollController _scrollController = ScrollController();
  int? _storageBytes;

  SpatialCaptureController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _refreshStorage();
    // Packages left over from a closed app or a lost connection resume here.
    final uploads = _controller.uploads;
    if (uploads != null) unawaited(uploads.retry());
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _refreshStorage();
  }

  Future<void> _refreshStorage() async {
    final bytes = await _controller.storageBytes();
    if (mounted && bytes != _storageBytes) {
      setState(() => _storageBytes = bytes);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _captureRoom() async {
    final method = await showDialog<_RoomCreationMethod>(
      context: context,
      builder: (context) => _RoomCreationMethodDialog(
        checkArAvailability: _controller.arAvailability,
      ),
    );
    if (method == null || !mounted) return;
    if (method == _RoomCreationMethod.floorplanTrace) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => FloorplanTraceScreen(controller: _controller),
        ),
      );
      return;
    }
    if (method == _RoomCreationMethod.manual) {
      final shape = await showDialog<_ManualShape>(
        context: context,
        builder: (context) => const _ManualShapeDialog(),
      );
      if (shape == null || !mounted) return;
      final suggestedName = 'Ambiente ${_controller.rooms.length + 1}';
      final sketch = await showDialog<_ManualSketchResult>(
        context: context,
        builder: (context) =>
            _ManualSketchDialog(suggestedName: suggestedName, template: shape),
      );
      if (sketch == null || !mounted) return;
      final message = await _controller.createWallBasedManualSketchRoom(
        name: sketch.name,
        sketch: sketch.points,
        height: sketch.height,
        measurements: sketch.measurements,
      );
      if (message != null && mounted) _show(message);
      return;
    }
    final choice = await showDialog<(String, CaptureMode)>(
      context: context,
      builder: (context) => _ArRoomDialog(
        suggestedName: 'Ambiente ${_controller.rooms.length + 1}',
      ),
    );
    if (choice == null || !mounted) return;
    final (name, mode) = choice;
    final message = await _controller.captureRoom(name, mode: mode);
    if (message != null && mounted) _show(message);
  }

  Future<void> _connect() async {
    final message = await showDialog<String?>(
      context: context,
      builder: (context) => _ConnectDialog(controller: _controller),
    );
    if (message != null && mounted) _show(message);
  }

  Future<void> _removeRoom(CapturedRoom room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar ${room.name}'),
        content: const Text(
          'Se borra la medición de este ambiente del teléfono y de la escena '
          'que se enviará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.removeRoom(room.id);
  }

  Future<void> _clearLocal() async {
    final cleared = await _controller.clearLocal();
    if (mounted) {
      _show(
        cleared
            ? 'Se borró la copia local. La escena sigue en RoomForge.'
            : 'Solo se puede borrar una captura ya sincronizada.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _controller.preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Captura espacial')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              key: const ValueKey('spatial-capture-screen'),
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Capturá cada ambiente con el método disponible en tu dispositivo. '
                  'Podés usar captura automática compatible o ingresar las medidas '
                  'manualmente. Antes de enviar, revisá el plano y las aberturas.',
                ),
                const SizedBox(height: 16),
                _SyncCard(
                  controller: _controller,
                  syncBlockedReason: widget.syncBlockedReason,
                  storageBytes: _storageBytes,
                  onClearLocal: _clearLocal,
                ),
                const SizedBox(height: 16),
                if (_controller.uploads case final uploads?
                    when uploads.items.isNotEmpty) ...[
                  _UploadsCard(uploads: uploads),
                  const SizedBox(height: 16),
                ],
                if (preview != null) ...[
                  FloorPlanView(document: preview.document),
                  const SizedBox(height: 12),
                  for (final warning in preview.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: theme.colorScheme.tertiary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(warning.message)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                Text('Ambientes', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                if (_controller.rooms.isEmpty)
                  const Text('Todavía no capturaste ambientes.'),
                for (final room in _controller.rooms)
                  _RoomCard(
                    room: room,
                    onTrace:
                        room.acquisition.method ==
                            RoomAcquisitionMethod.floorplanTrace
                        ? () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => FloorplanTraceScreen(
                                controller: _controller,
                                roomId: room.id,
                              ),
                            ),
                          )
                        : null,
                    onEdit: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => RoomEditorScreen(
                          controller: _controller,
                          roomId: room.id,
                        ),
                      ),
                    ),
                    onRemove: () => _removeRoom(room),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('capture-room-button'),
                  style: FilledButton.styleFrom(minimumSize: _actionMinSize),
                  onPressed: _controller.busy ? null : _captureRoom,
                  icon: const Icon(Icons.view_in_ar),
                  label: const Text('Capturar ambiente'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('connect-rooms-button'),
                  style: OutlinedButton.styleFrom(minimumSize: _actionMinSize),
                  onPressed: _controller.rooms.length < 2 ? null : _connect,
                  icon: const Icon(Icons.door_front_door_outlined),
                  label: const Text('Conectar ambientes por una puerta'),
                ),
                for (final connection in _controller.connections)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link),
                    title: Text(_connectionLabel(connection)),
                    trailing: IconButton(
                      tooltip: 'Quitar conexión',
                      icon: const Icon(Icons.link_off),
                      onPressed: () => _controller.disconnect(connection),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _connectionLabel(DoorConnection connection) {
    String name(String id) => _controller.rooms
        .firstWhere(
          (room) => room.id == id,
          orElse: () => _controller.rooms.first,
        )
        .name;
    return '${name(connection.roomA)} ↔ ${name(connection.roomB)}';
  }
}

/// Upload progress and reconstruction status of the walkthrough packages.
class _UploadsCard extends StatelessWidget {
  const _UploadsCard({required this.uploads});

  final CaptureUploadController uploads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('uploads-card'),
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recorridos para reconstrucción',
              style: theme.textTheme.titleMedium,
            ),
            if (uploads.message != null) ...[
              const SizedBox(height: 8),
              Text(uploads.message!),
            ],
            for (final item in uploads.items) ...[
              const SizedBox(height: 12),
              _UploadTile(item: item, uploads: uploads),
            ],
          ],
        ),
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({required this.item, required this.uploads});

  final CaptureUploadItem item;
  final CaptureUploadController uploads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = captureUploadText(item);
    final inProgress = item.phase != UploadPhase.idle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(text.detail),
        if (inProgress) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            key: const ValueKey('upload-progress'),
            value: text.progress,
          ),
        ],
        if (text.canRetry || text.canRefresh || text.canDismiss) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (text.canRetry)
                FilledButton.icon(
                  key: const ValueKey('upload-retry-button'),
                  style: FilledButton.styleFrom(minimumSize: _actionMinSize),
                  onPressed: uploads.busy ? null : uploads.retry,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Reintentar subida'),
                ),
              if (text.canRefresh)
                OutlinedButton.icon(
                  key: const ValueKey('upload-refresh-button'),
                  style: OutlinedButton.styleFrom(minimumSize: _actionMinSize),
                  onPressed: uploads.busy ? null : uploads.retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar estado'),
                ),
              if (text.canDismiss)
                TextButton(
                  key: const ValueKey('upload-dismiss-button'),
                  onPressed: () => uploads.dismiss(item.upload.captureId),
                  child: const Text('Quitar de la lista'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.controller,
    required this.syncBlockedReason,
    required this.storageBytes,
    required this.onClearLocal,
  });

  final SpatialCaptureController controller;
  final String? syncBlockedReason;
  final int? storageBytes;
  final VoidCallback onClearLocal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = controller.syncState;
    final title = switch (state) {
      CaptureSyncState.empty => 'Sin captura',
      CaptureSyncState.pending => 'Pendiente de enviar',
      CaptureSyncState.syncing => 'Enviando…',
      CaptureSyncState.synced => 'Escena sincronizada',
      CaptureSyncState.conflict => 'Conflicto con el servidor',
      CaptureSyncState.failed => 'No se pudo enviar',
    };
    final blocked = syncBlockedReason;
    final canSend =
        blocked == null &&
        !controller.busy &&
        (state == CaptureSyncState.pending || state == CaptureSyncState.failed);
    return Card(
      color:
          state == CaptureSyncState.conflict || state == CaptureSyncState.failed
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              key: const ValueKey('sync-state'),
              style: theme.textTheme.titleMedium,
            ),
            if (state == CaptureSyncState.syncing) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (controller.message != null) ...[
              const SizedBox(height: 8),
              Text(controller.message!, key: const ValueKey('sync-message')),
            ],
            if (blocked != null) ...[const SizedBox(height: 8), Text(blocked)],
            if (storageBytes != null && storageBytes! > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Guardado en el teléfono: '
                '${(storageBytes! / 1024).toStringAsFixed(1).replaceAll('.', ',')} KB',
              ),
            ],
            const SizedBox(height: 12),
            if (state == CaptureSyncState.conflict) ...[
              FilledButton(
                key: const ValueKey('overwrite-button'),
                style: FilledButton.styleFrom(minimumSize: _actionMinSize),
                onPressed: controller.busy || blocked != null
                    ? null
                    : controller.overwriteRemote,
                child: const Text('Reemplazar la escena del servidor'),
              ),
              const SizedBox(height: 4),
              const Text(
                'Si preferís conservar la del servidor, no envíes: tu captura '
                'queda en el teléfono.',
              ),
            ] else
              FilledButton.icon(
                key: const ValueKey('sync-button'),
                style: FilledButton.styleFrom(minimumSize: _actionMinSize),
                onPressed: canSend ? controller.sync : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  state == CaptureSyncState.failed
                      ? 'Reintentar envío'
                      : 'Enviar escena',
                ),
              ),
            if (state == CaptureSyncState.synced) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('clear-local-button'),
                onPressed: onClearLocal,
                child: const Text('Borrar la copia del teléfono'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.onEdit,
    required this.onRemove,
    this.onTrace,
  });

  final CapturedRoom room;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback? onTrace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issues = validateContour(room.corners);
    final wallBased =
        room.measurementMode == RoomMeasurementMode.wallConstraints;
    final correction = wallBased ? null : scaleCorrection(room);
    final shape = correctedRoom(room);
    final confirmed = {
      for (final measurement in room.references) measurement.edgeIndex,
    }.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(room.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            if (!wallBased || confirmed == room.corners.length) ...[
              Text(
                'Paredes: ${edgeLengths(shape.corners).map(metres).join(' · ')}',
              ),
              Text(
                'Superficie estimada: ${squareMetres(polygonArea(shape.corners))}',
              ),
            ] else
              Text('Paredes confirmadas: $confirmed/${room.corners.length}'),
            if (room.acquisition.method == RoomAcquisitionMethod.manual)
              const Text('Medidas ingresadas manualmente')
            else if (room.acquisition.method ==
                RoomAcquisitionMethod.manualSketch)
              Text(
                wallBased
                    ? 'Croquis manual con medidas por pared'
                    : 'Croquis manual calibrado con una medida real',
              )
            else if (room.acquisition.method ==
                RoomAcquisitionMethod.floorplanTrace)
              Text(
                wallBased
                    ? confirmed == room.corners.length
                          ? 'Plano o croquis con medidas por pared'
                          : 'Plano o croquis pendiente de revisión métrica'
                    : 'Plano o croquis trazado y calibrado',
              )
            else if (correction != null && correction.applied)
              Text(
                'Escala corregida con ${correction.referenceCount} '
                '${correction.referenceCount == 1 ? 'referencia' : 'referencias'}',
              )
            else
              const Text('Sin medida de referencia: escala sin comprobar'),
            Text(
              'Altura: ${metres(room.height.value)} '
              '(${heightSourceLabel(room.height.source)})',
            ),
            if (room.openings.isNotEmpty)
              Text('Aberturas: ${room.openings.length}'),
            if (room.boxes.isNotEmpty)
              Text('Volúmenes sin etiqueta: ${room.boxes.length}'),
            for (final issue in issues)
              Text(
                contourIssueMessage(issue),
                style: TextStyle(
                  color: issue.blocking
                      ? theme.colorScheme.error
                      : theme.colorScheme.tertiary,
                ),
              ),
            const SizedBox(height: 8),
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              overflowSpacing: 8,
              children: [
                if (onTrace != null)
                  TextButton.icon(
                    key: ValueKey('edit-trace-${room.id}'),
                    onPressed: onTrace,
                    icon: const Icon(Icons.gesture),
                    label: const Text('Editar trazado'),
                  ),
                TextButton.icon(
                  key: ValueKey('edit-room-${room.id}'),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Corregir'),
                ),
                TextButton.icon(
                  key: ValueKey('remove-room-${room.id}'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _RoomCreationMethod { automatic, manual, floorplanTrace }

enum _ManualShape { rectangular, lShape, irregular }

class _ManualShapeDialog extends StatelessWidget {
  const _ManualShapeDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Dibujar ambiente'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _option(
            context,
            key: 'manual-shape-irregular',
            icon: Icons.gesture,
            title: 'Dibujo libre',
            subtitle: 'Marcá las paredes y completá sus medidas.',
            value: _ManualShape.irregular,
          ),
          _option(
            context,
            key: 'manual-shape-rectangle',
            icon: Icons.crop_square,
            title: 'Plantilla rectangular',
            subtitle: 'Partí de cuatro paredes y medí cada una.',
            value: _ManualShape.rectangular,
          ),
          _option(
            context,
            key: 'manual-shape-l',
            icon: Icons.polyline_outlined,
            title: 'Plantilla en L',
            subtitle: 'Partí de seis paredes y medí cada una.',
            value: _ManualShape.lShape,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
    ],
  );

  Widget _option(
    BuildContext context, {
    required String key,
    required IconData icon,
    required String title,
    required String subtitle,
    required _ManualShape value,
  }) => ListTile(
    key: ValueKey(key),
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    onTap: () => Navigator.of(context).pop(value),
  );
}

class _RoomCreationMethodDialog extends StatefulWidget {
  const _RoomCreationMethodDialog({required this.checkArAvailability});

  final Future<ArAvailability> Function() checkArAvailability;

  @override
  State<_RoomCreationMethodDialog> createState() =>
      _RoomCreationMethodDialogState();
}

class _RoomCreationMethodDialogState extends State<_RoomCreationMethodDialog> {
  bool _checking = false;
  bool _unsupported = false;

  Future<void> _chooseAutomatic() async {
    if (_checking || _unsupported) return;
    setState(() => _checking = true);
    final availability = await widget.checkArAvailability();
    if (!mounted) return;
    if (availability == ArAvailability.unsupported) {
      setState(() {
        _checking = false;
        _unsupported = true;
      });
      return;
    }
    Navigator.of(context).pop(_RoomCreationMethod.automatic);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Crear ambiente'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('automatic-capture-method'),
            leading: const Icon(Icons.view_in_ar),
            title: const Text('Captura automática'),
            subtitle: Text(
              _unsupported
                  ? 'No disponible: este teléfono no admite ARCore.'
                  : 'Usa ARCore para recorrer o marcar las paredes.',
            ),
            enabled: !_checking && !_unsupported,
            trailing: _checking
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _chooseAutomatic,
          ),
          ListTile(
            key: const ValueKey('manual-capture-method'),
            leading: const Icon(Icons.straighten),
            title: const Text('Dibujar ambiente'),
            subtitle: const Text(
              'Marcá las paredes y completá sus medidas sin usar ARCore.',
            ),
            onTap: () => Navigator.of(context).pop(_RoomCreationMethod.manual),
          ),
          ListTile(
            key: const ValueKey('floorplan-capture-method'),
            leading: const Icon(Icons.architecture_outlined),
            title: const Text('Plano o croquis'),
            subtitle: const Text(
              'RoomForge intentará crear el ambiente desde una imagen.',
            ),
            onTap: () =>
                Navigator.of(context).pop(_RoomCreationMethod.floorplanTrace),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
    ],
  );
}

typedef _ManualSketchResult = ({
  String name,
  List<FloorPoint> points,
  List<ReferenceMeasurement> measurements,
  double height,
});

enum _SketchMode { navigate, draw }

class _ManualSketchDialog extends StatefulWidget {
  const _ManualSketchDialog({
    required this.suggestedName,
    this.template = _ManualShape.irregular,
  });
  final String suggestedName;
  final _ManualShape template;

  @override
  State<_ManualSketchDialog> createState() => _ManualSketchDialogState();
}

class _ManualSketchDialogState extends State<_ManualSketchDialog> {
  late final _name = TextEditingController(text: widget.suggestedName);
  final _height = TextEditingController();
  final _wallLengths = <int, TextEditingController>{};
  final List<FloorPoint> _points = [];
  final _transform = TransformationController();
  bool _closed = false;
  _SketchMode _mode = _SketchMode.draw;
  int? _selectedVertex;

  List<ReferenceMeasurement> get _measurements => [
    for (var index = 0; index < _points.length; index++)
      if (parseMetres(_wallLengths[index]?.text ?? '') case final value?)
        ReferenceMeasurement(edgeIndex: index, referenceMeters: value),
  ];

  WallGeometryResult? get _fittedGeometry {
    if (!_closed || _points.length < 3 || _measurements.isEmpty) return null;
    if (widget.template != _ManualShape.irregular &&
        _measurements.length != _points.length) {
      return null;
    }
    try {
      final room = buildWallBasedManualSketchRoom(
        id: 'preview',
        name: 'preview',
        sketch: _points,
        height: 2.5,
      ).copyWith(references: _measurements);
      return fitConfirmedWallLengths(room);
    } on ArgumentError {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    switch (widget.template) {
      case _ManualShape.rectangular:
        _points.addAll(const [
          FloorPoint(30, 25),
          FloorPoint(230, 25),
          FloorPoint(230, 155),
          FloorPoint(30, 155),
        ]);
        _closed = true;
      case _ManualShape.lShape:
        _points.addAll(const [
          FloorPoint(25, 20),
          FloorPoint(235, 20),
          FloorPoint(235, 90),
          FloorPoint(150, 90),
          FloorPoint(150, 160),
          FloorPoint(25, 160),
        ]);
        _closed = true;
      case _ManualShape.irregular:
        break;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    for (final controller in _wallLengths.values) {
      controller.dispose();
    }
    _transform.dispose();
    super.dispose();
  }

  void _tap(TapDownDetails details) {
    if (_closed) {
      setState(() => _selectedVertex = _vertexNear(details.localPosition));
      return;
    }
    setState(
      () => _points.add(
        FloorPoint(details.localPosition.dx, details.localPosition.dy),
      ),
    );
  }

  int? _vertexNear(Offset position) {
    var best = 24.0;
    int? selected;
    for (var i = 0; i < _points.length; i++) {
      final distance = math.sqrt(
        math.pow(_points[i].x - position.dx, 2) +
            math.pow(_points[i].z - position.dy, 2),
      );
      if (distance < best) {
        best = distance;
        selected = i;
      }
    }
    return selected;
  }

  void _panStart(DragStartDetails details) {
    if (!_closed || _points.isEmpty) return;
    setState(() => _selectedVertex = _vertexNear(details.localPosition));
  }

  void _panUpdate(DragUpdateDetails details) {
    final selected = _selectedVertex;
    if (selected == null) return;
    setState(
      () => _points[selected] = FloorPoint(
        details.localPosition.dx,
        details.localPosition.dy,
      ),
    );
  }

  void _submit() {
    final height = parseMetres(_height.text);
    if (!_closed ||
        _points.length < 3 ||
        height == null ||
        _name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cerrá un contorno válido e ingresá la altura.'),
        ),
      );
      return;
    }
    try {
      final room = buildWallBasedManualSketchRoom(
        id: 'check',
        name: _name.text,
        sketch: _points,
        height: height,
      ).copyWith(references: _measurements);
      final fitted = fitConfirmedWallLengths(room);
      if (!fitted.isCoherent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(fitted.message!)));
        return;
      }
    } on ArgumentError {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El croquis se cruza o tiene lados demasiado cortos. Revisalo.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop((
      name: _name.text.trim(),
      points: [..._points],
      measurements: _measurements,
      height: height,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final fitted = _fittedGeometry;
    final previewPoints = fitted?.corners ?? _points;
    return AlertDialog(
      title: Text(switch (widget.template) {
        _ManualShape.rectangular => 'Plantilla rectangular',
        _ManualShape.lShape => 'Plantilla en L',
        _ManualShape.irregular => 'Dibujo libre',
      }),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('sketch-room-name'),
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nombre del ambiente',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'La forma es una guía. Cada Pared N se mide y confirma de manera independiente.',
            ),
            const SizedBox(height: 8),
            SegmentedButton<_SketchMode>(
              key: const ValueKey('sketch-mode'),
              segments: const [
                ButtonSegment(
                  value: _SketchMode.navigate,
                  label: Text('Mover / zoom'),
                ),
                ButtonSegment(
                  value: _SketchMode.draw,
                  label: Text('Dibujar / editar'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
            const SizedBox(height: 8),
            SizedBox(
              key: const ValueKey('sketch-canvas'),
              height: 180,
              width: 260,
              child: InteractiveViewer(
                key: const ValueKey('sketch-interactive-viewer'),
                transformationController: _transform,
                panEnabled: _mode == _SketchMode.navigate,
                scaleEnabled: _mode == _SketchMode.navigate,
                minScale: 1,
                maxScale: 5,
                child: Builder(
                  builder: (context) {
                    final canvas = SizedBox(
                      height: 180,
                      width: 260,
                      child: Semantics(
                        label: fitted == null
                            ? 'Plantilla estable de ${_points.length} paredes'
                            : 'Geometría resuelta y ajustada de ${_points.length} paredes',
                        child: CustomPaint(
                          painter: _SketchPainter(
                            previewPoints,
                            closed: _closed,
                            selectedVertex: _selectedVertex,
                            selectedEdge: null,
                            fitToBounds: fitted != null,
                          ),
                        ),
                      ),
                    );
                    if (_mode == _SketchMode.navigate) return canvas;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: _tap,
                      onPanStart: _panStart,
                      onPanUpdate: _panUpdate,
                      child: canvas,
                    );
                  },
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('sketch-undo'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: _points.isEmpty || _closed
                      ? null
                      : () => setState(() => _points.removeLast()),
                  child: const Text('Deshacer'),
                ),
                TextButton(
                  key: const ValueKey('sketch-remove'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: _selectedVertex == null || _points.length <= 3
                      ? null
                      : () => setState(() {
                          _points.removeAt(_selectedVertex!);
                          _selectedVertex = null;
                        }),
                  child: const Text('Quitar vértice'),
                ),
                TextButton(
                  key: const ValueKey('sketch-reset'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => setState(() {
                    _points.clear();
                    _closed = false;
                    for (final controller in _wallLengths.values) {
                      controller.clear();
                    }
                  }),
                  child: const Text('Reiniciar'),
                ),
                TextButton(
                  key: const ValueKey('sketch-close'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: _points.length < 3 || _closed
                      ? null
                      : () => setState(() => _closed = true),
                  child: const Text('Cerrar contorno'),
                ),
              ],
            ),
            if (_closed) ...[
              if (fitted != null && !fitted.isCoherent)
                Text(
                  fitted.message!,
                  key: const ValueKey('sketch-geometry-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const Text(
                'Completá cada pared medida. Podés guardar pendientes y continuar luego.',
              ),
              for (var index = 0; index < _points.length; index++)
                TextField(
                  key: ValueKey('sketch-wall-$index'),
                  controller: _wallLengths.putIfAbsent(
                    index,
                    TextEditingController.new,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '${wallLabel(index)} · Largo real (m)',
                    helperText:
                        parseMetres(_wallLengths[index]?.text ?? '') == null
                        ? 'Estado: Pendiente'
                        : 'Estado: Confirmada',
                  ),
                ),
            ],
            TextField(
              key: const ValueKey('sketch-room-height'),
              controller: _height,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Altura del ambiente (m)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('sketch-confirm'),
          onPressed: _submit,
          child: const Text('Guardar ambiente'),
        ),
      ],
    );
  }
}

class _SketchPainter extends CustomPainter {
  const _SketchPainter(
    this.points, {
    required this.closed,
    this.selectedVertex,
    this.selectedEdge,
    this.fitToBounds = true,
  });
  final List<FloorPoint> points;
  final bool closed;
  final int? selectedVertex;
  final int? selectedEdge;
  final bool fitToBounds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfff4f6f4),
    );
    if (points.isEmpty) return;
    final minX = points.map((p) => p.x).reduce(math.min);
    final maxX = points.map((p) => p.x).reduce(math.max);
    final minZ = points.map((p) => p.z).reduce(math.min);
    final maxZ = points.map((p) => p.z).reduce(math.max);
    final scale = fitToBounds
        ? math.min(
            (size.width - 24) / math.max(maxX - minX, 1),
            (size.height - 24) / math.max(maxZ - minZ, 1),
          )
        : 1.0;
    Offset map(FloorPoint p) => fitToBounds
        ? Offset(12 + (p.x - minX) * scale, 12 + (p.z - minZ) * scale)
        : Offset(p.x, p.z);
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
    if (closed && selectedEdge != null) {
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
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(
        map(points[i]),
        i == selectedVertex ? 7 : 5,
        Paint()..color = const Color(0xffc96b31),
      );
    }
    if (closed) {
      for (var i = 0; i < points.length; i++) {
        final start = map(points[i]);
        final end = map(points[(i + 1) % points.length]);
        final label = TextPainter(
          text: TextSpan(
            text: 'PARED ${i + 1}',
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
  bool shouldRepaint(_SketchPainter old) => true;
}

class _ArRoomDialog extends StatefulWidget {
  const _ArRoomDialog({required this.suggestedName});

  /// Prefilled so the camera opens in one tap; the agent can rename it.
  final String suggestedName;

  @override
  State<_ArRoomDialog> createState() => _ArRoomDialogState();
}

class _ArRoomDialogState extends State<_ArRoomDialog> {
  late final _name = TextEditingController(text: widget.suggestedName);
  String? _nameError;
  CaptureMode _mode = CaptureMode.walkthrough;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Escribí un nombre para el ambiente.');
      return;
    }
    Navigator.of(context).pop((name, _mode));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuevo ambiente'),
    // Scrolls when the keyboard leaves too little room for the whole form.
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('room-name-field'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Nombre (por ejemplo, Estar)',
              errorText: _nameError,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          SegmentedButton<CaptureMode>(
            segments: const [
              ButtonSegment(
                value: CaptureMode.walkthrough,
                label: Text('Recorrido'),
              ),
              ButtonSegment(
                value: CaptureMode.walls,
                label: Text('Marcar paredes'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() => _mode = value.single),
          ),
          const SizedBox(height: 12),
          Text(
            _mode == CaptureMode.walkthrough
                ? 'Recomendado. Caminá despacio por el borde del ambiente apuntando a la '
                      'unión entre piso y pared: la app detecta las paredes y '
                      'propone el contorno. La cámara solo muestra la imagen en '
                      'vivo: no se graba video.'
                : 'Recorré el ambiente pared por pared, en orden, marcando dos '
                      'puntos en el piso al pie de cada una (separados 50 cm o '
                      'más). La cámara solo muestra la imagen en vivo: no se '
                      'graba video.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('room-name-confirm'),
        onPressed: _submit,
        child: const Text('Abrir cámara'),
      ),
    ],
  );
}

/// Picks a door in each of two rooms; room B moves to meet room A.
class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({required this.controller});

  final SpatialCaptureController controller;

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  (String, String)? _doorA;
  (String, String)? _doorB;

  List<(String, String)> get _doors => [
    for (final room in widget.controller.rooms)
      for (final opening in room.openings)
        if (opening.type == OpeningType.door) (room.id, opening.id),
  ];

  String _label((String, String) door) {
    final room = widget.controller.rooms.firstWhere((r) => r.id == door.$1);
    final index = room.openings.indexWhere((o) => o.id == door.$2);
    return '${room.name} · puerta ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final doors = _doors;
    return AlertDialog(
      title: const Text('Conectar ambientes'),
      content: doors.length < 2
          ? const Text(
              'Primero agregá una puerta en cada ambiente desde «Corregir».',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<(String, String)>(
                  key: const ValueKey('connect-door-a'),
                  initialValue: _doorA,
                  decoration: const InputDecoration(
                    labelText: 'Puerta del ambiente fijo',
                  ),
                  items: [
                    for (final door in doors)
                      DropdownMenuItem(value: door, child: Text(_label(door))),
                  ],
                  onChanged: (value) => setState(() => _doorA = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<(String, String)>(
                  key: const ValueKey('connect-door-b'),
                  initialValue: _doorB,
                  decoration: const InputDecoration(
                    labelText: 'Puerta del ambiente que se acomoda',
                  ),
                  items: [
                    for (final door in doors)
                      DropdownMenuItem(value: door, child: Text(_label(door))),
                  ],
                  onChanged: (value) => setState(() => _doorB = value),
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        if (doors.length >= 2)
          FilledButton(
            key: const ValueKey('connect-confirm'),
            onPressed: _doorA == null || _doorB == null
                ? null
                : () async {
                    final navigator = Navigator.of(context);
                    final message = await widget.controller.connect(
                      roomA: _doorA!.$1,
                      openingA: _doorA!.$2,
                      roomB: _doorB!.$1,
                      openingB: _doorB!.$2,
                    );
                    navigator.pop(message);
                  },
            child: const Text('Conectar'),
          ),
      ],
    );
  }
}
