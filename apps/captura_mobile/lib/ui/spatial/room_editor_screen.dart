import 'package:flutter/material.dart';

import '../../domain/spatial/spatial.dart';
import '../../domain/spatial_capture_controller.dart';
import 'spatial_format.dart';

/// Manual corrections of one captured room: height, tape references,
/// openings and unlabelled volumes. Every value typed here is marked as
/// manual; nothing typed is presented as measured.
class RoomEditorScreen extends StatefulWidget {
  const RoomEditorScreen({
    super.key,
    required this.controller,
    required this.roomId,
  });

  final SpatialCaptureController controller;
  final String roomId;

  @override
  State<RoomEditorScreen> createState() => _RoomEditorScreenState();
}

class _RoomEditorScreenState extends State<RoomEditorScreen> {
  final _height = TextEditingController();
  final _references = <int, TextEditingController>{};
  final _boxHeights = <String, TextEditingController>{};

  SpatialCaptureController get _controller => widget.controller;

  CapturedRoom? get _room {
    for (final room in _controller.rooms) {
      if (room.id == widget.roomId) return room;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _height.dispose();
    for (final controller in [..._references.values, ..._boxHeights.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveHeight(CapturedRoom room) async {
    final value = parseMetres(_height.text);
    if (value == null || value < 1.8 || value > 4.5) {
      _show('Ingresá una altura entre 1,80 y 4,50 m.');
      return;
    }
    _height.clear();
    await _controller.updateRoom(
      room.copyWith(height: RoomHeight(value, HeightSource.manual)),
    );
  }

  Future<void> _saveReference(CapturedRoom room, int edgeIndex) async {
    final field = _references[edgeIndex]!;
    final value = parseMetres(field.text);
    if (value == null) {
      _show('Ingresá la medida de la cinta en metros.');
      return;
    }
    field.clear();
    await _controller.updateRoom(
      room.copyWith(
        references: [
          for (final reference in room.references)
            if (reference.edgeIndex != edgeIndex) reference,
          ReferenceMeasurement(edgeIndex: edgeIndex, referenceMeters: value),
        ],
      ),
    );
  }

  Future<void> _saveBoxHeight(CapturedRoom room, OccupancyBox box) async {
    final value = parseMetres(_boxHeights[box.id]!.text);
    if (value == null || value > 3) {
      _show('Ingresá un alto entre 0 y 3 m.');
      return;
    }
    _boxHeights[box.id]!.clear();
    await _controller.updateRoom(
      room.copyWith(
        boxes: [
          for (final current in room.boxes)
            current.id == box.id
                ? box.correctedManually(height: value)
                : current,
        ],
      ),
    );
  }

  Future<void> _removeBox(CapturedRoom room, OccupancyBox box) =>
      _controller.updateRoom(
        room.copyWith(
          boxes: [
            for (final current in room.boxes)
              if (current.id != box.id) current,
          ],
        ),
      );

  Future<void> _editOpening(CapturedRoom room, [RoomOpening? opening]) async {
    final result = await showDialog<RoomOpening>(
      context: context,
      builder: (context) => _OpeningDialog(room: room, opening: opening),
    );
    if (result == null) return;
    final issues = validateOpening(room, result);
    if (issues.isNotEmpty) {
      _show(openingIssueMessage(issues.first));
      return;
    }
    await _controller.updateRoom(
      room.copyWith(
        openings: opening == null
            ? [...room.openings, result]
            : [
                for (final current in room.openings)
                  current.id == opening.id ? result : current,
              ],
      ),
    );
  }

  Future<void> _removeOpening(CapturedRoom room, RoomOpening opening) =>
      _controller.updateRoom(
        room.copyWith(
          openings: [
            for (final current in room.openings)
              if (current.id != opening.id) current,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final theme = Theme.of(context);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ambiente')),
        body: const Center(child: Text('El ambiente ya no existe.')),
      );
    }
    final lengths = edgeLengths(room.corners);
    final correction = scaleCorrection(room);
    final correctedLengths = correction != null && correction.applied
        ? edgeLengths(correctedRoom(room).corners)
        : null;
    final tolerances = {
      for (final record in toleranceRecords(room)) record.edgeIndex: record,
    };
    return Scaffold(
      appBar: AppBar(title: Text(room.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Altura', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Altura: ${metres(room.height.value)} '
              '(${heightSourceLabel(room.height.source)})',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('room-height-field'),
                    controller: _height,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Altura medida a mano (m)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('room-height-save'),
                  onPressed: () => _saveHeight(room),
                  child: const Text('Guardar'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Lados y tolerancia', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'El teléfono da la forma del ambiente; la escala exacta la da una '
              'medida con cinta o medidor láser. Medí al menos un lado: la app '
              'corrige todo el ambiente con esa referencia. Sin referencia solo '
              'afirmamos que la captura es repetible, no que sea exacta.',
            ),
            if (correction != null) ...[
              const SizedBox(height: 8),
              Text(
                correction.applied
                    ? 'Escala corregida ${_signedPercent(correction.factor - 1)} '
                          'con ${correction.referenceCount} '
                          '${correction.referenceCount == 1 ? 'referencia' : 'referencias'}.'
                    : correction.message!,
                key: const ValueKey('scale-correction'),
                style: theme.textTheme.titleSmall,
              ),
              if (correction.applied && correction.referenceCount == 1)
                const Text(
                  'Con una sola referencia no se puede estimar el error que '
                  'queda: medí otro lado para comprobarlo.',
                ),
              if (correction.applied && correction.referenceCount > 1)
                for (final entry in correction.residuals.entries)
                  Text(
                    'Diferencia restante en el lado ${entry.key + 1}: '
                    '${entry.value >= 0 ? '+' : '−'}${metres(entry.value.abs())}',
                  ),
            ],
            for (var index = 0; index < lengths.length; index++)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      correctedLengths == null
                          ? 'Lado ${index + 1}: ${metres(lengths[index])}'
                          : 'Lado ${index + 1}: ${metres(lengths[index])} '
                                'capturado → ${metres(correctedLengths[index])} '
                                'corregido',
                    ),
                    if (tolerances[index] case final record?)
                      Text(
                        'Error observado: '
                        '${record.absoluteError >= 0 ? '+' : '−'}'
                        '${metres(record.absoluteError.abs())} '
                        '(${record.relativeErrorPercent.abs().toStringAsFixed(1).replaceAll('.', ',')} %)',
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: ValueKey('reference-field-$index'),
                            controller: _references.putIfAbsent(
                              index,
                              TextEditingController.new,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Medida con cinta (m)',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          key: ValueKey('reference-save-$index'),
                          onPressed: () => _saveReference(room, index),
                          child: const Text('Registrar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Text('Puertas y ventanas', style: theme.textTheme.titleLarge),
            for (final (index, opening) in room.openings.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${openingTypeLabel(opening.type)} ${index + 1} · '
                  'lado ${opening.edgeIndex + 1}',
                ),
                subtitle: Text(
                  '${metres(opening.width)} × ${metres(opening.height)}',
                ),
                onTap: () => _editOpening(room, opening),
                trailing: IconButton(
                  tooltip: 'Eliminar abertura',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeOpening(room, opening),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('add-opening-button'),
              onPressed: () => _editOpening(room),
              icon: const Icon(Icons.add),
              label: const Text('Agregar puerta o ventana'),
            ),
            const SizedBox(height: 24),
            Text('Volúmenes sin etiqueta', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'Son cajas de ocupación: no tienen clase ni precio. La agencia '
              'puede promoverlas a un extra desde el panel.',
            ),
            for (final (index, box) in room.boxes.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Volumen ${index + 1}: ${metres(box.width)} × '
                      '${metres(box.depth)}'
                      '${box.height == null ? ' · alto sin medir' : ' × ${metres(box.height!)}'}'
                      ' (${boxSourceLabel(box.source)}'
                      '${box.confidence == null ? '' : ', confianza ${(box.confidence! * 100).round()} %'})',
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: ValueKey('box-height-field-${box.id}'),
                            controller: _boxHeights.putIfAbsent(
                              box.id,
                              TextEditingController.new,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Alto a mano (m)',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _saveBoxHeight(room, box),
                          child: const Text('Guardar'),
                        ),
                        IconButton(
                          tooltip: 'Eliminar volumen',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _removeBox(room, box),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (room.boxes.isEmpty) const Text('Sin volúmenes capturados.'),
          ],
        ),
      ),
    );
  }
}

/// A scale change as a signed percentage with a decimal comma: «+5,0 %».
String _signedPercent(double change) {
  final percent = change * 100;
  final text = percent.abs().toStringAsFixed(1).replaceAll('.', ',');
  return '${percent >= 0 ? '+' : '−'}$text %';
}

class _OpeningDialog extends StatefulWidget {
  const _OpeningDialog({required this.room, this.opening});

  final CapturedRoom room;
  final RoomOpening? opening;

  @override
  State<_OpeningDialog> createState() => _OpeningDialogState();
}

class _OpeningDialogState extends State<_OpeningDialog> {
  late OpeningType _type = widget.opening?.type ?? OpeningType.door;
  late int _edge = widget.opening?.edgeIndex ?? 0;
  late double _position = widget.opening?.position ?? 0.5;
  late final _width = TextEditingController(
    text: _decimal(widget.opening?.width ?? 0.9),
  );
  late final _height = TextEditingController(
    text: _decimal(widget.opening?.height ?? 2.1),
  );
  late final _sill = TextEditingController(
    text: _decimal(widget.opening?.sillHeight ?? 0.9),
  );

  static String _decimal(double value) =>
      value.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _sill.dispose();
    super.dispose();
  }

  String _newId() {
    final used = {for (final opening in widget.room.openings) opening.id};
    var index = widget.room.openings.length + 1;
    while (used.contains('${widget.room.id}-opening-$index')) {
      index++;
    }
    return '${widget.room.id}-opening-$index';
  }

  void _submit() {
    final width = parseMetres(_width.text);
    final height = parseMetres(_height.text);
    final sill = _type == OpeningType.window
        ? double.tryParse(_sill.text.trim().replaceAll(',', '.'))
        : null;
    if (width == null || height == null) return;
    Navigator.of(context).pop(
      RoomOpening(
        id: widget.opening?.id ?? _newId(),
        edgeIndex: _edge,
        position: _position,
        width: width,
        height: height,
        type: _type,
        sillHeight: sill,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lengths = edgeLengths(widget.room.corners);
    return AlertDialog(
      title: Text(widget.opening == null ? 'Nueva abertura' : 'Abertura'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<OpeningType>(
              segments: const [
                ButtonSegment(value: OpeningType.door, label: Text('Puerta')),
                ButtonSegment(
                  value: OpeningType.window,
                  label: Text('Ventana'),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) =>
                  setState(() => _type = value.single),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: const ValueKey('opening-edge'),
              initialValue: _edge,
              decoration: const InputDecoration(labelText: 'Lado'),
              items: [
                for (var index = 0; index < lengths.length; index++)
                  DropdownMenuItem(
                    value: index,
                    child: Text(
                      'Lado ${index + 1} (${metres(lengths[index])})',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _edge = value ?? 0),
            ),
            const SizedBox(height: 12),
            Text(
              'Posición a lo largo del lado: '
              '${metres(_position * lengths[_edge])}',
            ),
            Slider(
              value: _position,
              onChanged: (value) => setState(() => _position = value),
            ),
            TextField(
              key: const ValueKey('opening-width'),
              controller: _width,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Ancho (m)'),
            ),
            TextField(
              key: const ValueKey('opening-height'),
              controller: _height,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Alto (m)'),
            ),
            if (_type == OpeningType.window)
              TextField(
                key: const ValueKey('opening-sill'),
                controller: _sill,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Altura del alféizar (m)',
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
          key: const ValueKey('opening-confirm'),
          onPressed: _submit,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
