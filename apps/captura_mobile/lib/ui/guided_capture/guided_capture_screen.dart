import 'package:flutter/material.dart';

import '../../data/services/photo_source.dart';
import '../../domain/guided_capture/capture_checklist.dart';
import '../../domain/guided_capture_controller.dart';

const _actionMinSize = Size(48, 48);

/// Step-by-step capture session (F14.2): rooms in the suggested order, the
/// checks of each room and a photo that passes the quality validation.
///
/// [beforePhotoChange] runs before each photo; returning false cancels it
/// (the editor uses it to warn that a listing in review returns to draft).
class GuidedCaptureScreen extends StatelessWidget {
  const GuidedCaptureScreen({
    super.key,
    required this.controller,
    this.beforePhotoChange,
  });

  final GuidedCaptureController controller;
  final Future<bool> Function()? beforePhotoChange;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Captura guiada')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _body(context),
        ),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    switch (controller.state) {
      case GuidedCaptureLoadState.loading:
        return const Center(
          child: CircularProgressIndicator(key: ValueKey('guided-loading')),
        );
      case GuidedCaptureLoadState.failed:
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              controller.message ?? '',
              key: const ValueKey('guided-error'),
              style: theme.textTheme.bodyLarge,
            ),
          ],
        );
      case GuidedCaptureLoadState.ready:
        final progress = controller.progress;
        final problems = controller.problems;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Recorré los ambientes en este orden. En cada uno confirmá la '
              'lista y sacá al menos una foto: la app revisa tamaño, luz y '
              'nitidez antes de subirla.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              '${progress.finished} de ${progress.total} ambientes listos',
              key: const ValueKey('guided-progress'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress.total == 0
                  ? 0
                  : progress.finished / progress.total,
            ),
            if (controller.message != null) ...[
              const SizedBox(height: 12),
              Text(controller.message!, key: const ValueKey('guided-message')),
            ],
            const SizedBox(height: 16),
            for (final (index, room) in controller.checklist.rooms.indexed)
              _RoomCard(
                key: ValueKey('guided-room-${room.id}'),
                position: index + 1,
                room: room,
                controller: controller,
                beforePhotoChange: beforePhotoChange,
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('guided-add-room'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => _addRoom(context),
              icon: const Icon(Icons.add),
              label: const Text('Agregar ambiente'),
            ),
            const SizedBox(height: 16),
            if (problems.isEmpty)
              Text(
                'La captura guiada está completa. Ya podés enviar el inmueble a revisión.',
                key: const ValueKey('guided-complete'),
                style: theme.textTheme.titleSmall,
              )
            else ...[
              Text(
                'Falta para enviar a revisión',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final problem in problems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $problem'),
                ),
            ],
          ],
        );
    }
  }

  Future<void> _addRoom(BuildContext context) async {
    final label = await _askText(
      context,
      title: 'Agregar ambiente',
      label: 'Nombre (por ejemplo, Balcón o Patio)',
      action: 'Agregar',
      fieldKey: 'guided-room-name',
    );
    if (label != null) await controller.addExtraRoom(label);
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    super.key,
    required this.position,
    required this.room,
    required this.controller,
    required this.beforePhotoChange,
  });

  final int position;
  final CaptureRoom room;
  final GuidedCaptureController controller;
  final Future<bool> Function()? beforePhotoChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = controller.statusOf(room);
    final busy = controller.busyRoom == room.id;
    final anyBusy = controller.busyRoom != null;
    final photos = controller.photosOf(room);
    final message = controller.roomMessage(room.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$position. ${room.label}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  _statusLabel(status),
                  key: ValueKey('guided-status-${room.id}'),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            if (room.isSkipped) ...[
              const SizedBox(height: 8),
              Text('No aplica: ${room.skippedReason}'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('guided-unskip-${room.id}'),
                  style: TextButton.styleFrom(minimumSize: _actionMinSize),
                  onPressed: () => controller.unskip(room),
                  child: const Text('Volver a incluir'),
                ),
              ),
            ] else ...[
              for (final check in RoomCheck.values)
                CheckboxListTile(
                  key: ValueKey('guided-check-${room.id}-${check.name}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: room.checks.contains(check),
                  onChanged: (_) => controller.toggleCheck(room, check),
                  title: Text(check.label),
                  subtitle: Text(check.hint),
                ),
              Text(
                photos.isEmpty
                    ? 'Sin fotos aprobadas todavía.'
                    : '${photos.length} ${photos.length == 1 ? 'foto aprobada' : 'fotos aprobadas'}',
                key: ValueKey('guided-photos-${room.id}'),
              ),
              if (busy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                const Text('Revisando y subiendo la foto…'),
              ],
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  key: ValueKey('guided-room-message-${room.id}'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: ValueKey('guided-camera-${room.id}'),
                    style: FilledButton.styleFrom(minimumSize: _actionMinSize),
                    onPressed: anyBusy
                        ? null
                        : () => _capture(PhotoOrigin.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Tomar foto'),
                  ),
                  OutlinedButton.icon(
                    key: ValueKey('guided-gallery-${room.id}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: _actionMinSize,
                    ),
                    onPressed: anyBusy
                        ? null
                        : () => _capture(PhotoOrigin.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galería'),
                  ),
                  if (room.kind == RoomKind.extra)
                    TextButton(
                      key: ValueKey('guided-remove-${room.id}'),
                      style: TextButton.styleFrom(minimumSize: _actionMinSize),
                      onPressed: anyBusy
                          ? null
                          : () => controller.removeExtraRoom(room),
                      child: const Text('Quitar ambiente'),
                    )
                  else
                    TextButton(
                      key: ValueKey('guided-skip-${room.id}'),
                      style: TextButton.styleFrom(minimumSize: _actionMinSize),
                      onPressed: anyBusy ? null : () => _skip(context),
                      child: const Text('No aplica'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _capture(PhotoOrigin origin) async {
    final allowed = await beforePhotoChange?.call() ?? true;
    if (!allowed) return;
    await controller.capture(room, origin);
  }

  Future<void> _skip(BuildContext context) async {
    final reason = await _askText(
      context,
      title: '${room.label}: no aplica',
      label: 'Motivo (por ejemplo, monoambiente sin cocina separada)',
      action: 'Confirmar',
      fieldKey: 'guided-skip-reason',
    );
    if (reason != null) await controller.skip(room, reason);
  }

  static String _statusLabel(RoomStatus status) => switch (status) {
    RoomStatus.pending => 'Pendiente',
    RoomStatus.inProgress => 'En curso',
    RoomStatus.done => 'Listo',
    RoomStatus.skipped => 'No aplica',
  };
}

/// Asks for a short non-blank text; null on cancel.
Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  required String fieldKey,
}) async {
  final text = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: ValueKey(fieldKey),
        controller: text,
        autofocus: true,
        maxLength: 120,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: ValueKey('$fieldKey-confirm'),
          onPressed: () {
            final value = text.text.trim();
            if (value.isEmpty) return;
            Navigator.of(context).pop(value);
          },
          child: Text(action),
        ),
      ],
    ),
  );
  return result;
}
